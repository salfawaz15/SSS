import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/message.dart';

/// يدير المحادثات والرسائل عبر Firestore.
///
/// بنية البيانات:
///   users/{uid}
///   chats/{chatId}            -> participants, lastMessage, lastMessageTime, updatedAt
///   chats/{chatId}/messages/{messageId}
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// معرّف محادثة ثابت بين مستخدمَين (مرتّب أبجديًا).
  String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  /// قائمة كل المستخدمين عدا المستخدم الحالي (لبدء محادثة جديدة).
  Stream<List<AppUser>> allUsers(String currentUid) {
    return _db.collection('users').snapshots().map((snap) {
      return snap.docs
          .map(AppUser.fromDoc)
          .where((u) => u.uid.isNotEmpty && u.uid != currentUid)
          .toList();
    });
  }

  /// جلب بيانات مستخدم واحد.
  Future<AppUser?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromDoc(doc);
  }

  /// محادثات المستخدم الحالي مرتّبة بالأحدث.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> myChats(
    String currentUid,
  ) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: currentUid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs);
  }

  /// رسائل محادثة معيّنة (تدفّق فوري).
  Stream<List<Message>> messages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Message.fromDoc).toList());
  }

  /// إرسال رسالة نصية، مع إنشاء/تحديث وثيقة المحادثة.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required List<String> participants,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final chatRef = _db.collection('chats').doc(chatId);
    final messageRef = chatRef.collection('messages').doc();

    final batch = _db.batch();
    batch.set(chatRef, {
      'participants': participants,
      'lastMessage': trimmed,
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(messageRef, {
      'senderId': senderId,
      'text': trimmed,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}

final chatService = ChatService();
