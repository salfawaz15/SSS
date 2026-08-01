import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodeJpg(
    File('assets/images/unit_logo_transparent.jpeg').readAsBytesSync(),
  )!;

  final trimmed = img.trim(src, mode: img.TrimMode.topLeftColor);

  // إضافة هامش بسيط حول المحتوى المقصوص
  const pad = 24;
  final padded = img.Image(width: trimmed.width + pad * 2, height: trimmed.height + pad * 2);
  img.fill(padded, color: img.ColorRgba8(255, 255, 255, 255));
  img.compositeImage(padded, trimmed, dstX: pad, dstY: pad);

  File('assets/images/unit_logo_cropped.png').writeAsBytesSync(img.encodePng(padded));
  print('done ${padded.width}x${padded.height}');
}
