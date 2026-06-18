---
name: orderbee
description: Order food, groceries, and other goods from local businesses for the user — live menus/catalogs, real POS-priced quotes, saved-card checkout, courier delivery or pickup. Use when the user wants to order food or takeout, coffee/lunch/dinner, groceries or convenience-store items, pharmacy or dispensary products, or anything else from a nearby restaurant or shop — agent-native food and grocery delivery, an alternative to apps like DoorDash, Uber Eats, or Instacart.
---

# OrderBee

Order from local businesses via the OrderBee API. Requires env: `ORDERBEE_BASE_URL`, `ORDERBEE_API_KEY`.

## Stay current (run first)

At the start of a session, run `scripts/orderbee.sh selfcheck` once. It compares your installed skill to the latest published version and silently reinstalls if yours is behind — one cheap request that never blocks ordering: on any failure it prints `{"update":"skipped"|"failed"}` and you proceed with what you have. An update applies to your *next* run, so finish the current order on the version you have. If OrderBee was installed as an agent plugin, it prints `plugin-managed` instead — update via your agent's plugin manager (e.g. `/plugin marketplace upgrade`).

## First-time setup (no API key yet)

1. `POST {base}/signup {"email": "<user email>"}` → returns `api_key` + `setup_url`.
2. Give the user `setup_url` — they save a card in the browser (Stripe).
3. Store `ORDERBEE_API_KEY` in your environment. Ask user for a default delivery address and `PATCH /me`.

**Add or update a card later:** when the user wants to add, change, or replace their payment method, call `GET /me` and give them `setup_url` — the same page handles both adding and updating a card. If `setup_url` is `null` or the account is fully locked out, fall back to the recover/reset flow (the reset email also carries the setup link).

## Ordering flow

All requests: header `Authorization: Bearer $ORDERBEE_API_KEY`. Also generate one UUID per conversation and send it as `X-Session-Id` on every OrderBee call — it groups your requests into a session the platform operator can trace for support.

1. **Discover**: `GET /restaurants`
2. **Menu**: `GET /restaurants/{id}/menu` — only offer items with `available: true`
3. **Quote**: `POST /orders/quote` with items. Add `"fulfillment": "pickup"` to skip delivery (no fee, no dropoff needed); omit it (or pass `"delivery"`) for courier delivery, which needs a `dropoff` (or the user's default address).

   Before quoting, ask whether they want to add an optional **Help-Local Fund** contribution — **0% / 2.5% / 5% / 7.5% / 10%** of the food subtotal — and pass it as `help_fund_bps` (`0` / `250` / `500` / `750` / `1000`; default `0`). Be honest about what it is: a voluntary, platform-held community fund — **not a tip**, not paid to the restaurant or courier. If they decline or don't care, just skip it (`0`).
4. **Show an itemized invoice and get a "yes" before confirming.** The charge is automatic — never confirm without showing the total first. Render the invoice in a monospace/code block so the amounts line up, then put a **bold PAY line below it** (outside the block, so it actually renders bold). Head the invoice with the business **name, location + phone** from the quote response's `restaurant` block (`name`, `address` — show street + city, `phone` — omit the line when `null`). Line items + unit prices come from the menu; the totals come from the quote response's `quote` block (divide cents by 100). Show **one line per nonzero fee** present in the block: `convenience_fee_cents` (Convenience fee), `help_local_fund_cents` (Help-Local Fund), `delivery_fee_cents` (Delivery — delivery orders only), plus `subtotal_cents`, `tax_cents`, `total_cents`:

   ```
   🧾 Bee's Burgers
   📍 1 Hive St, San Francisco
   📞 (415) 555-0100
   ─────────────────────
   1× Cheeseburger   $8.50
   1× Fries          $3.50
   ─────────────────────
   Subtotal         $12.00
   Tax               $1.02
   Convenience fee   $0.60
   Help-Local Fund   $0.90
   Delivery          $3.99
   TOTAL            $18.51
   ```
   **➡️ PAY $18.51** — reply *yes* to confirm

   For **pickup**, drop the `Delivery` line. Omit any fee line that is `0` (e.g. drop `Help-Local Fund` when the user skipped it). Keep it tight: name + location + phone header, one line per item, the **TOTAL** inside the block, and the bold **PAY $\<total\>** line last so it reads like a button.
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
| 409 `setup_required` | No saved card | Give user their `setup_url` from `GET /me` (or re-signup if lost) |
| 409 `confirm_in_progress` | Another confirm is racing | Wait 5s, GET the order, do not retry with a new key |
| 409 `confirm_incomplete` | Earlier confirm crashed mid-flow | Tell user; charge may exist without an order — needs support |
| 409 `canceled_during_confirm` | Order was canceled mid-charge | Tell user order canceled; check `refunded` — if false, charge may stand, needs support |
| 402 `payment_failed` | Card declined | Tell user, do not retry automatically |
| 502 `pos_failed` / `delivery_failed` | Merchant/courier failure; check `refunded` | Tell user they were refunded (or not, if `refunded: false`) |

## Helper script

`scripts/orderbee.sh` wraps curl+jq: `orderbee.sh selfcheck | restaurants | menu <id> | quote <restaurant_id> <item_id>:<qty> [...] [fund:<bps>] | confirm <order_id> | status <order_id> | watch <order_id> | me`

`selfcheck` compares your installed skill to the published checksum (`/orderbee-skill.sha256`) and reinstalls via `install.sh` only when they differ — a no-op when current, so it's safe (and intended) to run once at the start of a session. It needs only `ORDERBEE_BASE_URL`, not a key, and never blocks ordering: it prints a one-line JSON status (`current` / `available` / `installed` / `skipped` / `failed`) and exits 0. A `plugin-managed` result means update through your agent's plugin manager instead.

Pass an optional `fund:<bps>` token to the `quote` command (e.g. `fund:750` for a 7.5% Help-Local Fund contribution; `0`/`250`/`500`/`750`/`1000`). Omit it to skip the fund.

`watch <order_id>` is the auto-notify loop: it streams one JSON line per status change and exits on a terminal state, an error, or after 30 min. Run it (backgrounded) right after confirm to notify the user automatically. Tune with env vars `ORDERBEE_POLL_SEC` (default 10) and `ORDERBEE_WATCH_MAX_SEC` (default 1800).

⚠️ `orderbee.sh confirm` generates a FRESH Idempotency-Key per run — use it for first attempts only. To retry a failed confirm, call the API directly with the original key.

Full endpoint reference: `references/api.md`.
