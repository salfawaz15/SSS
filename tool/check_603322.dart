import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:sulaiman/services/windows1256_decoder.dart';

void main() {
  final bytes = File(r'المرفقات\المواد\جداول الاقسام-الفصل الدراسي الأول 1448هـ 1\الحوية-طلاب.xls').readAsBytesSync();
  final text = Windows1256Decoder.decode(bytes);
  final doc = html_parser.parse(text);
  final rows = doc.querySelectorAll('tr');
  for (final tr in rows) {
    final spans = tr.querySelectorAll('span');
    final texts = <String>[];
    for (final s in spans) {
      final t = s.text.trim();
      if (t.isNotEmpty) texts.add(t);
    }
    if (texts.any((t) => t.contains('الشبكات'))) {
      print(texts);
    }
  }
}
