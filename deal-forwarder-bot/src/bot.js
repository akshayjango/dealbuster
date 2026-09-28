import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';
import { NewMessage } from 'telegram/events/index.js';
import dotenv from 'dotenv';
import { processMessageText, isAmazonUptoDeal } from './converter.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

dotenv.config({ path: path.join(rootDir, '.env') });

// ── Render / Cloud Web Service Health Check Server ───────────────────────────
const PORT = process.env.PORT || 8080;
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'ok',
    service: 'DealBuster Telegram Forwarder',
    uptime_seconds: Math.round(process.uptime()),
    time: new Date().toISOString()
  }));
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

  // Resolve target channel
  let targetPeer;
  try {
    targetPeer = await client.getEntity(config.target_channel);
    console.log(`🎯 Destination channel set to: ${targetPeer.title || config.target_channel}`);
  } catch (err) {
    console.error(`❌ Could not find target channel "${config.target_channel}":`, err.message);
    console.log('Make sure your Telegram account has joined or is an admin of this channel.');
    process.exit(1);
  }

  // Resolve source channels
  const sourceEntities = [];
  const sourceIds = new Set();

  for (const ch of config.source_channels) {
    if (!ch || ch.startsWith('@example')) continue;
    try {
      const entity = await client.getEntity(ch);
      sourceEntities.push(entity);
      sourceIds.add(entity.id.toString());
      console.log(`📡 Listening to source channel: ${entity.title || ch} (ID: ${entity.id})`);
    } catch (err) {
      console.warn(`⚠️ Could not resolve source channel "${ch}": ${err.message}`);
    }
  }

  if (sourceEntities.length === 0) {
    console.warn('\n⚠️ Warning: No active source channels configured!');
    console.log('Edit "config.json" to add channels you want to monitor, then restart.');
  }

  console.log('\n🚀 Auto-Forwarder is running! Waiting for new deals...\n');

  // Handle new incoming messages
  client.addEventHandler(async (event) => {
    try {
      const msg = event.message;
      if (!msg) return;

      const chat = await msg.getChat();
      if (!chat) return;

      const chatIdStr = chat.id ? chat.id.toString() : '';

      // Check if message is from an authorized source channel
      if (!sourceIds.has(chatIdStr)) {
        return;
      }

      const rawText = msg.message || '';
      console.log(`\n📥 [${new Date().toLocaleTimeString()}] New message from: ${chat.title || chatIdStr}`);

      // 1. Blacklist check
      const lower = rawText.toLowerCase();
      const matchedKeyword = (config.blacklist_keywords || []).find(k => lower.includes(k.toLowerCase()));
      if (matchedKeyword) {
        console.log(`⏩ Skipped: Matched blacklist keyword "${matchedKeyword}"`);
        return;
      }

      // 2. Process text and convert links
      const conversionOptions = {
        amazonTag: config.amazon_tag || 'dealbuster002-21',
        earnkaroToken: config.earnkaro_api_token,
        myChannel: config.target_channel || '@dealbusterindia',
        footer: config.custom_footer,
        removeCompetitorMentions: config.remove_competitor_mentions !== false,
      };

      const result = await processMessageText(rawText, conversionOptions);

      // Filter only allowed stores: amazon, flipkart, myntra, ajio, shopsy
      const validDeals = result.convertedLinks.filter(l => ['amazon', 'flipkart', 'myntra', 'ajio', 'shopsy'].includes(l.store));

      if (validDeals.length === 0) {
        console.log('⏩ Skipped: No allowed stores found (only Amazon, Flipkart, Myntra, Ajio, Shopsy are allowed).');
        return;
      }

      // Check Amazon "upto" condition:
      // If there are Amazon deals and the message contains "upto" or variable discount, skip it!
      const hasAmazonDeal = validDeals.some(l => l.store === 'amazon');
      if (hasAmazonDeal && isAmazonUptoDeal(rawText)) {
        console.log('⏩ Skipped: Amazon deal contains "upto / up to" discount text.');
        return;
      }

      // 3. Deduplication check
      for (const link of validDeals) {
        if (link.id && dedupCache[link.id]) {
          const hoursAgo = ((Date.now() - dedupCache[link.id]) / (1000 * 60 * 60)).toFixed(1);
          console.log(`⏩ Skipped: Duplicate product "${link.id}" posted ${hoursAgo}h ago.`);
          return;
        }
      }

      // Record in dedup cache
      for (const link of validDeals) {
        if (link.id) {
          dedupCache[link.id] = Date.now();
        }
      }
      saveDedupCache(dedupCache);

      // 4. Rate-limit delay
      if (config.delay_seconds) {
        await sleep(config.delay_seconds * 1000);
      }

      // 5. Send to destination channel
      console.log(`📤 Forwarding to ${config.target_channel}...`);
      if (result.convertedLinks.length > 0) {
        console.log(`   🔗 Converted ${result.convertedLinks.length} link(s):`);
        result.convertedLinks.forEach(l => console.log(`      [${l.store}] ${l.convertedUrl}`));
      }

      const sendOptions = {
        message: result.text,
        file: msg.media || undefined,
        linkPreview: false,
      };

      try {
        // Try with Markdown formatting
        await client.sendMessage(targetPeer, {
          ...sendOptions,
          parseMode: 'md',
        });
      } catch (err) {
        // Fallback to plain text if markdown formatting failed
        console.log(`   ℹ️ Note: Markdown parse failed (${err.message}), falling back to plain formatting`);
        await client.sendMessage(targetPeer, sendOptions);
      }

      console.log(`✅ Deal posted successfully to ${config.target_channel}!`);
    } catch (err) {
      console.error('❌ Error processing message:', err);
    }
  }, new NewMessage({}));
}

main().catch(err => {
  console.error('❌ Fatal error:', err);
  process.exit(1);
});
