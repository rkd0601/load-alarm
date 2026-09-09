import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/boss_alarm/presentation/boss_alarm_page.dart';

class LordnineBossAlarmApp extends StatelessWidget {
  const LordnineBossAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '로드나인 보스 알림',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const BossAlarmPage(),
    );
  }
}
