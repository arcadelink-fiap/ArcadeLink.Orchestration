data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Só subnets públicas e sem NAT Gateway (custo): os nodes recebem IP público.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "arcadelink"
  cidr = "10.40.0.0/16"

  azs             = local.azs
  public_subnets  = ["10.40.0.0/20", "10.40.16.0/20"]
  private_subnets = []

  enable_nat_gateway      = false
  map_public_ip_on_launch = true
  enable_dns_hostnames    = true
  enable_dns_support      = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
