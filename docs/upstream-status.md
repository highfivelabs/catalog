# Upstream status

Which tracked Terraform modules have a release newer than the one pinned in [`upstream/modules.yaml`](../upstream/modules.yaml), and what changed. Written by `task upstream-watch` (read-only: `git ls-remote --tags` and tarball GETs); the same data is in [`upstream-status.json`](upstream-status.json). A daily workflow keeps one issue with this report. This file is refreshed when someone runs the task and commits it; it is a snapshot.

168 modules checked on 2026-11-09: 167 up to date, **1 have a newer release** (0 with a chart).

To take a release: carry its changes into the chart, then `task upstream-bump -- <module> <tag>` (UPSTREAM.md, "Moving the pins").

## Other modules

| Module | Pinned | Latest | Releases behind | Interface changes | Links |
| --- | --- | --- | ---: | --- | --- |
| `aws/ecr` | v3.2.0 | v3.2.1 | 1 | none: the tag moved, the module's Terraform did not | [compare](https://github.com/terraform-aws-modules/terraform-aws-ecr/compare/v3.2.0...v3.2.1), [notes](https://github.com/terraform-aws-modules/terraform-aws-ecr/releases/tag/v3.2.1) |

## What changed

Interface differences are read from each module's `variable`, `output` and `resource` blocks; "files" counts the module's `.tf` files that differ at all, since behaviour can change with the interface unchanged. Only modules whose Terraform changed are listed; the JSON has all of them.

