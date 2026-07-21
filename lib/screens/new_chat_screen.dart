import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myUid = authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('محادثة جديدة')),
      body: StreamBuilder<List<AppUser>>(
        stream: chatService.allUsers(myUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data ?? const [];
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'لا يوجد مستخدمون آخرون بعد.\nادعُ صديقًا لإنشاء حساب وابدأ المحادثة!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(user.initials,
                          style: TextStyle(color: cs.onPrimaryContainer))
                      : null,
                ),
                title: Text(user.displayName),
                subtitle: Text(user.email),
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(peer: user),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
