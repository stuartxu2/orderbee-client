# OrderBee Client

Open integration layer for [OrderBee](https://orderbee.app/) — the AI agent skill for **food and grocery delivery** from local businesses (restaurants, cafés, grocery and convenience stores, pharmacies, dispensaries) with live catalogs, real prices, saved-card checkout, and courier delivery or pickup. Ask your agent to order takeout, a coffee, groceries, or pharmacy items — agent-native ordering, an alternative to apps like DoorDash, Uber Eats, or Instacart.

This repository holds the **public, safe-to-fork parts**: the agent skill and (over time) SDKs, a webhook verifier, an embeddable booking widget, and calendar/import adapters. The OrderBee marketplace core — backend API, Stripe Connect, payouts, dispute and fraud handling, POS/courier adapters, and the merchant dashboard — is **closed** and not in this repo.

## What's here

| Path | What it is | Status |
|------|------------|--------|
| `skills/orderbee/` | The OrderBee agent skill: `SKILL.md`, a `curl`+`jq` helper, and the API reference | ✅ Available |

## Roadmap (open layer)

These are intended to live here as they land — community contributions welcome:

- **API client SDK** (TypeScript / Python) over the public OrderBee API.
- **Webhook signature verifier** for order-status callbacks.
- **Embeddable booking button** widget for shop websites.
- **Calendar / import adapters** (Square, Vagaro, Booksy → OrderBee).
- **CLI / devtools.**

## Install the skill

The skill works in any agent that supports the `SKILL.md` format — Claude Code, Codex, OpenClaw, Hermes — only the directory differs.

One line (per agent):

```bash
# Claude Code
npx degit stuartxu2/OrderBee-Skill/skills/orderbee ~/.claude/skills/orderbee
# Codex
npx degit stuartxu2/OrderBee-Skill/skills/orderbee ~/.codex/skills/orderbee
# OpenClaw
npx degit stuartxu2/OrderBee-Skill/skills/orderbee ~/.openclaw/skills/orderbee
# Hermes
npx degit stuartxu2/OrderBee-Skill/skills/orderbee ~/.hermes/skills/orderbee
```

Or use the hosted cross-agent installer (auto-detects your agents):

```bash
curl -fsSL https://orderbee.app/install.sh | sh
```

### Native plugin install (Claude Code)

The same skill is also packaged as a Claude Code plugin, so it installs and auto-updates through the native plugin manager:

```bash
/plugin marketplace add stuartxu2/OrderBee-Skill
/plugin install orderbee@orderbee
```

Then set the environment and ask your agent to order:

```bash
export ORDERBEE_BASE_URL=https://orderbee.app
export ORDERBEE_API_KEY=...   # get a key at https://orderbee.app
```

## Pricing

OrderBee is free to use. The small convenience fee on each order covers server costs, API tokens, and platform operations — nothing more. No profit margin.

## Status

OrderBee is a sandbox MVP — payments run in Stripe test mode, so no real money is charged.

## License

[MIT](./LICENSE) — © 2026 Stuart Xu. The skill, SDKs, and tools in this repo are MIT-licensed. The OrderBee hosted service and its core are proprietary.
