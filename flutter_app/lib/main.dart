import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app/bootstrap.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await AppBootstrap.create();
  runApp(
    ProviderScope(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
      child: const YujianApp(),
    ),
  );
}
