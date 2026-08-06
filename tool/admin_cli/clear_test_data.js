#!/usr/bin/env node
/*
 * One-off local tool: clears ONLY the collegeRoster (faculty roster) and
 * courseSchedules (الحويّة) collections, so the user can test the upload
 * flow from a clean state. Does NOT touch advisingSchedules or any other
 * collection. Reuses the existing Firebase CLI login, same as
 * seed_advisor_roster.js / manage_users.js.
 *
 * Usage:
 *   node clear_test_data.js
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
  initAdmin();
  const db = admin.firestore();

  const targets = [
    { collection: 'collegeRoster', doc: 'current' },
    { collection: 'courseSchedules', doc: 'male' },
    { collection: 'courseSchedules', doc: 'female' },
  ];

  for (const t of targets) {
    const ref = db.collection(t.collection).doc(t.doc);
    const snap = await ref.get();
    if (!snap.exists) {
      console.log(`${t.collection}/${t.doc}: already empty (not found), skipping.`);
      continue;
    }
    await ref.delete();
    console.log(`${t.collection}/${t.doc}: deleted.`);
  }

  console.log('Done. collegeRoster and courseSchedules cleared. advisingSchedules and everything else left untouched.');
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
