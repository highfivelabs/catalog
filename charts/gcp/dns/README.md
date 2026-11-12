# dns

A Cloud DNS managed zone (public, private, forwarding or peering) with its
record sets and IAM, as Config Connector objects. A port of Cloud
Foundation Fabric's
[`modules/dns`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/dns)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-dns` (`package.yaml`). Checked against Config Connector v1.160.0.

## Example

```yaml
project_id: my-project
name: test-example
zone_config:
  domain: test.example.
  private:
    client_networks: [projects/my-project/global/networks/default]
recordsets:
  "A localhost": {records: [127.0.0.1]}
  "A myhost": {ttl: 600, records: [10.0.0.120]}
```

renders the `DNSManagedZone` `test-example` and two `DNSRecordSet`s,
`localhost.test.example.` and `myhost.test.example.`
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.zone` | not a fabric variable: the zone name in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter); unset, the name is `name` (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived zone name starts with `<namePrefix>-`; empty changes nothing. Record names are DNS names and take no prefix |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (fabric's `labels`, on the zone, are these) |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `project_id`, `name`, `description` | the zone's project annotation, `resourceID` and `description` |
| `zone_config` | the `DNSManagedZone`: `dnsName`, `visibility` (`private` for forwarding, peering and private zones), `reverseLookup`, `dnssecConfig` (fabric's key defaults), `forwardingConfig`, `peeringConfig`, `privateVisibilityConfig` (the client networks of whichever type), `serviceDirectoryConfig`, `cloudLoggingConfig` (logging off unless a public zone turns it on); only one type, as fabric checks |
| `zone_config: null` | no zone: record sets and IAM go on the existing zone `name` (named as above) |
| `force_destroy` | the `cnrm.cloud.google.com/force-destroy` annotation |
| `recordsets` | one `DNSRecordSet` per `"<type> <name>"` key: `name` as fabric resolves it (absolute when it ends in `.`, the zone's domain when empty, else `<name>.<domain>`), `ttl` (300), `rrdatas`; `geo_routing` and `wrr_routing` as `routingPolicy.geo` and `.wrr`, their records as `rrdatasRefs` external values and health-checked internal load balancers by reference; fabric's two validations |
| `iam` | one `IAMPartialPolicy` on the zone |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the zone and records |

Refused when set:

| Variable | Why |
| --- | --- |
| a relative record name with `zone_config: null` | fabric reads the existing zone's domain with a data source; a chart renders from its inputs alone, so give the name in full, ending in `.` |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the zone name, from the inputs |
| `id` | `projects/<project>/managedZones/<name>`, from the inputs |
| `domain` | `zone_config.domain`; null for an existing zone |
| `name_servers` | the zone's `status.nameServers`; null for an existing zone |

These are fabric's declared outputs, selected (`docs/design.md`,
"Outputs"). Not outputs: `zone` (a whole Terraform object) and `dns_keys`
(fabric reads them with a data source; Config Connector has no kind that
reads a zone's DNSKEY records).

## Differences from the module

- `iam` is an `IAMPartialPolicy`, which keeps the listed members but does
  not remove others (`docs/design.md`, "IAM").
- fabric's `labels` go on the zone; here the chart's `labels` go on every
  object, and Config Connector copies the unprefixed ones to the zone.

## From Terraform

A `module "x" { source = ".../modules/dns" ... }` block's arguments become
the values unchanged (`examples/dns/`). To adopt an existing zone and
records, keep their names: Config Connector acquires the zone of that name
and the record sets of those names and types (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/dns`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dns)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=dns`: render cases `basic`, `public` (DNSSEC, logging,
apex and absolute records), `forwarding`, `peering`, `routing` (geo and
weighted records, reverse lookup, Service Directory), `existing`
(`zone_config: null`), `names` and `mock`, each validated against Config
Connector v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml`.
`tests/mock.values.yaml` is for the fake cloud (`task test-mock`).

## Changes

- **0.1.0** (2026-11-12): the port: every zone type, record sets with
  routing policies, IAM.
