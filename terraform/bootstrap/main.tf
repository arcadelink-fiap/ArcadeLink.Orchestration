data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.region
  ecr_services    = toset(["users", "catalog", "payments"])
  cluster_name    = "arcadelink-eks"
  opensearch_name = "arcadelink-search"
}

# ---------------------------------------------------------------------------
# S3: state remoto das demais stacks
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket        = "arcadelink-tfstate-${local.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "service" {
  for_each = local.ecr_services

  name                 = "arcadelink/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter as 10 imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# GitHub Actions via OIDC
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/ArcadeLink.*:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "arcadelink-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for r in aws_ecr_repository.service : r.arn]
  }

  statement {
    sid       = "EksDescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${local.region}:${local.account_id}:cluster/${local.cluster_name}"]
  }

  statement {
    sid       = "OpenSearchDescribeDomain"
    actions   = ["es:DescribeDomain"]
    resources = ["arn:aws:es:${local.region}:${local.account_id}:domain/${local.opensearch_name}"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "arcadelink-github-actions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}

# ---------------------------------------------------------------------------
# OpenSearch service-linked role (necessária para domínio dentro da VPC)
# ---------------------------------------------------------------------------
resource "aws_iam_service_linked_role" "opensearch" {
  count = var.create_opensearch_slr ? 1 : 0

  aws_service_name = "opensearchservice.amazonaws.com"
}

# ---------------------------------------------------------------------------
# AWS Budgets
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "arcadelink-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
