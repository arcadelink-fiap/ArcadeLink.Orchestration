output "state_bucket_name" {
  description = "Bucket S3 do state remoto das demais stacks"
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_registry" {
  description = "Endereço do registry ECR"
  value       = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR (users, catalog, payments)"
  value       = { for k, r in aws_ecr_repository.service : k => r.repository_url }
}

output "github_actions_role_arn" {
  description = "ARN da role assumida pelo GitHub Actions via OIDC"
  value       = aws_iam_role.github_actions.arn
}
