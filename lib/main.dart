import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/firebase_app_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureFirebaseInitialized();
  runApp(const LordnineBossAlarmApp());
}
