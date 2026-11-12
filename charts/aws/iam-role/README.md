# iam-role

An IAM role with its trust policy, attached and inline policies and an
instance profile, as AWS Controllers for Kubernetes (ACK) objects. A port of
terraform-aws-modules'
[`terraform-aws-iam`](https://github.com/terraform-aws-modules/terraform-aws-iam/tree/55514b7873c411040395e024a422684998da77c2/modules/iam-role)
`iam-role` submodule at v6.8.2 (`55514b78`), Apache-2.0; modified (a
translation of the submodule's variables and its policy documents into a
Helm chart). Bundt Package `aws-iam-role` (`package.yaml`). Checked against
ACK's iam-controller v1.11.3 (`UPSTREAM.md`, "ACK controllers").

## Example

The submodule's README example "IAM Role - GitHub Free, Pro, & Team OIDC",
with a name and the account:

```yaml
name: github-actions
account_id: "111122223333"
enable_github_oidc: true
oidc_wildcard_subjects: ["terraform-aws-modules/terraform-aws-iam:*"]
policies:
  S3ReadOnly: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
tags: {Environment: test}
```

renders one `iam.services.k8s.aws/v1alpha1` `Role` (`hfl.dev/id` `role`)
trusting GitHub's OIDC provider for that repository, with the policy
attached (`tests/golden/github.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_iam_role` | `create` | `iam/Role` `role`: `name`, `path`, `description`, `assumeRolePolicyDocument`, `maxSessionDuration`, `permissionsBoundary`, `tags` |
| `data.aws_iam_policy_document.this` | always | the trust policy JSON, built as the submodule builds it: generic OIDC (one statement per `oidc_provider_urls` entry), `GithubOidcAuth`, `BitbucketOidcAuth` (the first provider URL), SAML, then `trust_policy_permissions` (in key order, `sid` defaulting to the key); `trust_policy_conditions` on every enabled federated statement; `source_trust_policy_documents` first and `override_trust_policy_documents` last, merged by `Sid` as `aws_iam_policy_document` merges them |
| `aws_iam_role_policy_attachment` | each of `policies` | `Role.policies`, in key order |
| `aws_iam_role_policy` | `create_inline_policy` | `Role.inlinePolicies`, one policy named as the role, built from `source_inline_policy_documents`, `inline_policy_permissions` and `override_inline_policy_documents` the same way |
| `aws_iam_instance_profile` | `create_instance_profile` | `iam/InstanceProfile` `instance-profile`: named as the role, `path`, `roleRef` to the role, `tags` |

**The account in the trust policy.** The submodule reads the account and
partition from the provider for the OIDC providers' ARNs
(`arn:<partition>:iam::<account>:oidc-provider/<url>`). A chart cannot look
them up, so it takes `account_id` and `partition` (default `aws`), which
Bundt fills from the Environment; the render stops, saying so, when the
trust policy needs `account_id` and it is unset (`enable_oidc` without
`oidc_account_id`, `enable_github_oidc`, `enable_bitbucket_oidc`). The
policy JSON is semantically the submodule's, not byte for byte (the
statement blocks' values are lists, keys are sorted, and a condition the
submodule repeats once per provider is written once).

IAM is global: no object takes a region annotation. ACK detaches a role's
policies before deleting it, as the submodule's `force_detach_policies =
true` does.

## Values

Every submodule variable is a value of the same name, type and default. The
chart adds `names` (`role`, which the inline policy and instance profile
share), `namePrefix`, `labels` (Kubernetes only), `account_id`, `partition`
and `deletion_policy`; `tags` is the submodule's own. `name` (or
`names.role`) is required: Terraform would generate one, which would change
between renders.

Accepted in part (`upstream.yaml`):

- `use_name_prefix` (default `true`): the role, its inline policy and its
  instance profile are named `name`, without Terraform's random suffix,
  since a render must not change between plans; `namePrefix` keeps two
  Instances' roles apart. To adopt a role Terraform made, set `names.role`
  to its full name.

## Outputs

All seven: `name`, `arn`, `unique_id` (IAM's RoleId), `instance_profile_arn`,
`instance_profile_id` and `instance_profile_name` (Terraform's id of an
instance profile is its name), `instance_profile_unique_id`.

## Differences from Terraform

- No random name suffix (above).
- Policies attached here belong to the role object: a policy attached by
  something else is detached by ACK. Attaching a policy to a role another
  stack owns is ack-extensions' `RolePolicyAttachment` (`docs/aws.md`,
  section 5).

## Tests

`task test CHART=aws/iam-role`: golden renders (the submodule's three
README examples, every trust source and both document merges at once, the
names convention) validated against iam-controller v1.11.3's CRDs, and the
refusal cases. `tests/mock.values.yaml` is the case the fake-AWS run
applies (`docs/aws.md`, "Charts").
