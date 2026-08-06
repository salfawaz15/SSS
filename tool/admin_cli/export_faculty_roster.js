#!/usr/bin/env node
/*
 * One-off local tool: dumps the current live collegeRoster (faculty only)
 * from Firestore to a JSON file, joining each member's office number from
 * advisingSchedules (the only place office numbers are actually uploaded),
 * so tool/build_faculty_office_list.dart can turn it into a standalone
 * Excel file. Reuses the existing Firebase CLI login, same as the other
 * admin_cli scripts.
 *
 * Usage:
 *   node export_faculty_roster.js <output.json>
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

// يوحّد الاسم لأغراض المطابقة فقط (لا يُستخدم في الإخراج): إزالة الهمزات
// وتطبيع المسافات.
function normalizeName(name) {
  return (name || '')
    .trim()
    .replace(/^(د|أ|دكتور|دكتورة|أستاذ|أستاذة)\.?\s+/u, '')
    .replace(/[أإآ]/g, 'ا')
    .replace(/\s+/g, ' ');
}

async function collectScheduleAdvisors(db) {
  const snap = await db.collection('advisingSchedules').get();
  const advisors = []; // { name: normalized, office }
  snap.forEach((doc) => {
    const slots = doc.data().slots || [];
    for (const slot of slots) {
      for (const entry of slot.entries || []) {
        const office = (entry.office || '').trim();
        const name = normalizeName(entry.advisorName);
        if (!office || !name) continue;
        // بعض ملفات Word المصدر مفتّتة حرفًا-حرفًا بسبب تنسيق ثنائي
        // الاتجاه معطوب، ما يُنتج أحيانًا أرقام وهمية طويلة (مثل "5000")
        // بدل رقم مكتب حقيقي (كل الأرقام الحقيقية المرصودة 1-3 أرقام) -
        // تُستبعد لتفادي تلويث الناتج ببيانات غير موثوقة.
        if (/\d{4,}/.test(office)) continue;
        advisors.push({ name, office });
      }
    }
  });
  return advisors;
}

// اسم جدول الإرشاد غالبًا مختصر (بلا اسم العائلة الكامل) مقارنة بالاسم
// الكامل في قاعدة بيانات منسوبي الكلية - المطابقة بالتساوي الحرفي تفشل
// لمعظم الحالات، لذا نعتبر تطابقًا لو كانت كل كلمات اسم الجدول موجودة ضمن
// كلمات الاسم الكامل (بنفس الترتيب النسبي غير مهم).
function isSubsetMatch(shortName, fullName) {
  const shortWords = shortName.split(' ').filter(Boolean);
  const fullWords = fullName.split(' ').filter(Boolean);
  if (shortWords.length === 0) return false;
  return shortWords.every((w) => fullWords.includes(w));
}

// عضو له أكثر من رقم مكتب مختلف في أيام مختلفة يُعتبر خطأً غير طبيعي
// (بخلاف عضوين يتشاركان نفس رقم المكتب، وهذا طبيعي) - يُترك فارغًا هنا
// ويُبلَّغ عنه في conflictsLog بدل كتابة رقم عشوائي أو دمجهما.
function findOffice(advisors, fullNameNormalized, conflictsLog) {
  const candidates = advisors.filter((a) => isSubsetMatch(a.name, fullNameNormalized));
  if (candidates.length === 0) return '';
  const distinctOffices = [...new Set(candidates.map((c) => c.office))];
  if (distinctOffices.length > 1) {
    conflictsLog.push({ name: fullNameNormalized, offices: distinctOffices });
    return '';
  }
  return distinctOffices[0];
}

async function main() {
  const outPath = process.argv[2];
  // ملف اختياري إضافي (office, name) مستخرج محليًا من تقرير مُعاد تجميعه
  // (وليس ملفًا رسميًا) - يُستخدم فقط لتعبئة رقم المكتب في هذا الملف
  // الناتج تحديدًا (طلب صريح من المستخدم)، ولا يُكتب إلى advisingSchedules
  // في Firestore لأنه ليس مصدرًا معتمدًا للجدول الرسمي نفسه.
  const extraPairsPath = process.argv[3];
  if (!outPath) {
    console.log('Usage: node export_faculty_roster.js <output.json> [extra-pairs.json]');
    process.exit(1);
  }
  initAdmin();
  const db = admin.firestore();
  const snap = await db.collection('collegeRoster').doc('current').get();
  if (!snap.exists) {
    console.log('collegeRoster/current not found - is empty.');
    fs.writeFileSync(outPath, JSON.stringify([]));
    return;
  }
  const advisors = await collectScheduleAdvisors(db);
  if (extraPairsPath && fs.existsSync(extraPairsPath)) {
    const extra = JSON.parse(fs.readFileSync(extraPairsPath, 'utf8'));
    for (const { office, name } of extra) {
      if (!office || !name || /\d{4,}/.test(office)) continue;
      advisors.push({ name: normalizeName(name), office });
    }
  }
  const conflicts = [];
  const data = snap.data();
  const faculty = (data.members || [])
    .filter((m) => m.type === 'faculty')
    .map((m) => ({
      ...m,
      office: m.office && m.office.trim() ? m.office : findOffice(advisors, normalizeName(m.name), conflicts),
    }));
  const matched = faculty.filter((m) => m.office).length;
  fs.writeFileSync(outPath, JSON.stringify(faculty, null, 2));
  console.log(`Wrote ${faculty.length} faculty members to ${outPath} (offices matched: ${matched})`);
  if (conflicts.length) {
    console.log('\nتعارض في رقم المكتب (أكثر من رقم مختلف بأيام مختلفة - تُرك فارغًا):');
    for (const c of conflicts) console.log(`  ${c.name}: ${c.offices.join(' ، ')}`);
  }
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
