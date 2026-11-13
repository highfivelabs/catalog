# shellcheck shell=bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Sourced by hack/live-apply.sh and hack/live-gke.sh: config-connector-
# extensions' manager beside Config Connector's, so the charts'
# config-connector-extensions kinds (*.gcp.hfl.dev: a network attachment,
# a router route policy, regional firewall policies, IAMBinding ...) are
# reconciled against Google Cloud, not only rendered. The fake cloud
# (hack/mock-apply.sh) already runs them: config-connector-extensions'
# cmd/fakecloud adds the same controllers to Config Connector's manager.
#
# How: in the scratch copy of config-connector-extensions at CCE_COMMIT
# that the caller unpacked into CCE_DIR (after its hack/upstream.sh, as
# for the fake cloud), the stock manager, cmd/manager, is built (not
# -tags fakecloud, so it cannot talk to a fake). Its CRDs
# (config/crds/*.gcp.hfl.dev_*.yaml, as its hack/fake-cloud/up.sh installs
# them) go into the kind cluster, and the manager runs on the host beside
# Config Connector's, with Application Default Credentials: on an offload
# VM, the VM's service account from the metadata server, the same
# identity as Config Connector's; never a key. It runs its own deletion
# defender for its kinds, and its metrics server is off, so it binds no
# port.
#
# Functions (ROOT, CCE_DIR and KUBECONFIG set by the caller):
#   cce_build_manager       build cmd/manager into bin/cce-manager
#   cce_install_crds        apply its CRDs and wait until Established
#   cce_start_manager LOG   start it, log to LOG, set CCE_MANAGER_PID, and
#                           fail unless it reaches "Starting workers"

cce_build_manager() {
  (cd "${CCE_DIR}" && GOTOOLCHAIN=auto go build -o "${ROOT}/bin/cce-manager" ./cmd/manager)
}

cce_install_crds() {
  local f crds=("${CCE_DIR}"/config/crds/*.gcp.hfl.dev_*.yaml)
  [[ -f "${crds[0]}" ]] || { echo "cce: no config/crds/*.gcp.hfl.dev_*.yaml in ${CCE_DIR}" >&2; return 2; }
  echo "== installing config-connector-extensions' ${#crds[@]} CRDs"
  for f in "${crds[@]}"; do printf -- '---\n'; cat "$f"; done \
    | kubectl apply --server-side --force-conflicts -f - >/dev/null
  kubectl wait --for=condition=Established crd --all --timeout=180s >/dev/null
}

cce_start_manager() {
  local log="$1" started=no
  "${ROOT}/bin/cce-manager" >"${log}" 2>&1 &
  CCE_MANAGER_PID=$!
  for _ in $(seq 1 90); do
    grep -q "Starting workers" "${log}" && { started=yes; break; }
    kill -0 "${CCE_MANAGER_PID}" 2>/dev/null || break
    sleep 2
  done
  if [[ "${started}" != yes ]]; then
    echo "cce: config-connector-extensions' manager did not start:" >&2
    tail -15 "${log}" >&2
    return 1
  fi
  echo "== config-connector-extensions' manager running (pid ${CCE_MANAGER_PID})"
}
