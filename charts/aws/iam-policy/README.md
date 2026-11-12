# iam-policy

An IAM managed policy, as an AWS Controllers for Kubernetes (ACK) object. A
port of terraform-aws-modules'
[`terraform-aws-iam`](https://github.com/terraform-aws-modules/terraform-aws-iam/tree/55514b7873c411040395e024a422684998da77c2/modules/iam-policy)
`iam-policy` submodule at v6.8.2 (`55514b78`), Apache-2.0; modified (a
translation of the submodule's variables into a Helm chart). Bundt Package
`aws-iam-policy` (`package.yaml`). Checked against ACK's iam-controller
v1.11.3 (`UPSTREAM.md`, "ACK controllers").

## Example

The submodule's README example, with `name` in place of `name_prefix`:

```yaml
name: example
path: /
description: My example policy
policy: '{"Version":"2012-10-17","Statement":[{"Action":["ec2:Describe*"],"Effect":"Allow","Resource":"*"}]}'
tags: {Environment: test}
```

renders one `iam.services.k8s.aws/v1alpha1` `Policy` (`hfl.dev/id`
`policy`) (`tests/golden/basic.yaml`).

## What it renders

| Module resource | ACK |
| --- | --- |
| `aws_iam_policy` | `Policy`: `name`, `path`, `description`, `policyDocument` (`policy`), `tags` |

IAM is global: the policy takes no region annotation.

## Values

Every submodule variable is a value of the same name, type and default.
The chart adds `names` (`policy`), `namePrefix`, `labels` (Kubernetes only)
and `deletion_policy` (`ABANDON` renders
`services.k8s.aws/deletion-policy: retain`); `tags` is the submodule's own.
`name` (or `names.policy`) and `policy` are required: Terraform would
generate a name, which would change between renders, and AWS refuses an
empty document.

Refused (`upstream.yaml`):

- `name_prefix`: Terraform's random suffix would change between renders.
  Set `name`; `namePrefix` keeps two Instances' policies apart.

## Outputs

All four: `id` and `arn` (Terraform's id of a policy is its ARN), `name`,
`policy`.

## Tests

`task test CHART=aws/iam-policy`: golden renders validated against
iam-controller v1.11.3's CRDs, and the refusal cases.
`tests/mock.values.yaml` is the case the fake-AWS run applies
(`docs/aws.md`, "Charts").
