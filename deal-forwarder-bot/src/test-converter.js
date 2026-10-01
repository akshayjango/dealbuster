import { processMessageText, isAmazonUptoDeal } from './converter.js';

async function runTests() {
  console.log('Testing Store Rules & Amazon Upto Filter...\n');

  const testCases = [
    {
      name: 'Case 1: Amazon deal with "upto 70% off" (MUST BE SKIPPED)',
      text: '🔥 Amazon Great Sale!\nUpto 70% off on Laptops\nhttps://www.amazon.in/dp/B0CHX1W1XY',
    },
    {
      name: 'Case 2: Amazon deal with "up to 50% off" (MUST BE SKIPPED)',
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
      name: 'Case 7: DealsPing Puma shoes Amazon deal (MUST CONVERT DIRECTLY TO AMAZON WITH TAG, NEVER DEALSPING)',
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

    const validDeals = result.convertedLinks.filter(l => ['amazon', 'flipkart', 'myntra', 'ajio', 'shopsy'].includes(l.store));

    if (validDeals.length === 0) {
      console.log('⏩ SKIPPED: No allowed stores found (only Amazon, Flipkart, Myntra, Ajio, Shopsy are allowed).');
      continue;
    }

    const hasAmazonDeal = validDeals.some(l => l.store === 'amazon');
    if (hasAmazonDeal && isAmazonUptoDeal(tc.text)) {
      console.log('⏩ SKIPPED: Amazon deal contains "upto" or variable discount text.');
      continue;
    }

    console.log('✅ FORWARDED:');
    console.log(result.text);
    console.log('Links:', validDeals.map(d => `[${d.store}] ${d.convertedUrl}`).join(', '));
  }
}

runTests();
