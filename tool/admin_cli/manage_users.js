#!/usr/bin/env node
/*
 * Local secret tool to manage the web portal's Firebase Auth accounts
 * (list / create / delete / change password for any account instantly).
 *
 * Runs ONLY on your own machine - never deployed with the website. Reuses
 * your existing Firebase CLI login (no service account key, no Blaze plan
 * needed, no extra cost).
 *
 * Usage:
 *   1) Once:  npm install          (inside this tool/admin_cli folder)
 *   2) Make sure you're logged in: firebase login
 *   3) Run:   node manage_users.js
 *
 * Note: output is kept in plain English on purpose - Windows cmd.exe often
 * garbles Arabic UTF-8 text.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const admin = require('firebase-admin');

const PROJECT_ID = 'sss-advising-tu';
const DOMAIN = 'sss-advising-tu.internal';

// Firebase CLI's own public OAuth client (published in firebase-tools'
// open-source repo) - used only to reuse your existing refresh_token
// (stored locally after `firebase login`), no extra login needed.
const FIREBASE_CLI_CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const FIREBASE_CLI_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

/** Friendly labels for known accounts instead of raw internal emails. */
const KNOWN_LABELS = {
  [`admin@${DOMAIN}`]: 'Admin (full access)',
  [`salfawaz@${DOMAIN}`]: 'salfawaz (super admin)',
  [`ameen@${DOMAIN}`]: 'Ameen Al-Wehda (viewer)',
  [`secretary@${DOMAIN}`]: 'Unit Secretary (viewer)',
  [`idara-male@${DOMAIN}`]: 'Idara dept - Male track',
  [`idara-female@${DOMAIN}`]: 'Idara dept - Female track',
  [`accounting-male@${DOMAIN}`]: 'Accounting dept - Male track',
  [`accounting-female@${DOMAIN}`]: 'Accounting dept - Female track',
  [`marketing-male@${DOMAIN}`]: 'Marketing dept - Male track',
  [`marketing-female@${DOMAIN}`]: 'Marketing dept - Female track',
  [`economy-male@${DOMAIN}`]: 'Economy & Finance dept - Male track',
  [`economy-female@${DOMAIN}`]: 'Economy & Finance dept - Female track',
  [`mis-male@${DOMAIN}`]: 'MIS dept - Male track',
  [`mis-female@${DOMAIN}`]: 'MIS dept - Female track',
  [`college-coordinator-male@${DOMAIN}`]: 'College coordinator - Male track (Adel)',
  [`college-coordinator-female@${DOMAIN}`]: 'College coordinator - Female track (Heba)',
};

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

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (question) => new Promise((resolve) => rl.question(question, resolve));

function label(email) {
  return KNOWN_LABELS[email] ? `${KNOWN_LABELS[email]}  (${email})` : email;
}

async function listUsers() {
  const result = await admin.auth().listUsers(1000);
  console.log(`\nTotal accounts: ${result.users.length}\n`);
  for (const user of result.users) {
    console.log(`- ${label(user.email)}`);
  }
  console.log('');
}

async function changePassword() {
  const email = (await ask('Account email (e.g. salfawaz@sss-advising-tu.internal): ')).trim();
  const newPassword = (await ask('New password: ')).trim();
  if (newPassword.length < 6) {
    console.log('Password must be at least 6 characters.\n');
    return;
  }
  const user = await admin.auth().getUserByEmail(email);
  await admin.auth().updateUser(user.uid, { password: newPassword });
  console.log(`Password updated successfully for: ${label(email)}\n`);
}

async function createUser() {
  const email = (await ask('New account email: ')).trim();
  const password = (await ask('Password: ')).trim();
  if (password.length < 6) {
    console.log('Password must be at least 6 characters.\n');
    return;
  }
  const user = await admin.auth().createUser({ email, password });
  console.log(`Account created: ${label(email)} (uid: ${user.uid})\n`);
}

async function deleteUser() {
  const email = (await ask('Account email to delete: ')).trim();
  const confirm = (await ask(`Confirm PERMANENT deletion of ${email}? Type "delete" to confirm: `)).trim();
  if (confirm !== 'delete') {
    console.log('Cancelled.\n');
    return;
  }
  const user = await admin.auth().getUserByEmail(email);
  await admin.auth().deleteUser(user.uid);
  console.log(`Deleted account: ${email}\n`);
}

async function setupSalfawaz() {
  const email = `salfawaz@${DOMAIN}`;
  const password = (await ask('Password for salfawaz (press Enter for 0551751515): ')).trim() || '0551751515';
  try {
    const existing = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(existing.uid, { password });
    console.log(`Account already existed - password updated: ${label(email)}\n`);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const user = await admin.auth().createUser({ email, password });
      console.log(`Created salfawaz account (uid: ${user.uid})\n`);
    } else {
      throw e;
    }
  }
}

async function main() {
  console.log('=== Academic Guidance Unit - Account Manager (local & secret) ===\n');
  initAdmin();

  let running = true;
  while (running) {
    console.log('Choose an action:');
    console.log('  1) List all accounts');
    console.log('  2) Change password for an account');
    console.log('  3) Create a new account');
    console.log('  4) Delete an account');
    console.log('  5) Setup / update salfawaz (super admin) account');
    console.log('  0) Exit');
    const choice = (await ask('> ')).trim();
    try {
      switch (choice) {
        case '1':
          await listUsers();
          break;
        case '2':
          await changePassword();
          break;
        case '3':
          await createUser();
          break;
        case '4':
          await deleteUser();
          break;
        case '5':
          await setupSalfawaz();
          break;
        case '0':
          running = false;
          break;
        default:
          console.log('Unknown option.\n');
      }
    } catch (err) {
      console.log(`Error: ${err.message}\n`);
    }
  }

  rl.close();
}

main();
