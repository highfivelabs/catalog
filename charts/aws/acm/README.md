# acm

An ACM certificate, or its Route 53 DNS validation records, as AWS
Controllers for Kubernetes (ACK) objects. A port of terraform-aws-modules'
[`terraform-aws-acm`](https://github.com/terraform-aws-modules/terraform-aws-acm/tree/aae84c011dd68ace1beb5d10e1feddfe9a334953)
at v6.3.1 (`aae84c01`), Apache-2.0; modified (a translation of the module's
variables and logic into a Helm chart). Bundt Package `aws-acm`
(`package.yaml`). Checked against ACK's acm-controller v1.11.0 and
route53-controller v1.8.0 (`UPSTREAM.md`, "ACK controllers").

## Example

DNS validation with Route 53 is two components, as in the module's README
example "Usage with Route53 DNS validation and separate AWS providers". The
certificate:

```yaml
domain_name: my-domain.com
subject_alternative_names: ["*.my-domain.com", "app.sub.my-domain.com"]
validation_method: DNS
create_route53_records: false
```

renders one `acm.services.k8s.aws/v1alpha1` `Certificate` (`hfl.dev/id`
`certificate`, `tests/golden/separate-acm.yaml`). Its records, a second
component whose `acm_certificate_domain_validation_options` and
`distinct_domain_names` take the first's outputs of the same names
(`valueFrom`):

```yaml
create_certificate: false
create_route53_records_only: true
validation_method: DNS
zone_id: Z266PL4W4W6MSG
distinct_domain_names: <the certificate's distinct_domain_names>
acm_certificate_domain_validation_options: <the certificate's acm_certificate_domain_validation_options>
```

renders a `route53.services.k8s.aws/v1alpha1` `RecordSet` per distinct
domain (`validation-record-<i>`, `tests/golden/separate-records.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_acm_certificate` | `create_certificate` | `acm/Certificate` `certificate`: `domainName`, `subjectAlternativeNames`, `domainValidationOptions` (`validation_option`), `keyAlgorithm`, `certificateAuthorityARN` (`private_authority_arn`), `options` (`certificateTransparencyLoggingPreference`, `export`), `tags` |
| `aws_route53_record.validation` | `create_route53_records_only`, DNS validation | `route53/RecordSet` `validation-record-<i>` for each of `distinct_domain_names` (or the domain and SANs without `*.`): the zone from `zones` (by domain) or `zone_id`, the record's name, type and value from `acm_certificate_domain_validation_options`, `ttl` (`dns_ttl`) |
| `aws_acm_certificate_validation` | | no kind: nothing waits for `ISSUED` (below) |

**Why two components.** ACK requests every certificate with DNS
validation, and the records to create are in the `Certificate`'s status
(`domainValidations[].resourceRecord`), known only once ACK has requested
it. One render cannot write them, so a certificate with DNS validation and
`create_route53_records: true` (the default) is refused with a message that
says what to do. The module's own records-only mode takes the records from
values, which a second component gets from the first's outputs
(`docs/aws.md`, section 6).

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (no keys: no name can collide), `namePrefix` (changes
nothing), `labels` (Kubernetes only) and `deletion_policy`; `tags` is the
module's own, and `region` becomes the annotation `services.k8s.aws/region`
on the certificate.

Refused or accepted in part (`upstream.yaml`):

- `validation_method`, in part: `DNS` or unset; `EMAIL` is refused (ACK
  always requests DNS validation).
- `create_route53_records` and `validate_certificate`, in part: both `true`
  with DNS validation on a certificate this component requests is refused
  (above).
- `wait_for_validation` and `validation_record_fqdns`, in part: accepted,
  but nothing waits for the certificate to be `ISSUED`. ACK's `Certificate`
  is synced, so the component is Ready, once requested
  (`PENDING_VALIDATION`); the `acm_certificate_status` output reports
  `ISSUED`.
- `validation_allow_overwrite_records`, in part: ACK creates a record with
  Route 53's `CREATE` action, which fails on a record already there.
- `validation_timeout`: Terraform's wait (by design).

## Outputs

All seven. `acm_certificate_domain_validation_options` and
`validation_domains` have Terraform's shape (`domain_name`,
`resource_record_name`, `resource_record_type`, `resource_record_value`);
`acm_certificate_validation_emails` is always empty (DNS validation only);
`validation_route53_record_fqdns` are the records' names, lower case,
without the trailing dot.

## Differences from Terraform

- DNS validation with Route 53 records is two components (above).
- The component is Ready before the certificate is `ISSUED`.

## Tests

`task test CHART=aws/acm`: golden renders (the module's README examples,
both halves of the two-component example, every certificate option)
validated against acm-controller v1.11.0's and route53-controller v1.8.0's
CRDs, and the refusal cases. `tests/mock.values.yaml` is the case the
fake-AWS run applies (`docs/aws.md`, "Charts").
