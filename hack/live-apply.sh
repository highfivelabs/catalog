#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply two pilot charts (iam-service-account and gcs) to real Google
# Cloud, with tiny resources, then delete them and check nothing is left
# (docs/design.md, "Testing", layer 3). Only after hack/mock-apply.sh
# passes; only in a project listed below; only on an offload VM acting as
# a service account, never with a key:
#
#   ../offload/offload run --sa catalog-live-tests@hfl-dev-514205.iam.gserviceaccount.com \
#     --hours 2 -- env PROJECT=hfl-dev-514205 \
#     CCE_TARBALL=gs://.../cce-<commit>.tar.gz hack/live-apply.sh
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
echo "== live run ${RUN} in ${PROJECT} as ${RUNNER}"

# The sweeper, run on any exit: this run's resources, and leftovers of
# earlier runs (names starting cat-, older than two hours).
sweep() {
  echo "== sweep"
  "${G[@]}" iam service-accounts delete "${SA_ID}@${PROJECT}.iam.gserviceaccount.com" >/dev/null 2>&1 && echo "swept service account ${SA_ID}" || true
  gcloud --quiet storage rm -r "gs://${BUCKET}" >/dev/null 2>&1 && echo "swept bucket ${BUCKET}" || true
  local cutoff; cutoff="$(date -u -d '2 hours ago' +%m%d%H%M)"
  "${G[@]}" iam service-accounts list --format='value(email)' | grep -E '^cat-[0-9]{8}-[0-9a-f]{4}-sa@' | while read -r e; do
    [[ "$(echo "$e" | cut -c5-12)" < "${cutoff}" ]] && "${G[@]}" iam service-accounts delete "$e" >/dev/null 2>&1 && echo "swept old service account $e"
  done || true
  gcloud storage buckets list --project "${PROJECT}" --format='value(name)' | grep -E "^${PROJECT}-cat-[0-9]{8}-[0-9a-f]{4}$" | while read -r b; do
    [[ "$(echo "$b" | sed "s/^${PROJECT}-cat-//" | cut -c1-8)" < "${cutoff}" ]] && gcloud --quiet storage rm -r "gs://$b" >/dev/null 2>&1 && echo "swept old bucket $b"
  done || true
}
cleanup() {
  [[ -n "${MANAGER_PID:-}" ]] && kill "${MANAGER_PID}" 2>/dev/null || true
  kind delete cluster --name catalog-live >/dev/null 2>&1 || true
  sweep
  echo "== left in ${PROJECT} (should be nothing below)"
  "${G[@]}" iam service-accounts list --format='value(email)' | grep -E '^cat-' || true
  gcloud storage buckets list --project "${PROJECT}" --format='value(name)' | grep -E "^${PROJECT}-cat-" || true
}
trap cleanup EXIT

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
for g in iam storage; do
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
location: US-CENTRAL1
force_destroy: true
soft_delete_retention: 0
public_access_prevention: enforced
labels: {catalog-run: ${RUN}}
iam:
  roles/storage.objectViewer: ["serviceAccount:${RUNNER}"]
VALUES

summary="${OUT}/summary.md"
{
  echo "# Live apply ${RUN}, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Project ${PROJECT}, as ${RUNNER}; catalog $(git rev-parse --short HEAD 2>/dev/null || echo unknown); Config Connector at config-connector-extensions' pin."
  echo
  echo "| Chart | Object | Ready | Deleted | Gone from Google Cloud |"
  echo "| --- | --- | --- | --- | --- |"
} >"${summary}"
failed=0
for chart in iam-service-account gcs; do
  echo "== ${chart}"
  helm template live "charts/gcp/${chart}" --namespace "${NS}" -f "${OUT}/${chart}.values.yaml" >"${OUT}/${chart}.rendered.yaml"
  kubectl apply --server-side -n "${NS}" -f "${OUT}/${chart}.rendered.yaml"
  mapfile -t objects < <(kubectl get -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}{"\n"}{end}')
  declare -A ready=()
  deadline=$(( $(date +%s) + TIMEOUT ))
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${NS}" --for=condition=Ready "$o" --timeout="${left}s" >/dev/null 2>&1; then ready[$o]=yes; else ready[$o]=no; fi
  done
  kubectl get -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" -o json >"${OUT}/${chart}.live.json"
  bin/catalogtool outputs "charts/gcp/${chart}/package.yaml" "${OUT}/${chart}.live.json" >"${OUT}/${chart}.outputs.json" 2>&1 || failed=$((failed + 1))
  cat "${OUT}/${chart}.outputs.json"
  kubectl delete -n "${NS}" -f "${OUT}/${chart}.rendered.yaml" --wait=false >/dev/null
  deadline=$(( $(date +%s) + TIMEOUT ))
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    kubectl wait -n "${NS}" --for=delete "$o" --timeout="${left}s" >/dev/null 2>&1 || true
  done
  if [[ "${chart}" == gcs ]]; then
    gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1 && gone=no || gone=yes
  else
    "${G[@]}" iam service-accounts describe "${SA_ID}@${PROJECT}.iam.gserviceaccount.com" >/dev/null 2>&1 && gone=no || gone=yes
  fi
  for o in "${objects[@]}"; do
    kubectl get -n "${NS}" "$o" >/dev/null 2>&1 && deleted=no || deleted=yes
    [[ "${ready[$o]}" == yes && "${deleted}" == yes && "${gone}" == yes ]] || failed=$((failed + 1))
    echo "| ${chart} | $o | ${ready[$o]} | ${deleted} | ${gone} |" >>"${summary}"
    echo "   $o ready=${ready[$o]} deleted=${deleted} gone=${gone}"
  done
  unset ready
done
{ echo; echo "${failed} failures."; } >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
