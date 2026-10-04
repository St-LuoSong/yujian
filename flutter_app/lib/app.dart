import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/app_update_gate.dart';
import 'screens/home_screen.dart';

class YujianApp extends StatelessWidget {
  const YujianApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '豫见智旅',
        theme: AppTheme.light(),
        home: const AppUpdateGate(child: HomeScreen()),
      );
}
