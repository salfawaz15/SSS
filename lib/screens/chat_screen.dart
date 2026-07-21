import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.peer});

  /// المستخدم الآخر في المحادثة.
  final AppUser peer;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final String _myUid;
  late final String _chatId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _myUid = authService.currentUser!.uid;
    _chatId = chatService.chatIdFor(_myUid, widget.peer.uid);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _textCtrl.clear();
    try {
      await chatService.sendMessage(
        chatId: _chatId,
        senderId: _myUid,
        participants: [_myUid, widget.peer.uid],
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال الرسالة')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              backgroundImage: widget.peer.photoUrl != null
                  ? NetworkImage(widget.peer.photoUrl!)
                  : null,
              child: widget.peer.photoUrl == null
                  ? Text(widget.peer.initials,
                      style: TextStyle(color: cs.onPrimaryContainer))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.peer.displayName,
                      style: const TextStyle(fontSize: 16)),
                  Text(widget.peer.email,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: chatService.messages(_chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'ابدأ المحادثة بإرسال رسالة 👋',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMine = msg.senderId == _myUid;
                    return _MessageBubble(message: msg, isMine: isMine);
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _textCtrl,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = message.timestamp != null
        ? DateFormat('h:mm a', 'ar').format(message.timestamp!)
        : '';

    return Align(
      alignment: isMine ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 4 : 16),
            bottomRight: Radius.circular(isMine ? 16 : 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isMine ? cs.onPrimary : cs.onSurface,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 10,
                color: (isMine ? cs.onPrimary : cs.onSurfaceVariant)
                    .withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'اكتب رسالة...',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: sending ? null : onSend,
              elevation: 0,
              child: sending
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
