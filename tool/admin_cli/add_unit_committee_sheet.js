#!/usr/bin/env node
/*
 * يضيف ورقة عمل جديدة ومستقلة تمامًا "تشكيل الوحدة" لملف منسوبي الكلية
 * الرسمي، بجراحة XML مباشرة عبر AdmZip (بدل XLSX.writeFile الذي يُفسد
 * تنسيق الورقتين الأصليتين) - لا تُلمَس أي بيانات في ورقتَي "منسوبو
 * الكلية"/"الإداريين" إطلاقًا، تمامًا كطلب سليمان: لا يتأثر منصب أي عضو آخر.
 */
const XLSX = require('xlsx');
const AdmZip = require('adm-zip');
const path = require('path');

const ROSTER_PATH = path.join(
  'C:', 'Users', 'salfa', 'Sulaiman Prj', 'sulaiman',
  'المرفقات', 'أعضاء هيئة التدريس', 'قالب البيانات النهائي .xlsx'
);

const HEADERS = ['م', 'الاسم', 'البريد الجامعي', 'القسم العلمي', 'العضوية'];

const ROWS = [
  ['آلاء عمر معتوق أحمد بارفعه', 'aobarefah@tu.edu.sa', 'نظم المعلومات الإدارية', 'رئيس الوحدة'],
  ['سليمان مفوز سليم الفواز', 'salfawaz@tu.edu.sa', 'نظم المعلومات الإدارية', 'نائب الرئيس'],
  ['عادل علي محمد حسن', 'ad.hassan@tu.edu.sa', 'الاقتصاد والتمويل', 'منسق الكلية للشؤون الأكاديمية'],
  ['هبه الله عبدالصبور أمين حسن', 'Heba79@tu.edu.sa', 'الاقتصاد والتمويل', 'منسقة الكلية للشؤون الأكاديمية'],
  ['تماضر عواض نفيع السلمي', 'Tamader.a@tu.edu.sa', 'الاقتصاد والتمويل', 'أمين الوحدة'],
  ['أكرم محمد بلحاج محمد', 'belhaajmohamed@tu.edu.sa', 'الإدارة', 'منسق قسم إدارة الأعمال - شطر الطلاب'],
  ['حنان عثمان عمسيب محمد', 'homohammed@tu.edu.sa', 'الإدارة', 'منسق قسم إدارة الأعمال - شطر الطالبات'],
  ['محمد ابكر احمد محمد', 'Abaker@tu.edu.sa', 'المحاسبة', 'منسق قسم المحاسبة - شطر الطلاب'],
  ['السارة سعد علي احمد', 'asahmad@tu.edu.sa', 'المحاسبة', 'منسق قسم المحاسبة - شطر الطالبات'],
  ['صالح حامد احمد العريفي', 's.hamed@tu.edu.sa', 'نظم المعلومات الإدارية', 'منسق قسم نظم المعلومات الإدارية - شطر الطلاب'],
  ['دلال مفرح علي العمري', 'd.mafarh@tu.edu.sa', 'نظم المعلومات الإدارية', 'منسق قسم نظم المعلومات الإدارية - شطر الطالبات'],
  ['الصادق محمد سالم الطيب', 'tayeb@tu.edu.sa', 'الاقتصاد والتمويل', 'منسق قسم الاقتصاد والتمويل - شطر الطلاب'],
  ['سوليمة ابراهيم بلحسن العبدلي', 'seabdelli@tu.edu.sa', 'الاقتصاد والتمويل', 'منسق قسم الاقتصاد والتمويل - شطر الطالبات'],
  ['حسن عبد الرحيم حسن الزبير', 'azubeir@tu.edu.sa', 'التسويق', 'منسق قسم التسويق - شطر الطلاب'],
  ['اميره سعد محمد الفقيه', 'amera@tu.edu.sa', 'التسويق', 'منسق قسم التسويق - شطر الطالبات'],
  ['منى النيل مصطفى مرسال', 'memursal@tu.edu.sa', 'الإدارة', 'منسق مسار الارشاد الأكاديمي'],
  ['السيد الحضري أحمد محمود', 'a.Elhadery@tu.edu.sa', 'الإدارة', 'منسق مسار الرعاية الطلابية'],
  ['مازن عبدالرحمن محمد المنجومي', 'mamanjumi@tu.edu.sa', 'الإدارة', 'منسق مسار البيانات والجودة والتطوير'],
  ['مزمل عوض طه احمد', 'malhadad@tu.edu.sa', 'المحاسبة', 'منسق مسار الخريجين'],
  ['أشواق علي طامي العتيبي', 'ashotaibi@tu.edu.sa', 'الاقتصاد والتمويل', 'منسق مسار الموهوبين والتفوق الاكاديمي'],
  ['يوسف علي عبدالله الشهراني', 'y.shahrani@tu.edu.sa', 'إدارة الكلية', 'منسق الوحدة للشؤون الإدارية'],
  ['رهف صالح محمد العصيمي', 'rahaf.a.alotaibi@gmail.com', 'إدارة الكلية', 'سكرتير الوحدة'],
];

function xmlEscape(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function colLetter(i) {
  let s = '';
  let n = i + 1;
  while (n > 0) {
    const rem = (n - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

function buildSheetXml() {
  const rows = [HEADERS, ...ROWS.map((r, i) => [i + 1, ...r])];
  const rowsXml = rows
    .map((row, rIdx) => {
      const cells = row
        .map((val, cIdx) => {
          const ref = `${colLetter(cIdx)}${rIdx + 1}`;
          if (typeof val === 'number') {
            return `<c r="${ref}"><v>${val}</v></c>`;
          }
          return `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(val)}</t></is></c>`;
        })
        .join('');
      return `<row r="${rIdx + 1}">${cells}</row>`;
    })
    .join('');

  return (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
    `<dimension ref="A1:${colLetter(HEADERS.length - 1)}${rows.length}"/>` +
    '<sheetViews><sheetView rightToLeft="1" workbookViewId="0"/></sheetViews>' +
    '<sheetFormatPr defaultRowHeight="15"/>' +
    `<sheetData>${rowsXml}</sheetData>` +
    '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>' +
    '</worksheet>'
  );
}

function main() {
  const zip = new AdmZip(ROSTER_PATH);

  const SHEET_NAME = 'تشكيل الوحدة';
  const NEW_SHEET_ID = 4;
  const NEW_R_ID = 'rId8';
  const NEW_PART = 'xl/worksheets/sheet4.xml';

  // 1) ورقة العمل الجديدة - addFile (لا updateFile) لأنه جزء جديد بالكامل
  // غير موجود في الأرشيف أصلاً.
  if (zip.getEntry(NEW_PART)) {
    zip.updateFile(NEW_PART, Buffer.from(buildSheetXml(), 'utf8'));
  } else {
    zip.addFile(NEW_PART, Buffer.from(buildSheetXml(), 'utf8'));
  }

  // 2) تسجيلها في workbook.xml
  let workbookXml = zip.getEntry('xl/workbook.xml').getData().toString('utf8');
  if (workbookXml.includes(`name="${SHEET_NAME}"`)) {
    console.log('الورقة موجودة بالفعل بملف workbook.xml - لا حاجة لإعادة الإضافة.');
  } else {
    workbookXml = workbookXml.replace(
      '</sheets>',
      `<sheet name="${SHEET_NAME}" sheetId="${NEW_SHEET_ID}" r:id="${NEW_R_ID}"/></sheets>`
    );
    zip.updateFile('xl/workbook.xml', Buffer.from(workbookXml, 'utf8'));
  }

  // 3) علاقة العلاقات
  let rels = zip.getEntry('xl/_rels/workbook.xml.rels').getData().toString('utf8');
  if (!rels.includes(NEW_R_ID)) {
    rels = rels.replace(
      '</Relationships>',
      `<Relationship Id="${NEW_R_ID}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/></Relationships>`
    );
    zip.updateFile('xl/_rels/workbook.xml.rels', Buffer.from(rels, 'utf8'));
  }

  // 4) [Content_Types].xml
  let ct = zip.getEntry('[Content_Types].xml').getData().toString('utf8');
  if (!ct.includes(NEW_PART)) {
    ct = ct.replace(
      '</Types>',
      `<Override PartName="/${NEW_PART}" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>`
    );
    zip.updateFile('[Content_Types].xml', Buffer.from(ct, 'utf8'));
  }

  zip.writeZip(ROSTER_PATH);
  console.log(`تمت إضافة ورقة "${SHEET_NAME}" (${ROWS.length} عضوًا) إلى ${ROSTER_PATH}`);

  // تحقق: أعِد فتح الملف وتأكّد أن الورقتين الأصليتين لم تتأثرا وأن الورقة
  // الجديدة تُقرأ بشكل صحيح.
  const check = XLSX.readFile(ROSTER_PATH);
  console.log('أوراق الملف الآن:', check.SheetNames);
  const rows = XLSX.utils.sheet_to_json(check.Sheets[SHEET_NAME]);
  console.log(`عدد صفوف "${SHEET_NAME}" المقروءة:`, rows.length);
}

main();
