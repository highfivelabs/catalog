# Cloud Foundation Fabric on Config Connector: inventory

Every module in Cloud Foundation Fabric's `modules/` at **v60.0.0**
(`f706bc3b`, 2026-11-05), checked against Config Connector's resource
list at **v1.160.0** (`c38b031c`, the release config-connector-extensions
pins). Read 2026-11-09. `docs/design.md` says how a module becomes a
chart; this page says which modules can, what each needs, and what
Config Connector lacks.

## Headline

91 modules (`__experimental_deprecated` and its six submodules are left
out). They create 433 distinct Terraform resource types, 120 of them IAM
resources (`*_iam_member`, `*_iam_binding`).

| Coverage | Modules | Meaning |
| --- | ---: | --- |
| full | 23 | every resource type has a stable (`v1beta1`) Config Connector kind, or is IAM on a kind IAMPolicyMember can reference |
| full, with alpha | 19 | as full, but at least one kind exists only as `v1alpha1` |
| partial | 42 | at least one resource type has no kind; the module's main resource is covered |
| none | 3 | the main resource has no kind: `looker-core`, `endpoints`, `container-registry` (deprecated upstream) |
| composite | 2 | `project-factory`, `net-vpc-factory`: they only compose other modules |
| n/a | 2 | `projects-data-source` (a read), `cloud-config-container` (cloud-init text) |

By resource type: 259 of 433 (60%) have a stable kind, 96 (22%) only an
alpha kind, 78 (18%) none; 2 of those 78 are covered by
config-connector-extensions' gap kinds (regional secrets and their
versions).

Of the 19 modules named first, 9 are **full**
(iam-service-account, net-vpc-firewall, net-cloudnat, dns, kms,
artifact-registry, cloudsql-instance, gke-nodepool, pubsub), 3 are
**full with alpha** (gke-cluster-standard and gke-cluster-autopilot for
GKE Backup, bigquery-dataset for dataset IAM) and 7 are **partial**
(project, folder, organization, net-vpc, gcs, secret-manager,
cloud-run-v2). None is uncovered.

## How to read it

- **Resource types, not fields.** A module counts as covered when each
  Terraform resource type it creates has a kind. A kind can still lack
  fields the module sets: the pilot found field gaps in every kind it
  ported (below, "Field gaps the pilot found"). Field coverage is known
  only for the pilot modules; for the rest, budget for some.
- **IAM.** `*_iam_member` maps to `IAMPolicyMember` exactly.
  `*_iam_binding` (authoritative for one role) has no exact equivalent:
  the charts use `IAMPartialPolicy`, which keeps the members it lists but
  does not remove members added out of band (docs/design.md, "IAM"). 43
  modules use `*_iam_binding`. IAM on a kind that IAMPolicyMember cannot
  reference (its "Supported Resources" table at v1.160.0) is a gap.
  BigQuery datasets take IAM only through the dataset's `spec.access` or
  the alpha `BigQueryDatasetAccess`, so they count as alpha.
- **Alpha.** A `v1alpha1` kind exists and works, but its schema may
  change without notice. Whether charts may use alpha kinds is a question
  for the builder (docs/design.md, "Questions"); the pilot refuses them.
- **Size** is the module's Terraform, a proxy for porting work: S under
  400 lines, M under 900, L under 2,000, XL above. For scale, the pilot
  ported iam-service-account (M) whole, gcs (L) and net-vpc (L) except
  their gaps and alpha features, and about a third of project (XL).
- **Rank** is foundational value: the first-named list first (the order a
  landing zone needs them), then the rest of a landing zone (billing,
  logging, firewall policies, VPC-SC, the factories, peering, VPN,
  groups, load balancers, VMs), then managed services, then specialised
  products.
- Made by `hack/inventory/run.sh` from the `.tf` files (each
  `resource "<type>"`), Config Connector's CRDs (kind, served versions)
  and service mappings (Terraform type to kind, for Terraform-based
  kinds), its IAMPolicyMember "Supported Resources" table, and a
  hand-checked table (`hack/inventory/manual.py`) for the types the
  service mappings do not name. The per-module tables below are its
  output; the text above them is written by hand.

## Gaps for config-connector-extensions

What no Config Connector v1.160.0 kind covers, ranked by how many modules
need it, foundational modules weighted first. "Modules" counts modules at
v60.0.0 that create the resource. Upstream status is as of v1.160.0;
check `master` and open pull requests before building (config-connector-extensions
`docs/design.md` 6.1).

| Rank | Gap | Modules | Which | Suggested kind |
| ---: | --- | ---: | --- | --- |
| 1 | **Role-authoritative IAM** (`google_*_iam_binding`): the members of one role on one resource, removing any others | 43 | every module with an `iam` or `iam_bindings` variable, all the foundation ones among them | `iam.gcp.hfl.dev/IAMBinding` (built in config-connector-extensions; first named `IAMRoleBinding`): `resourceRef` (any kind IAMPolicyMember takes), `role`, `members[]`/`memberFrom`, `condition`; owns that role (and condition) on the resource |
| 2 | **IAM on resources IAMPolicyMember cannot reference**: 32 resource types | 24 | secret-manager (regional secrets), gcs (managed folders), logging-bucket (log views), cloud-run-v2 (worker pools, IAP), cloud-function-v2, compute-vm (IAP tunnel), certificate-authority-service, cloud-deploy, dataform, dataplex (4), workstations, analytics-hub, api-gateway, binauthz, bigquery-connection, secure-source-manager, … | extend IAMPolicyMember/IAMPartialPolicy (or the kind in rank 1) to these resource types, starting with regional secrets, managed folders and log views |
| 3 | **Network endpoints**: `google_compute_region_network_endpoint` (none) and `google_compute_network_endpoint` / global endpoints (alpha only) | 9 | the load balancer modules (net-lb-app-ext, -ext-regional, -int, -int-cross-region, net-lb-proxy-int, -cross-region) | `ComputeRegionNetworkEndpoint`; promote the endpoint kinds |
| 4 | **Router route policies** (`google_compute_router_route_policy`) | 5 | net-vpn-ha, net-vpn-dynamic, net-vlan-attachment, net-ipsec-over-interconnect, ncc-spoke-ra | `ComputeRouterRoutePolicy` |
| 5 | **Bucket objects** (`google_storage_bucket_object`) | 4 | gcs, cloud-function-v1, cloud-function-v2, geap-agent-runtime | `StorageBucketObject` (small content inline or from a Secret/ConfigMap); arguably data, not infrastructure: a Bundt hook Job is the alternative |
| 6 | **Regional network firewall policies**: the policy, its rules, its association, and packet mirroring rules | 2 | net-firewall-policy, net-vpc (both foundational) | `ComputeRegionNetworkFirewallPolicy`, `...Rule`, `...Association` |
| 7 | **Hierarchy settings**: folder and organization service identities, folder and organization logging settings, a billing account's log sink | 3 | organization, folder, billing-account | `ServiceIdentity` with folder/organization parents; `LoggingSettings`; `LoggingLogSink` with a billing account parent |
| 8 | **Values known only after apply, needed in another object** | 3+ | iam-service-account (tag bindings name the account's unique ID), project (grants to service agents name the project number; Shared VPC service agent grants), gcs (a KMS key handle's key) | reference fields instead of strings: `TagsTagBinding.parentRef` to an `IAMServiceAccount`; `memberFrom` a project's service agent by service name; `StorageBucket.encryption.kmsKeyHandleRef` |
| 9 | **Field gaps on foundational kinds** (below) | 4 pilot modules | gcs, net-vpc, project | the fields, on the existing kinds, after checking for upstream pull requests (`StorageBucket.rpo` is PR #13713) |
| 10 | **Project settings**: default service accounts (delete, deprivilege, disable), default network tier, per-key compute metadata | 1 | project (every project made through it) | `ProjectDefaultServiceAccounts`, `ComputeProjectDefaultNetworkTier`, `ComputeProjectMetadataItem` |

Below the top ten, each needed by one module: Looker instances, Endpoints
services, Cloud Build v2 repositories, regional instance templates,
Secure Web Proxy policy rules, Chronicle rule deployments, the Discovery
Engine CMEK config, Apigee DNS zones, Agent Gateway kinds, workforce pool
SCIM tenants, project policy bindings. Container Registry is deprecated
upstream and should not be built.

### Alpha kinds foundational modules depend on

Not gaps (Config Connector has them, as `v1alpha1`), but the charts
refuse them today. By modules:

| Kind | Modules |
| --- | --- |
| `ComputeNetworkEndpoint` | 6 (load balancers) |
| `BigQueryDatasetAccess` (dataset IAM) | 5 (bigquery-dataset; log sinks to datasets in organization, folder, project, billing-account) |
| `ComputeOrganizationSecurityPolicyAssociation` | 4 (organization, folder, project, net-cloud-armor) |
| `IAMDenyPolicy` | 3 (organization, folder, project) |
| `SecurityCenterMuteConfig`, `SecurityCenterManagementSecurityHealthAnalyticsCustomModule` | 3 (organization, folder, project) |
| `GKEBackupBackupPlan`, `...RestorePlan`, `...Channel` | 2 (gke-cluster-standard, gke-cluster-autopilot) |
| `ComputeNetworkAttachment` | 2 (net-vpc, net-address) |
| `NetworkConnectivityInternalRange`, `...PolicyBasedRoute`, `...ServiceConnectionPolicy`, `ComputeNetworkPeeringRoutesConfig`, `ServiceNetworkingPeeredDNSDomain` | 1 each (net-vpc) |
| `DNSResponsePolicy`, `DNSResponsePolicyRule` | 1 (dns-response-policy) |
| `StorageManagedFolder` | 1 (gcs) |

### Field gaps the pilot found

Fields the fabric module sets that the Config Connector v1.160.0 kind does
not have. Each is refused by the chart when set.

| Kind | Missing | Fabric variable | Upstream |
| --- | --- | --- | --- |
| `StorageBucket` | `rpo` | `gcs.rpo` | PR #13713 |
| `StorageManagedFolder` (alpha) | nested folder names (`a/b`): its identity parser reads a one-level name only, so such a folder cannot be updated or deleted; and no project annotation fallback (panics without `spec.projectRef`) | `gcs.managed_folders` | found in the fake cloud; none found upstream |
| `StorageBucket` | `hierarchicalNamespace` | `gcs.enable_hierarchical_namespace` | none found |
| `StorageBucket` | `enableObjectRetention` | `gcs.enable_object_retention` | none found |
| `ComputeNetwork` | `bgpAlwaysCompareMed`, `bgpBestPathSelectionMode`, `bgpInterRegionCost` | `net-vpc.bgp_config` | none found |
| `ComputeNetwork` | `status.networkId` (the numeric ID) | output `net-vpc.network_id` | none found |
| `ComputeSubnetwork` | `ipCollection`, `allowSubnetCidrRoutesOverlap` | `net-vpc.subnets[].ip_collection`, `allow_subnet_cidr_routes_overlap` | none found |
| `ComputeSharedVPCServiceProject` | grants to the service project's service agents (Terraform does this in the module, not the kind) | `project.shared_vpc_service_config.service_agent_*` | see rank 8 |
| `TagsTagBinding` | a reference to an `IAMServiceAccount` as parent | `iam-service-account.tag_bindings` | see rank 8 |

## Inventory

<!-- generated below by hack/inventory/run.sh; edit above this line -->

| Rank | Module | Coverage | Size | Terraform lines | Variables | Resource types (beta / alpha / gap) |
| ---: | --- | --- | --- | ---: | ---: | --- |
| 1 | [project](#project) | partial | XL | 4634 | 58 | 41 / 6 / 2 |
| 2 | [folder](#folder) | partial | L | 1883 | 31 | 16 / 6 / 2 |
| 3 | [organization](#organization) | partial | XL | 3534 | 35 | 25 / 7 / 3 |
| 4 | [iam-service-account](#iam-service-account) | full | M | 838 | 28 | 9 / 0 / 0 |
| 5 | [net-vpc](#net-vpc) | partial | L | 1867 | 29 | 12 / 6 / 1 |
| 6 | [net-vpc-firewall](#net-vpc-firewall) | full | M | 511 | 8 | 1 / 0 / 0 |
| 7 | [net-cloudnat](#net-cloudnat) | full | M | 466 | 16 | 2 / 0 / 0 |
| 8 | [dns](#dns) | full | M | 478 | 9 | 3 / 0 / 0 |
| 9 | [kms](#kms) | full | M | 548 | 10 | 8 / 0 / 0 |
| 10 | [gcs](#gcs) | partial | L | 1044 | 36 | 8 / 1 / 3 |
| 11 | [artifact-registry](#artifact-registry) | full | M | 793 | 17 | 4 / 0 / 0 |
| 12 | [secret-manager](#secret-manager) | partial | M | 733 | 4 | 6 / 0 / 4 |
| 13 | [cloudsql-instance](#cloudsql-instance) | full | L | 983 | 35 | 4 / 0 / 0 |
| 14 | [gke-cluster-standard](#gke-cluster-standard) | full, with alpha | L | 1846 | 25 | 2 / 4 / 0 |
| 15 | [gke-cluster-autopilot](#gke-cluster-autopilot) | full, with alpha | L | 1459 | 21 | 2 / 4 / 0 |
| 16 | [gke-nodepool](#gke-nodepool) | full | M | 828 | 20 | 2 / 0 / 0 |
| 17 | [pubsub](#pubsub) | full | M | 633 | 14 | 7 / 0 / 0 |
| 18 | [bigquery-dataset](#bigquery-dataset) | full, with alpha | L | 1123 | 24 | 4 / 3 / 0 |
| 19 | [cloud-run-v2](#cloud-run-v2) | partial | XL | 2585 | 21 | 9 / 1 / 3 |
| 20 | [billing-account](#billing-account) | partial | M | 871 | 11 | 8 / 1 / 1 |
| 21 | [logging-bucket](#logging-bucket) | partial | M | 448 | 12 | 7 / 0 / 2 |
| 22 | [net-firewall-policy](#net-firewall-policy) | partial | L | 1148 | 13 | 6 / 1 / 4 |
| 23 | [vpc-sc](#vpc-sc) | full | XL | 2010 | 12 | 5 / 0 / 0 |
| 24 | [project-factory](#project-factory) | composite | XL | 3799 | 8 | 0 / 1 / 0 |
| 25 | [net-vpc-factory](#net-vpc-factory) | composite | S | 272 | 4 | 0 / 0 / 0 |
| 26 | [net-vpc-peering](#net-vpc-peering) | full | S | 204 | 7 | 1 / 0 / 0 |
| 27 | [net-address](#net-address) | full, with alpha | M | 613 | 9 | 4 / 1 / 0 |
| 28 | [net-vpn-ha](#net-vpn-ha) | partial | L | 933 | 19 | 6 / 0 / 1 |
| 29 | [cloud-identity-group](#cloud-identity-group) | full | S | 175 | 6 | 2 / 0 / 0 |
| 30 | [dns-response-policy](#dns-response-policy) | full, with alpha | S | 276 | 9 | 0 / 2 / 0 |
| 31 | [certificate-manager](#certificate-manager) | full, with alpha | S | 282 | 5 | 4 / 1 / 0 |
| 32 | [net-lb-app-ext](#net-lb-app-ext) | full, with alpha | XL | 3127 | 17 | 12 / 3 / 0 |
| 33 | [net-lb-int](#net-lb-int) | full | L | 1389 | 24 | 6 / 0 / 0 |
| 34 | [net-lb-ext](#net-lb-ext) | full | M | 646 | 11 | 4 / 0 / 0 |
| 35 | [net-lb-app-int](#net-lb-app-int) | partial | XL | 2770 | 22 | 12 / 1 / 1 |
| 36 | [compute-vm](#compute-vm) | partial | XL | 2404 | 43 | 11 / 4 / 3 |
| 37 | [compute-mig](#compute-mig) | full, with alpha | L | 1085 | 21 | 3 / 4 / 0 |
| 38 | [service-directory](#service-directory) | full | S | 249 | 8 | 5 / 0 / 0 |
| 39 | [workflows](#workflows) | full, with alpha | M | 798 | 18 | 4 / 2 / 0 |
| 40 | [cloud-function-v2](#cloud-function-v2) | partial | L | 917 | 25 | 6 / 1 / 2 |
| 41 | [alloydb](#alloydb) | full | L | 1458 | 33 | 4 / 0 / 0 |
| 42 | [spanner-instance](#spanner-instance) | full, with alpha | M | 426 | 7 | 6 / 1 / 0 |
| 43 | [bigtable-instance](#bigtable-instance) | full | S | 308 | 11 | 4 / 0 / 0 |
| 44 | [firestore](#firestore) | full, with alpha | M | 452 | 7 | 2 / 3 / 0 |
| 45 | [managed-kafka](#managed-kafka) | full, with alpha | S | 283 | 11 | 2 / 2 / 0 |
| 46 | [net-cloud-armor](#net-cloud-armor) | full, with alpha | XL | 2216 | 33 | 4 / 3 / 0 |
| 47 | [net-swp](#net-swp) | partial | M | 474 | 14 | 2 / 3 / 1 |
| 48 | [net-lb-app-ext-regional](#net-lb-app-ext-regional) | partial | XL | 2481 | 19 | 10 / 1 / 1 |
| 49 | [net-lb-app-int-cross-region](#net-lb-app-int-cross-region) | full, with alpha | XL | 2742 | 23 | 10 / 1 / 0 |
| 50 | [net-lb-proxy-int](#net-lb-proxy-int) | partial | L | 958 | 14 | 8 / 1 / 1 |
| 51 | [net-lb-proxy-int-cross-region](#net-lb-proxy-int-cross-region) | full, with alpha | M | 782 | 14 | 7 / 1 / 0 |
| 52 | [net-vpn-static](#net-vpn-static) | full | S | 328 | 9 | 5 / 0 / 0 |
| 53 | [net-vpn-dynamic](#net-vpn-dynamic) | partial | M | 515 | 8 | 7 / 0 / 1 |
| 54 | [net-vlan-attachment](#net-vlan-attachment) | partial | M | 557 | 15 | 5 / 0 / 1 |
| 55 | [net-ipsec-over-interconnect](#net-ipsec-over-interconnect) | partial | M | 470 | 8 | 6 / 0 / 1 |
| 56 | [ncc-spoke-ra](#ncc-spoke-ra) | partial | M | 400 | 8 | 5 / 0 / 1 |
| 57 | [gke-hub](#gke-hub) | full | M | 655 | 8 | 3 / 0 / 0 |
| 58 | [binauthz](#binauthz) | partial | S | 234 | 5 | 3 / 0 / 1 |
| 59 | [certificate-authority-service](#certificate-authority-service) | partial | M | 547 | 9 | 2 / 0 / 2 |
| 60 | [backup-dr](#backup-dr) | full, with alpha | S | 259 | 7 | 2 / 1 / 0 |
| 61 | [cloud-deploy](#cloud-deploy) | partial | L | 1123 | 14 | 1 / 3 / 4 |
| 62 | [cloud-build-v2-connection](#cloud-build-v2-connection) | partial | M | 546 | 13 | 1 / 1 / 3 |
| 63 | [secure-source-manager-instance](#secure-source-manager-instance) | partial | S | 381 | 11 | 2 / 1 / 4 |
| 64 | [source-repository](#source-repository) | full | S | 276 | 7 | 4 / 0 / 0 |
| 65 | [bigquery-connection](#bigquery-connection) | partial | S | 391 | 12 | 1 / 0 / 2 |
| 66 | [analytics-hub](#analytics-hub) | partial | S | 358 | 14 | 2 / 0 / 3 |
| 67 | [biglake-catalog](#biglake-catalog) | full, with alpha | S | 156 | 4 | 1 / 2 / 0 |
| 68 | [dataform-repository](#dataform-repository) | partial | S | 215 | 8 | 1 / 0 / 2 |
| 69 | [dataproc](#dataproc) | full | M | 720 | 9 | 3 / 0 / 0 |
| 70 | [datafusion](#datafusion) | full | S | 257 | 14 | 4 / 0 / 0 |
| 71 | [dataplex](#dataplex) | partial | S | 263 | 7 | 0 / 3 / 2 |
| 72 | [dataplex-datascan](#dataplex-datascan) | partial | M | 765 | 16 | 0 / 1 / 2 |
| 73 | [dataplex-aspect-types](#dataplex-aspect-types) | partial | S | 343 | 5 | 0 / 1 / 2 |
| 74 | [data-catalog-policy-tag](#data-catalog-policy-tag) | full | M | 474 | 12 | 6 / 0 / 0 |
| 75 | [data-catalog-tag](#data-catalog-tag) | full, with alpha | S | 146 | 2 | 0 / 1 / 0 |
| 76 | [data-catalog-tag-template](#data-catalog-tag-template) | partial | S | 351 | 4 | 0 / 1 / 2 |
| 77 | [api-gateway](#api-gateway) | partial | M | 522 | 11 | 4 / 2 / 3 |
| 78 | [apigee](#apigee) | partial | M | 827 | 13 | 9 / 2 / 1 |
| 79 | [endpoints](#endpoints) | none | S | 143 | 5 | 0 / 0 / 2 |
| 80 | [cloud-function-v1](#cloud-function-v1) | partial | M | 759 | 24 | 6 / 0 / 1 |
| 81 | [workstation-cluster](#workstation-cluster) | partial | M | 738 | 12 | 3 / 0 / 4 |
| 82 | [gcve-private-cloud](#gcve-private-cloud) | full, with alpha | S | 337 | 5 | 0 / 5 / 0 |
| 83 | [looker-core](#looker-core) | none | M | 435 | 15 | 0 / 0 / 1 |
| 84 | [ai-applications](#ai-applications) | partial | L | 1666 | 8 | 2 / 8 / 1 |
| 85 | [geap-agent-gateway](#geap-agent-gateway) | partial | L | 920 | 15 | 0 / 3 / 3 |
| 86 | [geap-agent-runtime](#geap-agent-runtime) | partial | L | 1132 | 14 | 3 / 1 / 1 |
| 87 | [geap-workbench](#geap-workbench) | partial | M | 668 | 30 | 1 / 1 / 1 |
| 88 | [secops-rules](#secops-rules) | partial | S | 180 | 5 | 0 / 2 / 1 |
| 89 | [container-registry](#container-registry) | none | S | 113 | 3 | 1 / 0 / 1 |
| 90 | [projects-data-source](#projects-data-source) | n/a | S | 169 | 5 | 0 / 0 / 0 |
| 91 | [cloud-config-container](#cloud-config-container) | n/a | L | 1954 | 72 | 0 / 0 / 0 |

## Per module

### project

This module implements the creation and management of one GCP project including IAM, organization policies, Shared VPC host or service attac…

Rank 1. Terraform module: [`modules/project`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/project). Coverage: **partial**. Size: XL (4634 lines of Terraform, 58 variables, 27 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_access_context_manager_service_perimeter_dry_run_resource` | AccessContextManagerServicePerimeter (spec.spec.resources) |  |
| `google_access_context_manager_service_perimeter_resource` | AccessContextManagerServicePerimeterResource |  |
| `google_bigquery_dataset_iam_member` | BigQueryDatasetAccess/BigQueryDataset.spec.access | alpha only |
| `google_bigquery_reservation` | BigQueryReservationReservation |  |
| `google_bigquery_reservation_assignment` | BigQueryReservationAssignment |  |
| `google_cloud_asset_project_feed` | AssetFeed |  |
| `google_cloud_quotas_quota_preference` | APIQuotaPreference |  |
| `google_compute_organization_security_policy_association` | ComputeOrganizationSecurityPolicyAssociation | alpha only |
| `google_compute_project_default_network_tier` | none | **gap** |
| `google_compute_project_metadata_item` | ComputeProjectMetadata (authoritative for all metadata) |  |
| `google_compute_shared_vpc_host_project` | ComputeSharedVPCHostProject |  |
| `google_compute_shared_vpc_service_project` | ComputeSharedVPCServiceProject |  |
| `google_compute_subnetwork_iam_member` | IAMPolicyMember -> ComputeSubnetwork |  |
| `google_essential_contacts_contact` | EssentialContactsContact |  |
| `google_folder_iam_member` | IAMPolicyMember -> Folder |  |
| `google_iam_deny_policy` | IAMDenyPolicy | alpha only |
| `google_iam_workload_identity_pool` | IAMWorkloadIdentityPool |  |
| `google_iam_workload_identity_pool_provider` | IAMWorkloadIdentityPoolProvider |  |
| `google_kms_crypto_key_iam_member` | IAMPolicyMember -> KMSCryptoKey |  |
| `google_kms_key_handle` | KMSKeyHandle |  |
| `google_logging_log_scope` | LoggingLogScope | alpha only |
| `google_logging_metric` | LoggingLogMetric |  |
| `google_logging_project_exclusion` | LoggingLogExclusion |  |
| `google_logging_project_sink` | LoggingLogSink |  |
| `google_monitoring_alert_policy` | MonitoringAlertPolicy |  |
| `google_monitoring_monitored_project` | MonitoringMonitoredProject |  |
| `google_monitoring_notification_channel` | MonitoringNotificationChannel |  |
| `google_org_policy_policy` | OrgPolicyPolicy |  |
| `google_privileged_access_manager_entitlement` | PrivilegedAccessManagerEntitlement |  |
| `google_project` | Project |  |
| `google_project_default_service_accounts` | none | **gap** |
| `google_project_iam_audit_config` | IAMAuditConfig |  |
| `google_project_iam_binding` | IAMPartialPolicy -> Project |  |
| `google_project_iam_custom_role` | IAMCustomRole |  |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_project_service` | Service |  |
| `google_project_service_identity` | ServiceIdentity |  |
| `google_pubsub_topic_iam_member` | IAMPolicyMember -> PubSubTopic |  |
| `google_resource_manager_lien` | ResourceManagerLien |  |
| `google_scc_management_project_security_health_analytics_custom_module` | SecurityCenterManagementSecurityHealthAnalyticsCustomModule | alpha only |
| `google_scc_v2_project_mute_config` | SecurityCenterMuteConfig | alpha only |
| `google_storage_bucket_iam_member` | IAMPolicyMember -> StorageBucket |  |
| `google_tags_tag_binding` | TagsTagBinding |  |
| `google_tags_tag_key` | TagsTagKey |  |
| `google_tags_tag_key_iam_binding` | IAMPartialPolicy -> TagsTagKey |  |
| `google_tags_tag_key_iam_member` | IAMPolicyMember -> TagsTagKey |  |
| `google_tags_tag_value` | TagsTagValue |  |
| `google_tags_tag_value_iam_binding` | IAMPartialPolicy -> TagsTagValue |  |
| `google_tags_tag_value_iam_member` | IAMPolicyMember -> TagsTagValue |  |

### folder

This module allows the creation and management of folders, including support for IAM bindings, organization policies, and hierarchical firew…

Rank 2. Terraform module: [`modules/folder`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/folder). Coverage: **partial**. Size: L (1883 lines of Terraform, 31 variables, 9 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_assured_workloads_workload` | AssuredWorkloadsWorkload | alpha only |
| `google_bigquery_dataset_iam_member` | BigQueryDatasetAccess/BigQueryDataset.spec.access | alpha only |
| `google_cloud_asset_folder_feed` | AssetFeed |  |
| `google_compute_firewall_policy_association` | ComputeFirewallPolicyAssociation |  |
| `google_compute_organization_security_policy_association` | ComputeOrganizationSecurityPolicyAssociation | alpha only |
| `google_essential_contacts_contact` | EssentialContactsContact |  |
| `google_folder` | Folder |  |
| `google_folder_iam_audit_config` | IAMAuditConfig |  |
| `google_folder_iam_binding` | IAMPartialPolicy -> Folder |  |
| `google_folder_iam_member` | IAMPolicyMember -> Folder |  |
| `google_folder_service_identity` | none | **gap** |
| `google_iam_deny_policy` | IAMDenyPolicy | alpha only |
| `google_kms_autokey_config` | KMSAutokeyConfig |  |
| `google_logging_folder_exclusion` | LoggingLogExclusion |  |
| `google_logging_folder_settings` | none | **gap** |
| `google_logging_folder_sink` | LoggingLogSink |  |
| `google_org_policy_policy` | OrgPolicyPolicy |  |
| `google_privileged_access_manager_entitlement` | PrivilegedAccessManagerEntitlement |  |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_pubsub_topic_iam_member` | IAMPolicyMember -> PubSubTopic |  |
| `google_scc_management_folder_security_health_analytics_custom_module` | SecurityCenterManagementSecurityHealthAnalyticsCustomModule | alpha only |
| `google_scc_v2_folder_mute_config` | SecurityCenterMuteConfig | alpha only |
| `google_storage_bucket_iam_member` | IAMPolicyMember -> StorageBucket |  |
| `google_tags_tag_binding` | TagsTagBinding |  |

### organization

This module allows managing several organization properties

Rank 3. Terraform module: [`modules/organization`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/organization). Coverage: **partial**. Size: XL (3534 lines of Terraform, 35 variables, 23 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_access_context_manager_access_level` | AccessContextManagerAccessLevel |  |
| `google_access_context_manager_gcp_user_access_binding` | AccessContextManagerGCPUserAccessBinding | alpha only |
| `google_bigquery_dataset_iam_member` | BigQueryDatasetAccess/BigQueryDataset.spec.access | alpha only |
| `google_cloud_asset_organization_feed` | AssetFeed |  |
| `google_compute_firewall_policy_association` | ComputeFirewallPolicyAssociation |  |
| `google_compute_organization_security_policy_association` | ComputeOrganizationSecurityPolicyAssociation | alpha only |
| `google_essential_contacts_contact` | EssentialContactsContact |  |
| `google_iam_deny_policy` | IAMDenyPolicy | alpha only |
| `google_iam_workforce_pool` | IAMWorkforcePool |  |
| `google_iam_workforce_pool_provider` | IAMWorkforcePoolProvider |  |
| `google_iam_workforce_pool_provider_scim_tenant` | none | **gap** |
| `google_logging_organization_exclusion` | LoggingLogExclusion |  |
| `google_logging_organization_settings` | none | **gap** |
| `google_logging_organization_sink` | LoggingLogSink |  |
| `google_model_armor_floorsetting` | ModelArmorFloorSetting | alpha only |
| `google_org_policy_custom_constraint` | OrgPolicyCustomConstraint |  |
| `google_org_policy_policy` | OrgPolicyPolicy |  |
| `google_organization_iam_audit_config` | IAMAuditConfig |  |
| `google_organization_iam_binding` | IAMPartialPolicy -> Organization |  |
| `google_organization_iam_custom_role` | IAMCustomRole |  |
| `google_organization_iam_member` | IAMPolicyMember -> Organization |  |
| `google_organization_service_identity` | none | **gap** |
| `google_privileged_access_manager_entitlement` | PrivilegedAccessManagerEntitlement |  |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_pubsub_topic_iam_member` | IAMPolicyMember -> PubSubTopic |  |
| `google_scc_management_organization_security_health_analytics_custom_module` | SecurityCenterManagementSecurityHealthAnalyticsCustomModule | alpha only |
| `google_scc_v2_organization_mute_config` | SecurityCenterMuteConfig | alpha only |
| `google_storage_bucket_iam_member` | IAMPolicyMember -> StorageBucket |  |
| `google_tags_tag_binding` | TagsTagBinding |  |
| `google_tags_tag_key` | TagsTagKey |  |
| `google_tags_tag_key_iam_binding` | IAMPartialPolicy -> TagsTagKey |  |
| `google_tags_tag_key_iam_member` | IAMPolicyMember -> TagsTagKey |  |
| `google_tags_tag_value` | TagsTagValue |  |
| `google_tags_tag_value_iam_binding` | IAMPartialPolicy -> TagsTagValue |  |
| `google_tags_tag_value_iam_member` | IAMPolicyMember -> TagsTagValue |  |

### iam-service-account

This module allows simplified creation and management of one a service account and its IAM bindings.

Rank 4. Terraform module: [`modules/iam-service-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/iam-service-account). Coverage: **full**. Size: M (838 lines of Terraform, 28 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_billing_account_iam_member` | IAMPolicyMember -> BillingAccount |  |
| `google_folder_iam_member` | IAMPolicyMember -> Folder |  |
| `google_organization_iam_member` | IAMPolicyMember -> Organization |  |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_service_account` | IAMServiceAccount |  |
| `google_service_account_iam_binding` | IAMPartialPolicy -> IAMServiceAccount |  |
| `google_service_account_iam_member` | IAMPolicyMember -> IAMServiceAccount |  |
| `google_storage_bucket_iam_member` | IAMPolicyMember -> StorageBucket |  |
| `google_tags_tag_binding` | TagsTagBinding |  |

### net-vpc

This module allows creation and management of VPC networks including subnetworks and subnetwork IAM bindings, and most features and options…

Rank 5. Terraform module: [`modules/net-vpc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc). Coverage: **partial**. Size: L (1867 lines of Terraform, 29 variables, 23 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_global_address` | ComputeAddress |  |
| `google_compute_network` | ComputeNetwork |  |
| `google_compute_network_attachment` | ComputeNetworkAttachment | alpha only |
| `google_compute_network_firewall_policy_association` | ComputeNetworkFirewallPolicyAssociation |  |
| `google_compute_network_peering` | ComputeNetworkPeering |  |
| `google_compute_network_peering_routes_config` | ComputeNetworkPeeringRoutesConfig | alpha only |
| `google_compute_region_network_firewall_policy_association` | none | **gap** |
| `google_compute_route` | ComputeRoute |  |
| `google_compute_shared_vpc_host_project` | ComputeSharedVPCHostProject |  |
| `google_compute_shared_vpc_service_project` | ComputeSharedVPCServiceProject |  |
| `google_compute_subnetwork` | ComputeSubnetwork |  |
| `google_compute_subnetwork_iam_binding` | IAMPartialPolicy -> ComputeSubnetwork |  |
| `google_compute_subnetwork_iam_member` | IAMPolicyMember -> ComputeSubnetwork |  |
| `google_dns_policy` | DNSPolicy |  |
| `google_network_connectivity_internal_range` | NetworkConnectivityInternalRange | alpha only |
| `google_network_connectivity_policy_based_route` | NetworkConnectivityPolicyBasedRoute | alpha only |
| `google_network_connectivity_service_connection_policy` | NetworkConnectivityServiceConnectionPolicy | alpha only |
| `google_service_networking_connection` | ServiceNetworkingConnection |  |
| `google_service_networking_peered_dns_domain` | ServiceNetworkingPeeredDNSDomain | alpha only |

### net-vpc-firewall

This module allows creation and management of different types of firewall rules for a single VPC network

Rank 6. Terraform module: [`modules/net-vpc-firewall`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-firewall). Coverage: **full**. Size: M (511 lines of Terraform, 8 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_firewall` | ComputeFirewall |  |

### net-cloudnat

Simple Cloud NAT management, with optional router creation.

Rank 7. Terraform module: [`modules/net-cloudnat`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-cloudnat). Coverage: **full**. Size: M (466 lines of Terraform, 16 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_router` | ComputeRouter |  |
| `google_compute_router_nat` | ComputeRouterNAT |  |

### dns

This module allows simple management of Google Cloud DNS zones and records. It supports creating public, private, forwarding, peering, servi…

Rank 8. Terraform module: [`modules/dns`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dns). Coverage: **full**. Size: M (478 lines of Terraform, 9 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_dns_managed_zone` | DNSManagedZone |  |
| `google_dns_managed_zone_iam_binding` | IAMPartialPolicy -> DNSManagedZone |  |
| `google_dns_record_set` | DNSRecordSet |  |

### kms

This module allows creating and managing KMS crypto keys and IAM bindings at both the keyring and crypto key level. An existing keyring can…

Rank 9. Terraform module: [`modules/kms`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/kms). Coverage: **full**. Size: M (548 lines of Terraform, 10 variables, 7 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_kms_crypto_key` | KMSCryptoKey |  |
| `google_kms_crypto_key_iam_binding` | IAMPartialPolicy -> KMSCryptoKey |  |
| `google_kms_crypto_key_iam_member` | IAMPolicyMember -> KMSCryptoKey |  |
| `google_kms_key_ring` | KMSKeyRing |  |
| `google_kms_key_ring_iam_binding` | IAMPartialPolicy -> KMSKeyRing |  |
| `google_kms_key_ring_iam_member` | IAMPolicyMember -> KMSKeyRing |  |
| `google_kms_key_ring_import_job` | KMSImportJob |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |

### gcs

Rank 10. Terraform module: [`modules/gcs`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gcs). Coverage: **partial**. Size: L (1044 lines of Terraform, 36 variables, 7 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_kms_key_handle` | KMSKeyHandle |  |
| `google_pubsub_topic` | PubSubTopic |  |
| `google_pubsub_topic_iam_binding` | IAMPartialPolicy -> PubSubTopic |  |
| `google_storage_bucket` | StorageBucket |  |
| `google_storage_bucket_iam_binding` | IAMPartialPolicy -> StorageBucket |  |
| `google_storage_bucket_iam_member` | IAMPolicyMember -> StorageBucket |  |
| `google_storage_bucket_object` | none | **gap** |
| `google_storage_managed_folder` | StorageManagedFolder | alpha only |
| `google_storage_managed_folder_iam_binding` | none | **gap** |
| `google_storage_managed_folder_iam_member` | none | **gap** |
| `google_storage_notification` | StorageNotification |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |

### artifact-registry

This module simplifies the creation of repositories using Google Cloud Artifact Registry.

Rank 11. Terraform module: [`modules/artifact-registry`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/artifact-registry). Coverage: **full**. Size: M (793 lines of Terraform, 17 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_artifact_registry_repository` | ArtifactRegistryRepository |  |
| `google_artifact_registry_repository_iam_binding` | IAMPartialPolicy -> ArtifactRegistryRepository |  |
| `google_artifact_registry_repository_iam_member` | IAMPolicyMember -> ArtifactRegistryRepository |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |

### secret-manager

This module allows managing one or more secrets with versions and IAM bindings. Version data can be passed via [write-only attributes](https…

Rank 12. Terraform module: [`modules/secret-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/secret-manager). Coverage: **partial**. Size: M (733 lines of Terraform, 4 variables, 5 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_secret_manager_regional_secret` | SecretManagerSecret (secretmanager.gcp.hfl.dev, spec.location) | gap kind (config-connector-extensions) |
| `google_secret_manager_regional_secret_iam_binding` | none | **gap** |
| `google_secret_manager_regional_secret_iam_member` | none | **gap** |
| `google_secret_manager_regional_secret_version` | SecretManagerSecretVersion (secretmanager.gcp.hfl.dev) | gap kind (config-connector-extensions) |
| `google_secret_manager_secret` | SecretManagerSecret |  |
| `google_secret_manager_secret_iam_binding` | IAMPartialPolicy -> SecretManagerSecret |  |
| `google_secret_manager_secret_iam_member` | IAMPolicyMember -> SecretManagerSecret |  |
| `google_secret_manager_secret_version` | SecretManagerSecretVersion |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |
| `google_tags_tag_binding` | TagsTagBinding |  |

### cloudsql-instance

This module manages the creation of Cloud SQL instances with potential read replicas in other regions. It can also create an initial set of…

Rank 13. Terraform module: [`modules/cloudsql-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloudsql-instance). Coverage: **full**. Size: L (983 lines of Terraform, 35 variables, 17 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_sql_database` | SQLDatabase |  |
| `google_sql_database_instance` | SQLInstance |  |
| `google_sql_ssl_cert` | SQLSSLCert |  |
| `google_sql_user` | SQLUser |  |
| `random_password` | n/a | not Google Cloud |

### gke-cluster-standard

This module offers a way to create and manage Google Kubernetes Engine (GKE) [Standard clusters](https://cloud.google.com/kubernetes-engine/…

Rank 14. Terraform module: [`modules/gke-cluster-standard`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-cluster-standard). Coverage: **full, with alpha**. Size: L (1846 lines of Terraform, 25 variables, 15 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_container_cluster` | ContainerCluster |  |
| `google_gke_backup_backup_channel` | GKEBackupBackupChannel | alpha only |
| `google_gke_backup_backup_plan` | GKEBackupBackupPlan | alpha only |
| `google_gke_backup_restore_channel` | GKEBackupRestoreChannel | alpha only |
| `google_gke_backup_restore_plan` | GKEBackupRestorePlan | alpha only |
| `google_pubsub_topic` | PubSubTopic |  |

### gke-cluster-autopilot

This module offers a way to create and manage Google Kubernetes Engine (GKE) [Autopilot clusters](https://cloud.google.com/kubernetes-engine…

Rank 15. Terraform module: [`modules/gke-cluster-autopilot`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-cluster-autopilot). Coverage: **full, with alpha**. Size: L (1459 lines of Terraform, 21 variables, 15 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_container_cluster` | ContainerCluster |  |
| `google_gke_backup_backup_channel` | GKEBackupBackupChannel | alpha only |
| `google_gke_backup_backup_plan` | GKEBackupBackupPlan | alpha only |
| `google_gke_backup_restore_channel` | GKEBackupRestoreChannel | alpha only |
| `google_gke_backup_restore_plan` | GKEBackupRestorePlan | alpha only |
| `google_pubsub_topic` | PubSubTopic |  |

### gke-nodepool

This module allows simplified creation and management of individual GKE nodepools, setting sensible defaults (eg a service account is create…

Rank 16. Terraform module: [`modules/gke-nodepool`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-nodepool). Coverage: **full**. Size: M (828 lines of Terraform, 20 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_container_node_pool` | ContainerNodePool |  |
| `google_service_account` | IAMServiceAccount |  |

### pubsub

This module allows managing a single Pub/Sub topic, including multiple subscriptions and IAM bindings at the topic and subscriptions levels,…

Rank 17. Terraform module: [`modules/pubsub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/pubsub). Coverage: **full**. Size: M (633 lines of Terraform, 14 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_pubsub_schema` | PubSubSchema |  |
| `google_pubsub_subscription` | PubSubSubscription |  |
| `google_pubsub_subscription_iam_binding` | IAMPartialPolicy -> PubSubSubscription |  |
| `google_pubsub_subscription_iam_member` | IAMPolicyMember -> PubSubSubscription |  |
| `google_pubsub_topic` | PubSubTopic |  |
| `google_pubsub_topic_iam_binding` | IAMPartialPolicy -> PubSubTopic |  |
| `google_pubsub_topic_iam_member` | IAMPolicyMember -> PubSubTopic |  |

### bigquery-dataset

This module allows managing a single BigQuery dataset, including access configuration, tables and views.

Rank 18. Terraform module: [`modules/bigquery-dataset`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigquery-dataset). Coverage: **full, with alpha**. Size: L (1123 lines of Terraform, 24 variables, 12 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_bigquery_dataset` | BigQueryDataset |  |
| `google_bigquery_dataset_access` | BigQueryDatasetAccess | alpha only |
| `google_bigquery_dataset_iam_binding` | BigQueryDatasetAccess/BigQueryDataset.spec.access | alpha only |
| `google_bigquery_dataset_iam_member` | BigQueryDatasetAccess/BigQueryDataset.spec.access | alpha only |
| `google_bigquery_routine` | BigQueryRoutine |  |
| `google_bigquery_table` | BigQueryTable |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |

### cloud-run-v2

Cloud Run Services and Jobs, with support for IAM roles and Eventarc trigger creation. This module uses provider default value for `deletion…

Rank 19. Terraform module: [`modules/cloud-run-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-run-v2). Coverage: **partial**. Size: XL (2585 lines of Terraform, 21 variables, 12 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_cloud_run_v2_job` | RunJob |  |
| `google_cloud_run_v2_job_iam_binding` | IAMPartialPolicy -> RunJob |  |
| `google_cloud_run_v2_service` | RunService |  |
| `google_cloud_run_v2_service_iam_binding` | IAMPartialPolicy -> RunService |  |
| `google_cloud_run_v2_worker_pool` | RunWorkerPool | alpha only |
| `google_cloud_run_v2_worker_pool_iam_binding` | none | **gap** |
| `google_eventarc_trigger` | EventarcTrigger |  |
| `google_iap_web_cloud_run_service_iam_binding` | none | **gap** |
| `google_iap_web_cloud_run_service_iam_member` | none | **gap** |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_service_account` | IAMServiceAccount |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |
| `google_vpc_access_connector` | VPCAccessConnector |  |

### billing-account

This module allows managing resources and policies related to a billing account

Rank 20. Terraform module: [`modules/billing-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/billing-account). Coverage: **partial**. Size: M (871 lines of Terraform, 11 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_bigquery_dataset_iam_member` | BigQueryDatasetAccess/BigQueryDataset.spec.access | alpha only |
| `google_billing_account_iam_binding` | IAMPartialPolicy -> BillingAccount |  |
| `google_billing_account_iam_member` | IAMPolicyMember -> BillingAccount |  |
| `google_billing_budget` | BillingBudgetsBudget |  |
| `google_billing_project_info` | Project (spec.billingAccountRef) |  |
| `google_logging_billing_account_sink` | none | **gap** |
| `google_monitoring_notification_channel` | MonitoringNotificationChannel |  |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_pubsub_topic_iam_member` | IAMPolicyMember -> PubSubTopic |  |
| `google_storage_bucket_iam_member` | IAMPolicyMember -> StorageBucket |  |

### logging-bucket

This module manages logging buckets for a project, folder, organization or.

Rank 21. Terraform module: [`modules/logging-bucket`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/logging-bucket). Coverage: **partial**. Size: M (448 lines of Terraform, 12 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_logging_billing_account_bucket_config` | LoggingLogBucket |  |
| `google_logging_folder_bucket_config` | LoggingLogBucket |  |
| `google_logging_linked_dataset` | LoggingLink |  |
| `google_logging_log_view` | LoggingLogView |  |
| `google_logging_log_view_iam_binding` | none | **gap** |
| `google_logging_log_view_iam_member` | none | **gap** |
| `google_logging_organization_bucket_config` | LoggingLogBucket |  |
| `google_logging_project_bucket_config` | LoggingLogBucket |  |
| `google_tags_tag_binding` | TagsTagBinding |  |

### net-firewall-policy

This module allows creation and management of two different firewall policy types

Rank 22. Terraform module: [`modules/net-firewall-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-firewall-policy). Coverage: **partial**. Size: L (1148 lines of Terraform, 13 variables, 1 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_firewall_policy` | ComputeFirewallPolicy |  |
| `google_compute_firewall_policy_association` | ComputeFirewallPolicyAssociation |  |
| `google_compute_firewall_policy_rule` | ComputeFirewallPolicyRule |  |
| `google_compute_network_firewall_policy` | ComputeNetworkFirewallPolicy |  |
| `google_compute_network_firewall_policy_association` | ComputeNetworkFirewallPolicyAssociation |  |
| `google_compute_network_firewall_policy_packet_mirroring_rule` | none | **gap** |
| `google_compute_network_firewall_policy_rule` | ComputeNetworkFirewallPolicyRule | alpha only |
| `google_compute_region_network_firewall_policy` | none | **gap** |
| `google_compute_region_network_firewall_policy_association` | none | **gap** |
| `google_compute_region_network_firewall_policy_rule` | none | **gap** |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |

### vpc-sc

This module offers a unified interface to manage VPC Service Controls [Access Policy](https://cloud.google.com/access-context-manager/docs/c…

Rank 23. Terraform module: [`modules/vpc-sc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/vpc-sc). Coverage: **full**. Size: XL (2010 lines of Terraform, 12 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_access_context_manager_access_level` | AccessContextManagerAccessLevel |  |
| `google_access_context_manager_access_policy` | AccessContextManagerAccessPolicy |  |
| `google_access_context_manager_access_policy_iam_binding` | IAMPartialPolicy -> AccessContextManagerAccessPolicy |  |
| `google_access_context_manager_access_policy_iam_member` | IAMPolicyMember -> AccessContextManagerAccessPolicy |  |
| `google_access_context_manager_service_perimeter` | AccessContextManagerServicePerimeter |  |

### project-factory

This module implements end-to-end creation processes for a folder hierarchy,   projects and billing budgets via YAML data configurations.

Rank 24. Terraform module: [`modules/project-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/project-factory). Coverage: **composite**. Size: XL (3799 lines of Terraform, 8 variables, 16 outputs). composes folder, project, iam-service-account, gcs, kms, pubsub, bigquery-dataset, logging-bucket, billing-account, data-catalog-policy-tag, dataplex-aspect-types; ported by porting those modules and composing them in a Bundt Template.

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_network_security_dns_threat_detector` | NetworkSecurityDNSThreatDetector | alpha only |
| `terraform_data` | n/a | not Google Cloud |

### net-vpc-factory

This module implements the creation of VPCs, subnets, routes, and firewall rules via YAML configurations. It is designed to be embedded in o…

Rank 25. Terraform module: [`modules/net-vpc-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-factory). Coverage: **composite**. Size: S (272 lines of Terraform, 4 variables, 3 outputs). composes net-vpc and net-vpc-firewall; ported by porting those modules and composing them in a Bundt Template.

### net-vpc-peering

This module allows creation of a VPC Network Peering between two networks.

Rank 26. Terraform module: [`modules/net-vpc-peering`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-peering). Coverage: **full**. Size: S (204 lines of Terraform, 7 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_network_peering` | ComputeNetworkPeering |  |

### net-address

This module allows reserving Compute Engine external, global, and internal addresses. The module also supports managing VPC network attachme…

Rank 27. Terraform module: [`modules/net-address`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-address). Coverage: **full, with alpha**. Size: M (613 lines of Terraform, 9 variables, 8 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_address` | ComputeAddress |  |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_global_address` | ComputeAddress |  |
| `google_compute_global_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_network_attachment` | ComputeNetworkAttachment | alpha only |

### net-vpn-ha

This module makes it easy to deploy either GCP-to-GCP or GCP-to-On-prem [Cloud HA VPN](https://cloud.google.com/network-connectivity/docs/vp…

Rank 28. Terraform module: [`modules/net-vpn-ha`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpn-ha). Coverage: **partial**. Size: L (933 lines of Terraform, 19 variables, 18 outputs). submodules or factory data: recipe-vpn-aws-gcp.

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `aws_customer_gateway` | n/a | not Google Cloud |
| `aws_vpc` | n/a | not Google Cloud |
| `aws_vpn_connection` | n/a | not Google Cloud |
| `aws_vpn_gateway` | n/a | not Google Cloud |
| `aws_vpn_gateway_attachment` | n/a | not Google Cloud |
| `aws_vpn_gateway_route_propagation` | n/a | not Google Cloud |
| `google_compute_external_vpn_gateway` | ComputeExternalVPNGateway |  |
| `google_compute_ha_vpn_gateway` | ComputeVPNGateway |  |
| `google_compute_router` | ComputeRouter |  |
| `google_compute_router_interface` | ComputeRouterInterface |  |
| `google_compute_router_peer` | ComputeRouterPeer |  |
| `google_compute_router_route_policy` | none | **gap** |
| `google_compute_vpn_tunnel` | ComputeVPNTunnel |  |
| `random_id` | n/a | not Google Cloud |

### cloud-identity-group

This module allows creating a Cloud Identity group and assigning members.

Rank 29. Terraform module: [`modules/cloud-identity-group`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-identity-group). Coverage: **full**. Size: S (175 lines of Terraform, 6 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_cloud_identity_group` | CloudIdentityGroup |  |
| `google_cloud_identity_group_membership` | CloudIdentityMembership |  |

### dns-response-policy

This module allows management of a Google Cloud DNS policy and its rules.

Rank 30. Terraform module: [`modules/dns-response-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dns-response-policy). Coverage: **full, with alpha**. Size: S (276 lines of Terraform, 9 variables, 3 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_dns_response_policy` | DNSResponsePolicy | alpha only |
| `google_dns_response_policy_rule` | DNSResponsePolicyRule | alpha only |

### certificate-manager

This module allows you to create a certificate manager map and associated entries, certificates, DNS authorizations and issueance configs. M…

Rank 31. Terraform module: [`modules/certificate-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/certificate-manager). Coverage: **full, with alpha**. Size: S (282 lines of Terraform, 5 variables, 5 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_certificate_manager_certificate` | CertificateManagerCertificate |  |
| `google_certificate_manager_certificate_issuance_config` | CertificateManagerCertificateIssuanceConfig | alpha only |
| `google_certificate_manager_certificate_map` | CertificateManagerCertificateMap |  |
| `google_certificate_manager_certificate_map_entry` | CertificateManagerCertificateMapEntry |  |
| `google_certificate_manager_dns_authorization` | CertificateManagerDNSAuthorization |  |

### net-lb-app-ext

This module allows managing Global HTTP/HTTPS Classic Load Balancers (GLBs). It's designed to expose the full configuration of the underlyin…

Rank 32. Terraform module: [`modules/net-lb-app-ext`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-app-ext). Coverage: **full, with alpha**. Size: XL (3127 lines of Terraform, 17 variables, 13 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_backend_bucket` | ComputeBackendBucket |  |
| `google_compute_backend_service` | ComputeBackendService |  |
| `google_compute_global_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_global_network_endpoint` | ComputeGlobalNetworkEndpoint | alpha only |
| `google_compute_global_network_endpoint_group` | ComputeGlobalNetworkEndpointGroup | alpha only |
| `google_compute_health_check` | ComputeHealthCheck |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_managed_ssl_certificate` | ComputeManagedSSLCertificate |  |
| `google_compute_network_endpoint` | ComputeNetworkEndpoint | alpha only |
| `google_compute_network_endpoint_group` | ComputeNetworkEndpointGroup |  |
| `google_compute_region_network_endpoint_group` | ComputeRegionNetworkEndpointGroup |  |
| `google_compute_ssl_certificate` | ComputeSSLCertificate |  |
| `google_compute_target_http_proxy` | ComputeTargetHTTPProxy |  |
| `google_compute_target_https_proxy` | ComputeTargetHTTPSProxy |  |
| `google_compute_url_map` | ComputeURLMap |  |

### net-lb-int

This module allows managing a GCE Internal Load Balancer and integrates the forwarding rule, regional backend, and optional health check res…

Rank 33. Terraform module: [`modules/net-lb-int`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-int). Coverage: **full**. Size: L (1389 lines of Terraform, 24 variables, 19 outputs). submodules or factory data: recipe-ilb-next-hop.

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_health_check` | ComputeHealthCheck |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_region_backend_service` | ComputeBackendService |  |
| `google_compute_region_health_check` | ComputeHealthCheck |  |
| `google_compute_service_attachment` | ComputeServiceAttachment |  |

### net-lb-ext

This module allows managing a GCE Network Load Balancer and integrates the forwarding rule, regional backend, and optional health check reso…

Rank 34. Terraform module: [`modules/net-lb-ext`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-ext). Coverage: **full**. Size: M (646 lines of Terraform, 11 variables, 12 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_region_backend_service` | ComputeBackendService |  |
| `google_compute_region_health_check` | ComputeHealthCheck |  |

### net-lb-app-int

This module allows managing Internal HTTP/HTTPS Load Balancers (L7 ILBs). It's designed to expose the full configuration of the underlying r…

Rank 35. Terraform module: [`modules/net-lb-app-int`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-app-int). Coverage: **partial**. Size: XL (2770 lines of Terraform, 22 variables, 13 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_health_check` | ComputeHealthCheck |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_network_endpoint` | ComputeNetworkEndpoint | alpha only |
| `google_compute_network_endpoint_group` | ComputeNetworkEndpointGroup |  |
| `google_compute_region_backend_service` | ComputeBackendService |  |
| `google_compute_region_health_check` | ComputeHealthCheck |  |
| `google_compute_region_network_endpoint` | none | **gap** |
| `google_compute_region_network_endpoint_group` | ComputeRegionNetworkEndpointGroup |  |
| `google_compute_region_ssl_certificate` | ComputeSSLCertificate |  |
| `google_compute_region_target_http_proxy` | ComputeTargetHTTPProxy |  |
| `google_compute_region_target_https_proxy` | ComputeTargetHTTPSProxy |  |
| `google_compute_region_url_map` | ComputeURLMap |  |
| `google_compute_service_attachment` | ComputeServiceAttachment |  |

### compute-vm

This module can operate in two distinct modes

Rank 36. Terraform module: [`modules/compute-vm`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/compute-vm). Coverage: **partial**. Size: XL (2404 lines of Terraform, 43 variables, 13 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_disk` | ComputeDisk |  |
| `google_compute_disk_resource_policy_attachment` | ComputeDiskResourcePolicyAttachment | alpha only |
| `google_compute_instance` | ComputeInstance |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_instance_group_membership` | ComputeInstanceGroup (spec.instances) |  |
| `google_compute_instance_iam_binding` | IAMPartialPolicy -> ComputeInstance |  |
| `google_compute_instance_template` | ComputeInstanceTemplate |  |
| `google_compute_region_disk` | ComputeDisk |  |
| `google_compute_region_disk_resource_policy_attachment` | ComputeRegionDiskResourcePolicyAttachment | alpha only |
| `google_compute_region_instance_template` | none | **gap** |
| `google_compute_resource_policy` | ComputeResourcePolicy |  |
| `google_iap_tunnel_instance_iam_binding` | none | **gap** |
| `google_iap_tunnel_instance_iam_member` | none | **gap** |
| `google_kms_key_handle` | KMSKeyHandle |  |
| `google_service_account` | IAMServiceAccount |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |
| `google_tpu_v2_queued_resource` | TPUQueuedResource | alpha only |
| `google_tpu_v2_vm` | TPUVirtualMachine | alpha only |

### compute-mig

This module allows creating a managed instance group supporting one or more application versions via instance templates. Optionally, a healt…

Rank 37. Terraform module: [`modules/compute-mig`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/compute-mig). Coverage: **full, with alpha**. Size: L (1085 lines of Terraform, 21 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_autoscaler` | ComputeAutoscaler | alpha only |
| `google_compute_health_check` | ComputeHealthCheck |  |
| `google_compute_instance_group_manager` | ComputeInstanceGroupManager |  |
| `google_compute_per_instance_config` | ComputePerInstanceConfig | alpha only |
| `google_compute_region_autoscaler` | ComputeRegionAutoscaler | alpha only |
| `google_compute_region_instance_group_manager` | ComputeInstanceGroupManager |  |
| `google_compute_region_per_instance_config` | ComputeRegionPerInstanceConfig | alpha only |

### service-directory

This module allows managing a single Service Directory namespace, including multiple services,.

Rank 38. Terraform module: [`modules/service-directory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/service-directory). Coverage: **full**. Size: S (249 lines of Terraform, 8 variables, 7 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_service_directory_endpoint` | ServiceDirectoryEndpoint |  |
| `google_service_directory_namespace` | ServiceDirectoryNamespace |  |
| `google_service_directory_namespace_iam_binding` | IAMPartialPolicy -> ServiceDirectoryNamespace |  |
| `google_service_directory_service` | ServiceDirectoryService |  |
| `google_service_directory_service_iam_binding` | IAMPartialPolicy -> ServiceDirectoryService |  |

### workflows

This module manages Google Cloud Workflows, providing end-to-end support for serverless workflow orchestration, execution call logging, envi…

Rank 39. Terraform module: [`modules/workflows`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/workflows). Coverage: **full, with alpha**. Size: M (798 lines of Terraform, 18 variables, 13 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_cloud_scheduler_job` | CloudSchedulerJob |  |
| `google_cloud_tasks_queue` | TasksQueue | alpha only |
| `google_eventarc_trigger` | EventarcTrigger |  |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_service_account` | IAMServiceAccount |  |
| `google_workflows_workflow` | WorkflowsWorkflow | alpha only |

### cloud-function-v2

Cloud Function management, with support for IAM roles, optional bucket creation and bundle via GCS URI, local zip, or local source folder.

Rank 40. Terraform module: [`modules/cloud-function-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-function-v2). Coverage: **partial**. Size: L (917 lines of Terraform, 25 variables, 14 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_cloud_run_service_iam_binding` | IAMPartialPolicy -> RunService |  |
| `google_cloud_run_service_iam_member` | IAMPolicyMember -> RunService |  |
| `google_cloudfunctions2_function` | CloudFunctions2Function | alpha only |
| `google_cloudfunctions2_function_iam_binding` | none | **gap** |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_service_account` | IAMServiceAccount |  |
| `google_storage_bucket` | StorageBucket |  |
| `google_storage_bucket_object` | none | **gap** |
| `google_vpc_access_connector` | VPCAccessConnector |  |

### alloydb

This module manages the creation of an AlloyDB cluster. It also supports cross-region replication scenario by setting up a secondary cluster…

Rank 41. Terraform module: [`modules/alloydb`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/alloydb). Coverage: **full**. Size: L (1458 lines of Terraform, 33 variables, 30 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_alloydb_cluster` | AlloyDBCluster |  |
| `google_alloydb_instance` | AlloyDBInstance |  |
| `google_alloydb_user` | AlloyDBUser |  |
| `google_tags_location_tag_binding` | TagsLocationTagBinding |  |
| `random_password` | n/a | not Google Cloud |

### spanner-instance

This module allows to create a spanner instance with associated spanner instance config and databases in the instance. Additionally it allow…

Rank 42. Terraform module: [`modules/spanner-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/spanner-instance). Coverage: **full, with alpha**. Size: M (426 lines of Terraform, 7 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_spanner_database` | SpannerDatabase |  |
| `google_spanner_database_iam_binding` | IAMPartialPolicy -> SpannerDatabase |  |
| `google_spanner_database_iam_member` | IAMPolicyMember -> SpannerDatabase |  |
| `google_spanner_instance` | SpannerInstance |  |
| `google_spanner_instance_config` | SpannerInstanceConfig | alpha only |
| `google_spanner_instance_iam_binding` | IAMPartialPolicy -> SpannerInstance |  |
| `google_spanner_instance_iam_member` | IAMPolicyMember -> SpannerInstance |  |

### bigtable-instance

This module allows managing a single BigTable instance, including access configuration and tables.

Rank 43. Terraform module: [`modules/bigtable-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigtable-instance). Coverage: **full**. Size: S (308 lines of Terraform, 11 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_bigtable_gc_policy` | BigtableGCPolicy |  |
| `google_bigtable_instance` | BigtableInstance |  |
| `google_bigtable_instance_iam_binding` | IAMPartialPolicy -> BigtableInstance |  |
| `google_bigtable_table` | BigtableTable |  |

### firestore

This module allows to crete a firestore datatabase, fields, indexes and documents.

Rank 44. Terraform module: [`modules/firestore`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/firestore). Coverage: **full, with alpha**. Size: M (452 lines of Terraform, 7 variables, 7 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_firestore_backup_schedule` | FirestoreBackupSchedule | alpha only |
| `google_firestore_database` | FirestoreDatabase |  |
| `google_firestore_document` | FirestoreDocument | alpha only |
| `google_firestore_field` | FirestoreField | alpha only |
| `google_firestore_index` | FirestoreIndex |  |

### managed-kafka

This module allows simplified creation and management of Google Cloud Managed Kafka clusters, including topics, Kafka Connect clusters, and…

Rank 45. Terraform module: [`modules/managed-kafka`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/managed-kafka). Coverage: **full, with alpha**. Size: S (283 lines of Terraform, 11 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_managed_kafka_cluster` | ManagedKafkaCluster |  |
| `google_managed_kafka_connect_cluster` | ManagedKafkaConnectCluster | alpha only |
| `google_managed_kafka_connector` | ManagedKafkaConnector | alpha only |
| `google_managed_kafka_topic` | ManagedKafkaTopic |  |

### net-cloud-armor

This module provisions and configures Cloud Armor security policies along wi.

Rank 46. Terraform module: [`modules/net-cloud-armor`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-cloud-armor). Coverage: **full, with alpha**. Size: XL (2216 lines of Terraform, 33 variables, 9 outputs). submodules or factory data: recipe-glb-waf, recipe-regional-waf.

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_organization_security_policy` | ComputeOrganizationSecurityPolicy | alpha only |
| `google_compute_organization_security_policy_association` | ComputeOrganizationSecurityPolicyAssociation | alpha only |
| `google_compute_organization_security_policy_rule` | ComputeOrganizationSecurityPolicyRule | alpha only |
| `google_compute_region_security_policy` | ComputeSecurityPolicy |  |
| `google_compute_region_security_policy_rule` | ComputeSecurityPolicy (spec.rule) |  |
| `google_compute_security_policy` | ComputeSecurityPolicy |  |
| `google_compute_security_policy_rule` | ComputeSecurityPolicy (spec.rule) |  |

### net-swp

This module allows creation and management of Secure Web Proxy, and its URL lists.

Rank 47. Terraform module: [`modules/net-swp`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-swp). Coverage: **partial**. Size: M (474 lines of Terraform, 14 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_service_attachment` | ComputeServiceAttachment |  |
| `google_network_security_gateway_security_policy` | NetworkSecurityGatewaySecurityPolicy | alpha only |
| `google_network_security_gateway_security_policy_rule` | none | **gap** |
| `google_network_security_tls_inspection_policy` | NetworkSecurityTLSInspectionPolicy | alpha only |
| `google_network_security_url_lists` | NetworkSecurityURLList | alpha only |
| `google_network_services_gateway` | NetworkServicesGateway |  |

### net-lb-app-ext-regional

This module allows managing External Regional HTTP/HTTPS Application Load Balancers. It's designed to expose the full configuration of the u…

Rank 48. Terraform module: [`modules/net-lb-app-ext-regional`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-app-ext-regional). Coverage: **partial**. Size: XL (2481 lines of Terraform, 19 variables, 10 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_network_endpoint` | ComputeNetworkEndpoint | alpha only |
| `google_compute_network_endpoint_group` | ComputeNetworkEndpointGroup |  |
| `google_compute_region_backend_service` | ComputeBackendService |  |
| `google_compute_region_health_check` | ComputeHealthCheck |  |
| `google_compute_region_network_endpoint` | none | **gap** |
| `google_compute_region_network_endpoint_group` | ComputeRegionNetworkEndpointGroup |  |
| `google_compute_region_ssl_certificate` | ComputeSSLCertificate |  |
| `google_compute_region_target_http_proxy` | ComputeTargetHTTPProxy |  |
| `google_compute_region_target_https_proxy` | ComputeTargetHTTPSProxy |  |
| `google_compute_region_url_map` | ComputeURLMap |  |

### net-lb-app-int-cross-region

This module allows managing Cross-regional Internal HTTP/HTTPS Load Balancers (L7 ILBs). It's designed to expose the full configuration of t…

Rank 49. Terraform module: [`modules/net-lb-app-int-cross-region`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-app-int-cross-region). Coverage: **full, with alpha**. Size: XL (2742 lines of Terraform, 23 variables, 14 outputs). submodules or factory data: recipe-cross-reg-int-app-lb-vm-dns.

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_backend_service` | ComputeBackendService |  |
| `google_compute_global_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_health_check` | ComputeHealthCheck |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_network_endpoint` | ComputeNetworkEndpoint | alpha only |
| `google_compute_network_endpoint_group` | ComputeNetworkEndpointGroup |  |
| `google_compute_region_network_endpoint_group` | ComputeRegionNetworkEndpointGroup |  |
| `google_compute_service_attachment` | ComputeServiceAttachment |  |
| `google_compute_target_http_proxy` | ComputeTargetHTTPProxy |  |
| `google_compute_target_https_proxy` | ComputeTargetHTTPSProxy |  |
| `google_compute_url_map` | ComputeURLMap |  |

### net-lb-proxy-int

This module allows managing Internal TCP proxy Load Balancers. It's designed to expose the full configuration of the underlying resources, a…

Rank 50. Terraform module: [`modules/net-lb-proxy-int`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-proxy-int). Coverage: **partial**. Size: L (958 lines of Terraform, 14 variables, 13 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_network_endpoint` | ComputeNetworkEndpoint | alpha only |
| `google_compute_network_endpoint_group` | ComputeNetworkEndpointGroup |  |
| `google_compute_region_backend_service` | ComputeBackendService |  |
| `google_compute_region_health_check` | ComputeHealthCheck |  |
| `google_compute_region_network_endpoint` | none | **gap** |
| `google_compute_region_network_endpoint_group` | ComputeRegionNetworkEndpointGroup |  |
| `google_compute_region_target_tcp_proxy` | ComputeTargetTCPProxy |  |
| `google_compute_service_attachment` | ComputeServiceAttachment |  |
| `terraform_data` | n/a | not Google Cloud |

### net-lb-proxy-int-cross-region

This module allows managing Cross-region Internal Proxy Network Load Balancers (L4 proxy ILBs). It's designed to expose the full configurati…

Rank 51. Terraform module: [`modules/net-lb-proxy-int-cross-region`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-proxy-int-cross-region). Coverage: **full, with alpha**. Size: M (782 lines of Terraform, 14 variables, 15 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_backend_service` | ComputeBackendService |  |
| `google_compute_global_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_health_check` | ComputeHealthCheck |  |
| `google_compute_instance_group` | ComputeInstanceGroup |  |
| `google_compute_network_endpoint` | ComputeNetworkEndpoint | alpha only |
| `google_compute_network_endpoint_group` | ComputeNetworkEndpointGroup |  |
| `google_compute_region_network_endpoint_group` | ComputeRegionNetworkEndpointGroup |  |
| `google_compute_target_tcp_proxy` | ComputeTargetTCPProxy |  |

### net-vpn-static

This module makes it easy to deploy a [Classic VPN](https://docs.cloud.google.com/network-connectivity/docs/vpn/concepts/overview#classic-vp…

Rank 52. Terraform module: [`modules/net-vpn-static`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpn-static). Coverage: **full**. Size: S (328 lines of Terraform, 9 variables, 9 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_address` | ComputeAddress |  |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_route` | ComputeRoute |  |
| `google_compute_vpn_gateway` | ComputeTargetVPNGateway |  |
| `google_compute_vpn_tunnel` | ComputeVPNTunnel |  |
| `random_id` | n/a | not Google Cloud |

### net-vpn-dynamic

This module makes it easy to deploy a [Classic VPN](https://docs.cloud.google.com/network-connectivity/docs/vpn/concepts/overview#classic-vp…

Rank 53. Terraform module: [`modules/net-vpn-dynamic`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpn-dynamic). Coverage: **partial**. Size: M (515 lines of Terraform, 8 variables, 12 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_address` | ComputeAddress |  |
| `google_compute_forwarding_rule` | ComputeForwardingRule |  |
| `google_compute_router` | ComputeRouter |  |
| `google_compute_router_interface` | ComputeRouterInterface |  |
| `google_compute_router_peer` | ComputeRouterPeer |  |
| `google_compute_router_route_policy` | none | **gap** |
| `google_compute_vpn_gateway` | ComputeTargetVPNGateway |  |
| `google_compute_vpn_tunnel` | ComputeVPNTunnel |  |
| `random_id` | n/a | not Google Cloud |

### net-vlan-attachment

This module allows for the provisioning of VLAN Attachments for [Dedicated Interconnect](https://cloud.google.com/network-connectivity/docs/…

Rank 54. Terraform module: [`modules/net-vlan-attachment`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vlan-attachment). Coverage: **partial**. Size: M (557 lines of Terraform, 15 variables, 9 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_address` | ComputeAddress |  |
| `google_compute_interconnect_attachment` | ComputeInterconnectAttachment |  |
| `google_compute_router` | ComputeRouter |  |
| `google_compute_router_interface` | ComputeRouterInterface |  |
| `google_compute_router_peer` | ComputeRouterPeer |  |
| `google_compute_router_route_policy` | none | **gap** |
| `random_id` | n/a | not Google Cloud |

### net-ipsec-over-interconnect

This module allows for the provisioning of [HA VPN over Interconnect](https://cloud.google.com/network-connectivity/docs/interconnect/concep…

Rank 55. Terraform module: [`modules/net-ipsec-over-interconnect`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-ipsec-over-interconnect). Coverage: **partial**. Size: M (470 lines of Terraform, 8 variables, 9 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_external_vpn_gateway` | ComputeExternalVPNGateway |  |
| `google_compute_ha_vpn_gateway` | ComputeVPNGateway |  |
| `google_compute_router` | ComputeRouter |  |
| `google_compute_router_interface` | ComputeRouterInterface |  |
| `google_compute_router_peer` | ComputeRouterPeer |  |
| `google_compute_router_route_policy` | none | **gap** |
| `google_compute_vpn_tunnel` | ComputeVPNTunnel |  |
| `random_id` | n/a | not Google Cloud |

### ncc-spoke-ra

This module allows management of NCC Spokes backed by Router Appliances. Network virtual appliances used as router appliances allow to conne…

Rank 56. Terraform module: [`modules/ncc-spoke-ra`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/ncc-spoke-ra). Coverage: **partial**. Size: M (400 lines of Terraform, 8 variables, 5 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_router` | ComputeRouter |  |
| `google_compute_router_interface` | ComputeRouterInterface |  |
| `google_compute_router_peer` | ComputeRouterPeer |  |
| `google_compute_router_route_policy` | none | **gap** |
| `google_network_connectivity_hub` | NetworkConnectivityHub |  |
| `google_network_connectivity_spoke` | NetworkConnectivitySpoke |  |

### gke-hub

This module allows simplified creation and management of a GKE Hub object and its features for a given set of clusters. The given list of cl…

Rank 57. Terraform module: [`modules/gke-hub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-hub). Coverage: **full**. Size: M (655 lines of Terraform, 8 variables, 1 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_gke_hub_feature` | GKEHubFeature |  |
| `google_gke_hub_feature_membership` | GKEHubFeatureMembership |  |
| `google_gke_hub_membership` | GKEHubMembership |  |

### binauthz

This module simplifies the creation of a Binary Authorization policy, attestors and attestor IAM bindings.

Rank 58. Terraform module: [`modules/binauthz`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/binauthz). Coverage: **partial**. Size: S (234 lines of Terraform, 5 variables, 3 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_binary_authorization_attestor` | BinaryAuthorizationAttestor |  |
| `google_binary_authorization_attestor_iam_binding` | none | **gap** |
| `google_binary_authorization_policy` | BinaryAuthorizationPolicy |  |
| `google_container_analysis_note` | ContainerAnalysisNote |  |

### certificate-authority-service

The module allows you to create one or more CAs and an optional CA pool.

Rank 59. Terraform module: [`modules/certificate-authority-service`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/certificate-authority-service). Coverage: **partial**. Size: M (547 lines of Terraform, 9 variables, 5 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_privateca_ca_pool` | PrivateCACAPool |  |
| `google_privateca_ca_pool_iam_binding` | none | **gap** |
| `google_privateca_ca_pool_iam_member` | none | **gap** |
| `google_privateca_certificate_authority` | PrivateCACertificateAuthority |  |

### backup-dr

This Terraform module creates a Google Cloud Backup and DR backup plan and, optionally, a backup vault.

Rank 60. Terraform module: [`modules/backup-dr`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/backup-dr). Coverage: **full, with alpha**. Size: S (259 lines of Terraform, 7 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_backup_dr_backup_plan` | BackupDRBackupPlan |  |
| `google_backup_dr_backup_vault` | BackupDRBackupVault |  |
| `google_backup_dr_management_server` | BackupDRManagementServer | alpha only |

### cloud-deploy

Cloud Deploy Module for creating and managing Delivery Pipelines, Targets, Automations, Deploy Policies and resource-level IAM roles.

Rank 61. Terraform module: [`modules/cloud-deploy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-deploy). Coverage: **partial**. Size: L (1123 lines of Terraform, 14 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_clouddeploy_automation` | CloudDeployAutomation | alpha only |
| `google_clouddeploy_delivery_pipeline` | CloudDeployDeliveryPipeline |  |
| `google_clouddeploy_delivery_pipeline_iam_binding` | none | **gap** |
| `google_clouddeploy_delivery_pipeline_iam_member` | none | **gap** |
| `google_clouddeploy_deploy_policy` | CloudDeployDeployPolicy | alpha only |
| `google_clouddeploy_target` | CloudDeployTarget | alpha only |
| `google_clouddeploy_target_iam_binding` | none | **gap** |
| `google_clouddeploy_target_iam_member` | none | **gap** |

### cloud-build-v2-connection

This module allows to create a Cloud Build v2 connection with associated repositories and triggers linked to each of them. Additionally, it…

Rank 62. Terraform module: [`modules/cloud-build-v2-connection`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-build-v2-connection). Coverage: **partial**. Size: M (546 lines of Terraform, 13 variables, 5 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_cloudbuild_trigger` | CloudBuildTrigger |  |
| `google_cloudbuildv2_connection` | CloudBuildConnection | alpha only |
| `google_cloudbuildv2_connection_iam_binding` | none | **gap** |
| `google_cloudbuildv2_connection_iam_member` | none | **gap** |
| `google_cloudbuildv2_repository` | none | **gap** |

### secure-source-manager-instance

This module allows to create a Secure Source Manager instance and repositories in it. Additionally it allows creating instance IAM bindings…

Rank 63. Terraform module: [`modules/secure-source-manager-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/secure-source-manager-instance). Coverage: **partial**. Size: S (381 lines of Terraform, 11 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_secure_source_manager_branch_rule` | SecureSourceManagerBranchRule | alpha only |
| `google_secure_source_manager_instance` | SecureSourceManagerInstance |  |
| `google_secure_source_manager_instance_iam_binding` | none | **gap** |
| `google_secure_source_manager_instance_iam_member` | none | **gap** |
| `google_secure_source_manager_repository` | SecureSourceManagerRepository |  |
| `google_secure_source_manager_repository_iam_binding` | none | **gap** |
| `google_secure_source_manager_repository_iam_member` | none | **gap** |

### source-repository

This module allows managing a single Cloud Source Repository, including IAM bindings and basic Cloud Build triggers.

Rank 64. Terraform module: [`modules/source-repository`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/source-repository). Coverage: **full**. Size: S (276 lines of Terraform, 7 variables, 3 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_cloudbuild_trigger` | CloudBuildTrigger |  |
| `google_sourcerepo_repository` | SourceRepoRepository |  |
| `google_sourcerepo_repository_iam_binding` | IAMPartialPolicy -> SourceRepoRepository |  |
| `google_sourcerepo_repository_iam_member` | IAMPolicyMember -> SourceRepoRepository |  |

### bigquery-connection

This module allows creating a BigQuery connection.

Rank 65. Terraform module: [`modules/bigquery-connection`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigquery-connection). Coverage: **partial**. Size: S (391 lines of Terraform, 12 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_bigquery_connection` | BigQueryConnectionConnection |  |
| `google_bigquery_connection_iam_binding` | none | **gap** |
| `google_bigquery_connection_iam_member` | none | **gap** |

### analytics-hub

This module allows managing Analytics Hub Exchange and Listing resource.

Rank 66. Terraform module: [`modules/analytics-hub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/analytics-hub). Coverage: **partial**. Size: S (358 lines of Terraform, 14 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_bigquery_analytics_hub_data_exchange` | BigQueryAnalyticsHubDataExchange |  |
| `google_bigquery_analytics_hub_data_exchange_iam_binding` | none | **gap** |
| `google_bigquery_analytics_hub_data_exchange_iam_member` | none | **gap** |
| `google_bigquery_analytics_hub_listing` | BigQueryAnalyticsHubListing |  |
| `google_bigquery_analytics_hub_listing_iam_binding` | none | **gap** |

### biglake-catalog

This module allows to create a BigLake Metastore with databases and corresponding tables in each database.

Rank 67. Terraform module: [`modules/biglake-catalog`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/biglake-catalog). Coverage: **full, with alpha**. Size: S (156 lines of Terraform, 4 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_biglake_catalog` | BigLakeCatalog | alpha only |
| `google_biglake_database` | BigLakeDatabase | alpha only |
| `google_biglake_table` | BigLakeTable |  |

### dataform-repository

This module allows managing a dataform repository, allows adding IAM permissions. Also enables attaching a remote repository.

Rank 68. Terraform module: [`modules/dataform-repository`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataform-repository). Coverage: **partial**. Size: S (215 lines of Terraform, 8 variables, 0 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_dataform_repository` | DataformRepository |  |
| `google_dataform_repository_iam_binding` | none | **gap** |
| `google_dataform_repository_iam_member` | none | **gap** |

### dataproc

This module Manages a Google Cloud Dataproc cluster resource, including IAM.

Rank 69. Terraform module: [`modules/dataproc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataproc). Coverage: **full**. Size: M (720 lines of Terraform, 9 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_dataproc_cluster` | DataprocCluster |  |
| `google_dataproc_cluster_iam_binding` | IAMPartialPolicy -> DataprocCluster |  |
| `google_dataproc_cluster_iam_member` | IAMPolicyMember -> DataprocCluster |  |

### datafusion

This module allows simple management of 'Google Data Fusion' instances. It supports creating Basic o.

Rank 70. Terraform module: [`modules/datafusion`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/datafusion). Coverage: **full**. Size: S (257 lines of Terraform, 14 variables, 6 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_compute_firewall` | ComputeFirewall |  |
| `google_compute_global_address` | ComputeAddress |  |
| `google_compute_network_peering` | ComputeNetworkPeering |  |
| `google_data_fusion_instance` | DataFusionInstance |  |

### dataplex

This module manages the creation of a Dataplex instance along with lake, zone & assets in single regions.

Rank 71. Terraform module: [`modules/dataplex`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataplex). Coverage: **partial**. Size: S (263 lines of Terraform, 7 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_dataplex_asset` | DataplexAsset | alpha only |
| `google_dataplex_lake` | DataplexLake | alpha only |
| `google_dataplex_lake_iam_binding` | none | **gap** |
| `google_dataplex_zone` | DataplexZone | alpha only |
| `google_dataplex_zone_iam_binding` | none | **gap** |

### dataplex-datascan

This module manages the creation of Dataplex DataScan resources.

Rank 72. Terraform module: [`modules/dataplex-datascan`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataplex-datascan). Coverage: **partial**. Size: M (765 lines of Terraform, 16 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_dataplex_datascan` | DataplexDataScan | alpha only |
| `google_dataplex_datascan_iam_binding` | none | **gap** |
| `google_dataplex_datascan_iam_member` | none | **gap** |

### dataplex-aspect-types

This module allows managing Dataplex Aspect Types and their associated IAM.

Rank 73. Terraform module: [`modules/dataplex-aspect-types`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataplex-aspect-types). Coverage: **partial**. Size: S (343 lines of Terraform, 5 variables, 4 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_dataplex_aspect_type` | DataplexAspectType | alpha only |
| `google_dataplex_aspect_type_iam_binding` | none | **gap** |
| `google_dataplex_aspect_type_iam_member` | none | **gap** |

### data-catalog-policy-tag

This module simplifies the creation of Data Catalog Policy Tags. Policy Tags can be used to configu.

Rank 74. Terraform module: [`modules/data-catalog-policy-tag`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/data-catalog-policy-tag). Coverage: **full**. Size: M (474 lines of Terraform, 12 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_data_catalog_policy_tag` | DataCatalogPolicyTag |  |
| `google_data_catalog_policy_tag_iam_binding` | IAMPartialPolicy -> DataCatalogPolicyTag |  |
| `google_data_catalog_policy_tag_iam_member` | IAMPolicyMember -> DataCatalogPolicyTag |  |
| `google_data_catalog_taxonomy` | DataCatalogTaxonomy |  |
| `google_data_catalog_taxonomy_iam_binding` | IAMPartialPolicy -> DataCatalogTaxonomy |  |
| `google_data_catalog_taxonomy_iam_member` | IAMPolicyMember -> DataCatalogTaxonomy |  |

### data-catalog-tag

This module allows managing Data Catalog Tag on GCP resources such as B.

Rank 75. Terraform module: [`modules/data-catalog-tag`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/data-catalog-tag). Coverage: **full, with alpha**. Size: S (146 lines of Terraform, 2 variables, 1 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_data_catalog_tag` | DataCatalogTag | alpha only |

### data-catalog-tag-template

This module allows managing Data Catalog Tag Templates.

Rank 76. Terraform module: [`modules/data-catalog-tag-template`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/data-catalog-tag-template). Coverage: **partial**. Size: S (351 lines of Terraform, 4 variables, 2 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_data_catalog_tag_template` | DataCatalogTagTemplate | alpha only |
| `google_data_catalog_tag_template_iam_binding` | none | **gap** |
| `google_data_catalog_tag_template_iam_member` | none | **gap** |

### api-gateway

This module allows creating an API with its associated API config and API gateway. It also allows you grant IAM roles on the created resourc…

Rank 77. Terraform module: [`modules/api-gateway`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/api-gateway). Coverage: **partial**. Size: M (522 lines of Terraform, 11 variables, 11 outputs). submodules or factory data: recipe-multi-region.

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_api_gateway_api` | APIGatewayAPI |  |
| `google_api_gateway_api_config` | APIGatewayAPIConfig | alpha only |
| `google_api_gateway_api_config_iam_binding` | none | **gap** |
| `google_api_gateway_api_iam_binding` | none | **gap** |
| `google_api_gateway_gateway` | APIGatewayGateway | alpha only |
| `google_api_gateway_gateway_iam_binding` | none | **gap** |
| `google_compute_region_network_endpoint_group` | ComputeRegionNetworkEndpointGroup |  |
| `google_project_service` | Service |  |
| `google_service_account` | IAMServiceAccount |  |
| `tls_private_key` | n/a | not Google Cloud |
| `tls_self_signed_cert` | n/a | not Google Cloud |

### apigee

This module simplifies the creation of a Apigee resources (organization, environment groups, environment group attachments, environments, in…

Rank 78. Terraform module: [`modules/apigee`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/apigee). Coverage: **partial**. Size: M (827 lines of Terraform, 13 variables, 10 outputs). submodules or factory data: recipe-apigee-swp.

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_apigee_addons_config` | ApigeeAddonsConfig | alpha only |
| `google_apigee_dns_zone` | none | **gap** |
| `google_apigee_endpoint_attachment` | ApigeeEndpointAttachment |  |
| `google_apigee_envgroup` | ApigeeEnvgroup |  |
| `google_apigee_envgroup_attachment` | ApigeeEnvgroupAttachment |  |
| `google_apigee_environment` | ApigeeEnvironment |  |
| `google_apigee_environment_iam_binding` | IAMPartialPolicy -> ApigeeEnvironment |  |
| `google_apigee_environment_iam_member` | IAMPolicyMember -> ApigeeEnvironment |  |
| `google_apigee_instance` | ApigeeInstance |  |
| `google_apigee_instance_attachment` | ApigeeInstanceAttachment |  |
| `google_apigee_nat_address` | ApigeeNATAddress | alpha only |
| `google_apigee_organization` | ApigeeOrganization |  |
| `local_file` | n/a | not Google Cloud |

### endpoints

This module allows simple management of 'Google Cloud Endpoints' services. It supports creating ['Ope.

Rank 79. Terraform module: [`modules/endpoints`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/endpoints). Coverage: **none**. Size: S (143 lines of Terraform, 5 variables, 3 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_endpoints_service` | none | **gap** |
| `google_endpoints_service_iam_binding` | none | **gap** |

### cloud-function-v1

Cloud Function management, with support for IAM roles, optional bucket creation and bundle via GCS URI, local zip, or local source folder.

Rank 80. Terraform module: [`modules/cloud-function-v1`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-function-v1). Coverage: **partial**. Size: M (759 lines of Terraform, 24 variables, 10 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_cloudfunctions_function` | CloudFunctionsFunction |  |
| `google_cloudfunctions_function_iam_binding` | IAMPartialPolicy -> CloudFunctionsFunction |  |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_service_account` | IAMServiceAccount |  |
| `google_storage_bucket` | StorageBucket |  |
| `google_storage_bucket_object` | none | **gap** |
| `google_vpc_access_connector` | VPCAccessConnector |  |

### workstation-cluster

This module allows to create a workstation cluster with associated workstation configs and workstations. In addition to this it allows to se…

Rank 81. Terraform module: [`modules/workstation-cluster`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/workstation-cluster). Coverage: **partial**. Size: M (738 lines of Terraform, 12 variables, 5 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_workstations_workstation` | Workstation |  |
| `google_workstations_workstation_cluster` | WorkstationCluster |  |
| `google_workstations_workstation_config` | WorkstationConfig |  |
| `google_workstations_workstation_config_iam_binding` | none | **gap** |
| `google_workstations_workstation_config_iam_member` | none | **gap** |
| `google_workstations_workstation_iam_binding` | none | **gap** |
| `google_workstations_workstation_iam_member` | none | **gap** |

### gcve-private-cloud

The module manages one or more Google Cloud VMWare Engine Private Clouds.

Rank 82. Terraform module: [`modules/gcve-private-cloud`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gcve-private-cloud). Coverage: **full, with alpha**. Size: S (337 lines of Terraform, 5 variables, 5 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_vmwareengine_cluster` | VMwareEngineCluster | alpha only |
| `google_vmwareengine_network` | VMwareEngineNetwork | alpha only |
| `google_vmwareengine_network_peering` | VMwareEngineNetworkPeering | alpha only |
| `google_vmwareengine_network_policy` | VMwareEngineNetworkPolicy | alpha only |
| `google_vmwareengine_private_cloud` | VMwareEnginePrivateCloud | alpha only |

### looker-core

This module manages the creation of a Looker Core instance.

Rank 83. Terraform module: [`modules/looker-core`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/looker-core). Coverage: **none**. Size: M (435 lines of Terraform, 15 variables, 11 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_looker_instance` | none | **gap** |

### ai-applications

This module handles the creation of AI Applications data sources, en.

Rank 84. Terraform module: [`modules/ai-applications`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/ai-applications). Coverage: **partial**. Size: L (1666 lines of Terraform, 8 variables, 8 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_data_loss_prevention_deidentify_template` | DLPDeidentifyTemplate |  |
| `google_data_loss_prevention_inspect_template` | DLPInspectTemplate |  |
| `google_dialogflow_cx_agent` | DialogflowCXAgent | alpha only |
| `google_dialogflow_cx_security_settings` | DialogflowSecuritySettings | alpha only |
| `google_discovery_engine_chat_engine` | DiscoveryEngineEngine | alpha only |
| `google_discovery_engine_cmek_config` | none | **gap** |
| `google_discovery_engine_data_store` | DiscoveryEngineDataStore | alpha only |
| `google_discovery_engine_schema` | DiscoveryEngineSchema | alpha only |
| `google_discovery_engine_search_engine` | DiscoveryEngineEngine | alpha only |
| `google_discovery_engine_sitemap` | DiscoveryEngineSitemap | alpha only |
| `google_discovery_engine_target_site` | DiscoveryEngineDataStoreTargetSite | alpha only |

### geap-agent-gateway

The module facilitates the deployments of Gemini Enterprise Agent Platform (GEAP) - Agent Gateways.

Rank 85. Terraform module: [`modules/geap-agent-gateway`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/geap-agent-gateway). Coverage: **partial**. Size: L (920 lines of Terraform, 15 variables, 7 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_iam_project_access_policy` | IAMAccessPolicy | alpha only |
| `google_iam_projects_policy_binding` | none | **gap** |
| `google_network_security_authz_policy` | NetworkSecurityAuthzPolicy | alpha only |
| `google_network_services_agent_connectivity_template` | none | **gap** |
| `google_network_services_agent_gateway` | none | **gap** |
| `google_network_services_authz_extension` | NetworkServicesAuthzExtension | alpha only |

### geap-agent-runtime

The module deploys Gemini Enterprise Agent Platform (GEAP) - Agent Runtime and related dependencies.

Rank 86. Terraform module: [`modules/geap-agent-runtime`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/geap-agent-runtime). Coverage: **partial**. Size: L (1132 lines of Terraform, 14 variables, 3 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_project_iam_member` | IAMPolicyMember -> Project |  |
| `google_service_account` | IAMServiceAccount |  |
| `google_storage_bucket` | StorageBucket |  |
| `google_storage_bucket_object` | none | **gap** |
| `google_vertex_ai_reasoning_engine` | AIPlatformReasoningEngine | alpha only |

### geap-workbench

This module manages Gemini Enterprise Agent Platform (GEAP) Workbench (Jupyter Notebook) instances, supporting machine types, GPU hardware a…

Rank 87. Terraform module: [`modules/geap-workbench`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/geap-workbench). Coverage: **partial**. Size: M (668 lines of Terraform, 30 variables, 11 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_service_account` | IAMServiceAccount |  |
| `google_workbench_instance` | NotebookInstanceV2 | alpha only |
| `google_workbench_instance_iam_binding` | none | **gap** |

### secops-rules

This module allows creation and management of custom rules as well as [r.

Rank 88. Terraform module: [`modules/secops-rules`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/secops-rules). Coverage: **partial**. Size: S (180 lines of Terraform, 5 variables, 0 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_chronicle_reference_list` | ChronicleReferenceList | alpha only |
| `google_chronicle_rule` | ChronicleRule | alpha only |
| `google_chronicle_rule_deployment` | none | **gap** |

### container-registry

This module simplifies the creation of GCS buckets used by Google Container Registry.

Rank 89. Terraform module: [`modules/container-registry`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/container-registry). Coverage: **none**. Size: S (113 lines of Terraform, 3 variables, 1 outputs).

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `google_container_registry` | none | **gap** |
| `google_storage_bucket_iam_binding` | IAMPartialPolicy -> StorageBucket |  |

### projects-data-source

This module extends functionality of [google_projects](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/pro…

Rank 90. Terraform module: [`modules/projects-data-source`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/projects-data-source). Coverage: **n/a**. Size: S (169 lines of Terraform, 5 variables, 2 outputs). data sources only (a read, not a resource).

### cloud-config-container

This set of modules creates specialized [cloud-config](https://cloud.google.com/container-optimized-os/docs/how-to/run-container-instance#st…

Rank 91. Terraform module: [`modules/cloud-config-container`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-config-container). Coverage: **n/a**. Size: L (1954 lines of Terraform, 72 variables, 11 outputs). generates cloud-init text; no resources; submodules or factory data: nginx-tls, envoy-sni-dyn-fwd-proxy, nginx, envoy-traffic-director, mysql, cos-generic-metadata ….

| Terraform resource | Config Connector | |
| --- | --- | --- |
| `random_uuid` | n/a | not Google Cloud |

