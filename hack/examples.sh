#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Check the migration examples (examples/*/): each holds a Terraform module
# call (main.tf, terraform.tfvars) and the files made from it.
#
#   bundt.yaml     the Template, Stack and Instance that replace it
#                  (checked by `go test ./convert`, task tools-test)
#   messages.txt   what the converter says it could not carry
#   plan.txt       the plan preview (plan-<x>.txt for convert-<x>.args): what Bundt would list for those documents
#   rendered.yaml  the Config Connector objects the charts render for them
#
# This script regenerates plan.txt and rendered.yaml with helm, compares them
# with the committed files, and validates rendered.yaml (kubeconform -strict)
# against Config Connector's CRD schemas. Light: helm and kubeconform only.
#
#   hack/examples.sh            check
#   UPDATE=1 hack/examples.sh   rewrite plan.txt and rendered.yaml (and bundt.yaml, messages.txt)
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
for t in helm kubeconform go; do
  command -v "$t" >/dev/null || { echo "examples.sh: $t is not installed" >&2; exit 2; }
done
CRDS="$(hack/kcc.sh)"
VERSION="$(basename "$(dirname "$(dirname "$(dirname "${CRDS}")")")" | sed 's/^kcc-//')"
SCHEMAS="${ROOT}/.cache/schemas-${VERSION}"
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)
if [[ -n "${UPDATE:-}" ]]; then (cd tools && UPDATE=1 go test ./convert >/dev/null); fi

fail=0; passed=0
bad() { echo "FAIL $*"; fail=$((fail + 1)); }
ok() { passed=$((passed + 1)); }
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT

for dir in examples/*/; do
  dir="${dir%/}"; name="$(basename "${dir}")"
  # convert.args holds extra flags for catalogtool convert; convert-<x>.args
  # makes a second plan (plan-<x>.txt), such as another Instance of the same Stack.
  argfiles=("${dir}"/convert.args)
  for f in "${dir}"/convert-*.args; do [[ -e "$f" ]] && argfiles+=("$f"); done
  for argfile in "${argfiles[@]}"; do
    suffix="$(basename "${argfile}" .args)"; suffix="${suffix#convert}"
    args=("${dir}/main.tf")
    [[ -f "${dir}/terraform.tfvars" ]] && args+=(--tfvars "${dir}/terraform.tfvars")
    [[ -f "${argfile}" ]] && read -r -a extra <"${argfile}" && args+=("${extra[@]}")
    rc=0
    bin/catalogtool convert "${args[@]}" --plan --render "${tmp}/rendered.yaml" >"${tmp}/plan.txt" 2>"${tmp}/stderr" || rc=$?
    # exit 3 means "something could not be carried": the plan is still made.
    if [[ ${rc} -ne 0 && ${rc} -ne 3 ]]; then bad "${name}: convert failed"; cat "${tmp}/stderr"; continue; fi
    [[ -f "${tmp}/rendered.yaml" ]] || : >"${tmp}/rendered.yaml"
    if [[ -n "${UPDATE:-}" ]]; then
      cp "${tmp}/plan.txt" "${dir}/plan${suffix}.txt"; cp "${tmp}/rendered.yaml" "${dir}/rendered${suffix}.yaml"
    fi
    for f in plan rendered; do
      ext=txt; [[ ${f} == rendered ]] && ext=yaml
      want="${dir}/${f}${suffix}.${ext}"; got="${tmp}/${f}.${ext}"
      if diff -u "${want}" "${got}" >/dev/null 2>&1; then ok; else bad "${name}: ${f}${suffix}.${ext} differs (UPDATE=1 to accept)"; diff -u "${want}" "${got}" | head -20 || true; fi
    done
    if [[ -s "${tmp}/rendered.yaml" ]]; then
      if out="$(kubeconform -strict -summary -schema-location "${SCHEMAS}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" "${tmp}/rendered.yaml" 2>&1)"; then
        ok; echo "ok   ${name}${suffix}: ${out#Summary: }"
      else
        bad "${name}${suffix}: kubeconform"; echo "${out}"
      fi
    fi
  done
done
(cd tools && go test ./convert >/dev/null) && ok || bad "convert: bundt.yaml or messages.txt differ from the converter's output (UPDATE=1 to accept)"
echo "${passed} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
