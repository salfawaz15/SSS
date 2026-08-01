#!/usr/bin/env node
/*
 * One-off local tool: creates the 2 college-coordinator Firebase Auth
 * accounts (male/female track - Adel/Heba) + their college_coordinator_accounts
 * Firestore docs. Reuses your existing Firebase CLI login, same as
 * manage_users.js - no service account key needed.
 *
 * Usage:
 *   node create_college_coordinators.js
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const PROJECT_ID = 'sss-advising-tu';
const DOMAIN = 'sss-advising-tu.internal';

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

const accounts = [
  {
    email: `college-coordinator-male@${DOMAIN}`,
    password: 'CollegeCoord2026!M',
    shatr: 'شطر الطلاب',
    label: 'عادل علي محمد حسن (منسّق الكلية - شطر الطلاب)',
  },
  {
    email: `college-coordinator-female@${DOMAIN}`,
    password: 'CollegeCoord2026!F',
    shatr: 'شطر الطالبات',
    label: 'هبة الله عبدالصبور أمين حسن (منسّقة الكلية - شطر الطالبات)',
  },
];

async function main() {
  initAdmin();
  const db = admin.firestore();

  for (const acc of accounts) {
    let user;
    try {
      user = await admin.auth().getUserByEmail(acc.email);
      await admin.auth().updateUser(user.uid, { password: acc.password });
      console.log(`Account already existed - password reset: ${acc.label} (${acc.email})`);
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        user = await admin.auth().createUser({ email: acc.email, password: acc.password });
        console.log(`Created account: ${acc.label} (${acc.email}), uid: ${user.uid}`);
      } else {
        throw e;
      }
    }

    await db.collection('college_coordinator_accounts').doc(user.uid).set({ shatr: acc.shatr });
    console.log(`  -> college_coordinator_accounts/${user.uid} = { shatr: '${acc.shatr}' }`);
  }

  console.log('\nDone. Login credentials:');
  for (const acc of accounts) {
    console.log(`  ${acc.label}: ${acc.email} / ${acc.password}`);
  }
  console.log('\nRemind both accounts to change their password after first login (portal supports this).');
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
