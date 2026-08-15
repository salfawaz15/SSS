#!/usr/bin/env node
/*
 * المرحلة 1 من إعادة هيكلة الدخول والصلاحيات (بطلب سليمان، 2026-08-15):
 * أداة سرّية تعمل على جهازك فقط (بلا خطة Blaze، بلا Cloud Functions) لإدارة
 * حسابات الموظفين الفعليين بالبوابة - حساب واحد لكل شخص، مفتاحه رقم منسوبه،
 * ودوره يُخزَّن كـ Custom Claim على حسابه (لا كمطابقة بريد حرفية بقواعد
 * الأمان كما كان سابقًا) - إضافية بحتة الآن، لا تلمس تسجيل الدخول الحالي.
 *
 * البريد الداخلي لكل حساب: <رقم_المنسوب>@sss-advising-tu.internal
 * كلمة المرور المبدئية: رقم المنسوب نفسه (يُطلَب تغييرها إجباريًا بأول دخول
 * عبر علم mustChangePassword في وثيقة Firestore الخاصة بالحساب).
 *
 * Usage: node manage_staff_accounts.js
 */

const readline = require('readline');
const admin = require('firebase-admin');
const { initAdmin, PROJECT_ID } = require('./firebase_admin_init');

const DOMAIN = 'sss-advising-tu.internal';

// الأدوار السبعة المعتمدة من الهيكل التنظيمي (2026-08-15) - أي دور جديد
// مستقبلًا (مثل مسار جديد) يُضاف كسطر واحد هنا فقط، بلا لمس قواعد الأمان.
const ROLES = {
  1: { code: 'super_admin', label: 'المدير العام (صلاحيات كاملة - سليمان فقط)' },
  2: { code: 'admin', label: 'الإدارة الكاملة (رئيس/نائب الوحدة)' },
  3: { code: 'ameen', label: 'أمين الوحدة (عرض فقط)' },
  4: { code: 'secretary', label: 'سكرتير الوحدة (عرض فقط)' },
  5: { code: 'unit_coordinator', label: 'منسّق الوحدة للشؤون الإدارية (رفع ملفات فقط)' },
  6: { code: 'college_coordinator', label: 'منسّق الكلية للشؤون الأكاديمية (يحتاج شطر)' },
  7: { code: 'dept_coordinator', label: 'منسّق قسم علمي (يحتاج قسم وشطر)' },
  8: { code: 'track_coordinator', label: 'منسّق مسار نوعي (يحتاج اسم المسار)' },
};

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (q) => new Promise((resolve) => rl.question(q, resolve));

function emailFor(staffNumber) {
  return `${staffNumber}@${DOMAIN}`;
}

async function chooseRole() {
  console.log('\nRoles:');
  for (const [k, v] of Object.entries(ROLES)) console.log(`  ${k}) ${v.label} [${v.code}]`);
  const choice = (await ask('Role number: ')).trim();
  const role = ROLES[choice];
  if (!role) throw new Error('Invalid role choice.');

  const claims = { role: role.code };
  if (role.code === 'college_coordinator' || role.code === 'dept_coordinator') {
    claims.shatr = (await ask('Shatr (male/female): ')).trim();
  }
  if (role.code === 'dept_coordinator') {
    claims.department = (await ask('Department (e.g. الإدارة, المحاسبة...): ')).trim();
  }
  if (role.code === 'track_coordinator') {
    claims.track = (await ask('Track code (e.g. academic_advising, student_care, data_quality, graduates, gifted): ')).trim();
  }
  return claims;
}

async function createAccount() {
  const staffNumber = (await ask('Staff number (رقم المنسوب): ')).trim();
  const name = (await ask('Full name (للعرض فقط): ')).trim();
  if (!staffNumber) {
    console.log('Staff number is required.\n');
    return;
  }
  const claims = await chooseRole();
  const email = emailFor(staffNumber);

  const existing = await admin
    .auth()
    .getUserByEmail(email)
    .catch(() => null);
  if (existing) {
    console.log(`Account already exists for staff number ${staffNumber}. Use "update role" or "reset password" instead.\n`);
    return;
  }

  const user = await admin.auth().createUser({
    email,
    password: staffNumber,
    displayName: name || undefined,
  });
  await admin.auth().setCustomUserClaims(user.uid, claims);
  await admin.firestore().collection('portal_users').doc(user.uid).set({
    staffNumber,
    name,
    email,
    ...claims,
    mustChangePassword: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`\nCreated. Staff number: ${staffNumber} | Temp password: ${staffNumber} | Role: ${claims.role}`);
  console.log('Share the staff number + temp password with the person - they must change it on first login.\n');
}

async function updateRole() {
  const staffNumber = (await ask('Staff number: ')).trim();
  const email = emailFor(staffNumber);
  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) {
    console.log('No account found for that staff number.\n');
    return;
  }
  const claims = await chooseRole();
  await admin.auth().setCustomUserClaims(user.uid, claims);
  await admin.firestore().collection('portal_users').doc(user.uid).set(claims, { merge: true });
  console.log(`Role updated for staff number ${staffNumber} -> ${claims.role}\n`);
}

async function resetPassword() {
  const staffNumber = (await ask('Staff number: ')).trim();
  const email = emailFor(staffNumber);
  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) {
    console.log('No account found for that staff number.\n');
    return;
  }
  const tempPassword = (await ask(`New temp password (press Enter for staff number "${staffNumber}"): `)).trim() || staffNumber;
  await admin.auth().updateUser(user.uid, { password: tempPassword });
  await admin.firestore().collection('portal_users').doc(user.uid).set({ mustChangePassword: true }, { merge: true });
  console.log(`Password reset for staff number ${staffNumber} -> temp password: ${tempPassword} (must change on next login)\n`);
}

async function deleteAccount() {
  const staffNumber = (await ask('Staff number to delete: ')).trim();
  const email = emailFor(staffNumber);
  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) {
    console.log('No account found for that staff number.\n');
    return;
  }
  const confirm = (await ask(`Confirm PERMANENT deletion of staff number ${staffNumber}? Type "delete": `)).trim();
  if (confirm !== 'delete') {
    console.log('Cancelled.\n');
    return;
  }
  await admin.auth().deleteUser(user.uid);
  await admin.firestore().collection('portal_users').doc(user.uid).delete();
  console.log(`Deleted staff number ${staffNumber}.\n`);
}

async function listAccounts() {
  const snapshot = await admin.firestore().collection('portal_users').get();
  console.log(`\nTotal staff accounts: ${snapshot.size}\n`);
  snapshot.forEach((doc) => {
    const d = doc.data();
    console.log(
      `- ${d.staffNumber}  ${d.name || ''}  role=${d.role}${d.department ? ' dept=' + d.department : ''}${d.shatr ? ' shatr=' + d.shatr : ''}${d.track ? ' track=' + d.track : ''}${d.mustChangePassword ? '  [must change password]' : ''}`
    );
  });
  console.log('');
}

async function main() {
  initAdmin();
  console.log(`Connected to project: ${PROJECT_ID}\n`);

  let running = true;
  while (running) {
    console.log('1) List staff accounts');
    console.log('2) Create staff account');
    console.log('3) Update role');
    console.log('4) Reset password');
    console.log('5) Delete account');
    console.log('0) Exit');
    const choice = (await ask('Choice: ')).trim();
    try {
      switch (choice) {
        case '1':
          await listAccounts();
          break;
        case '2':
          await createAccount();
          break;
        case '3':
          await updateRole();
          break;
        case '4':
          await resetPassword();
          break;
        case '5':
          await deleteAccount();
          break;
        case '0':
          running = false;
          break;
        default:
          console.log('Invalid choice.\n');
      }
    } catch (err) {
      console.log(`Error: ${err.message}\n`);
    }
  }
  rl.close();
}

main().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
