#!/usr/bin/env node
/*
 * One-off read-only check: confirms whether a coordinator_accounts doc
 * exists for a given Firebase Auth email, and what shatr/department it maps
 * to. Reuses the existing Firebase CLI login.
 *
 * Usage:
 *   node check_coordinator_account.js <email>
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const PROJECT_ID = 'sss-advising-tu';

const FIREBASE_CLI_CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const FIREBASE_CLI_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

function loadFirebaseCliRefreshToken() {
  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(configPath)) {
    throw new Error('Could not find a Firebase CLI session. Run "firebase login" first.');
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const refreshToken = config.tokens && config.tokens.refresh_token;
  if (!refreshToken) {
    throw new Error('Could not read Firebase CLI credentials. Run "firebase login" again.');
  }
  return refreshToken;
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
  process.on('exit', () => {
    try {
      fs.unlinkSync(adcPath);
    } catch {
      // ignore - temp file only
    }
  });

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

async function main() {
  const email = process.argv[2];
  if (!email) {
    console.error('Usage: node check_coordinator_account.js <email>');
    process.exit(1);
  }

  initAdmin();
  const auth = admin.auth();
  const db = admin.firestore();

  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch (e) {
    console.log(`Auth user NOT FOUND for ${email}: ${e.message}`);
    return;
  }
  console.log(`Auth user found: uid=${user.uid}`);

  const doc = await db.collection('coordinator_accounts').doc(user.uid).get();
  if (!doc.exists) {
    console.log(`coordinator_accounts/${user.uid}: NOT FOUND (this is why the page is blank)`);
  } else {
    console.log(`coordinator_accounts/${user.uid}: EXISTS - ${JSON.stringify(doc.data())}`);
  }
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
