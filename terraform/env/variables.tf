variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
  default     = "arcadelink-eks"
}

# verificar standard support antes do apply (extended support custa 6x)
variable "cluster_version" {
  description = "Versão do Kubernetes no EKS: a mais recente em standard support no dia do apply."
  type        = string
  default     = "1.35"
}

variable "github_actions_role_arn" {
  description = "ARN da role do GitHub Actions (output github_actions_role_arn da stack bootstrap)."
  type        = string
}

variable "enable_opensearch" {
  description = "Cria o domínio OpenSearch gerenciado (Task 10)."
  type        = bool
  default     = false
}

variable "opensearch_engine_version" {
  description = "Versão do engine OpenSearch. VERIFICAR a mais recente OpenSearch_2.x suportada (aws opensearch list-versions) antes do apply."
  type        = string
  default     = "OpenSearch_2.19"
}

variable "enable_messaging" {
  description = "Cria os tópicos SNS e as políticas de mensageria das roles de pod (Task 12). A fila SQS e a Lambda ficam na stack ArcadeLink.NotificationsFunction/terraform."
  type        = bool
  default     = false
}
