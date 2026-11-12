# config-connector-extensions CRDs

The CRDs of config-connector-extensions kinds the charts render, copied
from that repository so the render tests (`hack/test.sh`,
`hack/examples.sh`) validate them with `kubeconform -strict`, as they
validate Config Connector's own kinds against its CRDs.

| File | Kind | Copied from |
| --- | --- | --- |
| `iam.gcp.hfl.dev_iambindings.yaml` | `IAMBinding` (`iam.gcp.hfl.dev/v1beta1`) | `config/crds/` at `c4c26aa46f33d9e19a169a5ee5239145050d655b` (2026-11-10; config-connector-extensions' `agent/iambinding-v1beta1`, decision 24) |
| `compute.gcp.hfl.dev_computenetworkattachments.yaml` | `ComputeNetworkAttachment` (`compute.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `89806ec7a1ea127fd435ca264d2883b9c233de2c` (2026-11-12) |
| `compute.gcp.hfl.dev_computerouterroutepolicies.yaml` | `ComputeRouterRoutePolicy` (`compute.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `89806ec7a1ea127fd435ca264d2883b9c233de2c` (2026-11-12) |

`Taskfile.yml`'s `CCE_COMMIT`, which the fake-cloud and live runs use, is
older than these copies and has none of these kinds: move it to their
commit or later before a fake-cloud case renders one (`iam_bindings`, a
network attachment, a route policy). A chart's README says which of its
objects are only render-tested for this reason.
