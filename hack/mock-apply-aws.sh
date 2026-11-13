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
# Two fakes, as ack-extensions tests its kinds (docs/aws-emulator.md and
# tests/operator/run.sh there): AWS Emulator first (the release
# ack-extensions' hack/aws-emulator.sh pins, its package's signature
# checked), on this VM's loopback behind tools/emuproxy; then moto
# (config/fake-aws/moto.yaml, its image checked against the digest that
# file pins), in the cluster, for each chart that fails on the emulator
# (MOCK_BACKENDS="moto" for moto alone). In front of them, on kind:
#   - every ACK controller pinned in UPSTREAM.md ("ACK controllers"),
#     installed from its own Helm chart at the pinned commit, every AWS
#     endpoint at the fake in use, fake credentials;
#   - ack-extensions (config/default built by ko, the operator in its
#     fake-AWS mode), whose operator runs a manager beside each ACK
#     controller that has ack-extensions kinds (crds/ack-extensions), and a
#     Cloud Control manager for the namespace of each chart whose case
#     renders a Cloud Control kind (a CloudControlContext there, cc_context).
# Every AWS client in the cluster gets every endpoint at the fake and a
# dead proxy (ack-extensions' hack/noaws env), and the run stops unless
# ack-extensions' hack/noaws verify-deployments passes for all of them,
# after every switch of fake. The summary says which fake each chart
# passed on.
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
# (vpc_id: vpcs.ec2.services.k8s.aws/sg-vpc {.status.vpcID}), or the fake's
# own account in a format, `<value>: account <format>`
# (key_users[0]: account arn:aws:iam::%s:root), passed to the render with
# --set-string.
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
MOTO_URL="http://moto.fake-aws.svc:5000"
# AWS Emulator (github.com/aws/aws-emulator) runs on this host, on
# loopback, behind tools/emuproxy (plain HTTP, the emulator's keys, its own
# certificate trusted); a selector-less Service gives it this name in the
# cluster.
EMU_URL="http://emulator.fake-aws.svc:4567"
# The fakes, in order: every chart runs on the first; a chart that fails
# there runs again on the next (the summary says which it passed on).
BACKENDS="${MOCK_BACKENDS:-aws-emulator moto}"
url_of() { case "$1" in aws-emulator) echo "${EMU_URL}" ;; moto) echo "${MOTO_URL}" ;; *) echo "mock-apply-aws: unknown fake $1" >&2; exit 2 ;; esac; }
FIRST="${BACKENDS%% *}"
# The one account each fake answers as.
account_of() { case "$1" in aws-emulator) echo 000000000000 ;; moto) echo 123456789012 ;; esac; }
mkdir -p "${OUT}"

for t in docker kind kubectl helm go git jq crane ko setsid; do
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
cleanup() {
  pkill -f "${work}/emuproxy" 2>/dev/null || true
  pkill -f "aws-emulator --port 4566" 2>/dev/null || true
  kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true
  rm -rf "${work}" "${DOCKER_CONFIG}"
}
trap cleanup EXIT

start=$(date +%s)
echo "== cluster ${CLUSTER}"
kind get clusters | grep -qx "${CLUSTER}" || kind create cluster --name "${CLUSTER}" --image "${NODE_IMAGE}" --wait 120s
kubectl config use-context "kind-${CLUSTER}" >/dev/null
KUBE_HOST="$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')"
# fake_env URL: the environment ack-extensions' guard gives every AWS client
# for that fake (every endpoint at it, the fake keys, the dead proxy).
fake_env() {
  "${ROOT}/bin/noaws" env "$1" "${KUBE_HOST}" >"${work}/fake.env"
  mapfile -t FAKE_ENV <"${work}/fake.env"
  [[ ${#FAKE_ENV[@]} -gt 0 ]] || { echo "mock-apply-aws: hack/noaws env printed nothing" >&2; exit 1; }
}

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
kubectl -n fake-aws set env deploy/moto "MOTO_S3_CUSTOM_ENDPOINTS=${MOTO_URL}" MOTO_IAM_LOAD_MANAGED_POLICIES=true >/dev/null
kubectl -n fake-aws rollout status deploy/moto --timeout=180s >/dev/null
kubectl -n kube-system get configmap coredns -o json \
  | jq '.data.Corefile |= sub("ready\n"; "ready\n    rewrite name regex (.+)\\.moto\\.fake-aws\\.svc\\.cluster\\.local moto.fake-aws.svc.cluster.local answer auto\n    rewrite name regex (.+)\\.emulator\\.fake-aws\\.svc\\.cluster\\.local emulator.fake-aws.svc.cluster.local answer auto\n")' \
  >"${work}/coredns.json"
grep -q 'moto.fake-aws.svc.cluster.local answer auto' "${work}/coredns.json" \
  || { echo "mock-apply-aws: could not add the S3 host rewrite to CoreDNS's Corefile" >&2; exit 1; }
kubectl apply -f "${work}/coredns.json" >/dev/null
kubectl -n kube-system rollout restart deploy/coredns >/dev/null
kubectl -n kube-system rollout status deploy/coredns --timeout=120s >/dev/null
echo "   ${moto_image} (${moto_digest}); <bucket>.moto.fake-aws.svc answered by moto"

echo "== fake AWS (AWS Emulator)"
# The emulator at the version ack-extensions pins (its hack/aws-emulator.sh:
# the Debian package, its signature checked), on loopback, telemetry off,
# with the dead proxy: it reaches nothing.
"${ACKX_DIR}/hack/aws-emulator.sh" >/dev/null
EMU_VERSION="$(aws-emulator -v | awk '/^Version/ {print $2}')"
mkdir -p "${work}/emu-home"
env -i PATH="${PATH}" HOME="${work}/emu-home" EMULATOR_TELEMETRY=off \
  HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1,localhost \
  setsid -f aws-emulator --port 4566 --telemetry off --idle-timeout 36000 >"${work}/emulator.log" 2>&1
emu_info=""
for _ in $(seq 1 60); do
  # Lines that are not JSON are skipped (fromjson?).
  emu_info="$(jq -Rc 'fromjson? | select(type == "object") | (if .fields then .fields + {message: (.message // .fields.message)} else . end) | select(.message == "emulator server information")' "${work}/emulator.log" | head -n 1)"
  [[ -n "${emu_info}" ]] && break
  sleep 1
done
[[ -n "${emu_info}" ]] || { echo "mock-apply-aws: the emulator wrote no startup line in 60s" >&2; cat "${work}/emulator.log" >&2; exit 1; }
emu_endpoint="$(jq -r .endpoint_url <<<"${emu_info}")"
emu_ca="$(jq -r .ca_file <<<"${emu_info}")"
# The kind network's gateway: this host, as the cluster's pods reach it.
GW="$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)"
[[ -n "${GW}" ]] || { echo "mock-apply-aws: no IPv4 gateway on the kind network" >&2; exit 1; }
(cd tools && go build -o "${work}/emuproxy" ./emuproxy)
setsid -f "${work}/emuproxy" -listen "${GW}:4567" -upstream "${emu_endpoint}" -ca "${emu_ca}" \
  -credentials "$(dirname "${emu_ca}")/emulator_credentials" -base emulator.fake-aws.svc >"${work}/emuproxy.log" 2>&1
for _ in $(seq 1 30); do curl -s -o /dev/null "http://${GW}:4567/" && break; sleep 1; done
kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata: {name: emulator, namespace: fake-aws}
spec:
  ports: [{port: 4567, targetPort: 4567}]
---
apiVersion: v1
kind: Endpoints
metadata: {name: emulator, namespace: fake-aws}
subsets:
  - addresses: [{ip: "${GW}"}]
    ports: [{port: 4567}]
YAML
echo "   aws-emulator ${EMU_VERSION} at ${emu_endpoint}, behind emuproxy on ${GW}:4567 (emulator.fake-aws.svc)"

echo "== ACK controllers"
fake_env "$(url_of "${FIRST}")"
kubectl create namespace "${ACK_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "${ACK_NS}" create secret generic aws-creds \
  --from-literal=credentials=$'[default]\naws_access_key_id = testing\naws_secret_access_key = testing\n' \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
while read -r name version _; do
  svc="${name%-controller}"
  helm upgrade --install "ack-${svc}" "${ROOT}/.cache/ack-helm/${name}-${version}/helm" -n "${ACK_NS}" \
    --set aws.region="${REGION}" \
    --set aws.endpoint_url="$(url_of "${FIRST}")" \
    --set aws.identity_endpoint_url="$(url_of "${FIRST}")" \
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
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--fake-aws-endpoint='"$(url_of "${FIRST}")"'"}
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
echo "== fake AWS up in $(( $(date +%s) - start ))s; every AWS client verified to reach only the fakes (${FIRST} first)"

# point_at FAKE: every AWS client in the cluster (ACK's controllers,
# ack-extensions' operator and its managers) at that fake, then checked
# again by ack-extensions' guard.
point_at() {
  local url; url="$(url_of "$1")"
  echo "== every AWS client to $1 (${url})"
  fake_env "${url}"
  while read -r name version _; do
    svc="${name%-controller}"
    helm upgrade "ack-${svc}" "${ROOT}/.cache/ack-helm/${name}-${version}/helm" -n "${ACK_NS}" --reuse-values \
      --set aws.endpoint_url="${url}" --set aws.identity_endpoint_url="${url}" >/dev/null
    deploy="$(kubectl -n "${ACK_NS}" get deploy -l "app.kubernetes.io/name=${svc}-chart" -o jsonpath='{.items[0].metadata.name}')"
    kubectl -n "${ACK_NS}" set env "deploy/${deploy}" "${FAKE_ENV[@]}" >/dev/null
  done <<<"${PINS}"
  i="$(kubectl -n ack-extensions-system get deploy ack-extensions-operator -o json | jq '.spec.template.spec.containers[0].args | map(startswith("--fake-aws-endpoint=")) | index(true)')"
  kubectl -n ack-extensions-system patch deploy ack-extensions-operator --type=json \
    -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/args/'"${i}"'", "value": "--fake-aws-endpoint='"${url}"'"}]' >/dev/null
  local end=$(( $(date +%s) + 300 ))
  # Until every AWS client's AWS_ENDPOINT_URL is the fake's and it has rolled out.
  until [[ -z "$(kubectl get deploy -n "${ACK_NS}" -o json | jq -r --arg u "${url}" '.items[] | select(([.spec.template.spec.containers[].env // [] | .[] | select(.name == "AWS_ENDPOINT_URL") | .value] | length) > 0) | select(([.spec.template.spec.containers[].env // [] | .[] | select(.name == "AWS_ENDPOINT_URL") | .value] | all(. == $u)) | not) | .metadata.name')" ]]; do
    (( $(date +%s) < end )) || { echo "mock-apply-aws: AWS clients still not at ${url} after 300s" >&2; exit 1; }
    sleep 5
  done
  for d in $(kubectl -n "${ACK_NS}" get deploy -o name) deploy/ack-extensions-operator; do
    ns="${ACK_NS}"; [[ "${d}" == deploy/ack-extensions-operator ]] && ns=ack-extensions-system
    kubectl -n "${ns}" rollout status "${d}" --timeout=300s >/dev/null
  done
  kubectl get deploy -A -o json >"${work}/deployments.json"
  "${ROOT}/bin/noaws" verify-deployments <"${work}/deployments.json" >/dev/null \
    || { echo "mock-apply-aws: an AWS client in the cluster could reach real AWS" >&2; exit 1; }
}

summary="${OUT}/summary.md"
{
  echo "# Mock apply (AWS), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Catalog commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown); ack-extensions from ${ACKX_TARBALL:-${ACKX_DIR}};"
  echo "ACK controllers at UPSTREAM.md's pins ($(awk '{printf "%s%s %s", (NR > 1 ? ", " : ""), $1, $2}' <<<"${PINS}"));"
  echo "fakes, in order: ${BACKENDS} (aws-emulator ${EMU_VERSION}, ${moto_image}). A chart that fails on one runs again on the next."
} >"${summary}"

# moto_fixups: what AWS does and moto does not (above). Runs boto3 inside
# moto's own pod against moto on localhost, with fake credentials and a dead
# proxy: it reaches nothing else.
moto_fixups() {
  [[ "${BACKEND}" == moto ]] || return 0
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

# cc_context NS: ack-extensions' Cloud Control kinds (*.cloudcontrol.aws.hfl.dev)
# are served by a manager per environment, which a CloudControlContext in
# the environment's namespace starts (ack-extensions' pkg/operator,
# cloudcontrol.go); the operator's --fake-aws-endpoint points it at the fake
# in use. The role is the fake account's (nothing assumes it: the fake keys
# are the manager's). Waits until Ready, then checks the manager with
# ack-extensions' guard, as every other AWS client.
cc_context() {
  local ns="$1" end
  kubectl apply -f - >/dev/null <<YAML
apiVersion: cloudcontrol.aws.hfl.dev/v1alpha1
kind: CloudControlContext
metadata: {name: cloudcontrol, namespace: ${ns}}
spec: {roleARN: "arn:aws:iam::$(account_of "${BACKEND}"):role/catalog-cloudcontrol", region: ${REGION}}
YAML
  end=$(( $(date +%s) + 240 ))
  until [[ "$(kubectl -n "${ns}" get cloudcontrolcontext cloudcontrol -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == True ]]; do
    if (( $(date +%s) >= end )); then
      echo "mock-apply-aws: CloudControlContext ${ns}/cloudcontrol not Ready in 240s" >&2
      kubectl -n "${ns}" get cloudcontrolcontext cloudcontrol -o yaml >&2 || true
      kubectl -n ack-extensions-system logs deploy/ack-extensions-operator --tail=40 >&2 || true
      return 1
    fi
    sleep 3
  done
  kubectl get deploy -A -o json >"${work}/deployments.json"
  "${ROOT}/bin/noaws" verify-deployments <"${work}/deployments.json" >/dev/null \
    || { echo "mock-apply-aws: an AWS client in the cluster could reach real AWS" >&2; exit 1; }
  echo "   CloudControlContext ${ns}/cloudcontrol Ready: a Cloud Control manager serves ${ns}"
}

# run_chart VALUES: apply one chart's case to the fake BACKEND points at,
# check it, delete it. Its rows go to ${OUT}/${BACKEND}/<chart>.rows; it
# sets chart_failed (objects not Ready or not deleted, outputs not
# evaluated).
run_chart() {
  local values="$1" dir chart
  dir="$(dirname "$(dirname "${values}")")"; chart="$(basename "${dir}")"
  dir="$(dirname "$(dirname "${values}")")"; chart="$(basename "${dir}")"
  ns="catalog-${chart}-${BACKEND}"; rel="mock"
  echo "== ${chart} on ${BACKEND}"
  local out="${OUT}/${BACKEND}/${chart}" rows="${OUT}/${BACKEND}/${chart}.rows"
  mkdir -p "${out}"; : >"${rows}"; chart_failed=0
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if grep -q '^dependencies:' "${dir}/Chart.yaml"; then helm dependency build "${dir}" >/dev/null; fi
  needs="${dir}/tests/mock.needs.yaml"
  sets=()
  if [[ -f "${needs}" ]]; then
    kubectl apply --server-side -n "${ns}" -f "${needs}" >"${out}/needs.log"
    kubectl wait -n "${ns}" --for=condition=Ready -f "${needs}" --timeout="${TIMEOUT}s" >>"${out}/needs.log" 2>&1 \
      || echo "   ${chart}: tests/mock.needs.yaml not Ready in ${TIMEOUT}s" >&2
  fi
  if [[ -f "${dir}/tests/mock.set.yaml" ]]; then
    while read -r key obj path; do
      [[ -n "${key}" && "${key}" != \#* ]] || continue
      if [[ "${obj}" == account ]]; then
        # The fake's own account, in a format (%s): the caller's, as AWS checks it.
        # shellcheck disable=SC2059
        val="$(printf "${path:-%s}" "$(account_of "${BACKEND}")")"
      else
        val="$(kubectl get -n "${ns}" "${obj}" -o jsonpath="${path}")"
      fi
      echo "   ${key%:}=${val} (from ${obj})"
      sets+=(--set-string "${key%:}=${val}")
    done <"${dir}/tests/mock.set.yaml"
  fi
  helm template "${rel}" "${dir}" --namespace "${ns}" -f "${values}" "${sets[@]}" >"${out}/rendered.yaml"
  local cc=no
  if grep -Eq '^apiVersion: [a-z0-9]+\.cloudcontrol\.aws\.hfl\.dev/' "${out}/rendered.yaml"; then
    cc=yes
    cc_context "${ns}" || echo "   ${chart}: no Cloud Control manager for ${ns}" >&2
  fi
  kubectl apply --server-side -n "${ns}" -f "${out}/rendered.yaml" >"${out}/apply.log"
  # Fully qualified (kind.version.group/name), as hack/mock-apply.sh does.
  mapfile -t objects < <(kubectl get -n "${ns}" -f "${out}/rendered.yaml" -o json \
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
  kubectl get -n "${ns}" -f "${out}/rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${out}/live.json"
  if bin/catalogtool outputs "${dir}/package.yaml" "${out}/live.json" "${dir}/values.yaml" "${values}" >"${out}/outputs.json" 2>"${out}/outputs.err"; then
    outputs_ok=yes
  else
    outputs_ok=no
  fi
  echo "-- outputs (${outputs_ok})"; cat "${out}/outputs.json" "${out}/outputs.err"
  # Delete the component as Bundt prunes it: every object at once. ACK's
  # finalizer goes once the controller has deleted the resource in moto.
  kubectl delete -n "${ns}" -f "${out}/rendered.yaml" --wait=false >/dev/null
  deadline=$(( $(date +%s) + TIMEOUT ))
  while [[ -n "$(kubectl get -n "${ns}" -f "${out}/rendered.yaml" -o name --ignore-not-found)" ]] && (( $(date +%s) < deadline )); do
    moto_fixups
    sleep 3
  done
  for o in "${objects[@]}"; do
    d="$(jq -r --arg k "${o%%.*}" --arg n "${o#*/}" '.items[] | select((.kind | ascii_downcase) == $k and .metadata.name == $n) | "\(.kind)/\(.metadata.name)"' "${out}/live.json")"
    d="${d:-$o}"
    if kubectl get -n "${ns}" "${o}" >/dev/null 2>&1; then
      deleted=no
      cur="$(kubectl get -n "${ns}" "${o}" -o json)"
    else
      deleted=yes
      cur="$(jq --arg d "${d}" '.items[] | select("\(.kind)/\(.metadata.name)" == $d)' "${out}/live.json")"
    fi
    # The first condition that says why: ACK.Terminal, ACK.Recoverable, then Ready.
    msg="$(jq -r '[(.status.conditions // [])[] | select(.status == "True" and (.type == "ACK.Terminal" or .type == "ACK.Recoverable")) | "\(.type): \(.message // "")"] + [(.status.conditions // [])[] | select(.type == "Ready") | (.message // "")] | map(select(. != "")) | first // ""' <<<"${cur}" | tr '\n|' '  ' | cut -c1-200)"
    [[ "${ready[$o]}" == yes && "${deleted}" == yes ]] || chart_failed=$((chart_failed + 1))
    echo "| ${chart} | ${d} | ${ready[$o]} | ${deleted} | ${msg} |" >>"${rows}"
    echo "   ${d}: ready=${ready[$o]} deleted=${deleted} ${msg}"
  done
  echo "| ${chart} | outputs | ${outputs_ok} | | $(tr '\n' ' ' <"${out}/outputs.err" | cut -c1-160) |" >>"${rows}"
  if [[ -f "${needs}" ]]; then
    kubectl delete -n "${ns}" -f "${needs}" --wait=false >/dev/null 2>&1 || true
    deadline=$(( $(date +%s) + TIMEOUT ))
    while [[ -n "$(kubectl get -n "${ns}" -f "${needs}" -o name --ignore-not-found)" ]] && (( $(date +%s) < deadline )); do
      moto_fixups
      sleep 3
    done
    if [[ -n "$(kubectl get -n "${ns}" -f "${needs}" -o name --ignore-not-found)" ]]; then
      echo "| ${chart} | tests/mock.needs.yaml | | no | not deleted in ${TIMEOUT}s |" >>"${rows}"
      chart_failed=$((chart_failed + 1))
    fi
  fi
  if [[ "${cc}" == yes ]]; then
    kubectl -n "${ns}" delete cloudcontrolcontext cloudcontrol --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  [[ "${outputs_ok}" == yes ]] || chart_failed=$((chart_failed + 1))
  unset ready
}

charts=()
for values in charts/aws/*/tests/mock.values.yaml; do
  chart="$(basename "$(dirname "$(dirname "${values}")")")"
  if [[ -n "${MOCK_CHARTS:-}" && " ${MOCK_CHARTS} " != *" ${chart} "* ]]; then continue; fi
  charts+=("${values}")
done
declare -A passed_on=() tried=()
todo=("${charts[@]}")
for BACKEND in ${BACKENDS}; do
  [[ ${#todo[@]} -gt 0 ]] || break
  [[ "${BACKEND}" == "${FIRST}" ]] || point_at "${BACKEND}"
  next=()
  for values in "${todo[@]}"; do
    chart="$(basename "$(dirname "$(dirname "${values}")")")"
    run_chart "${values}"
    tried["${chart}"]="${tried[${chart}]:-}${tried[${chart}]:+, }${BACKEND} ($([[ ${chart_failed} -eq 0 ]] && echo pass || echo "${chart_failed} failures"))"
    if [[ ${chart_failed} -eq 0 ]]; then passed_on["${chart}"]="${BACKEND}"; else next+=("${values}"); fi
  done
  todo=("${next[@]}")
done

total=0; failed=0
{
  echo
  echo "| Chart | Passed on | Tried |"
  echo "| --- | --- | --- |"
  for values in "${charts[@]}"; do
    chart="$(basename "$(dirname "$(dirname "${values}")")")"
    echo "| ${chart} | ${passed_on[${chart}]:-none} | ${tried[${chart}]} |"
  done
  echo
  echo "| Chart | Fake | Object | Ready | Deleted | Message |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >>"${summary}"
for values in "${charts[@]}"; do
  chart="$(basename "$(dirname "$(dirname "${values}")")")"
  b="${passed_on[${chart}]:-${BACKENDS##* }}"
  for t in ${BACKENDS}; do
    [[ -f "${OUT}/${t}/${chart}.rows" ]] || continue
    # The fake it passed on, and the ones before it, that it failed on.
    sed "s/^| ${chart} | /| ${chart} | ${t} | /" "${OUT}/${t}/${chart}.rows" >>"${summary}"
    [[ "${t}" == "${b}" ]] && break
  done
  rows="${OUT}/${b}/${chart}.rows"
  total=$((total + $(grep -vc '| outputs |' "${rows}" || true)))
  [[ -n "${passed_on[${chart}]:-}" ]] || failed=$((failed + 1))
done

kubectl -n fake-aws logs deploy/moto >"${OUT}/moto.log" 2>&1 || true
for d in $(kubectl -n "${ACK_NS}" get deploy -o name); do
  kubectl -n "${ACK_NS}" logs "${d}" --tail=2000 >"${OUT}/$(basename "${d}").log" 2>&1 || true
done
cp "${work}/emulator.log" "${work}/emuproxy.log" "${OUT}/" 2>/dev/null || true
{ echo; echo "${#charts[@]} charts, ${total} objects; ${failed} charts passed on no fake (an object not Ready or not deleted, or the outputs not evaluated)."; } >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
