#!/usr/bin/env bash
# Demo do cache Redis em GET /games: compara MISS (1ª chamada) com HITs.
# Uso: scripts/demo-cache.sh <kong-host> [n=50] [admin-email admin-password]
#   Sem credenciais: se a 1ª chamada não for MISS (cache ainda válido, TTL de 60 s), aguarda 61 s e repete.
#   Com credenciais: faz um PUT no primeiro jogo (mesmos dados) para invalidar o cache antes de medir.
# Requer: curl e jq (jq só para o PUT opcional).
set -euo pipefail

if [[ $# -lt 1 || $# -eq 3 || $# -gt 4 ]]; then
  echo "Uso: $0 <kong-host> [n=50] [admin-email admin-password]" >&2
  exit 1
fi
HOST="$1"; N="${2:-50}"; EMAIL="${3:-}"; PASSWORD="${4:-}"
BASE="http://${HOST}"
[[ "$N" =~ ^[0-9]+$ && "$N" -ge 2 ]] || { echo "n deve ser um inteiro >= 2." >&2; exit 1; }

timed_get() { # imprime "<tempo_total_s> <X-Cache> <tempo_api_ms>" (tempo_api = X-Kong-Upstream-Latency)
  local out t hdr
  out="$(curl -sS -o /dev/null -D - -w 'TIME:%{time_total}\n' "${BASE}/games")"
  t="$(sed -n 's/^TIME://p' <<<"$out")"
  hdr="$(tr -d '\r' <<<"$out")"
  printf '%s %s %s\n' "$t" \
    "$(awk -F': ' 'tolower($1)=="x-cache"{print $2}' <<<"$hdr")" \
    "$(awk -F': ' 'tolower($1)=="x-kong-upstream-latency"{print $2}' <<<"$hdr")"
}

if [[ -n "$EMAIL" ]]; then
  echo "Invalidando o cache via PUT..."
  TOKEN="$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}' \
    | curl -fsS -X POST "${BASE}/auth/login" -H 'Content-Type: application/json' -d @- | jq -r '.token')"
  GAME="$(curl -fsS "${BASE}/games" | jq -c '.[0]')"
  [[ "$GAME" != "null" && -n "$GAME" ]] || { echo "Nenhum jogo cadastrado para o PUT." >&2; exit 1; }
  ID="$(jq -r '.id' <<<"$GAME")"
  jq '{title,description,genre,price,richDescription,tags,screenshots}' <<<"$GAME" \
    | curl -fsS -X PUT "${BASE}/games/${ID}" -H "Authorization: Bearer ${TOKEN}" \
        -H 'Content-Type: application/json' -d @- >/dev/null
fi

read -r first_t first_c first_api < <(timed_get)
if [[ "$first_c" != "MISS" && -z "$EMAIL" ]]; then
  echo "1ª chamada foi ${first_c:-sem header}; aguardando 61 s para o cache expirar..."
  sleep 61
  read -r first_t first_c first_api < <(timed_get)
fi
printf '1ª chamada: %s s total | API: %s ms (X-Cache: %s)\n' "$first_t" "${first_api:-?}" "${first_c:-?}"

times=()
apis=()
for _ in $(seq 2 "$N"); do
  read -r t c api < <(timed_get)
  if [[ "$c" == "HIT" ]]; then
    times+=("$t")
    [[ -n "$api" ]] && apis+=("$api")
  fi
done

if [[ ${#times[@]} -eq 0 ]]; then
  echo "Nenhum HIT observado (Redis indisponível?)." >&2
  exit 1
fi
printf '%s\n' "${times[@]}" | sort -n | awk -v total="$((N-1))" '
  { v[NR]=$1; s+=$1 }
  END {
    i=int(NR*0.95); if (i<NR*0.95) i++; if (i<1) i=1
    printf "HITs: %d de %d | média: %.4f s | p95: %.4f s (total, inclui a rede)\n", NR, total, s/NR, v[i]
  }'
if [[ ${#apis[@]} -gt 0 ]]; then
  printf '%s\n' "${apis[@]}" | awk -v miss="${first_api:-}" '
    { s+=$1 }
    END {
      printf "Tempo da API (X-Kong-Upstream-Latency): MISS %s ms | HIT média %.1f ms\n", (miss==""?"?":miss), s/NR
    }'
fi
