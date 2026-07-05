# DealBuster

Amazon India deal-aggregator site + Telegram channels (@dealbuster_in, @dealsanddiscountsofficial).

## Architecture

- **Static site**: root HTML files, deployed via GitHub Pages/Actions from this repo. `products.json` is the product database (bots commit to it constantly — expect `git push` to be rejected; `git pull --no-edit` then push).
- **Backend**: Cloudflare Worker in `admin-api/` (single file: `admin-api/src/index.js`). Deploy with `npx wrangler deploy` from `admin-api/`. Deploying does NOT require a git commit, but always commit+push code changes or the next deploy from a stale checkout will wipe them.
- **KV**: product sync state, dedup ledgers. **Free tier: 1,000 writes/day — usage sits ~80%. Be stingy with new KV writes.**
- Sync crons (wrangler.toml): IndiaFreeStuff every 10 min, DealsRadar+Amazon+badges every 15 min, Amazon deals page 2x/day, Telegram posting every 5 min.

## Telegram posting — CRITICAL RULES

History: duplicate posts repeatedly flooded the channel and lost subscribers. Root causes fixed July 2026. Do not regress:

1. **Every Telegram post MUST go through `postDealsAndTrack()`** → which delegates to the `TgPoster` Durable Object. NEVER call `postDealToChannels()` or `tgSend`-to-channel directly from new code. The DO is the single global serialization point; bypassing it reintroduces duplicates.
2. **KV locks cannot serialize posting** — KV is eventually consistent across colos. TWO schedulers fire the posting path every 5 min (internal CF cron + external pinger hitting `/cron-post-deals`, added because CF crons were unreliable on this account). Only the DO handles this correctly.
3. **Claim-before-send**: the DO marks products posted in its storage BEFORE sending. Preferred failure mode is a missed post, never a duplicate. Keep it that way.
4. Dedup is by product `id` AND `asin` (uppercased). The DO ledger is authoritative; KV `tg_posted_ids` is only an advisory mirror for the cron's cheap pre-check.
5. Never refresh `addedAt` on existing products (price drops, syncs) — it drives the site's "Updated Xhr ago" badge and previously made old deals look new. Bump array position instead.

## Gotchas

- `handlePublish()` already posts to Telegram internally — don't add a second post call after invoking it (this bug shipped once).
- Admin UI publish buttons need their double-click guard (`if (btn.disabled) return;` in `doPublish`, `admin-api/public/index.html`).
- Amazon Creators API rate-limits (429s on price-check chunks) are normal noise.
- Debug live: `npx wrangler tail --format pretty` from `admin-api/`.
