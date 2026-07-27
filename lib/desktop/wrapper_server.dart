import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Local HTTP server backing the desktop app.
///
/// The desktop app is a Flutter **web** build (Flutter's Linux embedder manages
/// only ~20fps at 4K where the same Dart in Chrome sustains ~144fps), so it
/// runs in a browser and cannot touch the filesystem. This process is the other
/// half of the desktop app: it serves the build, and owns the one file a
/// browser cannot write — a copy of the inventory log, so a wiped Chrome
/// profile is not a total-loss event for items that have not yet synced to
/// GitHub.
///
/// Imported only by `bin/home_inventory_desktop.dart`, never from `lib/main.dart`
/// — that is what keeps its `dart:io` out of the app's web graph.
///
/// Binds to loopback only. The backup endpoint reads and overwrites a file in
/// the user's home directory with no authentication, so exposing it on a
/// routable address would let anything on the network rewrite the inventory.
class WrapperServer {
  /// Creates a server serving [webRoot] and persisting to [logPath].
  WrapperServer({required this.webRoot, required this.logPath});

  /// Directory holding the built Flutter web assets.
  final String webRoot;

  /// Absolute path of the on-disk inventory-log copy.
  final String logPath;

  HttpServer? _server;

  /// Port the server is listening on, once [start] has completed.
  int get port => _server!.port;

  /// Binds to loopback on [requestedPort] and begins serving.
  ///
  /// Pass 0 to let the OS choose (tests do this); the desktop launcher passes
  /// the fixed port, because the browser keys IndexedDB by origin and a
  /// changing port would silently hide the whole inventory.
  Future<void> start(int requestedPort) async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      requestedPort,
    );
    unawaited(_serve(_server!));
  }

  /// Stops serving and releases the port.
  Future<void> stop() async => _server?.close(force: true);

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request);
      } on Exception {
        request.response.statusCode = HttpStatus.internalServerError;
      }
      await request.response.close();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/backup/log') {
      return _file(request, logPath);
    }
    return _static(request, request.uri.path);
  }

  /// GET returns the file's contents (404 when absent); POST overwrites it.
  Future<void> _file(HttpRequest request, String filePath) async {
    final file = File(filePath);
    if (request.method == 'POST') {
      await file.parent.create(recursive: true);
      await file.writeAsString(await utf8.decodeStream(request));
      request.response.statusCode = HttpStatus.noContent;
      return;
    }
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = ContentType.text;
    request.response.write(await file.readAsString());
  }

  Future<void> _static(HttpRequest request, String path) async {
    final relative = path == '/' ? 'index.html' : path.substring(1);
    // Reject traversal before touching the filesystem: the served root sits
    // next to the user's files, so `../` must not escape it.
    final resolved = p.normalize(p.join(webRoot, relative));
    // coverage:ignore-start
    // Defence in depth, and currently unreachable: Dart's HttpServer decodes
    // and normalises the path before a handler runs, so even `%2e%2e` arrives
    // already collapsed (asserted in wrapper_server_test). Kept so the
    // guarantee does not depend on that implementation detail holding.
    if (!p.isWithin(webRoot, resolved) && resolved != p.normalize(webRoot)) {
      request.response.statusCode = HttpStatus.forbidden;
      return;
    }
    // coverage:ignore-end
    final file = File(resolved);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = contentTypeFor(resolved);
    await request.response.addStream(file.openRead());
  }

  /// Content type for [filePath].
  ///
  /// Flutter web is strict here: CanvasKit refuses to instantiate a `.wasm`
  /// served as anything but `application/wasm`, and the app silently fails to
  /// render if the bootstrap `.js` is mislabelled.
  static ContentType contentTypeFor(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.html':
        return ContentType.html;
      case '.js' || '.mjs':
        return ContentType('text', 'javascript', charset: 'utf-8');
      case '.json':
        return ContentType.json;
      case '.wasm':
        return ContentType('application', 'wasm');
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.png':
        return ContentType('image', 'png');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.ttf':
        return ContentType('font', 'ttf');
      case '.otf':
        return ContentType('font', 'otf');
      case '.woff2':
        return ContentType('font', 'woff2');
      default:
        return ContentType.binary;
    }
  }
}
