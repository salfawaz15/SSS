import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/unit_committee_member.dart';
import '../services/unit_committee_repository.dart';
import '../theme/app_theme.dart';
import '../utils/name_display.dart';
import 'mobile_account_screen.dart';
import 'mobile_bottom_nav_bar.dart';

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
  late final _tabController = TabController(length: 5, vsync: this);

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
                        child: Text(
                          'وحدة الإرشاد الأكاديمي والخريجين',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.greenDark),
                        ),
                      ),
                      StreamBuilder<User?>(
                        stream: FirebaseAuth.instance.authStateChanges(),
                        builder: (context, snapshot) {
                          final loggedIn = snapshot.data != null;
                          return IconButton(
                            tooltip: loggedIn ? 'حسابي' : 'تسجيل الدخول',
                            icon: Icon(
                              loggedIn ? Icons.account_circle : Icons.login,
                              color: AppColors.greenDark,
                            ),
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
                                'كلية إدارة الأعمال - جامعة الطائف',
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
                  Tab(text: 'نبذة'),
                  Tab(text: 'الرؤية والرسالة'),
                  Tab(text: 'الأهداف'),
                  Tab(text: 'أعضاء الوحدة'),
                  Tab(text: 'التواصل'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _TextTabBody(paragraphs: [_kIntroText]),
                  _TextTabBody(paragraphs: [_kVisionText], heading: 'الرؤية'),
                  _GoalsTabBody(),
                  _CommitteeTabBody(),
                  _ContactTabBody(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MobileBottomNavBar(
        currentIndex: 0,
        tabs: [
          MobileNavTab(icon: Icons.home_outlined, label: 'الرئيسية', onTap: () {}),
          MobileNavTab(
            icon: Icons.fact_check_outlined,
            label: 'إدارة الطلبات',
            onTap: () => _showComingSoon(context, 'إدارة الطلبات'),
          ),
          MobileNavTab(
            icon: Icons.assessment_outlined,
            label: 'التقارير',
            onTap: () => _showComingSoon(context, 'التقارير'),
          ),
        ],
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

class _ContactTabBody extends StatelessWidget {
  const _ContactTabBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ContactTile(
          icon: Icons.email_outlined,
          label: 'البريد الرسمي',
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
