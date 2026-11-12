# kms

A KMS key, or a replica of a multi-Region key, with its key policy,
aliases and grants, as AWS Controllers for Kubernetes (ACK) objects. A port
of terraform-aws-modules'
[`terraform-aws-kms`](https://github.com/terraform-aws-modules/terraform-aws-kms/tree/d25e459bd43d8d0bdff7c250ba6b237a12be7381)
at v4.2.2 (`d25e459b`), Apache-2.0; modified (a translation of the
module's variables and its key policy document into a Helm chart). Bundt
Package `aws-kms` (`package.yaml`). Checked against ACK's kms-controller
v1.7.0 and ack-extensions' `ReplicaKey` (`crds/ack-extensions`).

## Example

```yaml
aliases: [app]
```

renders a `kms.services.k8s.aws/v1alpha1` `Key` (`hfl.dev/id` `key`) with
rotation on (the module's default) and an `Alias` `alias/app` pointing at
it (`tests/golden/default.yaml`). With the module's defaults the key
policy is the Default statement alone, which is what KMS's default key
policy grants, so the chart sets none.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_kms_key` | `create` | `kms/Key` `key`: `description`, `keySpec` (`customer_master_key_spec`), `keyUsage`, `customKeyStoreID`, `enableKeyRotation`, `multiRegion`, `bypassPolicyLockoutSafetyCheck`, `policy`, `tags` |
| `aws_kms_replica_key` | `create_replica`, with `allow_alpha: true` | ack-extensions `ReplicaKey` `key`: `keyID` (`primary_key_arn`), `replicaRegion` (`region`, required then), `description`, `policy`, `bypassPolicyLockoutSafetyCheck`, `tags`; the object's region is the primary key's, where `ReplicateKey` is called |
| `data.aws_iam_policy_document` | `policy` unset | the key policy JSON, built as the module builds it: `Default` (`enable_default_policy`), `KeyOwner`, `KeyAdministration`, `KeyUsage`, `KeyServiceUsage`, `KeyServiceRolesASG`, `KeyServiceRolesASGPersistentVol`, `KeySymmetricEncryption`, `KeyHMAC`, `KeyAsymmetricPublicEncryption`, `KeyAsymmetricSignVerify`, `Route53DnssecService` and `Route53DnssecGrant` (`enable_route53_dnssec`, `route53_dnssec_sources`), then `key_statements` |
| `aws_kms_alias` | each of `aliases` and `computed_aliases` | `kms/Alias` `alias-<key>`: `alias/<name>`, `targetKeyRef` to the key (a replica's: its key ID) |
| `aws_kms_grant` | each of `grants` | `kms/Grant` `grant-<key>`: `name` (default the key), `granteePrincipal`, `operations`, `retiringPrincipal`, `grantTokens`, `constraints` (one) |

**The account in the policy.** The module reads the account and partition
from the provider for the `Default` statement's principal
(`arn:<partition>:iam::<account>:root`) and a DNSSEC source without
`account_ids`. A chart cannot look them up, so it takes `account_id` and
`partition` (default `aws`), which Bundt fills from the Environment; the
render stops, saying so, when the policy needs `account_id` and it is
unset. The policy JSON is semantically the module's, not byte for byte
(every value is a list; keys are sorted).

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (no keys: no singular name can collide), `namePrefix`
(on alias names), `labels` (Kubernetes only), `account_id`, `partition`,
`allow_alpha` and `deletion_policy`; `tags` is the module's own, and
`region` becomes the annotation `services.k8s.aws/region`.

Refused or accepted in part (`upstream.yaml`):

- External keys and their replicas (`create_external`,
  `create_replica_external`, `key_material_base64`, `valid_to`, `key_spec`,
  `primary_external_key_arn`): no kind imports key material.
- `deletion_window_in_days`, `rotation_period_in_days`: no ACK field
  (KMS's defaults apply: 30 days, 365 days).
- `is_enabled: false`: no ACK field to disable a key.
- `source_policy_documents`, `override_policy_documents`: merging other
  documents by `sid` is not ported yet.
- `aliases_use_name_prefix`: a random suffix would change between renders.
- `grants`, in part: `retire_on_delete: true` (ACK revokes) and more than
  one `constraints` block.
- `create_replica`, in part: needs `allow_alpha: true` (ack-extensions).

## Outputs

`key_arn`, `key_id`, `key_region`, `key_policy`. Not provided: the external
key's outputs (refused), and `aliases` and `grants`, which are whole
Terraform objects.

## Differences from Terraform

- Deleting the component schedules the key's deletion with KMS's default
  waiting period (30 days), not `deletion_window_in_days`.
- The policy JSON differs in form from Terraform's (above): adopting a key
  Terraform made rewrites its policy to an equivalent one.

## Tests

`task test CHART=aws/kms`: golden renders validated against
kms-controller v1.7.0's CRDs and ack-extensions' `ReplicaKey` CRD, and the
refusal cases. `tests/mock.values.yaml` is the case a fake-AWS run will
apply (`docs/aws.md`, "Charts").
