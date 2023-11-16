locals {
  backbone = {
    aws_east = {
      department                                   = "accounting"
      transit_name                                 = "transit-aws-us-east-1"
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
      department          = "engineering"
      transit_name        = "transit-aws-us-east-2"
      transit_account     = var.aws_account
      transit_cloud       = "aws"
      transit_cidr        = "10.5.0.0/23"
      transit_region_name = "us-east-2"
      transit_asn         = 65105
      transit_ha_gw       = false
      firenet             = false
    },
    azure = {
      department          = "marketing"
      transit_name        = "transit-azure-north-europe"
      transit_account     = var.azure_account
      transit_cloud       = "azure"
      transit_cidr        = "10.2.0.0/23"
      transit_region_name = "North Europe"
      transit_asn         = 65102
      transit_ha_gw       = false
    },
    gcp = {
      department          = "operations"
      transit_name        = "transit-gcp-us-west2"
      transit_account     = var.gcp_account
      transit_cloud       = "gcp"
      transit_cidr        = "10.3.0.0/23"
      transit_region_name = "us-west2"
      transit_asn         = 65103
      transit_ha_gw       = false
    },
  }
}

# https://registry.terraform.io/modules/terraform-aviatrix-modules/mc-transit-deployment-framework/aviatrix/latest
module "backbone" {
  source          = "terraform-aviatrix-modules/backbone/aviatrix"
  version         = "v1.2.2"
  transit_firenet = local.backbone
}

# https://registry.terraform.io/modules/terraform-aviatrix-modules/mc-spoke/aviatrix/latest
module "spoke_1" {
  for_each = local.backbone
  source   = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version  = "1.6.4"

  cloud          = each.value.transit_cloud
  name           = each.key == "azure" ? "spoke-${each.value.department}-all" : "spoke-${each.value.department}-dev"
  cidr           = cidrsubnet("${trimsuffix(each.value.transit_cidr, "23")}16", 8, 2)
  region         = each.value.transit_region_name
  account        = each.value.transit_account
  subnet_pairs   = each.value.transit_cloud == "azure" ? 3 : null
  transit_gw     = module.backbone.transit[each.key].transit_gateway.gw_name
  instance_size  = each.key == "azure" ? "Standard_B2ms" : each.key == "gcp" ? "n1-standard-2" : null
  ha_gw          = false
  attached       = true
  single_ip_snat = true
}

module "spoke_2" {
  for_each = { for k, v in local.backbone : k => v if k != "azure" }
  source   = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version  = "1.6.4"

  cloud          = each.value.transit_cloud
  name           = "spoke-${each.value.department}-qa"
  cidr           = cidrsubnet("${trimsuffix(each.value.transit_cidr, "23")}16", 8, 3)
  region         = each.value.transit_region_name
  account        = each.value.transit_account
  transit_gw     = module.backbone.transit[each.key].transit_gateway.gw_name
  instance_size  = each.key == "azure" ? "Standard_B2ms" : each.key == "gcp" ? "n1-standard-2" : null
  ha_gw          = false
  attached       = true
  single_ip_snat = true
}

module "spoke_3" {
  for_each = { for k, v in local.backbone : k => v if k != "azure" }
  source   = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version  = "1.6.4"

  cloud          = each.value.transit_cloud
  name           = "spoke-${each.value.department}-prod"
  cidr           = cidrsubnet("${trimsuffix(each.value.transit_cidr, "23")}16", 8, 4)
  region         = each.value.transit_region_name
  account        = each.value.transit_account
  transit_gw     = module.backbone.transit[each.key].transit_gateway.gw_name
  instance_size  = each.key == "azure" ? "Standard_B2ms" : each.key == "gcp" ? "n1-standard-2" : null
  ha_gw          = false
  attached       = true
  single_ip_snat = true
}

# Public subnet filter gateway
data "aws_route_table" "spoke_dev_public_1" {
  subnet_id = module.spoke_1["aws_east"].vpc.public_subnets[0].subnet_id
}

data "aws_route_table" "spoke_dev_public_2" {
  subnet_id = module.spoke_1["aws_east"].vpc.public_subnets[1].subnet_id
}

resource "aviatrix_gateway" "psf_aws" {
  cloud_type                                  = 1
  account_name                                = var.aws_account
  gw_name                                     = "psf-aws-us-east-1"
  vpc_id                                      = module.spoke_1["aws_east"].vpc.vpc_id
  vpc_reg                                     = local.backbone.aws_east.transit_region_name
  gw_size                                     = "t3.micro"
  subnet                                      = cidrsubnet("10.1.2.0/24", 2, 1) #cidrsubnet("10.1.3.0/24", 2, 1)
  zone                                        = "${local.backbone.aws_east.transit_region_name}a"
  enable_public_subnet_filtering              = true
  public_subnet_filtering_route_tables        = [data.aws_route_table.spoke_dev_public_1.id, data.aws_route_table.spoke_dev_public_2.id]
  public_subnet_filtering_guard_duty_enforced = true
  single_az_ha                                = true
  enable_encrypt_volume                       = true
  lifecycle {
    ignore_changes = [public_subnet_filtering_route_tables]
  }
}
