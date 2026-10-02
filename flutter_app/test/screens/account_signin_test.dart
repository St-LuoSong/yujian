import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/app/session_providers.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/models/account_models.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/data/repositories/account_repository.dart';
import 'package:yujian_travel/screens/account_screen.dart';

import '../support/test_http.dart';

/// 登录页是历次真机反馈里反复出问题的地方，但它此前一条组件测试都没有：
/// 仓库层测过"登录只发一次请求"，却没人测过"页面到底有没有关掉、会话到底
/// 有没有切过去、迟到的旧会话会不会把新登录冲掉"。这里补上的正是这一段。
///
/// 这里**不用 pumpAndSettle**：登录成功后页面上总还挂着会自己重绘的东西
/// （SnackBar、路由动画、输入框光标），pumpAndSettle 会一直等"没有待处理帧"，
/// 于是整条用例表现为"卡住不动、连超时都不报"。改成推动固定帧数：
/// 时间轴明确、失败时能看到断言，而不是靠框架自己收敛。
Future<void> pushFrames(
  WidgetTester tester, {
  int frames = 24,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (int index = 0; index < frames; index++) {
    await tester.pump(step);
  }
}

void main() {
  Future<void> openAccount(WidgetTester tester) async {
    await tester.tap(find.text('打开登录'));
    await pushFrames(tester);
  }

  Future<void> submitSignIn(WidgetTester tester) async {
    await openAccount(tester);
    await tester.enterText(find.byType(TextField).first, 'traveler');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await pushFrames(tester);
  }

  testWidgets('登录成功后登录页关闭，会话切到该账号', (WidgetTester tester) async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    final adapter = RecordingAdapter((options, _) async {
      if (options.path == '/auth/login') {
        return jsonBody(authJson);
      }
      if (options.path == '/favorites') {
        return jsonBody(<Object>[
          <String, Object>{
            'id': 'f1',
            'poiId': 'longmen',
            'poiName': '龙门石窟',
          },
        ]);
      }
      throw StateError('unexpected request ${options.path}');
    });
    final container = ProviderContainer(overrides: <Override>[
      accountRepositoryProvider.overrideWithValue(
        AccountRepository(
          client: ApiClient(dioWith(adapter)),
          session: session,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostPage()),
      ),
    );
    await pushFrames(tester);
    await submitSignIn(tester);

    expect(find.text('打开登录'), findsOneWidget, reason: '登录成功后应该退出登录页');
    expect(find.textContaining('登录没有完成'), findsNothing);
    expect(container.read(sessionProvider).valueOrNull?.username, 'traveler');

    // 收藏是跟账号走的：登录后它必须自己跟着会话重建，而不是靠登录回调去
    // 反向 invalidate（那会触发 Riverpod 的循环依赖断言，正是登录假死的原因）。
    container.listen<AsyncValue<List<FavoriteItem>>>(
      favoritesProvider,
      (_, __) {},
    );
    await pushFrames(tester, frames: 8);
    expect(container.read(favoritesProvider).valueOrNull?.single.poiName, '龙门石窟');
    expect(
      adapter.requests.map((RequestOptions request) => request.path),
      contains('/favorites'),
    );

    // 凭据落盘：SessionStore 走的是平台 keystore，测试里换成内存实现，
    // 但读一次仍是真异步 —— 必须放在 runAsync 里，否则它会被 widget 测试的
    // 假时钟挂住（这正是本条用例之前"卡住不动"的原因）。
    final snapshot = await tester.runAsync(session.read);
    expect(snapshot?.hasUser, isTrue);
  });

  testWidgets('注册成功后同样直接进入登录态', (WidgetTester tester) async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    final adapter = RecordingAdapter((options, _) async {
      if (options.path == '/auth/register') {
        return jsonBody(authJson);
      }
      throw StateError('unexpected request ${options.path}');
    });
    final container = ProviderContainer(overrides: <Override>[
      accountRepositoryProvider.overrideWithValue(
        AccountRepository(
          client: ApiClient(dioWith(adapter)),
          session: session,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostPage()),
      ),
    );
    await pushFrames(tester);
    await openAccount(tester);
    await tester.tap(find.text('注册'));
    await pushFrames(tester);
    await tester.enterText(find.byType(TextField).at(0), 'traveler');
    await tester.enterText(find.byType(TextField).at(1), 'traveler@example.test');
    await tester.enterText(find.byType(TextField).at(2), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, '注册并登录'));
    await pushFrames(tester);

    expect(find.text('打开登录'), findsOneWidget, reason: '注册成功也应该退出登录页');
    expect(find.textContaining('登录没有完成'), findsNothing);
    expect(container.read(sessionProvider).valueOrNull?.username, 'traveler');
  });

  testWidgets('旧会话迟到的 401 不会把刚登录的账号冲掉', (WidgetTester tester) async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    // 旧的、已经失效的凭据：应用启动时会拿它去问 /auth/me。
    await session.saveUserSession(accessToken: 'stale', refreshToken: 'stale-r');

    final gate = Completer<void>();
    final adapter = RecordingAdapter((options, _) async {
      if (options.path == '/auth/me') {
        // 这次校验故意拖到用户登录之后才回答。
        await gate.future;
        return jsonBody(
          <String, Object>{'code': 'AUTH_REQUIRED', 'message': '请先登录'},
          status: 401,
        );
      }
      if (options.path == '/auth/login') {
        return jsonBody(authJson);
      }
      throw StateError('unexpected request ${options.path}');
    });
    final container = ProviderContainer(overrides: <Override>[
      accountRepositoryProvider.overrideWithValue(
        AccountRepository(
          client: ApiClient(dioWith(adapter)),
          session: session,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    // 读完就触发 restore()，它会挂在 /auth/me 上。
    container.read(sessionProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostPage()),
      ),
    );
    await pushFrames(tester, frames: 4);

    await submitSignIn(tester);
    expect(container.read(sessionProvider).valueOrNull?.username, 'traveler');

    // 现在那份过期会话的校验才返回 401。
    gate.complete();
    await pushFrames(tester);

    expect(
      container.read(sessionProvider).valueOrNull?.username,
      'traveler',
      reason: '迟到的旧会话校验不能把刚登录的账号覆盖成未登录',
    );
    final snapshot = await tester.runAsync(session.read);
    expect(snapshot?.accessToken, 'access-1');
  });
}

/// 一个最小宿主页：登录页是被 push 出来的，只有真的 push 过，
/// "登录成功有没有关掉页面"才是可断言的行为。
class HostPage extends StatelessWidget {
  const HostPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext context) => FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
              ),
              child: const Text('打开登录'),
            ),
          ),
        ),
      );
}

final Map<String, Object> authJson = <String, Object>{
  'accessToken': 'access-1',
  'refreshToken': 'refresh-1',
  'expiresIn': 7200,
  'user': <String, Object>{
    'id': 'u1',
    'username': 'traveler',
    'email': 'traveler@example.test',
    'emailVerified': false,
    'roles': <String>['USER'],
  },
};