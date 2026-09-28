import readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.resolve(__dirname, '../.env');

dotenv.config({ path: envPath });

const rl = readline.createInterface({ input, output });

async function ask(question, defaultValue = '') {
  const answer = await rl.question(question);
  return answer.trim() || defaultValue;
}

async function main() {
  console.log('========================================================');
  console.log('   DealBuster Telegram UserBot - Safe Private Login     ');
  console.log('========================================================');
  console.log('Note: All credentials stay 100% locally on your computer');
  console.log('No third-party bot or server will ever see your login.\n');

  let apiId = process.env.TELEGRAM_API_ID;
  let apiHash = process.env.TELEGRAM_API_HASH;

  if (!apiId || !apiHash) {
    console.log('To get API ID and API HASH (takes 1 minute):');
    console.log('1. Go to https://my.telegram.org');
    console.log('2. Log in with your phone number');
    console.log('3. Click "API development tools"');
    console.log('4. Create an app (put any title e.g. "DealBusterForwarder")\n');

    apiId = await ask('Enter your Telegram API_ID: ');
    apiHash = await ask('Enter your Telegram API_HASH: ');
  } else {
    console.log(`Using existing API_ID: ${apiId}`);
  }

  if (!apiId || !apiHash) {
    console.error('❌ API_ID and API_HASH are required!');
    rl.close();
    process.exit(1);
  }

  const session = new StringSession('');
  const client = new TelegramClient(session, parseInt(apiId, 10), apiHash, {
    connectionRetries: 5,
  });

  console.log('\nConnecting to Telegram...');
  await client.start({
    phoneNumber: async () => await ask('\nEnter your Telegram phone number with country code (e.g. +91XXXXXXXXXX): '),
    password: async () => await ask('\nEnter your Telegram 2FA cloud password (if enabled, otherwise press Enter): '),
    phoneCode: async () => await ask('\nEnter the login code sent to your Telegram app: '),
    onError: (err) => console.error('Telegram error:', err),
  });

  const sessionString = client.session.save();
  const me = await client.getMe();

  console.log('\n✅ Login successful!');
  console.log(`Logged in as: ${me.firstName || ''} ${me.lastName || ''} (@${me.username || me.id})`);

  // Save to .env
  let envContent = '';
  if (fs.existsSync(envPath)) {
    envContent = fs.readFileSync(envPath, 'utf8');
  }

  // Update or append values
  const setEnvVar = (content, key, val) => {
    const regex = new RegExp(`^${key}=.*$`, 'm');
    if (regex.test(content)) {
      return content.replace(regex, `${key}=${val}`);
    }
    return content ? `${content.trim()}\n${key}=${val}\n` : `${key}=${val}\n`;
  };

  envContent = setEnvVar(envContent, 'TELEGRAM_API_ID', apiId);
  envContent = setEnvVar(envContent, 'TELEGRAM_API_HASH', apiHash);
  envContent = setEnvVar(envContent, 'TELEGRAM_SESSION', sessionString);

  fs.writeFileSync(envPath, envContent, 'utf8');

  console.log(`\n🎉 Credentials saved safely to .env!`);
  console.log('You can now run: npm start');

  rl.close();
  await client.disconnect();
  process.exit(0);
}

main().catch(err => {
  console.error('\n❌ Login failed:', err.message);
  rl.close();
  process.exit(1);
});
