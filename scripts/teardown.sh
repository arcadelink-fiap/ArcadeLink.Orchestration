#!/usr/bin/env bash
# Destrói o ambiente: remove recursos criados pelo Kubernetes (NLB, EBS), depois terraform destroy.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform/env"
TIMEOUT_SECONDS=600
REGION="${AWS_REGION:-us-east-2}"

list_lbs() {
  # O cloud provider in-tree nomeia o NLB como a<uid>; a busca é pela tag do Service.
  aws resourcegroupstaggingapi get-resources --region "$REGION" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --tag-filters Key=kubernetes.io/service-name,Values=arcadelink/kong \
    --query 'ResourceTagMappingList[].ResourceARN' --output text
}
list_volumes() {
  aws ec2 describe-volumes --region "$REGION" --filters Name=tag:kubernetes.io/created-for/pvc/namespace,Values=arcadelink \
    --query 'Volumes[].VolumeId' --output text
}

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
echo "Inicializando terraform (bucket arcadelink-tfstate-$ACCOUNT)..."
terraform -chdir="$TF_DIR" init -input=false -backend-config="bucket=arcadelink-tfstate-$ACCOUNT"

cluster_ok=false
if aws eks describe-cluster --name arcadelink-eks --region "$REGION" >/dev/null 2>&1; then
  if aws eks update-kubeconfig --name arcadelink-eks --region "$REGION" >/dev/null; then
    cluster_ok=true
  fi
fi

if [[ "$cluster_ok" == true ]]; then
  KCTX="$(kubectl config current-context)"
  echo "Removendo namespace arcadelink no contexto $KCTX (NLB e volumes EBS)..."
  if kubectl --context "$KCTX" delete namespace arcadelink --wait=true --timeout=10m --ignore-not-found; then
    echo "Aguardando NLBs e volumes EBS sumirem..."
    deadline=$((SECONDS + TIMEOUT_SECONDS))
    while true; do
      lbs="$(list_lbs)"
      vols="$(list_volumes)"
      if [[ -z "${lbs//[[:space:]]/}" && -z "${vols//[[:space:]]/}" ]]; then
        break
      fi
      if ((SECONDS >= deadline)); then
        echo "ERRO: timeout aguardando remoção. Sobraram:" >&2
        echo "  Load balancers: ${lbs:-nenhum}" >&2
        echo "  Volumes: ${vols:-nenhum}" >&2
        exit 1
      fi
      sleep 15
    done
  else
    echo "AVISO: falha ao remover o namespace via kubectl; seguindo para o terraform destroy." >&2
  fi
else
  echo "AVISO: cluster arcadelink-eks não encontrado (ou kubeconfig falhou); pulando a limpeza via kubectl e seguindo para o terraform destroy." >&2
fi

echo "Executando terraform destroy..."
terraform -chdir="$TF_DIR" destroy -auto-approve

lbs="$(list_lbs)"
vols="$(list_volumes)"
if [[ -z "${lbs//[[:space:]]/}" && -z "${vols//[[:space:]]/}" ]]; then
  echo "Nada sobrando."
else
  echo "ATENÇÃO: sobraram recursos:"
  echo "  Load balancers: ${lbs:-nenhum}"
  echo "  Volumes: ${vols:-nenhum}"
fi

# Roles com nome fixo bloqueiam o próximo 'up' se ficarem para trás.
roles="$(aws iam list-roles --query "Roles[?starts_with(RoleName, 'arcadelink-') && RoleName != 'arcadelink-github-actions' && RoleName != 'arcadelink-notifications-lambda'].RoleName" --output text || true)"
if [[ -n "${roles//[[:space:]]/}" ]]; then
  echo "AVISO: IAM roles arcadelink-* ainda existem e podem bloquear o próximo 'up': $roles (a role da Lambda opcional, arcadelink-notifications-lambda, é esperada se a stack da Lambda foi mantida e não é listada aqui)" >&2
fi
