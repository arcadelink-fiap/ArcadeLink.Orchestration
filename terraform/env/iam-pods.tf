# Uma role por serviço: um ServiceAccount aceita uma única association no Pod Identity,
# então as políticas das Tasks 10 e 12 se somam na role de cada serviço.
locals {
  pod_services = toset(["users-api", "catalog-api", "payments-api"])
}

resource "aws_iam_role" "pod" {
  for_each = local.pod_services

  name = "arcadelink-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "pod" {
  for_each = local.pod_services

  cluster_name    = module.eks.cluster_name
  namespace       = "arcadelink"
  service_account = each.key
  role_arn        = aws_iam_role.pod[each.key].arn
}
