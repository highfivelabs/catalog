# Azure seed catalog: Azure Verified Modules mapped to ASO v2

The question: for Azure, what the Terraform registry says about usage, and
where the canonical modules are stored.

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
  inventory accept a `lock`, and ASO has none (issue #3756, open). They
  are out of the first catalog (2026-11-10). After that
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
| 1 | [naming](https://registry.terraform.io/modules/Azure/naming/azurerm) (archived; no resources) | azurerm | 8,336,284 | 22,898,636 | |
| 2 | [avm-res-network-virtualnetwork](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm) | azurerm | 7,131,017 | 8,259,157 | v0.23.0 `874b2d1ce38c` |
| 3 | [avm-utl-interfaces](https://registry.terraform.io/modules/Azure/avm-utl-interfaces/azure) (no resources) | azure | 6,597,108 | 6,936,367 | |
| 4 | [avm-res-network-networksecuritygroup](https://registry.terraform.io/modules/Azure/avm-res-network-networksecuritygroup/azurerm) | azurerm | 4,108,779 | 4,856,855 | v0.6.0 `c5283612e428` |
| 5 | [avm-res-storage-storageaccount](https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm) | azurerm | 3,964,392 | 5,401,219 | v0.11.0 `226f9bbefcc9` |
| 6 | [avm-res-keyvault-vault](https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm) | azurerm | 3,794,829 | 5,229,598 | v0.13.0 `7c53adbc7f4f` |
| 7 | [avm-res-compute-virtualmachine](https://registry.terraform.io/modules/Azure/avm-res-compute-virtualmachine/azurerm) | azurerm | 3,681,412 | 4,168,285 | v0.21.0 `a6e951bdebcf` |
| 8 | [avm-utl-regions](https://registry.terraform.io/modules/Azure/avm-utl-regions/azurerm) (no resources) | azurerm | 3,314,606 | 4,464,361 | |
| 9 | [avm-res-resources-resourcegroup](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm) | azurerm | 2,753,674 | 3,728,662 | v0.5.0 `4c7e926d9aa1` |
| 10 | [avm-res-managedidentity-userassignedidentity](https://registry.terraform.io/modules/Azure/avm-res-managedidentity-userassignedidentity/azurerm) | azurerm | 2,520,215 | 3,565,638 | v0.6.0 `7a0c461789f0` |
| 11 | [avm-res-operationalinsights-workspace](https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm) | azurerm | 1,129,542 | 1,583,538 | v0.5.1 `b4ffa3ff87ac` |
| 12 | [avm-res-network-routetable](https://registry.terraform.io/modules/Azure/avm-res-network-routetable/azurerm) | azurerm | 1,087,375 | 1,566,240 | v0.6.0 `7482f30b5f92` |
| 13 | [avm-res-network-natgateway](https://registry.terraform.io/modules/Azure/avm-res-network-natgateway/azurerm) | azurerm | 1,057,695 | 1,178,796 | v0.3.2 `597df2389d99` |
| 14 | [avm-res-network-privatednszone](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm) | azurerm | 1,032,578 | 1,623,379 | v0.6.0 `97ed94c12535` |
| 15 | [avm-utl-roledefinitions](https://registry.terraform.io/modules/Azure/avm-utl-roledefinitions/azure) (no resources) | azure | 783,679 | 806,072 | |
| 16 | [avm-res-network-publicipaddress](https://registry.terraform.io/modules/Azure/avm-res-network-publicipaddress/azurerm) | azurerm | 767,152 | 1,148,881 | v0.2.1 `2790d091b373` |
| 17 | [avm-res-network-loadbalancer](https://registry.terraform.io/modules/Azure/avm-res-network-loadbalancer/azurerm) | azurerm | 716,805 | 803,838 | v0.5.0 `e83d34778efe` |
| 18 | [avm-res-containerregistry-registry](https://registry.terraform.io/modules/Azure/avm-res-containerregistry-registry/azurerm) | azurerm | 691,266 | 974,026 | v0.9.0 `7f2dc78bb5db` |
| 19 | [avm-res-network-firewallpolicy](https://registry.terraform.io/modules/Azure/avm-res-network-firewallpolicy/azurerm) | azurerm | 660,760 | 1,017,127 | v0.3.4 `8580240f33fe` |
| 20 | [avm-res-containerservice-managedcluster](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm) | azurerm | 653,189 | 828,090 | v0.9.0 `1925e0490783` |
| 21 | [lz-vending](https://registry.terraform.io/modules/Azure/lz-vending/azurerm) (archived) | azurerm | 645,346 | 1,512,101 | v7.0.3 `ddc6b5989a01` |
| 22 | [avm-res-dbforpostgresql-flexibleserver](https://registry.terraform.io/modules/Azure/avm-res-dbforpostgresql-flexibleserver/azurerm) | azurerm | 627,646 | 749,702 | v0.2.3 `70d6e9c947f8` |
| 23 | [avm-res-cognitiveservices-account](https://registry.terraform.io/modules/Azure/avm-res-cognitiveservices-account/azurerm) | azurerm | 607,551 | 1,148,932 | v0.11.1 `02ac1c992bba` |
| 24 | [avm-ptn-alz-sub-vending](https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure) | azure | 570,438 | 574,735 | v0.3.4 `28577b03cf4a` |
| 25 | [avm-res-insights-component](https://registry.terraform.io/modules/Azure/avm-res-insights-component/azurerm) | azurerm | 564,949 | 730,504 | v0.5.0 `8c75ae7771d6` |
| 26 | [avm-res-app-containerapp](https://registry.terraform.io/modules/Azure/avm-res-app-containerapp/azurerm) | azurerm | 564,500 | 661,369 | v0.9.0 `ae03166abab0` |
| 27 | [avm-res-web-site](https://registry.terraform.io/modules/Azure/avm-res-web-site/azurerm) | azurerm | 562,169 | 819,963 | v0.24.1 `56c704e9f440` |
| 28 | [avm-res-network-privateendpoint](https://registry.terraform.io/modules/Azure/avm-res-network-privateendpoint/azurerm) | azurerm | 531,573 | 838,784 | v0.3.1 `84e427dd16ca` |
| 29 | [avm-res-authorization-roleassignment](https://registry.terraform.io/modules/Azure/avm-res-authorization-roleassignment/azurerm) | azurerm | 497,839 | 672,657 | v0.3.1 `8f90a2110e81` |
| 30 | [avm-res-network-bastionhost](https://registry.terraform.io/modules/Azure/avm-res-network-bastionhost/azurerm) | azurerm | 497,770 | 743,252 | v0.9.0 `7c7d294caf81` |
| 31 | [avm-res-sql-server](https://registry.terraform.io/modules/Azure/avm-res-sql-server/azurerm) | azurerm | 492,441 | 621,999 | v0.2.1 `dd3461fc43de` |
| 32 | [avm-res-network-azurefirewall](https://registry.terraform.io/modules/Azure/avm-res-network-azurefirewall/azurerm) | azurerm | 450,037 | 703,693 | v0.5.0 `e88c8db23982` |
| 33 | [avm-res-web-serverfarm](https://registry.terraform.io/modules/Azure/avm-res-web-serverfarm/azurerm) | azurerm | 433,905 | 594,099 | v2.0.8 `077bbb36ea58` |
| 34 | [aks](https://registry.terraform.io/modules/Azure/aks/azurerm) (archived) | azurerm | 406,315 | 1,399,384 | 11.7.0 `58ffc7c71a36` |
| 35 | [avm-ptn-alz](https://registry.terraform.io/modules/Azure/avm-ptn-alz/azurerm) | azurerm | 400,560 | 639,791 | v0.22.0 `e2a318c3eba9` |
| 36 | [avm-res-documentdb-databaseaccount](https://registry.terraform.io/modules/Azure/avm-res-documentdb-databaseaccount/azurerm) | azurerm | 396,414 | 534,300 | v0.12.0 `9939de3a2e36` |
| 37 | [avm-res-network-dnsresolver](https://registry.terraform.io/modules/Azure/avm-res-network-dnsresolver/azurerm) | azurerm | 393,028 | 645,221 | v0.8.0 `73b1df385505` |
| 38 | [avm-res-cache-redis](https://registry.terraform.io/modules/Azure/avm-res-cache-redis/azurerm) | azurerm | 390,989 | 493,207 | v0.5.0 `7469021fb795` |
| 39 | [regions](https://registry.terraform.io/modules/Azure/regions/azurerm) (archived) | azurerm | 364,289 | 823,168 | |
| 40 | [avm-res-app-managedenvironment](https://registry.terraform.io/modules/Azure/avm-res-app-managedenvironment/azurerm) | azurerm | 350,236 | 411,158 | v0.6.0 `c6709095a923` |
| 41 | [avm-res-network-applicationgateway](https://registry.terraform.io/modules/Azure/avm-res-network-applicationgateway/azurerm) | azurerm | 347,827 | 475,384 | v0.6.0 `f5961205a904` |
| 42 | [avm-ptn-network-private-link-private-dns-zones](https://registry.terraform.io/modules/Azure/avm-ptn-network-private-link-private-dns-zones/azurerm) | azurerm | 338,739 | 549,979 | v0.23.2 `4d2214f16280` |
| 43 | [vnet](https://registry.terraform.io/modules/Azure/vnet/azurerm) (archived) | azurerm | 319,356 | 3,424,330 | 5.0.1 `27359ed29033` |
| 44 | [avm-res-network-ddosprotectionplan](https://registry.terraform.io/modules/Azure/avm-res-network-ddosprotectionplan/azurerm) | azurerm | 288,387 | 465,403 | v0.3.0 `2d455cb9c6c6` |
| 45 | [avm-ptn-alz-management](https://registry.terraform.io/modules/Azure/avm-ptn-alz-management/azurerm) | azurerm | 281,649 | 471,782 | v0.10.0 `3026684f8aa4` |

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
| ContainerRegistry Registry | 2025-11-01 (released in v2.22.0 as `v20251101`; found when the chart was built) | 2025-11-01 |
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
| root | Linux or Windows VM, managed disks and attachments, NICs and their associations (LB, App Gateway, ASG, NSG, NAT rule), public IP, admin password in Key Vault, maintenance configuration assignment, backup protected item, auto-shutdown schedule | `compute/VirtualMachine` (2022-03-01; data disks inline), `compute/Disk`, `network/NetworkInterface` (associations inline), `network/PublicIPAddress`, `aso-ext` `VaultSecret`; aso-extensions `ConfigurationAssignment` (`maintenance.azure.hfl.dev`, 2023-04-01) and `Schedule` (`devtestlab.azure.hfl.dev`, 2018-09-15). **GAP**: the backup protected item (aso-extensions has Recovery Services vaults and policies, not `vaults/backupFabrics/protectionContainers/protectedItems`) |
| `extension` | VM extension | `compute/VirtualMachinesExtension` |
| `run-command` | VM run command | aso-extensions `VirtualMachinesRunCommand` (`compute.azure.hfl.dev`, 2022-03-01) |

The core works. The VM's ARM version is old. Charted as
`charts/azure/avm-res-compute-virtualmachine` (section 8).

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
| root | workspace, tables, data exports, linked service, linked storage account, private endpoint, AMPLS scoped resource, network security perimeter association | `operationalinsights/Workspace` (2025-07-01); the children through aso-extensions: `WorkspacesTable`, `WorkspacesDataExport`, `WorkspacesLinkedService`, `WorkspacesLinkedStorageAccount` (2025-07-01), `PrivateLinkScope`, `PrivateLinkScopesScopedResource` (2021-09-01), `NetworkSecurityPerimetersResourceAssociation` (2025-05-01) |
| `query_packs` | query packs and queries | aso-extensions `QueryPack`, `QueryPacksQuery` |
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

Covered, except the NIC association. Chart
`charts/azure/avm-res-network-loadbalancer` (2026-11-12): 22 of 23
variables, every child inline in the `LoadBalancer` (NAT rules too, not
`LoadBalancersInboundNatRule`, so one object owns them all), the public IPs
it makes as `PublicIPAddress` objects; `backend_address_pool_network_interfaces`
is refused (section 8).

### 14. avm-res-containerregistry-registry (v0.9.0)

| Submodule | Creates | ASO |
| --- | --- | --- |
| root | registry, replications, private endpoint | `containerregistry/Registry` (2023-07-01; 2025-11-01 next), `RegistryReplication` |
| `cache-rule` | `registries/cacheRules@2025-11-01` | `RegistryCacheRule` (2025-11-01) |
| `credential-set` | `registries/credentialSets@2025-11-01` | aso-extensions `RegistriesCredentialSet` (`containerregistry.azure.hfl.dev`, 2025-11-01) |
| `scope-map` | scope map, token, token password | aso-extensions `RegistriesScopeMap`, `RegistriesToken` (2025-11-01); a token's password is a secret returned once (refused) |

### 15. avm-res-network-firewallpolicy (v0.3.4; azurerm)

| Submodule | ASO (2025-03-01) |
| --- | --- |
| root | `network/FirewallPolicy` |
| `rule_collection_groups` | `FirewallPoliciesRuleCollectionGroup` |

Covered. Chart `charts/azure/avm-res-network-firewallpolicy` (2026-11-12):
21 of 22 variables (`firewall_policy_timeouts` refused by design), the
submodule as the chart value `rule_collection_groups`.

### 16. avm-res-containerservice-managedcluster (v0.9.0; azapi)

| Submodule | ARM types | ASO |
| --- | --- | --- |
| root | `managedClusters@2026-03-01` (and `2026-03-02-preview`), credential actions | `containerservice/ManagedCluster` (2025-08-01). The kubeconfig is exported to a Secret through `operatorSpec.secrets` |
| `agentpool` | `managedClusters/agentPools@2026-01-02-preview` | `ManagedClustersAgentPool` (2025-08-01) |
| `maintenanceconfiguration` | `maintenanceConfigurations@2026-03-01` | `MaintenanceConfiguration` |
| `namespace` | `managedNamespaces@2026-03-01` | aso-extensions `ManagedClustersManagedNamespace` (`containerservice.azure.hfl.dev`, 2026-05-01) |
| `monitoring` | data collection rules, endpoints and associations | `insights/DataCollectionRule`, `DataCollectionEndpoint`, `DataCollectionRuleAssociation` (2024-03-11) |
| `alerting` | Prometheus rule groups, action groups, metric alerts | `alertsmanagement/PrometheusRuleGroup`, `insights/ActionGroup`, `insights/MetricAlert` |

Covered; managed namespaces through aso-extensions. Charted as `charts/azure/avm-res-containerservice-managedcluster` (section 8).

### 17. avm-res-dbforpostgresql-flexibleserver (v0.2.3; azurerm)

| Submodule | Creates | ASO (2025-08-01) |
| --- | --- | --- |
| root | server, Entra administrator, configurations, firewall rules, virtual endpoint, private endpoint | `dbforpostgresql/FlexibleServer`, `FlexibleServersAdministrator`, `FlexibleServersConfiguration`, `FlexibleServersFirewallRule`, `FlexibleServersVirtualEndpoint` |
| `database` | database | `FlexibleServersDatabase` |

The ARM side is covered. Database users are the data plane: `aso-ext`
`dbforpostgresql.azure.hfl.dev/User` (Entra principals, privileges, schema
and default privileges, ownership).

Charted as `charts/azure/avm-res-dbforpostgresql-flexibleserver`
(2026-11-12): 36 of 40 variables and 6 of 6 outputs, private endpoints
included. The administrator password (`administrator_password` and its
write-only pair) is refused: a secret value does not belong in a
component's inputs, so a server the chart creates uses Entra
authentication only (section 8).

### 18. avm-res-cognitiveservices-account (v0.11.1)

| Submodule | ARM types | ASO (2025-06-01) |
| --- | --- | --- |
| root | `CognitiveServices/accounts@2025-06-01`, customer-managed key | `cognitiveservices/Account` (the key is inline) |
| `deployment` | `accounts/deployments` | `cognitiveservices/Deployment` |
| `rai_policy` | `accounts/raiPolicies@2024-10-01` | **GAP** in ASO; `aso-ext` `cognitiveservices.azure.hfl.dev/AccountsRaiPolicy` |

Chart `charts/azure/avm-res-cognitiveservices-account` (2026-11-13): 38 of
41 variables (`retry`, `timeouts` by design; the search service key, a
secret value, not ported; a user-assigned identity for the customer
managed key and a deployment's dynamic throttling refused: field gaps), 7
of 11 outputs (not the access keys, the sensitive object or the whole
account). Private endpoints, deployments and RAI policies are mapped.
Not applied live yet: the sandbox subscription has not registered the
`Microsoft.CognitiveServices` provider, and ASO's attempt to register it
(`POST /subscriptions/<id>/providers/Microsoft.CognitiveServices/register`)
is a subscription-scope action the live identity is refused (403
`AuthorizationFailed`, run `cat11130328999c`; nothing was created). The
`cog` case of `hack/azure-live.sh` (a free Language account, no
deployments) is ready and out of the default cases until someone with
subscription rights registers the provider (`az provider register
--namespace Microsoft.CognitiveServices --subscription <sandbox>`). Its
`tests/mock.values.yaml` passed against the fake cloud (stock ASO and
aso-extensions' manager against fakearm at `b9beb5b`, with PR #118's
`hack/azure-mock.sh`, run `off-catalog-1113030744-29467`: the account, a
deployment and its RAI policy Ready and deleted, outputs evaluated).

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
| `Insights/components@2020-02-02`, `components/pricingPlans`, `privateLinkScopes/scopedResources`, `components/linkedStorageAccounts` | `insights/Component` (2020-02-02), `insights/PricingPlan` (2017-10-01); the scoped resource through aso-extensions' `PrivateLinkScopesScopedResource` (2021-09-01). **GAP**: the profiler's linked storage account |

Charted as `charts/azure/avm-res-insights-component` (2026-11-12): 20 of
25 variables and 5 of 6 outputs (the deprecated `resource` is not one).
Refused: `linked_storage_account` (no kind), `ignore_body_changes`,
`resource_types`, `retry` and `timeouts` (section 8); accepted in part:
`application_type` (ASO's `Component` enumerates `web` and `other` only)
and `monitor_private_link_scope` (kind `Resource` only: the
aso-extensions kind's 2021-09-01 API has no `kind` or
`subscriptionLocation`).

### 21. avm-res-app-containerapp (v0.9.0; azapi)

| ARM types | ASO (2025-01-01) |
| --- | --- |
| `App/containerApps@2025-07-01` (and a preview), `containerApps/authConfigs@2025-01-01` | `app/ContainerApp`, `app/AuthConfig`. Covered, on an older API |

Covered, but for `kind`. Chart `charts/azure/avm-res-app-containerapp`
(2026-11-13): 22 of 24 variables and all 12 outputs; the app as a
`ContainerApp` (2025-01-01), each `auth_configs` entry as an `AuthConfig`.
Refused: `kind` (2025-01-01 has none), `timeouts` (by design), and in part
a null `location`, an identity setting's `Retain` lifecycle (not in
2025-01-01), registry passwords and secret values (secret values; Key
Vault references are taken).

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

Chart `charts/azure/avm-res-network-privateendpoint` (2026-11-13): 17 of
21 variables (`ignore_body_changes` a gap; `retry`, `timeouts` and
`resource_types` by design), 5 of 5 outputs (`private_ip_addresses` from
the endpoint's DNS configurations, not from its network interface).

### 24. avm-res-authorization-roleassignment (v0.3.1; azurerm and azuread)

| Creates | ASO |
| --- | --- |
| Azure RBAC role assignments | `authorization/RoleAssignment`, `RoleDefinition` (2022-04-01) |
| Entra directory role and directory role assignment | **GAP** in ASO (its Entra group has `Application`, `SecurityGroup` and `ServicePrincipal`); `aso-ext` `DirectoryRoleAssignment` (`entra.azure.hfl.dev/v1`, Microsoft Graph) |

Chart `charts/azure/avm-res-authorization-roleassignment` (2026-11-13): 17
of 31 variables, 4 of them in part, and 11 of 11 outputs (`role_defintions`
without the definitions' assignable scopes). Role assignments at every
scope variable are ASO `RoleAssignment`s owned by the scope's ARM ID, a
role by ID or by name (`wellKnownName`); Entra directory role assignments
are aso-extensions `DirectoryRoleAssignment`s, a role by template ID
(Graph assigns one without activating it, so `azuread_directory_role` is
not needed). Principals are taken by object ID. The 14 variables refused
whole are the module's lookups, which a render cannot make: users, groups,
applications and managed identities by name, mail, employee ID or client
ID in Microsoft Entra, and a user-assigned identity by group and name in
Resource Manager; no ASO or aso-extensions kind looks a principal up. In
part: `role_definitions.scope` (a lookup scope ASO's name resolution does
not take), `entra_id_role_definitions.display_name`, a management group by
display name, and `role_assignments_for_resources`, which needs a
`resource_type` the module reads from Resource Manager. Not applied live:
the live rules forbid role assignments, and the sandbox identity cannot
write them; the fake-cloud run applies an assignment by name, one by ID and
a directory role assignment through aso-extensions' fake Microsoft Graph
(chart README).

### 25. avm-res-network-bastionhost (v0.9.0)

| Creates | ASO |
| --- | --- |
| Bastion host | `network/BastionHost` (2025-03-01). Covered |

Covered. Chart `charts/azure/avm-res-network-bastionhost` (2026-11-12):
21 of 21 variables, every SKU (Developer as the network-only host), the
public IP it makes as a `PublicIPAddress`.

### Just below the top 25

| Module | ASO coverage |
| --- | --- |
| avm-res-sql-server (31) | server, databases, elastic pools and firewall rules: `sql/Server`, `ServersDatabase`, `ServersElasticPool`, `ServersFirewallRule` and 20 more `sql/*` kinds. The admin password goes to Key Vault (`aso-ext` `VaultSecret`). Entra database users: aso-extensions candidate a1, PR #5104 |
| avm-res-network-azurefirewall (32) | `network/AzureFirewall`. Covered. Chart `charts/azure/avm-res-network-azurefirewall` (2026-11-13): 18 of 23 variables (the five refused are the azapi mechanics: `ignore_body_changes`, `resource_types`, `retry`, `timeouts`, `firewall_timeouts`), 2 of 4 outputs: ASO's status has no IP configuration's private address (section 8) |
| avm-res-web-serverfarm (33) | `web/ServerFarm`. Covered. Chart `charts/azure/avm-res-web-serverfarm` (2026-11-12): `ServerFarm` at 2025-05-01 (the module sends 2025-03-01), 24 of 27 variables (`retry`, `timeouts` and a non-default `server_farm_resource_type` refused), both outputs |
| avm-ptn-alz (35) | management groups, policy definitions, policy set definitions and policy assignments are all **GAP** (no `Microsoft.Management` or `Microsoft.Authorization/policy*` kinds; management groups are issue #2249, open). Role definitions and assignments, and identities, are covered |
| avm-res-documentdb-databaseaccount (36) | `documentdb/DatabaseAccount` and its SQL and Mongo children. **GAP**: Gremlin databases and graphs, SQL dedicated gateway |
| avm-res-network-dnsresolver (37) | `network/DnsResolver`, its inbound and outbound endpoints, forwarding rulesets, rules and VNet links (2022-07-01, the version azurerm sends). Covered. Chart `charts/azure/avm-res-network-dnsresolver` (2026-11-13): 10 of 10 variables, 7 of 7 outputs (the azurerm-shaped ones with the attributes ASO's status has); live case `dnspr` (chart README) |
| avm-res-cache-redis (38) | `cache/Redis`, access policies, assignments, firewall rules, linked servers (2024-11-01). Covered |
| avm-res-app-managedenvironment (40) | `app/ManagedEnvironment`. **GAP**: all nine child types (Dapr components and subscriptions, storages, certificates, managed certificates, Java and .NET components, HTTP route configs, maintenance configurations) |
| avm-res-network-applicationgateway (41) | `network/ApplicationGateway` (2022-07-01, old). Chart `charts/azure/avm-res-network-applicationgateway` (2026-11-12): 41 of 50 variables, everything 2022-07-01 carries; what later versions added is refused by name (section 8) |
| avm-ptn-network-private-link-private-dns-zones (42) | `network/PrivateDnsZone`, `PrivateDnsZonesVirtualNetworkLink` (2024-06-01). Covered. Chart `charts/azure/avm-ptn-network-private-link-private-dns-zones` (2026-11-13): 18 of 19 variables (`timeouts` refused; `location` accepted in part for the regions of `avm-utl-regions` 0.12.0's data, which the chart carries as a table for `{regionName}` and `{regionCode}`, where the module reads the subscription's live list; a link name template takes the module's four placeholders, not other Terraform template expressions), 3 of 3 outputs; the module's zone and link logic is computed in the template. Live (three zones and their links to a network of the run) passed in run `cat111308205866`, the fake cloud in `off-catalog-1113080244-7256` |
| avm-res-network-ddosprotectionplan (44) | `network/DdosProtectionPlan` (2025-03-01). Covered. Chart `charts/azure/avm-res-network-ddosprotectionplan` (2026-11-13): 7 of 7 variables, 3 of 3 outputs. Not applied live: Azure bills a DDoS Network Protection plan at about 2,944 USD a month from its creation, far above the sandbox's limit; renders and the fake cloud only (chart README) |
| avm-ptn-alz-management (45) | `resources/ResourceGroup`, `operationalinsights/Workspace`, `insights/DataCollectionRule` (2024-03-11; the module sends 2021-04-01), `managedidentity/UserAssignedIdentity`; aso-extensions `AutomationAccount`, `WorkspacesLinkedService`, `Solution` (OperationsManagement) and Sentinel's `OnboardingState`. Covered. Chart `charts/azure/avm-ptn-alz-management` (2026-11-13): 29 of 30 variables (`timeouts` refused), 6 of 8 outputs (the two `*_keys` outputs are secrets); `automation_account.dsc_server_endpoint` is always null: aso-extensions' `AutomationAccount` status has no `agentRegistrationInformation`. Not applied live: the solutions (the sandbox subscription has not registered `Microsoft.OperationsManagement`; 403 on its register action) and Sentinel onboarding (a paid SIEM) |

## 5. Gaps ranked for aso-extensions

aso-extensions has a rule (plan.md section 1, open question 6, recommended):

- **Gaps in ARM go upstream to ASO as configuration**: an `$exportAs` entry,
  a sample and a recorded test.
- **Data-plane gaps, and gaps ASO declined, are built in aso-extensions.**

So each gap below says where it belongs. Ranked by how many of the 33 modules
in section 4 need it, then by downloads.

| # | Gap | Modules needing it | Kind of gap | Upstream | Belongs |
| --- | --- | --- | --- | --- | --- |
| 1 | Management locks (`Microsoft.Authorization/locks`) | 31 of 33 (optional `lock` input everywhere) | ARM | issue #3756 open; #4629 closed | not needed for the first catalog (2026-11-10); `lock` is refused until then. See below |
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

**Where these stand at aso-extensions `b9beb5b` (2026-11-12, 232
CRDs).** Built there, as kinds the charts can render: 1 (`ManagementLock`),
2 (`VaultSecret`), 3 (`ManagedEnvironments*` and `ConnectedEnvironments*`:
Dapr components, storages, certificates, managed certificates and more),
4 in part (slots, hostname bindings, certificates; not config sections or
publishing policies), 5 (tables, data exports, linked services, linked
storage, query packs, solutions), 6, 8 (management groups, Azure Policy,
budgets, vWAN hub connections, tags), 9, 10 (run commands, DevTest Labs
schedules, maintenance assignments, Recovery Services vaults and backup
policies), 11, 12, 13 (Gremlin, dedicated gateway services), 14, 15, 16
and the certificate import of 17. Still open: 7 (ASO's own `VaultKey`),
Key Vault certificate contacts (17), App Service config sections and
publishing policies (4) and the stale ARM versions (18).

Already built in aso-extensions and needed by the top modules:

- `VaultSecret` for keyvault, virtual machine, storage account and
  sql-server;
- the PostgreSQL `User` for the flexible server's database users.

**Answered 2026-11-10 (K10): resource locks are not needed
for the first catalog.** Locks are the single biggest gap by count, and
optional in AVM (default off), so the first Azure charts ship without them:
a chart keeps AVM's `lock` input, so a module call converts one to one, and
refuses it when set, naming the gap (as every chart refuses what it cannot
carry). Building a lock kind, upstream in ASO or in aso-extensions (the ARM
rule was reversed on 2026-11-09), waits until a later catalog asks for it.

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

## 8. Charts

Built from 2026-11-12. An Azure chart is a Google Cloud chart's twin
(`docs/design.md`, "A Package per module"), rendering ASO objects instead
of Config Connector's:

| | Google Cloud | Azure |
| --- | --- | --- |
| Directory, Package | `charts/gcp/<module>`, `gcp-<module>` | `charts/azure/<module>` (the AVM module's name), `azure-<module>`; `providers: [aso]` |
| Shared helpers | `lib/_kcc.tpl` (`kcc.*`) | `lib/_aso.tpl` (`aso.*`), copied into `templates/_aso.tpl` by `hack/sync-lib.sh` |
| Schemas the renders validate against | Config Connector v1.160.0 (`hack/kcc.sh`), `crds/config-connector-extensions` | ASO v2.22.0, the release's CRD bundle checked by SHA-256 (`hack/aso.sh`, `UPSTREAM.md`), `crds/aso-extensions` |
| Cloud name | `spec.resourceID` | `spec.azureName` (`nameFields` in `tests/name-prefix.yaml`) |
| Cloud labels or tags | unprefixed `metadata.labels` | `spec.tags`; every AVM module has a `tags` variable with that meaning. `labels` stay in Kubernetes |
| Parent | `cnrm.cloud.google.com/project-id` | `owner`: an object of the chart by `name`, or the module's `parent_id` (an ARM ID) as `armId` |
| `deletion_policy: ABANDON` | `cnrm.cloud.google.com/deletion-policy: abandon` | `serviceoperator.azure.com/reconcile-policy: detach-on-delete` on every object |
| Licence | Apache-2.0, `NOTICE` | MIT: `NOTICE` and `LICENSE.avm` in the chart |

**The AVM interfaces**, implemented once in `lib/_aso.tpl`:

| Interface | Object |
| --- | --- |
| `role_assignments` | `aso.roleAssignments`: ASO `RoleAssignment` (`authorization.azure.com/v20220401`), a role by ID (`armId`) or by name (`wellKnownName`) |
| `lock` | `aso.lock`: aso-extensions `ManagementLock` (`authorization.azure.hfl.dev/v1`); ASO has none (#3756) |
| `diagnostic_settings` | `aso.diagnosticSettings`: ASO `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`, Azure's only API version) |
| `private_endpoints` | ASO `PrivateEndpoint` and `PrivateEndpointsPrivateDnsZoneGroup`: per chart, when a chart maps it |

**What every AVM module has and the charts do not port.** Telemetry
(`enable_telemetry` is accepted; nothing is sent), and the azapi
provider's mechanics: `retry` and `timeouts` are refused when set (ASO
retries itself; Bundt sets a component's time limit), as is
`ignore_tag_changes` (ASO cannot leave a field to another writer).

**Refusals and gaps.** As on Google Cloud, a variable ASO and
aso-extensions cannot carry stays in the values and stops the render
naming the gap (`aso.unsupported`), and the chart's `upstream.yaml` lists
it with its kind (`gap`, `not-ported`, `by-design`), which `task coverage`
counts. Where the gap is a resource type with no ASO or aso-extensions
kind, the reason names the ARM type, so the list below is the queue for
aso-extensions:

| Chart | Variable | ARM type with no kind |
| --- | --- | --- |
| `avm-res-storage-storageaccount` | `static_website` | none: the blob service's data plane (Set Blob Service Properties, `staticWebsite`) |
| `avm-res-keyvault-vault` | `contacts` | none: Key Vault's data plane (certificate contacts, `/certificates/contacts`) |
| `avm-res-app-containerapp` | `kind`, `identity_settings[].lifecycle` `Retain` | none: fields of a later API version than ASO's `ContainerApp` (2025-01-01) |
| `avm-res-network-routetable` | `subnet_resource_ids` | none: the association is the `routeTable` property of an existing subnet; ASO has no subnet association kind and sets a subnet's properties only by owning the whole `VirtualNetworksSubnet` |
| `avm-res-network-loadbalancer` | `backend_address_pool_network_interfaces` | none: a NIC joins a pool through its own `ipConfigurations[].loadBalancerBackendAddressPools`; ASO has no association kind and sets a NIC's IP configurations only by owning the whole `NetworkInterface` |

The private DNS zone's `soa_record` maps to aso-extensions'
`PrivateDnsZonesSOARecord` (`network.azure.hfl.dev/v20240601`, its CRD
copied in `crds/aso-extensions`), which updates the SOA record set Azure
makes with the zone and leaves it when deleted.

The rest of what the charts refused for want of a kind now has one in
aso-extensions (at `b9beb5b`, the commit `ASOX_COMMIT` pins; 232 CRDs).
Each is a mapping still to land or landing, not a gap:

| Chart | Variable | aso-extensions kind | Mapped in |
| --- | --- | --- | --- |
| `avm-res-storage-storageaccount` | `local_user` | `StorageAccountsLocalUser` (`storage.azure.hfl.dev`) | not yet (its SSH keys are public keys; a password Azure generates would stay refused) |
| `avm-res-network-privatednszone` | `soa_record` | `PrivateDnsZonesSOARecord` (`network.azure.hfl.dev`) | #97 |
| `avm-res-containerregistry-registry` | `credential_sets`, a cache rule's `credential_set_key` | `RegistriesCredentialSet` (`containerregistry.azure.hfl.dev`) | #120 |
| `avm-res-containerregistry-registry` | `scope_maps` | `RegistriesScopeMap`, `RegistriesToken` (a token's passwords, secrets returned once, stay refused) | #120 |
| `avm-res-operationalinsights-workspace` | `log_analytics_workspace_data_exports` | `WorkspacesDataExport` (`operationalinsights.azure.hfl.dev`) | #121 |
| `avm-res-operationalinsights-workspace` | `log_analytics_workspace_dedicated_cluster_resource_id` | `WorkspacesLinkedService` (the module links a dedicated cluster with one) | #121 |
| `avm-res-operationalinsights-workspace` | `log_analytics_workspace_linked_storage_accounts` | `WorkspacesLinkedStorageAccount` | #121 |
| `avm-res-operationalinsights-workspace` | `log_analytics_workspace_tables`, `log_analytics_workspace_tables_update` | `WorkspacesTable` | #121 |
| `avm-res-operationalinsights-workspace` | `monitor_private_link_scope`, `monitor_private_link_scoped_resource`, `monitor_private_link_scoped_service_name` | `PrivateLinkScope`, `PrivateLinkScopesScopedResource` (`insights.azure.hfl.dev`) | the workspace follow-up to #88 (an existing scope's `exclusions` stay refused: the module updates a scope it does not own) |
| `avm-res-operationalinsights-workspace` | `network_security_perimeter_association` | `NetworkSecurityPerimetersResourceAssociation` (`network.azure.hfl.dev`) | #121 |
| `avm-res-containerservice-managedcluster` | `namespace` | `ManagedClustersManagedNamespace` (`containerservice.azure.hfl.dev`) | #102 |

The fake-cloud and live runs install aso-extensions' manager beside ASO
(`hack/asox-manager.sh`, below), so these kinds are applied and
reconciled, not only rendered.

Field gaps in ASO's agent pool (up to API 2025-10-02-preview), which
`avm-res-containerservice-managedcluster` refuses: `enableOSDiskFullCaching`
and `gpuProfile.nvidia` (`default_agent_pool` and `agent_pools`), and the
`ignore-pod-disruption-budget` option of a pool's delete
(`delete_options`).

The container registry's `credential_sets` (with a cache rule's
`credential_set_key`) and `scope_maps` with their tokens map to
aso-extensions' `RegistriesCredentialSet`, `RegistriesScopeMap` and
`RegistriesToken` (`containerregistry.azure.hfl.dev/v20251101`, CRDs copied
in `crds/aso-extensions`). A token's `passwords` stay refused: secrets
Azure generates and returns once, and whether a component may hold one is
the builder's decision.

The Log Analytics workspace's data exports, dedicated cluster link
(linked service), linked storage accounts, tables and table updates,
Monitor Private Link Scopes (with the workspace's scoped resource and the
scope's lock), scoped resources in existing scopes and network security
perimeter association map to aso-extensions kinds
(`operationalinsights.azure.hfl.dev`, `insights.azure.hfl.dev`,
`network.azure.hfl.dev`; CRDs copied in `crds/aso-extensions`). An existing
scope's `exclusions` stay refused: the module updates a scope it does not
own, after reading its access modes.

The storage account's `local_user` maps to aso-extensions'
`StorageAccountsLocalUser` (`storage.azure.hfl.dev/v20260601`, its CRD
copied in `crds/aso-extensions`); a local user's `ssh_password_enabled`
stays refused (Azure generates the password and returns it once, the
builder's decision).

**The application gateway's ARM version.** ASO v2.22.0's
`ApplicationGateway` is at ARM 2022-07-01 only (gap 18 in section 5), where
the module sends 2025-03-01. `avm-res-network-applicationgateway` maps
everything 2022-07-01 carries and refuses each later field by name when set:
`entra_jwt_validation_configs` (and a rule's `entra_jwt_validation_config`);
HTTP settings' `dedicated_backend_connection`, `sni_name`,
`validate_cert_chain_and_expiry` and `validate_sni`; backend settings'
`enable_l4_client_ip_preservation`; a TLS listener's `host_names`; a probe's
`enable_probe_proxy_protocol_header`; a rewrite header's
`header_value_matcher`; an SSL profile's `verify_client_auth_mode`; `sku.family`
and the Basic SKU; the `default_predefined_ssl_policy` output. ASO's
2022-07-01 type also takes a load distribution target only by reference (no
name, pool or weight) and has no `id` on a Private Link IP configuration or
a path rule. A new ASO version of the kind (upstream, a `$supportedFrom`
entry) closes all of them. Its certificates stay refused: ASO takes a
certificate's `data` and an SSL certificate's `password` only from a
Kubernetes Secret, and `key_vault_secret_id` is Key Vault secret material,
which waits on how a component supplies a secret (as the Key Vault
module's `secrets`).

The virtual machine (`avm-res-compute-virtualmachine`) maps 62 of the
module's 74 variables and 9 of its 13 outputs. Its interfaces, public IPs
and data disks are ASO objects; the module's association resources are
fields of the interface in ARM, and the data disk attachments entries of
the machine's `storageProfile.dataDisks`. Run commands, the shutdown
schedule and maintenance assignments are aso-extensions kinds
(`VirtualMachinesRunCommand`, `Schedule`, `ConfigurationAssignment`, CRDs
copied in `crds/aso-extensions`). It refuses what needs a secret value
(an admin password, generating an SSH key pair or password, protected run
command parameters and extension settings; the builder's decision), so a
Windows machine renders only from an attached OS disk; and the gaps:

| Chart | Variable | Missing |
| --- | --- | --- |
| `avm-res-compute-virtualmachine` | `azure_backup_configurations` | `Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems` (aso-extensions has the vault and its policies, not a protected item) |
| `avm-res-compute-virtualmachine` | `disk_controller_type`, `bypass_platform_safety_checks_on_user_schedule_enabled` | fields after ASO's `VirtualMachine` API version 2022-03-01 |
| `avm-res-compute-virtualmachine` | an extension's `provision_after_extensions`; a run command's managed identities | fields after the 2022-03-01 API version of ASO's `VirtualMachinesExtension` and aso-extensions' `VirtualMachinesRunCommand` |

Like azurerm, the chart sends `securityProfile.encryptionAtHost` only when
true: Azure refuses the property, even false, on a subscription without
the `EncryptionAtHost` feature (found live). It deletes an OS disk made
from an image with the machine (`osDisk.deleteOption: Delete`), as azurerm
does by default.

Not a kind gap, but an ASO field gap: a table's or share's
`signedIdentifiers[].id` is generated as an ARM reference
(`reference.armId`), so stored access policies cannot be given
(`avm-res-storage-storageaccount`'s `tables` and `shares`). Likewise ASO's `VaultKey` release policy has no `immutable`
flag (`avm-res-keyvault-vault`'s `keys`). ASO's cognitive services `Deployment` has no
`dynamicThrottlingEnabled` (`avm-res-cognitiveservices-account`'s
`cognitive_deployments`), and its `Account` takes the customer managed
key's `identityClientId` only as a literal, with no `FromConfig` form, so
a user-assigned identity's client ID, which the module reads from Azure,
cannot be given (`customer_managed_key.user_assigned_identity`). And ASO's `UserAssignedIdentity`
is at ARM API version 2023-01-31, without the later `isolationScope`
(`avm-res-managedidentity-userassignedidentity`'s `isolation_scope`).
An output gap of the same sort: ASO's `AzureFirewall` status gives an IP
configuration's ID only, not its private address, so
`avm-res-network-azurefirewall` has no `private_ip_address` output (nor
the azurerm-shaped `resource` that carries it).

`lib/_aso.tpl`'s `aso.diagnosticSettings` takes `selfWorkspace` for a Log
Analytics workspace, whose module sends a setting with no destination to
the workspace itself.

The network security group (`avm-res-network-networksecuritygroup`)
needs no gap: ASO's `NetworkSecurityGroup` has no `securityRules` field at
all, so its rules are always `NetworkSecurityGroupsSecurityRule` objects,
which is the arrangement the module forces by ignoring the group's
`securityRules`. Its diagnostic settings send no metrics (the shared
helper's `noMetrics`) and leave `Dedicated` to Azure (`dedicatedNull`), as
the module does.

A module whose parent is a resource group's name (azurerm's
`resource_group_name`, as the route table module's) has a chart value
`subscription_id` beside it, since ASO's owner is a resource ID;
`resource_group_name` may instead be the group's ID.

Open: the Key Vault module's `secrets` map onto aso-extensions'
`VaultSecret`, whose value comes from a Kubernetes Secret. The chart does
not map them until it is settled how a component supplies that Secret (a
secret's value does not belong in a component's inputs).

**Testing.** Layer 1 (render, `task test`) as on Google Cloud: golden
files, `kubeconform -strict` against ASO v2.22.0's CRDs and aso-extensions'
copied CRDs, refusals, `catalogtool ids` and `nameprefix`.

Layer 3 (live, `task test-live-azure`, `hack/azure-live.sh`): on an
offload VM acting as the service account the sandbox's app registration is
federated to (no secret, as aso-extensions' live runs), kind runs ASO
v2.22.0 from its own Helm chart, with cert-manager for the webhooks that
convert between its CRD versions (ASO cannot run without them, so it is
not run on the host as Config Connector is). ASO's credential is the VM's
Google ID token, mounted where ASO's global workload identity credential
reads it (`/var/run/secrets/tokens/azure-identity`, in place of the
chart's projected service account token, whose kind issuer Entra does not
trust). The virtual network, storage account, key vault, network security
group, route table, NAT gateway, public IP, private DNS zone, managed
identity, Log Analytics workspace, container registry, firewall policy, load
balancer, bastion host, private endpoint, application gateway and
firewall and container app charts are applied
(`AZURE_LIVE_CASES` picks some) with tiny resources named for the run, in the one resource group
the identity is Contributor on; every object must become Ready, the
Package's outputs are evaluated against the live objects, every object is
deleted and Azure must answer 404 for it; anything of the run left is
swept. The resource group chart (subscription scope) and the
aso-extensions lock (Contributor cannot write locks) are not applied. A
deleted key vault stays soft-deleted for 7 days (purging needs a
subscription-scope right). First passed on 2026-11-12; the network
security group (two rules), route table (two routes, the group by name
and `subscription_id`), NAT gateway (Standard, with a public IP it makes)
and public IP (the group by ID) passed on 2026-11-12 too: 9 objects
Ready, outputs evaluated (the allocated addresses among them), deleted,
Azure answering 404, nothing left. The private DNS zone (an A and a TXT
record), the managed identity (a federated credential; no outbound role
assignment, which the live identity may not make) and the Log Analytics
workspace (a diagnostic setting to itself) passed the same way (run
`cat1112191727ea`, 7 objects), and the container registry (Basic, a
cache rule from MCR) in run `cat11121946e404`. The first registry run
found that Azure refuses a Docker Hub cache rule without credentials.
The firewall policy (Basic, one rule
collection group with a network and an application rule collection)
passed in run `cat111223417a80`: 2 objects, outputs evaluated, nothing
left. Its `tests/mock.values.yaml` passed against the fake cloud too
(stock ASO against aso-extensions' fakearm at `e3b4177`, run
`off-catalog-1112233431-23161`: 2 objects Ready and deleted, outputs
evaluated).
The load balancer (public Standard,
with the public IP it makes, a pool, a TCP probe, a rule, a NAT rule and
an outbound rule) passed in run `cat11130126a761` on 2026-11-13: 2
objects, outputs evaluated (the address Azure allocated among them),
nothing left. Its `tests/mock.values.yaml` passed against the fake cloud
too (stock ASO against aso-extensions' fakearm at `b9beb5b`, with PR #98's
`hack/azure-mock.sh`, run `off-catalog-1113012254-13575`: 2 objects Ready
and deleted, outputs evaluated).
The bastion host (Basic, with the
public IP it makes, in the AzureBastionSubnet of a network the case
applies with it) passed in run `cat1113013124a2` on 2026-11-13: 4 objects
(the network and subnet among them), outputs evaluated (Azure's
`dnsName`), deleted, Azure answering 404, nothing left. Its
`tests/mock.values.yaml` passed against the fake cloud too (stock ASO
against aso-extensions' fakearm at `b9beb5b`, with PR #98's
`hack/azure-mock.sh`, run `off-catalog-1113012705-23006`: 2 objects Ready
and deleted, outputs evaluated).
The private endpoint (to a storage
account's blob service, with a DNS zone group in the blob service's
private DNS zone and a custom network interface name, in a subnet of a
network the case applies with it, the zone and the account applied with
it too) passed in run `cat11130308507d` on 2026-11-13: 6 objects Ready,
outputs evaluated (the network interface's ID and the endpoint's private
address from its DNS configurations), deleted, Azure answering 404. Its
`tests/mock.values.yaml` passed against the fake cloud too (stock ASO
against aso-extensions' fakearm at `b9beb5b`, with PR #118's
`hack/azure-mock.sh`, run `off-catalog-1113025403-8599`: the endpoint and
its zone group Ready and deleted, outputs evaluated).

The App Service plan chart (`avm-res-web-serverfarm`) is not applied live:
the sandbox subscription's App Service quota is 0 in eastus2, for B1 and
F1 alike. Its case (`asp`: Linux B1, one worker) ran only when named and
Azure refused it ("Operation cannot be completed without additional
quota", runs `cat11130326bbfc` with B1 and `cat111303502c33` with F1, on
2026-11-13; nothing was made). Raising the quota is a subscription-scope
change the live rules forbid, so the case waits on the builder. Its
`tests/mock.values.yaml` passed against the fake cloud (PR #118's
`hack/azure-mock.sh` with `web.azure.com` in its `crdPattern`, run
`off-catalog-1113031322-10940`: the plan Ready and deleted, outputs
evaluated).

The virtual machine chart has a live case (`AZURE_LIVE_CASES=vm`: a Linux
machine with an interface, a public IP it makes, a data disk and a script
extension, its subnet from the network chart), but it is not in the
default set: on 2026-11-13 Azure refused the sandbox subscription every
machine size tried with "Capacity Restrictions" (Standard_B1s and
Standard_B2s in eastus2 and eastus, Standard_D2s_v3 in eastus2; the
subscription has no quota for the v2 B families). In those runs
(`cat11130259f6a3`, `cat111303464b84` and others) the interface, public
IP, data disk and network became Ready, the outputs that read them evaluated (the
interface's private address and the public IP's), and were deleted with
Azure answering 404; the machine and its extension never became Ready.
Lifting the restriction is a subscription-level request, the builder's.
The first run found that Azure refuses `encryptionAtHost: false` without
the subscription feature; the chart now omits it, as azurerm does. The
chart's `tests/mock.values.yaml` passed against the fake cloud (stock ASO
against aso-extensions' fakearm at `b9beb5b`, with PR #98's
`hack/azure-mock.sh`, run `off-catalog-1113013113-10644`): the machine,
interface, public IP, data disk and extension Ready and deleted, outputs
evaluated. Both runs install the aso-extensions manager beside ASO
(below), so its kinds (run commands, shutdown schedules, maintenance
assignments, locks) can be applied, not only rendered; the mock values
carry none of them yet.

The application gateway (Standard_v2,
capacity 1, the public IP it makes, on a subnet the case first makes with
the virtual network chart, a pool, HTTP settings with a probe, a listener
and a basic rule, every reference by key) passed in run `cat111303093fb2`
on 2026-11-13: 4 objects Ready, outputs evaluated (operational state
Running, the allocated address), deleted, Azure answering 404. Neither cost
nor time forbids it: Standard_v2 at capacity 1 is about 0.25 USD an hour,
and the whole case (network, gateway, deletes) took about 20 minutes, most
of it the gateway's create and delete, so the case has a 40-minute limit.
Its `tests/mock.values.yaml` passed against the fake cloud too (PR #118's
`hack/azure-mock.sh`, run `off-catalog-1113030418-6345`: 2 objects Ready
and deleted, outputs evaluated).

The firewall (`avm-res-network-azurefirewall`, case `afw`: Basic,
zoneless, in the AzureFirewallSubnet of a network the case makes first,
with the AzureFirewallManagementSubnet and the two Standard public IPs a
Basic firewall needs, made first too as ASO objects of no chart; no
policy, so it passes nothing) passed in run `cat1113040454ba` (offload
`off-catalog-1113040024-17962`) on 2026-11-13, and again on this loop's
prerequisites (`afw-pre.objects.yaml`) in run `cat11130600091d` (offload
`off-catalog-1113055650-13517`): 6 objects Ready, outputs evaluated,
deleted, Azure answering 404. A Basic firewall is about 0.4 USD
an hour while it exists and the case took about 28 minutes, most of it the
firewall's create and delete, so it fits the sandbox and has a 40-minute
limit. Its `tests/mock.values.yaml` passed against the fake cloud too (PR
#118's `hack/azure-mock.sh`, aso-extensions `b9beb5b`, run
`off-catalog-1113034015-32067`: the firewall and its lock Ready and
deleted, outputs evaluated).

The Application Insights component (`avm-res-insights-component`, case
`appi`: workspace-based, a 1 GB daily cap, with a workspace the case makes
beside it) passed in run `cat111302020b65`: 3 objects Ready, outputs
evaluated (the app ID and connection string among them), deleted, Azure
answering 404. Its first run found that Azure cannot delete a component's
pricing plan (it goes with the component; ASO answers
`DeletionNotSupportedInAzure`), so the chart's `PricingPlan` is always
detached on delete, as the module's `azapi_update_resource` leaves it. Its
`tests/mock.values.yaml` passed against the fake cloud too (stock ASO
against aso-extensions' fakearm at `b9beb5b` with PR #98's
`hack/azure-mock.sh`, run `off-catalog-1113013709-32534`: 2 objects Ready
and deleted, outputs evaluated).

The container app (`avm-res-app-containerapp`, case `ca`: Microsoft's
public hello-world image, scaled to zero, external ingress on port 80, in
a Consumption-only environment the case makes first as an ASO object of
no chart) passed in run `cat111307137a10` (offload
`off-catalog-1113070946-25437`) on 2026-11-13: 2 objects Ready, the 12
outputs evaluated (the FQDN and outbound addresses among them), deleted,
Azure answering 404, nothing left. Earlier runs found that the sandbox
subscription may hold one Container Apps environment per region ("cannot
have more than 1 Container App Environments in East US 2"), so an
environment a stopped run leaves blocks the next until it is deleted
(about 25 minutes), and that ASO retries an app whose environment is still
provisioning only slowly, hence the environment first. Its
`tests/mock.values.yaml` passed against the fake cloud too (aso-extensions
`b9beb5b`, run `off-catalog-1113030900-10353`: the app and its auth config
Ready and deleted, outputs evaluated).

The PostgreSQL flexible server (`avm-res-dbforpostgresql-flexibleserver`,
case `psql`: Burstable B1ms, 32 GiB, Entra authentication only, a
database, a firewall rule for one documentation address, a server
parameter, and the live identity itself as its Entra administrator, a
PostgreSQL role on the server and not an Azure role assignment) passed in
run `cat11130237573e` in centralus: 5 objects Ready, outputs evaluated
(the FQDN among them), deleted, Azure answering 404. eastus2, the runs'
default region, refuses the SKU for this subscription ("Specified SKU is
not supported in this region"), so the case takes
`AZURE_LIVE_PSQL_LOCATION` (`centralus`). Run `cat11130155a5d6` found that
Azure cannot delete a server parameter (it goes with the server), so the
chart's `FlexibleServersConfiguration` is always detached on delete.
Against the fake cloud (PR #98's `hack/azure-mock.sh`, aso-extensions
`b9beb5b`, `dbforpostgresql.azure.com/*` added to its CRD pattern, as it now is; run
`off-catalog-1113011910-13823`) all 5 objects became Ready and were
deleted, but the outputs did not evaluate: the fake Resource Manager does
not compute a server's `fullyQualifiedDomainName` (a gap for
aso-extensions' `pkg/fakecloud/arm/computed.go`).


The AKS chart (`avm-res-containerservice-managedcluster`) is not applied
live: AKS makes the cluster's node resource group (`MC_<group>_<name>_<region>`,
or `node_resource_group`) beside the sandbox's one resource group, at
subscription scope, where the live identity has no rights and the live
rules allow no change. Its renders and the fake cloud are its tests.

Layer 2 (the fake cloud, `task test-mock-azure`, `hack/azure-mock.sh`): on
an offload VM, kind runs aso-extensions' fake Resource Manager
(`cmd/fakearm`, a store of resources by ARM ID) and fake Entra
(`cmd/fakeentra`, answering as `login.microsoftonline.com` through a
CoreDNS rewrite), built from aso-extensions at `ASOX_COMMIT` (Taskfile),
both over TLS from a throwaway CA; stock ASO v2.22.0 from its own chart
talks to them (`azureResourceManagerEndpoint`, workload identity, the CA
through `SSL_CERT_FILE`; the fakes listen on 443 in their pods, the only
egress ASO's network policies allow). Each chart's `tests/mock.values.yaml`
is applied, every object must become Ready and be deleted, and the
Package's outputs must evaluate against the live objects. First run on
2026-11-12 (run `off-catalog-1112211443-12213`): 23 of 26 objects Ready
and deleted across the twelve charts; the three that were not were the
fake's gaps (a vault's `vaultUri`, a storage account's default blob and
queue services). aso-extensions `b9beb5b` closed them: its fake Resource
Manager computes what Azure computes and the charts read (addresses,
principal IDs, a login server, a vault's URI, FQDNs, endpoints), makes a
storage account's default services and a DNS zone's SOA record set, and
serves Key Vault keys in the vault's data plane, which ASO's `VaultKey`
reads (`<vault>.vault.azure.net` is `fakearm` inside the cluster, through
a second CoreDNS rewrite; `fakearm` is given ASO's tenant, which Key
Vault's challenge names). Run `off-catalog-1112232041-31702`: 26 of 26
objects Ready and deleted, every chart's outputs evaluated.

**aso-extensions' manager in both runs** (`hack/asox-manager.sh`, sourced
by `hack/azure-mock.sh` and `hack/azure-live.sh`). aso-extensions at
`ASOX_COMMIT` is built once per run: its manager from `cmd/manager` (the
stock build: it reads ASO's `aso-controller-settings`, so it talks to the
Resource Manager ASO talks to) into a scratch image with the host's CA
bundle, loaded into kind and installed from its `config/default` (its 232
CRDs, its RBAC, the manager under its own service account
`aso-extensions-manager` in ASO's namespace). The manager starts an
informer for every ASO kind its kinds name as owners and exits when one's
CRD is missing, so ASO's `crdPattern` takes those groups too
(`ASOX_OWNER_GROUPS`). Its token is ASO's: against
the fake, a projected service account token for Entra's audience
(`fakearm` trusts that subject too) and the fake cloud's CA through
`SSL_CERT_FILE`; live, the node's directory holding the VM's Google ID
token. So the charts' aso-extensions kinds (a lock, an SOA record, an AKS
managed namespace, a registry's scope maps and tokens, a workspace's
tables ...) are applied and reconciled in both runs, not only rendered.
The identity chart's `tests/mock.values.yaml` carries a `CanNotDelete`
lock, which the fake honours: the identity's delete is refused with 409
`ScopeLocked` until the lock is gone. Live, a lock is still not applied:
writing `Microsoft.Authorization/locks` needs Owner or User Access
Administrator, and the live identity is Contributor on its group. First
run on 2026-11-13, with this branch merged with the charts that map
aso-extensions kinds (the registry and workspace follow-ups, the storage
account's local users, #97's SOA record, #102's AKS managed namespace):
fake cloud `off-catalog-1113015422-30541`, 43 of 43 objects Ready and
deleted and every chart's outputs evaluated, the aso-extensions objects
among them (the lock, which held the identity's delete until it went; the
SOA record; the managed namespace; a credential set, scope map and token;
a table, a table update, a data export, linked storage, a Monitor Private
Link Scope and its scoped resource; a local user). Live run
`cat1113015728ca` (storage, DNS, workspace and registry cases): 17 of 18
objects Ready, deleted and gone from Azure, nothing left; the SOA record,
the SFTP local user, the custom table, the Monitor Private Link Scope with
the workspace's scoped resource, the scope map and the token passed. The
credential set did not: Azure resolves its Key Vault secret URIs' host
when it is created ("Cannot resolve host"), so a live credential set needs
a real vault and secrets, which the case did not make.
