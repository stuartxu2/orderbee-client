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
6. **Track**: poll `GET /orders/{id}` every 10–30s; relay state changes to the user (delivery: courier assigned → picked up → delivered; pickup: see below). Quote expires in 5 minutes — if confirm returns 409 `quote_expired`, re-quote and re-show the total.

### Pickup orders

When `fulfillment` is `pickup`: there is no courier and no delivery fee. After confirm the order sits in `placed`; poll until state `ready_for_pickup`, then tell the user to collect it. The quote/order response carries a `pickup` block: `{ code, ready_at, address, hours }` — give the user the `code` and `address`. When the user has collected the order, call `POST /orders/{id}/pickup` to close it out (state → `picked_up`).

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

⚠️ `orderbee.sh confirm` generates a FRESH Idempotency-Key per run — use it for first attempts only. To retry a failed confirm, call the API directly with the original key.

Full endpoint reference: `references/api.md`.
