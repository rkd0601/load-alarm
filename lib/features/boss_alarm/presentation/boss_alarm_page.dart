import 'dart:async';
import 'package:flutter/material.dart';
import '../application/boss_controller.dart';
import '../domain/boss.dart';
import 'kill_time_input.dart';

class BossAlarmPage extends StatefulWidget {
  const BossAlarmPage({super.key, this.controller});
  final BossController? controller;
  @override
  State<BossAlarmPage> createState() => _BossAlarmPageState();
}

class _BossAlarmPageState extends State<BossAlarmPage>
    with WidgetsBindingObserver {
  late final BossController controller;
  Timer? timer;
  String search = '';
  int filter = 0;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? BossController();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    controller.initialize();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    controller.removeListener(_changed);
    // The controller may still be completing a platform call.
    super.dispose();
  }

  Future<void> _edit(Boss boss) async {
    final updated = await showDialog<Boss>(
        context: context, builder: (_) => _BossEditor(boss: boss));
    if (updated != null && mounted) await controller.change(updated);
  }

  Future<void> _inputKillTime(Boss boss) async {
    final entered = await showKillTimeInput(context, anchorMs: boss.anchorMs);
    if (entered != null && mounted) {
      await controller
          .change(boss.update(anchorMs: entered.millisecondsSinceEpoch));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final list = controller.bosses
        .where((b) =>
            (filter == 0 ||
                (filter == 1 && !b.isFixed) ||
                (filter == 2 && b.isFixed)) &&
            '${b.name} ${b.region} ${b.location}'.contains(search))
        .toList();
    list.sort((a, b) {
      final at = a.nextSpawn(now), bt = b.nextSpawn(now);
      if (at == null && bt == null) return a.id.compareTo(b.id);
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    final status = controller.status;
    return Scaffold(
      appBar: AppBar(title: const Text('로드나인 보스 알림'), actions: [
        IconButton(
            onPressed: controller.busy ? null : controller.refresh,
            tooltip: 'DB 동기화 및 알림 다시 예약',
            icon: const Icon(Icons.refresh)),
      ]),
      body: SafeArea(
          child: controller.loading
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  if (controller.error != null)
                    MaterialBanner(content: Text(controller.error!), actions: [
                      TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => controller.bosses.isEmpty
                                  ? controller.initialize()
                                  : controller.refresh(),
                          child: const Text('다시 시도')),
                    ]),
                  if (status.isNotEmpty &&
                      (status['allowed'] != true || status['exact'] != true))
                    MaterialBanner(
                        content: const Text(
                            '5분 전 알림을 받으려면 알림 및 정확한 알람 권한이 필요합니다. 기기 설정에서 허용해 주세요.'),
                        actions: [
                          TextButton(
                              onPressed: controller.busy
                                  ? null
                                  : controller.permissions,
                              child: const Text('권한 설정'))
                        ]),
                  if (status['platform'] == 'ios')
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                            status['horizonMs'] == null
                                ? 'iOS: 알림을 켜면 가까운 일정부터 최대 64건을 예약합니다. 앱을 열면 갱신됩니다.'
                                : 'iOS 예약: ${koreaTime(DateTime.fromMillisecondsSinceEpoch(status['horizonMs'] as int))} 이전까지. 그 전에 앱을 열어 예약을 갱신해 주세요.',
                            style: Theme.of(context).textTheme.bodySmall)),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('젠 5분 전 알림 · 모든 시간은 한국 시간',
                                style: Theme.of(context).textTheme.titleSmall),
                            Text(controller.cloudStatus,
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 4),
                            const Text('필드는 처치 체크부터 주기 반복 · 고정 보스는 요일 유지'),
                            const SizedBox(height: 12),
                            TextField(
                                onChanged: (v) =>
                                    setState(() => search = v.trim()),
                                decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search),
                                    hintText: '보스명 또는 지역 검색',
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              for (var i = 0; i < 3; i++)
                                ChoiceChip(
                                    label: Text(['전체 45', '필드 22', '고정 23'][i]),
                                    selected: filter == i,
                                    onSelected: (_) =>
                                        setState(() => filter = i)),
                            ]),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              FilledButton.icon(
                                onPressed:
                                    controller.busy || controller.bosses.isEmpty
                                        ? null
                                        : () => controller.setAllEnabled(true),
                                icon: const Icon(Icons.notifications_active),
                                label: const Text('전체 설정'),
                              ),
                              OutlinedButton.icon(
                                onPressed:
                                    controller.busy || controller.bosses.isEmpty
                                        ? null
                                        : () => controller.setAllEnabled(false),
                                icon: const Icon(Icons.notifications_off),
                                label: const Text('전체 해제'),
                              ),
                            ]),
                            const Text('전체 보스에 적용 · 처치 시간 미설정 필드는 설정 제외'),
                          ])),
                  if (controller.busy) const LinearProgressIndicator(),
                  Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('검색 결과가 없습니다.'))
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                final boss = list[index];
                                final spawn = boss.nextSpawn(now);
                                final alarm = boss.nextAlarm(now);
                                final remaining = spawn?.difference(now);
                                return Card(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 5),
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Expanded(
                                                    child: Text(boss.name,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium)),
                                                Switch(
                                                    value: boss.enabled,
                                                    onChanged: controller.busy
                                                        ? null
                                                        : (value) {
                                                            if (value &&
                                                                !boss.isFixed &&
                                                                boss.anchorMs ==
                                                                    null) {
                                                              _edit(boss.update(
                                                                  enabled:
                                                                      true));
                                                            } else {
                                                              controller.change(
                                                                  boss.update(
                                                                      enabled:
                                                                          value));
                                                            }
                                                          }),
                                              ]),
                                              Text(
                                                  '${boss.region} · ${boss.location}'),
                                              Text(boss.scheduleLabel),
                                              const SizedBox(height: 8),
                                              Text(spawn == null
                                                  ? '처치 시간을 설정해 주세요'
                                                  : '다음 젠 ${koreaTime(spawn)} · ${remaining!.inHours}시간 ${remaining.inMinutes % 60}분 남음'),
                                              if (!boss.isFixed &&
                                                  boss.anchorMs != null)
                                                Text(
                                                    '기준 처치 ${koreaTime(DateTime.fromMillisecondsSinceEpoch(boss.anchorMs!))}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall),
                                              if (boss.enabled && alarm != null)
                                                Text(
                                                    '예약 대상 ${koreaTime(alarm)}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall),
                                              if (boss.enabled &&
                                                  spawn != null &&
                                                  spawn
                                                          .difference(now)
                                                          .inSeconds <=
                                                      300)
                                                const Text(
                                                    '이번 젠의 5분 전 시각은 지났습니다. 다음 알림 대상은 다음 주기입니다.'),
                                              Wrap(spacing: 8, children: [
                                                if (!boss.isFixed)
                                                  TextButton.icon(
                                                      onPressed: controller.busy
                                                          ? null
                                                          : () => controller
                                                              .change(boss.update(
                                                                  anchorMs: DateTime
                                                                          .now()
                                                                      .millisecondsSinceEpoch)),
                                                      icon: const Icon(
                                                          Icons.check),
                                                      label: const Text(
                                                          '지금 처치 체크')),
                                                if (!boss.isFixed)
                                                  TextButton.icon(
                                                    onPressed: controller.busy
                                                        ? null
                                                        : () => _inputKillTime(
                                                            boss),
                                                    icon: const Icon(Icons
                                                        .edit_calendar_outlined),
                                                    label:
                                                        const Text('처치 시간 입력'),
                                                  ),
                                                TextButton.icon(
                                                    onPressed: controller.busy
                                                        ? null
                                                        : () => _edit(boss),
                                                    icon: const Icon(
                                                        Icons.edit_outlined),
                                                    label: const Text('시간 설정')),
                                                if (boss.ability.isNotEmpty ||
                                                    boss.loot.isNotEmpty)
                                                  TextButton(
                                                      onPressed: () => showDialog<
                                                              void>(
                                                          context: context,
                                                          builder: (_) => AlertDialog(
                                                                  title: Text(
                                                                      boss.name),
                                                                  content: Text(
                                                                      '안장 / 어빌\n${boss.ability.isEmpty ? '-' : boss.ability}\n\n무기 / 악세\n${boss.loot.isEmpty ? '-' : boss.loot}'),
                                                                  actions: [
                                                                    TextButton(
                                                                        onPressed: () =>
                                                                            Navigator.pop(
                                                                                context),
                                                                        child: const Text(
                                                                            '닫기'))
                                                                  ])),
                                                      child:
                                                          const Text('드롭 정보')),
                                              ]),
                                            ])));
                              })),
                ])),
    );
  }
}

class _BossEditor extends StatefulWidget {
  const _BossEditor({required this.boss});
  final Boss boss;
  @override
  State<_BossEditor> createState() => _BossEditorState();
}

class _BossEditorState extends State<_BossEditor> {
  late final TextEditingController hours;
  late final TextEditingController minutes;
  late DateTime anchor;
  late Set<int> days;
  late TimeOfDay fixedTime;
  late bool enabled;
  String? error;

  @override
  void initState() {
    super.initState();
    final b = widget.boss;
    hours = TextEditingController(text: '${b.intervalMinutes ~/ 60}');
    minutes = TextEditingController(text: '${b.intervalMinutes % 60}');
    anchor = DateTime.fromMillisecondsSinceEpoch(
        b.anchorMs ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true);
    days = b.weekdays.toSet();
    fixedTime =
        TimeOfDay(hour: b.minuteOfDay ~/ 60, minute: b.minuteOfDay % 60);
    enabled = b.enabled;
  }

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  Future<void> pickAnchor() async {
    final entered = await showKillTimeInput(context,
        anchorMs: anchor.millisecondsSinceEpoch);
    if (entered != null && mounted) {
      setState(() => anchor = entered);
    }
  }

  void save() {
    final b = widget.boss;
    if (b.isFixed) {
      if (days.isEmpty) {
        setState(() => error = '요일을 하나 이상 선택해 주세요.');
        return;
      }
      Navigator.pop(
          context,
          b.update(
              enabled: enabled,
              weekdays: days.toList()..sort(),
              minuteOfDay: fixedTime.hour * 60 + fixedTime.minute));
    } else {
      final h = int.tryParse(hours.text), m = int.tryParse(minutes.text);
      if (h == null ||
          m == null ||
          h < 0 ||
          m < 0 ||
          m > 59 ||
          h * 60 + m <= 5 ||
          h > 8760) {
        setState(() => error = '주기는 5분 초과, 8760시간 이하로 입력해 주세요. 분은 0~59입니다.');
        return;
      }
      if (anchor.isAfter(DateTime.now())) {
        setState(() => error = '처치 시간은 현재보다 미래일 수 없습니다.');
        return;
      }
      Navigator.pop(
          context,
          b.update(
              enabled: enabled,
              intervalMinutes: h * 60 + m,
              anchorMs: anchor.millisecondsSinceEpoch));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.boss.name} 시간 설정'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.boss.isFixed) ...[
            const Text('고정 젠 요일 · 한국 시간'),
            Wrap(spacing: 4, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                    label: Text(['월', '화', '수', '목', '금', '토', '일'][d - 1]),
                    selected: days.contains(d),
                    onSelected: (value) => setState(() {
                          if (value) {
                            days.add(d);
                          } else {
                            days.remove(d);
                          }
                        })),
            ]),
            TextButton(
                onPressed: () async {
                  final value = await showTimePicker(
                      context: context, initialTime: fixedTime);
                  if (value != null && mounted) {
                    setState(() => fixedTime = value);
                  }
                },
                child: Text(
                    '젠 시간 ${fixedTime.hour.toString().padLeft(2, '0')}:${fixedTime.minute.toString().padLeft(2, '0')}')),
          ] else ...[
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: hours,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: '젠 주기 (시간)'))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '분'))),
            ]),
            const SizedBox(height: 12),
            TextButton(
                onPressed: pickAnchor,
                child: Text('기준 처치 ${koreaTime(anchor)} 수정')),
            const Text('체크하지 않으면 이 시각을 기준으로 젠 주기만큼 자동 연장됩니다.'),
          ],
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('5분 전 알림'),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value)),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: save, child: const Text('저장')),
        ],
      );
}
