# Secrets: references to Kubernetes Secrets

The builder's decision (2026-11-14): a chart takes secret material (a TLS
certificate's PFX and its password, a connection string, an API key, a SAS
URL) as a **reference to a Kubernetes Secret**, assuming the Secret was
put in the cluster by [External Secrets Operator](https://external-secrets.io)
(ESO). A chart never takes a secret's value in its values, and never
generates one. The catalog holds no secret values, test ones included.

## The pattern

A value that is secret material is an object of two fields:

```yaml
data: {secretName: appgw-tls, key: pfx}
```

| Field | What |
| --- | --- |
| `secretName` | the name of a Kubernetes Secret in the component's namespace (the namespace the chart's objects are applied to) |
| `key` | the key in that Secret's `data` that holds the value |

The chart renders it as the controller's own secret reference: Azure
Service Operator's `SecretReference` (`{name, key}`) on Azure. The
controller reads the Secret when it reconciles and sends the value to the
cloud; the value is never in the chart's values, the rendered objects or
the component's inputs. A string where a reference is expected (the secret
itself) stops the render:

```text
avm-res-network-applicationgateway: ssl_certificates[0].data takes a reference to a Kubernetes Secret, {secretName, key}, never the secret's value (docs/secrets.md)
```

The variable keeps the module's name, so a module call converts by
replacing each secret value with the reference to where it is kept. The
Secret must exist before the controller can finish: until it does, the
object is not Ready and its condition names the missing Secret. A
rotation is a change to the Secret (ESO refreshes it on its interval);
the chart's values do not change.

A pointer to a secret is not secret material: a Key Vault secret ID
(`key_vault_secret_id`), a Key Vault URL or a secret's name in a secret
store are plain values, sent as they are.

## Where the Secret comes from: External Secrets Operator

ESO copies a value from a secret store into a Kubernetes Secret. One
`ExternalSecret` per component, in its namespace, named by `secretName`:

**Azure Key Vault** (a certificate imported into Key Vault is also a
secret of the same name whose value is the PFX, base64, without a
password):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: appgw-tls, namespace: team-web}
spec:
  refreshInterval: 1h
  secretStoreRef: {kind: ClusterSecretStore, name: azure-key-vault}
  target: {name: appgw-tls}
  data:
    - secretKey: pfx
      remoteRef: {key: secret/appgw-tls}
```

**Google Cloud Secret Manager**, a PFX kept as binary, base64-encoded by
ESO's template, and its password:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: appgw-tls, namespace: team-web}
spec:
  secretStoreRef: {kind: ClusterSecretStore, name: gcp-secret-manager}
  target:
    name: appgw-tls
    template:
      data:
        pfx: '{{ .pfx | b64enc }}'
        password: '{{ .password }}'
  data:
    - {secretKey: pfx, remoteRef: {key: appgw-tls-pfx}}
    - {secretKey: password, remoteRef: {key: appgw-tls-password}}
```

**AWS Secrets Manager**, one JSON secret with both fields:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: appgw-tls, namespace: team-web}
spec:
  secretStoreRef: {kind: ClusterSecretStore, name: aws-secrets-manager}
  target: {name: appgw-tls}
  dataFrom:
    - extract: {key: team-web/appgw-tls}
```

The value is what the cloud API takes, as text: Application Gateway's
`sslCertificates` `data` is the PFX in base64, and a trusted root or
authentication certificate's `data` is the certificate (DER) in base64.

A certificate already in Azure Key Vault is usually better given to the
gateway by `key_vault_secret_id` with a user-assigned identity: the
gateway reads it and follows its new versions itself, and nothing passes
through the cluster. The Secret reference is for a certificate kept
elsewhere, or a gateway without an identity.

## What takes a reference

| Chart | Variable | Rendered as |
| --- | --- | --- |
| `avm-res-network-applicationgateway` (0.4.0) | `ssl_certificates[].data`, `.password` | `sslCertificates[].data`, `.password` (aso-extensions' `ApplicationGateway`); `key_vault_secret_id` as it is |
| | `authentication_certificates[].data`, `trusted_client_certificates[].data`, `trusted_root_certificates[].data` | the collections' `data` (public certificates, which the kind takes only from a Secret); `trusted_root_certificates[].key_vault_secret_id` as it is |
| `avm-res-app-managedenvironment` (0.5.0) | `connection_string` (with `connection_string_version`) | `appInsightsConfiguration.connectionString` (aso-extensions' `ManagedEnvironment`) |
| | `key` (the Datadog API key, with `key_version`) | `openTelemetryConfiguration.destinationsConfiguration.dataDogConfiguration.key` |
| `avm-res-web-site` (0.4.0) | `logs.*.application_logs.*.azure_blob_storage.sas_url`, `logs.*.http_logs.*.azure_blob_storage.sas_url` | `applicationLogs.azureBlobStorage.sasUrl`, `httpLogs.azureBlobStorage.sasUrl` (aso-extensions' `SitesConfigLogs`) |

A module's `*_version` beside a write-only secret is required with it, as
in the module, and does nothing: the controller sends the whole body on
every change.

## Still refused, could take a reference next

Variables the Azure charts refuse as secret values whose kind already
takes the field as a `SecretReference`: each is a mapping like the ones
above, chart by chart.

| Chart | Variable | Field (kind) |
| --- | --- | --- |
| `avm-res-app-managedenvironment` | `shared_key` (and `log_analytics_workspace_primary_shared_key`; a `log-analytics` destination) | `appLogsConfiguration.logAnalyticsConfiguration.sharedKey` (aso-extensions' `ManagedEnvironment`) |
| | `certificate_password`, `certificate_value` (and the deprecated `custom_domain_certificate_*`) | `customDomainConfiguration.certificatePassword`, `.certificateValue` |
| | `dapr_ai_connection_string`, `dapr_ai_instrumentation_key` | `daprAIConnectionString`, `daprAIInstrumentationKey` |
| | `certificates[].password`, `.value` | `ManagedEnvironmentsCertificate` `properties.password`, `.value` |
| | `dapr_components[].secrets[].value` | `ManagedEnvironmentsDaprComponent` `secrets[].value` |
| | `storages[].azure_file.account_key` | `ManagedEnvironmentsStorage` `properties.azureFile.accountKey` |
| `avm-res-app-containerapp` | `secrets[].value` | `ContainerApp` `configuration.secrets[].value` |
| `avm-res-web-site` | `certificates[].pfx_blob`, `.password` | aso-extensions' `Certificate` `pfxBlob`, `password` |
| | `storage_shares_to_mount` (the access key) | `Site` `siteConfig.azureStorageAccounts` |
| `avm-res-compute-virtualmachine` | `admin_password`, `account_credentials.admin_credentials.password` (and with it a Windows OS profile) | `VirtualMachine` `osProfile.adminPassword` |
| `avm-res-containerservice-managedcluster` | `windows_profile_password`, `aad_profile.server_app_secret`, `service_principal_profile.secret` | `ManagedCluster` `windowsProfile.adminPassword`, `aadProfile.serverAppSecret`, `servicePrincipalProfile.secret` |
| `avm-res-dbforpostgresql-flexibleserver` | `administrator_password` (`_wo`) | `FlexibleServer` `administratorLoginPassword` |
| `avm-res-sql-server` | `administrator_login_password` (`_wo`) | `Server` `administratorLoginPassword` |
| `avm-res-cognitiveservices-account` | `custom_question_answering_search_service_key` | `Account` `apiProperties.qnaAzureSearchEndpointKey` |
| `avm-res-keyvault-vault` | `secrets`, `secrets_value` | aso-extensions' `VaultSecret` (its value from a Secret; its CRD is not copied into `crds/aso-extensions` yet) |

Not this pattern: a value the module generates (`generate_admin_password_or_ssh_key`,
`generate_administrator_login_password`: the catalog never generates
secrets), a password Azure returns once (a registry token's
`passwords`), and a secret a kind takes in plain text (a web app's
`connection_strings`, its Application Insights settings, a Redis cache's
storage connection strings): those need the kind to take a reference
first.

## Tests

No key material is committed. A test case that needs a Secret names it in
its values file, `# secret: NAME KIND`, and `hack/test-secret.sh` makes
it in the test's namespace before the apply, from material generated then
(a self-signed certificate as a password-protected PFX, or random bytes),
and deletes it afterwards. The fake-cloud run (`hack/azure-mock.sh`) and
the live run (`hack/azure-live.sh`) both call it.
