import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// يسجّل خروج المستخدم تلقائيًا بعد 15 دقيقة بلا أي نشاط (نقر/تمرير/كتابة) -
/// بطلب سليمان صراحةً، لحماية حسابات مشتركة قد تُترَك مفتوحة على جهاز عام.
/// يلتقط أي حركة مؤشر بأي مكان بالصفحة (`Listener` شفّاف لا يعطّل التفاعل
/// الطبيعي) لإعادة ضبط المؤقّت، فقط أثناء وجود مستخدم مسجَّل دخوله فعليًا.
class InactivityAutoLogout extends StatefulWidget {
  final Widget child;

  const InactivityAutoLogout({super.key, required this.child});

  static const Duration timeout = Duration(minutes: 15);

  @override
  State<InactivityAutoLogout> createState() => _InactivityAutoLogoutState();
}

class _InactivityAutoLogoutState extends State<InactivityAutoLogout> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(InactivityAutoLogout.timeout, () {
      if (FirebaseAuth.instance.currentUser != null) {
        FirebaseAuth.instance.signOut();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
