import {
  processMessageText,
  isAmazonUptoDeal,
  normalizeDealTitle,
  calculateTitleSimilarity,
  extractCanonicalDealId,
} from './converter.js';

function runTitleNormalizationTests() {
  console.log('=== Title Normalization & Deduplication Unit Tests ===\n');

  const titles = [
    'New Balance Mens Casual Shoes at minimum 68% Discount',
    'Upto 65% Off - New Balance Mens Casual Shoes',
    '🔥 Loot Deal : New Balance Mens Casual Shoes Under ₹1499',
    '⚡ Flat 70% Off on New Balance Mens Casual Shoes',
    '💥 Min 68% Off : New Balance Mens Casual Shoes',
    'New Balance Mens Casual Shoes',
    'New Balance Men Casual Shoes',
  ];

  const normalized = titles.map(t => normalizeDealTitle(t));
  console.log('Normalized Titles:');
  titles.forEach((t, i) => {
    console.log(`  "${t}" => "${normalized[i]}"`);
  });

  // Verify that all variations normalize to "new balance men casual shoe"
  const expected = 'new balance men casual shoe';
  let allMatched = true;
  for (let i = 0; i < normalized.length; i++) {
    if (normalized[i] !== expected) {
      console.error(`❌ Mismatch at index ${i}: expected "${expected}", got "${normalized[i]}"`);
      allMatched = false;
    }
  }

  if (allMatched) {
    console.log('✅ All 7 title variations normalized to EXACT same canonical title:', expected);
  } else {
    throw new Error('Title normalization test failed');
  }

  // Test similarity
  const sim = calculateTitleSimilarity(normalized[0], normalized[1]);
  console.log(`Similarity between Title 0 and Title 1: ${sim} (Expected: 1.0)`);
  if (sim !== 1.0) throw new Error('Similarity calculation test failed');

  // Test collection URL canonical extraction
  const url1 = 'https://www.flipkart.com/mens-footwear/new-balance~brand/pr?sid=osp,cil,e1f&marketplace=FLIPKART&sort=price_asc';
  const url2 = 'https://www.flipkart.com/mens-footwear/new-balance~brand/pr?sid=osp,cil,e1f&sort=recency_desc';
  const c1 = extractCanonicalDealId(url1);
  const c2 = extractCanonicalDealId(url2);
  console.log('Canonical ID 1:', c1?.id);
  console.log('Canonical ID 2:', c2?.id);
  if (!c1?.id || c1.id !== c2?.id) {
    throw new Error(`Collection canonical IDs do not match: ${c1?.id} vs ${c2?.id}`);
  }
  console.log('✅ Collection canonical IDs match perfectly:', c1.id);
  console.log('\n========================================\n');
}

runTitleNormalizationTests();

async function runTests() {
  console.log('Testing Store Rules & Amazon Upto Filter...\n');

  const testCases = [
    {
      name: 'Case 1: Amazon deal with "upto 70% off" (MUST BE FORWARDED)',
      text: '🔥 Amazon Great Sale!\nUpto 70% off on Laptops\nhttps://www.amazon.in/dp/B0CHX1W1XY',
    },
    {
      name: 'Case 2: Amazon deal with "up to 50% off" (MUST BE FORWARDED)',
      text: '🔥 Amazon Deal!\nUp to 50% off on Smartwatches\nhttps://www.amazon.in/dp/B0CHX1W1XY',
    },
    {
      name: 'Case 3: Amazon single product deal (MUST BE FORWARDED)',
      text: '🔥 Apple iPhone 15 at ₹58,999 (Flat ₹10,000 Off)\nhttps://www.amazon.in/dp/B0CHX1W1XY',
    },
    {
      name: 'Case 4: Flipkart deal with "Upto 80% off" (MUST BE FORWARDED)',
      text: '🔥 Flipkart Big Billion Days\nUpto 80% off on Fashion\nhttps://www.flipkart.com/apple-iphone-15-black-128-gb/p/itm6ac6485515ae4',
    },
    {
      name: 'Case 5: Ajio deal with "Upto 60% off" (MUST BE FORWARDED)',
      text: '🔥 Ajio Mega Sale: Upto 60% off\nhttps://www.ajio.com/s/sample-deal',
    },
    {
      name: 'Case 6: Random unapproved store (MUST BE SKIPPED)',
      text: '🔥 Random Store Loot!\nhttps://www.randomshop123.com/deal/xyz',
    },
    {
      name: 'Case 7: DealsPing dealsping.in link (MUST BE SKIPPED)',
      text: '⚡PUMA | Reeping XT 2 Mens Training Shoes | Peacoat-Faded Denim | 8UK\n💰₹1,085 (75% OFF) 🔻MRP ₹4,299\n\n🛒https://dealsping.in/amz/2609281611',
    },
    {
      name: 'Case 8: Borosil Dinner Set with direct link + long Master search link (Master link must become 👉 Check Now)',
      text: 'BOROSIL Dinner Set, 44 Pcs @ 2,897.\n\nhttps://www.amazon.in/dp/B07W8Y848L\n\nMaster https://www.amazon.in/s?rh=n%3A26953504031%2Cp_6%3AAXOGFIT0PZZ7G%2Cp_4%3Alarah%2Bby%2BBOROSIL%2Cp_n_pct-off-with-tax%3A45-&s=price-asc-rank&btn_type=ss&btn_ref=srctok-38582af3e9e789c2',
    },
    {
      name: 'Case 9: Wonderchef Kitchen Items with 🔗 and long search link (Must replace 🔗 and link with 👉 Check Now)',
      text: '💥70-78% Off On Wonderchef Kitchen Items.\n\n🔗https://www.amazon.in/s?k=Wonderchef&i=kitchen&rh=n%3A976442031%2Cp_123%3A313455%2Cp_6%3AAKWZD4S0TGH74%2Cp_n_pct-off-with-tax%3A27060457031&btn_ref=srctok-63fdd1b335d0b6b4&btn_type=ss&linkId=b4ca7daaf4d105bd6231158fc6cc5ef&ref_=as_li_ss_tl',
    },
    {
      name: 'Case 10: Meesho Loot Deal (MUST BE FORWARDED)',
      text: '💥 Meesho Kurti Loot at ₹149\nhttps://www.meesho.com/stylish-kurti/p/1op63p',
    },
    {
      name: 'Case 11: Amazon deal with amzn-to.co redirect link (MUST BE FORWARDED)',
      text: '🔥🔥 Fastrack New Limitless X2 Smart Watch, 1.91" UltraVU with Rotating Crown\n\n🎁 Deal Price : ₹1,449\n\nBuy Here : https://amzn-to.co/wCWY6r',
    },
    {
      name: 'Case 12: Clazkit Coconut Opener deal from Meesho Shopsy (MUST BE FORWARDED)',
      text: '🔥🔥Clazkit Stainless Steel Coconut Opener Tool, Coconut Driller\n\n🎁Deal Price : ₹73\n\nBuy Here : https://amzn-to.co/k810XC',
    },
    {
      name: 'Case 14: Amazon Loot Upto 92% Off On Men\'s Pants (MUST BE CONVERTED & EMBEDDED WITH 👉 Check Now)',
      text: 'Amazon Loot : Upto 92% Off On Men\'s Pants.\n\n🔗 https://amzn-to.co/5OnkZB',
    },
    {
      name: 'Case 15: Race coffee Flipkart shortlink (MUST RESOLVE TO FLIPKART PID)',
      text: '697 : https://fktr.in/T1ZjGMQ',
    },
    {
      name: 'Case 16: Multi-deal post with deep Flipkart links (MUST CONVERT TO FKTR.IN SHORT LINKS, NO CUELINKS)',
      text: 'Flipkart : Best deals on Fashion\n\nRare Rabbit Min 65% off\nhttps://dl.flipkart.com/dl/clothing-and-accessories/~cs-qsfyuh83gz/pr?sid=clo&collection-tab-name=RR+SMU&sort=popularity&src=ot&pwsvid=3DPW1791401370760S8ilHHIRVSq3sP4V&src=ot\n\nThe Bear House Under 599\nhttps://dl.flipkart.com/dl/clothing-and-accessories/topwear/shirts/~cs-qb7w8tg765/pr?sid=clo',
    },
  ];

  for (const tc of testCases) {
    console.log(`\n========================================`);
    console.log(tc.name);
    console.log(`----------------------------------------`);
    const result = await processMessageText(tc.text, {
      amazonTag: 'dealbuster002-21',
      myChannel: '@dealbusterindia',
      footer: '\n\n⚡ Join @dealbusterindia',
    });

    const validDeals = result.convertedLinks.filter(l => ['amazon', 'flipkart', 'myntra', 'ajio', 'shopsy', 'meesho'].includes(l.store));

    if (validDeals.length === 0) {
      console.log('⏩ SKIPPED: No allowed stores found (only Amazon, Flipkart, Myntra, Ajio, Shopsy, Meesho are allowed).');
      continue;
    }

    console.log('✅ FORWARDED:');
    console.log(result.text);
    console.log('Links:', validDeals.map(d => `[${d.store}] ID: ${d.id} -> ${d.convertedUrl}`).join(', '));
  }
}

runTests();
