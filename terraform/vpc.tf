data "aws_availability_zones" "main" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.0"

  name = local.environment

  azs                                             = local.availability_zones
  cidr                                            = var.vpc_cidr
  create_database_subnet_group                    = var.create_database_subnet_group
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_log
  create_flow_log_cloudwatch_log_group            = var.enable_flow_log
  database_subnet_group_name                      = var.create_database_subnet_group ? local.environment : null
  database_subnets                                = var.create_database_subnet_group ? local.database_subnets : []
  enable_dhcp_options                             = true
  enable_dns_hostnames                            = true
  enable_dns_support                              = true
  enable_flow_log                                 = var.enable_flow_log
  enable_nat_gateway                              = true
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days
  flow_log_max_aggregation_interval               = 60
  one_nat_gateway_per_az                          = var.vpc_redundancy

  private_subnet_suffix = "private"
  private_subnets       = local.private_subnets
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${local.environment}"    = "shared"
  }

  public_subnets = local.public_subnets
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.environment}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  }

  single_nat_gateway = !var.vpc_redundancy

  tags = var.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.6.0"

  vpc_id = module.vpc.vpc_id
  tags   = var.tags

  endpoints = {
    s3 = {
      route_table_ids = local.vpc_route_tables
      service         = "s3"
      service_type    = "Gateway"
      tags            = { Name = "${local.environment}-s3-vpc-endpoint" }
    }
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.environment}-ecr-api-vpc-endpoint" }
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.environment}-ecr-dkr-vpc-endpoint" }
    }
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.environment}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.environment}-vpc-endpoints"
  })

  lifecycle {
    create_before_destroy = true
  }
}