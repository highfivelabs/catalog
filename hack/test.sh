#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Render tests for every chart, offline and light (docs/design.md,
# "Testing"):
#
#   0. upstream/modules.yaml and each chart's upstream.yaml agree (task upstream-check),
#      and every variable the latter lists as refused is refused (task coverage-verify);
#   1. each chart's shared helpers are the canonical copy: templates/_kcc.tpl
#      is lib/_kcc.tpl (charts/gcp), templates/_ack.tpl is lib/_ack.tpl
#      (charts/aws), templates/_aso.tpl is lib/_aso.tpl (charts/azure);
#   2. helm lint;
#   3. its Package document matches the chart and its outputs compile;
#   4. each tests/<case>.values.yaml renders, matches
#      tests/golden/<case>.yaml, and validates (kubeconform -strict)
#      against Config Connector's CRD schemas at the release in UPSTREAM.md,
#      the ACK controllers' (hack/ack.sh) for an AWS chart, Azure Service
#      Operator's (hack/aso.sh) for an Azure chart;
#   4b. the namePrefix check (catalogtool nameprefix) and each case rendered with a
#      namePrefix validates too;
#   4c. every object of every case has an hfl.dev/id, and no two share one
#      (catalogtool ids);
#   5. each tests/<case>.fail.yaml fails to render with the message on its
#      first line ("# expect: ...").
#
#   hack/test.sh              all charts
#   hack/test.sh gcs          one chart (or gcp/gcs, aws/vpc)
#   UPDATE=1 hack/test.sh     rewrite the golden files
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

for t in helm kubeconform go git; do
  command -v "$t" >/dev/null || { echo "test.sh: $t is not installed" >&2; exit 2; }
done
CRDS="$(hack/kcc.sh)"
VERSION="$(basename "$(dirname "$(dirname "$(dirname "${CRDS}")")")" | sed 's/^kcc-//')"
SCHEMAS="${ROOT}/.cache/schemas-${VERSION}"
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)
# config-connector-extensions kinds (IAMBinding) validate against the CRDs
# copied in crds/config-connector-extensions.
CCE_SCHEMAS="${ROOT}/.cache/schemas-cce"
rm -rf "${CCE_SCHEMAS}"
bin/catalogtool schemas crds/config-connector-extensions "${CCE_SCHEMAS}" >/dev/null
# ACK's kinds validate against the CRDs of the controllers UPSTREAM.md pins
# (hack/ack.sh), ack-extensions kinds against the CRDs copied in
# crds/ack-extensions.
ACK_SCHEMAS="$(hack/ack.sh)"
ACKX_SCHEMAS="${ROOT}/.cache/schemas-ack-extensions"
rm -rf "${ACKX_SCHEMAS}"
bin/catalogtool schemas crds/ack-extensions "${ACKX_SCHEMAS}" >/dev/null
# Azure Service Operator kinds validate against its CRDs at the release in
# UPSTREAM.md (hack/aso.sh), aso-extensions kinds (ManagementLock) against
# the CRDs copied in crds/aso-extensions.
ASO_SCHEMAS="$(hack/aso.sh)"
ASOX_SCHEMAS="${ROOT}/.cache/schemas-aso-extensions"
rm -rf "${ASOX_SCHEMAS}"
bin/catalogtool schemas crds/aso-extensions "${ASOX_SCHEMAS}" >/dev/null
SCHEMA_ARGS=()
for s in "${SCHEMAS}" "${CCE_SCHEMAS}" "${ACK_SCHEMAS}" "${ACKX_SCHEMAS}" "${ASO_SCHEMAS}" "${ASOX_SCHEMAS}"; do
  SCHEMA_ARGS+=(-schema-location "${s}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")
done

fail=0; passed=0
bad() { echo "FAIL $*"; fail=$((fail + 1)); }
ok() { passed=$((passed + 1)); }

# upstream/modules.yaml and every chart's upstream.yaml agree.
if out="$(bin/catalogtool upstream check 2>&1)"; then ok; else bad "upstream: pins"; echo "${out}"; fi
# the variables each chart's upstream.yaml says it refuses really are refused.
if out="$(bin/catalogtool coverage verify 2>&1)"; then ok; echo "ok   ${out}"; else bad "coverage verify"; echo "${out}"; fi

# Chart directories: all, or the ones named (gcs, or gcp/gcs where two
# clouds have a chart of one name).
dirs=()
if [[ $# -eq 0 ]]; then
  for c in charts/*/*/Chart.yaml; do dirs+=("$(dirname "$c")"); done
else
  for a in "$@"; do
    found=()
    for c in charts/*/*/Chart.yaml; do
      d="$(dirname "$c")"
      if [[ "${d}" == "charts/${a}" || "$(basename "${d}")" == "${a}" ]]; then found+=("${d}"); fi
    done
    [[ ${#found[@]} -eq 1 ]] || { echo "test.sh: ${a} names ${#found[@]} charts (${found[*]:-none}): name it as <cloud>/<chart>" >&2; exit 2; }
    dirs+=("${found[0]}")
  done
fi

for dir in "${dirs[@]}"; do
  name="${dir#charts/}"
  # The shared helpers each cloud's charts carry (hack/sync-lib.sh).
  case "${name%%/*}" in
    aws) lib=_ack.tpl ;;
    azure) lib=_aso.tpl ;;
    *) lib=_kcc.tpl ;;
  esac
  if cmp -s "lib/${lib}" "${dir}/templates/${lib}"; then ok; else bad "${name}: templates/${lib} differs from lib/${lib} (run hack/sync-lib.sh)"; fi
  # A chart that depends on others (a wrapper) gets them from Chart.lock,
  # built from the charts beside it (file://), never fetched.
  if grep -q '^dependencies:' "${dir}/Chart.yaml"; then
    if out="$(helm dependency build "${dir}" 2>&1)"; then ok; else bad "${name}: helm dependency build"; echo "${out}"; continue; fi
  fi
  first="$(ls "${dir}"/tests/*.values.yaml | head -1)"
  if out="$(helm lint "${dir}" -f "${first}" 2>&1)"; then ok; else bad "${name}: helm lint"; echo "${out}"; fi
  if out="$(bin/catalogtool check "${dir}/package.yaml" "${dir}/Chart.yaml" 2>&1)"; then ok; else bad "${name}: package.yaml"; echo "${out}"; fi
  mkdir -p "${dir}/tests/golden"
  for values in "${dir}"/tests/*.values.yaml; do
    case="$(basename "${values}" .values.yaml)"
    golden="${dir}/tests/golden/${case}.yaml"
    if ! rendered="$(helm template "${case}" "${dir}" --namespace test -f "${values}" 2>&1)"; then
      bad "${name}/${case}: render"; echo "${rendered}"; continue
    fi
    if [[ -n "${UPDATE:-}" ]]; then printf '%s\n' "${rendered}" >"${golden}"; fi
    if diff -u "${golden}" <(printf '%s\n' "${rendered}") >/dev/null 2>&1; then ok; else
      bad "${name}/${case}: differs from tests/golden/${case}.yaml (UPDATE=1 to accept)"
      diff -u "${golden}" <(printf '%s\n' "${rendered}") | head -40 || true
    fi
    if out="$(printf '%s\n' "${rendered}" | kubeconform -strict -summary "${SCHEMA_ARGS[@]}" - 2>&1)"; then
      ok; echo "ok   ${name}/${case}: ${out#Summary: }"
    else
      bad "${name}/${case}: kubeconform"; echo "${out}"
    fi
  done
  # the namePrefix convention: every collision-prone cloud name carries it, an
  # empty one changes nothing (docs/design.md, "Names, labels and tags").
  if out="$(bin/catalogtool nameprefix "${dir}" 2>&1)"; then ok; else bad "${name}: namePrefix"; echo "${out}"; fi
  # every object has an hfl.dev/id and no two share one (docs/design.md, "Outputs").
  if out="$(bin/catalogtool ids "${dir}" 2>&1)"; then ok; else bad "${name}: ids"; echo "${out}"; fi
  # namePrefix=zz9 on the chart and on each chart it depends on.
  prefix_sets=()
  while read -r s; do prefix_sets+=(--set "$s"); done < <(bin/catalogtool nameprefix-sets "${dir}" zz9)
  for values in "${dir}"/tests/*.values.yaml; do
    case="$(basename "${values}" .values.yaml)"
    if rendered="$(helm template "${case}" "${dir}" --namespace test -f "${values}" "${prefix_sets[@]}" 2>&1)" \
        && out="$(printf '%s\n' "${rendered}" | kubeconform -strict -summary "${SCHEMA_ARGS[@]}" - 2>&1)"; then
      ok
    else
      bad "${name}/${case}: with namePrefix=zz9"; echo "${rendered}" | head -5; echo "${out:-}"
    fi
  done
  for values in "${dir}"/tests/*.fail.yaml; do
    [[ -e "${values}" ]] || continue
    case="$(basename "${values}" .fail.yaml)"
    want="$(sed -n '1s/^# expect: //p' "${values}")"
    [[ -n "${want}" ]] || { bad "${name}/${case}: no '# expect:' line"; continue; }
    if out="$(helm template "${case}" "${dir}" --namespace test -f "${values}" 2>&1)"; then
      bad "${name}/${case}: rendered, want a failure saying: ${want}"
    elif [[ "${out}" == *"${want}"* ]]; then
      ok; echo "ok   ${name}/${case}: refused: ${want}"
    else
      bad "${name}/${case}: failed, but not with: ${want}"; echo "${out}" | head -5
    fi
  done
done

echo "${passed} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
