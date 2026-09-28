/**
 * DealBuster Forwarder - Deal Link Converter & Text Rebrander
 */

// Regex patterns for shorteners and redirectors commonly used in deal channels
const REDIRECT_DOMAINS = [
  'amzn.to', 'link.amazon', 'a.co',
  'bit.ly', 'tinyurl.com', 'cutt.ly', 't.ly', 'shorturl.at',
  'fktr.in', 'fkrt.co', 'fkrt.cc', 'ekaro.in', 'myntr.it',
  'ajiio.in', 'linkredirect.in', 'linksredirect.com', 'clnk.in',
  'mdeal.in', 'deals.dr', 'opnr.app', 'openinapp.co', 'openinapp.link',
  'dealsping.in'
];

/**
 * Extract all URLs from a text string
 */
export function extractUrls(text) {
  if (!text) return [];
  const urlRegex = /(https?:\/\/[^\s<>"'()]+)/gi;
  const matches = text.match(urlRegex) || [];
  return matches
    .map(u => u.replace(/[.,!?]+$/, ''))
    .filter(u => {
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
          if (decoded.startsWith('http') || decoded.includes('amazon') || decoded.includes('flipkart') || decoded.includes('myntra') || decoded.includes('ajio')) {
            currentUrl = decoded;
            continue;
          }
        } catch {}
      }

      const res = await fetch(currentUrl, {
        method: 'HEAD',
        redirect: 'manual',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        signal: AbortSignal.timeout(5000),
      });

      const location = res.headers.get('location');
      if (location) {
        currentUrl = new URL(location, currentUrl).href;
      } else {
        // If HEAD didn't redirect, try GET with manual redirect
        if (res.status >= 300 && res.status < 400) {
          break;
        }
        // If not a redirect, we reached destination
        break;
      }
    } catch {
      // Timeout or network error, return the latest resolved URL
      break;
    }
  }

  // If dealsping.in deal page, extract target store link if not an Amazon ASIN slug
  if (currentUrl.includes('dealsping.in/deals/')) {
    const asinMatch = extractAmazonAsin(currentUrl);
    if (!asinMatch) {
      try {
        const html = await fetch(currentUrl, {
          headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' },
          signal: AbortSignal.timeout(5000),
        }).then(r => r.text());
        const affMatch = html.match(/"affiliateLink"\s*:\s*"([^"]+)"/i) ||
                         html.match(/href="([^"]*(?:amazon\.in|flipkart\.com|myntra\.com|ajio\.com|shopsy\.in)[^"]*)"/i);
        if (affMatch) {
          currentUrl = affMatch[1].replace(/\\u0026/g, '&');
        }
      } catch {}
    }
  }

  return currentUrl;
}

/**
 * Check if a URL is an Amazon link
 */
export function isAmazonUrl(url) {
  if (!url) return false;
  return /(?:^|https?:\/\/|[.\/])(?:amazon\.(?:in|com)|amzn\.to|link\.amazon|a\.co)(?:[/?#]|$)/i.test(url);
}

/**
 * Resolves a DealsPing redirect link to find the underlying Amazon ASIN or destination store URL
 */
export async function resolveDealsPingUrl(url) {
  if (!url) return null;
  try {
    const res = await fetch(url, {
      method: 'GET',
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      },
      signal: AbortSignal.timeout(7000),
    });

    const finalUrl = res.url || '';
    const asin = extractAmazonAsin(finalUrl);
    if (asin) {
      return { resolvedUrl: finalUrl, asin, store: 'amazon' };
    }

    // If finalUrl is a dealsping deal page, inspect HTML for destination link / ASIN
    if (finalUrl.includes('dealsping.in/deals/')) {
      const html = await res.text().catch(() => '');
      const asinMatch = html.match(/(?:dp|gp\/product)\/([A-Z0-9]{10})/i) ||
                        html.match(/-(B0[A-Z0-9]{8,9})/i);
      if (asinMatch) {
        return {
          resolvedUrl: `https://www.amazon.in/dp/${asinMatch[1].toUpperCase()}`,
          asin: asinMatch[1].toUpperCase(),
          store: 'amazon'
        };
      }
      const affMatch = html.match(/"affiliateLink"\s*:\s*"([^"]+)"/i) ||
                       html.match(/href="([^"]*(?:amazon\.in|flipkart\.com|myntra\.com|ajio\.com|shopsy\.in)[^"]*)"/i);
      if (affMatch) {
        const dest = affMatch[1].replace(/\\u0026/g, '&');
        const a = extractAmazonAsin(dest);
        return {
          resolvedUrl: dest,
          asin: a,
          store: a ? 'amazon' : 'other'
        };
      }
    }
  } catch (err) {
    console.warn('⚠️ Error resolving DealsPing link:', err.message);
  }
  return null;
}

/**
 * Extract Amazon ASIN from any URL or path
 */
export function extractAmazonAsin(url) {
  if (!url) return null;
  const m = url.match(/\/(?:dp|gp\/product|ASIN|gp\/aw\/d)\/([A-Z0-9]{10})/i) ||
            url.match(/[?&]asin=([A-Z0-9]{10})/i) ||
            url.match(/link\.amazon\/([A-Z0-9]{10})/i) ||
            url.match(/-(B0[A-Z0-9]{8,9})(?:[/?#]|$)/i);
  return m ? m[1].toUpperCase() : null;
}

/**
 * EarnKaro API converter
 */
export async function convertToEarnKaro(dealUrlOrText, token) {
  if (!token || !dealUrlOrText) return null;
  try {
    const res = await fetch('https://ekaro-api.affiliaters.in/api/converter/public', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token.trim()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        deal: dealUrlOrText,
        convert_option: 'convert_only',
      }),
      signal: AbortSignal.timeout(10000),
    });

    if (res.ok) {
      const data = await res.json();
      if (data?.success === 1 && data?.data) {
        const match = data.data.match(/https?:\/\/[^\s]+/i);
        if (match) return match[0];
      }
    }
  } catch (err) {
    console.warn('⚠️ EarnKaro conversion error:', err.message);
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

export const ALLOWED_STORES = ['amazon', 'flipkart', 'myntra', 'ajio', 'shopsy'];

/**
 * Converts a raw URL to our affiliate link
 */
export async function convertDealUrl(rawUrl, options = {}) {
  const {
    amazonTag = 'dealbuster002-21',
    earnkaroToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YTk0ZTM2Y2ZhNjMxOWMyMmVhMzkyMDkiLCJlYXJua2FybyI6IjEwMjk5MjIiLCJpYXQiOjE3ODgxODg1Mzl9.2XEPFAfOL8X9s7yoCu2aAMKB2-iBZF8g_BuDRXgoB_o',
  } = options;

  // 1. Dedicated resolution for DealsPing links
  if (rawUrl.includes('dealsping.in')) {
    const dp = await resolveDealsPingUrl(rawUrl);
    if (dp?.asin) {
      return {
        originalUrl: rawUrl,
        resolvedUrl: dp.resolvedUrl,
        convertedUrl: buildAmazonUrl(dp.asin, amazonTag),
        store: 'amazon',
        id: `amazon_${dp.asin}`
      };
    } else if (dp?.resolvedUrl && !dp.resolvedUrl.includes('dealsping.in')) {
      return convertDealUrl(dp.resolvedUrl, options);
    }
    // If DealsPing could NOT be resolved to a clean store/Amazon, REJECT IT so competitor links never leak!
    return {
      originalUrl: rawUrl,
      resolvedUrl: rawUrl,
      convertedUrl: null,
      store: 'other',
      id: null
    };
  }

  const resolved = await resolveUrl(rawUrl);

  // If resolved URL ended up on dealsping, resolve via DealsPing helper
  if (resolved.includes('dealsping.in')) {
    const dp = await resolveDealsPingUrl(resolved);
    if (dp?.asin) {
      return {
        originalUrl: rawUrl,
        resolvedUrl: dp.resolvedUrl,
        convertedUrl: buildAmazonUrl(dp.asin, amazonTag),
        store: 'amazon',
        id: `amazon_${dp.asin}`
      };
    } else if (dp?.resolvedUrl && !dp.resolvedUrl.includes('dealsping.in')) {
      return convertDealUrl(dp.resolvedUrl, options);
    }
    return {
      originalUrl: rawUrl,
      resolvedUrl: resolved,
      convertedUrl: null,
      store: 'other',
      id: null
    };
  }

  // 2. Amazon Deal
  if (isAmazonUrl(resolved) || isAmazonUrl(rawUrl)) {
    const asin = extractAmazonAsin(resolved) || extractAmazonAsin(rawUrl);
    if (asin) {
      return {
        originalUrl: rawUrl,
        resolvedUrl: resolved,
        convertedUrl: buildAmazonUrl(asin, amazonTag),
        store: 'amazon',
        id: `amazon_${asin}`
      };
    }
    // Fallback ONLY on genuine Amazon domains
    try {
      const u = new URL(resolved);
      if (/amazon\.(?:in|com)/i.test(u.hostname)) {
        u.searchParams.set('tag', amazonTag);
        return {
          originalUrl: rawUrl,
          resolvedUrl: resolved,
          convertedUrl: u.href,
          store: 'amazon',
          id: null
        };
      }
    } catch {}
    return { originalUrl: rawUrl, resolvedUrl: resolved, convertedUrl: null, store: 'other', id: null };
  }

  // 2. Non-Amazon store (Only Flipkart, Myntra, Ajio, Shopsy are allowed)
  let store = 'other';
  if (/flipkart\.com|fktr\.in|fkrt\.co|fkrt\.cc/i.test(resolved)) store = 'flipkart';
  else if (/myntra\.com|myntr\.it/i.test(resolved)) store = 'myntra';
  else if (/ajio\.com|ajiio\.in/i.test(resolved)) store = 'ajio';
  else if (/shopsy\.in/i.test(resolved)) store = 'shopsy';

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

  // Clean tracking params from non-Amazon URL
  let cleanUrl = resolved;
  try {
    const u = new URL(resolved);
    ['affid', 'affExtParam', 'affExtParam1', 'affExtParam2', 'utm_source', 'utm_medium', 'utm_campaign'].forEach(p => u.searchParams.delete(p));
    cleanUrl = u.href;
  } catch {}

  // Extract canonical product ID for cross-channel deduplication
  let canonicalId = `${store}_${cleanUrl}`;
  if (store === 'flipkart' || store === 'shopsy') {
    const pidMatch = cleanUrl.match(/[?&]pid=([A-Z0-9]{16})/i) || cleanUrl.match(/\/p\/([a-z0-9]{16})/i);
    if (pidMatch) canonicalId = `flipkart_${pidMatch[1]}`;
  } else if (store === 'myntra') {
    const myntraMatch = cleanUrl.match(/\/(\d{6,10})(?:\/buy|[?#]|$)/i);
    if (myntraMatch) canonicalId = `myntra_${myntraMatch[1]}`;
  } else if (store === 'ajio') {
    const ajioMatch = cleanUrl.match(/\/p\/([a-zA-Z0-9_]+)/i) || cleanUrl.match(/\/([0-9]{8,12})/i);
    if (ajioMatch) canonicalId = `ajio_${ajioMatch[1]}`;
  }

  // Convert via EarnKaro API
  const ekaroLink = await convertToEarnKaro(cleanUrl, earnkaroToken);

  return {
    originalUrl: rawUrl,
    resolvedUrl: resolved,
    convertedUrl: ekaroLink || cleanUrl,
    store,
    id: canonicalId
  };
}

/**
 * Formats a DealsPing post into DealBuster's standard channel style:
 *
 * Title
 * ✅Deal Price: ₹...
 * ❌MRP: ₹...
 * Discount: ...% OFF
 * 🏷️ Coupon: ...
 * 🏦 Bank Offer: ...
 *
 * 👉 https://...
 */
export function formatDealsPingPost(text, affLink) {
  const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
  let title = '';
  let dealPrice = '';
  let mrp = '';
  let discount = '';
  let coupon = '';
  let bankOffer = '';

  for (const line of lines) {
    if (line.includes('⚡')) {
      title = line.replace(/^[⚡\s]+/, '').trim();
    } else if (line.startsWith('💰') || line.includes('🔻')) {
      const priceMatch = line.match(/₹[\d,]+/g);
      if (priceMatch && priceMatch.length >= 2) {
        dealPrice = priceMatch[0];
        mrp = priceMatch[1];
      } else if (priceMatch && priceMatch.length === 1) {
        dealPrice = priceMatch[0];
      }
      const discMatch = line.match(/(?:\d+%\s*OFF|\d+%\s*off)/i);
      if (discMatch) discount = discMatch[0].toUpperCase();
    } else if (line.toLowerCase().includes('coupon:')) {
      coupon = line.replace(/^[🏷️\s]+/, '').trim();
    } else if (line.toLowerCase().includes('bank offer:')) {
      bankOffer = line.replace(/^[🏦\s]+/, '').trim();
    }
  }

  if (!title) {
    const candidate = lines.find(l => !l.startsWith('🏷️') && !l.startsWith('💰') && !l.startsWith('🛒') && !l.startsWith('http'));
    if (candidate) title = candidate.replace(/^[⚡\s]+/, '').trim();
  }

  // Only use if we extracted title and dealPrice
  if (title && dealPrice) {
    const out = [];
    out.push(title);
    out.push(`✅Deal Price: ${dealPrice}`);
    if (mrp) out.push(`❌MRP: ${mrp}`);
    if (discount) out.push(`Discount: ${discount}`);
    if (coupon) out.push(`🏷️ ${coupon}`);
    if (bankOffer) out.push(`🏦 ${bankOffer}`);
    out.push('');
    out.push(`👉 ${affLink}`);
    return out.join('\n');
  }

  return null;
}

/**
 * Clean and rebrand message text:
 * - Replace all original URLs with converted affiliate URLs
 * - Strip competitor usernames and channel joins
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
  const urls = extractUrls(text);
  const convertedLinks = [];

  // Convert each URL found in the text
  for (const rawUrl of urls) {
    const result = await convertDealUrl(rawUrl, options);
    convertedLinks.push(result);
    // Replace URL in text
    processed = processed.split(rawUrl).join(result.convertedUrl);
  }

  // Check if this post is from DealsPing (or matches ⚡ and 💰 price structure)
  const isDealsPingFormat = (text.includes('dealsping.in') || (text.includes('⚡') && text.includes('💰')));
  if (isDealsPingFormat && convertedLinks.length > 0) {
    const formatted = formatDealsPingPost(text, convertedLinks[0].convertedUrl);
    if (formatted) {
      processed = formatted;
    }
  }

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

  // Trim trailing whitespace and append our custom footer if provided
  processed = processed.trim();
  if (footer && footer.trim()) {
    processed += `\n\n${footer.trim()}`;
  }

  return {
    text: processed,
    convertedLinks
  };
}
