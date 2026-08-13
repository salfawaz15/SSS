#!/usr/bin/env node
/*
 * تصحيحات أسماء أكَّدها سليمان يدويًا (2026-08-13) بعد أن تعذّرت المطابقة
 * الآلية عليها (اختلاف إملائي كبير عن ملف منسوبي الكلية).
 */
const AdmZip = require('adm-zip');
const path = require('path');

const DIR = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'المرشدين', 'توزيع فترات الارشاد', 'توزيع فترات الارشاد محدث', 'تحديث', 'نماذج_جاهزة_للرفع'
);

function renameCell(filePath, oldText, newText) {
  const zip = new AdmZip(filePath);
  let xml = zip.getEntry('xl/worksheets/sheet1.xml').getData().toString('utf8');
  const re = new RegExp(`(<c r="B\\d+"[^>]*><v>)${oldText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(</v></c>)`);
  const m = xml.match(re);
  if (!m) {
    console.log(`  تعذّر إيجاد "${oldText}" بالملف ${path.basename(filePath)}`);
    return;
  }
  xml = xml.replace(re, `$1${newText}$2`);
  zip.updateFile('xl/worksheets/sheet1.xml', Buffer.from(xml, 'utf8'));
  zip.writeZip(filePath);
  console.log(`  "${oldText}" -> "${newText}" في ${path.basename(filePath)}`);
}

renameCell(path.join(DIR, 'الإدارة_طلاب.xlsx'), 'عوض عمر أبو مالح', 'عوض عمر علي ابومالح');
renameCell(path.join(DIR, 'الإدارة_طلاب.xlsx'), 'عبد الله بن مداري الحربي', 'عبد الله مداري عبدالله الحربي');
renameCell(path.join(DIR, 'الإدارة_طلاب.xlsx'), 'عبد الرحمن غسان الصديقي', 'عبدالرحمن غسان محمد الصديقي');
renameCell(path.join(DIR, 'المحاسبة_طلاب.xlsx'), 'عبدالرحمن عبدالله', 'عبد الرحمن عبد الله عبد الرحمن عبد الله');
renameCell(path.join(DIR, 'نظم المعلومات الإدارية_طلاب.xlsx'), 'د. طارق حلمي', 'طارق حلمى عبدالنبي علي');
renameCell(path.join(DIR, 'التسويق_طلاب.xlsx'), ' عبد الرحمن صالح العلياني', 'عبدالرحمن صالح محمد العلياني');
renameCell(path.join(DIR, 'الاقتصاد والتمويل_طلاب.xlsx'), 'أ. أحمد سجحي', 'احمد حسين احمد سبحي');

console.log('تم.');
