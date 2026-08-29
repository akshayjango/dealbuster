const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Password',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

// ── OAuth token ───────────────────────────────────────────────────────────────

let cachedToken = null;
let tokenExpiry = 0;

async function getAccessToken(clientId, clientSecret) {
  if (cachedToken && Date.now() < tokenExpiry) return cachedToken;
  const resp = await fetchWithTimeout('https://api.amazon.com/auth/o2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=client_credentials&client_id=${encodeURIComponent(clientId)}&client_secret=${encodeURIComponent(clientSecret)}&scope=creatorsapi%3A%3Adefault`,
  });
  const data = await resp.json();
  if (!resp.ok || !data.access_token) throw new Error(data.error_description || data.error || 'Token fetch failed');
  cachedToken = data.access_token;
  tokenExpiry = Date.now() + (data.expires_in - 60) * 1000;
  return cachedToken;
}

// ── Creators API search ───────────────────────────────────────────────────────

async function handleSearch(query, env) {
  let token;
  try { token = await getAccessToken(env.PA_ACCESS_KEY, env.PA_SECRET_KEY); }
  catch (e) { return json({ error: `Auth failed: ${e.message}` }, 502); }

  let resp;
  try {
    resp = await Promise.race([
      fetch('https://creatorsapi.amazon/catalog/v1/searchItems', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'x-marketplace': 'www.amazon.in' },
        body: JSON.stringify({
          keywords: query, resources: ['images.primary.large','itemInfo.title','offersV2.listings.price','offersV2.listings.dealDetails'],
          partnerTag: env.PA_PARTNER_TAG, partnerType: 'Associates', marketplace: 'www.amazon.in', itemCount: 10,
        }),
      }),
      new Promise((_, r) => setTimeout(() => r(new Error('Search timeout')), 20000)),
    ]);
  } catch (e) { return json({ error: e.message }, 504); }

  const rawText = await resp.text();
  let data;
  try { data = JSON.parse(rawText); } catch { return json({ error: 'Invalid response from Amazon', raw: rawText.slice(0,500) }, 502); }
  if (!resp.ok) return json({ error: data.errors?.[0]?.message || data.message || 'Search failed', raw: rawText.slice(0,500), status: resp.status }, 502);

  const items = (data.searchResult?.items || []).map(item => {
    const listing = item.offersV2?.listings?.[0];
    const price = listing?.price?.amount || 0;
    const mrp = listing?.dealDetails?.originalPrice?.amount || price;
    const disc = price && mrp && mrp > price ? Math.round((1 - price / mrp) * 100) : 0;
    return {
      asin: item.asin, title: decodeHtmlEntities(item.itemInfo?.title?.displayValue || ''),
      image: item.images?.primary?.large?.url || '',
      price: price ? `₹${Math.round(price)}` : '', mrp: mrp ? `₹${Math.round(mrp)}` : '',
      disc: disc ? `-${disc}%` : '0%', link: `https://www.amazon.in/dp/${item.asin}?tag=${env.PA_PARTNER_TAG}`,
    };
  });
  return json({ items });
}

// ── GitHub helpers ────────────────────────────────────────────────────────────

function encodeBase64Unicode(str) {
  // products.json crossed several MB; the old encodeURIComponent+regex-callback
  // approach invokes a JS callback per %XX triplet (3 per multi-byte char, e.g.
  // every ₹ in every price/priceHistory entry) — tens of thousands of calls per
  // write, enough to hit the Worker's CPU limit with no catchable error. This
  // does the same UTF-8 encode via TextEncoder (native, no per-char callback).
  const bytes = new TextEncoder().encode(str);
  let binary = '';
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

function ghHeaders(env) {
  return { 'Authorization': `token ${(env.GITHUB_TOKEN || '').trim()}`, 'User-Agent': 'Dealbuster-Admin' };
}

async function getProductsFile(env) {
  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/products.json`;
  const resp = await fetchWithTimeout(apiUrl, { headers: ghHeaders(env) });
  if (resp.status === 404) return { products: [], sha: null };
  if (!resp.ok) { const err = await resp.json().catch(() => ({})); throw new Error(err.message || `GitHub fetch failed: ${resp.status}`); }
  const file = await resp.json();

  // The Contents API only inlines file content for files <=1MB. products.json
  // crossed that line (grown past 1,048,576 bytes) — past it GitHub returns
  // content:"" + encoding:"none" instead of an error, so every reader silently
  // got an empty string, atob('') -> '', JSON.parse('') -> "Unexpected end of
  // JSON input". Every sync AND the admin dashboard read through here, so this
  // one crossing broke everything at once. Fall back to the Git Blobs API,
  // which returns base64 content regardless of size (up to 100MB).
  let base64 = file.content;
  if (!base64 || file.encoding === 'none') {
    const blobUrl = `https://api.github.com/repos/akshayjango/dealbuster/git/blobs/${file.sha}`;
    const blobResp = await fetchWithTimeout(blobUrl, { headers: ghHeaders(env) });
    if (!blobResp.ok) { const err = await blobResp.json().catch(() => ({})); throw new Error(err.message || `GitHub blob fetch failed: ${blobResp.status}`); }
    base64 = (await blobResp.json()).content;
  }

  const rawBytes = atob(base64.replace(/\n/g, ''));
  const uint8 = new Uint8Array(rawBytes.length);
  for (let i = 0; i < rawBytes.length; i++) uint8[i] = rawBytes.charCodeAt(i);
  const products = JSON.parse(new TextDecoder('utf-8').decode(uint8));
  return { products: Array.isArray(products) ? products : [], sha: file.sha };
}

// Global cron lock — only ONE cron runs at a time to prevent products.json SHA conflicts
const GLOBAL_CRON_LOCK = 'cron_global';
async function withCronLock(cronName, ttlSeconds, env, fn) {
  if (!env.KV) return fn();
  const held = await env.KV.get(GLOBAL_CRON_LOCK);
  if (held) { console.log(`Global cron lock held (by ${held}), skipping ${cronName}`); return null; }
  await env.KV.put(GLOBAL_CRON_LOCK, cronName, { expirationTtl: ttlSeconds });
  try { return await fn(); }
  finally { await env.KV.delete(GLOBAL_CRON_LOCK).catch(() => {}); }
}

function mergeProducts(local, remote) {
  const remoteMap = new Map(remote.map(p => [p.id, p]));
  const localMap = new Map(local.map(p => [p.id, p]));

  const merged = [];
  
  // Keep the remote list's ordering as the base
  for (const r of remote) {
    const l = localMap.get(r.id);
    if (l) {
      const mergedProduct = { ...r };
      const lCheck = l.lastChecked || 0;
      const rCheck = r.lastChecked || 0;
      const lBadge = l.lastBadgeCheck || 0;
      const rBadge = r.lastBadgeCheck || 0;
      
      if (lCheck >= rCheck) {
        if (l.price !== undefined) mergedProduct.price = l.price;
        if (l.outOfStock !== undefined) mergedProduct.outOfStock = l.outOfStock;
        if (l.priceDropText !== undefined) mergedProduct.priceDropText = l.priceDropText;
        if (l.lastChecked !== undefined) mergedProduct.lastChecked = l.lastChecked;
        if (l.dead !== undefined) mergedProduct.dead = l.dead;
        if (l.hidden !== undefined) mergedProduct.hidden = l.hidden;
      }
      if (lBadge >= rBadge) {
        if (l.lowestPriceText !== undefined) mergedProduct.lowestPriceText = l.lowestPriceText;
        if (l.highlights !== undefined) mergedProduct.highlights = l.highlights;
        if (l.category !== undefined) mergedProduct.category = l.category;
        if (l.rating !== undefined) mergedProduct.rating = l.rating;
        if (l.reviewCount !== undefined) mergedProduct.reviewCount = l.reviewCount;
        if (l.lastBadgeCheck !== undefined) mergedProduct.lastBadgeCheck = l.lastBadgeCheck;
      }
      
      if (l.featured !== r.featured) mergedProduct.featured = l.featured;
      
      merged.push(mergedProduct);
    } else {
      merged.push(r);
    }
  }

  // Prepend newly added local products that do not exist in remote
  const newlyAdded = [];
  for (const l of local) {
    if (!remoteMap.has(l.id)) {
      newlyAdded.push(l);
    }
  }

  return [...newlyAdded, ...merged];
}

async function saveProductsFile(products, sha, message, env, _retry = true) {
  // Safety net: whichever code path built this array, never persist two entries
  // with the same ASIN. Keeps the first occurrence — the array is newest-first, so
  // that's the most relevant one — and re-indexes `order` to stay contiguous.
  const seenAsins = new Set();
  const deduped = products.filter(p => {
    if (!p.asin) return true;
    const key = p.asin.toUpperCase();
    if (seenAsins.has(key)) return false;
    seenAsins.add(key);
    return true;
  }).map((p, i) => ({ ...p, order: i }));
  if (deduped.length !== products.length) {
    console.log(`saveProductsFile: dropped ${products.length - deduped.length} duplicate-ASIN entries`);
  }

  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/products.json`;
  const rawJson = JSON.stringify(deduped, null, 2);
  console.log(`saveProductsFile: writing ${(rawJson.length / 1024 / 1024).toFixed(2)}MB, ${deduped.length} products`);
  const body = { message, content: encodeBase64Unicode(rawJson) };
  if (sha) body.sha = sha;
  const resp = await fetchWithTimeout(apiUrl, { method: 'PUT', headers: { ...ghHeaders(env), 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, 15000);
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}));
    const msg = err.message || `GitHub write failed: ${resp.status}`;
    // On SHA conflict, re-read fresh SHA and retry once silently
    if (_retry && (resp.status === 409 || resp.status === 422) && msg.includes('does not match')) {
      console.log('SHA conflict — retrying with fresh SHA and merged products');
      try {
        const { products: freshProducts, sha: freshSha } = await getProductsFile(env);
        const mergedProducts = mergeProducts(products, freshProducts);
        return await saveProductsFile(mergedProducts, freshSha, message, env, false);
      } catch (retryErr) {
        // Retry also failed — throw a clear message for notification
        throw new Error(`SHA conflict — retry also failed: ${retryErr.message}`);
      }
    }
    throw new Error(msg);
  }
  return resp.json();
}

async function getDeletedAsins(env) {
  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/deleted_asins.json`;
  const resp = await fetchWithTimeout(apiUrl, { headers: ghHeaders(env) });
  if (resp.status === 404) return { asins: [], sha: null };
  if (!resp.ok) { const err = await resp.json().catch(() => ({})); throw new Error(err.message || `GitHub fetch failed for deleted_asins: ${resp.status}`); }
  const file = await resp.json();
  const rawBytes = atob(file.content.replace(/\n/g, ''));
  const uint8 = new Uint8Array(rawBytes.length);
  for (let i = 0; i < rawBytes.length; i++) uint8[i] = rawBytes.charCodeAt(i);
  const asins = JSON.parse(new TextDecoder('utf-8').decode(uint8));
  return { asins: Array.isArray(asins) ? asins : [], sha: file.sha };
}

async function addDeletedAsin(asin, env) {
  try {
    const { asins, sha } = await getDeletedAsins(env);
    const upper = asin.toUpperCase();
    if (asins.includes(upper)) return;
    asins.push(upper);
    const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/deleted_asins.json`;
    const body = { message: `Add deleted ASIN: ${upper}`, content: encodeBase64Unicode(JSON.stringify(asins, null, 2)) };
    if (sha) body.sha = sha;
    await fetchWithTimeout(apiUrl, { method: 'PUT', headers: { ...ghHeaders(env), 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  } catch (e) { console.error('Failed to save deleted ASIN:', e.message); }
}

async function restoreAsinIfDeleted(asin, env) {
  if (!asin) return;
  try {
    const { asins, sha } = await getDeletedAsins(env);
    const upper = asin.toUpperCase();
    if (!asins.includes(upper)) return;
    const remaining = asins.filter(a => a !== upper);
    await fetchWithTimeout(`https://api.github.com/repos/akshayjango/dealbuster/contents/deleted_asins.json`, {
      method: 'PUT',
      headers: { ...ghHeaders(env), 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: `Restore ASIN: ${upper}`, content: encodeBase64Unicode(JSON.stringify(remaining, null, 2)), sha }),
    });
  } catch (e) { console.error('Failed to restore ASIN:', e.message); }
}

// ── KV-based blocked brands (autosync + Telegram filter) ─────────────────────

async function getBlockedBrands(env) {
  if (!env.KV) return [];
  const list = await env.KV.get('blocked_brands', 'json');
  return Array.isArray(list) ? list : [];
}

async function setBlockedBrands(brands, env) {
  if (!env.KV) throw new Error('KV not configured');
  await env.KV.put('blocked_brands', JSON.stringify(brands));
}

// Blocklist matches by substring against the product title — there's no
// structured brand field, titles just start with the brand name (e.g. "Xiaomi ...").
function isBrandBlocked(title, blockedBrands) {
  if (!title || !blockedBrands.length) return false;
  const t = title.toLowerCase();
  return blockedBrands.some(b => t.includes(b.toLowerCase()));
}

// ── KV-based sync error notifications ────────────────────────────────────────

async function saveSyncError(source, message, env) {
  if (env.KV) {
    try {
      const existing = await env.KV.get('syncErrors', 'json') || [];
      existing.unshift({ id: Date.now().toString(), source, message, time: new Date().toISOString() });
      await env.KV.put('syncErrors', JSON.stringify(existing.slice(0, 20)));
    } catch (e) { console.error('Failed to save sync error:', e.message); }
  }

  await notifyAdminPush(`Sync error: ${source}`, message.slice(0, 180), env).catch(() => {});

  // Send Telegram Admin Alert on EVERY error / block
  try {
    const token = env.TELEGRAM_BOT_TOKEN;
    const adminId = env.TELEGRAM_ADMIN_ID || TG_ADMIN_ID;
    if (token && adminId) {
      const text = `🚨 <b>Sync Alert [${escHtml(source)}]</b>\n\n<code>${escHtml(message.slice(0, 500))}</code>`;
      await tgSend(token, adminId, text, { parse_mode: 'HTML' }).catch(() => {});
    }
  } catch (e) {
    console.error('Failed to send Telegram sync error notification:', e.message);
  }
}

async function getSyncErrors(env) {
  if (!env.KV) return [];
  try { return await env.KV.get('syncErrors', 'json') || []; }
  catch { return []; }
}

// Drop stale errors for a source once it succeeds again, so the dashboard's
// notification bell doesn't keep showing a 403/timeout from hours ago after
// the next cron tick already recovered on its own.
async function clearSyncError(source, env) {
  if (!env.KV) return;
  try {
    const existing = await env.KV.get('syncErrors', 'json') || [];
    if (!existing.some(e => e.source === source)) return; // nothing to clear, skip the write
    await env.KV.put('syncErrors', JSON.stringify(existing.filter(e => e.source !== source)));
  } catch (e) { console.error('Failed to clear sync error:', e.message); }
}

async function recordScraperStatus(source, status, message, count, env) {
  if (!env.KV) return;
  try {
    const key = 'scraper_status';
    const current = await env.KV.get(key, 'json') || {};
    current[source] = {
      status, // 'working' | 'error'
      message: message || '',
      lastSync: new Date().toISOString(),
      addedCount: count || 0
    };
    await env.KV.put(key, JSON.stringify(current));
  } catch (e) { console.error('Failed to record scraper status:', e.message); }
}

async function getScraperStatus(env) {
  if (!env.KV) return {};
  try { return await env.KV.get('scraper_status', 'json') || {}; }
  catch { return {}; }
}


// ── Web Push (RFC 8291/8188 aes128gcm) — no npm deps, pure Web Crypto ───────
// One admin subscription stored in KV under 'pushSubscription'. Sending costs
// zero KV writes (read-only); only (re)subscribing writes.

function b64urlToBuf(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf;
}
function bufToB64url(buf) {
  let bin = '';
  const arr = new Uint8Array(buf);
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function concatBufs(...bufs) {
  const total = bufs.reduce((n, b) => n + b.byteLength, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const b of bufs) { out.set(new Uint8Array(b), off); off += b.byteLength; }
  return out;
}
async function hmacSha256(keyBytes, data) {
  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, data));
}
async function hkdf(salt, ikm, info, length) {
  const prk = await hmacSha256(salt, ikm);
  const t = await hmacSha256(prk, concatBufs(info, new Uint8Array([1])));
  return t.slice(0, length);
}

async function buildVapidHeader(env, endpoint) {
  const dest = new URL(endpoint);
  const aud = `${dest.protocol}//${dest.host}`;
  const header = { typ: 'JWT', alg: 'ES256' };
  const payload = { aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: env.VAPID_SUBJECT || 'mailto:admin@dealbuster.in' };
  const enc = (obj) => bufToB64url(new TextEncoder().encode(JSON.stringify(obj)));
  const unsigned = `${enc(header)}.${enc(payload)}`;
  const key = await crypto.subtle.importKey('jwk', JSON.parse(env.VAPID_PRIVATE_KEY_JWK), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned));
  return `vapid t=${unsigned}.${bufToB64url(sig)}, k=${env.VAPID_PUBLIC_KEY}`;
}

async function encryptPushPayload(subscription, payloadObj) {
  const uaPublicRaw = b64urlToBuf(subscription.keys.p256dh);
  const authSecret = b64urlToBuf(subscription.keys.auth);

  const asKeyPair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublicRaw = new Uint8Array(await crypto.subtle.exportKey('raw', asKeyPair.publicKey));
  const uaPublicKey = await crypto.subtle.importKey('raw', uaPublicRaw, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const sharedSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaPublicKey }, asKeyPair.privateKey, 256));

  const keyInfo = concatBufs(new TextEncoder().encode('WebPush: info\0'), uaPublicRaw, asPublicRaw);
  const ikm = await hkdf(authSecret, sharedSecret, keyInfo, 32);

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, new TextEncoder().encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, new TextEncoder().encode('Content-Encoding: nonce\0'), 12);

  const plaintext = concatBufs(new TextEncoder().encode(JSON.stringify(payloadObj)), new Uint8Array([2]));
  const aesKey = await crypto.subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['encrypt']);
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, plaintext));

  const rs = 4096;
  const header = concatBufs(
    salt,
    new Uint8Array([(rs >>> 24) & 0xff, (rs >>> 16) & 0xff, (rs >>> 8) & 0xff, rs & 0xff]),
    new Uint8Array([asPublicRaw.length]),
    asPublicRaw
  );
  return concatBufs(header, ciphertext);
}

async function sendWebPushNotification(subscription, payloadObj, env) {
  const body = await encryptPushPayload(subscription, payloadObj);
  const vapidHeader = await buildVapidHeader(env, subscription.endpoint);
  const resp = await fetchWithTimeout(subscription.endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Encoding': 'aes128gcm',
      'TTL': '86400',
      'Authorization': vapidHeader,
    },
    body,
  }, 8000);
  // Gone/expired subscription — drop it so we stop trying (and don't leak a stale write later).
  if ((resp.status === 404 || resp.status === 410) && env.KV) {
    await env.KV.delete('pushSubscription').catch(() => {});
  }
  return resp;
}

async function notifyAdminPush(title, body, env) {
  if (!env.KV || !env.VAPID_PRIVATE_KEY_JWK) return;
  try {
    const sub = await env.KV.get('pushSubscription', 'json');
    if (!sub) return;
    await sendWebPushNotification(sub, { title, body }, env);
  } catch (e) { console.error('Push notify failed:', e.message); }
}

// ── Amazon helpers ────────────────────────────────────────────────────────────

const AMZ_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Accept-Language': 'en-IN,en;q=0.9',
  'Accept': 'text/html',
};

// Hard-timeout wrapper for every third-party fetch (Amazon/DealsRadar/
// IndiaFreeStuff scraping — sites we have no SLA with). Without this, a slow
// or rate-limiting response hangs the fetch indefinitely, which hangs the
// whole cron invocation past Cloudflare's execution limit and gets killed
// silently: no catchable exception, no error logged, nothing committed. This
// is what froze syncs for hours on 2026-07-20/21 (DealsRadar's deals.js fetch
// hung inside the cron_hourly lock, which — being a GLOBAL lock shared with
// cron_10min — then blocked IndiaFreeStuff/price-check from ever acquiring it
// too, even though IFS's own code was fine). AbortError from the timeout is a
// normal catchable exception, so every existing try/catch around a fetch call
// handles it exactly like any other network failure.
async function fetchWithTimeout(url, options = {}, timeoutMs = 8000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchWithProxy(targetUrl, options, timeoutMs, env) {
  const bdKey = env.BRIGHTDATA_API_KEY || '';
  const bdZone = env.BRIGHTDATA_ZONE || '';

  if (bdKey && bdZone) {
    try {
      console.log(`Routing request through Bright Data Web Unlocker (zone: ${bdZone})...`);
      const res = await fetchWithTimeout('https://api.brightdata.com/request', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${bdKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          zone: bdZone,
          url: targetUrl,
          format: 'raw'
        })
      }, timeoutMs);

      if (res.ok) {
        return res;
      }
      console.log(`Bright Data proxy returned status ${res.status}. Trying next proxy...`);
    } catch (e) {
      console.error(`Bright Data proxy request failed: ${e.message}. Trying next proxy...`);
    }
  }

  // For IndiaFreeStuff, try direct fetch first with browser headers
  if (targetUrl.includes('indiafreestuff.in')) {
    try {
      const directRes = await fetchWithTimeout(targetUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Cache-Control': 'no-cache'
        }
      }, timeoutMs);
      if (directRes.ok) {
        const text = await directRes.clone().text().catch(() => '');
        if (!text.includes('Just a moment...') && !text.includes('cf-browser-verification')) {
          console.log(`Direct fetch for IndiaFreeStuff succeeded (${directRes.status})`);
          return directRes;
        }
        console.log(`Direct fetch for IndiaFreeStuff hit Cloudflare WAF challenge, trying proxies...`);
      } else {
        console.log(`Direct fetch for IndiaFreeStuff returned ${directRes.status}, trying proxies...`);
      }
    } catch (e) {
      console.log(`Direct fetch for IndiaFreeStuff failed: ${e.message}, trying proxies...`);
    }
  }

  // 2. ScrapingAnt Proxy (with key rotation and auto-retry on 403 / 429 / Quota / Cloudflare WAF)
  const saKeysStr = env.SCRAPINGANT_API_KEYS || '';
  const saKeys = saKeysStr.split(',').map(k => k.trim()).filter(Boolean);

  if (saKeys.length > 0) {
    for (let idx = 0; idx < saKeys.length; idx++) {
      const key = saKeys[idx];
      const proxyUrl = `https://api.scrapingant.com/v2/general?url=${encodeURIComponent(targetUrl)}&x-api-key=${key}&browser=false`;
      try {
        console.log(`Trying ScrapingAnt proxy with key index ${idx} (browser=false)...`);
        const res = await fetchWithTimeout(proxyUrl, options, timeoutMs);
        const text = await res.clone().text().catch(() => '');

        const isQuotaErr = res.status === 403 && (text.includes('quota limit') || text.includes('API token') || text.includes('out of request credits'));
        const isWafBlock = res.status === 403 || text.includes('Just a moment...') || text.includes('cf-browser-verification');

        if (isQuotaErr) {
          console.log(`ScrapingAnt key index ${idx} quota limit reached. Rotating to next key...`);
          continue;
        }

        if (isWafBlock) {
          console.log(`ScrapingAnt key index ${idx} hit Cloudflare WAF on browser=false. Retrying key index ${idx} with browser=true...`);
          const jsProxyUrl = `https://api.scrapingant.com/v2/general?url=${encodeURIComponent(targetUrl)}&x-api-key=${key}&browser=true`;
          const jsRes = await fetchWithTimeout(jsProxyUrl, options, Math.max(timeoutMs, 25000));
          const jsText = await jsRes.clone().text().catch(() => '');
          if (jsRes.ok && !jsText.includes('Just a moment...') && !jsText.includes('quota limit')) {
            return jsRes;
          }
          console.log(`ScrapingAnt key index ${idx} browser=true returned status ${jsRes.status}. Rotating to next key...`);
          continue;
        }

        if (res.ok) {
          return res;
        }
      } catch (err) {
        console.log(`ScrapingAnt proxy key index ${idx} failed with error: ${err.message}. Rotating to next key...`);
      }
    }
  }

  const keysStr = env.SCRAPER_API_KEYS || '';
  const keys = keysStr.split(',').map(k => k.trim()).filter(Boolean);

  function getProxyRequestUrl(key, target) {
    return `http://api.scraperapi.com/?api_key=${key}&url=${encodeURIComponent(target)}`;
  }

  // Fallback to legacy SCRAPER_API_URL if SCRAPER_API_KEYS is not configured
  if (keys.length === 0) {
    const primaryUrl = env.SCRAPER_API_URL;
    if (!primaryUrl) {
      throw new Error('Neither Bright Data, ScrapingAnt, nor SCRAPER_API_KEYS / SCRAPER_API_URL is configured');
    }
    let url = primaryUrl;
    if (!url.includes('url=')) {
      url += (url.includes('?') ? '&' : '?') + 'url=';
    }
    const proxyUrl = url + encodeURIComponent(targetUrl);
    return await fetchWithTimeout(proxyUrl, options, timeoutMs);
  }

  // Iterate through ScraperAPI keys in order
  for (let idx = 0; idx < keys.length; idx++) {
    const key = keys[idx];
    const proxyUrl = getProxyRequestUrl(key, targetUrl);
    try {
      console.log(`Trying ScraperAPI proxy with key index ${idx}...`);
      const res = await fetchWithTimeout(proxyUrl, options, timeoutMs);
      const text = await res.clone().text().catch(() => '');
      
      const isBlockedOrExhausted = res.status === 403 || res.status === 429 || text.includes('limit') || text.includes('suspended') || text.includes('billing') || text.includes('Just a moment...');
      
      if (isBlockedOrExhausted) {
        console.log(`ScraperAPI proxy key index ${idx} exhausted/blocked (${res.status}). Trying next key...`);
        continue;
      }
      
      if (res.ok) {
        return res;
      }
    } catch (err) {
      console.log(`ScraperAPI proxy key index ${idx} failed with error: ${err.message}. Trying next key...`);
      if (idx === keys.length - 1) {
        throw err;
      }
    }
  }
  
  throw new Error('All configured proxy keys were exhausted or blocked');
}

// Derive product image from ASIN — no subrequest needed
function asinImage(asin) {
  return `https://m.media-amazon.com/images/P/${asin}.01._SL500_.jpg`;
}

// Map Amazon breadcrumb text → our category
function mapAmazonBreadcrumbCategory(text) {
  const c = (text || '').toLowerCase();
  if (/electron|computer|laptop|mobile|phone|camera|television|\btv\b|headphone|speaker|tablet|software|video game|gps|printer|projector|router|networking/.test(c)) return 'Electronics';
  if (/cloth|fashion|shirt|shoe|jeans|kurta|saree|bag|wallet|jewel|watch|luggage|apparel|handbag|dress|skirt|sari|lehenga|kurti|ethnic/.test(c)) return 'Fashion';
  if (/home|kitchen|garden|outdoor|tool|furniture|lighting|pet|lawn|automotive|industrial|storage|cookware|bedding|bath|curtain|mattress|lamp|fan|iron|mixer|grinder|cooker|utensil|cleaning|mop|broom|bucket/.test(c)) return 'Home';
  if (/beauty|personal care|cosmetic|fragrance|perfume|makeup|skincare|haircare|shampoo|conditioner|lotion|serum|cream|face wash/.test(c)) return 'Beauty';
  if (/health|sport|fitness|gym|baby|grocery|supplement|protein|vitamin|medicine|yoga|cycle|bicycle|cricket|football|badminton|toy|game/.test(c)) return 'Health';
  return null;
}

// Detect category from product title (used at sync time)
function detectCategoryFromTitle(title) {
  const tl = (title || '').toLowerCase();
  if (/\bshirt\b|\bshoe\b|\bjeans\b|\bkurta\b|\bsaree\b|\bsari\b|\bkurti\b|\bwallet\b|\bjewel|\bwatch\b|\bluggage\b|\bdress\b|\bskirt\b|\bblouse\b|\bsandal\b|\bhandbag\b|\bpurse\b|\bclutch\b|\bsunglasses\b/.test(tl)) return 'Fashion';
  if (/\bserum\b|\bbeauty\b|\bperfume\b|\blotion\b|\bconditioner\b|\bfoundation\b|\blipstick\b|\beyeliner\b|\bmakeup\b|\bskincare\b|\bhaircare\b|\bface.?wash\b|\bmoisturi|\bshampoo\b/.test(tl)) return 'Beauty';
  if (/\bsupplement\b|\bprotein\b|\bvitamin\b|\bcapsule\b|\bhealth\b|\bmedical\b|\bglucose\b|\bbp.?monitor|\bsports?\b|\bfitness\b|\bgym\b|\byoga\b|\bcycle\b|\bbicycle\b|\bcricket\b|\bfootball\b|\bbadminton\b|\btoy\b|\bpuzzle\b|\bbaby\b|\bdiaper\b/.test(tl)) return 'Health';
  if (/\bkitchen\b|\bfurniture\b|\btowel\b|\bcurtain\b|\bbulb\b|\bmop\b|\bbroom\b|\bvacuum\b|\biron\b|\bmixer\b|\bgrinder\b|\bcooker\b|\bfan\b|\blamp\b|\bbucket\b|\bstorage\b|\bpillow\b|\bblanket\b|\bbedsheet\b|\bsofa\b|\bchair\b|\bwardrobe\b|\bshelf\b|\bgarden\b|\bplant\b|\bseed\b|\bdrill\b|\bhammer\b|\bwrench\b|\bsaw\b|\bmower\b|\bpruner\b|\bdetergent\b|\butensil\b|\bcookware\b/.test(tl)) return 'Home';
  return 'Electronics';
}

// Used only by hourly badge-check cron (not sync)
// Returns { badge: string|null, highlights: string[], category: string|null }
async function fetchAmazonPageData(asin) {
  try {
    const r = await fetchWithTimeout(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS }, 5000);
    if (!r.ok) return { badge: null, highlights: [], category: null, rating: null, reviewCount: null, lowStock: false, undeliverable: false, isOOS: false };
    const html = await r.text();

    const badgeM = html.match(/(Lowest\s+price\s+(?:in\s+(?:the\s+|last\s+|past\s+)?\d+\s+days?|ever)|Best\s+price\s+in\s+(?:the\s+|last\s+|past\s+)?\d+\s+days?)/i);
    let badge = badgeM ? badgeM[1].trim() : null;
    if (!badge) {
      const altBadgeM = html.match(/class="[^"]*a-badge-text[^"]*"[^>]*>\s*([^<]*Lowest[^<]*)</i) ||
                        html.match(/"badgeText"\s*:\s*"([^"]*Lowest[^"]*)"/i);
      if (altBadgeM && altBadgeM[1].length < 40) badge = altBadgeM[1].trim();
    }

    const highlights = [];
    function extractBullets(sc) {
      for (const mm of sc.matchAll(/class="a-list-item"[^>]*>([\s\S]*?)<\/span>/g)) {
        const t = mm[1].replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim()
          .replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/&quot;/g, '"');
        if (t.length > 15 && t.length < 250 && t.split(/\s+/).length >= 3 &&
            !t.toLowerCase().startsWith('make sure') && !t.toLowerCase().startsWith('click') &&
            !/^[\s\W]+$/.test(t)) {
          highlights.push(t);
        }
        if (highlights.length >= 5) break;
      }
    }
    const fbM = html.match(/id="feature-bullets"([\s\S]{0,6000})/);
    if (fbM) extractBullets(fbM[1]);
    if (!highlights.length) {
      const abM = html.match(/id="apex_desktop_feature_bullets[\w-]*"([\s\S]{0,6000})/);
      if (abM) extractBullets(abM[1]);
    }
    if (!highlights.length) {
      const ovM = html.match(/id="productOverview_feature_div"([\s\S]{0,4000})/);
      if (ovM) {
        for (const mm of ovM[1].matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)) {
          const cells = [...mm[1].matchAll(/<(?:td|th)[^>]*>([\s\S]*?)<\/(?:td|th)>/g)]
            .map(c => c[1].replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim()).filter(Boolean);
          if (cells.length >= 2) { highlights.push(`${cells[0]}: ${cells[1]}`); if (highlights.length >= 5) break; }
        }
      }
    }

    // Extract category from breadcrumb
    let category = null;
    const bcM = html.match(/id="wayfinding-breadcrumbs[^"]*"([\s\S]{0,3000})/);
    if (bcM) {
      const links = [...bcM[1].matchAll(/<a[^>]*>([^<]+)<\/a>/g)].map(m => m[1].trim());
      for (const link of links) {
        const mapped = mapAmazonBreadcrumbCategory(link);
        if (mapped) { category = mapped; break; }
      }
    }

    // Star rating + review count — multi-pattern JSON-LD & Regex parsing
    let rating = null;
    let reviewCount = null;

    const schemaRegex = /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
    let match;
    while ((match = schemaRegex.exec(html)) !== null) {
      try {
        const data = JSON.parse(match[1].trim());
        const items = Array.isArray(data) ? data : [data];
        for (const item of items) {
          if (item && item.aggregateRating) {
            if (item.aggregateRating.ratingValue != null) rating = parseFloat(item.aggregateRating.ratingValue);
            if (item.aggregateRating.reviewCount || item.aggregateRating.ratingCount) {
              reviewCount = parseInt(item.aggregateRating.reviewCount || item.aggregateRating.ratingCount, 10);
            }
            break;
          }
        }
      } catch (e) {}
    }

    if (rating === null || isNaN(rating)) {
      const ratingM = html.match(/"ratingValue"\s*:\s*"?(\d(?:\.\d)?)"?/i) ||
                      html.match(/(\d(?:\.\d)?)\s+out of 5 stars/i) ||
                      html.match(/(\d(?:\.\d)?)\s+out of 5/i) ||
                      html.match(/class="[^\"]*a-icon-star[^\"]*"[^\>]*>\s*<span[^\>]*>(\d(?:\.\d)?)/i) ||
                      html.match(/a-star-(?:small-)?(\d)-(\d)/i);
      if (ratingM) {
        if (ratingM[2] !== undefined && ratingM[1].length === 1 && ratingM[2].length === 1) {
          rating = parseFloat(`${ratingM[1]}.${ratingM[2]}`);
        } else {
          rating = parseFloat(ratingM[1]);
        }
      }
    }

    if (reviewCount === null || isNaN(reviewCount)) {
      const reviewM = html.match(/id="acrCustomerReviewText"[^>]*>([\d,]+)\s*ratings?/i) ||
                      html.match(/"ratingCount"\s*:\s*"?([\d,]+)"?/i) ||
                      html.match(/([\d,]+)\s*customer ratings/i);
      if (reviewM) reviewCount = parseInt(reviewM[1].replace(/,/g, ''), 10);
    }

    // Check low stock ("Only 1 left in stock.", "Only 2 left in stock.", etc.)
    const lowStockM = html.match(/only\s+([1-4])\s+left\s+in\s+stock/i);
    const lowStock = !!lowStockM;

    // Check undeliverable message
    const undeliverable = html.toLowerCase().includes('cannot be shipped to your selected delivery location');

    // Check Out-of-Stock ("Currently unavailable", "We don't know when or if this item will be back in stock")
    const htmlLower = html.toLowerCase();
    const isOOS = htmlLower.includes('currently unavailable') ||
                  htmlLower.includes("don't know when or if this item will be back in stock") ||
                  html.includes('id="outOfStock"') ||
                  html.includes('schema.org/OutOfStock') ||
                  html.includes('schema.org/outOfStock') ||
                  html.includes('"availability":"OutOfStock"') ||
                  html.includes('"availability":"http://schema.org/OutOfStock"');

    return { badge, highlights, category, rating, reviewCount, lowStock, undeliverable, isOOS };
  } catch { return { badge: null, highlights: [], category: null, rating: null, reviewCount: null, lowStock: false, undeliverable: false, isOOS: false }; }
}

// ── DealsRadar sync (30 new deals / hour, 40 on manual) ───────────────────────

function parseDealsSpyHtml(html) {
  const cards = html.split(/<div class="dc-card/gi).slice(1);
  const parsedDeals = [];
  for (const card of cards) {
    const titleM = card.match(/class="dc-title"[^>]*>\s*([\s\S]*?)\s*<\/p>/i) || card.match(/class="dc-title"[^>]*>\s*([\s\S]*?)\s*<\/a>/i);
    if (!titleM) continue;
    const title = decodeHtmlEntities(titleM[1].replace(/<[^>]+>/g, '').replace(/\s+/g, ' ')).trim();

    const imgM = card.match(/<img[^>]*class="[^"]*lazy[^"]*"[^>]*data-src="([^"]+)"/i) || card.match(/<img[^>]*src="([^"]+)"/i);
    const image = imgM ? imgM[1].trim() : '';

    const priceM = card.match(/class="dc-price"[^>]*>\s*(₹\s*[\d,]+)/i);
    const price = priceM ? priceM[1].trim() : '';

    const mrpM = card.match(/class="dc-mrp"[^>]*>\s*(₹\s*[\d,]+)/i);
    const mrp = mrpM ? mrpM[1].trim() : price;

    const codeM = card.match(/data-code="([^"]+)"/i);
    let originalUrl = '';
    if (codeM) {
      const code = codeM[1];
      const utmContentM = code.match(/utm_content=([^&]+)/);
      if (utmContentM) {
        try {
          originalUrl = atob(decodeURIComponent(utmContentM[1]));
        } catch (e) {
          // ignore base64 errors
        }
      }
    }

    if (title && originalUrl) {
      parsedDeals.push({
        title,
        image,
        price,
        mrp,
        link: originalUrl
      });
    }
  }
  return parsedDeals;
}

async function scrapeIfsNonAmazonDeals(env) {
  if (!env.SCRAPER_API_URL) return [];
  const targetUrls = [
    'https://www.indiafreestuff.in/trending',
    'https://www.indiafreestuff.in/stores/flipkart',
    'https://www.indiafreestuff.in/stores/myntra',
    'https://www.indiafreestuff.in/stores/ajio',
    'https://www.indiafreestuff.in/stores/meesho',
    'https://www.indiafreestuff.in/stores/nykaa',
    'https://www.indiafreestuff.in/stores/tatacliq',
    'https://www.indiafreestuff.in/stores/shopsy',
  ];

  const candidateMap = new Map();
  for (const targetUrl of targetUrls) {
    try {
      const r = await fetchWithProxy(targetUrl, { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } }, 20000, env);
      if (!r.ok) continue;
      const html = await r.text();
      const blocks = html.split(/<div class="product-item">/g);
      
      for (let i = 1; i < blocks.length; i++) {
        const block = blocks[i];
        
        // Check if block contains any supported stores
        const storeMatch = block.match(/\/stores\/(flipkart|myntra|ajio|shopsy|meesho|nykaa|tatacliq)/i);
        if (!storeMatch) continue;
        const store = storeMatch[1].toLowerCase();

        const titleM = block.match(/class="item-title"[^>]*>\s*([^<]{5,}?)\s*<\/a>/i);
        if (!titleM) continue;
        let title = decodeHtmlEntities(titleM[1].replace(/\s+/g,' ').trim());
        title = title.replace(/\s*Rs\.\s*[\d,]+\s*[-–]\s*(?:Flipkart|Myntra|Ajio|Shopsy|Meesho|Nykaa|TataCliq)\s*$/i, '').trim();
        if (!title || title.length < 5) continue;

        const thumbM = block.match(/data-original="([^"]+)"/i) || block.match(/src="([^"]+)"/i);
        const image = thumbM ? thumbM[1] : '';

        const priceM = block.match(/class="new-price"[\s\S]*?fa-inr[^>]*><\/i>\s*([\d,]+)/i);
        const mrpM   = block.match(/class="old-price"[\s\S]*?fa-inr[^>]*><\/i>\s*([\d,]+)/i);
        const priceVal = priceM ? parseInt(priceM[1].replace(/,/g,'')) : 0;
        const mrpVal   = mrpM   ? parseInt(mrpM[1].replace(/,/g,''))   : priceVal;
        
        const price = priceVal > 0 ? '₹' + priceVal.toLocaleString('en-IN') : '';
        const mrp = mrpVal > 0 ? '₹' + mrpVal.toLocaleString('en-IN') : price;

        const rtoM = block.match(/href="https?:\/\/www\.indiafreestuff\.in\/\?rto=([^"]+)"/i);
        if (!rtoM) continue;
        const rtoParam = rtoM[1];

        if (!candidateMap.has(rtoParam)) {
          candidateMap.set(rtoParam, { title, image, price, mrp, rtoParam, store });
        }
      }
    } catch (e) {
      console.error(`Non-Amazon IFS fetch failed for ${targetUrl}:`, e.message);
    }
  }

  const candidates = Array.from(candidateMap.values());

  // Resolve target URLs (limit to 15 candidates to prevent hitting Cloudflare subrequest limits)
  const syncLimit = Math.min(candidates.length, 15);
  const targetCandidates = candidates.slice(0, syncLimit);

  const resolved = [];
  const chunkSize = 5;
  for (let i = 0; i < targetCandidates.length; i += chunkSize) {
    const chunk = targetCandidates.slice(i, i + chunkSize);
    const chunkResolved = await Promise.all(chunk.map(async (item) => {
      let resolvedUrl = '';
      try {
        const redirTarget = `https://www.indiafreestuff.in/?rto=${item.rtoParam}`;
        const red = await fetchWithProxy(redirTarget, {
          redirect: 'manual',
          headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] },
        }, 15000, env);
        resolvedUrl = red.headers.get('location') || red.url || '';
      } catch (err) {}
      return { ...item, link: resolvedUrl };
    }));
    resolved.push(...chunkResolved);
  }

  return resolved.filter(item => {
    if (!item.link) return false;
    const l = item.link.toLowerCase();
    return l.includes('flipkart.com') || l.includes('fkrt.it') || l.includes('fktr.in') ||
           l.includes('myntra.com') || l.includes('ajio.com') || l.includes('shopsy.in') ||
           l.includes('meesho.com') || l.includes('nykaa.com') || l.includes('tatacliq.com');
  });
}

async function scrapeAndSyncDealsSpy(env, limit = 30) {
  let html;
  try {
    const targetUrl = 'https://www.dealsspy.in/offers/amazon';
    const r = await fetchWithProxy(targetUrl, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' } }, 20000, env);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    html = await r.text();
  } catch (e) {
    const msg = `DealsSpy Amazon fetch failed: ${e.message}`;
    console.error(msg);
    await saveSyncError('DealsSpyAmazon', msg, env);
    await recordScraperStatus('dealspy', 'error', msg, 0, env);
    return { success: false, count: 0, message: msg };
  }

  let allDeals = [];
  try {
    allDeals = parseDealsSpyHtml(html);
  } catch (e) {
    const msg = `DealsSpy Amazon parse failed: ${e.message}`;
    await saveSyncError('DealsSpyAmazon', msg, env);
    await recordScraperStatus('dealspy', 'error', msg, 0, env);
    return { success: false, count: 0, message: msg };
  }

  const { products, sha } = await getProductsFile(env);
  let { asins: deletedAsins } = await getDeletedAsins(env).catch(() => ({ asins: [] }));
  const deletedSet = new Set(deletedAsins.map(a => a.toUpperCase()));
  const blockedBrands = await getBlockedBrands(env);

  // Build ASIN → product index
  const existingByAsin = new Map(products.filter(p => p.asin).map(p => [p.asin.toUpperCase(), p]));
  const seenThisRun = new Set();

  const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const added = [];
  const updated = [];

  for (const deal of allDeals) {
    const asinM = deal.link.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i);
    if (!asinM) continue;
    const asin = asinM[1];
    const asinUpper = asin.toUpperCase();
    if (deletedSet.has(asinUpper)) continue;
    if (seenThisRun.has(asinUpper)) continue;
    seenThisRun.add(asinUpper);
    if (isBrandBlocked(deal.title, blockedBrands)) continue;

    const parsedPriceVal = parsePrice(deal.price);
    const price = parsedPriceVal || 0;
    if (price <= 0) continue;
    
    const parsedMrpVal = parsePrice(deal.mrp);
    const mrp = parsedMrpVal || price;
    const discNum = mrp > price ? Math.round((1 - price / mrp) * 100) : 0;
    const priceStr = '₹' + price.toLocaleString('en-IN');
    const mrpStr = '₹' + mrp.toLocaleString('en-IN');
    const discStr = discNum > 0 ? `-${discNum}%` : '0%';
    const baseLink = `https://www.amazon.in/dp/${asin}`;
    const link = hasUptoOffInTitle(deal.title) ? buildManualCueLink(baseLink, env) : `${baseLink}?tag=${TAG}`;

    const category = detectCategoryFromTitle(deal.title);
    const highlights = [];

    if (existingByAsin.has(asinUpper)) {
      const existing = existingByAsin.get(asinUpper);
      if (isDead(existing)) continue;
      const existingPrice = parsePrice(existing.price);
      const newPrice = parsePrice(priceStr);
      
      if (newPrice && existingPrice && newPrice < existingPrice) {
        const priceHistory = appendPriceHistory(existing, priceStr);
        const updatedProduct = { ...existing, price: priceStr, mrp: mrpStr, disc: discStr, link, outOfStock: false, priceHistory };
        const origPrice = parsePrice(existing.originalPrice || existing.price);
        if (origPrice && newPrice && shouldDemote(origPrice, newPrice)) {
          updatedProduct.priceIncreased = true;
        } else {
          delete updatedProduct.priceIncreased;
        }
        updated.push(updatedProduct);
      }
    } else {
      if (added.length >= limit) break;
      const image = deal.image || asinImage(asin);

      added.push({
        id: `ds_${Date.now()}_${added.length}`,
        asin, title: deal.title || '', price: priceStr, mrp: mrpStr, disc: discStr,
        image, link, category, highlights, lowestPriceText: null, featured: false, hidden: false, outOfStock: false,
        order: 0, addedAt: new Date().toISOString(), originalPrice: priceStr,
      });
    }
  }

  if (added.length === 0 && updated.length === 0) {
    await clearSyncError('DealsSpyAmazon', env);
    await recordScraperStatus('dealspy', 'working', 'No new deals', 0, env);
    return { success: true, count: 0, message: 'No new or updated DealsSpy Amazon deals.' };
  }

  const updatedByAsin = new Map(updated.map(p => [p.asin.toUpperCase(), p]));
  const base = products.map(p => (p.asin && updatedByAsin.get(p.asin.toUpperCase())) || p);

  const final = await capLiveAndBury([...added, ...base], env);

  const msg = `DS Amazon sync: +${added.length} new, ${updated.length} updated`;
  await saveProductsFile(final, sha, msg, env);
  await clearSyncError('DealsSpyAmazon', env);
  await recordScraperStatus('dealspy', 'working', msg, added.length, env);
  return { success: true, added: added.length, updated: updated.length, message: msg, addedProducts: added };
}

// Helper to extract original URL from CueLinks URL
function getOriginalUrl(url) {
  if (url.includes('linksredirect.com')) {
    try {
      const u = new URL(url);
      return u.searchParams.get('url') || url;
    } catch (e) {
      return url;
    }
  }
  return url;
}

// Helper to strip feed error prefixes (e.g. "[Image Error]", "[MRP Error]", "[Error]") from titles
function sanitizeTitle(title) {
  if (!title || typeof title !== 'string') return '';
  return title
    .replace(/\[\s*[^\]]*Error\s*\]/gi, '')
    .replace(/\s+/g, ' ')
    .trim();
}

// Helper to check if title contains "upto X% off" or "up to X% off"
function hasUptoOffInTitle(title) {
  if (!title || typeof title !== 'string') return false;
  return /\b(?:up\s*to|upto)\s*\d+\s*%\s*off\b/i.test(title);
}

// Hand-built fallback — used when CUELINKS_API_KEY isn't configured, or the
// real API call fails/errors (network issue, outage). Strictly no worse than
// what this function did before the real API integration existed.
function buildManualCueLink(url, env = {}) {
  const pubId = (env && env.CUELINKS_PUB_ID) || '268568';
  return `https://linksredirect.com/?pub_id=${pubId}&subid=dealbuster&url=${encodeURIComponent(url)}`;
}

// Converts a scraped merchant URL into a real tracked CueLinks affiliate link,
// and asks CueLinks' AI to clean up the (often SEO-stuffed) scraped title —
// via /links/monetize, a strict superset of /links/convert (same
// link/affiliated fields, plus title/ai_rewritten). Non-Amazon deals only —
// Amazon never touches CueLinks and this isn't wired into that pipeline.
// Returns { link, title, affiliated }:
//   affiliated === true  → real tracking_url from CueLinks, confirmed active campaign
//   affiliated === false → CueLinks' v3 API doesn't recognize this URL as
//                          affiliated for this key's channel. NOT currently
//                          trusted as "definitely a dead link" — verified
//                          2026-08-21 that even known-good, currently-live
//                          Flipkart product URLs (site already earns commission
//                          on Flipkart via the legacy pub_id-based link) come
//                          back affiliated:false here, meaning the v3 API key's
//                          channel likely isn't recognized/approved for Flipkart
//                          in CueLinks' newer campaign system yet, separate from
//                          the older pub_id auth. Falls back to the manual link
//                          wrap rather than skipping publishing — do NOT change
//                          this to skip-on-false until affiliated:true has been
//                          confirmed working on at least one real deal.
//   affiliated === null  → key not configured, or the API call itself failed —
//                          same link fallback either way.
// Title always falls back to the original scraped title on any uncertainty —
// per CueLinks' own docs, "If the AI service is unavailable, the original
// title is returned... the request never fails due to AI," so this mirrors
// that same never-worse-than-before guarantee for the link side too.
async function convertToCueLink(url, title, env, inputDescription, channelId) {
  const apiKey = (env.CUELINKS_API_KEY || '').trim();
  if (!apiKey) return { link: buildManualCueLink(url), title, affiliated: null };

  try {
    const reqBody = { url, title, rewrite_using_ai: true, subid: 'dealbuster' };
    if (inputDescription) reqBody.description = inputDescription;
    if (channelId) reqBody.channel_id = Number(channelId);
    const res = await fetchWithTimeout('https://developers.cuelinks.com/pub_api/v3/links/monetize', {
      method: 'POST',
      headers: {
        'Authorization': `Token ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(reqBody),
    // 20s, not 10s — rewriting both a title AND a description takes CueLinks'
    // AI noticeably longer than title-only rewrites (confirmed: a title+description
    // call timed out at 10s on 2026-08-21 while title-only calls consistently
    // completed well within it). Still falls back safely either way.
    }, 20000);

    if (!res.ok) {
      const errBody = await res.text().catch(() => '');
      console.log(`CueLinks monetize API returned ${res.status} for ${url} — falling back to manual wrap. Body: ${errBody.slice(0, 300)}`);
      return { link: buildManualCueLink(url), title, affiliated: null, debugError: `HTTP ${res.status}: ${errBody.slice(0, 300)}` };
    }

    const body = await res.json();
    const data = body?.data;
    // Keep original normal title for deals per user request (do not overwrite with CueLinks AI title)
    const responseDescription = data?.description || null;

    if (data?.affiliated === true && data.tracking_url) {
      return { link: data.tracking_url, title, affiliated: true, description: responseDescription };
    }
    // Not trusted as a real "dead link" signal yet — see comment above. Publish
    // using the manual wrap (same as always) so a channel/access mismatch on
    // CueLinks' side can't silently stop deal publishing.
    console.log(`CueLinks reports affiliated:false for ${url} — publishing via manual wrap anyway (see convertToCueLink comment).`);
    return { link: buildManualCueLink(url), title, affiliated: false, description: responseDescription };
  } catch (e) {
    console.log(`CueLinks monetize API call failed for ${url}: ${e.message} — falling back to manual wrap.`);
    return { link: buildManualCueLink(url), title, affiliated: null, debugError: e.message };
  }
}

// CueLinks' AI descriptions come back as several sentences run together with
// no separator ("Save as much as 60% on selected items!Offers are inclusive
// for every shopper." — confirmed from live /offers feed examples), rather
// than actual bullet points. Splits on sentence-ending punctuation so each
// sentence becomes one highlight, capped at 5 to match the site's highlights
// UI. Returns [] (not a fallback array) if there's nothing usable — callers
// already default to [] today, so this can't make things worse than before.
function splitDescriptionIntoHighlights(description) {
  if (!description) return [];
  return description
    .split(/(?<=[.!?])\s*(?=[A-Z])|(?<=[.!?])$/)
    .map(s => s.trim())
    .filter(s => s.length > 3)
    .slice(0, 5);
}

// CueLinks has no documented webhook/notification for access-request status
// changes (checked their docs — Getting Started/API Reference/Links/
// Campaigns/Reference Data, no Webhooks section). Polling is the only option.
// Checked twice daily (piggybacked on the existing Amazon-deals-sweep cron
// slot) rather than more often — approval is a human/business process on the
// advertiser's side, not something that resolves in minutes, and this avoids
// burning extra CueLinks API calls for no reason. Surfaces through the same
// syncErrors bell/push-notification path as every other admin alert tonight.
// One tracked campaign per store with a pending access request — add more
// here if other stores' access gets requested later.
const CUELINKS_TRACKED_CAMPAIGNS = [
  { id: 1, name: 'Flipkart' },
  { id: 101, name: 'Myntra' },
  { id: 2589, name: 'Ajio' },
];

async function checkCueLinksCampaignAccess(env) {
  const apiKey = (env.CUELINKS_API_KEY || '').trim();
  if (!apiKey) return;

  for (const { id, name } of CUELINKS_TRACKED_CAMPAIGNS) {
    let campaign;
    try {
      const res = await fetchWithTimeout(
        `https://developers.cuelinks.com/pub_api/v3/campaigns/${id}`,
        { headers: { 'Authorization': `Token ${apiKey}` } },
        10000
      );
      if (!res.ok) continue; // transient API issue — just try again next scheduled check
      const body = await res.json();
      campaign = body?.data;
    } catch (e) {
      console.log(`CueLinks campaign access check failed for ${name} (${id}): ${e.message}`);
      continue;
    }
    if (!campaign) continue;

    const kvKey = `cuelinks_${name.toLowerCase()}_access_status`;
    const prevStatus = await env.KV.get(kvKey);
    const currentStatus = campaign.access_status;
    if (currentStatus === prevStatus) continue; // no change — nothing to do, no KV write

    await env.KV.put(kvKey, currentStatus);

    if (currentStatus !== 'not_applied' && currentStatus !== 'pending') {
      // Genuinely resolved (approved/open, or rejected) — this is the actual
      // signal to act on: re-test /test-cuelink and, if approved, the
      // affiliated:true path in convertToCueLink starts being used automatically.
      await saveSyncError(
        `CueLinks${name}Access`,
        `${name} campaign access_status changed: ${prevStatus || '(unknown)'} → ${currentStatus}. Check /test-cuelink to confirm affiliated:true is now returned.`,
        env
      );
    }
  }
}

// Generic across Flipkart/Myntra/Ajio/Shopsy/Meesho/TataCliq/Nykaa product pages —
// checks the live listing (via the proxy, so JS-rendered stock/price blocks resolve)
// before it's ever published, instead of trusting the aggregator feed's stale snapshot.
const OOS_PHRASES = [
  'sold out', 'out of stock', 'currently unavailable', 'product unavailable',
  'no longer available', 'notify me', 'item is unavailable',
  'this product is currently unavailable', 'coming back soon',
  'cannot be delivered', 'not deliverable', 'item currently unavailable',
];

function extractPageListedPrice(html) {
  const patterns = [
    /property="product:price:amount"\s+content="([\d.]+)"/i,
    /itemprop="price"[^>]*content="([\d.]+)"/i,
    /"price"\s*:\s*"?([\d.]+)"?/i,
  ];
  for (const re of patterns) {
    const m = html.match(re);
    if (m) {
      const val = parseFloat(m[1]);
      if (val > 0) return val;
    }
  }
  return null;
}

// Flipkart's delivery-availability text ("Not deliverable at your location") only
// renders against a saved account address — an anonymous page load always shows
// "Location not set" regardless of the item's actual serviceability. Bright Data's
// Web Unlocker (tried first in fetchWithProxy) silently ignores custom cookies and
// explicitly disallows forwarding auth/session credentials, so it can't be used
// here — it would "succeed" while still checking anonymously. ScrapingAnt's
// `cookies` param does forward a real session cookie to the target site, and works
// in plain (browser=false) mode, so this stays at the normal 1-credit cost instead
// of the 10-125x premium that Puppeteer/JS-interaction modes would require.
async function fetchFlipkartWithSession(url, env, timeoutMs) {
  const rawCookie = env.FLIPKART_SESSION_COOKIE || '';
  const saKeysStr = env.SCRAPINGANT_API_KEYS || '';
  const saKeys = saKeysStr.split(',').map(k => k.trim()).filter(Boolean);
  if (!rawCookie || saKeys.length === 0) return null;

  const cookieParam = rawCookie.split(';').map(p => p.trim()).filter(Boolean).join(';');

  for (let idx = 0; idx < saKeys.length; idx++) {
    const key = saKeys[idx];
    const proxyUrl = `https://api.scrapingant.com/v2/general?url=${encodeURIComponent(url)}&x-api-key=${key}&browser=false&cookies=${encodeURIComponent(cookieParam)}`;
    try {
      const res = await fetchWithTimeout(proxyUrl, { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } }, timeoutMs);
      if (res.status !== 403 && res.status !== 429) return res;
      console.log(`Flipkart authed check: ScrapingAnt key index ${idx} returned ${res.status}, trying next key...`);
    } catch (e) {
      console.log(`Flipkart authed check via ScrapingAnt key index ${idx} failed: ${e.message}`);
    }
  }
  return null;
}

function isFlipkartLink(url) {
  const l = url.toLowerCase();
  return l.includes('flipkart.com') || l.includes('fkrt.it') || l.includes('fktr.in');
}

async function checkListingAvailability(url, scrapedPrice, env) {
  // cookieHealth is null when this isn't an authed-Flipkart check at all (non-Flipkart
  // link, or FLIPKART_SESSION_COOKIE not configured) — the caller uses it to decide
  // whether to raise/clear the FlipkartSessionCookie dashboard notification.
  let cookieHealth = null;
  try {
    let r = null;
    const cookieConfigured = !!(env.FLIPKART_SESSION_COOKIE || '').trim();
    if (isFlipkartLink(url) && cookieConfigured) {
      r = await fetchFlipkartWithSession(url, env, 15000);
      cookieHealth = r ? 'pending' : 'request_failed';
    }
    if (!r) {
      r = await fetchWithProxy(url, { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } }, 15000, env);
    }
    if (r.status === 404) return { available: false, reason: 'http_404', cookieHealth, rating: null, reviewCount: null };
    if (!r.ok) return { available: true, cookieHealth, rating: null, reviewCount: null }; // Trust aggregator feed on 403/WAF/SPA shells
    const html = await r.text();
    if (html.length < 200) return { available: false, reason: 'empty_page', cookieHealth, rating: null, reviewCount: null };

    // "Location not set" is what Flipkart shows an anonymous visitor
    if (cookieHealth === 'pending') {
      cookieHealth = html.toLowerCase().includes('location not set') ? 'expired' : 'ok';
    }

    // Only mark OOS if explicitly declared in JSON-LD schema or product availability block
    const isExplicitSchemaOOS = html.includes('schema.org/OutOfStock') || html.includes('schema.org/outOfStock') || html.includes('"availability":"OutOfStock"');
    if (isExplicitSchemaOOS) return { available: false, reason: 'schema_out_of_stock', cookieHealth, rating: null, reviewCount: null };

    // Extract Rating & Review Count (JSON-LD & Regex fallback)
    let rating = null;
    let reviewCount = null;
    const schemaRegex = /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
    let match;
    while ((match = schemaRegex.exec(html)) !== null) {
      try {
        const data = JSON.parse(match[1].trim());
        const items = Array.isArray(data) ? data : [data];
        for (const item of items) {
          if (item.aggregateRating) {
            rating = parseFloat(item.aggregateRating.ratingValue);
            reviewCount = parseInt(item.aggregateRating.reviewCount || item.aggregateRating.ratingCount, 10);
            break;
          }
        }
      } catch (e) {}
    }

    if (!rating) {
      const rM = html.match(/"ratingValue"\s*:\s*"?(\d(?:\.\d)?)"?/i) ||
                 html.match(/(\d\.\d)\s*★/i) ||
                 html.match(/class="[^"]*(?:_3LWZlK|XqP1W8)[^"]*"[^>]*>(\d\.\d)/i);
      if (rM) rating = parseFloat(rM[1]);
    }

    if (!reviewCount) {
      const rvM = html.match(/"ratingCount"\s*:\s*"?([\d,]+)"?/i) ||
                  html.match(/based on ([\d,]+) ratings/i);
      if (rvM) reviewCount = parseInt(rvM[1].replace(/,/g, ''), 10);
    }

    // Price variation check: flag price increases (>15% for >=₹500, >25% for <₹500)
    let priceIncreased = false;
    if (scrapedPrice > 0) {
      const listedPrice = extractPageListedPrice(html);
      if (listedPrice && listedPrice > 0) {
        if (shouldDemote(scrapedPrice, listedPrice)) {
          priceIncreased = true;
          console.log(`Non-Amazon deal price increased (${scrapedPrice} -> ${listedPrice}): ${url}`);
        }
      }
    }

    return { available: true, cookieHealth, rating, reviewCount, priceIncreased };
  } catch (e) {
    return { available: true, cookieHealth, rating: null, reviewCount: null, priceIncreased: false }; // Fallback to available if fetch errors
  }
}

async function cronSyncAndPublishNonAmazonDeals(env, force = false) {
  // Save proxy credits: Do not run background crons between 2 AM and 7 AM IST unless forced
  if (!force) {
    const now = new Date();
    const istTime = new Date(now.getTime() + (5.5 * 60 * 60 * 1000));
    const hour = istTime.getUTCHours();
    if (hour >= 2 && hour < 7) {
      console.log(`Skipping background cron between 2 AM and 7 AM IST (Current IST hour: ${hour}) to conserve limits.`);
      return;
    }
  }

  // Fetch multiple DealsSpy store pages in parallel to maximise deal volume
  const dsPages = [
    'https://www.dealsspy.in/',                  // Homepage (mixed stores, freshest)
    'https://www.dealsspy.in/offers/flipkart',   // Flipkart
    'https://www.dealsspy.in/offers/myntra',     // Myntra
    'https://www.dealsspy.in/offers/ajio',       // Ajio
    'https://www.dealsspy.in/offers/meesho',     // Meesho
    'https://www.dealsspy.in/offers/electronics',
    'https://www.dealsspy.in/offers/footwear',
    'https://www.dealsspy.in/offers/mens-fashion',
    'https://www.dealsspy.in/offers/womens-fashion',
  ];

  const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  const dsResults = await Promise.allSettled(
    dsPages.map(async pageUrl => {
      try {
        const r = await fetchWithProxy(pageUrl, { headers: { 'User-Agent': UA } }, 20000, env);
        if (!r.ok) return [];
        const html = await r.text();
        return parseDealsSpyHtml(html);
      } catch (e) {
        console.error(`DS page fetch failed (${pageUrl}):`, e.message);
        return [];
      }
    })
  );

  // Deduplicate by link across all pages
  const seenDsLinks = new Set();
  const dsDeals = [];
  for (const result of dsResults) {
    if (result.status !== 'fulfilled') continue;
    for (const deal of result.value) {
      const key = deal.link.toLowerCase();
      if (seenDsLinks.has(key)) continue;
      seenDsLinks.add(key);
      // Skip Amazon deals from DealsSpy — Amazon is handled by its own dedicated pipeline
      if (deal.link.includes('amazon.in') || deal.link.includes('amazon.com') || deal.link.includes('amzn.to')) continue;
      dsDeals.push(deal);
    }
  }

  let ifsDeals = [];
  try {
    ifsDeals = await scrapeIfsNonAmazonDeals(env).catch(() => []);
  } catch (e) {
    console.error('Non-Amazon IFS cron fetch failed:', e.message);
  }

  const scrapedDeals = [...dsDeals, ...ifsDeals];
  if (!scrapedDeals.length) return;

  const { products, sha } = await getProductsFile(env);
  const liveOriginalLinks = new Set(
    products
      .filter(p => !isDead(p))
      .map(p => getOriginalUrl(p.link).toLowerCase())
  );
  
  let sentLinks = [];
  try {
    sentLinks = JSON.parse(await env.KV.get('fkart_sent_tg_urls') || '[]');
  } catch (e) {}
  const sentSet = new Set(sentLinks.map(l => l.toLowerCase()));

  let deletedUrls = [];
  try {
    deletedUrls = JSON.parse(await env.KV.get('deleted_fkart_urls') || '[]');
  } catch (e) {}
  const deletedSet = new Set(deletedUrls.map(l => l.toLowerCase()));

  const newProducts = [];
  const newSentLinks = [...sentLinks];

  const candidateDeals = [];
  for (const deal of scrapedDeals) {
    const origLinkLower = deal.link.toLowerCase();
    if (liveOriginalLinks.has(origLinkLower)) continue;
    if (sentSet.has(origLinkLower)) continue;
    if (deletedSet.has(origLinkLower)) continue;
    candidateDeals.push(deal);
  }

  // Verify each candidate's live listing (in stock, price still matches) before
  // publishing — the aggregator feeds (DealsSpy/IFS) lag reality by hours, which
  // is why unavailable/price-changed deals were getting auto-published. Checked
  // in small concurrent chunks to stay within Cloudflare's per-invocation
  // subrequest limit.
  const verifyChunkSize = 5;
  const flipkartCookieStatuses = [];
  for (let i = 0; i < candidateDeals.length && newProducts.length < 10; i += verifyChunkSize) {
    const chunk = candidateDeals.slice(i, i + verifyChunkSize);
    const checked = await Promise.all(chunk.map(async deal => {
      const availability = await checkListingAvailability(deal.link, parsePrice(deal.price) || 0, env);
      return { deal, availability };
    }));

    for (const { deal, availability } of checked) {
      if (availability.cookieHealth) flipkartCookieStatuses.push(availability.cookieHealth);
      if (newProducts.length >= 10) break;
      if (!availability.available) {
        console.log(`Skipping unavailable non-Amazon deal (${availability.reason}): ${deal.link}`);
        newSentLinks.push(deal.link); // don't re-check the same dead link every 5 min
        continue;
      }

      // Convert link to a real tracked CueLinks affiliate link, and ask CueLinks'
      // AI to clean up the scraped title (falls back to the manual link wrap and
      // original title on any uncertainty — see convertToCueLink's comment on
      // why affiliated:false isn't currently treated as a skip signal). The
      // original messy scraped title doubles as the "description" input —
      // CueLinks doesn't generate one from nothing, but rewriting the messy
      // spec-dump text produces genuinely usable highlight-sized sentences.
      const { link: cueLink, title: cleanedTitle, description: cleanedDescription } =
        await convertToCueLink(deal.link, deal.title || '', env, deal.title || '');

      const newProduct = {
        id: 'fk_' + Date.now() + '_' + Math.random().toString(36).substr(2, 5),
        asin: '',
        title: cleanedTitle || '',
        price: deal.price || '',
        mrp: deal.mrp || '',
        disc: deal.mrp && deal.price ? `-${Math.round((1 - parsePrice(deal.price) / parsePrice(deal.mrp)) * 100)}%` : '0%',
        image: deal.image || '',
        link: cueLink,
        // Category detection stays on the original scraped title, not the
        // AI-rewritten one — keeps this independent of any rewrite quirks.
        category: deal.category || detectCategoryFromTitle(deal.title),
        highlights: splitDescriptionIntoHighlights(cleanedDescription),
        lowestPriceText: null,
        featured: false,
        hidden: false,
        outOfStock: false,
        order: 0,
        addedAt: new Date().toISOString(),
        originalPrice: deal.price || '',
        rating: availability.rating || null,
        reviewCount: availability.reviewCount || null,
        priceIncreased: availability.priceIncreased || false
      };

      newProducts.push(newProduct);
      newSentLinks.push(deal.link);
    }
  }

  if (newProducts.length > 0) {
    console.log(`Auto-publishing ${newProducts.length} new non-Amazon deals to site with CueLinks...`);
    const updatedProducts = await capLiveAndBury([...newProducts, ...products], env);
    await saveProductsFile(updatedProducts, sha, `Auto-publish non-Amazon deals to site: ${newProducts.map(p => p.title.slice(0, 30)).join(', ')}`, env);
    
    await env.KV.put('fkart_sent_tg_urls', JSON.stringify(newSentLinks.slice(-500)));

    // Send EarnKaro reply prompts to TG admin DM for Telegram channel posting (do NOT auto-post CueLinks to TG channel)
    for (const p of newProducts) {
      const origLink = getOriginalUrl(p.link) || p.link;
      await sendNonAmazonDealPromptToAdmin({ title: p.title, price: p.price, mrp: p.mrp, image: p.image, link: origLink }, env)
        .catch(e => console.error('TG EarnKaro prompt non-Amazon failed:', e.message));
    }
  }

  // Surface FLIPKART_SESSION_COOKIE health on the admin dashboard (same bell/push
  // path as every other sync error) so an expired/rotated cookie doesn't fail
  // silently back to anonymous deliverability checks. Only evaluated when this run
  // actually attempted an authed check (flipkartCookieStatuses empty means no new
  // Flipkart candidates this tick, not that the cookie is fine) — 'expired' wins
  // over 'ok'/'request_failed' since even one confirmed-anonymous response means
  // every check this run was unauthenticated.
  if (flipkartCookieStatuses.length > 0) {
    if (flipkartCookieStatuses.includes('expired')) {
      await saveSyncError(
        'FlipkartSessionCookie',
        'Flipkart session cookie appears expired or invalid — deliverability checks are running anonymously again. Re-extract the cookie from a logged-in browser and run: npx wrangler secret put FLIPKART_SESSION_COOKIE',
        env
      );
    } else if (flipkartCookieStatuses.includes('ok')) {
      await clearSyncError('FlipkartSessionCookie', env);
    } else {
      // every attempt was 'request_failed' — ScrapingAnt itself failed (API key/credits/outage),
      // not necessarily the cookie. Distinct message so it's not confused with an expired cookie.
      await saveSyncError(
        'FlipkartSessionCookie',
        'Flipkart authenticated availability check failed for every candidate this run (ScrapingAnt request error) — check SCRAPINGANT_API_KEYS / credits.',
        env
      );
    }
  }
}

async function readHeadPrefix(res) {
  try {
    const text = await res.text();
    return text.slice(0, 20000);
  } catch (e) {
    return '';
  }
}

function isValidAsin(cand) {
  if (!cand || cand.length !== 10) return false;
  if (!/^[A-Z0-9]{10}$/.test(cand)) return false;
  if (!/\d/.test(cand)) return false;
  const invalidWords = new Set([
    'AUICLIENTS', 'HELPCENTRE', 'CATEGORIES', 'SUNGLASSES', 'COLLECTIONS',
    'PROMOTIONS', 'DISCOUNTS', 'BESTSELLER', 'NEWARRIVALS', 'SHOPONLINE',
    'ELECTRONIC', 'APPARELFAS', 'AUTOMOTIVE'
  ]);
  if (invalidWords.has(cand)) return false;
  if (cand.startsWith('NAV') || cand.startsWith('HEADER') || cand.startsWith('FOOTER')) return false;
  return cand.startsWith('B0') || cand.startsWith('B1') || cand.startsWith('B2') || /^\d/.test(cand);
}

function extractAsin(str) {
  if (!str || typeof str !== 'string') return null;

  const dpMatch = str.match(/(?:amazon\.[a-z.]+|amzn\.[a-z.]+)\/(?:[\w-]+\/)?(?:dp|gp\/product)\/([A-Z0-9]{10})/i) ||
                  str.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i) ||
                  str.match(/[?&]asin=([A-Z0-9]{10})/i);
  if (dpMatch) {
    const cand = dpMatch[1].toUpperCase();
    if (isValidAsin(cand)) return cand;
  }

  if (/(?:amazon|amzn)/i.test(str)) {
    const genericMatches = str.matchAll(/\/([A-Z0-9]{10})(?:\/|\?|#|$)/gi);
    for (const m of genericMatches) {
      const cand = (m[1] || '').toUpperCase();
      if (isValidAsin(cand)) return cand;
    }
  }

  return null;
}

async function scrapeAndSyncIndiaFreeStuff(env, limit = 10) {
  if (!env.SCRAPER_API_URL) {
    console.log('IndiaFreeStuff sync skipped: SCRAPER_API_URL not configured.');
    return { success: true, count: 0, message: 'IndiaFreeStuff: sync skipped (SCRAPER_API_URL not configured)' };
  }

  const matchesMap = new Map();
  const blockedBrands = await getBlockedBrands(env);

  const targetUrls = [
    'https://www.indiafreestuff.in/deals',
    'https://www.indiafreestuff.in/trending',
    'https://www.indiafreestuff.in/stores/amazon',
  ];

  for (const targetUrl of targetUrls) {
    try {
      let r = await fetchWithProxy(targetUrl, { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } }, 20000, env);
      if (!r.ok) {
        await new Promise(res => setTimeout(res, 2000));
        r = await fetchWithProxy(targetUrl, { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } }, 20000, env);
      }
      if (!r.ok) continue;
      const html = await r.text();
      console.log(`IFS fetch ${targetUrl}: HTTP ${r.status}, HTML len ${html.length}`);

      const blocks = html.split(/<div class="product-item/g);
      console.log(`IFS blocks count for ${targetUrl}: ${blocks.length - 1}`);
      for (let i = 1; i < blocks.length; i++) {
        const block = blocks[i];

        // Title from item-title anchor
        const titleM = block.match(/class="item-title"[^>]*>\s*([^<]{5,}?)\s*<\/a>/i);
        if (!titleM) continue;
        let title = decodeHtmlEntities(titleM[1].replace(/\s+/g,' ').trim());
        title = title.replace(/\s*Rs\.?\s*[\d,]+.*$/i, '').trim();
        if (!title || title.length < 5) continue;
        if (isBrandBlocked(title, blockedBrands)) continue;

        const thumbM = block.match(/data-original="([^"]+)"/i)
          || block.match(/src="([^"]+)"/i);
        let image = '';
        if (thumbM && thumbM[1].includes('http')) {
          image = thumbM[1];
        }

        const priceM = block.match(/class="new-price"[\s\S]*?fa-inr[^>]*><\/i>\s*([\d,]+)/i);
        const mrpM   = block.match(/class="old-price"[\s\S]*?fa-inr[^>]*><\/i>\s*([\d,]+)/i);
        const price = priceM ? parseInt(priceM[1].replace(/,/g,'')) : 0;
        const mrp   = mrpM   ? parseInt(mrpM[1].replace(/,/g,''))   : price;

        const rtoM = block.match(/href="https?:\/\/www\.indiafreestuff\.in\/\?rto=([^"]+)"/i);
        if (!rtoM) continue;
        const rtoParam = rtoM[1];

        const key = rtoParam;
        if (!matchesMap.has(key)) {
          matchesMap.set(key, { title, image, price, mrp, rtoParam });
        }
      }
    } catch (e) {
      console.error(`IFS fetch failed for ${targetUrl}:`, e.message);
    }
  }

  if (matchesMap.size === 0) {
    const msg = 'IndiaFreeStuff: no deals found (structure may have changed)';
    await saveSyncError('IndiaFreeStuff', msg, env);
    await recordScraperStatus('indiafreestuff', 'error', msg, 0, env);
    return { success: false, count: 0, message: msg };
  }

  const { products, sha } = await getProductsFile(env);
  let { asins: deletedAsins } = await getDeletedAsins(env).catch(() => ({ asins: [] }));
  const deletedSet = new Set(deletedAsins.map(a => a.toUpperCase()));
  const existingByAsin = new Map(products.filter(p => p.asin).map(p => [p.asin.toUpperCase(), p]));
  const existingTitles = new Set(products.map(p => p.title.toLowerCase().trim()));

  const candidates = [];
  for (const item of matchesMap.values()) {
    if (item.price <= 0) continue;

    // Skip only if the exact title already exists in products.json
    if (existingTitles.has(item.title.toLowerCase().trim())) continue;

    candidates.push(item);
  }

  // Resolve up to 50 candidates per sync run
  const syncLimit = Math.min(candidates.length, 50);
  const targetCandidates = candidates.slice(0, syncLimit);

  const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const added = [];
  const dbg = [];

  // Resolve redirects in batches of 5
  const resolved = [];
  const chunkSize = 5;
  for (let i = 0; i < targetCandidates.length; i += chunkSize) {
    const chunk = targetCandidates.slice(i, i + chunkSize);
    const chunkResolved = await Promise.all(chunk.map(async (item) => {
      let asin = '';
      let targetUrl = '';
      try {
        const redirTarget = `https://www.indiafreestuff.in/?rto=${item.rtoParam}`;

        // 1. Try manual redirect first to get location header quickly
        const redManual = await fetchWithProxy(redirTarget, {
          redirect: 'manual',
          headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] },
        }, 15000, env);
        
        const loc = redManual ? (redManual.headers.get('location') || '') : '';
        const bodyTextManual = redManual ? await redManual.text().catch(() => '') : '';

        // 2. Extract ASIN or target URL from location header or body text
        const searchStr = loc + ' ' + bodyTextManual;
        asin = extractAsin(searchStr) || '';
        targetUrl = loc;

        if (!asin && (!targetUrl || targetUrl.includes('indiafreestuff.in'))) {
          // 3. Follow redirect to final target URL
          const redFollow = await fetchWithProxy(redirTarget, {
            headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] },
          }, 15000, env);
          const finalUrl = redFollow ? (redFollow.url || '') : '';
          const finalBody = redFollow ? await redFollow.text().catch(() => '') : '';
          const finalSearch = finalUrl + ' ' + finalBody.slice(0, 10000);
          asin = extractAsin(finalSearch) || '';
          targetUrl = finalUrl;
        }
        if (dbg.length < 8) dbg.push(asin ? `amz:${asin}` : (targetUrl ? 'non-amz' : `miss:${redManual ? redManual.status : 'err'}`));
      } catch (err) {
        if (dbg.length < 8) dbg.push(`err:${err.message}`);
      }
      return { ...item, asin, targetUrl };
    }));
    resolved.push(...chunkResolved);
  }

  for (const item of resolved) {
    const { asin, title, image, price, mrp } = item;

    const discNum = mrp > price && price > 0 ? Math.round((1 - price / mrp) * 100) : 0;
    const priceStr = price > 0 ? '₹' + price.toLocaleString('en-IN') : '';
    const mrpStr   = mrp   > 0 ? '₹' + mrp.toLocaleString('en-IN')   : priceStr;
    const discStr  = discNum > 0 ? `-${discNum}%` : '0%';
    const category = detectCategoryFromTitle(title);

    if (asin) {
      // Amazon deal only
      if (deletedSet.has(asin) || existingByAsin.has(asin)) continue;
      const baseLink = `https://www.amazon.in/dp/${asin}`;
      const link = hasUptoOffInTitle(title) ? buildManualCueLink(baseLink, env) : `${baseLink}?tag=${TAG}`;

      added.push({
        id: `ifs_${Date.now()}_${added.length}`,
        asin, title, price: priceStr, mrp: mrpStr, disc: discStr,
        image, link, category, highlights: ['Great deal on Amazon'],
        lowestPriceText: null, featured: false, hidden: false, outOfStock: false,
        order: 0, addedAt: new Date().toISOString(), originalPrice: priceStr,
      });
    }
  }

  console.log('IFS redir debug:', JSON.stringify(dbg));

  if (added.length === 0) {
    await clearSyncError('IndiaFreeStuff', env);
    await recordScraperStatus('indiafreestuff', 'working', 'No new deals', 0, env);
    return { success: true, count: 0, message: 'IndiaFreeStuff: no new deals found.' };
  }

  const final = await capLiveAndBury([...added, ...products], env);

  const msg = `IndiaFreeStuff sync: +${added.length} new`;
  await saveProductsFile(final, sha, msg, env);
  await clearSyncError('IndiaFreeStuff', env);
  await recordScraperStatus('indiafreestuff', 'working', msg, added.length, env);
  return { success: true, added: added.length, message: msg, addedProducts: added };
}

function decodeHtmlEntities(str) {
  let prev;
  let decoded = str || '';
  do {
    prev = decoded;
    decoded = decoded
      .replace(/&amp;/g, '&')
      .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
      .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&apos;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>');
  } while (decoded !== prev);
  return decoded;
}

// ── DealOfTheDayIndia sync (Amazon-only) ──────────────────────────────────────
// Their robots.txt disallows /go.php (their redirect/shortlink endpoint), so
// unlike IndiaFreeStuff/DealsRadar we never request it — the real Amazon URL
// (and ASIN) is already sitting in that link's own query string in plain text
// on the listing page itself, which robots.txt does allow. One fetch, no
// redirect-follow subrequest needed at all.
async function scrapeAndSyncDealOfTheDayIndia(env, limit = 10) {
  const blockedBrands = await getBlockedBrands(env);
  let html;
  try {
    // Their site serves this listing page through a server-side page cache
    // (Jetpack Boost, on Hostinger) that can lag well behind what's actually
    // posted — a plain fetch here can return the SAME snapshot for 20+
    // minutes (confirmed: two plain fetches minutes apart came back
    // byte-identical, `X-Jetpack-Boost-Cache: hit`, while a request with a
    // cache-busting query param came back `miss` with fresher deals). The
    // random param forces a cache miss so every cron tick sees the real
    // current page instead of a stale one.
    const bust = `?_cb=${Date.now()}`;
    let r = await fetchWithTimeout('https://dealofthedayindia.com/store/amazon/' + bust, { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } });
    if (!r.ok) {
      await new Promise(res => setTimeout(res, 3000));
      r = await fetchWithTimeout('https://dealofthedayindia.com/store/amazon/' + bust, { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } });
    }
    if (!r.ok) throw new Error(`HTTP ${r.status} after retry`);
    console.log('DOTD debug: jetpack-cache=' + (r.headers.get('x-jetpack-boost-cache') || 'n/a') + ' hcdn-status=' + (r.headers.get('x-hcdn-cache-status') || 'n/a'));
    html = await r.text();
  } catch (e) {
    const msg = `DealOfTheDayIndia fetch failed: ${e.message}`;
    await saveSyncError('DealOfTheDayIndia', msg, env);
    await recordScraperStatus('dealoftheday', 'error', msg, 0, env);
    return { success: false, count: 0, message: msg };
  }

  const blocks = html.split('<div class="col_item offer_grid');
  const matchesMap = new Map(); // asin -> { title, image, price, mrp }

  for (let i = 1; i < blocks.length; i++) {
    const block = blocks[i];

    const asinM = block.match(/go\.php\?https?:\/\/(?:www\.)?amazon\.in\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i);
    if (!asinM) continue;
    const asin = asinM[1].toUpperCase();
    if (matchesMap.has(asin)) continue;

    // First <img> in the block is the product photo; its alt text is the title.
    const imgM = block.match(/<img\s+src="([^"]+)"[^>]*\salt="([^"]{5,}?)"/);
    if (!imgM) continue;
    const title = decodeHtmlEntities(imgM[2].replace(/\s+/g, ' ').trim());
    if (!title || title.length < 5) continue;
    if (isBrandBlocked(title, blockedBrands)) continue;
    // Their thumbnail is already the real Amazon CDN image, just undersized —
    // swap the size suffix instead of a second fetch to re-derive it.
    const image = imgM[1].replace(/_S[XY]\d+_/, '_SL500_');

    const priceM = block.match(/rh_regular_price">([\d,]+)<\/span>\s*<del>([\d,]+)<\/del>/);
    const price = priceM ? parseInt(priceM[1].replace(/,/g, '')) : 0;
    const mrp = priceM ? parseInt(priceM[2].replace(/,/g, '')) : price;
    if (!(price > 0)) continue; // ₹0/blank price is unpostable — see IFS's same guard above

    matchesMap.set(asin, { title, image, price, mrp });
  }

  if (matchesMap.size === 0) {
    const msg = 'DealOfTheDayIndia: no Amazon deals found (structure may have changed)';
    await saveSyncError('DealOfTheDayIndia', msg, env);
    await recordScraperStatus('dealoftheday', 'error', msg, 0, env);
    return { success: false, count: 0, message: msg };
  }

  const { products, sha } = await getProductsFile(env);
  let { asins: deletedAsins } = await getDeletedAsins(env).catch(() => ({ asins: [] }));
  const deletedSet = new Set(deletedAsins.map(a => a.toUpperCase()));
  const existingByAsin = new Map(products.filter(p => p.asin).map(p => [p.asin.toUpperCase(), p]));
  console.log('DOTD debug: matchesMap=' + matchesMap.size + ' productsLoaded=' + products.length + ' asins=' + [...matchesMap.keys()].join(',') + ' | alreadyExisting=' + [...matchesMap.keys()].filter(a => existingByAsin.has(a)).join(',') + ' | deleted=' + [...matchesMap.keys()].filter(a => deletedSet.has(a)).join(','));

  const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const added = [];

  for (const [asin, { title, image, price, mrp }] of matchesMap) {
    if (added.length >= limit) break;
    if (deletedSet.has(asin) || existingByAsin.has(asin)) continue; // see IFS's same "leave it alone" note above

    const discNum = mrp > price && price > 0 ? Math.round((1 - price / mrp) * 100) : 0;
    const priceStr = '₹' + price.toLocaleString('en-IN');
    const mrpStr = mrp > 0 ? '₹' + mrp.toLocaleString('en-IN') : priceStr;
    const discStr = discNum > 0 ? `-${discNum}%` : '0%';
    const baseLink = `https://www.amazon.in/dp/${asin}`;
    const link = hasUptoOffInTitle(title) ? buildManualCueLink(baseLink, env) : `${baseLink}?tag=${TAG}`;
    const category = detectCategoryFromTitle(title);

    added.push({
      id: `dotd_${Date.now()}_${added.length}`,
      asin, title, price: priceStr, mrp: mrpStr, disc: discStr,
      image, link, category, highlights: ['Great deal on Amazon'],
      lowestPriceText: null, featured: false, hidden: false, outOfStock: false,
      order: 0, addedAt: new Date().toISOString(), originalPrice: priceStr,
    });
  }

  if (added.length === 0) {
    await clearSyncError('DealOfTheDayIndia', env);
    await recordScraperStatus('dealoftheday', 'working', 'No new deals', 0, env);
    return { success: true, count: 0, message: 'DealOfTheDayIndia: no new Amazon deals.' };
  }

  const final = await capLiveAndBury([...added, ...products], env);
  const msg = `DealOfTheDayIndia sync: +${added.length} new`;
  await saveProductsFile(final, sha, msg, env);
  await clearSyncError('DealOfTheDayIndia', env);
  await recordScraperStatus('dealoftheday', 'working', msg, added.length, env);
  return { success: true, added: added.length, message: msg, addedProducts: added };
}

// ── Price check + OOS detection (Creators API) ────────────────────────────────

function parsePrice(str) {
  if (!str) return null;
  const n = parseFloat(str.replace(/[^0-9.]/g,''));
  return n > 0 ? Math.round(n) : null;
}

// Our own price-history tracker — no external API (Keepa is a paid product
// with real token limits; we already fetch prices ourselves via the Creators
// API and DR feed, this just stops throwing that data away). Only appends
// when the price actually changes, not on every check, so growth tracks real
// volatility instead of check frequency — most products change price rarely,
// keeping products.json's size increase small. Capped at 40 points/product as
// a hard ceiling regardless (products.json already crossed GitHub's 1MB
// Contents-API inline-read limit once; the Git-Blobs-API fallback handles any
// size now, but there's no reason to let this grow unbounded either).
const PRICE_HISTORY_CAP = 40;
function appendPriceHistory(product, newPriceStr) {
  const history = Array.isArray(product.priceHistory) ? [...product.priceHistory] : [];
  if (!history.length) {
    // Seed with the price the product started at, so the chart always has a
    // real first point instead of starting mid-story at the first change.
    history.push({ date: product.addedAt || new Date().toISOString(), price: product.price });
  }
  history.push({ date: new Date().toISOString(), price: newPriceStr });
  return history.slice(-PRICE_HISTORY_CAP);
}

function shouldDemote(origPrice, currentPrice) {
  if (!origPrice || !currentPrice) return false;
  const threshold = origPrice < 500 ? 1.25 : 1.15;
  return currentPrice >= origPrice * threshold;
}

async function checkAndCleanDeals(env) {
  const { products, sha } = await getProductsFile(env);
  if (!products.length) return { success: true, message: 'No products to check.' };

  let token;
  try { token = await getAccessToken(env.PA_ACCESS_KEY, env.PA_SECRET_KEY); }
  catch (e) { throw new Error(`Auth failed: ${e.message}`); }

  // Rotate through products: check oldest-checked first, up to 100 per run,
  // across ALL live products (up to the 1440 cap). At 6 runs/hour that's a
  // ~2.4hr full-cycle staleness at the 1440 cap vs ~72min at 720 — same API
  // call volume per run either way (100 checked, chunked by 10), just spread
  // across more products.
  const live = products.filter(p => !isDead(p));
  const withAsin = live.filter(p => p.asin);
  const checkable = withAsin.filter(p => {
    const hasCoupon = (p.title || '').match(/\[[^\]]*coupon[^\]]*\]/i);
    return !hasCoupon;
  });
  const sorted = [...checkable].sort((a, b) => (a.lastChecked || 0) - (b.lastChecked || 0));
  const toCheck = sorted.slice(0, 100);

  const productMap = new Map(products.map(p => [p.id, { ...p }]));
  let priceDrops = 0;
  let changed = false;

  const CHUNK = 10;
  for (let i = 0; i < toCheck.length; i += CHUNK) {
    const chunk = toCheck.slice(i, i + CHUNK);
    const asins = chunk.map(p => p.asin);
    const now = Date.now();

    try {
      const resp = await fetchWithTimeout('https://creatorsapi.amazon/catalog/v1/getItems', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'x-marketplace': 'www.amazon.in' },
        body: JSON.stringify({
          itemIds: asins, itemIdType: 'ASIN', marketplace: 'www.amazon.in',
          partnerTag: env.PA_PARTNER_TAG || 'dealbuster002-21',
          resources: ['itemInfo.title','offersV2.listings.price','offersV2.listings.availability','offersV2.listings.dealDetails'],
        }),
      });
      if (!resp.ok) {
        console.error(`GetItems chunk ${i} HTTP ${resp.status}`);
        continue;
      }

      // Only update lastChecked when the API response succeeds to retry rate-limited items
      chunk.forEach(p => { const u = productMap.get(p.id); if (u) u.lastChecked = now; });
      const data = await resp.json();
      const items = data.itemsResult?.items || [];
      const returnedAsins = new Set(items.map(it => it.asin.toUpperCase()));

      for (const p of chunk) {
        const updated = productMap.get(p.id);
        const item = items.find(it => it.asin.toUpperCase() === p.asin.toUpperCase());

        // Only mark OOS when API explicitly signals it — not on missing item or missing price
        const listing = item?.offersV2?.listings?.[0];
        const availability = listing?.availability;
        const isOOS = availability?.type === 'OUT_OF_STOCK';
        const availMsg = (availability?.message || '').toLowerCase();
        const isLowStockOrUndeliverable = !!availMsg.match(/only\s+[1-4]\s+left\s+in\s+stock/) ||
          availMsg.includes('cannot be shipped');

        if (isLowStockOrUndeliverable) {
          console.log(`Deleting product ${p.asin} due to low stock / undeliverable message: ${availMsg}`);
          productMap.delete(p.id);
          await addDeletedAsin(p.asin, env);
          changed = true;
          continue;
        }

        if (isOOS) {
          if (!updated.outOfStock) {
            updated.outOfStock = true;
            changed = true;
          }
          continue;
        }

        // Back in stock
        if (updated.outOfStock) { updated.outOfStock = false; changed = true; }

        // Low stock detection (1-4 left in stock)
        const availMessage = (availability?.message || '').toLowerCase();
        const stockMatch = availMessage.match(/only (\d+) left in stock/);
        let isLowStock = false;
        if (stockMatch) {
          const qty = parseInt(stockMatch[1], 10);
          if (qty >= 1 && qty <= 4) {
            isLowStock = true;
          }
        }
        const lowStockStateChanged = (updated.lowStock === true) !== isLowStock;
        if (lowStockStateChanged) {
          if (isLowStock) {
            updated.lowStock = true;
          } else {
            delete updated.lowStock;
          }
          changed = true;
        }

        // No price from API — don't overwrite with NaN, skip price update
        if (!amPrice || amPrice <= 0) continue;

        const dbPrice = parsePrice(p.price);
        const amMrp = listing?.dealDetails?.originalPrice?.amount || listing?.price?.amount || dbPrice || amPrice;
        const newDisc = amPrice && amMrp && amMrp > amPrice ? Math.round((1 - amPrice / amMrp) * 100) : 0;
        const newPriceStr = '₹' + Math.round(amPrice).toLocaleString('en-IN');
        const newMrpStr = '₹' + Math.round(amMrp).toLocaleString('en-IN');
        const newDiscStr = newDisc > 0 ? `-${newDisc}%` : '0%';

        const priceStrChanged = updated.price !== newPriceStr;
        const priceChanged = priceStrChanged || updated.mrp !== newMrpStr || updated.disc !== newDiscStr;
        const priceDrop = dbPrice !== null && amPrice < dbPrice;

        if (priceStrChanged) {
          updated.priceHistory = appendPriceHistory(updated, newPriceStr);
        }
        if (priceChanged) {
          updated.price = newPriceStr;
          updated.mrp = newMrpStr;
          updated.disc = newDiscStr;
          changed = true;
        }

        // Price check original-price escalation detection
        const origPrice = parsePrice(p.originalPrice || p.price);
        if (origPrice && amPrice && shouldDemote(origPrice, amPrice)) {
          updated.priceIncreased = true;
        } else {
          delete updated.priceIncreased;
        }
        if ((updated.priceIncreased === true) !== (p.priceIncreased === true)) {
          changed = true;
        }

        // Price drop: update in place only — no position bump (deals age out
        // normally by time) and never touch addedAt, that's the deal's true
        // first-seen time. Refreshing either made old deals look brand new.
        if (priceDrop) {
          // Dashboard bell alert — rides this products.json commit, zero KV cost.
          // p.price is the pre-sync price (updated is a copy).
          updated.priceDropText = `${p.price} → ${newPriceStr}`;
          priceDrops++;
          changed = true;
        } else if (updated.priceDropText && dbPrice !== null && amPrice > dbPrice) {
          // Price climbed back up — the drop alert is stale, retire it
          delete updated.priceDropText;
          changed = true;
        }
      }
    } catch (err) {
      console.error(`Chunk ${i} error:`, err.message);
    }
  }

  // Keep OOS products pinned to the bottom every cycle (same rule as the
  // dashboard's manual "Push OOS to Bottom" button). Zero-price products
  // become TOMBSTONES — hidden, off Telegram, but still in the array so the
  // source feeds (which keep listing dead products for days) can't re-add
  // them at the top as "new". Their TG-posted marks are deliberately KEPT:
  // clearing them is what let every re-add DM the admin again. OOS takes
  // priority when a product is somehow both, so an OOS item survives visible
  // (it has a real price to come back to).
  // Existing tombstones pass through untouched — capLiveAndBury (every sync
  // run) owns expiry, because expiry must also clear the TG ledger.
  const mid = [], priceClimbed = [], lowStock = [], oos = [], tombs = [];
  for (const p of products) {
    const updated = productMap.get(p.id) || p;
    if (isDead(updated)) tombs.push(updated);
    else if (updated.outOfStock) oos.push(updated);
    else if (isZeroPrice(updated)) tombs.push(makeTombstone(updated));
    else if (updated.lowStock) lowStock.push(updated);
    else if (updated.priceIncreased) priceClimbed.push(updated);
    else mid.push(updated);
  }
  const newlyDead = tombs.length - products.filter(isDead).length;
  const finalOrder = [...mid, ...priceClimbed, ...lowStock, ...oos, ...tombs];
  const orderChanged = finalOrder.length !== products.length ||
    finalOrder.some((p, i) => p.id !== products[i]?.id || isDead(p) !== isDead(products[i]));

  if (!changed && !orderChanged) {
    return { success: true, message: 'Prices up to date. No changes.' };
  }

  const reordered = finalOrder.map((p, i) => ({ ...p, order: i }));
  const msg = `Price sync: ${priceDrops} price drops (in place), ${oos.length} OOS at bottom, ${newlyDead} newly tombstoned`;
  await saveProductsFile(reordered, sha, msg, env);

  return {
    success: true, priceDrops, oosAtBottom: oos.length, newlyTombstoned: newlyDead,
    oosCount: [...productMap.values()].filter(p => p.outOfStock).length,
    message: `Price sync done. ${priceDrops} price drops updated in place, ${oos.length} OOS at bottom, ${newlyDead} newly tombstoned.`,
  };
}

// ── Lowest-price badge check + highlights fill (HTML, 8 products / hour) ─────

function needsHighlights(p) {
  return !p.highlights || p.highlights.length === 0 ||
    (p.highlights.length === 1 && p.highlights[0] === 'Great deal on Amazon');
}

async function checkLowestPriceBadges(env) {
  const { products, sha } = await getProductsFile(env);
  if (!products.length) return { success: true, message: 'No products.' };

  const withAsin = products.filter(p => p.asin && !p.outOfStock);

  // Products needing highlights go first, then sort by oldest badge check
  const needHL = withAsin.filter(needsHighlights).sort((a, b) => (a.lastBadgeCheck || 0) - (b.lastBadgeCheck || 0));
  const hasHL  = withAsin.filter(p => !needsHighlights(p)).sort((a, b) => (a.lastBadgeCheck || 0) - (b.lastBadgeCheck || 0));
  const toCheck = [...needHL, ...hasHL].slice(0, 40);

  const productMap = new Map(products.map(p => [p.id, { ...p }]));
  let changed = false;
  let badgeCount = 0;
  let highlightCount = 0;

  const CHUNK_SIZE = 5;
  for (let i = 0; i < toCheck.length; i += CHUNK_SIZE) {
    const chunk = toCheck.slice(i, i + CHUNK_SIZE);
    await Promise.all(chunk.map(async (p) => {
      const updated = productMap.get(p.id);
      if (!updated) return;
      updated.lastBadgeCheck = Date.now();

      const { badge, highlights, category, rating, reviewCount, lowStock, undeliverable, isOOS } = await fetchAmazonPageData(p.asin);

      // Filter out low rating (< 3.6), low stock (Only 1-4 left), undeliverable, or out of stock deals permanently!
      if ((rating != null && rating < 3.6) || lowStock || undeliverable || isOOS) {
        console.log(`Deleting Amazon product ${p.asin}: rating=${rating}, lowStock=${lowStock}, undeliverable=${undeliverable}, isOOS=${isOOS}`);
        productMap.delete(p.id);
        await addDeletedAsin(p.asin, env);
        changed = true;
        return;
      }

      // Fix wrong category: if Amazon breadcrumb says something different, update
      if (category && updated.category !== category) {
        updated.category = category;
        changed = true;
      }

      if (badge && updated.lowestPriceText !== badge) {
        updated.lowestPriceText = badge;
        changed = true;
        badgeCount++;
      }

      if (highlights.length > 0 && needsHighlights(updated)) {
        updated.highlights = highlights;
        changed = true;
        highlightCount++;
      }

      if (rating && (updated.rating !== rating || updated.reviewCount !== reviewCount)) {
        updated.rating = rating;
        updated.reviewCount = reviewCount;
        if (rating < 3.6) {
          updated.hidden = true;
          updated.dead = new Date().toISOString();
        }
        changed = true;
      }
    }));
  }

  if (!changed) return { success: true, message: `Checked ${toCheck.length} products. No changes from badge/highlight check.` };

  const reordered = [...productMap.values()].sort((a, b) => (a.order || 0) - (b.order || 0));
  await saveProductsFile(reordered, sha, `Badge/highlight check: ${badgeCount} badges, ${highlightCount} highlights`, env);

  return { success: true, checked: toCheck.length, badgeCount, highlightCount, message: `Checked ${toCheck.length} products: ${badgeCount} new badges, ${highlightCount} highlights filled.` };
}

// ── Amazon Deals page checker ─────────────────────────────────────────────────
// Fetches amazon.in/deals/, extracts ASINs, checks each for lowest-price badge.
// NOTE: Amazon's "View more" button requires JavaScript; this scrapes the SSR HTML
// and tries multiple paginated URLs to maximise coverage.

async function checkAmazonDeals(env) {
  const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';

  // Paginated URL builder — amazon.in/deals uses base64-encoded widget params
  const pageUrls = [
    'https://www.amazon.in/deals/',
    'https://www.amazon.in/deals/?deals-widget=' + btoa(JSON.stringify({ pageNumber: 2 })),
    'https://www.amazon.in/deals/?deals-widget=' + btoa(JSON.stringify({ pageNumber: 3 })),
    'https://www.amazon.in/deals/?deals-widget=' + btoa(JSON.stringify({ pageNumber: 4 })),
    'https://www.amazon.in/deals/?deals-widget=' + btoa(JSON.stringify({ pageNumber: 5 })),
  ];

  const asinSet = new Set();

  for (const pageUrl of pageUrls) {
    try {
      const r = await fetchWithTimeout(pageUrl, {
        headers: {
          ...AMZ_HEADERS,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Cache-Control': 'no-cache',
        },
      });
      if (!r.ok) continue;
      const html = await r.text();

      // ASIN extraction — multiple patterns
      for (const m of html.matchAll(/data-asin="([A-Z0-9]{10})"/g))              asinSet.add(m[1]);
      for (const m of html.matchAll(/\/dp\/([A-Z0-9]{10})[^A-Z0-9]/g))           asinSet.add(m[1]);
      for (const m of html.matchAll(/"asin"\s*:\s*"([A-Z0-9]{10})"/g))           asinSet.add(m[1]);
      for (const m of html.matchAll(/data-item-asin="([A-Z0-9]{10})"/g))         asinSet.add(m[1]);
      for (const m of html.matchAll(/\/gp\/product\/([A-Z0-9]{10})[^A-Z0-9]/g))  asinSet.add(m[1]);
      for (const m of html.matchAll(/"itemId"\s*:\s*"([A-Z0-9]{10})"/g))         asinSet.add(m[1]);
    } catch (e) {
      console.error(`Amazon deals page ${pageUrl} failed:`, e.message);
    }
  }

  if (asinSet.size === 0) {
    const msg = 'Amazon Deals: no ASINs found in page HTML (page may be fully JS-rendered)';
    await saveSyncError('AmazonDeals', msg, env);
    return { success: false, message: msg };
  }

  // Load existing alerts — skip ASINs already seen in the last 20 hours
  let existing = [];
  if (env.KV) {
    existing = await env.KV.get('amazonDealsAlerts', 'json') || [];
  }
  const recentCutoff = Date.now() - 20 * 60 * 60 * 1000;
  const recentAsins = new Set(
    existing.filter(a => new Date(a.detectedAt).getTime() > recentCutoff).map(a => a.asin)
  );

  const toCheck = [...asinSet].filter(a => !recentAsins.has(a)).slice(0, 40);

  const newAlerts = [];
  for (const asin of toCheck) {
    if (newAlerts.length >= 35) break; // Hard cap on subrequests

    try {
      const r = await fetchWithTimeout(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
      if (!r.ok) continue;
      const html = await r.text();

      // Lowest price badge
      const badgeM = html.match(/(Lowest\s+price\s+(?:in\s+\d+\s+days|ever))/i);
      if (!badgeM) continue;
      const badge = badgeM[1].trim();

      // Title
      const titleM = html.match(/id="productTitle"[^>]*>\s*([\s\S]*?)\s*<\/span>/);
      let title = titleM ? titleM[1].replace(/\s+/g, ' ').trim() : asin;
      title = title.replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'");
      if (title.length > 80) title = title.slice(0, 80).replace(/\s+\S*$/, '').trim() + '…';

      // Price
      const priceM = html.match(/class="[^"]*a-price-whole[^"]*"[^>]*>([\d,]+)/i);
      const price = priceM ? '₹' + priceM[1].replace(/,/g,'').replace(/\B(?=(\d{3})+(?!\d))/g,',') : '';

      // Image
      let image = '';
      const imgTagM = html.match(/<img[^>]*id="(?:landingImage|imgBlkFront)"[^>]*>/i);
      if (imgTagM) {
        const tag = imgTagM[0];
        const dynM = tag.match(/data-a-dynamic-image="([^"]+)"/i);
        if (dynM) { const urlM = dynM[1].match(/(https?:\/\/[^&"']+\.(?:jpg|png|jpeg))/i); if (urlM) image = urlM[1]; }
        if (!image) { const hM = tag.match(/data-old-hires="([^"]+)"/i); if (hM) image = hM[1]; }
        if (!image) { const sM = tag.match(/src="([^"]+)"/i); if (sM && !sM[1].includes('transparent-pixel') && !sM[1].startsWith('data:')) image = sM[1]; }
      }
      if (!image) { const hM = html.match(/"hiRes"\s*:\s*"([^"]+)"/i); if (hM) image = hM[1]; }

      newAlerts.push({
        id: `amzdeal_${asin}_${Date.now()}`,
        asin, title, price, image, badge,
        link: hasUptoOffInTitle(title) ? buildManualCueLink(`https://www.amazon.in/dp/${asin}`, env) : `https://www.amazon.in/dp/${asin}?tag=${TAG}`,
        detectedAt: new Date().toISOString(),
      });
    } catch (e) {
      console.error(`Amazon ASIN check ${asin}:`, e.message);
    }
  }

  if (newAlerts.length === 0) {
    return { success: true, count: 0, message: `Amazon Deals: checked ${toCheck.length} ASINs, no lowest-price badges found.` };
  }

  // Merge: keep new alerts at top, expire alerts older than 7 days, cap at 100
  const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const merged = [
    ...newAlerts,
    ...existing.filter(a => new Date(a.detectedAt).getTime() > sevenDaysAgo),
  ].slice(0, 100);

  if (env.KV) await env.KV.put('amazonDealsAlerts', JSON.stringify(merged));

  return { success: true, count: newAlerts.length, message: `Amazon Deals: found ${newAlerts.length} lowest-price deals from ${asinSet.size} ASINs checked.` };
}

// ── Amazon Deals → Products sync ─────────────────────────────────────────────
// Fetches amazon.in/deals, builds an ASIN queue in KV, adds limitPerRun deals per call.
// Hourly cron: limitPerRun=1 (1 deal/hour = 24/day). Manual button: limitPerRun=24.

async function syncAmazonDealsToProducts(env, limitPerRun = 1) {
  const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const blockedBrands = await getBlockedBrands(env);

  // Load existing queue
  let queue = env.KV ? (await env.KV.get('amazonDealsQueue', 'json') || []) : [];

  // Rebuild queue if nearly empty
  if (queue.length < 5) {
    const pageUrls = [
      'https://www.amazon.in/deals/',
      'https://www.amazon.in/deals/?deals-widget=' + btoa(JSON.stringify({ pageNumber: 2 })),
      'https://www.amazon.in/deals/?deals-widget=' + btoa(JSON.stringify({ pageNumber: 3 })),
      'https://www.amazon.in/deals/?deals-widget=' + btoa(JSON.stringify({ pageNumber: 4 })),
    ];
    const asinSet = new Set();
    for (const pageUrl of pageUrls) {
      try {
        const r = await fetchWithTimeout(pageUrl, { headers: { ...AMZ_HEADERS, 'Cache-Control': 'no-cache' } });
        if (!r.ok) continue;
        const html = await r.text();
        for (const m of html.matchAll(/data-asin="([A-Z0-9]{10})"/g))             asinSet.add(m[1]);
        for (const m of html.matchAll(/\/dp\/([A-Z0-9]{10})[^A-Z0-9]/g))          asinSet.add(m[1]);
        for (const m of html.matchAll(/"asin"\s*:\s*"([A-Z0-9]{10})"/g))          asinSet.add(m[1]);
        for (const m of html.matchAll(/"itemId"\s*:\s*"([A-Z0-9]{10})"/g))        asinSet.add(m[1]);
        for (const m of html.matchAll(/data-item-asin="([A-Z0-9]{10})"/g))        asinSet.add(m[1]);
      } catch (e) {
        console.error(`AMZ deals page failed: ${e.message}`);
      }
    }
    if (asinSet.size === 0) {
      const msg = 'Amazon Deals sync: no ASINs found in page HTML (may be JS-rendered)';
      await saveSyncError('AmazonDealsSync', msg, env);
      return { success: false, count: 0, message: msg };
    }
    const { products } = await getProductsFile(env);
    const existingAsins = new Set(products.filter(p => p.asin).map(p => p.asin.toUpperCase()));
    const { asins: deletedAsins } = await getDeletedAsins(env).catch(() => ({ asins: [] }));
    const deletedSet = new Set(deletedAsins.map(a => a.toUpperCase()));
    const queueSet = new Set(queue.map(a => a.toUpperCase()));
    const fresh = [...asinSet].filter(a => !existingAsins.has(a) && !deletedSet.has(a) && !queueSet.has(a));
    queue = [...queue, ...fresh].slice(0, 48);
    if (env.KV) await env.KV.put('amazonDealsQueue', JSON.stringify(queue));
  }

  if (queue.length === 0) {
    return { success: true, count: 0, message: 'Amazon Deals sync: queue empty, will refill next run' };
  }

  const toProcess = queue.slice(0, limitPerRun);
  const remaining = queue.slice(limitPerRun);

  const { products, sha } = await getProductsFile(env);
  const existingByAsin = new Map(products.filter(p => p.asin).map(p => [p.asin.toUpperCase(), p]));
  const { asins: deletedAsins } = await getDeletedAsins(env).catch(() => ({ asins: [] }));
  const deletedSet = new Set(deletedAsins.map(a => a.toUpperCase()));

  const added = [];

  for (const asin of toProcess) {
    if (existingByAsin.has(asin) || deletedSet.has(asin)) continue;
    try {
      const r = await fetchWithTimeout(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
      if (!r.ok) continue;
      const html = await r.text();

      // Title
      const titleM = html.match(/id="productTitle"[^>]*>\s*([\s\S]*?)\s*<\/span>/);
      let title = titleM ? titleM[1].replace(/\s+/g,' ').trim() : '';
      title = decodeHtmlEntities(title);
      if (!title || title.length < 5) continue;
      if (isBrandBlocked(title, blockedBrands)) continue;

      // Price
      const priceM = html.match(/class="[^"]*a-price-whole[^"]*"[^>]*>([\d,]+)/i);
      const price = priceM ? parseInt(priceM[1].replace(/,/g,'')) : 0;
      if (!price) continue;

      // MRP
      const mrpM = html.match(/class="[^"]*a-text-price[^"]*"[^>]*><span[^>]*>₹([\d,]+)/i) ||
                   html.match(/M\.R\.P\.[^₹]*₹\s*([\d,]+)/i);
      const mrp = mrpM ? parseInt(mrpM[1].replace(/,/g,'')) : price;
      const discNum = mrp > price ? Math.round((1 - price / mrp) * 100) : 0;
      if (discNum < 10) continue; // skip near-zero discount

      // Image
      let image = '';
      const imgTagM = html.match(/<img[^>]*id="(?:landingImage|imgBlkFront)"[^>]*>/i);
      if (imgTagM) {
        const tag = imgTagM[0];
        const dynM = tag.match(/data-a-dynamic-image="([^"]+)"/i);
        if (dynM) { const urlM = dynM[1].match(/(https?:\/\/[^&"']+\.(?:jpg|png|jpeg))/i); if (urlM) image = urlM[1]; }
        if (!image) { const hM = tag.match(/data-old-hires="([^"]+)"/i); if (hM) image = hM[1]; }
        if (!image) { const sM = tag.match(/src="([^"]+)"/i); if (sM && !sM[1].includes('transparent-pixel') && !sM[1].startsWith('data:')) image = sM[1]; }
      }
      if (!image) { const hM = html.match(/"hiRes"\s*:\s*"([^"]+)"/i); if (hM) image = hM[1]; }

      // Highlights from bullet points
      const highlights = [];
      for (const m of html.matchAll(/<span class="a-list-item">([\s\S]*?)<\/span>/gi)) {
        const t = m[1].replace(/<[^>]*>/g,'').replace(/\s+/g,' ').trim();
        if (t.length > 15 && t.length < 250 && highlights.length < 5) highlights.push(t);
      }

      // Category — from breadcrumb if available, else title keywords
      const bcMa = html.match(/id="wayfinding-breadcrumbs[^"]*"([\s\S]{0,3000})/);
      let category = null;
      if (bcMa) {
        const links = [...bcMa[1].matchAll(/<a[^>]*>([^<]+)<\/a>/g)].map(m => m[1].trim());
        for (const link of links) { const mc = mapAmazonBreadcrumbCategory(link); if (mc) { category = mc; break; } }
      }
      if (!category) category = detectCategoryFromTitle(title);

      added.push({
        id: `amzdeal_${Date.now()}_${added.length}`,
        asin, title,
        price: '₹' + price.toLocaleString('en-IN'),
        mrp: '₹' + mrp.toLocaleString('en-IN'),
        disc: discNum > 0 ? `-${discNum}%` : '0%',
        image, link: hasUptoOffInTitle(title) ? buildManualCueLink(`https://www.amazon.in/dp/${asin}`, env) : `https://www.amazon.in/dp/${asin}?tag=${TAG}`,
        category, highlights: highlights.length ? highlights : ['Great deal on Amazon'],
        lowestPriceText: null, featured: false, hidden: false, outOfStock: false,
        order: 0, addedAt: new Date().toISOString(), originalPrice: '₹' + price.toLocaleString('en-IN'),
      });
    } catch (e) {
      console.error(`AMZ deal ASIN ${asin}: ${e.message}`);
    }
  }

  // Always save updated queue (remove processed items regardless of success)
  if (env.KV) await env.KV.put('amazonDealsQueue', JSON.stringify(remaining));

  if (added.length === 0) {
    return { success: true, count: 0, message: `Amazon Deals sync: processed ${toProcess.length} ASINs, 0 valid deals (low discount or no data)` };
  }

  const trimmed = await capLiveAndBury([...added, ...products], env);
  await saveProductsFile(trimmed, sha, `Amazon deals sync: +${added.length}`, env);
  return { success: true, count: added.length, message: `Amazon Deals sync: added ${added.length} deal${added.length > 1 ? 's' : ''} from amazon.in/deals`, addedProducts: added };
}

// ── handlePublish ─────────────────────────────────────────────────────────────

async function handlePublish(body, env) {
  const { product, category, highlights } = body;
  if (product.asin) await restoreAsinIfDeleted(product.asin, env);

  const { products, sha } = await getProductsFile(env);
  const cleanTitleStr = sanitizeTitle(product.title || '');
  let finalLink = product.link || '';
  if (hasUptoOffInTitle(cleanTitleStr)) {
    if (!finalLink.includes('linksredirect.com')) {
      const rawUrl = product.asin ? `https://www.amazon.in/dp/${product.asin}` : getOriginalUrl(finalLink);
      if (rawUrl) finalLink = buildManualCueLink(rawUrl, env);
    }
  }

  const newProduct = {
    id: Date.now().toString(), asin: product.asin || '', title: cleanTitleStr,
    price: product.price || '', mrp: product.mrp || '', disc: product.disc || '0%',
    image: product.image || '', link: finalLink, category: category || '',
    highlights: highlights || [], lowestPriceText: product.lowestPriceText || null,
    featured: false, hidden: false, outOfStock: false, order: 0, addedAt: today,
  };
  let filtered = products;
  if (product.asin) {
    filtered = products.filter(p => !p.asin || p.asin.toUpperCase() !== product.asin.toUpperCase());
  } else if (product.link) {
    const linkLower = product.link.toLowerCase();
    filtered = products.filter(p => !p.link || p.link.toLowerCase() !== linkLower);
  }
  const updated = await capLiveAndBury([newProduct, ...filtered], env);
  await saveProductsFile(updated, sha, `Add deal: ${product.title.slice(0,60)}`, env);

  // Post new deal to Telegram channels (fire-and-forget) — tracked, so the
  // 5-min cron won't see it as "unposted" and send it again.
  postDealsAndTrack([newProduct], env).catch(e => console.error('TG post failed:', e.message));

  // Legacy: write card to index.html
  const params = new URLSearchParams({ title: product.title, cat: category, price: product.price, mrp: product.mrp, disc: product.disc, updated: today.slice(0,10), img: product.image, link: product.link, hl: (highlights||[]).join('|') });
  const cardHtml = `    <!-- Card added ${today.slice(0,10)} -->\n    <a class="product-card" data-cat="${category.toLowerCase()}" href="product.html?${params.toString()}">\n      <div class="card-img-wrap">\n        <img src="${product.image}" alt="${product.title}" style="width:100%;height:180px;object-fit:contain;display:block;background:#fff;">\n        <span class="discount-badge">${product.disc}</span>\n      </div>\n      <div class="card-body">\n        <p class="card-title">${product.title}</p>\n        <div class="card-prices" data-nosnippet>\n          <div class="price-original">${product.mrp}</div>\n          <div class="price-current">${product.price}</div>\n        </div>\n        <span class="btn-view">View More</span>\n      </div>\n    </a>`;

  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/index.html`;
  const ghHdrs = ghHeaders(env);
  const getResp = await fetch(apiUrl, { headers: ghHdrs });
  if (!getResp.ok) return json({ error: 'Could not fetch index.html' }, 502);
  const file = await getResp.json();
  const rawBytes = atob(file.content.replace(/\n/g,''));
  const uint8 = new Uint8Array(rawBytes.length);
  for (let i = 0; i < rawBytes.length; i++) uint8[i] = rawBytes.charCodeAt(i);
  const current = new TextDecoder('utf-8').decode(uint8);
  const marker = '  <div class="products-grid" id="productsGrid">\n';
  if (!current.includes(marker)) return json({ error: 'Products grid marker not found' }, 500);
  let cleanedHtml = current;
  if (product.asin) {
    const re = new RegExp(`\\s*(?:<!-- Card added [^>]* -->)?\\s*<a class="product-card"[^>]*href="[^"]*${product.asin.toUpperCase()}[^"]*"[^>]*>[\\s\\S]*?<\\/a>`, 'gi');
    cleanedHtml = cleanedHtml.replace(re, '');
  }
  const putResp = await fetch(apiUrl, { method: 'PUT', headers: { ...ghHdrs, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: `Add deal: ${product.title.slice(0,60)}`, content: encodeBase64Unicode(cleanedHtml.replace(marker, marker + '\n' + cardHtml + '\n\n')), sha: file.sha }) });
  if (!putResp.ok) { const err = await putResp.json().catch(()=>({})); return json({ error: 'GitHub commit failed', details: err.message }, 502); }
  return json({ success: true });
}

// ── handleUpload ──────────────────────────────────────────────────────────────

async function handleUpload(body, env) {
  const { filename, content } = body;
  if (!filename || !content) return json({ error: 'Missing filename or content' }, 400);
  let cleanPath = filename.replace(/\\/g,'/').replace(/\.\./g,'');
  if (cleanPath.startsWith('/')) cleanPath = cleanPath.slice(1);
  if (!cleanPath.startsWith('images/')) cleanPath = 'images/' + cleanPath;
  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/${cleanPath}`;
  const putResp = await fetch(apiUrl, { method: 'PUT', headers: { ...ghHeaders(env), 'Content-Type': 'application/json' }, body: JSON.stringify({ message: `Upload image: ${cleanPath}`, content: content.replace(/[^A-Za-z0-9+/=]/g,'') }) });
  const rawText = await putResp.text();
  if (!putResp.ok) { let m = rawText.slice(0,500); try { m = JSON.parse(rawText).message || m; } catch {} return json({ error: 'GitHub image upload failed', details: `HTTP ${putResp.status}: ${m}` }, 502); }
  return json({ success: true, path: cleanPath });
}

// ── handleDebug ───────────────────────────────────────────────────────────────

async function handleDebug(env) {
  const secrets = {
    PA_ACCESS_KEY: env.PA_ACCESS_KEY ? env.PA_ACCESS_KEY.slice(0,20)+'...' : 'NOT SET',
    PA_SECRET_KEY: env.PA_SECRET_KEY ? env.PA_SECRET_KEY.slice(0,10)+'...' : 'NOT SET',
    PA_PARTNER_TAG: env.PA_PARTNER_TAG || 'NOT SET',
    ADMIN_PASSWORD: env.ADMIN_PASSWORD ? 'SET' : 'NOT SET',
    GITHUB_TOKEN: env.GITHUB_TOKEN ? { length: env.GITHUB_TOKEN.length, prefix: env.GITHUB_TOKEN.slice(0,10) } : 'NOT SET',
    KV: env.KV ? 'BOUND' : 'NOT BOUND',
  };
  let token, tokenStatus, tokenFull;
  try {
    cachedToken = null;
    const tResp = await fetchWithTimeout('https://api.amazon.com/auth/o2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=client_credentials&client_id=${encodeURIComponent(env.PA_ACCESS_KEY)}&client_secret=${encodeURIComponent(env.PA_SECRET_KEY)}&scope=creatorsapi%3A%3Adefault` });
    tokenStatus = tResp.status; const tData = await tResp.json(); tokenFull = JSON.stringify(tData).slice(0,200); token = tData.access_token;
  } catch (e) { return json({ secrets, tokenError: e.message }); }
  const reqPayload = { keywords:'boat', resources:['images.primary.large','itemInfo.title','offersV2.listings.price'], partnerTag: env.PA_PARTNER_TAG, partnerType:'Associates', marketplace:'www.amazon.in', itemCount:1 };
  let searchStatus, searchRaw;
  try {
    const sResp = await Promise.race([fetch('https://creatorsapi.amazon/catalog/v1/searchItems',{method:'POST',headers:{'Authorization':`Bearer ${token}`,'Content-Type':'application/json','x-marketplace':'www.amazon.in'},body:JSON.stringify(reqPayload)}),new Promise((_,r)=>setTimeout(()=>r(new Error('timeout')),15000))]);
    searchStatus = sResp.status; searchRaw = await sResp.text();
  } catch(e){ searchRaw = e.message; searchStatus = 0; }
  let ghStatus, ghResp;
  try { const r = await fetch('https://api.github.com/repos/akshayjango/dealbuster',{headers:ghHeaders(env)}); ghStatus = r.status; ghResp = await r.text(); } catch(e){ ghStatus=0; ghResp=e.message; }
  return json({ secrets, step1_token:{httpStatus:tokenStatus,response:tokenFull,tokenObtained:!!token}, step2_search:{httpStatus:searchStatus,rawResponse:searchRaw.slice(0,1000)}, step3_github:{httpStatus:ghStatus,rawResponse:ghResp.slice(0,500)} });
}

// ── Router ────────────────────────────────────────────────────────────────────

// ── Telegram Bot ──────────────────────────────────────────────────────────────

const TG_CHANNELS = ['@dealbusterindia'];
const TG_ADMIN_ID = 715667303;

async function tgSend(token, chatId, text, opts = {}) {
  return fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true, ...opts }),
  });
}

async function tgSendPhoto(token, chatId, photo, caption, opts = {}) {
  return fetch(`https://api.telegram.org/bot${token}/sendPhoto`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, photo, caption, ...opts }),
  });
}

function escTg(text) {
  return (text || '').replace(/([_*\[\]()~`>#+\-=|{}.!\\])/g, '\\$1');
}

function escHtml(text) {
  return (text || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function trimTitle(raw) {
  let rawTitle = sanitizeTitle(raw).slice(0, 200);
  const pipeIdx = rawTitle.indexOf(' | ');
  const commaIdx = rawTitle.indexOf(',');
  const cutIdx = [pipeIdx, commaIdx].filter(i => i > 0).sort((a, b) => a - b)[0];
  if (cutIdx) rawTitle = rawTitle.slice(0, cutIdx).trim();
  return rawTitle;
}

function dealLink(product, tag, env = {}) {
  if (hasUptoOffInTitle(product?.title)) {
    if (product.link && product.link.includes('linksredirect.com')) {
      return product.link;
    }
    const rawAmz = product.asin
      ? `https://www.amazon.in/dp/${product.asin}`
      : getOriginalUrl(product.link || '');
    return rawAmz ? buildManualCueLink(rawAmz, env) : product.link || '';
  }
  return product.asin
    ? `https://www.amazon.in/dp/${product.asin}?tag=${tag}`
    : product.link || '';
}

function formatDealMsg(product, tag, isLowest = false, env = {}) {
  const link = dealLink(product, tag, env);
  const title = (isLowest ? 'Lowest ' : '') + escHtml(trimTitle(product.title));
  const price = product.price || '';
  const mrp = product.mrp || '';
  const disc = product.disc || '';
  const priceRow = price ? `✅Deal Price: <b>${escHtml(price)}</b>` : '';
  const mrpRow = mrp ? `❌MRP: ${escHtml(mrp)}` : '';
  const discRow = disc ? `Discount: ${escHtml(disc)}` : '';
  const detailsBlock = [priceRow, mrpRow, discRow].filter(Boolean).join('\n');
  return detailsBlock ? `${title}\n${detailsBlock}\n\n👉 ${link}` : `${title}\n\n👉 ${link}`;
}

// Plain-text caption for pasting into the Facebook deals group. No HTML/markdown
// (FB ignores formatting) — emojis + blank lines only.
function formatFbCaption(product, tag, isLowest = false, env = {}) {
  const title = (isLowest ? 'Lowest ' : '') + trimTitle(product.title);
  const price = product.price || '';
  const link = dealLink(product, tag, env);
  const priceBlock = price ? `💥 Deal Price @ ${price} 👇\n${link}` : `👇\n${link}`;
  return `🔥 ${title}\n${priceBlock}`;
}

// Tracks which products have already been posted — by id AND by ASIN. ASIN is the
// durable key: if a product's id ever changes (cap eviction, a sync re-adding it,
// any future bug) but the ASIN is the same, this still recognizes it as already
// posted. id-only tracking couldn't survive that and would repost it as "new".
function isAlreadyPosted(p, postedIds) {
  return postedIds.has(p.id) || (p.asin && postedIds.has(p.asin.toUpperCase()));
}
function markPosted(p, postedIds) {
  postedIds.add(p.id);
  if (p.asin) postedIds.add(p.asin.toUpperCase());
}

// Inline-keyboard row with the FB-caption button (and Keepa price history when
// the ASIN is known). Shown on approval DMs and autopost companion DMs alike.
function fbCaptionRow(p) {
  const row = [{ text: '📘 FB Caption', callback_data: `fbcap_${p.id}` }];
  if (p.asin) {
    // Keepa domain 10 = amazon.in; the page is buildable from ASIN alone.
    // (pricehistory.app can't do this — its product URLs are non-derivable slugs.)
    row.push({ text: '📈 Price History', url: `https://keepa.com/#!product/10-${p.asin.toUpperCase()}` });
  }
  return row;
}

// Same "no price" definition as the admin dashboard's ₹ N/A filter — keep in sync.
function isZeroPrice(p) {
  return !p.price || p.price === '₹0' || p.price === '₹';
}

// ── Tombstones ────────────────────────────────────────────────────────────────
// Dead products (OOS / price gone) are kept in products.json as invisible
// tombstones instead of being deleted. The source feeds (DR newest-240, IFS
// trending) keep listing a product for days after it dies on Amazon; if we
// dropped it from the array, the very next sync would see it as "new" and
// re-add it at the top — and it recycled like that for DAYS (top of site →
// OOS/₹0 → bottom → evicted → re-added at top, with a Telegram DM on every
// lap; one geyser did 20 laps in two days). Tombstones block the re-add via
// the syncs' existingByAsin check while hidden:true keeps them off the site
// and out of the TG queue. They don't count toward the 720 live cap and are
// pruned after 3 days — the observed recycle window was ~2 days (the "20
// laps" case above), so 3 keeps a 1.5x margin above that (was 4/2x; dropped
// deliberately, not down to 2/zero-margin, since matching the worst
// observed case exactly is what caused this same spam loop to ship broken
// twice before) without sitting on dead weight for two full weeks like the
// original 14 did.
const TOMBSTONE_TTL_MS = 1 * 24 * 60 * 60 * 1000;
function isDead(p) {
  return !!p.dead;
}
function makeTombstone(p) {
  return { ...p, hidden: true, outOfStock: true, dead: new Date().toISOString() };
}
// Cap live products at 1440. EVERY evictee becomes a tombstone — in-stock
// ones too, not just dead ones. At current add volume the cap evicts in ~1-3
// days while the DR feed still lists a deal for ~2+ days, so clearing TG
// marks at eviction time re-DM'd even healthy deals when the feed re-added
// them the next cycle. The ledger clear now happens when a tombstone EXPIRES
// (4 days): by then the feeds have long dropped the deal, so if it ever
// comes back it's a genuine return and posts to Telegram as new.
// NOTE: price/OOS checking (checkAndCleanDeals) now rotates across ALL live
// products up to this cap — full-cycle check staleness scales with it
// (~72min at 720 -> ~2.4hr at 1440); see the comment there for the tradeoff.
async function capLiveAndBury(all, env, cap = 1800) {
  const now = Date.now();
  const liveDeals = [];
  const tombs = [];
  const expired = [];

  for (const p of all) {
    // Permanent deletion filter: Amazon deals with a known rating < 3.6 are dropped completely
    if (p.asin && typeof p.rating === 'number' && p.rating < 3.6) {
      continue;
    }

    if (isDead(p)) {
      const ttl = p.asin ? TOMBSTONE_TTL_MS : (1 * 24 * 60 * 60 * 1000);
      if (now - Date.parse(p.dead) < ttl) {
        tombs.push(p);
      } else {
        expired.push(p);
      }
    } else {
      liveDeals.push(p);
    }
  }

  // Sort all live deals (featured first, price-increased last, newest addedAt first)
  liveDeals.sort((a, b) => {
    if (a.featured && !b.featured) return -1;
    if (!a.featured && b.featured) return 1;
    if (a.priceIncreased && !b.priceIncreased) return 1;
    if (!a.priceIncreased && b.priceIncreased) return -1;
    return Date.parse(b.addedAt || 0) - Date.parse(a.addedAt || 0);
  });

  // Combined global cap of 1800 live deals across all stores
  let keptLive = liveDeals;
  if (liveDeals.length > cap) {
    keptLive = liveDeals.slice(0, cap);
    tombs.push(...liveDeals.slice(cap).map(makeTombstone));
  }

  if (expired.length) {
    await clearTgPostedMarks(expired, env).catch(e => console.error('Tombstone-expiry ledger clear failed:', e.message));
  }

  return [...keptLive, ...tombs].map((p, i) => ({ ...p, order: i }));
}

// ── Autopost toggle + manual-approval queue ───────────────────────────────────
// When autopost is OFF, deals that would normally hit the channels are instead
// DM'd to the admin with Approve/Reject buttons. Approving sends that one deal
// through sendToChannels() directly — same DO, same choke point, just a manual
// trigger instead of the cron's automatic one.

async function isAutopostEnabled(env) {
  if (!env.KV) return true;
  const v = await env.KV.get('autopost_enabled');
  return v !== 'false'; // unset (fresh KV) === ON
}

async function setAutopostEnabled(enabled, env) {
  if (!env.KV) throw new Error('KV not configured');
  await env.KV.put('autopost_enabled', enabled ? 'true' : 'false');
}

const APPROVAL_TTL_MS = 4 * 60 * 60 * 1000; // 4h

// Pending approvals live in the TgPoster DO, NOT in KV. They used to be one
// shared KV JSON list, but three writers rewrite that list every few minutes
// (both 5-min schedulers queueing/sweeping, plus the Approve tap) and KV is
// last-write-wins across colos — a cron write that read the list before a deal
// was queued would write it back without that deal, leaving a DM in the admin
// chat whose buttons answered "Already handled or expired" minutes after it
// arrived. The DO serializes every mutation, so an entry only disappears when
// it is actually approved, rejected, or expired.
async function pendingApprovalsDO(env, path, body) {
  if (!env.TG_POSTER) throw new Error('TG_POSTER binding missing');
  const stub = env.TG_POSTER.get(env.TG_POSTER.idFromName('tg'));
  const r = await stub.fetch(`https://tg-poster${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  });
  if (!r.ok) throw new Error(`TgPoster ${path}: ${r.status} ${await r.text().catch(() => '')}`);
  return r.json();
}

// Erase products from the TG posted ledger (DO authoritative + KV advisory
// mirror) so a genuine future appearance — manual add or any sync — goes to
// the channel/queue again like a brand-new deal. Two call sites:
//  1. Tombstone expiry (4 days after burial) — never call this AT eviction
//     time instead: the feeds still list freshly evicted deals, and clearing
//     then re-DM'd every re-add (the July 2026 spam loop).
//  2. Reject — a deliberate per-instance admin decision, not an unattended
//     timeout, so it shouldn't blacklist the ASIN forever; if the same
//     product resurfaces later it deserves a fresh look.
// Approval EXPIRY does NOT call this (see sweepExpiredApprovals) — an
// unanswered timeout is left permanently marked posted, same as approve.
// Best-effort: if either clear fails the deal just stays "posted" and a
// re-add is silently skipped (missed post, never a duplicate — the preferred
// failure mode).
async function clearTgPostedMarks(products, env) {
  const keys = [];
  for (const p of products || []) {
    if (p.id) keys.push(p.id);
    if (p.asin) keys.push(p.asin.toUpperCase());
  }
  if (!keys.length) return;
  try {
    await pendingApprovalsDO(env, '/posted/clear', { keys });
  } catch (e) {
    console.error('TG ledger clear (DO) failed:', e.message);
    return; // don't clear the mirror if the authoritative ledger still blocks
  }
  try {
    const ids = new Set(JSON.parse(await env.KV.get('tg_posted_ids') || '[]'));
    let changed = false;
    for (const k of keys) if (ids.delete(k)) changed = true;
    if (changed) await env.KV.put('tg_posted_ids', JSON.stringify(Array.from(ids)));
  } catch (e) {
    console.error('TG ledger clear (KV mirror) failed:', e.message);
  }
}

async function queueForApproval(products, env) {
  const token = env.TELEGRAM_BOT_TOKEN;
  if (!token) { console.error('Cannot queue for approval — TELEGRAM_BOT_TOKEN missing'); return; }

  const tag = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const now = Date.now();

  // Claim in the DO ledger BEFORE DMing — authoritative and serialized, so a
  // deal can only ever be claimed once no matter how many schedulers race.
  // (The old KV-only claim raced: read-modify-write of one JSON value across
  // colos lost claims, and the same deals re-DM'd the admin on every tick.)
  // Claiming also covers reject/expire: those must never resurface either.
  // NOTE: approving a queued deal must therefore send with force:true — its
  // ledger marks already exist from this claim.
  const queued = [];
  try {
    const items = products.map(p => ({ id: p.id, asin: p.asin || null }));
    const { fresh } = await pendingApprovalsDO(env, '/posted/claim', { items });
    const freshSet = new Set(fresh);
    queued.push(...products.filter(p => freshSet.has(p.id)));
  } catch (e) {
    console.error('Approval claim failed — not queueing to avoid repeats:', e.message);
    return;
  }
  // Advisory KV mirror so the cron's cheap pre-check stops proposing these.
  // Mark EVERY requested product, not just the ones that came back fresh. If
  // the DO already held some of these as posted (e.g. a prior tick's mirror
  // write failed right after a successful DO claim), this is the only place
  // that heals the mirror for them. The old code returned early when nothing
  // came back fresh — skipping this block entirely — so once the mirror fell
  // behind the DO even once, getUnpostedTgFresh kept re-selecting the same
  // already-claimed ids forever: every tick got fresh:[] and bailed before
  // reaching here, permanently wedging the front of the queue and silently
  // starving all genuinely new deals behind it (no error logged either —
  // this is exactly how posting went quiet for 43 minutes with fresh deals
  // sitting in products.json the whole time).
  try {
    const ids = new Set(JSON.parse(await env.KV.get('tg_posted_ids') || '[]'));
    products.forEach(p => markPosted(p, ids));
    await env.KV.put('tg_posted_ids', JSON.stringify(Array.from(ids).slice(-20000)));
  } catch (e) {
    console.error('KV mirror failed (advisory only):', e.message);
  }

  if (!queued.length) return;

  const entries = [];
  for (const p of queued) {
    const text = formatDealMsg(p, tag, false, env);
    const keyboard = { inline_keyboard: [
      [
        { text: '✅ Approve', callback_data: `tgappr_a_${p.id}` },
        { text: '❌ Reject', callback_data: `tgappr_r_${p.id}` },
      ],
      fbCaptionRow(p),
    ] };
    try {
      let messageId = null;
      if (p.image) {
        const r = await tgSendPhoto(token, TG_ADMIN_ID, p.image, text, { parse_mode: 'HTML', reply_markup: keyboard });
        const data = await r.json().catch(() => null);
        messageId = data?.result?.message_id ?? null;
        if (!r.ok) {
          const r2 = await tgSend(token, TG_ADMIN_ID, text, { parse_mode: 'HTML', reply_markup: keyboard });
          const d2 = await r2.json().catch(() => null);
          messageId = d2?.result?.message_id ?? null;
        }
      } else {
        const r = await tgSend(token, TG_ADMIN_ID, text, { parse_mode: 'HTML', reply_markup: keyboard });
        const data = await r.json().catch(() => null);
        messageId = data?.result?.message_id ?? null;
      }
      entries.push({ product: p, queuedAt: now, messageId });
    } catch (e) {
      console.error('Failed to queue deal for approval:', e.message);
    }
  }

  if (!entries.length) return;
  try {
    await pendingApprovalsDO(env, '/pending/put', { entries });
  } catch (e) {
    console.error('Failed to store pending approvals — Approve buttons for this batch will be dead:', e.message);
  }
}

async function tgAnswerCallback(token, id, text) {
  return fetch(`https://api.telegram.org/bot${token}/answerCallbackQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ callback_query_id: id, text: text || '', show_alert: false }),
  });
}

async function tgSetKeyboard(token, chatId, messageId, rows) {
  return fetch(`https://api.telegram.org/bot${token}/editMessageReplyMarkup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, message_id: messageId, reply_markup: { inline_keyboard: rows || [] } }),
  });
}

async function handleApprovalCallback(cq, env) {
  const token = env.TELEGRAM_BOT_TOKEN;
  if (!token) return new Response('ok');
  if (cq.from?.id !== TG_ADMIN_ID) {
    await tgAnswerCallback(token, cq.id, '⛔ Unauthorized');
    return new Response('ok');
  }

  // FB caption request — look the product up fresh from products.json (no KV,
  // no DO storage) and send the caption in a <pre> block: tapping a monospace
  // block in Telegram copies it in one tap.
  const fb = (cq.data || '').match(/^fbcap_(.+)$/);
  if (fb) {
    const productId = fb[1];
    try {
      const { products } = await getProductsFile(env);
      const p = products.find(x => x.id === productId);
      if (!p) {
        await tgAnswerCallback(token, cq.id, 'Deal no longer in database');
        return new Response('ok');
      }
      const tag = env.PA_PARTNER_TAG || 'dealbuster002-21';
      const caption = formatFbCaption(p, tag, false, env);
      await tgSend(token, TG_ADMIN_ID, `<pre>${escHtml(caption)}</pre>`, { parse_mode: 'HTML' });
      await tgAnswerCallback(token, cq.id, '📘 Caption sent — tap it to copy');
    } catch (e) {
      console.error('FB caption failed:', e.message);
      await tgAnswerCallback(token, cq.id, '⚠️ Failed, try again');
    }
    return new Response('ok');
  }

  const m = (cq.data || '').match(/^tgappr_(a|r)_(.+)$/);
  if (!m) { await tgAnswerCallback(token, cq.id, ''); return new Response('ok'); }
  const [, action, productId] = m;

  // Atomic take from the DO — a second tap on the same button (or a concurrent
  // sweep) finds nothing and gets "already handled" instead of double-posting.
  let entry = null;
  try {
    ({ entry } = await pendingApprovalsDO(env, '/pending/take', { productId }));
  } catch (e) {
    console.error('Pending take failed:', e.message);
  }
  if (!entry) {
    await tgAnswerCallback(token, cq.id, 'Already handled or expired');
    return new Response('ok');
  }

  // Drop the Approve/Reject row but keep FB Caption / Price History usable
  // after the decision.
  if (entry.messageId) await tgSetKeyboard(token, TG_ADMIN_ID, entry.messageId, [fbCaptionRow(entry.product)]).catch(() => {});

  if (action === 'a') {
    // companionDm off: the approval DM above already carries these buttons.
    // force: the DO ledger already holds this deal's marks from queue time
    // (queueForApproval's /posted/claim) — without force the DO would skip it
    // as "already posted". Safe: /pending/take is atomic, single approve only.
    await sendToChannels([entry.product], env, { companionDm: false, force: true });
    await tgAnswerCallback(token, cq.id, '✅ Posted to channel');
    await tgSend(token, TG_ADMIN_ID, escTg(`✅ Approved & posted: ${entry.product.title.slice(0,60)}`));
  } else {
    // Clear the ledger mark this claim set — a reject means "not this listing",
    // not "never show this ASIN again". Without this, the product silently
    // stopped reaching Telegram on every future re-add, forever.
    await clearTgPostedMarks([entry.product], env).catch(e => console.error('Reject ledger clear failed:', e.message));
    await tgAnswerCallback(token, cq.id, '❌ Rejected');
    await tgSend(token, TG_ADMIN_ID, escTg(`❌ Rejected: ${entry.product.title.slice(0,60)}`));
  }
  return new Response('ok');
}

// Most recent 2:00 AM IST as a UTC timestamp — the daily cutoff below which
// pending approvals don't survive, so overnight backlogs don't greet the admin
// in the morning. Workers run on UTC; IST is UTC+5:30.
function lastDailyCutoff(now) {
  const IST_OFFSET = 330 * 60 * 1000;
  const DAY = 24 * 60 * 60 * 1000;
  const istNow = now + IST_OFFSET;
  let cutoffIst = Math.floor(istNow / DAY) * DAY + 2 * 60 * 60 * 1000;
  if (cutoffIst > istNow) cutoffIst -= DAY;
  return cutoffIst - IST_OFFSET;
}

// Drops queued deals older than 4h OR queued before the last 2 AM IST daily
// cutoff — piggybacks on the existing 5-min TG cron so this needs no extra
// Cron Trigger. The expiry itself happens inside the DO.
async function sweepExpiredApprovals(env) {
  const now = Date.now();
  const { expired } = await pendingApprovalsDO(env, '/pending/sweep', {
    now, ttlMs: APPROVAL_TTL_MS, cutoff: lastDailyCutoff(now),
  });
  if (!expired.length) return;

  // Expiry does NOT clear the posted-ledger mark — deliberately, as of
  // 2026-07-21. It used to (so a genuinely-missed deal wasn't blacklisted
  // forever), then got a one-free-requeue bound after that looped into an
  // all-night spam storm (2am-7am: expire -> mark cleared -> next tick
  // instantly re-queues it since nothing new exists to fill the slot ->
  // ignored -> expires again -> repeat). The bounded version barely helped
  // anyway: the second expiry window almost always falls in the same
  // overnight absence as the first. Simpler and safer to just treat an
  // unanswered expiry as final, same as if it had actually been posted.
  // The deal stays visible on the site regardless; it just won't get
  // re-DM'd for this ASIN again (same durability as approve). Reject is
  // unaffected — that's a deliberate per-instance admin decision, not an
  // unattended timeout, so it still clears the mark for a fresh look later.

  const token = env.TELEGRAM_BOT_TOKEN;
  if (!token) return;
  for (const e of expired) {
    if (e.messageId) await tgSetKeyboard(token, TG_ADMIN_ID, e.messageId, []).catch(() => {});
  }
  console.log(`Swept ${expired.length} expired approval(s), left marked posted (no re-queue)`);
}

// Single choke point for posting to Telegram. Every call site (manual publish,
// bot webhook, IFS manual sync, the cron, the external cron pinger) MUST go
// through this. All work is delegated to the TgPoster Durable Object — a single
// strongly-consistent instance that serializes every post batch globally. KV
// locks cannot do this job: KV is eventually consistent across data centers, so
// the internal cron and the external /cron-post-deals pinger (or a pinger retry)
// running in different colos could both read "not posted yet" and send the same
// batch twice. A DO has exactly one live instance worldwide, so that race is
// structurally impossible.
async function postDealsAndTrack(products, env) {
  const list = (products || []).filter(Boolean).filter(p => {
    if (isZeroPrice(p)) { console.log(`Skipping TG post (₹0/no price): ${p.title || p.id}`); return false; }
    if (p.priceIncreased) { console.log(`Skipping TG post (price increased >15%/25%): ${p.title || p.id}`); return false; }
    return true;
  });
  if (!list.length) return;

  if (!(await isAutopostEnabled(env))) {
    await queueForApproval(list, env);
    return;
  }
  await sendToChannels(list, env);
}

// Does the actual send — talks to the DO (or the KV fallback). Called by
// postDealsAndTrack's autopost path above, and directly by the approval
// callback once a queued deal is approved. Both routes end here, so the DO
// stays the single serialization point no matter which path a deal took.
// Returns how many actually went out (the DO skips already-posted ones unless
// force is set — force still claims before sending, it only bypasses the
// "seen before" check for deliberate manual re-posts).
async function sendToChannels(products, env, { force = false, companionDm = true } = {}) {
  const list = (products || []).filter(Boolean);
  if (!list.length) return 0;

  if (env.TG_POSTER) {
    const stub = env.TG_POSTER.get(env.TG_POSTER.idFromName('tg'));
    const r = await stub.fetch('https://tg-poster/post', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ products: list, force, companionDm }),
    });
    if (!r.ok) { console.error('TgPoster DO failed:', r.status, await r.text().catch(() => '')); return 0; }
    const { posted } = await r.json().catch(() => ({ posted: 0 }));
    console.log(`TgPoster: sent ${posted} of ${list.length} requested (rest already posted)`);
    return posted;
  }

  // Fallback if the DO binding is missing (should not happen once deployed):
  // best-effort KV claim-before-send. Weaker than the DO — eventually-consistent
  // — but keeps posting alive rather than going silent.
  console.error('TG_POSTER binding missing — using weaker KV fallback');
  const postedIds = new Set(JSON.parse(await env.KV.get('tg_posted_ids') || '[]'));
  const toSend = force ? list : list.filter(p => !isAlreadyPosted(p, postedIds));
  if (!toSend.length) return 0;
  toSend.forEach(p => markPosted(p, postedIds));
  await env.KV.put('tg_posted_ids', JSON.stringify(Array.from(postedIds).slice(-20000)));
  for (const p of toSend) {
    await postDealToChannels(p, env, { companionDm }).catch(e => console.error('TG post failed:', e.message));
  }
  return toSend.length;
}

// ── TgPoster Durable Object ───────────────────────────────────────────────────
// One instance globally (idFromName('tg')). Every Telegram post batch flows
// through here, strictly one at a time via the promise chain, with the
// posted-ids ledger in DO storage (strongly consistent, unlike KV). Ids are
// stored one-per-key ("posted:<id>") because a single 20k-entry JSON value
// would blow the DO's 128 KiB per-value limit.
export class TgPoster {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.chain = Promise.resolve(); // serializes concurrent post requests
  }

  async fetch(request) {
    let body;
    try { body = await request.json(); } catch { return new Response('bad request', { status: 400 }); }
    const path = new URL(request.url).pathname;
    // Everything — posts and pending-approval mutations — runs through the one
    // promise chain, so no two requests ever interleave.
    const run = this.chain.then(() => this.dispatch(path, body));
    this.chain = run.then(() => {}, () => {});
    try {
      const result = await run;
      return new Response(JSON.stringify(result), { headers: { 'Content-Type': 'application/json' } });
    } catch (e) {
      return new Response(JSON.stringify({ ok: false, error: e.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }
  }

  async dispatch(path, body) {
    switch (path) {
      case '/post': return { ok: true, posted: await this.postBatch(body.products || [], !!body.force, body.companionDm !== false) };
      case '/posted/claim': return this.postedClaim(body.items || []);
      case '/posted/check': return this.postedCheck(body.keys || []);
      case '/posted/clear': return this.postedClear(body.keys || []);
      case '/pending/put': return this.pendingPut(body.entries || []);
      case '/pending/take': return this.pendingTake(body.productId);
      case '/pending/sweep': return this.pendingSweep(body);
      case '/pending/count': return this.pendingCount();
      default: throw new Error(`unknown path: ${path}`);
    }
  }

  // Atomically claim items for the approval queue: returns the ids that were
  // NOT already in the posted ledger and marks them, all inside the DO's
  // serialized chain. This is the authoritative dedup for admin DMs — the KV
  // mirror alone raced (two 5-min schedulers doing read-modify-write on one
  // JSON value across colos lost claims, and any ledger clear resurrected
  // everything), which is how the same dead deal DM'd the admin 30+ times.
  async postedClaim(items) {
    await this.migrateFromKV();
    const fresh = [];
    const claim = {};
    for (const it of items) {
      if (!it?.id) continue;
      const keys = [`posted:${it.id}`];
      if (it.asin) keys.push(`posted:${it.asin.toUpperCase()}`);
      const found = await this.ctx.storage.get(keys);
      if ([...found.values()].some(Boolean)) continue;
      fresh.push(it.id);
      for (const k of keys) claim[k] = 1;
    }
    if (Object.keys(claim).length) await this.ctx.storage.put(claim);
    return { ok: true, fresh };
  }

  // Which of these ids/asins are in the posted-to-channel ledger. Batched
  // storage.get (128 keys/call), so ~1500 keys is a dozen cheap lookups.
  async postedCheck(keys) {
    await this.migrateFromKV();
    const posted = [];
    for (let i = 0; i < keys.length; i += 128) {
      const chunk = keys.slice(i, i + 128);
      const found = await this.ctx.storage.get(chunk.map(k => `posted:${k}`));
      for (const [k, v] of found) if (v) posted.push(k.slice('posted:'.length));
    }
    return { ok: true, posted };
  }

  // Forget posted ids/asins — called when deals fall off the site's 720 cap,
  // so a later re-add (sync or manual) posts to the channel again as new.
  async postedClear(keys) {
    await this.migrateFromKV();
    const full = keys.map(k => `posted:${k}`);
    for (let i = 0; i < full.length; i += 128) {
      await this.ctx.storage.delete(full.slice(i, i + 128));
    }
    return { ok: true, cleared: keys.length };
  }

  // ── Pending approvals (autopost OFF) ──────────────────────────────────────
  // Stored one-per-key ("pending:<productId>") in DO storage. Previously a
  // single KV JSON list, which the two 5-min schedulers and the Approve tap
  // all rewrote wholesale — last-write-wins races silently dropped entries and
  // made live Approve buttons answer "Already handled or expired".

  // One-time import of any approvals still queued in the old KV list.
  async migratePendingFromKV() {
    if (await this.ctx.storage.get('pending_migrated')) return;
    try {
      const old = (await this.env.KV.get('tg_pending_approvals', 'json')) || [];
      const batch = {};
      for (const e of old) if (e.product?.id) batch[`pending:${e.product.id}`] = e;
      if (Object.keys(batch).length) await this.ctx.storage.put(batch);
      await this.env.KV.delete('tg_pending_approvals');
    } catch (e) {
      console.error('Pending-approvals KV migration failed:', e.message);
    }
    await this.ctx.storage.put('pending_migrated', 1);
  }

  async pendingPut(entries) {
    await this.migratePendingFromKV();
    const batch = {};
    for (const e of entries) if (e.product?.id) batch[`pending:${e.product.id}`] = e;
    if (Object.keys(batch).length) await this.ctx.storage.put(batch);
    return { ok: true };
  }

  // Atomic get+delete — the caller either owns the entry exclusively or gets null.
  async pendingTake(productId) {
    await this.migratePendingFromKV();
    const key = `pending:${productId}`;
    const entry = await this.ctx.storage.get(key);
    if (entry) await this.ctx.storage.delete(key);
    return { ok: true, entry: entry ?? null };
  }

  async pendingSweep({ now, ttlMs, cutoff }) {
    await this.migratePendingFromKV();
    const expired = [];
    for (const [key, e] of await this.ctx.storage.list({ prefix: 'pending:' })) {
      if (now - e.queuedAt > ttlMs || e.queuedAt < cutoff) {
        expired.push(e);
        await this.ctx.storage.delete(key);
      }
    }
    return { ok: true, expired };
  }

  async pendingCount() {
    await this.migratePendingFromKV();
    return { ok: true, count: (await this.ctx.storage.list({ prefix: 'pending:' })).size };
  }

  keysFor(p) {
    const keys = [`posted:${p.id}`];
    if (p.asin) keys.push(`posted:${p.asin.toUpperCase()}`);
    return keys;
  }

  // One-time import of the existing KV ledger so nothing already posted gets
  // re-sent when the DO takes over.
  async migrateFromKV() {
    if (await this.ctx.storage.get('migrated_from_kv')) return;
    const old = JSON.parse(await this.env.KV.get('tg_posted_ids') || '[]');
    for (let i = 0; i < old.length; i += 128) {
      const batch = {};
      for (const id of old.slice(i, i + 128)) batch[`posted:${id}`] = 1;
      await this.ctx.storage.put(batch);
    }
    await this.ctx.storage.put('migrated_from_kv', 1);
  }

  // force skips the already-posted check (deliberate manual re-post from the
  // dashboard) but still claims before sending, like every other post.
  async postBatch(list, force = false, companionDm = true) {
    await this.migrateFromKV();

    const toSend = [];
    for (const p of list) {
      if (force) { toSend.push(p); continue; }
      const found = await this.ctx.storage.get(this.keysFor(p));
      if (![...found.values()].some(Boolean)) toSend.push(p);
    }
    if (!toSend.length) return 0;

    // Claim in DO storage before sending — any request that arrives during the
    // send sees the claim (strong consistency + serialized chain).
    const claim = {};
    for (const p of toSend) for (const k of this.keysFor(p)) claim[k] = 1;
    await this.ctx.storage.put(claim);

    for (const p of toSend) {
      await postDealToChannels(p, this.env, { companionDm }).catch(e => console.error('TG post failed:', e.message));
    }

    // Mirror into KV — only the cron's cheap "anything new?" pre-check reads
    // this (getUnpostedTgFresh). Advisory only; the DO ledger is authoritative.
    try {
      const ids = new Set(JSON.parse(await this.env.KV.get('tg_posted_ids') || '[]'));
      toSend.forEach(p => markPosted(p, ids));
      await this.env.KV.put('tg_posted_ids', JSON.stringify(Array.from(ids).slice(-20000)));
    } catch (e) {
      console.error('KV mirror failed:', e.message);
    }

    return toSend.length;
  }
}

async function getUnpostedTgFresh(env) {
  const postedIds = new Set(JSON.parse(await env.KV.get('tg_posted_ids') || '[]'));
  const { products } = await getProductsFile(env);
  // One-time fresh-start cutoff (KV `tg_fresh_start_cutoff`, ISO string): when
  // set, silently skips the entire existing backlog instead of working
  // through it — only products added AFTER the cutoff are eligible. This
  // doesn't need per-item ledger writes; everything already in products.json
  // at reset time was necessarily added before "now", and everything from any
  // future sync is added after — a plain addedAt comparison is exact for that
  // one purpose, unaffected by the ordering fuzziness noted below. Leave the
  // KV key in place permanently — once set, it's a no-op forever after (every
  // future addedAt is already past it), so there's no need to ever clear it.
  const cutoff = await env.KV.get('tg_fresh_start_cutoff');
  const cutoffMs = cutoff ? Date.parse(cutoff) : null;
  // products[] is already newest-first — that IS the site's recency ranking.
  // addedAt is not reliable for ordering: sync jobs stamp it while looping over
  // a batch (in source-feed order) and then prepend the whole batch, so within a
  // single batch addedAt increases while true recency decreases. Array position
  // is the only trustworthy signal.
  // Zero-price deals must be excluded HERE, before the batch slice — not just in
  // postDealsAndTrack. They are unpostable but never claimed (a later price sync
  // may fill the price), so if they merely got filtered after slicing they'd
  // permanently occupy the oldest-unposted batch slots and starve the queue:
  // slice(-5) kept returning the same ₹0 zombies while real new deals waited
  // at the top of the array (this shipped once — batches shrank to 2, then 0).
  const MAX_TG_POST_AGE_MS = 12 * 60 * 60 * 1000; // Only post deals added in the last 12 hours
  const now = Date.now();
  const unposted = products.filter(p => {
    if (p.hidden || p.outOfStock || isZeroPrice(p) || isAlreadyPosted(p, postedIds)) return false;
    if (cutoffMs !== null && Date.parse(p.addedAt) < cutoffMs) return false;
    const addedTime = Date.parse(p.addedAt || 0);
    if (!addedTime || (now - addedTime) > MAX_TG_POST_AGE_MS) return false;
    return true;
  });
  // Oldest unposted deals sit at the end of the array — send oldest-of-batch
  // first, newest last. Whatever doesn't fit in this batch of 5 carries over to
  // the next cron run, still oldest-first.
  const fresh = unposted.slice(-5).reverse();
  return { postedIds, fresh };
}

async function postNewDealsToTelegram(env) {
  const token = env.TELEGRAM_BOT_TOKEN;
  if (!token) return;

  const { fresh } = await getUnpostedTgFresh(env);
  if (!fresh.length) { console.log('TG cron: no new deals to post'); return; }

  await postDealsAndTrack(fresh, env);
  console.log(`TG cron: posted ${fresh.length} deals`);
}

// The actual send+track locking lives in postDealsAndTrack now. This wrapper is
// just a cheap pre-check (KV.get + a GitHub fetch, no KV write) so the 5-min
// cron doesn't touch GitHub/lock at all when there's nothing to post.
async function postNewDealsToTelegramLocked(env) {
  await sweepExpiredApprovals(env).catch(e => console.error('Approval sweep failed:', e.message));
  const { fresh } = await getUnpostedTgFresh(env);
  if (!fresh.length) { console.log('TG cron: nothing to post, skipping'); return; }
  await postNewDealsToTelegram(env);
}

async function postDealToChannels(product, env, { companionDm = true } = {}) {
  const token = env.TELEGRAM_BOT_TOKEN;
  if (!token) return;
  const noPrice = !product.price || product.price === '₹0' || product.price === '₹';
  if (noPrice) return;
  const tag = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const msg = formatDealMsg(product, tag, false, env);
  for (const ch of TG_CHANNELS) {
    try {
      if (product.image) {
        const r = await tgSendPhoto(token, ch, product.image, msg, { parse_mode: 'HTML' });
        if (!r.ok) await tgSend(token, ch, msg, { parse_mode: 'HTML' });
      } else {
        await tgSend(token, ch, msg, { parse_mode: 'HTML' });
      }
    } catch (e) {
      console.error('Telegram post failed for', ch, e.message);
    }
  }

  // Companion DM to the admin with an FB-caption button, so any deal can be
  // hand-picked for the Facebook group. Best-effort — never blocks the channel
  // post. Skipped for approval-flow posts (companionDm=false): the approval DM
  // already carries the same buttons.
  if (!companionDm) return;
  try {
    const summary = [escHtml(trimTitle(product.title)), escHtml(product.price || '')].filter(Boolean).join('\n');
    await tgSend(token, TG_ADMIN_ID, summary, {
      parse_mode: 'HTML',
      reply_markup: { inline_keyboard: [fbCaptionRow(product)] },
    });
  } catch (e) {
    console.error('FB-caption DM failed:', e.message);
  }
}

function getStoreNameFromTitleOrUrl(title, url) {
  const str = ((title || '') + ' ' + (url || '')).toLowerCase();
  if (str.includes('flipkart') || str.includes('fkrt.it') || str.includes('fktr.in')) return 'Flipkart';
  if (str.includes('myntra')) return 'Myntra';
  if (str.includes('ajio')) return 'Ajio';
  if (str.includes('meesho')) return 'Meesho';
  if (str.includes('shopsy')) return 'Shopsy';
  if (str.includes('tatacliq')) return 'TataCliq';
  if (str.includes('nykaa')) return 'Nykaa';
  if (str.includes('jiomart')) return 'JioMart';
  return 'Non-Amazon';
}

async function sendNonAmazonDealPromptToAdmin(deal, env) {
  const token = env.TELEGRAM_BOT_TOKEN;
  const adminId = env.TELEGRAM_ADMIN_ID || TG_ADMIN_ID;
  if (!token || !adminId) return;

  const storeName = getStoreNameFromTitleOrUrl(deal.title, deal.link) || 'Flipkart';
  const text = `📦 New ${storeName} Deal\n\nTitle: ${deal.title || ''}\nPrice: ${deal.price || ''}${deal.mrp ? ` (MRP: ${deal.mrp})` : ''}\nOriginal Link: ${deal.link || ''}\n${deal.image ? `Image: ${deal.image}\n` : ''}\n👉 Reply to this message with your converted EarnKaro affiliate link to publish it!`;

  if (deal.image) {
    try {
      await fetch(`https://api.telegram.org/bot${token}/sendPhoto`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: adminId, photo: deal.image, caption: text }),
      });
      return;
    } catch (e) {}
  }

  await tgSend(token, adminId, text);
}

async function handleTelegramWebhook(request, env) {
  let update;
  try { update = await request.json(); } catch { return new Response('ok'); }

  const token = env.TELEGRAM_BOT_TOKEN;
  if (!token) return new Response('ok');

  if (update.callback_query) {
    return handleApprovalCallback(update.callback_query, env);
  }

  const msg = update.message;
  if (!msg) return new Response('ok');

  const fromId = msg.from?.id;
  const adminIdStr = env.TELEGRAM_ADMIN_ID || TG_ADMIN_ID;
  if (fromId?.toString() !== adminIdStr?.toString()) {
    await tgSend(token, msg.chat.id, '⛔ Unauthorized');
    return new Response('ok');
  }

  const chatId = msg.chat.id;
  const text = msg.text || msg.caption || '';

  // ── 1. Reply to a Non-Amazon / Flipkart deal prompt ────────────────────────
  if (msg.reply_to_message) {
    const replyText = msg.reply_to_message.text || msg.reply_to_message.caption || '';
    const kvPendingKey = `pending_ml_${msg.reply_to_message.message_id}`;
    const kvPending = await env.KV.get(kvPendingKey);

    // Multi-Link EarnKaro Reply Handling
    if (kvPending || replyText.includes('Multi-Link Deal')) {
      const affiliateLinks = text.match(/https?:\/\/[^\s]+/gi) || [];
      if (!affiliateLinks.length) {
        await tgSend(token, chatId, escTg('❌ Please reply with valid converted EarnKaro link URLs.'));
        return new Response('ok');
      }

      let pending = null;
      try { pending = JSON.parse(kvPending || '{}'); } catch (e) {}

      const rawText = pending?.rawText || (msg.reply_to_message.text || msg.reply_to_message.caption || '');
      const NON_AMZ_RE = /https?:\/\/(?:[a-z0-9-]+\.)*(?:flipkart\.com|fkrt\.it|fktr\.in|myntra\.com|ajio\.com|meesho\.com|shopsy\.in|tatacliq\.com|nykaa\.com|jiomart\.com)[^\s]*/gi;
      const origLinks = pending?.originalLinks || Array.from(rawText.matchAll(NON_AMZ_RE), m => m[0]);

      let htmlText = escHtml(rawText);
      htmlText = htmlText.replace(/^.*\bjoin\b.*@\w+.*\bdeals?\b.*$/gim, '📣 Join <a href="https://t.me/dealbusterindia">Deal Buster</a> for more deals!');

      origLinks.forEach((origUrl, idx) => {
        const affUrl = affiliateLinks[idx] || affiliateLinks[affiliateLinks.length - 1];
        const btnHtml = `<a href="${escHtml(affUrl)}">👉 Check Now</a>`;
        htmlText = htmlText.split(escHtml(origUrl)).join(btnHtml);
        htmlText = htmlText.split(origUrl).join(btnHtml);
      });

      for (const ch of TG_CHANNELS) {
        if (pending?.photoId || msg.reply_to_message.photo) {
          const photoId = pending?.photoId || msg.reply_to_message.photo[msg.reply_to_message.photo.length - 1].file_id;
          await fetch(`https://api.telegram.org/bot${token}/sendPhoto`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ chat_id: ch, photo: photoId, caption: htmlText, parse_mode: 'HTML' }),
          });
        } else {
          await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ chat_id: ch, text: htmlText, parse_mode: 'HTML', disable_web_page_preview: true }),
          });
        }
      }

      await tgSend(token, chatId, escTg(`✅ Published multi-link deal to ${TG_CHANNELS.length} channels with ${affiliateLinks.length} EarnKaro links!`));
      return new Response('ok');
    }

    // Single-Link Non-Amazon EarnKaro Reply Handling
    if (replyText.includes('Reply to this message with your converted') || replyText.includes('New Flipkart Deal') || replyText.includes('New Non-Amazon Deal')) {
      const affiliateLinkM = text.match(/https?:\/\/[^\s]+/i);
      if (!affiliateLinkM) {
        await tgSend(token, chatId, escTg('❌ Please reply with a valid affiliate link URL.'));
        return new Response('ok');
      }
      const affiliateLink = affiliateLinkM[0].trim();

      const titleM = replyText.match(/Title:\s*(.+)/i);
      const priceM = replyText.match(/Price:\s*(₹[\d,]+)/i);
      const mrpM   = replyText.match(/MRP:\s*(₹[\d,]+)/i);
      const origLinkM = replyText.match(/Original Link:\s*(https?:\/\/[^\s]+)/i);
      const imageM = replyText.match(/Image:\s*(https?:\/\/[^\s]+)/i);

      const title = titleM ? titleM[1].trim() : 'Non-Amazon Deal';
      const price = priceM ? priceM[1].trim() : '';
      const mrp   = mrpM ? mrpM[1].trim() : price;
      const originalLink = origLinkM ? origLinkM[1].trim() : affiliateLink;
      let image = imageM ? imageM[1].trim() : '';

      const discNum = mrp && price ? Math.round((1 - parsePrice(price) / parsePrice(mrp)) * 100) : 0;
      const discStr = discNum > 0 ? `-${discNum}%` : '0%';

      const { products, sha } = await getProductsFile(env);

      const newProduct = {
        id: 'fk_' + Date.now(),
        asin: '',
        title: title,
        price: price,
        mrp: mrp,
        disc: discStr,
        image: image,
        link: affiliateLink,
        category: detectCategoryFromTitle(title),
        highlights: [],
        lowestPriceText: null,
        featured: false,
        hidden: false,
        outOfStock: false,
        order: 0,
        addedAt: new Date().toISOString(),
        originalPrice: price
      };

      const final = await capLiveAndBury([newProduct, ...products], env);
      await saveProductsFile(final, sha, `Add Non-Amazon deal: ${newProduct.title.slice(0, 60)}`, env);

      let sentLinks = [];
      try { sentLinks = JSON.parse(await env.KV.get('fkart_sent_tg_urls') || '[]'); } catch (e) {}
      sentLinks.push(originalLink);
      await env.KV.put('fkart_sent_tg_urls', JSON.stringify(sentLinks.slice(-500)));

      await postDealsAndTrack([newProduct], env).catch(e => console.error('TG post Non-Amazon reply failed:', e.message));

      await tgSend(token, chatId, escTg('✅ Published deal to Telegram channel and added to site!'));
      return new Response('ok');
    }
  }

  // ── 2. Check if non-Amazon link(s) sent/forwarded directly to bot ────────────
  const NON_AMZ_RE = /https?:\/\/(?:[a-z0-9-]+\.)*(?:flipkart\.com|fkrt\.it|fktr\.in|myntra\.com|ajio\.com|meesho\.com|shopsy\.in|tatacliq\.com|nykaa\.com|jiomart\.com)[^\s]*/gi;
  const nonAmzMatches = Array.from(text.matchAll(NON_AMZ_RE), m => m[0]);
  const uniqueNonAmzLinks = Array.from(new Set(nonAmzMatches));

  if (uniqueNonAmzLinks.length > 0 && !msg.reply_to_message) {
    if (uniqueNonAmzLinks.length > 1) {
      // Multi-link non-Amazon deal
      const linksListStr = uniqueNonAmzLinks.map((url, i) => `${i + 1}. ${url}`).join('\n');
      const promptMsgText = `📦 New Non-Amazon Multi-Link Deal (${uniqueNonAmzLinks.length} Links)\n\nOriginal Links:\n${linksListStr}\n\n👉 Reply to this message with your ${uniqueNonAmzLinks.length} converted EarnKaro affiliate links (one URL per line, in order) to publish it!`;

      let promptMsg;
      if (msg.photo && msg.photo.length > 0) {
        const photoId = msg.photo[msg.photo.length - 1].file_id;
        const r = await fetch(`https://api.telegram.org/bot${token}/sendPhoto`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ chat_id: chatId, photo: photoId, caption: promptMsgText }),
        });
        try { promptMsg = await r.json(); } catch (e) {}
      } else {
        const r = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ chat_id: chatId, text: promptMsgText }),
        });
        try { promptMsg = await r.json(); } catch (e) {}
      }

      const promptMsgId = promptMsg?.result?.message_id;
      if (promptMsgId) {
        await env.KV.put(`pending_ml_${promptMsgId}`, JSON.stringify({
          rawText: text,
          photoId: msg.photo ? msg.photo[msg.photo.length - 1].file_id : null,
          originalLinks: uniqueNonAmzLinks
        }), { expirationTtl: 86400 });
      }

      return new Response('ok');
    }

    // Single-link non-Amazon deal
    const rawUrl = uniqueNonAmzLinks[0];
    const storeName = getStoreNameFromTitleOrUrl(text, rawUrl);
    let title = trimTitle(text.replace(/https?:\/\/[^\s]+/g, '').trim()) || `${storeName} Special Deal`;
    let price = '';
    let mrp = '';
    const priceM = text.match(/(?:Deal Price|Price|₹)\s*:\s*₹?\s*([\d,]+)/i) || text.match(/₹\s*([\d,]+)/);
    if (priceM) price = '₹' + priceM[1].replace(/,/g, '');
    const mrpM = text.match(/(?:MRP|Original Price)\s*:\s*₹?\s*([\d,]+)/i);
    if (mrpM) mrp = '₹' + mrpM[1].replace(/,/g, '');

    await sendNonAmazonDealPromptToAdmin({ title, price, mrp, link: rawUrl }, env);
    return new Response('ok');
  }

  // Help command
  if (text.trim() === '/start' || text.trim() === '/help') {
    await tgSend(token, chatId, escTg('👋 DealBuster Bot\n\nSend me:\n• Forward any deal message with a link → I swap the link and repost\n• Non-Amazon deal → Reply with EarnKaro link to publish\n\nCommands:\n/help — this message'));
    return new Response('ok');
  }

  // Find every Amazon link in the message, however it's encoded:
  // - a bare URL sitting in the text (regex)
  // - a link hidden behind styled anchor text, e.g. "👉 Click Here 🛍️" — some
  //   source channels format links this way, and the destination URL isn't in
  //   `text`/`caption` at all then, only in the message's `entities` metadata.
  const AMZ_HOST_RE = /^(?:www\.)?(?:amazon\.in|amzn\.in|amzn\.to|amazn\.lt)$/i;
  const isAmazonUrl = u => { try { return AMZ_HOST_RE.test(new URL(u).hostname); } catch { return false; } };
  const entities = msg.entities || msg.caption_entities || [];
  let linkSpans = []; // { start, end, url } — end is exclusive
  for (const ent of entities) {
    if (ent.type === 'text_link' && ent.url && isAmazonUrl(ent.url)) {
      linkSpans.push({ start: ent.offset, end: ent.offset + ent.length, url: ent.url, isTextLink: true });
    } else if (ent.type === 'url') {
      const raw = text.slice(ent.offset, ent.offset + ent.length);
      if (isAmazonUrl(raw)) linkSpans.push({ start: ent.offset, end: ent.offset + ent.length, url: raw });
    }
  }
  // Regex fallback for bare URLs Telegram didn't tag as an entity, skipping
  // any range an entity above already covers.
  for (const m of text.matchAll(/https?:\/\/(?:(?:www\.)?amazon\.in|amzn\.in|amzn\.to|amazn\.lt)[^\s]*/gi)) {
    const start = m.index, end = start + m[0].length;
    if (!linkSpans.some(s => s.start < end && s.end > start)) linkSpans.push({ start, end, url: m[0] });
  }
  // A text_link anchor is often wrapped in decorative emoji the source channel
  // added around it, e.g. "👉 Click Here 🛍️" — only "Click Here" is the actual
  // hyperlink. Absorb an immediately-adjacent pointer/bag emoji into the span
  // so it gets removed along with the anchor text, instead of doubling up next
  // to our own "👉 Check Now" button.
  const DECOR_BEFORE = ['👉', '👆', '☝️'];
  const DECOR_AFTER = ['🛍️', '🛒', '🛍'];
  linkSpans = linkSpans.map(span => {
    if (!span.isTextLink) return span;
    let { start, end } = span;
    for (const d of DECOR_BEFORE) {
      const withSpace = d + ' ';
      if (text.slice(start - withSpace.length, start) === withSpace) { start -= withSpace.length; break; }
      if (text.slice(start - d.length, start) === d) { start -= d.length; break; }
    }
    for (const d of DECOR_AFTER) {
      const withSpace = ' ' + d;
      if (text.slice(end, end + withSpace.length) === withSpace) { end += withSpace.length; break; }
      if (text.slice(end, end + d.length) === d) { end += d.length; break; }
    }
    return { ...span, start, end };
  });
  linkSpans.sort((a, b) => a.start - b.start);

  if (!linkSpans.length) {
    await tgSend(token, chatId, escTg('❓ Send me an Amazon link or forward a deal message.'));
    return new Response('ok');
  }

  await tgSend(token, chatId, escTg('⏳ Fetching product info...'));

  try {
    const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';
    const resolveAsin = async (rawUrl) => {
      const r = await fetchWithTimeout(rawUrl, { redirect: 'follow', headers: AMZ_HEADERS });
      const finalUrl = r.url;
      const asinM = finalUrl.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i)
                 || rawUrl.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i);
      return { asinM, finalUrl, html: asinM ? await r.text() : null };
    };

    // Feature 3: forwarded message — replace link with embedded Buy Now, no preview
    const isForward = !!(msg.forward_from || msg.forward_from_chat || msg.forward_sender_name || msg.forward_date);
    if (isForward) {
      // Resolve every Amazon link independently — one bad/expired link shouldn't sink the rest.
      // Category/search links (no ASIN) still earn affiliate commission with the tag param,
      // so fall back to tagging the resolved URL directly instead of dropping the link.
      // Rebuilt by offset (not string split/join) since a hidden text_link's
      // destination URL doesn't appear in `text` at all — only its span does.
      // Each resolved link goes in as a placeholder so escHtml below can't
      // mangle it; a link that fails to resolve leaves its original display
      // text (raw URL or anchor text like "Click Here") untouched in place.
      const links = []; // { placeholder, affiliateLink }
      const pieces = [];
      let cursor = 0;
      for (const span of linkSpans) {
        try {
          const { asinM, finalUrl } = await resolveAsin(span.url);
          let affiliateLink;
          if (asinM) {
            affiliateLink = `https://www.amazon.in/dp/${asinM[1]}?tag=${TAG}`;
          } else if (finalUrl.includes('amazon.') || finalUrl.includes('amzn.')) {
            try {
              const u = new URL(finalUrl);
              u.searchParams.set('tag', TAG);
              affiliateLink = u.toString();
            } catch (e) {
              affiliateLink = buildManualCueLink(finalUrl, env);
            }
          } else {
            affiliateLink = buildManualCueLink(finalUrl, env);
          }
          const placeholder = `%%DBLINK${links.length}%%`;
          pieces.push(text.slice(cursor, span.start), placeholder);
          links.push({ placeholder, affiliateLink });
          cursor = span.end;
        } catch (e) {
          console.error('Link resolve failed for', span.url, e.message);
        }
      }
      pieces.push(text.slice(cursor));
      let newText = pieces.join('');
      const resolved = links.length;
      if (!resolved) {
        await tgSend(token, chatId, escTg('❌ Could not resolve any links in this message.'));
        return new Response('ok');
      }
      newText = newText.replace(/\n{3,}/g, '\n\n').trim();
      // Swap the source channel's own "Join @theirhandle for more deals" footer for
      // a clickable "Deal Buster" link. The anchor requires parse_mode HTML, so the
      // whole message is escaped first — swapping before escaping would mangle the
      // anchor tag itself.
      let htmlText = escHtml(newText);
      htmlText = htmlText.replace(/^.*\bjoin\b.*@\w+.*\bdeals?\b.*$/gim, '📣 Join <a href="https://t.me/dealbusterindia">Deal Buster</a> for more deals!');
      // Multi-link messages (e.g. one product per brand/size) get compact
      // "👉 Check Now" buttons instead of raw URLs — a wall of full Amazon
      // links per line is what this is fixing. A lone link still renders as a
      // button once it's long enough to wrap past ~3 lines on a phone screen;
      // short single links stay as plain text (Telegram auto-links them anyway).
      links.forEach(({ placeholder, affiliateLink }) => {
        const useButton = resolved > 1 || affiliateLink.length > 60;
        const rendered = useButton
          ? `<a href="${escHtml(affiliateLink)}">👉 Check Now</a>`
          : escHtml(affiliateLink);
        htmlText = htmlText.split(placeholder).join(rendered);
      });
      for (const ch of TG_CHANNELS) {
        if (msg.photo) {
          const photoId = msg.photo[msg.photo.length - 1].file_id;
          await fetch(`https://api.telegram.org/bot${token}/sendPhoto`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ chat_id: ch, photo: photoId, caption: htmlText, parse_mode: 'HTML' }),
          });
        } else {
          await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ chat_id: ch, text: htmlText, parse_mode: 'HTML', disable_web_page_preview: true }),
          });
        }
      }
      const skipped = linkSpans.length - resolved;
      const suffix = skipped > 0 ? ` (${skipped} link${skipped > 1 ? 's' : ''} skipped)` : '';
      await tgSend(token, chatId, escTg(`✅ Reposted to ${TG_CHANNELS.length} channels with ${resolved} affiliate link${resolved > 1 ? 's' : ''}!${suffix}`));
      return new Response('ok');
    }

    // Direct-link publish removed — the bot only reposts forwarded deal messages now.
    await tgSend(token, chatId, escTg('❌ Direct link publishing is disabled. Forward a deal message instead.'));
    return new Response('ok');

  } catch (e) {
    await tgSend(token, chatId, escTg(`❌ Error: ${e.message}`));
  }

  return new Response('ok');
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    // ── Public: live products feed (no auth) ──────────────────────────────────
    const url0 = new URL(request.url);
    if (url0.pathname === '/public/products.json' && request.method === 'GET') {
      try {
        const { products } = await getProductsFile(env);
        const visible = products.filter(p => !p.hidden);
        return new Response(JSON.stringify(visible), {
          headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), { status: 502, headers: { ...CORS, 'Content-Type': 'application/json' } });
      }
    }

    // ── Telegram webhook (public — Telegram doesn't send admin password) ────────
    if (url0.pathname === '/telegram-webhook' && request.method === 'POST') {
      return handleTelegramWebhook(request, env);
    }

    // ── External cron ping ───
    if (url0.pathname === '/cron-post-deals' && request.method === 'GET') {
      if (!env.CRON_SECRET) return json({ error: 'Unauthorized', reason: 'secret_not_set' }, 401);
      if (url0.searchParams.get('key') !== env.CRON_SECRET) return json({ error: 'Unauthorized', reason: 'key_mismatch' }, 401);
      try {
        await Promise.all([
          postNewDealsToTelegramLocked(env),
          cronSyncAndPublishNonAmazonDeals(env)
        ]);
        return json({ ok: true });
      } catch (e) {
        return json({ error: e.message }, 500);
      }
    }

    const password = request.headers.get('X-Admin-Password');
    if (password !== env.ADMIN_PASSWORD) return json({ error: 'Unauthorized' }, 401);

    const url = new URL(request.url);

    try {
      if (url.pathname === '/ping' && request.method === 'GET') return json({ ok: true });

      // ── POST /setup-telegram-webhook ─────────────────────────────────────────
      if (url.pathname === '/setup-telegram-webhook' && request.method === 'POST') {
        const token = env.TELEGRAM_BOT_TOKEN;
        if (!token) return json({ error: 'TELEGRAM_BOT_TOKEN not set' }, 500);
        const workerUrl = `${url.origin}/telegram-webhook`;
        const r = await fetch(`https://api.telegram.org/bot${token}/setWebhook`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url: workerUrl, allowed_updates: ['message', 'callback_query'] }),
        });
        const data = await r.json();
        return json({ success: data.ok, webhook_url: workerUrl, telegram_response: data });
      }

      // ── /fetchtitle ──────────────────────────────────────────────────────────
      if (url.pathname === '/fetchtitle' && request.method === 'GET') {
        let asin = url.searchParams.get('asin');
        const shortUrl = url.searchParams.get('url');
        if (!asin && !shortUrl) return json({ error: 'Missing asin or url' }, 400);
        try {
          let html = '';
          let finalUrl = shortUrl || (asin ? `https://www.amazon.in/dp/${asin}` : '');
          if (shortUrl) {
            try {
              const redir = await fetchWithTimeout(shortUrl, { redirect: 'follow', headers: AMZ_HEADERS });
              finalUrl = redir.url;
              const asinM = finalUrl.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i);
              if (asinM) { asin = asinM[1]; html = await redir.text(); }
            } catch (e) {
              // Redirect follow failed, treat the link as is
            }
          }

          const isAmazon = finalUrl.includes('amazon.in') || finalUrl.includes('amzn.to') || finalUrl.includes('amazon.com') || (asin && !shortUrl);

          if (!isAmazon) {
            // Fetch via proxy (since Flipkart/Myntra/Ajio block standard CF fetch requests)
            const resp = await fetchWithProxy(finalUrl, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' } }, 15000, env);
            if (!resp.ok) {
              return json({ error: `Proxy fetch failed for external link (HTTP ${resp.status})` }, 502);
            }
            html = await resp.text();
            
            let title = '';
            let price = null;
            let mrp = null;
            let image = '';
            let category = '';

            // Parse structured JSON-LD data
            const regex = /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
            let match;
            while ((match = regex.exec(html)) !== null) {
              try {
                const data = JSON.parse(match[1].trim());
                const dataObj = Array.isArray(data) ? data.find(o => o['@type'] === 'Product' || o['@type']?.includes('Product')) : data;
                
                if (dataObj && (dataObj['@type'] === 'Product' || dataObj['@type']?.includes('Product'))) {
                  if (dataObj.name) title = dataObj.name.trim();
                  if (dataObj.image) {
                    image = Array.isArray(dataObj.image) ? dataObj.image[0] : dataObj.image;
                    if (typeof image === 'object' && image.url) image = image.url;
                  }
                  const offers = dataObj.offers;
                  if (offers) {
                    const offersObj = Array.isArray(offers) ? offers[0] : offers;
                    price = offersObj.price || offersObj.lowPrice;
                    mrp = offersObj.highPrice || offersObj.priceSpecification?.price || price;
                  }
                  if (dataObj.category) {
                    category = typeof dataObj.category === 'string' ? dataObj.category : dataObj.category.name || '';
                  }
                }
              } catch (e) {
                // ignore json parse errors
              }
            }

            // Fallback parsing if JSON-LD is missing or incomplete
            if (!title) {
              const tM = html.match(/<title>([^|<]+)/i);
              if (tM) title = tM[1].trim();
            }
            title = title.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&apos;/g,"'").split('|')[0].trim();
            if (title.length > 70) title = title.slice(0, 70).replace(/\s+\S*$/, '').trim();
            
            if (category) {
              const catLower = category.toLowerCase();
              if (/electronic|mobile|phone|laptop|computer|camera|headphone|speaker|tv|tablet|watch|smart/.test(catLower)) category = 'Electronics';
              else if (/cloth|fashion|shoe|shirt|dress|jeans|apparel|wear|bag|wallet/.test(catLower)) category = 'Fashion';
              else if (/kitchen|home|furniture|decor|bed|bath|garden|tool|appliance/.test(catLower)) category = 'Home';
              else if (/beauty|skin|hair|makeup|cosmetic|perfume|grooming|face|lip/.test(catLower)) category = 'Beauty';
              else if (/health|medicine|supplement|vitamin|protein|fitness|sport|yoga|gym|ayurved|toothpaste|oral/.test(catLower)) category = 'Health';
              else category = '';
            }
            if (!category && title) {
              const tLower = title.toLowerCase();
              if (/electronic|mobile|phone|laptop|computer|camera|headphone|speaker|tv|tablet|watch|smart/.test(tLower)) category = 'Electronics';
              else if (/cloth|fashion|shoe|shirt|dress|jeans|apparel|wear|bag|wallet/.test(tLower)) category = 'Fashion';
              else if (/kitchen|home|furniture|decor|bed|bath|garden|tool|appliance/.test(tLower)) category = 'Home';
              else if (/beauty|skin|hair|makeup|cosmetic|perfume|grooming|face|lip/.test(tLower)) category = 'Beauty';
              else if (/health|medicine|supplement|vitamin|protein|fitness|sport|yoga|gym|ayurved|toothpaste|oral/.test(tLower)) category = 'Health';
            }

            // Extract rating and reviewCount from non-Amazon page HTML
            let rating = null;
            let reviewCount = null;
            const schemaRegex2 = /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
            let match2;
            while ((match2 = schemaRegex2.exec(html)) !== null) {
              try {
                const data2 = JSON.parse(match2[1].trim());
                const items2 = Array.isArray(data2) ? data2 : [data2];
                for (const item of items2) {
                  if (item.aggregateRating) {
                    rating = parseFloat(item.aggregateRating.ratingValue);
                    reviewCount = parseInt(item.aggregateRating.reviewCount || item.aggregateRating.ratingCount, 10);
                    break;
                  }
                }
              } catch (e) {}
            }
            if (!rating) {
              const rM = html.match(/"ratingValue"\s*:\s*"?(\d(?:\.\d)?)"?/i) || html.match(/(\d\.\d)\s*★/i) || html.match(/class="[^"]*(?:_3LWZlK|XqP1W8)[^"]*"[^>]*>(\d\.\d)/i);
              if (rM) rating = parseFloat(rM[1]);
            }
            if (!reviewCount) {
              const rvM = html.match(/"ratingCount"\s*:\s*"?([\d,]+)"?/i) || html.match(/based on ([\d,]+) ratings/i);
              if (rvM) reviewCount = parseInt(rvM[1].replace(/,/g, ''), 10);
            }

            if (rating != null && rating < 3.6) {
              return json({ error: `Product rating is too low (${rating} stars, minimum requirement is 3.6 stars)` }, 400);
            }

            const parsedPrice = price ? parsePrice(price.toString()) : null;
            const parsedMrp = mrp ? parsePrice(mrp.toString()) : null;

            // Affiliate link generation via Cuelinks (fallback to 268568 if no publisher ID set)
            const pubId = env.CUELINKS_PUB_ID || '268568';
            const affiliateUrl = `https://linksredirect.com/?pub_id=${pubId}&subid=dealbuster&url=${encodeURIComponent(finalUrl)}`;

            return json({
              title,
              price: parsedPrice,
              mrp: parsedMrp,
              image,
              category,
              link: affiliateUrl,
              asin: "",
              rating,
              reviewCount
            });
          }

          const isCaptcha = html && (html.includes('captcha') || html.includes('Robot Check'));
          const hasTitle = html && (html.includes('id="productTitle"') || html.includes('<title>'));
          if ((!html || isCaptcha || !hasTitle) && asin) {
            const r = await fetchWithTimeout(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
            html = await r.text();
          }
          let title = '';
          const m = html.match(/id="productTitle"[^>]*>\s*([\s\S]*?)\s*<\/span>/);
          if (m) title = m[1].replace(/\s+/g,' ').trim();
          else { const t = html.match(/<title>([^|<]+)/); if (t) title = t[1].trim(); }
          title = title.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&apos;/g,"'").split('|')[0].trim();
          if (title.length > 70) title = title.slice(0,70).replace(/\s+\S*$/,'').trim();

          function extractOffscreen(scope) {
            const re = /<span[^>]*class="a-offscreen"[^>]*>(₹\s*[\d,]+\.?\d*)<\/span>/gi;
            let m2;
            while ((m2 = re.exec(scope)) !== null) {
              const val = parsePrice(m2[1]);
              const after = scope.slice(re.lastIndex, re.lastIndex + 80);
              if (/\/\s*\d/.test(after) || /\/\s*(?:ml|g|kg|count|item|unit|ltr)/i.test(after) || after.includes('priceperunit')) continue;
              return val;
            }
            return null;
          }

          const priceSectionM = html.match(/id="corePriceDisplay_desktop_feature_div"([\s\S]{0,6000})/);
          const apexSectionM  = html.match(/id="apex_desktop_newAccordionRow"([\s\S]{0,6000})/);
          const priceSection  = (priceSectionM?.[1]||'') + (apexSectionM?.[1]||'');
          let price = null, mrp = null;
          if (priceSection) { const wM = priceSection.match(/class="[^"]*a-price-whole[^"]*"[^>]*>([\d,]+)/i); if(wM) price = parsePrice(wM[1]); }
          if (!price) { const wM = html.match(/class="[^"]*a-price-whole[^"]*"[^>]*>([\d,]+)/i); if(wM) price = parsePrice(wM[1]); }
          const reSpan = /<span[^>]*class="([^"]*a-price[^"]*)"[^>]*>\s*<span[^>]*class="a-offscreen"[^>]*>(₹\s*[\d,]+\.?\d*)<\/span>/gi;
          let pM2;
          const scope = priceSection || html;
          while ((pM2 = reSpan.exec(scope)) !== null) {
            const classes = pM2[1], val = parsePrice(pM2[2]);
            if (val) {
              const after = scope.slice(reSpan.lastIndex, reSpan.lastIndex+80);
              if (/\/\s*\d/.test(after)||/\/\s*(?:ml|g|kg|count|item|unit|ltr)/i.test(after)||after.includes('priceperunit')||classes.includes('priceperunit')) continue;
              if (classes.includes('a-text-price')) { if(!mrp) mrp = val; } else { if(!price) price = val; }
            }
          }
          if (!price) { for (const re of [/priceToPay[\s\S]{0,400}?<span[^>]*class="a-offscreen"[^>]*>(₹\s*[\d,]+\.?\d*)<\/span>/i,/id="priceblock_ourprice"[^>]*>(₹\s*[\d,]+\.?\d*)/i,/"priceAmount"\s*:\s*([\d.]+)/i]) { const mm = scope.match(re); if(mm){price=parsePrice(mm[1]);if(price)break;} } }
          if (!price && priceSection) price = extractOffscreen(priceSection);
          if (!mrp) { const mm = scope.match(/M\.R\.P\.?[^₹\n]{0,30}₹\s*([\d,]+\.?\d*)/i); if(mm) mrp=parsePrice(mm[1]); }
          if (!mrp) { const mm = html.match(/class="[^"]*a-text-price[^"]*"[^>]*>[\s\S]{0,300}?₹\s*([\d,]+\.?\d*)/i); if(mm) mrp=parsePrice(mm[1]); }
          if (!mrp) { for (const mm of (priceSection||html).matchAll(/<span[^>]*class="[^"]*a-text-price[^"]*"[^>]*>([\s\S]{0,300}?)<\/span>\s*<\/span>/g)) { const inner=mm[1]; if(inner.includes('priceperunit'))continue; const v=parsePrice(inner.match(/₹\s*([\d,]+\.?\d*)/)?.[1]); if(v){mrp=v;break;} } }
          if (price && !mrp) mrp = price;

          const highlights = [];
          function extractBullets(sc) {
            for (const mm of sc.matchAll(/class="a-list-item"[^>]*>([\s\S]*?)<\/span>/g)) {
              const t2 = mm[1].replace(/<[^>]+>/g,'').replace(/\s+/g,' ').trim().replace(/&amp;/g,'&').replace(/&#39;/g,"'");
              if (t2.length>20 && t2.split(/\s+/).length>=3 && t2.length<300 && !t2.toLowerCase().startsWith('make sure') && !t2.toLowerCase().startsWith('click') && !/^[\s\W]+$/.test(t2)) { highlights.push(t2); }
              if (highlights.length>=5) break;
            }
          }
          const fbM = html.match(/id="feature-bullets"([\s\S]{0,6000})/); if(fbM) extractBullets(fbM[1]);
          if (!highlights.length) { const abM = html.match(/id="apex_desktop_feature_bullets[\w-]*"([\s\S]{0,6000})/); if(abM) extractBullets(abM[1]); }
          if (!highlights.length) { const ovM = html.match(/id="productOverview_feature_div"([\s\S]{0,4000})/); if(ovM) { for(const mm of ovM[1].matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)){const cells=[...mm[1].matchAll(/<(?:td|th)[^>]*>([\s\S]*?)<\/(?:td|th)>/g)].map(c=>c[1].replace(/<[^>]+>/g,'').replace(/\s+/g,' ').trim()).filter(Boolean);if(cells.length>=2){highlights.push(`${cells[0]}: ${cells[1]}`);if(highlights.length>=5)break;}} } }

          let category = '';
          const bcM = html.match(/id="wayfinding-breadcrumbs_feature_div"([\s\S]{0,2000})/);
          const bc = bcM ? bcM[1].replace(/<[^>]+>/g,'').replace(/\s+/g,' ').toLowerCase() : title.toLowerCase();
          if (/electronic|mobile|phone|laptop|computer|camera|headphone|speaker|tv|tablet|watch|smart/.test(bc)) category='Electronics';
          else if (/cloth|fashion|shoe|shirt|dress|jeans|apparel|wear|bag|wallet/.test(bc)) category='Fashion';
          else if (/kitchen|home|furniture|decor|bed|bath|garden|tool|appliance/.test(bc)) category='Home';
          else if (/beauty|skin|hair|makeup|cosmetic|perfume|grooming|face|lip/.test(bc)) category='Beauty';
          else if (/health|medicine|supplement|vitamin|protein|fitness|sport|yoga|gym|ayurved|toothpaste|oral/.test(bc)) category='Health';

          let image = '';
          const imgTagM = html.match(/<img[^>]*id="(?:landingImage|imgBlkFront)"[^>]*>/i);
          if (imgTagM) {
            const tag = imgTagM[0];
            const dynM = tag.match(/data-a-dynamic-image="([^"]+)"/i); if(dynM){const urlM=dynM[1].match(/(https?:\/\/[^&"']+\.(?:jpg|png|jpeg|gif))/i);if(urlM)image=urlM[1];}
            if(!image){const hM=tag.match(/data-old-hires="([^"]+)"/i);if(hM)image=hM[1];}
            if(!image){const sM=tag.match(/src="([^"]+)"/i);if(sM&&!sM[1].includes('transparent-pixel')&&!sM[1].startsWith('data:'))image=sM[1];}
          }
          if(!image){const hM=html.match(/"hiRes"\s*:\s*"([^"]+)"/i);if(hM)image=hM[1];}
          if(!image){const lM=html.match(/"large"\s*:\s*"([^"]+)"/i);if(lM)image=lM[1];}
          if(image) image=image.replace(/&amp;/g,'&').replace(/&#39;/g,"'").replace(/&quot;/g,'"');

          const lowestPriceM = html.match(/(Lowest\s+price\s+(?:in\s+\d+\s+days|ever))/i);
          const lowestPriceText = lowestPriceM ? lowestPriceM[1].trim() : null;

          if (title) return json({ title, price, mrp, highlights, category, asin, image, lowestPriceText });
          return json({ error: 'Title not found' }, 404);
        } catch (e) { return json({ error: e.message }, 502); }
      }


      // ── /search ──────────────────────────────────────────────────────────────
      if (url.pathname === '/search' && request.method === 'GET') {
        const q = url.searchParams.get('q'); if (!q) return json({ error: 'Missing q' }, 400);
        return await handleSearch(q, env);
      }

      // ── /publish ─────────────────────────────────────────────────────────────
      if (url.pathname === '/publish' && request.method === 'POST') return await handlePublish(await request.json(), env);

      // ── POST /post-to-telegram (per-product button in the dashboard menu) ─────
      // An explicit admin tap is its own approval, so like the bot's Approve
      // button this goes straight to sendToChannels — still serialized and
      // deduped by the TgPoster DO. posted=0 means the DO skipped it as already
      // posted; the dashboard then offers a force re-post.
      if (url.pathname === '/post-to-telegram' && request.method === 'POST') {
        const { id, force } = await request.json();
        if (!id) return json({ error: 'Missing id' }, 400);
        const { products } = await getProductsFile(env);
        const product = products.find(p => p.id === id);
        if (!product) return json({ error: 'Product not found' }, 404);
        if (isZeroPrice(product)) return json({ error: 'Product has no price — refusing to post' }, 400);
        const posted = await sendToChannels([product], env, { force: !!force });
        return json({ success: true, posted, alreadyPosted: posted === 0 });
      }

      // ── /upload ──────────────────────────────────────────────────────────────
      if (url.pathname === '/upload' && request.method === 'POST') return await handleUpload(await request.json(), env);

      // ── /delete (image) ──────────────────────────────────────────────────────
      if (url.pathname === '/delete' && request.method === 'POST') {
        const { path } = await request.json(); if (!path) return json({ error: 'Missing path' }, 400);
        const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/${path}`;
        const ghHdrs = ghHeaders(env);
        const getR = await fetch(apiUrl, { headers: ghHdrs }); if (!getR.ok) return json({ error: 'File not found' }, 404);
        const { sha } = await getR.json();
        const delR = await fetch(apiUrl, { method: 'DELETE', headers: { ...ghHdrs, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: `Delete image: ${path}`, sha }) });
        if (!delR.ok) { const err = await delR.json().catch(()=>({})); return json({ error: err.message||'Delete failed' }, 502); }
        return json({ success: true });
      }

      // ── /fixencoding ─────────────────────────────────────────────────────────
      if (url.pathname === '/fixencoding' && request.method === 'POST') {
        function repairOnce(str) {
          const parts = []; let byteRun = [];
          for (let i = 0; i <= str.length; i++) {
            const code = i < str.length ? str.charCodeAt(i) : -1;
            if (code >= 0 && code <= 0xFF) { byteRun.push(code); } else {
              if (byteRun.length > 0) { try { parts.push(new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(byteRun))); } catch { parts.push(String.fromCharCode(...byteRun)); } byteRun = []; }
              if (code > 0xFF) parts.push(str[i]);
            }
          }
          return parts.join('');
        }
        const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/index.html`;
        const ghHdrs = ghHeaders(env);
        const getR = await fetch(apiUrl, { headers: ghHdrs }); if (!getR.ok) return json({ error: 'Could not fetch index.html' }, 502);
        const file = await getR.json();
        const raw = atob(file.content.replace(/\n/g,'')); const uint8 = new Uint8Array(raw.length); for(let i=0;i<raw.length;i++)uint8[i]=raw.charCodeAt(i);
        let content = new TextDecoder('utf-8').decode(uint8);
        for (let pass = 0; pass < 5; pass++) { const fixed = repairOnce(content); if (fixed === content) break; content = fixed; }
        const putR = await fetch(apiUrl, { method: 'PUT', headers: { ...ghHdrs, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: 'Fix UTF-8 encoding', content: encodeBase64Unicode(content), sha: file.sha }) });
        if (!putR.ok) { const err = await putR.json().catch(()=>({})); return json({ error: 'GitHub write failed', details: err.message }, 502); }
        return json({ success: true });
      }

      // ── /migrate ─────────────────────────────────────────────────────────────
      if (url.pathname === '/migrate' && request.method === 'POST') {
        const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/index.html`;
        const getR = await fetch(apiUrl, { headers: ghHeaders(env) }); if (!getR.ok) return json({ error: 'Could not fetch index.html' }, 502);
        const file = await getR.json(); const raw = atob(file.content.replace(/\n/g,'')); const bytes = new Uint8Array(raw.length); for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
        const html = new TextDecoder('utf-8').decode(bytes);
        const safeDecode = s => { try { return decodeURIComponent((s||'').replace(/\+/g,' ')); } catch { return s||''; } };
        const cardRe = /<a class="product-card" data-cat="([^"]*)" href="product\.html\?([^"]+)"/g;
        const { products: existing, sha } = await getProductsFile(env);
        const existingAsinSet = new Set(existing.map(p=>p.asin).filter(Boolean));
        const imported = []; let m2; let order = existing.length;
        while ((m2 = cardRe.exec(html)) !== null) {
          const cat = m2[1]; let params; try { params = new URLSearchParams(m2[2].replace(/&amp;/g,'&')); } catch { continue; }
          const link = safeDecode(params.get('link')||''); const asinM = link.match(/\/dp\/([A-Z0-9]{10})/i); const asin = asinM ? asinM[1] : null;
          if (asin && existingAsinSet.has(asin)) continue; if (asin) existingAsinSet.add(asin);
          imported.push({ id:`${Date.now()}${imported.length}`, asin:asin||'', title:safeDecode(params.get('title')||''), price:params.get('price')||'', mrp:params.get('mrp')||'', disc:params.get('disc')||'0%', image:safeDecode(params.get('img')||''), link, category:cat.charAt(0).toUpperCase()+cat.slice(1), highlights:params.get('hl')?safeDecode(params.get('hl')).split('|').filter(Boolean):[], featured:false, hidden:false, outOfStock:false, order:order++, addedAt:params.get('updated')||new Date().toISOString().slice(0,10) });
        }
        if (!imported.length) return json({ success: true, imported: 0, message: 'No new cards found' });
        const merged = [...existing, ...imported].map((p,i)=>({...p,order:i}));
        await saveProductsFile(merged, sha, `Migrate ${imported.length} cards from index.html`, env);
        return json({ success: true, imported: imported.length });
      }

      // ── /debug ───────────────────────────────────────────────────────────────
      if (url.pathname === '/debug' && request.method === 'GET') return await handleDebug(env);

      // ── /testgithub ──────────────────────────────────────────────────────────
      if (url.pathname === '/testgithub' && request.method === 'GET') {
        const ghHdrs = ghHeaders(env);
        const whoami = await fetch('https://api.github.com/user',{headers:ghHdrs}); const whoamiText = await whoami.text();
        const testPath = `images/test-${Date.now()}.txt`;
        const testR = await fetch(`https://api.github.com/repos/akshayjango/dealbuster/contents/${testPath}`,{method:'PUT',headers:{...ghHdrs,'Content-Type':'application/json'},body:JSON.stringify({message:'test upload',content:btoa('hi')})});
        return json({ tokenStatus:whoami.status, tokenUser:(()=>{try{return JSON.parse(whoamiText).login;}catch{return whoamiText.slice(0,100);}})(), testUploadStatus:testR.status });
      }

      // ── /sync-dealsradar ─────────────────────────────────────────────────────
      if (url.pathname === '/sync-dealsradar' && request.method === 'GET') {
        try { return json(await scrapeAndSyncDealsSpy(env, 40)); } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /telegram-post-now ───────────────────────────────────────────────────
      if (url.pathname === '/telegram-post-now' && request.method === 'POST') {
        try {
          await env.KV.delete('tg_last_posted_at');
          await postNewDealsToTelegram(env);
          const lastPostedAt = await env.KV.get('tg_last_posted_at');
          return json({ success: true, posted: lastPostedAt ? 5 : 0 });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /sync-indiafreestuff ─────────────────────────────────────────────────
      if (url.pathname === '/sync-indiafreestuff' && request.method === 'GET') {
        try {
          const r = await scrapeAndSyncIndiaFreeStuff(env, 30);
          if (r.addedProducts?.length) {
            await postDealsAndTrack(r.addedProducts.slice(0, 5), env).catch(e => console.error('TG post IFS manual:', e.message));
          }
          return json(r);
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /sync-non-amazon (manual test trigger, bypasses quiet hours) ──────────
      if (url.pathname === '/sync-non-amazon' && request.method === 'GET') {
        try {
          await cronSyncAndPublishNonAmazonDeals(env, true);
          return json({ success: true, message: 'Non-Amazon sync executed.' });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /test-cuelink (debug: isolate convertToCueLink from scraping/dedup noise) ──
      if (url.pathname === '/test-cuelink' && request.method === 'GET') {
        const testUrl = url.searchParams.get('url');
        const testTitle = url.searchParams.get('title') || 'Test Product Title';
        const testDescription = url.searchParams.get('description') || null;
        const testChannelId = url.searchParams.get('channel_id') || null;
        if (!testUrl) return json({ error: 'pass ?url=<merchant url to test>&title=<optional title>&description=<optional>&channel_id=<optional>' }, 400);
        try {
          const result = await convertToCueLink(testUrl, testTitle, env, testDescription, testChannelId);
          return json({ input: testUrl, inputTitle: testTitle, inputDescription: testDescription, inputChannelId: testChannelId, ...result, keyConfigured: !!(env.CUELINKS_API_KEY || '').trim() });
        } catch (e) {
          return json({ error: e.message }, 502);
        }
      }

      // ── /cuelink-ping (debug: confirm which CueLinks account this API key belongs to) ──
      if (url.pathname === '/cuelink-ping' && request.method === 'GET') {
        const apiKey = (env.CUELINKS_API_KEY || '').trim();
        if (!apiKey) return json({ error: 'CUELINKS_API_KEY not configured' }, 400);
        try {
          const res = await fetchWithTimeout(
            'https://developers.cuelinks.com/pub_api/v3/ping',
            { headers: { 'Authorization': `Token ${apiKey}` } },
            10000
          );
          const body = await res.json().catch(() => ({}));
          return json({ status: res.status, body });
        } catch (e) {
          return json({ error: e.message }, 502);
        }
      }

      // ── /cuelink-campaigns (debug: check a campaign's access_status, e.g. Flipkart) ──
      if (url.pathname === '/cuelink-campaigns' && request.method === 'GET') {
        const apiKey = (env.CUELINKS_API_KEY || '').trim();
        if (!apiKey) return json({ error: 'CUELINKS_API_KEY not configured' }, 400);
        const q = url.searchParams.get('q') || '';
        try {
          const res = await fetchWithTimeout(
            `https://developers.cuelinks.com/pub_api/v3/campaigns?q=${encodeURIComponent(q)}`,
            { headers: { 'Authorization': `Token ${apiKey}` } },
            10000
          );
          const body = await res.json().catch(() => ({}));
          return json({ status: res.status, body });
        } catch (e) {
          return json({ error: e.message }, 502);
        }
      }

      // ── /cuelink-offers (debug: browse live coupons/deals via CueLinks' own feed) ──
      if (url.pathname === '/cuelink-offers' && request.method === 'GET') {
        const apiKey = (env.CUELINKS_API_KEY || '').trim();
        if (!apiKey) return json({ error: 'CUELINKS_API_KEY not configured' }, 400);
        const q = url.searchParams.get('q') || '';
        const campaignId = url.searchParams.get('campaign_id') || '';
        const perPage = url.searchParams.get('per_page') || '10';
        const page = url.searchParams.get('page') || '1';
        try {
          const params = new URLSearchParams({ per_page: perPage, page });
          if (q) params.set('q', q);
          if (campaignId) params.set('campaign_id', campaignId);
          const res = await fetchWithTimeout(
            `https://developers.cuelinks.com/pub_api/v3/offers?${params.toString()}`,
            { headers: { 'Authorization': `Token ${apiKey}` } },
            10000
          );
          const body = await res.json().catch(() => ({}));
          return json({ status: res.status, body });
        } catch (e) {
          return json({ error: e.message }, 502);
        }
      }

      // ── /request-cuelink-access (debug: apply for a private campaign, e.g. Flipkart id 1) ──
      if (url.pathname === '/request-cuelink-access' && request.method === 'POST') {
        const apiKey = (env.CUELINKS_API_KEY || '').trim();
        if (!apiKey) return json({ error: 'CUELINKS_API_KEY not configured' }, 400);
        const campaignId = url.searchParams.get('id');
        if (!campaignId) return json({ error: 'pass ?id=<campaign id>' }, 400);
        try {
          const res = await fetchWithTimeout(
            `https://developers.cuelinks.com/pub_api/v3/campaigns/${encodeURIComponent(campaignId)}/request_access`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Token ${apiKey}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                promotion_details: 'Dealbuster (dealbuster.in) — deal-aggregator site + Telegram channel (@dealbusterindia), publishing daily deals to an active subscriber base.',
              }),
            },
            10000
          );
          const body = await res.json().catch(() => ({}));
          return json({ status: res.status, body });
        } catch (e) {
          return json({ error: e.message }, 502);
        }
      }

      // ── /sync-dotd ───────────────────────────────────────────────────────────
      if (url.pathname === '/sync-dotd' && request.method === 'GET') {
        try {
          const r = await scrapeAndSyncDealOfTheDayIndia(env, 10);
          if (r.addedProducts?.length) {
            await postDealsAndTrack(r.addedProducts.slice(0, 5), env).catch(e => console.error('TG post DOTD manual:', e.message));
          }
          return json(r);
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /sync-all ────────────────────────────────────────────────────────────
      if (url.pathname === '/sync-all' && request.method === 'GET') {
        const results = await Promise.allSettled([
          scrapeAndSyncDealsSpy(env, 40),
          scrapeAndSyncIndiaFreeStuff(env, 30),
          scrapeAndSyncDealOfTheDayIndia(env, 10)
        ]);
        return json({
          success: true,
          results: results.map((r,i) => ({
            site: ['DealsRadar','IndiaFreeStuff','DealOfTheDayIndia'][i],
            status: r.status,
            result: r.status==='fulfilled'?r.value:{error:r.reason.message}
          }))
        });
      }

      // ── /clean-deals ─────────────────────────────────────────────────────────
      if (url.pathname === '/clean-deals' && request.method === 'GET') {
        try { return json(await checkAndCleanDeals(env)); } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /repair-nan-prices ────────────────────────────────────────────────────
      if (url.pathname === '/repair-nan-prices' && request.method === 'GET') {
        try {
          const { products, sha } = await getProductsFile(env);
          const nanProducts = products.filter(p => p.asin && (String(p.price).includes('NaN') || String(p.mrp).includes('NaN')));
          if (!nanProducts.length) return json({ success: true, fixed: 0, message: 'No NaN prices found.' });

          const productMap = new Map(products.map(p => [p.id, { ...p }]));
          let fixed = 0;

          for (const p of nanProducts) {
            try {
              const r = await fetchWithTimeout(`https://www.amazon.in/dp/${p.asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
              if (!r.ok) continue;
              const html = await r.text();

              // Extract price using corePriceDisplay section first, then full page
              const priceSectionM = html.match(/id="corePriceDisplay_desktop_feature_div"([\s\S]{0,6000})/);
              const apexSectionM  = html.match(/id="apex_desktop_newAccordionRow"([\s\S]{0,6000})/);
              const priceSection  = (priceSectionM?.[1] || '') + (apexSectionM?.[1] || '');
              let price = null;
              if (priceSection) { const wM = priceSection.match(/class="[^"]*a-price-whole[^"]*"[^>]*>([\d,]+)/i); if (wM) price = parsePrice(wM[1]); }
              if (!price) { const wM = html.match(/class="[^"]*a-price-whole[^"]*"[^>]*>([\d,]+)/i); if (wM) price = parsePrice(wM[1]); }
              if (!price || price <= 0) continue;

              // Extract MRP (strikethrough price)
              let mrp = price;
              const mrpM = html.match(/class="[^"]*a-text-price[^"]*"[^>]*>\s*<span[^>]*class="a-offscreen"[^>]*>₹\s*([\d,]+)/i);
              if (mrpM) { const m = parsePrice(mrpM[1]); if (m && m > price) mrp = m; }

              const disc = mrp > price ? Math.round((1 - price / mrp) * 100) : 0;
              const updated = productMap.get(p.id);
              updated.price = '₹' + price.toLocaleString('en-IN');
              updated.mrp   = '₹' + mrp.toLocaleString('en-IN');
              updated.disc  = disc > 0 ? `-${disc}%` : '0%';
              fixed++;
            } catch { continue; }
          }

          if (!fixed) return json({ success: true, fixed: 0, message: 'Could not fetch prices for NaN products.' });
          const reordered = [...productMap.values()].sort((a, b) => (a.order || 0) - (b.order || 0));
          await saveProductsFile(reordered, sha, `Repair ${fixed} NaN prices`, env);
          return json({ success: true, fixed, message: `Repaired ${fixed} of ${nanProducts.length} NaN-priced products.` });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /check-badges ─────────────────────────────────────────────────────────
      if (url.pathname === '/check-badges' && request.method === 'GET') {
        try { return json(await checkLowestPriceBadges(env)); } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /sync-amazon-deals ────────────────────────────────────────────────────
      if (url.pathname === '/sync-amazon-deals' && request.method === 'GET') {
        try { return json(await syncAmazonDealsToProducts(env, 24)); } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /check-amazon-deals ───────────────────────────────────────────────────
      if (url.pathname === '/check-amazon-deals' && request.method === 'GET') {
        try { return json(await checkAmazonDeals(env)); } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── GET /amazon-deals-alerts ──────────────────────────────────────────────
      if (url.pathname === '/amazon-deals-alerts' && request.method === 'GET') {
        const alerts = env.KV ? await env.KV.get('amazonDealsAlerts', 'json') || [] : [];
        return json({ alerts });
      }

      // ── DELETE /amazon-deals-alerts (clear all) ────────────────────────────────
      if (url.pathname === '/amazon-deals-alerts' && request.method === 'DELETE') {
        if (env.KV) await env.KV.put('amazonDealsAlerts', JSON.stringify([]));
        return json({ success: true });
      }

      // ── DELETE /amazon-deals-alerts/:id (dismiss one) ─────────────────────────
      const amzAlertMatch = url.pathname.match(/^\/amazon-deals-alerts\/([^/]+)$/);
      if (amzAlertMatch && request.method === 'DELETE') {
        if (env.KV) {
          const alerts = await env.KV.get('amazonDealsAlerts', 'json') || [];
          await env.KV.put('amazonDealsAlerts', JSON.stringify(alerts.filter(a => a.id !== amzAlertMatch[1])));
        }
        return json({ success: true });
      }

      // ── POST /tg-posted (which of these ids/asins reached the TG channel) ────
      // Checks the TgPoster DO ledger — the authoritative record of what was
      // actually SENT to the channel. The KV tg_posted_ids mirror is wrong for
      // this: queueForApproval claims every deal there when it's queued to the
      // approval bot, so it flags things the channel never saw. No KV usage.
      if (url.pathname === '/tg-posted' && request.method === 'POST') {
        const { keys } = await request.json();
        if (!Array.isArray(keys)) return json({ error: 'keys must be an array' }, 400);
        const r = await pendingApprovalsDO(env, '/posted/check', { keys: keys.slice(0, 4000) });
        return json({ posted: r.posted });
      }

      // ── GET /autopost ─────────────────────────────────────────────────────────
      if (url.pathname === '/autopost' && request.method === 'GET') {
        const pendingCount = await pendingApprovalsDO(env, '/pending/count').then(r => r.count).catch(() => 0);
        return json({ enabled: await isAutopostEnabled(env), pending: pendingCount });
      }

      // ── POST /autopost ────────────────────────────────────────────────────────
      if (url.pathname === '/autopost' && request.method === 'POST') {
        const { enabled } = await request.json();
        await setAutopostEnabled(!!enabled, env);
        return json({ success: true, enabled: !!enabled });
      }

      // ── GET /blocked-brands ───────────────────────────────────────────────────
      if (url.pathname === '/blocked-brands' && request.method === 'GET') {
        return json({ brands: await getBlockedBrands(env) });
      }

      // ── POST /blocked-brands (add) ────────────────────────────────────────────
      if (url.pathname === '/blocked-brands' && request.method === 'POST') {
        const { brand } = await request.json();
        const clean = (brand || '').trim();
        if (!clean) return json({ error: 'Missing brand' }, 400);
        const brands = await getBlockedBrands(env);
        if (!brands.some(b => b.toLowerCase() === clean.toLowerCase())) brands.push(clean);
        await setBlockedBrands(brands, env);
        return json({ success: true, brands });
      }

      // ── DELETE /blocked-brands/:brand (remove) ────────────────────────────────
      const blockedBrandMatch = url.pathname.match(/^\/blocked-brands\/([^/]+)$/);
      if (blockedBrandMatch && request.method === 'DELETE') {
        const target = decodeURIComponent(blockedBrandMatch[1]).toLowerCase();
        const brands = await getBlockedBrands(env);
        const remaining = brands.filter(b => b.toLowerCase() !== target);
        await setBlockedBrands(remaining, env);
        return json({ success: true, brands: remaining });
      }

      // ── GET /scraper-status ──────────────────────────────────────────────────
      if (url.pathname === '/scraper-status' && request.method === 'GET') {
        const [statuses, errors] = await Promise.all([
          getScraperStatus(env),
          getSyncErrors(env)
        ]);
        return json({ statuses, errors });
      }

      // ── GET /sync-errors ─────────────────────────────────────────────────────
      if (url.pathname === '/sync-errors' && request.method === 'GET') {
        return json({ errors: await getSyncErrors(env) });
      }

      // ── DELETE /sync-errors ──────────────────────────────────────────────────
      if (url.pathname === '/sync-errors' && request.method === 'DELETE') {
        if (env.KV) await env.KV.put('syncErrors', JSON.stringify([]));
        return json({ success: true });
      }

      // ── GET /push/vapid-public-key ───────────────────────────────────────────
      if (url.pathname === '/push/vapid-public-key' && request.method === 'GET') {
        return json({ key: env.VAPID_PUBLIC_KEY || null });
      }

      // ── POST /push/subscribe ─────────────────────────────────────────────────
      if (url.pathname === '/push/subscribe' && request.method === 'POST') {
        const sub = await request.json();
        if (!sub || !sub.endpoint || !sub.keys) return json({ error: 'Invalid subscription' }, 400);
        if (env.KV) await env.KV.put('pushSubscription', JSON.stringify(sub));
        return json({ success: true });
      }

      // ── DELETE /push/subscribe ───────────────────────────────────────────────
      if (url.pathname === '/push/subscribe' && request.method === 'DELETE') {
        if (env.KV) await env.KV.delete('pushSubscription');
        return json({ success: true });
      }

      // ── GET /products ────────────────────────────────────────────────────────
      // ?live=1 excludes hidden/tombstoned products — the dashboard's default
      // view, so it doesn't have to download+parse+render dead weight (tombstones
      // are ~60% of the file and only need to exist for capLiveAndBury's 3-day
      // dedup window, not for the admin UI's normal product list).
      if (url.pathname === '/products' && request.method === 'GET') {
        try {
          const { products } = await getProductsFile(env);
          const live = url.searchParams.get('live') === '1';
          const filtered = live ? products.filter(p => !p.hidden) : products;
          return json({ products: filtered, totalCount: products.length, hiddenCount: products.filter(p => p.hidden).length });
        }
        catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products ───────────────────────────────────────────────────────
      if (url.pathname === '/products' && request.method === 'POST') {
        try {
          const body = await request.json(); const { product, category, highlights } = body;
          if (product.asin) await restoreAsinIfDeleted(product.asin, env);
          const { products, sha } = await getProductsFile(env);
          const today = new Date().toISOString();
          const newProduct = { id: Date.now().toString(), asin: product.asin||'', title: product.title||'', price: product.price||'', mrp: product.mrp||'', disc: product.disc||'0%', image: product.image||'', link: product.link||'', category: category||'', highlights: highlights||[], lowestPriceText: product.lowestPriceText||null, featured:false, hidden:false, outOfStock:false, order:0, addedAt:today, originalPrice: product.price||'' };
          const filtered = product.asin ? products.filter(p=>!p.asin||p.asin.toUpperCase()!==product.asin.toUpperCase()) : products;
          const updated = [newProduct, ...filtered].map((p,i)=>({...p,order:i}));
          await saveProductsFile(updated, sha, `Add deal: ${newProduct.title.slice(0,60)}`, env);
          return json({ success: true, product: newProduct });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── PUT /products/:id ────────────────────────────────────────────────────
      const putMatch = url.pathname.match(/^\/products\/([^/]+)$/);
      if (putMatch && request.method === 'PUT') {
        try {
          const id = putMatch[1]; const updates = await request.json();
          const { products, sha } = await getProductsFile(env);
          const idx = products.findIndex(p => p.id === id);
          if (idx === -1) return json({ error: 'Product not found' }, 404);
          products[idx] = { ...products[idx], ...updates };
          await saveProductsFile(products, sha, `Update product: ${products[idx].title.slice(0,60)}`, env);
          return json({ success: true, product: products[idx] });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── DELETE /products/:id ─────────────────────────────────────────────────
      const deleteMatch = url.pathname.match(/^\/products\/([^/]+)$/);
      if (deleteMatch && request.method === 'DELETE') {
        try {
          const id = deleteMatch[1]; const { products, sha } = await getProductsFile(env);
          const target = products.find(p => p.id === id);
          const filtered = products.filter(p => p.id !== id);
          if (filtered.length === products.length) return json({ error: 'Product not found' }, 404);
          await saveProductsFile(filtered.map((p,i)=>({...p,order:i})), sha, `Delete product ${id}`, env);
          if (target?.asin) await addDeletedAsin(target.asin, env);
          return json({ success: true });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/clear-lowest-prices ───────────────────────────────────
      if (url.pathname === '/products/clear-lowest-prices' && request.method === 'POST') {
        try {
          const { products, sha } = await getProductsFile(env);
          await saveProductsFile(products.map(p=>({...p,lowestPriceText:null})), sha, 'Dismiss all lowest price alerts', env);
          return json({ success: true });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /clear-cron-lock ─────────────────────────────────────────────────
      if (url.pathname === '/clear-cron-lock' && request.method === 'POST') {
        try {
          await env.KV.delete(GLOBAL_CRON_LOCK);
          return json({ success: true, message: 'Cron lock cleared' });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/clear-all-notifications ────────────────────────────────
      if (url.pathname === '/products/clear-all-notifications' && request.method === 'POST') {
        try {
          const { products, sha } = await getProductsFile(env);
          await saveProductsFile(products.map(p=>({...p,lowestPriceText:null,outOfStock:false,priceDropText:null})), sha, 'Dismiss all notifications', env);
          return json({ success: true });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/push-oos-to-bottom ────────────────────────────────────
      if (url.pathname === '/products/push-oos-to-bottom' && request.method === 'POST') {
        try {
          const { products, sha } = await getProductsFile(env);
          const inStock = products.filter(p => !p.outOfStock);
          const oos = products.filter(p => p.outOfStock);
          const reordered = [...inStock, ...oos].map((p, i) => ({ ...p, order: i }));
          await saveProductsFile(reordered, sha, `Pushed ${oos.length} OOS products to bottom`, env);
          return json({ success: true, moved: oos.length });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/push-zero-price-to-bottom ─────────────────────────────
      if (url.pathname === '/products/push-zero-price-to-bottom' && request.method === 'POST') {
        try {
          const { products, sha } = await getProductsFile(env);
          const priced = products.filter(p => !isZeroPrice(p));
          const zeroPrice = products.filter(p => isZeroPrice(p));
          const reordered = [...priced, ...zeroPrice].map((p, i) => ({ ...p, order: i }));
          await saveProductsFile(reordered, sha, `Pushed ${zeroPrice.length} zero-price products to bottom`, env);
          return json({ success: true, moved: zeroPrice.length });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/clear-oos-notifications ───────────────────────────────
      if (url.pathname === '/products/clear-oos-notifications' && request.method === 'POST') {
        try {
          const { products, sha } = await getProductsFile(env);
          const updated = products.map(p => p.outOfStock ? { ...p, outOfStock: false } : p);
          await saveProductsFile(updated, sha, 'Cleared OOS notifications', env);
          return json({ success: true });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/reorder ───────────────────────────────────────────────
      if (url.pathname === '/products/reorder' && request.method === 'POST') {
        try {
          const { orderedIds } = await request.json();
          if (!Array.isArray(orderedIds)) return json({ error: 'orderedIds must be an array' }, 400);
          const { products, sha } = await getProductsFile(env);
          const map = new Map(products.map(p => [p.id, p]));
          const seen = new Set();
          const reordered = [];
          for (let i = 0; i < orderedIds.length; i++) {
            const id = orderedIds[i];
            if (map.has(id) && !seen.has(id)) {
              seen.add(id);
              reordered.push({ ...map.get(id), order: reordered.length });
            }
          }
          for (const p of products) {
            if (!seen.has(p.id)) {
              reordered.push({ ...p, order: reordered.length });
            }
          }
          await saveProductsFile(reordered, sha, 'Reordered products', env);
          return json({ success: true, message: 'Products reordered successfully.' });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/:id/push-to-bottom ────────────────────────────────────
      const pushBottomMatch = url.pathname.match(/^\/products\/([^/]+)\/push-to-bottom$/);
      if (pushBottomMatch && request.method === 'POST') {
        try {
          const targetId = pushBottomMatch[1];
          const { products, sha } = await getProductsFile(env);
          const item = products.find(p => p.id === targetId || (p.asin && p.asin.toUpperCase() === targetId.toUpperCase()));
          if (!item) return json({ error: 'Product not found' }, 404);

          const others = products.filter(p => p.id !== item.id);
          const reordered = [...others, item].map((p, i) => ({ ...p, order: i }));

          await saveProductsFile(reordered, sha, `Pushed product ${item.id} to bottom`, env);
          return json({ success: true, message: 'Deal pushed to bottom successfully!' });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/:id/push-to-top ───────────────────────────────────────
      const pushTopMatch = url.pathname.match(/^\/products\/([^/]+)\/push-to-top$/);
      if (pushTopMatch && request.method === 'POST') {
        try {
          const targetId = pushTopMatch[1];
          const { products, sha } = await getProductsFile(env);
          const item = products.find(p => p.id === targetId || (p.asin && p.asin.toUpperCase() === targetId.toUpperCase()));
          if (!item) return json({ error: 'Product not found' }, 404);

          const others = products.filter(p => p.id !== item.id);
          const reordered = [item, ...others].map((p, i) => ({ ...p, order: i }));

          await saveProductsFile(reordered, sha, `Pushed product ${item.id} to top`, env);
          return json({ success: true, message: 'Deal pushed to top successfully!' });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      if (url.pathname === '/debug-ifs-kurlon') {
        const rtoKurlon = 'MzAwNTM5NDk4Ng==';
        const rtoFlorance = 'MzAwNTM5Mjc2NA==';
        
        const testRes = async (rto) => {
          const redirTarget = `https://www.indiafreestuff.in/?rto=${rto}`;
          const redManual = await fetchWithProxy(redirTarget, {
            redirect: 'manual',
            headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] },
          }, 15000, env);
          const loc = redManual ? (redManual.headers.get('location') || '') : '';
          const bodyManual = redManual ? await redManual.text().catch(() => '') : '';
          const searchStr = loc + ' ' + bodyManual;
          const asin = extractAsin(searchStr);

          let finalUrl = loc;
          let asin2 = asin;
          if (!asin) {
            const redFollow = await fetchWithProxy(redirTarget, {
              headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] },
            }, 15000, env);
            finalUrl = redFollow ? (redFollow.url || '') : '';
            const finalBody = redFollow ? await redFollow.text().catch(() => '') : '';
            asin2 = extractAsin(finalUrl + ' ' + finalBody.slice(0, 10000));
          }

          return { rto, status: redManual ? redManual.status : 'err', loc, asin, finalUrl, asin2 };
        };

        const kRes = await testRes(rtoKurlon);
        const fRes = await testRes(rtoFlorance);

        return json({ kurlon: kRes, florance: fRes });
      }

      return await env.ASSETS.fetch(request);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },

  // ── Cron jobs ─────────────────────────────────────────────────────────────
  async scheduled(event, env, ctx) {
    // Helper to check if current time is within sleep hours (2:00 AM - 7:00 AM IST)
    const getIstHour = () => new Date(Date.now() + 5.5 * 60 * 60 * 1000).getUTCHours();

    // Every 30 min (at :14,:44): sync IndiaFreeStuff
    if (event.cron === '14,44 * * * *') {
      if (getIstHour() >= 2 && getIstHour() < 7) {
        console.log('Skipping IndiaFreeStuff sync during sleep hours (2am-7am IST)');
        return;
      }
      ctx.waitUntil(
        withCronLock('cron_ifs', 180, env, async () => {
          try {
            console.log('IndiaFreeStuff sync start');
            const r = await scrapeAndSyncIndiaFreeStuff(env, 30);
            console.log('IndiaFreeStuff sync:', r.message);
          } catch (e) {
            console.error('IndiaFreeStuff sync error:', e.message);
            await saveSyncError('IndiaFreeStuff', e.message, env);
          }
        })
      );
    }

    // Every 10 min at :02,:12,:22,:32,:42,:52 — never overlaps with 5,35 cron
    if (event.cron === '2,12,22,32,42,52 * * * *') {
      if (getIstHour() >= 2 && getIstHour() < 7) {
        console.log('Skipping Price Check during sleep hours (2am-7am IST)');
        return;
      }
      ctx.waitUntil(
        withCronLock('cron_10min', 180, env, async () => {
          try {
            console.log('Price check start');
            const r = await checkAndCleanDeals(env);
            console.log('Price check:', r.message);
          } catch (e) {
            console.error('Price check error:', e.message);
          }
        })
      );
    }

    // Every 15 min (at :08,:23,:38,:53): 1 Amazon deal + badge check + Flipkart cron
    if (event.cron === '8,23,38,53 * * * *') {
      if (getIstHour() >= 2 && getIstHour() < 7) {
        console.log('Skipping Hourly checks during sleep hours (2am-7am IST)');
        return;
      }
      ctx.waitUntil(
        withCronLock('cron_hourly', 300, env, async () => {
          try {
            console.log('Amazon deals sync start (1/hr)');
            const r = await syncAmazonDealsToProducts(env, 1);
            console.log('Amazon deals sync:', r.message);
          } catch (e) {
            console.error('Amazon deals sync error:', e.message);
            await saveSyncError('AmazonDealsSync', e.message, env);
          }
          try {
            console.log('Badge check start');
            const r = await checkLowestPriceBadges(env);
            console.log('Badge check:', r.message);
          } catch (e) {
            console.error('Badge check error:', e.message);
          }
          try {
            console.log('Non-Amazon deals auto-publish start');
            await cronSyncAndPublishNonAmazonDeals(env);
            console.log('Non-Amazon deals auto-publish complete');
          } catch (e) {
            console.error('Non-Amazon auto-publish cron error:', e.message);
          }
        })
      );
    }

    // 8 AM & 6 PM IST (2:31 & 12:31 UTC) — Amazon deals sweep, merged into one trigger slot
    if (event.cron === '31 2,12 * * *') {
      ctx.waitUntil(
        (async () => {
          try {
            console.log('Amazon Deals check start');
            const r = await checkAmazonDeals(env);
            console.log('Amazon Deals check:', r.message);
          } catch (e) {
            console.error('Amazon Deals check error:', e.message);
            await saveSyncError('AmazonDeals', e.message, env);
          }
          try {
            await checkCueLinksCampaignAccess(env);
          } catch (e) {
            console.error('CueLinks campaign access check error:', e.message);
          }
        })()
      );
    }

    // Dedicated slot for Telegram posting and DealsSpy/DealOfTheDay syncs (except :15 and :45)
    if (event.cron === '0,5,10,20,25,30,35,40,50,55 * * * *') {
      if (getIstHour() >= 2 && getIstHour() < 7) {
        console.log('Skipping Telegram posting and Amazon syncs during sleep hours (2am-7am IST)');
        return;
      }
      ctx.waitUntil(
        postNewDealsToTelegramLocked(env).catch(e => console.error('TG cron error:', e.message))
      );

      ctx.waitUntil(
        withCronLock('cron_radar_dotd', 180, env, async () => {
          try {
            console.log('DealsSpy sync start');
            const r = await scrapeAndSyncDealsSpy(env);
            console.log('DealsSpy sync:', r.message);
          } catch (e) {
            console.error('DealsSpy sync error:', e.message);
            await saveSyncError('DealsSpyAmazon', e.message, env);
          }
          try {
            console.log('DealOfTheDayIndia sync start');
            const r = await scrapeAndSyncDealOfTheDayIndia(env, 10);
            console.log('DealOfTheDayIndia sync:', r.message);
          } catch (e) {
            console.error('DealOfTheDayIndia sync error:', e.message);
            await saveSyncError('DealOfTheDayIndia', e.message, env);
          }
        })
      );
    }
  },
};
