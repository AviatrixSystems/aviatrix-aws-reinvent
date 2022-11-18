locals {
  transit_firenet = {
    aws_east = {
      transit_account                              = var.aws_account
      transit_cloud                                = "aws"
      transit_cidr                                 = "10.1.0.0/23"
      transit_region_name                          = "us-east-1"
      transit_asn                                  = 65101
      transit_ha_gw                                = false
      firenet                                      = true
      firenet_firewall_image                       = "Palo Alto Networks VM-Series Next-Generation Firewall (BYOL)"
      firenet_inspection_enabled                   = true
      firenet_keep_alive_via_lan_interface_enabled = true
    },
    aws_east_2 = {
      transit_account        = var.aws_account
      transit_cloud          = "aws"
      transit_cidr           = "10.5.0.0/23"
      transit_region_name    = "us-east-2"
      transit_asn            = 65105
      transit_ha_gw          = false
      firenet                = true
      firenet_firewall_image = "Aviatrix FQDN Egress Filtering"
      firenet_single_ip_snat = true
    },
    azure_germany = {
      transit_account     = var.azure_account
      transit_cloud       = "azure"
      transit_cidr        = "10.2.0.0/23"
      transit_region_name = "Germany West Central"
      transit_asn         = 65102
      transit_ha_gw       = false
    },
    oci_singapore = {
      transit_account     = var.oci_account
      transit_cloud       = "oci"
      transit_cidr        = "10.3.0.0/23"
      transit_region_name = "ap-singapore-1"
      transit_asn         = 65103
      transit_ha_gw       = false
    },
    gcp_west = {
      transit_account     = var.gcp_account
      transit_cloud       = "gcp"
      transit_cidr        = "10.4.0.0/23"
      transit_region_name = "us-west1"
      transit_asn         = 65104
      transit_ha_gw       = false
    },
  }
}

# https://registry.terraform.io/modules/terraform-aviatrix-modules/mc-transit-deployment-framework/aviatrix/latest
module "transit" {
  source          = "terraform-aviatrix-modules/mc-transit-deployment-framework/aviatrix"
  version         = "v1.0.1"
  transit_firenet = local.transit_firenet
}

# https://registry.terraform.io/modules/terraform-aviatrix-modules/mc-spoke/aviatrix/latest
module "spoke_1" {
  for_each   = { for k, v in local.transit_firenet : k => v if k != "aws_east_2" }
  source     = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version    = "1.4.1"
  cloud      = each.value.transit_cloud
  name       = "avx-${replace(lower(each.value.transit_region_name), " ", "-")}-spoke-1"
  cidr       = cidrsubnet("${trimsuffix(each.value.transit_cidr, "23")}16", 8, 2)
  region     = each.value.transit_region_name
  account    = each.value.transit_account
  transit_gw = module.transit.transit[each.key].transit_gateway.gw_name
  ha_gw      = false
  attached   = true
}

module "spoke_2" {
  for_each   = { for k, v in local.transit_firenet : k => v if k != "azure_germany" && k != "aws_east_2" }
  source     = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version    = "1.4.1"
  cloud      = each.value.transit_cloud
  name       = "avx-${replace(lower(each.value.transit_region_name), " ", "-")}-spoke-2"
  cidr       = cidrsubnet("${trimsuffix(each.value.transit_cidr, "23")}16", 8, 3)
  region     = each.value.transit_region_name
  account    = each.value.transit_account
  transit_gw = module.transit.transit[each.key].transit_gateway.gw_name
  ha_gw      = false
  attached   = true
}

module "spoke_3" {
  for_each   = { for k, v in local.transit_firenet : k => v if k != "azure_germany" && k != "aws_east_2" }
  source     = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version    = "1.4.1"
  cloud      = each.value.transit_cloud
  name       = "avx-${replace(lower(each.value.transit_region_name), " ", "-")}-spoke-3"
  cidr       = cidrsubnet("${trimsuffix(each.value.transit_cidr, "23")}16", 8, 4)
  region     = each.value.transit_region_name
  account    = each.value.transit_account
  transit_gw = module.transit.transit[each.key].transit_gateway.gw_name
  ha_gw      = false
  attached   = true
}
