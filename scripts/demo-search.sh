#!/usr/bin/env bash
# Demo da busca (OpenSearch): cria jogos de seed (se faltarem), reindexa e roda buscas com erro de digitação.
# Uso: scripts/demo-search.sh <kong-host> <admin-email> <admin-password>
# Requer: curl e jq.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Uso: $0 <kong-host> <admin-email> <admin-password>" >&2
  exit 1
fi
HOST="$1"; EMAIL="$2"; PASSWORD="$3"
BASE="http://${HOST}"

command -v jq >/dev/null || { echo "jq é necessário." >&2; exit 1; }

echo "Autenticando como ${EMAIL}..."
TOKEN="$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}' \
  | curl -fsS -X POST "${BASE}/auth/login" -H 'Content-Type: application/json' -d @- \
  | jq -r '.token')"
[[ -n "$TOKEN" && "$TOKEN" != "null" ]] || { echo "Falha no login." >&2; exit 1; }

# título|gênero|preço|tags (separadas por vírgula)
SEEDS=(
  "The Legend of Zelda: Breath of the Wild|Aventura|59.90|aventura,mundo aberto,fantasia"
  "Hollow Knight|Metroidvania|27.99|metroidvania,plataforma,dificil"
  "Celeste|Plataforma|36.99|plataforma,indie,dificil"
  "Hades|Roguelike|47.99|roguelike,acao,mitologia"
  "Stardew Valley|Simulacao|24.99|fazenda,relaxante,indie"
  "Super Metroid|Metroidvania|19.99|metroidvania,classico,exploracao"
  "Dark Souls|RPG|39.99|rpg,dificil,soulslike"
  "Portal 2|Puzzle|19.99|puzzle,cooperativo,fisica"
)

EXISTING="$(curl -fsS "${BASE}/games" | jq -r '.[].title')"

for seed in "${SEEDS[@]}"; do
  IFS='|' read -r title genre price tags <<<"$seed"
  if grep -Fxq -- "$title" <<<"$EXISTING"; then
    echo "Já existe: ${title}"
    continue
  fi
  body="$(jq -n --arg t "$title" --arg g "$genre" --argjson p "$price" --arg tags "$tags" \
    '{title:$t, description:("Jogo de seed: " + $t), genre:$g, price:$p,
      richDescription:("Descrição detalhada de " + $t), tags:($tags|split(",")), screenshots:[]}')"
  curl -fsS -X POST "${BASE}/games" -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' -d "$body" >/dev/null
  echo "Criado: ${title}"
done

echo "Reindexando..."
curl -fsS -X POST "${BASE}/admin/search/reindex" -H "Authorization: Bearer ${TOKEN}" | jq -c .

for q in "zeldda" "holow nite" "celest"; do
  echo
  echo "Busca: \"${q}\""
  curl -fsS -G "${BASE}/search" --data-urlencode "q=${q}" \
    | jq -r '"  total: \(.total)", (.hits[] | "  \(.title)  (score \(.score))")'
done
