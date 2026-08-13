#!/usr/bin/env node
/*
 * "التسويق_طلاب.xlsx" ملف مختلف بنيويًا عن باقي التسعة (Excel حقيقي بشرح
 * صور/تعليقات وSharedStrings، وليس مبنيًا بمكتبة الموقع) - يحتاج معالجة
 * خاصة: الأسماء مرجعية بجدول sharedStrings.xml لا نصًا مباشرًا بالخلية.
 */
const XLSX = require('xlsx');
const AdmZip = require('adm-zip');
const path = require('path');

const ROSTER_PATH = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'أعضاء هيئة التدريس', 'قالب البيانات النهائي .xlsx'
);
const FILE_PATH = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'المرشدين', 'توزيع فترات الارشاد', 'توزيع فترات الارشاد محدث', 'تحديث', 'نماذج_جاهزة_للرفع',
  'التسويق_طلاب.xlsx'
);

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
function normWord(w) {
  return w.replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ال/g, '');
}
function words(name) {
  return stripAdvisorTitle(name).split(/\s+/).filter(Boolean).map(normWord);
}
function isSubsequence(shortWords, fullWords) {
  let i = 0;
  for (const fw of fullWords) {
    if (i < shortWords.length && fw.startsWith(shortWords[i])) i++;
  }
  return i === shortWords.length;
}

// رقم المكتب غير فريد إطلاقًا بملف منسوبي الكلية (عشرات المكاتب مشتركة بين
// أعضاء متعددين) - المطابقة هنا بالاسم لا بالمكتب، تفاديًا لتكرار نفس الخلل
// الذي وقع بالملفات التسعة الأخرى أول محاولة.
const rosterWb = XLSX.readFile(ROSTER_PATH);
const rosterRows = XLSX.utils.sheet_to_json(rosterWb.Sheets['منسوبو الكلية'], { defval: '' });
const byDeptShatr = new Map();
for (const r of rosterRows) {
  const dept = looseDept(String(r['القسم / الجهة'] || ''));
  const shatr = String(r['الشطر'] || '').trim();
  const fullName = String(r['الاسم الكامل'] || '').trim();
  const key = `${dept}|${shatr}`;
  if (!byDeptShatr.has(key)) byDeptShatr.set(key, []);
  byDeptShatr.get(key).push({ name: fullName, words: words(fullName) });
}

const zip = new AdmZip(FILE_PATH);
let sheetXml = zip.getEntry('xl/worksheets/sheet1.xml').getData().toString('utf8');
let sharedXml = zip.getEntry('xl/sharedStrings.xml').getData().toString('utf8');

// يفكّك <si><t>..</t></si> أو <si><t xml:space="preserve">..</t></si> بالترتيب.
const siRegex = /<si>(?:<t(?:\s+xml:space="preserve")?>([^<]*)<\/t>|<t\/>)<\/si>/g;
const sharedStrings = [];
let m;
while ((m = siRegex.exec(sharedXml)) !== null) sharedStrings.push(m[1] ?? '');

function cellValue(rowInner, col, rowNum) {
  const m = rowInner.match(new RegExp(`<c r="${col}${rowNum}"[^>]*t="s"[^>]*><v>(\\d+)</v></c>`));
  return m ? sharedStrings[parseInt(m[1], 10)] : null;
}

const deptShatrRow = sheetXml.match(/<row r="2"[^>]*>(.*?)<\/row>/s)[1];
const shatrValue = cellValue(deptShatrRow, 'B', 2) || '';
const deptValue = cellValue(deptShatrRow, 'D', 2) || '';
const deptKey = looseDept(deptValue);
const rosterShatr = shatrValue.includes('طالبات') ? 'طالبات' : 'طلاب';
const candidates = byDeptShatr.get(`${deptKey}|${rosterShatr}`) || [];
console.log(`ملف: ${deptValue} - ${shatrValue}`);

let changed = 0;
const unmatched = [];
const newStrings = []; // { text, index } لأي اسم جديد يُضاف لجدول sharedStrings

function sharedIndexFor(text) {
  const existing = sharedStrings.indexOf(text);
  if (existing !== -1) return existing;
  const idx = sharedStrings.length; // الفهرس التالي المتاح فعليًا بعد كل الإضافات السابقة بهذه التشغيلة
  newStrings.push({ text, index: idx });
  sharedStrings.push(text); // يُحدَّث فورًا حتى تصير sharedStrings.length صحيحة للاستدعاء التالي، ويُعثَر على هذا النص لو تكرر لاحقًا
  return idx;
}

const rowRegex = /<row r="(\d+)"([^>]*)>((?:(?!<\/row>).)*)<\/row>/gs;
sheetXml = sheetXml.replace(rowRegex, (fullRow, rowNum, rowAttrs, inner) => {
  const n = parseInt(rowNum, 10);
  if (n < 4) return fullRow;

  const nameCellMatch = inner.match(new RegExp(`<c r="B${n}"[^>]*t="s"[^>]*><v>(\\d+)</v></c>`));
  if (!nameCellMatch) return fullRow;
  const currentName = sharedStrings[parseInt(nameCellMatch[1], 10)];
  const shortWords = words(currentName);
  if (shortWords.length === 0) return fullRow;

  const matches = candidates.filter((c) => isSubsequence(shortWords, c.words));
  if (matches.length !== 1) {
    unmatched.push(`${currentName} (${matches.length} تطابق)`);
    return fullRow;
  }
  const fullName = stripAdvisorTitle(matches[0].name);
  if (fullName.trim() === stripAdvisorTitle(currentName).trim()) return fullRow;

  changed++;
  const newIdx = sharedIndexFor(fullName);
  const newCell = `<c r="B${n}" t="s"><v>${newIdx}</v></c>`;
  const newInner = inner.replace(new RegExp(`<c r="B${n}"[^>]*t="s"[^>]*><v>\\d+</v></c>`), newCell);
  return `<row r="${rowNum}"${rowAttrs}>${newInner}</row>`;
});

// أضف أي نصوص جديدة لجدول sharedStrings.xml وحدّث count/uniqueCount.
if (newStrings.length > 0) {
  const newSiXml = newStrings.map(({ text }) => `<si><t xml:space="preserve">${xmlEscape(text)}</t></si>`).join('');
  sharedXml = sharedXml.replace('</sst>', newSiXml + '</sst>');
  sharedXml = sharedXml.replace(/uniqueCount="(\d+)"/, (_, c) => `uniqueCount="${parseInt(c, 10) + newStrings.length}"`);
  sharedXml = sharedXml.replace(/count="(\d+)"/, (_, c) => `count="${parseInt(c, 10) + newStrings.length}"`);
}

zip.updateFile('xl/worksheets/sheet1.xml', Buffer.from(sheetXml, 'utf8'));
zip.updateFile('xl/sharedStrings.xml', Buffer.from(sharedXml, 'utf8'));
zip.writeZip(FILE_PATH);

console.log(`صُحِّح: ${changed} اسمًا`);
if (unmatched.length) {
  console.log(`بلا تطابق (${unmatched.length}):`);
  unmatched.forEach((u) => console.log(`  - ${u}`));
}
