import 'dart:io';
import 'package:image/image.dart' as img;

/// يولّد أيقونة مربّعة للتطبيق من الشعار الكامل (خلفية خضراء + شعار في المنتصف)
/// بدون تشويه نسبة العرض إلى الارتفاع.
void main() {
  final logo = img.decodePng(
    File('assets/images/full_logo_green.png').readAsBytesSync(),
  )!;

  // اقتصاص شارة "TU" المربّعة من أقصى يمين الشعار (أوضح عنصر كأيقونة صغيرة)
  final badgeSize = logo.height;
  final badge = img.copyCrop(
    logo,
    x: logo.width - badgeSize,
    y: 0,
    width: badgeSize,
    height: badgeSize,
  );

  const size = 1024;
  final canvas = img.Image(width: size, height: size);
  img.fill(canvas, color: img.ColorRgba8(0x15, 0x4B, 0x36, 0xFF));

  const padding = 90;
  final targetSize = size - padding * 2;
  final resized = img.copyResize(badge, width: targetSize, height: targetSize);

  final dstX = (size - targetSize) ~/ 2;
  final dstY = (size - targetSize) ~/ 2;

  img.compositeImage(canvas, resized, dstX: dstX, dstY: dstY);

  File('assets/images/app_icon.png').writeAsBytesSync(img.encodePng(canvas));
  // ignore: avoid_print
  print('تم إنشاء assets/images/app_icon.png بحجم ${size}x$size');
}
