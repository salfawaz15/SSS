import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myUid = authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('محادثات'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'signout') authService.signOut();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  authService.currentUser?.email ?? '',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 12),
                    Text('تسجيل الخروج'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: chatService.myChats(myUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'تعذّر تحميل المحادثات.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            );
          }
          final chats = snapshot.data ?? const [];
          if (chats.isEmpty) {
            return _EmptyState(colorScheme: cs);
          }
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
            itemBuilder: (context, index) {
              return _ChatTile(chatDoc: chats[index], myUid: myUid);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewChatScreen()),
        ),
        icon: const Icon(Icons.chat_rounded),
        label: const Text('جديدة'),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chatDoc, required this.myUid});

  final QueryDocumentSnapshot<Map<String, dynamic>> chatDoc;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = chatDoc.data();
    final participants =
        (data['participants'] as List?)?.cast<String>() ?? const [];
    final peerId = participants.firstWhere(
      (id) => id != myUid,
      orElse: () => '',
    );
    final lastMessage = data['lastMessage'] as String? ?? '';
    final ts = data['updatedAt'];
    final time = ts is Timestamp ? _formatTime(ts.toDate()) : '';

    return FutureBuilder<AppUser?>(
      future: chatService.getUser(peerId),
      builder: (context, snapshot) {
        final peer = snapshot.data;
        final name = peer?.displayName ?? '...';
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: cs.primaryContainer,
            backgroundImage: peer?.photoUrl != null
                ? NetworkImage(peer!.photoUrl!)
                : null,
            child: peer?.photoUrl == null
                ? Text(peer?.initials ?? '؟',
                    style: TextStyle(color: cs.onPrimaryContainer))
                : null,
          ),
          title: Text(name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(lastMessage,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(time,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          onTap: peer == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(peer: peer),
                    ),
                  ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final sameDay =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    return sameDay
        ? DateFormat('h:mm a', 'ar').format(dt)
        : DateFormat('d MMM', 'ar').format(dt);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined,
              size: 80, color: colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('لا توجد محادثات بعد',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'اضغط "جديدة" لبدء محادثة',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
