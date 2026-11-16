terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Backend local: esta stack é quem cria o bucket de state das demais.
  # O terraform.tfstate fica gitignored e precisa ser guardado pelo usuário.
  backend "local" {}
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Project   = "arcadelink"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
