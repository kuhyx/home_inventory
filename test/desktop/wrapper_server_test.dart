import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/desktop/wrapper_server.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String logPath;
  late WrapperServer server;
  late String origin;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wrapper-test');
    logPath = p.join(root.path, 'state', 'home_inventory.json');
    final webRoot = Directory(p.join(root.path, 'web'))..createSync();
    File(p.join(webRoot.path, 'index.html')).writeAsStringSync('<h1>hi</h1>');
    File(p.join(webRoot.path, 'main.dart.js')).writeAsStringSync('console;');
    server = WrapperServer(webRoot: webRoot.path, logPath: logPath);
    // Port 0 lets the OS pick, so tests never collide with a running desktop
    // app on the fixed port.
    await server.start(0);
    origin = 'http://localhost:${server.port}';
  });

  tearDown(() async {
    await server.stop();
    root.deleteSync(recursive: true);
  });

  group('static assets', () {
    test('serves index.html at the root', () async {
      final response = await http.get(Uri.parse('$origin/'));

      expect(response.statusCode, 200);
      expect(response.body, contains('hi'));
      expect(response.headers['content-type'], contains('text/html'));
    });

    test('serves a named file', () async {
      final response = await http.get(Uri.parse('$origin/main.dart.js'));

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('javascript'));
    });

    test('404s an unknown path', () async {
      final response = await http.get(Uri.parse('$origin/nope.png'));

      expect(response.statusCode, 404);
    });

    // The served root sits next to the user's files. Dart's HttpServer
    // normalises the path before a handler runs, so even an encoded `..`
    // arrives already collapsed — this asserts that, which is what lets the
    // explicit traversal guard be marked unreachable rather than untested.
    test('cannot escape the web root', () async {
      final response = await http.get(
        Uri.parse('$origin/%2e%2e/%2e%2e/etc/passwd'),
      );

      expect(response.statusCode, 404);
    });
  });

  group('log backup', () {
    test('404s before anything has been written', () async {
      final response = await http.get(Uri.parse('$origin/backup/log'));

      expect(response.statusCode, 404);
    });

    // The parent directory does not exist on a fresh machine; the handler has
    // to create it rather than fail the very first backup.
    test('POST creates the file and its parent directory', () async {
      final response = await http.post(
        Uri.parse('$origin/backup/log'),
        body: '{"a":1}',
      );

      expect(response.statusCode, 204);
      expect(File(logPath).readAsStringSync(), '{"a":1}');
    });

    test('GET returns what was written', () async {
      await http.post(Uri.parse('$origin/backup/log'), body: '{"a":1}');

      final response = await http.get(Uri.parse('$origin/backup/log'));

      expect(response.statusCode, 200);
      expect(response.body, '{"a":1}');
    });

    // Any handler failure has to become a 500 rather than tearing down the
    // accept loop and taking the whole desktop app's server with it.
    test('a write that cannot succeed becomes a 500', () async {
      final blocked = WrapperServer(
        webRoot: p.join(root.path, 'web'),
        // Parent is an existing *file*, so creating the directory throws.
        logPath: p.join(root.path, 'web', 'index.html', 'log.json'),
      );
      await blocked.start(0);
      addTearDown(blocked.stop);

      final response = await http.post(
        Uri.parse('http://localhost:${blocked.port}/backup/log'),
        body: 'x',
      );

      expect(response.statusCode, 500);
    });

    test('rejects other methods', () async {
      final response = await http.delete(Uri.parse('$origin/backup/log'));

      expect(response.statusCode, 405);
    });
  });

  group('contentTypeFor', () {
    // Flutter web is strict: CanvasKit refuses a .wasm served as anything but
    // application/wasm, and a mislabelled bootstrap .js renders nothing at all.
    test('names the types Flutter web insists on', () {
      expect(
        WrapperServer.contentTypeFor('a.wasm').mimeType,
        'application/wasm',
      );
      expect(
        WrapperServer.contentTypeFor('a.js').mimeType,
        'text/javascript',
      );
      expect(
        WrapperServer.contentTypeFor('a.mjs').mimeType,
        'text/javascript',
      );
      expect(WrapperServer.contentTypeFor('a.html').mimeType, 'text/html');
      expect(
        WrapperServer.contentTypeFor('a.json').mimeType,
        'application/json',
      );
      expect(WrapperServer.contentTypeFor('a.css').mimeType, 'text/css');
    });

    test('names image and font types', () {
      expect(WrapperServer.contentTypeFor('a.png').mimeType, 'image/png');
      expect(WrapperServer.contentTypeFor('a.svg').mimeType, 'image/svg+xml');
      expect(WrapperServer.contentTypeFor('a.ttf').mimeType, 'font/ttf');
      expect(WrapperServer.contentTypeFor('a.otf').mimeType, 'font/otf');
      expect(WrapperServer.contentTypeFor('a.woff2').mimeType, 'font/woff2');
    });

    test('falls back to binary, case-insensitively', () {
      expect(
        WrapperServer.contentTypeFor('a.bin').mimeType,
        'application/octet-stream',
      );
      expect(WrapperServer.contentTypeFor('A.PNG').mimeType, 'image/png');
    });
  });
}
