# shellcheck shell=bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Sourced by hack/azure-mock.sh and hack/azure-live.sh: aso-extensions'
# manager beside stock Azure Service Operator, so the charts' aso-extensions
# kinds (a ManagementLock, a private DNS zone's SOA record, an AKS managed
# namespace, a registry's tokens, a workspace's tables ...) are applied and
# reconciled, not only rendered (docs/azure.md, "8. Charts", Testing).
#
# How: aso-extensions at one commit (ASOX_TARBALL, a `git archive` in Cloud
# Storage, or ASOX_DIR, a checkout) is unpacked; its manager is built from
# cmd/manager (the stock build, not -tags fakecloud: it reads ASO's own
# aso-controller-settings, so it talks to whatever Resource Manager ASO
# talks to) into a scratch image with the host's CA bundle, loaded into
# kind, and installed from its config/default (its CRDs, its RBAC and the
# manager under its own service account aso-extensions-manager in ASO's
# namespace). The caller patches the Deployment with how the manager gets
# its token (asox_install_manager's argument), as it does ASO's.
#
# Functions:
#   asox_crd_pattern P       ASO's crdPattern P plus the owner groups
#   asox_fetch WORK          set ASOX_DIR (from ASOX_TARBALL unless set)
#   asox_build_manager WORK  build the image catalog.local/asox-manager:run
#   asox_install_manager CLUSTER PATCH
#                            load the image into kind CLUSTER, install
#                            config/default with it, apply PATCH (a
#                            strategic merge patch of the Deployment, JSON)
#                            and wait for the rollout
#   asox_manager_logs FILE   the manager's log

ASOX_IMAGE=catalog.local/asox-manager:run
# The ASO API groups of the owners aso-extensions' kinds name (its
# pkg/controllers OwnerTypes at ASOX_COMMIT): the manager starts an informer
# for each at startup and exits when one's CRD is missing, so ASO is
# installed with these groups too (asox_crd_pattern).
ASOX_OWNER_GROUPS="dbforpostgresql keyvault app resources web operationalinsights containerregistry compute sql containerservice network documentdb cognitiveservices storage"
ASOX_NS=azureserviceoperator-system
ASOX_DEPLOYMENT=aso-extensions-manager

# asox_crd_pattern PATTERN: ASO's crdPattern PATTERN with every owner group
# added that it lacks.
asox_crd_pattern() {
  local out="$1" g
  for g in ${ASOX_OWNER_GROUPS}; do
    [[ ";${out};" == *";${g}.azure.com/*;"* ]] || out="${out};${g}.azure.com/*"
  done
  echo "${out}"
}

asox_fetch() {
  local work="$1" obj bucket token
  if [[ -z "${ASOX_DIR:-}" ]]; then
    [[ -n "${ASOX_TARBALL:-}" ]] || { echo "asox: set ASOX_TARBALL or ASOX_DIR" >&2; return 2; }
    ASOX_DIR="${work}/aso-extensions"
    mkdir -p "${ASOX_DIR}"
    # gcloud where the VM has it, else the Cloud Storage JSON API as the
    # VM's service account.
    if command -v gcloud >/dev/null; then
      gcloud storage cp --quiet "${ASOX_TARBALL}" "${work}/asox.tar.gz"
    else
      obj="${ASOX_TARBALL#gs://}"; bucket="${obj%%/*}"; obj="${obj#*/}"
      token="$(curl -sf -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -er .access_token)"
      curl -sfL -o "${work}/asox.tar.gz" -H "Authorization: Bearer ${token}" \
        "https://storage.googleapis.com/storage/v1/b/${bucket}/o/$(jq -rn --arg o "${obj}" '$o|@uri')?alt=media"
    fi
    tar -xzf "${work}/asox.tar.gz" -C "${ASOX_DIR}"
  fi
  ASOX_DIR="$(cd "${ASOX_DIR}" && pwd)"
  # aso-extensions builds against its patched Azure Service Operator
  # checkout (third_party/, not committed; its hack/upstream.sh fetches the
  # pin).
  [[ -d "${ASOX_DIR}/third_party/azure-service-operator/v2" ]] || (cd "${ASOX_DIR}" && hack/upstream.sh)
}

asox_build_manager() {
  local work="$1" ca
  mkdir -p "${work}/img-asox-manager"
  (cd "${ASOX_DIR}" && CGO_ENABLED=0 go build -o "${work}/img-asox-manager/manager" ./cmd/manager)
  # The host's CA bundle, for Azure's endpoints in a live run (the fake
  # cloud's CA comes through SSL_CERT_FILE instead).
  for ca in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt; do
    [[ -f "${ca}" ]] && break
  done
  [[ -f "${ca}" ]] || { echo "asox: no CA bundle on this host" >&2; return 2; }
  cp "${ca}" "${work}/img-asox-manager/ca-certificates.crt"
  # A numeric user: the manager's pod runs as non-root.
  printf 'FROM scratch\nCOPY ca-certificates.crt /etc/ssl/certs/ca-certificates.crt\nCOPY manager /manager\nUSER 65532:65532\nENTRYPOINT ["/manager"]\n' \
    >"${work}/img-asox-manager/Dockerfile"
  docker build -q -t "${ASOX_IMAGE}" "${work}/img-asox-manager" >/dev/null
}

asox_install_manager() {
  local cluster="$1" patch="$2" crds
  kind load docker-image "${ASOX_IMAGE}" --name "${cluster}" >/dev/null
  # config/default names the image ko://...; this run's image instead. The
  # CRDs go first, server-side (some are larger than a client-side apply's
  # annotation allows).
  kubectl kustomize "${ASOX_DIR}/config/default" \
    | sed -E "s#image: ko://github.com/highfivelabs/aso-extensions/cmd/manager#image: ${ASOX_IMAGE}#" >"${WORK}/asox-install.yaml"
  grep -q "image: ${ASOX_IMAGE}" "${WORK}/asox-install.yaml" || { echo "asox: config/default names no ko:// manager image" >&2; return 1; }
  kubectl apply --server-side -k "${ASOX_DIR}/config/crds" >/dev/null
  mapfile -t crds < <(kubectl get -k "${ASOX_DIR}/config/crds" -o name)
  kubectl wait --for=condition=Established "${crds[@]}" --timeout=300s >/dev/null
  # The Deployment gets its token patch before it is created, so no pod
  # ever starts without one.
  awk -v out="${WORK}/asox-deployment.yaml" -v rest="${WORK}/asox-rest.yaml" '
    function flush() { if (doc != "") { print doc > (doc ~ /\nkind: Deployment\n/ ? out : rest); print "---" > (doc ~ /\nkind: Deployment\n/ ? out : rest) } doc = "" }
    /^---$/ { flush(); next }
    { doc = doc "\n" $0 }
    END { flush() }' "${WORK}/asox-install.yaml"
  kubectl patch --local --type strategic -p "${patch}" -f "${WORK}/asox-deployment.yaml" -o yaml >"${WORK}/asox-deployment-patched.yaml"
  kubectl apply --server-side -f "${WORK}/asox-rest.yaml" >/dev/null
  kubectl apply --server-side -f "${WORK}/asox-deployment-patched.yaml" >/dev/null
  if ! kubectl -n "${ASOX_NS}" rollout status deployment "${ASOX_DEPLOYMENT}" --timeout 5m; then
    echo "asox: the manager did not become ready" >&2
    kubectl -n "${ASOX_NS}" get pods -l app.kubernetes.io/component=manager -o wide >&2 || true
    kubectl -n "${ASOX_NS}" describe pods -l app.kubernetes.io/component=manager 2>&1 | tail -40 >&2 || true
    kubectl -n "${ASOX_NS}" logs "deployment/${ASOX_DEPLOYMENT}" --tail=80 >&2 || true
    kubectl -n "${ASOX_NS}" logs "deployment/${ASOX_DEPLOYMENT}" --previous --tail=40 >&2 || true
    return 1
  fi
}

asox_manager_logs() {
  kubectl -n "${ASOX_NS}" logs "deployment/${ASOX_DEPLOYMENT}" --tail=-1 >"$1" 2>&1 || true
}
