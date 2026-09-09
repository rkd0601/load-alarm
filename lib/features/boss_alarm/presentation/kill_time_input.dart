import 'package:flutter/material.dart';

/// Returns a UTC instant; entered calendar values always mean Korean time.
Future<DateTime?> showKillTimeInput(BuildContext context, {int? anchorMs}) =>
    showDialog<DateTime>(
      context: context,
      builder: (_) => _KillTimeInput(anchorMs: anchorMs),
    );

class _KillTimeInput extends StatefulWidget {
  const _KillTimeInput({this.anchorMs});
  final int? anchorMs;

  @override
  State<_KillTimeInput> createState() => _KillTimeInputState();
}

class _KillTimeInputState extends State<_KillTimeInput> {
  late final TextEditingController date;
  late final TextEditingController time;
  String? error;

  @override
  void initState() {
    super.initState();
    final korea = DateTime.fromMillisecondsSinceEpoch(
      widget.anchorMs ?? DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    ).add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    date = TextEditingController(
        text:
            '${korea.year.toString().padLeft(4, '0')}-${two(korea.month)}-${two(korea.day)}');
    time = TextEditingController(
        text: '${two(korea.hour)}:${two(korea.minute)}:${two(korea.second)}');
  }

  @override
  void dispose() {
    date.dispose();
    time.dispose();
    super.dispose();
  }

  void save() {
    final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date.text.trim());
    final t = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$')
        .firstMatch(time.text.trim());
    if (d == null || t == null) {
      setState(() => error = '날짜는 YYYY-MM-DD, 시간은 HH:mm 또는 HH:mm:ss로 입력해 주세요.');
      return;
    }
    final year = int.parse(d[1]!);
    final month = int.parse(d[2]!);
    final day = int.parse(d[3]!);
    final hour = int.parse(t[1]!);
    final minute = int.parse(t[2]!);
    final second = int.parse(t[3] ?? '0');
    final entered = DateTime.utc(year, month, day, hour, minute, second);
    if (year < 1 ||
        entered.year != year ||
        entered.month != month ||
        entered.day != day ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      setState(() => error = '존재하는 날짜와 올바른 시각을 입력해 주세요.');
      return;
    }
    final utc = entered.subtract(const Duration(hours: 9));
    if (utc.isAfter(DateTime.now())) {
      setState(() => error = '처치 시간은 현재보다 미래일 수 없습니다.');
      return;
    }
    Navigator.pop(context, utc);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('처치 시간 입력'),
        content: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('실제 처치한 날짜와 시각을 입력해 주세요.\n한국 시간 · 24시간 형식'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('kill-date'),
              controller: date,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                  labelText: '처치 날짜', hintText: '2026-09-08'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('kill-time'),
              controller: time,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                  labelText: '처치 시각', hintText: '14:30 또는 14:30:25'),
              onSubmitted: (_) => save(),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: save, child: const Text('적용')),
        ],
      );
}
