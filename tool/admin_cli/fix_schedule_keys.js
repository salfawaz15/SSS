#!/usr/bin/env node
/*
 * One-off fix: the advisingSchedules docs uploaded earlier used department
 * names without the correct hamza form and a shatr value without the
 * "شطر " prefix (e.g. "قسم الادارة"/"طلاب"), which don't match the exact
 * strings the app's admin screen uses to build the doc ID
 * (CourseCatalog.departments + ExcelParserService.shatrMale/Female, e.g.
 * "قسم الإدارة"/"شطر الطلاب") - so none of that data was actually
 * reachable from the site. Re-saves every doc under the correct doc ID and
 * deletes the old mismatched one.
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
  return JSON.parse(fs.readFileSync(configPath, 'utf8')).tokens.refresh_token;
}
function initAdmin() {
  const refreshToken = loadFirebaseCliRefreshToken();
  const adcPath = path.join(os.tmpdir(), `sss-advising-adc-${process.pid}.json`);
  fs.writeFileSync(adcPath, JSON.stringify({
    type: 'authorized_user', client_id: FIREBASE_CLI_CLIENT_ID, client_secret: FIREBASE_CLI_CLIENT_SECRET, refresh_token: refreshToken,
  }));
  process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
}

const DEPT_MAP = {
  'قسم الادارة': 'قسم الإدارة',
  'قسم نظم المعلومات': 'قسم نظم المعلومات الإدارية',
  'قسم الاقتصاد': 'قسم الاقتصاد والتمويل',
  'قسم التسويق': 'قسم التسويق',
  'قسم المحاسبة': 'قسم المحاسبة',
};
const SHATR_MAP = { 'طلاب': 'شطر الطلاب', 'طالبات': 'شطر الطالبات' };

async function main() {
  initAdmin();
  const db = admin.firestore();
  const col = db.collection('advisingSchedules');
  const snap = await col.get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const newDept = DEPT_MAP[data.department] || data.department;
    const newShatr = SHATR_MAP[data.shatr] || data.shatr;
    const newId = `${newDept}_${newShatr}`;
    if (newId === doc.id) {
      console.log(`OK بالفعل: ${doc.id}`);
      continue;
    }
    await col.doc(newId).set({
      department: newDept,
      shatr: newShatr,
      uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
      slots: data.slots,
    });
    await col.doc(doc.id).delete();
    console.log(`${doc.id}  ->  ${newId}`);
  }
}

main().catch((err) => { console.error('Error:', err.message); process.exit(1); });
