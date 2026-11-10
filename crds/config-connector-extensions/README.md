# config-connector-extensions CRDs

The CRDs of config-connector-extensions kinds the charts render, copied
from that repository so the render tests (`hack/test.sh`,
`hack/examples.sh`) validate them with `kubeconform -strict`, as they
validate Config Connector's own kinds against its CRDs.

| File | Kind | Copied from |
| --- | --- | --- |
| `iam.gcp.hfl.dev_iambindings.yaml` | `IAMBinding` (`iam.gcp.hfl.dev/v1alpha1`) | `config/crds/` at `748bff29e378b1e01407faab4d2afe080f323702` (2026-11-10) |

`Taskfile.yml`'s `CCE_COMMIT`, which the fake-cloud and live runs use, is
older than this copy and has no `IAMBinding`: move it to this commit or
later before a fake-cloud case sets `iam_bindings` with `allow_alpha`.
