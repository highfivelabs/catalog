#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Copy lib/_kcc.tpl into every chart's templates/ (a chart is published
# alone, so it carries its own copy). hack/test.sh fails when a copy
# differs.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for c in "${ROOT}"/charts/*/*/Chart.yaml; do
  cp "${ROOT}/lib/_kcc.tpl" "$(dirname "$c")/templates/_kcc.tpl"
done
