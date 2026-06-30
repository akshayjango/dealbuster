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
  const resp = await fetch('https://api.amazon.com/auth/o2/token', {
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
      asin: item.asin, title: item.itemInfo?.title?.displayValue || '',
      image: item.images?.primary?.large?.url || '',
      price: price ? `₹${Math.round(price)}` : '', mrp: mrp ? `₹${Math.round(mrp)}` : '',
      disc: disc ? `-${disc}%` : '0%', link: `https://www.amazon.in/dp/${item.asin}?tag=${env.PA_PARTNER_TAG}`,
    };
  });
  return json({ items });
}

// ── GitHub helpers ────────────────────────────────────────────────────────────

function encodeBase64Unicode(str) {
  return btoa(encodeURIComponent(str).replace(/%([0-9A-F]{2})/g, (_, p) => String.fromCharCode('0x' + p)));
}

function ghHeaders(env) {
  return { 'Authorization': `token ${(env.GITHUB_TOKEN || '').trim()}`, 'User-Agent': 'Dealbuster-Admin' };
}

async function getProductsFile(env) {
  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/products.json`;
  const resp = await fetch(apiUrl, { headers: ghHeaders(env) });
  if (resp.status === 404) return { products: [], sha: null };
  if (!resp.ok) { const err = await resp.json().catch(() => ({})); throw new Error(err.message || `GitHub fetch failed: ${resp.status}`); }
  const file = await resp.json();
  const rawBytes = atob(file.content.replace(/\n/g, ''));
  const uint8 = new Uint8Array(rawBytes.length);
  for (let i = 0; i < rawBytes.length; i++) uint8[i] = rawBytes.charCodeAt(i);
  const products = JSON.parse(new TextDecoder('utf-8').decode(uint8));
  return { products: Array.isArray(products) ? products : [], sha: file.sha };
}

async function saveProductsFile(products, sha, message, env) {
  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/products.json`;
  const body = { message, content: encodeBase64Unicode(JSON.stringify(products, null, 2)) };
  if (sha) body.sha = sha;
  const resp = await fetch(apiUrl, { method: 'PUT', headers: { ...ghHeaders(env), 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  if (!resp.ok) { const err = await resp.json().catch(() => ({})); throw new Error(err.message || `GitHub write failed: ${resp.status}`); }
  return resp.json();
}

async function getDeletedAsins(env) {
  const apiUrl = `https://api.github.com/repos/akshayjango/dealbuster/contents/deleted_asins.json`;
  const resp = await fetch(apiUrl, { headers: ghHeaders(env) });
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
    await fetch(apiUrl, { method: 'PUT', headers: { ...ghHeaders(env), 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  } catch (e) { console.error('Failed to save deleted ASIN:', e.message); }
}

async function restoreAsinIfDeleted(asin, env) {
  if (!asin) return;
  try {
    const { asins, sha } = await getDeletedAsins(env);
    const upper = asin.toUpperCase();
    if (!asins.includes(upper)) return;
    const remaining = asins.filter(a => a !== upper);
    await fetch(`https://api.github.com/repos/akshayjango/dealbuster/contents/deleted_asins.json`, {
      method: 'PUT',
      headers: { ...ghHeaders(env), 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: `Restore ASIN: ${upper}`, content: encodeBase64Unicode(JSON.stringify(remaining, null, 2)), sha }),
    });
  } catch (e) { console.error('Failed to restore ASIN:', e.message); }
}

// ── KV-based sync error notifications ────────────────────────────────────────

async function saveSyncError(source, message, env) {
  if (!env.KV) return;
  try {
    const existing = await env.KV.get('syncErrors', 'json') || [];
    existing.unshift({ id: Date.now().toString(), source, message, time: new Date().toISOString() });
    await env.KV.put('syncErrors', JSON.stringify(existing.slice(0, 20)));
  } catch (e) { console.error('Failed to save sync error:', e.message); }
}

async function getSyncErrors(env) {
  if (!env.KV) return [];
  try { return await env.KV.get('syncErrors', 'json') || []; }
  catch { return []; }
}

// ── Amazon helpers ────────────────────────────────────────────────────────────

const AMZ_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Accept-Language': 'en-IN,en;q=0.9',
  'Accept': 'text/html',
};

// Derive product image from ASIN — no subrequest needed
function asinImage(asin) {
  return `https://m.media-amazon.com/images/P/${asin}.01._SL500_.jpg`;
}

// Used only by hourly badge-check cron (not sync)
// Returns { badge: string|null, highlights: string[] }
async function fetchAmazonPageData(asin) {
  try {
    const r = await fetch(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
    if (!r.ok) return { badge: null, highlights: [] };
    const html = await r.text();

    const badgeM = html.match(/(Lowest\s+price\s+(?:in\s+\d+\s+days|ever))/i);
    const badge = badgeM ? badgeM[1].trim() : null;

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

    return { badge, highlights };
  } catch { return { badge: null, highlights: [] }; }
}

// ── DealsRadar sync (30 new deals / hour, 40 on manual) ───────────────────────

async function scrapeAndSyncDealsRadar(env, limit = 30) {
  let dealsJs;
  try {
    const r = await fetch('https://www.dealsradar.in/deals.js', { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    dealsJs = await r.text();
  } catch (e) {
    const msg = `DealsRadar fetch failed: ${e.message}`;
    console.error(msg);
    await saveSyncError('DealsRadar', msg, env);
    return { success: false, count: 0, message: msg };
  }

  const startIdx = dealsJs.indexOf('[');
  const endIdx = dealsJs.lastIndexOf(']') + 1;
  let allDeals;
  try {
    if (startIdx === -1 || endIdx <= 0) throw new Error('Array not found in deals.js');
    allDeals = JSON.parse(dealsJs.slice(startIdx, endIdx));
    if (!Array.isArray(allDeals)) throw new Error('Parsed data is not array');
  } catch (e) {
    const msg = `DealsRadar parse failed: ${e.message}`;
    await saveSyncError('DealsRadar', msg, env);
    return { success: false, count: 0, message: msg };
  }

  const { products, sha } = await getProductsFile(env);
  let { asins: deletedAsins } = await getDeletedAsins(env).catch(() => ({ asins: [] }));
  const deletedSet = new Set(deletedAsins.map(a => a.toUpperCase()));

  // Build ASIN → product index
  const existingByAsin = new Map(products.filter(p => p.asin).map(p => [p.asin.toUpperCase(), p]));

  const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const added = [];
  const updated = [];

  // Process newest 240 from DealsRadar
  const recentDeals = allDeals.slice(0, 240);

  for (const deal of recentDeals) {
    if (!deal.asin) continue;
    const asinUpper = deal.asin.toUpperCase();
    if (deletedSet.has(asinUpper)) continue;

    const price = deal.currentPrice || 0;
    const mrp = deal.originalPrice || price;
    const discNum = mrp > price ? Math.round((1 - price / mrp) * 100) : 0;
    const priceStr = '₹' + price.toLocaleString('en-IN');
    const mrpStr = '₹' + mrp.toLocaleString('en-IN');
    const discStr = discNum > 0 ? `-${discNum}%` : '0%';
    const link = `https://www.amazon.in/dp/${deal.asin}?tag=${TAG}`;

    const drCat = (deal.category || '').toLowerCase();
    let category = 'Electronics';
    if (drCat.includes('fashion') || drCat.includes('apparel') || drCat.includes('shoe') || drCat.includes('bag') || drCat.includes('wallet')) category = 'Fashion';
    else if (drCat.includes('home') || drCat.includes('kitchen') || drCat.includes('furniture') || drCat.includes('garden')) category = 'Home';
    else if (drCat.includes('beauty') || drCat.includes('cosmetic') || drCat.includes('skin') || drCat.includes('hair')) category = 'Beauty';
    else if (drCat.includes('health') || drCat.includes('medicine') || drCat.includes('supplement') || drCat.includes('protein')) category = 'Health';

    const highlights = (deal.description || '').split('|').map(h => h.replace(/\s+/g,' ').trim()).filter(h => h.length > 10 && h.split(' ').length >= 3 && h.length < 300).slice(0, 5);

    if (existingByAsin.has(asinUpper)) {
      // Update existing: refresh price, push to top later
      const existing = existingByAsin.get(asinUpper);
      updated.push({ ...existing, price: priceStr, mrp: mrpStr, disc: discStr, link, addedAt: new Date().toISOString(), outOfStock: false });
    } else {
      if (added.length >= limit) break;
      const image = deal.image || asinImage(deal.asin);

      added.push({
        id: `dr_${Date.now()}_${added.length}`,
        asin: deal.asin, title: deal.title || '', price: priceStr, mrp: mrpStr, disc: discStr,
        image, link, category, highlights, lowestPriceText: null, featured: false, hidden: false, outOfStock: false,
        order: 0, addedAt: new Date().toISOString(),
      });
    }
  }

  if (added.length === 0 && updated.length === 0) {
    return { success: true, count: 0, message: 'No new or updated DealsRadar deals.' };
  }

  // Remove updated products from current list (we'll re-add them at top)
  const updatedAsinSet = new Set(updated.map(p => p.asin.toUpperCase()));
  const base = products.filter(p => !p.asin || !updatedAsinSet.has(p.asin.toUpperCase()));

  // New and updated go to top
  let final = [...added, ...updated, ...base].map((p, i) => ({ ...p, order: i }));

  // Trim to 270
  if (final.length > 270) final = final.slice(0, 270);

  const msg = `DR sync: +${added.length} new, ${updated.length} updated`;
  await saveProductsFile(final, sha, msg, env);
  return { success: true, added: added.length, updated: updated.length, message: msg };
}

// ── IndiaFreeStuff sync (10 deals / 10 min, Amazon-only) ─────────────────────

function decodeHtmlEntities(str) {
  return str.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#039;/g,"'").replace(/&#124;/g,'|').replace(/&#8211;/g,'-').replace(/&#8217;/g,"'").replace(/&#8220;/g,'"').replace(/&#8221;/g,'"');
}

function parseTimeAgo(text, baseTime) {
  const now = baseTime || Date.now();
  const t = text.toLowerCase().trim();
  const num = n => parseInt(t.match(/\d+/)?.[0] || String(n));
  if (t.includes('second')) return now - num(1) * 1000;
  if (t.includes('minute')) return now - num(1) * 60 * 1000;
  if (t.includes('hour'))   return now - num(1) * 60 * 60 * 1000;
  if (t.includes('day'))    return now - num(1) * 24 * 60 * 60 * 1000;
  if (t.includes('week'))   return now - num(1) * 7 * 24 * 60 * 60 * 1000;
  if (t.includes('month'))  return now - num(1) * 30 * 24 * 60 * 60 * 1000;
  const parsed = new Date(text);
  return isNaN(parsed.getTime()) ? now : parsed.getTime();
}

async function scrapeAndSyncIndiaFreeStuff(env, limit = 10) {
  // Server-rendered. 1 fetch for /trending (40 deals) + 1 redirect-follow per NEW Amazon deal for ASIN.
  // Filter: only blocks containing /stores/amazon link.
  // Image: extract Amazon image hash from their thumbnail filename — no extra fetch.
  const matchesMap = new Map();

  try {
    const r = await fetch('https://www.indiafreestuff.in/trending', { headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] } });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const html = await r.text();

    const blocks = html.split(/<div class="product-item">/g);
    for (let i = 1; i < blocks.length; i++) {
      const block = blocks[i];

      // Amazon-only filter — block must link to /stores/amazon
      if (!block.includes('/stores/amazon')) continue;

      // Title from item-title anchor
      const titleM = block.match(/class="item-title"[^>]*>\s*([^<]{5,}?)\s*<\/a>/i);
      if (!titleM) continue;
      let title = decodeHtmlEntities(titleM[1].replace(/\s+/g,' ').trim());
      // Strip trailing " Rs. NNN - Amazon" suffix sites append
      title = title.replace(/\s*Rs\.\s*[\d,]+\s*[-–]\s*Amazon\s*$/i, '').trim();
      if (!title || title.length < 5) continue;

      // Image: extract Amazon image hash from their thumbnail filename
      // e.g. thumb_f8ec8aef_61NiiBDN0yL.SX522.jpg → 61NiiBDN0yL → Amazon CDN image
      const thumbM = block.match(/data-original="([^"]+images\.indiafreestuff\.in[^"]+)"/i);
      let image = '';
      if (thumbM) {
        const fname = thumbM[1].split('/').pop();
        const hashM = fname.match(/thumb_[a-f0-9]+_([A-Za-z0-9]{11})\./);
        image = hashM
          ? `https://m.media-amazon.com/images/I/${hashM[1]}._SL500_.jpg`
          : thumbM[1]; // fallback to their CDN thumbnail
      }

      // Prices
      const priceM = block.match(/class="new-price"[\s\S]*?fa-inr[^>]*><\/i>\s*([\d,]+)/i);
      const mrpM   = block.match(/class="old-price"[\s\S]*?fa-inr[^>]*><\/i>\s*([\d,]+)/i);
      const price = priceM ? parseInt(priceM[1].replace(/,/g,'')) : 0;
      const mrp   = mrpM   ? parseInt(mrpM[1].replace(/,/g,''))   : price;

      // rto redirect URL → will resolve to ASIN later for new deals only
      const rtoM = block.match(/href="https?:\/\/www\.indiafreestuff\.in\/\?rto=([^"]+)"/i);
      if (!rtoM) continue;
      const rtoParam = rtoM[1];

      const key = rtoParam; // dedupe by rto param until we have ASIN
      if (!matchesMap.has(key)) {
        matchesMap.set(key, { title, image, price, mrp, rtoParam });
      }
    }
  } catch (e) {
    const msg = `IndiaFreeStuff fetch failed: ${e.message}`;
    await saveSyncError('IndiaFreeStuff', msg, env);
    return { success: false, count: 0, message: msg };
  }

  if (matchesMap.size === 0) {
    const msg = 'IndiaFreeStuff: no Amazon deals found (structure may have changed)';
    await saveSyncError('IndiaFreeStuff', msg, env);
    return { success: false, count: 0, message: msg };
  }

  const { products, sha } = await getProductsFile(env);
  let { asins: deletedAsins } = await getDeletedAsins(env).catch(() => ({ asins: [] }));
  const deletedSet = new Set(deletedAsins.map(a => a.toUpperCase()));
  const existingByAsin = new Map(products.filter(p => p.asin).map(p => [p.asin.toUpperCase(), p]));

  const TAG = env.PA_PARTNER_TAG || 'dealbuster002-21';
  const added = [];
  const updated = [];

  for (const { title, image, price, mrp, rtoParam } of matchesMap.values()) {
    if (added.length >= limit) break;

    // Follow redirect (manual) — 1 subrequest, gets Location header with Amazon URL → ASIN
    let asin = '';
    try {
      const red = await fetch(`https://www.indiafreestuff.in/?rto=${rtoParam}`, {
        redirect: 'manual',
        headers: { 'User-Agent': AMZ_HEADERS['User-Agent'] },
      });
      const loc = red.headers.get('location') || '';
      if (!loc.includes('amazon.in')) continue; // skip non-Amazon redirects
      const asinM = loc.match(/\/dp\/([A-Z0-9]{10})/i);
      if (asinM) asin = asinM[1].toUpperCase();
    } catch { continue; }

    if (!asin || deletedSet.has(asin)) continue;

    const discNum = mrp > price && price > 0 ? Math.round((1 - price / mrp) * 100) : 0;
    const priceStr = price > 0 ? '₹' + price.toLocaleString('en-IN') : '';
    const mrpStr   = mrp   > 0 ? '₹' + mrp.toLocaleString('en-IN')   : priceStr;
    const discStr  = discNum > 0 ? `-${discNum}%` : '0%';
    const link = `https://www.amazon.in/dp/${asin}?tag=${TAG}`;

    if (existingByAsin.has(asin)) {
      const existing = existingByAsin.get(asin);
      updated.push({ ...existing, price: priceStr || existing.price, mrp: mrpStr || existing.mrp, disc: discStr, addedAt: new Date().toISOString(), outOfStock: false });
      continue;
    }

    const tl = title.toLowerCase();
    let category = 'Electronics';
    if (tl.includes('shirt')||tl.includes('shoe')||tl.includes('jeans')||tl.includes('kurta')||tl.includes('saree')||tl.includes('bag')||tl.includes('wallet')) category = 'Fashion';
    else if (tl.includes('home')||tl.includes('kitchen')||tl.includes('bottle')||tl.includes('furniture')||tl.includes('led')||tl.includes('towel')||tl.includes('bed')||tl.includes('curtain')||tl.includes('bulb')) category = 'Home';
    else if (tl.includes('face')||tl.includes('serum')||tl.includes('cream')||tl.includes('shampoo')||tl.includes('beauty')||tl.includes('perfume')||tl.includes('lotion')||tl.includes('wash')) category = 'Beauty';
    else if (tl.includes('supplement')||tl.includes('health')||tl.includes('protein')||tl.includes('capsule')||tl.includes('tablet')) category = 'Health';

    added.push({
      id: `ifs_${Date.now()}_${added.length}`,
      asin, title, price: priceStr, mrp: mrpStr, disc: discStr,
      image, link, category, highlights: ['Great deal on Amazon'],
      lowestPriceText: null, featured: false, hidden: false, outOfStock: false,
      order: 0, addedAt: new Date().toISOString(),
    });
  }

  if (added.length === 0 && updated.length === 0) {
    return { success: true, count: 0, message: 'IndiaFreeStuff: no new Amazon deals.' };
  }

  const updatedAsinSet = new Set(updated.map(p => p.asin.toUpperCase()));
  const base = products.filter(p => !p.asin || !updatedAsinSet.has(p.asin.toUpperCase()));
  let final = [...added, ...updated, ...base].map((p, i) => ({ ...p, order: i }));
  if (final.length > 270) final = final.slice(0, 270);

  const msg = `IndiaFreeStuff sync: +${added.length} new, ${updated.length} updated`;
  await saveProductsFile(final, sha, msg, env);
  return { success: true, added: added.length, updated: updated.length, message: msg };
}

// ── Price check + OOS detection (Creators API) ────────────────────────────────

function parsePrice(str) {
  if (!str) return null;
  const n = parseFloat(str.replace(/[^0-9.]/g,''));
  return n > 0 ? Math.round(n) : null;
}

async function checkAndCleanDeals(env) {
  const { products, sha } = await getProductsFile(env);
  if (!products.length) return { success: true, message: 'No products to check.' };

  let token;
  try { token = await getAccessToken(env.PA_ACCESS_KEY, env.PA_SECRET_KEY); }
  catch (e) { throw new Error(`Auth failed: ${e.message}`); }

  // Rotate through products: check oldest-checked first, up to 100
  const withAsin = products.filter(p => p.asin);
  const sorted = [...withAsin].sort((a, b) => (a.lastChecked || 0) - (b.lastChecked || 0));
  const toCheck = sorted.slice(0, 100);

  const productMap = new Map(products.map(p => [p.id, { ...p }]));
  const toPushTop = [];
  let changed = false;

  const CHUNK = 10;
  for (let i = 0; i < toCheck.length; i += CHUNK) {
    const chunk = toCheck.slice(i, i + CHUNK);
    const asins = chunk.map(p => p.asin);
    const now = Date.now();

    chunk.forEach(p => { const u = productMap.get(p.id); if (u) u.lastChecked = now; });

    try {
      const resp = await fetch('https://creatorsapi.amazon/catalog/v1/getItems', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json', 'x-marketplace': 'www.amazon.in' },
        body: JSON.stringify({
          itemIds: asins, itemIdType: 'ASIN', marketplace: 'www.amazon.in',
          partnerTag: env.PA_PARTNER_TAG || 'dealbuster002-21',
          resources: ['itemInfo.title','offersV2.listings.price','offersV2.listings.availability','offersV2.listings.dealDetails'],
        }),
      });
      if (!resp.ok) { console.error(`GetItems chunk ${i} HTTP ${resp.status}`); continue; }
      const data = await resp.json();
      const items = data.itemsResult?.items || [];
      const returnedAsins = new Set(items.map(it => it.asin.toUpperCase()));

      for (const p of chunk) {
        const updated = productMap.get(p.id);
        const item = items.find(it => it.asin.toUpperCase() === p.asin.toUpperCase());

        // Only mark OOS when API explicitly signals it — not on missing item or missing price
        const listing = item?.offersV2?.listings?.[0];
        const amPrice = listing?.price?.amount;
        const availability = listing?.availability;
        const isOOS = item && (
          ['OUT_OF_STOCK','UNAVAILABLE'].includes((availability?.type||'').toUpperCase()) ||
          !!(availability?.message||'').toLowerCase().match(/out of stock|unavailable/)
        );

        if (isOOS) {
          if (!updated.outOfStock) {
            updated.outOfStock = true;
            changed = true;
          }
          continue;
        }

        // Back in stock
        if (updated.outOfStock) { updated.outOfStock = false; changed = true; }

        // No price from API — don't overwrite with NaN, skip price update
        if (!amPrice || amPrice <= 0) continue;

        const dbPrice = parsePrice(p.price);
        const amMrp = listing?.dealDetails?.originalPrice?.amount || listing?.price?.amount || dbPrice || amPrice;
        const newDisc = amPrice && amMrp && amMrp > amPrice ? Math.round((1 - amPrice / amMrp) * 100) : 0;
        const newPriceStr = '₹' + Math.round(amPrice).toLocaleString('en-IN');
        const newMrpStr = '₹' + Math.round(amMrp).toLocaleString('en-IN');
        const newDiscStr = newDisc > 0 ? `-${newDisc}%` : '0%';

        const priceChanged = updated.price !== newPriceStr || updated.mrp !== newMrpStr || updated.disc !== newDiscStr;
        const priceDrop = dbPrice !== null && amPrice < dbPrice;

        if (priceChanged) {
          updated.price = newPriceStr;
          updated.mrp = newMrpStr;
          updated.disc = newDiscStr;
          changed = true;
        }

        if (priceDrop) {
          updated.addedAt = new Date().toISOString();
          toPushTop.push(p.id);
          changed = true;
        }
      }
    } catch (err) {
      console.error(`Chunk ${i} error:`, err.message);
    }
  }

  if (!changed && toPushTop.length === 0) {
    return { success: true, message: 'Prices up to date. No changes.' };
  }

  const pushSet = new Set(toPushTop);
  const top = [], rest = [];
  for (const p of products) {
    const updated = productMap.get(p.id) || p;
    if (pushSet.has(p.id)) top.push(updated);
    else rest.push(updated);
  }

  const reordered = [...top, ...rest].map((p, i) => ({ ...p, order: i }));
  await saveProductsFile(reordered, sha, `Price sync: ${toPushTop.length} price drops, updated remaining`, env);

  return {
    success: true, priceDrops: toPushTop.length,
    oosCount: [...productMap.values()].filter(p => p.outOfStock).length,
    message: `Price sync done. ${toPushTop.length} drops pushed to top.`,
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
  const toCheck = [...needHL, ...hasHL].slice(0, 8);

  const productMap = new Map(products.map(p => [p.id, { ...p }]));
  let changed = false;
  let badgeCount = 0;
  let highlightCount = 0;

  for (const p of toCheck) {
    const updated = productMap.get(p.id);
    if (!updated) continue;
    updated.lastBadgeCheck = Date.now();

    const { badge, highlights } = await fetchAmazonPageData(p.asin);

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
  }

  if (!changed) return { success: true, message: 'No changes from badge/highlight check.' };

  const reordered = [...productMap.values()].sort((a, b) => (a.order || 0) - (b.order || 0));
  await saveProductsFile(reordered, sha, `Badge/highlight check: ${badgeCount} badges, ${highlightCount} highlights`, env);

  return { success: true, badgeCount, highlightCount, message: `${badgeCount} new badges, ${highlightCount} highlights filled.` };
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
      const r = await fetch(pageUrl, {
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
      const r = await fetch(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
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
        link: `https://www.amazon.in/dp/${asin}?tag=${TAG}`,
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
        const r = await fetch(pageUrl, { headers: { ...AMZ_HEADERS, 'Cache-Control': 'no-cache' } });
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
      const r = await fetch(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
      if (!r.ok) continue;
      const html = await r.text();

      // Title
      const titleM = html.match(/id="productTitle"[^>]*>\s*([\s\S]*?)\s*<\/span>/);
      let title = titleM ? titleM[1].replace(/\s+/g,' ').trim() : '';
      title = decodeHtmlEntities(title);
      if (!title || title.length < 5) continue;

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

      // Category
      const tl = title.toLowerCase();
      let category = 'Electronics';
      if (tl.includes('shirt')||tl.includes('shoe')||tl.includes('jeans')||tl.includes('kurta')||tl.includes('saree')||tl.includes('bag')||tl.includes('wallet')) category = 'Fashion';
      else if (tl.includes('home')||tl.includes('kitchen')||tl.includes('bottle')||tl.includes('furniture')||tl.includes('towel')||tl.includes('bed')) category = 'Home';
      else if (tl.includes('face')||tl.includes('serum')||tl.includes('cream')||tl.includes('shampoo')||tl.includes('beauty')||tl.includes('perfume')) category = 'Beauty';
      else if (tl.includes('supplement')||tl.includes('health')||tl.includes('protein')||tl.includes('capsule')||tl.includes('tablet')) category = 'Health';

      added.push({
        id: `amzdeal_${Date.now()}_${added.length}`,
        asin, title,
        price: '₹' + price.toLocaleString('en-IN'),
        mrp: '₹' + mrp.toLocaleString('en-IN'),
        disc: discNum > 0 ? `-${discNum}%` : '0%',
        image, link: `https://www.amazon.in/dp/${asin}?tag=${TAG}`,
        category, highlights: highlights.length ? highlights : ['Great deal on Amazon'],
        lowestPriceText: null, featured: false, hidden: false, outOfStock: false,
        order: 0, addedAt: new Date().toISOString(),
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

  const final = [...added, ...products].map((p, i) => ({ ...p, order: i }));
  const trimmed = final.length > 270 ? final.slice(0, 270) : final;
  await saveProductsFile(trimmed, sha, `Amazon deals sync: +${added.length}`, env);
  return { success: true, count: added.length, message: `Amazon Deals sync: added ${added.length} deal${added.length > 1 ? 's' : ''} from amazon.in/deals` };
}

// ── handlePublish ─────────────────────────────────────────────────────────────

async function handlePublish(body, env) {
  const { product, category, highlights } = body;
  if (product.asin) await restoreAsinIfDeleted(product.asin, env);

  const { products, sha } = await getProductsFile(env);
  const today = new Date().toISOString();
  const newProduct = {
    id: Date.now().toString(), asin: product.asin || '', title: product.title || '',
    price: product.price || '', mrp: product.mrp || '', disc: product.disc || '0%',
    image: product.image || '', link: product.link || '', category: category || '',
    highlights: highlights || [], lowestPriceText: product.lowestPriceText || null,
    featured: false, hidden: false, outOfStock: false, order: 0, addedAt: today,
  };
  const filtered = product.asin ? products.filter(p => !p.asin || p.asin.toUpperCase() !== product.asin.toUpperCase()) : products;
  const updated = [newProduct, ...filtered].map((p, i) => ({ ...p, order: i }));
  await saveProductsFile(updated, sha, `Add deal: ${product.title.slice(0,60)}`, env);

  // Legacy: write card to index.html
  const params = new URLSearchParams({ title: product.title, cat: category, price: product.price, mrp: product.mrp, disc: product.disc, updated: today.slice(0,10), img: product.image, link: product.link, hl: (highlights||[]).join('|') });
  const cardHtml = `    <!-- Card added ${today.slice(0,10)} -->\n    <a class="product-card" data-cat="${category.toLowerCase()}" href="product.html?${params.toString()}">\n      <div class="card-img-wrap">\n        <img src="${product.image}" alt="${product.title}" style="width:100%;height:180px;object-fit:contain;display:block;background:#fff;">\n        <span class="discount-badge">${product.disc}</span>\n        <span class="updated-tag">Updated today</span>\n      </div>\n      <div class="card-body">\n        <p class="card-title">${product.title}</p>\n        <div class="card-prices">\n          <div class="price-original">${product.mrp}</div>\n          <div class="price-current">${product.price}</div>\n        </div>\n        <span class="btn-view">View More</span>\n      </div>\n    </a>`;

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
    const tResp = await fetch('https://api.amazon.com/auth/o2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `grant_type=client_credentials&client_id=${encodeURIComponent(env.PA_ACCESS_KEY)}&client_secret=${encodeURIComponent(env.PA_SECRET_KEY)}&scope=creatorsapi%3A%3Adefault` });
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

    const password = request.headers.get('X-Admin-Password');
    if (password !== env.ADMIN_PASSWORD) return json({ error: 'Unauthorized' }, 401);

    const url = new URL(request.url);

    try {
      if (url.pathname === '/ping' && request.method === 'GET') return json({ ok: true });

      // ── /fetchtitle ──────────────────────────────────────────────────────────
      if (url.pathname === '/fetchtitle' && request.method === 'GET') {
        let asin = url.searchParams.get('asin');
        const shortUrl = url.searchParams.get('url');
        if (!asin && !shortUrl) return json({ error: 'Missing asin or url' }, 400);
        try {
          let html = '';
          if (shortUrl) {
            const redir = await fetch(shortUrl, { redirect: 'follow', headers: AMZ_HEADERS });
            const asinM = redir.url.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i);
            if (asinM) { asin = asinM[1]; html = await redir.text(); }
          }
          const isCaptcha = html && (html.includes('captcha') || html.includes('Robot Check'));
          const hasTitle = html && (html.includes('id="productTitle"') || html.includes('<title>'));
          if ((!html || isCaptcha || !hasTitle) && asin) {
            const r = await fetch(`https://www.amazon.in/dp/${asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
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
        try { return json(await scrapeAndSyncDealsRadar(env, 40)); } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /sync-indiafreestuff ─────────────────────────────────────────────────
      if (url.pathname === '/sync-indiafreestuff' && request.method === 'GET') {
        try { return json(await scrapeAndSyncIndiaFreeStuff(env, 20)); } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── /sync-all ────────────────────────────────────────────────────────────
      if (url.pathname === '/sync-all' && request.method === 'GET') {
        const results = await Promise.allSettled([scrapeAndSyncDealsRadar(env, 40), scrapeAndSyncIndiaFreeStuff(env, 20)]);
        return json({ success: true, results: results.map((r,i) => ({ site: i===0?'DealsRadar':'IndiaFreeStuff', status: r.status, result: r.status==='fulfilled'?r.value:{error:r.reason.message} })) });
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
              const r = await fetch(`https://www.amazon.in/dp/${p.asin}?th=1&psc=1`, { headers: AMZ_HEADERS });
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

      // ── GET /sync-errors ─────────────────────────────────────────────────────
      if (url.pathname === '/sync-errors' && request.method === 'GET') {
        return json({ errors: await getSyncErrors(env) });
      }

      // ── DELETE /sync-errors ──────────────────────────────────────────────────
      if (url.pathname === '/sync-errors' && request.method === 'DELETE') {
        if (env.KV) await env.KV.put('syncErrors', JSON.stringify([]));
        return json({ success: true });
      }

      // ── GET /products ────────────────────────────────────────────────────────
      if (url.pathname === '/products' && request.method === 'GET') {
        try { const { products } = await getProductsFile(env); return json({ products }); }
        catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products ───────────────────────────────────────────────────────
      if (url.pathname === '/products' && request.method === 'POST') {
        try {
          const body = await request.json(); const { product, category, highlights } = body;
          if (product.asin) await restoreAsinIfDeleted(product.asin, env);
          const { products, sha } = await getProductsFile(env);
          const today = new Date().toISOString();
          const newProduct = { id: Date.now().toString(), asin: product.asin||'', title: product.title||'', price: product.price||'', mrp: product.mrp||'', disc: product.disc||'0%', image: product.image||'', link: product.link||'', category: category||'', highlights: highlights||[], lowestPriceText: product.lowestPriceText||null, featured:false, hidden:false, outOfStock:false, order:0, addedAt:today };
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

      // ── POST /products/clear-all-notifications ────────────────────────────────
      if (url.pathname === '/products/clear-all-notifications' && request.method === 'POST') {
        try {
          const { products, sha } = await getProductsFile(env);
          await saveProductsFile(products.map(p=>({...p,lowestPriceText:null,outOfStock:false})), sha, 'Dismiss all notifications', env);
          return json({ success: true });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      // ── POST /products/reorder ───────────────────────────────────────────────
      if (url.pathname === '/products/reorder' && request.method === 'POST') {
        try {
          const { orderedIds } = await request.json();
          if (!Array.isArray(orderedIds)) return json({ error: 'orderedIds must be an array' }, 400);
          const { products, sha } = await getProductsFile(env);
          const map = new Map(products.map(p=>[p.id,p]));
          const reordered = orderedIds.map((id,i) => map.has(id) ? {...map.get(id),order:i} : null).filter(Boolean);
          let nextOrder = reordered.length;
          for (const p of products) { if (!orderedIds.includes(p.id)) reordered.push({...p,order:nextOrder++}); }
          await saveProductsFile(reordered, sha, 'Reorder products', env);
          return json({ success: true });
        } catch (e) { return json({ error: e.message }, 502); }
      }

      return await env.ASSETS.fetch(request);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  },

  // ── Cron jobs ─────────────────────────────────────────────────────────────
  async scheduled(event, env, ctx) {
    // Every 10 min: sync IndiaFreeStuff (10 new Amazon deals) + price/OOS check
    if (event.cron === '*/10 * * * *') {
      ctx.waitUntil(
        (async () => {
          try {
            console.log('IndiaFreeStuff sync start');
            const r = await scrapeAndSyncIndiaFreeStuff(env, 10);
            console.log('IndiaFreeStuff sync:', r.message);
          } catch (e) {
            console.error('IndiaFreeStuff sync error:', e.message);
            await saveSyncError('IndiaFreeStuff', e.message, env);
          }
          try {
            console.log('Price check start');
            const r = await checkAndCleanDeals(env);
            console.log('Price check:', r.message);
          } catch (e) {
            console.error('Price check error:', e.message);
          }
        })()
      );
    }

    // Every hour: sync DealsRadar (30 deals) + 1 Amazon deal + badge check
    if (event.cron === '0 * * * *') {
      ctx.waitUntil(
        (async () => {
          try {
            console.log('DealsRadar sync start');
            const r = await scrapeAndSyncDealsRadar(env);
            console.log('DealsRadar sync:', r.message);
          } catch (e) {
            console.error('DealsRadar sync error:', e.message);
            await saveSyncError('DealsRadar', e.message, env);
          }
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
        })()
      );
    }

    // 8 AM IST (2:30 UTC) — morning Amazon deals sweep
    if (event.cron === '30 2 * * *') {
      ctx.waitUntil(
        (async () => {
          try {
            console.log('Amazon Deals morning check start');
            const r = await checkAmazonDeals(env);
            console.log('Amazon Deals morning:', r.message);
          } catch (e) {
            console.error('Amazon Deals morning error:', e.message);
            await saveSyncError('AmazonDeals', e.message, env);
          }
        })()
      );
    }

    // 6 PM IST (12:30 UTC) — evening Amazon deals sweep
    if (event.cron === '30 12 * * *') {
      ctx.waitUntil(
        (async () => {
          try {
            console.log('Amazon Deals evening check start');
            const r = await checkAmazonDeals(env);
            console.log('Amazon Deals evening:', r.message);
          } catch (e) {
            console.error('Amazon Deals evening error:', e.message);
            await saveSyncError('AmazonDeals', e.message, env);
          }
        })()
      );
    }
  },
};
