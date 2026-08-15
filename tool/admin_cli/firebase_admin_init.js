/*
 * دالة تهيئة firebase-admin مشتركة بجلسة Firebase CLI المسجَّلة على الجهاز
 * (بلا حاجة لمفتاح حساب خدمة) - نفس الأسلوب المستخدم في seed_advisor_roster.js.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const PROJECT_ID = 'sss-advising-tu';

const FIREBASE_CLI_CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const FIREBASE_CLI_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

function loadFirebaseCliRefreshToken() {
  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(configPath)) {
    throw new Error('Could not find a Firebase CLI session. Run "firebase login" first.');
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const refreshToken = config.tokens && config.tokens.refresh_token;
  if (!refreshToken) {
    throw new Error('Could not read Firebase CLI credentials. Run "firebase login" again.');
  }
  return refreshToken;
}

function initAdmin() {
  if (admin.apps.length) return admin.app();
  const refreshToken = loadFirebaseCliRefreshToken();
  const adcPath = path.join(os.tmpdir(), `sss-advising-adc-${process.pid}.json`);
  fs.writeFileSync(
    adcPath,
    JSON.stringify({
      type: 'authorized_user',
      client_id: FIREBASE_CLI_CLIENT_ID,
      client_secret: FIREBASE_CLI_CLIENT_SECRET,
      refresh_token: refreshToken,
    })
  );
  process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  process.on('exit', () => {
    try {
      fs.unlinkSync(adcPath);
    } catch {
      // ignore - temp file only
    }
  });

  return admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
}

module.exports = { initAdmin, PROJECT_ID };
