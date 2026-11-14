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
# artifact-registry, net-vpc-firewall, net-vpc-peering, net-lb-int,
# net-lb-ext, net-vpn-static, net-address, net-cloud-armor,
# net-lb-proxy-int-cross-region, net-lb-app-int-cross-region, compute-mig
# and compute-mig-stateful (a second case of the compute-mig chart). Each needs
# the runner's roles on its resources: the pilot's are catalog-live-tests',
# artifact-registry needs roles/artifactregistry.admin, net-vpc-firewall
# roles/compute.securityAdmin (cce-live-tests has both), net-lb-int,
# net-lb-ext, net-vpn-static, net-address, net-lb-proxy-int-cross-region
# and net-lb-app-int-cross-region roles/compute.networkAdmin (both have
# it; net-address's case includes a PSC network attachment,
# config-connector-extensions' ComputeNetworkAttachment), net-cloud-armor
# roles/compute.securityAdmin (cce-live-tests), compute-mig and
# compute-mig-stateful roles/compute.instanceAdmin.v1 and
# roles/compute.networkAdmin (cce-live-tests; each makes one e2-micro VM,
# a zonal managed instance group with config-connector-extensions'
# ComputeAutoscaler or ComputePerInstanceConfig, and checks that Config
# Connector leaves the group's size to them). A chart whose case
# needs objects it does not make (a network for the firewall rules, two for
# the peering, a network and subnets for the load balancer) has them applied
# with its render and deleted with it.
#
# Config Connector runs as config-connector-extensions' fake cloud does
# (its manager on the host against a kind cluster holding the CRDs), but
# against Google Cloud: hack/live/realcloud.go.txt, built in a scratch
# copy of config-connector-extensions so it uses the same pinned Config
# Connector. Beside it, config-connector-extensions' own manager
# (hack/cce-manager.sh, its cmd/manager from the same copy, acting as the
# same service account) reconciles the charts' *.gcp.hfl.dev kinds, as
# the fake cloud does. Writes offload-artifacts/live/summary.md.
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
NLB="${RUN}-nlb"
XILB="${RUN}-xilb"
XALB="${RUN}-xalb"
REGION2=us-east1
VPN="${RUN}-vpn"
ADDR_G="${RUN}-ga"
ADDR_E="${RUN}-ea"
NA="${RUN}-na"
ARMOR="${RUN}-armor"
MIG="${RUN}-mig"
MIGS="${RUN}-migs"
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
  # net-lb-ext: the forwarding rule, backend service, health check and group.
  "${G[@]}" compute forwarding-rules delete "${r}-nlb" --region "${REGION}" >/dev/null 2>&1 && echo "swept forwarding rule ${r}-nlb" || true
  "${G[@]}" compute backend-services delete "${r}-nlb" --region "${REGION}" >/dev/null 2>&1 && echo "swept backend service ${r}-nlb" || true
  "${G[@]}" compute health-checks delete "${r}-nlb" --region "${REGION}" >/dev/null 2>&1 && echo "swept health check ${r}-nlb" || true
  "${G[@]}" compute instance-groups unmanaged delete "${r}-nlb-a" --zone "${REGION}-a" >/dev/null 2>&1 && echo "swept instance group ${r}-nlb-a" || true
  # net-vpn-static: the forwarding rules, gateway and address (its network
  # goes below).
  for n in esp udp-500 udp-4500; do
    "${G[@]}" compute forwarding-rules delete "vpn-${r}-vpn-$n" --region "${REGION}" >/dev/null 2>&1 && echo "swept forwarding rule vpn-${r}-vpn-$n" || true
  done
  "${G[@]}" compute target-vpn-gateways delete "${r}-vpn" --region "${REGION}" >/dev/null 2>&1 && echo "swept VPN gateway ${r}-vpn" || true
  "${G[@]}" compute addresses delete "vpn-${r}-vpn" --region "${REGION}" >/dev/null 2>&1 && echo "swept address vpn-${r}-vpn" || true
  # net-lb-proxy-int-cross-region: the global forwarding rules, the TCP
  # proxy, the backend service, the health check, the group and the NEG,
  # then its subnets (the network goes below).
  for g in "${REGION}" "${REGION2}"; do
    "${G[@]}" compute forwarding-rules delete "${r}-xilb-${g}" --global >/dev/null 2>&1 && echo "swept forwarding rule ${r}-xilb-${g}" || true
  done
  "${G[@]}" compute target-tcp-proxies delete "${r}-xilb" --global >/dev/null 2>&1 && echo "swept target proxy ${r}-xilb" || true
  "${G[@]}" compute backend-services delete "${r}-xilb" --global >/dev/null 2>&1 && echo "swept backend service ${r}-xilb" || true
  "${G[@]}" compute health-checks delete "${r}-xilb" --global >/dev/null 2>&1 && echo "swept health check ${r}-xilb" || true
  "${G[@]}" compute instance-groups unmanaged delete "${r}-xilb-a" --zone "${REGION}-a" >/dev/null 2>&1 && echo "swept instance group ${r}-xilb-a" || true
  "${G[@]}" compute network-endpoint-groups delete "${r}-xilb-neg" --zone "${REGION2}-b" >/dev/null 2>&1 && echo "swept network endpoint group ${r}-xilb-neg" || true
  for n in "${r}-xilb-sn1:${REGION}" "${r}-xilb-pr1:${REGION}" "${r}-xilb-sn2:${REGION2}" "${r}-xilb-pr2:${REGION2}"; do
    "${G[@]}" compute networks subnets delete "${n%%:*}" --region "${n#*:}" >/dev/null 2>&1 && echo "swept subnet ${n%%:*}" || true
  done
  # net-lb-app-int-cross-region: the global forwarding rules, the HTTP
  # proxy, the URL map, the backend services, the health checks, the
  # group and the NEG, then its subnets (the network goes below).
  for g in "${REGION}" "${REGION2}"; do
    "${G[@]}" compute forwarding-rules delete "${r}-xalb-${g}" --global >/dev/null 2>&1 && echo "swept forwarding rule ${r}-xalb-${g}" || true
  done
  "${G[@]}" compute target-http-proxies delete "${r}-xalb" --global >/dev/null 2>&1 && echo "swept target proxy ${r}-xalb" || true
  "${G[@]}" compute url-maps delete "${r}-xalb" --global >/dev/null 2>&1 && echo "swept URL map ${r}-xalb" || true
  for b in default groups; do
    "${G[@]}" compute backend-services delete "${r}-xalb-${b}" --global >/dev/null 2>&1 && echo "swept backend service ${r}-xalb-${b}" || true
  done
  for h in default tcp; do
    "${G[@]}" compute health-checks delete "${r}-xalb-${h}" --global >/dev/null 2>&1 && echo "swept health check ${r}-xalb-${h}" || true
  done
  "${G[@]}" compute instance-groups unmanaged delete "${r}-xalb-a" --zone "${REGION}-a" >/dev/null 2>&1 && echo "swept instance group ${r}-xalb-a" || true
  "${G[@]}" compute network-endpoint-groups delete "${r}-xalb-neg" --zone "${REGION2}-b" >/dev/null 2>&1 && echo "swept network endpoint group ${r}-xalb-neg" || true
  for n in "${r}-xalb-sn1:${REGION}" "${r}-xalb-pr1:${REGION}" "${r}-xalb-sn2:${REGION2}" "${r}-xalb-pr2:${REGION2}"; do
    "${G[@]}" compute networks subnets delete "${n%%:*}" --region "${n#*:}" >/dev/null 2>&1 && echo "swept subnet ${n%%:*}" || true
  done
  # net-address: the network attachment, then its subnet (its network
  # goes below).
  "${G[@]}" compute network-attachments describe "${r}-na" --region "${REGION}" >/dev/null 2>&1 \
    && "${G[@]}" compute network-attachments delete "${r}-na" --region "${REGION}" >/dev/null 2>&1 && echo "swept network attachment ${r}-na" || true
  for n in "${r}-ilb-psc" "${r}-ilb-sn" "${r}-na-sn"; do
    "${G[@]}" compute networks subnets delete "$n" --region "${REGION}" >/dev/null 2>&1 && echo "swept subnet $n" || true
  done
  "${G[@]}" compute security-policies delete "${r}-armor" >/dev/null 2>&1 && echo "swept security policy ${r}-armor" || true
  # compute-mig and compute-mig-stateful: the autoscaler (gcloud has no
  # autoscaler commands: the API), the groups (and their VMs), the health
  # check, the templates and the subnets (the networks go below).
  curl -sf -X DELETE -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" \
    "https://compute.googleapis.com/compute/v1/projects/${PROJECT}/zones/${REGION}-a/autoscalers/${r}-mig" >/dev/null 2>&1 \
    && echo "swept autoscaler ${r}-mig" && sleep 20 || true
  for n in "${r}-mig" "${r}-migs"; do
    "${G[@]}" compute instance-groups managed delete "$n" --zone "${REGION}-a" >/dev/null 2>&1 && echo "swept managed instance group $n" || true
    "${G[@]}" compute instance-templates delete "${n}-tpl" >/dev/null 2>&1 && echo "swept instance template ${n}-tpl" || true
    "${G[@]}" compute networks subnets delete "${n}-sn" --region "${REGION}" >/dev/null 2>&1 && echo "swept subnet ${n}-sn" || true
  done
  "${G[@]}" compute health-checks delete "${r}-mig" --global >/dev/null 2>&1 && echo "swept health check ${r}-mig" || true
  for n in "${r}-fwnet" "${r}-pa" "${r}-pb" "${r}-ilb-net" "${r}-vpn-net" "${r}-xilb-net" "${r}-xalb-net" "${r}-na-net" "${r}-mig-net" "${r}-migs-net"; do
    "${G[@]}" compute networks delete "$n" >/dev/null 2>&1 && echo "swept network $n" || true
  done
  "${G[@]}" compute addresses delete "${r}-ga" --global >/dev/null 2>&1 && echo "swept address ${r}-ga" || true
  "${G[@]}" compute addresses delete "${r}-ea" --region "${REGION}" >/dev/null 2>&1 && echo "swept address ${r}-ea" || true
}
# sweep_old: every cat- run older than two hours.
sweep_old() {
  local cutoff r
  cutoff="$(date -u -d '2 hours ago' +%m%d%H%M)"
  { "${G[@]}" iam service-accounts list --format='value(email)' | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-sa@.*/\1/p'
    "${G[@]}" storage buckets list --format='value(name)' | sed -n "s/^${PROJECT}-\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)\$/\1/p"
    "${G[@]}" compute networks list --format='value(name)' | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-\(net\|fwnet\|pa\|pb\|ilb-net\|vpn-net\|xilb-net\|xalb-net\|na-net\|mig-net\|migs-net\)$/\1/p'
    "${G[@]}" artifacts repositories list --location "${REGION}" --format='value(name.basename())' 2>/dev/null | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-ar$/\1/p'
    "${G[@]}" compute addresses list --format='value(name)' 2>/dev/null | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-\(ga\|ea\)$/\1/p'
    "${G[@]}" compute security-policies list --format='value(name)' 2>/dev/null | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-armor$/\1/p'
    "${G[@]}" compute instance-groups managed list --format='value(name)' 2>/dev/null | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-\(mig\|migs\)$/\1/p'
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
  "${G[@]}" compute target-tcp-proxies list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute target-http-proxies list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute url-maps list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute network-endpoint-groups list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute service-attachments list --format='value(name)' 2>/dev/null | grep -E '^cat-' || true
  "${G[@]}" compute network-attachments list --format='value(name)' 2>/dev/null | grep -E '^cat-' || true
  "${G[@]}" compute target-vpn-gateways list --format='value(name)' | grep -E '^cat-' || true
  "${G[@]}" compute addresses list --format='value(name)' | grep -E '^(vpn-)?cat-' || true
  "${G[@]}" compute security-policies list --format='value(name)' 2>/dev/null | grep -E '^cat-' || true
  "${G[@]}" compute instance-templates list --format='value(name)' 2>/dev/null | grep -E '^cat-' || true
  "${G[@]}" compute instances list --format='value(name)' 2>/dev/null | grep -E '^cat-' || true
}
cleanup() {
  [[ -n "${MANAGER_PID:-}" ]] && kill "${MANAGER_PID}" 2>/dev/null || true
  [[ -n "${CCE_MANAGER_PID:-}" ]] && kill "${CCE_MANAGER_PID}" 2>/dev/null || true
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
(cd "${CCE_DIR}" && hack/upstream.sh >/dev/null)
mkdir -p "${CCE_DIR}/cmd/realcloud"
cp hack/live/realcloud.go.txt "${CCE_DIR}/cmd/realcloud/main.go"
(cd "${CCE_DIR}" && GOTOOLCHAIN=auto go build -o "${ROOT}/bin/realcloud" ./cmd/realcloud)
# shellcheck source=hack/cce-manager.sh
source hack/cce-manager.sh
cce_build_manager
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
# config-connector-extensions' manager, for the *.gcp.hfl.dev kinds.
cce_install_crds
if ! cce_start_manager "${OUT}/cce-manager.log"; then
  { echo; echo "config-connector-extensions' manager did not start; nothing was applied."; } >>"${OUT}/summary.md" 2>/dev/null || true
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

cat >"${OUT}/net-lb-ext.values.yaml" <<VALUES
project_id: ${PROJECT}
region: ${REGION}
name: ${NLB}
labels: {catalog-run: ${RUN}}
group_configs:
  a: {zone: ${REGION}-a}
backends:
  - group: a
forwarding_rules_config:
  "": {ports: ["80"]}
health_check_config:
  tcp: {port: 80}
VALUES

cat >"${OUT}/net-vpn-static.values.yaml" <<VALUES
project_id: ${PROJECT}
region: ${REGION}
name: ${VPN}
network: projects/${PROJECT}/global/networks/${VPN}-net
labels: {catalog-run: ${RUN}}
VALUES
cat >"${OUT}/net-vpn-static.needs.yaml" <<NEEDS
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-vpn-net
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${VPN}-net
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
NEEDS

cat >"${OUT}/net-address.values.yaml" <<VALUES
project_id: ${PROJECT}
labels: {catalog-run: ${RUN}}
global_addresses:
  ${ADDR_G}: {description: catalog live test ${RUN}}
external_addresses:
  ${ADDR_E}: {region: ${REGION}, tier: STANDARD, description: catalog live test ${RUN}}
network_attachments:
  ${NA}:
    subnet_self_link: projects/${PROJECT}/regions/${REGION}/subnetworks/${NA}-sn
    description: catalog live test ${RUN}
VALUES
# The network attachment's network and subnet.
cat >"${OUT}/net-address.needs.yaml" <<NEEDS
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-na-net
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${NA}-net
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-na-sn
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${NA}-sn
  region: ${REGION}
  ipCidrRange: 10.251.0.0/28
  networkRef: {name: live-na-net}
  description: catalog live test ${RUN}
NEEDS

cat >"${OUT}/net-cloud-armor.values.yaml" <<VALUES
name: ${ARMOR}
parent_id: {project_id: ${PROJECT}}
description: catalog live test ${RUN}
labels: {catalog-run: ${RUN}}
rules:
  deny-ip: {priority: 1000, action: deny(403), match: {src_ip_ranges: [192.0.2.0/24]}}
  throttle:
    priority: 2000
    action: throttle
    match: {src_ip_ranges: ["*"]}
    rate_limit_options: {exceed_action: deny(429), rate_limit_threshold: {count: 100, interval_sec: 60}, enforce_on_key: IP}
VALUES

# The cross-region proxy: forwarding rules in two regions, each beside a
# GLOBAL_MANAGED_PROXY subnet; a zonal NEG as the backend and an instance
# group beside it (the API refuses a backend service with both instance
# groups and NEGs as backends: seen live, run cat-11130131-7401). No endpoints: ComputeNetworkEndpoint is config-connector-
# extensions', whose controllers this harness does not run (the fake cloud
# covers it).
cat >"${OUT}/net-lb-proxy-int-cross-region.values.yaml" <<VALUES
project_id: ${PROJECT}
name: ${XILB}
port: 80
labels: {catalog-run: ${RUN}}
vpc_config:
  network: projects/${PROJECT}/global/networks/${XILB}-net
  subnetworks:
    ${REGION}: projects/${PROJECT}/regions/${REGION}/subnetworks/${XILB}-sn1
    ${REGION2}: projects/${PROJECT}/regions/${REGION2}/subnetworks/${XILB}-sn2
group_configs:
  a: {zone: ${REGION}-a, named_ports: {tcp: 80}}
neg_configs:
  neg:
    gce:
      zone: ${REGION2}-b
      network: projects/${PROJECT}/global/networks/${XILB}-net
      subnetwork: projects/${PROJECT}/regions/${REGION2}/subnetworks/${XILB}-sn2
backend_service_config:
  backends:
    - {group: neg, max_connections: {per_endpoint: 100}}
VALUES
cat >"${OUT}/net-lb-proxy-int-cross-region.needs.yaml" <<NEEDS
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-xilb-net
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${XILB}-net
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-xilb-sn1
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${XILB}-sn1
  region: ${REGION}
  ipCidrRange: 10.252.0.0/28
  networkRef: {name: live-xilb-net}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-xilb-sn2
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${XILB}-sn2
  region: ${REGION2}
  ipCidrRange: 10.252.1.0/28
  networkRef: {name: live-xilb-net}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-xilb-pr1
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${XILB}-pr1
  region: ${REGION}
  ipCidrRange: 10.252.2.0/26
  purpose: GLOBAL_MANAGED_PROXY
  role: ACTIVE
  networkRef: {name: live-xilb-net}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-xilb-pr2
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${XILB}-pr2
  region: ${REGION2}
  ipCidrRange: 10.252.3.0/26
  purpose: GLOBAL_MANAGED_PROXY
  role: ACTIVE
  networkRef: {name: live-xilb-net}
NEEDS

# The cross-region application load balancer: forwarding rules in two
# regions, each beside a GLOBAL_MANAGED_PROXY subnet; an HTTP proxy (no
# certificates); a URL map sending /groups to a backend service on an
# instance group and the rest to one on a zonal NEG (the API refuses
# groups and NEGs in one service); an HTTP and a TCP health check. No
# endpoints, as for net-lb-proxy-int-cross-region.
cat >"${OUT}/net-lb-app-int-cross-region.values.yaml" <<VALUES
project_id: ${PROJECT}
name: ${XALB}
labels: {catalog-run: ${RUN}}
vpc_config:
  network: projects/${PROJECT}/global/networks/${XALB}-net
  subnetworks:
    ${REGION}: projects/${PROJECT}/regions/${REGION}/subnetworks/${XALB}-sn1
    ${REGION2}: projects/${PROJECT}/regions/${REGION2}/subnetworks/${XALB}-sn2
group_configs:
  a: {zone: ${REGION}-a, named_ports: {http: 80}}
neg_configs:
  neg:
    gce:
      zone: ${REGION2}-b
      subnetwork: projects/${PROJECT}/regions/${REGION2}/subnetworks/${XALB}-sn2
health_check_configs:
  default:
    http: {port_specification: USE_SERVING_PORT, request_path: /healthz}
  tcp:
    tcp: {port: 80}
backend_service_configs:
  default:
    backends:
      - {group: neg, balancing_mode: RATE, max_rate: {per_endpoint: 100}}
  groups:
    port_name: http
    health_checks: [tcp]
    backends:
      - {group: a}
urlmap_config:
  default_service: default
  host_rules:
    - hosts: ["*"]
      path_matcher: main
  path_matchers:
    main:
      default_service: default
      path_rules:
        - paths: [/groups, /groups/*]
          service: groups
VALUES
sed -e 's/live-xilb-/live-xalb-/g' -e "s/${XILB}-/${XALB}-/g" -e 's#10\.252\.#10.253.#g' \
  "${OUT}/net-lb-proxy-int-cross-region.needs.yaml" >"${OUT}/net-lb-app-int-cross-region.needs.yaml"

# compute-mig: a zonal group of one e2-micro VM (no external address, no
# service account), held at one by config-connector-extensions'
# ComputeAutoscaler (min = max = 1) with no target_size (so min_replicas),
# the auto-created
# TCP health check for auto-healing (a long initial delay: no firewall
# rule admits the probes, so the VM would be recreated after it).
# compute-mig-stateful: the same chart, a zonal group of target_size 1,
# applied first without stateful_config; once the group has made its VM,
# mig_stateful_config adds a stateful_config entry naming that VM, and the
# case goes on with config-connector-extensions' ComputePerInstanceConfig
# for it (updatePerInstanceConfigs: a config names a VM the group has and
# never adds one, so the group stays at 1). mig_check, below, reads what
# the group holds.
cat >"${OUT}/compute-mig.values.yaml" <<VALUES
project_id: ${PROJECT}
location: ${REGION}-a
name: ${MIG}
description: catalog live test ${RUN}
instance_template: projects/${PROJECT}/global/instanceTemplates/${MIG}-tpl
named_ports: {ssh: 22}
auto_healing_policies: {initial_delay_sec: 3600}
health_check_config:
  tcp: {port: 22}
autoscaler_config:
  min_replicas: 1
  max_replicas: 1
  scaling_signals:
    cpu_utilization: {target: 0.9}
VALUES
cat >"${OUT}/compute-mig-stateful.values.yaml" <<VALUES
project_id: ${PROJECT}
location: ${REGION}-a
name: ${MIGS}
description: catalog live test ${RUN}
instance_template: projects/${PROJECT}/global/instanceTemplates/${MIGS}-tpl
target_size: 1
update_policy: {minimal_action: NONE, type: OPPORTUNISTIC}
VALUES
# The network, subnet and template each case's group needs (live-mig- or
# live-migs-).
for c in mig migs; do
  n="${RUN}-${c}"
  cat >"${OUT}/compute-${c/migs/mig-stateful}.needs.yaml" <<NEEDS
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeNetwork
metadata:
  name: live-${c}-net
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${n}-net
  autoCreateSubnetworks: false
  description: catalog live test ${RUN}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeSubnetwork
metadata:
  name: live-${c}-sn
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
spec:
  resourceID: ${n}-sn
  region: ${REGION}
  ipCidrRange: $([[ ${c} == mig ]] && echo 10.254.0.0/28 || echo 10.254.1.0/28)
  networkRef: {name: live-${c}-net}
  description: catalog live test ${RUN}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeInstanceTemplate
metadata:
  name: live-${c}-tpl
  annotations: {cnrm.cloud.google.com/project-id: ${PROJECT}}
  labels: {catalog-run: ${RUN}}
spec:
  resourceID: ${n}-tpl
  description: catalog live test ${RUN}
  machineType: e2-micro
  disk:
    - sourceImageRef: {external: projects/debian-cloud/global/images/family/debian-12}
      boot: true
      autoDelete: true
      diskSizeGb: 10
      diskType: pd-standard
  networkInterface:
    - networkRef: {name: live-${c}-net}
      subnetworkRef: {name: live-${c}-sn}
  shieldedInstanceConfig: {enableSecureBoot: true, enableVtpm: true, enableIntegrityMonitoring: true}
NEEDS
done

# mig_check CHART GROUP [INSTANCE]: the group's size and VMs, once Config
# Connector has made it and again after it has reconciled the group a
# second time (a changed annotation), must be 1 and 1 (charts/gcp/compute-mig,
# README.md, "The target size"), and the named INSTANCE, when given, must be
# the one left and have the group's per-instance config (with the run's
# metadata). Appends a row to the summary; fails otherwise.
mig_check() {
  local chart="$1" group="$2" want="${3:-}" zone="${REGION}-a" s1 n1 s2 n2 vms cfg="" ok=yes
  "${G[@]}" compute instance-groups managed wait-until "${group}" --zone "${zone}" --stable --timeout 600 >/dev/null 2>&1 || true
  s1="$("${G[@]}" compute instance-groups managed describe "${group}" --zone "${zone}" --format='value(targetSize)' 2>/dev/null || true)"
  n1="$("${G[@]}" compute instance-groups managed list-instances "${group}" --zone "${zone}" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  kubectl annotate -n "${NS}" computeinstancegroupmanager.v1beta1.compute.cnrm.cloud.google.com/live \
    "catalog-live/reconcile=$(date +%s)" --overwrite >/dev/null
  sleep 120
  "${G[@]}" compute instance-groups managed wait-until "${group}" --zone "${zone}" --stable --timeout 300 >/dev/null 2>&1 || true
  s2="$("${G[@]}" compute instance-groups managed describe "${group}" --zone "${zone}" --format='value(targetSize)' 2>/dev/null || true)"
  vms="$("${G[@]}" compute instance-groups managed list-instances "${group}" --zone "${zone}" --format='value(name)' 2>/dev/null | tr '\n' ' ')"
  n2="$(wc -w <<<"${vms}" | tr -d ' ')"
  [[ "${s1}" == 1 && "${n1}" == 1 && "${s2}" == 1 && "${n2}" == 1 ]] || ok=no
  [[ -z "${want}" || " ${vms}" == *" ${want} "* ]] || ok=no
  if [[ -n "${want}" ]]; then
    cfg="$("${G[@]}" compute instance-groups managed instance-configs list "${group}" --zone "${zone}" \
      --format='value(name,preservedState.metadata.catalog-run)' 2>/dev/null | tr '\t\n' ': ' || true)"
    [[ " ${cfg}" == *" ${want}:${RUN} "* ]] || ok=no
  fi
  echo "   ${group}: targetSize ${s1} with ${n1} VMs; after a second reconcile ${s2} with ${n2} VMs (${vms% })${want:+; per-instance configs: ${cfg% }} (want 1 and 1${want:+, ${want}:${RUN}}): ${ok}"
  echo "| ${chart} | group size | ${ok} | | | targetSize ${s1}, ${n1} VMs; after a second reconcile ${s2}, ${n2} VMs: ${vms% }${want:+; per-instance configs: ${cfg% }} (want 1${want:+, ${want} with its config}) |" >>"${summary}"
  [[ "${ok}" == yes ]]
}

# mig_stateful_config: compute-mig-stateful's group (and what it needs)
# applied without stateful_config, Ready, and stable; then its one VM's name
# in MIGS_VM and a stateful_config entry for that VM appended to the case's
# values. Fails when the group is not Ready or has no VM.
mig_stateful_config() {
  helm template live charts/gcp/compute-mig --namespace "${NS}" -f "${OUT}/compute-mig-stateful.values.yaml" \
    | cat "${OUT}/compute-mig-stateful.needs.yaml" <(echo "---") - >"${OUT}/compute-mig-stateful.base.yaml"
  kubectl apply --server-side -n "${NS}" -f "${OUT}/compute-mig-stateful.base.yaml"
  kubectl wait -n "${NS}" --for=condition=Ready computeinstancegroupmanager.v1beta1.compute.cnrm.cloud.google.com/live \
    --timeout="${TIMEOUT}s" >/dev/null || { echo "   ${MIGS}: the group is not Ready"; return 1; }
  "${G[@]}" compute instance-groups managed wait-until "${MIGS}" --zone "${REGION}-a" --stable --timeout 600 >/dev/null 2>&1 || true
  MIGS_VM="$("${G[@]}" compute instance-groups managed list-instances "${MIGS}" --zone "${REGION}-a" --format='value(name)' 2>/dev/null | head -1)"
  [[ -n "${MIGS_VM}" ]] || { echo "   ${MIGS}: the group has no VM"; return 1; }
  echo "   ${MIGS}: its VM is ${MIGS_VM}; adding a per-instance config for it"
  cat >>"${OUT}/compute-mig-stateful.values.yaml" <<VALUES
stateful_config:
  ${MIGS_VM}:
    minimal_action: NONE
    most_disruptive_action: REPLACE
    preserved_state:
      metadata: {catalog-run: ${RUN}}
VALUES
}

summary="${OUT}/summary.md"
{
  echo "# Live apply ${RUN}, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Project ${PROJECT}, as ${RUNNER}; catalog $(git rev-parse --short HEAD 2>/dev/null || echo unknown); Config Connector at config-connector-extensions' pin, and config-connector-extensions' manager, from ${CCE_TARBALL}."
  echo
  echo "| Chart | Object | Ready | Deleted | Gone from Google Cloud | Message |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >"${summary}"
failed=0
for chart in ${LIVE_CHARTS}; do
  echo "== ${chart}"
  dir="charts/gcp/${chart}"
  # A second case of one chart.
  [[ "${chart}" == compute-mig-stateful ]] && dir=charts/gcp/compute-mig
  # The per-instance config names a VM the group already has.
  if [[ "${chart}" == compute-mig-stateful ]] && ! mig_stateful_config; then
    failed=$((failed + 1))
    echo "| ${chart} | per-instance config | no | | | the group had no VM to name |" >>"${summary}"
  fi
  helm template live "${dir}" --namespace "${NS}" -f "${OUT}/${chart}.values.yaml" >"${OUT}/${chart}.rendered.yaml"
  # What the case needs and the chart does not make, applied and deleted with it.
  if [[ -f "${OUT}/${chart}.needs.yaml" ]]; then
    { cat "${OUT}/${chart}.needs.yaml"; echo "---"; cat "${OUT}/${chart}.rendered.yaml"; } >"${OUT}/${chart}.with-needs.yaml"
    mv "${OUT}/${chart}.with-needs.yaml" "${OUT}/${chart}.rendered.yaml"
  fi
  kubectl apply --server-side -n "${NS}" -f "${OUT}/${chart}.rendered.yaml"
  # Fully qualified (kind.version.group/name): "Service" alone is the core kind.
  # One object comes back as itself, not a List (net-cloud-armor's policy):
  # make it one, as hack/mock-apply.sh does.
  mapfile -t objects < <(kubectl get -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" -o json \
    | jq -r '(if .items then .items else [.] end)[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"')
  declare -A ready=() msgs=()
  deadline=$(( $(date +%s) + TIMEOUT ))
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${NS}" --for=condition=Ready "$o" --timeout="${left}s" >/dev/null 2>&1; then ready[$o]=yes; else ready[$o]=no; fi
    msgs[$o]="$(kubectl get -n "${NS}" "$o" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | tr '\n|' '  ' | cut -c1-200 || true)"
  done
  kubectl get -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${chart}.live.json"
  bin/catalogtool outputs "${dir}/package.yaml" "${OUT}/${chart}.live.json" "${dir}/values.yaml" "${OUT}/${chart}.values.yaml" >"${OUT}/${chart}.outputs.json" 2>&1 || failed=$((failed + 1))
  cat "${OUT}/${chart}.outputs.json"
  case "${chart}" in
    compute-mig) mig_check "${chart}" "${MIG}" || failed=$((failed + 1)) ;;
    compute-mig-stateful) mig_check "${chart}" "${MIGS}" "${MIGS_VM:-}" || failed=$((failed + 1)) ;;
  esac
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
    net-lb-ext)
      gone=yes
      "${G[@]}" compute forwarding-rules describe "${NLB}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute backend-services describe "${NLB}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute health-checks describe "${NLB}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute instance-groups unmanaged describe "${NLB}-a" --zone "${REGION}-a" >/dev/null 2>&1 && gone=no ;;
    net-vpn-static)
      gone=yes
      for n in esp udp-500 udp-4500; do
        "${G[@]}" compute forwarding-rules describe "vpn-${VPN}-$n" --region "${REGION}" >/dev/null 2>&1 && gone=no
      done
      "${G[@]}" compute target-vpn-gateways describe "${VPN}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute addresses describe "vpn-${VPN}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks describe "${VPN}-net" >/dev/null 2>&1 && gone=no ;;
    net-address)
      gone=yes
      "${G[@]}" compute addresses describe "${ADDR_G}" --global >/dev/null 2>&1 && gone=no
      "${G[@]}" compute addresses describe "${ADDR_E}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute network-attachments describe "${NA}" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks subnets describe "${NA}-sn" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks describe "${NA}-net" >/dev/null 2>&1 && gone=no ;;
    net-cloud-armor) "${G[@]}" compute security-policies describe "${ARMOR}" >/dev/null 2>&1 && gone=no || gone=yes ;;
    net-lb-proxy-int-cross-region)
      gone=yes
      for g in "${REGION}" "${REGION2}"; do
        "${G[@]}" compute forwarding-rules describe "${XILB}-${g}" --global >/dev/null 2>&1 && gone=no
      done
      "${G[@]}" compute target-tcp-proxies describe "${XILB}" --global >/dev/null 2>&1 && gone=no
      "${G[@]}" compute backend-services describe "${XILB}" --global >/dev/null 2>&1 && gone=no
      "${G[@]}" compute health-checks describe "${XILB}" --global >/dev/null 2>&1 && gone=no
      "${G[@]}" compute instance-groups unmanaged describe "${XILB}-a" --zone "${REGION}-a" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute network-endpoint-groups describe "${XILB}-neg" --zone "${REGION2}-b" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks describe "${XILB}-net" >/dev/null 2>&1 && gone=no ;;
    net-lb-app-int-cross-region)
      gone=yes
      for g in "${REGION}" "${REGION2}"; do
        "${G[@]}" compute forwarding-rules describe "${XALB}-${g}" --global >/dev/null 2>&1 && gone=no
      done
      "${G[@]}" compute target-http-proxies describe "${XALB}" --global >/dev/null 2>&1 && gone=no
      "${G[@]}" compute url-maps describe "${XALB}" --global >/dev/null 2>&1 && gone=no
      for b in default groups; do
        "${G[@]}" compute backend-services describe "${XALB}-${b}" --global >/dev/null 2>&1 && gone=no
      done
      for h in default tcp; do
        "${G[@]}" compute health-checks describe "${XALB}-${h}" --global >/dev/null 2>&1 && gone=no
      done
      "${G[@]}" compute instance-groups unmanaged describe "${XALB}-a" --zone "${REGION}-a" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute network-endpoint-groups describe "${XALB}-neg" --zone "${REGION2}-b" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks describe "${XALB}-net" >/dev/null 2>&1 && gone=no ;;
    compute-mig|compute-mig-stateful)
      gone=yes
      [[ "${chart}" == compute-mig ]] && n="${MIG}" || n="${MIGS}"
      "${G[@]}" compute instance-groups managed describe "${n}" --zone "${REGION}-a" >/dev/null 2>&1 && gone=no
      curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" \
        "https://compute.googleapis.com/compute/v1/projects/${PROJECT}/zones/${REGION}-a/autoscalers/${n}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute health-checks describe "${n}" --global >/dev/null 2>&1 && gone=no
      [[ -z "$("${G[@]}" compute instances list --filter="name~^${n}-" --format='value(name)' 2>/dev/null)" ]] || gone=no
      "${G[@]}" compute instance-templates describe "${n}-tpl" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks subnets describe "${n}-sn" --region "${REGION}" >/dev/null 2>&1 && gone=no
      "${G[@]}" compute networks describe "${n}-net" >/dev/null 2>&1 && gone=no ;;
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
