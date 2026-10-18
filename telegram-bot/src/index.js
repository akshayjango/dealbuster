const ADMIN_API = 'https://dealbuster-admin-api.vakshay083.workers.dev';
const TG_CHANNEL = '@dealbusterindia';
const DEFAULT_AMZ_TAG = 'dealbuster002-21';
const EARNKARO_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YTk0ZTM2Y2ZhNjMxOWMyMmVhMzkyMDkiLCJlYXJua2FybyI6IjEwMjk5MjIiLCJpYXQiOjE3ODgxODg1Mzl9.2XEPFAfOL8X9s7yoCu2aAMKB2-iBZF8g_BuDRXgoB_o';

function tg(token, method, body) {
  return fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

async function tgEdit(token, chatId, msgId, text, isPhoto = false) {
  const method = isPhoto ? 'editMessageCaption' : 'editMessageText';
  const param = isPhoto ? 'caption' : 'text';
  let r = await tg(token, method, { chat_id: chatId, message_id: msgId, [param]: text, parse_mode: 'HTML' });
  if (!r.ok && isPhoto) {
    await tg(token, 'editMessageText', { chat_id: chatId, message_id: msgId, text, parse_mode: 'HTML' });
  }
}

function escHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function extractUrls(text, entities = []) {
  const urls = new Set();
  for (const ent of entities) {
    if (ent.type === 'text_link' && ent.url) {
      urls.add(ent.url.replace(/[.,!?]+$/, ''));
    } else if (ent.type === 'url' && text) {
      const raw = text.slice(ent.offset, ent.offset + ent.length);
      if (raw) urls.add(raw.replace(/[.,!?]+$/, ''));
    }
  }
  if (text) {
    const matches = text.match(/https?:\/\/[^\s<>"'()]+/gi) || [];
    for (const u of matches) urls.add(u.replace(/[.,!?]+$/, ''));
  }
  return Array.from(urls).filter(u => !/(?:t\.me|telegram\.me|whatsapp\.com|wa\.me|instagram\.com|twitter\.com|x\.com)\//i.test(u));
}

async function resolveCanonicalUrl(inputUrl) {
  if (!inputUrl) return inputUrl;
  let currentUrl = inputUrl.trim();
  const dlMatch = currentUrl.match(/[?&](?:dl|url)=([^&]+)/i);
  if (dlMatch) {
    try {
      const decoded = decodeURIComponent(dlMatch[1]);
      if (decoded.startsWith('http')) currentUrl = decoded;
    } catch {}
  }
  const isRedirect = /fktr\.in|fkrt\.co|fkrt\.cc|ekaro\.in|bit\.ly|tinyurl\.com|myntr\.it|ajiio\.in|linkredirect\.in|linksredirect\.com|amzn\.to|link\.amazon|a\.co/i.test(currentUrl);
  if (isRedirect) {
    try {
      let hops = 0;
      while (hops < 4) {
        hops++;
        const res = await fetch(currentUrl, { method: 'HEAD', redirect: 'manual' });
        const loc = res.headers.get('location');
        if (loc) {
          currentUrl = new URL(loc, currentUrl).href;
          const locDl = currentUrl.match(/[?&](?:dl|url)=([^&]+)/i);
          if (locDl) {
            try {
              const dec = decodeURIComponent(locDl[1]);
              if (dec.startsWith('http')) currentUrl = dec;
            } catch {}
          }
        } else {
          break;
        }
      }
    } catch {}
  }
  return currentUrl;
}

function detectStore(url) {
  if (!url) return 'other';
  if (/amazon\.(?:in|com)|amzn\.(?:to|in)|link\.amazon|a\.co/i.test(url)) return 'amazon';
  if (/flipkart\.com|dl\.flipkart\.com|fktr\.in|fkrt\.(?:co|cc)/i.test(url)) return 'flipkart';
  if (/myntra\.com|myntr\.it|myntr\.in/i.test(url)) return 'myntra';
  if (/ajio\.com|ajiio\.(?:in|co)/i.test(url)) return 'ajio';
  if (/shopsy\.in|bitli\.in/i.test(url)) return 'shopsy';
  if (/meesho\.com/i.test(url)) return 'meesho';
  if (/tatacliq\.com/i.test(url)) return 'tatacliq';
  if (/nykaa\.com/i.test(url)) return 'nykaa';
  return 'other';
}

function formatStoreName(store) {
  const map = {
    amazon: 'Amazon',
    flipkart: 'Flipkart',
    myntra: 'Myntra',
    ajio: 'Ajio',
    shopsy: 'Shopsy',
    meesho: 'Meesho',
    tatacliq: 'Tata CLiQ',
    nykaa: 'Nykaa',
    other: 'Online'
  };
  return map[store] || 'Online';
}

function buildCueLinks(url, pubId = '312552') {
  return `https://linksredirect.com/?pub_id=${pubId}&subid=dealbuster&url=${encodeURIComponent(url)}`;
}

async function convertToEarnKaro(dealUrlOrText, token) {
  const authToken = token || EARNKARO_TOKEN;
  if (!authToken || !dealUrlOrText) return null;
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
    });
    if (res.ok) {
      const data = await res.json();
      if (data?.success === 1 && data?.data) {
        const m = data.data.match(/https?:\/\/[^\s]+/i);
        return m ? m[0] : data.data;
      }
    }
  } catch {}
  return null;
}

function extractDealTitleFromText(text) {
  if (!text || typeof text !== 'string') return '';
  const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  let candidate = '';
  for (const line of lines) {
    if (/^https?:\/\//i.test(line)) continue;
    if (/^(?:use\s*coupon|coupon\s*code|code|apply\s*code)\s*[:\-]/i.test(line)) continue;
    if (/^(?:👉|🔗|🛒|🛍️)?\s*(?:buy|shop|check|link|order|grab|visit)\s*(?:here|now|link)?\s*[:\-]?\s*https?:\/\//i.test(line)) continue;
    if (/(?:deal\s*price|mrp|price|discount)\s*[:\-]/i.test(line)) continue;
    const withoutEmojis = line.replace(/[\p{Emoji}\p{Symbol}]/gu, '').trim();
    if (withoutEmojis.length < 4) continue;
    if (/^(?:loot|deal|deals|hot|mega|super|huge|hurry|lowest|special|offer|sale|flat\s*\d+%\s*off|upto\s*\d+%\s*off)+$/i.test(withoutEmojis.replace(/\s+/g, ''))) continue;
    candidate = line;
    break;
  }
  if (!candidate) candidate = lines[0] || '';
  let cleaned = candidate
    .replace(/<[^>]+>/g, ' ')
    .replace(/[*_~`]/g, ' ')
    .replace(/https?:\/\/[^\s]+/gi, ' ')
    .replace(/\b(?:at\s*)?(?:min|minimum|upto|up\s+to|flat|extra|save|off|discount)\s*\d+%\s*(?:off|discount|from|onwards)?(?:\s+(?:on|for))?\b/gi, ' ')
    .replace(/\b\d+%\s*(?:off|discount)?\b/gi, ' ')
    .replace(/(?:deal\s*price|mrp|price)\s*[:\-–—]?\s*(?:₹|Rs\.?|INR)?\s*[\d,]+/gi, ' ')
    .replace(/(?:@|at|just|only)\s*(?:₹|Rs\.?|INR)\s*[\d,]+/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned;
}

function extractDealDetailsFromText(text) {
  let dealPrice = '';
  let mrp = '';
  let discount = '';

  if (!text) return { dealPrice, mrp, discount };

  const mrpM = text.match(/(?:~~|<s>|<strike>)[₹\s]*([0-9,]+)(?:~~|<\/s>|<\/strike>)/i) ||
               text.match(/(?:MRP|M\.R\.P\.?|Original\s*Price|Actual\s*Price|List\s*Price)\s*[:\-–—]?\s*(?:₹|Rs\.?|INR)?\s*([0-9,]+)/i);
  if (mrpM) {
    const val = parseInt(mrpM[1].replace(/,/g, ''), 10);
    if (val > 0 && val < 10000000) mrp = `₹${val.toLocaleString('en-IN')}`;
  }

  const priceM = text.match(/(?:Deal\s*Price|Special\s*Price|Offer\s*Price|Selling\s*Price|Effective\s*Price|Price|Now|Sale\s*Price)\s*[:\-–—@]?\s*(?:₹|Rs\.?|INR)?\s*([0-9,]+)/i) ||
                 text.match(/(?:@|at|just|only)\s*(?:₹|Rs\.?|INR)\s*([0-9,]+)/i) ||
                 text.match(/(?:₹|Rs\.?)\s*([0-9,]+)/i);
  if (priceM) {
    const val = parseInt(priceM[1].replace(/,/g, ''), 10);
    if (val > 0 && val < 10000000) {
      const formatted = `₹${val.toLocaleString('en-IN')}`;
      if (formatted !== mrp) {
        dealPrice = formatted;
      }
    }
  }

  const discM = text.match(/([1-9][0-9]?)\s*%\s*(?:off|discount)?/i);
  if (discM) {
    discount = `${discM[1]}% OFF`;
  } else if (dealPrice && mrp) {
    const pVal = parseInt(dealPrice.replace(/[^\d]/g, ''), 10);
    const mVal = parseInt(mrp.replace(/[^\d]/g, ''), 10);
    if (mVal > pVal && pVal > 0) {
      discount = `-${Math.round((1 - pVal / mVal) * 100)}%`;
    }
  }

  return { dealPrice, mrp, discount };
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return new Response('ok');

    let update;
    try { update = await request.json(); } catch { return new Response('ok'); }

    const token = env.TELEGRAM_BOT_TOKEN;

    // ── Callback query (Action Buttons) ───────────────────────────────────────
    if (update.callback_query) {
      const cb = update.callback_query;
      const chatId = String(cb.message.chat.id);
      const msgId = cb.message.message_id;
      const data = cb.data;
      const isPhoto = Boolean(cb.message?.photo);

      await tg(token, 'answerCallbackQuery', { callback_query_id: cb.id });

      if (data === 'cancel') {
        await tgEdit(token, chatId, msgId, '❌ Cancelled.', isPhoto);
        return new Response('ok');
      }

      const match = data.match(/^(?:publish:|pub_(site|chan|both):)(.+)$/);
      if (match) {
        const action = match[1] || 'site';
        const key = match[2];

        let pending;
        try { pending = await env.KV.get(key, 'json'); } catch {}

        if (!pending || !pending.product) {
          await tgEdit(token, chatId, msgId, '⏱️ Session expired. Please forward the deal again.', isPhoto);
          return new Response('ok');
        }

        const { product, channelText, photoId } = pending;
        const title = product.title || 'Deal';
        const price = product.price || '';
        const mrp = product.mrp || '';
        const disc = product.disc || '';

        try {
          let publishedSite = false;
          let postedChan = false;

          // ── 1. Publish to Site ──
          if (action === 'site' || action === 'both') {
            const resp = await fetch(`${ADMIN_API}/products`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'X-Admin-Password': env.ADMIN_PASSWORD },
              body: JSON.stringify(pending),
            });
            const result = await resp.json().catch(() => ({}));
            if (result.success) publishedSite = true;
          }

          // ── 2. Post to Channel ──
          if (action === 'chan' || action === 'both') {
            const textToSend = channelText || `${title}\n${price}  ~~${mrp}~~  ${disc}\n\n👉 ${product.link}`;
            if (photoId) {
              await tg(token, 'sendPhoto', {
                chat_id: TG_CHANNEL,
                photo: photoId,
                caption: textToSend,
                parse_mode: 'HTML',
                disable_notification: true
              });
            } else if (product.image && !product.image.includes('dealbuster_icon')) {
              await tg(token, 'sendPhoto', {
                chat_id: TG_CHANNEL,
                photo: product.image,
                caption: textToSend,
                parse_mode: 'HTML',
                disable_notification: true
              });
            } else {
              await tg(token, 'sendMessage', {
                chat_id: TG_CHANNEL,
                text: textToSend,
                parse_mode: 'HTML',
                disable_notification: true,
                disable_web_page_preview: true
              });
            }

            // Sync with admin-api DO ledger
            try {
              await fetch(`${ADMIN_API}/tg-posted/claim`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ items: [{ id: product.id || String(Date.now()), asin: product.asin || null }] }),
              });
            } catch {}
            postedChan = true;
          }

          await env.KV.delete(key).catch(() => {});

          let successMsg = '';
          if (publishedSite && postedChan) {
            successMsg = `🚀 <b>Published to Both!</b>\n\n<b>${escHtml(title)}</b>\n${price ? `Price: <b>${escHtml(price)}</b>` : ''}${mrp ? `  <s>${escHtml(mrp)}</s>` : ''}${disc ? `  (<b>${escHtml(disc)}</b>)` : ''}\n\n✅ Live on dealbuster.in & posted to @dealbusterindia!`;
          } else if (publishedSite) {
            successMsg = `🌐 <b>Published to Site!</b>\n\n<b>${escHtml(title)}</b>\n${price ? `Price: <b>${escHtml(price)}</b>` : ''}${mrp ? `  <s>${escHtml(mrp)}</s>` : ''}${disc ? `  (<b>${escHtml(disc)}</b>)` : ''}\n\n✅ Live on dealbuster.in!`;
          } else {
            successMsg = `📢 <b>Posted to Channel!</b>\n\n<b>${escHtml(title)}</b>\n${price ? `Price: <b>${escHtml(price)}</b>` : ''}${mrp ? `  <s>${escHtml(mrp)}</s>` : ''}${disc ? `  (<b>${escHtml(disc)}</b>)` : ''}\n\n✅ Broadcast to @dealbusterindia!`;
          }

          await tgEdit(token, chatId, msgId, successMsg, isPhoto);
        } catch (e) {
          await tgEdit(token, chatId, msgId, `❌ Error: ${e.message}`, isPhoto);
        }

        return new Response('ok');
      }
    }

    // ── Incoming message ──────────────────────────────────────────────────────
    const msg = update.message;
    if (!msg) return new Response('ok');

    const chatId = String(msg.chat.id);
    if (chatId !== String(env.TELEGRAM_CHAT_ID)) return new Response('ok');

    const text = (msg.text || msg.caption || '').trim();

    if (text.startsWith('/')) {
      await tg(token, 'sendMessage', {
        chat_id: chatId,
        text: '👋 <b>DealBuster Bot</b>\n\nForward any Amazon or Non-Amazon deal to me, or send a link!\nI will convert the links to our affiliate tags and let you choose:\n• 🌐 <b>Publish to Site</b>\n• 📢 <b>Post to Channel</b>\n• 🚀 <b>Publish Both</b>',
        parse_mode: 'HTML',
      });
      return new Response('ok');
    }

    const allUrls = extractUrls(text, msg.entities || msg.caption_entities);
    if (!allUrls.length) {
      await tg(token, 'sendMessage', { chat_id: chatId, text: '⚠️ Please forward a deal message or send a product link (Amazon, Flipkart, Myntra, Ajio, Shopsy, Meesho).' });
      return new Response('ok');
    }

    const rawUrl = allUrls[0];
    const isAmz = /amazon\.(?:in|com)|amzn\.(?:to|in)|link\.amazon|a\.co/i.test(rawUrl);
    let store = 'other';
    let storeName = 'Online';
    let finalAffiliateUrl = '';
    let asin = '';

    if (isAmz) {
      store = 'amazon';
      storeName = 'Amazon';
      const canonical = await resolveCanonicalUrl(rawUrl);
      const asinM = canonical.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i) || rawUrl.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i) || rawUrl.match(/link\.amazon\/([A-Z0-9]{10})/i);
      asin = asinM ? asinM[1].toUpperCase() : '';
      finalAffiliateUrl = asin ? `https://www.amazon.in/dp/${asin}?tag=${DEFAULT_AMZ_TAG}` : canonical;
    } else {
      const canonical = await resolveCanonicalUrl(rawUrl);
      store = detectStore(canonical);
      storeName = formatStoreName(store);

      try {
        finalAffiliateUrl = await convertToEarnKaro(canonical, env.EARNKARO_API_TOKEN || EARNKARO_TOKEN);
      } catch {}

      if (!finalAffiliateUrl && text.length > rawUrl.length) {
        try {
          finalAffiliateUrl = await convertToEarnKaro(rawUrl, env.EARNKARO_API_TOKEN || EARNKARO_TOKEN);
        } catch {}
      }

      if (!finalAffiliateUrl) {
        finalAffiliateUrl = buildCueLinks(canonical);
      }
    }

    let { dealPrice, mrp, discount } = extractDealDetailsFromText(text);
    let title = extractDealTitleFromText(text);
    const photoId = msg.photo && msg.photo.length > 0 ? msg.photo[msg.photo.length - 1].file_id : null;
    let image = '';

    if (!title || !dealPrice) {
      try {
        const query = isAmz && asin ? `asin=${asin}` : `url=${encodeURIComponent(rawUrl)}&converter=earnkaro`;
        const r = await fetch(`${ADMIN_API}/fetchtitle?${query}`, {
          headers: { 'X-Admin-Password': env.ADMIN_PASSWORD },
        });
        const data = await r.json();
        if (data && !data.error) {
          if (!title && data.title) title = data.title;
          if (!dealPrice && data.price) dealPrice = `₹${data.price}`;
          if (!mrp && data.mrp) mrp = `₹${data.mrp}`;
          if (data.image) image = data.image;
        }
      } catch {}
    }

    if (!title) title = `${storeName} Deal`;
    if (!dealPrice && mrp) dealPrice = mrp;
    if (dealPrice && mrp && !discount) {
      const pVal = parseInt(dealPrice.replace(/[^\d]/g, ''), 10);
      const mVal = parseInt(mrp.replace(/[^\d]/g, ''), 10);
      if (mVal > pVal && pVal > 0) {
        discount = `${Math.round((1 - pVal / mVal) * 100)}% OFF`;
      }
    }

    const cleanTitle = escHtml(title.slice(0, 90));
    const priceRow = dealPrice ? `✅Deal Price: <b>${escHtml(dealPrice)}</b>` : '';
    const mrpRow = mrp ? `❌MRP: ${escHtml(mrp)}` : '';
    const discRow = discount ? `Discount: <b>${escHtml(discount)}</b>` : '';
    const detailsBlock = [priceRow, mrpRow, discRow].filter(Boolean).join('\n');
    const isLong = finalAffiliateUrl.length > 70;
    const linkHtml = isLong ? `<a href="${escHtml(finalAffiliateUrl)}">👉 Check Now</a>` : `👉 ${escHtml(finalAffiliateUrl)}`;
    const channelText = detailsBlock ? `${cleanTitle}\n${detailsBlock}\n\n${linkHtml}` : `${cleanTitle}\n\n${linkHtml}`;

    const previewLines = [
      `📦 <b>${cleanTitle}</b>`,
      dealPrice ? `✅ Deal Price: <b>${escHtml(dealPrice)}</b>` : '',
      mrp ? `❌ MRP: <s>${escHtml(mrp)}</s>${discount ? ` (<b>${escHtml(discount)}</b>)` : ''}` : '',
      `🛒 Store: <b>${escHtml(storeName)}</b>`,
      `\n🔗 ${escHtml(finalAffiliateUrl)}`
    ].filter(Boolean).join('\n');

    const key = `pending:${chatId}:${Date.now()}`;
    const pending = {
      product: {
        id: Date.now().toString(),
        asin,
        title,
        price: dealPrice || '',
        mrp: mrp || '',
        disc: discount || '0%',
        image: image || '',
        link: finalAffiliateUrl,
        category: 'other',
        highlights: []
      },
      category: 'other',
      highlights: [],
      channelText,
      photoId
    };

    await env.KV.put(key, JSON.stringify(pending), { expirationTtl: 86400 });

    const keyboard = {
      inline_keyboard: [
        [
          { text: '🌐 Publish to Site', callback_data: `pub_site:${key}` },
          { text: '📢 Post to Channel', callback_data: `pub_chan:${key}` }
        ],
        [
          { text: '🚀 Publish Both', callback_data: `pub_both:${key}` }
        ],
        [
          { text: '❌ Cancel', callback_data: 'cancel' }
        ]
      ]
    };

    if (photoId) {
      const r = await tg(token, 'sendPhoto', {
        chat_id: chatId,
        photo: photoId,
        caption: previewLines,
        parse_mode: 'HTML',
        reply_markup: keyboard
      });
      if (!r.ok) {
        await tg(token, 'sendMessage', {
          chat_id: chatId,
          text: previewLines,
          parse_mode: 'HTML',
          reply_markup: keyboard,
          disable_web_page_preview: true
        });
      }
    } else {
      await tg(token, 'sendMessage', {
        chat_id: chatId,
        text: previewLines,
        parse_mode: 'HTML',
        reply_markup: keyboard,
        disable_web_page_preview: true
      });
    }

    return new Response('ok');
  },
};
