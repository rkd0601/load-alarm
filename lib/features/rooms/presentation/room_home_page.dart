import 'package:flutter/material.dart';

import '../../../core/services/boss_cloud_store.dart';
import '../../boss_alarm/application/boss_controller.dart';
import '../../boss_alarm/presentation/boss_alarm_page.dart';
import '../application/room_service.dart';
import '../domain/room.dart';
import '../domain/room_member.dart';

class RoomHomePage extends StatelessWidget {
  const RoomHomePage({super.key, required this.room, required this.service});

  final BossRoom room;
  final RoomService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RoomMember?>(
      stream: service.myMember(room.id),
      builder: (context, snapshot) {
        final member = snapshot.data;
        final canEdit = member?.canEditSettings ??
            room.ownerUid == service.currentUser?.uid;
        final isOwner =
            member?.isOwner ?? room.ownerUid == service.currentUser?.uid;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name),
                  Text(room.serverLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              actions: [
                if (isOwner)
                  IconButton(
                    tooltip: '방 권한 관리',
                    icon: const Icon(Icons.manage_accounts),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _RoomMembersDialog(
                        room: room,
                        service: service,
                      ),
                    ),
                  ),
              ],
              bottom: const TabBar(tabs: [
                Tab(icon: Icon(Icons.notifications), text: '보스 알림'),
                Tab(icon: Icon(Icons.chat_bubble_outline), text: '채팅'),
              ]),
            ),
            body: TabBarView(
              children: [
                BossAlarmPage(
                  key: ValueKey('boss-${room.id}-$canEdit'),
                  embedded: true,
                  controller: BossController(
                    shareEnabled: true,
                    canEditSharedSettings: canEdit,
                    cloud: FirestoreBossCloudStore(roomId: room.id),
                  ),
                ),
                _RoomChat(room: room, service: service),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoomMembersDialog extends StatelessWidget {
  const _RoomMembersDialog({required this.room, required this.service});

  final BossRoom room;
  final RoomService service;

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return '방장';
      case 'editor':
        return '설정 편집자';
      default:
        return '방원';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('방 권한 관리'),
      content: SizedBox(
        width: 420,
        child: StreamBuilder<List<RoomMember>>(
          stream: service.members(room.id),
          builder: (context, snapshot) {
            final members = snapshot.data ?? const <RoomMember>[];
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (members.isEmpty) return const Text('참여한 방원이 없습니다.');
            return ListView.separated(
              shrinkWrap: true,
              itemCount: members.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final member = members[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.displayName),
                  subtitle: Text(_roleLabel(member.role)),
                  trailing: member.isOwner
                      ? const Chip(label: Text('방장'))
                      : PopupMenuButton<String>(
                          onSelected: (value) async {
                            try {
                              if (value == 'owner') {
                                await service.transferOwner(
                                    room.id, member.uid);
                              } else {
                                await service.setMemberRole(
                                    room.id, member.uid, value);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$e')));
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'editor',
                              child: Text('설정 편집자 부여'),
                            ),
                            PopupMenuItem(
                              value: 'member',
                              child: Text('일반 방원으로 변경'),
                            ),
                            PopupMenuItem(
                              value: 'owner',
                              child: Text('방장 임명'),
                            ),
                          ],
                        ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
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
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
