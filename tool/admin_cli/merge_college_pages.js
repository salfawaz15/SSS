#!/usr/bin/env node
/*
 * يستخرج صفحات كليتَي "إدارة الأعمال" و"الحاسبات وتقنية المعلومات" فقط من
 * ملف "طلاب تابعين لمرشد - جميع الكليات" الضخم (بالاعتماد على فهرس
 * college_pages_index.json المبني مسبقًا بـextract_college_pages.js)، ويدمجها
 * بملف PDF واحد جديد بنفس ترتيبها الأصلي بالملف المصدر.
 */
const fs = require('fs');
const path = require('path');
const { PDFDocument } = require('pdf-lib');

const SRC = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'صفحه الارشاد', 'طلاب تابعين لمرشد-جميع الكليات 13-08-2026م.pdf'
);
const OUT = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'صفحه الارشاد', 'طلاب تابعين لمرشد-كلية إدارة الأعمال والحاسبات 13-08-2026م.pdf'
);
const TARGET_COLLEGES = ['كلية إدارة الأعمال', 'كلية الحاسبات وتقنية المعلومات'];

async function main() {
  const pageCollege = JSON.parse(
    fs.readFileSync(path.join(__dirname, 'college_pages_index.json'), 'utf8')
  );

  const matchedPageIndices0Based = [];
  for (let p = 1; p < pageCollege.length; p++) {
    if (TARGET_COLLEGES.includes(pageCollege[p])) matchedPageIndices0Based.push(p - 1);
  }
  console.log('matched pages:', matchedPageIndices0Based.length);

  const srcBytes = fs.readFileSync(SRC);
  const srcDoc = await PDFDocument.load(srcBytes);
  const outDoc = await PDFDocument.create();

  // copyPages بدفعات (لا كل الصفحات دفعة واحدة) لتفادي استهلاك ذاكرة كبير.
  const batchSize = 100;
  for (let i = 0; i < matchedPageIndices0Based.length; i += batchSize) {
    const batch = matchedPageIndices0Based.slice(i, i + batchSize);
    const copied = await outDoc.copyPages(srcDoc, batch);
    copied.forEach((pg) => outDoc.addPage(pg));
    console.log('copied', Math.min(i + batchSize, matchedPageIndices0Based.length), '/', matchedPageIndices0Based.length);
  }

  const outBytes = await outDoc.save();
  fs.writeFileSync(OUT, outBytes);
  console.log('saved to:', OUT);
  console.log('output pages:', outDoc.getPageCount());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
