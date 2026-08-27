#!/usr/bin/env node
/*
 * One-off migration: يحسب توزيع الحالات الثلاث (منتظم/مفصول أكاديميًا/منقطع
 * عن الدراسة) لبيانات "advisingReports" (base) الحالية المرفوعة مسبقًا (قبل
 * إضافة حقول regularCount/dismissedCount/withdrawnCount لـ
 * AdvisingReportRepository.save) ويكتبها مباشرة على المستند الرئيسي لكل شطر
 * - بلا حاجة لإعادة رفع الملفات الستة. بعد هذا التشغيل، صفحة "رفع وتنزيل
 * الملفات" تقرأ هذه الحقول مباشرة (قراءة خفيفة) بدل تحميل كل السجلات (كان
 * يُجمِّد الصفحة فعليًا - سليمان 2026-08-27).
 *
 * Usage: node backfill_academic_status_counts.js
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

async function backfillShatr(db, shatrDocId) {
  const docRef = db.collection('advisingReports').doc(shatrDocId);
  const chunksSnap = await docRef.collection('chunks').get();
  let regular = 0;
  let dismissed = 0;
  let withdrawn = 0;
  let total = 0;
  for (const chunkDoc of chunksSnap.docs) {
    const records = chunkDoc.data().records || [];
    total += records.length;
    for (const r of records) {
      const status = (r.enrollmentStatus || '').trim();
      if (status.includes('مفصول')) dismissed++;
      else if (status.includes('منقطع')) withdrawn++;
      else regular++;
    }
  }
  await docRef.set({ regularCount: regular, dismissedCount: dismissed, withdrawnCount: withdrawn }, { merge: true });
  console.log(`${shatrDocId}: total=${total} regular=${regular} dismissed=${dismissed} withdrawn=${withdrawn}`);
}

async function main() {
  initAdmin();
  const db = admin.firestore();
  await backfillShatr(db, 'male');
  await backfillShatr(db, 'female');
  console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
