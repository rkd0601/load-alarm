import 'package:flutter/material.dart';

import '../../../core/services/boss_cloud_store.dart';
import '../../boss_alarm/application/boss_controller.dart';
import '../../boss_alarm/presentation/boss_alarm_page.dart';
import '../application/room_service.dart';
import '../domain/room.dart';

class RoomHomePage extends StatelessWidget {
  const RoomHomePage({super.key, required this.room, required this.service});

  final BossRoom room;
  final RoomService service;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.name),
              Text(room.serverLabel,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.notifications), text: '보스 알림'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: '채팅'),
          ]),
        ),
        body: TabBarView(
          children: [
            BossAlarmPage(
              embedded: true,
              controller: BossController(
                shareEnabled: true,
                cloud: FirestoreBossCloudStore(roomId: room.id),
              ),
            ),
            _RoomChat(room: room, service: service),
          ],
        ),
      ),
    );
  }
}

class _RoomChat extends StatefulWidget {
  const _RoomChat({required this.room, required this.service});

  final BossRoom room;
  final RoomService service;

  @override
  State<_RoomChat> createState() => _RoomChatState();
}

class _RoomChatState extends State<_RoomChat> {
  final input = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.service.sendMessage(widget.room.id, input.text);
      input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.service.currentUser;
    return Column(
      children: [
        Expanded(
          child: StreamBuilder(
            stream: widget.service.messages(widget.room.id),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? const [];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (docs.isEmpty) {
                return const Center(child: Text('아직 메시지가 없습니다.'));
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final mine = data['uid'] == user?.uid;
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Card(
                        color: mine
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['displayName'] as String? ?? '사용자',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(data['text'] as String? ?? ''),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: '메시지 입력',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? null : send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
