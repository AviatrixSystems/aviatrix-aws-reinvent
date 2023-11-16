# Network domains
resource "aviatrix_segmentation_network_domain" "dev" {
  domain_name = "Dev"
}

resource "aviatrix_segmentation_network_domain" "qa" {
  domain_name = "QA"
}

resource "aviatrix_segmentation_network_domain" "prod" {
  domain_name = "Prod"
}

resource "aviatrix_segmentation_network_domain" "azure" {
  domain_name = "Azure"
}

resource "aviatrix_segmentation_network_domain" "edge" {
  domain_name = "Edge"
}

# Connections policies
resource "aviatrix_segmentation_network_domain_connection_policy" "edge_dev" {
  domain_name_1 = aviatrix_segmentation_network_domain.edge.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.dev.domain_name
}

resource "aviatrix_segmentation_network_domain_connection_policy" "edge_qa" {
  domain_name_1 = aviatrix_segmentation_network_domain.edge.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.qa.domain_name
}

resource "aviatrix_segmentation_network_domain_connection_policy" "edge_prod" {
  domain_name_1 = aviatrix_segmentation_network_domain.edge.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.prod.domain_name
}

resource "aviatrix_segmentation_network_domain_connection_policy" "azure_edge" {
  domain_name_1 = aviatrix_segmentation_network_domain.azure.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.edge.domain_name
}

resource "aviatrix_segmentation_network_domain_connection_policy" "azure_dev" {
  domain_name_1 = aviatrix_segmentation_network_domain.azure.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.dev.domain_name
}

resource "aviatrix_segmentation_network_domain_connection_policy" "azure_qa" {
  domain_name_1 = aviatrix_segmentation_network_domain.azure.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.qa.domain_name
}

resource "aviatrix_segmentation_network_domain_connection_policy" "azure_prod" {
  domain_name_1 = aviatrix_segmentation_network_domain.azure.domain_name
  domain_name_2 = aviatrix_segmentation_network_domain.prod.domain_name
}

# Associations
resource "aviatrix_segmentation_network_domain_association" "azure" {
  transit_gateway_name = module.backbone.transit["azure"].transit_gateway.gw_name
  network_domain_name  = aviatrix_segmentation_network_domain.azure.domain_name
  attachment_name      = module.spoke_1["azure"].spoke_gateway.gw_name
}

resource "aviatrix_segmentation_network_domain_association" "dev" {
  for_each             = { for k, v in local.backbone : k => v if k != "azure" }
  transit_gateway_name = module.backbone.transit[each.key].transit_gateway.gw_name
  network_domain_name  = aviatrix_segmentation_network_domain.dev.domain_name
  attachment_name      = module.spoke_1[each.key].spoke_gateway.gw_name
}

resource "aviatrix_segmentation_network_domain_association" "qa" {
  for_each             = { for k, v in local.backbone : k => v if k != "azure" }
  transit_gateway_name = module.backbone.transit[each.key].transit_gateway.gw_name
  network_domain_name  = aviatrix_segmentation_network_domain.qa.domain_name
  attachment_name      = module.spoke_2[each.key].spoke_gateway.gw_name
}

resource "aviatrix_segmentation_network_domain_association" "prod" {
  for_each             = { for k, v in local.backbone : k => v if k != "azure" }
  transit_gateway_name = module.backbone.transit[each.key].transit_gateway.gw_name
  network_domain_name  = aviatrix_segmentation_network_domain.prod.domain_name
  attachment_name      = module.spoke_3[each.key].spoke_gateway.gw_name
}

resource "aviatrix_segmentation_network_domain_association" "finance_dev" {
  transit_gateway_name = module.backbone.transit["aws_east"].transit_gateway.gw_name
  network_domain_name  = aviatrix_segmentation_network_domain.dev.domain_name
  attachment_name      = aviatrix_transit_external_device_conn.cloudwan_dev.connection_name
}

resource "aviatrix_segmentation_network_domain_association" "finance_prod" {
  transit_gateway_name = module.backbone.transit["aws_east"].transit_gateway.gw_name
  network_domain_name  = aviatrix_segmentation_network_domain.prod.domain_name
  attachment_name      = aviatrix_transit_external_device_conn.cloudwan_prod.connection_name
}
