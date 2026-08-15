#!/usr/bin/env node
/*
 * يدفع بيانات ورقة "تشكيل الوحدة" (من ملف منسوبي الكلية الرسمي) إلى وثيقة
 * Firestore العامة public_unit_committee/current - محاكاة لما تفعله شاشة
 * إدارة منسوبي الكلية تلقائيًا عند رفع نسخة جديدة من الملف (تُستخدم هنا
 * كتشغيل أولي فقط لأن الموقع لا يملك بيانات بعد).
 */
const XLSX = require('xlsx');
const path = require('path');
const admin = require('firebase-admin');
const { initAdmin } = require('./firebase_admin_init');

const ROSTER_PATH = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'أعضاء هيئة التدريس', 'قالب البيانات النهائي .xlsx'
);

async function main() {
  const wb = XLSX.readFile(ROSTER_PATH);
  const rows = XLSX.utils.sheet_to_json(wb.Sheets['تشكيل الوحدة'], { defval: '' });
  const members = rows
    .map((r) => ({
      name: String(r['الاسم'] || '').trim(),
      department: String(r['القسم العلمي'] || '').trim(),
      role: String(r['العضوية'] || '').trim(),
      email: String(r['البريد الجامعي'] || '').trim(),
    }))
    .filter((m) => m.name);

  if (!members.length) {
    throw new Error('لم يُعثر على أي عضو في ورقة "تشكيل الوحدة".');
  }

  initAdmin();
  const db = admin.firestore();
  await db.collection('public_unit_committee').doc('current').set({
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    members,
  });

  console.log(`تم حفظ ${members.length} عضوًا في public_unit_committee/current.`);
}

main().catch((err) => {
  console.error('خطأ:', err.message);
  process.exit(1);
});
