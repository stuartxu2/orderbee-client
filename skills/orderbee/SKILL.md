---
name: orderbee
description: Order from local businesses for the user — live menus/catalogs, POS-priced quotes, saved-card checkout, courier or pickup. Use when the user asks to order food, pharmacy/convenience/dispensary items, or other goods from a local business for delivery or pickup.
---

# OrderBee

Order from local businesses via the OrderBee API. Requires env: `ORDERBEE_BASE_URL`, `ORDERBEE_API_KEY`.

## First-time setup (no API key yet)

1. `POST {base}/signup {"email": "<user email>"}` → returns `api_key` + `setup_url`.
2. Give the user `setup_url` — they save a card in the browser (Stripe).
3. Store `ORDERBEE_API_KEY` in your environment. Ask user for a default delivery address and `PATCH /me`.

## Ordering flow

All requests: header `Authorization: Bearer $ORDERBEE_API_KEY`. Also generate one UUID per conversation and send it as `X-Session-Id` on every OrderBee call — it groups your requests into a session the platform operator can trace for support.

1. **Discover**: `GET /restaurants`
2. **Menu**: `GET /restaurants/{id}/menu` — only offer items with `available: true`
3. **Quote**: `POST /orders/quote` with items. Add `"fulfillment": "pickup"` to skip delivery (no fee, no dropoff needed); omit it (or pass `"delivery"`) for courier delivery, which needs a `dropoff` (or the user's default address).
4. **Show the user the itemized total (items + tax + delivery fee) and get their go-ahead.** The charge is automatic — never confirm without stating the total first.
5. **Confirm**: `POST /orders/{id}/confirm` with header `Idempotency-Key: <uuid you generate once per order>`. Retry with the SAME key only.
6. **Track (automatic)**: right after confirm, start the watcher — `scripts/orderbee.sh watch <order_id>` — in the background if your runtime supports it. It polls and prints **one JSON line per status change**: `{"event":"change","prev":"placed","state":"courier_assigned","tracking_url":...,"pickup_code":...,"ready_at":...}`. The first line is `event:"baseline"` (the current state — you usually already told the user this). On every `change`, **proactively message the user** a short update (delivery: 🛵 courier assigned → 📦 picked up → ✅ delivered; pickup: see below). The watcher exits on a terminal state, on `{"event":"error",...}` (relay the error), or after 30 min (`{"event":"timeout"}` — tell the user it's taking unusually long). Quote expires in 5 minutes — if confirm returns 409 `quote_expired`, re-quote and re-show the total.

   No background support? Poll `GET /orders/{id}` every 10–30s yourself and relay each state change the same way.

### Pickup orders

When `fulfillment` is `pickup`: there is no courier and no delivery fee. After confirm the order sits in `placed`; the watcher (step 6) emits a `change` to `ready_for_pickup` carrying `pickup_code` and `ready_at` — at that point tell the user to collect it, giving them the `pickup_code` and the restaurant `address` (from the quote/order `pickup` block: `{ code, ready_at, address, hours }`). When the user has collected the order, call `POST /orders/{id}/pickup` to close it out (state → `picked_up`).

## Errors you must handle

| Response | Meaning | What to do |
|---|---|---|
| 403 `over_cap` | Total exceeds user's per-order cap | Tell user; they can raise cap via `PATCH /me` |
| 409 `quote_expired` | Quote older than 5 min | Re-quote, re-show total |
| 409 `setup_required` | No saved card | Send user their setup link (re-signup if lost) |
| 409 `confirm_in_progress` | Another confirm is racing | Wait 5s, GET the order, do not retry with a new key |
| 409 `confirm_incomplete` | Earlier confirm crashed mid-flow | Tell user; charge may exist without an order — needs support |
| 409 `canceled_during_confirm` | Order was canceled mid-charge | Tell user order canceled; check `refunded` — if false, charge may stand, needs support |
| 402 `payment_failed` | Card declined | Tell user, do not retry automatically |
| 502 `pos_failed` / `delivery_failed` | Merchant/courier failure; check `refunded` | Tell user they were refunded (or not, if `refunded: false`) |

## Helper script

`scripts/orderbee.sh` wraps curl+jq: `orderbee.sh restaurants | menu <id> | quote <restaurant_id> <item_id>:<qty> [...] | confirm <order_id> | status <order_id> | watch <order_id> | me`

`watch <order_id>` is the auto-notify loop: it streams one JSON line per status change and exits on a terminal state, an error, or after 30 min. Run it (backgrounded) right after confirm to notify the user automatically. Tune with env vars `ORDERBEE_POLL_SEC` (default 10) and `ORDERBEE_WATCH_MAX_SEC` (default 1800).

⚠️ `orderbee.sh confirm` generates a FRESH Idempotency-Key per run — use it for first attempts only. To retry a failed confirm, call the API directly with the original key.

Full endpoint reference: `references/api.md`.
