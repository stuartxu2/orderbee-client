#!/usr/bin/env bash
# OrderBee CLI helper. Needs: curl, jq, ORDERBEE_BASE_URL, ORDERBEE_API_KEY.
set -euo pipefail

: "${ORDERBEE_BASE_URL:?set ORDERBEE_BASE_URL}"
: "${ORDERBEE_API_KEY:?set ORDERBEE_API_KEY}"

req() { # method path [json-body] [extra-header]
  local method=$1 path=$2 body=${3:-} extra=${4:-}
  local args=(-sS -X "$method" -H "Authorization: Bearer $ORDERBEE_API_KEY" -H "content-type: application/json")
  [[ -n $body ]] && args+=(-d "$body")
  [[ -n $extra ]] && args+=(-H "$extra")
  curl "${args[@]}" "$ORDERBEE_BASE_URL$path"
}

cmd=${1:-help}; shift || true
case "$cmd" in
  restaurants) req GET /restaurants | jq ;;
  menu)        req GET "/restaurants/$1/menu" | jq ;;
  quote)       # quote <restaurant_id> <item_id>:<qty> [<item_id>:<qty> ...]
    rid=$1; shift
    items=$(printf '%s\n' "$@" | jq -R 'split(":") | {item_id: .[0], quantity: (.[1] // "1" | tonumber)}' | jq -s .)
    req POST /orders/quote "{\"restaurant_id\":\"$rid\",\"items\":$items}" | jq ;;
  # NOTE: fresh uuid per run — first attempts only; retries must reuse the original key via the API
  confirm)     req POST "/orders/$1/confirm" '' "Idempotency-Key: $(uuidgen)" | jq ;;
  status)      req GET "/orders/$1" | jq '{state, quote, tracking_url, timeline}' ;;
  watch)       while sleep 10; do s=$(req GET "/orders/$1" | jq -r .state); echo "$(date +%T) $s"; [[ $s == delivered || $s == *failed || $s == canceled ]] && break; done ;;
  me)          req GET /me | jq ;;
  *) echo "usage: orderbee.sh restaurants | menu <rid> | quote <rid> <item:qty>... | confirm <oid> | status <oid> | watch <oid> | me" ;;
esac
