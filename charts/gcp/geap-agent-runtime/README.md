# geap-agent-runtime

A Vertex AI Agent Engine runtime (a reasoning engine), with the service
account it runs as, that account's project roles and a staging bucket, as
Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/geap-agent-runtime`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/geap-agent-runtime)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-geap-agent-runtime` (`package.yaml`). The engine is
config-connector-extensions' `AIPlatformReasoningEngine`
(`aiplatform.gcp.hfl.dev/v1beta1`, at `0ee17dd`; Config Connector's own is
`v1alpha1`); the rest are Config Connector v1.160.0's `IAMServiceAccount`,
`IAMPolicyMember` and `StorageBucket`.

## Example

```yaml
name: my-agent
project_id: project-id
region: europe-west8
agent_runtime_config:
  agent_framework: google-adk
  identity_type: SERVICE_ACCOUNT     # required: AGENT_IDENTITY is refused
deployment_config:
  package_config:
    are_paths_local: false           # required: local paths are refused
    pickle_path: gs://my-bucket/pickle.pkl
    dependencies_path: gs://my-bucket/dependencies.tar.gz
    requirements_path: gs://my-bucket/requirements.txt
```

renders the `AIPlatformReasoningEngine` `my-agent` with its package in
GCS, the `IAMServiceAccount` `my-agent` it runs as, an `IAMPolicyMember`
on the project for each of `roles/aiplatform.user` and
`roles/storage.objectViewer`, and the `StorageBucket` `my-agent`
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.agent` sets the engine's display name, `names.serviceAccount` the service account ID and `names.bucket` the bucket's name, each in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name not set under `names` starts with `<namePrefix>-`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the engine (`spec.labels`) and the bucket |
| `tags` | not a fabric variable: cloud labels on the engine and the bucket |
| `name` | the engine's `displayName` (the API assigns its ID), and the service account ID and bucket name unless `service_account_config.name` or `bucket_config.name` is set |
| `project_id`, `region` | every object's project; the engine's `location` and the bucket's `location` |
| `description` | the engine's `description` (fabric's default `Terraform managed.`) |
| `encryption_key` | the engine's `encryptionSpec.kmsKeyRef` |
| `agent_runtime_config` | `agent_framework` → `spec.agentFramework`; `container_concurrency`, `max_instances`, `min_instances`, `resource_limits`, `environment_variables` (`env`) and `secret_environment_variables` (`secretEnv`) → `spec.deploymentSpec`, which is sent only when one of them (or a network attachment) is set, as fabric's; `python_version` → `spec.packageSpec.pythonVersion`. **`identity_type` must be `SERVICE_ACCOUNT`**: `AGENT_IDENTITY`, fabric's default, is refused (below). `class_methods` is refused: the kind has no `classMethods` |
| `deployment_config` | `package_config` with `are_paths_local: false`: its three paths are the engine's `packageSpec` GCS URIs. `are_paths_local: true` (fabric's default) is refused: a chart cannot read the caller's files to upload them, so the three `google_storage_bucket_object`s are never rendered. `container_config` and `source_files_config` are refused: the kind has no `containerSpec` or `sourceCodeSpec` |
| `bucket_config` | the `StorageBucket`, made when `create` (default) and a `package_config` is set, as fabric's: `name`, `uniform_bucket_level_access` |
| `service_account_config` | `create` (default): the `IAMServiceAccount` (`name`, `display_name`) and one `IAMPolicyMember` on the project per entry of `roles`, the account as member; the engine's `serviceAccountRef` names it. `create: false`: `email`, when set, is the engine's `serviceAccountRef`; nothing else is made |
| `networking_config` | `network_attachment_id` → `deploymentSpec.pscInterfaceConfig.networkAttachmentRef`, and with it `dns_peering_configs` → `dnsPeeringConfigs` (fabric sends them only with an attachment too). `agent_gateways` is refused: the kind has no `agentGatewayConfig` |
| `enable_deletion_protection` | `true` (default) is what Config Connector does. `false` is refused: it is Terraform's `deletion_policy = "FORCE"` on the engine (which also deletes its sessions and memories) and `force_destroy` on the bucket, and the kind has no force deletion |
| `managed` | `true` (default). `false` is refused: fabric's unmanaged engine ignores later code changes (`lifecycle.ignore_changes`), and Config Connector reconciles every field it is given |
| `memory_bank_config` | refused: the kind has no `contextSpec` |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the engine, the service account and the bucket (not the roles) |

Checks: the service account ID is 6 to 30 characters, starts with a letter
and ends with a letter or digit. With a `namePrefix`, a display name over
128, a service account ID over 30 or a bucket name over 63 characters
stops the render; a name set under `names` is always checked.

## Outputs

| Output | From |
| --- | --- |
| `id` | the engine's `status.externalRef`, `projects/<project>/locations/<region>/reasoningEngines/<id>`, the ID the API assigns at create; null until reported |
| `identity` | the email of the service account the chart makes (its `status.email`; null until reported), else `service_account_config.email`, else null |

Not outputs: `agent`, fabric's whole object.

## Differences from the module

- **No agent identity.** fabric's default `identity_type`,
  `AGENT_IDENTITY`, gives the engine an identity of its own and grants
  `service_account_config.roles` to it (`iam_member_identity`). The kind
  has no `identityType` and reports no `effectiveIdentity`, so the chart
  refuses it rather than make an engine that runs as something else.
  `identity` is therefore never fabric's `principal://...`, and with
  `create: false` and no `email` it is null where fabric returns a
  placeholder for the Vertex AI service agent.
- **References are full resource names**, as the kind validates them: a
  `secret_id` that is not `projects/...` becomes
  `projects/<project_id>/secrets/<secret_id>`, its version
  `<secret>/versions/<version>` (`latest` by default), and a DNS peering
  `target_network_name` that is not `projects/...` becomes
  `projects/<target project>/global/networks/<name>`. config-connector-
  extensions sends these to the API as written, where fabric sends the
  secret, version and network as given; whether the API takes the full
  names was not checked live.
- **Labels reach the cloud through `spec.labels`**, the unprefixed keys of
  the chart's `labels` and `tags`; fabric labels nothing.

## From Terraform

A `module "x" { source = ".../modules/geap-agent-runtime" ... }` block's
arguments become the values unchanged, apart from what is refused above:
set `identity_type = "SERVICE_ACCOUNT"`, and point `package_config` at
files already in GCS. An existing engine is adopted by its ID through
`AIPlatformReasoningEngine`'s `resourceID`, which this chart does not set;
the service account and the bucket keep their names, so they adopt what
Terraform made (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/geap-agent-runtime`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/geap-agent-runtime)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=geap-agent-runtime`: render cases `basic` (fabric's README
"Serialized Object Deployment", files in GCS), `sa-external`
("Identities"), `psc-i` ("Private networking"), `environment` ("Define
environment variables and use secrets", "Specify an encryption key"),
`minimal` (no code, no account), `full`, `names` and `mock`, each
validated against the CRDs in `crds/config-connector-extensions` and
Config Connector's, and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): the engine (`google-adk`, a package in
GCS), the service account it runs as with its two project roles, and the
staging bucket. On 2026-11-12 (offload VM `off-catalog-1113030135-20664`;
config-connector-extensions `0ee17dd`) all five objects became Ready, the
outputs evaluated (`id` the engine's
`projects/mock-project/locations/us-central1/reasoningEngines/<id>`,
`identity` the account's email) and everything was deleted. mockgcp does
not run the package: it stores the engine as sent. The PSC interface,
secrets, KMS key and environment are only render-tested.

Live: not run. The catalog's live harness runs Config Connector's
controllers only, not config-connector-extensions' (so not
`AIPlatformReasoningEngine`); the live-test project has the Vertex AI API
off, and neither live-test service account has a Vertex AI role. This work
changes no IAM and enables no API.

## Changes

- **0.1.0** (2026-11-12): the port: the engine with a package in GCS, its
  service account and roles, and the staging bucket.
