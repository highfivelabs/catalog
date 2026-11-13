# ssm-parameter

An SSM Parameter Store parameter, as an AWS Controllers for Kubernetes
(ACK) object. A port of terraform-aws-modules'
[`terraform-aws-ssm-parameter`](https://github.com/terraform-aws-modules/terraform-aws-ssm-parameter/tree/c798b114a38a36d278e2ba74550bf52f9b944563)
at v2.1.2 (`c798b114`), Apache-2.0; modified (a translation of the
module's variables into a Helm chart). Bundt Package `aws-ssm-parameter`
(`package.yaml`). Checked against ACK's ssm-controller v1.8.0
(`UPSTREAM.md`, "ACK controllers").

## Example

```yaml
name: /app/config/endpoint
value: https://api.example.com
description: The endpoint
tags: {Environment: dev}
```

renders one `ssm.services.k8s.aws/v1alpha1` `Parameter` (`hfl.dev/id`
`parameter`) of type `String` (`tests/golden/basic.yaml`).

## What it renders

| Module resource | ACK |
| --- | --- |
| `aws_ssm_parameter.this` | `Parameter`: `name`, `type`, `value`, `allowedPattern`, `dataType`, `description`, `keyID` (a SecureString's), `tier`, `tags` |

The type and value are derived as the module's locals derive them: `type`
when set, else `StringList` when `values` is set, else `SecureString` when
`secure_type`, else `String`; a StringList's value is
`jsonencode(values)` when `values` is set.

A SecureString's value is in the `Parameter`'s spec, which is how ACK
takes it: whoever can read the object can read the value. Terraform keeps
it out of state with a write-only argument; on ACK, keep such a value in a
Secret-backed tool, or limit who reads the namespace.

`region` becomes the annotation `services.k8s.aws/region`.

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`parameter`), `namePrefix` (after the leading `/` of a
hierarchical name: `/app/x` becomes `/<namePrefix>-app/x`), `labels`
(Kubernetes only) and `deletion_policy` (`ABANDON` renders
`services.k8s.aws/deletion-policy: retain`); `tags` is the module's own.
`name` (or `names.parameter`) and `value` (or `values`) are required.
`value_wo_version` is accepted and has no effect: ACK has no write-only
values, and applies a changed value whenever the spec changes.

Refused (`upstream.yaml`):

- `ignore_value_changes`: ACK's controller sets the value in the spec on
  every sync; nothing leaves it alone once created.
- `overwrite`: ACK's `Parameter` has no overwrite field: the controller
  creates the parameter (failing if one of that name exists) and then owns
  it.

## Outputs

`raw_value`, `insecure_value` (a String's or StringList's), `secure_value`
(a SecureString's), `secure_type`, `ssm_parameter_arn`,
`ssm_parameter_version`, `ssm_parameter_name`, `ssm_parameter_type`. Not
provided: `value`, the module's `jsondecode` of the raw value (outputs
cannot decode JSON).

## Tests

`task test CHART=aws/ssm-parameter`: golden renders validated against
ssm-controller v1.8.0's CRDs, and the refusal cases.
`tests/mock.values.yaml` is the case the fake-AWS run applies
(`docs/aws.md`, "Charts").
