#!/usr/bin/env node
/*
 * يصحّح أسماء المرشدين المختصرة بملفات "توزيع فترات الإرشاد" العشرة (تظهر
 * كاسمَين فقط - أول وأخير - بدل الاسم الكامل) بمطابقتها برقم المكتب مقابل
 * ملف منسوبي الكلية (المصدر الموثوق) داخل نفس القسم/الشطر - أدق من مطابقة
 * الاسم نفسه لاحتمال تشابه أسماء مختلفة. يعدّل sheet1.xml مباشرة (بلا
 * SheetJS) لتفادي تكرار خلل إفساد numFmtId الذي حدث سابقًا اليوم.
 */
const XLSX = require('xlsx');
const AdmZip = require('adm-zip');
const path = require('path');

const ROSTER_PATH = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'أعضاء هيئة التدريس', 'قالب البيانات النهائي .xlsx'
);
const SCHEDULE_DIR = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'المرشدين', 'توزيع فترات الارشاد', 'توزيع فترات الارشاد محدث', 'تحديث', 'نماذج_جاهزة_للرفع'
);

const SCHEDULE_FILES = [
  'الإدارة_طالبات.xlsx', 'الإدارة_طلاب.xlsx',
  'الاقتصاد والتمويل_طالبات.xlsx', 'الاقتصاد والتمويل_طلاب.xlsx',
  'التسويق_طالبات.xlsx', 'التسويق_طلاب.xlsx',
  'المحاسبة_طالبات.xlsx', 'المحاسبة_طلاب.xlsx',
  'نظم المعلومات الإدارية_طالبات.xlsx', 'نظم المعلومات الإدارية_طلاب.xlsx',
];

// نفس منطق AdvisingScheduleEntry.stripAdvisorTitle بالكود (lib/models/advising_schedule.dart)
function stripAdvisorTitle(name) {
  let n = name.trim();
  const titlePattern = /^(د|أ)\s*[.\/]\s*/;
  while (titlePattern.test(n)) n = n.replace(titlePattern, '').trim();
  return n;
}

function looseDept(s) {
  return s.replace(/\s+/g, '').replace(/[أإآ]/g, 'ا');
}

function xmlEscape(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// فهرس رقم المكتب -> الاسم الكامل (بعد حذف اللقب)، لكل (قسم مطبَّع، شطر)
const rosterWb = XLSX.readFile(ROSTER_PATH);
const rosterRows = XLSX.utils.sheet_to_json(rosterWb.Sheets['منسوبو الكلية'], { defval: '' });
const officeIndex = new Map(); // key: `${loosedept}|${shatr}|${office}` -> fullName

for (const r of rosterRows) {
  const office = String(r['رقم المكتب'] || '').trim();
  if (!office) continue;
  const dept = looseDept(String(r['القسم / الجهة'] || ''));
  const shatr = String(r['الشطر'] || '').trim();
  const key = `${dept}|${shatr}|${office}`;
  officeIndex.set(key, stripAdvisorTitle(String(r['الاسم الكامل'] || '')));
}

for (const file of SCHEDULE_FILES) {
  const filePath = path.join(SCHEDULE_DIR, file);
  const zip = new AdmZip(filePath);
  let xml = zip.getEntry('xl/worksheets/sheet1.xml').getData().toString('utf8');

  const shatrMatch = xml.match(/<c r="B2"[^>]*><v>([^<]*)<\/v><\/c>/);
  const deptMatch = xml.match(/<c r="D2"[^>]*><v>([^<]*)<\/v><\/c>/);
  const shatrValue = shatrMatch ? shatrMatch[1] : '';
  const deptValue = deptMatch ? deptMatch[1] : '';
  const deptKey = looseDept(deptValue);
  // الشطر بملفات الجدول "شطر الطلاب"/"شطر الطالبات" مقابل روستر "طلاب"/"طالبات"
  const rosterShatr = shatrValue.includes('طالبات') ? 'طالبات' : 'طلاب';

  let changed = 0;
  let unmatched = [];

  // كل صف بيانات: <row r="N"><c r="AN">...م...</c><c r="BN">...اسم...</c><c r="CN">...مكتب...</c>...
  const rowRegex = /<row r="(\d+)">((?:(?!<\/row>).)*)<\/row>/gs;
  xml = xml.replace(rowRegex, (fullRow, rowNum, inner) => {
    const n = parseInt(rowNum, 10);
    if (n < 4) return fullRow; // صفوف 1-3: بانر/محدِّدات/عناوين
    const nameMatch = inner.match(new RegExp(`<c r="B${n}"[^>]*><v>([^<]*)</v></c>`));
    const officeMatch = inner.match(new RegExp(`<c r="C${n}"[^>]*><v>([^<]*)</v></c>`));
    if (!nameMatch) return fullRow;
    const currentName = nameMatch[1];
    const office = officeMatch ? officeMatch[1].trim() : '';
    if (!office) {
      unmatched.push(`${currentName} (بلا رقم مكتب)`);
      return fullRow;
    }
    const key = `${deptKey}|${rosterShatr}|${office}`;
    const fullName = officeIndex.get(key);
    if (!fullName) {
      unmatched.push(`${currentName} (مكتب ${office} - لا تطابق بملف منسوبي الكلية)`);
      return fullRow;
    }
    if (fullName === currentName) return fullRow; // مطابق أصلًا، لا تغيير
    changed++;
    const newCell = `<c r="B${n}" t="str"><v>${xmlEscape(fullName)}</v></c>`;
    const newInner = inner.replace(new RegExp(`<c r="B${n}"[^>]*><v>[^<]*</v></c>`), newCell);
    return `<row r="${rowNum}">${newInner}</row>`;
  });

  zip.updateFile('xl/worksheets/sheet1.xml', Buffer.from(xml, 'utf8'));
  zip.writeZip(filePath);

  console.log(`=== ${file} (${deptValue} - ${shatrValue}) ===`);
  console.log(`  صُحِّح: ${changed} اسمًا`);
  if (unmatched.length) {
    console.log(`  بلا تطابق (${unmatched.length}):`);
    unmatched.forEach((u) => console.log(`    - ${u}`));
  }
}
