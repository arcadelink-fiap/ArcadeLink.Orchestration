output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}

output "pod_role_arns" {
  description = "ARN da role de pod por serviço (users-api, catalog-api, payments-api)."
  value       = { for k, r in aws_iam_role.pod : k => r.arn }
}

output "sns_topic_arns" {
  description = "ARN dos tópicos SNS por nome (vazio quando enable_messaging = false)."
  value       = { for k, t in aws_sns_topic.events : k => t.arn }
}

output "opensearch_endpoint" {
  description = "Endpoint (host) do domínio OpenSearch; vazio quando enable_opensearch = false."
  value       = try(aws_opensearch_domain.search[0].endpoint, "")
}
