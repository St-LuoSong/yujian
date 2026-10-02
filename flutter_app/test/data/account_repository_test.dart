import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/network/api_failure.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/data/repositories/account_repository.dart';

import '../support/test_http.dart';

/// Covers the parts of the account layer that are easy to get wrong: that sign
/// in never waits for the optional trial handover, that the handover runs
/// exactly once, that a failed handover does not break sign in, and that a
/// stale token resolves to "signed out".
void main() {
  test('sign in stores the session and reports the pending handover', () async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    await session.saveAnonymousToken('anon-1');

    final adapter = RecordingAdapter((options, _) async {
      switch (options.path) {
        case '/auth/login':
          return jsonBody(_authJson());
        case '/auth/merge-anonymous':
          // The merge endpoint only reads the anonymous header, so the client
          // must send it explicitly even though an access token now exists.
          expect(options.headers[SessionStore.anonymousHeader], 'anon-1');
          return jsonBody(<String, Object>{'merged': true, 'userId': 'u1'});
        default:
          throw StateError('unexpected request ${options.path}');
      }
    });

    final repository = AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    );
    final outcome = await repository.signIn(
      identifier: 'traveler',
      password: 'secret123',
    );

    expect(outcome.user.username, 'traveler');
    // 登录只等一次凭据交换：合并是随后的独立一步，不能挡住登录按钮。
    expect(outcome.mergePending, isTrue);
    expect(
      adapter.requests.map((request) => request.path),
      <String>['/auth/login'],
    );

    final snapshot = await session.read();
    expect(snapshot.hasUser, isTrue);
    expect(snapshot.accessToken, 'access-1');

    final merge = await repository.mergeAnonymousTrips();
    expect(merge.merged, isTrue);
    expect(merge.failure, isNull);
    expect(
      adapter.requests.map((request) => request.path),
      <String>['/auth/login', '/auth/merge-anonymous'],
    );
    // The trial session is converted on the server and can no longer
    // authenticate, so the client must stop sending it.
    expect((await session.read()).anonymousToken, isNull);
  });

  test('sign in without a trial session does not call the merge endpoint',
      () async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    final adapter = RecordingAdapter((_, __) async => jsonBody(_authJson()));

    final repository = AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    );
    final outcome = await repository.signIn(
      identifier: 'traveler',
      password: 'secret123',
    );

    expect(outcome.mergePending, isFalse);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.path, '/auth/login');

    // 没有体验会话时合并是空操作，连请求都不该发出去。
    final merge = await repository.mergeAnonymousTrips();
    expect(merge.nothingToMerge, isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('a failed handover still signs the user in and is reported', () async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    await session.saveAnonymousToken('anon-expired');

    final adapter = RecordingAdapter((options, _) async {
      if (options.path == '/auth/login') {
        return jsonBody(_authJson());
      }
      return jsonBody(
        <String, Object>{
          'code': 'ANONYMOUS_SESSION_INVALID',
          'message': '匿名体验会话已失效，无法合并',
        },
        status: 401,
      );
    });

    final repository = AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    );
    final outcome = await repository.signIn(
      identifier: 'traveler',
      password: 'secret123',
    );

    // 合并失败不影响登录本身：账号先可用，失败只作为一条提示。
    expect(outcome.user.username, 'traveler');
    expect(outcome.mergePending, isTrue);

    final merge = await repository.mergeAnonymousTrips();
    expect(merge.merged, isFalse);
    expect(merge.failure?.code, 'ANONYMOUS_SESSION_INVALID');
    // The trial token is kept: it may still be usable if the merge is retried.
    expect((await session.read()).anonymousToken, 'anon-expired');
  });

  test('restore without a stored token makes no request', () async {
    final adapter = RecordingAdapter((_, __) async {
      throw StateError('restore must not call the server when signed out');
    });

    final user = await AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: SessionStore(storage: MemoryKeyValueStore()),
    ).restore();

    expect(user, isNull);
    expect(adapter.requests, isEmpty);
  });

  test('restore clears a stale token instead of failing', () async {
    final store = MemoryKeyValueStore();
    final session = SessionStore(storage: store);
    await session.saveUserSession(
      accessToken: 'stale',
      refreshToken: 'stale-refresh',
    );
    final adapter = RecordingAdapter(
      (_, __) async => jsonBody(
        <String, Object>{'code': 'AUTH_REQUIRED', 'message': '登录状态已失效'},
        status: 401,
      ),
    );

    final user = await AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    ).restore();

    expect(user, isNull);
    expect((await session.read()).hasUser, isFalse);
    expect(store.values.containsKey('yujian.access_token'), isFalse);
  });

  test('a stale token rejection does not drop the session that replaced it',
      () async {
    final store = MemoryKeyValueStore();
    final session = SessionStore(storage: store);
    await session.saveUserSession(accessToken: 'stale', refreshToken: 'stale-r');

    final gate = Completer<void>();
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/auth/me');
      await gate.future;
      return jsonBody(
        <String, Object>{'code': 'AUTH_REQUIRED', 'message': '请先登录'},
        status: 401,
      );
    });
    final repository = AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    );

    // 旧 token 的校验还挂在网络上……
    final pending = repository.restore();
    // ……用户在这期间登录成功，写入了新的凭据。
    await session.saveUserSession(accessToken: 'fresh', refreshToken: 'fresh-r');

    gate.complete();
    expect(await pending, isNull);
    // 迟到的 401 只能清掉它自己校验过的那一份会话，不能顺手把新登录删掉。
    expect((await session.read()).accessToken, 'fresh');
  });

  test('favourites are listed and removed by attraction id', () async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    await session.saveUserSession(accessToken: 'a', refreshToken: 'r');

    final adapter = RecordingAdapter((options, _) async {
      if (options.method == 'GET') {
        return jsonBody(<Object>[
          <String, Object>{
            'id': 'f1',
            'poiId': 'longmen',
            'poiName': '龙门石窟',
            'city': '洛阳',
            'imageUrl': 'https://example.test/longmen.jpg',
            'createdAt': '2026-10-01T10:00:00Z',
          },
        ]);
      }
      return ResponseBody.fromString('', 204, headers: jsonHeaders);
    });
    final repository = AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    );

    final favorites = await repository.listFavorites();
    expect(favorites, hasLength(1));
    expect(favorites.single.poiName, '龙门石窟');
    expect(favorites.single.createdAt, isNotNull);

    await repository.removeFavorite('longmen');
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.path, '/favorites/poi/longmen');
  });

  test('a rejected sign in surfaces the backend message', () async {
    final adapter = RecordingAdapter(
      (_, __) async => jsonBody(
        <String, Object>{
          'code': 'INVALID_CREDENTIALS',
          'message': '账号或密码不正确',
        },
        status: 401,
      ),
    );

    expect(
      () => AccountRepository(
        client: ApiClient(dioWith(adapter)),
        session: SessionStore(storage: MemoryKeyValueStore()),
      ).signIn(identifier: 'traveler', password: 'wrong'),
      throwsA(
        isA<ApiFailure>()
            .having((failure) => failure.code, 'code', 'INVALID_CREDENTIALS')
            .having((failure) => failure.message, 'message', '账号或密码不正确'),
      ),
    );
  });

  test('profile update carries nickname and preset avatar', () async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    await session.saveUserSession(accessToken: 'a', refreshToken: 'r');
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/auth/me');
      expect(options.method, 'PATCH');
      expect(options.data, <String, Object?>{
        'nickname': '河洛旅人',
        'avatarKey': 'celadon',
      });
      return jsonBody(<String, Object>{
        'id': 'u1',
        'username': 'traveler',
        'nickname': '河洛旅人',
        'email': 'traveler@example.test',
        'avatarKey': 'celadon',
        'emailVerified': true,
        'roles': <String>['USER'],
      });
    });

    final user = await AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    ).updateProfile(nickname: '河洛旅人', avatarKey: 'celadon');

    expect(user.displayName, '河洛旅人');
    expect(user.avatarKey, 'celadon');
  });

  test('email verification surfaces the development code', () async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    await session.saveUserSession(accessToken: 'a', refreshToken: 'r');
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/email/send-code');
      expect(options.data, <String, Object?>{
        'email': 'traveler@example.test',
        'purpose': 'VERIFY_EMAIL',
      });
      return jsonBody(<String, Object>{
        'message': '验证码已发送',
        'debugCode': '123456',
      });
    });

    final result = await AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    ).sendEmailCode('traveler@example.test');

    expect(result.message, '验证码已发送');
    expect(result.debugCode, '123456');
  });

  test('account deletion sends the password and clears local credentials',
      () async {
    final session = SessionStore(storage: MemoryKeyValueStore());
    await session.saveUserSession(accessToken: 'a', refreshToken: 'r');
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/auth/me');
      expect(options.method, 'DELETE');
      expect(options.data, <String, Object?>{'password': 'secret-123'});
      return ResponseBody.fromString('', 204, headers: jsonHeaders);
    });

    await AccountRepository(
      client: ApiClient(dioWith(adapter)),
      session: session,
    ).deleteAccount('secret-123');

    expect((await session.read()).isEmpty, isTrue);
  });
}

Map<String, Object> _authJson() => <String, Object>{
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
