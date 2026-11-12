#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply each AWS chart's tests/mock.values.yaml to a fake AWS and check it
# end to end, as hack/mock-apply.sh does for Google Cloud (docs/design.md,
# "Testing"; docs/aws.md, section 8): every object synced and Ready, the
# Package's outputs evaluated against the live objects, then every object
# deleted and gone. Heavy: run it on an offload VM, never on a laptop
# (task test-mock-aws):
#
#   offload run --hours 2 -- \
#     env ACKX_TARBALL=gs://.../ackx-<commit>.tar.gz hack/mock-apply-aws.sh
#
# The fake AWS is ack-extensions' (its tests/operator/run.sh): a kind
# cluster with moto in it (config/fake-aws/moto.yaml, its image checked
# against the digest that file pins), and in front of it:
#   - every ACK controller pinned in UPSTREAM.md ("ACK controllers"),
#     installed from its own Helm chart at the pinned commit, every AWS
#     endpoint at moto, fake credentials;
#   - ack-extensions (config/default built by ko, the operator in its
#     fake-AWS mode), whose operator runs a manager beside each ACK
#     controller that has ack-extensions kinds (crds/ack-extensions).
# Every AWS client in the cluster gets every endpoint at moto and a dead
# proxy (ack-extensions' hack/noaws env), and the run stops unless
# ack-extensions' hack/noaws verify-deployments passes for all of them.
# Nothing here reaches real AWS; no AWS credentials are used.
#
# ack-extensions is read from ACKX_TARBALL (a `git archive` of one commit,
# in Cloud Storage; task ackx-snapshot) or ACKX_DIR (a checkout).
# MOCK_CHARTS="vpc kms" applies only those charts (default: every chart
# under charts/aws with a tests/mock.values.yaml). A chart whose case needs
# objects it does not make (a security group needs a VPC) has them in
# tests/mock.needs.yaml: applied first and waited for, deleted after the
# chart's objects. tests/mock.set.yaml names the values read from them once
# they are Ready, one per line: `<value>: <resource>/<name> <jsonpath>`
# (vpc_id: vpcs.ec2.services.k8s.aws/sg-vpc {.status.vpcID}), passed to the
# render with --set-string.
#
# moto_fixups does in moto what AWS does and moto does not, while a chart's
# objects are created and deleted:
#   - AWS removes a deleted subnet's route table associations; moto keeps
#     them, so a route table whose subnets are gone could never be deleted;
#   - AWS encrypts every new bucket with SSE-S3 by default (since 2023);
#     moto leaves it without, and ACK's s3-controller v1.15.0 then panics
#     reading the bucket (a nil GetBucketEncryption response,
#     pkg/resource/bucket/hook.go:487).
#
# Writes offload-artifacts/mock-aws/summary.md and, per chart, the render,
# the live objects, the outputs and the controllers' logs.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
OUT="${ROOT}/offload-artifacts/mock-aws"
TIMEOUT="${MOCK_TIMEOUT:-300}"
CLUSTER="${CLUSTER:-catalog-aws-mock}"
NODE_IMAGE="${NODE_IMAGE:-kindest/node:v1.37.0}"
REGION=us-east-1
ACK_NS=ack-system
# Short of .cluster.local on purpose: moto takes a bucket from the host
# (S3's virtual-hosted style, which ACK's s3-controller uses) except under
# .svc.cluster.local; the cluster's search path still resolves it, and
# ack-extensions' guard accepts any .svc host.
FAKE_AWS="http://moto.fake-aws.svc:5000"
mkdir -p "${OUT}"

for t in docker kind kubectl helm go git jq crane ko; do
  command -v "$t" >/dev/null || { echo "mock-apply-aws: $t is not installed" >&2; exit 2; }
done

# ack-extensions: the fake AWS, its no-real-AWS guard, and its kinds.
if [[ -z "${ACKX_DIR:-}" ]]; then
  [[ -n "${ACKX_TARBALL:-}" ]] || { echo "mock-apply-aws: set ACKX_TARBALL or ACKX_DIR" >&2; exit 2; }
  ACKX_DIR="${ROOT}/.cache/ack-extensions"
  rm -rf "${ACKX_DIR}" && mkdir -p "${ACKX_DIR}"
  gcloud storage cat "${ACKX_TARBALL}" | tar -xz -C "${ACKX_DIR}"
fi
ACKX_DIR="$(cd "${ACKX_DIR}" && pwd)"
# ko reads the version from git: a snapshot gets a repository of its own,
# or ko reads (and warns about) this one.
if [[ ! -e "${ACKX_DIR}/.git" ]]; then
  git -C "${ACKX_DIR}" init -q && git -C "${ACKX_DIR}" add -A && \
    git -C "${ACKX_DIR}" -c user.email=mock@example.com -c user.name=mock commit -qm "ack-extensions snapshot"
fi
echo "== ack-extensions from ${ACKX_TARBALL:-${ACKX_DIR}}"
(cd "${ACKX_DIR}" && go build -o "${ROOT}/bin/noaws" ./hack/noaws)
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)

# The ACK controllers, as hack/ack.sh reads them: | `ec2-controller` | `v1.23.1` | `<commit>` | ...
PINS="$(sed -n 's/^| `\([a-z0-9]*-controller\)` | `\(v[0-9.]*\)` | `\([0-9a-f]\{40\}\)`.*/\1 \2 \3/p' UPSTREAM.md)"
[[ -n "${PINS}" ]] || { echo "mock-apply-aws: no ACK controller rows in UPSTREAM.md" >&2; exit 1; }
# Each controller's Helm chart at its pinned commit (a sparse, shallow checkout of helm/).
while read -r name version commit; do
  dir="${ROOT}/.cache/ack-helm/${name}-${version}"
  if [[ ! -d "${dir}/helm" ]]; then
    rm -rf "${dir}"
    git clone -q --filter=blob:none --no-checkout --depth 1 --branch "${version}" \
      "https://github.com/aws-controllers-k8s/${name}.git" "${dir}"
    git -C "${dir}" sparse-checkout set helm
    git -C "${dir}" checkout -q "${version}"
  fi
  got="$(git -C "${dir}" rev-parse HEAD)"
  [[ "${got}" == "${commit}" ]] || { echo "mock-apply-aws: ${name} ${version} is ${got}, UPSTREAM.md says ${commit}" >&2; exit 1; }
done <<<"${PINS}"

DOCKER_CONFIG="$(mktemp -d)"
echo '{}' >"${DOCKER_CONFIG}/config.json"
export DOCKER_CONFIG
work="$(mktemp -d)"
cleanup() { kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true; rm -rf "${work}" "${DOCKER_CONFIG}"; }
trap cleanup EXIT

start=$(date +%s)
echo "== cluster ${CLUSTER}"
kind get clusters | grep -qx "${CLUSTER}" || kind create cluster --name "${CLUSTER}" --image "${NODE_IMAGE}" --wait 120s
kubectl config use-context "kind-${CLUSTER}" >/dev/null
KUBE_HOST="$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')"
"${ROOT}/bin/noaws" env "${FAKE_AWS}" "${KUBE_HOST}" >"${work}/fake.env"
mapfile -t FAKE_ENV <"${work}/fake.env"
[[ ${#FAKE_ENV[@]} -gt 0 ]] || { echo "mock-apply-aws: hack/noaws env printed nothing" >&2; exit 1; }

echo "== fake AWS (moto)"
moto_yaml="${ACKX_DIR}/config/fake-aws/moto.yaml"
moto_digest="$(sed -n 's/^#  *\(sha256:[0-9a-f]\{64\}\)$/\1/p' "${moto_yaml}")"
moto_image="$(sed -n 's/^ *image: \(docker.io\/motoserver\/moto:.*\)$/\1/p' "${moto_yaml}")"
[[ -n "${moto_digest}" && -n "${moto_image}" ]] || { echo "mock-apply-aws: no moto image and digest in ${moto_yaml}" >&2; exit 1; }
got="$(crane digest "${moto_image}")"
[[ "${got}" == "${moto_digest}" ]] || { echo "mock-apply-aws: ${moto_image} is now ${got}, ack-extensions pins ${moto_digest}" >&2; exit 1; }
crane pull --platform "linux/$(go env GOARCH)" "${moto_image}" "${work}/moto.tar"
kind load image-archive --name "${CLUSTER}" "${work}/moto.tar" >/dev/null
kubectl apply -f "${moto_yaml}" >/dev/null
# S3 addresses a bucket by host (<bucket>.moto.fake-aws.svc), as ACK's
# s3-controller does: the cluster's DNS answers every such name with moto,
# and moto reads the bucket from the host, except for its own endpoint's.
# moto has AWS's managed IAM policies only when asked (a role attaches
# arn:aws:iam::aws:policy/...).
kubectl -n fake-aws set env deploy/moto "MOTO_S3_CUSTOM_ENDPOINTS=${FAKE_AWS}" MOTO_IAM_LOAD_MANAGED_POLICIES=true >/dev/null
kubectl -n fake-aws rollout status deploy/moto --timeout=180s >/dev/null
kubectl -n kube-system get configmap coredns -o json \
  | jq '.data.Corefile |= sub("ready\n"; "ready\n    rewrite name regex (.+)\\.moto\\.fake-aws\\.svc\\.cluster\\.local moto.fake-aws.svc.cluster.local answer auto\n")' \
  >"${work}/coredns.json"
grep -q 'moto.fake-aws.svc.cluster.local answer auto' "${work}/coredns.json" \
  || { echo "mock-apply-aws: could not add the S3 host rewrite to CoreDNS's Corefile" >&2; exit 1; }
kubectl apply -f "${work}/coredns.json" >/dev/null
kubectl -n kube-system rollout restart deploy/coredns >/dev/null
kubectl -n kube-system rollout status deploy/coredns --timeout=120s >/dev/null
echo "   ${moto_image} (${moto_digest}); <bucket>.moto.fake-aws.svc answered by moto"

echo "== ACK controllers"
kubectl create namespace "${ACK_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "${ACK_NS}" create secret generic aws-creds \
  --from-literal=credentials=$'[default]\naws_access_key_id = testing\naws_secret_access_key = testing\n' \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
while read -r name version _; do
  svc="${name%-controller}"
  helm upgrade --install "ack-${svc}" "${ROOT}/.cache/ack-helm/${name}-${version}/helm" -n "${ACK_NS}" \
    --set aws.region="${REGION}" \
    --set aws.endpoint_url="${FAKE_AWS}" \
    --set aws.identity_endpoint_url="${FAKE_AWS}" \
    --set aws.allow_unsafe_aws_endpoint_urls=true \
    --set aws.credentials.secretName=aws-creds \
    --set image.pullPolicy=IfNotPresent >/dev/null
  deploy="$(kubectl -n "${ACK_NS}" get deploy -l "app.kubernetes.io/name=${svc}-chart" -o jsonpath='{.items[0].metadata.name}')"
  kubectl -n "${ACK_NS}" set env "deploy/${deploy}" "${FAKE_ENV[@]}" >/dev/null
  echo "   ${name} ${version}: ${ACK_NS}/${deploy}"
done <<<"${PINS}"
while read -r name _ _; do
  svc="${name%-controller}"
  deploy="$(kubectl -n "${ACK_NS}" get deploy -l "app.kubernetes.io/name=${svc}-chart" -o jsonpath='{.items[0].metadata.name}')"
  kubectl -n "${ACK_NS}" rollout status "deploy/${deploy}" --timeout=300s >/dev/null
done <<<"${PINS}"

echo "== ack-extensions (config/default by ko, the operator against the fake)"
(cd "${ACKX_DIR}" && kubectl kustomize config/default \
  | KO_DOCKER_REPO=kind.local KIND_CLUSTER_NAME="${CLUSTER}" ko resolve --platform="linux/$(go env GOARCH)" -f - >"${work}/ackx.yaml")
kubectl apply --server-side -f "${work}/ackx.yaml" >/dev/null
kubectl -n ack-extensions-system patch deploy ack-extensions-operator --type=json -p '[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--fake-aws-endpoint='"${FAKE_AWS}"'"}
]' >/dev/null
kubectl -n ack-extensions-system rollout status deploy/ack-extensions-operator --timeout=180s >/dev/null
# A manager for each service whose ack-extensions kinds the charts render
# (crds/ack-extensions/<service>.aws.hfl.dev_*.yaml).
for svc in $(find crds/ack-extensions -name '*.aws.hfl.dev_*.yaml' -exec basename {} \; | sed 's/\..*//' | sort -u); do
  end=$(( $(date +%s) + 180 ))
  until kubectl -n "${ACK_NS}" rollout status "deploy/ack-extensions-${svc}-manager" --timeout=5s >/dev/null 2>&1; do
    (( $(date +%s) < end )) || { echo "mock-apply-aws: no ack-extensions ${svc} manager in ${ACK_NS} within 180s" >&2; kubectl -n ack-extensions-system logs deploy/ack-extensions-operator --tail=40 >&2 || true; exit 1; }
    sleep 3
  done
  echo "   ${ACK_NS}/ack-extensions-${svc}-manager"
done
kubectl get deploy -A -o json >"${work}/deployments.json"
"${ROOT}/bin/noaws" verify-deployments <"${work}/deployments.json" \
  || { echo "mock-apply-aws: an AWS client in the cluster could reach real AWS" >&2; exit 1; }
echo "== fake AWS up in $(( $(date +%s) - start ))s; every AWS client verified to reach only moto"

summary="${OUT}/summary.md"
{
  echo "# Mock apply (AWS), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Catalog commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown); ack-extensions from ${ACKX_TARBALL:-${ACKX_DIR}};"
  echo "ACK controllers at UPSTREAM.md's pins ($(awk '{printf "%s%s %s", (NR > 1 ? ", " : ""), $1, $2}' <<<"${PINS}")) against ${moto_image}."
  echo
  echo "| Chart | Object | Ready | Deleted | Message |"
  echo "| --- | --- | --- | --- | --- |"
} >"${summary}"

# moto_fixups: what AWS does and moto does not (above). Runs boto3 inside
# moto's own pod against moto on localhost, with fake credentials and a dead
# proxy: it reaches nothing else.
moto_fixups() {
  kubectl -n fake-aws exec deploy/moto -- env -i PATH=/usr/local/bin:/usr/bin:/bin \
    AWS_ACCESS_KEY_ID=testing AWS_SECRET_ACCESS_KEY=testing AWS_CONFIG_FILE=/dev/null \
    AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_EC2_METADATA_DISABLED=true \
    HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost \
    python -I -c '
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
kw = dict(endpoint_url="http://localhost:5000", region_name="'"${REGION}"'")
ec2 = boto3.client("ec2", **kw)
subnets = {s["SubnetId"] for s in ec2.describe_subnets()["Subnets"]}
for rt in ec2.describe_route_tables()["RouteTables"]:
    for a in rt.get("Associations", []):
        if a.get("SubnetId") and a["SubnetId"] not in subnets:
            ec2.disassociate_route_table(AssociationId=a["RouteTableAssociationId"])
            print("moto_fixups: removed", a["RouteTableAssociationId"], "of", rt["RouteTableId"], "(subnet", a["SubnetId"], "deleted)")
s3 = boto3.client("s3", config=Config(s3={"addressing_style": "path"}), **kw)
for b in s3.list_buckets().get("Buckets", []):
    try:
        s3.get_bucket_encryption(Bucket=b["Name"])
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchBucket":
            continue  # deleted since the list
        if e.response["Error"]["Code"] != "ServerSideEncryptionConfigurationNotFoundError":
            raise
        s3.put_bucket_encryption(Bucket=b["Name"], ServerSideEncryptionConfiguration={"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]})
        print("moto_fixups: default SSE-S3 on bucket", b["Name"])
' || echo "mock-apply-aws: moto_fixups failed" >&2
}

total=0; failed=0
for values in charts/aws/*/tests/mock.values.yaml; do
  dir="$(dirname "$(dirname "${values}")")"; chart="$(basename "${dir}")"
  if [[ -n "${MOCK_CHARTS:-}" && " ${MOCK_CHARTS} " != *" ${chart} "* ]]; then continue; fi
  ns="catalog-${chart}"; rel="mock"
  echo "== ${chart}"
  mkdir -p "${OUT}/${chart}"
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if grep -q '^dependencies:' "${dir}/Chart.yaml"; then helm dependency build "${dir}" >/dev/null; fi
  needs="${dir}/tests/mock.needs.yaml"
  sets=()
  if [[ -f "${needs}" ]]; then
    kubectl apply --server-side -n "${ns}" -f "${needs}" >"${OUT}/${chart}/needs.log"
    kubectl wait -n "${ns}" --for=condition=Ready -f "${needs}" --timeout="${TIMEOUT}s" >>"${OUT}/${chart}/needs.log" 2>&1 \
      || echo "   ${chart}: tests/mock.needs.yaml not Ready in ${TIMEOUT}s" >&2
    if [[ -f "${dir}/tests/mock.set.yaml" ]]; then
      while read -r key obj path; do
        [[ -n "${key}" && "${key}" != \#* ]] || continue
        val="$(kubectl get -n "${ns}" "${obj}" -o jsonpath="${path}")"
        echo "   ${key%:}=${val} (from ${obj})"
        sets+=(--set-string "${key%:}=${val}")
      done <"${dir}/tests/mock.set.yaml"
    fi
  fi
  helm template "${rel}" "${dir}" --namespace "${ns}" -f "${values}" "${sets[@]}" >"${OUT}/${chart}/rendered.yaml"
  kubectl apply --server-side -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" >"${OUT}/${chart}/apply.log"
  # Fully qualified (kind.version.group/name), as hack/mock-apply.sh does.
  mapfile -t objects < <(kubectl get -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq -r '(if .items then .items else [.] end)[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"')
  deadline=$(( $(date +%s) + TIMEOUT ))
  declare -A ready=()
  for o in "${objects[@]}"; do ready["$o"]=no; done
  while :; do
    pending=0
    for o in "${objects[@]}"; do
      [[ "${ready[$o]}" == yes ]] && continue
      if [[ "$(kubectl get -n "${ns}" "${o}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]; then
        ready["$o"]=yes
      else
        pending=$((pending + 1))
      fi
    done
    (( pending == 0 || $(date +%s) >= deadline )) && break
    moto_fixups
    sleep 3
  done
  kubectl get -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${chart}/live.json"
  if bin/catalogtool outputs "${dir}/package.yaml" "${OUT}/${chart}/live.json" "${dir}/values.yaml" "${values}" >"${OUT}/${chart}/outputs.json" 2>"${OUT}/${chart}/outputs.err"; then
    outputs_ok=yes
  else
    outputs_ok=no
  fi
  echo "-- outputs (${outputs_ok})"; cat "${OUT}/${chart}/outputs.json" "${OUT}/${chart}/outputs.err"
  # Delete the component as Bundt prunes it: every object at once. ACK's
  # finalizer goes once the controller has deleted the resource in moto.
  kubectl delete -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" --wait=false >/dev/null
  deadline=$(( $(date +%s) + TIMEOUT ))
  while [[ -n "$(kubectl get -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" -o name --ignore-not-found)" ]] && (( $(date +%s) < deadline )); do
    moto_fixups
    sleep 3
  done
  for o in "${objects[@]}"; do
    total=$((total + 1))
    d="$(jq -r --arg k "${o%%.*}" --arg n "${o#*/}" '.items[] | select((.kind | ascii_downcase) == $k and .metadata.name == $n) | "\(.kind)/\(.metadata.name)"' "${OUT}/${chart}/live.json")"
    d="${d:-$o}"
    if kubectl get -n "${ns}" "${o}" >/dev/null 2>&1; then
      deleted=no
      cur="$(kubectl get -n "${ns}" "${o}" -o json)"
    else
      deleted=yes
      cur="$(jq --arg d "${d}" '.items[] | select("\(.kind)/\(.metadata.name)" == $d)' "${OUT}/${chart}/live.json")"
    fi
    # The first condition that says why: ACK.Terminal, ACK.Recoverable, then Ready.
    msg="$(jq -r '[(.status.conditions // [])[] | select(.status == "True" and (.type == "ACK.Terminal" or .type == "ACK.Recoverable")) | "\(.type): \(.message // "")"] + [(.status.conditions // [])[] | select(.type == "Ready") | (.message // "")] | map(select(. != "")) | first // ""' <<<"${cur}" | tr '\n|' '  ' | cut -c1-200)"
    [[ "${ready[$o]}" == yes && "${deleted}" == yes ]] || failed=$((failed + 1))
    echo "| ${chart} | ${d} | ${ready[$o]} | ${deleted} | ${msg} |" >>"${summary}"
    echo "   ${d}: ready=${ready[$o]} deleted=${deleted} ${msg}"
  done
  echo "| ${chart} | outputs | ${outputs_ok} | | $(tr '\n' ' ' <"${OUT}/${chart}/outputs.err" | cut -c1-160) |" >>"${summary}"
  if [[ -f "${needs}" ]]; then
    kubectl delete -n "${ns}" -f "${needs}" --wait=false >/dev/null 2>&1 || true
    deadline=$(( $(date +%s) + TIMEOUT ))
    while [[ -n "$(kubectl get -n "${ns}" -f "${needs}" -o name --ignore-not-found)" ]] && (( $(date +%s) < deadline )); do
      moto_fixups
      sleep 3
    done
    if [[ -n "$(kubectl get -n "${ns}" -f "${needs}" -o name --ignore-not-found)" ]]; then
      echo "| ${chart} | tests/mock.needs.yaml | | no | not deleted in ${TIMEOUT}s |" >>"${summary}"
      failed=$((failed + 1))
    fi
  fi
  [[ "${outputs_ok}" == yes ]] || failed=$((failed + 1))
  unset ready
done

kubectl -n fake-aws logs deploy/moto >"${OUT}/moto.log" 2>&1 || true
for d in $(kubectl -n "${ACK_NS}" get deploy -o name); do
  kubectl -n "${ACK_NS}" logs "${d}" --tail=2000 >"${OUT}/$(basename "${d}").log" 2>&1 || true
done
{ echo; echo "${total} objects; ${failed} failures (an object not Ready or not deleted, or a chart's outputs not evaluated)."; } >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
