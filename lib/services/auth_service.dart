import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// يدير المصادقة (بريد/كلمة مرور + Google) ويزامن وثيقة المستخدم في Firestore.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static bool _googleInitialized = false;

  /// تدفّق حالة المصادقة (مسجّل / غير مسجّل).
  Stream<User?> get authState => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// تسجيل الدخول بالبريد وكلمة المرور.
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _syncUserDoc();
  }

  /// إنشاء حساب جديد بالبريد وكلمة المرور.
  Future<void> registerWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.updateDisplayName(displayName.trim());
    await _syncUserDoc(overrideName: displayName.trim());
  }

  /// تسجيل الدخول عبر حساب Google.
  Future<void> signInWithGoogle() async {
    final signIn = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await signIn.initialize();
      _googleInitialized = true;
    }

    if (!signIn.supportsAuthenticate()) {
      throw FirebaseAuthException(
        code: 'google-unsupported',
        message: 'تسجيل الدخول عبر Google غير مدعوم على هذه المنصة.',
      );
    }

    final account = await signIn.authenticate(scopeHint: const ['email']);
    final auth = account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: auth.idToken);
    await _auth.signInWithCredential(credential);
    await _syncUserDoc();
  }

  Future<void> signOut() async {
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // نتجاهل أخطاء تسجيل الخروج من Google
      }
    }
    await _auth.signOut();
  }

  /// ينشئ/يحدّث وثيقة المستخدم في مجموعة users.
  Future<void> _syncUserDoc({String? overrideName}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final displayName = overrideName ??
        user.displayName ??
        (user.email?.split('@').first ?? 'مستخدم');

    final data = {
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': displayName,
      'photoUrl': user.photoURL,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('users').doc(user.uid).set(
          data,
          SetOptions(merge: true),
        );
  }

  /// يحوّل رمز الخطأ من Firebase إلى رسالة عربية واضحة.
  static String messageFromError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'صيغة البريد الإلكتروني غير صحيحة.';
        case 'user-disabled':
          return 'تم تعطيل هذا الحساب.';
        case 'user-not-found':
        case 'invalid-credential':
          return 'بيانات الدخول غير صحيحة.';
        case 'wrong-password':
          return 'كلمة المرور غير صحيحة.';
        case 'email-already-in-use':
          return 'هذا البريد مستخدم بالفعل.';
        case 'weak-password':
          return 'كلمة المرور ضعيفة (٦ أحرف على الأقل).';
        case 'network-request-failed':
          return 'تعذّر الاتصال بالشبكة.';
        default:
          return error.message ?? 'حدث خطأ غير متوقّع.';
      }
    }
    return 'حدث خطأ غير متوقّع. حاول مرة أخرى.';
  }
}

/// نسخة مشتركة يستخدمها التطبيق.
final authService = AuthService();
