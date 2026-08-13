#!/usr/bin/env node
/*
 * يضيف الأعضاء الأربعة الناقصين من توزيع فترات الإرشاد لملفات "نماذج جاهزة
 * للرفع" الموجودة (بلا تعديل أي توزيع سابق معتمَد) - قاعدة سليمان
 * (2026-08-13): يومان بالفترة الأولى + يوم واحد بالفترة الثانية لكل عضو،
 * مع توزيع يوم الفترة الثانية بالتساوي على الأيام الثلاثة بين الأعضاء.
 */
const XLSX = require('xlsx');
const path = require('path');

const DIR = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'المرشدين', 'توزيع فترات الارشاد', 'توزيع فترات الارشاد محدث', 'تحديث', 'نماذج_جاهزة_للرفع'
);

const DAYS = ['الأحد', 'الاثنين', 'الثلاثاء']; // نفس ترتيب أعمدة D/E/F بالنموذج
const P1 = 'الفترة الأولى';
const P2 = 'الفترة الثانية';

// كل عضو: [الملف, الاسم, رقم المكتب, يوم الفترة الثانية]
const ADDITIONS = [
  ['الاقتصاد والتمويل_طلاب.xlsx', 'بشير بكرى عجيب بابكر', '85', 'الأحد'],
  ['الاقتصاد والتمويل_طلاب.xlsx', 'احمد حسين احمد سبحي', '', 'الاثنين'],
  ['الاقتصاد والتمويل_طالبات.xlsx', 'شروق عايض عيضة الثبيتي', '', 'الثلاثاء'],
  ['نظم المعلومات الإدارية_طلاب.xlsx', 'معاذ يوسف ابراهيم الذنيبات', '57', 'الأحد'],
];

function periodsFor(day2) {
  return DAYS.map((d) => (d === day2 ? P2 : P1));
}

for (const [file, name, office, day2] of ADDITIONS) {
  const filePath = path.join(DIR, file);
  const wb = XLSX.readFile(filePath);
  const sheetName = wb.SheetNames[0];
  const ws = wb.Sheets[sheetName];
  const range = XLSX.utils.decode_range(ws['!ref']);

  // أول صف بيانات فارغ فعليًا (عمود الاسم فارغ) بدءًا من الصف 3 (0-فهرسة).
  let targetRow = 3;
  let lastM = 0;
  for (let r = 3; r <= range.e.r; r++) {
    const nameCell = ws[XLSX.utils.encode_cell({ r, c: 1 })];
    const mCell = ws[XLSX.utils.encode_cell({ r, c: 0 })];
    if (nameCell && String(nameCell.v).trim() !== '') {
      targetRow = r + 1;
      if (mCell && typeof mCell.v === 'number') lastM = mCell.v;
    }
  }

  const periods = periodsFor(day2);
  const rowValues = [lastM + 1, name, office, periods[0], periods[1], periods[2]];
  for (let c = 0; c < rowValues.length; c++) {
    const addr = XLSX.utils.encode_cell({ r: targetRow, c });
    const v = rowValues[c];
    ws[addr] = typeof v === 'number' ? { t: 'n', v } : { t: 's', v: String(v) };
  }

  const newRange = XLSX.utils.decode_range(ws['!ref']);
  if (targetRow > newRange.e.r) newRange.e.r = targetRow;
  if (5 > newRange.e.c) newRange.e.c = 5;
  ws['!ref'] = XLSX.utils.encode_range(newRange);

  XLSX.writeFile(wb, filePath);
  console.log(`added "${name}" to ${file} at row ${targetRow + 1} (Excel row), م=${lastM + 1}, يوم الفترة الثانية=${day2}`);
}
