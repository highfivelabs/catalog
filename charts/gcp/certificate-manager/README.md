# certificate-manager

Certificate Manager certificates, DNS authorizations, issuance configs and a
certificate map with its entries, as Config Connector objects. A port of
Cloud Foundation Fabric's
[`modules/certificate-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/certificate-manager)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-certificate-manager` (`package.yaml`). Checked against Config
Connector v1.160.0 and config-connector-extensions at `f3d17dda`.

## Example

```yaml
project_id: my-project
map:
  name: map
  entries:
    mycertentry: {certificates: [mycert], hostname: example.com}
certificates:
  mycert:
    managed: {domains: [example.com]}
```

renders a `CertificateManagerCertificateMap` (`map`), its
`CertificateManagerCertificateMapEntry` (`mycertentry`) and the managed
`CertificateManagerCertificate` (`mycert`) (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.map` | not a fabric variable: the certificate map's name in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart gives (the map's, and each certificate's, DNS authorization's, issuance config's and map entry's key) starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | labels on every object (Kubernetes labels; unprefixed ones and `tags` reach Google Cloud); an issuance config, a config-connector-extensions kind, also carries `tags` and its own labels as `spec.labels` |
| `project_id` | `projectRef` of every object, and the project annotation |
| `certificates` | a `CertificateManagerCertificate` per key: description, labels, location (`global` unless set, as the API defaults it), scope, and a managed certificate's domains, DNS authorizations (by reference to this chart's) and issuance config (by its ID, as fabric: a key `issuance_configs` does not have is dropped, as fabric's `try` drops it). fabric's checks: either `managed` or `self_managed`; DNS authorizations or an issuance config, not both; a scope Certificate Manager knows. `self_managed` is refused (below) |
| `dns_authorizations` | a `CertificateManagerDNSAuthorization` per key: domain, description, location, type. Its `labels` are accepted and not applied, as fabric's module does not apply them |
| `issuance_configs` | a `CertificateManagerCertificateIssuanceConfig` (config-connector-extensions, `certificatemanager.gcp.hfl.dev/v1beta1`; Config Connector's own kind is `v1alpha1`) per key: CA pool, description, key algorithm, labels, lifetime, location (`global` unless set), rotation window |
| `map` | a `CertificateManagerCertificateMap` (name, description, labels) and a `CertificateManagerCertificateMapEntry` per entry (description, labels, hostname or matcher, as fabric checks, and the certificates by reference to this chart's) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

Refused (the render stops, naming the reason):

| Variable | Why |
| --- | --- |
| `certificates.<key>.self_managed` | the private key given here would be in the rendered manifest. `CertificateManagerCertificate` can take it from a Kubernetes Secret (`pemPrivateKey.valueFrom`), which the chart does not take yet: the same open question as `cloudsql-instance`'s `root_password` |

## Outputs

| Output | Value |
| --- | --- |
| `certificate_ids` | each certificate's ID (`projects/<p>/locations/<l>/certificates/<name>`), keyed as fabric keys them |
| `map_id` | the map's ID, or null without a map |

fabric's `certificates`, `dns_authorizations` and `map` outputs are whole
Terraform objects, which a Package does not output (`docs/design.md`,
"Outputs").

## From Terraform

A `module "x" { source = ".../modules/certificate-manager" ... }` block's
arguments become the values unchanged (`examples/certificate-manager/`).
To adopt existing resources, keep their names: Config Connector acquires
the resources of those names (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/certificate-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/certificate-manager)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=certificate-manager`: render cases `basic`, `full`,
`names` and `mock`, each validated against Config Connector v1.160.0's CRD
schemas (and the issuance config against config-connector-extensions'
CRD), and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock MOCK_CHARTS=certificate-manager`, offload run
`off-catalog-1112225005-24178`, 2026-11-12): `tests/mock.values.yaml`'s DNS
authorization, the certificate it authorizes, the map and its entry all
Ready; the outputs evaluated; all four deleted at once and gone.

Live (`hack/live-apply.sh` `LIVE_CHARTS=certificate-manager`, `tests/live.yaml`;
2026-11-14, run `cat-11140046-902f`, offload VM
`off-catalog-1114004144-1090`, as cce-live-tests, config-connector-extensions `c2f0c7d2`): a DNS
authorization, a certificate it authorizes, a map with an entry for it,
and an issuance config on a CA pool of the run. The authorization,
certificate, map, entry and pool were Ready, deleted and gone. The issuance
config (config-connector-extensions'
`CertificateManagerCertificateIssuanceConfig`) was refused: "Error 400:
Config validation failed". The pool has no CA; an enabled CA is the
likely requirement, and a CA cannot be deleted without 30 days pending,
so the live case does not make one.

## Changes

- **0.1.0** (2026-11-12): the port.
