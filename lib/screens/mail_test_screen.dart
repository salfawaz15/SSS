import 'package:flutter/material.dart';
import '../services/mail_service.dart';

class MailTestScreen extends StatefulWidget {
  const MailTestScreen({super.key});

  @override
  State<MailTestScreen> createState() => _MailTestScreenState();
}

class _MailTestScreenState extends State<MailTestScreen> {
  String _status = 'اضغط الزر للاختبار';
  bool _sending = false;

  Future<void> _testSend() async {
    setState(() {
      _sending = true;
      _status = 'جاري الإرسال...';
    });

    final success = await MailService.sendDepartmentReport(
      
      shatr: 'شطر الطلاب',
      department: 'قسم اختبار',
      cycleId: 'test_cycle',
      tickets: [
        {
          'name': 'سلطان الاختباري',
   'university_id': '',
          'shatr': 'شطر الطلاب',
          'department': 'قسم اختبار',
          'advisor': 'مرشد تجريبي',
          'phone': '0500000000',
          'expected_graduate': true,
          'has_disability': false,
          'actions': [
            {
              'action_type': 'إضافة شعبة',
              'course': 'مقرر تجريبي',
              'required_section': '101',
              'reason': 'اختبار النظام',
            }
          ],
        }
      ],
    );

    setState(() {
      _sending = false;
      _status = success ? 'نجح الإرسال ✅ تحقق من بريدك' : 'فشل الإرسال ❌';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار الإرسال')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _sending ? null : _testSend,
              child: const Text('إرسال إيميل تجريبي'),
            ),
          ],
        ),
      ),
    );
  }
}