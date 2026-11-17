terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # O bucket (arcadelink-tfstate-<account_id>) é passado via
  # `terraform init -backend-config="bucket=..."` no up.sh, para não versionar o account id.
  backend "s3" {
    key          = "env/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
    encrypt      = true
  }
}

# Módulos fixados na major mais recente do registry (2026-11-11):
#   terraform-aws-modules/vpc/aws -> ~> 6.0 (6.7.3)
#   terraform-aws-modules/eks/aws -> ~> 21.0 (21.29.0)

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "arcadelink"
      ManagedBy = "terraform"
      Stack     = "env"
    }
  }
}

data "aws_caller_identity" "current" {}
