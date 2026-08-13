#!/usr/bin/env node
/*
 * نسخة آمنة من add_missing_schedule_members.js: بدل إعادة كتابة الملف كاملاً
 * عبر مكتبة SheetJS (أفسدت جدول numFmt الداخلي بـstyles.xml وسبّبت فشل قراءة
 * الملف بالموقع - "custom numFmtId starts at 164 but found a value of 56")،
 * هذه النسخة تعدّل xl/worksheets/sheet1.xml مباشرة كنص XML خام داخل أرشيف
 * الـzip (adm-zip) بلا لمس styles.xml أو أي جزء آخر من الملف إطلاقًا - أضمن
 * طريقة للحفاظ على سلامة الملف الأصلي 100%.
 */
const AdmZip = require('adm-zip');
const path = require('path');

const DIR = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'المرشدين', 'توزيع فترات الارشاد', 'توزيع فترات الارشاد محدث', 'تحديث', 'نماذج_جاهزة_للرفع'
);

const DAYS = ['الأحد', 'الاثنين', 'الثلاثاء'];
const P1 = 'الفترة الأولى';
const P2 = 'الفترة الثانية';

const ADDITIONS = [
  ['الاقتصاد والتمويل_طلاب.xlsx', 'بشير بكرى عجيب بابكر', '85', 'الأحد'],
  ['الاقتصاد والتمويل_طلاب.xlsx', 'احمد حسين احمد سبحي', '', 'الاثنين'],
  ['الاقتصاد والتمويل_طالبات.xlsx', 'شروق عايض عيضة الثبيتي', '', 'الثلاثاء'],
  ['نظم المعلومات الإدارية_طلاب.xlsx', 'معاذ يوسف ابراهيم الذنيبات', '57', 'الأحد'],
];

function periodsFor(day2) {
  return DAYS.map((d) => (d === day2 ? P2 : P1));
}

function xmlEscape(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// يجمع الإضافات حسب الملف لأن أكثر من عضو قد يُضاف لنفس الملف (الاقتصاد
// والتمويل_طلاب.xlsx له عضوان) - يجب تعديل XML مرة واحدة متتابعة لكل ملف.
const byFile = new Map();
for (const [file, name, office, day2] of ADDITIONS) {
  if (!byFile.has(file)) byFile.set(file, []);
  byFile.get(file).push({ name, office, day2 });
}

for (const [file, members] of byFile) {
  const filePath = path.join(DIR, file);
  const zip = new AdmZip(filePath);
  const sheetEntry = zip.getEntry('xl/worksheets/sheet1.xml');
  let xml = sheetEntry.getData().toString('utf8');

  // آخر رقم صف ورقم "م" مستخدَمين فعليًا - يُستخرجان من آخر عنصر <row> بالملف.
  const rowMatches = [...xml.matchAll(/<row r="(\d+)">.*?<\/row>/gs)];
  const lastRow = rowMatches[rowMatches.length - 1];
  const lastRowNum = parseInt(lastRow[1], 10);
  const mMatch = lastRow[0].match(/<c r="A\d+"><v>(\d+)<\/v><\/c>/);
  let lastM = mMatch ? parseInt(mMatch[1], 10) : lastRowNum - 3;

  let newRowsXml = '';
  let rowNum = lastRowNum;
  for (const { name, office, day2 } of members) {
    rowNum += 1;
    lastM += 1;
    const periods = periodsFor(day2);
    newRowsXml +=
      `<row r="${rowNum}">` +
      `<c r="A${rowNum}"><v>${lastM}</v></c>` +
      `<c r="B${rowNum}" t="str"><v>${xmlEscape(name)}</v></c>` +
      `<c r="C${rowNum}" t="str"><v>${xmlEscape(office)}</v></c>` +
      `<c r="D${rowNum}" t="str"><v>${xmlEscape(periods[0])}</v></c>` +
      `<c r="E${rowNum}" t="str"><v>${xmlEscape(periods[1])}</v></c>` +
      `<c r="F${rowNum}" t="str"><v>${xmlEscape(periods[2])}</v></c>` +
      `</row>`;
    console.log(`${file}: adding "${name}" as row ${rowNum} (م=${lastM}, يوم الفترة الثانية=${day2})`);
  }

  // إدراج الصفوف الجديدة قبل </sheetData>، وتحديث dimension ليشمل آخر صف.
  xml = xml.replace('</sheetData>', newRowsXml + '</sheetData>');
  xml = xml.replace(/<dimension ref="A1:F\d+"\/>/, `<dimension ref="A1:F${rowNum}"/>`);
  xml = xml.replace(/sqref="A1:F\d+"/, `sqref="A1:F${rowNum}"`);

  zip.updateFile('xl/worksheets/sheet1.xml', Buffer.from(xml, 'utf8'));
  zip.writeZip(filePath);
  console.log(`saved: ${file}`);
}
