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
4. Dedup is by product `id` AND `asin` (uppercased). The DO ledger is authoritative; KV `tg_posted_ids` is only an advisory mirror for the cron's cheap pre-check — `queueForApproval()`'s DO claim (`/posted/claim`) must update the mirror for EVERY requested product, not just the ones that came back fresh, or a mirror that ever falls one tick behind the DO gets permanently wedged re-selecting the same already-claimed ids forever (silently — no error logged; this shipped once, killed TG posting for 43 minutes while real new deals piled up unposted). `clearTgPostedMarks()` (formerly `clearTgPostedForEvicted`) erases ledger marks so a future re-add posts as new — called from three places: tombstone expiry (14 days), **reject**, and **approval-expiry sweep**. Reject/expiry MUST clear the mark — they are not a permanent "never show this ASIN again," just "not this listing." Skipping this left rejected/timed-out deals invisible to Telegram on every future re-add forever, indistinguishable from a real repost (this shipped once too — several genuinely live, in-stock deals silently never reached the bot again after one reject/timeout). NEVER clear at 720-cap eviction time — the feeds still list freshly evicted deals, and clearing there re-DM's every re-add (the original July 2026 spam loop). DO-clear failure aborts the mirror clear — a re-add is then silently skipped (missed post, never a duplicate).
5. Never refresh `addedAt` on existing products (price drops, syncs) — it drives the site's "Updated Xhr ago" badge and previously made old deals look new. Since July 2026, price drops also do NOT bump array position — the price updates in place and the deal ages out purely by time. Only manual dashboard deletes blocklist an ASIN via `deleted_asins.json`.
5b. **Tombstones**: EVERY product leaving the live list — 720-cap evictees (healthy or not) and price-sync ₹0 detections — stays in products.json as a `{hidden: true, dead: <ISO>}` tombstone instead of being deleted. The DR/IFS feeds keep listing deals for days after we drop them; deleting one meant the next sync re-added it at the top as "new" (one geyser did 20 laps in 2 days, each lap DMing the admin). Tombstones block re-adds via existingByAsin, don't count toward the 720 live cap, keep their TG ledger marks, and expire after 14 days (`capLiveAndBury()` then drops them AND clears their ledger marks, so a genuine return posts as new). All sync cap-trims MUST go through `capLiveAndBury()`. Syncs must also skip feed items with no/zero price entirely.
6. **Autopost toggle** (KV `autopost_enabled`, default ON, dashboard switch calls `POST /autopost`): when OFF, new deals are DM'd to the admin (`TG_ADMIN_ID`) with Approve/Reject inline buttons instead of hitting the channel. Pending items live in KV `tg_pending_approvals` (one read+write per batch, not per deal). `sweepExpiredApprovals()` piggybacks on the 5-min TG cron to drop anything unapproved after 4h — no separate cron needed. Turning autopost back ON does not flush the backlog; only new deals from that point auto-post, old pending ones still need a manual tap.

## Gotchas

- `handlePublish()` already posts to Telegram internally — don't add a second post call after invoking it (this bug shipped once).
- Admin UI publish buttons need their double-click guard (`if (btn.disabled) return;` in `doPublish`, `admin-api/public/index.html`).
- Amazon Creators API rate-limits (429s on price-check chunks) are normal noise.
- Debug live: `npx wrangler tail --format pretty` from `admin-api/`.
