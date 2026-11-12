#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply each chart's tests/mock.values.yaml to a fake Google Cloud and
# check it end to end (docs/design.md, "Testing"): every object Ready, the
# Package's outputs evaluated against the live objects, then every object
# deleted. Heavy: run it on an offload VM, never on a laptop:
#
#   ../offload/offload run --hours 2 -- \
#     env CCE_TARBALL=gs://.../cce-<commit>.tar.gz hack/mock-apply.sh
#
# The fake cloud is config-connector-extensions' (its docs/fake-cloud.md):
# a kind cluster holding Config Connector's CRDs, and Config Connector's
# own manager on the host with every Google API answered in process by
# mockgcp. config-connector-extensions is read from CCE_TARBALL (a
# `git archive` of one commit, in Cloud Storage) or CCE_DIR (a checkout).
#
# MOCK_CHARTS="gcs net-vpc" applies only those charts (default: every
# chart with a tests/mock.values.yaml).
#
# Writes offload-artifacts/mock/summary.md and, per chart, the render,
# the live objects and the outputs.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
OUT="${ROOT}/offload-artifacts/mock"
PROJECT=mock-project
TIMEOUT="${MOCK_TIMEOUT:-300}"
GROUPS_NEEDED="iam resourcemanager compute storage pubsub serviceusage dns servicenetworking orgpolicy essentialcontacts tags container artifactregistry kms secretmanager sql logging"
mkdir -p "${OUT}"

for t in docker kind kubectl helm go git; do
  command -v "$t" >/dev/null || { echo "mock-apply: $t is not installed" >&2; exit 2; }
done

if [[ -z "${CCE_DIR:-}" ]]; then
  [[ -n "${CCE_TARBALL:-}" ]] || { echo "mock-apply: set CCE_TARBALL or CCE_DIR" >&2; exit 2; }
  CCE_DIR="${ROOT}/.cache/cce"
  rm -rf "${CCE_DIR}" && mkdir -p "${CCE_DIR}"
  gcloud storage cat "${CCE_TARBALL}" | tar -xz -C "${CCE_DIR}"
  # hack/upstream.sh wants a git checkout to compare against.
  git -C "${CCE_DIR}" init -q && git -C "${CCE_DIR}" add -A && \
    git -C "${CCE_DIR}" -c user.email=mock@example.com -c user.name=mock commit -qm "cce from ${CCE_TARBALL}"
fi
CCE_DIR="$(cd "${CCE_DIR}" && pwd)"
# Workaround, in this scratch copy only: config-connector-extensions'
# hack/fake-cloud/up.sh applies config/crds/*.yaml, which at 1de95478
# also matches kustomization.yaml, and kubectl refuses it. Reported to
# config-connector-extensions; remove when its up.sh skips it.
if [[ -f "${CCE_DIR}/config/crds/kustomization.yaml" ]]; then
  mkdir -p "${CCE_DIR}/.moved" && mv "${CCE_DIR}/config/crds/kustomization.yaml" "${CCE_DIR}/.moved/"
fi
if [[ ! -d "${CCE_DIR}/.git" ]]; then
  # hack/upstream.sh wants a git checkout to compare against.
  git -C "${CCE_DIR}" init -q && git -C "${CCE_DIR}" add -A && \
    git -C "${CCE_DIR}" -c user.email=mock@example.com -c user.name=mock commit -qm "cce snapshot"
fi
echo "== config-connector-extensions from ${CCE_TARBALL:-${CCE_DIR}}"

(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)
start=$(date +%s)
(cd "${CCE_DIR}" && make upstream >/dev/null)
(cd "${CCE_DIR}" && CRD_GROUPS="${GROUPS_NEEDED}" FAKE_CLOUD_PROJECT="${PROJECT}" make fake-cloud-up)
export KUBECONFIG="${CCE_DIR}/bin/fake-cloud/kubeconfig"
echo "== fake cloud up in $(( $(date +%s) - start ))s"
trap '(cd "${CCE_DIR}" && make fake-cloud-down) >/dev/null 2>&1 || true' EXIT

summary="${OUT}/summary.md"
{
  echo "# Mock apply, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Catalog commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown); config-connector-extensions from ${CCE_TARBALL:-${CCE_DIR}};"
  echo "Config Connector at $(sed -n 's/^| Commit | `\([0-9a-f]*\)`.*/\1/p' "${CCE_DIR}/UPSTREAM.md" | cut -c1-12) (config-connector-extensions' pin) against mockgcp."
  echo
  echo "| Chart | Object | Ready | Deleted | Message |"
  echo "| --- | --- | --- | --- | --- |"
} >"${summary}"

total=0; failed=0
for values in charts/*/*/tests/mock.values.yaml; do
  dir="$(dirname "$(dirname "${values}")")"; chart="$(basename "${dir}")"
  if [[ -n "${MOCK_CHARTS:-}" && " ${MOCK_CHARTS} " != *" ${chart} "* ]]; then continue; fi
  ns="catalog-${chart}"; rel="mock"
  echo "== ${chart}"
  mkdir -p "${OUT}/${chart}"
  kubectl create namespace "${ns}" --dry-run=client -o yaml \
    | kubectl annotate --local -f - "cnrm.cloud.google.com/project-id=${PROJECT}" -o yaml \
    | kubectl apply -f - >/dev/null
  if grep -q '^dependencies:' "${dir}/Chart.yaml"; then helm dependency build "${dir}" >/dev/null; fi
  helm template "${rel}" "${dir}" --namespace "${ns}" -f "${values}" >"${OUT}/${chart}/rendered.yaml"
  kubectl apply --server-side -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" >"${OUT}/${chart}/apply.log"
  # Fully qualified (kind.version.group/name): "Service" alone is the core kind.
  # One object comes back as itself, not a List: make it one.
  mapfile -t objects < <(kubectl get -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq -r '(if .items then .items else [.] end)[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"')
  short() { local k="${1%%.*}" n="${1#*/}"; jq -r --arg k "$k" --arg n "$n" '.items[] | select((.kind | ascii_downcase) == $k and .metadata.name == $n) | "\(.kind)/\(.metadata.name)"' "${OUT}/${chart}/live.json"; }
  deadline=$(( $(date +%s) + TIMEOUT ))
  declare -A ready=()
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${ns}" --for=condition=Ready "${o}" --timeout="${left}s" >/dev/null 2>&1; then
      ready["$o"]=yes
    else
      ready["$o"]=no
    fi
  done
  kubectl get -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${chart}/live.json"
  if bin/catalogtool outputs "${dir}/package.yaml" "${OUT}/${chart}/live.json" "${dir}/values.yaml" "${values}" >"${OUT}/${chart}/outputs.json" 2>"${OUT}/${chart}/outputs.err"; then
    outputs_ok=yes
  else
    outputs_ok=no
  fi
  echo "-- outputs (${outputs_ok})"; cat "${OUT}/${chart}/outputs.json" "${OUT}/${chart}/outputs.err"
  # Delete the component as Bundt prunes it: every object at once.
  kubectl delete -n "${ns}" -f "${OUT}/${chart}/rendered.yaml" --wait=false >/dev/null
  # The fake cloud runs Config Connector's controller manager but not its
  # deletion defender (a separate pod, cnrm-deletiondefender, in a real
  # install), so nothing releases the cnrm.cloud.google.com/deletion-defender
  # finalizer of Config Connector's own kinds. Do what that pod does when
  # the kind's CRD is not being uninstalled: remove it. Config Connector's
  # controller then deletes the resource in the fake cloud and removes its
  # own finalizer.
  deadline=$(( $(date +%s) + TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    left=0
    for o in "${objects[@]}"; do
      f="$(kubectl get -n "${ns}" "${o}" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)" || continue
      left=$((left + 1))
      if [[ "${f}" == *deletion-defender* ]]; then
        kubectl get -n "${ns}" "${o}" -o json \
          | jq '.metadata.finalizers |= map(select(. != "cnrm.cloud.google.com/deletion-defender"))' \
          | kubectl replace -f - >/dev/null 2>&1 || true
      fi
    done
    (( left == 0 )) && break
    sleep 3
  done
  for o in "${objects[@]}"; do
    total=$((total + 1))
    d="$(short "$o")"; d="${d:-$o}"
    msg="$(kubectl get -n "${ns}" "${o}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null | tr '\n|' '  ' | cut -c1-160 || true)"
    if kubectl get -n "${ns}" "${o}" >/dev/null 2>&1; then deleted=no; else deleted=yes; fi
    if [[ -z "${msg}" ]]; then
      msg="$(jq -r --arg d "${d}" '.items[] | select("\(.kind)/\(.metadata.name)" == $d) | (.status.conditions // [])[] | select(.type=="Ready") | .message' "${OUT}/${chart}/live.json" | tr '\n|' '  ' | cut -c1-160)"
    fi
    [[ "${ready[$o]}" == yes && "${deleted}" == yes ]] || failed=$((failed + 1))
    echo "| ${chart} | ${d} | ${ready[$o]} | ${deleted} | ${msg} |" >>"${summary}"
    echo "   ${d}: ready=${ready[$o]} deleted=${deleted} ${msg}"
  done
  echo "| ${chart} | outputs | ${outputs_ok} | | $(tr '\n' ' ' <"${OUT}/${chart}/outputs.err" | cut -c1-160) |" >>"${summary}"
  [[ "${outputs_ok}" == yes ]] || failed=$((failed + 1))
  unset ready
done

cp "${CCE_DIR}/bin/fake-cloud/fakecloud.log" "${OUT}/fakecloud.log" 2>/dev/null || true
{ echo; echo "${total} objects; ${failed} failures (an object not Ready or not deleted, or a chart's outputs not evaluated)."; } >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
