import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

/// يمثّل مستخدمًا مسجّلًا في التطبيق (وثيقة في مجموعة users).
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'مستخدم',
      photoUrl: map['photoUrl'] as String?,
    );
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromMap(doc.data() ?? const {});
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
      };

  /// أول حرف من الاسم لعرضه في الصورة الرمزية عند غياب الصورة.
  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '؟';
    return name.characters.first;
  }
}
