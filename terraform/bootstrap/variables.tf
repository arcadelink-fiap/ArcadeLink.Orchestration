variable "github_owner" {
  description = "Usuário/organização do GitHub dono dos repositórios ArcadeLink.*"
  type        = string
}

variable "github_owner_id" {
  description = "ID numérico do owner no GitHub (gh api orgs/<owner> -q .id). Obrigatório quando o token OIDC traz o sub com IDs imutáveis (owner@id/repo@id)"
  type        = string
  default     = null
}

variable "budget_email" {
  description = "E-mail que recebe os alertas do AWS Budgets"
  type        = string
}

variable "budget_limit_usd" {
  description = "Limite mensal de custo (USD) do AWS Budget"
  type        = number
  default     = 60
}

variable "create_opensearch_slr" {
  description = "Cria a service-linked role do OpenSearch (false se já existir na conta, pois a criação falha)"
  type        = bool
  default     = true
}
