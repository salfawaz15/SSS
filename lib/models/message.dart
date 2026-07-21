import 'package:cloud_firestore/cloud_firestore.dart';

/// رسالة واحدة داخل محادثة.
class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime? timestamp;

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final ts = data['timestamp'];
    return Message(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      };
}
