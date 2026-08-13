#!/usr/bin/env node
/*
 * تصحيح الأسماء المختصرة بملفات توزيع فترات الإرشاد - بمطابقة الاسم نفسه (لا
 * رقم المكتب، تبيّن أنه غير فريد إطلاقًا - عشرات المكاتب مشتركة بين أعضاء
 * متعددين بملف منسوبي الكلية، فمطابقته أعطت أسماء خاطئة لعدة صفوف). كل كلمة
 * بالاسم المختصر يجب أن تظهر بنفس الترتيب ضمن كلمات الاسم الكامل بالروستر
 * (نفس القسم/الشطر) - إن طابق عضوًا واحدًا فقط بثقة، يُستبدَل الاسم؛ غير ذلك
 * يُترَك كما هو ويُبلَّغ للمراجعة اليدوية.
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
function normWord(w) {
  return w.replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ال/g, '');
}
function words(name) {
  return stripAdvisorTitle(name).split(/\s+/).filter(Boolean).map(normWord);
}
function xmlEscape(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// هل كل كلمات shortWords تظهر ضمن fullWords بنفس الترتيب (ليس بالضرورة متتالية)؟
function isSubsequence(shortWords, fullWords) {
  let i = 0;
  for (const fw of fullWords) {
    if (i < shortWords.length && fw.startsWith(shortWords[i])) i++;
  }
  return i === shortWords.length;
}

const rosterWb = XLSX.readFile(ROSTER_PATH);
const rosterRows = XLSX.utils.sheet_to_json(rosterWb.Sheets['منسوبو الكلية'], { defval: '' });
const byDeptShatr = new Map(); // key: dept|shatr -> [{name, words}]
for (const r of rosterRows) {
  const dept = looseDept(String(r['القسم / الجهة'] || ''));
  const shatr = String(r['الشطر'] || '').trim();
  const fullName = String(r['الاسم الكامل'] || '').trim();
  const key = `${dept}|${shatr}`;
  if (!byDeptShatr.has(key)) byDeptShatr.set(key, []);
  byDeptShatr.get(key).push({ name: fullName, words: words(fullName) });
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
  const candidates = byDeptShatr.get(`${deptKey}|${rosterShatr}`) || [];

  let changed = 0;
  const unmatched = [];
  const rowRegex = /<row r="(\d+)">((?:(?!<\/row>).)*)<\/row>/gs;
  xml = xml.replace(rowRegex, (fullRow, rowNum, inner) => {
    const n = parseInt(rowNum, 10);
    if (n < 4) return fullRow;
    const nameMatch = inner.match(new RegExp(`<c r="B${n}"[^>]*><v>([^<]*)</v></c>`));
    if (!nameMatch) return fullRow;
    const currentName = nameMatch[1];
    const shortWords = words(currentName);
    if (shortWords.length === 0) return fullRow;

    const matches = candidates.filter((c) => isSubsequence(shortWords, c.words));
    if (matches.length !== 1) {
      unmatched.push(`${currentName} (${matches.length} تطابق)`);
      return fullRow;
    }
    const fullName = stripAdvisorTitle(matches[0].name);
    if (fullName === stripAdvisorTitle(currentName)) return fullRow;
    changed++;
    const newCell = `<c r="B${n}" t="str"><v>${xmlEscape(fullName)}</v></c>`;
    const newInner = inner.replace(new RegExp(`<c r="B${n}"[^>]*><v>[^<]*</v></c>`), newCell);
    return `<row r="${rowNum}">${newInner}</row>`;
  });

  zip.updateFile('xl/worksheets/sheet1.xml', Buffer.from(xml, 'utf8'));
  zip.writeZip(filePath);

  console.log(`=== ${file} (${deptValue} - ${shatrValue}) ===`);
  console.log(`  صُحِّح: ${changed}`);
  if (unmatched.length) {
    console.log(`  بلا تطابق مؤكَّد (${unmatched.length}):`);
    unmatched.forEach((u) => console.log(`    - ${u}`));
  }
}
