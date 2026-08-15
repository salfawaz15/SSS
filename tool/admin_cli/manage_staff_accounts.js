#!/usr/bin/env node
/*
 * المرحلة 1 من إعادة هيكلة الدخول والصلاحيات (بطلب سليمان، 2026-08-15):
 * أداة سرّية تعمل على جهازك فقط (بلا خطة Blaze، بلا Cloud Functions) لإدارة
 * حسابات الموظفين الفعليين بالبوابة - حساب واحد لكل شخص، مفتاحه رقم منسوبه،
 * ودوره يُخزَّن كـ Custom Claim على حسابه (لا كمطابقة بريد حرفية بقواعد
 * الأمان كما كان سابقًا) - إضافية بحتة الآن، لا تلمس تسجيل الدخول الحالي.
 *
 * أوامر (بدل القوائم التفاعلية - أوثق عند التشغيل الآلي/عبر سكربت):
 *   node manage_staff_accounts.js list
 *   node manage_staff_accounts.js create <staffNumber> <role> [--name="..."] [--shatr=male|female] [--department="..."] [--track=...]
 *   node manage_staff_accounts.js update-role <staffNumber> <role> [--shatr=...] [--department=...] [--track=...]
 *   node manage_staff_accounts.js reset-password <staffNumber> [newPassword]
 *   node manage_staff_accounts.js delete <staffNumber> --confirm
 *
 * البريد الداخلي لكل حساب: <رقم_المنسوب>@sss-advising-tu.internal
 * كلمة المرور المبدئية: رقم المنسوب نفسه (يُطلَب تغييرها إجباريًا بأول دخول
 * عبر علم mustChangePassword في وثيقة Firestore الخاصة بالحساب).
 */

const admin = require('firebase-admin');
const { initAdmin, PROJECT_ID } = require('./firebase_admin_init');

const DOMAIN = 'sss-advising-tu.internal';

// الأدوار الثمانية المعتمدة من الهيكل التنظيمي (2026-08-15) - أي دور جديد
// مستقبلًا (مثل مسار جديد) يُضاف كسطر واحد هنا فقط، بلا لمس قواعد الأمان.
const ROLES = {
  super_admin: 'المدير العام (صلاحيات كاملة - سليمان فقط)',
  admin: 'الإدارة الكاملة (رئيس/نائب الوحدة)',
  ameen: 'أمين الوحدة (عرض فقط)',
  secretary: 'سكرتير الوحدة (عرض فقط)',
  unit_coordinator: 'منسّق الوحدة للشؤون الإدارية (رفع ملفات فقط)',
  college_coordinator: 'منسّق الكلية للشؤون الأكاديمية (يحتاج --shatr)',
  dept_coordinator: 'منسّق قسم علمي (يحتاج --department و --shatr)',
  track_coordinator: 'منسّق مسار نوعي (يحتاج --track)',
};

function emailFor(staffNumber) {
  return `${staffNumber}@${DOMAIN}`;
}

function parseFlags(args) {
  const flags = {};
  for (const a of args) {
    const m = a.match(/^--([a-zA-Z]+)=(.*)$/);
    if (m) flags[m[1]] = m[2];
    else if (a === '--confirm') flags.confirm = true;
  }
  return flags;
}

function claimsFromFlags(role, flags) {
  if (!ROLES[role]) {
    throw new Error(`Unknown role "${role}". Valid roles: ${Object.keys(ROLES).join(', ')}`);
  }
  const claims = { role };
  if (role === 'college_coordinator' || role === 'dept_coordinator') {
    if (!flags.shatr) throw new Error('Role requires --shatr=male|female');
    claims.shatr = flags.shatr;
  }
  if (role === 'dept_coordinator') {
    if (!flags.department) throw new Error('Role requires --department="..."');
    claims.department = flags.department;
  }
  if (role === 'track_coordinator') {
    if (!flags.track) throw new Error('Role requires --track=...');
    claims.track = flags.track;
  }
  return claims;
}

async function listAccounts() {
  const snapshot = await admin.firestore().collection('portal_users').get();
  console.log(`Total staff accounts: ${snapshot.size}`);
  snapshot.forEach((doc) => {
    const d = doc.data();
    console.log(
      `- ${d.staffNumber}  ${d.name || ''}  role=${d.role}${d.department ? ' dept=' + d.department : ''}${d.shatr ? ' shatr=' + d.shatr : ''}${d.track ? ' track=' + d.track : ''}${d.mustChangePassword ? '  [must change password]' : ''}`
    );
  });
}

async function createAccount(staffNumber, role, flags) {
  const claims = claimsFromFlags(role, flags);
  const email = emailFor(staffNumber);

  const existing = await admin.auth().getUserByEmail(email).catch(() => null);
  if (existing) {
    throw new Error(`Account already exists for staff number ${staffNumber}. Use update-role or reset-password instead.`);
  }

  const user = await admin.auth().createUser({ email, password: staffNumber, displayName: flags.name || undefined });
  await admin.auth().setCustomUserClaims(user.uid, claims);
  await admin.firestore().collection('portal_users').doc(user.uid).set({
    staffNumber,
    name: flags.name || '',
    email,
    ...claims,
    mustChangePassword: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`Created. Staff number: ${staffNumber} | Temp password: ${staffNumber} | Role: ${role}`);
  console.log('Share the staff number + temp password with the person - they must change it on first login.');
}

async function updateRole(staffNumber, role, flags) {
  const claims = claimsFromFlags(role, flags);
  const email = emailFor(staffNumber);
  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) throw new Error('No account found for that staff number.');
  await admin.auth().setCustomUserClaims(user.uid, claims);
  await admin.firestore().collection('portal_users').doc(user.uid).set(claims, { merge: true });
  console.log(`Role updated for staff number ${staffNumber} -> ${role}`);
}

async function resetPassword(staffNumber, newPassword) {
  const email = emailFor(staffNumber);
  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) throw new Error('No account found for that staff number.');
  const tempPassword = newPassword || staffNumber;
  await admin.auth().updateUser(user.uid, { password: tempPassword });
  await admin.firestore().collection('portal_users').doc(user.uid).set({ mustChangePassword: true }, { merge: true });
  console.log(`Password reset for staff number ${staffNumber} -> temp password: ${tempPassword} (must change on next login)`);
}

async function deleteAccount(staffNumber, flags) {
  if (!flags.confirm) throw new Error('Add --confirm to permanently delete this account.');
  const email = emailFor(staffNumber);
  const user = await admin.auth().getUserByEmail(email).catch(() => null);
  if (!user) throw new Error('No account found for that staff number.');
  await admin.auth().deleteUser(user.uid);
  await admin.firestore().collection('portal_users').doc(user.uid).delete();
  console.log(`Deleted staff number ${staffNumber}.`);
}

function printUsage() {
  console.log('Usage:');
  console.log('  node manage_staff_accounts.js list');
  console.log('  node manage_staff_accounts.js create <staffNumber> <role> [--name="..."] [--shatr=male|female] [--department="..."] [--track=...]');
  console.log('  node manage_staff_accounts.js update-role <staffNumber> <role> [--shatr=...] [--department=...] [--track=...]');
  console.log('  node manage_staff_accounts.js reset-password <staffNumber> [newPassword]');
  console.log('  node manage_staff_accounts.js delete <staffNumber> --confirm');
  console.log('\nRoles:');
  for (const [k, v] of Object.entries(ROLES)) console.log(`  ${k} - ${v}`);
}

async function main() {
  const [, , cmd, ...rest] = process.argv;
  if (!cmd || cmd === '--help' || cmd === '-h') {
    printUsage();
    return;
  }

  initAdmin();
  console.log(`Connected to project: ${PROJECT_ID}`);

  const flags = parseFlags(rest);
  const positional = rest.filter((a) => !a.startsWith('--'));

  switch (cmd) {
    case 'list':
      await listAccounts();
      break;
    case 'create':
      await createAccount(positional[0], positional[1], flags);
      break;
    case 'update-role':
      await updateRole(positional[0], positional[1], flags);
      break;
    case 'reset-password':
      await resetPassword(positional[0], positional[1]);
      break;
    case 'delete':
      await deleteAccount(positional[0], flags);
      break;
    default:
      printUsage();
  }
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
