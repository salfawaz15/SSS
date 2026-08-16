import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/unit_committee_member.dart';
import '../services/unit_committee_repository.dart';
import '../theme/app_theme.dart';
import '../utils/name_display.dart';
import 'change_password_dialog.dart';
import 'mobile_account_screen.dart';
import 'mobile_bottom_nav_bar.dart';
import 'portal_cards.dart';
import 'portal_role_gate.dart';

/// أسماء الأقسام الخمسة بترتيبها المعتمَد - لفرز جدول منسّقي الأقسام
/// بالهيكل التنظيمي (نفس الترتيب المستخدَم بالصفحة العامة بالموقع).
const _memberDeptOrder = <String>[
  'الإدارة',
  'المحاسبة',
  'التسويق',
  'الاقتصاد والتمويل',
  'نظم المعلومات الإدارية',
];

int _deptIndex(String department) {
  final i = _memberDeptOrder.indexOf(department);
  return i == -1 ? _memberDeptOrder.length : i;
}

const String _kIntroText =
    'نظراً لأهمية الدور الذي تؤديه كلية إدارة الأعمال بجامعة الطائف في خدمة '
    'النهضة التعليمية والمساهمة بتحقيق أهداف الرؤية 2030 والأهداف الاستراتيجية '
    'للجامعة، من خلال العمل على الارتقاء بكفاءة طلابها وتميز مخرجاتها التعليمية '
    'لتلبية احتياجات سوق العمل، فقد أنشأت عدداً من الوحدات المساندة تحت مظلة '
    'الكلية حتى يتم تنظيم وتنسيق أدوارها المختلفة على أكمل وجه. وفي ضوء ذلك تم '
    'إنشاء وحدة الإرشاد الأكاديمي والخريجين وإعادة تشكيلها بموجب القرار الصادر '
    'عن سعادة عميد الكلية رقم (59304/39) بتاريخ 28/11/1445هـ.\n\n'
    'وتسعى هذه الوحدة إلى تحقيق التميز وتلبية احتياج الطلاب في مجالات الإرشاد '
    'الأكاديمي المتنوعة على أكمل وجه لضمان نجاح مسيرتهم التعليمية بشكل يساهم '
    'في دعم وتعزيز منظومة الإرشاد الأكاديمي في الجامعة.';

const String _kVisionText =
    'التميز في تقديم خدمات إرشادية متنوعة للطالب بما يتوافق مع احتياجاته '
    'الأكاديمية والنفسية والاجتماعية والمهنية عبر الوسائل التقليدية والرقمية '
    'ووفقاً لأفضل الممارسات العالمية.';

const String _kMissionText =
    'إرشاد ودعم الطالب أكاديمياً ونفسياً واجتماعياً ومهنياً، وتقديم خدمات '
    'رعاية ودعم المتفوقين والموهوبين، وكذلك الطلبة من أصحاب الهمم، وإقامة '
    'علاقة مستدامة مع الخريجين.';

/// الصفحة الرئيسية الجوّالة **العامة** - أول ما يُفتح به التطبيق دائمًا، بلا
/// أي بوابة دخول (بطلب سليمان الصريح 2026-08-16: "طبيعي عندما أدخل الموقع
/// يفتح على الصفحة الرئيسية، كذلك التطبيق - بعدها لي الخيار أن أبقى بالصفحة
/// الرئيسية أو أذهب لتسجيل الدخول"). محتوى "عن الوحدة" من الصفحة العامة
/// بالموقع (`public_landing_screen.dart`) مُضمَّن هنا **كتبويب داخل نفس
/// الصفحة** (`TabBar`/`TabBarView`) لا صفحة منفصلة.
///
/// أيقونة الحساب أعلى يمين الصفحة تفتح [MobileAccountScreen] (شاشة الدخول
/// إن لم تكن هناك جلسة، أو بطاقة الحساب إن كانت هناك جلسة محفوظة) - الجلسة
/// تبقى محفوظة طبيعيًا بين مرات فتح التطبيق، لكن **هذه الصفحة العامة تبقى
/// دائمًا أول ما يظهر**، لا انتقال تلقائي لأي لوحة بعد الدخول.
///
/// بعد أن كشف اختبار سليمان الحي أن دفع شاشات الموقع العريضة
/// (`AdminWorkspaceScreen`, `CoordinatorWorkspaceScreen`...) مباشرة على
/// الجوال ينتج صفحات مكسورة - القرار: التوقف عن الاعتماد عليها كليًا
/// بالجوال. تبويبا "إدارة الطلبات"/"التقارير" بالشريط السفلي معطَّلان مؤقتًا
/// (رسالة "قيد التطوير") لنفس السبب.
class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 8, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showComingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label - قيد التطوير، قريبًا بإذن الله')),
    );
  }

  /// عناصر الشريط السفلي حسب دور الحساب الحالي - "الرئيسية" أولًا دائمًا
  /// (نفس هذه الصفحة، بلا تنقّل)، ثم أهم أقسام بوابة هذا الدور تحديدًا على
  /// الويب (ترتيب/تسمية مطابقان لـ`admin_nav.dart`/`coordinator_nav.dart`) -
  /// بطلب سليمان الصريح (2026-08-16): "إظهار كل صفحة حسب دورها وأهميتها
  /// بالتبويب السفلي" بدل التبويبات العامة الثابتة السابقة. محتوى كل قسم
  /// (غير "الرئيسية") لا يزال "قيد التطوير" - سيُبنى جوّالًا أصيلاً واحدًا
  /// تلو الآخر بجلسات قادمة (لا دفع شاشات الويب العريضة كما ثبت فشله سابقًا).
  /// أقسام الدور (بلا "الرئيسية") مرتَّبة حسب الأهمية - أول عنصرين فقط
  /// يظهران كتبويب مباشر، والباقي (إن وجد) ينتقل لقائمة "المزيد" - بطلب
  /// سليمان صراحةً (2026-08-16): "أربع اختيارات كما هي، على أن يكون الخيار
  /// الأخير المزيد ويفتح قائمة نختار منها" (بدل تكديس كل الأقسام كتبويبات
  /// مباشرة، كما كان مع دور الإدارة - 3 تبويبات + الرئيسية = 4 بلا مساحة
  /// لأي قسم إضافي مستقبلي).
  List<(IconData, String)> _roleSections(PortalRole? role) => switch (role) {
        PortalRole.superAdmin || PortalRole.admin => const [
            (Icons.dashboard_outlined, 'لوحة الإدارة'),
            (Icons.assessment_outlined, 'تقارير'),
            (Icons.fact_check_outlined, 'لوحة الإرشاد'),
          ],
        PortalRole.ameen => const [(Icons.assessment_outlined, 'تقارير')],
        PortalRole.unitCoordinator => const [(Icons.upload_file_outlined, 'رفع الملفات')],
        PortalRole.collegeCoordinator || PortalRole.deptCoordinator => const [
            (Icons.fact_check_outlined, 'متابعة الطلبات'),
            (Icons.insights_outlined, 'متابعة الإنجاز'),
          ],
        PortalRole.trackCoordinator => const [(Icons.route_outlined, 'حالات المسار')],
        PortalRole.unknown || null => const [],
      };

  void _openMoreSheet(BuildContext context, List<(IconData, String)> items) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 6),
            for (final item in items)
              ListTile(
                leading: Icon(item.$1, color: AppColors.greenDark),
                title: Text(item.$2),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showComingSoon(context, item.$2);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  MobileBottomNavBar _bottomNavForRole(BuildContext context, PortalRole? role) {
    // كان بلا أثر (onTap فارغ) - يفترض أن المستخدم بصفحة "الرئيسية" أصلًا
    // فلا حاجة لفعل شيء، لكن هذا خطأ حين يكون مفتوحًا بتبويب علوي آخر (مثال
    // "الأهداف") - الآن يُعيد تبويبات الصفحة العلوية لـ"الرئيسية" فعليًا
    // (سليمان لاحظه صراحةً 2026-08-16 بلقطة شاشة من تبويب "الأهداف").
    final home = MobileNavTab(
      icon: Icons.home_outlined,
      label: 'الرئيسية',
      onTap: () => _tabController.animateTo(0),
    );

    final sections = _roleSections(role);
    final direct = sections.take(2);
    final overflow = sections.skip(2).toList();

    return MobileBottomNavBar(
      currentIndex: 0,
      tabs: [
        home,
        for (final s in direct) MobileNavTab(icon: s.$1, label: s.$2, onTap: () => _showComingSoon(context, s.$2)),
      ],
      onMore: overflow.isEmpty ? null : () => _openMoreSheet(context, overflow),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'جامعة الطائف - كلية إدارة الأعمال',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.greenDark),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'وحدة الإرشاد الأكاديمي والخريجين',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      StreamBuilder<User?>(
                        stream: FirebaseAuth.instance.authStateChanges(),
                        builder: (context, snapshot) {
                          final loggedIn = snapshot.data != null;
                          // مسجَّل الدخول: قائمة منبثقة سريعة (تغيير كلمة
                          // المرور/خروج) بدل فتح صفحة كاملة منفصلة - سليمان
                          // لاحظ صراحةً (2026-08-16) أن فتح صفحة جديدة لمجرد
                          // هذين الإجراءين مزعج مقارنة بباقي التصميم الممتاز.
                          // غير مسجَّل: يبقى الدفع لصفحة الدخول كما هي (إجراء
                          // متعدد الحقول يستحق صفحة كاملة).
                          if (loggedIn) {
                            return PopupMenuButton<VoidCallback>(
                              tooltip: 'حسابي',
                              icon: const Icon(Icons.account_circle, color: AppColors.greenDark),
                              onSelected: (action) => action(),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: () => showChangePasswordDialog(context),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.lock_outline, size: 18, color: AppColors.greenDark),
                                      SizedBox(width: 10),
                                      Text('تغيير كلمة المرور'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: () => FirebaseAuth.instance.signOut(),
                                  child: Row(
                                    children: [
                                      Icon(Icons.logout, size: 18, color: Colors.red.shade700),
                                      const SizedBox(width: 10),
                                      Text('تسجيل خروج', style: TextStyle(color: Colors.red.shade700)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                          return IconButton(
                            tooltip: 'تسجيل الدخول',
                            icon: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.greenDark),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const MobileAccountScreen()),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.greenDark, AppColors.green],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      children: [
                        Text('👋', style: TextStyle(fontSize: 26)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'أهلاً بك',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'نتمنى لك يومًا موفقًا',
                                style: TextStyle(color: Colors.white70, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: AppColors.greenDark,
                unselectedLabelColor: Colors.grey.shade500,
                indicatorColor: AppColors.gold,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'الرئيسية'),
                  Tab(text: 'نبذة'),
                  Tab(text: 'الرؤية والرسالة'),
                  Tab(text: 'الأهداف'),
                  Tab(text: 'الهيكل التنظيمي'),
                  Tab(text: 'أعضاء الوحدة'),
                  Tab(text: 'مواقع مهمة'),
                  Tab(text: 'التواصل'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const _StatsTabBody(),
                  _TextTabBody(paragraphs: [_kIntroText]),
                  _TextTabBody(paragraphs: [_kVisionText], heading: 'الرؤية'),
                  _GoalsTabBody(),
                  _OrgChartTabBody(),
                  _CommitteeTabBody(),
                  _ImportantLinksTabBody(),
                  _ContactTabBody(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          return FutureBuilder<PortalResolvedRole?>(
            // key بمعرِّف المستخدم يجبر إعادة الحساب عند تبدّل الدخول/الخروج
            // بدل الاحتفاظ بنتيجة Future الحساب السابق.
            key: ValueKey(authSnapshot.data?.uid),
            future: PortalRoleGate.resolveSimple(authSnapshot.data),
            builder: (context, roleSnapshot) => _bottomNavForRole(context, roleSnapshot.data?.role),
          );
        },
      ),
    );
  }
}

class _StatsTabBody extends StatelessWidget {
  const _StatsTabBody();

  static String _displayValue(int? value, {bool isPercent = false}) {
    if (value == null || value == 0) return 'قيد الرصد التلقائي';
    return isPercent ? '$value%' : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('public_stats').doc('summary').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final stats = <({IconData icon, String label, String value, Color color})>[
          (
            icon: Icons.assignment_turned_in_outlined,
            label: 'عدد الطلبات المُنجزة',
            value: _displayValue(data?['completed_requests'] as int?),
            color: AppColors.greenDark,
          ),
          (
            icon: Icons.groups_outlined,
            label: 'عدد الطلاب المستفيدين',
            value: _displayValue(data?['students_served'] as int?),
            color: AppColors.gold,
          ),
          (
            icon: Icons.support_agent_outlined,
            label: 'عدد المرشدين الأكاديميين',
            value: _displayValue(data?['advisors_count'] as int?),
            color: AppColors.green,
          ),
          (
            icon: Icons.trending_up,
            label: 'نسبة الإنجاز',
            value: _displayValue(data?['completion_rate'] as int?, isPercent: true),
            color: AppColors.goldLight,
          ),
        ];

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('إحصائيات هامة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.greenDark)),
            const SizedBox(height: 4),
            Text('تُحدَّث تلقائيًا كلما أنجز المنسّقون طلبات جديدة', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 16),
            for (final s in stats) ...[
              PortalStatCard(icon: s.icon, value: s.value, label: s.label, accentColor: s.color),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _OrgChartTabBody extends StatelessWidget {
  const _OrgChartTabBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<List<UnitCommitteeMember>>(
        stream: UnitCommitteeRepository.watch(),
        builder: (context, snapshot) {
          final members = snapshot.data ?? const <UnitCommitteeMember>[];
          if (snapshot.connectionState == ConnectionState.waiting && members.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
          }
          if (members.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لم يُعتمَد الهيكل التنظيمي بعد.', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          UnitCommitteeMember? firstMatch(bool Function(UnitCommitteeMember) test) {
            for (final m in members) {
              if (test(m)) return m;
            }
            return null;
          }

          final head = firstMatch((m) => m.role.contains('رئيس') && !m.role.contains('نائب'));
          final deputy = firstMatch((m) => m.role.contains('نائب'));
          final unitSecretaryGeneral = firstMatch((m) => m.role.contains('أمين الوحدة'));
          final unitCoordinator = firstMatch((m) => m.role.contains('منسّق الوحدة') || m.role.contains('منسق الوحدة'));
          final unitSecretary = firstMatch((m) => m.role.contains('سكرتير الوحدة'));

          final collegeCoords = members.where((m) => m.role.contains('الكلية')).toList();
          final trackCoords = members.where((m) => m.role.contains('مسار')).toList();
          final deptCoords = members.where((m) => m.role.contains('قسم')).toList()
            ..sort((a, b) => _deptIndex(a.department) - _deptIndex(b.department));
          final depts = deptCoords.map((m) => m.department).toSet().toList()
            ..sort((a, b) => _deptIndex(a) - _deptIndex(b));

          return ListView(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (head != null) Expanded(child: _OrgLeaderCard(member: head)),
                  if (head != null && deputy != null) const SizedBox(width: 10),
                  if (deputy != null) Expanded(child: _OrgLeaderCard(member: deputy)),
                ],
              ),
              const SizedBox(height: 4),
              Container(height: 2, color: AppColors.gold),
              const SizedBox(height: 16),
              _OrgClusterCard(
                icon: Icons.explore_outlined,
                title: 'منسّقو المسارات النوعية',
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: trackCoords
                      .map((m) => _OrgMemberChip(
                            role: m.role.replaceFirst(RegExp('^منسّ?ق مسار '), ''),
                            name: displayName(m.name),
                            width: 140,
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              _OrgClusterCard(
                icon: Icons.groups_outlined,
                title: 'القيادة الإدارية للوحدة',
                child: Column(
                  children: [
                    if (unitSecretaryGeneral != null)
                      _OrgMemberChip(role: 'أمين الوحدة', name: displayName(unitSecretaryGeneral.name), accent: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (unitCoordinator != null)
                          Expanded(child: _OrgMemberChip(role: 'منسّق الوحدة', name: displayName(unitCoordinator.name))),
                        if (unitCoordinator != null && unitSecretary != null) const SizedBox(width: 8),
                        if (unitSecretary != null)
                          Expanded(child: _OrgMemberChip(role: 'سكرتير الوحدة', name: displayName(unitSecretary.name))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _OrgClusterCard(
                icon: Icons.school_outlined,
                title: 'منسّقو الكلية للشؤون الأكاديمية',
                child: Row(
                  children: collegeCoords
                      .map((m) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _OrgMemberChip(
                                role: m.role.contains('منسقة') ? 'شطر الطالبات' : 'شطر الطلاب',
                                name: displayName(m.name),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              _OrgClusterCard(
                icon: Icons.grid_view_outlined,
                title: 'منسّقو الأقسام العلمية',
                child: _OrgDeptTable(depts: depts, deptCoords: deptCoords),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrgLeaderCard extends StatelessWidget {
  const _OrgLeaderCard({required this.member});

  final UnitCommitteeMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(member.role, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 3),
          Text(displayName(member.name), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w600, fontSize: 11)),
        ],
      ),
    );
  }
}

class _OrgClusterCard extends StatelessWidget {
  const _OrgClusterCard({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.greenDark, AppColors.green])),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: AppColors.goldLight),
                const SizedBox(width: 6),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }
}

class _OrgMemberChip extends StatelessWidget {
  const _OrgMemberChip({required this.role, required this.name, this.width, this.accent = false});

  final String role;
  final String name;
  final double? width;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent ? AppColors.gold : Colors.grey.shade300, width: accent ? 1.4 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(role, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.green)),
          const SizedBox(height: 3),
          Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _OrgDeptTable extends StatelessWidget {
  const _OrgDeptTable({required this.depts, required this.deptCoords});

  final List<String> depts;
  final List<UnitCommitteeMember> deptCoords;

  @override
  Widget build(BuildContext context) {
    UnitCommitteeMember? byShatr(String dept, bool female) => deptCoords.cast<UnitCommitteeMember?>().firstWhere(
          (m) => m!.department == dept && m.role.contains('الطالبات') == female,
          orElse: () => null,
        );

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6)),
      columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFE7EFEA)),
          children: [
            const SizedBox(),
            _OrgDeptCell('شطر الطلاب', bold: true),
            _OrgDeptCell('شطر الطالبات', bold: true),
          ],
        ),
        for (final dept in depts)
          TableRow(children: [
            _OrgDeptCell(dept, bold: true, small: true),
            _OrgDeptCell(displayName(byShatr(dept, false)?.name ?? '—')),
            _OrgDeptCell(displayName(byShatr(dept, true)?.name ?? '—')),
          ]),
      ],
    );
  }
}

class _OrgDeptCell extends StatelessWidget {
  const _OrgDeptCell(this.text, {this.bold = false, this.small = false});

  final String text;
  final bool bold;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: small ? 10.5 : 11.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
    );
  }
}

class _TextTabBody extends StatelessWidget {
  const _TextTabBody({required this.paragraphs, this.heading});

  final List<String> paragraphs;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (heading != null) ...[
          Text(heading!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark)),
          const SizedBox(height: 8),
        ],
        for (final p in paragraphs) ...[
          Text(p, style: const TextStyle(fontSize: 13.5, height: 1.8, color: Color(0xFF3A3A3A))),
          const SizedBox(height: 16),
        ],
        if (heading == 'الرؤية') ...[
          const Text('الرسالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark)),
          const SizedBox(height: 8),
          const Text(_kMissionText, style: TextStyle(fontSize: 13.5, height: 1.8, color: Color(0xFF3A3A3A))),
        ],
      ],
    );
  }
}

class _GoalsTabBody extends StatelessWidget {
  const _GoalsTabBody();

  static const _categories = <(String, List<String>)>[
    ('أولاً: الإرشاد الأكاديمي', [
      'توعية الطلبة بمسئولياتهم الأكاديمية والعلمية وتعريفهم باللوائح المنظمة للشؤون الدراسية.',
      'تقديم الدعم الإرشادي بما يدعم إنهاء متطلبات الخطة الدراسية بالفترة المحددة.',
      'متابعة أداء الطلبة وتقديم الدعم للمتعثرين دراسيًا.',
    ]),
    ('ثانياً: الإرشاد النفسي والاجتماعي', [
      'مساعدة الطلبة في اكتشاف ذاتهم وتحفيزهم أكاديميًا ونفسيًا وسلوكيًا.',
      'إيجاد الحلول للمشاكل المرتبطة بقدرات الطالب الشخصية والاجتماعية.',
    ]),
    ('ثالثاً: الإرشاد المهني والخريجين', [
      'تعريف الطلاب بالمسارات المهنية المناسبة لتخصصاتهم.',
      'متابعة الخريجين وبناء علاقة مستدامة معهم.',
    ]),
    ('رابعاً: إرشاد ذوي الاحتياجات الخاصة', [
      'إدارة العلاقة والاتصال مع الطلبة ذوي الإعاقة لتقديم الدعم اللازم لهم.',
    ]),
    ('خامساً: إرشاد المتفوقين والموهوبين', [
      'اكتشاف ودعم الطلاب الموهوبين وتحفيز المتفوقين علميًا.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final cat in _categories) ...[
          Text(cat.$1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.greenDark)),
          const SizedBox(height: 8),
          for (final point in cat.$2)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.circle, size: 6, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(child: Text(point, style: const TextStyle(fontSize: 13, height: 1.6))),
                ],
              ),
            ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _CommitteeTabBody extends StatelessWidget {
  const _CommitteeTabBody();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UnitCommitteeMember>>(
      stream: UnitCommitteeRepository.watch(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('تعذّر تحميل بيانات الوحدة: ${snapshot.error}', textAlign: TextAlign.center),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final members = snapshot.data!;
        if (members.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('لم يُعتمَد تشكيل الوحدة بعد.', style: TextStyle(color: Colors.grey)),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: members.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final m = members[i];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFE7EFEA),
                    child: Icon(Icons.person_outline, color: AppColors.greenDark),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName(m.name), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 3),
                        Text(m.role, style: TextStyle(color: AppColors.green, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        if (m.department.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(m.department, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                  if (m.email.isNotEmpty)
                    IconButton(
                      tooltip: 'مراسلة بالبريد',
                      icon: const Icon(Icons.mail_outline, color: AppColors.gold, size: 20),
                      onPressed: () => launchUrl(Uri.parse('mailto:${m.email}')),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ImportantLink {
  const _ImportantLink(this.label, this.url, this.icon);

  final String label;
  final String url;
  final IconData icon;
}

const _kImportantLinks = <_ImportantLink>[
  _ImportantLink('جامعة الطائف', 'https://www.tu.edu.sa/', Icons.account_balance_outlined),
  _ImportantLink(
    'كلية إدارة الأعمال',
    'https://www.tu.edu.sa/Ar/%D8%A7%D9%84%D9%83%D9%84%D9%8A%D8%A7%D8%AA/98/%D9%83%D9%84%D9%8A%D8%A9-%D8%A5%D8%AF%D8%A7%D8%B1%D8%A9-%D8%A7%D9%84%D8%A7%D8%B9%D9%85%D8%A7%D9%84',
    Icons.apartment_outlined,
  ),
  _ImportantLink(
    'وحدة الإرشاد على موقع الكلية',
    'https://www.tu.edu.sa/Ar/%D9%83%D9%84%D9%8A%D8%A9-%D8%A5%D8%AF%D8%A7%D8%B1%D8%A9-%D8%A7%D9%84%D8%A7%D8%B9%D9%85%D8%A7%D9%84/98/Pages/22234/%D9%88%D8%AD%D8%AF%D8%A9-%D8%A7%D9%84%D8%A5%D8%B1%D8%B4%D8%A7%D8%AF-%D8%A7%D9%84%D8%A3%D9%83%D8%A7%D8%AF%D9%8A%D9%85%D9%8A-%D9%88%D8%A7%D9%84%D8%AE%D8%B1%D9%8A%D8%AC%D9%8A%D9%86',
    Icons.groups_outlined,
  ),
  _ImportantLink('المنظومة الخارجية', 'https://edugate.tu.edu.sa/tu/init', Icons.public_outlined),
  _ImportantLink('المنظومة الداخلية', 'http://ereg.tu.edu.sa:7778/forms/frmservlet?config=sis', Icons.dns_outlined),
  _ImportantLink('منصة بلاك بورد', 'https://lms.tu.edu.sa/', Icons.laptop_outlined),
];

class _ImportantLinksTabBody extends StatelessWidget {
  const _ImportantLinksTabBody();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(20),
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.05,
      children: [
        for (final link in _kImportantLinks)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                boxShadow: [BoxShadow(color: AppColors.greenDark.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.greenDark, AppColors.green], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(link.icon, color: AppColors.goldLight, size: 20),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    link.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.greenDark, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ContactTabBody extends StatelessWidget {
  const _ContactTabBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ContactTile(
          icon: Icons.email_outlined,
          label: 'البريد الرسمي للوحدة',
          value: 'cba.ag@tu.edu.sa',
          onTap: () => launchUrl(Uri.parse('mailto:cba.ag@tu.edu.sa')),
        ),
        const SizedBox(height: 12),
        _ContactTile(
          icon: Icons.build_outlined,
          label: 'الدعم الفني للموقع',
          value: 'salfawaz@tu.edu.sa',
          onTap: () => launchUrl(Uri.parse('mailto:salfawaz@tu.edu.sa')),
        ),
        const SizedBox(height: 12),
        const _ContactTile(
          icon: Icons.location_on_outlined,
          label: 'الموقع',
          value: 'كلية إدارة الأعمال - جامعة الطائف',
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.label, required this.value, this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              Icon(icon, color: AppColors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
