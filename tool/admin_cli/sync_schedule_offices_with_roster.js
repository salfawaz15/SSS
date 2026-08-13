#!/usr/bin/env node
/*
 * بعد تصحيح الأسماء، سليمان حدَّث أرقام مكاتب بملف منسوبي الكلية لكنها بقيت
 * قديمة بملفات توزيع فترات الإرشاد (لم نلمس عمود "رقم المكتب" أثناء تصحيح
 * الأسماء). يطابق كل اسم بالجدول (الآن مصحَّح ومطابق حرفيًا) مع اسمه بملف
 * منسوبي الكلية داخل نفس القسم/الشطر، ويحدّث عمود المكتب لآخر قيمة معتمدة.
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
  'التسويق_طالبات.xlsx',
  'المحاسبة_طالبات.xlsx', 'المحاسبة_طلاب.xlsx',
  'نظم المعلومات الإدارية_طالبات.xlsx', 'نظم المعلومات الإدارية_طلاب.xlsx',
];

function stripAdvisorTitle(name) {
  let n = name.trim();
  const p = /^(د|أ)\s*[.\/]\s*/;
  while (p.test(n)) n = n.replace(p, '').trim();
  return n;
}
function looseDept(s) {
  return s.replace(/\s+/g, '').replace(/[أإآ]/g, 'ا');
}
function normName(s) {
  return stripAdvisorTitle(s).replace(/\s+/g, ' ').trim();
}
function xmlEscape(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

const rosterWb = XLSX.readFile(ROSTER_PATH);
const rosterRows = XLSX.utils.sheet_to_json(rosterWb.Sheets['منسوبو الكلية'], { defval: '' });
const byDeptShatrName = new Map(); // key: dept|shatr|normName -> office
for (const r of rosterRows) {
  const dept = looseDept(String(r['القسم / الجهة'] || ''));
  const shatr = String(r['الشطر'] || '').trim();
  const name = normName(String(r['الاسم الكامل'] || ''));
  const office = String(r['رقم المكتب'] || '').trim();
  byDeptShatrName.set(`${dept}|${shatr}|${name}`, office);
}

for (const file of SCHEDULE_FILES) {
  const filePath = path.join(SCHEDULE_DIR, file);
  const zip = new AdmZip(filePath);
  let xml = zip.getEntry('xl/worksheets/sheet1.xml').getData().toString('utf8');

  const shatrM = xml.match(/<c r="B2"[^>]*><v>([^<]*)<\/v><\/c>/);
  const deptM = xml.match(/<c r="D2"[^>]*><v>([^<]*)<\/v><\/c>/);
  const shatrValue = shatrM ? shatrM[1] : '';
  const deptValue = deptM ? deptM[1] : '';
  const deptKey = looseDept(deptValue);
  const rosterShatr = shatrValue.includes('طالبات') ? 'طالبات' : 'طلاب';

  let changed = 0;
  const unmatched = [];
  const rowRegex = /<row r="(\d+)">((?:(?!<\/row>).)*)<\/row>/gs;
  xml = xml.replace(rowRegex, (fullRow, rowNum, inner) => {
    const n = parseInt(rowNum, 10);
    if (n < 4) return fullRow;
    const nameMatch = inner.match(new RegExp(`<c r="B${n}"[^>]*><v>([^<]*)</v></c>`));
    const officeMatch = inner.match(new RegExp(`<c r="C${n}"[^>]*><v>([^<]*)</v></c>`));
    if (!nameMatch || !officeMatch) return fullRow;
    const currentName = normName(nameMatch[1]);
    const currentOffice = officeMatch[1].trim();

    const key = `${deptKey}|${rosterShatr}|${currentName}`;
    if (!byDeptShatrName.has(key)) {
      unmatched.push(`${currentName} (لا يوجد بملف منسوبي الكلية بهذا الاسم بالضبط)`);
      return fullRow;
    }
    const newOffice = byDeptShatrName.get(key);
    if (!newOffice || newOffice === currentOffice) return fullRow;

    changed++;
    console.log(`  ${currentName}: ${currentOffice || '(فارغ)'} -> ${newOffice}`);
    const newCell = `<c r="C${n}" t="str"><v>${xmlEscape(newOffice)}</v></c>`;
    const newInner = inner.replace(new RegExp(`<c r="C${n}"[^>]*><v>[^<]*</v></c>`), newCell);
    return `<row r="${rowNum}">${newInner}</row>`;
  });

  zip.updateFile('xl/worksheets/sheet1.xml', Buffer.from(xml, 'utf8'));
  zip.writeZip(filePath);

  console.log(`=== ${file} (${deptValue} - ${shatrValue}) - حُدِّث ${changed} مكتب ===`);
  if (unmatched.length) unmatched.forEach((u) => console.log(`    ! ${u}`));
}
