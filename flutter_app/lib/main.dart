import 'package:flutter/material.dart';

import 'app/startup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化被搬进 YujianBootstrap：第一帧先画加载页，慢启动与失败都有交代。
  runApp(const YujianBootstrap());
}
