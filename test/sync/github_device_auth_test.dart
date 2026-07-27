import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/sync/github_device_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

/// Builds an auth client over a scripted sequence of token-endpoint bodies.
///
/// The `delay` indirection is injected so the poll loop never actually
/// waits — a real `interval` of 5s would make this suite unusable.
GitHubDeviceAuth authWith(List<Map<String, dynamic>> tokenResponses) {
  var call = 0;
  final client = http_testing.MockClient((request) async {
    if (request.url.path.contains('/login/device/code')) {
      return http.Response(
        jsonEncode({
          'device_code': 'dev-1',
          'user_code': 'ABCD-1234',
          'verification_uri': 'https://github.com/login/device',
          'interval': 1,
          'expires_in': 900,
        }),
        200,
      );
    }
    final body = tokenResponses[call.clamp(0, tokenResponses.length - 1)];
    call++;
    return http.Response(jsonEncode(body), 200);
  });
  return GitHubDeviceAuth(
    clientId: 'client-1',
    httpClient: client,
    delay: (_) async {},
  );
}

void main() {
  group('requestDeviceCode', () {
    test('parses the user code and verification url', () async {
      final auth = authWith([]);
      addTearDown(auth.close);

      final device = await auth.requestDeviceCode();

      expect(device.deviceCode, 'dev-1');
      expect(device.userCode, 'ABCD-1234');
      expect(device.verificationUri, 'https://github.com/login/device');
      expect(device.interval, 1);
      expect(device.expiresIn, 900);
    });

    test('defaults interval and expiry when GitHub omits them', () {
      final device = DeviceCodeResponse.fromJson(const {
        'device_code': 'd',
        'user_code': 'u',
        'verification_uri': 'v',
      });

      expect(device.interval, 5);
      expect(device.expiresIn, 900);
    });

    test('throws on a non-200', () async {
      final auth = GitHubDeviceAuth(
        clientId: 'c',
        httpClient: http_testing.MockClient(
          (_) async => http.Response('nope', 500),
        ),
        delay: (_) async {},
      );
      addTearDown(auth.close);

      await expectLater(
        auth.requestDeviceCode(),
        throwsA(isA<DeviceAuthException>()),
      );
    });
  });

  group('pollForToken', () {
    test('returns the token once the user authorizes', () async {
      final auth = authWith([
        {'error': 'authorization_pending'},
        {'access_token': 'gho_secret'},
      ]);
      addTearDown(auth.close);

      final device = await auth.requestDeviceCode();

      expect(await auth.pollForToken(device), 'gho_secret');
    });

    test('backs off and keeps going on slow_down', () async {
      final auth = authWith([
        {'error': 'slow_down', 'interval': 2},
        {'access_token': 'gho_secret'},
      ]);
      addTearDown(auth.close);

      final device = await auth.requestDeviceCode();

      expect(await auth.pollForToken(device), 'gho_secret');
    });

    test('backs off with a default step when no interval is given', () async {
      final auth = authWith([
        {'error': 'slow_down'},
        {'access_token': 'gho_secret'},
      ]);
      addTearDown(auth.close);

      final device = await auth.requestDeviceCode();

      expect(await auth.pollForToken(device), 'gho_secret');
    });

    test('throws on a terminal error such as access_denied', () async {
      final auth = authWith([
        {'error': 'access_denied', 'error_description': 'user said no'},
      ]);
      addTearDown(auth.close);

      final device = await auth.requestDeviceCode();

      await expectLater(
        auth.pollForToken(device),
        throwsA(
          isA<DeviceAuthException>()
              .having((e) => e.code, 'code', 'access_denied')
              .having((e) => e.message, 'message', 'user said no'),
        ),
      );
    });

    test('falls back to the code when no description is given', () async {
      final auth = authWith([
        {'error': 'expired_token'},
      ]);
      addTearDown(auth.close);

      final device = await auth.requestDeviceCode();

      await expectLater(
        auth.pollForToken(device),
        throwsA(
          isA<DeviceAuthException>().having(
            (e) => e.message,
            'message',
            'expired_token',
          ),
        ),
      );
    });

    test('throws on a response with neither token nor error', () async {
      final auth = authWith([<String, dynamic>{}]);
      addTearDown(auth.close);

      final device = await auth.requestDeviceCode();

      await expectLater(
        auth.pollForToken(device),
        throwsA(
          isA<DeviceAuthException>().having((e) => e.code, 'code', 'unknown'),
        ),
      );
    });

    test('gives up once the device code has expired', () async {
      final auth = authWith([
        {'error': 'authorization_pending'},
      ]);
      addTearDown(auth.close);

      const device = DeviceCodeResponse(
        deviceCode: 'd',
        userCode: 'u',
        verificationUri: 'v',
        interval: 1,
        // Already expired, so the loop body never runs.
        expiresIn: -1,
      );

      await expectLater(
        auth.pollForToken(device),
        throwsA(
          isA<DeviceAuthException>().having(
            (e) => e.code,
            'code',
            'expired_token',
          ),
        ),
      );
    });
  });

  test('DeviceAuthException prints its code and message', () {
    expect(
      DeviceAuthException('bad', 'went wrong').toString(),
      contains('bad'),
    );
  });

  // Production constructs this with neither an http client nor a delay, so
  // the defaulted branch of the constructor is the one that actually ships.
  test('builds its own http client and delay when none are injected', () {
    final auth = GitHubDeviceAuth(clientId: 'c');

    expect(auth.clientId, 'c');
    expect(auth.scope, 'repo');
    auth.close();
  });
}
