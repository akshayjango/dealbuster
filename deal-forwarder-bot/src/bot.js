import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';
import { NewMessage } from 'telegram/events/index.js';
import { HTMLParser } from 'telegram/extensions/html.js';
import dotenv from 'dotenv';
import { processMessageText, extractAmazonAsin, extractUrls, extractCanonicalDealId, isAmazonUrl } from './converter.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

dotenv.config({ path: path.join(rootDir, '.env') });

// ── Live Bot State & Diagnostics ─────────────────────────────────────────────
const botState = {
  status: 'ok',
  service: 'DealBuster Telegram Forwarder',
  connected: false,
  user: null,
  targetChannel: null,
  monitoredChannels: [],
  queueLength: 0,
  isQueueProcessing: false,
  recentEvents: [],
};

function logEvent(action, channel, text) {
  botState.recentEvents.unshift({
    time: new Date().toLocaleTimeString(),
    action,
    channel: channel || 'Unknown',
    snippet: (text || '').replace(/\s+/g, ' ').slice(0, 90)
  });
  if (botState.recentEvents.length > 30) botState.recentEvents.pop();
}

// ── Render / Cloud Web Service Health Check Server ───────────────────────────
const PORT = process.env.PORT || 8080;
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    ...botState,
    uptime_seconds: Math.round(process.uptime()),
    time: new Date().toISOString()
  }, null, 2));
});

server.listen(PORT, () => {
  console.log(`🌐 Health check server listening on port ${PORT}`);
});

// Self-ping to keep Render free tier awake 24/7
const pingUrl = process.env.RENDER_EXTERNAL_URL || process.env.SELF_PING_URL;
if (pingUrl) {
  console.log(`⏱️ Self-ping enabled for: ${pingUrl}`);
  setInterval(() => {
    fetch(pingUrl).catch(() => {});
  }, 10 * 60 * 1000); // ping every 10 minutes
}

// Helper to load deleted_asins.json
function loadDeletedAsins() {
  try {
    const localFile = path.join(rootDir, 'deleted_asins.json');
    const parentFile = path.join(rootDir, '../deleted_asins.json');
    const target = fs.existsSync(localFile) ? localFile : (fs.existsSync(parentFile) ? parentFile : null);
    if (target) {
      const arr = JSON.parse(fs.readFileSync(target, 'utf8'));
      return Array.isArray(arr) ? arr.map(a => a.toUpperCase()) : [];
    }
  } catch {}
  return [];
}

const configPath = path.join(rootDir, 'config.json');
const dedupPath = path.join(rootDir, 'dedup_cache.json');

// Helper to load config safely
function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (err) {
    console.error('❌ Failed to read config.json:', err.message);
    process.exit(1);
  }
}

// Helper to load dedup cache
function loadDedupCache() {
  try {
    if (fs.existsSync(dedupPath)) {
      return JSON.parse(fs.readFileSync(dedupPath, 'utf8'));
    }
  } catch {}
  return {};
}

// Helper to save dedup cache
function saveDedupCache(cache) {
  try {
    fs.writeFileSync(dedupPath, JSON.stringify(cache, null, 2), 'utf8');
  } catch (err) {
    console.warn('⚠️ Could not save dedup_cache.json:', err.message);
  }
}

// Clean old dedup entries
function cleanDedupCache(cache, ttlHours) {
  const now = Date.now();
  const maxAge = ttlHours * 60 * 60 * 1000;
  let changed = false;
  for (const [id, timestamp] of Object.entries(cache)) {
    if (now - timestamp > maxAge) {
      delete cache[id];
      changed = true;
    }
  }
  if (changed) saveDedupCache(cache);
}

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function main() {
  console.log('========================================================');
  console.log('     DealBuster Telegram Channel Auto-Forwarder         ');
  console.log('========================================================\n');

  const apiId = process.env.TELEGRAM_API_ID;
  const apiHash = process.env.TELEGRAM_API_HASH;
  const sessionString = process.env.TELEGRAM_SESSION;

  if (!apiId || !apiHash || !sessionString) {
    console.error('❌ Missing credentials in .env!');
    console.log('Please run the login script first:');
    console.log('  npm run login\n');
    process.exit(1);
  }

  const config = loadConfig();
  const dedupCache = loadDedupCache();
  cleanDedupCache(dedupCache, config.dedup_ttl_hours || 24);

  console.log('🔄 Initializing Telegram client...');
  const client = new TelegramClient(
    new StringSession(sessionString),
    parseInt(apiId, 10),
    apiHash,
    { connectionRetries: 5 }
  );

  await client.connect();

  const me = await client.getMe();
  console.log(`✅ Logged in as: ${me.firstName || ''} ${me.lastName || ''} (@${me.username || me.id})`);

  // Load all joined channels and chats into GramJS memory
  console.log('🔄 Loading joined channels and chats into memory...');
  const dialogs = await client.getDialogs({ limit: 100 });

  // Resolve target channel
  let targetPeer;
  try {
    targetPeer = await client.getEntity(config.target_channel);
    console.log(`🎯 Destination channel set to: ${targetPeer.title || config.target_channel}`);
  } catch (err) {
    const clean = config.target_channel.toString().replace(/^@/, '').toLowerCase();
    targetPeer = dialogs.find(d => d.entity?.username?.toLowerCase() === clean || (d.entity?.title && d.entity.title.toLowerCase().includes(clean)))?.entity;
    if (targetPeer) {
      console.log(`🎯 Destination channel set to: ${targetPeer.title || config.target_channel}`);
    } else {
      console.error(`❌ Could not find target channel "${config.target_channel}":`, err.message);
      console.log('Make sure your Telegram account has joined or is an admin of this channel.');
      process.exit(1);
    }
  }

  // Resolve source channels
  const sourceEntities = [];
  const sourceIds = new Set();
  const sourceEntityMap = new Map();

  for (const ch of config.source_channels) {
    if (!ch || ch.startsWith('@example')) continue;
    let entity = null;
    try {
      entity = await client.getEntity(ch);
    } catch {
      // Fallback: match in loaded dialogs by username, ID, or title
      const clean = ch.toString().replace(/^@/, '').toLowerCase();
      const match = dialogs.find(d => {
        const e = d.entity;
        if (!e) return false;
        const eId = e.id?.toString() || '';
        return e.username?.toLowerCase() === clean ||
               eId === clean ||
               `-100${eId}` === clean ||
               (e.title && e.title.toLowerCase().includes(clean));
      });
      if (match) entity = match.entity;
    }

    if (entity) {
      sourceEntities.push(entity);
      const eId = entity.id.toString();
      sourceIds.add(eId);
      sourceIds.add(`-100${eId}`);
      sourceIds.add(`-${eId}`);
      if (entity.username) sourceIds.add(entity.username.toLowerCase());
      sourceEntityMap.set(eId, entity);
      sourceEntityMap.set(`-100${eId}`, entity);
      sourceEntityMap.set(`-${eId}`, entity);
      if (entity.username) sourceEntityMap.set(entity.username.toLowerCase(), entity);
      console.log(`📡 Listening to source channel: ${entity.title || ch} (ID: ${entity.id})`);
    } else {
      console.warn(`⚠️ Could not resolve source channel "${ch}". Make sure your Telegram account has joined this channel.`);
    }
  }

  if (sourceEntities.length === 0) {
    console.warn('\n⚠️ Warning: No active source channels configured!');
    console.log('Edit "config.json" to add channels you want to monitor, then restart.');
  }

  botState.connected = true;
  botState.user = `${me.firstName || ''} ${me.lastName || ''} (@${me.username || me.id})`.trim();
  botState.targetChannel = targetPeer?.title || config.target_channel;
  botState.monitoredChannels = sourceEntities.map(e => `${e.title || e.username} (ID: ${e.id})`);

  // Fast query to Cloudflare Worker DO to check if deal is in authoritative channel ledger
  async function isAlreadyPostedInAdminApi(keys) {
    if (!Array.isArray(keys) || keys.length === 0) return false;
    const cleanKeys = keys.filter(Boolean).map(k => String(k).trim()).filter(Boolean);
    if (cleanKeys.length === 0) return false;
    try {
      const res = await fetch('https://dealbuster-admin-api.vakshay083.workers.dev/tg-posted/check', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ keys: cleanKeys }),
        signal: AbortSignal.timeout(4000),
      });
      if (res.ok) {
        const data = await res.json().catch(() => ({}));
        if (Array.isArray(data?.posted) && data.posted.length > 0) {
          console.log(`📡 Cloudflare Worker DO reports already posted: [${data.posted.join(', ')}]`);
          return true;
        }
      }
    } catch {}
    return false;
  }

  // Synchronize posted deal with Cloudflare Worker so background crons never double-post
  async function syncPostedToAdminApi(item) {
    try {
      const items = [];
      if (item.convertedLinks) {
        for (const l of item.convertedLinks) {
          let asin = l.asin || null;
          if (!asin && l.store === 'amazon') {
            asin = extractAmazonAsin(l.convertedUrl) || extractAmazonAsin(l.originalUrl);
          }
          items.push({ id: l.id, asin, pid: l.pid || null });
        }
      }
      if (items.length > 0) {
        await fetch('https://dealbuster-admin-api.vakshay083.workers.dev/tg-posted/claim', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ items }),
          signal: AbortSignal.timeout(5000),
        }).catch(() => {});
        console.log(`📡 Synced ${items.length} deal mark(s) to Cloudflare Worker DO/KV.`);
      }
    } catch (err) {
      console.warn('⚠️ Admin-api claim sync error:', err.message);
    }
  }

  // Real-time ingestion of any deal posted directly to @dealbusterindia (e.g. by admin-api or manual post)
  function ingestTargetChannelMessage(msg) {
    try {
      if (!msg || !msg.message) return;
      const text = msg.message;
      const urls = extractUrls(text, msg.entities);
      let added = 0;
      const now = (msg.date || 0) * 1000 || Date.now();
      for (const u of urls) {
        const canonical = extractCanonicalDealId(u);
        if (canonical?.id) {
          if (!dedupCache[canonical.id]) { dedupCache[canonical.id] = now; added++; }
        }
        if (canonical?.asin) {
          const aKey = 'amazon_' + canonical.asin.toUpperCase();
          if (!dedupCache[aKey]) { dedupCache[aKey] = now; added++; }
        }
        if (canonical?.pid) {
          const pKey = `pid_${canonical.pid}`;
          if (!dedupCache[pKey]) { dedupCache[pKey] = now; added++; }
        }
        const uKey = 'url_' + u;
        if (!dedupCache[uKey]) { dedupCache[uKey] = now; added++; }
      }
      const fp = getDealFingerprint(text, msg.media);
      if (fp && !dedupCache[fp]) {
        dedupCache[fp] = now;
        added++;
      }
      if (added > 0) {
        saveDedupCache(dedupCache);
        console.log(`📡 Ingested ${added} mark(s) from @dealbusterindia into dedupCache.`);
      }
    } catch (e) {
      console.warn('⚠️ Target channel message ingestion error:', e.message);
    }
  }

  // Pre-seed dedupCache from recent channel messages in @dealbusterindia
  async function seedDedupFromTargetChannel(client, targetPeer) {
    try {
      console.log('🔄 Pre-seeding dedup cache from @dealbusterindia recent history...');
      const msgs = await client.getMessages(targetPeer, { limit: 120 });
      let addedCount = 0;
      for (const m of msgs) {
        if (!m.message) continue;
        const msgDate = (m.date || 0) * 1000 || Date.now();
        const urls = extractUrls(m.message, m.entities);
        for (const u of urls) {
          const canonical = extractCanonicalDealId(u);
          if (canonical?.id && !dedupCache[canonical.id]) {
            dedupCache[canonical.id] = msgDate;
            addedCount++;
          }
          if (canonical?.asin) {
            const key = 'amazon_' + canonical.asin.toUpperCase();
            if (!dedupCache[key]) {
              dedupCache[key] = msgDate;
              addedCount++;
            }
          }
          if (canonical?.pid) {
            const pKey = `pid_${canonical.pid}`;
            if (!dedupCache[pKey]) {
              dedupCache[pKey] = msgDate;
              addedCount++;
            }
          }
          const uKey = 'url_' + u;
          if (!dedupCache[uKey]) {
            dedupCache[uKey] = msgDate;
            addedCount++;
          }
        }
        const fp = getDealFingerprint(m.message, m.media);
        if (fp && !dedupCache[fp]) {
          dedupCache[fp] = msgDate;
          addedCount++;
        }
      }
      saveDedupCache(dedupCache);
      console.log(`✅ Pre-seeded ${addedCount} entries from @dealbusterindia channel history.`);
    } catch (err) {
      console.warn('⚠️ Could not pre-seed from target channel:', err.message);
    }
  }

  // ── Deal Forwarding Queue & Anti-Spam Pacing ─────────────────────────────────
  const dealQueue = [];
  let isQueueProcessing = false;
  let lastDealPostedTime = 0;

  async function processQueue(client, targetPeer, config) {
    if (isQueueProcessing) return;
    isQueueProcessing = true;
    botState.isQueueProcessing = true;

    try {
      while (dealQueue.length > 0) {
        // Post immediately per user preference (minimal safety interval to prevent Telegram FloodWait on rapid bursts)
        const pacingSec = (config.pacing_interval_seconds !== undefined) ? Number(config.pacing_interval_seconds) : 0;
        const minBurstDelaySec = (config.delay_seconds !== undefined) ? Number(config.delay_seconds) : 1;
        const effectiveIntervalSec = pacingSec > 0 ? pacingSec : minBurstDelaySec;

        const timeSinceLast = (Date.now() - lastDealPostedTime) / 1000;
        if (timeSinceLast < effectiveIntervalSec && lastDealPostedTime > 0) {
          const waitTimeMs = Math.ceil((effectiveIntervalSec - timeSinceLast) * 1000);
          if (waitTimeMs > 0) {
            await sleep(waitTimeMs);
          }
        }

        botState.queueLength = dealQueue.length;
        const item = dealQueue.shift();
        botState.queueLength = dealQueue.length;

        try {
          console.log(`\n📤 [Queue] Forwarding deal to ${config.target_channel} (${dealQueue.length} remaining in queue)...`);
          if (item.convertedLinks?.length > 0) {
            item.convertedLinks.forEach(l => console.log(`   🔗 [${l.store}] ${l.convertedUrl}`));
          }

          let messageToSend = item.text;
          let entitiesToSend = undefined;
          try {
            const [parsedText, parsedEntities] = HTMLParser.parse(item.text);
            messageToSend = parsedText;
            entitiesToSend = parsedEntities;
          } catch (pErr) {
            console.warn('⚠️ HTML parsing fallback:', pErr.message);
          }

          const sendOptions = {
            message: messageToSend,
            formattingEntities: entitiesToSend,
            file: item.media || undefined,
            linkPreview: false,
            silent: true,
          };

          try {
            await client.sendMessage(targetPeer, sendOptions);
          } catch (err) {
            console.log(`   ℹ️ Note: Formatted send failed (${err.message}), retrying as plain text without media...`);
            try {
              const plainText = item.text
                .replace(/<a\s+href="([^"]+)">👉\s*Check Now<\/a>/gi, '$1')
                .replace(/<[^>]+>/g, '');
              await client.sendMessage(targetPeer, {
                message: plainText,
                linkPreview: false,
                silent: true,
              });
            } catch (err2) {
              console.error('❌ Error sending queued deal as plain text:', err2.message);
            }
          }

          lastDealPostedTime = Date.now();
          if (item.fingerprint) {
            dedupCache[item.fingerprint] = Date.now();
            saveDedupCache(dedupCache);
          }

          logEvent('Forwarded deal to channel', item.title, item.text);
          console.log(`✅ Deal posted successfully to ${config.target_channel}!`);

          // Synchronize with Cloudflare Worker so crons never double-post this deal
          syncPostedToAdminApi(item).catch(() => {});
        } catch (err) {
          console.error('❌ Error sending queued deal:', err.message);
          logEvent('Error sending deal: ' + err.message, item.title, item.text);
        }
      }
    } finally {
      isQueueProcessing = false;
      botState.isQueueProcessing = false;
      botState.queueLength = dealQueue.length;
    }
  }

  // Telegram connection keepalive heartbeat
  setInterval(async () => {
    try {
      if (client && !client.connected) {
        console.log('🔄 Reconnecting to Telegram...');
        await client.connect();
      }
      botState.connected = client ? client.connected : false;
    } catch (e) {
      console.warn('⚠️ Telegram keepalive error:', e.message);
    }
  }, 25 * 1000);

  // Pre-seed dedupCache from recent messages in @dealbusterindia to guarantee zero duplicate re-posts across restarts/crons
  await seedDedupFromTargetChannel(client, targetPeer);

  console.log('\n🚀 Auto-Forwarder is running! Waiting for new deals...\n');

  // Track latest message ID per channel to prevent reprocessing and enable reliable polling
  const lastSeenMsgIds = new Map();
  // In-flight claims set to synchronously serialize and drop concurrent duplicates across channels
  const inFlightClaims = new Set();

  function getDealFingerprint(text, media = null) {
    if (!text && !media) return '';
    const clean = (text || '')
      .toLowerCase()
      .replace(/https?:\/\/[^\s]+/g, '')
      .replace(/[^a-z0-9]/g, '')
      .slice(0, 50);
    const photoId = media?.photo?.id?.toString() || media?.document?.id?.toString() || '';
    if (!clean && !photoId) return '';
    return 'fp_' + clean + (photoId ? `_m${photoId}` : '');
  }

  // Core message processor: converts links, validates stores, applies filters, and queues for posting
  async function handleIncomingMessage(msg, matchedEntity = null) {
    let claimedFingerprint = null;
    let claimedAsinKey = null;
    let validDeals = [];
    try {
      if (!msg || !msg.message) return;

      const rawChatId = msg.chatId ? msg.chatId.toString() : '';
      const rawPeerId = msg.peerId?.channelId ? msg.peerId.channelId.toString() : '';

      // Instant in-memory entity resolution
      const entity = matchedEntity ||
                     sourceEntityMap.get(rawPeerId) ||
                     sourceEntityMap.get(rawChatId) ||
                     sourceEntityMap.get(`-100${rawPeerId}`);

      if (!entity) return;

      const chatIdStr = entity.id ? entity.id.toString() : '';
      const chatUsername = entity.username ? entity.username.toLowerCase() : '';
      const channelTitle = entity.title || chatUsername || rawChatId;

      const rawText = msg.message || '';
      if (!rawText.trim()) return;

      // DealsPing check
      const isDealsPing = (chatUsername === 'dealping') ||
                          (channelTitle && /dealping/i.test(channelTitle)) ||
                          chatIdStr === '2549771239' ||
                          rawChatId === '-1002549771239' ||
                          rawPeerId === '2549771239';

      // 0. FAST RAW URL PRE-CHECK
      const rawUrls = extractUrls(rawText, msg.entities);

      // DealsPing: Skip all Amazon deals immediately! Only non-Amazon deals allowed.
      if (isDealsPing && (isAmazonUrl(rawText) || rawUrls.some(u => isAmazonUrl(u) || u.includes('dealsping.in/amz') || u.includes('amazn.') || u.includes('amzn.')))) {
        console.log(`⏩ Skipped: Amazon deal from DealsPing (${channelTitle}). Only non-Amazon deals are accepted from DealsPing.`);
        logEvent('Skipped: DealsPing Amazon deal', channelTitle, rawText);
        return;
      }
      for (const u of rawUrls) {
        if (dedupCache['url_' + u] || dedupCache[u]) {
          console.log(`⏩ Skipped: URL "${u}" was already posted.`);
          logEvent(`Skipped: Duplicate URL`, channelTitle, rawText);
          return;
        }
      }

      // 1. FAST ASIN PRE-CHECK:
      // If message contains an Amazon link whose ASIN was already posted or in-flight, skip immediately!
      let detectedAsin = null;
      for (const u of rawUrls) {
        const a = extractAmazonAsin(u);
        if (a) { detectedAsin = a.toUpperCase(); break; }
      }
      if (detectedAsin) {
        const asinKey = 'amazon_' + detectedAsin;
        if (dedupCache[asinKey] || inFlightClaims.has(asinKey)) {
          const hoursAgo = dedupCache[asinKey] ? ((Date.now() - dedupCache[asinKey]) / (1000 * 60 * 60)).toFixed(1) : 0;
          console.log(`⏩ Skipped: ASIN "${detectedAsin}" was already posted ${hoursAgo}h ago.`);
          logEvent(`Skipped: Duplicate ASIN "${detectedAsin}" (${hoursAgo}h ago)`, channelTitle, rawText);
          return;
        }
        // Also check Cloudflare Worker DO authoritative ledger
        const inWorker = await isAlreadyPostedInAdminApi([detectedAsin, asinKey]);
        if (inWorker) {
          console.log(`⏩ Skipped: ASIN "${detectedAsin}" was already posted in Cloudflare Worker DO.`);
          logEvent(`Skipped: Duplicate ASIN in Worker DO`, channelTitle, rawText);
          dedupCache[asinKey] = Date.now();
          saveDedupCache(dedupCache);
          return;
        }
        inFlightClaims.add(asinKey);
        claimedAsinKey = asinKey;
      }

      // 2. FAST CONTENT PRE-CHECK & SYNCHRONOUS IN-FLIGHT CLAIM:
      // If the deal was already posted or is being processed concurrently by another channel, DROP IT in 0ms!
      const fingerprint = getDealFingerprint(rawText, msg.media);
      if (fingerprint && fingerprint.length >= 4) {
        if (inFlightClaims.has(fingerprint)) {
          console.log(`⏩ Skipped: Duplicate deal already in-flight from another channel.`);
          logEvent('Skipped: Concurrent cross-channel duplicate (in-flight)', channelTitle, rawText);
          return;
        }
        if (dedupCache[fingerprint]) {
          const hoursAgo = ((Date.now() - dedupCache[fingerprint]) / (1000 * 60 * 60)).toFixed(1);
          console.log(`⏩ Skipped: Duplicate deal content across channels posted ${hoursAgo}h ago.`);
          logEvent(`Skipped: Cross-channel duplicate (${hoursAgo}h ago)`, channelTitle, rawText);
          return;
        }
        inFlightClaims.add(fingerprint);
        claimedFingerprint = fingerprint;
      }

      console.log(`\n📥 [${new Date().toLocaleTimeString()}] New message from: ${channelTitle}`);

      // 2. Blacklist check
      const lower = rawText.toLowerCase();
      const matchedKeyword = (config.blacklist_keywords || []).find(k => lower.includes(k.toLowerCase()));
      if (matchedKeyword) {
        console.log(`⏩ Skipped: Matched blacklist keyword "${matchedKeyword}"`);
        logEvent(`Skipped: Blacklist keyword "${matchedKeyword}"`, channelTitle, rawText);
        return;
      }

      // Check blocked brands from admin dashboard
      const matchedBrand = (config.blocked_brands || []).find(b => {
        const bl = b.toLowerCase();
        const regex = new RegExp(`(?:^|[^a-zA-Z0-9])${bl}(?:[^a-zA-Z0-9]|$)`, 'i');
        return regex.test(lower);
      });
      if (matchedBrand) {
        console.log(`⏩ Skipped: Matched blocked brand "${matchedBrand}"`);
        logEvent(`Skipped: Blocked brand "${matchedBrand}"`, channelTitle, rawText);
        return;
      }

      // 3. Process text and convert links
      const conversionOptions = {
        amazonTag: config.amazon_tag || 'dealbuster002-21',
        earnkaroToken: process.env.EARNKARO_API_TOKEN || config.earnkaro_api_token,
        myChannel: config.target_channel || '@dealbusterindia',
        footer: config.custom_footer,
        removeCompetitorMentions: config.remove_competitor_mentions !== false,
        entities: msg.entities,
      };

      const result = await processMessageText(rawText, conversionOptions);

      // Filter only allowed stores: amazon, flipkart, myntra, ajio, shopsy, meesho
      validDeals = result.convertedLinks.filter(l => {
        if (!['amazon', 'flipkart', 'myntra', 'ajio', 'shopsy', 'meesho'].includes(l.store)) return false;
        if (!l.convertedUrl || /dealsping\.in|t\.me|telegram\.me/i.test(l.convertedUrl)) return false;

        // Verify Amazon has our affiliate tag
        if (l.store === 'amazon') {
          return l.convertedUrl.includes('tag=dealbuster');
        }
        // For Flipkart, Myntra, Ajio, Shopsy: STRICTLY REQUIRE EarnKaro shortlink (fktr.in, ekaro.in, myntr.it, ajiio.in)
        if (['flipkart', 'myntra', 'ajio', 'shopsy'].includes(l.store)) {
          return /(?:ekaro\.in|fktr\.in|myntr\.it|ajiio\.in)/i.test(l.convertedUrl);
        }
        // For other stores (e.g. Meesho where EarnKaro is unavailable), accept CueLinks
        return /(?:ekaro\.in|fktr\.in|myntr\.it|ajiio\.in|linksredirect\.com|linkredirect\.in|clnk\.in)/i.test(l.convertedUrl);
      });

      if (validDeals.length === 0) {
        console.log('⏩ Skipped: No valid converted affiliate deals found.');
        logEvent('Skipped: No valid converted affiliate deals', channelTitle, rawText);
        return;
      }

      // 4. Channel-specific store rule:
      // DealsPing & LootPing: ONLY non-Amazon deals (Flipkart, Myntra, Ajio, Shopsy). Skip all Amazon deals!
      const isDealsPing = (chatUsername === 'dealping') ||
                          (channelTitle && /dealping/i.test(channelTitle)) ||
                          chatIdStr === '2549771239' ||
                          rawChatId === '-1002549771239' ||
                          rawPeerId === '2549771239';
      const isLootPing = (chatUsername === 'lootping') ||
                         (channelTitle && /lootping/i.test(channelTitle)) ||
                         chatIdStr === '1175095956' ||
                         rawChatId === '-1001175095956' ||
                         rawPeerId === '1175095956';
      const channelRule = config.channel_rules?.[`@${chatUsername}`] ||
                          config.channel_rules?.[chatUsername] ||
                          (isDealsPing ? config.channel_rules?.['@DealPing'] : null) ||
                          (isLootPing ? config.channel_rules?.['@lootping'] : null);
      const isNonAmazonOnly = isDealsPing || Boolean(channelRule?.non_amazon_only);

      if (isNonAmazonOnly && validDeals.some(l => l.store === 'amazon')) {
        console.log(`⏩ Skipped: Amazon deal from ${channelTitle} (configured for non-Amazon deals only).`);
        logEvent(`Skipped: Amazon deal from ${channelTitle}`, channelTitle, rawText);
        return;
      }

      // 5. Check deleted/blocked ASINs
      const deletedAsins = loadDeletedAsins();
      for (const deal of validDeals) {
        if (deal.store === 'amazon' && deal.id) {
          const asin = deal.id.replace('amazon_', '').toUpperCase();
          if (deletedAsins.includes(asin)) {
            console.log(`⏩ Skipped: Amazon ASIN "${asin}" is in deleted_asins blocklist.`);
            logEvent(`Skipped: Deleted ASIN "${asin}"`, channelTitle, rawText);
            return;
          }
        }
      }

      // 7. Deduplication check by canonical product ID and Cloudflare Worker DO ledger
      for (const link of validDeals) {
        const dealId = link.id;
        if (!dealId) continue;

        if (dedupCache[dealId] || inFlightClaims.has(dealId)) {
          const hoursAgo = dedupCache[dealId] ? ((Date.now() - dedupCache[dealId]) / (1000 * 60 * 60)).toFixed(1) : 0;
          console.log(`⏩ Skipped: Duplicate canonical product "${dealId}" posted ${hoursAgo}h ago.`);
          logEvent(`Skipped: Duplicate canonical product (${hoursAgo}h ago)`, channelTitle, rawText);
          return;
        }

        // Check Cloudflare Worker DO ledger for canonicalId, pid, asin
        const checkKeys = [dealId];
        if (link.pid) checkKeys.push(link.pid);
        if (link.asin) checkKeys.push(link.asin);
        const inWorker = await isAlreadyPostedInAdminApi(checkKeys);
        if (inWorker) {
          console.log(`⏩ Skipped: Product "${dealId}" already in Cloudflare Worker DO ledger.`);
          logEvent(`Skipped: Product in Worker DO`, channelTitle, rawText);
          dedupCache[dealId] = Date.now();
          saveDedupCache(dedupCache);
          return;
        }
      }

      // Record in dedup cache and in-flight claims immediately to prevent any concurrent race
      for (const link of validDeals) {
        if (link.id) {
          inFlightClaims.add(link.id);
          dedupCache[link.id] = Date.now();
        }
        if (link.asin) {
          const aKey = 'amazon_' + link.asin.toUpperCase();
          inFlightClaims.add(aKey);
          dedupCache[aKey] = Date.now();
        }
        if (link.pid) {
          dedupCache[`pid_${link.pid}`] = Date.now();
        }
        if (link.originalUrl) {
          dedupCache['url_' + link.originalUrl] = Date.now();
        }
      }
      if (claimedFingerprint) {
        dedupCache[claimedFingerprint] = Date.now();
      }
      if (claimedAsinKey) {
        dedupCache[claimedAsinKey] = Date.now();
      }
      saveDedupCache(dedupCache);

      // Pre-claim with Cloudflare Worker DO immediately so Worker crons never double-post
      syncPostedToAdminApi({ convertedLinks: validDeals }).catch(() => {});

      // Add to pacing queue and trigger queue processor
      console.log(`📥 Added to queue (Queue length: ${dealQueue.length + 1})`);
      logEvent(`Queued deal (${validDeals.map(d => d.store).join(', ')})`, channelTitle, result.text);
      dealQueue.push({
        text: result.text,
        media: msg.media || null,
        convertedLinks: validDeals,
        title: channelTitle,
        fingerprint: claimedFingerprint,
        queuedAt: Date.now(),
      });

      // Start processing queue (non-blocking)
      processQueue(client, targetPeer, config).catch(e => console.error('Queue error:', e));
    } catch (err) {
      console.error('❌ Error processing message:', err);
    } finally {
      if (claimedFingerprint) {
        inFlightClaims.delete(claimedFingerprint);
      }
      if (claimedAsinKey) {
        inFlightClaims.delete(claimedAsinKey);
      }
      for (const link of validDeals || []) {
        if (link?.id) inFlightClaims.delete(link.id);
      }
    }
  }

  // 1. Event listener for real-time socket updates
  client.addEventHandler(async (event) => {
    try {
      const msg = event.message;
      if (!msg) return;

      const rawChatId = msg.chatId ? msg.chatId.toString() : '';
      const rawPeerId = msg.peerId?.channelId ? msg.peerId.channelId.toString() : '';

      // Check if message was posted directly to our target channel @dealbusterindia
      const targetIdStr = targetPeer?.id ? targetPeer.id.toString() : '';
      const isTargetChannel = targetIdStr && (
        rawPeerId === targetIdStr ||
        rawChatId === targetIdStr ||
        rawPeerId === `-100${targetIdStr}` ||
        rawChatId === `-100${targetIdStr}`
      );

      if (isTargetChannel) {
        ingestTargetChannelMessage(msg);
        return;
      }

      const entity = sourceEntityMap.get(rawPeerId) ||
                     sourceEntityMap.get(rawChatId) ||
                     sourceEntityMap.get(`-100${rawPeerId}`);
      if (!entity) return;

      const eIdStr = entity.id.toString();
      if (msg.id) {
        const lastId = lastSeenMsgIds.get(eIdStr) || 0;
        if (msg.id <= lastId) return;
        lastSeenMsgIds.set(eIdStr, Math.max(lastId, msg.id));
      }

      await handleIncomingMessage(msg, entity);
    } catch (err) {
      console.error('❌ Error in message event handler:', err);
    }
  }, new NewMessage({}));

  // Periodically refresh dedupCache from recent messages in @dealbusterindia (every 5 minutes)
  setInterval(() => {
    seedDedupFromTargetChannel(client, targetPeer).catch(() => {});
  }, 5 * 60 * 1000);

  // 2. Initial deal sweep & active background polling worker
  // On startup: Check the latest 5 messages from each source channel to catch any deals posted in the last 30 minutes
  const startupTime = Date.now();
  for (const entity of sourceEntities) {
    try {
      const recent = await client.getMessages(entity, { limit: 5 });
      if (recent && recent.length > 0) {
        const eIdStr = entity.id.toString();
        lastSeenMsgIds.set(eIdStr, recent[0].id);
        console.log(`📍 Checkpoint for ${entity.title || entity.id}: latest msg ID ${recent[0].id}`);

        // Catch up on recent unposted deals from the last 30 minutes
        const unhandled = recent
          .filter(m => m && m.date && (startupTime - m.date * 1000) < 30 * 60 * 1000)
          .sort((a, b) => a.id - b.id);

        for (const msg of unhandled) {
          await handleIncomingMessage(msg, entity);
        }
      }
    } catch (e) {
      console.warn(`⚠️ Could not get initial checkpoint for ${entity.title || entity.id}:`, e.message);
    }
  }

  async function pollChannelsWorker() {
    while (true) {
      try {
        await sleep(10000);
        if (!client || !client.connected) continue;

        for (const entity of sourceEntities) {
          try {
            const eIdStr = entity.id.toString();
            const lastId = lastSeenMsgIds.get(eIdStr) || 0;
            const msgs = await client.getMessages(entity, { limit: 10 });
            if (!msgs || msgs.length === 0) continue;

            const unhandled = msgs.filter(m => m && m.id > lastId).sort((a, b) => a.id - b.id);
            for (const msg of unhandled) {
              lastSeenMsgIds.set(eIdStr, Math.max(lastSeenMsgIds.get(eIdStr) || 0, msg.id));
              await handleIncomingMessage(msg, entity);
            }
            if (msgs[0]?.id && msgs[0].id > (lastSeenMsgIds.get(eIdStr) || 0)) {
              lastSeenMsgIds.set(eIdStr, msgs[0].id);
            }
          } catch {
            // Per-channel fetch error non-fatal, continue next channel
          }
        }
      } catch (err) {
        console.warn('⚠️ Polling loop error:', err.message);
      }
    }
  }

  pollChannelsWorker().catch(e => console.error('Polling worker exited:', e));
}

main().catch(err => {
  console.error('❌ Fatal error:', err);
  process.exit(1);
});
