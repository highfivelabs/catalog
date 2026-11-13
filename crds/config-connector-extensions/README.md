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
| `biglake.gcp.hfl.dev_biglakecatalogs.yaml` | `BigLakeCatalog` (`biglake.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `biglake.gcp.hfl.dev_biglakedatabases.yaml` | `BigLakeDatabase` (`biglake.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `certificatemanager.gcp.hfl.dev_certificatemanagercertificateissuanceconfigs.yaml` | `CertificateManagerCertificateIssuanceConfig` (`certificatemanager.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `f3d17ddac1f255c36dd07972b84042b58ceee53f` (2026-11-12) |
| `dataplex.gcp.hfl.dev_dataplexaspecttypes.yaml` | `DataplexAspectType` (`dataplex.gcp.hfl.dev/v1beta1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12, the pin) |
| `dataplex.gcp.hfl.dev_dataplexdatascans.yaml` | `DataplexDataScan` (`dataplex.gcp.hfl.dev/v1beta1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12, the pin) |
| `iam.gcp.hfl.dev_iammembers.yaml` | `IAMMember` (`iam.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12, the pin) |

`Taskfile.yml`'s `CCE_COMMIT`, which the fake-cloud and live runs use, is
`11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12), at or after every
copy above, so the fake cloud serves each of these kinds (each file is the
same at the pin). A CRD copied from a later commit needs the pin moved
first, in its own change, before a fake-cloud case renders the kind; until
then the chart's README says which of its objects are only render-tested.
