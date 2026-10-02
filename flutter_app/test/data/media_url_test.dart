import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/config/app_config.dart';

/// An upload made in the operator console comes back as `localhost`, because
/// the backend derives the photo URL from the browser that uploaded it. These
/// tests pin the rewrite that makes the same payload loadable on the phone,
/// and pin everything that must stay untouched.
AppConfig _config(String apiBaseUrl) => AppConfig(
      apiBaseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    );

void main() {
  group('resolveMediaUrl', () {
    final emulator = _config('http://10.0.2.2:8080/api');

    test('debug builds default to the emulator loopback host', () {
      expect(AppConfig.resolve().apiBaseUrl, 'http://10.0.2.2:8080/api');
    });

    test('re-points a localhost photo at the host the API uses', () {
      expect(
        emulator.resolveMediaUrl('http://localhost:8080/media/abc.jpg'),
        'http://10.0.2.2:8080/media/abc.jpg',
      );
    });

    test('re-points 127.0.0.1 as well', () {
      expect(
        emulator.resolveMediaUrl('http://127.0.0.1:8080/media/abc.jpg'),
        'http://10.0.2.2:8080/media/abc.jpg',
      );
    });

    test('keeps a photo that is already reachable', () {
      const remote = 'https://images.example.com/longmen.jpg';
      expect(emulator.resolveMediaUrl(remote), remote);
    });

    test('joins a path only photo onto the API origin', () {
      expect(
        emulator.resolveMediaUrl('/media/abc.jpg'),
        'http://10.0.2.2:8080/media/abc.jpg',
      );
    });

    test('re-points a protocol relative loopback photo', () {
      expect(
        emulator.resolveMediaUrl('//localhost:8080/media/abc.jpg'),
        'http://10.0.2.2:8080/media/abc.jpg',
      );
    });

    test('leaves a protocol relative remote photo alone', () {
      const remote = '//cdn.example.com/abc.jpg';
      expect(emulator.resolveMediaUrl(remote), remote);
    });

    test('preserves the query string', () {
      expect(
        emulator.resolveMediaUrl('http://localhost:8080/media/abc.jpg?v=2'),
        'http://10.0.2.2:8080/media/abc.jpg?v=2',
      );
    });

    test('an empty value stays empty', () {
      expect(emulator.resolveMediaUrl(''), '');
      expect(emulator.resolveMediaUrl('   '), '');
    });

    test('a build without an endpoint cannot rewrite anything', () {
      final release = _config('');
      expect(release.hasEndpoint, isFalse);
      expect(
        release.resolveMediaUrl('http://localhost:8080/media/abc.jpg'),
        'http://localhost:8080/media/abc.jpg',
      );
    });

    test('omits the port when the API uses the scheme default', () {
      final tls = _config('https://api.example.com/api');
      expect(
        tls.resolveMediaUrl('http://localhost/media/abc.jpg'),
        'https://api.example.com/media/abc.jpg',
      );
    });

    test('a loopback API host keeps loopback photos intact', () {
      final desktop = _config('http://localhost:8080/api');
      expect(
        desktop.resolveMediaUrl('http://localhost:8080/media/abc.jpg'),
        'http://localhost:8080/media/abc.jpg',
      );
    });
  });

  group('isLoopbackHost', () {
    test('accepts the loopback spellings the backend can emit', () {
      for (final host in <String>[
        'localhost',
        'LOCALHOST',
        '127.0.0.1',
        '0.0.0.0',
        '::1',
        'preview.localhost',
      ]) {
        expect(AppConfig.isLoopbackHost(host), isTrue, reason: host);
      }
    });

    test('rejects a real host', () {
      expect(AppConfig.isLoopbackHost('10.0.2.2'), isFalse);
      expect(AppConfig.isLoopbackHost('api.example.com'), isFalse);
    });
  });
}
