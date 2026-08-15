import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/mailto.dart';
import '../utils/name_display.dart';

import '../models/unit_committee_member.dart';
import '../services/app_update_service.dart';
import '../services/unit_committee_repository.dart';
import '../services/unit_guide_pdf_service.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import 'portal_cards.dart';
import 'portal_root.dart';

class _ExternalLink {
  final String label;
  final String url;
  final IconData icon;

  const _ExternalLink(this.label, this.url, this.icon);
}

/// ترتيب منطقي واحد (بدل تقسيم فئات): الجامعة، ثم الكلية، ثم الوحدة، ثم
/// المنظومة الخارجية، ثم الداخلية، ثم بلاك بورد.
const _allLinks = <_ExternalLink>[
  _ExternalLink('جامعة الطائف', 'https://www.tu.edu.sa/', Icons.account_balance_outlined),
  _ExternalLink(
    'كلية إدارة الأعمال',
    'https://www.tu.edu.sa/Ar/%D8%A7%D9%84%D9%83%D9%84%D9%8A%D8%A7%D8%AA/98/%D9%83%D9%84%D9%8A%D8%A9-%D8%A5%D8%AF%D8%A7%D8%B1%D8%A9-%D8%A7%D9%84%D8%A7%D8%B9%D9%85%D8%A7%D9%84',
    Icons.apartment_outlined,
  ),
  _ExternalLink(
    'وحدة الإرشاد على موقع الكلية',
    'https://www.tu.edu.sa/Ar/%D9%83%D9%84%D9%8A%D8%A9-%D8%A5%D8%AF%D8%A7%D8%B1%D8%A9-%D8%A7%D9%84%D8%A7%D8%B9%D9%85%D8%A7%D9%84/98/Pages/22234/%D9%88%D8%AD%D8%AF%D8%A9-%D8%A7%D9%84%D8%A5%D8%B1%D8%B4%D8%A7%D8%AF-%D8%A7%D9%84%D8%A3%D9%83%D8%A7%D8%AF%D9%8A%D9%85%D9%8A-%D9%88%D8%A7%D9%84%D8%AE%D8%B1%D9%8A%D8%AC%D9%8A%D9%86',
    Icons.groups_outlined,
  ),
  _ExternalLink(
    'المنظومة الخارجية',
    'https://edugate.tu.edu.sa/tu/init',
    Icons.public_outlined,
  ),
  _ExternalLink(
    'المنظومة الداخلية',
    'http://ereg.tu.edu.sa:7778/forms/frmservlet?config=sis',
    Icons.dns_outlined,
  ),
  _ExternalLink(
    'منصة بلاك بورد',
    'https://lms.tu.edu.sa/',
    Icons.laptop_outlined,
  ),
];

// ترتيب هرمي ثابت لبطاقات صفحة "تواصل معنا" (رئيس، نائب، أمين، منسّق
// الوحدة، سكرتير) - "نائب" يُفحَص قبل "رئيس" لأن "نائب رئيس الوحدة" يحتوي
// الكلمتين معًا، بصرف النظر عن الصياغة الدقيقة (رئيس/رئيسة، أمين/أمينة...).
const _unitLeaderKeywordOrder = <String, int>{
  'نائب': 1,
  'رئيس': 0,
  'أمين': 2,
  'منسّق': 3,
  'منسق': 3,
  'سكرتير': 4,
};

int _unitLeaderOrder(String role) {
  for (final entry in _unitLeaderKeywordOrder.entries) {
    if (role.contains(entry.key)) return entry.value;
  }
  return _unitLeaderKeywordOrder.length;
}

// ترتيب الأقسام الرسمي المعتمد في كل أعمال الوحدة (نفس ترتيب نموذج الحذف
// والإضافة، ونفس الصياغة الحرفية لعمود "القسم العلمي" بورقة "تشكيل الوحدة"):
// الإدارة، المحاسبة، التسويق، الاقتصاد والتمويل، نظم المعلومات الإدارية.
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

class _GoalCategory {
  final String title;
  final List<String> points;

  const _GoalCategory(this.title, this.points);
}

const _goalCategories = <_GoalCategory>[
  _GoalCategory('أولاً: الإرشاد الأكاديمي', [
    'توعية الطلبة بمسئولياتهم الأكاديمية والعلمية وتعريفهم بأهم اللوائح المنظمة للشؤون الدراسية واللوائح والأنظمة المتبعة داخل الحرم الجامعي، وكل ما يتعلق بمسيرتهم التعليمية في الجامعة بما في ذلك التعريف ببرامج الكلية وهيكلها التنظيمي وعلاقات الاتصال، وقنوات التواصل المتاحة، وحقوق الطلبة وواجباتهم التي نصت عليها اللوائح والأنظمة.',
    'تقديم الدعم الإرشادي للطلبة بما يدعم تحقيق التزامه بإنهاء متطلبات الخطة الدراسية في الفترة الزمنية المحددة.',
    'متابعة أداء الطلبة خلال دراستهم وتقديم الدعم للمتعثرين دراسياً ومساعدتهم في التغلب على الصعوبات الأكاديمية وإزالة أسباب التعثر الدراسي.',
  ]),
  _GoalCategory('ثانياً: الإرشاد النفسي والاجتماعي', [
    'مساعدة الطلبة في اكتشاف ذاتهم وتحفيزهم أكاديمياً ونفسياً وسلوكياً خلال جميع مراحل مسيرتهم الجامعية.',
    'العمل على إيجاد الحلول للمشاكل التي تواجه الطالب والمرتبطة بقدراته الشخصية والاجتماعية، وتقديم الدعم والمساندة النفسية والاجتماعية.',
    'تقديم الإرشاد الداعم لتعديل السلوكيات المخالفة لأنظمة وتعليمات الجامعة.',
    'تعزيز المواطنة الصالحة وحب الانتماء للجامعة بشكل عام وللكلية بشكل خاص.',
  ]),
  _GoalCategory('ثالثاً: الإرشاد المهني والخريجين', [
    'تعريف الطلاب بالمسارات المهنية المناسبة لتخصصاتهم والمتطلبات التدريبية والشهادات المهنية المتعلقة بها.',
    'تقديم التدريب المهني المناسب للطلبة الداعم لمتطلبات سوق العمل في ضوء تخصصاتهم العلمية.',
    'بناء العلاقات المستدامة مع أرباب العمل لتوفير فرص التوظيف والتدريب لطلبة الكلية.',
    'متابعة الطلبة الخريجين وبناء علاقة مستدامة معهم للحصول على التغذية الراجعة اللازمة لتطوير الأداء الأكاديمي في الكلية.',
  ]),
  _GoalCategory('رابعاً: إرشاد ذوي الاحتياجات الخاصة', [
    'إدارة العلاقة والاتصال مع الطلبة ذوي الإعاقة لتقديم الدعم اللازم لهم مما يعينهم على المتابعة في العملية التعليمية في الجامعة.',
  ]),
  _GoalCategory('خامساً: إرشاد المتفوقين والموهوبين', [
    'اكتشاف ودعم الطلاب الموهوبين.',
    'تحفيز الطلاب المتفوقين علمياً.',
  ]),
];

/// الصفحة العامة (التعريفية) لوحدة الإرشاد الأكاديمي والخريجين - أول ما يفتحه
/// أي زائر لرابط بوابة الويب، قبل تسجيل الدخول. تحتوي نفس المحتوى الرسمي
/// الموجود في تطبيق الأندرويد (نبذة، رؤية ورسالة، أهداف، أعضاء الوحدة)، مع
/// قائمة تنقّل علوية يكون تسجيل الدخول أحد عناصرها بدل أن يكون الصفحة
/// الافتراضية.
class PublicLandingScreen extends StatefulWidget {
  const PublicLandingScreen({super.key});

  @override
  State<PublicLandingScreen> createState() => _PublicLandingScreenState();
}

class _PublicLandingScreenState extends State<PublicLandingScreen> {
  void _openLogin() => _pushLogin(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopUtilityBar(onLogin: _openLogin),
            const _NavBar(),
            const _HeroSection(),
            const _StatsSection(),
            _Footer(onLogin: _openLogin),
          ],
        ),
      ),
    );
  }
}

void _pushLogin(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PortalRoot(), settings: const RouteSettings(name: kPortalRootRouteName)),
  );
}

void _goHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// إطار موحّد للصفحات الداخلية (نبذة، الرؤية والرسالة، الأهداف، أعضاء
/// الوحدة، النماذج) - نفس الشريط العلوي وتذييل الصفحة الرئيسية، مع محتوى
/// الصفحة الخاص بينهما. هذا يُبقي التصفح متسقًا بصريًا في كل مكان بدل أن
/// تكون كل الأقسام مضغوطة في صفحة تمرير واحدة طويلة.
class InfoPageScaffold extends StatelessWidget {
  final Widget child;

  const InfoPageScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopUtilityBar(onLogin: () => _pushLogin(context)),
            const _NavBar(),
            child,
            _Footer(onLogin: () => _pushLogin(context)),
          ],
        ),
      ),
    );
  }
}

/// صفحة "نبذة عن الوحدة" - نافذة داخلية منفصلة يُصل إليها من تبويب الشريط.
class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'من نحن',
        title: 'نبذة عن الوحدة',
        icon: Icons.info_outline,
        child: _TextCard(
          text: 'نظراً لأهمية الدور الذي تؤديه كلية إدارة الأعمال بجامعة الطائف في '
              'خدمة النهضة التعليمية والمساهمة بتحقيق أهداف الرؤية 2030 والأهداف '
              'الاستراتيجية للجامعة، من خلال العمل على الارتقاء بكفاءة طلابها '
              'وتميز مخرجاتها التعليمية لتلبية احتياجات سوق العمل، فقد أنشأت '
              'عدداً من الوحدات المساندة تحت مظلة الكلية حتى يتم تنظيم وتنسيق '
              'أدوارها المختلفة على أكمل وجه. وفي ضوء ذلك تم إنشاء وحدة الإرشاد '
              'الأكاديمي والخريجين وإعادة تشكيلها بموجب القرار الصادر عن سعادة '
              'عميد الكلية رقم (59304/39) بتاريخ 28/11/1445هـ. وتسعى هذه الوحدة '
              'إلى تحقيق التميز وتلبية احتياج الطلاب في مجالات الإرشاد الأكاديمي '
              'المتنوعة على أكمل وجه لضمان نجاح مسيرتهم التعليمية بشكل يساهم في '
              'دعم وتعزيز منظومة الإرشاد الأكاديمي في الجامعة.\n\n'
              'ونرجو أن تكون هذه الوحدة داعماً أساسياً وموجهاً في تنفيذ المبادرات '
              'والأنشطة التي تختص بعمليات الإرشاد الأكاديمي والمهني والنفسي '
              'والاجتماعي، بالإضافة إلى إرشاد الطلبة من ذوي الهمم وكذلك الطلبة '
              'المتفوقين بالتنسيق المستمر مع إدارة الكلية وكذلك إدارة الإرشاد '
              'الجامعي.',
        ),
      ),
    );
  }
}

/// صفحة "الرؤية والرسالة".
class VisionPage extends StatelessWidget {
  const VisionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'وجهتنا',
        title: 'الرؤية والرسالة',
        icon: Icons.visibility_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TextCard(
              heading: 'الرؤية',
              headingIcon: Icons.remove_red_eye_outlined,
              text: 'التميز في تقديم خدمات إرشادية متنوعة للطالب بما يتوافق مع '
                  'احتياجاته الأكاديمية والنفسية والاجتماعية والمهنية عبر الوسائل '
                  'التقليدية والرقمية ووفقاً لأفضل الممارسات العالمية.',
            ),
            const SizedBox(height: 20),
            _TextCard(
              heading: 'الرسالة',
              headingIcon: Icons.flag_outlined,
              text: 'إرشاد ودعم الطالب أكاديمياً ونفسياً واجتماعياً ومهنياً، وتقديم '
                  'خدمات رعاية ودعم المتفوقين والموهوبين، وكذلك الطلبة من أصحاب '
                  'الهمم، وإقامة علاقة مستدامة مع الخريجين. وبما يتوافق مع معايير '
                  'الجودة في التعليم الجامعي ويدعم منظومة الإرشاد الأكاديمي في '
                  'الجامعة.',
            ),
          ],
        ),
      ),
    );
  }
}

/// صفحة "تواصل" الموحّدة - على غرار مركز التواصل في موقع سدايا: تجمع كل
/// قنوات التواصل في صفحة واحدة بدل تشتيتها في عدة عناصر قائمة منفصلة. تضم
/// قسم "تواصل مع إدارة الوحدة" (رئيس/نائب رئيس الوحدة - بيانات إدارية قد
/// تتغيّر بتغيّر شاغل المنصب) وقسم "الدعم الفني" (تواصل ثابت مع مطوّر
/// الموقع، بمعزل عن الهيكل الإداري).
class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'تواصل معنا',
        title: 'تواصل',
        icon: Icons.support_agent_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // البريد الرسمي الموحَّد للوحدة (لا مرتبط بشخص بعينه، يبقى ثابتًا
            // بتغيّر شاغلي المناصب) - بطلب سليمان صراحةً (2026-08-15) بعد
            // إنشائه حديثًا. يظهر بطاقة مستقلة أعلى بطاقات القيادات الفردية.
            const _UnitLeaderCard(
              role: 'البريد الرسمي للوحدة',
              name: 'وحدة الإرشاد الأكاديمي والخريجين',
              email: 'cba.ag@tu.edu.sa',
              accent: AppColors.green,
              icon: Icons.mail_outline,
            ),
            const SizedBox(height: 14),
            // بطاقات قيادة الوحدة (رئيس/نائب/أمين/منسّق الوحدة/سكرتير) - تُقرأ
            // حيًّا من "تشكيل الوحدة" بدل أسماء ثابتة بالكود، فتُحدَّث الصفحة
            // تلقائيًا عند اعتماد تشكيل جديد. تُستبعَد صراحةً بطاقات منسّقي
            // الأقسام/الكلية (تظهر في قسم "أعضاء الوحدة" أدناه بدلًا من هنا).
            StreamBuilder<List<UnitCommitteeMember>>(
              stream: UnitCommitteeRepository.watch(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <UnitCommitteeMember>[];
                final leaders = all.where((m) => m.role.contains('الوحدة')).toList()
                  ..sort((a, b) => _unitLeaderOrder(a.role) - _unitLeaderOrder(b.role));
                if (leaders.isEmpty) {
                  return const Text('لم يُعتمَد تشكيل الوحدة بعد.', style: TextStyle(color: Colors.grey));
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth < 640
                        ? constraints.maxWidth
                        : constraints.maxWidth < 900
                            ? (constraints.maxWidth - 14) / 2
                            : (constraints.maxWidth - 14 * 3) / 4;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: leaders
                          .asMap()
                          .entries
                          .map((entry) => SizedBox(
                                width: cardWidth,
                                child: _UnitLeaderCard(
                                  role: entry.value.role,
                                  name: entry.value.name,
                                  email: entry.value.email,
                                  accent: entry.key.isEven ? AppColors.green : AppColors.gold,
                                ),
                              ))
                          .toList(),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'الدعم الفني',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.greenDark),
            ),
            const SizedBox(height: 14),
            const _UnitLeaderCard(
              role: 'الدعم الفني للموقع',
              name: 'سليمان مفوز سليم الفواز',
              email: 'salfawaz@tu.edu.sa',
              accent: AppColors.gold,
              icon: Icons.build_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة عضو هيكلي واحدة (رئيس الوحدة، نائب الرئيس، الدعم الفني...) -
/// شريط علوي ملوّن بهوية الوحدة (بدل الشريط الجانبي الذهبي الثابت سابقًا)
/// لإعطاء إحساس "مخطط هيكلي" بدل بطاقة نصية عادية.
class _UnitLeaderCard extends StatelessWidget {
  const _UnitLeaderCard({
    required this.role,
    required this.name,
    required this.email,
    this.accent = AppColors.gold,
    this.icon = Icons.person_rounded,
  });

  final String role;
  final String name;
  final String email;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.greenDark, AppColors.green],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              child: Icon(icon, color: AppColors.goldLight, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              role,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: AppColors.goldLight),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => openMailto(email),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.email_outlined, size: 14, color: AppColors.goldLight),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.goldLight,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.goldLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// صفحة "أهداف الوحدة".
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'طموحنا',
        title: 'أهداف الوحدة',
        icon: Icons.flag_circle_outlined,
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'انطلاقاً من الأهداف الاستراتيجية لكلية إدارة الأعمال، والأهداف '
                'الاستراتيجية لجامعة الطائف، فقد تم صياغة الأهداف الرئيسية لوحدة '
                'الإرشاد الأكاديمي والخريجين بكلية إدارة الأعمال على النحو التالي:',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 18),
              ..._goalCategories.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: Card(
                      elevation: 1,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ExpansionTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${entry.key + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                        title: Text(
                          entry.value.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.green,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: entry.value.points.map((point) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Icon(Icons.circle, size: 6, color: AppColors.gold),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    point,
                                    style: const TextStyle(fontSize: 14, height: 1.8),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صفحة "الهيكل التنظيمي" - كانت سابقًا "أعضاء الوحدة" (قائمة مسطّحة)،
/// استُبدلت بمخطط هيكلي بصري بطلب سليمان صراحةً (2026-08-15).
class MembersPage extends StatelessWidget {
  const MembersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'هيكلتنا',
        title: 'الهيكل التنظيمي',
        icon: Icons.account_tree_outlined,
        maxWidth: 1180,
        child: const _OrgChartSection(),
      ),
    );
  }
}

enum _CalendarCategory { milestone, academic, holiday, exam }

extension on _CalendarCategory {
  String get label => switch (this) {
        _CalendarCategory.milestone => 'المحطات الرئيسية',
        _CalendarCategory.academic => 'الإجراءات الأكاديمية',
        _CalendarCategory.holiday => 'الإجازات',
        _CalendarCategory.exam => 'الاختبارات',
      };
  Color get color => switch (this) {
        _CalendarCategory.milestone => AppColors.green,
        _CalendarCategory.academic => const Color(0xFF2F8F6E),
        _CalendarCategory.holiday => AppColors.gold,
        _CalendarCategory.exam => const Color(0xFF7A1F2B),
      };
  IconData get icon => switch (this) {
        _CalendarCategory.milestone => Icons.flag_outlined,
        _CalendarCategory.academic => Icons.assignment_outlined,
        _CalendarCategory.holiday => Icons.beach_access_outlined,
        _CalendarCategory.exam => Icons.event_note_outlined,
      };
}

class _CalendarEvent {
  final int order;
  final _CalendarCategory category;
  final String title;
  final String start;
  final String? end;

  const _CalendarEvent(this.order, this.category, this.title, this.start, [this.end]);
}

// التقويم الجامعي المعتمد للفصل الدراسي الأول 1448هـ - نص حر يطابق التقويم
// الرسمي الصادر عن الجامعة حرفيًا (قابل للتغيير حسب إعلانات الجامعة الرسمية).
const _academicCalendarEvents = <_CalendarEvent>[
  _CalendarEvent(1, _CalendarCategory.milestone, 'بداية الدراسة للفصل الدراسي الأول',
      'الأحد 1448/03/27هـ الموافق 2026/08/30م', 'الخميس 1448/07/29هـ الموافق 2027/01/07م'),
  _CalendarEvent(2, _CalendarCategory.academic, 'تأجيل الدراسة', 'الثلاثاء 1448/03/12هـ الموافق 2026/08/25م',
      'الخميس 1448/03/21هـ الموافق 2026/09/03م'),
  _CalendarEvent(3, _CalendarCategory.academic, 'استقبال طلبات الزيارة', 'الأحد 1448/03/10هـ الموافق 2026/08/23م',
      'الخميس 1448/03/21هـ الموافق 2026/09/03م'),
  _CalendarEvent(4, _CalendarCategory.academic, 'طلب إعادة القيد', 'الأحد 1448/03/10هـ الموافق 2026/08/23م',
      'الخميس 1448/03/21هـ الموافق 2026/09/03م'),
  _CalendarEvent(5, _CalendarCategory.academic, 'الرفع للكليات بالطلبة المتقطعين بعذر غير معلوم',
      'الأحد 1448/05/21هـ الموافق 2026/01/11م', 'الخميس 1448/05/25هـ الموافق 2026/11/05م'),
  _CalendarEvent(6, _CalendarCategory.holiday, 'إجازة اليوم الوطني', 'الأربعاء 1448/04/12هـ الموافق 2026/09/23م',
      'الخميس 1448/04/13هـ الموافق 2026/09/24م'),
  _CalendarEvent(7, _CalendarCategory.academic, 'تقديم أعذار الطلبة المتغيّبين عن اختبار الفصل الماضي',
      'الأحد 1448/04/02هـ الموافق 2026/09/13م', 'الخميس 1448/05/11هـ الموافق 2026/10/22م'),
  _CalendarEvent(8, _CalendarCategory.academic, 'الاعتذار عن الدراسة', 'الأحد 1448/03/24هـ الموافق 2026/09/06م',
      'الخميس 1448/06/23هـ الموافق 2026/12/03م'),
  _CalendarEvent(9, _CalendarCategory.holiday, 'إجازة منتصف الفصل الدراسي الأول',
      'نهاية دوام الخميس 1448/06/09هـ الموافق 2026/11/19م', 'الأحد 1448/06/19هـ الموافق 2026/11/29م'),
  _CalendarEvent(10, _CalendarCategory.milestone, 'بداية الدراسة بعد إجازة منتصف الفصل الدراسي الأول',
      'الأحد 1448/06/19هـ الموافق 2026/11/29م', 'الخميس 1448/07/29هـ الموافق 2027/01/07م'),
  _CalendarEvent(11, _CalendarCategory.academic, 'الاعتذار عن مقرر دراسي', 'الأحد 1448/06/19هـ الموافق 2026/11/29م',
      'الخميس 1448/06/23هـ الموافق 2026/12/03م'),
  _CalendarEvent(12, _CalendarCategory.exam, 'الاختبارات البديلة للطلاب الموافَق على أعذارهم',
      'الأحد 1448/06/26هـ الموافق 2026/12/06م', 'الخميس 1448/07/01هـ الموافق 2026/12/10م'),
  _CalendarEvent(13, _CalendarCategory.exam, 'الاختبارات النهائية', 'الأحد 1448/07/11هـ الموافق 2026/12/20م',
      'الاثنين 1448/07/26هـ الموافق 2027/01/04م'),
  _CalendarEvent(14, _CalendarCategory.academic, 'إدخال رغبات تغيير التخصص', 'الأحد 1448/07/04هـ الموافق 2026/12/13م',
      'الأحد 1448/08/02هـ الموافق 2027/01/10م'),
  _CalendarEvent(15, _CalendarCategory.milestone, 'اعتماد النتائج وإغلاق الفصل',
      'الأربعاء 1448/07/28هـ الموافق 2027/01/06م'),
  _CalendarEvent(16, _CalendarCategory.milestone, 'تاريخ التخرّج الرسمي', 'الخميس 1448/07/29هـ الموافق 2027/01/07م'),
  _CalendarEvent(17, _CalendarCategory.holiday, 'إجازة نهاية الفصل الدراسي الأول',
      'بداية دوام يوم الخميس 1448/07/29هـ الموافق 2027/01/07م'),
];

/// صفحة "التقويم الجامعي" - نص حر منسوخ حرفيًا عن التقويم الرسمي الصادر عن
/// الجامعة للفصل الدراسي الأول 1448هـ (سليمان أرسل صورة التقويم الرسمي
/// 2026-08-15) - لا يُقرأ من أي مصدر بيانات حي، يُحدَّث يدويًا عند صدور
/// تقويم جديد من الجامعة.
const _academicCalendarMonths = <String>['أغسطس 2026', 'سبتمبر 2026', 'أكتوبر 2026', 'نوفمبر 2026', 'ديسمبر 2026', 'يناير 2027'];

/// صفحة "التقويم الجامعي" - أُعيد تصميمها بطلب سليمان صراحةً (2026-08-15)
/// لمطابقة تصميم البوستر الرسمي الذي أرسله (شريط أشهر زمني، جدول بصفوف
/// متبادلة الألوان وشارات تصنيف، صندوق ملاحظات) بدل قائمة البطاقات البسيطة.
class AcademicCalendarPage extends StatelessWidget {
  const AcademicCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'هيكلتنا الزمنية',
        title: 'التقويم الجامعي للفصل الدراسي الأول لعام 1448هـ',
        icon: Icons.calendar_month_outlined,
        maxWidth: 1180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CalendarMonthsStrip(),
            const SizedBox(height: 24),
            const _CalendarTable(),
            const SizedBox(height: 20),
            const _CalendarNotesBox(),
          ],
        ),
      ),
    );
  }
}

/// شريط الأشهر الزمني أعلى الجدول - أشهر الفصل الدراسي متصلة بخط ونقاط،
/// أسوة بالبوستر الرسمي.
class _CalendarMonthsStrip extends StatelessWidget {
  const _CalendarMonthsStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFE7EFEA),
            child: Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.green),
          ),
          const SizedBox(width: 8),
          for (final month in _academicCalendarMonths)
            Expanded(
              child: Column(
                children: [
                  Text(month.split(' ').first, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.greenDark)),
                  Text(month.split(' ').last, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// جدول التقويم الجامعي - رأس أخضر، صفوف متبادلة الألوان، وشارة تصنيف
/// ملوَّنة لكل حدث (أسوة بالبوستر الرسمي).
class _CalendarTable extends StatelessWidget {
  const _CalendarTable();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: Table(
            columnWidths: const {
              0: FixedColumnWidth(44),
              1: FlexColumnWidth(1.3),
              2: FlexColumnWidth(2.2),
              3: FlexColumnWidth(1.7),
              4: FlexColumnWidth(1.7),
            },
            border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade200)),
            children: [
              const TableRow(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.greenDark, AppColors.green])),
                children: [
                  _CalHeaderCell('م'),
                  _CalHeaderCell('التصنيف'),
                  _CalHeaderCell('الحدث'),
                  _CalHeaderCell('تاريخ البداية'),
                  _CalHeaderCell('تاريخ النهاية'),
                ],
              ),
              for (final event in _academicCalendarEvents)
                TableRow(
                  decoration: BoxDecoration(color: event.order.isEven ? const Color(0xFFF7F5EF) : Colors.white),
                  children: [
                    _CalCell(Text('${event.order}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                    _CalCell(_CategoryBadge(category: event.category)),
                    _CalCell(Text(event.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                    _CalCell(Text(event.start, style: const TextStyle(fontSize: 11, color: Colors.black54))),
                    _CalCell(Text(event.end ?? '—', style: const TextStyle(fontSize: 11, color: Colors.black54))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalHeaderCell extends StatelessWidget {
  final String text;
  const _CalHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );
  }
}

class _CalCell extends StatelessWidget {
  final Widget child;
  const _CalCell(this.child);

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), child: child);
  }
}

class _CategoryBadge extends StatelessWidget {
  final _CalendarCategory category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: category.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 13, color: category.color),
          const SizedBox(width: 5),
          Text(category.label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: category.color)),
        ],
      ),
    );
  }
}

/// صندوق "ملاحظات مهمة" أسفل الجدول - أسوة بالبوستر الرسمي.
class _CalendarNotesBox extends StatelessWidget {
  const _CalendarNotesBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: AppColors.gold),
              SizedBox(width: 8),
              Text('ملاحظات مهمة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.greenDark)),
            ],
          ),
          const SizedBox(height: 10),
          for (final note in const [
            'جميع التواريخ أعلاه حسب ما ورد في التقويم الجامعي المعتمد.',
            'التقويم قابل للتغيير وفق ما يستجدّ من إعلانات رسمية من الجامعة.',
            'يُرجى متابعة القنوات الرسمية للجامعة للحصول على آخر المستجدات.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 5, color: AppColors.gold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note, style: const TextStyle(fontSize: 12.5, color: Colors.black87))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// صفحة "روابط مهمة" المفصولة عن الشريط - تُبقي كل الروابط الخارجية بمكان
/// واحد يمكن الوصول إليه أيضًا مباشرة (بالإضافة إلى القائمة المنسدلة في
/// الشريط) لمن يفضّل صفحة كاملة بدل قائمة منبثقة.
class ImportantLinksPage extends StatelessWidget {
  const ImportantLinksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoPageScaffold(child: _ImportantLinksSection());
  }
}

/// صفحة "النماذج" - عنصر تنقّل جديد في الشريط لنماذج الوحدة، سيُبنى محتواه
/// لاحقًا؛ الآن نموذج أولي فارغ (Placeholder) فقط لحجز موضعه في التنقّل.
class FormsPage extends StatefulWidget {
  const FormsPage({super.key});

  @override
  State<FormsPage> createState() => _FormsPageState();
}

class _FormsPageState extends State<FormsPage> {
  bool _isGeneratingSupportForm = false;
  bool _isGeneratingHardshipForm = false;
  bool _isGeneratingAddDropForm = false;

  Future<void> _downloadSupportForm() async {
    setState(() => _isGeneratingSupportForm = true);
    try {
      final bytes = await UnitGuidePdfService.buildSupportRequestFormPdf();
      await downloadBytes(bytes, 'نموذج_طلب_دعم_نفسي_واجتماعي.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء النموذج: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingSupportForm = false);
    }
  }

  Future<void> _downloadHardshipForm() async {
    setState(() => _isGeneratingHardshipForm = true);
    try {
      final bytes = await UnitGuidePdfService.buildHardshipCaseFormPdf();
      await downloadBytes(bytes, 'نموذج_توثيق_حالة_الطالب.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء النموذج: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingHardshipForm = false);
    }
  }

  Future<void> _downloadAddDropForm() async {
    setState(() => _isGeneratingAddDropForm = true);
    try {
      final bytes = await UnitGuidePdfService.buildAddDropManualFormPdf();
      await downloadBytes(bytes, 'نموذج_الحذف_والإضافة_الورقي.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إنشاء النموذج: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAddDropForm = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'نماذج',
        title: 'نماذج الوحدة',
        icon: Icons.description_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _formCard(
              context,
              icon: Icons.favorite_border,
              title: 'طلب دعم نفسي واجتماعي',
              description: 'نموذج ورقي سرّي - نزّله واطبعه وعبّئه بخط يدك، ثم سلّمه للمرشد الأكاديمي أو منسّق قسمك.',
              loading: _isGeneratingSupportForm,
              onTap: _isGeneratingSupportForm ? null : _downloadSupportForm,
            ),
            const SizedBox(height: 12),
            _formCard(
              context,
              icon: Icons.assignment_outlined,
              title: 'توثيق حالة الطالب',
              description:
                  'لديك ظرف قهري أو أسري أو صحي؟ نزّل النموذج واطبعه وعبّئه بخط يدك، ثم سلّمه للمرشد الأكاديمي أو منسّق قسمك.',
              loading: _isGeneratingHardshipForm,
              onTap: _isGeneratingHardshipForm ? null : _downloadHardshipForm,
            ),
            const SizedBox(height: 12),
            _formCard(
              context,
              icon: Icons.edit_document,
              title: 'نموذج الحذف والإضافة الورقي',
              description: 'تعذّر عليك تقديم الطلب إلكترونياً؟ نزّل النموذج واطبعه وعبّئه بخط يدك، ثم سلّمه للمرشد الأكاديمي.',
              loading: _isGeneratingAddDropForm,
              onTap: _isGeneratingAddDropForm ? null : _downloadAddDropForm,
            ),
          ],
        ),
      ),
    );
  }

  Widget _formCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.goldLight, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark)),
                    const SizedBox(height: 6),
                    Text(description, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.6)),
                  ],
                ),
              ),
              loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.download, size: 20, color: AppColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة نص موحّدة (بدل فقرة عارية على الخلفية) - تكسر شعور "الورقة الطويلة"
/// بحدود وظل خفيفين وشريط جانبي ذهبي، مع عنوان فرعي اختياري.
class _TextCard extends StatelessWidget {
  final String text;
  final String? heading;
  final IconData? headingIcon;

  const _TextCard({required this.text, this.heading, this.headingIcon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(right: BorderSide(color: AppColors.gold, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) ...[
            Row(
              children: [
                if (headingIcon != null) ...[
                  Icon(headingIcon, color: AppColors.green, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  heading!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: AppColors.greenDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(text, style: const TextStyle(height: 1.9, fontSize: 14.5, color: Color(0xFF3A3A3A))),
        ],
      ),
    );
  }
}

/// شريط علوي رفيع (أخضر غامق) يحتوي زر تسجيل الدخول - على غرار الأشرطة
/// العلوية الشائعة في المواقع الحكومية الرسمية (رابط دخول أعلى الصفحة، منفصل
/// عن شريط التنقّل الرئيسي الأبيض).
class _TopUtilityBar extends StatefulWidget {
  final VoidCallback onLogin;

  const _TopUtilityBar({required this.onLogin});

  @override
  State<_TopUtilityBar> createState() => _TopUtilityBarState();
}

class _TopUtilityBarState extends State<_TopUtilityBar> {
  bool _isChecking = false;

  Future<void> _checkForUpdate() async {
    setState(() => _isChecking = true);
    try {
      final result = await AppUpdateService.checkForUpdate();
      if (!mounted) return;

      if (!result.hasUpdate) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('لا يوجد تحديث جديد'),
            content: Text('لديك أحدث إصدار من التطبيق (${result.currentVersionName}).'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('حسنًا')),
            ],
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('يتوفّر تحديث جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الإصدار الجديد: ${result.latestVersionName ?? ''}'),
              if ((result.releaseNotes ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(result.releaseNotes!),
              ],
              const SizedBox(height: 10),
              Text(
                'سيبدأ تنزيل ملف التحديث عبر المتصفح، ثم افتحه لإكمال التثبيت.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('لاحقًا')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.parse(result.apkUrl!), mode: LaunchMode.externalApplication);
              },
              child: const Text('تنزيل التحديث'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر التحقق من التحديثات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // شريط تحديث التطبيق - يظهر فقط في تطبيق الأندرويد (وليس الموقع)
        // لأنه لا معنى لـ"تحديث" صفحة ويب بهذه الطريقة.
        if (!kIsWeb)
          Container(
            color: AppColors.greenDark,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _isChecking ? null : _checkForUpdate,
                      tooltip: 'التحقق من وجود تحديث',
                      icon: _isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                            )
                          : const Icon(Icons.system_update_alt, size: 18, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // شريط "تسجيل الدخول" البارز - بأسلوب موقع سدايا: شريط أخضر كامل
        // العرض مستقل، بدل زر صغير ضمن شريط أدوات عام - يقود لدخول المنسّقين
        // وإدارة الوحدة والسكرتارية (الدخول السري للإدارة العليا يبقى مخفيًا
        // كما هو، بلا أي رابط ظاهر له).
        // top:kIsWeb: على الويب لا يوجد notch فلا ضرر من تفعيلها، وعلى
        // الأندرويد شريط التحديث (أعلاه) يحمي الشِّق العلوي بالفعل فتُعطَّل
        // هنا لتفادي حشوة مضاعفة.
        Container(
          color: AppColors.green,
          child: SafeArea(
            bottom: false,
            top: kIsWeb,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onLogin,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text(
                  'تسجيل الدخول',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// شعار موحّد (نفس تصميم الحلقة الذهبية حول "TU" الظاهرة في قسم الترحيب)
/// يُستخدم في الشريط العلوي، والضغط عليه يعيد المستخدم للصفحة الرئيسية من
/// أي مكان في الموقع/التطبيق. النسخة المعتمدة هنا هي الشعار الكامل بخلفية
/// خضراء صلبة (نفس الشعار الظاهر في الصفحة الرئيسية).
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _goHome(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Image.asset(
          'assets/images/full_logo_green.png',
          height: 36,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 860;

          final navButtonStyle = TextButton.styleFrom(
            foregroundColor: AppColors.green,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          );
          final navItems = [
            TextButton(
              onPressed: () => _goHome(context),
              style: navButtonStyle,
              child: const Text('الرئيسية'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IntroPage()),
              ),
              style: navButtonStyle,
              child: const Text('نبذة عن الوحدة'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VisionPage()),
              ),
              style: navButtonStyle,
              child: const Text('الرؤية والرسالة'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GoalsPage()),
              ),
              style: navButtonStyle,
              child: const Text('الأهداف'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MembersPage()),
              ),
              style: navButtonStyle,
              child: const Text('الهيكل التنظيمي'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FormsPage()),
              ),
              style: navButtonStyle,
              child: const Text('النماذج'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GuidesHubPage()),
              ),
              style: navButtonStyle,
              child: const Text('الدليل الإرشادي'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactPage()),
              ),
              style: navButtonStyle,
              child: const Text('تواصل'),
            ),
            IconButton(
              tooltip: 'التقويم الجامعي',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AcademicCalendarPage()),
              ),
              icon: const Icon(Icons.calendar_month_outlined, color: AppColors.green),
            ),
            PopupMenuButton<String>(
              tooltip: 'روابط مهمة',
              color: const Color(0xFFFBF6E9),
              onSelected: (url) async {
                await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
              },
              itemBuilder: (context) => _allLinks
                  .map(
                    (l) => PopupMenuItem(
                      value: l.url,
                      child: Row(
                        children: [
                          Icon(l.icon, size: 18, color: AppColors.green),
                          const SizedBox(width: 10),
                          Text(
                            l.label,
                            style: const TextStyle(
                              color: AppColors.greenDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'روابط مهمة',
                      style: TextStyle(
                        color: AppColors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: 20, color: AppColors.green),
                  ],
                ),
              ),
            ),
          ];

          if (isWide) {
            return Row(
              children: [
                const _BrandLogo(),
                const SizedBox(width: 24),
                ...navItems,
                const Spacer(),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _BrandLogo(),
              PopupMenuButton<int>(
                icon: const Icon(Icons.menu),
                onSelected: (i) {
                  switch (i) {
                    case 0:
                      _goHome(context);
                      break;
                    case 1:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IntroPage()));
                      break;
                    case 2:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VisionPage()));
                      break;
                    case 3:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalsPage()));
                      break;
                    case 4:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembersPage()));
                      break;
                    case 5:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FormsPage()));
                      break;
                    case 6:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportantLinksPage()));
                      break;
                    case 7:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnitGuidePage()));
                      break;
                    case 8:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactPage()));
                      break;
                    case 9:
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AcademicCalendarPage()));
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 0, child: Text('الرئيسية')),
                  PopupMenuItem(value: 1, child: Text('نبذة عن الوحدة')),
                  PopupMenuItem(value: 2, child: Text('الرؤية والرسالة')),
                  PopupMenuItem(value: 3, child: Text('الأهداف')),
                  PopupMenuItem(value: 4, child: Text('الهيكل التنظيمي')),
                  PopupMenuItem(value: 5, child: Text('النماذج')),
                  PopupMenuItem(value: 6, child: Text('روابط مهمة')),
                  PopupMenuItem(value: 7, child: Text('الدليل الإرشادي')),
                  PopupMenuItem(value: 8, child: Text('تواصل')),
                  PopupMenuItem(value: 9, child: Text('التقويم الجامعي')),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: isNarrow ? 18 : 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.greenDark, AppColors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              const Text(
                'وحدة الإرشاد الأكاديمي والخريجين',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
              ),
              const SizedBox(height: 6),
              Text(
                'جامعة الطائف — كلية إدارة الأعمال',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عنوان قسم موحّد (شارة أيقونة + تسمية صغيرة بالذهبي + عنوان كبير + خط
/// أخضر) يُستخدم في كل الأقسام لضمان اتساق بصري واحد على طول الصفحة.
class _SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final IconData icon;

  const _SectionHeader({required this.eyebrow, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.greenDark, AppColors.green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.goldLight, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class PageSection extends StatelessWidget {
  final String eyebrow;
  final String title;
  final IconData icon;
  final Widget child;
  final Color? background;
  final double maxWidth;

  const PageSection({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.child,
    this.background,
    this.maxWidth = 820,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      color: background,
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: isNarrow ? 32 : 56),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(eyebrow: eyebrow, title: title, icon: icon),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final VoidCallback onLogin;

  const _Footer({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.greenDark,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              const Text(
                'وحدة الإرشاد الأكاديمي والخريجين — كلية إدارة الأعمال — جامعة الطائف',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: onLogin,
                style: TextButton.styleFrom(foregroundColor: AppColors.goldLight),
                icon: const Icon(Icons.login, size: 18),
                label: const Text('تسجيل الدخول'),
              ),
              const SizedBox(height: 10),
              Container(height: 1, width: 60, color: Colors.white.withValues(alpha: 0.15)),
              const SizedBox(height: 10),
              Text(
                'جميع الحقوق محفوظة لـ سليمان الفواز © 2026',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// الهيكل التنظيمي لوحدة الإرشاد الأكاديمي والخريجين - يُقرأ حيًّا من
/// "تشكيل الوحدة" (نفس البيانات التي تغذّي بطاقات صفحة "تواصل معنا") ويُصنَّف
/// تلقائيًا إلى مجموعاته الأربع بحسب نص الدور (يحتوي "مسار"/"قسم"/"الكلية"
/// أو مطابقة صريحة لمسمّيات القيادة) - بلا أي اسم مكتوب يدويًا بالكود، حتى
/// يعكس أي تحديث لملف منسوبي الكلية تلقائيًا.
class _OrgChartSection extends StatelessWidget {
  const _OrgChartSection();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UnitCommitteeMember>>(
      stream: UnitCommitteeRepository.watch(),
      builder: (context, snapshot) {
        final members = snapshot.data ?? const <UnitCommitteeMember>[];
        if (snapshot.connectionState == ConnectionState.waiting && members.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }
        if (members.isEmpty) {
          return const Text('لم يُعتمَد الهيكل التنظيمي بعد.', style: TextStyle(color: Colors.grey));
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

        final chart = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (deputy != null) Expanded(child: _LeaderCard(member: deputy)),
                if (head != null && deputy != null) const SizedBox(width: 12),
                if (head != null) Expanded(child: _LeaderCard(member: head)),
              ],
            ),
            const SizedBox(height: 4),
            Container(height: 2, color: AppColors.gold),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 640;
                final cards = [
                  _ClusterCard(
                    icon: Icons.explore_outlined,
                    title: 'منسّقو المسارات النوعية',
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: trackCoords
                          .map((m) => _MemberChip(
                                role: m.role.replaceFirst(RegExp('^منسّ?ق مسار '), ''),
                                name: displayName(m.name),
                                width: 140,
                              ))
                          .toList(),
                    ),
                  ),
                  _ClusterCard(
                    icon: Icons.groups_outlined,
                    title: 'القيادة الإدارية للوحدة',
                    child: Column(
                      children: [
                        if (unitSecretaryGeneral != null)
                          _MemberChip(role: 'أمين الوحدة', name: displayName(unitSecretaryGeneral.name), accent: true),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (unitCoordinator != null)
                              Expanded(child: _MemberChip(role: 'منسّق الوحدة', name: displayName(unitCoordinator.name))),
                            if (unitCoordinator != null && unitSecretary != null) const SizedBox(width: 8),
                            if (unitSecretary != null)
                              Expanded(child: _MemberChip(role: 'سكرتير الوحدة', name: displayName(unitSecretary.name))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _ClusterCard(
                    icon: Icons.school_outlined,
                    title: 'منسّقو الكلية للشؤون الأكاديمية',
                    child: Row(
                      children: collegeCoords
                          .map((m) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: _MemberChip(
                                    // روايا الكلية تُميَّز بالتأنيث ("منسقة") لا بذكر "شطر
                                    // الطالبات" صراحةً كما في منسّقي الأقسام.
                                    role: m.role.contains('منسقة') ? 'شطر الطالبات' : 'شطر الطلاب',
                                    name: displayName(m.name),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  _ClusterCard(
                    icon: Icons.grid_view_outlined,
                    title: 'منسّقو الأقسام العلمية',
                    child: _DeptTable(depts: depts, deptCoords: deptCoords),
                  ),
                ];
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: cards
                      .map((c) => SizedBox(width: wide ? (constraints.maxWidth - 42) / 4 : constraints.maxWidth, child: c))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 28),
            const _MissionBar(),
          ],
        );

        return Stack(
          children: [
            Positioned.fill(child: IgnorePointer(child: _SignatureWatermark())),
            chart,
          ],
        );
      },
    );
  }
}

/// توقيع مائي خفيف "S/A" متكرر بميل قطري - بطلب سليمان صراحةً.
class _SignatureWatermark extends StatelessWidget {
  const _SignatureWatermark();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 900.0;
        const step = 150.0;
        final tiles = <Widget>[];
        for (double y = -50; y < h + 50; y += step) {
          for (double x = -50; x < w + 50; x += step) {
            tiles.add(Positioned(
              left: x,
              top: y,
              child: Transform.rotate(
                angle: -0.55,
                child: Text(
                  'S/A',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.green.withValues(alpha: 0.05)),
                ),
              ),
            ));
          }
        }
        return Stack(children: tiles);
      },
    );
  }
}

class _LeaderCard extends StatelessWidget {
  final UnitCommitteeMember member;

  const _LeaderCard({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.workspace_premium_outlined, size: 18, color: AppColors.goldLight),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(member.role, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(displayName(member.name), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClusterCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _ClusterCard({required this.icon, required this.title, required this.child});

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
                Icon(icon, size: 16, color: AppColors.goldLight),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  final String role;
  final String name;
  final double? width;
  final bool accent;

  const _MemberChip({required this.role, required this.name, this.width, this.accent = false});

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
          Text(role, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10.5, color: AppColors.green)),
          const SizedBox(height: 3),
          Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

/// جدول منسّقي الأقسام العلمية (القسم | شطر الطلاب | شطر الطالبات) - اسم
/// القسم وعنوانا الشطرين يظهران مرة واحدة فقط، لا مكرَّرين لكل قسم.
class _DeptTable extends StatelessWidget {
  final List<String> depts;
  final List<UnitCommitteeMember> deptCoords;

  const _DeptTable({required this.depts, required this.deptCoords});

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
            _DeptCell('شطر الطلاب', bold: true),
            _DeptCell('شطر الطالبات', bold: true),
          ],
        ),
        for (final dept in depts)
          TableRow(children: [
            _DeptCell(dept, bold: true, small: true),
            _DeptCell(displayName(byShatr(dept, false)?.name ?? '—')),
            _DeptCell(displayName(byShatr(dept, true)?.name ?? '—')),
          ]),
      ],
    );
  }
}

class _DeptCell extends StatelessWidget {
  final String text;
  final bool bold;
  final bool small;

  const _DeptCell(this.text, {this.bold = false, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: small ? 9.5 : 10, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
    );
  }
}

/// شريط رسالة الوحدة الختامي - أخضر متدرّج ونص ذهبي، أسوة بمثال الهوية
/// البصرية لوحدة الشراكات.
class _MissionBar extends StatelessWidget {
  const _MissionBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.gold),
      ),
      child: Row(
        children: [
          const Icon(Icons.grain, color: AppColors.gold, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'نسعى لإرشاد الطالب ودعمه أكاديميًا ونفسيًا ومهنيًا، ورعاية المتفوقين وذوي الهمم، وبناء تواصل مستدام مع خريجينا.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.6),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.grain, color: AppColors.gold, size: 20),
        ],
      ),
    );
  }
}

class _Stat {
  final IconData icon;
  final String label;
  final String value;

  const _Stat(this.icon, this.label, this.value);
}

/// قسم "إحصائيات هامة" على غرار موقع جامعة الطائف الرسمي - حلقة ذهبية
/// مزدوجة حول كل أيقونة، تسمية خضراء، ورقم ذهبي بارز أسفلها.
/// تعرض القيمة الفعلية إن توفّرت بيانات حقيقية (> صفر)، وإلا نصًا توضيحيًا
/// بدل رقم صفر يبدو وكأن الموقع فارغ أو معطّل عند أول انطلاقه.
String _statDisplayValue(int? value, {bool isPercent = false}) {
  if (value == null || value == 0) return 'قيد الرصد التلقائي';
  return isPercent ? '$value%' : value.toString();
}

/// قسم "إحصائيات هامة" - مرتبط لحظيًا بوثيقة public_stats/summary التي
/// تُحدَّثها لوحة الإدارة تلقائيًا مع كل تغيير في بيانات الطلبات. يظهر نص
/// "قيد الرصد التلقائي" بدل الرقم صفر طالما لم تُرفع بيانات فعلية بعد.
class _StatsSection extends StatelessWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionHeader(
                eyebrow: 'أرقامنا',
                title: 'إحصائيات هامة',
                icon: Icons.bar_chart_rounded,
              ),
              const SizedBox(height: 8),
              Text(
                'تُحدَّث تلقائيًا كلما أنجز المنسّقون طلبات جديدة',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
              ),
              const SizedBox(height: 28),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('public_stats')
                    .doc('summary')
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  final stats = <_Stat>[
                    _Stat(
                      Icons.assignment_turned_in_outlined,
                      'عدد الطلبات المُنجزة',
                      _statDisplayValue(data?['completed_requests'] as int?),
                    ),
                    _Stat(
                      Icons.groups_outlined,
                      'عدد الطلاب المستفيدين',
                      _statDisplayValue(data?['students_served'] as int?),
                    ),
                    _Stat(
                      Icons.support_agent_outlined,
                      'عدد المرشدين الأكاديميين',
                      _statDisplayValue(data?['advisors_count'] as int?),
                    ),
                    _Stat(
                      Icons.trending_up,
                      'نسبة الإنجاز',
                      _statDisplayValue(data?['completion_rate'] as int?, isPercent: true),
                    ),
                  ];

                  final accentColors = [
                    AppColors.greenDark,
                    AppColors.gold,
                    AppColors.green,
                    AppColors.goldLight,
                  ];
                  final isNarrow = MediaQuery.of(context).size.width < 700;
                  return GridView.count(
                    crossAxisCount: isNarrow ? 1 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: isNarrow ? 3.4 : 3.6,
                    children: [
                      for (var i = 0; i < stats.length; i++)
                        PortalStatCard(
                          icon: stats[i].icon,
                          value: stats[i].value,
                          label: stats[i].label,
                          accentColor: accentColors[i % accentColors.length],
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// قسم بارز في الصفحة الرئيسية يجمّع الروابط الخارجية المهمة (تُستخدم يوميًا
/// من المرشدين والمنسّقين للوصول لأنظمة الجامعة) مُقسّمة إلى تفريعات ذكية
/// حسب الغرض، بدل قائمة صغيرة داخل الشريط العلوي.
class _ImportantLinksSection extends StatelessWidget {
  const _ImportantLinksSection();

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      color: const Color(0xFFFBF6E9),
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: isNarrow ? 28 : 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(eyebrow: 'دائمة الاستخدام', title: 'روابط مهمة', icon: Icons.link),
              const SizedBox(height: 28),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isNarrow ? 300 : 560),
                  child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isNarrow ? 2 : 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.05,
                children: _allLinks.map((link) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openLink(link.url),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.greenDark.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.greenDark, AppColors.green],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                              color: AppColors.greenDark,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صفحة "الأدلة الإرشادية" - نقطة دخول واحدة تجمع كل الأدلة المتاحة
/// للتنزيل (دليل الطلبة، دليل المنسّقين، دليل المرشد الأكاديمي)، بدل القفز
/// مباشرة لمحتوى دليل واحد فقط عند الضغط على تبويب "الدليل الإرشادي".
class GuidesHubPage extends StatefulWidget {
  const GuidesHubPage({super.key});

  @override
  State<GuidesHubPage> createState() => _GuidesHubPageState();
}

class _GuidesHubPageState extends State<GuidesHubPage> {
  bool _isDownloadingStudent = false;
  bool _isDownloadingCoordinator = false;
  bool _isDownloadingAdvisor = false;

  Future<void> _downloadStudentGuide() async {
    setState(() => _isDownloadingStudent = true);
    try {
      final bytes = await UnitGuidePdfService.buildOfficialStudentGuide();
      downloadBytes(bytes, 'الدليل_الإرشادي_نموذج_الحذف_والإضافة.pdf');
    } finally {
      if (mounted) setState(() => _isDownloadingStudent = false);
    }
  }

  Future<void> _downloadCoordinatorGuide() async {
    setState(() => _isDownloadingCoordinator = true);
    try {
      final bytes = await UnitGuidePdfService.buildInternalOperationsGuide();
      downloadBytes(bytes, 'دليل_استخدام_البوابة_للمنسقين.pdf');
    } finally {
      if (mounted) setState(() => _isDownloadingCoordinator = false);
    }
  }

  Future<void> _downloadAdvisorGuide() async {
    setState(() => _isDownloadingAdvisor = true);
    try {
      final bytes = await UnitGuidePdfService.buildAdvisorInternalSystemGuide();
      downloadBytes(bytes, 'دليل_المنظومة_الداخلية_للمرشد_الأكاديمي.pdf');
    } finally {
      if (mounted) setState(() => _isDownloadingAdvisor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: PageSection(
        eyebrow: 'مرجعك الشامل',
        title: 'الأدلة الإرشادية',
        icon: Icons.menu_book_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اختر الدليل المناسب لك وحمّله بصيغة PDF:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            _guideCard(
              icon: Icons.school_outlined,
              title: 'الدليل الإرشادي لطلاب وطالبات الكلية',
              description: 'شرح كامل لخطوات تقديم طلب الحذف والإضافة الإلكتروني ومتابعة نتيجته.',
              isDownloading: _isDownloadingStudent,
              onDownload: _downloadStudentGuide,
              onView: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnitGuidePage())),
            ),
            const SizedBox(height: 16),
            _guideCard(
              icon: Icons.groups_outlined,
              title: 'دليل استخدام البوابة لمنسّقي الأقسام',
              description: 'خطوات عمل منسّق القسم على البوابة: تنزيل الملفات، رفعها بعد المعالجة، ومتابعة الإنجاز.',
              isDownloading: _isDownloadingCoordinator,
              onDownload: _downloadCoordinatorGuide,
            ),
            const SizedBox(height: 16),
            _guideCard(
              icon: Icons.computer_outlined,
              title: 'دليل استخدام المنظومة الداخلية للمرشد الأكاديمي',
              description: 'شرح استخدام المرشد الأكاديمي للمنظومة الداخلية الرسمية بالجامعة لإجراء عمليات الحذف والإضافة ونقل الشعب.',
              isDownloading: _isDownloadingAdvisor,
              onDownload: _downloadAdvisorGuide,
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isDownloading,
    required VoidCallback onDownload,
    VoidCallback? onView,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.goldLight, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.greenDark)),
                const SizedBox(height: 6),
                Text(description, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.6)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isDownloading ? null : onDownload,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                      icon: isDownloading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download, size: 18),
                      label: const Text('تنزيل PDF'),
                    ),
                    if (onView != null)
                      OutlinedButton.icon(
                        onPressed: onView,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('عرض على الموقع'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// صفحة "الدليل الإرشادي" العامة - نسخة موجّهة للطلبة، خالية تمامًا من أي
/// ذكر لبوابتنا الداخلية (هي نفس النسخة التي ستُنشر كملف PDF على صفحة
/// الوحدة الرسمية بموقع الجامعة)، فمن الآمن عرضها هنا للزوار مباشرة. تستخدم
/// نفس إطار الصفحات الداخلية (InfoPageScaffold) لضمان وجود شريط الدخول
/// والتنقّل في كل مكان بالموقع بلا استثناء.
class UnitGuidePage extends StatefulWidget {
  const UnitGuidePage({super.key});

  @override
  State<UnitGuidePage> createState() => _UnitGuidePageState();
}

class _UnitGuidePageState extends State<UnitGuidePage> {
  bool _isDownloading = false;

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      final bytes = await UnitGuidePdfService.buildOfficialStudentGuide();
      downloadBytes(bytes, 'الدليل_الإرشادي_نموذج_الحذف_والإضافة.pdf');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InfoPageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GuideHeader(isDownloading: _isDownloading, onDownload: _download),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _guideIntroSection(),
                    const SizedBox(height: 32),
                    _guideWarningBanner(),
                    const SizedBox(height: 32),
                    _guideStepsSection(),
                    const SizedBox(height: 32),
                    _guideProceduresSection(),
                    const SizedBox(height: 32),
                    _guideTipsSection(),
                    const SizedBox(height: 32),
                    _guideSection(
                      'متابعة نتيجة طلبك',
                      Icons.fact_check_outlined,
                      [
                        'يمكنك متابعة حالة طلبك وما إذا تم تنفيذه من خلال المنظومة الجامعية.',
                        'سجّل الدخول ← تبويب "أكاديمي" ← الجدول الدراسي / السجل الأكاديمي، للتأكد من تنفيذ الإجراء المطلوب.',
                        'عند وجود استفسار، تواصل مع مرشدك الأكاديمي مباشرة عبر تبويب "التواصل مع المرشد الأكاديمي" داخل المنظومة، أو عبر بريده الجامعي الرسمي.',
                      ],
                    ),
                    const SizedBox(height: 32),
                    _guideFaqSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideIntroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'يشرح هذا الدليل آلية تقديم طلب الحذف والإضافة عبر النموذج الإلكتروني '
          'المعتمد من وحدة الإرشاد الأكاديمي والخريجين، بديلاً عن التوجه '
          'الشخصي وتعبئة النماذج الورقية. اقرأ الخطوات التالية بعناية قبل '
          'تقديم طلبك لضمان إنجازه بأقل جهد ودون أي تأخير.',
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800, height: 1.8),
        ),
        const SizedBox(height: 20),
        _guideSection(
          'لماذا التحول الإلكتروني؟',
          Icons.bolt_outlined,
          [
            'القضاء على التكدس والحضور الشخصي خلال فترة الحذف والإضافة.',
            'تتبّع لحظي لحالة طلبك بدل الانتظار دون معرفة نتيجة الإجراء.',
            'حقول إلزامية تمنع أي طلب ناقص البيانات من الوصول للمعالجة.',
            'أولوية معالجة فورية لطلبات الخريجين المتوقعين وذوي الإعاقة.',
          ],
        ),
      ],
    );
  }

  /// "دليل الإجراءات" - شرح تفصيلي لكل نوع إجراء يمكن للطالب اختياره، بدل
  /// الاكتفاء بذكر الاسم فقط ضمن خطوات التقديم.
  Widget _guideProceduresSection() {
    const procedures = [
      ['إضافة شعبة', 'تسجيل شعبة جديدة لمقرر لم يكن مسجّلاً في جدولك. يُطلب منك تحديد رقم الشعبة المطلوبة بدقة بعد التأكد من توفّرها وعدم تعارضها مع بقية جدولك.'],
      ['حذف شعبة', 'إلغاء تسجيلك في شعبة موجودة حاليًا ضمن جدولك. يُطلب رقم الشعبة الحالية المراد حذفها.'],
      ['تعديل', 'الانتقال من شعبة إلى أخرى لنفس المقرر (يجمع بين حذف الشعبة الحالية وإضافة الشعبة الجديدة في خطوة واحدة).'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _guideSectionTitle('دليل الإجراءات', Icons.rule_folder_outlined),
        const SizedBox(height: 6),
        Text(
          'قبل تعبئة النموذج، تعرّف على معنى كل إجراء لتختار المناسب لحالتك:',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        ...procedures.map((p) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p[0], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.greenDark, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(p[1], style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.7)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _guideWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('قبل البدء: يرجى الانتباه', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800, fontSize: 13.5)),
                const SizedBox(height: 6),
                Text(
                  'في بداية النموذج إقرار وتعهد إلزامي بصحة بياناتك؛ عدم الموافقة عليه يوقف تقديم الطلب نهائيًا.',
                  style: TextStyle(fontSize: 12.5, color: Colors.red.shade900, height: 1.6),
                ),
                const SizedBox(height: 6),
                Text(
                  'يُسمح لك بتقديم النموذج مرة واحدة فقط، لذا راجع وتأكد من جميع طلباتك (الإضافة/الحذف/التعديل) بعناية قبل الضغط على الإرسال النهائي.',
                  style: TextStyle(fontSize: 12.5, color: Colors.red.shade900, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideStepsSection() {
    const steps = [
      ['تسجيل الدخول', 'افتح النموذج وسجّل الدخول إلزاميًا بالبريد الجامعي الرسمي فقط لتوثيق هويتك.'],
      ['الإقرار والتعهد', 'يجب الموافقة على الإقرار الإلزامي للمتابعة؛ عدم الموافقة يوقف تقديم الطلب نهائيًا.'],
      ['البيانات الأساسية', 'رقم الجوال، حالة التخرج المتوقعة، من ذوي الإعاقة، الشطر والقسم العلمي، والمرشد الأكاديمي.'],
      ['نوع الإجراء', 'اختيار إضافة/حذف/تعديل شعبة، مع رقم الشعبة الحالية إلزاميًا للجميع (راجع "دليل الإجراءات" أعلاه).'],
      ['المقرر وسبب الطلب', 'تحديد المقرر المرتبط بالإجراء وسبب الطلب من قائمة محددة.'],
      ['أكثر من إجراء في نفس النموذج', 'يمكنك إدراج أكثر من إجراء (إضافة وحذف وتعديل) ضمن نفس النموذج قبل الإرسال النهائي.'],
      ['الإرسال النهائي', 'الإرسال لا يُعدّ موافقة على التنفيذ؛ تُدرس طلباتك وفق اللوائح والضوابط الأكاديمية.'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _guideSectionTitle('خطوات تقديم الطلب', Icons.list_alt_outlined),
        const SizedBox(height: 16),
        ...steps.asMap().entries.map((e) => _guideStepTile('${e.key + 1}', e.value[0], e.value[1])),
      ],
    );
  }

  Widget _guideTipsSection() {
    const tips = [
      ['الدخول بالبريد الجامعي', 'التوثيق الذكي يعتمد طلبك باسمك رسميًا، ويحمي سجلّك الأكاديمي.'],
      ['الحقول الإلزامية', 'لا يقبل النظام طلبًا ناقص البيانات — تأكد من اكتمال جميع الحقول قبل الإرسال.'],
      ['أكثر من إجراء في نموذج واحد', 'أدرج جميع احتياجاتك من إضافة وحذف وتعديل قبل الإرسال النهائي.'],
      ['الإرسال ليس موافقة على التنفيذ', 'تُدرس الطلبات وفق اللوائح الأكاديمية، وتصلك النتيجة عبر متابعتك بنفسك.'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _guideSectionTitle('تنبيهات مهمة قبل الإرسال', Icons.info_outline),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: tips.map((t) {
            return Container(
              width: 340,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t[0], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.greenDark, fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Text(t[1], style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.6)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _guideFaqSection() {
    const faq = [
      ['هل إرسال النموذج يعني موافقة الكلية على طلبي؟', 'لا، الإرسال هو تقديم للطلب فقط. تُدرس الطلبات وفق اللوائح والضوابط الأكاديمية، وتُنفَّذ إن كانت مستوفية الشروط.'],
      ['كم يستغرق تنفيذ طلبي؟', 'تتم معالجة الطلبات ضمن فترة الحذف والإضافة المعلنة. تابع حالة طلبك بنفسك عبر المنظومة الجامعية.'],
      ['نسيت إضافة إجراء ضمن نموذجي، ماذا أفعل؟', 'لا يُسمح بتقديم نموذج ثانٍ. تواصل مباشرة مع وحدة الإرشاد الأكاديمي عبر البريد الرسمي، أو من خلال مرشدك الأكاديمي.'],
      ['أنا من ذوي الإعاقة أو من الخريجين المتوقعين، هل هناك أولوية؟', 'نعم، حدّد ذلك بدقة في الحقول المخصصة بالنموذج، ويمنحك هذا أولوية أعلى في سرعة المعالجة.'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _guideSectionTitle('أسئلة شائعة', Icons.help_outline),
        const SizedBox(height: 16),
        ...faq.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('س: ${f[0]}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.greenDark, fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text('ج: ${f[1]}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.6)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _guideSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.greenDark, AppColors.green]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.goldLight, size: 20),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
      ],
    );
  }

  Widget _guideStepTile(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            child: Text(number, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.greenDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.greenDark, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideSection(String title, IconData icon, List<String> points) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF6E9),
        borderRadius: BorderRadius.circular(16),
        border: Border(right: BorderSide(color: AppColors.gold, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _guideSectionTitle(title, icon),
          const SizedBox(height: 14),
          ...points.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 6, color: AppColors.gold),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p, style: const TextStyle(fontSize: 13, height: 1.7))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _GuideHeader extends StatelessWidget {
  final bool isDownloading;
  final VoidCallback onDownload;

  const _GuideHeader({required this.isDownloading, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.greenDark, AppColors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.menu_book_outlined, color: AppColors.goldLight, size: 36),
            const SizedBox(height: 12),
            const Text(
              'الدليل الإرشادي لطلاب وطالبات كلية إدارة الأعمال',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
            ),
            const SizedBox(height: 6),
            Text(
              'نموذج الحذف والإضافة الإلكتروني',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isDownloading ? null : onDownload,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              icon: isDownloading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
              label: const Text('تنزيل الدليل PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
