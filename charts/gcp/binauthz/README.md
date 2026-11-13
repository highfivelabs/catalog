# binauthz

A project's Binary Authorization policy, its attestors, the attestors'
notes and IAM on the attestors, as Config Connector objects. A port of
Cloud Foundation Fabric's
[`modules/binauthz`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/binauthz)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-binauthz` (`package.yaml`). Checked against Config Connector v1.160.0
and config-connector-extensions' `IAMBinding` (`iam.gcp.hfl.dev/v1beta1`).

## Example

```yaml
project_id: my-project
default_admission_rule:
  evaluation_mode: ALWAYS_DENY
  enforcement_mode: ENFORCED_BLOCK_AND_AUDIT_LOG
  attestors: null
cluster_admission_rules:
  europe-west1-c.cluster:
    evaluation_mode: REQUIRE_ATTESTATION
    enforcement_mode: ENFORCED_BLOCK_AND_AUDIT_LOG
    attestors: [test]
attestors_config:
  test:
    note_reference: null
    pgp_public_keys: ["mQENBFtP0doBCADF..."]
    pkix_public_keys: null
    iam:
      roles/viewer: ["user:user1@example.com"]
```

renders the `BinaryAuthorizationPolicy`, the `BinaryAuthorizationAttestor`
`test`, its `ContainerAnalysisNote` `test-note` and an `IAMBinding` of
`roles/viewer` on the attestor (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults. The
chart carries all five.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: the chart names no singular resource (attestors are named by their keys), so it takes no key |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every attestor and note name starts with `<namePrefix>-`; empty changes nothing |
| `labels` | Kubernetes labels on every object; none of these resources takes Google Cloud labels |
| `tags` | the same: they stay in Kubernetes |
| `project_id` | every object's project annotation, and the policy's and attestors' `projectRef` |
| `admission_whitelist_patterns` | the policy's `admissionWhitelistPatterns`, each pattern once, sorted (fabric's `toset`) |
| `default_admission_rule` | the policy's `defaultAdmissionRule`; `attestors` become `requireAttestationsBy`, references to this chart's attestors. A name that is not a key of `attestors_config` stops the render, as fabric's lookup fails |
| `cluster_admission_rules` | the policy's `clusterAdmissionRules`, keyed by `<location>.<cluster ID>`, the attestors as above |
| `attestors_config` | one `BinaryAuthorizationAttestor` per key, named by the key. `note_reference` null makes a `ContainerAnalysisNote` `<key>-note` (fabric's hint, `Attestor <key> note`) and refers to it; otherwise `noteRef.external` takes the note's ID. `pgp_public_keys` and `pkix_public_keys` are `publicKeys`, PGP first, PKIX in fabric's order (by `<pem>-<algorithm>`). `iam` is one `IAMBinding` per role on the attestor (config-connector-extensions, `v1beta1`): exact, as fabric's `google_binary_authorization_attestor_iam_binding` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the policy, attestors and notes (not the IAM bindings) |

`evaluation_mode` and `enforcement_mode` are checked against the values the
API takes (`ALWAYS_ALLOW`, `ALWAYS_DENY`, `REQUIRE_ATTESTATION`;
`ENFORCED_BLOCK_AND_AUDIT_LOG`, `DRYRUN_AUDIT_LOG_ONLY`), which Terraform's
provider checks too.

Nothing is refused. Name lengths: with a `namePrefix`, an attestor or note
name longer than 63 characters stops the render. The API documents no
limit for either; 63 is an assumption, the length the catalog uses for
names that have none documented.

## Outputs

| Output | From |
| --- | --- |
| `id` | `projects/<project>`, the policy's Terraform ID, from the inputs |
| `attestors` | `{<key>: projects/<project>/attestors/<name>}`, from the inputs. fabric's output is a map of whole attestor objects; a Package outputs the field a consumer takes (`docs/design.md`, "Outputs") |
| `notes` | `{<key>: projects/<project>/notes/<name>}` for the notes the chart makes, from the inputs; fabric's is a map of whole note objects |

## From Terraform

A `module "x" { source = ".../modules/binauthz" ... }` block's arguments
become the values unchanged (`examples/binauthz/`). A project has one
policy, so adopting the module adopts the project's policy as it is; give
attestors and notes their existing names to adopt them (`docs/design.md`,
"From Terraform"). The attestors' IAM is `IAMBinding`, exact per role as
fabric's is: members added out of band to a role the chart manages are
removed.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/binauthz`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/binauthz)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=binauthz`: render cases `basic` (fabric's README
example), `defaults`, `full` (every field the chart carries) and `names`, each validated against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' `IAMBinding` CRD, and the refusals in
`tests/*.fail.yaml`.

No fake-cloud case: the fake cloud has no Binary Authorization API. A
trial on 2026-11-12 (offload VM `off-catalog-1112225432-16822`,
config-connector-extensions `11baa460`) applied a policy requiring one
attestor, the attestor with a PKIX key, its note and an `IAMBinding` on
it: the note and the `IAMBinding` became Ready (mockgcp serves any IAM
policy path) and the outputs evaluated, but mockgcp answered
`binaryauthorization.googleapis.com` with "host name not known", so the
attestor and the policy (waiting on it) never became Ready. All four were
deleted.

Not applied live: the Binary Authorization and Container Analysis APIs are
not enabled in the live-test project, and no live-test service account has
their roles.

## Changes

- **0.1.0** (2026-11-12): the port: the policy, attestors, notes and the
  attestors' IAM.
