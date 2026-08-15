#!/usr/bin/env node
/*
 * ينشر محتوى firestore.rules الحالي عبر Security Rules API في firebase-admin
 * (بلا حاجة لتثبيت Firebase CLI) - نفس أسلوب جلسة CLI المسجَّلة المستخدم في
 * seed_advisor_roster.js.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const { initAdmin } = require('./firebase_admin_init');

async function main() {
  const rulesPath = path.join(__dirname, '..', '..', 'firestore.rules');
  const source = fs.readFileSync(rulesPath, 'utf8');

  initAdmin();
  const rulesClient = admin.securityRules();
  const ruleset = await rulesClient.createRuleset(
    rulesClient.createRulesFileFromSource('firestore.rules', source)
  );
  await rulesClient.releaseFirestoreRuleset(ruleset);
  console.log('تم نشر قواعد Firestore بنجاح. Ruleset name:', ruleset.name);
}

main().catch((err) => {
  console.error('خطأ:', err.message);
  process.exit(1);
});
