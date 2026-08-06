#!/usr/bin/env node
/*
 * One-off read-only check: reports document counts/sizes for collegeRoster,
 * courseSchedules, and advisingSchedules, to confirm what's actually stored
 * right now. Reuses the existing Firebase CLI login.
 *
 * Usage:
 *   node check_data.js
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

  const checks = [
    { collection: 'collegeRoster', doc: 'current', countField: 'membersCount' },
    { collection: 'courseSchedules', doc: 'male', countField: 'sectionsCount' },
    { collection: 'courseSchedules', doc: 'female', countField: 'sectionsCount' },
    { collection: 'advisingSchedules', doc: null, countField: null },
  ];

  for (const c of checks) {
    if (c.doc) {
      const snap = await db.collection(c.collection).doc(c.doc).get();
      if (!snap.exists) {
        console.log(`${c.collection}/${c.doc}: NOT FOUND (empty)`);
      } else {
        const data = snap.data();
        console.log(`${c.collection}/${c.doc}: EXISTS - ${c.countField}=${data[c.countField]}, uploadedAt=${data.uploadedAt ? data.uploadedAt.toDate().toISOString() : 'n/a'}`);
      }
    } else {
      const snap = await db.collection(c.collection).get();
      console.log(`${c.collection}: ${snap.size} document(s) - ${snap.docs.map((d) => d.id).join(', ')}`);
    }
  }
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
