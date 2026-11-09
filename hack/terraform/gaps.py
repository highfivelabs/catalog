#!/usr/bin/env python3
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
"""For each row of the three foundation.md work queues, the Terraform resources
that cover it, found by name patterns chosen by hand. Writes
docs/terraform/data/foundation-gaps.csv (cloud,row,item,tf_resources,providers,verdict).
Run from the repository root after export-schemas.sh."""
import csv, re

ROWS = {
 "gcp": [
  (1, "Hierarchy and project settings (folder/org service identity, default service accounts, default network tier)", r"^google_(folder_service_identity|organization_service_identity|project_service_identity|project_default_service_accounts|compute_project_default_network_tier)$"),
  (2, "Regional network firewall policy rules, associations, packet mirroring rules", r"^google_compute_(region_network_firewall_policy_(rule|association|with_rules)|(network_|region_network_)?firewall_policy_packet_mirroring_rule|region_network_firewall_policy_packet_mirroring_rule)$"),
  (3, "Organization-level custom IAM roles", r"^google_organization_iam_custom_role$"),
  (4, "Workforce identity (SCIM, provider keys) and OAuth clients", r"^google_iam_(workforce_pool_provider_(key|scim_tenant|scim_token)|oauth_client(_credential)?)$"),
  (5, "Fleet RBAC role bindings and rollout sequences", r"^google_gke_hub_(membership_rbac_role_binding|scope_rbac_role_binding|rollout_sequence)$"),
  (6, "Organization-level network security objects (address groups, security profiles)", r"^google_network_security_(address_group|security_profile|security_profile_group)$"),
  (7, "BYOIP prefixes and cross-site interconnect groups", r"^google_compute_(public_advertised_prefix|public_delegated_prefix|global_public_delegated_prefix|interconnect_group|cross_site_network)$"),
  (8, "Stable kinds for alpha-only foundation kinds (deny policies, PAB, hierarchical policy, network firewall rules, response policies)", r"^google_(iam_deny_policy|iam_principal_access_boundary_policy|compute_firewall_policy(_rule|_association|_with_rules)?|compute_network_firewall_policy(_rule|_association|_with_rules)?|dns_response_policy(_rule)?)$"),
  (9, "Cloud Router fields (BGP peers, NAT, interfaces, MD5)", r"^google_compute_router(_nat|_peer|_interface|_nat_address|_named_set|_route_policy)?$"),
  (10, "VPN tunnel and Interconnect attachment fields", r"^google_compute_(vpn_tunnel|ha_vpn_gateway|interconnect_attachment|interconnect|external_vpn_gateway)$"),
  (11, "Service attachment fields (PSC producers)", r"^google_compute_service_attachment$"),
  (12, "Logging fields (buckets, sinks) and saved queries", r"^google_logging_(project_bucket_config|project_sink|folder_sink|organization_sink|saved_query|log_view|linked_dataset)$"),
  (13, "Organization policy fields (alternate policy)", r"^google_org_policy_policy$"),
  (14, "GKE cluster and node pool fields", r"^google_container_(cluster|node_pool)$"),
  (15, "Cloud DNS fields (routing policies, forwarding and peering zones)", r"^google_dns_(managed_zone|record_set|policy)$"),
  (16, "Network and subnetwork fields", r"^google_compute_(network|subnetwork)$"),
  (17, "Billing account log sink", r"^google_logging_billing_account_sink$"),
  (18, "KMS fields (key access justifications, key backend)", r"^google_kms_(crypto_key|key_ring|crypto_key_version|project_kaj_policy_config|folder_kaj_policy_config|organization_kaj_policy_config)$"),
  (19, "Hierarchical firewall policy rule fields", r"^google_compute_firewall_policy_rule$"),
  (20, "Security Command Center at folder and project level", r"^google_scc_(folder|project|v2_folder|v2_project)_.*$|^google_scc_(notification_config|source|mute_config)$"),
  (21, "VPC Service Controls (authorized orgs descriptions, dry-run spec, user access bindings)", r"^google_access_context_manager_(authorized_orgs_desc|service_perimeter|service_perimeter_dry_run_resource|access_level|gcp_user_access_binding|service_perimeter_egress_policy|service_perimeter_ingress_policy)$"),
  (22, "Privileged Access Manager grants", r"^google_privileged_access_manager_(entitlement|grant)$"),
  (23, "Resource Manager capability configs, boundaries and tag holds", r"^google_resource_manager_(capability|boundary|boundary_config)$|^google_tags_tag_value_tag_hold$"),
  (24, "Cloud Identity SSO profiles, assignments and policies", r"^google_cloud_identity_(group|group_membership|policy|sso.*)$|^google_identity_platform.*$"),
  (25, "Binary Authorization, Private CA and Certificate Manager fields", r"^google_(binary_authorization_(attestor|policy)|privateca_.*|certificate_manager_.*)$"),
  (26, "Secret Manager fields", r"^google_secret_manager_(secret|regional_secret)$"),
  (27, "Cloud Armor security policy fields", r"^google_compute_security_policy(_rule)?$"),
 ],
 "aws": [
  ("F01", "Organizations: SCPs and other policy types, attachment, delegated administrators, features, account placement", r"^aws_organizations_"),
  ("F02", "IAM Identity Center: permission sets and account assignments", r"^aws_ssoadmin_"),
  ("F03", "IAM: SAML providers and access keys", r"^aws_iam_(saml_provider|access_key|virtual_mfa_device|openid_connect_provider)$"),
  ("F04", "EC2 networking: Transit Gateway route tables, associations, propagation, routes, peering", r"^aws_ec2_transit_gateway"),
  ("F05", "EC2 networking: site-to-site VPN and route propagation", r"^aws_(vpn_|customer_gateway)"),
  ("F06", "EC2 networking: network interfaces, block public access, placement groups, CIDR reservations", r"^aws_(network_interface|vpc_block_public_access|placement_group|ec2_subnet_cidr_reservation)"),
  ("F07", "Control Tower: landing zone, controls, baselines", r"^aws_controltower_"),
  ("F08", "Route 53: DNSSEC, query logging, CIDR collections, second-VPC association", r"^aws_route53_(key_signing_key|hosted_zone_dnssec|query_log|cidr_|zone_association|vpc_association)"),
  ("F09", "Route 53 Resolver: DNS Firewall, endpoint settings, configuration", r"^aws_route53_resolver_"),
  ("F10", "CloudTrail: logging and event selectors; organization trails", r"^aws_cloudtrail"),
  ("F11", "ECR: registry policy, scanning, replication, signing", r"^aws_ecr_"),
  ("F12", "Identity Store: users, groups, memberships", r"^aws_identitystore_"),
  ("F13", "Network Manager (Cloud WAN) and Direct Connect", r"^aws_(networkmanager_|dx_)"),
  ("F14", "Config: recorder, delivery channel, rules, aggregators, organization rules", r"^aws_config_"),
  ("F15", "GuardDuty", r"^aws_guardduty_"),
  ("F16", "Security Hub", r"^aws_securityhub_"),
  ("F17", "Secrets Manager: resource policy and rotation", r"^aws_secretsmanager_"),
  ("F18", "Access Analyzer, Macie, Inspector, Detective, Firewall Manager, Audit Manager, Security Lake", r"^aws_(accessanalyzer|macie2|inspector2?|detective|fms|auditmanager|securitylake)_"),
 ],
 "azure": [
  (1, "ManagementGroup, subscription placement, settings", r"^azurerm_management_group($|_subscription_association)"),
  (2, "Subscription tags, billing subscription alias", r"^azurerm_(subscription$|resource_tag$|tags$)"),
  (3, "Policy definitions, initiatives, assignments, exemptions", r"^azurerm_(policy_definition|policy_set_definition|management_group_policy_(set_definition|assignment|exemption)|subscription_policy_(assignment|exemption)|resource_group_policy_(assignment|exemption)|resource_policy_(assignment|exemption))$"),
  (4, "Policy remediation", r"^azurerm_.*policy_remediation$"),
  (5, "PIM eligibility and role management policy", r"^azurerm_(pim_|role_management_policy)"),
  (6, "Budgets and cost exports", r"^azurerm_(consumption_budget_|.*cost_management_export|cost_anomaly_alert)"),
  (7, "Management lock completion", r"^azurerm_(management_lock)$"),
  (8, "VPN connections and local network gateways", r"^azurerm_(virtual_network_gateway_connection|local_network_gateway)$"),
  (9, "ExpressRoute", r"^azurerm_express_route_"),
  (10, "Virtual WAN, hubs, VPN gateways", r"^azurerm_(virtual_wan|virtual_hub|vpn_|point_to_site_vpn)"),
  (11, "Network Manager", r"^azurerm_network_manager"),
  (12, "DNS SOA, IP groups, route filters, service endpoint policies", r"^azurerm_(ip_group|route_filter|subnet_service_endpoint_storage_policy|private_dns_resolver_dns_security|dns_soa)"),
  (13, "Managed HSM, vault access policy, secrets", r"^azurerm_key_vault_(managed_hardware_security_module|access_policy|secret)"),
  (14, "Log Analytics solutions, data sources, clusters", r"^azurerm_(log_analytics_)"),
  (15, "AKS managed namespaces, snapshots, private endpoint connections", r"^azurerm_kubernetes_(cluster_(node_pool|trusted_access|extension)|fleet)"),
  (16, "Flux source control configuration, K8s configuration", r"^azurerm_(kubernetes_flux|arc_kubernetes_flux|kubernetes_cluster_extension)"),
  (17, "Container registry tasks, connected registries", r"^azurerm_container_registry_(task|token|scope_map|agent_pool)"),
  (18, "Monitor: metric alerts, scheduled query rules, DCE, activity log alerts, workbooks", r"^azurerm_(monitor_(metric_alert|scheduled_query_rules|data_collection_endpoint|activity_log_alert)|application_insights_workbook)"),
  (19, "Defender for Storage", r"^azurerm_security_center_storage_defender$"),
  (20, "Defender: pricing, contacts, auto-provisioning, settings", r"^azurerm_security_center_"),
  (21, "Policy attestation", r"^azurerm_.*policy_attestation$"),
  (22, "Sentinel", r"^azurerm_sentinel_"),
  (23, "Defender for Cloud standards, security connectors", r"^azurerm_(security_center_|defender_for_cloud)"),
  (24, "Purview, HSM clusters, DDoS custom policy, security partner provider, CDN WAF", r"^azurerm_(purview_|dedicated_hardware_security_module|network_ddos_protection_plan|cdn_frontdoor_firewall_policy)"),
 ],
}
# Checked by hand against the resource list: where the pattern finds something but
# part of the row is missing (verdict "partial"), or the whole row is (verdict "no").
NOTES = {
    ("gcp", 1): ("yes", "folder, organization and project service identities are google-beta only"),
    ("gcp", 2): ("partial", "regional rules and association yes; packet mirroring rule only for the global network policy (google-beta); none for the regional or hierarchical policy"),
    ("gcp", 3): ("yes", "and Config Connector's IAMCustomRole already takes cnrm.cloud.google.com/organization-id (samples/resources/iamcustomrole/organization-role), so the row may not be a gap"),
    ("gcp", 5): ("yes", "membership RBAC role binding is google-beta only"),
    ("gcp", 22): ("partial", "entitlement and settings; a grant is a runtime request, not a resource"),
    ("gcp", 23): ("partial", "capability, boundary and boundary config; no tag hold resource"),
    ("gcp", 24): ("partial", "Cloud Identity groups, memberships and policy (policy is google-beta only); no SSO profile, assignment or setting"),
    ("aws", "F11"): ("yes", "registry policy, scanning, replication yes; signing configuration not found in the schema"),
    ("azure", 12): ("partial", "IP group, route filter, service endpoint policy yes; no SOA record, no DNS resolver policy"),
    ("azure", 15): ("partial", "node pools, trusted access, fleet yes; no managed namespace or AKS snapshot (azurerm_snapshot is a disk snapshot)"),
    ("azure", 16): ("partial", "Flux configuration yes; no source control configuration or private link scope"),
    ("azure", 21): ("no", "no policy attestation resource"),
    ("azure", 22): ("yes", "Sentinel: 32 resources; not all of the row's items verified one by one"),
}
PROV = {"gcp": "google,google-beta", "aws": "aws", "azure": "azurerm"}

for cloud, rows in ROWS.items():
    tf = {}
    for r in csv.DictReader(open(f"docs/terraform/data/{cloud}.tf-resources.csv")):
        tf.setdefault(r["resource"], set()).add(r["provider"])
    with open("docs/terraform/data/foundation-gaps.csv", "a" if cloud != "gcp" else "w", newline="") as fh:
        w = csv.writer(fh)
        if cloud == "gcp":
            w.writerow(["cloud", "row", "item", "terraform_resources", "provider_only_in", "verdict", "note"])
        for n, item, pat in rows:
            hit = sorted(k for k in tf if re.search(pat, k))
            beta_only = sorted(k for k in hit if tf[k] == {"google-beta"})
            verdict, note = NOTES.get((cloud, n), ("yes" if hit else "no", ""))
            w.writerow([cloud, n, item, " ".join(hit), " ".join(beta_only), verdict, note])
            print(cloud, n, verdict, len(hit), item[:70])
