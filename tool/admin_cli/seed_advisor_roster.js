#!/usr/bin/env node
/*
 * One-off local tool: replaces the entire advisor_roster Firestore collection
 * with the data generated from "أعضاء_هيئة_التدريس_كلية_إدارة_الأعمال.xlsx"
 * (the college's official faculty list), so the coordinator-relief
 * redistribution in AdvisorZipService has a real pool of advisors per
 * department/shatr to distribute cases to. Reuses your existing Firebase CLI
 * login, same as manage_users.js - no service account key needed.
 *
 * Usage:
 *   node seed_advisor_roster.js <path-to-roster.json>
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
  const jsonPath = process.argv[2];
  if (!jsonPath) {
    console.log('Usage: node seed_advisor_roster.js <path-to-roster.json>');
    process.exit(1);
  }
  const entries = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  console.log(`Loaded ${entries.length} advisor entries from ${jsonPath}`);

  initAdmin();
  const db = admin.firestore();
  const col = db.collection('advisor_roster');

  const existing = await col.get();
  console.log(`Deleting ${existing.size} existing advisor_roster documents...`);
  const deleteBatch = db.batch();
  existing.docs.forEach((doc) => deleteBatch.delete(doc.ref));
  await deleteBatch.commit();

  console.log(`Writing ${entries.length} new advisor_roster documents...`);
  let batch = db.batch();
  let count = 0;
  for (const entry of entries) {
    const ref = col.doc();
    batch.set(ref, {
      name: entry.name,
      department: entry.department,
      shatr: entry.shatr,
      is_coordinator: !!entry.is_coordinator,
    });
    count++;
    if (count % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();

  console.log(`Done. advisor_roster now has ${entries.length} entries.`);
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
