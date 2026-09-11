import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Returns a UTC instant; entered calendar values always mean Korean time.
Future<DateTime?> showKillTimeInput(BuildContext context,
        {int? anchorMs, bool resetAll = false}) =>
    showDialog<DateTime>(
      context: context,
      builder: (_) => _WebKeyboardStableDialog(
        child: _KillTimeInput(anchorMs: anchorMs, resetAll: resetAll),
      ),
    );

class _WebKeyboardStableDialog extends StatelessWidget {
  const _WebKeyboardStableDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
      child: child,
    );
  }
}

class _KillTimeInput extends StatefulWidget {
  const _KillTimeInput({this.anchorMs, this.resetAll = false});
  final bool resetAll;
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
      setState(() => error = widget.resetAll
          ? '리셋 기준 시간은 현재보다 미래일 수 없습니다.'
          : '처치 시간은 현재보다 미래일 수 없습니다.');
      return;
    }
    Navigator.pop(context, utc);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.resetAll ? '전체 시간 리셋' : '처치 시간 입력'),
        content: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.resetAll
                ? '공통 DB의 모든 필드 보스 처치 기준을 변경합니다.\n다른 사용자에게도 적용됩니다.\n다음 젠은 기준 시간 + 보스별 주기로 계산합니다.\n고정 보스 일정과 알림 선택은 유지됩니다.\n한국 시간 · 24시간 형식'
                : '실제 처치한 날짜와 시각을 입력해 주세요.\n한국 시간 · 24시간 형식'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('kill-date'),
              scrollPadding: EdgeInsets.zero,
              controller: date,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                  labelText: widget.resetAll ? '리셋 기준 날짜' : '처치 날짜',
                  hintText: '2026-09-08'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('kill-time'),
              scrollPadding: EdgeInsets.zero,
              controller: time,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                  labelText: widget.resetAll ? '리셋 기준 시각' : '처치 시각',
                  hintText: '14:30 또는 14:30:25'),
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
