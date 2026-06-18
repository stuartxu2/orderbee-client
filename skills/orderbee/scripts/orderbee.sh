#!/usr/bin/env bash
# OrderBee CLI helper. Needs: curl, jq, ORDERBEE_BASE_URL, ORDERBEE_API_KEY.
set -euo pipefail

cmd=${1:-help}; shift || true

: "${ORDERBEE_BASE_URL:?set ORDERBEE_BASE_URL}"
# selfcheck/help run before a key may exist; every API command needs the key.
[[ $cmd == selfcheck || $cmd == help ]] || : "${ORDERBEE_API_KEY:?set ORDERBEE_API_KEY}"

sha256() { # stdin -> 64-char hex digest, using whichever tool is present
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else openssl dgst -sha256 | awk '{print $NF}'; fi
}

req() { # method path [json-body] [extra-header]
  local method=$1 path=$2 body=${3:-} extra=${4:-}
  local args=(-sS -X "$method" -H "Authorization: Bearer $ORDERBEE_API_KEY" -H "content-type: application/json")
  [[ -n $body ]] && args+=(-d "$body")
  [[ -n $extra ]] && args+=(-H "$extra")
  curl "${args[@]}" "$ORDERBEE_BASE_URL$path"
}

case "$cmd" in
  selfcheck)   # compare installed skill to the published checksum; reinstall only if behind. cheap; never fatal.
    root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
    have=$(cat "$root/SKILL.md" "$root/scripts/orderbee.sh" "$root/references/api.md" 2>/dev/null | sha256) || have=''
    want=$(curl -fsSL "$ORDERBEE_BASE_URL/orderbee-skill.sha256" 2>/dev/null | tr -cd '[:xdigit:]') || want=''
    if [[ -z $want ]]; then echo '{"update":"skipped","reason":"checksum unreachable"}'; exit 0; fi
    if [[ -n $have && $have == "$want" ]]; then echo '{"update":"current"}'; exit 0; fi
    # Plugin-managed installs (path under a .../plugins/... store) update via the agent's plugin
    # manager, not the curl installer — reinstalling would write a second copy into ~/.<agent>/skills.
    case "$root" in
      */plugins/*) echo '{"update":"available","reason":"plugin-managed; update via your agent plugin manager"}'; exit 0 ;;
    esac
    echo '{"update":"available"}'
    if curl -fsSL "$ORDERBEE_BASE_URL/install.sh" | sh >/dev/null 2>&1
      then echo '{"update":"installed"}'
      else echo '{"update":"failed","reason":"reinstall error; keep using current version"}'
    fi ;;
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
  *) echo "usage: orderbee.sh selfcheck | restaurants | menu <rid> | quote <rid> <item:qty>... | confirm <oid> | status <oid> | watch <oid> | me" ;;
esac
