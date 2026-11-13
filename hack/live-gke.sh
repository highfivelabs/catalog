#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply gke-cluster to real Google Cloud once per mode, wait for Ready,
# delete, and check Google Cloud no longer has the clusters
# (docs/design.md, "Testing", layer 3). Only on an offload VM acting as a
# service account, never with a key. `task test-live-gke` runs it:
#
#   offload run --sa "$GCP_CCE_LIVE_SA" \
#     --machine e2-standard-8 --hours 2 -- env PROJECT="$GCP_PROJECT" \
#     CCE_TARBALL=gs://.../cce-<commit>.tar.gz hack/live-gke.sh
#
# What it makes, all named cat-<UTC month day hour minute>-<4 hex>-...:
# a network and a /24 subnet with pod and service ranges (the net-vpc
# chart), a zonal Standard cluster with its default pool removed and two
# node pools of one Spot e2-small node each (one autoscaled min 1 max 1,
# one fixed), and a regional Autopilot cluster with no workloads. The
# Standard cluster has the module's cluster and shadow firewall rules
# (seven ComputeFirewalls), the Autopilot cluster its webhook rule. On the
# Standard cluster the gke-nodepool chart then adds a third pool of one
# Spot e2-small node, which is deleted and checked gone before the rest. Both
# clusters have private nodes and a public endpoint. Then the mode change:
# the Standard cluster rendered as Autopilot must be refused by the chart
# when helm can see the cluster (--dry-run=server), and by Config Connector
# when the offline render is applied, leaving the cluster unchanged. The nodes run as NODE_SA (default: the project's Compute Engine
# default account), so the run needs no project IAM change: the chart's
# create_service_account path (an account and three project grants) is
# render-tested only. Expect about 30 minutes and well under a dollar.
#
# The runner needs, on the project: roles/container.clusterAdmin,
# roles/compute.networkAdmin, roles/compute.securityAdmin (the firewall
# rules), roles/iam.serviceAccountUser (to run nodes as NODE_SA), and the
# Kubernetes Engine API enabled. A sweeper deletes this
# run's clusters and network after the run, and any cat- cluster or network
# older than two hours; at the end the script lists what is left
# (gcloud container clusters list --project).
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
: "${GCP_PROJECT:?set GCP_PROJECT, the live-test project (see .env.example)}"
ALLOWED_PROJECTS=("${GCP_PROJECT}")
# And the test estate generation's project (factory/estate/gcp), when its
# env file is loaded.
[[ -z "${HFL_GCP_TEST_PROJECT:-}" ]] || ALLOWED_PROJECTS+=("${HFL_GCP_TEST_PROJECT}")
PROJECT="${PROJECT:-}"
allowed=no
for p in "${ALLOWED_PROJECTS[@]}"; do [[ "${PROJECT}" == "${p}" ]] && allowed=yes; done
[[ "${allowed}" == yes ]] || { echo "live-gke: refusing project '${PROJECT}': only ${ALLOWED_PROJECTS[*]} (GCP_PROJECT, HFL_GCP_TEST_PROJECT)" >&2; exit 2; }
REGION=us-central1
ZONE=us-central1-a
TIMEOUT="${LIVE_TIMEOUT:-1800}"
OUT="${ROOT}/offload-artifacts/live-gke"
mkdir -p "${OUT}"
md() { curl -sf -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/$1"; }
RUNNER="$(md instance/service-accounts/default/email || true)"
[[ "${RUNNER}" == *.iam.gserviceaccount.com ]] || { echo "live-gke: not on a VM acting as a service account (got '${RUNNER}')" >&2; exit 2; }
for t in docker kind kubectl helm go git gcloud jq; do
  command -v "$t" >/dev/null || { echo "live-gke: $t is not installed" >&2; exit 2; }
done
G=(gcloud --quiet --project "${PROJECT}")
NODE_SA="${NODE_SA:-$("${G[@]}" iam service-accounts list --filter='email~-compute@developer.gserviceaccount.com$' --format='value(email)' | head -1)}"
[[ -n "${NODE_SA}" ]] || { echo "live-gke: no NODE_SA and no Compute Engine default account" >&2; exit 2; }

RUN="cat-$(date -u +%m%d%H%M)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
NET="${RUN}-net"; SUBNET="${RUN}-sn"
echo "== live GKE run ${RUN} in ${PROJECT} as ${RUNNER}, nodes as ${NODE_SA}"

# sweep_run PREFIX: delete the clusters and the network a run made.
sweep_run() {
  local r="$1" n l
  "${G[@]}" container clusters list --filter="name~^${r}-" --format='value(name,location)' 2>/dev/null | while read -r n l; do
    "${G[@]}" container clusters delete "$n" --location "$l" >/dev/null 2>&1 && echo "swept cluster $n"
  done || true
  "${G[@]}" compute firewall-rules list --filter="network~/${r}-net\$" --format='value(name)' 2>/dev/null | while read -r n; do
    "${G[@]}" compute firewall-rules delete "$n" >/dev/null 2>&1 && echo "swept firewall rule $n"
  done || true
  "${G[@]}" compute networks subnets delete "${r}-sn" --region "${REGION}" >/dev/null 2>&1 && echo "swept subnet ${r}-sn" || true
  "${G[@]}" compute networks delete "${r}-net" >/dev/null 2>&1 && echo "swept network ${r}-net" || true
}
# sweep_old: every cat- run older than two hours.
sweep_old() {
  local cutoff r
  cutoff="$(date -u -d '2 hours ago' +%m%d%H%M)"
  { "${G[@]}" container clusters list --format='value(name)' 2>/dev/null | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-.*/\1/p'
    "${G[@]}" compute networks list --format='value(name)' | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-net$/\1/p'
  } | sort -u | while read -r r; do
    [[ "$(echo "$r" | cut -c5-12)" < "${cutoff}" ]] && { echo "sweeping old run $r"; sweep_run "$r"; }
  done || true
}
list_left() {
  "${G[@]}" container clusters list --format='value(name,location,status)' | grep -E '^cat-' || true
  "${G[@]}" compute networks list --format='value(name)' | grep -E '^cat-' || true
}
cleanup() {
  [[ -n "${MANAGER_PID:-}" ]] && kill "${MANAGER_PID}" 2>/dev/null || true
  [[ -n "${CCE_MANAGER_PID:-}" ]] && kill "${CCE_MANAGER_PID}" 2>/dev/null || true
  kind delete cluster --name catalog-live-gke >/dev/null 2>&1 || true
  echo "== sweep after"; sweep_run "${RUN}"; sweep_old
  echo "== gcloud container clusters list --project ${PROJECT}"
  "${G[@]}" container clusters list 2>&1 || true
  echo "== cat- things left in ${PROJECT} (nothing should follow)"; left="$(list_left)"; echo "${left}"
  { echo; echo "Left in ${PROJECT} after the run: ${left:-nothing}."; } >>"${OUT}/summary.md" 2>/dev/null || true
}
trap cleanup EXIT
echo "== sweep before"; sweep_old; list_left

# config-connector-extensions, its pinned Config Connector, and the
# manager acting on Google Cloud, and config-connector-extensions' own
# manager beside it (hack/cce-manager.sh), as hack/live-apply.sh runs them.
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
kind create cluster --name catalog-live-gke --kubeconfig "${KUBECONFIG}" --wait 120s
KCC="${CCE_DIR}/third_party/k8s-config-connector"
{ for f in "${KCC}"/operator/config/crd/bases/core.cnrm.cloud.google.com_*.yaml; do printf -- '---\n'; cat "$f"; done
  for g in iam compute container; do
    for f in "${KCC}"/config/crds/resources/*."${g}".cnrm.cloud.google.com.yaml; do printf -- '---\n'; cat "$f"; done
  done; } | kubectl apply --server-side --force-conflicts -f - >/dev/null
kubectl wait --for=condition=Established crd --all --timeout=180s >/dev/null
"${ROOT}/bin/realcloud" >"${OUT}/manager.log" 2>&1 &
MANAGER_PID=$!
started=no
for _ in $(seq 1 90); do
  grep -q "Starting workers" "${OUT}/manager.log" && { started=yes; break; }
  kill -0 "${MANAGER_PID}" 2>/dev/null || break
  sleep 2
done
[[ "${started}" == yes ]] || { echo "live-gke: the manager did not start:" >&2; grep -v round_trippers "${OUT}/manager.log" | tail -15 >&2; exit 1; }
cce_install_crds
cce_start_manager "${OUT}/cce-manager.log"
NS=catalog-live-gke
kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl annotate --local -f - "cnrm.cloud.google.com/project-id=${PROJECT}" -o yaml | kubectl apply -f - >/dev/null

cat >"${OUT}/net.values.yaml" <<VALUES
project_id: ${PROJECT}
name: ${NET}
description: catalog live GKE test ${RUN}
subnets:
  - name: ${SUBNET}
    region: ${REGION}
    ip_cidr_range: 10.250.0.0/24
    description: catalog live GKE test ${RUN}
    secondary_ip_ranges:
      pods: {ip_cidr_range: 10.252.0.0/16}
      services: {ip_cidr_range: 10.251.0.0/20}
VALUES
common="project_id: ${PROJECT}
network: ${NET}
subnetwork: ${SUBNET}
ip_range_pods: pods
ip_range_services: services
create_service_account: false
service_account: ${NODE_SA}
deletion_protection: false
cluster_resource_labels: {catalog-run: ${RUN}}"
cat >"${OUT}/standard.values.yaml" <<VALUES
${common}
name: ${RUN}-std
regional: false
zones: [${ZONE}]
remove_default_node_pool: true
node_pools:
  - {name: spot, machine_type: e2-small, disk_size_gb: 20, min_count: 1, max_count: 1, spot: true}
  - {name: spot-fixed, machine_type: e2-small, disk_size_gb: 20, autoscaling: false, node_count: 1, spot: true}
add_cluster_firewall_rules: true
add_shadow_firewall_rules: true
firewall_ranges: {subnetwork: 10.250.0.0/24, pods: {pods: 10.252.0.0/16}}
VALUES
# The same Standard cluster (same release, name and location) rendered as
# Autopilot: the mode change the chart and Config Connector must refuse.
cat >"${OUT}/modechange.values.yaml" <<VALUES
${common}
name: ${RUN}-std
regional: false
zones: [${ZONE}]
mode: autopilot
VALUES
cat >"${OUT}/autopilot.values.yaml" <<VALUES
${common}
mode: autopilot
name: ${RUN}-ap
region: ${REGION}
add_master_webhook_firewall_rules: true
firewall_ranges: {subnetwork: 10.250.0.0/24}
VALUES

summary="${OUT}/summary.md"
{
  echo "# Live GKE apply ${RUN}, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Project ${PROJECT}, as ${RUNNER}; catalog $(git rev-parse --short HEAD 2>/dev/null || echo unknown); Config Connector at config-connector-extensions' pin."
  echo
  echo "| Component | Object | Ready | Seconds to Ready | Deleted | Message |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >"${summary}"
failed=0

# objects FILE: the rendered objects, as kubectl names them. A file of one
# object (Autopilot with an external node account) comes back as that
# object, not a List.
objects() {
  kubectl get -n "${NS}" -f "$1" -o json \
    | jq -r '(if .items then .items[] else . end) | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"'
}
# delete_all FILE...: delete the objects of every file at once, doing the
# deletion defender's part, and wait until they are gone.
delete_all() {
  local file deadline left o f objs=()
  for file in "$@"; do mapfile -t -O "${#objs[@]}" objs < <(objects "${file}"); done
  for file in "$@"; do kubectl delete -n "${NS}" -f "${file}" --wait=false >/dev/null; done
  deadline=$(( $(date +%s) + TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    left=0
    for o in "${objs[@]}"; do
      f="$(kubectl get -n "${NS}" "$o" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)" || continue
      left=$((left + 1))
      if [[ "${f}" == *deletion-defender* ]]; then
        kubectl get -n "${NS}" "$o" -o json \
          | jq '.metadata.finalizers |= map(select(. != "cnrm.cloud.google.com/deletion-defender"))' \
          | kubectl replace -f - >/dev/null 2>&1 || true
      fi
    done
    (( left == 0 )) && return 0
    # A line a minute: offload deletes a VM whose log is silent for 45
    # minutes, and then the cleanup trap never runs (2026-11-11).
    (( ($(date +%s) - deadline + TIMEOUT) % 60 < 10 )) && echo "   deleting: ${left} left, $(( deadline - $(date +%s) ))s to go: $(for o in "${objs[@]}"; do kubectl get -n "${NS}" "$o" -o jsonpath='{.kind}/{.metadata.name}={.status.conditions[?(@.type=="Ready")].reason} ' 2>/dev/null; done)"
    sleep 10
  done
  return 1
}

declare -A ready=() secs=() msgs=()
# wait_ready COMPONENT FILE START: wait for every object, record the result.
wait_ready() {
  local c="$1" file="$2" start="$3" deadline left o
  deadline=$(( start + TIMEOUT ))
  while read -r o; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${NS}" --for=condition=Ready "$o" --timeout="${left}s" >/dev/null 2>&1; then
      ready["$c $o"]=yes; secs["$c $o"]=$(( $(date +%s) - start ))
    else
      ready["$c $o"]=no; secs["$c $o"]=-
    fi
    msgs["$c $o"]="$(kubectl get -n "${NS}" "$o" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | tr '\n|' '  ' | cut -c1-200 || true)"
    echo "   ${c} ${o} ready=${ready["$c $o"]} after ${secs["$c $o"]}s ${msgs["$c $o"]}"
  done < <(objects "${file}")
}

echo "== network"
helm template net charts/gcp/net-vpc --namespace "${NS}" -f "${OUT}/net.values.yaml" >"${OUT}/net.rendered.yaml"
t0=$(date +%s)
kubectl apply --server-side -n "${NS}" -f "${OUT}/net.rendered.yaml"
wait_ready net "${OUT}/net.rendered.yaml" "${t0}"

echo "== clusters: Standard and Autopilot, side by side"
helm template std charts/gcp/gke-cluster --namespace "${NS}" -f "${OUT}/standard.values.yaml" >"${OUT}/standard.rendered.yaml"
helm template ap charts/gcp/gke-cluster --namespace "${NS}" -f "${OUT}/autopilot.values.yaml" >"${OUT}/autopilot.rendered.yaml"
t0=$(date +%s)
kubectl apply --server-side -n "${NS}" -f "${OUT}/standard.rendered.yaml"
kubectl apply --server-side -n "${NS}" -f "${OUT}/autopilot.rendered.yaml"
wait_ready standard "${OUT}/standard.rendered.yaml" "${t0}"
wait_ready autopilot "${OUT}/autopilot.rendered.yaml" "${t0}"
declare -A short=([standard]=std [autopilot]=ap)
for m in standard autopilot; do
  kubectl get -n "${NS}" -f "${OUT}/${m}.rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${m}.live.json"
  echo "-- ${m} outputs"
  bin/catalogtool outputs charts/gcp/gke-cluster/package.yaml "${OUT}/${m}.live.json" charts/gcp/gke-cluster/values.yaml "${OUT}/${m}.values.yaml" \
    | tee "${OUT}/${m}.outputs.json" || failed=$((failed + 1))
  "${G[@]}" container clusters list --filter="name=${RUN}-${short[$m]}" --format='value(name,location,status,currentMasterVersion,autopilot.enabled)' | tee -a "${OUT}/${m}.gcloud.txt" || true
done

echo "== gke-nodepool: one more Spot node pool on the Standard cluster, then deleted"
cat >"${OUT}/nodepool.values.yaml" <<VALUES
project_id: ${PROJECT}
cluster_name: ${RUN}-std
location: ${ZONE}
name: extra
labels: {catalog-run: ${RUN}}
k8s_labels: {catalog-run: ${RUN}}
service_account: {email: ${NODE_SA}}
node_count: {initial: 1}
node_config: {machine_type: e2-small, disk_size_gb: 20, spot: true}
nodepool_config:
  management: {auto_repair: true, auto_upgrade: true}
  upgrade_settings: {max_surge: 1, max_unavailable: 0}
taints:
  catalog: {value: live, effect: NO_SCHEDULE}
VALUES
helm template np charts/gcp/gke-nodepool --namespace "${NS}" -f "${OUT}/nodepool.values.yaml" >"${OUT}/nodepool.rendered.yaml"
t0=$(date +%s)
kubectl apply --server-side -n "${NS}" -f "${OUT}/nodepool.rendered.yaml"
wait_ready nodepool "${OUT}/nodepool.rendered.yaml" "${t0}"
kubectl get -n "${NS}" -f "${OUT}/nodepool.rendered.yaml" -o json \
  | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/nodepool.live.json"
echo "-- nodepool outputs"
bin/catalogtool outputs charts/gcp/gke-nodepool/package.yaml "${OUT}/nodepool.live.json" charts/gcp/gke-nodepool/values.yaml "${OUT}/nodepool.values.yaml" \
  | tee "${OUT}/nodepool.outputs.json" || failed=$((failed + 1))
"${G[@]}" container node-pools list --cluster "${RUN}-std" --location "${ZONE}" --format='value(name,status,config.machineType,config.spot)' | tee "${OUT}/nodepool.gcloud.txt" || true
delete_all "${OUT}/nodepool.rendered.yaml" || echo "live-gke: the node pool was not deleted in ${TIMEOUT}s"
# Config Connector lets the object go once GKE has accepted the delete;
# the pool can stay listed (STOPPING) for a few minutes after.
np_gone=no; deadline=$(( $(date +%s) + 900 ))
while (( $(date +%s) < deadline )); do
  if ! "${G[@]}" container node-pools describe extra --cluster "${RUN}-std" --location "${ZONE}" >/dev/null 2>&1; then np_gone=yes; break; fi
  echo "   node pool extra: $("${G[@]}" container node-pools describe extra --cluster "${RUN}-std" --location "${ZONE}" --format='value(status)' 2>/dev/null || true)"
  sleep 20
done
[[ "${np_gone}" == yes ]] || { failed=$((failed + 1)); echo "live-gke: node pool extra is still in Google Cloud after 15 minutes"; }
echo "   node pool extra gone from Google Cloud: ${np_gone}"

echo "== the refused mode change: Standard ${RUN}-std rendered as Autopilot"
mc="${OUT}/modechange.md"
{ echo; echo "## The mode change (Standard ${RUN}-std rendered with mode: autopilot)"; echo; } >"${mc}"
std_before="$("${G[@]}" container clusters describe "${RUN}-std" --location "${ZONE}" --format='value(createTime,autopilot.enabled)' 2>&1 || true)"
# 1. A render that can see the cluster stops (templates/refused.yaml).
if helm install std charts/gcp/gke-cluster --namespace "${NS}" -f "${OUT}/modechange.values.yaml" --dry-run=server >"${OUT}/modechange.helm.txt" 2>&1; then
  failed=$((failed + 1)); echo "1. helm install --dry-run=server: rendered (expected a refusal). FAIL" >>"${mc}"
elif grep -q "cannot change a cluster's mode" "${OUT}/modechange.helm.txt"; then
  echo "1. helm install --dry-run=server (lookup sees the cluster): refused: \`$(grep -o "gke-cluster: mode is[^.]*" "${OUT}/modechange.helm.txt" | head -1)\`. PASS" >>"${mc}"
else
  failed=$((failed + 1)); echo "1. helm install --dry-run=server failed for another reason: \`$(tail -1 "${OUT}/modechange.helm.txt" | cut -c1-300)\`. FAIL" >>"${mc}"
fi
# 2. An offline render applies; Config Connector must refuse the immutable
# field and leave the cluster as it is.
helm template std charts/gcp/gke-cluster --namespace "${NS}" -f "${OUT}/modechange.values.yaml" >"${OUT}/modechange.rendered.yaml"
dry="$(kubectl apply --server-side --force-conflicts --dry-run=server -n "${NS}" -f "${OUT}/modechange.rendered.yaml" 2>&1 || true)"
echo "2. kubectl apply --server-side --dry-run=server of the offline render: \`$(echo "${dry}" | tr '\n' ' ' | cut -c1-300)\` (this run has no Config Connector webhooks, so a dry run shows only the API server's schema checks)." >>"${mc}"
kubectl apply --server-side --force-conflicts -n "${NS}" -f "${OUT}/modechange.rendered.yaml"
refused=no; deadline=$(( $(date +%s) + 600 ))
while (( $(date +%s) < deadline )); do
  cond="$(kubectl get -n "${NS}" containercluster/std -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}|{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || true)"
  case "${cond%%|*}" in UpdateFailed|*Immutable*|*Error*) refused=yes; break ;; esac
  sleep 10
done
std_after="$("${G[@]}" container clusters describe "${RUN}-std" --location "${ZONE}" --format='value(createTime,autopilot.enabled)' 2>&1 || true)"
echo "3. Applied for real: Ready reason \`${cond%%|*}\`, message \`$(echo "${cond#*|}" | tr '\n|' '  ' | cut -c1-400)\`." >>"${mc}"
echo "4. gcloud before (createTime, autopilot.enabled): \`${std_before}\`; after: \`${std_after}\`." >>"${mc}"
if [[ "${refused}" == yes && -n "${std_before}" && "${std_before}" == "${std_after}" ]]; then
  echo "5. Config Connector refused the change and the cluster is the same Standard cluster. PASS" >>"${mc}"
else
  failed=$((failed + 1)); echo "5. Refused: ${refused}; cluster unchanged: $([[ "${std_before}" == "${std_after}" ]] && echo yes || echo no). FAIL" >>"${mc}"
fi
# Put the Standard spec back before deleting.
kubectl apply --server-side --force-conflicts -n "${NS}" -f "${OUT}/standard.rendered.yaml" >/dev/null
cat "${mc}"

echo "== delete the clusters, then the network"
delete_all "${OUT}/standard.rendered.yaml" "${OUT}/autopilot.rendered.yaml" || echo "live-gke: the clusters were not deleted in ${TIMEOUT}s"
delete_all "${OUT}/net.rendered.yaml" || echo "live-gke: the network was not deleted in ${TIMEOUT}s"

for m in net standard autopilot nodepool; do
  while read -r o; do
    kubectl get -n "${NS}" "$o" >/dev/null 2>&1 && deleted=no || deleted=yes
    [[ "${ready["$m $o"]}" == yes && "${deleted}" == yes ]] || failed=$((failed + 1))
    echo "| ${m} | ${o%%.*}/${o#*/} | ${ready["$m $o"]} | ${secs["$m $o"]} | ${deleted} | ${msgs["$m $o"]} |" >>"${summary}"
  done < <(for k in "${!ready[@]}"; do [[ "$k" == "$m "* ]] && echo "${k#* }"; done | sort)
done
gone="$("${G[@]}" container clusters list --filter="name~^${RUN}-" --format='value(name)')"
[[ -z "${gone}" ]] || { failed=$((failed + 1)); echo "live-gke: still in Google Cloud: ${gone}"; }
# The chart's firewall rules (gke-<cluster>-... and gke-shadow-<cluster>-...).
fw_left="$("${G[@]}" compute firewall-rules list --filter="name~^gke-(shadow-)?${RUN}-" --format='value(name)')"
[[ -z "${fw_left}" ]] || { failed=$((failed + 1)); echo "live-gke: firewall rules still in Google Cloud: ${fw_left}"; }
{ echo; echo "Clusters of this run in gcloud container clusters list after the deletes: ${gone:-none}; the chart's firewall rules left: ${fw_left:-none}; the gke-nodepool chart's pool gone after its delete: ${np_gone:-not checked}."
  cat "${mc}"
  echo; echo "${failed} failures."; } >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
