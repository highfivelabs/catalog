#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply the Azure charts (avm-res-network-virtualnetwork,
# avm-res-storage-storageaccount, avm-res-keyvault-vault,
# avm-res-network-networksecuritygroup, avm-res-network-routetable,
# avm-res-network-natgateway, avm-res-network-publicipaddress,
# avm-res-network-privatednszone,
# avm-res-managedidentity-userassignedidentity,
# avm-res-operationalinsights-workspace, avm-res-containerregistry-registry)
# to the Azure
# sandbox with tiny resources, check their outputs, delete them, and check
# Azure no longer has them (docs/azure.md, "8. Charts", Testing).
# AZURE_LIVE_CASES (space-separated: vnet storage kv nsg rt natgw pip dns
# uai law acr)
# applies only those; the default is all. Only on
# an offload VM acting as the service account the sandbox identity trusts
# (keyless federation, as aso-extensions' live runs: its docs/live-runs.md);
# `task test-live-azure` runs it:
#
#   ../scripts/offload/offload run --sa "$AZURE_LIVE_SA" --hours 2 -- \
#     env AZURE_SUBSCRIPTION_ID=... AZURE_TENANT_ID=... AZURE_CLIENT_ID=... \
#     AZURE_LIVE_RESOURCE_GROUP=... hack/azure-live.sh
#
# How: a kind cluster runs Azure Service Operator v2.22.0 from its own Helm
# chart (with cert-manager for its webhooks, which convert between CRD
# versions), its credential the Google ID token of the VM's service
# account, which Entra exchanges for the sandbox identity (workload
# identity: the token file, refreshed every 20 minutes, is mounted where
# ASO reads it). The identity is Contributor on one resource group, so the
# resource group chart and the aso-extensions lock are not applied here.
#
# Rules: one resource group (AZURE_LIVE_RESOURCE_GROUP); every name starts
# with this run's ID (cat<month day hour minute><4 hex>) and every resource
# that takes tags carries catalog-run=<run ID>; the test deletes what it
# makes, checks Azure answers 404, and at the end deletes anything of this
# run still there and lists what of any catalog run is left. A key vault
# stays soft-deleted for 7 days after its delete (purging needs a
# subscription-scope right the identity does not have); its name is the
# run's, so nothing collides. Writes offload-artifacts/azure-live/.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
: "${AZURE_SUBSCRIPTION_ID:?set AZURE_SUBSCRIPTION_ID (.env.example)}"
: "${AZURE_TENANT_ID:?set AZURE_TENANT_ID (.env.example)}"
: "${AZURE_CLIENT_ID:?set AZURE_CLIENT_ID (.env.example)}"
: "${AZURE_LIVE_RESOURCE_GROUP:?set AZURE_LIVE_RESOURCE_GROUP (.env.example)}"
ASO_VERSION="$(sed -n 's/^| Azure Service Operator release | `v\([0-9.]*\)`.*/\1/p' UPSTREAM.md)"
CERT_MANAGER_VERSION=v1.15.3
LOCATION="${AZURE_LIVE_LOCATION:-eastus2}"
TIMEOUT="${LIVE_TIMEOUT:-900}"
CASES="${AZURE_LIVE_CASES:-vnet storage kv nsg rt natgw pip dns uai law acr}"
OUT="${ROOT}/offload-artifacts/azure-live"
WORK="$(mktemp -d)"
CLUSTER=catalog-azure-live
NS=catalog-live
ARM=https://management.azure.com
RG="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_LIVE_RESOURCE_GROUP}"
mkdir -p "${OUT}"

for t in docker kind kubectl helm go jq curl; do
  command -v "$t" >/dev/null || { echo "azure-live: $t is not installed" >&2; exit 2; }
done
md() { curl -sf -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/$1"; }
RUNNER="$(md instance/service-accounts/default/email || true)"
[[ "${RUNNER}" == *.iam.gserviceaccount.com ]] || { echo "azure-live: not on a VM acting as a service account (got '${RUNNER}')" >&2; exit 2; }
# Federated credentials only.
unset AZURE_CLIENT_SECRET AZURE_CLIENT_CERTIFICATE AZURE_CLIENT_CERTIFICATE_PATH \
  AZURE_CLIENT_CERTIFICATE_PASSWORD AZURE_USERNAME AZURE_PASSWORD

RUN="cat$(date -u +%m%d%H%M)$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
echo "== live run ${RUN} in resource group ${AZURE_LIVE_RESOURCE_GROUP} as ${RUNNER}"

# The Google ID token Entra exchanges; ASO's global workload identity
# credential reads it from /var/run/secrets/tokens/azure-identity (its
# default, identity.FederatedTokenFilePath).
TOKENS="${WORK}/tokens"
mkdir -p "${TOKENS}"
# ASO runs as a non-root user: it must reach the file through the mount.
chmod 755 "${WORK}" "${TOKENS}"
google_token() { md "instance/service-accounts/default/identity?audience=api://AzureADTokenExchange&format=full"; }
google_token >"${TOKENS}/t.new" && mv "${TOKENS}/t.new" "${TOKENS}/azure-identity"
chmod 644 "${TOKENS}/azure-identity"
( while sleep 1200; do google_token >"${TOKENS}/t.new" && chmod 644 "${TOKENS}/t.new" && mv "${TOKENS}/t.new" "${TOKENS}/azure-identity"; done ) &
refresher=$!

arm_token() {
  curl -fsS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
    --data-urlencode "client_id=${AZURE_CLIENT_ID}" \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode 'scope=https://management.azure.com/.default' \
    --data-urlencode 'client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer' \
    --data-urlencode "client_assertion=$(cat "${TOKENS}/azure-identity")" | jq -er .access_token
}
api() { curl -sS -H "Authorization: Bearer $(arm_token)" "$@"; }
# run_resources PREFIX...: id and type of each top-level resource in the
# group whose name starts with one of the prefixes.
run_resources() {
  api "${ARM}${RG}/resources?api-version=2021-04-01" | jq -r --args '.value[] | select(.name as $n | $ARGS.positional | any(. as $p | $n | startswith($p))) | "\(.id) \(.type)"' "$@"
}
sweep() { # sweep PREFIX: delete what this run left in the group
  local id type ns rtype v
  run_resources "$1" | while read -r id type; do
    ns="${type%%/*}" rtype="${type#*/}"
    v="$(api "${ARM}/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/${ns}?api-version=2021-04-01" \
      | jq -r --arg t "${rtype}" '.resourceTypes[] | select((.resourceType|ascii_downcase) == ($t|ascii_downcase)) | .apiVersions | map(select(test("preview")|not)) | .[0] // empty')"
    echo "   sweep: delete ${type} ${id##*/}: $(api -o /dev/null -w '%{http_code}' -X DELETE "${ARM}${id}?api-version=${v}")"
  done
}
cleanup() {
  kill "${refresher}" 2>/dev/null || true
  sweep "${RUN}" || true
  kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true
  rm -rf "${WORK}"
}
trap cleanup EXIT
arm_token >/dev/null || { echo "azure-live: Entra refused the federated token" >&2; exit 1; }
echo "== Entra issued a Resource Manager token for ${AZURE_CLIENT_ID}"

# kind, with the token directory on the node.
cat >"${WORK}/kind.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: ${TOKENS}
        containerPath: /azure-tokens
        readOnly: true
EOF
kind create cluster --name "${CLUSTER}" --config "${WORK}/kind.yaml" --wait 180s
export KUBECONFIG="${WORK}/kubeconfig"
kind get kubeconfig --name "${CLUSTER}" >"${KUBECONFIG}"

echo "== cert-manager ${CERT_MANAGER_VERSION}, Azure Service Operator v${ASO_VERSION}"
helm install cert-manager cert-manager --repo https://charts.jetstack.io --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m >/dev/null
helm install aso azure-service-operator --repo https://raw.githubusercontent.com/Azure/azure-service-operator/main/v2/charts \
  --version "v${ASO_VERSION}" --namespace azureserviceoperator-system --create-namespace \
  --set azureSubscriptionID="${AZURE_SUBSCRIPTION_ID}" --set azureTenantID="${AZURE_TENANT_ID}" \
  --set azureClientID="${AZURE_CLIENT_ID}" --set useWorkloadIdentityAuth=true \
  --set crdPattern='network.azure.com/*;storage.azure.com/*;keyvault.azure.com/*;authorization.azure.com/*;insights.azure.com/*;managedidentity.azure.com/*;operationalinsights.azure.com/*;containerregistry.azure.com/*' \
  --timeout 10m >/dev/null
# The token where ASO reads it: the chart projects a Kubernetes service
# account token into /var/run/secrets/tokens (Azure Workload Identity's
# shape, for AKS); kind's issuer is not federated, so the volume becomes
# the node's directory holding the Google ID token instead.
kubectl -n azureserviceoperator-system patch deployment azureserviceoperator-controller-manager --type strategic -p '{
  "spec": {"template": {"spec": {"volumes": [
    {"name": "azure-identity", "projected": null, "hostPath": {"path": "/azure-tokens", "type": "Directory"}}
  ]}}}}' >/dev/null
kubectl -n azureserviceoperator-system rollout status deployment azureserviceoperator-controller-manager --timeout 10m
for crd in virtualnetworks.network.azure.com virtualnetworkssubnets.network.azure.com storageaccounts.storage.azure.com \
    storageaccountsblobservicescontainers.storage.azure.com storageaccountsqueueservicesqueues.storage.azure.com vaults.keyvault.azure.com \
    networksecuritygroups.network.azure.com networksecuritygroupssecurityrules.network.azure.com routetables.network.azure.com \
    routetablesroutes.network.azure.com natgateways.network.azure.com publicipaddresses.network.azure.com \
    privatednszones.network.azure.com privatednszonesarecords.network.azure.com privatednszonestxtrecords.network.azure.com \
    privatednszonesvirtualnetworklinks.network.azure.com userassignedidentities.managedidentity.azure.com \
    federatedidentitycredentials.managedidentity.azure.com workspaces.operationalinsights.azure.com \
    registries.containerregistry.azure.com registrycacherules.containerregistry.azure.com; do
  for _ in $(seq 60); do kubectl get crd "${crd}" >/dev/null 2>&1 && break; sleep 5; done
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=120s >/dev/null
done
kubectl create namespace "${NS}" >/dev/null
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)

# The cases: each chart's smallest useful Instance, named for the run.
cat >"${WORK}/vnet.yaml" <<EOF
name: ${RUN}-vnet
location: ${LOCATION}
parent_id: ${RG}
address_space: [10.250.0.0/24]
tags: {catalog-run: ${RUN}}
subnets:
  a: {name: snet-a, address_prefix: 10.250.0.0/26}
EOF
cat >"${WORK}/storage.yaml" <<EOF
name: ${RUN}
location: ${LOCATION}
parent_id: ${RG}
account_sku_name: Standard_LRS
account_replication_type: LRS
tags: {catalog-run: ${RUN}}
containers:
  a: {name: assets}
queues:
  q: {name: jobs}
EOF
cat >"${WORK}/kv.yaml" <<EOF
name: ${RUN}-kv
location: ${LOCATION}
parent_id: ${RG}
tenant_id: ${AZURE_TENANT_ID}
sku_name: standard
purge_protection_enabled: false
soft_delete_retention_days: 7
tags: {catalog-run: ${RUN}}
EOF
cat >"${WORK}/nsg.yaml" <<EOF
name: ${RUN}-nsg
location: ${LOCATION}
parent_id: ${RG}
tags: {catalog-run: ${RUN}}
security_rules:
  ssh: {name: allow-ssh, access: Allow, direction: Inbound, priority: 100, protocol: Tcp, source_address_prefix: 10.0.0.0/8, source_port_range: "*", destination_address_prefix: "*", destination_port_range: "22"}
  out: {name: deny-internet, access: Deny, direction: Outbound, priority: 4000, protocol: "*", source_address_prefix: "*", source_port_range: "*", destination_address_prefix: Internet, destination_port_range: "*"}
EOF
cat >"${WORK}/rt.yaml" <<EOF
name: ${RUN}-rt
location: ${LOCATION}
resource_group_name: ${AZURE_LIVE_RESOURCE_GROUP}
subscription_id: ${AZURE_SUBSCRIPTION_ID}
bgp_route_propagation_enabled: false
tags: {catalog-run: ${RUN}}
routes:
  local: {name: local, address_prefix: 10.250.0.0/24, next_hop_type: VnetLocal}
  nva: {name: to-nva, address_prefix: 0.0.0.0/0, next_hop_type: VirtualAppliance, next_hop_in_ip_address: 10.250.0.4}
EOF
# A Standard (regional) gateway with a regional Standard address: the
# smallest shape every region has.
cat >"${WORK}/natgw.yaml" <<EOF
name: ${RUN}-natgw
location: ${LOCATION}
parent_id: ${RG}
sku_name: Standard
tags: {catalog-run: ${RUN}}
public_ips:
  a: {name: ${RUN}-natgw-pip}
public_ip_configuration:
  a: {sku: Standard, zones: []}
EOF
cat >"${WORK}/pip.yaml" <<EOF
name: ${RUN}-pip
location: ${LOCATION}
resource_group_name: ${RG}
tags: {catalog-run: ${RUN}}
EOF
# A zone named for the run, with an A and a TXT record and no link (a
# link needs a network of the run; the network chart is its own case).
cat >"${WORK}/dns.yaml" <<EOF
domain_name: ${RUN}.catalog.internal
parent_id: ${RG}
tags: {catalog-run: ${RUN}}
a_records:
  app: {name: app, ttl: 60, ip_addresses: [10.250.0.10]}
txt_records:
  owner: {name: "@", ttl: 60, records: {a: {value: [catalog-run=${RUN}]}}}
EOF
# An identity with a federated credential; no outbound role assignment
# (the live identity may not assign roles).
cat >"${WORK}/uai.yaml" <<EOF
name: ${RUN}-uai
location: ${LOCATION}
resource_group_name: ${AZURE_LIVE_RESOURCE_GROUP}
subscription_id: ${AZURE_SUBSCRIPTION_ID}
tags: {catalog-run: ${RUN}}
federated_identity_credentials:
  gh: {name: gh-main, audience: [api://AzureADTokenExchange], issuer: https://token.actions.githubusercontent.com, subject: "repo:highfivelabs/catalog:ref:refs/heads/main"}
EOF
# A workspace at the smallest retention its SKU takes, with a diagnostic
# setting to itself (the module's default destination).
cat >"${WORK}/law.yaml" <<EOF
name: ${RUN}-law
location: ${LOCATION}
resource_group_name: ${RG}
log_analytics_workspace_retention_in_days: 30
tags: {catalog-run: ${RUN}}
diagnostic_settings:
  self: {log_groups: [audit], metric_categories: []}
EOF
# A Basic registry (the cheapest; no zone redundancy below Premium) with a
# cache rule for an anonymous MCR image (Docker Hub needs credentials). Its
# name is letters and digits.
cat >"${WORK}/acr.yaml" <<EOF
name: ${RUN}acr
location: ${LOCATION}
resource_group_name: ${RG}
sku: Basic
zone_redundancy_enabled: false
tags: {catalog-run: ${RUN}}
cache_rules:
  mcr: {name: mcr-busybox, source_repository: mcr.microsoft.com/azurelinux/busybox, target_repository: cache/busybox}
EOF
summary="${OUT}/summary.md"
{
  echo "# Azure live apply, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Catalog commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown); run ${RUN}; Azure Service Operator v${ASO_VERSION} on kind; one resource group of the sandbox subscription."
  echo
  echo "| Chart | Object | Ready | Deleted | Gone from Azure | Message |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >"${summary}"

total=0; failed=0
for c in vnet:avm-res-network-virtualnetwork storage:avm-res-storage-storageaccount kv:avm-res-keyvault-vault \
    nsg:avm-res-network-networksecuritygroup rt:avm-res-network-routetable natgw:avm-res-network-natgateway \
    pip:avm-res-network-publicipaddress dns:avm-res-network-privatednszone \
    uai:avm-res-managedidentity-userassignedidentity law:avm-res-operationalinsights-workspace \
    acr:avm-res-containerregistry-registry; do
  case_="${c%%:*}" chart="${c#*:}" dir="charts/azure/${c#*:}"
  [[ " ${CASES} " == *" ${case_} "* ]] || continue
  echo "== ${chart}"
  mkdir -p "${OUT}/${chart}"
  helm template "${case_}" "${dir}" --namespace "${NS}" -f "${WORK}/${case_}.yaml" >"${OUT}/${chart}/rendered.yaml"
  kubectl apply --server-side -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" >"${OUT}/${chart}/apply.log"
  mapfile -t objects < <(kubectl get -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq -r '(if .items then .items else [.] end)[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"')
  declare -A ready=() armid=()
  deadline=$(( $(date +%s) + TIMEOUT ))
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${NS}" --for=condition=Ready "${o}" --timeout="${left}s" >/dev/null 2>&1; then ready["$o"]=yes; else ready["$o"]=no; fi
    armid["$o"]="$(kubectl get -n "${NS}" "${o}" -o jsonpath='{.status.id}' 2>/dev/null || true)"
  done
  kubectl get -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${chart}/live.json"
  if bin/catalogtool outputs "${dir}/package.yaml" "${OUT}/${chart}/live.json" "${dir}/values.yaml" "${WORK}/${case_}.yaml" >"${OUT}/${chart}/outputs.json" 2>"${OUT}/${chart}/outputs.err"; then
    outputs_ok=yes
  else
    outputs_ok=no
  fi
  echo "-- outputs (${outputs_ok})"; cat "${OUT}/${chart}/outputs.json" "${OUT}/${chart}/outputs.err"
  kubectl delete -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" --wait=false >/dev/null
  deadline=$(( $(date +%s) + TIMEOUT ))
  # Until every object is gone (kubectl get -f fails as soon as one is).
  while (( $(date +%s) < deadline )); do
    left=0
    for o in "${objects[@]}"; do kubectl get -n "${NS}" "${o}" >/dev/null 2>&1 && left=$((left + 1)); done
    (( left == 0 )) && break
    sleep 10
  done
  for o in "${objects[@]}"; do
    total=$((total + 1))
    msg="$(jq -r --arg n "${o#*/}" '.items[] | select(.metadata.name == $n) | (.status.conditions // [])[] | select(.type=="Ready") | .message' "${OUT}/${chart}/live.json" | tr '\n|' '  ' | cut -c1-160)"
    if kubectl get -n "${NS}" "${o}" >/dev/null 2>&1; then deleted=no; else deleted=yes; fi
    gone=n/a
    if [[ -n "${armid[$o]}" ]]; then
      # The provider and type after the last /providers/: an extension
      # resource (a diagnostic setting) is its own type, not its parent's.
      tail="${armid[$o]##*/providers/}"; ns="${tail%%/*}"; rest="${tail#*/}"; rtype="${rest%%/*}"
      v="$(api "${ARM}/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/${ns}?api-version=2021-04-01" \
        | jq -r --arg t "${rtype}" '.resourceTypes[] | select((.resourceType|ascii_downcase) == ($t|ascii_downcase)) | .apiVersions | map(select(test("preview")|not)) | .[0] // empty')"
      code="$(api -o /dev/null -w '%{http_code}' "${ARM}${armid[$o]}?api-version=${v}")"
      if [[ "${code}" == 404 ]]; then gone=yes; else gone="no (${code})"; fi
    fi
    [[ "${ready[$o]}" == yes && "${deleted}" == yes && "${gone}" != no* ]] || failed=$((failed + 1))
    echo "| ${chart} | ${o%%.*}/${o#*/} | ${ready[$o]} | ${deleted} | ${gone} | ${msg} |" >>"${summary}"
    echo "   ${o}: ready=${ready[$o]} deleted=${deleted} gone=${gone} ${msg}"
  done
  echo "| ${chart} | outputs | ${outputs_ok} | | | $(tr '\n|' '  ' <"${OUT}/${chart}/outputs.err" | cut -c1-160) |" >>"${summary}"
  [[ "${outputs_ok}" == yes ]] || failed=$((failed + 1))
  unset ready armid
done

kubectl -n azureserviceoperator-system logs deployment/azureserviceoperator-controller-manager --tail=-1 >"${OUT}/aso.log" 2>&1 || true
{
  echo
  echo "${total} objects; ${failed} failures (an object not Ready, not deleted or still in Azure, or a chart's outputs not evaluated)."
  echo
  echo "Left in the group from catalog runs (cat...): $(run_resources cat | wc -l | tr -d ' ')."
} >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
