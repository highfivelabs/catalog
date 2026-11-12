#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply three pilot charts (iam-service-account, gcs, net-vpc) to real
# Google Cloud with tiny resources, delete them, and check nothing is left
# (docs/design.md, "Testing", layer 3). Only after hack/mock-apply.sh
# passes; only in a project allowed below; only on an offload VM acting as
# a service account, never with a key. `task test-live` runs it:
#
#   ../offload/offload run --sa "$GCP_LIVE_SA" \
#     --machine e2-standard-8 --hours 2 -- env PROJECT="$GCP_PROJECT" \
#     GCP_PROJECT="$GCP_PROJECT" CCE_TARBALL=gs://.../cce-<commit>.tar.gz \
#     hack/live-apply.sh
#
# Rules: one project (GCP_PROJECT, or the test estate generation's project
# HFL_GCP_TEST_PROJECT); every gcloud call passes --project;
# every name starts with a run ID, cat-<UTC month day hour minute>-<4 hex>,
# and every object that takes labels carries catalog-run=<run ID>; the test
# deletes what it makes; a sweeper runs before and after (this run's
# resources, and any "cat-" leftovers older than two hours); at the end it
# lists what is left in the project.
#
# LIVE_CHARTS picks the charts (default: the pilot's three,
# "iam-service-account gcs net-vpc"); the others it knows are
# artifact-registry, net-vpc-firewall, net-vpc-peering and net-lb-int. Each
# needs the runner's roles on its resources: the pilot's are
# catalog-live-tests', artifact-registry needs roles/artifactregistry.admin,
# net-vpc-firewall roles/compute.securityAdmin (cce-live-tests has both),
# net-lb-int roles/compute.networkAdmin (both have it). A chart whose case
# needs objects it does not make (a network for the firewall rules, two for
# the peering, a network and subnets for the load balancer) has them applied
# with its render and deleted with it.
#
# Config Connector runs as config-connector-extensions' fake cloud does
# (its manager on the host against a kind cluster holding the CRDs), but
# against Google Cloud: hack/live/realcloud.go.txt, built in a scratch
# copy of config-connector-extensions so it uses the same pinned Config
# Connector. Writes offload-artifacts/live/summary.md.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
: "${GCP_PROJECT:?set GCP_PROJECT, the live-test project (see .env.example)}"
ALLOWED_PROJECTS=("${GCP_PROJECT}")
# And the test estate generation's project (factory/estate/gcp), in the
# live-tests folder, when its env file is loaded.
[[ -z "${HFL_GCP_TEST_PROJECT:-}" ]] || ALLOWED_PROJECTS+=("${HFL_GCP_TEST_PROJECT}")
PROJECT="${PROJECT:-}"
REGION=us-central1
TIMEOUT="${LIVE_TIMEOUT:-600}"
OUT="${ROOT}/offload-artifacts/live"
mkdir -p "${OUT}"

allowed=no
for p in "${ALLOWED_PROJECTS[@]}"; do [[ "${PROJECT}" == "${p}" ]] && allowed=yes; done
[[ "${allowed}" == yes ]] || { echo "live-apply: refusing project '${PROJECT}': only ${ALLOWED_PROJECTS[*]} (GCP_PROJECT, HFL_GCP_TEST_PROJECT)" >&2; exit 2; }
md() { curl -sf -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/$1"; }
RUNNER="$(md instance/service-accounts/default/email || true)"
[[ "${RUNNER}" == *.iam.gserviceaccount.com ]] || { echo "live-apply: not on a VM acting as a service account (got '${RUNNER}')" >&2; exit 2; }
for t in docker kind kubectl helm go git gcloud jq; do
  command -v "$t" >/dev/null || { echo "live-apply: $t is not installed" >&2; exit 2; }
done
G=(gcloud --quiet --project "${PROJECT}")

RUN="cat-$(date -u +%m%d%H%M)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
SA_ID="${RUN}-sa"
BUCKET="${PROJECT}-${RUN}"
NET="${RUN}-net"
REPO="${RUN}-ar"
FWNET="${RUN}-fwnet"
PEER_A="${RUN}-pa"
PEER_B="${RUN}-pb"
ILB="${RUN}-ilb"
LIVE_CHARTS="${LIVE_CHARTS:-iam-service-account gcs net-vpc}"
SUBNET="${RUN}-sn"
echo "== live run ${RUN} in ${PROJECT} as ${RUNNER}"

# sweep_run PREFIX: delete what a run PREFIX (cat-MMDDHHMM-xxxx) made.
sweep_run() {
  local r="$1" s n
  "${G[@]}" iam service-accounts delete "${r}-sa@${PROJECT}.iam.gserviceaccount.com" >/dev/null 2>&1 && echo "swept service account ${r}-sa" || true
  "${G[@]}" storage rm -r "gs://${PROJECT}-${r}" >/dev/null 2>&1 && echo "swept bucket ${PROJECT}-${r}" || true
  "${G[@]}" compute routes list --filter="name~^${r}-net-" --format='value(name)' 2>/dev/null | while read -r n; do
    "${G[@]}" compute routes delete "$n" >/dev/null 2>&1 && echo "swept route $n"
  done || true
  "${G[@]}" compute networks subnets list --filter="name~^${r}-sn\$" --format='value(name,region.basename())' 2>/dev/null | while read -r n s; do
    "${G[@]}" compute networks subnets delete "$n" --region "$s" >/dev/null 2>&1 && echo "swept subnet $n"
  done || true
  "${G[@]}" compute networks delete "${r}-net" >/dev/null 2>&1 && echo "swept network ${r}-net" || true
  "${G[@]}" artifacts repositories delete "${r}-ar" --location "${REGION}" >/dev/null 2>&1 && echo "swept repository ${r}-ar" || true
  "${G[@]}" compute firewall-rules list --filter="name~^${r}-" --format='value(name)' 2>/dev/null | while read -r n; do
    "${G[@]}" compute firewall-rules delete "$n" >/dev/null 2>&1 && echo "swept firewall rule $n"
  done || true
  for n in "${r}-pa" "${r}-pb"; do
    "${G[@]}" compute networks peerings list --network "$n" --format='value(peerings[].name)' 2>/dev/null | tr ';' '\n' | while read -r s; do
      [[ -n "$s" ]] && "${G[@]}" compute networks peerings delete "$s" --network "$n" >/dev/null 2>&1 && echo "swept peering $s"
    done || true
  done
  # net-lb-int: the service attachment, forwarding rule, backend service,
  # health check and group, then its subnets (the network goes below).
  # gcloud's service-attachments delete exits 0 for a name that does not
  # exist, so ask first.
  "${G[@]}" compute service-attachments describe "${r}-ilb" --region "${REGION}" >/dev/null 2>&1 \
    && "${G[@]}" compute service-attachments delete "${r}-ilb" --region "${REGION}" >/dev/null 2>&1 && echo "swept service attachment ${r}-ilb" || true
  "${G[@]}" compute forwarding-rules delete "${r}-ilb" --region "${REGION}" >/dev/null 2>&1 && echo "swept forwarding rule ${r}-ilb" || true
  "${G[@]}" compute backend-services delete "${r}-ilb" --region "${REGION}" >/dev/null 2>&1 && echo "swept backend service ${r}-ilb" || true
  "${G[@]}" compute health-checks delete "${r}-ilb" --global >/dev/null 2>&1 && echo "swept health check ${r}-ilb" || true
  "${G[@]}" compute instance-groups unmanaged delete "${r}-ilb-a" --zone "${REGION}-a" >/dev/null 2>&1 && echo "swept instance group ${r}-ilb-a" || true
  for n in "${r}-ilb-psc" "${r}-ilb-sn"; do
    "${G[@]}" compute networks subnets delete "$n" --region "${REGION}" >/dev/null 2>&1 && echo "swept subnet $n" || true
  done
  for n in "${r}-fwnet" "${r}-pa" "${r}-pb" "${r}-ilb-net"; do
    "${G[@]}" compute networks delete "$n" >/dev/null 2>&1 && echo "swept network $n" || true
  done
}
# sweep_old: every cat- run older than two hours.
sweep_old() {
  local cutoff r
  cutoff="$(date -u -d '2 hours ago' +%m%d%H%M)"
  { "${G[@]}" iam service-accounts list --format='value(email)' | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-sa@.*/\1/p'
    "${G[@]}" storage buckets list --format='value(name)' | sed -n "s/^${PROJECT}-\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)\$/\1/p"
    "${G[@]}" compute networks list --format='value(name)' | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-\(net\|fwnet\|pa\|pb\|ilb-net\)$/\1/p'
    "${G[@]}" artifacts repositories list --location "${REGION}" --format='value(name.basename())' 2>/dev/null | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-ar$/\1/p'
  } | sort -u | while read -r r; do
    [[ "$(echo "$r" | cut -c5-12)" < "${cutoff}" ]] && { echo "sweeping old run $r"; sweep_run "$r"; }
  done || true
}
list_left() {
  "${G[@]}" iam service-accounts list --format='value(email)' | grep -E '^cat-' || true
  "${G[@]}" storage buckets list --format='value(name)' | grep -E "^${PROJECT}-cat-" || true
  "${G[@]}" compute networks list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute routes list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute networks subnets list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" artifacts repositories list --location "${REGION}" --format='value(name.basename())' 2>/dev/null | grep -E '^cat-' || true
  "${G[@]}" compute firewall-rules list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute forwarding-rules list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute backend-services list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute health-checks list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute instance-groups list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute service-attachments list --format='value(name)' 2>/dev/null | grep -E '^cat-' || true
}
cleanup() {
  [[ -n "${MANAGER_PID:-}" ]] && kill "${MANAGER_PID}" 2>/dev/null || true
  kind delete cluster --name catalog-live >/dev/null 2>&1 || true
  echo "== sweep after"; sweep_run "${RUN}"; sweep_old
  echo "== left in ${PROJECT} (nothing should follow)"; left="$(list_left)"; echo "${left}"
  { echo; echo "Left in ${PROJECT} after the run: ${left:-nothing}."; } >>"${OUT}/summary.md" 2>/dev/null || true
}
trap cleanup EXIT
echo "== sweep before"; sweep_old; echo "== left before (other people's cat- things would show here)"; list_left

# config-connector-extensions, its pinned Config Connector, and the manager.
CCE_DIR="${ROOT}/.cache/cce-live"
rm -rf "${CCE_DIR}" && mkdir -p "${CCE_DIR}"
gcloud storage cat "${CCE_TARBALL:?set CCE_TARBALL}" | tar -xz -C "${CCE_DIR}"
git -C "${CCE_DIR}" init -q && git -C "${CCE_DIR}" add -A && \
  git -C "${CCE_DIR}" -c user.email=live@example.com -c user.name=live commit -qm "cce from ${CCE_TARBALL}"
(cd "${CCE_DIR}" && make upstream >/dev/null)
mkdir -p "${CCE_DIR}/cmd/realcloud"
cp hack/live/realcloud.go.txt "${CCE_DIR}/cmd/realcloud/main.go"
(cd "${CCE_DIR}" && GOTOOLCHAIN=auto go build -o "${ROOT}/bin/realcloud" ./cmd/realcloud)
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)

export KUBECONFIG="${OUT}/kubeconfig"
kind create cluster --name catalog-live --kubeconfig "${KUBECONFIG}" --wait 120s
KCC="${CCE_DIR}/third_party/k8s-config-connector"
# Config Connector's own core CRDs (ConfigConnector, ConfigConnectorContext)
# first: the manager's registration controller reads them and stops without.
{ for f in "${KCC}"/operator/config/crd/bases/core.cnrm.cloud.google.com_*.yaml; do printf -- '---\n'; cat "$f"; done
  for g in iam storage compute artifactregistry; do
    for f in "${KCC}"/config/crds/resources/*."${g}".cnrm.cloud.google.com.yaml; do printf -- '---\n'; cat "$f"; done
  done; } | kubectl apply --server-side --force-conflicts -f - >/dev/null
kubectl wait --for=condition=Established crd --all --timeout=180s >/dev/null
"${ROOT}/bin/realcloud" >"${OUT}/manager.log" 2>&1 &
MANAGER_PID=$!
# Fail fast: a manager that stopped (the first live run's did, for want of
# the core CRDs) reconciles nothing, and waiting ten minutes per chart for
# Ready would only say so slowly.
started=no
for _ in $(seq 1 90); do
  grep -q "Starting workers" "${OUT}/manager.log" && { started=yes; break; }
  kill -0 "${MANAGER_PID}" 2>/dev/null || break
  sleep 2
done
if [[ "${started}" != yes ]]; then
  echo "live-apply: the manager did not start:" >&2; grep -v round_trippers "${OUT}/manager.log" | tail -15 >&2
  { echo; echo "The manager did not start; nothing was applied."; } >>"${OUT}/summary.md" 2>/dev/null || true
  exit 1
fi
NS=catalog-live
kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl annotate --local -f - "cnrm.cloud.google.com/project-id=${PROJECT}" -o yaml | kubectl apply -f - >/dev/null

cat >"${OUT}/iam-service-account.values.yaml" <<VALUES
project_id: ${PROJECT}
name: ${SA_ID}
display_name: catalog live test ${RUN}
iam:
  roles/iam.serviceAccountUser: ["serviceAccount:${RUNNER}"]
VALUES
cat >"${OUT}/gcs.values.yaml" <<VALUES
project_id: ${PROJECT}
name: ${BUCKET}
location: ${REGION^^}
force_destroy: true
soft_delete_retention: 0
public_access_prevention: enforced
labels: {catalog-run: ${RUN}}
iam:
  roles/storage.objectViewer: ["serviceAccount:${RUNNER}"]
VALUES
cat >"${OUT}/net-vpc.values.yaml" <<VALUES
project_id: ${PROJECT}
name: ${NET}
description: catalog live test ${RUN}
subnets:
  - name: ${SUBNET}
    region: ${REGION}
    ip_cidr_range: 10.250.0.0/28
    description: catalog live test ${RUN}
routes:
  appliance: {dest_range: 192.168.250.0/24, next_hop_type: ip, next_hop: 10.250.0.5}
VALUES

cat >"${OUT}/artifact-registry.values.yaml" <<VALUES
project_id: ${PROJECT}
location: ${REGION}
name: ${REPO}
description: catalog live test ${RUN}
labels: {catalog-run: ${RUN}}
format: {docker: {standard: {immutable_tags: false}}}
cleanup_policy_dry_run: true
cleanup_policies:
  keep-3: {action: KEEP, most_recent_versions: {keep_count: 3}}
iam:
  roles/artifactregistry.reader: ["serviceAccount:${RUNNER}"]
iam_bindings_additive:
  writer: {member: "serviceAccount:${RUNNER}", role: roles/artifactregistry.writer}
VALUES

cat >"${OUT}/net-vpc-firewall.values.yaml" <<VALUES
project_id: ${PROJECT}
network: ${FWNET}
default_rules_config: {http_ranges: [], https_ranges: []}
ingress_rules:
  ${RUN}-allow-ntp:
    description: catalog live test ${RUN}
    targets: [ntp-svc]
    source_ranges: [rfc1918]
    rules: [{protocol: udp, ports: ["123"]}]
egress_rules:
  ${RUN}-deny-egress: {priority: 65000, enable_logging: {include_metadata: false}}
VALUES
cat >"${OUT}/net-vpc-firewall.needs.yaml" <<NEEDS
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-fwnet
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${FWNET}
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
NEEDS
cat >"${OUT}/net-vpc-peering.values.yaml" <<VALUES
local_network: projects/${PROJECT}/global/networks/${PEER_A}
peer_network: projects/${PROJECT}/global/networks/${PEER_B}
routes_config:
  local: {import: false}
VALUES
cat >"${OUT}/net-vpc-peering.needs.yaml" <<NEEDS
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-pa
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${PEER_A}
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-pb
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${PEER_B}
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
NEEDS

cat >"${OUT}/net-lb-int.values.yaml" <<VALUES
project_id: ${PROJECT}
region: ${REGION}
name: ${ILB}
vpc_config:
  network: projects/${PROJECT}/global/networks/${ILB}-net
  subnetwork: projects/${PROJECT}/regions/${REGION}/subnetworks/${ILB}-sn
labels: {catalog-run: ${RUN}}
group_configs:
  a: {zone: ${REGION}-a, named_ports: {http: 80}}
backends:
  - group: a
forwarding_rules_config:
  "": {ports: ["80"], global_access: false}
health_check_config:
  http: {port: 80, request_path: /healthz}
service_attachments:
  "":
    nat_subnets: [projects/${PROJECT}/regions/${REGION}/subnetworks/${ILB}-psc]
VALUES
cat >"${OUT}/net-lb-int.needs.yaml" <<NEEDS
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-ilb-net
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${ILB}-net
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-ilb-sn
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${ILB}-sn
  region: ${REGION}
  ipCidrRange: 10.251.0.0/28
  networkRef: {name: live-ilb-net}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-ilb-psc
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${ILB}-psc
  region: ${REGION}
  ipCidrRange: 10.251.1.0/28
  purpose: PRIVATE_SERVICE_CONNECT
  networkRef: {name: live-ilb-net}
NEEDS

summary="${OUT}/summary.md"
{
  echo "# Live apply ${RUN}, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Project ${PROJECT}, as ${RUNNER}; catalog $(git rev-parse --short HEAD 2>/dev/null || echo unknown); Config Connector at config-connector-extensions' pin."
  echo
  echo "| Chart | Object | Ready | Deleted | Gone from Google Cloud | Message |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >"${summary}"
failed=0
for chart in ${LIVE_CHARTS}; do
  echo "== ${chart}"
  dir="charts/gcp/${chart}"
  helm template live "${dir}" --namespace "${NS}" -f "${OUT}/${chart}.values.yaml" >"${OUT}/${chart}.rendered.yaml"
  # What the case needs and the chart does not make, applied and deleted with it.
  if [[ -f "${OUT}/${chart}.needs.yaml" ]]; then
    { cat "${OUT}/${chart}.needs.yaml"; echo "---"; cat "${OUT}/${chart}.rendered.yaml"; } >"${OUT}/${chart}.with-needs.yaml"
    mv "${OUT}/${chart}.with-needs.yaml" "${OUT}/${chart}.rendered.yaml"
  fi
  kubectl apply --server-side -n "${NS}" -f "${OUT}/${chart}.rendered.yaml"
  # Fully qualified (kind.version.group/name): "Service" alone is the core kind.
  mapfile -t objects < <(kubectl get -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" -o json \
    | jq -r '.items[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"')
  declare -A ready=() msgs=()
  deadline=$(( $(date +%s) + TIMEOUT ))
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${NS}" --for=condition=Ready "$o" --timeout="${left}s" >/dev/null 2>&1; then ready[$o]=yes; else ready[$o]=no; fi
    msgs[$o]="$(kubectl get -n "${NS}" "$o" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | tr '\n|' '  ' | cut -c1-200 || true)"
  done
  kubectl get -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" -o json >"${OUT}/${chart}.live.json"
  bin/catalogtool outputs "${dir}/package.yaml" "${OUT}/${chart}.live.json" "${dir}/values.yaml" "${OUT}/${chart}.values.yaml" >"${OUT}/${chart}.outputs.json" 2>&1 || failed=$((failed + 1))
  cat "${OUT}/${chart}.outputs.json"
  kubectl delete -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" --wait=false >/dev/null
  # Config Connector's deletion defender runs as its own pod in a real
  # install; here the manager runs alone, so do the defender's part: remove
  # its finalizer, and Config Connector's controller deletes the resource.
  deadline=$(( $(date +%s) + TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    left=0
    for o in "${objects[@]}"; do
      f="$(kubectl get -n "${NS}" "$o" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)" || continue
      left=$((left + 1))
      if [[ "${f}" == *deletion-defender* ]]; then
        kubectl get -n "${NS}" "$o" -o json \
          | jq '.metadata.finalizers |= map(select(. != "cnrm.cloud.google.com/deletion-defender"))' \
          | kubectl replace -f - >/dev/null 2>&1 || true
      fi
    done
    (( left == 0 )) && break
    sleep 3
  done
  case "${chart}" in
    gcs) "${G[@]}" storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1 && gone=no || gone=yes ;;
    iam-service-account) "${G[@]}" iam service-accounts describe "${SA_ID}@${PROJECT}.iam.gserviceaccount.com" >/dev/null 2>&1 && gone=no || gone=yes ;;
    net-vpc)
      gone=yes
      "${G[@]}" compute networks describe "${NET}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks subnets describe "${SUBNET}" --region "${REGION}" >/dev/null 2>&1 && gone=no ;;
    artifact-registry) "${G[@]}" artifacts repositories describe "${REPO}" --location "${REGION}" >/dev/null 2>&1 && gone=no || gone=yes ;;
    net-vpc-firewall)
      gone=yes
      "${G[@]}" compute networks describe "${FWNET}" >/dev/null 2>&1 && gone=no
      [[ -z "$("${G[@]}" compute firewall-rules list --filter="network~/${FWNET}\$" --format='value(name)' 2>/dev/null)" ]] || gone=no ;;
    net-vpc-peering)
      gone=yes
      "${G[@]}" compute networks describe "${PEER_A}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks describe "${PEER_B}" >/dev/null 2>&1 && gone=no ;;
    net-lb-int)
      gone=yes
      "${G[@]}" compute forwarding-rules describe "${ILB}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute backend-services describe "${ILB}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute health-checks describe "${ILB}" --global >/dev/null 2>&1 && gone=no
      "${G[@]}" compute instance-groups unmanaged describe "${ILB}-a" --zone "${REGION}-a" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute service-attachments describe "${ILB}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks describe "${ILB}-net" >/dev/null 2>&1 && gone=no ;;
    *) echo "live-apply: no check that ${chart} is gone" >&2; gone=no ;;
  esac
  for o in "${objects[@]}"; do
    kubectl get -n "${NS}" "$o" >/dev/null 2>&1 && deleted=no || deleted=yes
    [[ "${ready[$o]}" == yes && "${deleted}" == yes && "${gone}" == yes ]] || failed=$((failed + 1))
    d="${o%%.*}/${o#*/}"
    echo "| ${chart} | ${d} | ${ready[$o]} | ${deleted} | ${gone} | ${msgs[$o]} |" >>"${summary}"
    echo "   ${d} ready=${ready[$o]} deleted=${deleted} gone=${gone} ${msgs[$o]}"
  done
  unset ready msgs
done
{ echo; echo "${failed} failures."; } >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
