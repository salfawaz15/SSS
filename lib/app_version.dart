/// رقم/اسم الإصدار المضمَّن بهذه النسخة المبنية من الموقع - يُنشَأ هذا الملف
/// **تلقائيًا** بخطوة "Generate version files from pubspec.yaml" بملف
/// `.github/workflows/deploy.yml` أثناء كل بناء (يستخرج القيمتين من سطر
/// `version:` بـ`pubspec.yaml` مباشرة)، فيبقى مطابقًا دومًا لملف
/// `web/version.json` المنشور بنفس اللحظة بلا أي تحديث يدوي مزدوج. القيم
/// أدناه للتطوير المحلي فقط (لا تُقرَأ أثناء النشر الفعلي عبر GitHub Actions).
const int kAppBuildNumber = 19;
const String kAppVersionName = '1.0.16';
