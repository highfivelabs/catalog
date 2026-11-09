# Upstream

The catalog ports Terraform modules from Cloud Foundation Fabric to Helm
charts of Config Connector objects. Two upstreams are pinned here;
`hack/kcc.sh` reads the Config Connector rows, and every chart names the
fabric commit it was ported from in its `Chart.yaml` (`sources` and the
`hfl.dev/source-*` annotations) and in its README.

| | |
| --- | --- |
| Fabric repository | `github.com/GoogleCloudPlatform/cloud-foundation-fabric` |
| Fabric release | `v60.0.0` (2026-11-05) |
| Fabric commit | `f706bc3b6166787df01402f73a96f1de57097477` |
| Fabric licence | Apache-2.0 (`LICENSE` in that repository) |
| Config Connector repository | `github.com/GoogleCloudPlatform/k8s-config-connector` |
| Config Connector release | `v1.160.0` (2026-10-29) |
| Config Connector commit | `c38b031c7f5e5657b6ac6afc18da95e039066ad8` |
| Gap kinds | `config-connector-extensions` (groups `*.gcp.hfl.dev`), none used by the pilot charts |
| Read on | 2026-11-09 |

## Every module the catalog tracks

`upstream/modules.yaml` is the one list of the open-source Terraform modules
the catalog tracks, ported or not: all 91 Cloud Foundation Fabric modules at
`v60.0.0`, the 40 most-downloaded terraform-aws-modules and the 37
most-downloaded Azure Verified Modules (`docs/aws.md` and `docs/azure.md`,
"Ranking"). Each entry names the upstream repository and the module's
directory in it, the tag pattern that marks a release, the pinned release
and the commit it points at, the licence and copyright holder, the module's
page at that tag, its Terraform Registry page (fabric is not published
there), and the chart that ports it or `null`.

Each chart also records its own provenance in `charts/<cloud>/<chart>/upstream.yaml`:
the same repository, path, release, commit and licence, the module's page,
and the date last synced. `task upstream-check` fails when the two disagree,
or when a chart's `Chart.yaml` annotations name another release.

| Source | Licence | Notice |
| --- | --- | --- |
| Cloud Foundation Fabric | Apache-2.0 | Copyright Google LLC |
| terraform-aws-modules | Apache-2.0 | no copyright line in the modules' `LICENSE` files, except `eventbridge` (Sven Lito); no `NOTICE` files |
| Azure Verified Modules | MIT | Copyright (c) Microsoft Corporation |

Only fabric is ported so far; `NOTICE` says what a chart ported from the
other two must carry.

## What is ported, from where

| Chart | Fabric module | Ported | Left out (refused when set) |
| --- | --- | --- | --- |
| `charts/gcp/iam-service-account` | `modules/iam-service-account` | the account; IAM on it (authoritative and additive); roles granted to it on billing accounts, folders, organizations, projects, service accounts and buckets | `service_account_reuse`, `create_ignore_already_exists`, `tag_bindings`, `context` |
| `charts/gcp/gcs` | `modules/gcs` | the bucket and every field Config Connector has; IAM; the notification, its topic and the topic's publisher binding; tag bindings; IAM on an existing bucket (`bucket_create: false`) | `enable_object_retention`, `enable_hierarchical_namespace`, `rpo`, `objects_to_upload`, `managed_folders`, `kms_autokeys`, `context` |
| `charts/gcp/net-vpc` | `modules/net-vpc` | see the chart's README | see the chart's README |
| `charts/gcp/project` | `modules/project` | see the chart's README | see the chart's README |

## Moving the pins

A new fabric release is a new port, not a merge: diff the module between
the two commits (`git diff <old>..<new> -- modules/<module>`), carry each
change into the chart, bump the chart's version (docs/design.md,
"Versioning"), and update the rows above, the chart's annotations, the
chart's `upstream.yaml` and the module's entry in `upstream/modules.yaml`
(`task upstream-check` fails until all of them agree). A
new Config Connector release: update the rows above, run `task test`
(it re-fetches the CRDs and re-validates every render), and re-read the
gaps in `docs/gcp-inventory.md`: a gap that the release closes becomes a
value the chart now supports.
