import 'package:flutter/material.dart';

import '../services/advising_case_analyzer.dart';
import '../services/course_schedule_repository.dart' show Shatr;
import '../theme/app_theme.dart';
import 'coordinator_nav.dart';
import 'portal_header.dart';

/// صفحة "الإرشاد" لمنسّق القسم - نفس فكرة "متابعة حالات الإرشاد" بلوحة
/// الإدارة (`AdvisingCasesAdminScreen`) لكن مقصورة على قسم/شطر هذا المنسّق
/// فقط (بطلب سليمان 2026-08-09): طلاب القسم بلا مرشد، طلاب القسم بمرشد من
/// خارج القسم، ونطاقات المعدل. تُصفَّى قائمة الطلاب بالقسم **قبل** التحليل
/// (نفس أسلوب فلتر القسم بشاشة الإدارة) حتى تصير كل الإحصائيات مقصورة على
/// القسم تلقائيًا بلا حساب إضافي.
class CoordinatorAdvisingScreen extends StatefulWidget {
  final String shatr;
  final String department;

  const CoordinatorAdvisingScreen({super.key, required this.shatr, required this.department});

  @override
  State<CoordinatorAdvisingScreen> createState() => _CoordinatorAdvisingScreenState();
}

class _CoordinatorAdvisingScreenState extends State<CoordinatorAdvisingScreen> {
  // بانتظار ملف "بيانات الطلبة الأكاديمية" الشامل الجديد (سيوفّره سليمان
  // قريبًا) - الصفحة تعرض "تحت التطوير" فقط حتى يصدر أمر صريح بتفعيلها،
  // لأن البيانات الحالية غير مكتملة (سليمان 2026-08-09). التفعيل: اجعل هذا
  // الثابت true.
  static const bool _enabled = false;

  bool _loading = true;
  String? _error;
  AdvisingCaseAnalysis? _analysis;

  @override
  void initState() {
    super.initState();
    if (_enabled) _load();
  }

  /// نفس مصدر [AdvisingCasesAdminScreen] الحالي (تقرير "كل الكليات" + ذوو
  /// الإعاقة) عبر [AdvisingCaseAnalyzer.loadCollegeScopedStudents] المشترك،
  /// مع فلترة القسم/الشطر قبل التحليل - نفس أسلوب فلتر القسم بشاشة الإدارة.
  Future<void> _load() async {
    try {
      final shatr = widget.shatr == 'شطر الطلاب' ? Shatr.male : Shatr.female;
      final loaded = await AdvisingCaseAnalyzer.loadCollegeScopedStudents();
      if (!mounted) return;

      final shatrStudents = shatr == Shatr.male ? loaded.male : loaded.female;
      final deptStudents = shatrStudents.where((s) => s.department == widget.department).toList();

      final analysis = AdvisingCaseAnalyzer.analyze(students: deptStudents, facultyByNameKey: loaded.facultyByKey);

      setState(() {
        _analysis = analysis;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل بيانات الإرشاد: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScaffold(
      title: 'الإرشاد - ${widget.department} (${widget.shatr})',
      showBackButton: true,
      navItems: buildCoordinatorNavItems(
        context,
        current: 'advising',
        shatr: widget.shatr,
        department: widget.department,
      ),
      body: !_enabled
          ? const Center(
              child: Text('الصفحة تحت التطوير', style: TextStyle(fontSize: 18, color: Colors.grey)),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    final analysis = _analysis!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _statCard(
                  icon: Icons.person_search_outlined,
                  value: '${analysis.studentsWithoutAdvisor.length}',
                  label: 'طلاب بلا مرشد',
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  icon: Icons.compare_arrows_outlined,
                  value: '${analysis.studentsWithWrongDeptAdvisor.length}',
                  label: 'مرشدهم من خارج القسم',
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (analysis.studentsWithoutAdvisor.isNotEmpty) ...[
          const Text('طلاب بلا مرشد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final s in analysis.studentsWithoutAdvisor)
                  ListTile(
                    title: Text(s.studentName),
                    subtitle: Text(s.studentId),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (analysis.studentsWithWrongDeptAdvisor.isNotEmpty) ...[
          const Text('طلاب مرشدهم من خارج القسم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final m in analysis.studentsWithWrongDeptAdvisor)
                  ListTile(
                    title: Text(m.student.studentName),
                    subtitle: Text('${m.student.studentId} - المرشد: ${m.advisor?.name ?? m.student.advisorNameRaw}'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _statCard({required IconData icon, required String value, required String label, required Color color}) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
