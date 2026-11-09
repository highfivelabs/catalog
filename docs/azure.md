# Azure seed catalog: Azure Verified Modules mapped to ASO v2

The builder asked for this (verbatim): "For azure may need to look at the tf
registry for usage data and where canonical modules are stored."

This is an inventory. It says where Azure's canonical Terraform modules live,
ranks them by use, lists what the top modules create, maps each one to Azure
Service Operator v2 (ASO) kinds, and ranks the gaps for `aso-extensions`. It
ends with a kro verdict. Nothing was built.

## Summary

- **Canonical modules are Azure Verified Modules (AVM).**
  - They are published in the Terraform Registry under the namespace `Azure`.
  - Their source is `github.com/Azure/terraform-azurerm-avm-{res,ptn,utl}-*`,
    and for newer modules `github.com/Azure/terraform-azure-avm-*`.
  - The official index is the CSV files in `Azure/Azure-Verified-Modules`.
  - Every older `Azure/terraform-azurerm-*` module checked is **archived**.
    That includes `aks`, `vnet`, `network`, `caf-enterprise-scale`,
    `lz-vending` and `naming`.
- **Current AVM modules are mostly `azapi`.** They declare raw ARM resources,
  `azapi_resource` with `type = "Microsoft.X/y@<api-version>"`, not
  `azurerm_*`. ASO is generated from the same ARM specs, so an AVM module's
  `azapi` body maps nearly one-to-one onto an ASO spec. Porting AVM to
  ASO-backed charts is closer to transcription than translation. The catch
  is the API version: AVM often pins a newer one than ASO has released.
- **By yearly downloads**, the top ten resource modules are:
  1. virtual network;
  2. network security group;
  3. storage account;
  4. Key Vault;
  5. virtual machine;
  6. resource group;
  7. user-assigned identity;
  8. Log Analytics workspace;
  9. route table;
  10. NAT gateway.

  ASO covers the main resource of all ten, and of 24 of the top 25.
- **Gaps.** The biggest by count is **management locks**
  (`Microsoft.Authorization/locks`). 31 of the 33 modules read for this
  inventory accept a `lock`, and ASO has none (issue #3756, open). After that
  come:
  - Key Vault secrets, already built in aso-extensions as `VaultSecret`;
  - the child resources of Container Apps environments, App Service sites
    and Log Analytics workspaces;
  - the Azure Monitor private link scope;
  - management groups and Azure Policy.
- **kro verdict: not worth it for Azure.** ASO already wires status into spec
  without kro:
  - parent and child resources are linked by `owner`;
  - other resources are linked by `*Reference` fields;
  - values move through CEL `operatorSpec.configMapExpressions` exports and
    `*FromConfig` fields, such as `FederatedIdentityCredential.issuerFromConfig`
    and `RoleAssignment.principalIdFromConfig`.

  Helm (or `manifests`) for every Package in the top 25.

## Sources and pins

Read on 2026-11-09 (UTC), read-only, with `gh api` and `curl`.

| Source | Pin |
| --- | --- |
| Terraform Registry v1, `GET /v1/modules/Azure?limit=100&offset=...` (all modules in the namespace, total downloads) | 2026-11-09 07:37 UTC; 201 modules |
| Terraform Registry v2, `GET /v2/modules/Azure/<name>/<provider>/downloads/summary` (week, month, year, total) | 2026-11-09 07:39 UTC |
| Terraform Registry v1, `GET /v1/modules/Azure/<name>/<provider>` (resources per root and submodule) | 2026-11-09 07:40 UTC |
| AVM index: `Azure/Azure-Verified-Modules` `docs/static/module-indexes/Terraform{Resource,Pattern,Utility}Modules.csv` | `2f1a487902191fe243b57e580e0686434e80de48` (2026-11-06) |
| Module sources: each module's tarball at its latest tag, searched for `Microsoft.*@<version>` types (`examples/` and `tests/` excluded) | tags and commits in the ranking table |
| ASO v2 supported resources: `docs/hugo/content/reference/_index.md` | v2.22.0 (2026-10-30), `03b1e9142cdff81c573f2d3492dc4c5e1817cd2e` |
| ASO generated types (for `*FromConfig` fields) | v2.22.0, `v2/api/managedidentity/v1api20230131`, `v2/api/authorization/v1api20220401` |
| ASO issues | `gh search issues --repo Azure/azure-service-operator`, 2026-11-09 |
| aso-extensions | `aso-extensions/docs/plan.md`, local, as of 2026-11-09 |
| kro | `kubernetes-sigs/kro` v0.9.4, `4ba0e410fd8c87ff5d2df638b6942d46766995f7` |

**Ranking key.** Modules are ranked by downloads in the last year, from the
v2 summary. The v2 `week` figure is nearly equal to `month` for every module,
which looks wrong, so it is not used.

## 1. Where the canonical modules live

**AVM is canonical**, confirmed three ways:

1. **The index.** `Azure/Azure-Verified-Modules` publishes three CSVs, at
   commit `2f1a487`:

   | Index | Rows | Status |
   | --- | --- | --- |
   | Resource | 162 | 119 Available, 41 Proposed, 2 Orphaned |
   | Pattern | 64 | 34 Available, 27 Proposed, 3 Deprecated |
   | Utility | 6 | 6 Available |

   Each row names its ARM resource type, its GitHub repository and its
   registry path.
2. **The registry.** Of the 201 modules in namespace `Azure`, 164 are AVM
   (121 `avm-res-*`, 37 `avm-ptn-*`, 6 `avm-utl-*`) and 37 are not.
3. **The older modules are archived.** Eleven `Azure/terraform-azurerm-*`
   repositories were checked: `naming`, `vnet`, `network`,
   `network-security-group`, `aks`, `caf-enterprise-scale`, `lz-vending`,
   `regions`, `compute`, `loadbalancer` and `postgresql`. All are archived.
   Their AVM successors:

   | Archived | AVM successor |
   | --- | --- |
   | `vnet`, `network` | `avm-res-network-virtualnetwork` |
   | `aks` | `avm-res-containerservice-managedcluster` |
   | `caf-enterprise-scale` | `avm-ptn-alz` |
   | `lz-vending` | `avm-ptn-alz-sub-vending` |
   | `naming` | `avm-utl-naming` |

**Two repository naming schemes.**

- `terraform-azurerm-avm-<kind>-<service>-<resource>`: registry provider
  `azurerm`, most modules.
- `terraform-azure-avm-<...>`: registry provider `azure`. 13 registry
  modules use it, including `avm-utl-interfaces`, `avm-ptn-alz-sub-vending`,
  `avm-utl-naming` and `avm-res-appconfiguration-configurationstore`. These
  are the provider-neutral (`azapi`-only) modules.

**AVM's shared "interfaces."** Every resource module takes the same optional
inputs, through `avm-utl-interfaces`:

- `lock`;
- `role_assignments`;
- `diagnostic_settings`;
- `private_endpoints`;
- `managed_identities`;
- `customer_managed_key`.

Across the 33 modules read here:

| Interface | Modules | ASO kind |
| --- | --- | --- |
| `role_assignments` | 33 | `RoleAssignment` |
| `lock` | 31 | none |
| `diagnostic_settings` | 23 | `DiagnosticSetting` |
| `private_endpoints` | 12 | `PrivateEndpoint` and `PrivateEndpointsPrivateDnsZoneGroup` |
| `customer_managed_key` | 5 | a field of the parent |

A Bundt port should implement these once, as a shared Helm library chart,
not per module.

**AVM telemetry.** Most modules create a `modtm_telemetry` resource and an
empty `Microsoft.Resources/deployments` deployment to count usage. A port
drops both.

**Licence.** Every module read, AVM and archived alike, is MIT, "Copyright
(c) Microsoft Corporation." ASO is MIT too.

## 2. Ranking

"Year" is downloads in the last year; "Total" is all time. The `azure`
provider marks a `terraform-azure-avm-*` repository. Archived modules and
modules that create no Azure resource (`naming`, `regions`, `avm-utl-*`)
are listed, but are not seeds.

| # | Module | Provider | Year | Total | Tag, commit |
| --- | --- | --- | --- | --- | --- |
| 1 | naming (archived; no resources) | azurerm | 8,336,284 | 22,898,636 | |
| 2 | avm-res-network-virtualnetwork | azurerm | 7,131,017 | 8,259,157 | v0.23.0 `874b2d1ce38c` |
| 3 | avm-utl-interfaces (no resources) | azure | 6,597,108 | 6,936,367 | |
| 4 | avm-res-network-networksecuritygroup | azurerm | 4,108,779 | 4,856,855 | v0.6.0 `c5283612e428` |
| 5 | avm-res-storage-storageaccount | azurerm | 3,964,392 | 5,401,219 | v0.11.0 `226f9bbefcc9` |
| 6 | avm-res-keyvault-vault | azurerm | 3,794,829 | 5,229,598 | v0.13.0 `7c53adbc7f4f` |
| 7 | avm-res-compute-virtualmachine | azurerm | 3,681,412 | 4,168,285 | v0.21.0 `a6e951bdebcf` |
| 8 | avm-utl-regions (no resources) | azurerm | 3,314,606 | 4,464,361 | |
| 9 | avm-res-resources-resourcegroup | azurerm | 2,753,674 | 3,728,662 | v0.5.0 `4c7e926d9aa1` |
| 10 | avm-res-managedidentity-userassignedidentity | azurerm | 2,520,215 | 3,565,638 | v0.6.0 `7a0c461789f0` |
| 11 | avm-res-operationalinsights-workspace | azurerm | 1,129,542 | 1,583,538 | v0.5.1 `b4ffa3ff87ac` |
| 12 | avm-res-network-routetable | azurerm | 1,087,375 | 1,566,240 | v0.6.0 `7482f30b5f92` |
| 13 | avm-res-network-natgateway | azurerm | 1,057,695 | 1,178,796 | v0.3.2 `597df2389d99` |
| 14 | avm-res-network-privatednszone | azurerm | 1,032,578 | 1,623,379 | v0.6.0 `97ed94c12535` |
| 15 | avm-utl-roledefinitions (no resources) | azure | 783,679 | 806,072 | |
| 16 | avm-res-network-publicipaddress | azurerm | 767,152 | 1,148,881 | v0.2.1 `2790d091b373` |
| 17 | avm-res-network-loadbalancer | azurerm | 716,805 | 803,838 | v0.5.0 `e83d34778efe` |
| 18 | avm-res-containerregistry-registry | azurerm | 691,266 | 974,026 | v0.9.0 `7f2dc78bb5db` |
| 19 | avm-res-network-firewallpolicy | azurerm | 660,760 | 1,017,127 | v0.3.4 `8580240f33fe` |
| 20 | avm-res-containerservice-managedcluster | azurerm | 653,189 | 828,090 | v0.9.0 `1925e0490783` |
| 21 | lz-vending (archived) | azurerm | 645,346 | 1,512,101 | v7.0.3 `ddc6b5989a01` |
| 22 | avm-res-dbforpostgresql-flexibleserver | azurerm | 627,646 | 749,702 | v0.2.3 `70d6e9c947f8` |
| 23 | avm-res-cognitiveservices-account | azurerm | 607,551 | 1,148,932 | v0.11.1 `02ac1c992bba` |
| 24 | avm-ptn-alz-sub-vending | azure | 570,438 | 574,735 | v0.3.4 `28577b03cf4a` |
| 25 | avm-res-insights-component | azurerm | 564,949 | 730,504 | v0.5.0 `8c75ae7771d6` |
| 26 | avm-res-app-containerapp | azurerm | 564,500 | 661,369 | v0.9.0 `ae03166abab0` |
| 27 | avm-res-web-site | azurerm | 562,169 | 819,963 | v0.24.1 `56c704e9f440` |
| 28 | avm-res-network-privateendpoint | azurerm | 531,573 | 838,784 | v0.3.1 `84e427dd16ca` |
| 29 | avm-res-authorization-roleassignment | azurerm | 497,839 | 672,657 | v0.3.1 `8f90a2110e81` |
| 30 | avm-res-network-bastionhost | azurerm | 497,770 | 743,252 | v0.9.0 `7c7d294caf81` |
| 31 | avm-res-sql-server | azurerm | 492,441 | 621,999 | v0.2.1 `dd3461fc43de` |
| 32 | avm-res-network-azurefirewall | azurerm | 450,037 | 703,693 | v0.5.0 `e88c8db23982` |
| 33 | avm-res-web-serverfarm | azurerm | 433,905 | 594,099 | v2.0.8 `077bbb36ea58` |
| 34 | aks (archived) | azurerm | 406,315 | 1,399,384 | 11.7.0 `58ffc7c71a36` |
| 35 | avm-ptn-alz | azurerm | 400,560 | 639,791 | v0.22.0 `e2a318c3eba9` |
| 36 | avm-res-documentdb-databaseaccount | azurerm | 396,414 | 534,300 | v0.12.0 `9939de3a2e36` |
| 37 | avm-res-network-dnsresolver | azurerm | 393,028 | 645,221 | v0.8.0 `73b1df385505` |
| 38 | avm-res-cache-redis | azurerm | 390,989 | 493,207 | v0.5.0 `7469021fb795` |
| 39 | regions (archived) | azurerm | 364,289 | 823,168 | |
| 40 | avm-res-app-managedenvironment | azurerm | 350,236 | 411,158 | v0.6.0 `c6709095a923` |
| 41 | avm-res-network-applicationgateway | azurerm | 347,827 | 475,384 | v0.6.0 `f5961205a904` |
| 42 | avm-ptn-network-private-link-private-dns-zones | azurerm | 338,739 | 549,979 | v0.23.2 `4d2214f16280` |
| 43 | vnet (archived) | azurerm | 319,356 | 3,424,330 | 5.0.1 `27359ed29033` |
| 44 | avm-res-network-ddosprotectionplan | azurerm | 288,387 | 465,403 | v0.3.0 `2d455cb9c6c6` |
| 45 | avm-ptn-alz-management | azurerm | 281,649 | 471,782 | v0.10.0 `3026684f8aa4` |

The full commit SHAs, by tag:

- avm-res-network-virtualnetwork `874b2d1ce38cd59ca0759d416cb3e174c2543ffb`
- avm-res-network-networksecuritygroup `c5283612e428c44229a54d1278f184d5203e322b`
- avm-res-storage-storageaccount `226f9bbefcc9299ad46f6263fc9005edb39a38e5`
- avm-res-keyvault-vault `7c53adbc7f4f716fa00b21af90e1a120db5e19ef`
- avm-res-compute-virtualmachine `a6e951bdebcf50656a1fa29881fcc5a4c87e7a77`
- avm-res-resources-resourcegroup `4c7e926d9aa11000d7c31a6b4c26100371b2ac62`
- avm-res-managedidentity-userassignedidentity `7a0c461789f0177a0b666378924cd5d33196ef8a`
- avm-res-operationalinsights-workspace `b4ffa3ff87ac09ff6de3b7014c44b4d213aa302b`
- avm-res-network-routetable `7482f30b5f92ef88d5abfeb62a4296aa4a474342`
- avm-res-network-natgateway `597df2389d997c93da6a559f64fe7096ef30e24e`
- avm-res-network-privatednszone `97ed94c12535fac61c3bad293754ba408b8a8d56`
- avm-res-network-publicipaddress `2790d091b373fc2fd9e13aed3165c8d0813a87e4`
- avm-res-network-loadbalancer `e83d34778efeb54a1779b968106067cc4b2bad63`
- avm-res-containerregistry-registry `7f2dc78bb5dbfc6e05809963410be844006f9490`
- avm-res-network-firewallpolicy `8580240f33fee12f92ef4834a9574ab0481686c5`
- avm-res-containerservice-managedcluster `1925e0490783695919ab21e4c73ebf1f53d95e2d`
- avm-res-dbforpostgresql-flexibleserver `70d6e9c947f8b2c24b706bb3484228d53cf7858a`
- avm-res-cognitiveservices-account `02ac1c992bbadd4286d36171cfd43792a513c375`
- avm-ptn-alz-sub-vending `28577b03cf4ad2cd5faa2e9ee7991f07c7c2dab0`
- avm-res-insights-component `8c75ae7771d672228595c19cefa6c216a8955d49`
- avm-res-app-containerapp `ae03166abab035743ead9550bd32818bf75efdd9`
- avm-res-web-site `56c704e9f44002a46a71226d3c19f3915e1865c0`
- avm-res-network-privateendpoint `84e427dd16ca927f449b7659d8888f3685f38a7d`
- avm-res-authorization-roleassignment `8f90a2110e81def1c63f8f81f44e60554793e50e`
- avm-res-network-bastionhost `7c7d294caf81377671b99687aa75726e1072002e`
- avm-res-sql-server `dd3461fc43de092133eea999eb21efba31983079`
- avm-res-network-azurefirewall `e88c8db23982193eb3511c0d69fea71d0dcfbb2c`
- avm-res-web-serverfarm `077bbb36ea58ae8e2ead058848c551db0c664544`
- avm-ptn-alz `e2a318c3eba91967c4ce3cd2738b2b2569db994e`
- avm-res-documentdb-databaseaccount `9939de3a2e36161242f5140bcf0cd28e23a3e1f0`
- avm-res-network-dnsresolver `73b1df385505485dee12fc3901756d4994fe9cc8`
- avm-res-cache-redis `7469021fb795f8ee3dce2ed2dba2f41b91c4785c`
- avm-res-app-managedenvironment `c6709095a923c7c3d1fb54da0d43cb56d95b731e`
- avm-res-network-applicationgateway `f5961205a9046adc86ea1c85cc490c19e462ecbd`
- avm-ptn-network-private-link-private-dns-zones `4d2214f162806d48ea9a157de4b904f879fc61d4`
- avm-res-network-ddosprotectionplan `2d455cb9c6c61e9061730ba8373b103ae6886cbb`
- avm-ptn-alz-management `3026684f8aa489dd9f88f637afdf859cb1bcee27`
- lz-vending `ddc6b5989a01e658250b998285c8dccb7b3afa30`
- aks `58ffc7c71a36871dc955ded13816fd29ac798791`
- vnet `27359ed290331d84d850e7ee6c6c88f3adb0377e`

**Scale.** AWS's top module, iam, has 119.6 million downloads a year. Azure's
top resource module, the virtual network, has 7.1 million. Azure's Terraform
usage in this registry is about a fifteenth of AWS's at the top.

## 3. ASO maturity

ASO v2 is GA as a project; v2.22.0 (2026-10-30) is its latest release. It
has no per-controller maturity. Each kind is generated per ARM API version
(CRD version `v1api<date>`). "GA" below means ASO has released the kind on a
GA ARM API version. "Preview" means ASO offers only a preview ARM version.
"Next" means the kind is merged to ASO's main branch but not yet in a
release.

At v2.22.0 the reference lists 304 kinds across 47 groups. Every kind this
inventory relies on is on a GA ARM version, except `Insights/DiagnosticSetting`
(`2021-05-01-preview`, Azure's only version) and `KeyVault/VaultKey`
(next).

**Installation.** ASO installs only the CRDs that match its `crdPattern`
setting, such as `network.azure.com/*`. A Bundt provider for ASO has to name
the groups its Packages use.

**API versions trail AVM.** These are places where AVM pins a newer ARM
version than ASO has released:

| Kind | ASO released | AVM uses |
| --- | --- | --- |
| VirtualMachine | 2022-03-01 | azurerm's current resource |
| ApplicationGateway | 2022-07-01 | 2025-03-01 |
| KeyVault Vault | 2023-07-01 | 2026-02-01 |
| ContainerRegistry Registry | 2023-07-01 (2025-11-01 next) | 2025-11-01 |
| ManagedCluster | 2025-08-01 (2026-05-01 next) | 2026-03-01 and 2026-03-02-preview |
| ContainerApp | 2025-01-01 | 2025-07-01 and 2025-02-02-preview |
| ResourceGroup | 2020-06-01 | 2025-04-01 |
| DNS zones | 2018-05-01 | |

Older versions usually work, but newer properties a module exposes may not
exist in ASO's schema.

## 4. The top 25, module by module

"AVM ARM types" are the `Microsoft.*@version` strings found in the module
source, or the `azurerm_*` resources where the module still uses azurerm.
"ASO" is the kind in group `<service>.azure.com`, with its released ARM
version. **GAP** means no ASO kind at v2.22.0. `aso-ext` means
aso-extensions has built it.

**Common to nearly every module, and not repeated per module** (the AVM
interfaces):

| Interface | ASO kind |
| --- | --- |
| role assignments | `authorization/RoleAssignment` (2022-04-01, GA) |
| diagnostic settings | `insights/DiagnosticSetting` (2021-05-01-preview) |
| private endpoints | `network/PrivateEndpoint` and `PrivateEndpointsPrivateDnsZoneGroup` (2025-03-01) |
| locks | **GAP** (`Microsoft.Authorization/locks`; issue #3756 open, #4629 closed) |

### 1. avm-res-network-virtualnetwork (v0.23.0; azapi)

| Submodule | ARM types | ASO |
| --- | --- | --- |
| root | `Microsoft.Network/virtualNetworks@2024-07-01` | `network/VirtualNetwork` (2025-03-01) |
| `subnet` | `.../subnets@2024-07-01` | `network/VirtualNetworksSubnet`. NSG, route table and NAT gateway associations are subnet properties |
| `peering` | `.../virtualNetworkPeerings@2024-07-01` | `network/VirtualNetworksVirtualNetworkPeering` |

Fully covered, apart from the lock.

### 2. avm-res-network-networksecuritygroup (v0.6.0; azapi)

| ARM types | ASO |
| --- | --- |
| `networkSecurityGroups@2024-10-01`, `.../securityRules@2024-10-01` | `network/NetworkSecurityGroup`, `network/NetworkSecurityGroupsSecurityRule` (2025-03-01). Fully covered. Unlike ACK, ASO has standalone rules |

### 3. avm-res-storage-storageaccount (v0.11.0; azapi)

| Submodule | ARM types | ASO (2025-06-01) |
| --- | --- | --- |
| root | `storageAccounts@2025-08-01`, `managementPolicies` | `storage/StorageAccount`, `StorageAccountsManagementPolicy` |
| `blob_service`, `container`, `data_lake_filesystem` | `blobServices`, `blobServices/containers` | `StorageAccountsBlobService`, `StorageAccountsBlobServicesContainer` (a Data Lake filesystem is a container) |
| `file_service`, `share` | `fileServices`, `fileServices/shares` | `StorageAccountsFileService`, `StorageAccountsFileServicesShare` |
| `queue` | `queueServices`, `queueServices/queues` | `StorageAccountsQueueService`, `StorageAccountsQueueServicesQueue` |
| `table_service`, `table` | `tableServices`, `tableServices/tables` | `StorageAccountsTableService`, `StorageAccountsTableServicesTable` |
| `local_user` | `storageAccounts/localUsers` (SFTP) | **GAP** |
| `private_endpoint`, `role_assignments`, `diagnostic_setting` | interfaces | as above |

The module can also write account keys to a Key Vault as secrets:
`aso-ext` `VaultSecret`.

### 4. avm-res-keyvault-vault (v0.13.0; azapi with azurerm for the data plane)

| Submodule | Creates | ASO |
| --- | --- | --- |
| root | `KeyVault/vaults@2026-02-01`, certificate contacts, private endpoints | `keyvault/Vault` (2023-07-01). **GAP**: certificate contacts (a data-plane API) |
| `secret` | `azurerm_key_vault_secret`, role assignments | `aso-ext` `keyvault.azure.hfl.dev/VaultSecret`. ASO declined secrets (#1894) |
| `key` | `azurerm_key_vault_key`, role assignments | `keyvault/VaultKey`: **next**, merged in ASO but not in v2.22.0 |

### 5. avm-res-compute-virtualmachine (v0.21.0; mostly azurerm)

| Submodule | Creates | ASO |
| --- | --- | --- |
| root | Linux or Windows VM, managed disks and attachments, NICs and their associations (LB, App Gateway, ASG, NSG, NAT rule), public IP, admin password in Key Vault, maintenance configuration assignment, backup protected item, auto-shutdown schedule | `compute/VirtualMachine` (2022-03-01; data disks inline), `compute/Disk`, `network/NetworkInterface` (associations inline), `network/PublicIPAddress`, `aso-ext` `VaultSecret`. **GAP**: `Microsoft.Maintenance/configurationAssignments`, Recovery Services (the whole `RecoveryServices` group is absent from ASO), `Microsoft.DevTestLab/schedules` |
| `extension` | VM extension | `compute/VirtualMachinesExtension` |
| `run-command` | VM run command | **GAP** |

The core works. The VM's ARM version is old.

### 6. avm-res-resources-resourcegroup (v0.5.0; azapi)

| ARM types | ASO |
| --- | --- |
| `resourceGroups@2025-04-01` | `resources/ResourceGroup` (2020-06-01). Covered |

### 7. avm-res-managedidentity-userassignedidentity (v0.6.0)

| Creates | ASO |
| --- | --- |
| identity, federated identity credentials | `managedidentity/UserAssignedIdentity`, `FederatedIdentityCredential` (2023-01-31). Covered |

### 8. avm-res-operationalinsights-workspace (v0.5.1)

| Submodule | Creates | ASO |
| --- | --- | --- |
| root | workspace, tables, data exports, linked service, linked storage account, private endpoint, AMPLS scoped resource, network security perimeter association | `operationalinsights/Workspace` (2025-07-01). **GAP**: `workspaces/tables`, `dataExports`, `linkedServices`, `linkedStorageAccounts`, `Insights/privateLinkScopes/scopedResources`, `networkSecurityPerimeters/resourceAssociations` |
| `query_packs` | query packs and queries | **GAP** |
| `log_analytics_solution` | `OperationsManagement/solutions` | **GAP** |

### 9. avm-res-network-routetable (v0.6.0)

| Creates | ASO |
| --- | --- |
| route table, routes, subnet associations | `network/RouteTable`, `RouteTablesRoute` (2025-03-01). The association is `VirtualNetworksSubnet.routeTable`. Covered |

### 10. avm-res-network-natgateway (v0.3.2; azapi)

| Creates | ASO |
| --- | --- |
| NAT gateway, public IPs | `network/NatGateway`, `PublicIPAddress` (2025-03-01). Covered |

### 11. avm-res-network-privatednszone (v0.6.0; azapi)

| Submodule | ASO (2024-06-01) |
| --- | --- |
| root | `network/PrivateDnsZone` |
| A, AAAA, CNAME, MX, PTR, SRV, TXT records | `PrivateDnsZones{A,AAAA,CNAME,MX,PTR,SRV,TXT}Record` |
| `private_dns_soa_record` | **GAP** (a minor one: the SOA record always exists and is only updated) |
| `private_dns_virtual_network_link` | `PrivateDnsZonesVirtualNetworkLink` |

### 12. avm-res-network-publicipaddress (v0.2.1; azurerm)

| Creates | ASO |
| --- | --- |
| public IP | `network/PublicIPAddress` (2025-03-01). Covered |

### 13. avm-res-network-loadbalancer (v0.5.0; azurerm)

| Creates | ASO |
| --- | --- |
| LB, backend pools and addresses, probes, rules, NAT rules and pools, outbound rules, public IPs, NIC associations | `network/LoadBalancer` (pools, probes, rules and outbound rules are inline ARM properties), `LoadBalancersInboundNatRule`, `PublicIPAddress`. NIC association is a `NetworkInterface` property. Covered |

### 14. avm-res-containerregistry-registry (v0.9.0)

| Submodule | Creates | ASO |
| --- | --- | --- |
| root | registry, replications, private endpoint | `containerregistry/Registry` (2023-07-01; 2025-11-01 next), `RegistryReplication` |
| `cache-rule` | `registries/cacheRules@2025-11-01` | `RegistryCacheRule` (2025-11-01) |
| `credential-set` | `registries/credentialSets@2025-11-01` | **GAP** |
| `scope-map` | scope map, token, token password | **GAP** |

### 15. avm-res-network-firewallpolicy (v0.3.4; azurerm)

| Submodule | ASO (2025-03-01) |
| --- | --- |
| root | `network/FirewallPolicy` |
| `rule_collection_groups` | `FirewallPoliciesRuleCollectionGroup` |

Covered.

### 16. avm-res-containerservice-managedcluster (v0.9.0; azapi)

| Submodule | ARM types | ASO |
| --- | --- | --- |
| root | `managedClusters@2026-03-01` (and `2026-03-02-preview`), credential actions | `containerservice/ManagedCluster` (2025-08-01). The kubeconfig is exported to a Secret through `operatorSpec.secrets` |
| `agentpool` | `managedClusters/agentPools@2026-01-02-preview` | `ManagedClustersAgentPool` (2025-08-01) |
| `maintenanceconfiguration` | `maintenanceConfigurations@2026-03-01` | `MaintenanceConfiguration` |
| `namespace` | `managedNamespaces@2026-03-01` | **GAP** |
| `monitoring` | data collection rules, endpoints and associations | `insights/DataCollectionRule`, `DataCollectionEndpoint`, `DataCollectionRuleAssociation` (2024-03-11) |
| `alerting` | Prometheus rule groups, action groups, metric alerts | `alertsmanagement/PrometheusRuleGroup`, `insights/ActionGroup`, `insights/MetricAlert` |

Covered, except managed namespaces and preview-only properties.

### 17. avm-res-dbforpostgresql-flexibleserver (v0.2.3; azurerm)

| Submodule | Creates | ASO (2025-08-01) |
| --- | --- | --- |
| root | server, Entra administrator, configurations, firewall rules, virtual endpoint, private endpoint | `dbforpostgresql/FlexibleServer`, `FlexibleServersAdministrator`, `FlexibleServersConfiguration`, `FlexibleServersFirewallRule`, `FlexibleServersVirtualEndpoint` |
| `database` | database | `FlexibleServersDatabase` |

The ARM side is covered. Database users are the data plane: `aso-ext`
`dbforpostgresql.azure.hfl.dev/User` (Entra principals, privileges, schema
and default privileges, ownership).

### 18. avm-res-cognitiveservices-account (v0.11.1)

| Submodule | ARM types | ASO (2025-06-01) |
| --- | --- | --- |
| root | `CognitiveServices/accounts@2025-06-01`, customer-managed key | `cognitiveservices/Account` (the key is inline) |
| `deployment` | `accounts/deployments` | `cognitiveservices/Deployment` |
| `rai_policy` | `accounts/raiPolicies@2024-10-01` | **GAP** |

### 19. avm-ptn-alz-sub-vending (v0.3.4; azapi; a pattern)

| Submodule | ARM types | ASO |
| --- | --- | --- |
| `subscription` | `Subscription/aliases`, `Management/managementGroups/subscriptions`, `Resources/subscriptions`, `Resources/tags` | `subscription/Alias`. **GAP**: management group placement, subscription tags |
| `resource-group`, `user-assigned-managed-identity`, `virtual-network`, `network-security-group`, `route-table`, `role-assignment` | as named | covered (see above) |
| `budget` | `Consumption/budgets` | **GAP** |
| `resource-provider` | provider registration (an action) | **GAP**: an action, not a resource |
| (virtual WAN) | `virtualHubs/hubVirtualNetworkConnections` | **GAP** (no vWAN kinds) |

This is a platform landing-zone pattern, run with tenant-level rights, not an
application stack. It is low priority for a team catalog.

### 20. avm-res-insights-component (v0.5.0; azapi)

| ARM types | ASO |
| --- | --- |
| `Insights/components@2020-02-02`, `privateLinkScopes/scopedResources` | `insights/Component` (2020-02-02). **GAP**: AMPLS scoped resource |

### 21. avm-res-app-containerapp (v0.9.0; azapi)

| ARM types | ASO (2025-01-01) |
| --- | --- |
| `App/containerApps@2025-07-01` (and a preview), `containerApps/authConfigs@2025-01-01` | `app/ContainerApp`, `app/AuthConfig`. Covered, on an older API |

### 22. avm-res-web-site (v0.24.1; azapi)

| Submodule | ARM types | ASO |
| --- | --- | --- |
| root | `Web/sites@2025-03-01` | `web/Site` (2025-05-01). App settings and connection strings can go inline in `siteConfig` |
| `slot` | `sites/slots` | **GAP** |
| `hostname_binding` | `sites/hostNameBindings` | **GAP** |
| `certificate` | `Web/certificates` | **GAP** |
| `config_*` (appsettings, connectionstrings, authsettings, authsettingsV2, logs, backup, metadata) | `sites/config` | **GAP** as separate objects; partly inline |
| `publishing_credential_policy` | `sites/basicPublishingCredentialsPolicies` | **GAP** |

Custom domains and deployment slots are core to App Service, so this is a
real gap.

### 23. avm-res-network-privateendpoint (v0.3.1; azapi)

| ARM types | ASO (2025-03-01) |
| --- | --- |
| `privateEndpoints@2025-07-01`, `privateDnsZoneGroups` | `network/PrivateEndpoint`, `PrivateEndpointsPrivateDnsZoneGroup`. Covered |

### 24. avm-res-authorization-roleassignment (v0.3.1; azurerm and azuread)

| Creates | ASO |
| --- | --- |
| Azure RBAC role assignments | `authorization/RoleAssignment`, `RoleDefinition` (2022-04-01) |
| Entra directory role and directory role assignment | **GAP** (ASO's Entra group has `Application` and `SecurityGroup`; `ServicePrincipal` is next) |

### 25. avm-res-network-bastionhost (v0.9.0)

| Creates | ASO |
| --- | --- |
| Bastion host | `network/BastionHost` (2025-03-01). Covered |

### Just below the top 25

| Module | ASO coverage |
| --- | --- |
| avm-res-sql-server (31) | server, databases, elastic pools and firewall rules: `sql/Server`, `ServersDatabase`, `ServersElasticPool`, `ServersFirewallRule` and 20 more `sql/*` kinds. The admin password goes to Key Vault (`aso-ext` `VaultSecret`). Entra database users: aso-extensions candidate a1, PR #5104 |
| avm-res-network-azurefirewall (32) | `network/AzureFirewall`. Covered |
| avm-res-web-serverfarm (33) | `web/ServerFarm`. Covered |
| avm-ptn-alz (35) | management groups, policy definitions, policy set definitions and policy assignments are all **GAP** (no `Microsoft.Management` or `Microsoft.Authorization/policy*` kinds; management groups are issue #2249, open). Role definitions and assignments, and identities, are covered |
| avm-res-documentdb-databaseaccount (36) | `documentdb/DatabaseAccount` and its SQL and Mongo children. **GAP**: Gremlin databases and graphs, SQL dedicated gateway |
| avm-res-network-dnsresolver (37) | `network/DnsResolver`, its inbound and outbound endpoints, forwarding rulesets, rules and VNet links. Covered |
| avm-res-cache-redis (38) | `cache/Redis`, access policies, assignments, firewall rules, linked servers (2024-11-01). Covered |
| avm-res-app-managedenvironment (40) | `app/ManagedEnvironment`. **GAP**: all nine child types (Dapr components and subscriptions, storages, certificates, managed certificates, Java and .NET components, HTTP route configs, maintenance configurations) |
| avm-res-network-applicationgateway (41) | `network/ApplicationGateway` (2022-07-01, old) |

## 5. Gaps ranked for aso-extensions

aso-extensions has a rule (plan.md section 1, open question 6, recommended):

- **Gaps in ARM go upstream to ASO as configuration**: an `$exportAs` entry,
  a sample and a recorded test.
- **Data-plane gaps, and gaps ASO declined, are built in aso-extensions.**

So each gap below says where it belongs. Ranked by how many of the 33 modules
in section 4 need it, then by downloads.

| # | Gap | Modules needing it | Kind of gap | Upstream | Belongs |
| --- | --- | --- | --- | --- | --- |
| 1 | Management locks (`Microsoft.Authorization/locks`) | 31 of 33 (optional `lock` input everywhere) | ARM | issue #3756 open; #4629 closed | upstream. Also see the question below |
| 2 | Key Vault secrets written by a module | 4 (keyvault, virtual machine, storage account, sql-server) | data plane, declined by ASO (#1894) | n/a | **built**: `VaultSecret` |
| 3 | Container Apps environment children (Dapr components, storages, certificates, managed certificates, ...) | 1 (managedenvironment, 40), but every container app that uses Dapr or Azure Files needs them | ARM | no issue found | upstream |
| 4 | App Service site children (slots, hostname bindings, certificates, config sections, publishing policies) | 1 (web-site, 22); core to App Service | ARM | no issue found | upstream |
| 5 | Log Analytics children (tables, data exports, linked services, linked storage, query packs, solutions) | 2 (workspace, alz-management); also the archived aks | ARM | none found | upstream |
| 6 | Azure Monitor private link scope and scoped resources; network security perimeter associations | 2 (insights-component, workspace) | ARM | none found | upstream |
| 7 | Key Vault keys | 1 (keyvault); 5 modules take a `customer_managed_key` that needs one | ARM and data plane | `VaultKey` merged in ASO, next release | **wait** for ASO's release |
| 8 | Management groups, Azure Policy (definitions, sets, assignments), budgets, vWAN hub connections, subscription tags | 2 (avm-ptn-alz, alz-sub-vending), plus lz-vending (archived) | ARM, tenant-scope | management groups #2249 open | upstream; low priority (platform, not app) |
| 9 | ACR tokens, scope maps, credential sets | 1 (registry) | ARM; a token password is a secret returned once | none found | upstream; the password needs ASO's `operatorSpec.secrets` |
| 10 | VM extras: run command, auto-shutdown schedule, maintenance assignment, Recovery Services backup | 1 (virtual machine); also avm-res-recoveryservices-vault (rank 56, 163,024 a year) | ARM | issue #4455 (a Recovery Services vault for storage), open | upstream |
| 11 | Storage local users (SFTP) | 1 (storage account) | ARM | none found | upstream |
| 12 | Cognitive Services RAI policies | 1 (cognitive account) | ARM | none found | upstream |
| 13 | Cosmos DB Gremlin, SQL dedicated gateway | 1 (documentdb) | ARM | none found | upstream |
| 14 | AKS managed namespaces | 1 (managedcluster) | ARM | none found | upstream |
| 15 | Entra directory roles and their assignments | 1 (roleassignment) | Microsoft Graph, not ARM | n/a | aso-extensions candidate, if wanted: ASO's Entra reconcilers are hand-written, like aso-extensions' kinds |
| 16 | Azure SQL Entra users | 1 (sql-server) | data plane | PR #5104 open | aso-extensions candidate a1 (open question 5) |
| 17 | Key Vault certificate import and certificate contacts | 1 (keyvault); App Service certificates from Key Vault | data plane | n/a | aso-extensions b6, after `VaultSecret`'s shape |
| 18 | Stale ARM versions (VirtualMachine 2022-03-01, ApplicationGateway 2022-07-01, DNS zones 2018-05-01) | 3 (virtual machine, application gateway, dnszone) | ARM version | n/a | upstream (a new `$supportedFrom` version) |

Already built in aso-extensions and needed by the top modules:

- `VaultSecret` for keyvault, virtual machine, storage account and
  sql-server;
- the PostgreSQL `User` for the flexible server's database users.

**A question for the builder, not decided here.** Locks are the single
biggest gap by count, and each is a small extension resource. Under
aso-extensions' open question 6, the recommendation is never to build an ARM
kind in aso-extensions. Locks may be the case that tests that rule. They are
optional in AVM (default off), so a first catalog can also ship without
them.

## 6. kro verdict for Azure

**Not worth it. Helm, or `manifests`, for every Package in the top 25.**

kro's value is wiring live status into another resource's spec, collections
over status, and aggregated status. On Azure each of these already has a
home:

- **Ordering and parent IDs come from ASO's `owner`.** A child names its
  parent, and ASO waits for the parent and computes the ARM ID: subnets
  under a VNet, a database under a server, records under a zone, agent
  pools under a cluster. Most AVM submodules are exactly such children.
- **References between siblings are `*Reference` fields.** They take an ARM
  ID or a Kubernetes group, kind and name. Examples are a private endpoint's
  subnet, a NIC's subnet and a role assignment's scope.
- **Status into spec is built into ASO.**
  - A resource exports values from its status to a ConfigMap or Secret with
    `operatorSpec.configMaps`/`secrets`, or with CEL through
    `operatorSpec.configMapExpressions`/`secretExpressions`.
  - Another resource reads them with `*FromConfig` fields. Read at v2.22.0:
    `FederatedIdentityCredential` has `issuerFromConfig` and
    `subjectFromConfig`, and `RoleAssignment` has `principalIdFromConfig`.
  - So the two classic cases are handled in ASO without kro:
    - AKS's OIDC issuer into a workload identity's federated credential;
    - a managed identity's principal ID into a role assignment.
- **Aggregated readiness and outputs are Bundt's.** Bundt reads `Ready` (ASO
  sets it) and computes CEL outputs over live status.
- **Fan-out is from inputs.** Subnets, records, rules and role assignments
  are known when the plan renders, so Helm `range` covers them.

The only place kro would add something is a collection over a list that
exists only in live status. None of the top 25 has one.

Where a `*FromConfig` field is missing for some pair, split the module into
two Packages joined by the Template's `valueFrom` before reaching for kro.

## 7. Porting notes

- **Transcribe, do not translate.** For the many `azapi` AVM modules, each
  `azapi_resource` body is the ARM resource body. An ASO spec is the same
  body with `owner` (or a `*Reference`) in place of `parent_id`, in
  camelCase, with secrets as `SecretReference`s. A mechanical converter is
  realistic, at the ARM version ASO has.
- **The AVM interfaces become one Helm library chart**:
  - `roleAssignments` → `RoleAssignment`;
  - `diagnosticSettings` → `DiagnosticSetting`;
  - `privateEndpoints` → `PrivateEndpoint` plus a DNS zone group;
  - `managedIdentities` → the parent's `identity`;
  - `customerManagedKey` → the parent's encryption properties;
  - `lock` → nothing yet (gap 1).
- **Values keep AVM's variable names** in camelCase
  (`private_endpoints` becomes `privateEndpoints`), so a team's `tfvars`
  moves over mechanically. Outputs keep AVM's output names (`resource_id`
  becomes `resourceId`, and so on).
- **Drop:**
  - `modtm_telemetry`;
  - the telemetry `Microsoft.Resources/deployments`;
  - `random_*` passwords: use a Secret the team provides, or an Entra-only
    login;
  - `time_sleep`: ASO waits on its own.
- **Licence and attribution.** AVM is MIT, "Copyright (c) Microsoft
  Corporation." MIT needs the copyright and permission notice kept "in all
  copies or substantial portions." A chart derived from an AVM module
  should:
  - carry the MIT notice, in the chart directory or a third-party notices
    file;
  - name the module, tag and commit it came from;
  - keep the catalog repository's own licence for the rest.

  ASO is MIT too, and aso-extensions' own licence is still an open question
  (plan.md, question 1).
- **Pattern modules** (`avm-ptn-*`) map onto Bundt Templates, not Packages:
  several resource Packages wired by `valueFrom`. The ALZ patterns need
  management group and policy kinds that ASO lacks (gap 8). The
  `avm-ptn-aiml-*`, `app-service-landing-zone` and
  `private-link-private-dns-zones` patterns are the likelier first
  Templates.
- **Not seeds.** These create no Azure resources; their logic becomes CEL
  in Bundt's expressions or a values helper:
  - `naming` (archived, still #1 by downloads);
  - `avm-utl-naming`;
  - `avm-utl-regions`;
  - `avm-utl-interfaces`;
  - `avm-utl-roledefinitions`.
