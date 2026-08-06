import 'package:flutter/material.dart';

import '../services/unit_guide_pdf_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'portal_header.dart';

/// دليل استخدام البوابة لمنسّقي الأقسام - يشرح خطوات عمل المنسّق فقط (تنزيل
/// ملف القسم، رفع الملف المعالج، ملف ذوي الإعاقة، متابعة الإنجاز، تغيير
/// كلمة المرور) مدعّمًا بصور فعلية من واجهة البوابة، حتى يستطيع أي منسّق -
/// بغض النظر عن مستوى إلمامه بالتقنية - فهم العمل من قراءة الدليل فقط.
class PortalOperationsGuidePage extends StatefulWidget {
  const PortalOperationsGuidePage({super.key});

  @override
  State<PortalOperationsGuidePage> createState() => _PortalOperationsGuidePageState();
}

class _PortalOperationsGuidePageState extends State<PortalOperationsGuidePage> {
  bool _isDownloading = false;
  bool _isDownloadingAdvisorGuide = false;

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      final bytes = await UnitGuidePdfService.buildInternalOperationsGuide();
      downloadBytes(bytes, 'دليل_استخدام_البوابة_للمنسقين.pdf');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadAdvisorGuide() async {
    setState(() => _isDownloadingAdvisorGuide = true);
    try {
      final bytes = await UnitGuidePdfService.buildAdvisorInternalSystemGuide();
      downloadBytes(bytes, 'دليل_المنظومة_الداخلية_للمرشد_الأكاديمي.pdf');
    } finally {
      if (mounted) setState(() => _isDownloadingAdvisorGuide = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'دليل استخدام البوابة',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'يشرح هذا الدليل خطوات عملك كمنسّق قسم على البوابة، من تسجيل الدخول '
                  'وحتى رفع الملفات المعالجة ومتابعة الإنجاز، مع صور توضيحية من '
                  'الواجهة الفعلية لكل خطوة.',
                  style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800, height: 1.8),
                ),
                const SizedBox(height: 28),

                _step(
                  number: 1,
                  title: 'تسجيل الدخول',
                  description: 'اختر تبويب "دخول منسّقي الوحدة"، ثم حدّد الشطر والقسم العلمي التابع لك، وأدخل كلمة المرور الخاصة بك.',
                  image: 'assets/images/guide/login_coordinator.png',
                ),
                _step(
                  number: 2,
                  title: 'تنزيل ملف قسمك',
                  description: 'بعد الدخول تظهر لك لوحة قسمك مباشرة (كما في الصورة أدناه). اضغط "تنزيل ملف قسمي" للحصول على ملف مضغوط بداخله ملف Excel منفصل ومحمي لكل مرشد أكاديمي.',
                  image: 'assets/images/guide/workspace_overview.png',
                ),
                _bullet('أرسل ملف كل مرشد له بطريقتك الخاصة (واتساب أو بريد شخصي).'),
                const SizedBox(height: 20),

                _step(
                  number: 3,
                  title: 'رفع الملفات المعالجة',
                  description: 'بعد استلام الملفات من المرشدين بعد تعبئتها، اضغط "رفع الملفات المعالجة" واختر ملف واحد أو أكثر دفعة واحدة. تُحدَّث حالة الطلبات تلقائيًا فور الرفع.',
                ),
                const SizedBox(height: 20),

                _step(
                  number: 4,
                  title: 'حالات ذوي الإعاقة',
                  description: 'إن وُجدت حالات إعاقة فعلية في قسمك، يظهر لك زر "تنزيل حالات ذوي الإعاقة" بنفس شكل بقية الأزرار. اضغط عليه للحصول على ملف واحد بكل هذه الحالات، وأرسله لأمين القسم، ثم ارفع عودته بنفس زر "رفع الملفات المعالجة" في الخطوة السابقة.',
                ),
                const SizedBox(height: 20),

                _step(
                  number: 5,
                  title: 'متابعة إنجاز قسمك',
                  description: 'قسم "متابعة إنجاز قسمي" يرتّب مرشدي قسمك حسب نسبة الإنجاز ويعرض لوحة رسم بياني تلقائية، مع خيارات طباعة وتنزيل Excel وPDF لهذا التقرير.',
                ),
                const SizedBox(height: 20),

                _step(
                  number: 6,
                  title: 'تفريغ حالة القسم (عند الحاجة)',
                  description: 'إذا رفعت ملفًا معالجًا بالخطأ، يمكنك الضغط على "تفريغ حالة القسم" للتراجع عن آخر عملية دمج - بيانات الطلاب الأصلية تبقى كما هي، فقط تُمسح حالة الإنجاز لتتمكن من إعادة الرفع الصحيح.',
                ),
                const SizedBox(height: 28),

                _step(
                  number: 7,
                  title: 'تغيير كلمة المرور',
                  description: 'اضغط أيقونة القفل 🔒 أعلى الشاشة بجانب زر تسجيل الخروج، أدخل كلمة المرور الحالية ثم الجديدة وتأكيدها، واضغط "حفظ".',
                  image: 'assets/images/guide/change_password.png',
                ),

                const SizedBox(height: 32),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : _download,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                    icon: _isDownloading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download),
                    label: const Text('تنزيل هذا الدليل PDF'),
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF6E9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'دليل المنظومة الداخلية للمرشد الأكاديمي',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppColors.greenDark),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'دليل منفصل يشرح للمرشد الأكاديمي كيفية استخدام المنظومة الداخلية الرسمية بالجامعة لإجراء عمليات الحذف والإضافة ونقل الشعب مباشرة. يمكنك تنزيله وإرساله لمرشدي قسمك.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.6),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _isDownloadingAdvisorGuide ? null : _downloadAdvisorGuide,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.greenDark),
                        icon: _isDownloadingAdvisorGuide
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.download),
                        label: const Text('تنزيل دليل المرشد الأكاديمي PDF'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 36, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: AppColors.gold),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.6))),
        ],
      ),
    );
  }

  Widget _step({required int number, required String title, required String description, String? image}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                child: Text('$number', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.greenDark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: AppColors.greenDark)),
                    const SizedBox(height: 4),
                    Text(description, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.7)),
                  ],
                ),
              ),
            ],
          ),
          if (image != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 42),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                  child: Image.asset(image, fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
