# config-connector-extensions CRDs

The CRDs of config-connector-extensions kinds the charts render, copied
from that repository so the render tests (`hack/test.sh`,
`hack/examples.sh`) validate them with `kubeconform -strict`, as they
validate Config Connector's own kinds against its CRDs.

| File | Kind | Copied from |
| --- | --- | --- |
| `iam.gcp.hfl.dev_iambindings.yaml` | `IAMBinding` (`iam.gcp.hfl.dev/v1beta1`) | `config/crds/` at `c4c26aa46f33d9e19a169a5ee5239145050d655b` (2026-11-10; config-connector-extensions' `agent/iambinding-v1beta1`, decision 24) |

`Taskfile.yml`'s `CCE_COMMIT`, which the fake-cloud and live runs use, is
older than this copy and has no `IAMBinding`: move it to this commit or
later before a fake-cloud case sets `iam_bindings`.
