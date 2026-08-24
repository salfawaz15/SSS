import 'package:flutter/material.dart';

import '../../../services/advising_overview_stats_service.dart';
import '../../theme/portal_theme.dart';
import '../../widgets/mobile_error_state.dart';
import '../../widgets/mobile_kpi_card.dart';
import '../../widgets/mobile_loading_state.dart';
import '../../widgets/portal_app_bar_logo.dart';
import 'home_data_controller.dart';

/// الشاشة الرئيسية لـ"بوابة الإرشاد" - جزآن فقط بنفس الهوية البصرية للموقع
/// حرفيًا، بلا أي إضافات (سليمان 2026-08-23): "مؤشرات رئيسية لحالات
/// الإرشاد" (القسم العلوي) و"إحصائيات طلبات الحذف والإضافة" (القسم السفلي) -
/// نفس تسميات وأرقام بطاقات الموقع بالضبط. القسمان يتوزَّعان بمسافات متساوية
/// عبر ارتفاع الشاشة كاملاً (`spaceEvenly` داخل `ConstrainedBox` بارتفاع
/// أدنى = ارتفاع الشاشة) بدل فراغ متروك أسفلها فقط (سليمان 2026-08-23).
class PortalHomeScreen extends StatefulWidget {
  const PortalHomeScreen({super.key});

  @override
  State<PortalHomeScreen> createState() => _PortalHomeScreenState();
}

class _PortalHomeScreenState extends State<PortalHomeScreen> {
  final _deleteAddStream = DeleteAddOverviewController.watch();
  late Future<AdvisingOverviewStats> _advisingFuture = AdvisingOverviewController.load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // الشعار الرسمي النظيف (خلفية مُفرَّغة فعليًا) - نفس شعار شاشة الدخول
        // بالضبط. `leading` يظهر على يمين الشاشة تلقائيًا مع اتجاه RTL
        // (سليمان 2026-08-23).
        leadingWidth: kPortalAppBarLeadingWidth,
        leading: const PortalAppBarLogo(),
        title: const Text(
          'وحدة الإرشاد الأكاديمي والخريجين',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _advisingFuture = AdvisingOverviewController.load()),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - AppSpacing.lg * 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAdvisingSection(),
                    _buildDeleteAddSection(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAdvisingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('مؤشرات رئيسية لحالات الإرشاد', style: AppTextStyles.h3()),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<AdvisingOverviewStats>(
          future: _advisingFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return MobileErrorState(onRetry: () => setState(() => _advisingFuture = AdvisingOverviewController.load()));
            }
            if (!snapshot.hasData) {
              return const MobileLoadingState();
            }
            final a = snapshot.data!;
            return _StatGrid(
              cards: [
                _StatCardData(
                  label: 'طلبة على غير مرشدهم',
                  value: '${a.wrongAdvisor}',
                  note: 'منهم ${a.wrongAdvisorWithDisability} من ذوي الإعاقة',
                  icon: Icons.sync_problem_outlined,
                  color: AppColors.gold,
                ),
                _StatCardData(
                  label: 'طلبة بلا مرشد',
                  value: '${a.withoutAdvisor}',
                  icon: Icons.person_off_outlined,
                  color: AppColors.errorRed,
                ),
                _StatCardData(
                  label: 'طلبة تابعين لمرشد – ذوي الإعاقة',
                  value: '${a.assignedWithDisability}',
                  icon: Icons.accessible_outlined,
                  color: AppColors.green,
                ),
                _StatCardData(
                  label: 'طلبة تابعين لمرشد',
                  value: '${a.assigned}',
                  icon: Icons.school_outlined,
                  color: AppColors.greenDark,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDeleteAddSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.bar_chart_outlined, size: 18, color: AppColors.greenDark),
            const SizedBox(width: AppSpacing.xs),
            Text('إحصائيات طلبات الحذف والإضافة', style: AppTextStyles.h3()),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        StreamBuilder<DeleteAddOverview>(
          stream: _deleteAddStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return MobileErrorState(onRetry: () => setState(() {}));
            }
            if (!snapshot.hasData) {
              return const MobileLoadingState();
            }
            final d = snapshot.data!;
            return _StatGrid(
              cards: [
                _StatCardData(
                  label: 'طلبات إضافة',
                  value: '${d.addCount}',
                  note: 'طلبًا',
                  icon: Icons.add_circle_outline,
                  color: AppColors.green,
                ),
                _StatCardData(
                  label: 'طلبات حذف',
                  value: '${d.deleteCount}',
                  note: 'طلبًا',
                  icon: Icons.remove_circle_outline,
                  color: AppColors.errorRed,
                ),
                _StatCardData(
                  label: 'طلبات تعديل',
                  value: '${d.editCount}',
                  note: 'طلبًا',
                  icon: Icons.sync_alt_outlined,
                  color: AppColors.gold,
                ),
                _StatCardData(
                  label: 'نسبة الإنجاز العامة',
                  value: '${d.completionPercent}%',
                  note: 'من إجمالي الطلبات',
                  icon: Icons.donut_small_outlined,
                  color: AppColors.green,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatCardData {
  final String label;
  final String value;
  final String? note;
  final IconData icon;
  final Color color;

  const _StatCardData({
    required this.label,
    required this.value,
    this.note,
    required this.icon,
    required this.color,
  });
}

/// شبكة إحصائيات بعمودين - نفس الهوية البصرية لبطاقات الموقع (أيقونة مربَّعة
/// ملوَّنة + رقم كبير + تسمية)، لكن بعمودين بدل صف أفقي واحد (4 بطاقات بصف
/// واحد لا تصلح لعرض جوال ضيق - القسم 30 من المواصفات: لا تمرير أفقي).
class _StatGrid extends StatelessWidget {
  final List<_StatCardData> cards;
  const _StatGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.5,
      ),
      itemBuilder: (context, i) {
        final c = cards[i];
        return MobileKpiCard(
          label: c.label,
          value: c.value,
          note: c.note,
          icon: c.icon,
          accentColor: c.color,
        );
      },
    );
  }
}
