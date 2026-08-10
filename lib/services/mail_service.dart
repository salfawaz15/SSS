import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/secrets.dart';
import 'excel_export_service.dart';
import 'excel_protection_service.dart';

class MailService {
  static const String _sendGridUrl = 'https://api.sendgrid.com/v3/mail/send';

  static Future<bool> sendDepartmentReport({
    required String shatr,
    required String department,
    required String cycleId,
    required List<Map<String, dynamic>> tickets,
    required String coordinatorEmail,
    String? coordinatorName,
  }) async {
    final rawXlsxBytes = ExcelExportService.buildDepartmentWorkbook(tickets);
    final dataRowCount = tickets.fold<int>(0, (sum, t) {
      final actions = (t['actions'] as List?) ?? [];
      return sum + (actions.isEmpty ? 1 : actions.length);
    });
    final xlsxBytes = ExcelProtectionService.protect(
      rawXlsxBytes,
      dropdowns: [
        DropdownColumn(
          columnIndex: ExcelExportService.coordinatorStatusColumnIndex,
          options: ExcelProtectionService.statusOptions,
        ),
      ],
      unlockedColumnIndexes: [
        ExcelExportService.coordinatorStatusColumnIndex,
        ExcelExportService.coordinatorNotesColumnIndex,
      ],
      dataRowCount: dataRowCount,
    );
    final xlsxBase64 = base64Encode(xlsxBytes);

    final expectedGrads = tickets
        .where((t) => t['expected_graduate'] == true)
        .length;
    final disabilityCases = tickets
        .where((t) => t['has_disability'] == true)
        .length;

    final body = {
      'personalizations': [
        {
          'to': [
            {
              'email': coordinatorEmail,
              if (coordinatorName != null && coordinatorName.isNotEmpty)
                'name': coordinatorName,
            },
          ],
        },
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
        },
      ],
      'attachments': [
        {
          'content': xlsxBase64,
          'filename': '${department}_${shatr}_$cycleId.xlsx',
          'type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'disposition': 'attachment',
        },
      ],
    };

    try {
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
    } catch (e) {
      // ignore: avoid_print
      print('خطأ أثناء إرسال الإيميل: $e');
      return false;
    }
  }
}
