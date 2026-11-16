# Task 12 (opcional): mensageria AmazonSqs (MassTransit) com SNS -> SQS.
# Os tópicos são criados aqui (e não pelo MassTransit) para que a stack da Lambda os encontre por nome.
locals {
  sns_topic_names = toset([
    "arcadelink-user-created",
    "arcadelink-order-placed",
    "arcadelink-payment-processed",
  ])
}

resource "aws_sns_topic" "events" {
  for_each = var.enable_messaging ? local.sns_topic_names : toset([])

  name = each.key
}

# O MassTransit (AmazonSqs) também cria/assina filas e tópicos por conta própria em runtime,
# por isso as permissões cobrem todos os tópicos/filas da conta nesta região.
data "aws_iam_policy_document" "messaging" {
  count = var.enable_messaging ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:Publish",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:ListTopics",
      "sns:ListSubscriptionsByTopic",
      "sns:TagResource",
    ]
    resources = ["arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:ListQueues",
    ]
    resources = ["arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  # sns:ListTopics e sqs:ListQueues não aceitam restrição por recurso.
  statement {
    effect    = "Allow"
    actions   = ["sns:ListTopics", "sqs:ListQueues"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "messaging" {
  for_each = var.enable_messaging ? local.pod_services : toset([])

  name   = "messaging"
  role   = aws_iam_role.pod[each.key].id
  policy = data.aws_iam_policy_document.messaging[0].json
}
