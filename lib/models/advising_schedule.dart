/// مرشد واحد ضمن فترة زمنية معيّنة داخل جدول توزيع فترات الإرشاد
class AdvisingScheduleEntry {
  final String advisorName;
  final String office;

  const AdvisingScheduleEntry({required this.advisorName, required this.office});

  /// يُستخدم عند بناء الاسم من مصدر خارجي (ملف مرفوع) بدل المنشئ المباشر -
  /// يزيل ألقاب "د."/"أ."/"د/" (وتراكيبها مثل "أ. د.") من بداية الاسم قبل
  /// التخزين، بناءً على قاعدة صريحة ومتكررة: لا تظهر ألقاب المرشدين في أي
  /// مكان بالموقع، الاسم فقط.
  factory AdvisingScheduleEntry.clean({required String advisorName, required String office}) =>
      AdvisingScheduleEntry(advisorName: stripAdvisorTitle(advisorName), office: office);

  static String stripAdvisorTitle(String name) {
    var n = name.trim();
    final titlePattern = RegExp(r'^(د|أ)\s*[.\/]\s*');
    while (titlePattern.hasMatch(n)) {
      n = n.replaceFirst(titlePattern, '').trim();
    }
    return n;
  }

  Map<String, dynamic> toJson() => {'advisorName': advisorName, 'office': office};

  factory AdvisingScheduleEntry.fromJson(Map<String, dynamic> json) => AdvisingScheduleEntry(
        advisorName: stripAdvisorTitle(json['advisorName'] as String? ?? ''),
        office: json['office'] as String? ?? '',
      );
}

/// فترة زمنية واحدة ضمن يوم معيّن (مثال: الأحد - الفترة الأولى 8-11ص)
class AdvisingScheduleSlot {
  final String dayLabel; // مثال: "الأحد - 1448/3/17هـ"
  final String periodLabel; // مثال: "8:00 ص - 11:00 ص"
  final List<AdvisingScheduleEntry> entries;

  const AdvisingScheduleSlot({
    required this.dayLabel,
    required this.periodLabel,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
        'dayLabel': dayLabel,
        'periodLabel': periodLabel,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory AdvisingScheduleSlot.fromJson(Map<String, dynamic> json) => AdvisingScheduleSlot(
        dayLabel: json['dayLabel'] as String? ?? '',
        periodLabel: json['periodLabel'] as String? ?? '',
        entries: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => AdvisingScheduleEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
