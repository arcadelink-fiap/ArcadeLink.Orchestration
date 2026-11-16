#!/usr/bin/env bash
# Sobe o ambiente: Terraform (EKS) -> kubeconfig -> namespace -> workflows de deploy.
# Requer GITHUB_OWNER. Opcional: ENABLE_OPENSEARCH=true, AWS_REGION.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform/env"
REGION="${AWS_REGION:-us-east-2}"

if [[ -z "${GITHUB_OWNER:-}" ]]; then
  echo "ERRO: defina GITHUB_OWNER (dono dos repositórios no GitHub)." >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

echo "Inicializando Terraform..."
terraform -chdir="$TF_DIR" init -input=false -backend-config="bucket=arcadelink-tfstate-${ACCOUNT_ID}"

echo "Aplicando Terraform (enable_opensearch=${ENABLE_OPENSEARCH:-false})..."
terraform -chdir="$TF_DIR" apply -auto-approve -var "enable_opensearch=${ENABLE_OPENSEARCH:-false}"

CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"
TF_REGION="$(terraform -chdir="$TF_DIR" output -raw region)"

echo "Atualizando kubeconfig para $CLUSTER_NAME..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "${TF_REGION:-$REGION}"

kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"

if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "AVISO: gh ausente ou não autenticado; pulando disparo dos workflows." >&2
  echo "Dispare manualmente: deploy-platform.yml (Orchestration) e ci-cd.yml (Users, Catalog, Payments)." >&2
  exit 0
fi

echo "Disparando deploy da plataforma..."
gh workflow run deploy-platform.yml -R "$GITHUB_OWNER/ArcadeLink.Orchestration"

for repo in Users Catalog Payments; do
  echo "Disparando ci-cd.yml em ArcadeLink.$repo..."
  gh workflow run ci-cd.yml -R "$GITHUB_OWNER/ArcadeLink.$repo"
done

echo "Ambiente no ar. Acompanhe os workflows com: gh run list -R $GITHUB_OWNER/ArcadeLink.Orchestration"
