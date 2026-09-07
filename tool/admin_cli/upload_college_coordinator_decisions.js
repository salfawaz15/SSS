#!/usr/bin/env node
/*
 * يرفع قرارات منسّق/ة الكلية (المكتوبة يدويًا بملفات "طلبات عاجلة" الناتجة عن
 * emergency_college_priority_split.js بعد التعديل والمراجعة اليدوية) إلى
 * Firestore مباشرة - يحدّث فقط action.college_status/college_notes لكل
 * إجراء مطابَق (نفس منطق looseActionKey/looseActionKeyFromAction الموجود في
 * emergency_college_priority_split.js)، بلا مساس بأي حقل آخر (advisor_status/
 * coordinator_status/غيرها تبقى كما هي).
 *
 * التشغيل: node tool/admin_cli/upload_college_coordinator_decisions.js
 */
const ExcelJS = require('exceljs');
const { initAdmin } = require('./firebase_admin_init');

const SHATR_MALE = 'شطر الطلاب';
const SHATR_FEMALE = 'شطر الطالبات';

// الملفان الفعليان الجاهزان بعد المراجعة والدمج اليدوي.
const SOURCES = [
  {
    shatr: SHATR_FEMALE,
    filePath: 'C:/Users/salfa/Desktop/حالات_عاجلة_شطر_الطالبات_مدمج.xlsx',
    // كل الشيتات تعتبر مراجَعة بالكامل بالنسبة لشطر الطالبات.
    excludeSheets: [],
    excludeStudentIds: [],
  },
  {
    shatr: SHATR_MALE,
    filePath: 'C:/Users/salfa/Desktop/حالات عاجلة_شطر_الطلاب Sulaiman - مراجعة - ملاحظات - مسق الكلية.xlsx',
    // شيت "البقية" لم يُراجَع (حالات لا تتطلب تدخل بسبب ضيق الوقت) - يُستبعَد صراحةً.
    excludeSheets: ['4-البقية'],
    // الحالتان المعلّقتان (غياب عن اختبار + فرصة اختبار بديل) - سليمان صراحةً
    // 2026-09-08: تبقيان معلّقتين حتى التأكد من وجود عذر.
    excludeStudentIds: ['44455008', '44208229'],
  },
];

function looseActionKey(actionType, courseCode, currentSection, requiredSection) {
  return [actionType, courseCode, currentSection, requiredSection]
    .map((v) => (v || '').toString().trim())
    .join('||');
}

function looseActionKeyFromAction(action) {
  return looseActionKey(
    action.action_type,
    action.course_code,
    action.current_section,
    action.required_section,
  );
}

async function readDecisionRows({ filePath, excludeSheets, excludeStudentIds }) {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(filePath);
  const rows = [];
  for (const sheet of workbook.worksheets) {
    if (excludeSheets.includes(sheet.name)) {
      console.log(`  (تجاهُل شيت "${sheet.name}" - غير مراجَع)`);
      continue;
    }
    const col = {};
    sheet.getRow(1).eachCell((cell, colNumber) => {
      col[cell.value ? cell.value.toString().trim() : ''] = colNumber;
    });
    const cell = (row, header) => {
      const idx = col[header];
      if (!idx) return '';
      const v = row.getCell(idx).value;
      if (v === null || v === undefined) return '';
      if (typeof v === 'object' && v.richText) return v.richText.map((t) => t.text).join('');
      return v.toString().trim();
    };

    for (let r = 2; r <= sheet.rowCount; r++) {
      const row = sheet.getRow(r);
      const universityId = cell(row, 'الرقم الجامعي');
      if (!universityId) continue;
      if (excludeStudentIds.includes(universityId)) continue;

      const note = cell(row, 'ملاحظة منسّق الكلية');
      const status = cell(row, 'حالة منسّق الكلية');
      // "أي ملاحظة (أو حالة صريحة) = قرار اتُّخذ فعليًا" - سليمان صراحةً 2026-09-08.
      if (!note && !status) continue;

      rows.push({
        sheet: sheet.name,
        row: r,
        universityId,
        actionType: cell(row, 'نوع الإجراء'),
        courseCode: cell(row, 'رمز المقرر'),
        currentSection: cell(row, 'الشعبة الحالية'),
        requiredSection: cell(row, 'الشعبة المطلوبة'),
        note,
        status,
      });
    }
  }
  return rows;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  if (dryRun) console.log('*** وضع تجريبي (dry-run) - لن يُكتب أي شيء فعليًا بـFirestore ***\n');
  initAdmin();
  const db = require('firebase-admin').firestore();
  const col = db.collection('tickets');

  let totalMatched = 0;
  let totalUnmatched = 0;
  const unmatchedLog = [];

  for (const source of SOURCES) {
    console.log(`\n=== ${source.shatr} :: ${source.filePath} ===`);
    const decisionRows = await readDecisionRows(source);
    console.log(`صفوف بها قرار فعلي: ${decisionRows.length}`);

    // تجميع حسب الطالب لتقليل عدد قراءات/كتابات Firestore.
    const byStudent = new Map();
    for (const r of decisionRows) {
      if (!byStudent.has(r.universityId)) byStudent.set(r.universityId, []);
      byStudent.get(r.universityId).push(r);
    }

    const batch = db.batch();
    let batchCount = 0;

    for (const [universityId, decisions] of byStudent.entries()) {
      const doc = await col.doc(universityId).get();
      if (!doc.exists) {
        totalUnmatched += decisions.length;
        unmatchedLog.push({ universityId, shatr: source.shatr, reason: 'لا توجد تذكرة بهذا الرقم الجامعي' });
        continue;
      }
      const data = doc.data();
      if (data.shatr !== source.shatr) {
        totalUnmatched += decisions.length;
        unmatchedLog.push({ universityId, shatr: source.shatr, reason: `الشطر بالتذكرة مختلف (${data.shatr})` });
        continue;
      }
      const actions = (data.actions || []).map((a) => ({ ...a }));
      let changed = false;

      for (const d of decisions) {
        const key = looseActionKey(d.actionType, d.courseCode, d.currentSection, d.requiredSection);
        const idx = actions.findIndex((a) => looseActionKeyFromAction(a) === key);
        if (idx === -1) {
          totalUnmatched++;
          unmatchedLog.push({ universityId, shatr: source.shatr, sheet: d.sheet, row: d.row, reason: 'لا يوجد إجراء مطابِق بالتذكرة' });
          continue;
        }
        const collegeStatus = d.status === 'تم' || d.status === 'تم الإنجاز' ? 'تم الإنجاز'
          : d.status === 'لم يتم' ? 'تم الإنجاز' // قرار اتُّخذ (حتى لو رفض) = مُعالَج
          : 'تم الإنجاز'; // وجود ملاحظة فقط بلا حالة صريحة = قرار اتُّخذ أيضًا
        actions[idx].college_status = collegeStatus;
        if (d.note) actions[idx].college_notes = d.note;
        changed = true;
        totalMatched++;
      }

      if (changed) {
        batch.update(doc.ref, { actions });
        batchCount++;
      }
    }

    if (batchCount > 0) {
      if (!dryRun) await batch.commit();
      console.log(`${dryRun ? '(تجريبي) سيتم تحديث' : 'تم تحديث'} ${batchCount} تذكرة لـ${source.shatr}.`);
    } else {
      console.log('لا تحديثات لهذا الملف.');
    }
  }

  console.log(`\nإجمالي المطابَق: ${totalMatched}`);
  console.log(`إجمالي غير المطابَق: ${totalUnmatched}`);
  if (unmatchedLog.length > 0) {
    console.log('\n--- تفاصيل غير المطابَق (يستحق مراجعة يدوية) ---');
    unmatchedLog.slice(0, 50).forEach((u) => console.log(JSON.stringify(u)));
    if (unmatchedLog.length > 50) console.log(`... و${unmatchedLog.length - 50} أخرى`);
  }
}

main().catch((err) => {
  console.error('خطأ:', err);
  process.exit(1);
});
