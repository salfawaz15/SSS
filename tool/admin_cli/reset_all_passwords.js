#!/usr/bin/env node
/*
 * One-off: resets every account's password to a fixed value, except
 * salfawaz (super admin), per Sulaiman's explicit request. Reuses the
 * Firebase CLI login, same pattern as manage_users.js.
 *
 * Usage:
 *   node reset_all_passwords.js
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const PROJECT_ID = 'sss-advising-tu';
const DOMAIN = 'sss-advising-tu.internal';
const NEW_PASSWORD = '00000000';
const EXCLUDE_EMAIL = `salfawaz@${DOMAIN}`;

const FIREBASE_CLI_CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const FIREBASE_CLI_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

function loadFirebaseCliRefreshToken() {
  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  return config.tokens.refresh_token;
}

function initAdmin() {
  const refreshToken = loadFirebaseCliRefreshToken();
  const adcPath = path.join(os.tmpdir(), `sss-advising-adc-${process.pid}.json`);
  fs.writeFileSync(
    adcPath,
    JSON.stringify({
      type: 'authorized_user',
      client_id: FIREBASE_CLI_CLIENT_ID,
      client_secret: FIREBASE_CLI_CLIENT_SECRET,
      refresh_token: refreshToken,
    })
  );
  process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  process.on('exit', () => { try { fs.unlinkSync(adcPath); } catch {} });

  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
}

async function main() {
  initAdmin();
  const result = await admin.auth().listUsers(1000);
  console.log(`Total accounts: ${result.users.length}\n`);

  for (const user of result.users) {
    if (user.email === EXCLUDE_EMAIL) {
      console.log(`SKIPPED (excluded): ${user.email}`);
      continue;
    }
    await admin.auth().updateUser(user.uid, { password: NEW_PASSWORD });
    console.log(`Password reset: ${user.email}`);
  }

  console.log('\nDone.');
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
