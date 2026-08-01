import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'team_members_screen.dart';

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

/// شاشة "عن الوحدة" مقسّمة لأربعة تبويبات فرعية بدل عرض كل المحتوى في تمرير
/// واحد طويل: نبذة، الرؤية والرسالة، الأهداف، وأعضاء الوحدة.
class AboutUnitScreen extends StatefulWidget {
  const AboutUnitScreen({super.key});

  @override
  State<AboutUnitScreen> createState() => _AboutUnitScreenState();
}

class _AboutUnitScreenState extends State<AboutUnitScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عن الوحدة'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'نبذة'),
            Tab(text: 'الرؤية والرسالة'),
            Tab(text: 'الأهداف'),
            Tab(text: 'أعضاء الوحدة'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _IntroTab(),
          _VisionMissionTab(),
          _GoalsTab(),
          TeamMembersTab(),
        ],
      ),
    );
  }
}

class _IntroTab extends StatelessWidget {
  const _IntroTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SectionCard(
          icon: Icons.info_outline,
          title: 'نبذة عن الوحدة',
          child: Text(
            'نظراً لأهمية الدور الذي تؤديه كلية إدارة الأعمال بجامعة الطائف في '
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
            style: TextStyle(height: 1.8, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

class _VisionMissionTab extends StatelessWidget {
  const _VisionMissionTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SectionCard(
          icon: Icons.visibility_outlined,
          title: 'الرؤية',
          child: Text(
            'التميز في تقديم خدمات إرشادية متنوعة للطالب بما يتوافق مع '
            'احتياجاته الأكاديمية والنفسية والاجتماعية والمهنية عبر الوسائل '
            'التقليدية والرقمية ووفقاً لأفضل الممارسات العالمية.',
            style: TextStyle(height: 1.8, fontSize: 13.5),
          ),
        ),
        SizedBox(height: 12),
        _SectionCard(
          icon: Icons.flag_outlined,
          title: 'الرسالة',
          child: Text(
            'إرشاد ودعم الطالب أكاديمياً ونفسياً واجتماعياً ومهنياً، وتقديم '
            'خدمات رعاية ودعم المتفوقين والموهوبين، وكذلك الطلبة من أصحاب '
            'الهمم، وإقامة علاقة مستدامة مع الخريجين. وبما يتوافق مع معايير '
            'الجودة في التعليم الجامعي ويدعم منظومة الإرشاد الأكاديمي في '
            'الجامعة.',
            style: TextStyle(height: 1.8, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

class _GoalsTab extends StatelessWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'انطلاقاً من الأهداف الاستراتيجية لكلية إدارة الأعمال، والأهداف '
          'الاستراتيجية لجامعة الطائف، فقد تم صياغة الأهداف الرئيسية لوحدة '
          'الإرشاد الأكاديمي والخريجين بكلية إدارة الأعمال على النحو التالي:',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12.5,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 14),
        ..._goalCategories.map(
          (category) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: Card(
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ExpansionTile(
                  title: Text(
                    category.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.green,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: category.points.map((point) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: AppColors.gold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              point,
                              style: const TextStyle(fontSize: 13, height: 1.7),
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
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.green, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
