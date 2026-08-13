#!/usr/bin/env node
/*
 * يستخرج فقط صفحات كتلة "طارق حلمي عبدالنبي علي" (رقم المرشد 4280812) من
 * ملف "طلاب تابعين لمرشد - جميع الكليات" - الملف السابق (531 صفحة، كليتَي
 * إدارة الأعمال والحاسبات كاملتين) كان كبيرًا جدًا ويعلّق عند سليمان.
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
  'المرفقات', 'صفحه الارشاد', 'طلاب تابعين لمرشد-طارق حلمي فقط 13-08-2026م.pdf'
);

// صفحات 1059-1061 (1-based بالمصدر) - تحقَّقنا يدويًا: 1059 يحوي رأس الكتلة
// (رقم المرشد 4280812)، 1060-1061 استمرار بلا رأس جديد، 1062 مرشد آخر (4280900).
const PAGES_1_BASED = [1059, 1060, 1061];

async function main() {
  const srcBytes = fs.readFileSync(SRC);
  const srcDoc = await PDFDocument.load(srcBytes);
  const outDoc = await PDFDocument.create();
  const copied = await outDoc.copyPages(srcDoc, PAGES_1_BASED.map((p) => p - 1));
  copied.forEach((pg) => outDoc.addPage(pg));
  const outBytes = await outDoc.save();
  fs.writeFileSync(OUT, outBytes);
  console.log('saved to:', OUT, '-', outDoc.getPageCount(), 'pages');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
