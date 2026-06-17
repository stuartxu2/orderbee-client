# OrderBee API Reference

Base URL: `$ORDERBEE_BASE_URL`. Auth: `Authorization: Bearer $ORDERBEE_API_KEY` on everything except `POST /signup`. All money fields are integer cents. Optional header on every request: `X-Session-Id: <uuid>` — generate one per conversation; OrderBee groups requests into agent sessions for platform support. Not a chat transcript: only method/path/order-id are recorded.

## POST /signup
Body: `{"email": "user@example.com"}` → 201 `{"api_key": "ob_...", "setup_url": "https://.../setup/<token>"}`
409 `email_exists`. Rate-limited per IP (429 after 5/hour).

## GET /me
200 `{"email", "has_payment_method": bool, "default_address": {...}|null, "per_order_cap_cents": 7500}`

## PATCH /me
Body (any subset): `{"per_order_cap_cents": 10000, "default_address": {"street","city","state","zip"}}` → 200 profile. Cap range: 100–50000 cents.

## GET /restaurants
200 `{"restaurants": [{"id", "name", "address", "hours"}]}`

## GET /restaurants/:id/menu
200 `{"restaurant_id", "items": [{"id", "name", "price_cents", "available", "description"}]}`
503 `pos_unavailable` if the restaurant's POS is down.

## POST /orders/quote
Body: `{"restaurant_id": "<uuid>", "items": [{"item_id": "bb-classic", "quantity": 2}], "dropoff": {address}?, "fulfillment": "delivery"|"pickup"?, "help_fund_bps": 0|250|500|750|1000?}`
`fulfillment` defaults to `delivery`. For `delivery`, `dropoff` defaults to the user's `default_address` (400 `dropoff_required` if neither set). For `pickup`, no `dropoff` is needed and `delivery_fee_cents` is `0`. Quantity 1–20 per line.
`help_fund_bps` is the optional **Help-Local Fund** contribution (defaults to `0`): a voluntary, platform-held community fund taken as a % of the food subtotal — `0`/`250`/`500`/`750`/`1000` = 0%/2.5%/5%/7.5%/10%. Any other value → 400 `invalid_body`. It is not a tip and is not paid to the restaurant.
201:
```json
{
  "id": "<order uuid>", "state": "quoted",
  "restaurant": {"name": "Bee's Burgers", "phone": "+14155550100", "address": {"street","city","state","zip"}},
  "quote": {"subtotal_cents": 2275, "tax_cents": 202, "service_charge_cents": 0, "convenience_fee_cents": 114, "help_local_fund_cents": 0, "delivery_fee_cents": 499, "total_cents": 3090},
  "quote_expires_at": "<iso8601>", "dropoff": {...}, "timeline": [...]
}
```
`restaurant` carries the business `name`, `phone` (may be `null`) + `address` so the invoice is self-contained (present on quote, confirm, and `GET /orders/:id`; `null` in the `GET /orders` list).
`convenience_fee_cents` is a flat 5% platform fee on the subtotal (every order). `help_local_fund_cents` is the contribution chosen via `help_fund_bps` (`0` when skipped). Both are already included in `total_cents`.
For `pickup` orders the response also includes `"pickup": {"code": "A1B2", "ready_at": null, "address": {...}, "hours": "..."}` and `"dropoff": null`. The `code` is a short 4-character pickup code.
Pricing comes from the restaurant's POS (Toast `/prices`) plus the courier quote — totals are authoritative; OrderBee never computes food prices itself.

## POST /orders/:id/confirm
Headers: `Idempotency-Key: <uuid>` (required; reuse the same key on retries — never a new one).
Charges saved card off-session, places POS order, and dispatches a courier (delivery only — pickup orders stop at `placed`).
200 order (state `placed`) | 400 missing key | 402 `payment_failed` | 403 `over_cap` | 409 `quote_expired` / `setup_required` / `invalid_state` / `confirm_in_progress` / `confirm_incomplete` / `canceled_during_confirm` | 502 `pos_failed` / `delivery_failed` (with `"refunded": true|false`).

## GET /orders/:id
200 order with `state`, `quote`, `tracking_url`, `timeline: [{"from","to","source","at"}]`.
States — delivery: `quoted → pending_payment → paid → placed → courier_assigned → picked_up → delivered`; pickup: `quoted → pending_payment → paid → placed → ready_for_pickup → picked_up`; failures: `payment_failed`, `pos_failed`, `delivery_failed`, `canceled`.

## GET /orders
200 `{"orders": [...]}` — 20 most recent (list omits timeline).

## POST /orders/:id/cancel
Pre-pickup only. 200 canceled order with `"refunded": true|false|null` (null = nothing was charged) | 409 `not_cancelable`.

## POST /orders/:id/pickup
Pickup orders only. Customer confirms they collected the order: `ready_for_pickup → picked_up`.
200 order (state `picked_up`; replay after pickup also 200) | 409 `not_ready` (not yet `ready_for_pickup`) | 409 `not_a_pickup_order` | 404 `order_not_found`.
