# dns-response-policy

A Cloud DNS response policy bound to VPC networks and GKE clusters, and its
rules (answer a name with local data, or let it through), as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/dns-response-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/dns-response-policy)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-dns-response-policy` (`package.yaml`). Checked against
config-connector-extensions' `DNSResponsePolicy` and
`DNSResponsePolicyRule` (`dns.gcp.hfl.dev/v1beta1`), at `0ee17dd`; Config
Connector v1.160.0 has both only as `v1alpha1`.

## Example

```yaml
project_id: my-project
name: googleapis
networks:
  landing: projects/my-project/global/networks/landing
rules:
  pubsub:
    dns_name: pubsub.googleapis.com.
    local_data:
      A:
        rrdatas: [199.36.153.4, 199.36.153.5]
```

renders the `DNSResponsePolicy` `googleapis` bound to the network, and a
`DNSResponsePolicyRule` `pubsub` in it that answers
`pubsub.googleapis.com.` with the two addresses (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.policy` sets the policy's name in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the policy's name (unless set under `names`) and every rule's name start with `<namePrefix>-`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the policy |
| `tags` | not a fabric variable: cloud labels on the policy |
| `project_id` | every object's project annotation and `projectRef` |
| `name` | the policy's name (`resourceID`), with the `namePrefix` |
| `description` | the policy's `description` (`Terraform managed.` by default) |
| `networks` | the policy's `networks`, one `networkUrl` per entry, in key order; a self link or a `projects/...` path (the controller makes it a full URL) |
| `clusters` | the policy's `gkeClusters`, one `gkeClusterName` per entry |
| `policy_create` | `false`: no `DNSResponsePolicy`; the rules go into the existing policy of that name |
| `rules` | one `DNSResponsePolicyRule` per key, its name the key (with the `namePrefix`), in `projects/<project>/responsePolicies/<policy>`: `dnsName`, and either `localData` (one record per type, named the rule's DNS name, as fabric names it, with `ttl` when set and `rrdatas`) or, with no local data, `behavior` (`bypassResponsePolicy` by default) |
| `factories_config` | accepted and ignored: a chart cannot read files. The YAML file `factories_config.rules` names goes under `factories_data.rules`, exactly its content (a map of rules in the `rules` format); a rule of `rules` wins over the file's of the same name, as fabric's `merge` does |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups (`$addresses:`, `$dns_names:`, `$networks:`, `$project_ids:`) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the policy and its rules |

Checks: a local data record type outside fabric's list (`A`, `AAAA`, ...
`TXT`) is refused, as fabric's validation refuses it, here for the
factory's rules too. With a `namePrefix`, a policy or rule name over 63
characters stops the render; a name set under `names` is always checked.
63 is an assumption, the length the catalog uses where the API documents
none.

## Outputs

| Output | From |
| --- | --- |
| `id` | `projects/<project>/responsePolicies/<name>`, Terraform's ID, from the rendered policy; null with `policy_create: false`, as fabric's |
| `name` | computed from the values as the chart names the policy (`names.policy`, else `name` with the `namePrefix`), so it is known before the policy exists, and names the existing policy with `policy_create: false` |

Not an output: fabric's `policy`, the whole resource (`docs/design.md`,
"Outputs").

## Differences from the module

- **`$context` lookups** are refused (above): a rule's `dns_name`,
  `rrdatas` and the networks are written as values, or Bundt expressions.
- **Rule names take the `namePrefix`** when it is set, as other repeated
  sub-resources do, so two Instances writing rules into one existing
  policy cannot collide; fabric names rules by their keys, which an empty
  `namePrefix` keeps.
- **Rules wait for the policy.** A rule names its policy by path, not by
  a Kubernetes reference; until the chart's policy exists the rule's
  create is refused (404) and retried.

## From Terraform

A `module "x" { source = ".../modules/dns-response-policy" ... }` block's
arguments become the values unchanged, apart from `context` (refused) and
the factory's file (`factories_data.rules`). The policy and the rules keep
their names, so they adopt what Terraform made (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/dns-response-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dns-response-policy)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=dns-response-policy`: render cases `basic`, `existing`
and `factory` (fabric's three README examples, the last with the rules
file as data), `full` (every variable), `names` and `mock`, each validated
against the CRDs in `crds/config-connector-extensions`, and the refusals
in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a policy bound to
one network, a local data rule and a bypass rule. On 2026-11-13 (offload
VM `off-catalog-1113025821-15164`; config-connector-extensions `0ee17dd`)
all three objects became Ready, the outputs evaluated (`id`
`projects/mock-project/responsePolicies/catalog-mock-rp`, `name`
`catalog-mock-rp`) and all three were deleted. mockgcp does not check
that a bound network exists, nor what the real API refuses in a rule
(both or neither of `behavior` and `localData`; `SOA` and `NS` records).

Live (`hack/live-apply.sh` `LIVE_CHARTS=dns-response-policy`, `tests/live.yaml`;
2026-11-13, run `cat-11132355-cc50`, offload VM
`off-catalog-1113235106-1058`, as cce-live-tests, config-connector-extensions `c2f0c7d2`): a policy bound
to a network of the run, a local data rule and a bypass rule. Passed: the
policy and both rules Ready, deleted and gone from Google Cloud, with the
network.

## Changes

- **0.1.0** (2026-11-12): the port: the policy, its rules from the
  variable and the factory.
