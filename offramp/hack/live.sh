#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The offramp's live proof for one fixture shape: apply the Terraform,
# scan, convert (from the state and from the scan), apply the Config
# Connector objects to a kind cluster, and show the adoption changes
# nothing in Google Cloud. Then destroy everything.
#
#   offload run --sa cce-live-tests@hfl-dev-514205.iam.gserviceaccount.com --hours 2 -- \
#     env PROJECT=hfl-dev-514205 offramp/hack/live.sh shared-vpc
#
# Shapes: shared-vpc, folders, platform-project, gke. For folders and
# platform-project set PARENT (folders/<n>, the live-tests folder) and
# ORG_ID; for platform-project BILLING_ACCOUNT too. FIXTURES is the
# directory of root modules (default offramp/fixtures; they may move to the
# terraform-offramp-demo repository).
#
# Every resource of a fixture comes from a published module call. Step 3
# converts each call to an Instance of the catalog chart that ports its
# module (the call's arguments as the chart's values), renders the chart,
# and checks the render against the objects converted from the state;
# steps 4 to 9 adopt what Bundt would deliver: each graduated call's chart
# render (krm/adopt.yaml), and the frozen objects of any call left over.
#
# The proof, in order (each step's result goes to the run's summary.md):
#  1. terraform apply, then `terraform plan -detailed-exitcode` is empty.
#  2. scan.sh; `offramp names`; `config-connector export` of each name.
#  3. `offramp state` (from the state) and `offramp krm` (from the scan);
#     `offramp compare` of the two.
#  4. kind, Config Connector's CRDs, the objects applied with server-side
#     apply as the field manager `bundt` (as Bundt's outpost applies).
#  5. `config-connector preview`: Config Connector's reconcilers run
#     against Google Cloud with every write intercepted; each object must
#     be HEALTHY with no GCP_WRITE. This is the check a plan can make
#     before anything is applied.
#  6. Config Connector's manager starts (window T0): every object Ready
#     with reason UpToDate; the manager's log has no create or update.
#  7. `kubectl diff --server-side --field-manager=bundt`: what Bundt's live
#     check (plans.md R46 R47) would see; must be empty.
#  8. `terraform plan -detailed-exitcode` again: Terraform sees no change.
#  9. Delete the objects (abandon; window T1 to T2): the resources stay.
# 10. Cloud Audit Logs (Admin Activity) for this account in T0..T2: the
#     mutating calls on the run's resources must be none.
# Rules as hack/live-apply.sh: one allowed project, every gcloud call
# passes --project, names start with the run ID, a VM acting as a service
# account, never a key; everything is destroyed and listed at the end.
set -o errexit -o nounset -o pipefail
SHAPE="${1:?shape: shared-vpc, folders, platform-project or gke}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OFF="${ROOT}/offramp"
ALLOWED_PROJECTS=(hfl-dev-514205)
PROJECT="${PROJECT:-}"
REGION="${REGION:-us-central1}"
KCC_REF="${KCC_REF:-v1.160.0}"
TF_VERSION="${TF_VERSION:-1.17.1}"
CACHE_BUCKET="${CACHE_BUCKET:-gs://hfl-dev-514205-offload/catalog-inputs}"
allowed=no
for p in "${ALLOWED_PROJECTS[@]}"; do [[ "${PROJECT}" == "${p}" ]] && allowed=yes; done
[[ "${allowed}" == yes ]] || { echo "live.sh: refusing project '${PROJECT}': only ${ALLOWED_PROJECTS[*]}" >&2; exit 2; }
FIXTURES="${FIXTURES:-${OFF}/fixtures}"
[[ -d "${FIXTURES}/${SHAPE}" ]] || { echo "live.sh: no fixture ${FIXTURES}/${SHAPE}" >&2; exit 2; }
md() { curl -sf -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/$1"; }
RUNNER="$(md instance/service-accounts/default/email || true)"
[[ "${RUNNER}" == *.iam.gserviceaccount.com ]] || { echo "live.sh: not on a VM acting as a service account (got '${RUNNER}')" >&2; exit 2; }
G=(gcloud --quiet --project "${PROJECT}")
RUN="ofr-$(date -u +%m%d%H%M)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
OUT="${ROOT}/offload-artifacts/offramp/${SHAPE}-${RUN}"
mkdir -p "${OUT}"
SUMMARY="${OUT}/summary.md"
KCFG="${OUT}/kubeconfig"
TF=(terraform -chdir="${OUT}/tf")
log() { echo "== $(date -u +%H:%M:%S) $*"; }
row() { echo "| $1 | $2 | $3 |" >>"${SUMMARY}"; }
{
  echo "# Offramp live run ${RUN}: ${SHAPE}"
  echo
  echo "Project ${PROJECT}, as ${RUNNER}; Config Connector ${KCC_REF}; Terraform ${TF_VERSION}; catalog $(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown); started $(date -u +%FT%TZ)."
  echo
  echo "| Step | Result | Detail |"
  echo "| --- | --- | --- |"
} >"${SUMMARY}"

# ---- tools -------------------------------------------------------------
log "tools"
if ! command -v terraform >/dev/null || [[ "$(terraform version -json | jq -r .terraform_version)" != "${TF_VERSION}" ]]; then
  curl -sfLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  python3 -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract("terraform", "/usr/local/bin")' /tmp/tf.zip
  chmod +x /usr/local/bin/terraform
fi
KT="${ROOT}/.cache/offramp-kcc-${KCC_REF}"
OFFRAMP="${ROOT}/bin/offramp"
# Config Connector's manager and CLI, and the converter: built only once
# the Terraform has applied, so a shape that is refused stops early.
kcc_tools() {
  if [[ ! -x "${KT}/bin/realcloud" ]]; then
    mkdir -p "${KT}"
    if gcloud storage cp --quiet "${CACHE_BUCKET}/offramp-kcc-${KCC_REF}.tgz" /tmp/kt.tgz 2>/dev/null; then
      tar -xzf /tmp/kt.tgz -C "${KT}"
    else
      log "building Config Connector's manager and CLI at ${KCC_REF} (once; cached in ${CACHE_BUCKET})"
      SRC="${ROOT}/.cache/kcc-src-${KCC_REF}"
      rm -rf "${SRC}"
      git clone -q --depth 1 --branch "${KCC_REF}" https://github.com/GoogleCloudPlatform/k8s-config-connector.git "${SRC}"
      mkdir -p "${SRC}/cmd/realcloud" "${KT}/bin" "${KT}/config"
      cp "${ROOT}/hack/live/realcloud.go.txt" "${SRC}/cmd/realcloud/main.go"
      (cd "${SRC}" && GOTOOLCHAIN=auto go build -o "${KT}/bin/realcloud" ./cmd/realcloud && GOTOOLCHAIN=auto go build -o "${KT}/bin/config-connector" ./cmd/config-connector)
      cp -r "${SRC}/config/crds" "${SRC}/config/servicemappings" "${KT}/config/"
      mkdir -p "${KT}/operator-crds" && cp "${SRC}"/operator/config/crd/bases/core.cnrm.cloud.google.com_*.yaml "${KT}/operator-crds/"
      tar -czf /tmp/kt.tgz -C "${KT}" . && gcloud storage cp --quiet /tmp/kt.tgz "${CACHE_BUCKET}/offramp-kcc-${KCC_REF}.tgz" || true
    fi
  fi
  (cd "${OFF}" && go build -o "${ROOT}/bin/offramp" ./cmd/offramp)
  OFFRAMP="${ROOT}/bin/offramp"
}

# ---- cleanup -------------------------------------------------------------
cleanup() {
  local rc=$?
  set +o errexit
  log "cleanup"
  systemctl stop offramp-kcc >/dev/null 2>&1
  kind delete cluster --name offramp >/dev/null 2>&1
  if [[ -f "${OUT}/tf/terraform.tfstate" ]]; then
    for i in 1 2 3; do
      "${TF[@]}" destroy -auto-approve -input=false -no-color >"${OUT}/destroy-${i}.log" 2>&1 && { row "terraform destroy" ok "attempt ${i}"; break; }
      row "terraform destroy" "failed (attempt ${i})" "$(grep -m1 'Error' "${OUT}/destroy-${i}.log" | tr '|' '/' | cut -c1-200)"
      sleep 20
    done
    "${TF[@]}" state list >"${OUT}/left-in-state.txt" 2>/dev/null
    row "left in the state" "$(wc -l <"${OUT}/left-in-state.txt" | tr -d ' ')" "$(tr '\n' ' ' <"${OUT}/left-in-state.txt" | cut -c1-300)"
  fi
  left="$(leftovers)"
  row "left in Google Cloud named ${RUN}" "$( [[ -z "${left}" ]] && echo none || echo "${left}" | wc -l | tr -d ' ')" "$(echo "${left}" | tr '\n' ' ' | cut -c1-300)"
  echo >>"${SUMMARY}"; echo "Finished $(date -u +%FT%TZ), exit ${rc}." >>"${SUMMARY}"
  cat "${SUMMARY}"
  exit "${rc}"
}
leftovers() {
  "${G[@]}" compute networks list --filter="name~^${RUN}" --format='value(name)' 2>/dev/null
  "${G[@]}" compute networks subnets list --filter="name~^${RUN}" --format='value(name)' 2>/dev/null
  "${G[@]}" compute firewall-rules list --filter="name~^${RUN}" --format='value(name)' 2>/dev/null
  "${G[@]}" compute routes list --filter="name~^${RUN}" --format='value(name)' 2>/dev/null
  "${G[@]}" compute network-firewall-policies list --global --filter="name~^${RUN}" --format='value(name)' 2>/dev/null
  "${G[@]}" container clusters list --filter="name~^${RUN}" --format='value(name)' 2>/dev/null
  "${G[@]}" iam service-accounts list --filter="email~^${RUN}" --format='value(email)' 2>/dev/null
  if [[ -n "${PARENT:-}" ]]; then
    gcloud resource-manager folders list --folder="${PARENT#folders/}" --filter="displayName~^${RUN}" --format='value(name)' 2>/dev/null
    gcloud projects list --filter="parent.id=${PARENT#folders/} AND name~^${RUN}" --format='value(projectId)' 2>/dev/null
  fi
}
trap cleanup EXIT

# ---- 1. terraform apply --------------------------------------------------
log "1. terraform apply (${SHAPE}, prefix ${RUN})"
mkdir -p "${OUT}/tf"
cp "${FIXTURES}/${SHAPE}"/*.tf "${OUT}/tf/"
case "${SHAPE}" in
  shared-vpc)
    cat >"${OUT}/tf/terraform.tfvars" <<EOF
project_id        = "${PROJECT}"
prefix            = "${RUN}"
region            = "${REGION}"
apps_subnet_users = ["serviceAccount:${RUNNER}"]
gke_subnet_users  = ["serviceAccount:${RUNNER}"]
EOF
    ;;
  folders)
    cat >"${OUT}/tf/terraform.tfvars" <<EOF
parent          = "${PARENT:?set PARENT}"
org_id          = "${ORG_ID:?set ORG_ID}"
billing_project = "${PROJECT}"
prefix          = "${RUN}"
prod_admins     = ["serviceAccount:${RUNNER}"]
auditor         = "serviceAccount:${RUNNER}"
EOF
    ;;
  platform-project)
    cat >"${OUT}/tf/terraform.tfvars" <<EOF
folder_id       = "${PARENT#folders/}"
billing_account = "${BILLING_ACCOUNT:?set BILLING_ACCOUNT}"
prefix          = "${RUN}"
platform_admins = ["serviceAccount:${RUNNER}"]
region          = "${REGION}"
EOF
    ;;
  gke)
    cat >"${OUT}/tf/terraform.tfvars" <<EOF
project_id             = "${PROJECT}"
prefix                 = "${RUN}"
region                 = "${REGION}"
autopilot              = ${AUTOPILOT:-false}
create_service_account = false
EOF
    ;;
esac
"${TF[@]}" init -input=false -no-color >"${OUT}/init.log" 2>&1 || { row "terraform init" failed "$(grep -m1 Error "${OUT}/init.log")"; exit 1; }
"${TF[@]}" version -json >"${OUT}/terraform-version.json"
if ! "${TF[@]}" apply -auto-approve -input=false -no-color >"${OUT}/apply.log" 2>&1; then
  grep -A3 '^Error' "${OUT}/apply.log" >"${OUT}/apply-errors.txt" || true
  row "terraform apply" "**blocked**" "$(grep -m3 -oE 'Error[^│]*|Permission [^ ]+ denied[^│]*|IAM_PERMISSION_DENIED[^│]*|SERVICE_DISABLED[^│]*' "${OUT}/apply.log" | tr '\n|' '  ' | cut -c1-400)"
  exit 3
fi
row "terraform apply" ok "$(grep -oE 'Apply complete! Resources: [0-9]+ added' "${OUT}/apply.log")"
"${TF[@]}" state pull >"${OUT}/state.json"
set +o errexit
"${TF[@]}" plan -detailed-exitcode -input=false -no-color >"${OUT}/plan-before.txt" 2>&1; rc=$?
set -o errexit
row "terraform plan after apply" "$( ((rc == 0)) && echo 'no changes' || echo "exit ${rc}")" "plan-before.txt"
log "tools: Config Connector ${KCC_REF} and the converter"
kcc_tools

# ---- 2. scan and export ----------------------------------------------------
log "2. scan"
"${OFF}/hack/scan.sh" --scope "projects/${PROJECT}" --match "${RUN}" --billing-project "${PROJECT}" >"${OUT}/assets.json" 2>"${OUT}/scan.log" || true
row "scan" "$(jq length "${OUT}/assets.json" 2>/dev/null || echo 0) assets" "$(grep -m1 -E 'Cloud Asset Inventory (refused|answered)' "${OUT}/scan.log" | cut -c1-250)"
"${OFFRAMP}" names --assets "${OUT}/assets.json" >"${OUT}/names.txt" 2>"${OUT}/names-skipped.txt"
mkdir -p "${OUT}/export"
exported=0 failed=0
i=0
while read -r n; do
  i=$((i + 1))
  if "${KT}/bin/config-connector" export "${n}" --iam-format policymember --output "${OUT}/export/$(printf %03d "$i").yaml" >"${OUT}/export/$(printf %03d "$i").log" 2>&1; then
    exported=$((exported + 1))
  else
    failed=$((failed + 1)); echo "${n}: $(tail -1 "${OUT}/export/$(printf %03d "$i").log")" >>"${OUT}/export-failed.txt"
  fi
done <"${OUT}/names.txt"
row "config-connector export" "${exported} exported, ${failed} refused" "$(cut -c1-200 "${OUT}/export-failed.txt" 2>/dev/null | tr '\n|' '  ' | cut -c1-400)"

# ---- 3. convert --------------------------------------------------------------
log "3. convert"
COMMON=(--team platform --env live --target offramp-kind --namespace offramp --name "${SHAPE}" --kcc-version "${KCC_REF#v}")
"${OFFRAMP}" state --kcc "${KT}" --state "${OUT}/state.json" --out "${OUT}/from-state" "${COMMON[@]}" \
  --root "${OUT}/tf" --tfvars "${OUT}/tf/terraform.tfvars" --catalog "${ROOT}" >"${OUT}/convert-state.txt"
row "offramp state, module calls to catalog charts" ok "$(cat "${OUT}/convert-state.txt")"
awk '/^## Module calls and catalog charts/{on=1} /^## Components/{on=0} on && (/^\| `module/ || /^- /)' "${OUT}/from-state/report.md" >"${OUT}/calls.txt"
while read -r l; do row "call" "" "${l//|//}"; done <"${OUT}/calls.txt"
if compgen -G "${OUT}/export/*.yaml" >/dev/null; then
  "${OFFRAMP}" krm --krm "${OUT}/export" --out "${OUT}/from-scan" "${COMMON[@]}" >"${OUT}/convert-scan.txt"
  set +o errexit
  "${OFFRAMP}" compare "${OUT}/from-state/krm/all.yaml" "${OUT}/from-scan/krm/all.yaml" >"${OUT}/compare.txt" 2>&1; rc=$?
  set -o errexit
  row "compare state and scan" "$( ((rc == 0)) && echo same || echo "$(wc -l <"${OUT}/compare.txt" | tr -d ' ') differences")" "compare.txt"
fi

# ---- 4. kind and the objects ---------------------------------------------------
log "4. kind"
export KUBECONFIG="${KCFG}"
kind create cluster --name offramp --kubeconfig "${KCFG}" --wait 120s >"${OUT}/kind.log" 2>&1
{ for f in "${KT}"/operator-crds/*.yaml; do printf -- '---\n'; cat "$f"; done
  for g in compute iam resourcemanager orgpolicy serviceusage container; do
    for f in "${KT}"/config/crds/resources/*."${g}".cnrm.cloud.google.com.yaml; do printf -- '---\n'; cat "$f"; done
  done; } | kubectl apply --server-side --force-conflicts -f - >"${OUT}/crds.log" 2>&1
kubectl wait --for=condition=Established crd --all --timeout=180s >/dev/null
kubectl create namespace offramp
kubectl annotate namespace offramp "cnrm.cloud.google.com/project-id=${PROJECT}"
# What Bundt delivers: the graduated calls' chart renders, the frozen
# objects of any other call.
APPLY="${OUT}/from-state/krm/adopt.yaml"
kubectl apply --server-side --field-manager=bundt -n offramp -f "${APPLY}" >"${OUT}/kubectl-apply.log" 2>&1
row "objects applied (server-side, manager bundt)" "$(grep -c 'serverside-applied' "${OUT}/kubectl-apply.log")" "from-state/krm/adopt.yaml"

# ---- 5. preview ------------------------------------------------------------------
log "5. config-connector preview"
mkdir -p "${OUT}/preview"
set +o errexit
(cd "${OUT}/preview" && timeout 1200 "${KT}/bin/config-connector" preview --kubeconfig "${KCFG}" -n offramp --timeout 15 --report-prefix report --full-report >preview.log 2>&1); rc=$?
set -o errexit
rep="$(find "${OUT}/preview" -maxdepth 1 -name 'report-*' ! -name '*-full-*' ! -name '*-detail' | head -1 || true)"
if [[ -n "${rep}" ]]; then
  good="$(grep -m1 -oE 'Detected [0-9]+ good and [0-9]+ bad objects in default run' "${rep}" || echo 'no count')"
  writes=$(grep -c 'GCP_WRITE' "${rep}" || true)
  row "config-connector preview" "exit ${rc}; ${good}; GCP_WRITE ${writes}" "$(basename "${rep}")"
else
  row "config-connector preview" "exit ${rc}, no report" "$(tail -3 "${OUT}/preview/preview.log" | tr '\n|' '  ' | cut -c1-300)"
fi

# ---- 6. Config Connector adopts ---------------------------------------------------------
log "6. manager"
T0="$(date -u +%FT%TZ)"
systemd-run --unit=offramp-kcc --setenv=KUBECONFIG="${KCFG}" \
  --property=StandardOutput="file:${OUT}/manager.log" --property=StandardError="file:${OUT}/manager.log" \
  "${KT}/bin/realcloud" >/dev/null
started=no
for _ in $(seq 1 90); do
  grep -q "Starting workers" "${OUT}/manager.log" 2>/dev/null && { started=yes; break; }
  systemctl is-active --quiet offramp-kcc || break
  sleep 2
done
[[ "${started}" == yes ]] || { row "Config Connector manager" "did not start" "$(tail -5 "${OUT}/manager.log" | tr '\n|' '  ' | cut -c1-300)"; exit 1; }
deadline=$(( $(date +%s) + 900 ))
mapfile -t objs < <(kubectl get -n offramp -f "${APPLY}" -o json | jq -r '.items[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"')
for o in "${objs[@]}"; do
  left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
  kubectl wait -n offramp --for=condition=Ready "$o" --timeout="${left}s" >/dev/null 2>&1 || true
done
sleep 60 # let a second reconcile of quick kinds, and any late write, happen inside the window
kubectl get -n offramp -f "${APPLY}" -o json >"${OUT}/live-objects.json"
jq -r '.items[] | [.kind, .metadata.name, ((.status.conditions // [])[] | select(.type=="Ready") | .status + " " + .reason + " " + ((.message // "") | gsub("\\|"; "/")))] | @tsv' "${OUT}/live-objects.json" >"${OUT}/ready.tsv"
total=${#objs[@]}
uptodate=$(awk -F'\t' '$3 ~ /^True UpToDate/' "${OUT}/ready.tsv" | wc -l | tr -d ' ')
row "objects Ready, reason UpToDate" "${uptodate} of ${total}" "ready.tsv"
kubectl get events -n offramp -o json >"${OUT}/events.json"
jq -r '[.items[] | .reason] | group_by(.) | map("\(.[0]) \(length)") | join(", ")' "${OUT}/events.json" >"${OUT}/event-reasons.txt"
row "events" "$(cat "${OUT}/event-reasons.txt")" "events.json"
creates=$(grep -ciE 'creating underlying resource|creating resource|create call|Created resource' "${OUT}/manager.log" || true)
updates=$(grep -ciE 'updating underlying resource|updating resource|update call|patching|Updated resource' "${OUT}/manager.log" || true)
row "manager log: create, update lines" "${creates}, ${updates}" "manager.log"

# ---- 7. Bundt's live check ---------------------------------------------------------------
log "7. kubectl diff as bundt"
set +o errexit
kubectl diff --server-side --field-manager=bundt --force-conflicts -n offramp -f "${APPLY}" >"${OUT}/bundt-diff.txt" 2>&1; rc=$?
set -o errexit
row "server-side dry run as bundt (Bundt's live check)" "$( ((rc == 0)) && echo 'no difference' || echo "exit ${rc}: differences")" "bundt-diff.txt"

# ---- 8. terraform plan again ----------------------------------------------------------------
log "8. terraform plan"
set +o errexit
"${TF[@]}" plan -detailed-exitcode -input=false -no-color >"${OUT}/plan-after.txt" 2>&1; rc=$?
set -o errexit
row "terraform plan after adoption" "$( ((rc == 0)) && echo 'no changes' || echo "exit ${rc}")" "plan-after.txt"
T1="$(date -u +%FT%TZ)"

# ---- 9. delete the objects, keep the resources ---------------------------------------------
log "9. delete with abandon"
kubectl delete -n offramp -f "${APPLY}" --wait=true --timeout=300s >"${OUT}/kubectl-delete.log" 2>&1 || true
T2="$(date -u +%FT%TZ)"
"${G[@]}" compute networks list --filter="name~^${RUN}" --format='value(name)' >"${OUT}/kept-networks.txt" 2>/dev/null || true
row "deleted the objects (abandon): networks still there" "$(wc -l <"${OUT}/kept-networks.txt" | tr -d ' ')" "kept-networks.txt"
systemctl stop offramp-kcc || true
echo "T0=${T0} T1=${T1} T2=${T2} RUNNER=${RUNNER} RUN=${RUN}" >"${OUT}/windows.txt"

# ---- 10. audit logs ----------------------------------------------------------------------------
log "10. audit logs (they arrive within a minute or two)"
sleep 120
FILTER="logName=\"projects/${PROJECT}/logs/cloudaudit.googleapis.com%2Factivity\" AND protoPayload.authenticationInfo.principalEmail=\"${RUNNER}\" AND timestamp>=\"${T0}\" AND timestamp<=\"${T2}\""
if "${G[@]}" logging read "${FILTER}" --format=json --limit=1000 >"${OUT}/audit.json" 2>"${OUT}/audit.err"; then
  row "Admin Activity audit entries by ${RUNNER}, T0 to T2" "$(jq length "${OUT}/audit.json")" "$(jq -r '[.[] | .protoPayload.methodName] | group_by(.) | map("\(.[0]) \(length)") | join(", ")' "${OUT}/audit.json" | cut -c1-300)"
else
  row "Admin Activity audit entries" "not readable here" "$(head -c 200 "${OUT}/audit.err" | tr '\n|' '  '); read them with: gcloud logging read '${FILTER}' --project ${PROJECT}"
fi
log "done; cleanup follows"
