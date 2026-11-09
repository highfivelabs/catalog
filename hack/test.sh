#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Render tests for every chart, offline and light (docs/design.md,
# "Testing"):
#
#   1. each chart's templates/_kcc.tpl is lib/_kcc.tpl;
#   2. helm lint;
#   3. its Package document matches the chart and its outputs compile;
#   4. each tests/<case>.values.yaml renders, matches
#      tests/golden/<case>.yaml, and validates (kubeconform -strict)
#      against Config Connector's CRD schemas at the release in UPSTREAM.md;
#   5. each tests/<case>.fail.yaml fails to render with the message on its
#      first line ("# expect: ...").
#
#   hack/test.sh              all charts
#   hack/test.sh gcs          one chart
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

fail=0; passed=0
bad() { echo "FAIL $*"; fail=$((fail + 1)); }
ok() { passed=$((passed + 1)); }

charts=("$@")
if [[ ${#charts[@]} -eq 0 ]]; then
  for c in charts/*/*/Chart.yaml; do charts+=("$(basename "$(dirname "$c")")"); done
fi

for name in "${charts[@]}"; do
  dir="$(dirname "$(ls charts/*/"${name}"/Chart.yaml)")"
  if cmp -s lib/_kcc.tpl "${dir}/templates/_kcc.tpl"; then ok; else bad "${name}: templates/_kcc.tpl differs from lib/_kcc.tpl (run hack/sync-lib.sh)"; fi
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
    if out="$(printf '%s\n' "${rendered}" | kubeconform -strict -summary \
        -schema-location "${SCHEMAS}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" - 2>&1)"; then
      ok; echo "ok   ${name}/${case}: ${out#Summary: }"
    else
      bad "${name}/${case}: kubeconform"; echo "${out}"
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
