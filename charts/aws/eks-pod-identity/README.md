# eks-pod-identity

An IAM role for EKS Pod Identity with its policies and its pod identity
associations, as AWS Controllers for Kubernetes (ACK) objects. A port of
terraform-aws-modules'
[`terraform-aws-eks-pod-identity`](https://github.com/terraform-aws-modules/terraform-aws-eks-pod-identity/tree/f72040b99272c264e0340f44758219e0808a52a2)
at v2.10.0 (`f72040b9`), Apache-2.0; modified (a translation of the
module's variables into a Helm chart). Bundt Package `aws-eks-pod-identity`
(`package.yaml`). Checked against ACK's iam-controller v1.11.3 and
eks-controller v1.26.0 (`UPSTREAM.md`, "ACK controllers").

## Example

The module's README "custom" usage (`tests/basic.values.yaml`):

```yaml
name: custom
attach_custom_policy: true
policy_statements:
  - sid: S3ReadOnly
    actions: ["s3:GetObject", "s3:ListBucket"]
    resources: ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
associations:
  this: {cluster_name: example, namespace: default, service_account: example-sa}
```

renders the `Role` (`hfl.dev/id` `role`), its custom `Policy` (`policy`,
attached by reference) and a `PodIdentityAssociation`
(`association-this`, `roleRef` to the role).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_iam_role` | `create` | `iam/Role` `role`: named `name`, trusting `pods.eks.amazonaws.com` (`sts:AssumeRole`, `sts:TagSession`) with `trust_policy_conditions`, then `trust_policy_statements`; `path`, `description`, `maxSessionDuration`, `permissionsBoundary`, `tags` |
| `aws_iam_role_policy_attachment` (`additional_policy_arns`) | given | the role's `policies` (ARNs) |
| `aws_iam_policy`, `aws_iam_role_policy_attachment` (custom) | `attach_custom_policy` | `iam/Policy` `policy`, named as the role: `source_policy_documents`, `policy_statements` and `override_policy_documents` merged by Sid as `aws_iam_policy_document` merges them, `description` (`custom_policy_description`), `path`; in the role's `policyRefs`, or with `additional_policy_arns` beside it, by an ARN built from `account_id` (ACK's `Role` takes ARNs or references, not both) |
| `aws_eks_pod_identity_association` | one per `associations` entry | `eks/PodIdentityAssociation` `association-<key>`: `clusterName`, `namespace`, `serviceAccount`, `targetRoleARN`, `disableSessionTags` (each from the entry, else `association_defaults`), `roleRef` to the role, `tags` (`tags`, the entry's, the defaults', merged in the module's order) |

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`role`), `namePrefix`, `labels` (Kubernetes only),
`account_id` and `partition`, and `deletion_policy`; `tags` is the
module's own, and `region` becomes the annotation `services.k8s.aws/region`
on the associations.

Refused or accepted in part (`upstream.yaml`):

- The module's preset policies, 63 variables: `policy_name_prefix` and
  every `attach_*_policy` preset (EBS CSI, load balancer controller,
  external-dns, Karpenter's neighbours, ...) with its name and ARN
  variables. Not ported yet: `iam/Policy` is stable, so this is chart work
  (each preset is an `aws_iam_policy_document` to carry as data). Until
  then, pass a preset's document in `source_policy_documents` with
  `attach_custom_policy`, or its ARN in `additional_policy_arns`.
- `use_name_prefix`, in part: the role and the custom policy are named
  `name`, without Terraform's random suffix; `namePrefix` keeps two
  Instances' roles apart.

## Outputs

`iam_role_arn`, `iam_role_name`, `iam_role_path`, `iam_role_unique_id`,
`iam_policy_arn`, `iam_policy_name` and `iam_policy_id` (the custom
policy's; a policy's Terraform id is its ARN). Not provided:
`associations` (whole Terraform objects).

## Tests

`task test CHART=aws/eks-pod-identity` renders every `tests/*.values.yaml`
against its golden file and the pinned controllers' CRDs, and checks each
`tests/*.fail.yaml` is refused with its message. `tests/mock.values.yaml`
is the fake-AWS case (`task test-mock-aws`): the role and its policies; an
association needs an EKS cluster, which that layer does not make.
