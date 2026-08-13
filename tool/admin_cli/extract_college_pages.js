#!/usr/bin/env node
/*
 * يفحص كل صفحة من ملف "طلاب تابعين لمرشد - جميع الكليات" الضخم، يحدّد أي
 * كلية تخصّها (من رمز "الكلية :" - القيمة تسبقه في ترتيب استخراج pdf.js)،
 * ويبني فهرس صفحة->كلية لاستخدامه لاحقًا باستخراج صفحات كليتين محدَّدتين فقط.
 */
const fs = require('fs');
const path = require('path');
const { deshape } = require('./arabic_deshape');

const SRC = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'صفحه الارشاد', 'طلاب تابعين لمرشد-جميع الكليات 13-08-2026م.pdf'
);

async function main() {
  const pdfjsLib = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const data = new Uint8Array(fs.readFileSync(SRC));
  const doc = await pdfjsLib.getDocument({ data, disableFontFace: true }).promise;
  console.log('total pages:', doc.numPages);

  const pageCollege = new Array(doc.numPages + 1).fill(null);

  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p);
    const content = await page.getTextContent();
    const items = content.items.map((it) => deshape(it.str.trim())).filter((s) => s.length > 0);
    const labelIdx = items.indexOf('الكلية :');
    pageCollege[p] = labelIdx > 0 ? items[labelIdx - 1] : null;
    page.cleanup();
    if (p % 200 === 0) console.log('processed', p, 'pages...');
  }

  fs.writeFileSync(
    path.join(__dirname, 'college_pages_index.json'),
    JSON.stringify(pageCollege)
  );

  const distinct = [...new Set(pageCollege.filter(Boolean))];
  console.log('distinct college labels found:', distinct);
  for (const c of distinct) {
    const count = pageCollege.filter((x) => x === c).length;
    console.log(`  ${c}: ${count} page(s)`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
