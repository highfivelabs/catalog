#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Copy lib/_kcc.tpl into every Google Cloud chart's templates/, and
# lib/_aso.tpl into every Azure chart's (a chart is published alone, so it
# carries its own copy). hack/test.sh fails when a copy differs.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for c in "${ROOT}"/charts/*/*/Chart.yaml; do
  case "$c" in
    "${ROOT}"/charts/azure/*) cp "${ROOT}/lib/_aso.tpl" "$(dirname "$c")/templates/_aso.tpl" ;;
    *) cp "${ROOT}/lib/_kcc.tpl" "$(dirname "$c")/templates/_kcc.tpl" ;;
  esac
done
