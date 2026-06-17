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
  quote)       # quote <restaurant_id> <item_id>:<qty> [<item_id>:<qty> ...] [fund:<bps>]
    rid=$1; shift
    fund=0; lines=()
    for a in "$@"; do
      if [[ $a == fund:* ]]; then fund=${a#fund:}; else lines+=("$a"); fi
    done
    items=$(printf '%s\n' "${lines[@]}" | jq -R 'split(":") | {item_id: .[0], quantity: (.[1] // "1" | tonumber)}' | jq -s .)
    req POST /orders/quote "{\"restaurant_id\":\"$rid\",\"items\":$items,\"help_fund_bps\":$fund}" | jq ;;
  # NOTE: fresh uuid per run — first attempts only; retries must reuse the original key via the API
  confirm)     req POST "/orders/$1/confirm" '' "Idempotency-Key: $(uuidgen)" | jq ;;
  status)      req GET "/orders/$1" | jq '{state, quote, tracking_url, timeline}' ;;
  watch)       # watch <order_id> — emit one JSON event per status change; exit on terminal state or after max wait.
    oid=$1                                                   # tune: ORDERBEE_POLL_SEC (interval), ORDERBEE_WATCH_MAX_SEC (give-up)
    interval=${ORDERBEE_POLL_SEC:-10}; max_wait=${ORDERBEE_WATCH_MAX_SEC:-1800}
    terminal='delivered|canceled|payment_failed|pos_failed|delivery_failed'   # picked_up handled below (terminal only for pickup)
    start=$(date +%s); prev=''
    while :; do
      o=$(req GET "/orders/$oid") || { sleep "$interval"; continue; }   # transient curl failure → retry next tick
      err=$(jq -r '.error // empty' <<<"$o" 2>/dev/null) || err=''
      if [[ -n $err ]]; then jq -nc --arg e "$err" '{event:"error", error:$e}'; break; fi
      state=$(jq -r '.state // empty' <<<"$o" 2>/dev/null) || state=''
      [[ -z $state ]] && { sleep "$interval"; continue; }               # unparseable body → retry
      fulfillment=$(jq -r '.fulfillment // empty' <<<"$o" 2>/dev/null) || fulfillment=''
      if [[ $state != "$prev" ]]; then
        jq -nc --argjson o "$o" --arg prev "$prev" \
          '{event:(if $prev=="" then "baseline" else "change" end), prev:(if $prev=="" then null else $prev end),
            state:$o.state, tracking_url:($o.tracking_url // null),
            pickup_code:($o.pickup.code // null), ready_at:($o.pickup.ready_at // null)}'
        prev=$state
      fi
      [[ $state =~ ^($terminal)$ ]] && break
      [[ $state == picked_up && $fulfillment == pickup ]] && break       # delivery 'picked_up' = courier en route; keep watching
      if (( $(date +%s) - start >= max_wait )); then jq -nc --arg s "$state" '{event:"timeout", state:$s}'; break; fi
      sleep "$interval"
    done ;;
  me)          req GET /me | jq ;;
  *) echo "usage: orderbee.sh restaurants | menu <rid> | quote <rid> <item:qty>... | confirm <oid> | status <oid> | watch <oid> | me" ;;
esac
