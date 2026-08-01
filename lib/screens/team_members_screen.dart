import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class _Member {
  final String name;
  final String department;
  final String role;

  const _Member(this.name, this.department, this.role);
}

enum _MemberCategory { leadership, coordinator, member }

_MemberCategory _memberCategory(String role) {
  if (role == 'عضو') return _MemberCategory.member;
  if (role.contains('منسق')) return _MemberCategory.coordinator;
  return _MemberCategory.leadership;
}

// ترتيب الأقسام الرسمي المعتمد في كل أعمال الوحدة (نفس ترتيب نموذج الحذف
// والإضافة): الإدارة، المحاسبة، التسويق، الاقتصاد والتمويل، نظم المعلومات.
const _memberDeptOrder = <String>[
  'إدارة الأعمال',
  'المحاسبة',
  'التسويق',
  'الاقتصاد والتمويل',
  'نظم المعلومات الإدارية',
];

int _deptIndex(String department) {
  final i = _memberDeptOrder.indexOf(department);
  return i == -1 ? _memberDeptOrder.length : i;
}

bool _isFemaleRole(String role) => role.contains('منسقة') || role.contains('أمينة');

/// يرتّب: الرجال أولاً (حسب ترتيب الأقسام الرسمي)، ثم النساء (بنفس ترتيب
/// الأقسام) - بدل خلط الشطرين حسب القسم مباشرة.
List<_Member> _sortedByDeptThenGender(Iterable<_Member> members) {
  final list = members.toList();
  list.sort((a, b) {
    final genderCompare = (_isFemaleRole(a.role) ? 1 : 0) - (_isFemaleRole(b.role) ? 1 : 0);
    if (genderCompare != 0) return genderCompare;
    return _deptIndex(a.department) - _deptIndex(b.department);
  });
  return list;
}

const _members = <_Member>[
  _Member('د. ألاء عمر بارفعة', 'نظم المعلومات الإدارية', 'رئيس الوحدة'),
  _Member('أ. سليمان مفوز الفواز', 'نظم المعلومات الإدارية', 'نائب الرئيس'),
  _Member('د. تماضر عواض السلمي', 'الاقتصاد والتمويل', 'أمين الوحدة'),
  _Member('د. الساره سعد علي احمد', 'المحاسبة', 'منسقة قسم المحاسبة'),
  _Member('د. حسن عبدالرحيم الزبير', 'التسويق', 'أمين ومنسق قسم التسويق'),
  _Member('د. السيد الحضري احمد', 'إدارة الأعمال', 'عضو'),
  _Member('د. سوليمة عبدلي', 'الاقتصاد والتمويل', 'منسقة قسم الاقتصاد والتمويل'),
  _Member('د. صالح حامد العريفي', 'نظم المعلومات الإدارية', 'منسق قسم نظم المعلومات الإدارية'),
  _Member('د. أميرة سعد الفقيه', 'التسويق', 'منسقة قسم التسويق'),
  _Member('أ. دلال مفرح العمري', 'نظم المعلومات الإدارية', 'منسقة قسم نظم المعلومات الإدارية'),
  _Member('د. أكرم محمد بلحاج محمد', 'إدارة الأعمال', 'منسق قسم الإدارة'),
  _Member('د. محمد ابكر احمد محمد', 'المحاسبة', 'منسق قسم المحاسبة'),
  _Member('أ. مازن عبدالرحمن محمد المنجومي', 'إدارة الأعمال', 'عضو'),
  _Member('د. حنان عثمان محمد', 'إدارة الأعمال', 'منسقة قسم الإدارة'),
  _Member('أ. أشواق علي طامي العتيبي', 'الاقتصاد والتمويل', 'عضو'),
  _Member('د. الصادق محمد سالم الطيب', 'الاقتصاد والتمويل', 'منسق قسم الاقتصاد والتمويل'),
  _Member('د. مني النيل مصطفى مرسال', 'إدارة الأعمال', 'عضو'),
  _Member('د. مزمل عوض طه احمد', 'المحاسبة', 'عضو'),
  _Member('أ. رهف صالح العصيمي', 'نظم المعلومات الإدارية', 'سكرتير الوحدة'),
];

/// محتوى تبويب "أعضاء الوحدة" (بدون Scaffold خاص به - يُستخدم كتبويب ضمن
/// شاشة "عن الوحدة").
class TeamMembersTab extends StatelessWidget {
  const TeamMembersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final leadership = _members.where((m) => _memberCategory(m.role) == _MemberCategory.leadership).toList();
    final coordinators = _sortedByDeptThenGender(_members.where((m) => _memberCategory(m.role) == _MemberCategory.coordinator));
    final regular = _sortedByDeptThenGender(_members.where((m) => _memberCategory(m.role) == _MemberCategory.member));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel('الهيئة الإدارية (${leadership.length})'),
        const SizedBox(height: 10),
        _MembersCard(members: leadership),
        const SizedBox(height: 22),
        _SectionLabel('المنسّقون (${coordinators.length})'),
        const SizedBox(height: 10),
        _MembersCard(members: coordinators),
        const SizedBox(height: 22),
        _SectionLabel('الأعضاء (${regular.length})'),
        const SizedBox(height: 10),
        _MembersCard(members: regular),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    );
  }
}

class _MembersCard extends StatelessWidget {
  final List<_Member> members;

  const _MembersCard({required this.members});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: members.asMap().entries.map((entry) {
          final index = entry.key;
          final member = entry.value;
          final isLeadership = member.role != 'عضو';
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              // بنية مخصّصة (بدل ListTile) - عمود العنوان يأخذ العرض الكامل
              // المتاح ثم شارة الدور تحته، بدل عمود trailing ثابت العرض إلى
              // جانب leading كان يضغط الاسم في نصف الشاشة على الجوّال فيتكسّر
              // حرفًا حرفًا.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          (isLeadership ? AppColors.gold : AppColors.green)
                              .withValues(alpha: 0.12),
                      child: Icon(
                        Icons.person_outline,
                        size: 18,
                        color: isLeadership ? AppColors.gold : AppColors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            member.department,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (isLeadership ? AppColors.gold : Colors.grey)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: (isLeadership ? AppColors.gold : Colors.grey)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              member.role,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isLeadership
                                    ? AppColors.gold
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
