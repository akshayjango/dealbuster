import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';
import { NewMessage } from 'telegram/events/index.js';
import dotenv from 'dotenv';
import { processMessageText, isAmazonUptoDeal, extractAmazonAsin, extractUrls } from './converter.js';

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

  // Synchronize posted deal with Cloudflare Worker so background crons never double-post
  async function syncPostedToAdminApi(item) {
    try {
      const items = [];
      if (item.convertedLinks) {
        for (const l of item.convertedLinks) {
          let asin = null;
          if (l.store === 'amazon') {
            asin = extractAmazonAsin(l.convertedUrl) || extractAmazonAsin(l.originalUrl);
          }
          items.push({ id: l.id, asin });
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

  // Pre-seed dedupCache from recent channel messages in @dealbusterindia
  async function seedDedupFromTargetChannel(client, targetPeer) {
    try {
      console.log('🔄 Pre-seeding dedup cache from @dealbusterindia recent history...');
      const msgs = await client.getMessages(targetPeer, { limit: 100 });
      let addedCount = 0;
      for (const m of msgs) {
        if (!m.message) continue;
        const urls = extractUrls(m.message);
        for (const u of urls) {
          const asin = extractAmazonAsin(u);
          if (asin) {
            const key = 'amazon_' + asin.toUpperCase();
            if (!dedupCache[key]) {
              dedupCache[key] = (m.date || 0) * 1000;
              addedCount++;
            }
          }
        }
        const fp = getDealFingerprint(m.message);
        if (fp.length >= 8 && !dedupCache[fp]) {
          dedupCache[fp] = (m.date || 0) * 1000;
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
        // Enforce strict pacing interval between any two Telegram channel posts
        const intervalSec = config.pacing_interval_seconds || 60;
        const timeSinceLast = (Date.now() - lastDealPostedTime) / 1000;
        if (timeSinceLast < intervalSec && lastDealPostedTime > 0) {
          const waitTimeMs = Math.ceil((intervalSec - timeSinceLast) * 1000);
          console.log(`⏳ Anti-Spam Pacing: Waiting ${(waitTimeMs / 1000).toFixed(1)}s before sending next deal in queue...`);
          await sleep(waitTimeMs);
        }

        botState.queueLength = dealQueue.length;
        const item = dealQueue.shift();
        botState.queueLength = dealQueue.length;

        // Final duplicate check right before sending
        if (item.fingerprint && dedupCache[item.fingerprint] && (dedupCache[item.fingerprint] < item.queuedAt)) {
          console.log(`⏩ Dropped from queue before send: already posted (${item.fingerprint}).`);
          continue;
        }

        try {
          console.log(`\n📤 [Queue] Forwarding deal to ${config.target_channel} (${dealQueue.length} remaining in queue)...`);
          if (item.convertedLinks?.length > 0) {
            item.convertedLinks.forEach(l => console.log(`   🔗 [${l.store}] ${l.convertedUrl}`));
          }

          const sendOptions = {
            message: item.text,
            file: item.media || undefined,
            linkPreview: false,
          };

          try {
            await client.sendMessage(targetPeer, {
              ...sendOptions,
              parseMode: 'md',
            });
          } catch (err) {
            console.log(`   ℹ️ Note: Send failed (${err.message}), retrying as plain text without media...`);
            try {
              await client.sendMessage(targetPeer, {
                message: item.text,
                linkPreview: false,
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

  function getDealFingerprint(text) {
    if (!text) return '';
    return 'fp_' + text
      .toLowerCase()
      .replace(/https?:\/\/[^\s]+/g, '')
      .replace(/[^a-z0-9]/g, '')
      .slice(0, 50);
  }

  // Core message processor: converts links, validates stores, applies filters, and queues for posting
  async function handleIncomingMessage(msg, matchedEntity = null) {
    let claimedFingerprint = null;
    let claimedAsinKey = null;
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

      // 1. FAST ASIN PRE-CHECK:
      // If message contains an Amazon link whose ASIN was already posted or in-flight, skip immediately!
      let detectedAsin = null;
      const rawUrls = extractUrls(rawText);
      for (const u of rawUrls) {
        const a = extractAmazonAsin(u);
        if (a) { detectedAsin = a; break; }
      }
      if (detectedAsin) {
        const asinKey = 'amazon_' + detectedAsin.toUpperCase();
        if (dedupCache[asinKey] || inFlightClaims.has(asinKey)) {
          const hoursAgo = dedupCache[asinKey] ? ((Date.now() - dedupCache[asinKey]) / (1000 * 60 * 60)).toFixed(1) : 0;
          console.log(`⏩ Skipped: ASIN "${detectedAsin}" was already posted ${hoursAgo}h ago.`);
          logEvent(`Skipped: Duplicate ASIN "${detectedAsin}" (${hoursAgo}h ago)`, channelTitle, rawText);
          return;
        }
        inFlightClaims.add(asinKey);
        claimedAsinKey = asinKey;
      }

      // 2. FAST CONTENT PRE-CHECK & SYNCHRONOUS IN-FLIGHT CLAIM:
      // If the deal was already posted or is being processed concurrently by another channel, DROP IT in 0ms!
      const fingerprint = getDealFingerprint(rawText);
      if (fingerprint.length >= 8) {
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
        earnkaroToken: config.earnkaro_api_token,
        myChannel: config.target_channel || '@dealbusterindia',
        footer: config.custom_footer,
        removeCompetitorMentions: config.remove_competitor_mentions !== false,
      };

      const result = await processMessageText(rawText, conversionOptions);

      // Filter only allowed stores: amazon, flipkart, myntra, ajio, shopsy
      const validDeals = result.convertedLinks.filter(l => {
        if (!['amazon', 'flipkart', 'myntra', 'ajio', 'shopsy'].includes(l.store)) return false;
        if (!l.convertedUrl || /dealsping\.in|t\.me|telegram\.me/i.test(l.convertedUrl)) return false;

        // Verify Amazon has our affiliate tag
        if (l.store === 'amazon') {
          return l.convertedUrl.includes('tag=dealbuster');
        }
        // Verify non-Amazon has an affiliate domain (EarnKaro or CueLinks)
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
      const isNonAmazonOnly = isDealsPing || isLootPing || channelRule?.non_amazon_only;

      if (isNonAmazonOnly && validDeals.some(l => l.store === 'amazon')) {
        console.log(`⏩ Skipped: Amazon deal from ${channelTitle} (configured for non-Amazon deals only).`);
        logEvent(`Skipped: Amazon deal from ${channelTitle}`, channelTitle, rawText);
        return;
      }

      // 5. Check Amazon "upto" condition:
      const hasAmazonDeal = validDeals.some(l => l.store === 'amazon');
      if (hasAmazonDeal && isAmazonUptoDeal(rawText)) {
        console.log('⏩ Skipped: Amazon deal contains "upto / up to" discount text.');
        logEvent('Skipped: Amazon deal contains "upto" text', channelTitle, rawText);
        return;
      }

      // 6. Check deleted/blocked ASINs
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

      // 7. Deduplication check by product ID
      for (const link of validDeals) {
        if (link.id && dedupCache[link.id]) {
          const hoursAgo = ((Date.now() - dedupCache[link.id]) / (1000 * 60 * 60)).toFixed(1);
          console.log(`⏩ Skipped: Duplicate product "${link.id}" posted ${hoursAgo}h ago.`);
          logEvent(`Skipped: Duplicate product (${hoursAgo}h ago)`, channelTitle, rawText);
          return;
        }
      }

      // Record in dedup cache
      for (const link of validDeals) {
        if (link.id) {
          dedupCache[link.id] = Date.now();
        }
      }
      if (claimedFingerprint) {
        dedupCache[claimedFingerprint] = Date.now();
      }
      if (claimedAsinKey) {
        dedupCache[claimedAsinKey] = Date.now();
      }
      saveDedupCache(dedupCache);

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
    }
  }

  // 1. Event listener for real-time socket updates
  client.addEventHandler(async (event) => {
    try {
      const msg = event.message;
      if (!msg) return;

      const rawChatId = msg.chatId ? msg.chatId.toString() : '';
      const rawPeerId = msg.peerId?.channelId ? msg.peerId.channelId.toString() : '';

      const entity = sourceEntityMap.get(rawPeerId) ||
                     sourceEntityMap.get(rawChatId) ||
                     sourceEntityMap.get(`-100${rawPeerId}`);
      if (!entity) return;

      const eIdStr = entity.id.toString();
      if (msg.id) {
        lastSeenMsgIds.set(eIdStr, Math.max(lastSeenMsgIds.get(eIdStr) || 0, msg.id));
      }

      await handleIncomingMessage(msg, entity);
    } catch (err) {
      console.error('❌ Error in message event handler:', err);
    }
  }, new NewMessage({}));

  // 2. Active background polling worker (runs every 10 seconds)
  // Guarantees 100% reliability even if Telegram's MTProto socket pauses passive channel push updates
  for (const entity of sourceEntities) {
    try {
      const latest = await client.getMessages(entity, { limit: 1 });
      if (latest && latest[0]?.id) {
        lastSeenMsgIds.set(entity.id.toString(), latest[0].id);
        console.log(`📍 Checkpoint for ${entity.title || entity.id}: latest msg ID ${latest[0].id}`);
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
            const msgs = await client.getMessages(entity, { limit: 3 });
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
