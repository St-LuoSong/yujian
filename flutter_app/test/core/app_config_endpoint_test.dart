import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/config/app_config.dart';

void main() {
  test('bare host becomes https and gets the api path', () {
    expect(
      AppConfig.normalizeUserEndpoint('travel.example.com'),
      'https://travel.example.com/api',
    );
  });

  test('trailing slashes are removed', () {
    expect(
      AppConfig.normalizeUserEndpoint('https://travel.example.com/api/'),
      'https://travel.example.com/api',
    );
  });

  test('debug endpoint keeps http so emulator loopback remains usable', () {
    expect(
      AppConfig.normalizeUserEndpoint('http://10.0.2.2:8080'),
      'http://10.0.2.2:8080/api',
    );
  });

  test('unsupported schemes are rejected', () {
    expect(AppConfig.normalizeUserEndpoint('ftp://travel.example.com'), isNull);
    expect(AppConfig.normalizeUserEndpoint('https://'), isNull);
  });

  test('runtime endpoint wins over the emulator fallback', () {
    final AppConfig config = AppConfig.resolve(
      runtimeEndpoint: 'https://travel.example.com',
    );

    expect(config.apiBaseUrl, 'https://travel.example.com/api');
    expect(config.hasEndpoint, isTrue);
  });

  test('withEndpoint keeps timeout policy', () {
    final AppConfig base = AppConfig.resolve(
      runtimeEndpoint: 'https://old.example.com',
    );
    final AppConfig changed = base.withEndpoint('https://new.example.com/api');

    expect(changed.apiBaseUrl, 'https://new.example.com/api');
    expect(changed.connectTimeout, base.connectTimeout);
    expect(changed.receiveTimeout, base.receiveTimeout);
    expect(changed.sendTimeout, base.sendTimeout);
  });
}
