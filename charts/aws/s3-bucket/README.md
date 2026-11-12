# s3-bucket

An S3 bucket with its configurations, as one AWS Controllers for
Kubernetes (ACK) `Bucket`. A port of terraform-aws-modules'
[`terraform-aws-s3-bucket`](https://github.com/terraform-aws-modules/terraform-aws-s3-bucket/tree/9afa4fc8c8f1e0b3fd913474c1bef8d0c454b235)
at v5.17.0 (`9afa4fc8`), Apache-2.0; modified (a translation of the
module's root variables and logic into a Helm chart). Bundt Package
`aws-s3-bucket` (`package.yaml`). Checked against ACK's s3-controller
v1.15.0 (`UPSTREAM.md`, "ACK controllers").

## Example

The module's README, "Private bucket with versioning enabled":

```yaml
bucket: my-s3-bucket
acl: private
control_object_ownership: true
object_ownership: ObjectWriter
versioning:
  enabled: "true"
```

renders one `s3.services.k8s.aws/v1alpha1` `Bucket` (`hfl.dev/id`
`bucket`) with ownership controls, the public access block (the module's
default), the canned ACL and versioning (`tests/golden/basic.yaml`).

## What it renders

ACK keeps the bucket's configurations inline in `Bucket`, so each module
resource is a field of the one object:

| Module resource | When | `Bucket` field |
| --- | --- | --- |
| `aws_s3_bucket` | `create_bucket` | `name` (`bucket`), `objectLockEnabledForBucket`, `createBucketConfiguration.locationConstraint` (`region`, none for `us-east-1`), `tagging.tagSet` (`tags`) |
| `aws_s3_bucket_ownership_controls` | `control_object_ownership` | `ownershipControls` (`object_ownership`) |
| `aws_s3_bucket_public_access_block` | `attach_public_policy` (default `true`) | `publicAccessBlock` (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`) |
| `aws_s3_bucket_acl` | `acl` (a canned ACL) | `acl` |
| `aws_s3_bucket_versioning` | `versioning` | `versioning.status`, from `enabled` or `status` as the module reads them |
| `aws_s3_bucket_server_side_encryption_configuration` | `server_side_encryption_configuration.rule` | `encryption.rules` |
| `aws_s3_bucket_cors_configuration` | `cors_rule` | `cors.corsRules` |
| `aws_s3_bucket_logging` | `logging` | `logging.loggingEnabled` |
| `aws_s3_bucket_website_configuration` | a `website` attribute set | `website` |
| `aws_s3_bucket_accelerate_configuration` | `acceleration_status` | `accelerate.status` |
| `aws_s3_bucket_request_payment_configuration` | `request_payer` | `requestPayment.payer` |
| `aws_s3_bucket_object_lock_configuration` | `object_lock_enabled` and a default retention | `objectLockConfiguration` |
| `aws_s3_bucket_policy` | `attach_policy`, `attach_require_latest_tls_policy`, `attach_deny_insecure_transport_policy` | `policy`: the module's `denyOutdatedTLS` and `denyInsecureTransport` statements and the statements of `policy`, in the module's order, with `_S3_BUCKET_ID_`, `_S3_BUCKET_ARN_` and `_AWS_ACCOUNT_ID_` replaced |

The bucket's ARN is `arn:<partition>:s3:::<bucket>`. The chart adds
`partition` (default `aws`) and `account_id`, which the module reads from
the provider; `account_id` is needed only when `policy` uses
`_AWS_ACCOUNT_ID_`, and Bundt fills it from the Environment.

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`bucket`), `namePrefix`, `labels` (Kubernetes only),
`account_id`, `partition` and `deletion_policy`; `tags` is the module's
own, and `region` becomes the annotation `services.k8s.aws/region`.

`bucket` is required: the module names an unnamed bucket with a random
suffix, which would change between renders.

Refused (`upstream.yaml`, 51 of 78 variables):

- **Not ported yet** (ACK has the fields): lifecycle rules, replication,
  inventory, analytics, metrics and Intelligent-Tiering configurations, ACL
  grants (`grant`, `owner`), the log-delivery, destination and
  encryption-header policies (`attach_*_log_delivery_policy`,
  `attach_deny_incorrect_*`, ...; write them in `policy` meanwhile), and S3
  Files file systems (`file_system*`).
- **Gaps**: directory buckets (`is_directory_bucket`, `type`, ...),
  metadata configurations, `bucket_prefix` (random suffix),
  `bucket_namespace`, `force_destroy` (ACK cannot empty a bucket),
  `expected_bucket_owner`, `transition_default_minimum_object_size`.
- **In part**: `versioning` (no `mfa`, `mfa_delete`),
  `server_side_encryption_configuration` (no `blocked_encryption_types`),
  `object_lock_configuration` (no `token`), and
  `skip_destroy_public_access_block` (the block is a field of the bucket).

## Outputs

`s3_bucket_id`, `s3_bucket_arn`, `s3_bucket_region`,
`s3_bucket_bucket_domain_name`, `s3_bucket_bucket_regional_domain_name`,
`s3_bucket_policy`, `aws_s3_bucket_versioning_status`,
`s3_bucket_website_endpoint`, built as the Terraform provider builds them.
Not provided: `s3_bucket_hosted_zone_id` and `s3_bucket_website_domain`
(Region tables the provider keeps), `s3_bucket_tags`, and the outputs of
what is refused.

## Differences from Terraform

- **One object.** The configurations are fields of one `Bucket`, so
  another component cannot add a policy statement or a CORS rule without
  taking over the field (`docs/aws.md`, "Inline versus standalone").
- **The policy JSON** is semantically the module's, not byte for byte.
- **Deleting** a bucket that holds objects fails (no `force_destroy`).

## Tests

`task test CHART=aws/s3-bucket`: golden renders validated against
s3-controller v1.15.0's CRDs, and the refusal cases.
`tests/mock.values.yaml` is the case a fake-AWS run will apply
(`docs/aws.md`, "Charts").
