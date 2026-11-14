# avm-res-app-containerapp

An Azure Container App with its containers, init containers, probes,
volumes, scale rules, ingress, Dapr, registries, Key Vault secret
references, identities, authentication configurations, lock and role
assignments, as Azure Service Operator (ASO) objects. A port of the Azure
Verified Module
[`avm-res-app-containerapp`](https://github.com/Azure/terraform-azurerm-avm-res-app-containerapp/tree/ae03166abab035743ead9550bd32818bf75efdd9)
at v0.9.0 (`ae03166a`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-app-containerapp`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: ca-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
container_app_environment_resource_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.App/managedEnvironments/cae-example
template:
  containers:
    - {name: hello, image: mcr.microsoft.com/k8se/quickstart:latest, cpu: 0.25, memory: 0.5Gi}
ingress:
  external_enabled: true
  target_port: 80
  traffic_weight: [{latest_revision: true, percentage: 100}]
```

renders one ASO `ContainerApp` `ca-example` in the environment, reachable
from outside it on port 80 (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.container_app`, `azapi_resource_action.post_creation_update` | always | aso-extensions' `ContainerApp` (`app.azure.hfl.dev/v20260701`, beside ASO's 2025-01-01 kind under its name; aso-extensions `docs/plan.md` §8 open question 11), `container_app`, owned by the resource group. The module PATCHes the template after creation to avoid a PUT's checks; ASO sends the whole body on every change, template included |
| `azapi_resource.auth_config` | one per `auth_configs` entry | `AuthConfig` (`app.azure.com/v20250101`), `auth_config:<key>`, owned by the container app by its ARM ID (ASO's kind names ASO's `ContainerApp` as owner) |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `data.azapi_resource.rg`, `data.azapi_resource.existing`, `terraform_data.update_keeper`, telemetry | never | not ported: the render reads nothing from Azure |

## Moving from an earlier version

From this version the chart always renders aso-extensions' `ContainerApp`
(`app.azure.hfl.dev/v20260701`), never ASO's (`app.azure.com/v20250101`), so setting or clearing a newer field
never swaps the object's kind. That needs aso-extensions' manager and CRDs
installed beside Azure Service Operator (`docs/azure.md`, "8. Charts";
aso-extensions pin `ASOX_COMMIT`). For a deployment made by an earlier
version, which rendered ASO's kind, the upgrade replaces the Kubernetes
object with one of the other kind under the same name in Azure. Do it
once, with `deletion_policy: ABANDON`: apply the new version with
`ABANDON` (the old object is detached, and the new one adopts the app),
check it is Ready, then remove `ABANDON`. Without it, the old object's
delete deletes the app in Azure.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), with the module's defaults for
optional object attributes and its validations.

| Module input | ASO |
| --- | --- |
| `name` (required) | `azureName` (2 to 32 letters, digits and hyphens) |
| `resource_group_name` (required), `resource_group_id` | `owner.armId`: `resource_group_id` when set (checked to name the same group, as the module checks it), else `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a group's ID |
| `location` | `location`; required here (below) |
| `container_app_environment_resource_id` (required) | `environmentReference` and `managedEnvironmentReference`, as the module sends both |
| `kind` | `kind`: `functionapp` or `workflowapp`, lower-cased (the module passes any string; ARM's enum is lower case) |
| `workload_profile_name` | `workloadProfileName` |
| `revision_mode`, `max_inactive_revisions` | `configuration.activeRevisionsMode`, `maxInactiveRevisions` |
| `managed_identities` | `identity` (`SystemAssigned`, `UserAssigned` or both) |
| `identity_settings` | `configuration.identitySettings`: the identity by ID, its `lifecycle` (default `All`) |
| `dapr` | `configuration.dapr`, with the module's defaults (`http`, `info`, disabled) |
| `ingress` | `configuration.ingress`: `allowInsecure`, `clientCertificateMode`, `exposedPort`, `external`, `targetPort`, `transport` (lower case, as ASO's enum has it; the module title-cases it and Azure takes either), `additionalPortMappings`, `corsPolicy`, `customDomains` (`custom_domain` and `custom_domains` together, as the module concatenates them; a certificate by ID), `ipSecurityRestrictions`, `stickySessions`, `traffic` (a weight's `revision_suffix` is its `revisionName`, as in the module) |
| `registries` | `configuration.registries`: `server`, the pull identity (a user-assigned identity's ID, or `system`), and `username` with `password_secret_name` as `passwordSecretRef` (the name of one of the app's `secrets`, whose value is a reference to a Kubernetes Secret or a Key Vault secret) |
| `secrets` | `configuration.secrets`: a secret's `value` as a reference to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)); a string is refused. Or a Key Vault reference (`keyVaultUrl`, the identity by ID or `system`). One of the two, as in the module |
| `runtime`, `service` | `configuration.runtime.java.enableMetrics`, `configuration.service.type` |
| `template` | `template`: containers (args, command, env with values or secret names, image, `resources`, volume mounts, and probes built as the module builds them from `liveness_probes`, `readiness_probes`, `startup_probes` and the deprecated `startup_probe`, with its defaults), init containers, `revisionSuffix`, `scale` (cooldown, minimum and maximum replicas, polling interval, and the Azure Queue, custom, HTTP and TCP rules with their authentication and identity), `serviceBinds`, `terminationGracePeriodSeconds`, `volumes` |
| `auth_configs` | `AuthConfig`: `platform`, `globalValidation`, `identityProviders` (Entra ID, Facebook, GitHub, Google, Twitter, Apple, Static Web Apps and custom OpenID Connect providers), `login`, `httpSettings`, `encryptionSettings`. Secrets are named, not given: a provider's `*_setting_name` names a container app secret |
| `tags` | `spec.tags` |
| `lock` | the AVM lock interface, named `lock-<name>` by default |
| `role_assignments` | the AVM interface |
| `enable_telemetry` | accepted; the chart sends no telemetry |

`template.revision_suffix` is sent as given. The module sends it only when
it differs from the running app's, so a revision is not made twice; with
ASO, change the suffix whenever the template changes, or leave it unset and
let Azure name revisions.

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when it is a name and `resource_group_id` is not set: ASO's owner is a resource ID |
| `names.containerApp` | the container app's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 32-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `timeouts` | by-design | ASO has no per-request timeouts; Bundt sets a component's time limit |
| `location` null | by-design | the module reads the resource group's location then, which a render cannot; give `location` |
| `identity_settings[].lifecycle` `Retain` | gap | ASO's `ContainerApp` (2025-01-01) takes `All`, `Init`, `Main` and `None` |

## Outputs

| Output | From |
| --- | --- |
| `name`, `location` | the container app's `azureName` and `location` |
| `resource_id` | its `status.id` |
| `environment_id` | `container_app_environment_resource_id`, as the module returns it |
| `fqdn_url`, `latest_revision_fqdn` | `https://` and the ingress FQDN, the latest revision's FQDN; `""` before Azure gives one, as in the module |
| `latest_revision_name`, `latest_ready_revision_name`, `outbound_ip_addresses`, `custom_domains`, `custom_domain_verification_id` | `status`, null until Azure fills them |
| `identity` | `type`, `principal_id`, `tenant_id` and `identity_ids` (the user-assigned identities' IDs), the fields of the module's azapi identity block; null without an identity |

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name and `resource_group_id` is not set, and
`location` when the module call left it to the resource group. ASO adopts
a container app that exists when an object with its name is applied, so
keep the name and leave `namePrefix` empty; set `deletion_policy: ABANDON`
for the first apply, `terraform state rm` the module, then remove
`ABANDON`. A secret's value becomes a reference to the Kubernetes Secret
that holds it (External Secrets Operator puts it there; docs/secrets.md).

## Upstream

Ported from the Azure Verified Module
[`avm-res-app-containerapp`](https://github.com/Azure/terraform-azurerm-avm-res-app-containerapp/tree/v0.9.0)
at v0.9.0 (`ae03166a`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-app-containerapp`: render cases `basic`, `full`,
`names`, `kind` (aso-extensions' kind), `secrets` (secret values from a
Kubernetes Secret, a registry's password among them), `mock` (with a
secret from a Secret the fake-cloud run makes) and `mock-kind`, each validated against ASO v2.22.0's CRD schemas and
aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. `task test-live-azure` (case `ca`) applies a container
app from Microsoft's public hello-world image, scaled to zero, with
external ingress, in a Consumption-only environment the case makes beside
it, evaluates the outputs, deletes both and checks Azure no longer has
them. `task test-mock-azure` applies `tests/mock.values.yaml` to
aso-extensions' fake cloud.

Results (2026-11-13): live run `cat111307137a10` (offload
`off-catalog-1113070946-25437`), both objects Ready, outputs evaluated,
deleted and gone from Azure; fake cloud run `off-catalog-1113030900-10353`,
both objects Ready and deleted, outputs evaluated. 0.4.0 (2026-11-14): fake cloud run
`off-catalog-1114090347-8775` (aso-extensions `8d7f8c2`), `mock` with a
secret from a Secret the run made and `mock-kind`, every object Ready and
deleted, outputs evaluated. Live run `cat111409089072` (offload
`off-catalog-1114090347-26947`, 2026-11-14): the `ca` case with a secret
whose value is a reference to a Kubernetes Secret the run made, given to
the container as `API_KEY`; the environment and the app Ready, outputs
evaluated, both deleted and gone from Azure.

## Changes

- **0.4.0** (2026-11-14): `secrets[].value` is mapped as a reference to a
  Kubernetes Secret, `{secretName, key}` (docs/secrets.md, the builder's
  decision); a string is refused. With it `registries[].username` and
  `password_secret_name` are mapped (the password is one of the app's
  secrets).
- **0.3.0** (2026-11-14): always aso-extensions' `ContainerApp`, its auth
  configurations, lock and role assignments always owning it by ARM ID (the
  builder's choice). Moving from an earlier version: above.
- **0.2.0** (2026-11-13): `kind` is mapped: set, it renders aso-extensions'
  `ContainerApp` (`app.azure.hfl.dev/v20260701`, aso-extensions `8d7f8c2`)
  in place of ASO's, its auth configurations, lock and role assignments
  owned by its ARM ID.
- **0.1.0** (2026-11-13): the port.
