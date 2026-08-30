import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/secrets.dart';
import 'excel_export_service.dart';
import 'excel_protection_service.dart';

class MailService {
  static const String _sendGridUrl = 'https://api.sendgrid.com/v3/mail/send';

  /// يرسل ملف Excel جاهزًا (مبنيًا مسبقًا من المتصل - مثل ملف "مرحلة
  /// المنسّق" `EscalationFileService.buildStage2File`) لبريد منسّق قسم حقيقي
  /// (`FirestoreCoordinatorService`، لا حساب الدخول الداخلي الوهمي بالبوابة)
  /// - يُستخدم من لوحة إدارة الموقع (`admin_workspace_screen.dart`) عبر زر
  /// "إرسال بالبريد" بجانب زر التنزيل، بلا حاجة لإعادة بناء الملف كما تفعل
  /// [sendDepartmentReport] القديمة (مصمَّمة لتطبيق CBA Advising فقط وبعمود
  /// حالة مختلف).
  static Future<bool> sendPrebuiltAttachment({
    required String toEmail,
    String? toName,
    required String subject,
    required String bodyText,
    required Uint8List xlsxBytes,
    required String attachmentFilename,
  }) async {
    final body = {
      'personalizations': [
        {
          'to': [
            {
              'email': toEmail,
              if (toName != null && toName.isNotEmpty) 'name': toName,
            },
          ],
        },
      ],
      'from': {'email': Secrets.senderEmail},
      'subject': subject,
      'content': [
        {'type': 'text/plain', 'value': bodyText},
      ],
      'attachments': [
        {
          'content': base64Encode(xlsxBytes),
          'filename': attachmentFilename,
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
      if (response.statusCode == 202) return true;
      // ignore: avoid_print
      print('فشل إرسال الإيميل: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('خطأ أثناء إرسال الإيميل: $e');
      return false;
    }
  }

  static Future<bool> sendDepartmentReport({
    required String shatr,
    required String department,
    required String cycleId,
    required List<Map<String, dynamic>> tickets,
    required String coordinatorEmail,
    String? coordinatorName,
  }) async {
    final workbookResult = await ExcelExportService.buildDepartmentWorkbook(tickets);
    final dataRowCount = workbookResult.totalDataRowCount;
    final xlsxBytes = ExcelProtectionService.protect(
      workbookResult.bytes,
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
