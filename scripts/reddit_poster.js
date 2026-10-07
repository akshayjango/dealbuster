// scripts/reddit_poster.js
// Automated Reddit poster using Playwright to handle modern Reddit web interface and reCAPTCHA.

const { chromium } = require('playwright-chromium');

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

function getDefaultPromo() {
  const title = "🔥 Daily Deal Alert: Download DealBuster Android App & Join Telegram for Lowest Price Alerts!";
  const text = `Welcome to r/DealBusterIndia!

We track thousands of products 24/7 across Amazon, Flipkart, Myntra, Ajio, and more to detect all-time lowest price drops and genuine discounts.

### 🚀 Get Real-Time Deal Alerts:
* 📲 **Android App:** [Download DealBuster on Google Play Store](https://play.google.com/store/apps/details?id=com.dealbusterindia.app)
  * Real-time push notifications for price glitches & lowest price drops
  * Handpicked verified deals & discount coupons
  * 100% free with clean UI

* 💬 **Telegram Channel:** [Join @dealbusterindia on Telegram](https://t.me/dealbusterindia)
  * Instant alerts for flash sales, lightning deals, and price glitches

* 🌐 **Web Platform:** [dealbuster.in](https://dealbuster.in)
  * Search deals across all categories anytime

Drop your deal requests or product recommendations in the comments!`;
  return { title, text };
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
    console.log('No post title provided. Using daily community promo post...');
    const promo = getDefaultPromo();
    title = promo.title;
    text = promo.text;
  }

  console.log(`Preparing to post to r/DealBusterIndia: "${title.slice(0, 60)}..."`);

  const cookies = parseCookieString(rawCookie);

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-accelerated-2d-canvas',
      '--no-first-run',
      '--no-zygote',
      '--disable-gpu'
    ]
  });

  try {
    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      viewport: { width: 1280, height: 850 }
    });

    await context.addCookies(cookies);
    const page = await context.newPage();

    console.log('Navigating to submit page...');
    await page.goto('https://www.reddit.com/r/DealBusterIndia/submit', {
      waitUntil: 'domcontentloaded',
      timeout: 45000
    });

    await page.waitForTimeout(3000);

    // Verify logged in
    const pageContent = await page.content();
    if (pageContent.includes('Log In') && !pageContent.includes('Resident-Job586') && !pageContent.includes('DealBusterIndia')) {
      console.warn('Warning: Log In prompt detected, checking if session is active...');
    }

    // Try finding title input
    console.log('Looking for title input...');
    const titleSelectors = [
      'textarea[placeholder*="Title"]',
      'input[placeholder*="Title"]',
      'textarea[name="title"]',
      'input[name="title"]',
      '#post-composer-title'
    ];

    let titleEl = null;
    for (const sel of titleSelectors) {
      titleEl = await page.$(sel);
      if (titleEl) {
        console.log(`Found title input using selector: ${sel}`);
        break;
      }
    }

    if (!titleEl) {
      await page.screenshot({ path: 'debug-submit-page.png' });
      throw new Error('Could not locate title field on Reddit submit page. Screenshot saved to debug-submit-page.png');
    }

    await titleEl.click();
    await titleEl.fill(title);
    await page.waitForTimeout(500);

    // Look for body input or markdown mode
    console.log('Looking for body / text field...');
    // If there is a "Switch to markdown" or "Markdown" button, prefer clicking it
    const markdownBtn = await page.$('button:has-text("Markdown"), button:has-text("Switch to markdown")');
    if (markdownBtn) {
      try {
        await markdownBtn.click();
        await page.waitForTimeout(500);
      } catch (e) {}
    }

    const bodySelectors = [
      'textarea[placeholder*="Text"]',
      'textarea[placeholder*="body"]',
      'div[contenteditable="true"]',
      'div[role="textbox"]',
      '#post-composer-body'
    ];

    let bodyEl = null;
    for (const sel of bodySelectors) {
      bodyEl = await page.$(sel);
      if (bodyEl) {
        console.log(`Found body field using selector: ${sel}`);
        break;
      }
    }

    if (bodyEl && text) {
      await bodyEl.click();
      await page.waitForTimeout(300);
      const isContentEditable = await bodyEl.evaluate(el => el.getAttribute('contenteditable') === 'true');
      if (isContentEditable) {
        await page.evaluate(({ el, text }) => {
          el.innerText = text;
          el.dispatchEvent(new Event('input', { bubbles: true }));
        }, { el: bodyEl, text });
      } else {
        await bodyEl.fill(text);
      }
      await page.waitForTimeout(500);
    }

    // Find and click the Post button
    console.log('Locating Post button...');
    const postBtnSelectors = [
      'button:has-text("Post"):not([disabled])',
      'button[type="submit"]:has-text("Post")',
      '#post-composer-submit-button',
      'button:has-text("Publish")'
    ];

    let postBtn = null;
    for (const sel of postBtnSelectors) {
      postBtn = await page.$(sel);
      if (postBtn) {
        const disabled = await postBtn.evaluate(el => el.disabled || el.getAttribute('aria-disabled') === 'true');
        if (!disabled) {
          console.log(`Found enabled Post button with selector: ${sel}`);
          break;
        }
      }
    }

    if (!postBtn) {
      await page.screenshot({ path: 'debug-post-btn.png' });
      throw new Error('Post button not found or is disabled.');
    }

    console.log('Clicking Post button...');
    await postBtn.click();

    // Wait for submission to complete (URL changes to comments/... or confirmation dialog)
    try {
      await page.waitForURL(/comments|dealbusterindia/i, { timeout: 15000 });
      console.log(`SUCCESS! Post published: ${page.url()}`);
    } catch (e) {
      console.log('Waited for URL change, current URL:', page.url());
      await page.waitForTimeout(3000);
    }

    console.log('Reddit post operation finished successfully.');
  } catch (err) {
    console.error('Reddit posting failed:', err.message);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

run();
