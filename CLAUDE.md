# DealBuster

Amazon India deal-aggregator site + Telegram channel (@dealbusterindia, https://t.me/dealbusterindia).

## Architecture

- **Static site**: root HTML files, deployed via GitHub Pages/Actions from this repo. `products.json` is the product database (bots commit to it constantly — expect `git push` to be rejected; `git pull --no-edit` then push).
- **Backend**: Cloudflare Worker in `admin-api/` (single file: `admin-api/src/index.js`). Deploy with `npx wrangler deploy` from `admin-api/`. Deploying does NOT require a git commit, but always commit+push code changes or the next deploy from a stale checkout will wipe them.
- **KV**: product sync state, dedup ledgers. **Free tier: 1,000 writes/day — usage sits ~80%. Be stingy with new KV writes.**
- Sync crons (wrangler.toml): IndiaFreeStuff every 10 min, DealsRadar+Amazon+badges every 15 min, Amazon deals page 2x/day, Telegram posting every 5 min.

## Telegram posting — CRITICAL RULES

History: duplicate posts repeatedly flooded the channel and lost subscribers. Root causes fixed July 2026. Do not regress:

1. **Every Telegram post MUST go through `postDealsAndTrack()`** → which either sends immediately via `sendToChannels()` (delegates to the `TgPoster` Durable Object) or, when the autopost toggle is off, hands off to `queueForApproval()` instead. NEVER call `postDealToChannels()`, `sendToChannels()`, or `tgSend`-to-channel directly from new code — always go through `postDealsAndTrack()`. The DO is the single global serialization point; bypassing it reintroduces duplicates.
2. **KV locks cannot serialize posting** — KV is eventually consistent across colos. TWO schedulers fire the posting path every 5 min (internal CF cron + external pinger hitting `/cron-post-deals`, added because CF crons were unreliable on this account). Only the DO handles this correctly.
3. **Claim-before-send**: the DO marks products posted in its storage BEFORE sending. Preferred failure mode is a missed post, never a duplicate. Keep it that way.
4. Dedup is by product `id` AND `asin` (uppercased). The DO ledger is authoritative; KV `tg_posted_ids` is only an advisory mirror for the cron's cheap pre-check. `queueForApproval()` also claims through the DO (`/posted/claim`) — never KV-only (KV read-modify-write races lost claims and re-DM'd the same deals 30+ times). Exception: when an IN-STOCK, PRICED deal ages out at the 720 cap, `clearTgPostedForEvicted()` erases its ledger entries (DO first, then mirror) so a later re-add posts as new. NEVER clear the ledger for OOS/zero-price evictees — that was the July 2026 spam loop. DO-clear failure aborts the mirror clear — a re-add is then silently skipped (missed post, never a duplicate).
5. Never refresh `addedAt` on existing products (price drops, syncs) — it drives the site's "Updated Xhr ago" badge and previously made old deals look new. Since July 2026, price drops also do NOT bump array position — the price updates in place and the deal ages out purely by time. Once evicted (720 cap), a re-synced/re-added product enters as a new deal (only manual dashboard deletes blocklist an ASIN via `deleted_asins.json`).
5b. **Tombstones**: dead products (OOS/₹0 at eviction, or price gone in price sync) stay in products.json as `{hidden: true, dead: <ISO>}` tombstones instead of being deleted — the DR/IFS feeds keep listing dead products for days, and deleting one meant the next sync re-added it at the top as "new" (top of site → dies → evicted → re-added, one geyser did 20 laps in 2 days, each lap DMing the admin). Tombstones don't count toward the 720 live cap, are pruned after 14 days, and keep their TG ledger marks. All sync cap-trims MUST go through `capLiveAndBury()`. Syncs must also skip feed items with no/zero price entirely.
6. **Autopost toggle** (KV `autopost_enabled`, default ON, dashboard switch calls `POST /autopost`): when OFF, new deals are DM'd to the admin (`TG_ADMIN_ID`) with Approve/Reject inline buttons instead of hitting the channel. Pending items live in KV `tg_pending_approvals` (one read+write per batch, not per deal). `sweepExpiredApprovals()` piggybacks on the 5-min TG cron to drop anything unapproved after 4h — no separate cron needed. Turning autopost back ON does not flush the backlog; only new deals from that point auto-post, old pending ones still need a manual tap.

## Gotchas

- `handlePublish()` already posts to Telegram internally — don't add a second post call after invoking it (this bug shipped once).
- Admin UI publish buttons need their double-click guard (`if (btn.disabled) return;` in `doPublish`, `admin-api/public/index.html`).
- Amazon Creators API rate-limits (429s on price-check chunks) are normal noise.
- Debug live: `npx wrangler tail --format pretty` from `admin-api/`.
