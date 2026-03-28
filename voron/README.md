# Voron — RSS Feed Health Check

n8n workflow · 8 nodes · category: infra

## What it does

Accepts a list of URLs (from n8n chat or Telegram), fetches each feed,
parses the XML, checks the freshness of the latest entry.
Returns a report: healthy feeds and problematic ones with reasons.

## Triggers

- **Chat** — paste URLs into the n8n chat widget
- **Telegram** — send URLs to the bot, get the report back in the same chat

## How it works

1. Extract all URLs from the incoming message
2. Fetch each feed via HTTP (15 s timeout, browser User-Agent)
3. Parse RSS/Atom XML — find the most recent `<item>` or `<entry>`
4. Check publication date — flag feeds older than 100 days
5. Build a report split into chunks (≤ 3 800 chars each)
6. Route: Telegram source → send via Telegram bot; Chat source → return to chat

## Output format

```
✅ Healthy (N)
✅ 3d — example.com/feed
✅ 12d — another.org/rss

❌ Problematic (N)
❌ Timeout — slow-site.net/feed
❌ 210d — stale-blog.com/rss.xml
❌ Cloudflare — blocked-source.com/feed
```

## Error reasons

| Code | Meaning |
|------|---------|
| `Timeout` | No response in 15 s |
| `Cloudflare` | Access blocked |
| `Empty` | Response under 50 chars |
| `No entries` | No `<item>` / `<entry>` found |
| `Date` | Date field missing or unparseable |
| `Nd` | Feed is N days stale (> 100 d) |
| `5xx / 4xx` | HTTP error code |

## Requirements

- n8n with HTTP Request and Code nodes
- Telegram bot token (for Telegram trigger + send)
  — credential name: **RSS check**

## Files

```
voron/
├── README.md                          ← this file
└── Voron__RSS-Feed-Health-Check.json  ← workflow export
```

## Import

1. In n8n → **Workflows → Import from file**
2. Select `Voron__RSS-Feed-Health-Check.json`
3. Set up the **RSS check** Telegram credential
4. Activate
