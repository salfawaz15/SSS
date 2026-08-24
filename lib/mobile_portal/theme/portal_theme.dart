/// نقطة استيراد واحدة للهوية البصرية لتطبيق "بوابة الإرشاد" الجوّالة -
/// تُعيد تصدير `AppColors`/`AppTextStyles`/`AppRadius`/`AppSpacing`/`AppNotice`/
/// `AppTheme` من `theme/app_theme.dart` نفسها المستخدَمة بالموقع، بلا أي لون
/// أو خط جديد (القسم 24 من مواصفات التطبيق الجديد: لا ألوان إضافية عشوائية).
library;
export '../../theme/app_theme.dart';

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// ألوان حالة موحّدة لعناصر بوابة الإرشاد (تقدّم/تنبيهات) - نفس دلالات
/// القسم 24: أخضر=مكتمل، ذهبي=معالجة/تصعيد، رمادي محايد=لم يبدأ، أحمر=تحذير فقط.
class PortalStatusColors {
  static const completed = AppColors.green;
  static const escalated = AppColors.gold;
  static const notStarted = Color(0xFF9AA39D);
  static const warning = AppColors.errorRed;
}
