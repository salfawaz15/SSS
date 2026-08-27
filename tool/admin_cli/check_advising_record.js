#!/usr/bin/env node
/*
 * One-off local tool: looks up specific student IDs inside the live
 * "كل الكليات" report (advisingAllCollegesReports/{male|female}/chunks) and
 * prints the EXACT stored AdvisingCaseRecord JSON fields - used to diagnose
 * column-misalignment bugs precisely instead of guessing from the UI.
 *
 * Usage:
 *   node check_advising_record.js <shatrDocId: male|female> <studentId1> [studentId2 ...]
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const PROJECT_ID = 'sss-advising-tu';
const FIREBASE_CLI_CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
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
  fs.writeFileSync(adcPath, JSON.stringify({
    type: 'authorized_user',
    client_id: FIREBASE_CLI_CLIENT_ID,
    client_secret: FIREBASE_CLI_CLIENT_SECRET,
    refresh_token: refreshToken,
  }));
  process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  process.on('exit', () => {
    try { fs.unlinkSync(adcPath); } catch {}
  });
  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
}

async function main() {
  const [shatrDocId, ...ids] = process.argv.slice(2);
  if (!shatrDocId || ids.length === 0) {
    console.error('Usage: node check_advising_record.js <male|female> <studentId1> [studentId2 ...]');
    process.exit(1);
  }
  initAdmin();
  const db = admin.firestore();
  const chunksSnap = await db.collection('advisingAllCollegesReports').doc(shatrDocId).collection('chunks').get();
  console.log(`Chunks found: ${chunksSnap.docs.length}`);
  const idsSet = new Set(ids);
  let totalRecords = 0;
  for (const chunkDoc of chunksSnap.docs) {
    const records = chunkDoc.data().records || [];
    totalRecords += records.length;
    for (const r of records) {
      if (idsSet.has(String(r.studentId))) {
        console.log(`--- chunk ${chunkDoc.id} ---`);
        console.log(JSON.stringify(r, null, 2));
      }
    }
  }
  console.log(`Total records scanned: ${totalRecords}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
