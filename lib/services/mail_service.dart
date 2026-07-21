import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/secrets.dart';

class MailService {
  static const String _sendGridUrl = 'https://api.sendgrid.com/v3/mail/send';

  static String _buildCsv(List<Map<String, dynamic>> tickets) {
   final headers = [
     'اسم الطالب', 'الرقم الجامعي', 'الشطر', 'القسم', 'المرشد الأكاديمي', 'رقم الجوال',
     'خريج متوقع', 'ذوي إعاقة',
     'نوع الإجراء', 'المقرر', 'رقم الشعبة', 'سبب الطلب',
   ];

    final rows = <String>[headers.join(',')];

    for (final t in tickets) {
      final baseInfo = [
     t['name'] ?? '',
     t['university_id'] ?? '',
     t['shatr'] ?? '',
     t['department'] ?? '',
     t['advisor'] ?? '',
     t['phone'] ?? '',
     (t['expected_graduate'] == true) ? 'نعم' : 'لا',
     (t['has_disability'] == true) ? 'نعم' : 'لا',
   ];
      final actions = (t['actions'] as List?) ?? [];

      if (actions.isEmpty) {
        rows.add([...baseInfo, '', '', '', ''].map(_csvEscape).join(','));
        continue;
      }

      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final row = [
          ...baseInfo,
          action['action_type'] ?? '',
          action['course'] ?? '',
          action['required_section'] ?? action['current_section'] ?? '',
          action['reason_detail'] ?? action['reason'] ?? '',
        ];
        rows.add(row.map(_csvEscape).join(','));
      }
    }

    return rows.join('\n');
  }

  static String _csvEscape(dynamic value) {
    final str = value?.toString() ?? '';
    if (str.contains(',') || str.contains('"') || str.contains('\n')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  static Future<bool> sendDepartmentReport({
    required String shatr,
    required String department,
    required String cycleId,
    required List<Map<String, dynamic>> tickets,
  }) async {
    final csvContent = '\uFEFF' + 'sep=,\n' + _buildCsv(tickets);
    final csvBase64 = base64Encode(utf8.encode(csvContent));

    final expectedGrads = tickets.where((t) => t['expected_graduate'] == true).length;
    final disabilityCases = tickets.where((t) => t['has_disability'] == true).length;

    final body = {
      'personalizations': [
        {
          'to': [
            {'email': Secrets.recipientEmail}
          ],
        }
      ],
      'from': {'email': Secrets.senderEmail},
      'subject': 'طلبات $department - $shatr - دورة $cycleId',
      'content': [
        {
          'type': 'text/plain',
          'value':
              'عدد الحالات: ${tickets.length}\n'
              'خريجون متوقعون: $expectedGrads\n'
              'ذوو إعاقة: $disabilityCases\n\n'
              'الملف المرفق يحتوي كل التفاصيل - جاهز للتحويل لمنسّق القسم.',
        }
      ],
      'attachments': [
        {
          'content': csvBase64,
          'filename': '${department}_${shatr}_$cycleId.csv',
          'type': 'text/csv',
          'disposition': 'attachment',
        }
      ],
    };

    final response = await http.post(
      Uri.parse(_sendGridUrl),
      headers: {
        'Authorization': 'Bearer ${Secrets.sendGridApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 202) {
      return true;
    } else {
      // ignore: avoid_print
      print('فشل إرسال الإيميل: ${response.statusCode} - ${response.body}');
      return false;
    }
  }
}