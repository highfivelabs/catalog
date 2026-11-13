#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Apply the Azure charts (avm-res-network-virtualnetwork,
# avm-res-storage-storageaccount, avm-res-keyvault-vault,
# avm-res-network-networksecuritygroup, avm-res-network-routetable,
# avm-res-network-natgateway, avm-res-network-publicipaddress,
# avm-res-network-privatednszone,
# avm-res-managedidentity-userassignedidentity,
# avm-res-operationalinsights-workspace, avm-res-containerregistry-registry,
# avm-res-network-firewallpolicy,
# avm-res-network-loadbalancer,
# avm-res-network-bastionhost,
# avm-res-insights-component,
# avm-res-dbforpostgresql-flexibleserver,
# avm-res-network-privateendpoint,
# avm-res-network-applicationgateway,
# avm-res-cognitiveservices-account,
# avm-res-app-containerapp)
# to the Azure
# sandbox with tiny resources, check their outputs, delete them, and check
# Azure no longer has them (docs/azure.md, "8. Charts", Testing).
# AZURE_LIVE_CASES (space-separated: vnet storage kv nsg rt natgw pip dns
# uai law acr fwp lb bas appi psql pe appgw cog ca)
# applies only those; the default is all. A case may first apply another
# chart it needs (PRE: the application gateway's virtual network and
# subnet), or ASO objects of no chart (CASE-pre.objects.yaml: the container
# app's environment), deleted after the case's own objects are gone. Only on
# an offload VM acting as the service account the sandbox identity trusts
# (keyless federation, as aso-extensions' live runs: its docs/live-runs.md);
# `task test-live-azure` runs it:
#
#   ../scripts/offload/offload run --sa "$AZURE_LIVE_SA" --hours 2 -- \
#     env AZURE_SUBSCRIPTION_ID=... AZURE_TENANT_ID=... AZURE_CLIENT_ID=... \
#     AZURE_LIVE_RESOURCE_GROUP=... ASOX_TARBALL=gs://.../asox-<commit>.tar.gz \
#     hack/azure-live.sh
#
# How: a kind cluster runs Azure Service Operator v2.22.0 from its own Helm
# chart (with cert-manager for its webhooks, which convert between CRD
# versions), its credential the Google ID token of the VM's service
# account, which Entra exchanges for the sandbox identity (workload
# identity: the token file, refreshed every 20 minutes, is mounted where
# ASO reads it). Beside ASO, aso-extensions' manager (hack/asox-manager.sh,
# from ASOX_TARBALL or ASOX_DIR) reconciles the charts' aso-extensions kinds
# with the same token. The identity is Contributor on one resource group,
# so the resource group chart (subscription scope) and the lock (writing
# Microsoft.Authorization/locks needs Owner or User Access Administrator)
# are not applied here.
#
# Rules: one resource group (AZURE_LIVE_RESOURCE_GROUP); every name starts
# with this run's ID (cat<month day hour minute><4 hex>) and every resource
# that takes tags carries catalog-run=<run ID>; the test deletes what it
# makes, checks Azure answers 404, and at the end deletes anything of this
# run still there and lists what of any catalog run is left. A deleted
# Cognitive Services account stays soft-deleted for 48 hours; the test
# tries to purge it and logs Azure's answer (403 when the identity may
# not). A key vault
# stays soft-deleted for 7 days after its delete (purging needs a
# subscription-scope right the identity does not have); its name is the
# run's, so nothing collides. Writes offload-artifacts/azure-live/.
set -o errexit -o nounset -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
: "${AZURE_SUBSCRIPTION_ID:?set AZURE_SUBSCRIPTION_ID (.env.example)}"
: "${AZURE_TENANT_ID:?set AZURE_TENANT_ID (.env.example)}"
: "${AZURE_CLIENT_ID:?set AZURE_CLIENT_ID (.env.example)}"
: "${AZURE_LIVE_RESOURCE_GROUP:?set AZURE_LIVE_RESOURCE_GROUP (.env.example)}"
ASO_VERSION="$(sed -n 's/^| Azure Service Operator release | `v\([0-9.]*\)`.*/\1/p' UPSTREAM.md)"
CERT_MANAGER_VERSION=v1.15.3
LOCATION="${AZURE_LIVE_LOCATION:-eastus2}"
TIMEOUT="${LIVE_TIMEOUT:-900}"
# cog is not in the default: the sandbox subscription has not registered
# Microsoft.CognitiveServices, and registering a provider is a
# subscription-scope action the identity may not take (docs/azure.md).
CASES="${AZURE_LIVE_CASES:-vnet storage kv nsg rt natgw pip dns uai law acr fwp lb bas appi psql pe appgw ca}"
OUT="${ROOT}/offload-artifacts/azure-live"
WORK="$(mktemp -d)"
CLUSTER=catalog-azure-live
NS=catalog-live
ARM=https://management.azure.com
RG="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_LIVE_RESOURCE_GROUP}"
mkdir -p "${OUT}"

for t in docker kind kubectl helm go jq curl; do
  command -v "$t" >/dev/null || { echo "azure-live: $t is not installed" >&2; exit 2; }
done
md() { curl -sf -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/$1"; }
RUNNER="$(md instance/service-accounts/default/email || true)"
[[ "${RUNNER}" == *.iam.gserviceaccount.com ]] || { echo "azure-live: not on a VM acting as a service account (got '${RUNNER}')" >&2; exit 2; }
# Federated credentials only.
unset AZURE_CLIENT_SECRET AZURE_CLIENT_CERTIFICATE AZURE_CLIENT_CERTIFICATE_PATH \
  AZURE_CLIENT_CERTIFICATE_PASSWORD AZURE_USERNAME AZURE_PASSWORD

RUN="cat$(date -u +%m%d%H%M)$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
echo "== live run ${RUN} in resource group ${AZURE_LIVE_RESOURCE_GROUP} as ${RUNNER}"

# The Google ID token Entra exchanges; ASO's global workload identity
# credential reads it from /var/run/secrets/tokens/azure-identity (its
# default, identity.FederatedTokenFilePath).
TOKENS="${WORK}/tokens"
mkdir -p "${TOKENS}"
# ASO runs as a non-root user: it must reach the file through the mount.
chmod 755 "${WORK}" "${TOKENS}"
google_token() { md "instance/service-accounts/default/identity?audience=api://AzureADTokenExchange&format=full"; }
google_token >"${TOKENS}/t.new" && mv "${TOKENS}/t.new" "${TOKENS}/azure-identity"
chmod 644 "${TOKENS}/azure-identity"
( while sleep 1200; do google_token >"${TOKENS}/t.new" && chmod 644 "${TOKENS}/t.new" && mv "${TOKENS}/t.new" "${TOKENS}/azure-identity"; done ) &
refresher=$!

arm_token() {
  curl -fsS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
    --data-urlencode "client_id=${AZURE_CLIENT_ID}" \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode 'scope=https://management.azure.com/.default' \
    --data-urlencode 'client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer' \
    --data-urlencode "client_assertion=$(cat "${TOKENS}/azure-identity")" | jq -er .access_token
}
api() { curl -sS -H "Authorization: Bearer $(arm_token)" "$@"; }
# run_resources PREFIX...: id and type of each top-level resource in the
# group whose name starts with one of the prefixes.
run_resources() {
  api "${ARM}${RG}/resources?api-version=2021-04-01" | jq -r --args '.value[] | select(.name as $n | $ARGS.positional | any(. as $p | $n | startswith($p))) | "\(.id) \(.type)"' "$@"
}
sweep() { # sweep PREFIX: delete what this run left in the group
  local id type ns rtype v
  run_resources "$1" | while read -r id type; do
    ns="${type%%/*}" rtype="${type#*/}"
    v="$(api "${ARM}/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/${ns}?api-version=2021-04-01" \
      | jq -r --arg t "${rtype}" '.resourceTypes[] | select((.resourceType|ascii_downcase) == ($t|ascii_downcase)) | .apiVersions | map(select(test("preview")|not)) | .[0] // empty')"
    echo "   sweep: delete ${type} ${id##*/}: $(api -o /dev/null -w '%{http_code}' -X DELETE "${ARM}${id}?api-version=${v}")"
  done
}
cleanup() {
  kill "${refresher}" 2>/dev/null || true
  sweep "${RUN}" || true
  kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true
  rm -rf "${WORK}"
}
trap cleanup EXIT
# shellcheck source=hack/asox-manager.sh
source "${ROOT}/hack/asox-manager.sh"
asox_fetch "${WORK}"
asox_build_manager "${WORK}"
arm_token >/dev/null || { echo "azure-live: Entra refused the federated token" >&2; exit 1; }
echo "== Entra issued a Resource Manager token for ${AZURE_CLIENT_ID}"

# kind, with the token directory on the node.
cat >"${WORK}/kind.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: ${TOKENS}
        containerPath: /azure-tokens
        readOnly: true
EOF
kind create cluster --name "${CLUSTER}" --config "${WORK}/kind.yaml" --wait 180s
export KUBECONFIG="${WORK}/kubeconfig"
kind get kubeconfig --name "${CLUSTER}" >"${KUBECONFIG}"

echo "== cert-manager ${CERT_MANAGER_VERSION}, Azure Service Operator v${ASO_VERSION}"
helm install cert-manager cert-manager --repo https://charts.jetstack.io --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m >/dev/null
helm install aso azure-service-operator --repo https://raw.githubusercontent.com/Azure/azure-service-operator/main/v2/charts \
  --version "v${ASO_VERSION}" --namespace azureserviceoperator-system --create-namespace \
  --set azureSubscriptionID="${AZURE_SUBSCRIPTION_ID}" --set azureTenantID="${AZURE_TENANT_ID}" \
  --set azureClientID="${AZURE_CLIENT_ID}" --set useWorkloadIdentityAuth=true \
  --set crdPattern="$(asox_crd_pattern 'network.azure.com/*;storage.azure.com/*;keyvault.azure.com/*;authorization.azure.com/*;insights.azure.com/*;managedidentity.azure.com/*;operationalinsights.azure.com/*;containerregistry.azure.com/*;dbforpostgresql.azure.com/*;cognitiveservices.azure.com/*')" \
  --timeout 10m >/dev/null
# The token where ASO reads it: the chart projects a Kubernetes service
# account token into /var/run/secrets/tokens (Azure Workload Identity's
# shape, for AKS); kind's issuer is not federated, so the volume becomes
# the node's directory holding the Google ID token instead.
kubectl -n azureserviceoperator-system patch deployment azureserviceoperator-controller-manager --type strategic -p '{
  "spec": {"template": {"spec": {"volumes": [
    {"name": "azure-identity", "projected": null, "hostPath": {"path": "/azure-tokens", "type": "Directory"}}
  ]}}}}' >/dev/null
kubectl -n azureserviceoperator-system rollout status deployment azureserviceoperator-controller-manager --timeout 10m
for crd in virtualnetworks.network.azure.com virtualnetworkssubnets.network.azure.com storageaccounts.storage.azure.com \
    storageaccountsblobservicescontainers.storage.azure.com storageaccountsqueueservicesqueues.storage.azure.com vaults.keyvault.azure.com \
    networksecuritygroups.network.azure.com networksecuritygroupssecurityrules.network.azure.com routetables.network.azure.com \
    routetablesroutes.network.azure.com natgateways.network.azure.com publicipaddresses.network.azure.com \
    privatednszones.network.azure.com privatednszonesarecords.network.azure.com privatednszonestxtrecords.network.azure.com \
    privatednszonesvirtualnetworklinks.network.azure.com userassignedidentities.managedidentity.azure.com \
    federatedidentitycredentials.managedidentity.azure.com workspaces.operationalinsights.azure.com \
    registries.containerregistry.azure.com registrycacherules.containerregistry.azure.com \
    firewallpolicies.network.azure.com firewallpoliciesrulecollectiongroups.network.azure.com \
    loadbalancers.network.azure.com \
    bastionhosts.network.azure.com \
    components.insights.azure.com pricingplans.insights.azure.com \
    flexibleservers.dbforpostgresql.azure.com flexibleserversdatabases.dbforpostgresql.azure.com \
    flexibleserversfirewallrules.dbforpostgresql.azure.com flexibleserversconfigurations.dbforpostgresql.azure.com \
    flexibleserversadministrators.dbforpostgresql.azure.com \
    privateendpoints.network.azure.com privateendpointsprivatednszonegroups.network.azure.com \
    accounts.cognitiveservices.azure.com \
    managedenvironments.app.azure.com containerapps.app.azure.com; do
  for _ in $(seq 60); do kubectl get crd "${crd}" >/dev/null 2>&1 && break; sleep 5; done
  kubectl wait --for=condition=Established "crd/${crd}" --timeout=120s >/dev/null
done
echo "== aso-extensions' manager beside ASO, from ${ASOX_TARBALL:-${ASOX_DIR}}"
# Its token where ASO's credential reads it: the node's directory holding
# the Google ID token, as ASO's.
asox_install_manager "${CLUSTER}" '{
  "spec": {"template": {"spec": {
    "volumes": [{"name": "azure-identity", "hostPath": {"path": "/azure-tokens", "type": "Directory"}}],
    "containers": [{"name": "manager",
      "volumeMounts": [{"name": "azure-identity", "mountPath": "/var/run/secrets/tokens", "readOnly": true}]}]}}}}'
kubectl create namespace "${NS}" >/dev/null
(cd tools && go build -o "${ROOT}/bin/catalogtool" ./catalogtool)

# The cases: each chart's smallest useful Instance, named for the run.
cat >"${WORK}/vnet.yaml" <<EOF
name: ${RUN}-vnet
location: ${LOCATION}
parent_id: ${RG}
address_space: [10.250.0.0/24]
tags: {catalog-run: ${RUN}}
subnets:
  a: {name: snet-a, address_prefix: 10.250.0.0/26}
EOF
cat >"${WORK}/storage.yaml" <<EOF
name: ${RUN}
location: ${LOCATION}
parent_id: ${RG}
account_sku_name: Standard_LRS
account_replication_type: LRS
tags: {catalog-run: ${RUN}}
containers:
  a: {name: assets}
queues:
  q: {name: jobs}
EOF
cat >"${WORK}/kv.yaml" <<EOF
name: ${RUN}-kv
location: ${LOCATION}
parent_id: ${RG}
tenant_id: ${AZURE_TENANT_ID}
sku_name: standard
purge_protection_enabled: false
soft_delete_retention_days: 7
tags: {catalog-run: ${RUN}}
EOF
cat >"${WORK}/nsg.yaml" <<EOF
name: ${RUN}-nsg
location: ${LOCATION}
parent_id: ${RG}
tags: {catalog-run: ${RUN}}
security_rules:
  ssh: {name: allow-ssh, access: Allow, direction: Inbound, priority: 100, protocol: Tcp, source_address_prefix: 10.0.0.0/8, source_port_range: "*", destination_address_prefix: "*", destination_port_range: "22"}
  out: {name: deny-internet, access: Deny, direction: Outbound, priority: 4000, protocol: "*", source_address_prefix: "*", source_port_range: "*", destination_address_prefix: Internet, destination_port_range: "*"}
EOF
cat >"${WORK}/rt.yaml" <<EOF
name: ${RUN}-rt
location: ${LOCATION}
resource_group_name: ${AZURE_LIVE_RESOURCE_GROUP}
subscription_id: ${AZURE_SUBSCRIPTION_ID}
bgp_route_propagation_enabled: false
tags: {catalog-run: ${RUN}}
routes:
  local: {name: local, address_prefix: 10.250.0.0/24, next_hop_type: VnetLocal}
  nva: {name: to-nva, address_prefix: 0.0.0.0/0, next_hop_type: VirtualAppliance, next_hop_in_ip_address: 10.250.0.4}
EOF
# A Standard (regional) gateway with a regional Standard address: the
# smallest shape every region has.
cat >"${WORK}/natgw.yaml" <<EOF
name: ${RUN}-natgw
location: ${LOCATION}
parent_id: ${RG}
sku_name: Standard
tags: {catalog-run: ${RUN}}
public_ips:
  a: {name: ${RUN}-natgw-pip}
public_ip_configuration:
  a: {sku: Standard, zones: []}
EOF
cat >"${WORK}/pip.yaml" <<EOF
name: ${RUN}-pip
location: ${LOCATION}
resource_group_name: ${RG}
tags: {catalog-run: ${RUN}}
EOF
# A zone named for the run, with an A and a TXT record and no link (a
# link needs a network of the run; the network chart is its own case).
cat >"${WORK}/dns.yaml" <<EOF
domain_name: ${RUN}.catalog.internal
parent_id: ${RG}
tags: {catalog-run: ${RUN}}
a_records:
  app: {name: app, ttl: 60, ip_addresses: [10.250.0.10]}
txt_records:
  owner: {name: "@", ttl: 60, records: {a: {value: [catalog-run=${RUN}]}}}
EOF
# An identity with a federated credential; no outbound role assignment
# (the live identity may not assign roles).
cat >"${WORK}/uai.yaml" <<EOF
name: ${RUN}-uai
location: ${LOCATION}
resource_group_name: ${AZURE_LIVE_RESOURCE_GROUP}
subscription_id: ${AZURE_SUBSCRIPTION_ID}
tags: {catalog-run: ${RUN}}
federated_identity_credentials:
  gh: {name: gh-main, audience: [api://AzureADTokenExchange], issuer: https://token.actions.githubusercontent.com, subject: "repo:highfivelabs/catalog:ref:refs/heads/main"}
EOF
# A workspace at the smallest retention its SKU takes, with a diagnostic
# setting to itself (the module's default destination).
cat >"${WORK}/law.yaml" <<EOF
name: ${RUN}-law
location: ${LOCATION}
resource_group_name: ${RG}
log_analytics_workspace_retention_in_days: 30
tags: {catalog-run: ${RUN}}
diagnostic_settings:
  self: {log_groups: [audit], metric_categories: []}
EOF
# A Basic registry (the cheapest; no zone redundancy below Premium) with a
# cache rule for an anonymous MCR image (Docker Hub needs credentials). Its
# name is letters and digits.
cat >"${WORK}/acr.yaml" <<EOF
name: ${RUN}acr
location: ${LOCATION}
resource_group_name: ${RG}
sku: Basic
zone_redundancy_enabled: false
tags: {catalog-run: ${RUN}}
cache_rules:
  mcr: {name: mcr-busybox, source_repository: mcr.microsoft.com/azurelinux/busybox, target_repository: cache/busybox}
EOF
# A Basic policy (the cheapest tier) with one rule collection group: a
# network rule collection and an application rule collection.
cat >"${WORK}/fwp.yaml" <<EOF
name: ${RUN}-fwp
location: ${LOCATION}
resource_group_name: ${AZURE_LIVE_RESOURCE_GROUP}
subscription_id: ${AZURE_SUBSCRIPTION_ID}
firewall_policy_sku: Basic
firewall_policy_threat_intelligence_mode: Alert
tags: {catalog-run: ${RUN}}
rule_collection_groups:
  core:
    name: rcg-core
    priority: 200
    network_rule_collection:
      - name: dns
        priority: 400
        action: Allow
        rule:
          - {name: dns, protocols: [UDP, TCP], source_addresses: [10.250.0.0/24], destination_addresses: [168.63.129.16], destination_ports: ["53"]}
    application_rule_collection:
      - name: web
        priority: 500
        action: Allow
        rule:
          - {name: microsoft, source_addresses: [10.250.0.0/24], destination_fqdns: ["*.microsoft.com"], protocols: [{type: Https, port: 443}]}
EOF
# A public Standard load balancer with a regional (zoneless) public IP the
# chart makes: a pool, a TCP probe, a rule, a NAT rule and an outbound rule
# on the one frontend (the rule leaves outbound SNAT to the outbound rule).
# No backends: nothing is reachable, and an empty pool costs nothing more.
cat >"${WORK}/lb.yaml" <<EOF
name: ${RUN}-lb
location: ${LOCATION}
resource_group_name: ${AZURE_LIVE_RESOURCE_GROUP}
subscription_id: ${AZURE_SUBSCRIPTION_ID}
tags: {catalog-run: ${RUN}}
frontend_ip_configurations:
  pub: {name: fe-public, create_public_ip_address: true, public_ip_address_resource_name: ${RUN}-lb-pip, zones: [None]}
backend_address_pools:
  web: {name: be-web}
lb_probes:
  tcp: {name: probe-tcp, protocol: Tcp, port: 80}
lb_rules:
  http: {name: rule-http, frontend_ip_configuration_name: fe-public, backend_address_pool_object_names: [web], frontend_port: 80, backend_port: 80, probe_object_name: tcp, disable_outbound_snat: true}
lb_nat_rules:
  ssh: {name: nat-ssh, frontend_ip_configuration_name: fe-public, protocol: Tcp, frontend_port: 2222, backend_port: 22}
lb_outbound_rules:
  out: {name: outbound-web, frontend_ip_configurations: [{name: fe-public}], backend_address_pool_object_name: web}
EOF
# A Basic bastion host with the zoneless public IP it makes, in an
# AzureBastionSubnet (/26, Azure's smallest for it) of a network of the run
# that the case also applies (CASE.network.yaml: the network chart's
# values, rendered into the case, so it is made first, waited for, deleted
# and checked gone with it).
cat >"${WORK}/bas.yaml" <<EOF
name: ${RUN}-bas
location: ${LOCATION}
parent_id: ${RG}
sku: Basic
zones: []
tags: {catalog-run: ${RUN}}
ip_configuration:
  subnet_id: ${RG}/providers/Microsoft.Network/virtualNetworks/${RUN}-bas-vnet/subnets/AzureBastionSubnet
  public_ip_address_name: ${RUN}-bas-pip
EOF
cat >"${WORK}/bas.network.yaml" <<EOF
name: ${RUN}-bas-vnet
location: ${LOCATION}
parent_id: ${RG}
address_space: [10.251.0.0/24]
tags: {catalog-run: ${RUN}}
subnets:
  bastion: {name: AzureBastionSubnet, address_prefix: 10.251.0.0/26}
EOF
# A workspace-based component (classic ones are retired) with a 1 GB daily
# cap; the case makes its workspace first (appi.pre.yaml, an ASO Workspace
# applied and deleted with the chart's objects; hfl.dev/id live-workspace).
cat >"${WORK}/appi.yaml" <<EOF
name: ${RUN}-appi
location: ${LOCATION}
parent_id: ${RG}
workspace_id: ${RG}/providers/Microsoft.OperationalInsights/workspaces/${RUN}-appi-law
daily_data_cap_in_gb: 1
retention_in_days: 30
tags: {catalog-run: ${RUN}}
EOF
cat >"${WORK}/appi.pre.yaml" <<EOF
---
apiVersion: operationalinsights.azure.com/v20250701
kind: Workspace
metadata:
  name: appi-live-law
  annotations: {hfl.dev/id: live-workspace}
spec:
  azureName: ${RUN}-appi-law
  location: ${LOCATION}
  owner: {armId: ${RG}}
  retentionInDays: 30
  sku: {name: PerGB2018}
  tags: {catalog-run: ${RUN}}
EOF
# The smallest server (Burstable B1ms, 32 GiB, no high availability), Entra
# authentication only (the chart takes no password), with a database, a
# firewall rule for one documentation address (TEST-NET-3), a server
# parameter and the live identity itself as its Entra administrator (a
# PostgreSQL role on this server, not an Azure role assignment; its object
# ID is the oid of the identity's own token). AZURE_LIVE_PSQL_LOCATION
# overrides the region (PostgreSQL is offered per region per subscription).
SP_OID="$(arm_token | cut -d. -f2 | tr '_-' '/+' | awk '{ n = length($0) % 4; if (n) $0 = $0 substr("===", 1, 4 - n); print }' | base64 -d | jq -er .oid)"
cat >"${WORK}/psql.yaml" <<EOF
name: ${RUN}-psql
location: ${AZURE_LIVE_PSQL_LOCATION:-${LOCATION}}
resource_group_name: ${RG}
sku_name: B_Standard_B1ms
server_version: "16"
storage_mb: 32768
high_availability: null
maintenance_window: null
public_network_access_enabled: true
authentication: {active_directory_auth_enabled: true, password_auth_enabled: false, tenant_id: ${AZURE_TENANT_ID}}
tags: {catalog-run: ${RUN}}
databases:
  app: {name: app}
firewall_rules:
  doc: {name: doc-net, start_ip_address: 203.0.113.10, end_ip_address: 203.0.113.10}
server_configuration:
  slow: {name: log_min_duration_statement, config: "1000"}
ad_administrator:
  live: {tenant_id: ${AZURE_TENANT_ID}, object_id: ${SP_OID}, principal_name: aso-extensions-live-tests, principal_type: ServicePrincipal}
EOF
# A private endpoint to the blob service of a storage account of the run,
# in a subnet of a network of the run, with a DNS zone group in the blob
# service's private DNS zone: the case applies those with it
# (CASE.with.CHART.yaml: that chart's values, rendered into the case, so
# they are made, waited for, deleted and checked gone with it). The zone's
# name is Azure's, not the run's: the case stops if the group has one.
cat >"${WORK}/pe.yaml" <<EOF
name: ${RUN}-pe
location: ${LOCATION}
parent_id: ${RG}
network_interface_name: ${RUN}-pe-nic
private_connection_resource_id: ${RG}/providers/Microsoft.Storage/storageAccounts/${RUN}pe
subnet_resource_id: ${RG}/providers/Microsoft.Network/virtualNetworks/${RUN}-pe-vnet/subnets/snet-pe
subresource_names: [blob]
private_dns_zone_resource_ids: [${RG}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net]
tags: {catalog-run: ${RUN}}
EOF
cat >"${WORK}/pe.with.avm-res-network-virtualnetwork.yaml" <<EOF
name: ${RUN}-pe-vnet
location: ${LOCATION}
parent_id: ${RG}
address_space: [10.252.0.0/24]
tags: {catalog-run: ${RUN}}
subnets:
  pe: {name: snet-pe, address_prefix: 10.252.0.0/27}
EOF
cat >"${WORK}/pe.with.avm-res-storage-storageaccount.yaml" <<EOF
name: ${RUN}pe
location: ${LOCATION}
parent_id: ${RG}
account_sku_name: Standard_LRS
account_replication_type: LRS
tags: {catalog-run: ${RUN}}
EOF
cat >"${WORK}/pe.with.avm-res-network-privatednszone.yaml" <<EOF
domain_name: privatelink.blob.core.windows.net
parent_id: ${RG}
tags: {catalog-run: ${RUN}}
EOF
# A Standard_v2 application gateway of capacity 1 (the smallest v2 shape:
# about 0.25 USD an hour) on a subnet of its own, which the case makes first
# with the virtual network chart (PRE), and a regional Standard public IP
# the chart makes: a pool, HTTP settings with a probe, a listener on port
# 80 and a basic rule, every reference by key. No backends: nothing is
# reachable. A v2 gateway takes several minutes to create and to delete,
# hence its longer time limit (CASE_TIMEOUT).
cat >"${WORK}/appgw-pre.yaml" <<EOF
name: ${RUN}-agw-vnet
location: ${LOCATION}
parent_id: ${RG}
address_space: [10.251.0.0/24]
tags: {catalog-run: ${RUN}}
subnets:
  agw: {name: snet-appgw, address_prefix: 10.251.0.0/26}
EOF
cat >"${WORK}/appgw.yaml" <<EOF
name: ${RUN}-agw
location: ${LOCATION}
parent_id: ${RG}
tags: {catalog-run: ${RUN}}
sku: {name: Standard_v2, tier: Standard_v2, capacity: 1}
public_ip_addresses:
  pub: {name: ${RUN}-agw-pip, zones: []}
gateway_ip_configurations:
  - {name: gw-ip, subnet: {id: ${RG}/providers/Microsoft.Network/virtualNetworks/${RUN}-agw-vnet/subnets/snet-appgw}}
frontend_ip_configurations:
  - {name: fe-public, public_ip_address_key: pub}
frontend_ports:
  - {name: port-80, port: 80}
backend_address_pools:
  - {name: pool-web}
probes:
  - {name: probe-http, protocol: Http, host: 127.0.0.1, path: /, interval: 30, timeout: 30, unhealthy_threshold: 3}
backend_http_settings_collection:
  - {name: http-80, port: 80, protocol: Http, cookie_based_affinity: Disabled, request_timeout: 30, probe: {probe_key: probe-http}}
http_listeners:
  - {name: listener-80, protocol: Http, frontend_ip_configuration: {frontend_ip_configuration_key: fe-public}, frontend_port: {frontend_port_key: port-80}}
request_routing_rules:
  - {name: rule-basic, rule_type: Basic, priority: 100, http_listener: {http_listener_key: listener-80}, backend_address_pool: {backend_address_pool_key: pool-web}, backend_http_settings: {backend_http_settings_key: http-80}}
EOF
# A container app from Microsoft's public hello-world image (no registry
# credential), scaled to zero when idle, with external ingress on port 80,
# in a Consumption-only environment of the run made first as an ASO object
# of no chart (ca-pre.objects.yaml). The environment sends its logs nowhere,
# so it needs no workspace. The sandbox subscription may have one
# environment per region, so a run's environment must be gone before the
# next is made. An environment takes several minutes to create and to
# delete (CASE_TIMEOUT).
cat >"${WORK}/ca.yaml" <<EOF
name: ${RUN}-ca
location: ${LOCATION}
resource_group_name: ${AZURE_LIVE_RESOURCE_GROUP}
subscription_id: ${AZURE_SUBSCRIPTION_ID}
container_app_environment_resource_id: ${RG}/providers/Microsoft.App/managedEnvironments/${RUN}-cae
tags: {catalog-run: ${RUN}}
template:
  min_replicas: 0
  max_replicas: 1
  containers:
    - {name: hello, image: mcr.microsoft.com/k8se/quickstart:latest, cpu: 0.25, memory: 0.5Gi}
ingress:
  external_enabled: true
  target_port: 80
  traffic_weight: [{latest_revision: true, percentage: 100}]
EOF
cat >"${WORK}/ca-pre.objects.yaml" <<EOF
apiVersion: app.azure.com/v20250101
kind: ManagedEnvironment
metadata: {name: ca-env}
spec:
  azureName: ${RUN}-cae
  location: ${LOCATION}
  owner: {armId: ${RG}}
  zoneRedundant: false
  tags: {catalog-run: ${RUN}}
EOF
declare -A PRE=([appgw]=avm-res-network-virtualnetwork)
declare -A CASE_TIMEOUT=([appgw]=2400 [ca]=2400)
# object_list FILE: kind.version.group/name of each object in a render.
object_list() {
  kubectl get -n "${NS}" -f "$1" -o json \
    | jq -r '(if .items then .items else [.] end)[] | "\(.kind | ascii_downcase).\(.apiVersion | split("/") | .[1]).\(.apiVersion | split("/") | .[0])/\(.metadata.name)"'
}
# wait_gone LIMIT OBJECT...: until no object is left, or LIMIT seconds.
wait_gone() {
  local deadline=$(( $(date +%s) + $1 )) left o; shift
  while (( $(date +%s) < deadline )); do
    left=0
    for o in "$@"; do kubectl get -n "${NS}" "${o}" >/dev/null 2>&1 && left=$((left + 1)); done
    (( left == 0 )) && break
    sleep 10
  done
}
# The smallest Cognitive Services account: a Language (TextAnalytics)
# account on the free tier (AZURE_LIVE_COG_SKU=S for the paid one when the
# subscription's one free account of the kind is taken), local keys off,
# no deployments.
cat >"${WORK}/cog.yaml" <<EOF
name: ${RUN}-cog
location: ${LOCATION}
parent_id: ${RG}
kind: TextAnalytics
sku_name: ${AZURE_LIVE_COG_SKU:-F0}
custom_subdomain_name: ${RUN}-cog
local_auth_enabled: false
managed_identities: {system_assigned: true}
tags: {catalog-run: ${RUN}}
EOF
summary="${OUT}/summary.md"
{
  echo "# Azure live apply, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Catalog commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown); run ${RUN}; Azure Service Operator v${ASO_VERSION} and aso-extensions' manager (${ASOX_TARBALL:-${ASOX_DIR}}) on kind; one resource group of the sandbox subscription."
  echo
  echo "| Chart | Object | Ready | Deleted | Gone from Azure | Message |"
  echo "| --- | --- | --- | --- | --- | --- |"
} >"${summary}"

total=0; failed=0
for c in vnet:avm-res-network-virtualnetwork storage:avm-res-storage-storageaccount kv:avm-res-keyvault-vault \
    nsg:avm-res-network-networksecuritygroup rt:avm-res-network-routetable natgw:avm-res-network-natgateway \
    pip:avm-res-network-publicipaddress dns:avm-res-network-privatednszone \
    uai:avm-res-managedidentity-userassignedidentity law:avm-res-operationalinsights-workspace \
    acr:avm-res-containerregistry-registry fwp:avm-res-network-firewallpolicy \
    lb:avm-res-network-loadbalancer \
    bas:avm-res-network-bastionhost \
    appi:avm-res-insights-component \
    psql:avm-res-dbforpostgresql-flexibleserver \
    pe:avm-res-network-privateendpoint \
    appgw:avm-res-network-applicationgateway \
    cog:avm-res-cognitiveservices-account \
    ca:avm-res-app-containerapp; do
  case_="${c%%:*}" chart="${c#*:}" dir="charts/azure/${c#*:}"
  [[ " ${CASES} " == *" ${case_} "* ]] || continue
  echo "== ${chart}"
  mkdir -p "${OUT}/${chart}"
  limit="${CASE_TIMEOUT[${case_}]:-${TIMEOUT}}"
  declare -A ready=() armid=()
  pre_objects=()
  if [[ -n "${PRE[${case_}]:-}" || -f "${WORK}/${case_}-pre.objects.yaml" ]]; then
    # What the case needs first, from its own chart or as ASO objects of no
    # chart, Ready before the case.
    if [[ -n "${PRE[${case_}]:-}" ]]; then
      helm template "${case_}-pre" "charts/azure/${PRE[${case_}]}" --namespace "${NS}" -f "${WORK}/${case_}-pre.yaml" >"${OUT}/${chart}/pre.yaml"
    else
      cp "${WORK}/${case_}-pre.objects.yaml" "${OUT}/${chart}/pre.yaml"
    fi
    kubectl apply --server-side -n "${NS}" -f "${OUT}/${chart}/pre.yaml" >"${OUT}/${chart}/pre-apply.log"
    mapfile -t pre_objects < <(object_list "${OUT}/${chart}/pre.yaml")
    deadline=$(( $(date +%s) + limit ))
    for o in "${pre_objects[@]}"; do
      left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
      if kubectl wait -n "${NS}" --for=condition=Ready "${o}" --timeout="${left}s" >/dev/null 2>&1; then ready["$o"]=yes; else ready["$o"]=no; fi
      armid["$o"]="$(kubectl get -n "${NS}" "${o}" -o jsonpath='{.status.id}' 2>/dev/null || true)"
    done
    kubectl get -n "${NS}" -f "${OUT}/${chart}/pre.yaml" -o json \
      | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${chart}/pre-live.json"
  fi
  : >"${OUT}/${chart}/rendered.yaml"
  if [[ -f "${WORK}/${case_}.network.yaml" ]]; then
    helm template "${case_}-net" charts/azure/avm-res-network-virtualnetwork --namespace "${NS}" -f "${WORK}/${case_}.network.yaml" >>"${OUT}/${chart}/rendered.yaml"
  fi
  for w in "${WORK}/${case_}".with.*.yaml; do
    [[ -f "${w}" ]] || continue
    wchart="${w#"${WORK}/${case_}".with.}" wchart="${wchart%.yaml}"
    if [[ "${wchart}" == avm-res-network-privatednszone ]]; then
      zone="$(sed -n 's/^domain_name: //p' "${w}")"
      code="$(api -o /dev/null -w '%{http_code}' "${ARM}${RG}/providers/Microsoft.Network/privateDnsZones/${zone}?api-version=2020-06-01")"
      [[ "${code}" == 404 ]] || { echo "azure-live: the group already has the private DNS zone ${zone} (${code}); not adopting it" >&2; exit 1; }
    fi
    helm template "${case_}-${wchart#avm-res-}" "charts/azure/${wchart}" --namespace "${NS}" -f "${w}" >>"${OUT}/${chart}/rendered.yaml"
  done
  helm template "${case_}" "${dir}" --namespace "${NS}" -f "${WORK}/${case_}.yaml" >>"${OUT}/${chart}/rendered.yaml"
  # What a case needs that its chart does not make (appi's workspace).
  if [[ -f "${WORK}/${case_}.pre.yaml" ]]; then cat "${WORK}/${case_}.pre.yaml" >>"${OUT}/${chart}/rendered.yaml"; fi
  kubectl apply --server-side -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" >"${OUT}/${chart}/apply.log"
  mapfile -t objects < <(object_list "${OUT}/${chart}/rendered.yaml")
  deadline=$(( $(date +%s) + limit ))
  for o in "${objects[@]}"; do
    left=$(( deadline - $(date +%s) )); (( left < 5 )) && left=5
    if kubectl wait -n "${NS}" --for=condition=Ready "${o}" --timeout="${left}s" >/dev/null 2>&1; then ready["$o"]=yes; else ready["$o"]=no; fi
    armid["$o"]="$(kubectl get -n "${NS}" "${o}" -o jsonpath='{.status.id}' 2>/dev/null || true)"
  done
  kubectl get -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" -o json \
    | jq 'if .items then . else {apiVersion: "v1", kind: "List", items: [.]} end' >"${OUT}/${chart}/live.json"
  if bin/catalogtool outputs "${dir}/package.yaml" "${OUT}/${chart}/live.json" "${dir}/values.yaml" "${WORK}/${case_}.yaml" >"${OUT}/${chart}/outputs.json" 2>"${OUT}/${chart}/outputs.err"; then
    outputs_ok=yes
  else
    outputs_ok=no
  fi
  echo "-- outputs (${outputs_ok})"; cat "${OUT}/${chart}/outputs.json" "${OUT}/${chart}/outputs.err"
  kubectl delete -n "${NS}" -f "${OUT}/${chart}/rendered.yaml" --wait=false >/dev/null
  # Until every object is gone (kubectl get -f fails as soon as one is),
  # then what the case needed first.
  wait_gone "${limit}" "${objects[@]}"
  if (( ${#pre_objects[@]} > 0 )); then
    kubectl delete -n "${NS}" -f "${OUT}/${chart}/pre.yaml" --wait=false >/dev/null
    wait_gone "${TIMEOUT}" "${pre_objects[@]}"
  fi
  for o in "${pre_objects[@]}" "${objects[@]}"; do
    total=$((total + 1))
    msg="$(cat "${OUT}/${chart}/live.json" "${OUT}/${chart}/pre-live.json" 2>/dev/null | jq -r --arg n "${o#*/}" '.items[] | select(.metadata.name == $n) | (.status.conditions // [])[] | select(.type=="Ready") | .message' | tr '\n|' '  ' | cut -c1-160)"
    if kubectl get -n "${NS}" "${o}" >/dev/null 2>&1; then deleted=no; else deleted=yes; fi
    gone=n/a
    if [[ -n "${armid[$o]}" ]]; then
      # The provider and type after the last /providers/: an extension
      # resource (a diagnostic setting) is its own type, not its parent's.
      tail="${armid[$o]##*/providers/}"; ns="${tail%%/*}"; rest="${tail#*/}"; rtype="${rest%%/*}"
      v="$(api "${ARM}/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/${ns}?api-version=2021-04-01" \
        | jq -r --arg t "${rtype}" '.resourceTypes[] | select((.resourceType|ascii_downcase) == ($t|ascii_downcase)) | .apiVersions | map(select(test("preview")|not)) | .[0] // empty')"
      code="$(api -o /dev/null -w '%{http_code}' "${ARM}${armid[$o]}?api-version=${v}")"
      if [[ "${code}" == 404 ]]; then gone=yes; else gone="no (${code})"; fi
    fi
    [[ "${ready[$o]}" == yes && "${deleted}" == yes && "${gone}" != no* ]] || failed=$((failed + 1))
    echo "| ${chart} | ${o%%.*}/${o#*/} | ${ready[$o]} | ${deleted} | ${gone} | ${msg} |" >>"${summary}"
    echo "   ${o}: ready=${ready[$o]} deleted=${deleted} gone=${gone} ${msg}"
  done
  echo "| ${chart} | outputs | ${outputs_ok} | | | $(tr '\n|' '  ' <"${OUT}/${chart}/outputs.err" | cut -c1-160) |" >>"${summary}"
  [[ "${outputs_ok}" == yes ]] || failed=$((failed + 1))
  unset ready armid
done

# A deleted Cognitive Services account is soft-deleted, holding its name
# and subdomain for 48 hours: purge it.
if [[ " ${CASES} " == *" cog "* ]]; then
  echo "   purge soft-deleted account ${RUN}-cog: $(api -o /dev/null -w '%{http_code}' -X DELETE \
    "${ARM}/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.CognitiveServices/locations/${LOCATION}/resourceGroups/${AZURE_LIVE_RESOURCE_GROUP}/deletedAccounts/${RUN}-cog?api-version=2025-06-01")" | tee -a "${OUT}/purge.log"
fi
kubectl -n azureserviceoperator-system logs deployment/azureserviceoperator-controller-manager --tail=-1 >"${OUT}/aso.log" 2>&1 || true
asox_manager_logs "${OUT}/asox-manager.log"
{
  echo
  echo "${total} objects; ${failed} failures (an object not Ready, not deleted or still in Azure, or a chart's outputs not evaluated)."
  echo
  echo "Left in the group from catalog runs (cat...): $(run_resources cat | wc -l | tr -d ' ')."
} >>"${summary}"
cat "${summary}"
[[ ${failed} -eq 0 ]]
