import 'package:flutter/material.dart';

import '../models/hardship_case.dart';
import '../theme/dashboard_tokens.dart';
import 'advising_cases_admin_screen.dart';
import 'advising_hub_screen.dart';
import 'advising_schedule_admin_screen.dart';
import 'advisor_students_lookup_screen.dart';
import 'hardship_cases_admin_screen.dart';
import 'support_cases_admin_screen.dart';

/// نظام تصميم موحّد لـ"لوحة الإرشاد" (نظرة عامة + 5 شاشات فرعية) - بديل
/// لتصحيحات بصرية منعزلة بكل شاشة. كل الشاشات الست تشترك بنفس التنقّل
/// الداخلي وهيدر الصفحة والحالة الفارغة ونظام الحالة اللونية ونافذة مسار
/// المتابعة، بهوية `DashTokens` نفسها (لا هوية جديدة).
///
/// الهيدر العام للبوابة (`PortalHeader`/التبويب العلوي "لوحة الإرشاد" وسهم
/// الرجوع) **لا يُمَس هنا إطلاقًا** - هذا الملف يبني فقط منطقة المحتوى تحت
/// ذلك الهيدر.

/// عرض مساحة العمل الأقصى الموحَّد لكل محتوى لوحة الإرشاد (تنقّل داخلي +
/// هيدر صفحة + مؤشرات + فلاتر + جداول) - قيمة واحدة يُبنى عليها كل شيء بدل
/// عرض مختلف بكل قسم (كان التنقّل الداخلي بعرض الشاشة الكامل بينما المحتوى
/// أسفله محصور بعرض أضيق ومُمركَز، فبدا التنقّل "منزاحًا" عن بقية الصفحة -
/// سليمان 2026-08-21: "التصحيح العاجل").
const double kAdvisingWorkspaceMaxWidth = 1400;

/// مفاتيح الشاشات الست الثابتة - نفس الترتيب المطلوب بالتنقّل الداخلي.
enum AdvisingSection { overview, cases, lookup, hardship, support, schedule }

class _AdvisingDestination {
  final AdvisingSection section;
  final String label;
  final IconData icon;
  final bool Function(bool isSuperAdmin) visible;
  final WidgetBuilder builder;

  const _AdvisingDestination({
    required this.section,
    required this.label,
    required this.icon,
    required this.visible,
    required this.builder,
  });
}

final List<_AdvisingDestination> _kAdvisingDestinations = [
  _AdvisingDestination(
    section: AdvisingSection.overview,
    label: 'نظرة عامة',
    icon: Icons.query_stats_outlined,
    visible: (_) => true,
    builder: (_) => const AdvisingHubScreen(),
  ),
  _AdvisingDestination(
    section: AdvisingSection.cases,
    label: 'متابعة الحالات',
    icon: Icons.fact_check_outlined,
    visible: (isSuperAdmin) => isSuperAdmin,
    builder: (_) => const AdvisingCasesAdminScreen(),
  ),
  _AdvisingDestination(
    section: AdvisingSection.lookup,
    label: 'بحث عن مرشد',
    icon: Icons.person_search_outlined,
    visible: (isSuperAdmin) => isSuperAdmin,
    builder: (_) => const AdvisorStudentsLookupScreen(),
  ),
  _AdvisingDestination(
    section: AdvisingSection.hardship,
    label: 'الظروف الخاصة',
    icon: Icons.volunteer_activism_outlined,
    visible: (_) => true,
    builder: (_) => const HardshipCasesAdminScreen(),
  ),
  _AdvisingDestination(
    section: AdvisingSection.support,
    label: 'الدعم النفسي والاجتماعي',
    icon: Icons.favorite_border,
    visible: (_) => true,
    builder: (_) => const SupportCasesAdminScreen(),
  ),
  _AdvisingDestination(
    section: AdvisingSection.schedule,
    label: 'فترات الإرشاد',
    icon: Icons.schedule_outlined,
    visible: (_) => true,
    builder: (_) => const AdvisingScheduleAdminScreen(),
  ),
];

/// شريط التنقّل الداخلي الثابت لكل شاشات لوحة الإرشاد - يظهر مباشرة تحت
/// الهيدر العام المعتمَد (لا يستبدله). التبديل بين التبويبات يستخدم
/// `pushReplacement` (لا يكدّس شاشات فوق بعضها) حتى يبقى المستخدم داخل نفس
/// "مساحة العمل" منطقيًا.
class AdvisingSubNavigation extends StatelessWidget {
  final AdvisingSection current;
  final bool isSuperAdmin;

  const AdvisingSubNavigation({super.key, required this.current, required this.isSuperAdmin});

  @override
  Widget build(BuildContext context) {
    final items = _kAdvisingDestinations.where((d) => d.visible(isSuperAdmin)).toList();
    // `Wrap` مُمركَز داخل نفس حاوية مساحة العمل [kAdvisingWorkspaceMaxWidth]
    // المستخدَمة بمحتوى كل صفحة أسفله - بدل `Row`+تمرير أفقي غير مُقيَّد كان
    // يُحاذي التبويبات لليمين بمعزل عن عرض المحتوى فيبدو الشريط "منزاحًا".
    // على الشاشات الضيقة تلتفّ التبويبات لسطر ثانٍ بدل تمرير أفقي - أبسط
    // وأكثر ثباتًا مع 6 تبويبات نصّها قصير.
    return Container(
      width: double.infinity,
      color: DashTokens.cardBg,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: DashTokens.border))),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kAdvisingWorkspaceMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Semantics(
              container: true,
              label: 'التنقل داخل لوحة الإرشاد',
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final d in items)
                    _SubNavItem(
                      label: d.label,
                      icon: d.icon,
                      active: d.section == current,
                      onTap: d.section == current
                          ? null
                          : () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: d.builder)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  const _SubNavItem({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        focusColor: DashTokens.green900.withValues(alpha: 0.08),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? DashTokens.green900.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.transparent),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: active ? DashTokens.green900 : DashTokens.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? DashTokens.green900 : DashTokens.textSecondary,
                    ),
                  ),
                ],
              ),
              if (active)
                Positioned(
                  bottom: -8,
                  right: 28,
                  left: 28,
                  child: Container(height: 2, decoration: BoxDecoration(color: DashTokens.gold600, borderRadius: BorderRadius.circular(999))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// فتات تنقّل (breadcrumb) خافتة أعلى عنوان الصفحة - ليست بديلاً عن العنوان.
class AdvisingBreadcrumb extends StatelessWidget {
  final String trail;

  const AdvisingBreadcrumb({super.key, required this.trail});

  @override
  Widget build(BuildContext context) {
    return Text('لوحة الإرشاد ← $trail', style: const TextStyle(fontSize: 12, color: DashTokens.textMuted));
  }
}

/// هيدر صفحة موحَّد لكل شاشات لوحة الإرشاد: فتات تنقّل ↓ عنوان ↓ وصف قصير ↓
/// إجراءات سياقية اختيارية (بدل سهم رجوع منعزل بلا نص).
class AdvisingPageHeader extends StatelessWidget {
  final String breadcrumbTrail;
  final String title;
  final String description;
  final IconData icon;
  final List<Widget> actions;

  const AdvisingPageHeader({
    super.key,
    required this.breadcrumbTrail,
    required this.title,
    required this.description,
    required this.icon,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdvisingBreadcrumb(trail: breadcrumbTrail),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: DashTokens.green900),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(fontSize: 11.5, color: DashTokens.textSecondary.withValues(alpha: 0.9))),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ],
    );
  }
}

/// زر رجوع سياقي واضح (نص + سهم) بدل سهم عائم بلا تسمية - يُستخدَم فقط حين
/// يحتاج المستخدم فعليًا العودة للنظرة العامة (التنقّل الداخلي أعلاه يغني عن
/// معظم حالات الرجوع).
class AdvisingBackAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const AdvisingBackAction({super.key, this.label = 'العودة إلى نظرة عامة', required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(foregroundColor: DashTokens.green900),
    );
  }
}

/// بطاقة مؤشر (KPI) تُبرز الرقم قبل كل شيء - نسخة أكثر إحكامًا من
/// `DashKpiCard` (نفس الهوية: شريط أعلى ملوَّن + أيقونة دائرية) لكن بخط رقم
/// أكبر ليهيمن على البطاقة، مع حالة لونية دلالية اختيارية.
class AdvisingMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color accent;

  const AdvisingMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 115),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        border: Border.all(color: DashTokens.border),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        boxShadow: DashTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DashTokens.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: accent),
              ),
            ],
          ),
          Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1, color: DashTokens.textPrimary)),
          Text(note, style: const TextStyle(fontSize: 11, color: DashTokens.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// حالة فارغة موحَّدة قابلة لإعادة الاستخدام بكل شاشات لوحة الإرشاد - أيقونة
/// + عنوان واضح + شرح قصير + إجراء اختياري، بدل جملة رمادية معزولة بمنتصف
/// شاشة فارغة.
class AdvisingEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  const AdvisingEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        border: Border.all(color: DashTokens.border),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: DashTokens.textMuted),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DashTokens.textPrimary), textAlign: TextAlign.center),
          const SizedBox(height: 5),
          Text(description, style: const TextStyle(fontSize: 12, color: DashTokens.textMuted, height: 1.4), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// شارة حالة (status chip) دلالية اللون - تُستخدم لحالات "الظروف الخاصة"
/// و"الدعم النفسي والاجتماعي" (نفس نموذج `HardshipStatus`).
class AdvisingStatusChip extends StatelessWidget {
  final HardshipStatus status;

  const AdvisingStatusChip({super.key, required this.status});

  Color get _color => switch (status) {
        HardshipStatus.newCase => DashTokens.danger,
        HardshipStatus.underReview => DashTokens.gold600,
        HardshipStatus.contactedStudent => DashTokens.gold600,
        HardshipStatus.contactedFamily => DashTokens.gold600,
        HardshipStatus.referred => DashTokens.gold600,
        HardshipStatus.improved => DashTokens.success,
        HardshipStatus.needsOngoingFollowUp => DashTokens.danger,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// بطاقة حالة موحَّدة (تُستخدم لكل من "الظروف الخاصة" و"الدعم النفسي
/// والاجتماعي" - نفس نموذج `HardshipCase`) بعرض محتوى محكوم بدل تمدّد بضعة
/// أسطر عبر كامل الشاشة.
class AdvisingCaseCard extends StatelessWidget {
  final HardshipCase hardshipCase;

  const AdvisingCaseCard({super.key, required this.hardshipCase});

  @override
  Widget build(BuildContext context) {
    final c = hardshipCase;
    // تركيبة أفقية (منطقة رئيسية + منطقة ثانوية جانبية) بدل التكديس الرأسي
    // الكامل السابق - على عرض الصفحة الكامل (~1400px) كانت البطاقة تترك
    // فراغًا أبيض كبيرًا يسار المحتوى النصي القصير نسبيًا (سليمان 2026-08-22:
    // "البطاقة عريضة جدًا مقارنة بكمية المعلومات، فراغ داخلي كبير غير مستغَل" -
    // بند 35). الحالة والإجراء الآن بعمود جانبي ثابت العرض يملأ يسار البطاقة
    // بدل ترك الفراغ، والزر بشكل خلفية مملوءة خفيفة ليبدو تفاعليًا بوضوح.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DashTokens.cardBg,
        border: Border.all(color: DashTokens.border),
        borderRadius: BorderRadius.circular(DashTokens.radiusLg),
        boxShadow: DashTokens.cardShadow,
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;

        final primary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.studentName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: DashTokens.textPrimary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MetaChip(icon: Icons.badge_outlined, label: c.universityId),
                _MetaChip(icon: Icons.apartment_outlined, label: c.department),
                _MetaChip(icon: Icons.groups_outlined, label: c.shatr),
              ],
            ),
            if (c.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(c.description, style: const TextStyle(fontSize: 12.5, color: DashTokens.textPrimary, height: 1.5)),
            ],
          ],
        );

        final secondary = Column(
          crossAxisAlignment: isNarrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            AdvisingStatusChip(status: c.status),
            const SizedBox(height: 10),
            Material(
              color: DashTokens.green900.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showAdvisingTimelineDialog(context, subjectName: c.studentName, history: c.history),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timeline_outlined, size: 15, color: DashTokens.green900),
                      SizedBox(width: 6),
                      Text('مسار المتابعة الكامل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DashTokens.green900)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        if (isNarrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [primary, const SizedBox(height: 12), secondary]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: primary),
            const SizedBox(width: 16),
            secondary,
          ],
        );
      }),
    );
  }
}

/// شارة معلومة صغيرة (أيقونة + نص) - تُستخدَم داخل [AdvisingCaseCard] لعرض
/// الرقم الجامعي/القسم/الشطر بشكل منظَّم بدل سطر نصي واحد مفصول بنقاط.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: DashTokens.pageBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: DashTokens.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: DashTokens.textMuted),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: DashTokens.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// شريحة مرشد موحَّدة الشكل (لجداول "توزيع فترات الإرشاد") - ارتفاع/نصف قطر
/// ثابتان بدل الاعتماد على `Chip` القياسي المتفاوت الحجم حسب طول الاسم.
class AdvisingAdvisorChip extends StatelessWidget {
  final String label;

  const AdvisingAdvisorChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: DashTokens.green900.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DashTokens.border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DashTokens.textPrimary)),
    );
  }
}

/// نافذة "مسار المتابعة" الموحَّدة - عرض جدول زمني حقيقي (نقاط متصلة بخط)
/// بدل قائمة نصية بسيطة، مع تمييز واضح لآخر حدث. تعرض فقط الحقول المتوفرة
/// فعليًا بنموذج `HardshipHistoryEntry` (الحالة/الملاحظات/مَن حدَّثها/متى) -
/// لا حقول جهة/دور لأنها غير مخزَّنة حاليًا بقاعدة البيانات.
Future<void> showAdvisingTimelineDialog(BuildContext context, {required String subjectName, required List<HardshipHistoryEntry> history}) {
  final events = history.reversed.toList();
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.timeline_outlined, size: 18, color: DashTokens.green900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('مسار المتابعة: $subjectName', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: DashTokens.textPrimary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: DashTokens.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: events.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('لا توجد أحداث مسجَّلة بعد.', style: TextStyle(color: DashTokens.textMuted)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < events.length; i++)
                            _TimelineEvent(entry: events[i], isLatest: i == 0, isLast: i == events.length - 1),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TimelineEvent extends StatelessWidget {
  final HardshipHistoryEntry entry;
  final bool isLatest;
  final bool isLast;

  const _TimelineEvent({required this.entry, required this.isLatest, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = isLatest ? DashTokens.green900 : DashTokens.textMuted;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: isLatest ? 14 : 10,
                height: isLatest ? 14 : 10,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: isLatest ? Border.all(color: DashTokens.gold600, width: 2) : null),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: DashTokens.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.status.label,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: isLatest ? DashTokens.textPrimary : DashTokens.textSecondary),
                  ),
                  if (entry.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(entry.notes, style: const TextStyle(fontSize: 12, color: DashTokens.textSecondary, height: 1.4)),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${entry.updatedBy} — ${_formatDate(entry.updatedAt)}',
                    style: const TextStyle(fontSize: 11, color: DashTokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} — ${two(d.hour)}:${two(d.minute)}';
  }
}
