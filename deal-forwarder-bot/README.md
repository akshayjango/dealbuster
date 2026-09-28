# 🚀 DealBuster Telegram Auto-Forwarder & Link Converter

A private, self-hosted Telegram bot that listens to deals from other channels, automatically converts affiliate links to your own tags, strips competitor branding/mentions, and posts clean deals directly to your channel.

---

### 🛡️ Why Self-Hosted? (Never Give Credentials to 3rd-Party Bots)
Commercial forwarder bots ask you to send your **Phone Number**, **Telegram OTP**, and **2FA Password** in a private chat. That gives a third party full control over your personal Telegram account and messages.

With this self-hosted bot:
- You own the bot completely.
- Your session and credentials stay **100% locally** in your `.env` file on your computer/VPS.
- Zero risk of account compromise.

---

## ⚡ Quick Start Guide (4 Simple Steps)

### Step 1: Get Telegram API ID & API Hash (Free & takes 1 min)
1. Open [my.telegram.org](https://my.telegram.org) in your browser.
2. Log in with your Telegram phone number.
3. Click on **API development tools**.
4. Create a new application (enter any title, e.g., `DealBusterForwarder`, and short name, e.g., `dealbuster`).
5. Copy your **`api_id`** (numeric) and **`api_hash`** (string).

---

### Step 2: Log In Safely
Open terminal inside the `deal-forwarder-bot` directory:

```powershell
cd deal-forwarder-bot
npm run login
```

The script will prompt you:
1. Enter your `API_ID` and `API_HASH`.
2. Enter your phone number (e.g. `+919876543210`).
3. Enter the login OTP sent by Telegram directly to your Telegram app.
4. Enter your 2FA password (if you have one enabled).

✅ Once logged in, your session string is automatically and safely saved to your local `.env` file!

---

### Step 3: Configure Your Channels & Tags
Open `config.json` and configure:

```json
{
  "source_channels": [
    "@CompetitorDeals1",
    "@LootOffersChannel2"
  ],
  "target_channel": "@dealbusterindia",
  "amazon_tag": "dealbuster002-21",
  "earnkaro_api_token": "YOUR_EARNKARO_API_TOKEN",
  "custom_footer": "\n\n⚡ Join @dealbusterindia for verified deals!",
  "remove_competitor_mentions": true,
  "blacklist_keywords": [
    "loot over",
    "expired",
    "giveaway",
    "free recharge"
  ],
  "dedup_ttl_hours": 24,
  "delay_seconds": 2
}
```

- **`source_channels`**: List of channel usernames (e.g. `@channel_name`) or numeric IDs you want to monitor. (Make sure your account has joined these channels).
- **`target_channel`**: Your channel username or ID (make sure your account has permission to post).
- **`amazon_tag`**: Your Amazon Associates tag (`dealbuster002-21`).
- **`earnkaro_api_token`**: Your EarnKaro Converter API Token for Flipkart, Myntra, Ajio, Shopsy, etc. (already pre-filled).
- **`custom_footer`**: Message added at the bottom of every deal.
- **`remove_competitor_mentions`**: Automatically removes competitor `@username` mentions, invite links, and promo lines.
- **`dedup_ttl_hours`**: Prevents posting the same product twice within 24 hours.

---

### Step 4: Start the Auto-Forwarder

```powershell
npm start
```

Whenever any of your source channels post a new deal:
1. The bot catches the post in real-time.
2. Checks keywords (skips expired/blacklist keywords).
3. Unrolls shortlinks (`amzn.to`, `bit.ly`, `fktr.in`, etc.).
4. Replaces Amazon tags with `dealbuster002-21`.
5. Converts Flipkart/Myntra/Ajio links via CueLinks.
6. Strips competitor mentions and watermark lines.
7. Checks deduplication (skips if already posted within 24h).
8. Reposts cleanly with photos/media to `@dealbusterindia`!

---

## 🛠️ Testing the Link Converter
You can test the link resolution and text cleaner on sample text anytime with:

```powershell
npm run test-converter
```

---

## 🔄 Running 24/7 (Optional)
If you want to keep the bot running in the background on your PC or VPS:
Using `pm2` (Node process manager):
```bash
npm install -g pm2
pm2 start src/bot.js --name "dealbuster-forwarder"
pm2 save
pm2 startup
```
