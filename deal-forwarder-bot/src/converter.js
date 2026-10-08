/**
 * DealBuster Forwarder - Deal Link Converter & Text Rebrander
 */

// Regex patterns for shorteners and redirectors commonly used in deal channels
const REDIRECT_DOMAINS = [
  'amzn.to', 'link.amazon', 'a.co', 'amzn-to.co', 'amzn-to', 'urlgeni.us',
  'bit.ly', 'tinyurl.com', 'cutt.ly', 't.ly', 'shorturl.at',
  'fktr.in', 'fkrt.co', 'fkrt.cc', 'ekaro.in', 'myntr.it',
  'ajiio.in', 'linkredirect.in', 'linksredirect.com', 'clnk.in',
  'mdeal.in', 'deals.dr', 'opnr.app', 'openinapp.co', 'openinapp.link',
  'dealsping.in', 'wishlink.com', 'extrape.com', 'extp.in'
];

/**
 * Extract all URLs from a text string and optional Telegram entities
 */
export function extractUrls(text, entities = []) {
  const urls = new Set();
  if (text) {
    const urlRegex = /(https?:\/\/[^\s<>"'()]+)/gi;
    const matches = text.match(urlRegex) || [];
    for (const u of matches) {
      urls.add(u.replace(/[.,!?]+$/, ''));
    }
  }
  if (Array.isArray(entities)) {
    for (const ent of entities) {
      if (ent?.url && typeof ent.url === 'string') {
        urls.add(ent.url.replace(/[.,!?]+$/, ''));
      }
    }
  }
  return Array.from(urls).filter(u => {
    // Do not convert Telegram, WhatsApp, or Instagram links as affiliate links
    return !/(?:t\.me|telegram\.me|whatsapp\.com|wa\.me|instagram\.com|twitter\.com|x\.com)\//i.test(u);
  });
}

/**
 * Resolve redirects to find the canonical product destination URL
 */
export async function resolveUrl(url, maxHops = 4) {
  let currentUrl = url;

  for (let i = 0; i < maxHops; i++) {
    try {
      // Unpack embedded destination URLs in urlgeni.us links: e.g. https://amzn.urlgeni.us/https://www.amazon.in/...
      const urlgeniMatch = currentUrl.match(/(?:amzn\.)?urlgeni\.us\/(https?:\/\/.+)/i);
      if (urlgeniMatch) {
        currentUrl = urlgeniMatch[1];
        continue;
      }

      const parsed = new URL(currentUrl);
      const isRedirectDomain = REDIRECT_DOMAINS.some(d => parsed.hostname.toLowerCase().includes(d));

      // If it's already a full Amazon or Flipkart product URL with ASIN/PID, no need to follow further
      if (isAmazonUrl(currentUrl) && extractAmazonAsin(currentUrl)) {
        break;
      }

      if (!isRedirectDomain && i > 0) {
        break;
      }

      // Special handling for dl= or url= parameter (used by ekaro, fktr, and aggregators)
      const dlMatch = currentUrl.match(/[?&](?:dl|url)=([^&]+)/i);
      if (dlMatch) {
        try {
          const decoded = decodeURIComponent(dlMatch[1]);
          if (decoded.startsWith('http') || decoded.includes('amazon') || decoded.includes('flipkart') || decoded.includes('myntra') || decoded.includes('ajio') || decoded.includes('shopsy') || decoded.includes('meesho')) {
            currentUrl = decoded;
            continue;
          }
        } catch {}
      }

      let res = await fetch(currentUrl, {
        method: 'HEAD',
        redirect: 'manual',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        signal: AbortSignal.timeout(6000),
      });

      let location = res.headers.get('location');

      // If HEAD did not redirect, try GET with manual redirect (shorteners often require GET)
      if (!location && (res.status === 405 || res.status === 200 || isRedirectDomain)) {
        try {
          const getRes = await fetch(currentUrl, {
            method: 'GET',
            redirect: 'manual',
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
            signal: AbortSignal.timeout(6000),
          });
          location = getRes.headers.get('location');
          if (!location && getRes.status === 200) {
            const html = await getRes.text();
            const metaMatch = html.match(/content=["']\d+;\s*url=([^"']+)["']/i) ||
                              html.match(/window\.location(?:\.href)?\s*=\s*["']([^"']+)["']/i) ||
                              html.match(/location\.replace\(["']([^"']+)["']\)/i) ||
                              html.match(/href=["'](https?:\/\/(?:www\.)?(?:amazon|amzn)[^"']+)["']/i);
            if (metaMatch) {
              location = metaMatch[1];
            }
          }
        } catch {}
      }

      if (location) {
        currentUrl = new URL(location, currentUrl).href;
        // Unpack any embedded URL in the new location
        const innerMatch = currentUrl.match(/(?:amzn\.)?urlgeni\.us\/(https?:\/\/.+)/i);
        if (innerMatch) {
          currentUrl = innerMatch[1];
        }
      } else {
        // If not a redirect, we reached destination
        break;
      }
    } catch {
      // Timeout or network error, return the latest resolved URL
      break;
    }
  }

  return currentUrl;
}

/**
 * Check if a URL is an Amazon link or known Amazon shortener/deep-link
 */
export function isAmazonUrl(url) {
  if (!url) return false;
  return /(?:^|https?:\/\/|[.\/])(?:amazon\.(?:in|com)|amzn\.(?:to|in)|amzn-to\.(?:co|[a-z]+)|amzn-to|amazn\.lt|link\.amazon|a\.co|(?:amzn\.)?urlgeni\.us)(?:[/?#:]|$)/i.test(url);
}

/**
 * Extract Amazon ASIN from any URL or path
 */
export function extractAmazonAsin(url) {
  if (!url) return null;
  const m = url.match(/\/(?:dp|gp\/product|ASIN|gp\/aw\/d)\/([A-Z0-9]{10})/i) ||
            url.match(/[?&]asin=([A-Z0-9]{10})/i) ||
            url.match(/link\.amazon\/([A-Z0-9]{10})/i) ||
            url.match(/-(B0[A-Z0-9]{8,9})(?:[/?#]|$)/i) ||
            url.match(/(?:urlgeni\.us|amzn-to\.co)[^\s]*\/([A-Z0-9]{10})/i);
  return m ? m[1].toUpperCase() : null;
}

/**
 * EarnKaro API converter
 */
export async function convertToEarnKaro(dealUrlOrText, token) {
  const authToken = (token || process.env.EARNKARO_API_TOKEN || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YTk0ZTM2Y2ZhNjMxOWMyMmVhMzkyMDkiLCJlYXJua2FybyI6IjEwMjk5MjIiLCJpYXQiOjE3ODgxODg1Mzl9.2XEPFAfOL8X9s7yoCu2aAMKB2-iBZF8g_BuDRXgoB_o').trim();
  if (!authToken || !dealUrlOrText) return null;

  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const res = await fetch('https://ekaro-api.affiliaters.in/api/converter/public', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${authToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          deal: dealUrlOrText,
          convert_option: 'convert_only',
        }),
        signal: AbortSignal.timeout(12000),
      });

      if (res.ok) {
        const data = await res.json();
        if (data?.success === 1 && data?.data) {
          const match = data.data.match(/https?:\/\/[^\s]+/i);
          if (match) return match[0];
        } else if (data?.data && typeof data.data === 'string' && data.data.includes('could not locate')) {
          // Seller not available on EarnKaro
          return null;
        }
      } else {
        const errText = await res.text().catch(() => '');
        console.warn(`⚠️ EarnKaro API attempt ${attempt} returned HTTP ${res.status}: ${errText.slice(0, 100)}`);
      }
    } catch (err) {
      if (attempt === 2) {
        console.warn('⚠️ EarnKaro conversion error:', err.message);
      }
    }
  }
  return null;
}

/**
 * Build Amazon Affiliate URL
 */
export function buildAmazonUrl(asin, tag = 'dealbuster002-21') {
  return `https://www.amazon.in/dp/${asin}?tag=${tag}`;
}

/**
 * Detects whether deal text represents an Amazon variable discount / "upto" promo
 * Matches "upto", "up to", "upto X% off", "min/minimum X% off", "X% off from/onwards"
 */
export function isAmazonUptoDeal(text) {
  if (!text) return false;
  return /\b(upto|up\s+to)\b/i.test(text) ||
         /\b(?:min|minimum)\s*\d+%\s*off\b/i.test(text) ||
         /\b\d+%\s*off\s*(?:from|onwards|starting)\b/i.test(text);
}

export const ALLOWED_STORES = ['amazon', 'flipkart', 'myntra', 'ajio', 'shopsy', 'meesho'];

/**
 * Build CueLinks Affiliate URL (DealBuster pub_id 312552)
 */
export function buildCueLinksUrl(url, pubId = '312552') {
  if (!url) return null;
  return `https://linksredirect.com/?pub_id=${pubId}&subid=dealbuster&url=${encodeURIComponent(url)}`;
}

/**
 * Extract canonical store and product identifier across stores (Amazon ASIN, Flipkart PID, collections, etc.)
 */
export function extractCanonicalDealId(url) {
  if (!url) return null;

  let targetUrl = url;
  try {
    const m = url.match(/[?&](?:url|dl|target|destination)=([^&]+)/i);
    if (m) {
      const decoded = decodeURIComponent(m[1]);
      if (/https?:\/\//i.test(decoded)) targetUrl = decoded;
    }
  } catch {}

  // 1. Amazon: check both targetUrl and url
  const asin = extractAmazonAsin(targetUrl) || extractAmazonAsin(url);
  if (asin) {
    return { store: 'amazon', asin: asin.toUpperCase(), id: `amazon_${asin.toUpperCase()}` };
  }

  // 2. Flipkart / Shopsy:
  if (/flipkart\.com|dl\.flipkart\.com|fktr\.in|fkrt\.(?:co|cc)|shopsy\.in/i.test(targetUrl) ||
      /flipkart\.com|dl\.flipkart\.com|fktr\.in|fkrt\.(?:co|cc)|shopsy\.in/i.test(url)) {
    const pidMatch = targetUrl.match(/[?&]pid=([A-Z0-9]{16})/i) ||
                     url.match(/[?&]pid=([A-Z0-9]{16})/i) ||
                     targetUrl.match(/\/p\/itm([a-z0-9]{10,16})/i) ||
                     url.match(/\/p\/itm([a-z0-9]{10,16})/i) ||
                     targetUrl.match(/\/p\/([a-z0-9]{16})/i) ||
                     url.match(/\/p\/([a-z0-9]{16})/i);
    if (pidMatch) {
      const pid = pidMatch[1].toUpperCase();
      return { store: 'flipkart', pid, id: `flipkart_${pid}` };
    }

    // Collection / Brand / Curated list / Search handling across channels
    const brandMatch = targetUrl.match(/([a-z0-9-]+~brand)/i) || url.match(/([a-z0-9-]+~brand)/i);
    const sidMatch = targetUrl.match(/[?&]sid=([a-z0-9,]+)/i) || url.match(/[?&]sid=([a-z0-9,]+)/i);
    if (brandMatch) {
      const brand = brandMatch[1].toLowerCase();
      const sid = sidMatch ? `_${sidMatch[1].toLowerCase()}` : '';
      return { store: 'flipkart', collId: `${brand}${sid}`, id: `flipkart_coll_${brand}${sid}` };
    }

    const csMatch = targetUrl.match(/~cs-([a-z0-9]+)/i) || url.match(/~cs-([a-z0-9]+)/i);
    if (csMatch) {
      const sid = sidMatch ? `_${sidMatch[1].toLowerCase()}` : '';
      return { store: 'flipkart', collId: csMatch[1].toLowerCase(), id: `flipkart_coll_${csMatch[1].toLowerCase()}${sid}` };
    }

    const qMatch = targetUrl.match(/[?&]q=([^&]+)/i) || url.match(/[?&]q=([^&]+)/i);
    if (qMatch) {
      const q = decodeURIComponent(qMatch[1]).toLowerCase().replace(/[^a-z0-9]/g, '');
      if (q.length >= 3) {
        return { store: 'flipkart', q, id: `flipkart_search_${q}` };
      }
    }
  }

  // 3. Myntra:
  if (/myntra\.com|myntr\.(?:it|in)/i.test(targetUrl) || /myntra\.com|myntr\.(?:it|in)/i.test(url)) {
    const myntraMatch = targetUrl.match(/\/(\d{5,12})(?:\/buy|[?#]|$)/i) ||
                        url.match(/\/(\d{5,12})(?:\/buy|[?#]|$)/i) ||
                        targetUrl.match(/[?&](?:productId|styleId)=(\d{5,12})/i);
    if (myntraMatch) {
      return { store: 'myntra', pid: myntraMatch[1], id: `myntra_${myntraMatch[1]}` };
    }

    const myntraBrand = targetUrl.match(/myntra\.com\/([a-z0-9-]+)(?:[/?#]|$)/i) || url.match(/myntra\.com\/([a-z0-9-]+)(?:[/?#]|$)/i);
    if (myntraBrand && !['gateway', 'checkout', 'login', 'shop'].includes(myntraBrand[1].toLowerCase())) {
      return { store: 'myntra', id: `myntra_coll_${myntraBrand[1].toLowerCase()}` };
    }
  }

  // 4. Ajio:
  if (/ajio\.com|ajiio\.(?:in|co)/i.test(targetUrl) || /ajio\.com|ajiio\.(?:in|co)/i.test(url)) {
    const ajioMatch = targetUrl.match(/\/p\/([a-zA-Z0-9_]+)/i) ||
                      url.match(/\/p\/([a-zA-Z0-9_]+)/i) ||
                      targetUrl.match(/\/([0-9]{8,14})(?:[/?#]|$)/i);
    if (ajioMatch) {
      return { store: 'ajio', pid: ajioMatch[1], id: `ajio_${ajioMatch[1]}` };
    }

    const ajioColl = targetUrl.match(/ajio\.com\/(?:s|b)\/([a-z0-9-]+)/i) || url.match(/ajio\.com\/(?:s|b)\/([a-z0-9-]+)/i);
    if (ajioColl) {
      return { store: 'ajio', id: `ajio_coll_${ajioColl[1].toLowerCase()}` };
    }
  }

  // 5. Meesho:
  if (/meesho\.com/i.test(targetUrl) || /meesho\.com/i.test(url)) {
    const meeshoMatch = targetUrl.match(/\/p\/([a-zA-Z0-9]+)/i) ||
                        targetUrl.match(/\/product\/([a-zA-Z0-9]+)/i);
    if (meeshoMatch) {
      return { store: 'meesho', pid: meeshoMatch[1], id: `meesho_${meeshoMatch[1]}` };
    }
  }

  return null;
}

/**
 * Normalizes deal titles to a canonical product/brand representation
 * Strips promotional fluff, percentages, prices, hype buzzwords, and store names
 */
export function normalizeDealTitle(text) {
  if (!text || typeof text !== 'string') return '';

  // 1. Split lines and find the first line containing the product/deal name
  const lines = text
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(Boolean);

  let candidateLine = '';
  for (const line of lines) {
    // Skip lines that are only URLs
    if (/^https?:\/\//i.test(line)) continue;
    // Skip lines that are only coupon codes
    if (/^(?:use\s*coupon|coupon\s*code|code|apply\s*code)\s*[:\-]/i.test(line)) continue;
    // Skip call-to-action lines
    if (/^(?:👉|🔗|🛒|🛍️)?\s*(?:buy|shop|check|link|order|grab|visit)\s*(?:here|now|link)?\s*[:\-]?\s*https?:\/\//i.test(line)) continue;
    // Skip lines with only emojis or tiny tags (< 4 characters)
    const withoutEmojis = line.replace(/[\p{Emoji}\p{Symbol}]/gu, '').trim();
    if (withoutEmojis.length < 4) continue;
    // Skip pure discount/hype lines like "🔥 80% OFF 🔥" or "LOOT OF THE DAY"
    if (/^(?:🔥|⚡|💥|✨|🚨|📢|‼️|\s)*(?:loot|deal|deals|hot|mega|super|huge|hurry|lowest|special|offer|sale|discounts?|flat\s*\d+%\s*off|upto\s*\d+%\s*off)*(?:🔥|⚡|💥|✨|🚨|📢|‼️|\s)*$/i.test(withoutEmojis)) continue;

    candidateLine = line;
    break;
  }

  if (!candidateLine) {
    candidateLine = lines[0] || '';
  }

  // 2. Remove HTML tags, markdown formatting, and URLs
  let cleaned = candidateLine
    .replace(/<[^>]+>/g, ' ')
    .replace(/[*_~`]/g, ' ')
    .replace(/https?:\/\/[^\s]+/gi, ' ');

  // 3. Remove discount expressions:
  // e.g. "at minimum 68% Discount", "min 70% off", "upto 65% off", "flat 50% off", "extra 10% off", "68% off", "68% discount"
  cleaned = cleaned
    .replace(/\b(?:at\s*)?(?:min|minimum|upto|up\s+to|flat|extra|save|off|discount)\s*\d+%\s*(?:off|discount|from|onwards)?(?:\s+(?:on|for))?\b/gi, ' ')
    .replace(/\bat\s*(?:min|minimum)?\s*\d+%\s*(?:off|discount)?(?:\s+(?:on|for))?\b/gi, ' ')
    .replace(/\b\d+%\s*(?:off|discount|from|onwards)(?:\s+(?:on|for))?\b/gi, ' ')
    .replace(/\b\d+%\b/g, ' ');

  // 4. Remove price expressions:
  // e.g. "at ₹1,299", "under 599", "@ ₹999", "just 499", "starting @ ₹199", "price ₹1,499", "mrp ₹4,999"
  cleaned = cleaned
    .replace(/\b(?:under|@|at|just|starting\s*(?:at|@)?|price|deal\s*price|now\s*at|loot\s*at|mrp|worth)\s*₹?\s*[\d,]+(?:\s*\/\-)?\b/gi, ' ')
    .replace(/₹\s*[\d,]+(?:\s*\/\-)?/g, ' ')
    .replace(/\brs\.?\s*[\d,]+/gi, ' ');

  // 5. Remove promotional buzzwords / tags:
  cleaned = cleaned
    .replace(/\b(?:super\s*loot|mega\s*loot|loot\s*deal|hot\s*deal|loot|deals?|mega|super|crazy|biggest|best|lowest|price\s*drop|drop|sales?|offers?|grab|fast|hurry|special|bbd|gif|diwali|festive|lightning|flash|live|back\s*in\s*stock|restocked?|coupons?|free|steal|unbelievable)\b/gi, ' ');

  // 6. Remove store mentions:
  cleaned = cleaned
    .replace(/\b(?:on\s+)?(?:amazon|flipkart|myntra|ajio|shopsy|meesho|tatacliq|nykaa)\b/gi, ' ');

  // 7. Normalize plural forms for fashion/products:
  cleaned = cleaned
    .replace(/\bmens\b/gi, 'men')
    .replace(/\bwomens\b/gi, 'women')
    .replace(/\bshoes\b/gi, 'shoe')
    .replace(/\bshirts\b/gi, 'shirt')
    .replace(/\btshirts\b/gi, 'tshirt');

  // 8. Replace all non-alphanumeric characters with space
  cleaned = cleaned.toLowerCase().replace(/[^a-z0-9\s]/g, ' ');

  // 9. Strip leading prepositions (e.g. "on new balance", "for men")
  cleaned = cleaned.replace(/^\s*(?:on|for|at|in|with)\s+/gi, ' ');

  // 10. Collapse multiple spaces and trim
  return cleaned.replace(/\s+/g, ' ').trim();
}

/**
 * Calculates similarity between two normalized deal titles (0.0 to 1.0)
 * Uses token Jaccard similarity and containment
 */
export function calculateTitleSimilarity(normA, normB) {
  if (!normA || !normB) return 0;
  if (normA === normB) return 1.0;

  const wordsA = normA.split(/\s+/).filter(w => w.length >= 2);
  const wordsB = normB.split(/\s+/).filter(w => w.length >= 2);
  if (wordsA.length === 0 || wordsB.length === 0) return 0;

  const setA = new Set(wordsA);
  const setB = new Set(wordsB);

  let common = 0;
  for (const w of setA) {
    if (setB.has(w)) common++;
  }

  // Jaccard similarity
  const union = new Set([...setA, ...setB]).size;
  const jaccard = union > 0 ? common / union : 0;

  // Containment similarity (e.g. all words of the shorter title are present in the longer title)
  const minSize = Math.min(setA.size, setB.size);
  const containment = minSize > 0 ? common / minSize : 0;

  if (common >= 3 && (jaccard >= 0.70 || containment >= 0.85)) {
    return Math.max(jaccard, containment);
  }

  return jaccard;
}

/**
 * Converts a raw URL to our affiliate link
 */
export async function convertDealUrl(rawUrl, options = {}) {
  const {
    amazonTag = 'dealbuster002-21',
    earnkaroToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YTk0ZTM2Y2ZhNjMxOWMyMmVhMzkyMDkiLCJlYXJua2FybyI6IjEwMjk5MjIiLCJpYXQiOjE3ODgxODg1Mzl9.2XEPFAfOL8X9s7yoCu2aAMKB2-iBZF8g_BuDRXgoB_o',
  } = options;

  // 1. Reject DealsPing deal links
  if (rawUrl.includes('dealsping.in')) {
    return {
      originalUrl: rawUrl,
      resolvedUrl: rawUrl,
      convertedUrl: null,
      store: 'other',
      id: null
    };
  }

  const resolved = await resolveUrl(rawUrl);

  if (resolved.includes('dealsping.in')) {
    return {
      originalUrl: rawUrl,
      resolvedUrl: resolved,
      convertedUrl: null,
      store: 'other',
      id: null
    };
  }

  // 2. Extract canonical deal identity across resolved and raw URL
  const canonical = extractCanonicalDealId(resolved) || extractCanonicalDealId(rawUrl);

  // 3. Amazon Deal Handling
  if (isAmazonUrl(resolved) || isAmazonUrl(rawUrl) || canonical?.store === 'amazon') {
    const asin = canonical?.asin || extractAmazonAsin(resolved) || extractAmazonAsin(rawUrl);
    if (asin) {
      return {
        originalUrl: rawUrl,
        resolvedUrl: resolved,
        convertedUrl: buildAmazonUrl(asin, amazonTag),
        store: 'amazon',
        asin,
        id: `amazon_${asin}`
      };
    }
    // Fallback ONLY on genuine Amazon domains (unwrapping urlgeni if present)
    try {
      let finalResolved = resolved;
      const emb = resolved.match(/(?:amzn\.)?urlgeni\.us\/(https?:\/\/.+)/i);
      if (emb) finalResolved = emb[1];

      const u = new URL(finalResolved);
      if (/amazon\.(?:in|com)/i.test(u.hostname)) {
        let converted = finalResolved.replace(/\|/g, '%7C');
        if (/[?&]tag=[^&]+/i.test(converted)) {
          converted = converted.replace(/([?&])tag=[^&]+/i, (match, prefix) => `${prefix}tag=${amazonTag}`);
        } else {
          const sep = converted.includes('?') ? '&' : '?';
          converted = `${converted}${sep}tag=${amazonTag}`;
        }

        const searchKey = u.searchParams.get('hidden-keywords') || u.searchParams.get('k') || u.searchParams.get('node') || u.pathname;
        const promoId = searchKey ? `amazon_search_${searchKey.replace(/[^a-zA-Z0-9]/g, '').slice(0, 32)}` : null;

        return {
          originalUrl: rawUrl,
          resolvedUrl: finalResolved,
          convertedUrl: converted,
          store: 'amazon',
          id: promoId
        };
      }
    } catch {}
    return { originalUrl: rawUrl, resolvedUrl: resolved, convertedUrl: null, store: 'other', id: null };
  }

  // If resolved URL is an intermediary tracker wrapping an inner store URL, extract clean store URL
  const innerStoreMatch = resolved.match(/[?&](?:url|dl|target|destination)=([^&]+)/i);
  if (innerStoreMatch) {
    try {
      const decoded = decodeURIComponent(innerStoreMatch[1]);
      if (/https?:\/\/[^\s]*(?:flipkart\.com|myntra\.com|ajio\.com|shopsy\.in|meesho\.com|amazon\.)/i.test(decoded)) {
        resolved = decoded;
      }
    } catch {}
  }

  // 4. Non-Amazon store detection
  let store = canonical?.store || 'other';
  if (store === 'other') {
    if (/flipkart\.com|dl\.flipkart\.com|fktr\.in|fkrt\.co|fkrt\.cc/i.test(resolved)) store = 'flipkart';
    else if (/myntra\.com|myntr\.it|myntr\.in/i.test(resolved)) store = 'myntra';
    else if (/ajio\.com|ajiio\.in|ajiio\.co/i.test(resolved)) store = 'ajio';
    else if (/shopsy\.in/i.test(resolved)) store = 'shopsy';
    else if (/meesho\.com/i.test(resolved)) store = 'meesho';
  }

  // If not one of our allowed stores, do not convert
  if (store === 'other') {
    return {
      originalUrl: rawUrl,
      resolvedUrl: resolved,
      convertedUrl: rawUrl,
      store: 'other',
      id: null
    };
  }

  // Clean tracking and competitor affiliate params from non-Amazon URL
  let cleanUrl = resolved;
  try {
    const u = new URL(resolved);
    [
      'affid', 'affExtParam', 'affExtParam1', 'affExtParam2',
      'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
      'af_siteid', 'af_sub_siteid', 'c', 'tag', 'subid', 'pub_id',
      'pwsvid', 'cmpid', 'src'
    ].forEach(p => u.searchParams.delete(p));
    cleanUrl = u.href;
  } catch {}

  // For Flipkart: also prepare normalized standard web URL if it was an app deep-link
  let cleanWebUrl = cleanUrl;
  if (/dl\.flipkart\.com\/dl\//i.test(cleanUrl)) {
    cleanWebUrl = cleanUrl.replace(/dl\.flipkart\.com\/dl\//i, 'www.flipkart.com/');
  }

  // Always use canonical ID if found; fallback to cleaned store URL
  const canonicalId = canonical?.id || `${store}_${cleanUrl}`;

  // 5. Convert via EarnKaro API (primary)
  let ekaroLink = await convertToEarnKaro(cleanUrl, earnkaroToken);
  if (!ekaroLink && cleanWebUrl !== cleanUrl) {
    ekaroLink = await convertToEarnKaro(cleanWebUrl, earnkaroToken);
  }
  if (!ekaroLink && cleanUrl !== rawUrl) {
    ekaroLink = await convertToEarnKaro(rawUrl, earnkaroToken);
  }

  // CueLinks is ONLY permitted for stores EarnKaro does not support (e.g. Meesho).
  // For Flipkart, Myntra, Ajio, and Shopsy, ONLY EarnKaro shortlinks are allowed per user rules.
  const cuelinksPubId = options.cuelinksPubId || '312552';
  const finalAffiliateUrl = ekaroLink || (store === 'meesho' ? buildCueLinksUrl(cleanUrl, cuelinksPubId) : null);

  return {
    originalUrl: rawUrl,
    resolvedUrl: resolved,
    convertedUrl: finalAffiliateUrl,
    store,
    pid: canonical?.pid || null,
    id: canonicalId
  };
}

export function escHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}


/**
 * Clean and rebrand message text:
 * - Replace all original URLs with converted affiliate URLs
 * - Strip competitor usernames and channel joins
 * - Embed links that take >4 lines into "👉 Check Now" buttons
 * - Format into DealBuster channel style
 */
export async function processMessageText(text, options = {}) {
  if (!text) return { text: '', convertedLinks: [] };

  const {
    myChannel = '@dealbusterindia',
    footer = '',
    removeCompetitorMentions = true
  } = options;

  let processed = text;
  const urls = extractUrls(text, options.entities);
  const convertedLinks = [];

  // Convert each URL found in the text
  for (const rawUrl of urls) {
    const result = await convertDealUrl(rawUrl, options);
    convertedLinks.push(result);
  }

    // Replace raw URLs with converted affiliate URLs, embedding links that wrap > 4 lines (length > 75) into "👉 Check Now" buttons
    const placeholders = [];
    convertedLinks.forEach((l, idx) => {
      const rawUrl = l.originalUrl;
      const affUrl = l.convertedUrl;
      const isAmazon = (l.store === 'amazon') || isAmazonUrl(affUrl) || isAmazonUrl(rawUrl);
      const isLongLink = Boolean(affUrl && (affUrl.length > 60 || (isAmazon && (convertedLinks.length > 1 || /\/s\?|\/b\?|\/gp\/browse/i.test(affUrl)))));
      const placeholder = `%%DBLINK${idx}%%`;

      // If the link is long and preceded by a decorative hand/link emoji (e.g. 🔗, 👉, 👇, 🛍️),
      // absorb that emoji into the placeholder so we don't end up with "🔗 👉 Check Now"
      const urlIndex = processed.indexOf(rawUrl);
      if (isLongLink && urlIndex > 0) {
        const prefix = processed.slice(Math.max(0, urlIndex - 6), urlIndex);
        const decorMatch = prefix.match(/(?:🔗|👉|👇|☝️|👆|🛍️|🛒)\s*$/);
        if (decorMatch) {
          processed = processed.slice(0, urlIndex - decorMatch[0].length) + placeholder + processed.slice(urlIndex + rawUrl.length);
          placeholders.push({ placeholder, affUrl, isLongLink });
          return;
        }
      }

      processed = processed.split(rawUrl).join(placeholder);
      placeholders.push({ placeholder, affUrl, isLongLink });
    });

    if (removeCompetitorMentions) {
      const safeChannelName = myChannel.replace(/^@/, '');
      const channelRegex = new RegExp(`https?:\\/\\/(?:t\\.me|telegram\\.me)\\/(?!${safeChannelName}\\b)[a-zA-Z0-9_+/]+`, 'gi');
      const mentionRegex = new RegExp(`(^|\\s)@(?!${safeChannelName}\\b)[a-zA-Z0-9_]+`, 'gi');

      // 1. Remove competitor Telegram channel links
      processed = processed.replace(channelRegex, '');

      // 2. Remove competitor mentions
      processed = processed.replace(mentionRegex, '$1');

      // 3. Remove hashtags (e.g. #Beauty, #Amazon, #Home)
      processed = processed.replace(/(^|\s)#[a-zA-Z0-9_]+/g, '');

      // 4. Remove promotional lines & channel signoffs
      const lines = processed.split('\n');
      const cleanedLines = lines.filter(line => {
        const l = line.toLowerCase().trim();
        if (!l) return true; // keep spacing
        if (/(?:join|subscribe|follow).*?(?:channel|group|telegram|loot|whatsapp|deals?|more|fast)/i.test(l)) {
          return false;
        }
        if (/shared via|posted by|credit:|credits:|forwarded from/i.test(l)) {
          return false;
        }
        // Remove lines that are now empty or just whitespace/punctuation
        if (/^[\s.,!?:;*~_-]+$/.test(l)) {
          return false;
        }
        return true;
      });

      processed = cleanedLines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
    }

    // Escape HTML in the surrounding message text so special chars don't break Telegram HTML parser
    processed = escHtml(processed);

    // Replace placeholders with clean HTML
    placeholders.forEach(({ placeholder, affUrl, isLongLink }) => {
      const rendered = isLongLink
        ? `<a href="${escHtml(affUrl)}">👉 Check Now</a>`
        : escHtml(affUrl);
      processed = processed.split(placeholder).join(rendered);
    });

  // Trim trailing whitespace and append our custom footer if provided
  processed = processed.trim();
  if (footer && footer.trim()) {
    processed += `\n\n${escHtml(footer.trim())}`;
  }

  return {
    text: processed,
    convertedLinks
  };
}
