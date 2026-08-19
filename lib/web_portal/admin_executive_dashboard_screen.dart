import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_nav.dart';
import 'portal_header.dart';
import 'upload_hub_screen.dart';

/// لوحة الإدارة الرئيسية (Executive Dashboard) - أول ما يراه مدير الوحدة بعد
/// الدخول. أُعيدت صياغتها مرتين بطلب سليمان (2026-08-19): الأولى تحويلها من
/// صفحة روابط إلى لوحة مراقبة وقرار حقيقية، والثانية (هذه النسخة) لتصحيح
/// المصطلحات (إدارة الوحدة لا "الإدارة" وحدها - لبس مع قسم الإدارة العلمي)،
/// تكثيف الأحجام (Compact) بعد أن كانت البطاقات أكبر من حجم معلوماتها،
/// تمثيل مسار سير العمل الإداري الحقيقي (6 مراحل لا 5)، إعادة استخدام
/// المؤشرات الدائرية (Donut) من التصميم الأول، إضافة قسم "حالة الإنجاز حسب
/// نوع الإجراء"، وتحويل "تحتاج تدخل إدارة الوحدة" لهرم تدرّجي (شطر ← قسم
/// علمي ← تفاصيل) بدل عرض أسماء الطلبة مباشرة بالصفحة الرئيسية.
///
/// **جميع بيانات هذه الصفحة وهمية عمدًا (Mock Data)** بطلب سليمان صراحةً
/// لتقييم التصميم قبل الربط الفعلي بـFirestore - لا يوجد أي ربط بقاعدة
/// بيانات بعد.
class AdminExecutiveDashboardScreen extends StatelessWidget {
  const AdminExecutiveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'لوحة الإدارة',
      showBackButton: false,
      navItems: buildAdminNavItems(context, current: 'dashboard'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1600),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LastUpdateBar(),
                  SizedBox(height: 14),
                  _KpiRow(),
                  SizedBox(height: 18),
                  _WorkflowSection(),
                  SizedBox(height: 18),
                  _DepartmentPerformanceSection(),
                  SizedBox(height: 18),
                  _ActionTypeCompletionSection(),
                  SizedBox(height: 18),
                  _MainGrid(),
                  SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionTitle({required this.title, required this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    // فونت عناوين الأقسام رُفع إلى 18-20px (سليمان 2026-08-19: "عنوان متابعة
    // سير العمل 18-20px" - يُطبَّق على كل عناوين اللوحة بنفس المكوّن حفاظًا
    // على اتساق بصري واحد بدل عنوان استثنائي لقسم واحد).
    return Row(
      children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Icon(icon, size: 19, color: AppColors.greenDark),
        const SizedBox(width: 7),
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: AppColors.greenDark)),
        ),
        ?trailing,
      ],
    );
  }
}

/// مؤشر دائري مصغَّر (Donut) - نفس الأسلوب البصري الذي أُعجب سليمان به
/// بالتصميم الأول، بحجم Compact يناسب الاستخدام داخل بطاقات ووحدات صغيرة
/// بدل التوسّع بحجم كبير كالسابق.
class _MiniDonut extends StatelessWidget {
  final double percent;
  final Color color;
  final double size;
  final double strokeWidth;
  final String? centerText;

  const _MiniDonut({
    required this.percent,
    required this.color,
    this.size = 32,
    this.strokeWidth = 4.5,
    this.centerText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(value: 1, strokeWidth: strokeWidth, color: Colors.grey.shade200),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: percent.clamp(0, 1),
              strokeWidth: strokeWidth,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (centerText != null)
            Text(centerText!, style: TextStyle(fontSize: size * 0.27, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// شريط صغير هادئ: آخر تحديث للبيانات + رابط نصي خافت لصفحة "رفع ملفات"
/// المستقلة (باسم "إدارة البيانات" لا تكرار اسمها هنا - موجودة أصلاً بشريط
/// التنقّل العلوي).
class _LastUpdateBar extends StatelessWidget {
  const _LastUpdateBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.update, size: 13, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text('آخر تحديث للبيانات: 18 أغسطس 2026 – 10:35 ص', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
        Text('  |  ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400)),
        InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadHubScreen())),
          child: Text(
            'إدارة البيانات',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.grey.shade500,
              decoration: TextDecoration.underline,
              decorationColor: Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }
}

/// 4 بطاقات تشغيلية Compact - أصغر بنحو 20% من النسخة السابقة، مع مؤشر دائري
/// مصغَّر لبطاقة نسبة الإنجاز بدل أيقونة ثابتة.
class _KpiRow extends StatelessWidget {
  const _KpiRow();

  @override
  Widget build(BuildContext context) {
    // نسبة/عدد الإنجاز مُشتقّان من [_kDepartmentPerf] نفسها (المصدر المركزي)
    // بدل رقم منفصل - يضمن اتساق "78%" مع مجموع أداء الأقسام العلمية دائمًا.
    final total = _kTotalRequests;
    final completed = _kTotalCompleted;
    final rate = total == 0 ? 0 : (completed / total * 100).round();

    final cards = <Widget>[
      const _KpiCard(
        title: 'طلبات تحتاج إجراء',
        value: '12',
        meta: '3 طلبات جديدة منذ آخر دخول',
        icon: Icons.pending_actions_outlined,
        accent: AppColors.green,
      ),
      const _KpiCard(
        title: 'حالات مصعدة لإدارة الوحدة',
        value: '4',
        meta: 'تحتاج مراجعة عاجلة',
        icon: Icons.priority_high_rounded,
        accent: AppColors.errorRed,
      ),
      const _KpiCard(
        title: 'طلبات متأخرة',
        value: '7',
        meta: 'أقدم طلب منذ 3 أيام',
        icon: Icons.schedule_outlined,
        accent: AppColors.gold,
      ),
      _KpiCard(
        title: 'نسبة الإنجاز',
        value: '$rate%',
        meta: '$completed من أصل $total طلبًا',
        icon: Icons.donut_large_outlined,
        accent: AppColors.greenDark,
        donutPercent: rate / 100,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth < 650 ? 1 : (constraints.maxWidth < 1100 ? 2 : 4);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final c in cards) SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns, child: c),
        ],
      );
    });
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String meta;
  final IconData icon;
  final Color accent;
  final double? donutPercent;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.meta,
    required this.icon,
    required this.accent,
    this.donutPercent,
  });

  @override
  Widget build(BuildContext context) {
    // minHeight لا height ثابت - يمنع أي Overflow نهائيًا مهما كان المحتوى
    // (سليمان 2026-08-19: ظهر BOTTOM OVERFLOWED 4px مع height ثابت وخط أكبر -
    // "لا يتم حل المشكلة بالقص، بل برفع الارتفاع عند الحاجة"). المحتوى يبقى
    // مُمركَزًا كوحدة واحدة عبر Center، والخطوط رُفعت للحد المطلوب صراحةً
    // (لا مزيد من التصغير): عنوان 14، رقم 28، وصف 12.
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          // لمسة هوية دقيقة (خط ذهبي رفيع 3px) بدل إطار ذهبي حول البطاقة
          // كاملة - القسم لا يحمل عنوانًا خاصًا به فوقه (بخلاف بقية الأقسام)
          // فهذه اللمسة تعوّض حضور الهوية هنا تحديدًا (سليمان 2026-08-19).
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(width: 3, height: 30, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(3))),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (donutPercent != null)
                  _MiniDonut(percent: donutPercent!, color: accent, size: 46, strokeWidth: 5.5)
                else
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
                    child: Icon(icon, size: 23, color: accent),
                  ),
                const SizedBox(width: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 3),
                      Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.greenDark, height: 1)),
                      const SizedBox(height: 3),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// متابعة سير العمل - يمثّل المسار الإداري الحقيقي (6 مراحل، لا 5): إدارة
/// الوحدة توزّع الطلب، منسّق القسم العلمي يحيله للمرشد، المرشد ينفّذ، يعود
/// لمنسّق القسم العلمي للمراجعة، ثم منسّق الكلية، وأخيرًا يعود لإدارة الوحدة
/// (لا "مكتمل" منفصلة - العودة لإدارة الوحدة هي الإغلاق). الألوان تعبّر عن
/// الحالة (محايد أثناء المعالجة، أخضر عند الإغلاق) لا عن الدور - بطلب سليمان
/// صراحةً (2026-08-19).
class _WorkflowStage {
  final String role;
  final String subtitle;
  final int value;
  final Color color;
  const _WorkflowStage({required this.role, required this.subtitle, required this.value, required this.color});
}

class _WorkflowSection extends StatelessWidget {
  const _WorkflowSection();

  static const _neutral = Color(0xFF5B6B7C);

  static const _stages = [
    _WorkflowStage(role: 'إدارة الوحدة', subtitle: 'توزيع الطلبات', value: 10, color: _neutral),
    _WorkflowStage(role: 'منسّق القسم العلمي', subtitle: 'إحالة للمرشد', value: 14, color: _neutral),
    _WorkflowStage(role: 'المرشد الأكاديمي', subtitle: 'تنفيذ الإجراء', value: 9, color: _neutral),
    _WorkflowStage(role: 'منسّق القسم العلمي', subtitle: 'مراجعة الإجراء', value: 8, color: _neutral),
    _WorkflowStage(role: 'منسّق الكلية', subtitle: 'المراجعة والاعتماد', value: 6, color: _neutral),
    _WorkflowStage(role: 'إدارة الوحدة', subtitle: 'المراجعة والإغلاق', value: 13, color: AppColors.green),
  ];

  @override
  Widget build(BuildContext context) {
    // Process Stepper / Process Strip حقيقي - لا Cards كبيرة منفصلة بحدود
    // وخلفيات لكل مرحلة، بل عُقَد نصية مضغوطة داخل شريط أفقي واحد (بطلب
    // سليمان صراحةً 2026-08-19: تغيير نمط العرض نفسه لا تصغير البطاقات
    // السابقة). ارتفاع القسم بالكامل (العنوان + الشريط) يبقى ضمن 110-120px.
    // Padding مخفَّض (18×8 رأسيًا بدل 12) - رفع Typography بالمسار لا يعني
    // تكبير الحاوية، بل العكس: خط أوضح + حاوية أقصر بنحو 15-20% (سليمان
    // 2026-08-19).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(title: 'متابعة سير العمل', icon: Icons.timeline_outlined),
          const SizedBox(height: 4),
          Text('الأرقام تمثّل عدد الطلبات الموجودة حاليًا في كل مرحلة', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          // المسار يُمركَز أفقيًا كوحدة واحدة (Center داخل ConstrainedBox
          // بأقل عرض = عرض الحاوية) بدل الالتصاق بحافة البداية وترك فراغ
          // كبير على الحافة الأخرى في الشاشات العريضة (سليمان 2026-08-19):
          // "Process Strip نفسه يجب أن يكون Centered". يبقى قابلاً للتمرير
          // أفقيًا لو ضاقت الشاشة عن احتواء المسار كاملاً.
          LayoutBuilder(builder: (context, constraints) {
            final strip = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _stages.length; i++) ...[
                  _WorkflowStepNode(stage: _stages[i], isEdge: i == 0 || i == _stages.length - 1),
                  if (i != _stages.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_back, size: 16, color: Colors.grey.shade400),
                    ),
                ],
              ],
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Center(child: strip),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WorkflowStepNode extends StatelessWidget {
  final _WorkflowStage stage;
  final bool isEdge;
  const _WorkflowStepNode({required this.stage, this.isEdge = false});

  @override
  Widget build(BuildContext context) {
    // عقدة نصية بلا خلفية/حدود ثابتة - فقط Hover خفيف عند التفاعل، بما
    // يطابق شكل "Stepper" لا "Cards". الخطوط رُفعت للحد المطلوب صراحةً (اسم
    // الدور 14، الرقم 17، الوصف 12) - لا مزيد من التصغير (سليمان 2026-08-19).
    // مرحلتا البداية/النهاية (إدارة الوحدة) تحملان خطًّا ذهبيًا رفيعًا مائزًا
    // تحت الاسم - تمييز خفيف لبداية/نهاية الدورة بلا تحويلهما لبطاقتين.
    return InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('عرض حالات مرحلة "${stage.role} - ${stage.subtitle}" (${stage.value}) - سيُفعَّل عند الربط الفعلي')),
      ),
      borderRadius: BorderRadius.circular(8),
      hoverColor: stage.color.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(children: [
                TextSpan(text: stage.role, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.greenDark)),
                TextSpan(text: '  |  ', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                TextSpan(text: '${stage.value}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: stage.color)),
              ]),
            ),
            if (isEdge) ...[
              const SizedBox(height: 2),
              Container(width: 22, height: 2, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
            ],
            const SizedBox(height: 1),
            Text(stage.subtitle, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

/// إحصائيات قسم علمي واحد لشطر واحد - تُجمَع (male+female) لعرض "الكل".
class _DeptShatrStats {
  final int total;
  final int processing;
  final int overdue;
  final int completed;
  const _DeptShatrStats({required this.total, required this.processing, required this.overdue, required this.completed});

  int get rate => total == 0 ? 0 : (completed / total * 100).round();

  _DeptShatrStats operator +(_DeptShatrStats other) => _DeptShatrStats(
        total: total + other.total,
        processing: processing + other.processing,
        overdue: overdue + other.overdue,
        completed: completed + other.completed,
      );
}

class _DepartmentPerf {
  final String name;
  final _DeptShatrStats male;
  final _DeptShatrStats female;
  const _DepartmentPerf({required this.name, required this.male, required this.female});
}

/// مصدر Mock Data مركزي واحد لأداء الأقسام العلمية - تُشتَق منه كل الأرقام
/// المرتبطة بالإجمالي/المكتمل في بقية اللوحة (المؤشرات الرئيسية) بدل تكرار
/// أرقام منفصلة قد تتعارض حسابيًا (سليمان 2026-08-19: "جميع الأرقام يجب أن
/// تحكي نفس القصة" - إجمالي الطلبات 60، المكتمل 47، نسبة الإنجاز 78%).
const _kDepartmentPerf = [
  _DepartmentPerf(
    name: 'قسم الإدارة',
    male: _DeptShatrStats(total: 10, processing: 2, overdue: 1, completed: 7),
    female: _DeptShatrStats(total: 8, processing: 3, overdue: 0, completed: 5),
  ),
  _DepartmentPerf(
    name: 'قسم المحاسبة',
    male: _DeptShatrStats(total: 7, processing: 1, overdue: 0, completed: 6),
    female: _DeptShatrStats(total: 5, processing: 1, overdue: 0, completed: 4),
  ),
  _DepartmentPerf(
    name: 'قسم التسويق',
    male: _DeptShatrStats(total: 5, processing: 1, overdue: 0, completed: 4),
    female: _DeptShatrStats(total: 4, processing: 0, overdue: 0, completed: 4),
  ),
  _DepartmentPerf(
    name: 'قسم نظم المعلومات الإدارية',
    male: _DeptShatrStats(total: 8, processing: 1, overdue: 1, completed: 6),
    female: _DeptShatrStats(total: 6, processing: 1, overdue: 0, completed: 5),
  ),
  _DepartmentPerf(
    name: 'قسم الاقتصاد والتمويل',
    male: _DeptShatrStats(total: 4, processing: 1, overdue: 0, completed: 3),
    female: _DeptShatrStats(total: 3, processing: 0, overdue: 0, completed: 3),
  ),
];

/// إجمالي/مكتمل مشتقّان من [_kDepartmentPerf] نفسه - المرجع الوحيد لهذين
/// الرقمين بكل اللوحة (تستهلكهما بطاقة "نسبة الإنجاز" بالمؤشرات الرئيسية).
int get _kTotalRequests => _kDepartmentPerf.fold(0, (sum, d) => sum + d.male.total + d.female.total);
int get _kTotalCompleted => _kDepartmentPerf.fold(0, (sum, d) => sum + d.male.completed + d.female.completed);

enum _ShatrFilter { all, male, female }

/// أداء الأقسام العلمية - نُقل مباشرة بعد "متابعة سير العمل" (بطلب سليمان:
/// مدير الوحدة يحتاج معرفة أداء الأقسام العلمية مبكرًا)، مع فلتر شطر جديد
/// (الكل/الطلاب/الطالبات) لمقارنة الأداء بحسب الشطر.
class _DepartmentPerformanceSection extends StatefulWidget {
  const _DepartmentPerformanceSection();

  @override
  State<_DepartmentPerformanceSection> createState() => _DepartmentPerformanceSectionState();
}

class _DepartmentPerformanceSectionState extends State<_DepartmentPerformanceSection> {
  _ShatrFilter _filter = _ShatrFilter.all;

  _DeptShatrStats _statsFor(_DepartmentPerf d) => switch (_filter) {
        _ShatrFilter.male => d.male,
        _ShatrFilter.female => d.female,
        _ShatrFilter.all => d.male + d.female,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: 'أداء الأقسام العلمية',
            icon: Icons.bar_chart_outlined,
            trailing: _ShatrFilterChips(value: _filter, onChanged: (v) => setState(() => _filter = v)),
          ),
          const SizedBox(height: 10),
          const _DepartmentGridHeader(),
          const Divider(height: 10, thickness: 1),
          // ترتيب الأقسام العلمية يبقى كما هو متّفَق عليه (لا فرز حسب الأداء
          // أو الاسم) - نفس ترتيب [_kDepartmentPerf] دائمًا (سليمان 2026-08-19).
          for (final d in _kDepartmentPerf) _DepartmentRow(name: d.name, stats: _statsFor(d)),
        ],
      ),
    );
  }
}

/// رأس أعمدة واحد لكل الجدول - بدل تكرار مسميات "الإجمالي/قيد المعالجة/
/// متأخرة/مكتملة" داخل كل صف (سليمان 2026-08-19: كان يسبّب تكرارًا بصريًا
/// ويزيد الارتفاع بلا فائدة). التصميم يبقى خفيفًا (لا حدود شبكية ثقيلة).
class _DepartmentGridHeader extends StatelessWidget {
  const _DepartmentGridHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Expanded(flex: 3, child: SizedBox()),
          Expanded(flex: 2, child: Text('الإجمالي', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('قيد المعالجة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('متأخرة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('مكتملة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 3, child: Text('نسبة الإنجاز', textAlign: TextAlign.center, style: style)),
        ],
      ),
    );
  }
}

class _ShatrFilterChips extends StatelessWidget {
  final _ShatrFilter value;
  final ValueChanged<_ShatrFilter> onChanged;
  const _ShatrFilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _ShatrFilter v) {
      final selected = value == v;
      return InkWell(
        onTap: () => onChanged(v),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: selected ? AppColors.green : Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.grey.shade700)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      chip('الكل', _ShatrFilter.all),
      chip('شطر الطلاب', _ShatrFilter.male),
      chip('شطر الطالبات', _ShatrFilter.female),
    ]);
  }
}

class _DepartmentRow extends StatelessWidget {
  final String name;
  final _DeptShatrStats stats;
  const _DepartmentRow({required this.name, required this.stats});

  Color get _rateColor => stats.rate >= 80
      ? AppColors.green
      : stats.rate >= 60
          ? AppColors.gold
          : AppColors.errorRed;

  @override
  Widget build(BuildContext context) {
    // صف أرقام فقط - المسميات (الإجمالي/قيد المعالجة/متأخرة/مكتملة) صارت
    // برأس أعمدة واحد (_DepartmentGridHeader) بدل تكرارها بكل صف (سليمان
    // 2026-08-19: كان يزيد الارتفاع بلا فائدة). نفس توزيع flex الموجود
    // بالرأس تمامًا حتى تتحاذى الأعمدة رأسيًا.
    return InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('عرض تفاصيل "$name" - سيُفعَّل عند الربط الفعلي')),
      ),
      borderRadius: BorderRadius.circular(10),
      hoverColor: AppColors.green.withValues(alpha: 0.05),
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        constraints: const BoxConstraints(minHeight: 42),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
        child: LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                    Text('${stats.rate}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _rateColor)),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 12, runSpacing: 2, children: [
                  _inlineStat('الإجمالي', stats.total),
                  _inlineStat('قيد المعالجة', stats.processing),
                  _inlineStat('متأخرة', stats.overdue),
                  _inlineStat('مكتملة', stats.completed),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: stats.rate / 100, minHeight: 5, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(_rateColor)),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 3, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
              Expanded(flex: 2, child: Text('${stats.total}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.grey.shade700))),
              Expanded(flex: 2, child: Text('${stats.processing}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF2563EB)))),
              Expanded(flex: 2, child: Text(stats.overdue == 0 ? '—' : '${stats.overdue}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: stats.overdue == 0 ? Colors.grey.shade400 : AppColors.errorRed))),
              Expanded(flex: 2, child: Text('${stats.completed}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.green))),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: stats.rate / 100, minHeight: 5, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation(_rateColor)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 32, child: Text('${stats.rate}%', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _rateColor))),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _inlineStat(String label, int value) => Text('$label: $value', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600));
}

/// حالة الإنجاز حسب نوع الإجراء - قسم مستعاد من التصميم الأول (بطلب سليمان
/// صراحةً: يجيب "في أي نوع من الطلبات يوجد التأخير؟" بخلاف أداء الأقسام
/// العلمية الذي يجيب "أين يوجد التأخير؟"). عنوان عادي متناسق مع بقية عناوين
/// اللوحة بدل الشريط الأخضر الكبير السابق.
class _ActionTypeStats {
  final String label;
  final int completed;
  final int processing;
  final int notStarted;
  const _ActionTypeStats({required this.label, required this.completed, required this.processing, required this.notStarted});

  int get total => completed + processing + notStarted;
  double get rate => total == 0 ? 0 : completed / total;
}

class _ActionTypeCompletionSection extends StatelessWidget {
  const _ActionTypeCompletionSection();

  // مجموع الإجمالي هنا (31+18+11=60) والمكتمل (24+15+8=47) يطابقان عمدًا
  // إجمالي/مكتمل "أداء الأقسام العلمية" (_kTotalRequests/_kTotalCompleted) -
  // نفس الـ60 طلبًا مصنَّفة بحسب القسم العلمي هنا، وبحسب نوع الإجراء هناك.
  static const _types = [
    _ActionTypeStats(label: 'طلبات الإضافة', completed: 24, processing: 4, notStarted: 3),
    _ActionTypeStats(label: 'طلبات الحذف', completed: 15, processing: 2, notStarted: 1),
    _ActionTypeStats(label: 'طلبات تعديل الشعبة', completed: 8, processing: 2, notStarted: 1),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(title: 'حالة الإنجاز حسب نوع الإجراء', icon: Icons.pie_chart_outline_rounded),
          const SizedBox(height: 8),
          // توزيع العناصر الثلاثة بالتساوي على عرض الحاوية (Expanded) - بدل
          // Wrap بعرض ثابت كان يجمّعها يسارًا ويترك فراغًا كبيرًا يمينًا على
          // الشاشات العريضة (سليمان 2026-08-19).
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(children: [for (final t in _types) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ActionTypeCard(stats: t))]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _types.length; i++) ...[
                  if (i != 0) const SizedBox(width: 10),
                  Expanded(child: _ActionTypeCard(stats: _types[i])),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ActionTypeCard extends StatelessWidget {
  final _ActionTypeStats stats;
  const _ActionTypeCard({required this.stats});

  Color get _color => stats.rate >= 0.6
      ? AppColors.green
      : stats.rate >= 0.4
          ? AppColors.gold
          : AppColors.errorRed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _MiniDonut(percent: stats.rate, color: _color, size: 39, strokeWidth: 5, centerText: '${(stats.rate * 100).round()}%'),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${stats.label} — ${stats.total} طلبًا', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${stats.completed} مكتمل • ${stats.processing} قيد المعالجة • ${stats.notStarted} لم يبدأ',
                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// درجة أهمية الحالة (تُستخدم لتلوين وتصنيف الحالات ضمن "تحتاج تدخل إدارة
/// الوحدة" - لا علاقة لها بالدور المسؤول، فقط بحالة الطلب نفسه).
enum _CaseSeverity { urgent, overdue, review }

class _ManagementCase {
  final String shatr; // 'male' | 'female'
  final String department;
  final String student;
  final String type;
  final String status;
  final String reason;
  final String waiting;
  final _CaseSeverity severity;
  const _ManagementCase({
    required this.shatr,
    required this.department,
    required this.student,
    required this.type,
    required this.status,
    required this.reason,
    required this.waiting,
    required this.severity,
  });
}

/// 14 حالة وهمية (8 بشطر الطلاب، 6 بشطر الطالبات) - نفس توزيع الأمثلة التي
/// طلبها سليمان بالضبط لشطر الطلاب.
const _kManagementCases = <_ManagementCase>[
  _ManagementCase(
    shatr: 'male',
    department: 'قسم الإدارة',
    student: 'فهد ناصر المطيري',
    type: 'إضافة وحذف',
    status: 'أعيدت مرتين',
    reason: 'تعارض في بيانات المقررات',
    waiting: '6 ساعات',
    severity: _CaseSeverity.review,
  ),
  _ManagementCase(
    shatr: 'male',
    department: 'قسم الإدارة',
    student: 'عبدالرحمن سعيد الحارثي',
    type: 'حالة إرشادية',
    status: 'مصعدة لإدارة الوحدة',
    reason: 'تجاوزت مدة المعالجة',
    waiting: 'يوم واحد',
    severity: _CaseSeverity.urgent,
  ),
  _ManagementCase(
    shatr: 'male',
    department: 'قسم الإدارة',
    student: 'سلطان فهد العمري',
    type: 'إضافة مقرر',
    status: 'متأخرة',
    reason: 'تجاوزت مدة المعالجة',
    waiting: '4 أيام',
    severity: _CaseSeverity.overdue,
  ),
  _ManagementCase(
    shatr: 'male',
    department: 'قسم المحاسبة',
    student: 'تركي عبدالله الزهراني',
    type: 'حذف مقرر',
    status: 'تحتاج مراجعة',
    reason: 'المرشد المختار غير مطابق',
    waiting: '5 ساعات',
    severity: _CaseSeverity.review,
  ),
  _ManagementCase(
    shatr: 'male',
    department: 'قسم التسويق',
    student: 'محمد سالم الشهري',
    type: 'حذف مقرر',
    status: 'غير مسندة',
    reason: 'طلب غير مسند لمرشد',
    waiting: 'يوم واحد',
    severity: _CaseSeverity.review,
  ),
  _ManagementCase(
    shatr: 'male',
    department: 'قسم التسويق',
    student: 'خالد إبراهيم الغامدي',
    type: 'إضافة وحذف',
    status: 'مصعدة لإدارة الوحدة',
    reason: 'طالب من ذوي الإعاقة',
    waiting: '3 ساعات',
    severity: _CaseSeverity.urgent,
  ),
  _ManagementCase(
    shatr: 'male',
    department: 'قسم نظم المعلومات الإدارية',
    student: 'أحمد محمد العتيبي',
    type: 'إضافة مقرر',
    status: 'مصعدة لإدارة الوحدة',
    reason: 'تجاوزت مدة المعالجة',
    waiting: 'يومان',
    severity: _CaseSeverity.urgent,
  ),
  _ManagementCase(
    shatr: 'male',
    department: 'قسم الاقتصاد والتمويل',
    student: 'ياسر عبدالعزيز السبيعي',
    type: 'حالة إرشادية',
    status: 'تحتاج قرارًا من إدارة الوحدة',
    reason: 'طالب متوقع تخرجه',
    waiting: '4 ساعات',
    severity: _CaseSeverity.review,
  ),
  _ManagementCase(
    shatr: 'female',
    department: 'قسم الإدارة',
    student: 'ريم عبدالعزيز آل سعيد',
    type: 'حالة إرشادية',
    status: 'تحتاج قرارًا من إدارة الوحدة',
    reason: 'طالبة متوقع تخرجها',
    waiting: '4 ساعات',
    severity: _CaseSeverity.review,
  ),
  _ManagementCase(
    shatr: 'female',
    department: 'قسم المحاسبة',
    student: 'سارة عبدالله القحطاني',
    type: 'حالة إرشادية',
    status: 'تحتاج مراجعة',
    reason: 'المرشد المختار غير مطابق',
    waiting: '5 ساعات',
    severity: _CaseSeverity.review,
  ),
  _ManagementCase(
    shatr: 'female',
    department: 'قسم المحاسبة',
    student: 'لمياء خالد الدوسري',
    type: 'إضافة مقرر',
    status: 'متأخرة',
    reason: 'تجاوزت مدة المعالجة',
    waiting: '3 أيام',
    severity: _CaseSeverity.overdue,
  ),
  _ManagementCase(
    shatr: 'female',
    department: 'قسم التسويق',
    student: 'نورة فهد المالكي',
    type: 'حذف مقرر',
    status: 'مصعدة لإدارة الوحدة',
    reason: 'طالبة من ذوي الإعاقة',
    waiting: '3 ساعات',
    severity: _CaseSeverity.urgent,
  ),
  _ManagementCase(
    shatr: 'female',
    department: 'قسم نظم المعلومات الإدارية',
    student: 'هند سعد القرني',
    type: 'تعديل شعبة',
    status: 'تحتاج مراجعة',
    reason: 'تعارض في بيانات الشعبة',
    waiting: '6 ساعات',
    severity: _CaseSeverity.review,
  ),
  _ManagementCase(
    shatr: 'female',
    department: 'قسم الاقتصاد والتمويل',
    student: 'عبير ناصر الجهني',
    type: 'إضافة وحذف',
    status: 'مصعدة لإدارة الوحدة',
    reason: 'تجاوزت مدة المعالجة',
    waiting: 'يومان',
    severity: _CaseSeverity.urgent,
  ),
];

/// شبكة رئيسية: تحتاج تدخل إدارة الوحدة (70%) + النشاطات والتنبيهات (30%) -
/// بلا فرض تساوي الارتفاع (كل قسم بارتفاعه الطبيعي، بطلب سليمان صراحةً).
class _MainGrid extends StatelessWidget {
  const _MainGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 1000;
      if (stacked) {
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ManagementAttentionSection(),
            SizedBox(height: 14),
            _ActivityFeedSection(),
          ],
        );
      }
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: _ManagementAttentionSection()),
          SizedBox(width: 14),
          Expanded(flex: 3, child: _ActivityFeedSection()),
        ],
      );
    });
  }
}

/// "تحتاج تدخل إدارة الوحدة" - هرم تدرّجي (الشطر ← القسم العلمي ← تفاصيل
/// الحالة) بدل عرض أسماء الطلبة مباشرة بالصفحة الرئيسية (بطلب سليمان
/// صراحةً: Dashboard يعرض الصورة الإدارية العامة، وتفاصيل الحالات الفردية
/// تظهر فقط بعد الدخول للقسم العلمي).
class _ManagementAttentionSection extends StatefulWidget {
  const _ManagementAttentionSection();

  @override
  State<_ManagementAttentionSection> createState() => _ManagementAttentionSectionState();
}

class _ManagementAttentionSectionState extends State<_ManagementAttentionSection> {
  // شطر الطلاب محدَّد افتراضيًا (لا يُترك الشطران مغلقين) - حتى يظهر
  // المستوى الثاني (الأقسام العلمية) فورًا بدل مساحة فارغة كبيرة (سليمان
  // 2026-08-19).
  String _shatr = 'male';
  String? _department;

  List<_ManagementCase> get _casesInShatr => _kManagementCases.where((c) => c.shatr == _shatr).toList();
  List<_ManagementCase> get _casesInDept => _casesInShatr.where((c) => c.department == _department).toList();

  String _severityLabel(_CaseSeverity s) => switch (s) {
        _CaseSeverity.urgent => 'عاجلة',
        _CaseSeverity.overdue => 'متأخرة',
        _CaseSeverity.review => 'مراجعة',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Badge عدد الحالات مُلاصِق للعنوان مباشرةً - لا يُستخدَم trailing
          // العام (_SectionTitle) الذي كان يدفعه لأقصى الطرف الآخر بعيدًا عن
          // العنوان (سليمان 2026-08-19: "معلومتان مرتبطتان يجب أن تكونا
          // متقاربتين").
          Row(
            children: [
              Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              const Icon(Icons.report_gmailerrorred_outlined, size: 19, color: AppColors.greenDark),
              const SizedBox(width: 7),
              const Text('تحتاج تدخل إدارة الوحدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: AppColors.greenDark)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.errorRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text('عدد الحالات: ${_kManagementCases.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.errorRed)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildShatrTabs(),
          const SizedBox(height: 8),
          if (_department != null) ...[
            _buildBreadcrumb(),
            const SizedBox(height: 8),
          ],
          if (_department == null) _buildDepartmentLevel() else _buildCaseLevel(),
        ],
      ),
    );
  }

  /// شريحتان صغيرتان (Segmented Control) بدل بطاقتين كبيرتين - توفّر مساحة
  /// كبيرة كانت تظهر فارغة أسفلهما (سليمان 2026-08-19).
  Widget _buildShatrTabs() {
    final male = _kManagementCases.where((c) => c.shatr == 'male').length;
    final female = _kManagementCases.where((c) => c.shatr == 'female').length;

    Widget tab(String label, String value, int count) {
      final selected = _shatr == value;
      return InkWell(
        onTap: () => setState(() {
          _shatr = value;
          _department = null;
        }),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
          decoration: BoxDecoration(color: selected ? AppColors.green : Colors.grey.shade100, borderRadius: BorderRadius.circular(7)),
          child: Text(
            '$label  $count',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.grey.shade700),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      tab('شطر الطلاب', 'male', male),
      const SizedBox(width: 6),
      tab('شطر الطالبات', 'female', female),
    ]);
  }

  Widget _buildBreadcrumb() {
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
      _crumb(_shatr == 'male' ? 'شطر الطلاب' : 'شطر الطالبات', onTap: () => setState(() => _department = null)),
      Icon(Icons.chevron_left, size: 14, color: Colors.grey.shade400),
      _crumb(_department!, isCurrent: true),
    ]);
  }

  Widget _crumb(String label, {VoidCallback? onTap, bool isCurrent = false}) {
    final text = Text(
      label,
      style: TextStyle(fontSize: 11.5, fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600, color: isCurrent ? AppColors.greenDark : Colors.grey.shade500),
    );
    if (onTap == null || isCurrent) return text;
    return InkWell(onTap: onTap, child: text);
  }

  /// Compact Structured Grid بدل صف بمعلومتين في طرفيه - عمود لكل تصنيف
  /// (عاجلة/متأخرة/مراجعة) بدل نص حر متفرق (سليمان 2026-08-19).
  Widget _buildDepartmentLevel() {
    final cases = _casesInShatr;
    final departments = cases.map((c) => c.department).toSet().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeptGridHeader(),
        const Divider(height: 8, thickness: 1),
        for (final dep in departments) _buildDeptRow(dep, cases.where((c) => c.department == dep).toList()),
      ],
    );
  }

  Widget _buildDeptGridHeader() {
    TextStyle style = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Expanded(flex: 3, child: SizedBox()),
          Expanded(flex: 2, child: Text('عاجلة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('متأخرة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('مراجعة', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('الإجمالي', textAlign: TextAlign.center, style: style)),
          const SizedBox(width: 19),
        ],
      ),
    );
  }

  Widget _buildDeptRow(String dep, List<_ManagementCase> cases) {
    final urgent = cases.where((c) => c.severity == _CaseSeverity.urgent).length;
    final overdue = cases.where((c) => c.severity == _CaseSeverity.overdue).length;
    final review = cases.where((c) => c.severity == _CaseSeverity.review).length;

    Widget cell(int n, Color color) => Expanded(
          flex: 2,
          child: Text(n == 0 ? '—' : '$n', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: n == 0 ? Colors.grey.shade400 : color)),
        );

    return InkWell(
      onTap: () => setState(() => _department = dep),
      borderRadius: BorderRadius.circular(8),
      hoverColor: AppColors.green.withValues(alpha: 0.05),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(minHeight: 38),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(dep, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5))),
            cell(urgent, AppColors.errorRed),
            cell(overdue, AppColors.gold),
            cell(review, const Color(0xFF2563EB)),
            Expanded(flex: 2, child: Text('${cases.length}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.greenDark))),
            SizedBox(width: 19, child: Icon(Icons.chevron_left, size: 15, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _buildCaseLevel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final c in _casesInDept) _ManagementCaseRow(item: c, severityLabel: _severityLabel(c.severity))],
    );
  }
}

class _ManagementCaseRow extends StatelessWidget {
  final _ManagementCase item;
  final String severityLabel;
  const _ManagementCaseRow({required this.item, required this.severityLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(item.student, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                      child: Text(item.status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.errorRed)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${item.type} · ${item.reason}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(item.waiting, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  minimumSize: const Size(0, 26),
                  foregroundColor: AppColors.green,
                  side: const BorderSide(color: AppColors.green),
                ),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('عرض تفاصيل حالة "${item.student}" - سيُفعَّل عند الربط الفعلي')),
                ),
                child: const Text('عرض', style: TextStyle(fontSize: 10.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityItem {
  final String time;
  final String text;
  final IconData icon;
  final Color color;
  const _ActivityItem({required this.time, required this.text, required this.icon, required this.color});
}

enum _FeedTab { alerts, activity }

/// النشاطات والتنبيهات - أصبحت تبويبين مستقلّين ("التنبيهات" الافتراضي و
/// "آخر النشاطات") بدل قائمة مختلطة، لأن التنبيه (يحتاج انتباهًا) والنشاط
/// العادي (سجل لما حدث) ليسا بنفس الأهمية (سليمان 2026-08-19). قائمة العمل
/// الفعلية تبقى حصرًا بقسم "تحتاج تدخل إدارة الوحدة" - التنبيه هنا إشعار
/// فقط، لا قائمة عمل ثانية. ارتفاع القسم طبيعي (لا يُساوى بارتفاع القسم
/// المجاور)، ويعرض 5 عناصر كحد أقصى + زر "عرض الكل" يتبع التبويب النشط.
class _ActivityFeedSection extends StatefulWidget {
  const _ActivityFeedSection();

  @override
  State<_ActivityFeedSection> createState() => _ActivityFeedSectionState();
}

class _ActivityFeedSectionState extends State<_ActivityFeedSection> {
  _FeedTab _tab = _FeedTab.alerts;

  static const _alerts = [
    _ActivityItem(time: 'منذ 20 دقيقة', text: 'تم تصعيد حالة إلى إدارة الوحدة', icon: Icons.priority_high_rounded, color: AppColors.errorRed),
    _ActivityItem(time: 'منذ ساعتين', text: 'طلب تجاوز مدة المعالجة', icon: Icons.warning_amber_rounded, color: AppColors.gold),
    _ActivityItem(time: 'منذ 3 ساعات', text: 'طالب مرتبط بمرشد غير مطابق', icon: Icons.person_search_outlined, color: AppColors.gold),
    _ActivityItem(time: 'منذ 5 ساعات', text: 'حالة تحتاج قرارًا من إدارة الوحدة', icon: Icons.gavel_outlined, color: AppColors.errorRed),
    _ActivityItem(time: 'منذ يوم واحد', text: 'طلب غير مسند إلى مرشد', icon: Icons.person_off_outlined, color: AppColors.gold),
  ];

  static const _activities = [
    _ActivityItem(time: '10:12 ص', text: 'تم إنهاء طلب إضافة مقرر', icon: Icons.check_circle_outline, color: AppColors.green),
    _ActivityItem(time: '09:30 ص', text: 'تم تحديث بيانات المقررات الدراسية', icon: Icons.sync_outlined, color: Color(0xFF2563EB)),
    _ActivityItem(time: '08:47 ص', text: 'تم إسناد حالة إلى منسّق القسم العلمي', icon: Icons.assignment_ind_outlined, color: Color(0xFF2563EB)),
    _ActivityItem(time: '08:20 ص', text: 'تم إنهاء طلب حذف مقرر', icon: Icons.check_circle_outline, color: AppColors.green),
    _ActivityItem(time: '07:55 ص', text: 'تم اعتماد مراجعة منسّق الكلية', icon: Icons.verified_outlined, color: Color(0xFF2563EB)),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _tab == _FeedTab.alerts ? _alerts : _activities;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabStrip(),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++) _ActivityRow(item: items[i], isLast: i == items.length - 1),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_tab == _FeedTab.alerts ? 'عرض جميع التنبيهات - سيُفعَّل عند الربط الفعلي' : 'عرض جميع النشاطات - سيُفعَّل عند الربط الفعلي')),
              ),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: const Size(0, 28)),
              child: Text(_tab == _FeedTab.alerts ? 'عرض جميع التنبيهات' : 'عرض جميع النشاطات', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip() {
    Widget tab(String label, _FeedTab value) {
      final selected = _tab == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppColors.green : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.grey.shade700)),
          ),
        ),
      );
    }

    return Row(children: [
      tab('التنبيهات', _FeedTab.alerts),
      const SizedBox(width: 6),
      tab('آخر النشاطات', _FeedTab.activity),
    ]);
  }
}

class _ActivityRow extends StatelessWidget {
  final _ActivityItem item;
  final bool isLast;
  const _ActivityRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(item.icon, size: 12, color: item.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Text(item.time, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
