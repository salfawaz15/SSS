#!/usr/bin/env node
/*
 * One-off local tool: looks up specific names in the live collegeRoster
 * (Firestore collegeRoster/current) and prints their raw stored fields
 * (department, position, employeeStatus, type) - used to diagnose whether a
 * name that looks unfamiliar to سليمان is actually present in the uploaded
 * roster file (data-entry issue upstream) or a code matching bug.
 *
 * Usage:
 *   node check_roster_names.js "الاسم الأول" "الاسم الثاني" ...
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

function looseKey(s) {
  return (s || '')
    .trim()
    .replace(/\s+/g, '')
    .replace(/[أإآ]/g, 'ا');
}

async function main() {
  const targets = process.argv.slice(2);
  if (targets.length === 0) {
    console.error('Usage: node check_roster_names.js "name1" "name2" ...');
    process.exit(1);
  }
  initAdmin();
  const db = admin.firestore();
  const doc = await db.collection('collegeRoster').doc('current').get();
  if (!doc.exists) {
    console.log('collegeRoster/current does not exist.');
    return;
  }
  const members = doc.data().members || [];
  console.log(`Total members in roster: ${members.length}\n`);
  for (const target of targets) {
    const key = looseKey(target);
    const matches = members.filter((m) => looseKey(m.name).includes(key) || key.includes(looseKey(m.name)));
    console.log(`--- "${target}" (${matches.length} match(es)) ---`);
    for (const m of matches) {
      console.log(JSON.stringify({
        name: m.name,
        type: m.type,
        department: m.department,
        position: m.position,
        position2: m.position2,
        employeeStatus: m.employeeStatus,
        staffNumber: m.staffNumber,
        shatr: m.shatr,
      }, null, 2));
    }
    if (matches.length === 0) console.log('(not found in roster)');
    console.log('');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
