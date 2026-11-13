{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

The module's data, as the chart's: Helm merges a map given in values into a
map default (Terraform replaces it), so these defaults live here, not in
values.yaml.

plpdz.defaultZones: the default of private_link_private_dns_zones, from
terraform-azurerm-avm-ptn-network-private-link-private-dns-zones
variables.tf (v0.23.2, 4d2214f162806d48ea9a157de4b904f879fc61d4), 85
zones, Copyright (c) Microsoft Corporation, MIT. Each entry takes the
module's optional defaults (private_dns_zone_supports_private_link true,
custom_iterator and resolution_policy null) in the template.
*/ -}}
{{- define "plpdz.defaultZones" -}}
azure_container_apps: {zone_name: "privatelink.{regionName}.azurecontainerapps.io"}
azure_ml: {zone_name: "privatelink.api.azureml.ms"}
azure_ml_notebooks: {zone_name: "privatelink.notebooks.azure.net"}
azure_ai_cog_svcs: {zone_name: "privatelink.cognitiveservices.azure.com"}
azure_ai_oai: {zone_name: "privatelink.openai.azure.com"}
azure_ai_services: {zone_name: "privatelink.services.ai.azure.com"}
azure_bot_svc_bot: {zone_name: "privatelink.directline.botframework.com"}
azure_bot_svc_token: {zone_name: "privatelink.token.botframework.com"}
azure_service_hub: {zone_name: "privatelink.servicebus.windows.net"}
azure_data_factory: {zone_name: "privatelink.datafactory.azure.net"}
azure_data_factory_portal: {zone_name: "privatelink.adf.azure.com"}
azure_hdinsight: {zone_name: "privatelink.azurehdinsight.net"}
azure_data_explorer: {zone_name: "privatelink.{regionName}.kusto.windows.net"}
azure_storage_blob: {zone_name: "privatelink.blob.core.windows.net"}
azure_storage_queue: {zone_name: "privatelink.queue.core.windows.net"}
azure_storage_table: {zone_name: "privatelink.table.core.windows.net"}
azure_storage_file: {zone_name: "privatelink.file.core.windows.net"}
azure_storage_web: {zone_name: "privatelink.web.core.windows.net"}
azure_data_lake_gen2: {zone_name: "privatelink.dfs.core.windows.net"}
azure_file_sync: {zone_name: "privatelink.afs.azure.net"}
azure_power_bi_tenant_analysis: {zone_name: "privatelink.analysis.windows.net"}
azure_power_bi_dedicated: {zone_name: "privatelink.pbidedicated.windows.net"}
azure_power_bi_power_query: {zone_name: "privatelink.tip1.powerquery.microsoft.com"}
azure_databricks_ui_api: {zone_name: "privatelink.azuredatabricks.net"}
azure_fabric: {zone_name: "privatelink.fabric.microsoft.com"}
azure_batch: {zone_name: "privatelink.batch.azure.com"}
azure_avd_global: {zone_name: "privatelink-global.wvd.microsoft.com"}
azure_avd_feed_mgmt: {zone_name: "privatelink.wvd.microsoft.com"}
azure_aks_mgmt: {zone_name: "privatelink.{regionName}.azmk8s.io"}
azure_acr_registry: {zone_name: "privatelink.azurecr.io"}
azure_sql_server: {zone_name: "privatelink.database.windows.net"}
azure_cosmos_db_sql: {zone_name: "privatelink.documents.azure.com"}
azure_cosmos_db_mongo: {zone_name: "privatelink.mongo.cosmos.azure.com"}
azure_cosmos_db_mongo_vcore: {zone_name: "privatelink.mongocluster.cosmos.azure.com"}
azure_cosmos_db_cassandra: {zone_name: "privatelink.cassandra.cosmos.azure.com"}
azure_cosmos_db_gremlin: {zone_name: "privatelink.gremlin.cosmos.azure.com"}
azure_cosmos_db_table: {zone_name: "privatelink.table.cosmos.azure.com"}
azure_cosmos_db_analytical: {zone_name: "privatelink.analytics.cosmos.azure.com"}
azure_cosmos_db_postgres: {zone_name: "privatelink.postgres.cosmos.azure.com"}
azure_maria_db_server: {zone_name: "privatelink.mariadb.database.azure.com"}
azure_postgres_sql_server: {zone_name: "privatelink.postgres.database.azure.com"}
azure_mysql_db_server: {zone_name: "privatelink.mysql.database.azure.com"}
azure_redis_cache: {zone_name: "privatelink.redis.cache.windows.net"}
azure_redis_enterprise: {zone_name: "privatelink.redisenterprise.cache.azure.net"}
azure_managed_redis: {zone_name: "privatelink.redis.azure.net"}
azure_arc_hybrid_compute: {zone_name: "privatelink.his.arc.azure.com"}
azure_arc_guest_configuration: {zone_name: "privatelink.guestconfiguration.azure.com"}
azure_arc_kubernetes: {zone_name: "privatelink.dp.kubernetesconfiguration.azure.com"}
azure_event_grid: {zone_name: "privatelink.eventgrid.azure.net"}
azure_event_grid_mqtt: {zone_name: "privatelink.ts.eventgrid.azure.net"}
azure_api_management: {zone_name: "privatelink.azure-api.net"}
azure_healthcare: {zone_name: "privatelink.azurehealthcareapis.com"}
azure_healthcare_dicom: {zone_name: "privatelink.dicom.azurehealthcareapis.com"}
azure_iot_hub: {zone_name: "privatelink.azure-devices.net"}
azure_iot_hub_provisioning: {zone_name: "privatelink.azure-devices-provisioning.net"}
azure_iot_hub_update: {zone_name: "privatelink.api.adu.microsoft.com"}
azure_iot_central: {zone_name: "privatelink.azureiotcentral.com"}
azure_digital_twins: {zone_name: "privatelink.digitaltwins.azure.net"}
azure_media_services_delivery: {zone_name: "privatelink.media.azure.net"}
azure_automation: {zone_name: "privatelink.azure-automation.net"}
azure_backup: {zone_name: "privatelink.{regionCode}.backup.windowsazure.com"}
azure_site_recovery: {zone_name: "privatelink.siterecovery.windowsazure.com"}
azure_monitor: {zone_name: "privatelink.monitor.azure.com"}
azure_log_analytics: {zone_name: "privatelink.oms.opinsights.azure.com"}
azure_log_analytics_data: {zone_name: "privatelink.ods.opinsights.azure.com"}
azure_monitor_agent: {zone_name: "privatelink.agentsvc.azure-automation.net"}
azure_managed_prometheus: {zone_name: "privatelink.{regionName}.prometheus.monitor.azure.com"}
azure_purview_account: {zone_name: "privatelink.purview.azure.com"}
azure_purview_studio: {zone_name: "privatelink.purviewstudio.azure.com"}
azure_purview_service: {zone_name: "privatelink.purview-service.microsoft.com"}
azure_migration_service: {zone_name: "privatelink.prod.migration.windowsazure.com"}
azure_grafana: {zone_name: "privatelink.grafana.azure.com"}
azure_key_vault: {zone_name: "privatelink.vaultcore.azure.net"}
azure_managed_hsm: {zone_name: "privatelink.managedhsm.azure.net"}
azure_app_configuration: {zone_name: "privatelink.azconfig.io"}
azure_attestation: {zone_name: "privatelink.attest.azure.net"}
azure_search: {zone_name: "privatelink.search.windows.net"}
azure_app_service: {zone_name: "privatelink.azurewebsites.net"}
azure_signalr_service: {zone_name: "privatelink.service.signalr.net"}
azure_static_web_apps: {zone_name: "privatelink.azurestaticapps.net"}
azure_static_web_apps_partitioned: {zone_name: "privatelink.{partitionId}.azurestaticapps.net", custom_iterator: {replacement_placeholder: partitionId, replacement_values: {"1": "1", "2": "2", "3": "3", "4": "4", "5": "5"}}}
azure_synapse: {zone_name: "privatelink.azuresynapse.net"}
azure_synapse_sql: {zone_name: "privatelink.sql.azuresynapse.net"}
azure_synapse_dev: {zone_name: "privatelink.dev.azuresynapse.net"}
azure_web_pubsub: {zone_name: "privatelink.webpubsub.azure.com"}
{{- end -}}

{{- /*
plpdz.regions: the regions the module's location may name, by name, with
the display name it also takes and the region code ({regionCode}), from
terraform-azurerm-avm-utl-regions v0.12.0 (the version the module calls;
e9d62409c6fcc5554b60dd79cd60f55b344ad2f0), Copyright (c) Microsoft Corporation,
MIT: its cached location list (modules/cached-data/locations.tf.json, the
Physical regions) and its geo codes (locals.geo.codes.tf.json). The module
reads the subscription's location list live (use_cached_data = false); a
region not in this table is refused, naming it. A region with no code
(geo_code null) takes no zone with {regionCode}, as the module cannot
either; a region known only by its code has no display name here.
*/ -}}
{{- define "plpdz.regions" -}}
australiacentral: {display_name: "Australia Central", geo_code: acl}
australiacentral2: {display_name: "Australia Central 2", geo_code: acl2}
australiaeast: {display_name: "Australia East", geo_code: ae}
australiasoutheast: {display_name: "Australia Southeast", geo_code: ase}
austriaeast: {display_name: "Austria East", geo_code: aue}
belgiumcentral: {display_name: "Belgium Central", geo_code: bec}
brazilsouth: {display_name: "Brazil South", geo_code: brs}
brazilsoutheast: {display_name: "Brazil Southeast", geo_code: bse}
canadacentral: {display_name: "Canada Central", geo_code: cnc}
canadaeast: {display_name: "Canada East", geo_code: cne}
centralindia: {display_name: "Central India", geo_code: inc}
centralus: {display_name: "Central US", geo_code: cus}
centraluseuap: {display_name: "Central US EUAP", geo_code: ccy}
chilecentral: {display_name: "Chile Central", geo_code: clc}
denmarkeast: {display_name: "Denmark East", geo_code: dke}
eastasia: {display_name: "East Asia", geo_code: ea}
eastus: {display_name: "East US", geo_code: eus}
eastus2: {display_name: "East US 2", geo_code: eus2}
eastus2euap: {display_name: "East US 2 EUAP", geo_code: ecy}
eastus3: {display_name: null, geo_code: eus3}
eastusstg: {display_name: "East US STG", geo_code: null}
francecentral: {display_name: "France Central", geo_code: frc}
francesouth: {display_name: "France South", geo_code: frs}
germanynorth: {display_name: "Germany North", geo_code: gn}
germanywestcentral: {display_name: "Germany West Central", geo_code: gwc}
indiasouthcentral: {display_name: null, geo_code: insc}
indonesiacentral: {display_name: "Indonesia Central", geo_code: idc}
israelcentral: {display_name: "Israel Central", geo_code: ilc}
israelnorthwest: {display_name: null, geo_code: iln}
italynorth: {display_name: "Italy North", geo_code: itn}
japaneast: {display_name: "Japan East", geo_code: jpe}
japanwest: {display_name: "Japan West", geo_code: jpw}
jioindiacentral: {display_name: "Jio India Central", geo_code: jic}
jioindiawest: {display_name: "Jio India West", geo_code: jiw}
koreacentral: {display_name: "Korea Central", geo_code: krc}
koreasouth: {display_name: "Korea South", geo_code: krs}
malaysiasouth: {display_name: null, geo_code: mys}
malaysiawest: {display_name: "Malaysia West", geo_code: myw}
mexicocentral: {display_name: "Mexico Central", geo_code: mxc}
newzealandnorth: {display_name: "New Zealand North", geo_code: nzn}
northcentralus: {display_name: "North Central US", geo_code: ncus}
northeastus5: {display_name: null, geo_code: ne5s}
northeurope: {display_name: "North Europe", geo_code: ne}
norwayeast: {display_name: "Norway East", geo_code: nwe}
norwaywest: {display_name: "Norway West", geo_code: nww}
polandcentral: {display_name: "Poland Central", geo_code: plc}
qatarcentral: {display_name: "Qatar Central", geo_code: qac}
southafricanorth: {display_name: "South Africa North", geo_code: san}
southafricawest: {display_name: "South Africa West", geo_code: saw}
southcentralus: {display_name: "South Central US", geo_code: scus}
southcentralus2: {display_name: null, geo_code: usc2}
southcentralusstg: {display_name: "South Central US STG", geo_code: null}
southeastasia: {display_name: "Southeast Asia", geo_code: sea}
southeastus: {display_name: null, geo_code: use}
southeastus3: {display_name: null, geo_code: use3}
southeastus5: {display_name: null, geo_code: use5}
southindia: {display_name: "South India", geo_code: ins}
southwestus: {display_name: null, geo_code: swus}
spaincentral: {display_name: "Spain Central", geo_code: spc}
swedencentral: {display_name: "Sweden Central", geo_code: sdc}
swedensouth: {display_name: null, geo_code: sds}
switzerlandnorth: {display_name: "Switzerland North", geo_code: szn}
switzerlandwest: {display_name: "Switzerland West", geo_code: szw}
taiwannorth: {display_name: null, geo_code: twn}
taiwannorthwest: {display_name: null, geo_code: tnw}
uaecentral: {display_name: "UAE Central", geo_code: uac}
uaenorth: {display_name: "UAE North", geo_code: uan}
uksouth: {display_name: "UK South", geo_code: uks}
ukwest: {display_name: "UK West", geo_code: ukw}
westcentralus: {display_name: "West Central US", geo_code: wcus}
westeurope: {display_name: "West Europe", geo_code: we}
westindia: {display_name: "West India", geo_code: inw}
westus: {display_name: "West US", geo_code: wus}
westus2: {display_name: "West US 2", geo_code: wus2}
westus3: {display_name: "West US 3", geo_code: wus3}
{{- end -}}
