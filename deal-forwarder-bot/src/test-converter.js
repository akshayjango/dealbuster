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
