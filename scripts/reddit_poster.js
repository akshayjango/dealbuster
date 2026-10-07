// scripts/reddit_poster.js
// Automated Reddit poster using Puppeteer with daily rotating SEO promo topics and deal posting.

const puppeteer = require('puppeteer');

function parseCookieString(cookieStr) {
  return cookieStr
    .split(';')
    .map(c => c.trim())
    .filter(Boolean)
    .map(c => {
      const idx = c.indexOf('=');
      if (idx === -1) return null;
      const name = c.slice(0, idx).trim();
      const value = c.slice(idx + 1).trim();
      return {
        name,
        value,
        domain: '.reddit.com',
        path: '/',
        secure: true,
        httpOnly: name === 'reddit_session' || name === 'token_v2' || name === 'csrf_token'
      };
    })
    .filter(Boolean);
}

function getDailySeoPromo() {
  const promos = [
    // 0: Sunday - Budget / Loot / Under 99
    {
      title: "Where to Find Real ₹99 Loot Deals and Lowest Price Drops in India? (Daily Verified List)",
      text: `Looking for genuine budget deals, glitch prices, and loot discounts under ₹99 to ₹499 in India?

Most deal sites flood feeds with thousands of expired offers or fake "MRP marked up" discounts. Here is how we track and filter only genuine price crashes on **DealBuster**:

### 🎯 What Makes a Real Deal?
1. **Price History Tracking:** We compare every deal against its 30-day and 90-day price history across Amazon and Flipkart.
2. **Zero Fake Discounts:** If a seller increased the MRP to show a fake "80% off", we filter it out.
3. **Instant Flash Alerts:** Most error prices and flash discounts last only 10 to 30 minutes before stock runs out.

### 🚀 Get Live Deal Alerts Right Now:
* 📲 **Android App:** [Download DealBuster on Google Play Store](https://play.google.com/store/apps/details?id=com.dealbusterindia.app)
  * Instant push notifications when prices crash to all-time lows
  * Clean, ad-free experience
* 💬 **Telegram Channel:** [Join @dealbusterindia on Telegram](https://t.me/dealbusterindia)
  * Real-time lightning-fast loot alerts
* 🌐 **Website:** [dealbuster.in](https://dealbuster.in)
  * Browse and search live deals across Electronics, Fashion, Home, and Beauty

What products or categories are you hunting deals on right now? Drop a comment and we'll track them for you!`
    },
    // 1: Monday - Best Deals App India
    {
      title: "Best Deals App in India for Amazon & Flipkart: Instant Price Drop Alerts (DealBuster)",
      text: `If you shop frequently on Amazon and Flipkart, having a fast deal tracker app saves thousands of rupees every month.

### 📱 Meet DealBuster (Android App)
DealBuster is a dedicated Indian deal aggregator that continuously tracks thousands of products 24/7 across Amazon, Flipkart, Myntra, Ajio, and more.

### ✨ Key Features:
* 🔔 **Instant Push Notifications:** Never miss a price glitch or lightning deal before it expires.
* 🏷️ **Verified All-Time Lowest Prices:** Automatically tags products hitting their lowest price in 30 or 90 days.
* ⚡ **Lightning Fast:** Handpicked deals verified for stock availability every 10-15 minutes.
* 🛡️ **100% Free & No Spam:** No intrusive ads or spam notifications.

---
🔗 **Official Links:**
* 📲 **Google Play Store:** [Download DealBuster App](https://play.google.com/store/apps/details?id=com.dealbusterindia.app)
* 💬 **Telegram:** [Join @dealbusterindia](https://t.me/dealbusterindia)
* 🌐 **Web:** [dealbuster.in](https://dealbuster.in)`
    },
    // 2: Tuesday - Where to find lowest price deals
    {
      title: "Where Can I Find Lowest Price Deals & Price Drops in India? (Amazon, Flipkart & Myntra)",
      text: `Tracking price drops manually across Amazon, Flipkart, Myntra, and Ajio is exhausting. DealBuster automates the entire process.

### 🔍 How to Spot Genuine Deals:
* **All-time low detection:** We verify if an item is truly at its lowest recorded price before posting.
* **Coupon & Bank Discounts:** We calculate final checkout prices including applicable coupons.
* **Real-time stock checks:** Out-of-stock items are automatically flagged and removed.

---
### 🚀 Follow DealBuster for Live Updates:
* 📲 **Android App:** [Install on Google Play](https://play.google.com/store/apps/details?id=com.dealbusterindia.app) *(Instant push notifications for price drops)*
* 💬 **Telegram Channel:** [Join @dealbusterindia](https://t.me/dealbusterindia) *(Live deal feed)*
* 🌐 **Website:** [dealbuster.in](https://dealbuster.in) *(Search all live deals)*`
    },
    // 3: Wednesday - Top Telegram channel
    {
      title: "Best Telegram Channels for Amazon & Flipkart Loot Deals in India [Verified & No Spam]",
      text: `If you are looking for active, clean Telegram deal channels in India that don't spam fake links, check out **@dealbusterindia**.

### Why Join DealBuster India on Telegram?
* 🚀 **High-frequency, high-discount only:** We prioritize deals with 50%+ real discounts.
* 🛑 **No spam or junk:** No constant casino/crypto promotions or random ads.
* 🛒 **Direct Buy Links:** Handpicked deals across electronics, home essentials, groceries, and fashion.

---
🔗 **Connect With Us:**
* 💬 **Telegram Channel:** [Join @dealbusterindia](https://t.me/dealbusterindia)
* 📲 **Android App:** [Download on Google Play Store](https://play.google.com/store/apps/details?id=com.dealbusterindia.app)
* 🌐 **Website:** [dealbuster.in](https://dealbuster.in)`
    },
    // 4: Thursday - Electronics & Gadgets
    {
      title: "Best Electronics & Gadget Discounts in India (TWS Earbuds, Laptops, Smartwatches & TVs)",
      text: `Looking for discount deals on headphones, TWS earbuds, laptops, monitors, or smartwatches?

DealBuster monitors top tech brands (Sony, boAt, Noise, OnePlus, Samsung, Asus, Lenovo) to catch sudden price drops and lightning sales.

### 💡 Shopping Tips for Gadgets:
* Price drops happen most frequently early morning (around 2 AM to 8 AM) and during flash sales.
* Set notifications to catch stock before scalpers and resellers buy them out.

---
### 🔔 Catch the Next Gadget Price Drop:
* 📲 **Android App:** [Download DealBuster App](https://play.google.com/store/apps/details?id=com.dealbusterindia.app)
* 💬 **Telegram Channel:** [Join @dealbusterindia](https://t.me/dealbusterindia)
* 🌐 **Website:** [dealbuster.in](https://dealbuster.in)`
    },
    // 5: Friday - Fashion & Lifestyle
    {
      title: "How to Get 70% to 80% Off on Fashion, Shoes & Clothing (Myntra, Ajio, Shopsy & Flipkart)",
      text: `Branded sneakers, shirts, watches, and sportswear regularly drop by 70%-80% on Myntra, Ajio, and Flipkart.

DealBuster scans these platforms daily for hidden price slashes on Nike, Puma, Adidas, Levi's, Red Tape, and more.

---
### 🛍️ Never Miss a Fashion Sale:
* 📲 **Android App:** [Download DealBuster App](https://play.google.com/store/apps/details?id=com.dealbusterindia.app)
* 💬 **Telegram:** [Join @dealbusterindia](https://t.me/dealbusterindia)
* 🌐 **Web:** [dealbuster.in](https://dealbuster.in)`
    },
    // 6: Saturday - Shopping Hacks & Glitches
    {
      title: "Online Shopping Hacks in India: How to Never Miss a Flash Sale or Price Glitch",
      text: `Flash sales and price glitches sell out in minutes. Here is how you can always be first to grab them:

1. **Use Push Notifications instead of checking websites:** Apps like DealBuster notify you within seconds of a price drop.
2. **Keep payment methods ready:** UPI or saved cards prevent missing 10-minute flash sales.
3. **Verify price history:** Ensure the discount is genuine before purchasing.

---
🚀 **Join the Community:**
* 📲 **Android App:** [Download on Google Play](https://play.google.com/store/apps/details?id=com.dealbusterindia.app)
* 💬 **Telegram:** [Join @dealbusterindia](https://t.me/dealbusterindia)
* 🌐 **Website:** [dealbuster.in](https://dealbuster.in)`
    }
  ];

  const dayOfWeek = new Date().getUTCDay();
  return promos[dayOfWeek] || promos[0];
}

async function run() {
  const rawCookie = process.env.REDDIT_COOKIES || '';
  if (!rawCookie) {
    console.error('ERROR: REDDIT_COOKIES environment variable is required.');
    process.exit(1);
  }

  let title = (process.env.POST_TITLE || '').trim();
  let text = (process.env.POST_TEXT || '').trim();

  if (!title) {
    console.log('No post title provided. Selecting daily rotating SEO promo post...');
    const promo = getDailySeoPromo();
    title = promo.title;
    text = promo.text;
  }

  console.log(`Target Subreddit: r/DealBusterIndia`);
  console.log(`Title: "${title.slice(0, 80)}..."`);

  const cookies = parseCookieString(rawCookie);

  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--window-size=1280,800'
    ]
  });

  try {
    const page = await browser.newPage();
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
    await page.setViewport({ width: 1280, height: 800 });

    console.log('Setting Reddit session cookies...');
    await page.setCookie(...cookies);

    console.log('Navigating to modern r/DealBusterIndia submit page...');
    await page.goto('https://www.reddit.com/r/DealBusterIndia/submit', {
      waitUntil: 'domcontentloaded',
      timeout: 60000
    });

    console.log('Waiting for modern Reddit composer to mount...');
    await new Promise(r => setTimeout(r, 6000));
    console.log(`Current page URL: ${page.url()}`);

    // Deep search helper across all shadow DOM roots
    async function findInShadow(selector, timeoutMs = 35000) {
      const start = Date.now();
      while (Date.now() - start < timeoutMs) {
        const handle = await page.evaluateHandle((sel) => {
          function search(root) {
            const direct = root.querySelector(sel);
            if (direct) return direct;
            const all = root.querySelectorAll('*');
            for (const el of all) {
              if (el.shadowRoot) {
                const found = search(el.shadowRoot);
                if (found) return found;
              }
            }
            return null;
          }
          return search(document);
        }, selector);

        const el = handle.asElement();
        if (el) return el;
        await new Promise(r => setTimeout(r, 500));
      }
      return null;
    }

    // 1. Locate and fill Title inside <post-composer-title>'s shadow-root
    console.log('Locating Title input inside Shadow DOM...');
    const titleEl = await findInShadow('textarea[name="title"], textarea[placeholder*="Title"], post-composer-title textarea', 35000);
    if (!titleEl) {
      throw new Error('Title element not found in modern Reddit composer Shadow DOM.');
    }

    console.log('Found Title textarea. Typing title...');
    await titleEl.click();
    await page.evaluate((el, val) => {
      el.focus();
      el.value = val;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }, titleEl, title);
    console.log('Title typed successfully.');

    await new Promise(r => setTimeout(r, 1500));

    // 2. Locate and fill Body / Markdown editor inside Shadow DOM
    if (text) {
      console.log('Locating Body editor inside Shadow DOM...');
      const bodyEl = await findInShadow('div[contenteditable="true"], div[role="textbox"], textarea[placeholder*="body"], textarea[placeholder*="Text"]', 15000);
      if (bodyEl) {
        console.log('Found Body element. Filling text...');
        await bodyEl.click();
        await page.evaluate((el, val) => {
          el.focus();
          // Set contenteditable text
          if (el.getAttribute('contenteditable') === 'true' || el.getAttribute('role') === 'textbox') {
            document.execCommand('insertText', false, val);
          } else {
            el.value = val;
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }
        }, bodyEl, text);
        console.log('Body filled successfully.');
      } else {
        console.warn('Body element not found, proceeding with title-only post...');
      }
    }

    await new Promise(r => setTimeout(r, 2000));

    // 3. Locate and click Post button inside Shadow DOM or main document
    console.log('Locating enabled Post button...');
    const postBtnHandle = await page.evaluateHandle(() => {
      function searchButtons(root) {
        const btns = Array.from(root.querySelectorAll('button'));
        for (const b of btns) {
          const txt = (b.textContent || '').trim().toLowerCase();
          const disabled = b.disabled || b.getAttribute('aria-disabled') === 'true';
          if ((txt === 'post' || txt === 'publish') && !disabled) {
            return b;
          }
        }
        const all = root.querySelectorAll('*');
        for (const el of all) {
          if (el.shadowRoot) {
            const found = searchButtons(el.shadowRoot);
            if (found) return found;
          }
        }
        return null;
      }
      return searchButtons(document);
    });

    const postBtn = postBtnHandle.asElement();
    if (!postBtn) {
      throw new Error('Enabled Post button could not be located.');
    }

    console.log('Clicking Post button...');
    await postBtn.click();

    console.log('Post button clicked! Waiting for submission to finalize...');
    await new Promise(r => setTimeout(r, 10000));

    console.log(`Final page URL: ${page.url()}`);
    console.log('Reddit post workflow completed successfully!');
  } catch (err) {
    console.error('ERROR during Reddit post:', err.message);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

run();
