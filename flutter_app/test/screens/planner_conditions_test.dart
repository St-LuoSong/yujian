import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/config/app_config.dart';
import 'package:yujian_travel/core/formatters/chinese_date.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/storage/session_store.dart';

import '../support/test_http.dart';

/// 规划表单的行为回归。
///
/// 这一组用例盯的是本轮改掉的七个具体问题：英文日期弹层、选中胶囊文字被底色吃掉、
/// 同行人数占两行、无样式的下拉列表、可拖拉的天数、出发地/目的地不能换也不能搜索、
/// 历史行程只留最近一份。每一条都写成可以直接看见的断言，
/// 而不是只检查组件存在。
void main() {
  group('中文日期口径', () {
    test('同一天在日历、表单和列表里只有一种写法', () {
      expect(formatChineseDate(DateTime(2026, 10, 3)), '2026年10月3日 周六');
      expect(formatChineseDateCompact(DateTime(2026, 10, 3)), '10月3日 周六');
      expect(chineseWeekday(DateTime(2026, 10, 4)), '周日');
      expect(formatChineseMonth(DateTime(2026, 10, 1)), '2026年10月');
    });

    test('相对日只在三天内给标签，超出返回 null', () {
      final DateTime now = DateTime(2026, 10, 2, 9, 5);
      expect(relativeDayLabel(DateTime(2026, 10, 2), now: now), '今天');
      expect(relativeDayLabel(DateTime(2026, 10, 3), now: now), '明天');
      expect(relativeDayLabel(DateTime(2026, 10, 4), now: now), '后天');
      expect(relativeDayLabel(DateTime(2026, 10, 5), now: now), isNull);
    });

    test('时间戳按设备本地时区展示，不会把 UTC 直接显示出来', () {
      final DateTime utc = DateTime.utc(2026, 10, 2, 13, 30);
      final DateTime local = utc.toLocal();
      String two(int part) => part.toString().padLeft(2, '0');
      expect(
        formatChineseTimestamp(utc, now: local),
        '今天 ${two(local.hour)}:${two(local.minute)}',
      );
      expect(formatChineseTimestamp(null), '时间未知');
    });

    test('昨天用一个词说完，不再重复年份', () {
      final DateTime now = DateTime(2026, 10, 2, 21, 0);
      expect(
        formatChineseTimestamp(DateTime(2026, 10, 1, 8, 5), now: now),
        '昨天 08:05',
      );
      expect(
        formatChineseTimestamp(DateTime(2026, 9, 20, 8, 5), now: now),
        '9月20日 08:05',
      );
      expect(
        formatChineseTimestamp(DateTime(2025, 12, 31, 8, 5), now: now),
        '2025年12月31日 08:05',
      );
    });
  });

  group('出行条件表单', () {
    testWidgets('同行人数在同一行，成人左侧、儿童右侧', (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(360, 800));
      await tester.ensureVisible(find.text('同行人数'));
      await tester.pumpAndSettle();

      final Offset adults = tester.getCenter(find.text('成人'));
      final Offset children = tester.getCenter(find.text('儿童'));
      expect(adults.dy, closeTo(children.dy, 0.6));
      expect(adults.dx, lessThan(children.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('行程天数是可输入的步进控件，超出范围当场夹回',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(390, 844));
      await tester.ensureVisible(find.text('行程天数'));
      await tester.pumpAndSettle();

      final Finder stepper = find.byKey(const Key('planner-days-stepper'));
      final Finder input = find.byKey(const Key('planner-days-input'));
      expect(input, findsOneWidget);
      expect(find.descendant(of: stepper, matching: find.byType(Slider)),
          findsNothing);

      // 默认两天，点一次加号变三天。
      await tester.tap(find.descendant(of: stepper, matching: find.byIcon(Icons.add)));
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, '3');

      // 键盘输入超过上限 7 时立刻夹回，并把框里的字一起改掉。
      await tester.enterText(input, '9');
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, '7');

      // 下限是 1，不会出现 0 天。
      await tester.enterText(input, '0');
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('兴趣与体力各有自定义入口，添加后不破坏布局',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(360, 800));
      await tester.ensureVisible(find.text('兴趣偏好'));
      await tester.pumpAndSettle();

      // 两组各有一个自定义胶囊。
      expect(find.text('自定义'), findsNWidgets(2));

      await tester.tap(find.text('自定义').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-input-兴趣偏好')),
        '摄影',
      );
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      // 新值以选中胶囊出现，输入行收起，没有溢出。
      expect(find.text('摄影'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('custom-input-兴趣偏好')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('交通方式展开后有样式的候选项，选中结果回填到收起态',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(390, 844));
      final Finder field = find.byKey(const Key('planner-transport-field'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('交通方式'), findsWidgets);
      expect(find.text('城际坐高铁，市内以打车为主'), findsOneWidget);

      await tester.tap(find.text('自驾'));
      await tester.pumpAndSettle();
      expect(find.text('全程自驾，适合山水类目的地'), findsNothing);
      expect(
        find.descendant(of: field, matching: find.text('自驾')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('出行日期弹层是全中文的，且带快捷入口',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(360, 800));
      final Finder field = find.byKey(const Key('planner-date-field'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      await tester.tap(field);
      await tester.pumpAndSettle();

      expect(find.text('选择出行日期'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('明天'), findsOneWidget);
      expect(find.text('后天'), findsOneWidget);
      // 「下周六」和「明天」落在同一天时会被合并成一个入口（周五就是这么一天），
      // 所以这里断言的是「不重复」，而不是「一定有四个」。
      expect(
        find.text('下周六'),
        _isNextSaturdayDistinct() ? findsOneWidget : findsNothing,
      );
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
      // 之前弹出来的是 Material 的英文日历，这两个词就是那个版本的特征。
      expect(find.textContaining('Cancel'), findsNothing);
      expect(find.textContaining('OK'), findsNothing);

      await tester.tap(find.text('明天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      final String expected = formatChineseDateCompact(
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(
        find.descendant(of: field, matching: find.text(expected)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('中间的环形箭头真的把出发地与目的地对调',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(390, 844));
      final Finder swap = find.byIcon(Icons.sync);
      await tester.ensureVisible(swap);
      await tester.pumpAndSettle();

      // 交换前：郑州在左、洛阳在右。
      expect(
        tester.getCenter(find.text('郑州')).dx,
        lessThan(tester.getCenter(find.text('洛阳')).dx),
      );

      await tester.tap(swap);
      await tester.pumpAndSettle();

      // 交换后：两侧的值互换了位置，不是只换了一个显示文案。
      expect(
        tester.getCenter(find.text('郑州')).dx,
        greaterThan(tester.getCenter(find.text('洛阳')).dx),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('交换之后两边城市名仍留在裁剪框里，不会被滑出可视区',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(390, 844));
      final Finder swap = find.byIcon(Icons.sync);
      await tester.ensureVisible(swap);
      await tester.pumpAndSettle();
      await tester.tap(swap);
      await tester.pumpAndSettle();

      for (final String city in <String>['郑州', '洛阳']) {
        final Finder text = find.text(city);
        expect(text, findsOneWidget);
        final Rect clip = tester.getRect(
          find.ancestor(of: text, matching: find.byType(ClipRect)).first,
        );
        final Rect painted = tester.getRect(text);
        // 滑动动画必须已经归位：文字整块留在裁剪框里。
        // 上一版用 FractionalTranslation 算位移，位移只按建树那一帧的
        // animation.value 算了一次（新值恰好建在 0 那一帧），于是文字被永久
        // 推到裁剪框外 —— 屏幕上就是「交换后两边城市名一起不见了」。
        expect(
          painted.left >= clip.left - 0.5 && painted.right <= clip.right + 0.5,
          isTrue,
          reason: '$city 被滑出了可视区：文字 $painted，裁剪框 $clip',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('出发地选成和目的地同一个城市时，两边直接对调',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(390, 844));
      await tester.tap(find.text('郑州'));
      await tester.pumpAndSettle();

      // 必须在弹层里点，不能让 finder 命中后面那张表单上的「洛阳」。
      // 「洛阳」在热门推荐和河南省内各出现一次，取第一个（热门推荐）。
      final Finder sheet = find.byType(BottomSheet);
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('洛阳')).first,
      );
      await tester.pumpAndSettle();

      // 结果不是「洛阳 → 洛阳」，而是两个城市整体反了过来。
      expect(find.text('郑州'), findsOneWidget);
      expect(find.text('洛阳'), findsOneWidget);
      expect(
        tester.getCenter(find.text('洛阳')).dx,
        lessThan(tester.getCenter(find.text('郑州')).dx),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('城市选择器可以搜索，也可以直接用输入的城市',
        (WidgetTester tester) async {
      await _pumpPlanner(tester, const Size(390, 844));
      await tester.tap(find.text('郑州'));
      await tester.pumpAndSettle();

      expect(find.text('选择出发地'), findsOneWidget);
      expect(find.text('热门推荐'), findsOneWidget);
      expect(find.text('河南省内'), findsOneWidget);
      expect(find.text('省外热门'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '输入城市或地区'), '深圳北');
      await tester.pumpAndSettle();
      expect(find.text('使用「深圳北」'), findsOneWidget);

      await tester.tap(find.text('使用「深圳北」'));
      await tester.pumpAndSettle();
      expect(find.text('深圳北'), findsOneWidget);
      expect(find.text('洛阳'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('历史行程', () {
    testWidgets('全部行程都列出来，点一行能打开那一份',
        (WidgetTester tester) async {
      final RecordingAdapter adapter = RecordingAdapter((options, _) async {
        switch (options.path) {
          case '/pois':
            return jsonBody(<Object>[]);
          case '/trip-plans':
            return jsonBody(<Object>[
              _summaryJson(
                id: 'plan-1',
                title: '洛阳历史文化两日游',
                daysCount: 2,
                perPersonCost: 192,
              ),
              _summaryJson(
                id: 'plan-2',
                title: '开封古都一日游',
                daysCount: 1,
                perPersonCost: 118,
              ),
            ]);
          case '/trip-plans/plan-1/today':
            return jsonBody(<String, Object>{
              'tripId': 'plan-1',
              'date': '今日',
              'nextStop': '龙门石窟',
              'arrival': '09:00',
              'weather': '晴 18—26℃',
              'status': '演示数据',
              'remainingItems': <Object>[],
            });
          case '/trip-plans/plan-2':
            return jsonBody(_planJson(id: 'plan-2', title: '开封古都一日游'));
          default:
            return jsonBody(<String, Object>{});
        }
      });

      await _pumpApp(
        tester,
        const Size(390, 844),
        // 这一组要真的走网络分支：配置里没有 endpoint 时，
        // 仓库会直接返回「一份都没有」，看不到列表。
        config: const AppConfig(
          apiBaseUrl: testBaseUrl,
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 1),
          sendTimeout: Duration(seconds: 1),
        ),
        overrides: <Override>[
          apiClientProvider.overrideWithValue(ApiClient(dioWith(adapter))),
        ],
      );
      await _selectTab(tester, Icons.route_outlined);
      await tester.tap(find.text('查看历史行程'));
      await tester.pumpAndSettle();

      // 行程页本身也叫"我的行程"，历史页也是 —— 这里只断言历史页的内容到了。
      expect(find.text('我的行程'), findsWidgets);
      expect(find.text('全部行程'), findsOneWidget);
      expect(find.text('共 2 份'), findsOneWidget);
      // 最近一份会出现两次：顶部「下一站」卡片下面的标题，和列表里可回看的那一行。
      expect(find.text('洛阳历史文化两日游'), findsNWidgets(2));
      expect(find.text('开封古都一日游'), findsOneWidget);
      expect(find.textContaining('人均 ¥192'), findsOneWidget);
      expect(
        find.text(formatChineseTimestamp(DateTime.parse('2026-10-01T10:00:00Z'))),
        findsWidgets,
      );

      await tester.tap(find.text('开封古都一日游'));
      await tester.pumpAndSettle();

      expect(
        adapter.requests.map((RequestOptions option) => option.path),
        contains('/trip-plans/plan-2'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('历史行程能重命名，也能在确认之后删除',
        (WidgetTester tester) async {
      final List<String> titles = <String>['洛阳历史文化两日游', '开封古都一日游'];
      final adapter = RecordingAdapter((options, body) async {
        if (options.path == '/pois') {
          return jsonBody(<Object>[]);
        }
        if (options.path == '/trip-plans') {
          return jsonBody(<Object>[
            for (int i = 0; i < titles.length; i++)
              _summaryJson(
                id: 'plan-${i + 1}',
                title: titles[i],
                daysCount: 1,
                perPersonCost: 100,
              ),
          ]);
        }
        if (options.path.endsWith('/today')) {
          return jsonBody(<String, Object>{
            'tripId': options.path.split('/')[2],
            'date': '今日',
            'nextStop': '龙门石窟',
            'arrival': '09:00',
            'weather': '晴 18—26℃',
            'status': '演示数据',
            'remainingItems': <Object>[],
          });
        }
        if (options.method == 'PATCH') {
          expect(options.path, '/trip-plans/plan-1');
          titles[0] =
              (jsonDecode(body!) as Map<String, dynamic>)['title'] as String;
          return jsonBody(<String, Object>{});
        }
        if (options.method == 'DELETE') {
          expect(options.path, '/trip-plans/plan-1');
          titles.removeAt(0);
          return ResponseBody.fromString('', 204, headers: jsonHeaders);
        }
        return jsonBody(<String, Object>{});
      });

      await _pumpApp(
        tester,
        const Size(390, 844),
        config: const AppConfig(
          apiBaseUrl: testBaseUrl,
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 1),
          sendTimeout: Duration(seconds: 1),
        ),
        overrides: <Override>[
          apiClientProvider.overrideWithValue(ApiClient(dioWith(adapter))),
        ],
      );
      await _selectTab(tester, Icons.route_outlined);
      await tester.tap(find.text('查看历史行程'));
      await tester.pumpAndSettle();

      // 重命名：弹层 → 输入 → 保存。服务端收到 PATCH，列表以服务端为准重拉。
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('删除这份行程'), findsOneWidget);

      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('trip-rename-field')),
        '洛阳慢游',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(
        adapter.requests.any((RequestOptions option) =>
            option.method == 'PATCH' && option.path == '/trip-plans/plan-1'),
        isTrue,
      );
      expect(find.text('洛阳慢游'), findsWidgets);
      expect(find.text('洛阳历史文化两日游'), findsNothing);

      // 删除要先确认：直接删掉一份方案不该是一次误触就能发生的事。
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除这份行程'));
      await tester.pumpAndSettle();
      expect(find.text('删除这份行程？'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(
        adapter.requests.any((RequestOptions option) =>
            option.method == 'DELETE' && option.path == '/trip-plans/plan-1'),
        isTrue,
      );
      expect(find.text('洛阳慢游'), findsNothing);
      expect(find.text('开封古都一日游'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 打开规划表单。
///
/// 行程页现在的默认状态是"我的行程"首页（最近一份行程 + 新建/历史两个入口 +
/// 你的足迹），表单要点"新建一个行程"才进来 —— 这条路径本身就是被测的行为，
/// 所以这里照真实用户的操作走，而不是绕过首页直接渲染表单。
Future<void> _pumpPlanner(WidgetTester tester, Size size) async {
  await _pumpApp(tester, size);
  await _selectTab(tester, Icons.route_outlined);
  await tester.tap(find.text('新建一个行程').first);
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(
  WidgetTester tester,
  Size size, {
  AppConfig config = _offlineConfig,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(
          AppBootstrap(
            config: config,
            sessionStore: SessionStore(storage: MemoryKeyValueStore()),
          ),
        ),
        ...overrides,
      ],
      child: const YujianApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// 空服务器的启动配置：默认走本地演示数据，不联网、不碰平台缓存目录。
/// 历史行程那组用例换成真的 endpoint，并在 `overrides` 里塞一个假 transport。
const AppConfig _offlineConfig = AppConfig(
  apiBaseUrl: '',
  connectTimeout: Duration(seconds: 1),
  receiveTimeout: Duration(seconds: 1),
  sendTimeout: Duration(seconds: 1),
);

/// 「下周六」和今天、明天、后天是否落在不同的日子。
/// 只有不同才会出现第四个快捷入口，判断逻辑和 date_picker_sheet 里一致。
bool _isNextSaturdayDistinct() {
  final DateTime today = DateTime.now();
  final int delta = (DateTime.saturday - today.weekday + 7) % 7;
  final DateTime nextSaturday =
      today.add(Duration(days: delta == 0 ? 7 : delta));
  return nextSaturday.day != today.day &&
      nextSaturday.day != today.add(const Duration(days: 1)).day &&
      nextSaturday.day != today.add(const Duration(days: 2)).day;
}

Future<void> _selectTab(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object> _summaryJson({
  required String id,
  required String title,
  required int daysCount,
  required int perPersonCost,
}) =>
    <String, Object>{
      'id': id,
      'title': title,
      'summary': '沿着伊河读懂千年中原',
      'corridor': '郑州—洛阳',
      'intensity': '适中',
      'totalCost': perPersonCost * 2,
      'perPersonCost': perPersonCost,
      'daysCount': daysCount,
      'dataStatus': '演示数据',
      'updatedAt': '2026-10-01T10:00:00Z',
    };

Map<String, Object> _planJson({required String id, required String title}) =>
    <String, Object>{
      'id': id,
      'title': title,
      'corridor': '郑州—开封',
      'intensity': '适中',
      'totalCost': 236,
      'perPersonCost': 118,
      'dataStatus': '演示数据',
      'warnings': <String>['门票信息请以官方渠道为准。'],
      'days': <Object>[
        <String, Object>{
          'label': 'DAY 01',
          'date': '古都一日',
          'items': <Object>[
            <String, Object>{
              'type': '景点',
              'title': '清明上河园',
              'time': '09:00',
              'duration': '约3小时',
              'transport': '公共交通',
              'description': '开封站 → 景区约20分钟',
              'cost': 60,
              'source': '系统景点库',
              'dataStatus': '演示数据',
              'risk': '建议提前预约',
            },
          ],
        },
      ],
    };
