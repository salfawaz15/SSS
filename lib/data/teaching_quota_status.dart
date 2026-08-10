import 'package:flutter/material.dart';

/// حالة النصاب التدريسي لعضو هيئة تدريس - نفس التصنيف المستخدَم بتقرير
/// النصاب (`course_schedule_admin_screen.dart`)، مُستخرَج هنا كوحدة مشتركة
/// حتى تُستخدَم نفس الألوان في أي مكان آخر يعرض العبء الدراسي (مثال: عمود
/// "العبء الدراسي" بشاشة منسوبي الكلية - سليمان 2026-08-09: "ألوان العبء
/// الدراسي لم تظهر في المنسوبين").
enum TeachingQuotaStatus { ok, under, over, overWithinRounding, unknown }

/// أقرب رقم قابل للتحقيق فعليًا عند/فوق الحد النظامي، باعتبار أن أغلب
/// المقررات 3 ساعات معتمدة.
int _practicalMax(int maxHours) => ((maxHours + 2) ~/ 3) * 3;

/// يقارن الساعات الفعلية بالنصاب الفعلي (المخفَّض إن وُجد) ونصاب الدرجة
/// العلمية الكامل - انظر توثيق `_quotaCompare` الأصلي بـ
/// `course_schedule_admin_screen.dart` لتفاصيل قاعدة "الزيادة الإجبارية
/// مقابل الاختيارية".
TeachingQuotaStatus compareTeachingQuota(int actualHours, int? maxHours, {int? fullRankMaxHours}) {
  if (maxHours == null) return TeachingQuotaStatus.unknown;
  if (actualHours == maxHours) return TeachingQuotaStatus.ok;
  if (actualHours < maxHours) return TeachingQuotaStatus.under;

  final overtimeBase = fullRankMaxHours ?? maxHours;
  if (actualHours <= overtimeBase) return TeachingQuotaStatus.ok;

  return actualHours <= _practicalMax(overtimeBase) ? TeachingQuotaStatus.overWithinRounding : TeachingQuotaStatus.over;
}

/// أحمر = دون النصاب، أخضر = مطابق، برتقالي = زائد إجباري (فارق تقريب)،
/// أرجواني = زائد اختياري (زيادة حقيقية).
Color teachingQuotaColor(TeachingQuotaStatus status) => switch (status) {
      TeachingQuotaStatus.over => Colors.purple.shade700,
      TeachingQuotaStatus.overWithinRounding => Colors.orange.shade800,
      TeachingQuotaStatus.under => Colors.red.shade700,
      TeachingQuotaStatus.ok => Colors.green.shade700,
      TeachingQuotaStatus.unknown => Colors.grey.shade700,
    };
