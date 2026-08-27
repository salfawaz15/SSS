#!/usr/bin/env node
/*
 * One-off read-only check: dumps ticket count/shape for one department, and
 * roster size, to reproduce what the coordinator dashboard would receive.
 *
 * Usage:
 *   node check_department_tickets.js "<shatr>" "<department>"
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
  process.on('exit', () => {
    try { fs.unlinkSync(adcPath); } catch {}
  });

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

async function main() {
  const shatr = process.argv[2];
  const department = process.argv[3];
  if (!shatr || !department) {
    console.error('Usage: node check_department_tickets.js "<shatr>" "<department>"');
    process.exit(1);
  }

  initAdmin();
  const db = admin.firestore();

  const snap = await db.collection('tickets')
    .where('shatr', '==', shatr)
    .where('department', '==', department)
    .get();

  console.log(`tickets for ${department} / ${shatr}: ${snap.size} document(s)`);
  if (snap.size > 0) {
    console.log('Sample doc keys:', Object.keys(snap.docs[0].data()));
    console.log('Sample doc:', JSON.stringify(snap.docs[0].data(), null, 2).slice(0, 1500));
  }

  const rosterSnap = await db.collection('advisor_roster').get();
  console.log(`advisor_roster total docs: ${rosterSnap.size}`);
  const deptRoster = rosterSnap.docs.filter((d) => d.data().department === department);
  console.log(`advisor_roster docs for this department: ${deptRoster.length}`);
  if (deptRoster.length > 0) {
    console.log('Sample roster doc:', JSON.stringify(deptRoster[0].data(), null, 2));
  }

  const coordAccounts = await db.collection('coordinator_accounts').get();
  console.log(`coordinator_accounts total docs: ${coordAccounts.size}`);
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
