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
| avm-res-network-applicationgateway (41) | `network/ApplicationGateway` (2022-07-01, old). Chart `charts/azure/avm-res-network-applicationgateway` (2026-11-12): 41 of 50 variables, everything 2022-07-01 carries; what later versions added is refused by name (section 8) |

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
| `avm-res-storage-storageaccount` | `local_user` | `Microsoft.Storage/storageAccounts/localUsers` (SFTP and NFSv3 local users) |
| `avm-res-storage-storageaccount` | `static_website` | none: the blob service's data plane (Set Blob Service Properties, `staticWebsite`) |
| `avm-res-keyvault-vault` | `contacts` | none: Key Vault's data plane (certificate contacts, `/certificates/contacts`) |
| `avm-res-network-routetable` | `subnet_resource_ids` | none: the association is the `routeTable` property of an existing subnet; ASO has no subnet association kind and sets a subnet's properties only by owning the whole `VirtualNetworksSubnet` |
| `avm-res-network-privatednszone` | `soa_record` | `Microsoft.Network/privateDnsZones/SOA` (the zone's SOA record, which exists with the zone and is only updated; ASO has every other private DNS record kind) |

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

Not a kind gap, but an ASO field gap: a table's or share's
`signedIdentifiers[].id` is generated as an ARM reference
(`reference.armId`), so stored access policies cannot be given
(`avm-res-storage-storageaccount`'s `tables` and `shares`). Likewise ASO's `VaultKey` release policy has no `immutable`
flag (`avm-res-keyvault-vault`'s `keys`). And ASO's `UserAssignedIdentity`
is at ARM API version 2023-01-31, without the later `isolationScope`
(`avm-res-managedidentity-userassignedidentity`'s `isolation_scope`).

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
group, route table, NAT gateway, public IP and application gateway charts are applied
(`AZURE_LIVE_CASES` picks some) with tiny resources named for the run, in the one resource group
the identity is Contributor on; every object must become Ready, the
Package's outputs are evaluated against the live objects, every object is
deleted and Azure must answer 404 for it; anything of the run left is
swept. The resource group chart (subscription scope) and the
aso-extensions lock (its manager is not installed) are not applied. A
deleted key vault stays soft-deleted for 7 days (purging needs a
subscription-scope right). First passed on 2026-11-12; the network
security group (two rules), route table (two routes, the group by name
and `subscription_id`), NAT gateway (Standard, with a public IP it makes)
and public IP (the group by ID) passed on 2026-11-12 too: 9 objects
Ready, outputs evaluated (the allocated addresses among them), deleted,
Azure answering 404, nothing left. The application gateway (Standard_v2,
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

Layer 2 (the fake cloud) does not run yet for Azure. aso-extensions' fake
Resource Manager (`cmd/fakearm`) can stand in for Azure, but stock ASO
gets its token from Entra over HTTP (`AZURE_AUTHORITY_HOST`), and
aso-extensions' fake Entra is an in-process `http.RoundTripper` only: a
fake Entra server (and ASO trusting the fake cloud's CA) is what is
missing. Each chart's `tests/mock.values.yaml` is ready for it.
