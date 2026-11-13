#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply each Azure chart's tests/mock.values.yaml to aso-extensions' fake
# cloud with stock Azure Service Operator, and check every object becomes
# Ready and is deleted (docs/azure.md, "8. Charts", Testing, layer 2). The
# Azure counterpart of hack/mock-apply.sh. Only on an offload VM; `task
# test-mock-azure` runs it:
#
#   ../scripts/offload/offload run -- env ASOX_TARBALL=gs://.../asox-<commit>.tar.gz hack/azure-mock.sh
#
# How (aso-extensions' docs/fake-cloud.md, "Stock ASO against the fake
# cloud"): a kind cluster runs aso-extensions' fake Resource Manager
# (cmd/fakearm, a store of resources by ARM ID) and fake Entra
# (cmd/fakeentra, answering as login.microsoftonline.com through a CoreDNS
# rewrite), both over TLS from a throwaway CA (its tests/operator/fixtures);
# ASO v2.22.0 from its own Helm chart talks to them: Resource Manager at
# https://fakearm.fake-cloud.svc, workload identity (its service account's
# token, which the fake Entra takes as the subject), the CA through
# SSL_CERT_FILE. Nothing reaches Azure. aso-extensions is read from
# ASOX_TARBALL (a `git archive` of one commit, in Cloud Storage) or
# ASOX_DIR (a checkout). MOCK_CHARTS="avm-res-network-routetable ..."
# applies only those charts. Writes offload-artifacts/azure-mock/.
#
# The fake keeps a resource's body as sent and adds its id, name, type and
# provisioningState, and computes what Azure computes that the charts read
# (an address, a principal ID, a login server, a vault's URI, FQDNs;
# aso-extensions' pkg/fakecloud/arm/computed.go), so every Package's outputs
# must evaluate too. A VaultKey reads its key in the vault's data plane:
# <vault>.vault.azure.net is fakearm inside the cluster (a CoreDNS rewrite;
# the fixtures' certificate carries the name), and fakearm is given ASO's
# tenant, which Key Vault's challenge names.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
ASO_VERSION="$(sed -n 's/^| Azure Service Operator release | `v\([0-9.]*\)`.*/\1/p' UPSTREAM.md)"
CERT_MANAGER_VERSION=v1.15.3
TIMEOUT="${MOCK_TIMEOUT:-300}"
OUT="${ROOT}/offload-artifacts/azure-mock"
WORK="$(mktemp -d)"
CLUSTER=catalog-azure-mock
NS=catalog-mock
ASO_NS=azureserviceoperator-system
# The fake cloud's subscription and tenant: the ones every mock.values.yaml
# names (/subscriptions/0000.../resourceGroups/catalog-rg).
SUB=00000000-0000-0000-0000-000000000000
TENANT=11111111-2222-3333-4444-555555555555
CLIENT=22222222-3333-4444-5555-666666666666
RG="/subscriptions/${SUB}/resourceGroups/catalog-rg"
mkdir -p "${OUT}"

for t in docker kind kubectl helm go jq; do
  command -v "$t" >/dev/null || { echo "azure-mock: $t is not installed" >&2; exit 2; }
done
if [[ -z "${ASOX_DIR:-}" ]]; then
  [[ -n "${ASOX_TARBALL:-}" ]] || { echo "azure-mock: set ASOX_TARBALL or ASOX_DIR" >&2; exit 2; }
  ASOX_DIR="${WORK}/aso-extensions"
  mkdir -p "${ASOX_DIR}"
  # gcloud where the VM has it, else the Cloud Storage JSON API as the VM's
  # service account.
  if command -v gcloud >/dev/null; then
    gcloud storage cp --quiet "${ASOX_TARBALL}" "${WORK}/asox.tar.gz"
  else
    obj="${ASOX_TARBALL#gs://}"; bucket="${obj%%/*}"; obj="${obj#*/}"
    token="$(curl -sf -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -er .access_token)"
    curl -sfL -o "${WORK}/asox.tar.gz" -H "Authorization: Bearer ${token}" \
      "https://storage.googleapis.com/storage/v1/b/${bucket}/o/$(jq -rn --arg o "${obj}" '$o|@uri')?alt=media"
  fi
  tar -xzf "${WORK}/asox.tar.gz" -C "${ASOX_DIR}"
fi
ASOX_DIR="$(cd "${ASOX_DIR}" && pwd)"
cleanup() {
  kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

echo "== the fake cloud: fakearm and fakeentra from ${ASOX_TARBALL:-${ASOX_DIR}}"
# aso-extensions builds against its patched Azure Service Operator checkout
# (third_party/, not committed; its hack/upstream.sh fetches the pin).
[[ -d "${ASOX_DIR}/third_party/azure-service-operator/v2" ]] || (cd "${ASOX_DIR}" && hack/upstream.sh)
(cd "${ASOX_DIR}" && CGO_ENABLED=0 go build -o "${WORK}/bin/" ./cmd/fakearm ./cmd/fakeentra \
  && go run ./tests/operator/fixtures --out "${WORK}/fixtures" --tenant "${TENANT}" --client "${CLIENT}")
for b in fakearm fakeentra; do
  mkdir -p "${WORK}/img-${b}"
  cp "${WORK}/bin/${b}" "${WORK}/img-${b}/${b}"
  printf 'FROM scratch\nCOPY %s /%s\nENTRYPOINT ["/%s"]\n' "${b}" "${b}" "${b}" >"${WORK}/img-${b}/Dockerfile"
  docker build -q -t "catalog.local/${b}:mock" "${WORK}/img-${b}" >/dev/null
done

kind create cluster --name "${CLUSTER}" --wait 180s
export KUBECONFIG="${WORK}/kubeconfig"
kind get kubeconfig --name "${CLUSTER}" >"${KUBECONFIG}"
for b in fakearm fakeentra; do kind load docker-image "catalog.local/${b}:mock" --name "${CLUSTER}" >/dev/null; done

kubectl create namespace fake-cloud >/dev/null
kubectl create namespace "${ASO_NS}" >/dev/null
for b in fakearm fakeentra; do
  kubectl -n fake-cloud create secret tls "${b}-tls" --cert "${WORK}/fixtures/${b}.crt" --key "${WORK}/fixtures/${b}.key" >/dev/null
done
kubectl -n "${ASO_NS}" create configmap fake-cloud-ca --from-file=ca.crt="${WORK}/fixtures/ca.crt" >/dev/null
# ASO's workload identity token names its service account; the fake Entra
# puts that subject in the token, and fakearm trusts it for this client.
ASO_SUBJECT="system:serviceaccount:${ASO_NS}:azureserviceoperator-default"
# The fakes serve on 443 in the pod too: ASO's chart installs network
# policies that let its controller reach TCP 443 only, and a policy sees the
# pod's port, not the Service's.
cat >"${WORK}/fake-cloud.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: fakearm, namespace: fake-cloud}
spec:
  replicas: 1
  selector: {matchLabels: {app: fakearm}}
  template:
    metadata: {labels: {app: fakearm}}
    spec:
      containers:
      - name: fakearm
        image: catalog.local/fakearm:mock
        imagePullPolicy: Never
        args: [--listen=:443, --audience=https://fakearm.fake-cloud.svc, "--tenant=${TENANT}", "--trust=${CLIENT}=${ASO_SUBJECT}", "--resource=/subscriptions/${SUB},${RG}"]
        ports: [{containerPort: 443}]
        volumeMounts: [{name: tls, mountPath: /tls, readOnly: true}]
      volumes: [{name: tls, secret: {secretName: fakearm-tls}}]
---
apiVersion: v1
kind: Service
metadata: {name: fakearm, namespace: fake-cloud}
spec:
  selector: {app: fakearm}
  ports: [{port: 443, targetPort: 443}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: fakeentra, namespace: fake-cloud}
spec:
  replicas: 1
  selector: {matchLabels: {app: fakeentra}}
  template:
    metadata: {labels: {app: fakeentra}}
    spec:
      containers:
      - name: fakeentra
        image: catalog.local/fakeentra:mock
        imagePullPolicy: Never
        args: [--listen=:443]
        ports: [{containerPort: 443}]
        volumeMounts: [{name: tls, mountPath: /tls, readOnly: true}]
      volumes: [{name: tls, secret: {secretName: fakeentra-tls}}]
---
apiVersion: v1
kind: Service
metadata: {name: fakeentra, namespace: fake-cloud}
spec:
  selector: {app: fakeentra}
  ports: [{port: 443, targetPort: 443}]
EOF
kubectl apply -f "${WORK}/fake-cloud.yaml" >/dev/null
kubectl -n fake-cloud rollout status deploy/fakearm --timeout=180s
kubectl -n fake-cloud rollout status deploy/fakeentra --timeout=180s
# login.microsoftonline.com is the fake Entra inside the cluster, and every
# vault's data plane (<vault>.vault.azure.net, which ASO's VaultKey reads) is
# fakearm, which holds the keys and whose certificate carries the name.
corefile="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
corefile="$(awk '{print} /^ *ready *$/ {
  print "    rewrite name exact login.microsoftonline.com fakeentra.fake-cloud.svc.cluster.local answer auto"
  print "    rewrite name regex (.+)\\.vault\\.azure\\.net fakearm.fake-cloud.svc.cluster.local answer auto"}' <<<"${corefile}")"
grep -q 'vault' <<<"${corefile}" || { echo "azure-mock: no ready line in the Corefile for the rewrite" >&2; exit 1; }
kubectl -n kube-system create configmap coredns --from-literal=Corefile="${corefile}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n kube-system rollout restart deploy/coredns >/dev/null
kubectl -n kube-system rollout status deploy/coredns --timeout=120s

echo "== cert-manager ${CERT_MANAGER_VERSION}, Azure Service Operator v${ASO_VERSION} against the fake cloud"
helm install cert-manager cert-manager --repo https://charts.jetstack.io --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m >/dev/null
helm install aso azure-service-operator --repo https://raw.githubusercontent.com/Azure/azure-service-operator/main/v2/charts \
  --version "v${ASO_VERSION}" --namespace "${ASO_NS}" \
  --set azureSubscriptionID="${SUB}" --set azureTenantID="${TENANT}" --set azureClientID="${CLIENT}" \
  --set useWorkloadIdentityAuth=true \
  --set azureResourceManagerEndpoint=https://fakearm.fake-cloud.svc \
  --set azureResourceManagerAudience=https://fakearm.fake-cloud.svc \
  --set crdPattern='resources.azure.com/*;network.azure.com/*;storage.azure.com/*;keyvault.azure.com/*;authorization.azure.com/*;insights.azure.com/*;managedidentity.azure.com/*;operationalinsights.azure.com/*;containerregistry.azure.com/*;containerservice.azure.com/*' \
  --timeout 10m >/dev/null
# The fake cloud's CA, trusted through SSL_CERT_FILE.
kubectl -n "${ASO_NS}" patch deployment azureserviceoperator-controller-manager --type strategic -p '{
  "spec": {"template": {"spec": {
    "volumes": [{"name": "fake-cloud-ca", "configMap": {"name": "fake-cloud-ca"}}],
    "containers": [{"name": "manager",
      "env": [{"name": "SSL_CERT_FILE", "value": "/fake-cloud-ca/ca.crt"}],
      "volumeMounts": [{"name": "fake-cloud-ca", "mountPath": "/fake-cloud-ca", "readOnly": true}]}]}}}}' >/dev/null
kubectl -n "${ASO_NS}" rollout status deployment azureserviceoperator-controller-manager --timeout 10m
for _ in $(seq 60); do kubectl get crd virtualnetworks.network.azure.com >/dev/null 2>&1 && break; sleep 5; done
kubectl wait --for=condition=Established crd --all --timeout=300s >/dev/null
kubectl create namespace "${NS}" >/dev/null
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)

summary="${OUT}/summary.md"
{
  echo "# Azure fake-cloud apply, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Catalog commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown); aso-extensions ${ASOX_TARBALL:-${ASOX_DIR}}; Azure Service Operator v${ASO_VERSION} on kind against fakearm and fakeentra."
  echo
  echo "| Chart | Object | Ready | Deleted | Message |"
  echo "| --- | --- | --- | --- | --- |"
} >"${summary}"
total=0; failed=0
# The resource group chart last: its mock is the group every other mock is
# in (catalog-rg), and deleting it takes the group from the fake.
dirs=()
for d in charts/azure/*/; do [[ "${d}" == */avm-res-resources-resourcegroup/ ]] || dirs+=("${d}"); done
dirs+=(charts/azure/avm-res-resources-resourcegroup/)
for dir in "${dirs[@]}"; do
  chart="$(basename "${dir}")"
  [[ -f "${dir}/tests/mock.values.yaml" ]] || continue
  if [[ -n "${MOCK_CHARTS:-}" && " ${MOCK_CHARTS} " != *" ${chart} "* ]]; then continue; fi
  echo "== ${chart}"
  mkdir -p "${OUT}/${chart}"
  helm template mock "${dir}" --namespace "${NS}" -f "${dir}/tests/mock.values.yaml" >"${OUT}/${chart}/rendered.yaml"
  kubectl apply --server-side -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" >"${OUT}/${chart}/apply.log"
  mapfile -t objects < <(kubectl get -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq -r '(if .items then .items else [.] end)[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"')
  declare -A ready=()
  deadline=$(( $(date +%s) + TIMEOUT ))
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${NS}" --for=condition=Ready "${o}" --timeout="${left}s" >/dev/null 2>&1; then ready["$o"]=yes; else ready["$o"]=no; fi
  done
  kubectl get -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${chart}/live.json"
  if bin/catalogtool outputs "${dir}/package.yaml" "${OUT}/${chart}/live.json" "${dir}/values.yaml" "${dir}/tests/mock.values.yaml" >"${OUT}/${chart}/outputs.json" 2>"${OUT}/${chart}/outputs.err"; then
    outputs=evaluated
  else
    outputs="not evaluated: $(tr '\n|' '  ' <"${OUT}/${chart}/outputs.err" | cut -c1-120)"
    failed=$((failed + 1))
  fi
  kubectl delete -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" --wait=false >/dev/null
  deadline=$(( $(date +%s) + TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    left=0
    for o in "${objects[@]}"; do kubectl get -n "${NS}" "${o}" >/dev/null 2>&1 && left=$((left + 1)); done
    (( left == 0 )) && break
    sleep 5
  done
  for o in "${objects[@]}"; do
    total=$((total + 1))
    msg="$(jq -r --arg n "${o#*/}" '.items[] | select(.metadata.name == $n) | (.status.conditions // [])[] | select(.type=="Ready") | .message' "${OUT}/${chart}/live.json" | tr '\n|' '  ' | cut -c1-160)"
    if kubectl get -n "${NS}" "${o}" >/dev/null 2>&1; then deleted=no; else deleted=yes; fi
    [[ "${ready[$o]}" == yes && "${deleted}" == yes ]] || failed=$((failed + 1))
    echo "| ${chart} | ${o%%.*}/${o#*/} | ${ready[$o]} | ${deleted} | ${msg} |" >>"${summary}"
    echo "   ${o}: ready=${ready[$o]} deleted=${deleted} ${msg}"
  done
  echo "| ${chart} | outputs | | | ${outputs} |" >>"${summary}"
  echo "-- outputs: ${outputs}"
  unset ready
done
kubectl -n "${ASO_NS}" logs deployment/azureserviceoperator-controller-manager --tail=-1 >"${OUT}/aso.log" 2>&1 || true
kubectl -n fake-cloud logs deployment/fakearm --tail=-1 >"${OUT}/fakearm.log" 2>&1 || true
kubectl -n fake-cloud logs deployment/fakeentra --tail=-1 >"${OUT}/fakeentra.log" 2>&1 || true
{
  echo
  echo "${total} objects; ${failed} failures (an object not Ready or not deleted, or a chart's outputs not evaluated)."
} >>"${summary}"
cat "${summary}"
[[ ${total} -gt 0 && ${failed} -eq 0 ]]
