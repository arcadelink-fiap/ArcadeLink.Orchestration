#!/usr/bin/env bash
# Cria/atualiza os Secrets do namespace arcadelink a partir de variáveis de ambiente.
# Uso: JWT_KEY=... POSTGRES_PASSWORD=... [OPENSEARCH_ENDPOINT=...] scripts/create-secrets.sh [--restart]
set -euo pipefail

NS="arcadelink"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESTART=false

for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=true ;;
    *) echo "Argumento desconhecido: $arg (use --restart)" >&2; exit 2 ;;
  esac
done

REQUIRED=(JWT_KEY POSTGRES_PASSWORD MONGO_ROOT_PASSWORD REDIS_PASSWORD RABBITMQ_PASSWORD GRAFANA_ADMIN_PASSWORD ADMIN_SEED_EMAIL ADMIN_SEED_PASSWORD)
PASSWORDS=(POSTGRES_PASSWORD MONGO_ROOT_PASSWORD REDIS_PASSWORD RABBITMQ_PASSWORD GRAFANA_ADMIN_PASSWORD)

missing=()
for v in "${REQUIRED[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    missing+=("$v")
  fi
done
if ((${#missing[@]} > 0)); then
  echo "ERRO: variáveis obrigatórias vazias ou ausentes: ${missing[*]}" >&2
  exit 1
fi

if ((${#JWT_KEY} < 32)); then
  echo "ERRO: JWT_KEY deve ter pelo menos 32 caracteres." >&2
  exit 1
fi

bad=()
for v in "${PASSWORDS[@]}"; do
  if [[ ! "${!v}" =~ ^[A-Za-z0-9]+$ ]]; then
    bad+=("$v")
  fi
done
if ((${#bad[@]} > 0)); then
  echo "ERRO: senhas só podem conter [A-Za-z0-9]; inválidas: ${bad[*]}" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERRO: kubectl não encontrado." >&2
  exit 1
fi
if ! command -v envsubst >/dev/null 2>&1; then
  echo "ERRO: envsubst não encontrado (pacote gettext)." >&2
  exit 1
fi

OPENSEARCH_ENDPOINT="${OPENSEARCH_ENDPOINT:-}"
if [[ -z "$OPENSEARCH_ENDPOINT" ]]; then
  if command -v aws >/dev/null 2>&1 &&
    ep="$(aws opensearch describe-domain --domain-name arcadelink-search \
      --query 'DomainStatus.Endpoints.vpc' --output text 2>/dev/null)" &&
    [[ -n "$ep" && "$ep" != "None" ]]; then
    OPENSEARCH_ENDPOINT="https://$ep"
    echo "OpenSearch encontrado: $OPENSEARCH_ENDPOINT"
  else
    echo "AVISO: domínio OpenSearch 'arcadelink-search' não encontrado; seguindo com endpoint vazio (busca desligada)." >&2
    OPENSEARCH_ENDPOINT=""
  fi
fi

# O Catalog monta o cliente com new Uri(...): precisa de URI completa.
if [[ -n "$OPENSEARCH_ENDPOINT" && ! "$OPENSEARCH_ENDPOINT" =~ ^https?:// ]]; then
  OPENSEARCH_ENDPOINT="https://$OPENSEARCH_ENDPOINT"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

apply_secret() {
  local name="$1"
  shift
  kubectl create secret generic "$name" -n "$NS" "$@" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "Secret aplicado: $name"
}

PG_BASE="Host=postgres;Port=5432;Username=postgres;Password=${POSTGRES_PASSWORD}"
REDIS_CS="redis:6379,password=${REDIS_PASSWORD},abortConnect=false"
MONGO_CS="mongodb://arcadelink:${MONGO_ROOT_PASSWORD}@mongodb:27017/?authSource=admin"

apply_secret postgres-secret --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
apply_secret mongodb-secret \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=arcadelink \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD"
apply_secret redis-secret --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD"
apply_secret rabbitmq-secret \
  --from-literal=RABBITMQ_DEFAULT_USER=arcadelink \
  --from-literal=RABBITMQ_DEFAULT_PASS="$RABBITMQ_PASSWORD"
apply_secret grafana-secret --from-literal=GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD"

# shellcheck disable=SC2016 # envsubst precisa do literal ${JWT_KEY}
JWT_KEY="$JWT_KEY" envsubst '${JWT_KEY}' <"$ROOT_DIR/k8s/kong/kong.yml.tpl" >"$TMP_DIR/kong.yml"
apply_secret kong-declarative-config --from-file=kong.yml="$TMP_DIR/kong.yml"

apply_secret users-api-secret \
  --from-literal=ConnectionStrings__Postgres="${PG_BASE};Database=arcadelink_users" \
  --from-literal=Jwt__Key="$JWT_KEY" \
  --from-literal=RabbitMq__Username=arcadelink \
  --from-literal=RabbitMq__Password="$RABBITMQ_PASSWORD" \
  --from-literal=Redis__ConnectionString="$REDIS_CS" \
  --from-literal=AdminSeed__Email="$ADMIN_SEED_EMAIL" \
  --from-literal=AdminSeed__Password="$ADMIN_SEED_PASSWORD"

apply_secret catalog-api-secret \
  --from-literal=ConnectionStrings__Postgres="${PG_BASE};Database=arcadelink_catalog" \
  --from-literal=RabbitMq__Username=arcadelink \
  --from-literal=RabbitMq__Password="$RABBITMQ_PASSWORD" \
  --from-literal=Redis__ConnectionString="$REDIS_CS" \
  --from-literal=Mongo__ConnectionString="$MONGO_CS" \
  --from-literal=Search__Endpoint="$OPENSEARCH_ENDPOINT"

apply_secret payments-api-secret \
  --from-literal=RabbitMq__Username=arcadelink \
  --from-literal=RabbitMq__Password="$RABBITMQ_PASSWORD" \
  --from-literal=Redis__ConnectionString="$REDIS_CS"

if $RESTART; then
  echo "Reiniciando Deployments e StatefulSets do namespace $NS..."
  kubectl get deployments,statefulsets -n "$NS" -o name | while read -r res; do
    kubectl rollout restart "$res" -n "$NS"
  done
fi

echo "Secrets criados/atualizados no namespace $NS."
