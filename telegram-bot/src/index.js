const ADMIN_API = 'https://dealbuster-admin-api.vakshay083.workers.dev';

function tg(token, method, body) {
  return fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

function extractAmazonUrl(text) {
  const m = text.match(/https?:\/\/(?:[\w.-]*amazon\.in\/[^\s]+|amzn\.to\/[^\s]+)/i);
  return m ? m[0].replace(/[.,!?]+$/, '') : null;
}

function isShortLink(url) {
  return /amzn\.to\//i.test(url);
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return new Response('ok');

    let update;
    try { update = await request.json(); } catch { return new Response('ok'); }

    const token = env.TELEGRAM_BOT_TOKEN;

    // ── Callback query (button press) ─────────────────────────────────────────
    if (update.callback_query) {
      const cb = update.callback_query;
      const chatId = String(cb.message.chat.id);
      const msgId = cb.message.message_id;
      const data = cb.data;

      await tg(token, 'answerCallbackQuery', { callback_query_id: cb.id });

      if (data === 'cancel') {
        await tg(token, 'editMessageText', { chat_id: chatId, message_id: msgId, text: '❌ Cancelled.' });
        return new Response('ok');
      }

      if (data.startsWith('publish:')) {
        const key = data.slice(8);
        let pending;
        try { pending = await env.KV.get(key, 'json'); } catch {}

        if (!pending) {
          await tg(token, 'editMessageText', { chat_id: chatId, message_id: msgId, text: '⏱️ Session expired. Send the link again.' });
          return new Response('ok');
        }

        const resp = await fetch(`${ADMIN_API}/products`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Admin-Password': env.ADMIN_PASSWORD },
          body: JSON.stringify(pending),
        });
        const result = await resp.json();
        await env.KV.delete(key);

        if (result.success) {
          await tg(token, 'editMessageText', {
            chat_id: chatId, message_id: msgId,
            text: `✅ *Published!*\n\n*${pending.product.title}*\n${pending.product.price}  ~~${pending.product.mrp}~~  ${pending.product.disc}`,
            parse_mode: 'Markdown',
          });
        } else {
          await tg(token, 'editMessageText', {
            chat_id: chatId, message_id: msgId,
            text: `❌ Publish failed: ${result.error || 'Unknown error'}`,
          });
        }
        return new Response('ok');
      }
    }

    // ── Incoming message ──────────────────────────────────────────────────────
    const msg = update.message;
    if (!msg?.text) return new Response('ok');

    const chatId = String(msg.chat.id);

    // Only respond to authorized user
    if (chatId !== String(env.TELEGRAM_CHAT_ID)) return new Response('ok');

    const text = msg.text.trim();

    // /start or /help
    if (text.startsWith('/')) {
      await tg(token, 'sendMessage', {
        chat_id: chatId,
        text: '👋 *Dealbuster Bot*\n\nJust paste any Amazon product link and I\'ll fetch the deal details and publish it to your site.',
        parse_mode: 'Markdown',
      });
      return new Response('ok');
    }

    const url = extractAmazonUrl(text);
    if (!url) {
      await tg(token, 'sendMessage', { chat_id: chatId, text: '⚠️ Please send an Amazon product link (amazon.in or amzn.to).' });
      return new Response('ok');
    }

    // Acknowledge
    await tg(token, 'sendMessage', { chat_id: chatId, text: '🔍 Fetching deal details…' });

    // Fetch product details from admin API
    const short = isShortLink(url);
    const asinMatch = url.match(/\/dp\/([A-Z0-9]{10})/i);
    const query = short ? `url=${encodeURIComponent(url)}` : `asin=${asinMatch?.[1]}`;

    let data;
    try {
      const r = await fetch(`${ADMIN_API}/fetchtitle?${query}`, {
        headers: { 'X-Admin-Password': env.ADMIN_PASSWORD },
      });
      data = await r.json();
    } catch (e) {
      await tg(token, 'sendMessage', { chat_id: chatId, text: `❌ Fetch error: ${e.message}` });
      return new Response('ok');
    }

    if (!data.title) {
      await tg(token, 'sendMessage', { chat_id: chatId, text: `❌ Could not fetch product: ${data.error || 'Title not found'}` });
      return new Response('ok');
    }

    // Build product object
    const asin = data.asin || asinMatch?.[1] || '';
    const link = short ? url : `https://www.amazon.in/dp/${asin}?tag=dealbuster002-21`;
    const price = data.price ? `₹${data.price}` : '';
    const mrp   = data.mrp  ? `₹${data.mrp}`  : '';
    const disc  = data.price && data.mrp && data.mrp > data.price
      ? `-${Math.round((1 - data.price / data.mrp) * 100)}%`
      : '0%';

    const pending = {
      product: { asin, title: data.title, price, mrp, disc, image: '', link },
      category: data.category || 'other',
      highlights: data.highlights || [],
    };

    // Store in KV with 5 min TTL
    const key = `pending:${chatId}:${Date.now()}`;
    await env.KV.put(key, JSON.stringify(pending), { expirationTtl: 300 });

    // Build preview message
    const lines = [
      `📦 *${data.title}*`,
      price ? `💰 ${price}  ~~${mrp}~~  *${disc}*` : '',
      data.category ? `🏷️ ${data.category}` : '',
      data.highlights?.length
        ? '\n✨ ' + data.highlights.slice(0, 3).join('\n✨ ')
        : '',
      `\n🔗 ${url}`,
    ].filter(Boolean).join('\n');

    await tg(token, 'sendMessage', {
      chat_id: chatId,
      text: lines,
      parse_mode: 'Markdown',
      reply_markup: {
        inline_keyboard: [[
          { text: '✅ Publish to Site', callback_data: `publish:${key}` },
          { text: '❌ Cancel',          callback_data: 'cancel' },
        ]],
      },
    });

    return new Response('ok');
  },
};
