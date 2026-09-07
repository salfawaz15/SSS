#!/usr/bin/env node
/*
 * سليمان صراحةً 2026-09-08: كل حالات الحذف/الإضافة في الشطرين تم الانتهاء من
 * معالجتها فعليًا هذا الفصل (الحالات العاجلة عُولجت فردًا فردًا عبر الملفات
 * المدمَجة/المراجَعة، والباقي حالات لا تتطلب تدخلاً وتُعتبر "معالَجة" ضمنيًا
 * بقرار عدم التدخل) - ما عدا طالبين اثنين بشطر الطلاب معلّقين فعليًا (غياب عن
 * اختبار، بانتظار التأكد من العذر).
 *
 * يمرّ على كل تذاكر Firestore (كلا الشطرين) ويضع college_status = 'تم
 * الإنجاز' لكل إجراء لا يزال معلّقًا (effectiveStatus ليست مكتملة أصلاً -
 * مرشد/منسق قسم أنجزها مسبقًا يبقى كما هو، لا إعادة كتابة)، باستثناء إجراءات
 * الطالبين المستثنيين بالاسم أدناه.
 *
 * التشغيل التجريبي أولاً: node tool/admin_cli/finalize_all_remaining_cases.js --dry-run
 * التنفيذ الفعلي: node tool/admin_cli/finalize_all_remaining_cases.js
 */
const { initAdmin } = require('./firebase_admin_init');

const EXCLUDED_STUDENT_IDS = new Set(['44455008', '44208229']);

function effectiveStatus(action) {
  const college = (action.college_status || '').toString().trim();
  if (college) return college;
  const coord = (action.coordinator_status || '').toString().trim();
  if (coord) return coord;
  return (action.advisor_status || '').toString().trim();
}

function isCompleted(status) {
  return status === 'تم الإنجاز' || status === 'تم التنفيذ';
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  if (dryRun) console.log('*** وضع تجريبي (dry-run) - لن يُكتب أي شيء فعليًا بـFirestore ***\n');

  initAdmin();
  const db = require('firebase-admin').firestore();
  const col = db.collection('tickets');

  const snap = await col.get();
  console.log(`عدد التذاكر الكلي: ${snap.size}`);

  let ticketsChanged = 0;
  let actionsFinalized = 0;
  let actionsExcluded = 0;
  const excludedStudentsSeen = new Set();

  let batch = db.batch();
  let batchOps = 0;
  const commitIfNeeded = async () => {
    if (batchOps >= 400) {
      if (!dryRun) await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  };

  for (const doc of snap.docs) {
    const data = doc.data();
    const universityId = (data.university_id || doc.id || '').toString();
    const actions = data.actions;
    if (!Array.isArray(actions) || actions.length === 0) continue;

    if (EXCLUDED_STUDENT_IDS.has(universityId)) {
      excludedStudentsSeen.add(universityId);
      const pendingCount = actions.filter((a) => !isCompleted(effectiveStatus(a))).length;
      actionsExcluded += pendingCount;
      continue;
    }

    let changed = false;
    const newActions = actions.map((a) => {
      const action = { ...a };
      if (!isCompleted(effectiveStatus(action))) {
        action.college_status = 'تم الإنجاز';
        changed = true;
        actionsFinalized++;
      }
      return action;
    });

    if (changed) {
      ticketsChanged++;
      batch.update(doc.ref, { actions: newActions });
      batchOps++;
      await commitIfNeeded();
    }
  }

  if (batchOps > 0 && !dryRun) await batch.commit();

  console.log(`\n${dryRun ? '(تجريبي) سيتم' : 'تم'} تحديث ${ticketsChanged} تذكرة.`);
  console.log(`عدد الإجراءات التي ${dryRun ? 'سيُوضع' : 'وُضع'} لها "تم الإنجاز": ${actionsFinalized}`);
  console.log(`عدد الإجراءات المعلّقة المستثناة (الطالبان): ${actionsExcluded}`);
  console.log(`الطلاب المستثنَون الفعليون الموجودون فعلاً بقاعدة البيانات: ${[...excludedStudentsSeen].join(', ') || '(لم يُعثر عليهما)'}`);
}

main().catch((err) => {
  console.error('خطأ:', err);
  process.exit(1);
});
