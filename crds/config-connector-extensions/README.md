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
| `biglake.gcp.hfl.dev_biglaketables.yaml` | `BigLakeTable` (`biglake.gcp.hfl.dev/v1beta1`; Config Connector's own, `bigquerybiglake.cnrm.cloud.google.com`, reads BigLake's 403 for a missing table as a denial and never creates one) | `config/crds/` at `d7b525010062e2ef9b34cbdc8409add693ebb00a` (2026-11-14, the pin) |
| `certificatemanager.gcp.hfl.dev_certificatemanagercertificateissuanceconfigs.yaml` | `CertificateManagerCertificateIssuanceConfig` (`certificatemanager.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `f3d17ddac1f255c36dd07972b84042b58ceee53f` (2026-11-12) |
| `dataplex.gcp.hfl.dev_dataplexaspecttypes.yaml` | `DataplexAspectType` (`dataplex.gcp.hfl.dev/v1beta1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `dataplex.gcp.hfl.dev_dataplexdatascans.yaml` | `DataplexDataScan` (`dataplex.gcp.hfl.dev/v1beta1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `iam.gcp.hfl.dev_iammembers.yaml` | `IAMMember` (`iam.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `compute.gcp.hfl.dev_computenetworkendpoints.yaml` | `ComputeNetworkEndpoint` (`compute.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `apigateway.gcp.hfl.dev_apigatewayapiconfigs.yaml` | `APIGatewayAPIConfig` (`apigateway.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `apigateway.gcp.hfl.dev_apigatewaygateways.yaml` | `APIGatewayGateway` (`apigateway.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `backupdr.gcp.hfl.dev_backupdrmanagementservers.yaml` | `BackupDRManagementServer` (`backupdr.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `dataplex.gcp.hfl.dev_dataplexlakes.yaml` | `DataplexLake` (`dataplex.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `dataplex.gcp.hfl.dev_dataplexzones.yaml` | `DataplexZone` (`dataplex.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `dataplex.gcp.hfl.dev_dataplexassets.yaml` | `DataplexAsset` (`dataplex.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `11baa460f60ad9f9345cefcb6f2b594a95ce0568` (2026-11-12) |
| `aiplatform.gcp.hfl.dev_aiplatformreasoningengines.yaml` | `AIPlatformReasoningEngine` (`aiplatform.gcp.hfl.dev/v1beta1`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `cloudbuild.gcp.hfl.dev_cloudbuildconnections.yaml` | `CloudBuildConnection` (`cloudbuild.gcp.hfl.dev/v1beta1`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `cloudbuild.gcp.hfl.dev_cloudbuildrepositories.yaml` | `CloudBuildRepository` (`cloudbuild.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `cloudfunctions2.gcp.hfl.dev_cloudfunctions2functions.yaml` | `CloudFunctions2Function` (`cloudfunctions2.gcp.hfl.dev/v1beta1`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `datacatalog.gcp.hfl.dev_datacatalogtags.yaml` | `DataCatalogTag` (`datacatalog.gcp.hfl.dev/v1beta1`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `dns.gcp.hfl.dev_dnsresponsepolicies.yaml` | `DNSResponsePolicy` (`dns.gcp.hfl.dev/v1beta1`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `dns.gcp.hfl.dev_dnsresponsepolicyrules.yaml` | `DNSResponsePolicyRule` (`dns.gcp.hfl.dev/v1beta1`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `iam.gcp.hfl.dev_iammembers.yaml` | `IAMMember` (`iam.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `spanner.gcp.hfl.dev_spannerinstanceconfigs.yaml` | `SpannerInstanceConfig` (`spanner.gcp.hfl.dev/v1beta1`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `storage.gcp.hfl.dev_storagebucketobjects.yaml` | `StorageBucketObject` (`storage.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `0ee17dd438d942df8279270dac3f3fe6fcc7bebb` (2026-11-12) |
| `apigee.gcp.hfl.dev_apigeednszones.yaml` | `ApigeeDnsZone` (`apigee.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `apigee.gcp.hfl.dev_apigeenataddresses.yaml` | `ApigeeNATAddress` (`apigee.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `compute.gcp.hfl.dev_computeperinstanceconfigs.yaml` | `ComputePerInstanceConfig` (`compute.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `compute.gcp.hfl.dev_computeregionautoscalers.yaml` | `ComputeRegionAutoscaler` (`compute.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `compute.gcp.hfl.dev_computeregiondiskresourcepolicyattachments.yaml` | `ComputeRegionDiskResourcePolicyAttachment` (`compute.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `networksecurity.gcp.hfl.dev_networksecuritygatewaysecuritypolicies.yaml` | `NetworkSecurityGatewaySecurityPolicy` (`networksecurity.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `networksecurity.gcp.hfl.dev_networksecuritygatewaysecuritypolicyrules.yaml` | `NetworkSecurityGatewaySecurityPolicyRule` (`networksecurity.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `networksecurity.gcp.hfl.dev_networksecuritytlsinspectionpolicies.yaml` | `NetworkSecurityTLSInspectionPolicy` (`networksecurity.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `networksecurity.gcp.hfl.dev_networksecurityurllists.yaml` | `NetworkSecurityURLList` (`networksecurity.gcp.hfl.dev/v1beta1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `chronicle.gcp.hfl.dev_chronicleruledeployments.yaml` | `ChronicleRuleDeployment` (`chronicle.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `d54a2075f611ec13c22fd77d52aa35d0e55cef53` (2026-11-13) |
| `iam.gcp.hfl.dev_iampolicybindings.yaml` | `IAMPolicyBinding` (`iam.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`; `target.resource` and an `ACCESS` policy since this copy) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `networkservices.gcp.hfl.dev_networkservicesgateways.yaml` | `NetworkServicesGateway` (`networkservices.gcp.hfl.dev/v1beta1`; Config Connector's own cannot make a `SECURE_WEB_GATEWAY`) | `config/crds/` at `d54a2075f611ec13c22fd77d52aa35d0e55cef53` (2026-11-13) |
| `servicemanagement.gcp.hfl.dev_endpointsservices.yaml` | `EndpointsService` (`servicemanagement.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `d54a2075f611ec13c22fd77d52aa35d0e55cef53` (2026-11-13) |
| `logging.gcp.hfl.dev_loggingbillingaccountsinks.yaml` | `LoggingBillingAccountSink` (`logging.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `d54a2075f611ec13c22fd77d52aa35d0e55cef53` (2026-11-13) |
| `networkservices.gcp.hfl.dev_networkservicesagentgateways.yaml` | `NetworkServicesAgentGateway` (`networkservices.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `d54a2075f611ec13c22fd77d52aa35d0e55cef53` (2026-11-13) |
| `networkservices.gcp.hfl.dev_networkservicesagentconnectivitytemplates.yaml` | `NetworkServicesAgentConnectivityTemplate` (`networkservices.gcp.hfl.dev/v1alpha1`: a chart renders it only with `allow_alpha`) | `config/crds/` at `d54a2075f611ec13c22fd77d52aa35d0e55cef53` (2026-11-13) |
| `chronicle.gcp.hfl.dev_chroniclerules.yaml` | `ChronicleRule` (`chronicle.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `chronicle.gcp.hfl.dev_chroniclereferencelists.yaml` | `ChronicleReferenceList` (`chronicle.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `networkservices.gcp.hfl.dev_networkservicesauthzextensions.yaml` | `NetworkServicesAuthzExtension` (`networkservices.gcp.hfl.dev/v1beta1`, with `service` for IAP or Model Armor; Config Connector's own is `v1alpha1`) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `iam.gcp.hfl.dev_iamaccesspolicies.yaml` | `IAMAccessPolicy` (`iam.gcp.hfl.dev/v1beta1`, with an organization, folder or project parent) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `compute.gcp.hfl.dev_computeinterconnectattachments.yaml` | `ComputeInterconnectAttachment` (`compute.gcp.hfl.dev/v1beta1`, with the candidate Cloud Router and customer IP fields) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `iam.gcp.hfl.dev_iamdenypolicies.yaml` | `IAMDenyPolicy` (`iam.gcp.hfl.dev/v1beta1`, with every parent) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `compute.gcp.hfl.dev_computevpntunnels.yaml` | `ComputeVPNTunnel` (`compute.gcp.hfl.dev/v1beta1`, with `cipherSuite`) | `config/crds/` at `3de8de68304dd1be11757e786692db235139df7a` (2026-11-13) |
| `networksecurity.gcp.hfl.dev_networksecurityauthzpolicies.yaml` | `NetworkSecurityAuthzPolicy` (`networksecurity.gcp.hfl.dev/v1beta1`; a target's resources by name, an agent gateway among them, and a `CUSTOM` action's authz extension) | `config/crds/` at `c2f0c7d295da38314aad8d8da674d283befcfb46` (2026-11-13, the pin) |
| `compute.gcp.hfl.dev_computeautoscalers.yaml` | `ComputeAutoscaler` (`compute.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |
| `compute.gcp.hfl.dev_computeregionperinstanceconfigs.yaml` | `ComputeRegionPerInstanceConfig` (`compute.gcp.hfl.dev/v1beta1`; Config Connector's own is `v1alpha1`) | `config/crds/` at `35833eb8c7594675ea5237c11373665cd806658e` (2026-11-12) |

`Taskfile.yml`'s `CCE_COMMIT`, which the fake-cloud and live runs use, is
`384d07c01932defd747c17038a833ca3b591fa7a` (2026-11-14), at or after every
copy above, so the fake cloud serves each of these kinds (each file is the
same at the pin). A CRD copied from a later commit needs the pin moved
first, in its own change, before a fake-cloud case renders the kind; until
then the chart's README says which of its objects are only render-tested.
