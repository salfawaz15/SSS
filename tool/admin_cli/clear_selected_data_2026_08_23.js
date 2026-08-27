#!/usr/bin/env node
/*
 * One-off script (2026-08-23): سليمان طلب صراحةً حذف كل البيانات الحالية
 * من 3 فئات فقط ليعيد رفع كل شيء من جديد:
 *   1) tickets (حالات الحذف والإضافة) - كل المستندات.
 *   2) advisingAllCollegesReports + advisingAllCollegesReportsPrevious
 *      (الإرشاد الكامل - كل الكليات) لكلا الشطرين، بما فيها مجموعات chunks
 *      الفرعية.
 *   3) courseSchedules (المقررات الدراسية - الحويّة) لكلا الشطرين.
 * لا يمسّ أي مجموعة أخرى (collegeRoster/advisingHealthReports/
 * advisingSchedules/hardship_cases/support_cases...). نفس آلية مصادقة
 * Firebase CLI الموجودة أصلاً بـclear_test_data.js.
 *
 * Usage:
 *   node clear_selected_data_2026_08_23.js
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

async function deleteCollection(db, collectionPath, batchSize = 300) {
  const collRef = db.collection(collectionPath);
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await collRef.limit(batchSize).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    total += snap.size;
  }
  return total;
}

async function deleteDocWithChunks(db, collection, docId) {
  const docRef = db.collection(collection).doc(docId);
  const chunksDeleted = await deleteCollection(db, `${collection}/${docId}/chunks`);
  const snap = await docRef.get();
  if (snap.exists) {
    await docRef.delete();
    console.log(`${collection}/${docId}: deleted (chunks removed: ${chunksDeleted}).`);
  } else {
    console.log(`${collection}/${docId}: already empty (not found), chunks removed: ${chunksDeleted}.`);
  }
}

async function main() {
  initAdmin();
  const db = admin.firestore();

  // 1) حالات الحذف والإضافة
  const ticketsDeleted = await deleteCollection(db, 'tickets');
  console.log(`tickets: ${ticketsDeleted} مستند محذوف.`);

  // 2) الإرشاد الكامل (كل الكليات) - الحالي والسابق، كلا الشطرين
  for (const collection of ['advisingAllCollegesReports', 'advisingAllCollegesReportsPrevious']) {
    for (const docId of ['male', 'female']) {
      await deleteDocWithChunks(db, collection, docId);
    }
  }

  // 3) المقررات الدراسية (الحويّة)
  for (const docId of ['male', 'female']) {
    const ref = db.collection('courseSchedules').doc(docId);
    const snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      console.log(`courseSchedules/${docId}: deleted.`);
    } else {
      console.log(`courseSchedules/${docId}: already empty (not found), skipping.`);
    }
  }

  console.log('Done. tickets + advisingAllCollegesReports(+Previous) + courseSchedules cleared. Everything else left untouched.');
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
