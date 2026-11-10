#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Scan what is in Google Cloud at a scope and write it as a JSON array of
# Cloud Asset Inventory assets (name, assetType, ancestors,
# resource.data), the input of `offramp names` and then
# `config-connector export`.
#
#   scan.sh --scope projects/<id>|folders/<n>|organizations/<n> [--match REGEX] [--billing-project P] > assets.json
#
# First it asks Cloud Asset Inventory (`gcloud asset list`), which needs
# the Cloud Asset API enabled on the billing project and
# roles/cloudasset.viewer on the scope. When that is refused it falls back
# to the services' own list calls for the asset types the four offramp
# shapes hold, and writes the same fields, each record's `source` naming
# the call. The fallback covers a project (networks, subnetworks,
# firewalls, routes, network firewall policies, service accounts, enabled
# services, GKE clusters) or a folder (its folders, organization policies
# and hierarchical firewall policies, and the projects directly in it).
#
# --match keeps only assets whose resource name matches REGEX (a live run's
# prefix), so a scan of a shared project never reads beyond the run.
# Progress and the reason for a fallback go to stderr.
set -o errexit -o nounset -o pipefail

SCOPE="" MATCH="" BILLING=""
while (($#)); do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --match) MATCH="$2"; shift 2 ;;
    --billing-project) BILLING="$2"; shift 2 ;;
    *) echo "scan.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ "${SCOPE}" =~ ^(projects|folders|organizations)/[a-z0-9-]+$ ]] || { echo "scan.sh: --scope projects/<id>, folders/<n> or organizations/<n>" >&2; exit 2; }
kind="${SCOPE%%/*}" id="${SCOPE#*/}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

filter() { # keep assets whose name matches MATCH
  if [[ -n "${MATCH}" ]]; then jq --arg m "${MATCH}" '[.[] | select(.name | test($m))]'; else cat; fi
}

# 1. Cloud Asset Inventory.
scope_flag=(--project "${id}")
[[ "${kind}" == folders ]] && scope_flag=(--folder "${id}")
[[ "${kind}" == organizations ]] && scope_flag=(--organization "${id}")
bp=()
[[ -n "${BILLING}" ]] && bp=(--billing-project "${BILLING}")
if gcloud asset list "${scope_flag[@]}" "${bp[@]}" --content-type=resource --format=json >"${TMP}/cai.json" 2>"${TMP}/cai.err"; then
  echo "scan: Cloud Asset Inventory answered for ${SCOPE}" >&2
  jq '[.[] | . + {source: "cloudasset"}]' "${TMP}/cai.json" | filter
  exit 0
fi
echo "scan: Cloud Asset Inventory refused (${SCOPE}): $(grep -m1 -oE '(PERMISSION_DENIED|SERVICE_DISABLED|has not been used|does not have)[^.]*' "${TMP}/cai.err" || head -c 300 "${TMP}/cai.err")" >&2
echo "scan: falling back to the services' list calls" >&2

# 2. The fallback. Each list call's JSON becomes assets of one type; a call
# that is refused is reported and skipped.
emit() { # emit ASSET_TYPE NAME_PREFIX SOURCE < json-array
  jq --arg t "$1" --arg p "$2" --arg s "$3" --arg anc "${SCOPE}" \
    '[.[] | {name: ($p + (.selfLink // .name // .email // .config.name // "" | sub("^https://www.googleapis.com/compute/v1/"; "") | sub("^https://compute.googleapis.com/compute/v1/"; ""))),
             assetType: $t, ancestors: [$anc], resource: {data: .}, source: $s}]'
}
list() { # list FILE SOURCE CMD... : run a list call, keep its output or an empty list
  local f="$1" src="$2"; shift 2
  if "$@" --format=json >"${f}" 2>"${f}.err"; then
    echo "scan: ${src}: $(jq length "${f}")" >&2
  else
    echo "scan: ${src} refused: $(grep -m1 -oE '(PERMISSION_DENIED|SERVICE_DISABLED|has not been used|does not have|Required)[^.]*' "${f}.err" || head -c 200 "${f}.err")" >&2
    echo '[]' >"${f}"
  fi
}
parts=()
if [[ "${kind}" == projects ]]; then
  G=(gcloud --quiet --project "${id}")
  list "${TMP}/net.json" compute.networks.list "${G[@]}" compute networks list
  emit compute.googleapis.com/Network //compute.googleapis.com/ compute.networks.list <"${TMP}/net.json" >"${TMP}/a1.json"; parts+=("${TMP}/a1.json")
  list "${TMP}/sub.json" compute.subnetworks.list "${G[@]}" compute networks subnets list
  emit compute.googleapis.com/Subnetwork //compute.googleapis.com/ compute.subnetworks.list <"${TMP}/sub.json" >"${TMP}/a2.json"; parts+=("${TMP}/a2.json")
  list "${TMP}/fw.json" compute.firewalls.list "${G[@]}" compute firewall-rules list
  emit compute.googleapis.com/Firewall //compute.googleapis.com/ compute.firewalls.list <"${TMP}/fw.json" >"${TMP}/a3.json"; parts+=("${TMP}/a3.json")
  list "${TMP}/rt.json" compute.routes.list "${G[@]}" compute routes list
  emit compute.googleapis.com/Route //compute.googleapis.com/ compute.routes.list <"${TMP}/rt.json" >"${TMP}/a4.json"; parts+=("${TMP}/a4.json")
  list "${TMP}/nfp.json" compute.networkFirewallPolicies.list "${G[@]}" compute network-firewall-policies list --global
  emit compute.googleapis.com/FirewallPolicy //compute.googleapis.com/ compute.networkFirewallPolicies.list <"${TMP}/nfp.json" >"${TMP}/a5.json"; parts+=("${TMP}/a5.json")
  list "${TMP}/sa.json" iam.serviceAccounts.list "${G[@]}" iam service-accounts list
  jq --arg p "${id}" --arg anc "${SCOPE}" '[.[] | {name: ("//iam.googleapis.com/projects/" + $p + "/serviceAccounts/" + .uniqueId), assetType: "iam.googleapis.com/ServiceAccount", ancestors: [$anc], resource: {data: .}, source: "iam.serviceAccounts.list"}]' \
    <"${TMP}/sa.json" >"${TMP}/a6.json"; parts+=("${TMP}/a6.json")
  list "${TMP}/gke.json" container.clusters.list "${G[@]}" container clusters list
  jq --arg p "${id}" --arg anc "${SCOPE}" '[.[] | {name: ("//container.googleapis.com/projects/" + $p + "/locations/" + .location + "/clusters/" + .name), assetType: "container.googleapis.com/Cluster", ancestors: [$anc], resource: {data: .}, source: "container.clusters.list"}]' \
    <"${TMP}/gke.json" >"${TMP}/a7.json"; parts+=("${TMP}/a7.json")
else
  # A folder: its child folders, its organization policies, its
  # hierarchical firewall policies and the projects directly in it.
  list "${TMP}/fo.json" cloudresourcemanager.folders.list gcloud resource-manager folders list "--${kind%s}=${id}"
  jq --arg anc "${SCOPE}" '[.[] | {name: ("//cloudresourcemanager.googleapis.com/" + .name), assetType: "cloudresourcemanager.googleapis.com/Folder", ancestors: [$anc], resource: {data: .}, source: "cloudresourcemanager.folders.list"}]' \
    <"${TMP}/fo.json" >"${TMP}/b1.json"; parts+=("${TMP}/b1.json")
  list "${TMP}/op.json" orgpolicy.policies.list gcloud org-policies list "--${kind%s}=${id}" --show-unset=false
  jq --arg anc "${SCOPE}" --arg sc "${SCOPE}" '[.[] | {name: ("//orgpolicy.googleapis.com/" + $sc + "/policies/" + (.constraint | sub("^constraints/"; ""))), assetType: "orgpolicy.googleapis.com/Policy", ancestors: [$anc], resource: {data: .}, source: "orgpolicy.policies.list"}]' \
    <"${TMP}/op.json" >"${TMP}/b2.json"; parts+=("${TMP}/b2.json")
  list "${TMP}/hfp.json" compute.firewallPolicies.list gcloud compute firewall-policies list "--${kind%s}=${id}"
  jq --arg anc "${SCOPE}" '[.[] | {name: ("//compute.googleapis.com/locations/global/firewallPolicies/" + .name), assetType: "compute.googleapis.com/FirewallPolicy", ancestors: [$anc], resource: {data: .}, source: "compute.firewallPolicies.list"}]' \
    <"${TMP}/hfp.json" >"${TMP}/b3.json"; parts+=("${TMP}/b3.json")
  list "${TMP}/pr.json" cloudresourcemanager.projects.list gcloud projects list --filter="parent.id=${id}"
  jq --arg anc "${SCOPE}" '[.[] | {name: ("//cloudresourcemanager.googleapis.com/projects/" + .projectNumber), assetType: "cloudresourcemanager.googleapis.com/Project", ancestors: [$anc], resource: {data: .}, source: "cloudresourcemanager.projects.list"}]' \
    <"${TMP}/pr.json" >"${TMP}/b4.json"; parts+=("${TMP}/b4.json")
fi
jq -s 'add // []' "${parts[@]}" | filter
