# Task 10: domínio Amazon OpenSearch gerenciado (só existe com enable_opensearch = true).
# Acesso por IAM (SigV4) a partir do pod do Catalog; sem fine-grained access control.

# Domínios dentro de VPC exigem o service-linked role AWSServiceRoleForAmazonOpenSearchService.
# Ele é criado pela stack terraform/bootstrap (aws_iam_service_linked_role.opensearch, create_opensearch_slr = true por padrão).
# Só é preciso criá-lo manualmente se o bootstrap rodou com create_opensearch_slr = false e a role ainda não existe:
#   aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com

locals {
  opensearch_domain_name = "arcadelink-search"
}

resource "aws_security_group" "opensearch" {
  count = var.enable_opensearch ? 1 : 0

  name        = "arcadelink-opensearch"
  description = "HTTPS para o dominio OpenSearch a partir dos nos do EKS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS dos nos e do cluster EKS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      module.eks.node_security_group_id,
      module.eks.cluster_primary_security_group_id,
    ]
  }
}

resource "aws_opensearch_domain" "search" {
  count = var.enable_opensearch ? 1 : 0

  domain_name    = local.opensearch_domain_name
  engine_version = var.opensearch_engine_version

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  # Uma única subnet => um único nó, sem Multi-AZ.
  vpc_options {
    subnet_ids         = [module.vpc.public_subnets[0]]
    security_group_ids = [aws_security_group.opensearch[0].id]
  }

  # t3.small.search suporta criptografia em repouso (apenas a família t2 não suporta).
  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.pod["catalog-api"].arn }
      Action    = "es:ESHttp*"
      Resource  = "arn:aws:es:${var.region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
    }]
  })
}

data "aws_iam_policy_document" "opensearch_catalog" {
  count = var.enable_opensearch ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "es:ESHttpGet",
      "es:ESHttpPut",
      "es:ESHttpPost",
      "es:ESHttpDelete",
      "es:ESHttpHead",
    ]
    resources = [
      aws_opensearch_domain.search[0].arn,
      "${aws_opensearch_domain.search[0].arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "opensearch_catalog" {
  count = var.enable_opensearch ? 1 : 0

  name   = "opensearch"
  role   = aws_iam_role.pod["catalog-api"].id
  policy = data.aws_iam_policy_document.opensearch_catalog[0].json
}
