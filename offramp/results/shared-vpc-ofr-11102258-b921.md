# Offramp live run ofr-11102258-b921: shared-vpc

Project hfl-dev-514205, as cce-live-tests@hfl-dev-514205.iam.gserviceaccount.com; Config Connector v1.160.0; Terraform 1.17.1; catalog 744a7eb; started 2026-11-10T22:58:12Z.

| Step | Result | Detail |
| --- | --- | --- |
| terraform apply | ok | Apply complete! Resources: 12 added |
| terraform plan after apply | no changes | plan-before.txt |
| scan | 7 assets | scan: Cloud Asset Inventory refused (projects/hfl-dev-514205): does not have permission to access projects instance [hfl-dev-514205] (or it may not exist): Cloud Asset API has not been used in project hfl-dev-514205 before or it is disabled |
| config-connector export | 7 exported, 0 refused |  |
| offramp state | ok | 12 objects, 3 components, 3 note |
| compare state and scan | 3 differences | compare.txt |
| objects applied (server-side, manager bundt) | 12 | from-state/krm/all.yaml |
| config-connector preview | exit 0; Detected 12 good and 0 bad objects in default run; GCP_WRITE 0 | report-20261110-230044.325 |
| objects Ready, reason UpToDate | 12 of 12 | ready.tsv |
| events | UpToDate 12 | events.json |
| manager log: create, update lines | 0, 0 | manager.log |
| server-side dry run as bundt (Bundt's live check) | no difference | bundt-diff.txt |
| terraform plan after adoption | no changes | plan-after.txt |
| deleted the objects (abandon): networks still there | 1 | kept-networks.txt |
| Admin Activity audit entries | not readable here | ERROR: (gcloud.logging.read) PERMISSION_DENIED: Permission denied for all log views. This command is authenticated as cce-live-tests@hfl-dev-514205.iam.gserviceaccount.com which is the active account ; read them with: gcloud logging read 'logName="projects/hfl-dev-514205/logs/cloudaudit.googleapis.com%2Factivity" AND protoPayload.authenticationInfo.principalEmail="cce-live-tests@hfl-dev-514205.iam.gserviceaccount.com" AND timestamp>="2026-11-10T23:00:44Z" AND timestamp<="2026-11-10T23:06:50Z"' --project hfl-dev-514205 |
| terraform destroy | ok | attempt 1 |
| left in the state | 0 |  |
| left in Google Cloud named ofr-11102258-b921 | none |   |

Finished 2026-11-10T23:09:46Z, exit 0.

## Read afterwards

Admin Activity audit log, read from the laptop as the builder (read only), for `cce-live-tests@` on resources named `ofr-11102258-b921` between T0 23:00:44 and T2 23:06:50 UTC: **0 entries**. `offramp compare` lists only the network firewall policy's rules and association, which the scan cannot see.
