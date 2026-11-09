#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply three pilot charts (iam-service-account, gcs, net-vpc) to real
# Google Cloud with tiny resources, delete them, and check nothing is left
# (docs/design.md, "Testing", layer 3). Only after hack/mock-apply.sh
# passes; only in a project listed below; only on an offload VM acting as
# a service account, never with a key. `task test-live` runs it:
#
#   ../offload/offload run --sa catalog-live-tests@hfl-dev-514205.iam.gserviceaccount.com \
#     --machine e2-standard-8 --hours 2 -- env PROJECT=hfl-dev-514205 \
#     CCE_TARBALL=gs://.../cce-<commit>.tar.gz hack/live-apply.sh
#
# Rules: one project (hfl-dev-514205); every gcloud call passes --project;
# every name starts with a run ID, cat-<UTC month day hour minute>-<4 hex>,
# and every object that takes labels carries catalog-run=<run ID>; the test
# deletes what it makes; a sweeper runs before and after (this run's
# resources, and any "cat-" leftovers older than two hours); at the end it
# lists what is left in the project.
#
# Config Connector runs as config-connector-extensions' fake cloud does
# (its manager on the host against a kind cluster holding the CRDs), but
# against Google Cloud: hack/live/realcloud.go.txt, built in a scratch
# copy of config-connector-extensions so it uses the same pinned Config
# Connector. Writes offload-artifacts/live/summary.md.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
ALLOWED_PROJECTS=(hfl-dev-514205)
PROJECT="${PROJECT:-}"
REGION=us-central1
TIMEOUT="${LIVE_TIMEOUT:-600}"
OUT="${ROOT}/offload-artifacts/live"
mkdir -p "${OUT}"

allowed=no
for p in "${ALLOWED_PROJECTS[@]}"; do [[ "${PROJECT}" == "${p}" ]] && allowed=yes; done
[[ "${allowed}" == yes ]] || { echo "live-apply: refusing project '${PROJECT}': only ${ALLOWED_PROJECTS[*]}" >&2; exit 2; }
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
}
# sweep_old: every cat- run older than two hours.
sweep_old() {
  local cutoff r
  cutoff="$(date -u -d '2 hours ago' +%m%d%H%M)"
  { "${G[@]}" iam service-accounts list --format='value(email)' | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-sa@.*/\1/p'
    "${G[@]}" storage buckets list --format='value(name)' | sed -n "s/^${PROJECT}-\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)\$/\1/p"
    "${G[@]}" compute networks list --format='value(name)' | sed -n 's/^\(cat-[0-9]\{8\}-[0-9a-f]\{4\}\)-net$/\1/p'
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
for g in iam storage compute; do
  for f in "${KCC}"/config/crds/resources/*."${g}".cnrm.cloud.google.com.yaml; do printf -- '---\n'; cat "$f"; done
done | kubectl apply --server-side --force-conflicts -f - >/dev/null
kubectl wait --for=condition=Established crd --all --timeout=180s >/dev/null
"${ROOT}/bin/realcloud" >"${OUT}/manager.log" 2>&1 &
MANAGER_PID=$!
for _ in $(seq 1 90); do grep -q "Starting workers" "${OUT}/manager.log" && break; sleep 2; done
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
for chart in iam-service-account gcs net-vpc; do
  echo "== ${chart}"
  dir="charts/gcp/${chart}"
  helm template live "${dir}" --namespace "${NS}" -f "${OUT}/${chart}.values.yaml" >"${OUT}/${chart}.rendered.yaml"
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
