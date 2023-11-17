data "aws_caller_identity" "current" {}

# CloudWAN Vpcs
module "finance_dev_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name               = "spoke-finance-dev"
  cidr               = "10.4.2.0/24"
  enable_nat_gateway = true

  azs             = ["${local.backbone.aws_east.transit_region_name}a", "${local.backbone.aws_east.transit_region_name}b"]
  public_subnets  = [cidrsubnet("10.4.2.0/24", 4, 0), cidrsubnet("10.4.2.0/24", 4, 1)]
  private_subnets = [cidrsubnet("10.4.2.0/24", 4, 2), cidrsubnet("10.4.2.0/24", 4, 3)]
}

module "finance_prod_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name               = "spoke-finance-prod"
  cidr               = "10.4.4.0/24"
  enable_nat_gateway = true

  azs             = ["${local.backbone.aws_east.transit_region_name}a", "${local.backbone.aws_east.transit_region_name}b"]
  public_subnets  = [cidrsubnet("10.4.4.0/24", 4, 0), cidrsubnet("10.4.4.0/24", 4, 1)]
  private_subnets = [cidrsubnet("10.4.4.0/24", 4, 2), cidrsubnet("10.4.4.0/24", 4, 3)]
}

# CloudWAN
data "aws_networkmanager_core_network_policy_document" "default_policy" {
  core_network_configuration {
    vpn_ecmp_support   = false
    asn_ranges         = ["64512-64520"]
    inside_cidr_blocks = ["10.71.0.0/24"]
    edge_locations {
      location = local.backbone.aws_east.transit_region_name
      asn      = 64512
    }
  }

  segments {
    name                          = "dev"
    description                   = "dev"
    require_attachment_acceptance = false
  }

  segments {
    name                          = "prod"
    description                   = "prod"
    require_attachment_acceptance = false
  }

  attachment_policies {
    rule_number     = 100
    condition_logic = "or"

    conditions {
      type     = "tag-value"
      operator = "equals"
      key      = "env"
      value    = "dev"
    }
    action {
      association_method = "constant"
      segment            = "dev"
    }
  }
  attachment_policies {
    rule_number     = 200
    condition_logic = "or"

    conditions {
      type     = "tag-value"
      operator = "equals"
      key      = "env"
      value    = "prod"
    }
    action {
      association_method = "constant"
      segment            = "prod"
    }
  }
}

module "cloudwan" {
  source  = "aws-ia/cloudwan/aws"
  version = "2.0.0"

  global_network = {
    create      = true
    description = "global network"
  }
  core_network = {
    description     = "core network"
    policy_document = data.aws_networkmanager_core_network_policy_document.default_policy.json
  }

  tags = {
    Name = "global-network"
  }
  providers = {
    aws = aws
  }
}

resource "aws_networkmanager_vpc_attachment" "avx_transit" {
  subnet_arns = [
    element([for subnet_id in module.backbone.transit["aws_east"].vpc.subnets[*].subnet_id : "arn:aws:ec2:${local.backbone.aws_east.transit_region_name}:${data.aws_caller_identity.current.account_id}:subnet/${subnet_id}"], 1),
    element([for subnet_id in module.backbone.transit["aws_east"].vpc.subnets[*].subnet_id : "arn:aws:ec2:${local.backbone.aws_east.transit_region_name}:${data.aws_caller_identity.current.account_id}:subnet/${subnet_id}"], 3),
  ]
  core_network_id = module.cloudwan.core_network.id
  vpc_arn         = "arn:aws:ec2:${local.backbone.aws_east.transit_region_name}:${data.aws_caller_identity.current.account_id}:vpc/${module.backbone.transit["aws_east"].vpc.vpc_id}"
  tags = {
    env  = "avx"
    Name = module.backbone.transit["aws_east"].transit_gateway.gw_name
  }
  depends_on = [module.cloudwan]
}

resource "aws_networkmanager_vpc_attachment" "dev" {
  subnet_arns     = module.finance_dev_vpc.private_subnet_arns
  core_network_id = module.cloudwan.core_network.id
  vpc_arn         = module.finance_dev_vpc.vpc_arn
  tags = {
    Department = "finance"
    env        = "dev"
    Name       = module.finance_dev_vpc.name
  }
  depends_on = [module.cloudwan]
}

resource "aws_networkmanager_vpc_attachment" "prod" {
  subnet_arns     = module.finance_prod_vpc.private_subnet_arns
  core_network_id = module.cloudwan.core_network.id
  vpc_arn         = module.finance_prod_vpc.vpc_arn
  tags = {
    Department = "finance"
    env        = "prod"
    Name       = module.finance_prod_vpc.name
  }
  depends_on = [module.cloudwan]
}

resource "aws_networkmanager_connect_attachment" "avx_transit_dev" {
  core_network_id         = module.cloudwan.core_network.id
  transport_attachment_id = aws_networkmanager_vpc_attachment.avx_transit.id
  edge_location           = aws_networkmanager_vpc_attachment.avx_transit.edge_location
  options {
    protocol = "GRE"
  }
  tags = {
    Department = "finance"
    env        = "dev"
    Name       = "${module.backbone.transit["aws_east"].transit_gateway.gw_name}-dev"
  }
}

resource "aws_networkmanager_connect_attachment" "avx_transit_prod" {
  core_network_id         = module.cloudwan.core_network.id
  transport_attachment_id = aws_networkmanager_vpc_attachment.avx_transit.id
  edge_location           = aws_networkmanager_vpc_attachment.avx_transit.edge_location
  options {
    protocol = "GRE"
  }
  tags = {
    Department = "finance"
    env        = "prod"
    Name       = "${module.backbone.transit["aws_east"].transit_gateway.gw_name}-prod"
  }
}

resource "aws_networkmanager_connect_peer" "avx_transit_dev" {
  connect_attachment_id = aws_networkmanager_connect_attachment.avx_transit_dev.id
  peer_address          = module.backbone.transit["aws_east"].transit_gateway.private_ip
  bgp_options {
    peer_asn = 65101
  }
  inside_cidr_blocks = ["169.254.101.0/29"]
  tags = {
    env  = "dev"
    Name = module.finance_dev_vpc.name
  }
}

resource "aws_networkmanager_connect_peer" "avx_transit_prod" {
  connect_attachment_id = aws_networkmanager_connect_attachment.avx_transit_prod.id
  peer_address          = module.backbone.transit["aws_east"].transit_gateway.private_ip
  bgp_options {
    peer_asn = 65101
  }
  inside_cidr_blocks = ["169.254.101.8/29"]
  tags = {
    env  = "prod"
    Name = module.finance_prod_vpc.name
  }
}

resource "aviatrix_transit_external_device_conn" "cloudwan_dev" {
  vpc_id             = module.backbone.transit["aws_east"].vpc.vpc_id
  connection_name    = "finance-dev"
  gw_name            = module.backbone.transit["aws_east"].transit_gateway.gw_name
  connection_type    = "bgp"
  bgp_local_as_num   = "65101"
  bgp_remote_as_num  = "64512"
  remote_gateway_ip  = aws_networkmanager_connect_peer.avx_transit_dev.configuration[0].core_network_address
  tunnel_protocol    = "GRE"
  local_tunnel_cidr  = "169.254.101.1/29"
  remote_tunnel_cidr = "169.254.101.2/29"
  enable_jumbo_frame = false
}

resource "aviatrix_transit_external_device_conn" "cloudwan_prod" {
  vpc_id             = module.backbone.transit["aws_east"].vpc.vpc_id
  connection_name    = "finance-prod"
  gw_name            = module.backbone.transit["aws_east"].transit_gateway.gw_name
  connection_type    = "bgp"
  bgp_local_as_num   = "65101"
  bgp_remote_as_num  = "64512"
  remote_gateway_ip  = aws_networkmanager_connect_peer.avx_transit_prod.configuration[0].core_network_address
  tunnel_protocol    = "GRE"
  local_tunnel_cidr  = "169.254.101.9/29"
  remote_tunnel_cidr = "169.254.101.10/29"
  enable_jumbo_frame = false
}

# Routes
resource "aws_route" "avx_transit" {
  count                  = 3
  route_table_id         = module.backbone.transit["aws_east"].vpc.route_tables[count.index]
  destination_cidr_block = "10.71.0.0/24"
  core_network_arn       = module.cloudwan.core_network.arn
  depends_on             = [module.cloudwan, module.backbone]
}

resource "aws_route" "finance_dev" {
  count                  = 2
  route_table_id         = module.finance_dev_vpc.private_route_table_ids[count.index]
  destination_cidr_block = "10.0.0.0/8"
  core_network_arn       = module.cloudwan.core_network.arn
  depends_on             = [module.cloudwan, module.finance_dev_vpc]
}

resource "aws_route" "finance_prod" {
  count                  = 2
  route_table_id         = module.finance_prod_vpc.private_route_table_ids[count.index]
  destination_cidr_block = "10.0.0.0/8"
  core_network_arn       = module.cloudwan.core_network.arn
  depends_on             = [module.cloudwan, module.finance_prod_vpc]
}
