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

**Finding what moved.** `task upstream-watch` reads `upstream/modules.yaml`,
finds each module's latest release (`git ls-remote --tags`), and for every
module that moved fetches the module's Terraform at both tags and diffs it:
variables, outputs and resource types added, removed or changed, and which
`.tf` files differ at all. It writes `docs/upstream-status.md` and
`docs/upstream-status.json`. It only reads; it never writes to, comments on
or opens anything in an upstream repository. The scheduled workflow
(`.github/workflows/upstream-watch.yml`, daily) runs it and keeps one issue,
"Upstream releases to take", in this repository.

**Taking a release** is a short, reviewed pull request, a port and not a
merge:

1. Read the issue's entry for the module (the diff, the compare link, the
   release notes) and `git diff <old>..<new> -- <path>` in the upstream
   repository.
2. Carry each change into the chart: new variables into `values.yaml` and
   `values.schema.json`, changed defaults, new resources into the templates.
   A variable the chart cannot carry goes under `refused` in its
   `upstream.yaml`, with its kind and reason. Bump the chart's version
   (`Chart.yaml`, `package.yaml`; docs/design.md, "Versioning"), add render
   cases, run `task test`.
3. `task upstream-bump -- gcs v61.0.0` moves the pin: the module's entry in
   `upstream/modules.yaml`, the chart's `upstream.yaml` (and its date
   synced) and `Chart.yaml`'s `hfl.dev/source-*` annotations, `appVersion`
   and source URL; it then regenerates `docs/coverage`. For a module with no
   chart it only moves the pin and the coverage numbers. It does not port
   anything.
4. `task upstream-check` and `task test` agree with the new pin; commit
   everything, open the pull request. The fabric rows at the top of this page
   and `docs/gcp-inventory.md` describe the release the inventory was made
   at (`task inventory` rereads the "Fabric release" row); move them when
   the inventory is regenerated for a new release, not with a single
   module.

A new Config Connector release: update the rows at the top of this page, run
`task test` (it re-fetches the CRDs and re-validates every render), and
re-read the gaps in `docs/gcp-inventory.md`: a gap that the release closes
becomes a value the chart now supports.
