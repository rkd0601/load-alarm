import 'package:flutter/material.dart';

import '../application/room_service.dart';
import '../domain/app_popup.dart';
import '../domain/game_server.dart';
import '../domain/room.dart';
import 'room_home_page.dart';

class RoomLobbyPage extends StatefulWidget {
  const RoomLobbyPage({super.key, required this.service});

  final RoomService service;

  @override
  State<RoomLobbyPage> createState() => _RoomLobbyPageState();
}

class _RoomLobbyPageState extends State<RoomLobbyPage> {
  static final Set<String> _shownPopupVersions = <String>{};
  String search = '';

  RoomService get service => widget.service;

  Future<void> _create(BuildContext context) async {
    final room = await showDialog<BossRoom>(
      context: context,
      builder: (_) => _CreateRoomDialog(service: service),
    );
    if (room != null && context.mounted) {
      _openRoom(context, room);
    }
  }

  Future<void> _join(BuildContext context, BossRoom room) async {
    final password = room.hasPassword
        ? await showDialog<String>(
            context: context,
            builder: (_) => const _PasswordDialog(),
          )
        : '';
    if (password == null) return;
    try {
      await service.joinRoom(room, password);
      if (context.mounted) _openRoom(context, room);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _openRoom(BuildContext context, BossRoom room) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RoomHomePage(room: room, service: service),
    ));
  }

  List<BossRoom> _filterRooms(List<BossRoom> rooms) {
    final keyword = search.trim();
    if (keyword.isEmpty) return rooms;
    return rooms
        .where((room) => '${room.name} ${room.serverLabel}'.contains(keyword))
        .toList();
  }

  void _maybeShowPopup(BuildContext context, AppPopup? popup) {
    if (popup == null || _shownPopupVersions.contains(popup.version)) return;
    _shownPopupVersions.add(popup.version);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(popup.title),
          content: Text(popup.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = service.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('방 선택'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: service.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('방 만들기'),
      ),
      body: StreamBuilder(
        stream: service.activePopup(),
        builder: (context, popupSnapshot) {
          _maybeShowPopup(context, popupSnapshot.data);
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  user?.displayName?.isNotEmpty == true
                      ? '${user!.displayName}님'
                      : user?.email ?? '',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) => setState(() => search = value),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: '방 이름 또는 서버 검색',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('참여한 방', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                StreamBuilder<List<BossRoom>>(
                  stream: service.myRooms(),
                  builder: (context, snapshot) {
                    final rooms = _filterRooms(snapshot.data ?? const []);
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (rooms.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('아직 참여한 방이 없습니다.'),
                      );
                    }
                    return Column(
                      children: rooms
                          .map((room) => _RoomTile(
                                room: room,
                                joined: true,
                                onTap: () => _openRoom(context, room),
                              ))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('전체 방', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                StreamBuilder<List<BossRoom>>(
                  stream: service.rooms(),
                  builder: (context, snapshot) {
                    final rooms = _filterRooms(snapshot.data ?? const []);
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (rooms.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('생성된 방이 없습니다.'),
                      );
                    }
                    return Column(
                      children: rooms
                          .map((room) => _RoomTile(
                                room: room,
                                joined: false,
                                onTap: () => _join(context, room),
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.joined,
    required this.onTap,
  });

  final BossRoom room;
  final bool joined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(room.hasPassword ? Icons.lock : Icons.meeting_room),
        title: Text(room.name),
        subtitle: Text(room.serverLabel),
        trailing: Text(joined ? '입장' : '참여'),
        onTap: onTap,
      ),
    );
  }
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({required this.service});

  final RoomService service;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final name = TextEditingController();
  final password = TextEditingController();
  GameWorld world = gameWorlds.first;
  int serverNo = 1;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> create() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final room = await widget.service.createRoom(
        name: name.text,
        server: GameServer(world: world, number: serverNo),
        password: password.text,
      );
      if (mounted) Navigator.pop(context, room);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('방 만들기'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '방 이름'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<GameWorld>(
              value: world,
              decoration: const InputDecoration(labelText: '월드'),
              items: gameWorlds
                  .map((w) => DropdownMenuItem(value: w, child: Text(w.name)))
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                        world = value ?? gameWorlds.first;
                        serverNo = 1;
                      }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: serverNo,
              decoration: const InputDecoration(labelText: '서버'),
              items: [
                for (var n = 1; n <= 10; n++)
                  DropdownMenuItem(
                    value: n,
                    child: Text('${n.toString().padLeft(2, '0')} 서버'),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => serverNo = value ?? 1),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '방 비밀번호',
                helperText: '비워두면 공개 방으로 생성됩니다.',
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: busy ? null : create,
          child: const Text('생성'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final password = TextEditingController();

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('방 비밀번호'),
      content: TextField(
        controller: password,
        obscureText: true,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: const InputDecoration(labelText: '비밀번호'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, password.text),
          child: const Text('입장'),
        ),
      ],
    );
  }
}
