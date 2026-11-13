# cloud-identity-group

A Cloud Identity group with its managers and members, as Config Connector
objects. A port of Cloud Foundation Fabric's
[`modules/cloud-identity-group`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/cloud-identity-group)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-cloud-identity-group` (`package.yaml`). Checked against Config
Connector v1.160.0.

**Organization level.** A group belongs to a Cloud Identity or Google
Workspace customer (`customer_id`), not to a project. Config Connector's
service account must be a groups administrator of that customer, so the
chart runs only in a platform namespace whose account has that role, in an
Environment the platform team owns (`docs/design.md`, "Organization,
folders and Config Connector's scope").

## Example

```yaml
customer_id: customers/C01234567
name: mygroup@example.com
display_name: My group name
managers: [user1@example.com]
members: [user2@example.com, user3@example.com]
```

renders a `CloudIdentityGroup` and three `CloudIdentityMembership`s
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.group` | not a fabric variable: the group's key (its email address) in full, in place of `name` (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: accepted, as in every chart, and unused: the group's name is an email address, given in full, and Cloud Identity names the group and its memberships |
| `labels`, `tags` | Kubernetes labels on every object; Cloud Identity's labels are fixed group types, not free labels, so these stay in Kubernetes |
| `customer_id` | the group's `parent` (fabric's check: `customers/C0` and seven characters) |
| `name` | the group's `groupKey.id` |
| `display_name`, `description` | `displayName`, `description` |
| `managers` | a `CloudIdentityMembership` each, roles `MEMBER` and `MANAGER` |
| `members` | a `CloudIdentityMembership` each, role `MEMBER` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the group and its memberships |

As fabric, every group carries the label
`cloudidentity.googleapis.com/groups.discussion_forum` and is created
`EMPTY`. Nothing is refused.

## Outputs

| Output | Value |
| --- | --- |
| `id` | the group's resource name, `groups/<id>`, which Cloud Identity assigns: the group's `status.name` |
| `name` | the group's key, from the inputs (`names.group`, else `name`) |

## From Terraform

A `module "x" { source = ".../modules/cloud-identity-group" ... }` block's
arguments become the values unchanged (`examples/cloud-identity-group/`).
To adopt an existing group, set `deletion_policy: ABANDON` for the first
apply (`docs/design.md`, "From Terraform"); Config Connector finds a group
by its resource name, so an existing group's `groups/<id>` would have to be
given, which the chart does not take yet: a chart applied to a key that
exists fails rather than taking the group over.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/cloud-identity-group`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-identity-group)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=cloud-identity-group`: render cases `basic`, `names` and
`mock`, each validated against Config Connector v1.160.0's CRD schemas, and
the refusals in `tests/*.fail.yaml`.

Fake cloud, `task test-mock MOCK_CHARTS=cloud-identity-group`, 2026-11-12,
with a group, a manager and a member: all three Ready; the group deleted;
the two memberships never deleted. Deleted together, as Bundt prunes a
component, the group goes first, and Config Connector's membership
controller then resolves `groupRef` before deleting and stops with
"reference CloudIdentityGroup ... is not found", so the memberships keep
their finalizer (a Config Connector bug: the membership went with its
group). Until it is fixed, delete a group's memberships before the group:
remove `managers` and `members` and apply, then delete the component.
`tests/mock.values.yaml` holds the group alone, which passes. Not applied
live:
the test estate has no Cloud Identity customer the live-test service
accounts administer.

## Changes

- **0.1.0** (2026-11-12): the port.
