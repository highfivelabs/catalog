#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Copy the shared helpers into every chart's templates/ (a chart is
# published alone, so it carries its own copy): lib/_kcc.tpl into the
# Google Cloud charts, lib/_ack.tpl into the AWS charts (ACK) and
# lib/_aso.tpl into the Azure charts (Azure Service Operator). hack/test.sh
# fails when a copy differs.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for c in "${ROOT}"/charts/*/*/Chart.yaml; do
  case "$c" in
    "${ROOT}"/charts/aws/*) cp "${ROOT}/lib/_ack.tpl" "$(dirname "$c")/templates/_ack.tpl" ;;
    "${ROOT}"/charts/azure/*) cp "${ROOT}/lib/_aso.tpl" "$(dirname "$c")/templates/_aso.tpl" ;;
    *) cp "${ROOT}/lib/_kcc.tpl" "$(dirname "$c")/templates/_kcc.tpl" ;;
  esac
done
