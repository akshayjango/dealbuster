import fs from 'node:fs';
import path from 'node:path';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';

function getReloginSecret() {
  return process.env.RELOGIN_PASSWORD || process.env.ADMIN_PASSWORD || process.env.TELEGRAM_API_HASH || '';
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => {
      data += chunk;
      if (data.length > 64 * 1024) {
        reject(new Error('Request body too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        reject(new Error('Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload, null, 2));
}

function saveSessionToEnv(rootDir, sessionString) {
  try {
    const envPath = path.join(rootDir, '.env');
    if (!fs.existsSync(envPath)) return false;
    let content = fs.readFileSync(envPath, 'utf8');
    const regex = /^TELEGRAM_SESSION=.*$/m;
    if (regex.test(content)) {
      content = content.replace(regex, `TELEGRAM_SESSION=${sessionString}`);
    } else {
      content = `${content.trim()}\nTELEGRAM_SESSION=${sessionString}\n`;
    }
    fs.writeFileSync(envPath, content, 'utf8');
    return true;
  } catch {
    return false;
  }
}

const RELOGIN_HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>DealBuster Forwarder — Phone Re-Login</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; background:#0f172a; color:#e2e8f0; margin:0; padding:18px; }
    .card { max-width:440px; margin:20px auto; background:#1e293b; border-radius:14px; padding:20px; box-shadow:0 10px 30px rgba(0,0,0,.35); }
    h1 { font-size:1.2rem; margin:0 0 8px; }
    p { font-size:.9rem; color:#94a3b8; margin:0 0 16px; }
    label { display:block; font-size:.82rem; color:#cbd5e1; margin:12px 0 5px; }
    input { width:100%; box-sizing:border-box; padding:11px 12px; border-radius:8px; border:1px solid #334155; background:#0f172a; color:#fff; font-size:1rem; }
    button { width:100%; margin-top:14px; padding:12px; border:0; border-radius:8px; background:#3b82f6; color:#fff; font-weight:600; font-size:1rem; cursor:pointer; }
    button.secondary { background:#10b981; }
    button:disabled { opacity:.6; cursor:not-allowed; }
    .msg { margin-top:14px; padding:10px 12px; border-radius:8px; font-size:.88rem; display:none; word-break:break-word; }
    .msg.ok { display:block; background:#064e3b; color:#a7f3d0; }
    .msg.err { display:block; background:#7f1d1d; color:#fecaca; }
    textarea { width:100%; box-sizing:border-box; margin-top:10px; padding:10px; border-radius:8px; border:1px solid #334155; background:#0f172a; color:#38bdf8; font-family:monospace; font-size:.78rem; min-height:85px; }
    .hidden { display:none; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🔐 DealBuster Forwarder Re-Login</h1>
    <p>Reconnect Telegram directly from your phone without a laptop or terminal.</p>

    <label>Admin / Relogin Password</label>
    <input id="pwd" type="password" placeholder="RELOGIN_PASSWORD (or API_HASH)" autocomplete="current-password" />

    <div id="step1">
      <label>Telegram Phone Number (with country code)</label>
      <input id="phone" type="tel" placeholder="+91XXXXXXXXXX" />
      <button id="sendBtn" onclick="sendCode()">Send OTP to Telegram</button>
    </div>

    <div id="step2" class="hidden">
      <label>Telegram OTP Code</label>
      <input id="code" type="text" inputmode="numeric" placeholder="12345" />
      <label>2FA Cloud Password (only if enabled)</label>
      <input id="tfa" type="password" placeholder="Optional" />
      <button id="verifyBtn" class="secondary" onclick="verifyCode()">Verify &amp; Reconnect</button>
    </div>

    <div id="status" class="msg"></div>
    <div id="sessionBox" class="hidden">
      <label>New TELEGRAM_SESSION (copy into Render env vars to persist across redeploys):</label>
      <textarea id="sessionOut" readonly></textarea>
      <button onclick="copySession()">Copy Session String</button>
    </div>
  </div>
<script>
function showMsg(text, ok) {
  const el = document.getElementById('status');
  el.textContent = text;
  el.className = 'msg ' + (ok ? 'ok' : 'err');
}
async function sendCode() {
  const btn = document.getElementById('sendBtn');
  btn.disabled = true;
  showMsg('Sending OTP request to Telegram...', true);
  try {
    const r = await fetch('/relogin/send-code', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        password: document.getElementById('pwd').value.trim(),
        phoneNumber: document.getElementById('phone').value.trim(),
      })
    });
    const d = await r.json();
    if (!r.ok || !d.ok) throw new Error(d.error || 'Failed to send OTP');
    document.getElementById('step2').classList.remove('hidden');
    showMsg(d.message || 'OTP sent! Check your Telegram app.', true);
  } catch (e) {
    showMsg(e.message, false);
  } finally {
    btn.disabled = false;
  }
}
async function verifyCode() {
  const btn = document.getElementById('verifyBtn');
  btn.disabled = true;
  showMsg('Verifying OTP and reconnecting...', true);
  try {
    const r = await fetch('/relogin/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        password: document.getElementById('pwd').value.trim(),
        code: document.getElementById('code').value.trim(),
        twoFactorPassword: document.getElementById('tfa').value,
      })
    });
    const d = await r.json();
    if (!r.ok || !d.ok) throw new Error(d.error || 'Verification failed');
    showMsg('✅ Connected as ' + d.user + ' and auto-forwarding resumed!', true);
    document.getElementById('sessionOut').value = d.sessionString;
    document.getElementById('sessionBox').classList.remove('hidden');
  } catch (e) {
    showMsg(e.message, false);
  } finally {
    btn.disabled = false;
  }
}
function copySession() {
  const ta = document.getElementById('sessionOut');
  ta.select();
  navigator.clipboard?.writeText(ta.value);
  showMsg('📋 Copied TELEGRAM_SESSION! Paste it into Render Environment Variables.', true);
}
</script>
</body>
</html>`;

export function createReloginHandler({ rootDir, onNewSession }) {
  let pendingAuth = null;

  async function cleanupPending() {
    if (pendingAuth?.client) {
      try { await pendingAuth.client.disconnect(); } catch {}
    }
    pendingAuth = null;
  }

  return async function handleReloginRequest(req, res) {
    const urlPath = (req.url || '/').split('?')[0];

    if (urlPath === '/relogin' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(RELOGIN_HTML);
      return true;
    }

    if (urlPath === '/relogin/send-code' && req.method === 'POST') {
      try {
        const body = await readJsonBody(req);
        const secret = getReloginSecret();
        if (!secret || body.password !== secret) {
          sendJson(res, 401, { ok: false, error: 'Invalid password' });
          return true;
        }
        const phoneNumber = (body.phoneNumber || '').trim();
        if (!phoneNumber) {
          sendJson(res, 400, { ok: false, error: 'Phone number is required (e.g. +91XXXXXXXXXX)' });
          return true;
        }
        const apiId = parseInt(process.env.TELEGRAM_API_ID, 10);
        const apiHash = process.env.TELEGRAM_API_HASH;
        if (!apiId || !apiHash) {
          sendJson(res, 500, { ok: false, error: 'TELEGRAM_API_ID / TELEGRAM_API_HASH not configured' });
          return true;
        }

        await cleanupPending();

        const authClient = new TelegramClient(new StringSession(''), apiId, apiHash, { connectionRetries: 5 });
        let codePromptedResolve;
        const codePromptedPromise = new Promise((resolve) => { codePromptedResolve = resolve; });

        const state = {
          client: authClient,
          resolveCode: null,
          rejectCode: null,
          resolve2FA: null,
          reject2FA: null,
          startPromise: null,
          error: null,
        };
        pendingAuth = state;

        state.startPromise = authClient.start({
          phoneNumber: async () => phoneNumber,
          phoneCode: () => {
            codePromptedResolve();
            return new Promise((resolve, reject) => {
              state.resolveCode = resolve;
              state.rejectCode = reject;
            });
          },
          password: () => new Promise((resolve, reject) => {
            state.resolve2FA = resolve;
            state.reject2FA = reject;
          }),
          onError: (err) => {
            state.error = err?.message || String(err);
          },
        });

        // Wait until Telegram prompts for OTP (or fails early)
        await Promise.race([
          codePromptedPromise,
          state.startPromise.then(() => { throw new Error('Unexpected early completion'); }),
          new Promise((_, reject) => setTimeout(() => reject(new Error(state.error || 'Timed out waiting for Telegram OTP prompt')), 20000)),
        ]);

        sendJson(res, 200, { ok: true, message: 'OTP sent! Check your Telegram app.' });
      } catch (err) {
        await cleanupPending();
        sendJson(res, 500, { ok: false, error: err.message });
      }
      return true;
    }

    if (urlPath === '/relogin/verify' && req.method === 'POST') {
      try {
        const body = await readJsonBody(req);
        const secret = getReloginSecret();
        if (!secret || body.password !== secret) {
          sendJson(res, 401, { ok: false, error: 'Invalid password' });
          return true;
        }
        if (!pendingAuth || !pendingAuth.resolveCode) {
          sendJson(res, 400, { ok: false, error: 'No pending OTP request. Click "Send OTP" first.' });
          return true;
        }
        const code = (body.code || '').trim();
        if (!code) {
          sendJson(res, 400, { ok: false, error: 'OTP code is required' });
          return true;
        }

        const state = pendingAuth;
        state.resolveCode(code);

        // If 2FA is requested by Telegram, supply it once resolve2FA is set
        const twoFactor = body.twoFactorPassword || '';
        const wait2FA = setInterval(() => {
          if (state.resolve2FA) {
            clearInterval(wait2FA);
            state.resolve2FA(twoFactor);
          }
        }, 150);

        try {
          await Promise.race([
            state.startPromise,
            new Promise((_, reject) => setTimeout(() => reject(new Error(state.error || 'Timed out verifying OTP')), 25000)),
          ]);
        } finally {
          clearInterval(wait2FA);
        }

        const sessionString = state.client.session.save();
        const me = await state.client.getMe();
        const userLabel = `${me.firstName || ''} ${me.lastName || ''} (@${me.username || me.id})`.trim();
        await state.client.disconnect();
        pendingAuth = null;

        process.env.TELEGRAM_SESSION = sessionString;
        saveSessionToEnv(rootDir, sessionString);

        if (typeof onNewSession === 'function') {
          onNewSession(sessionString).catch(e => console.error('❌ Reconnect error after relogin:', e));
        }

        sendJson(res, 200, { ok: true, user: userLabel, sessionString });
      } catch (err) {
        await cleanupPending();
        sendJson(res, 500, { ok: false, error: err.message });
      }
      return true;
    }

    return false;
  };
}
