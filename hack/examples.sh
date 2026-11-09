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
#   plan.txt       the plan preview: what Bundt would list for those documents
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
  args=("${dir}/main.tf")
  [[ -f "${dir}/terraform.tfvars" ]] && args+=(--tfvars "${dir}/terraform.tfvars")
  rc=0
  bin/catalogtool convert "${args[@]}" --plan --render "${tmp}/rendered.yaml" >"${tmp}/plan.txt" 2>"${tmp}/stderr" || rc=$?
  # exit 3 means "something could not be carried": the plan is still made.
  if [[ ${rc} -ne 0 && ${rc} -ne 3 ]]; then bad "${name}: convert failed"; cat "${tmp}/stderr"; continue; fi
  [[ -f "${tmp}/rendered.yaml" ]] || : >"${tmp}/rendered.yaml"
  if [[ -n "${UPDATE:-}" ]]; then
    cp "${tmp}/plan.txt" "${dir}/plan.txt"; cp "${tmp}/rendered.yaml" "${dir}/rendered.yaml"
  fi
  for f in plan.txt rendered.yaml; do
    if diff -u "${dir}/${f}" "${tmp}/${f}" >/dev/null 2>&1; then ok; else bad "${name}: ${f} differs (UPDATE=1 to accept)"; diff -u "${dir}/${f}" "${tmp}/${f}" | head -20 || true; fi
  done
  if [[ -s "${tmp}/rendered.yaml" ]]; then
    if out="$(kubeconform -strict -summary -schema-location "${SCHEMAS}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" "${tmp}/rendered.yaml" 2>&1)"; then
      ok; echo "ok   ${name}: ${out#Summary: }"
    else
      bad "${name}: kubeconform"; echo "${out}"
    fi
  fi
done
(cd tools && go test ./convert >/dev/null) && ok || bad "convert: bundt.yaml or messages.txt differ from the converter's output (UPDATE=1 to accept)"
echo "${passed} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
