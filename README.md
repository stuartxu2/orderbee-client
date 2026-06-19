# OrderBee Skill/Plugin

Order from local businesses without leaving your AI agent. OrderBee is a `SKILL.md` skill — also packaged as a Claude Code plugin — that lets your assistant order food, coffee, groceries, pharmacy, and convenience items from nearby shops, with live catalogs, real POS prices, saved-card checkout, and courier delivery or pickup. Agent-native ordering, an alternative to DoorDash, Uber Eats, or Instacart.

→ https://orderbee.app

## What's in this repo

This is the public, safe-to-fork layer: the agent skill, the Claude Code plugin manifests, and the API reference. The OrderBee marketplace core — backend API, Stripe Connect, payouts, fraud and dispute handling, POS and courier adapters, and the merchant dashboard — is closed and not here.

| Path | What it is |
|------|------------|
| `skills/orderbee/SKILL.md` | The skill definition your agent loads |
| `skills/orderbee/references/api.md` | OrderBee public API reference |
| `skills/orderbee/scripts/orderbee.sh` | `curl` + `jq` helper the skill calls |
| `.claude-plugin/` | Claude Code plugin and marketplace manifests |

## Install

### One line, every agent (recommended)

The hosted installer auto-detects your agents and installs into each one it finds — Claude Code, Codex, Copilot CLI, Gemini CLI, OpenClaw, Hermes:

```bash
curl -fsSL https://orderbee.app/install.sh | sh
```

Just one agent, or a different one (Pi, Antigravity, the Claude apps, or any `SKILL.md` agent):

```bash
# pick one: claude · codex · copilot · gemini · openclaw · hermes
curl -fsSL https://orderbee.app/install.sh | sh -s -- --agent codex
# or any custom skills folder
curl -fsSL https://orderbee.app/install.sh | sh -s -- --dir ~/path/to/skills
```

### Claude Code plugin

The same skill ships as a Claude Code plugin, so it installs and auto-updates through the native plugin manager:

```bash
/plugin marketplace add stuartxu2/OrderBee-Skill
/plugin install orderbee@orderbee
```

### Manual (one agent at a time)

```bash
npx degit stuartxu2/OrderBee-Skill/skills/orderbee ~/.claude/skills/orderbee
```

Swap `~/.claude` for `~/.codex`, `~/.copilot`, `~/.gemini`, `~/.openclaw`, or `~/.hermes`.

## Configure

Set two variables, then ask your agent to order:

```bash
export ORDERBEE_BASE_URL=https://orderbee.app
export ORDERBEE_API_KEY=sk_...   # get a key at https://orderbee.app
```

Then, in plain words:

> Order a large oat-milk latte from the nearest coffee shop.

Your agent reads the live menu, gets a real POS-priced quote, shows you the itemized total, and only charges once you say go.

## Pricing

OrderBee runs as a non-profit, at cost. No markup on item prices — you pay the shop's real POS price. The delivery fee goes to your Uber or DoorDash courier (choose pickup to skip it), and a small convenience fee only covers AI tokens, servers, and daily operations.

## Status

Sandbox MVP — payments run in Stripe test mode, so no real money is charged. Toast POS and Uber Direct integrations are built on test credentials; mock adapters run the full order lifecycle end to end.

## For local businesses

Run a shop? Connect your POS and take orders from AI agents and the people who use them — your menu, your prices, no commissions. Onboard at https://orderbee.app.

## License

[MIT](./LICENSE) — © 2026 Stuart Xu. The skill, plugin, and tools in this repo are MIT-licensed. The OrderBee hosted service and its core are proprietary.
