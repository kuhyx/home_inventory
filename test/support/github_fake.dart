import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

/// One recorded PUT to the GitHub Contents API.
class PutCall {
  /// Creates a record of a push.
  PutCall(this.path, this.content);

  /// Repo-relative path written.
  final String path;

  /// Decoded file body.
  final String content;
}

/// A fake GitHub Contents API.
///
/// **The repo-existence probe is not optional.** `GitHubClient.listDirectory`
/// answers a 404 by calling `_repoExists()`, which GETs bare
/// `/repos/<owner>/<repo>` with no `/contents` segment, purely to tell "this
/// path is unused yet" apart from "this repo is missing". A fake that does
/// not answer that with 200 makes the very first sync test — the one where
/// the device directory legitimately does not exist — fail with
/// `RepoNotFoundError`, which reads like a credential bug and is nothing of
/// the kind.
class GitHubFake {
  /// Creates a fake serving [files], with [dirs] listed under each prefix.
  GitHubFake({
    Map<String, String>? files,
    Map<String, List<String>>? dirs,
    this.repoExists = true,
  }) : files = files ?? {},
       dirs = dirs ?? {};

  /// Repo-relative path -> file body.
  final Map<String, String> files;

  /// Repo-relative directory -> entry names.
  final Map<String, List<String>> dirs;

  /// Whether the bare repo probe succeeds.
  final bool repoExists;

  /// Every PUT the client made, in order.
  final List<PutCall> puts = [];

  /// The HTTP client to hand to `GitHubClient`.
  http.Client get client => http_testing.MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;

    if (!path.contains('/contents/')) {
      return repoExists
          ? http.Response(jsonEncode({'full_name': 'kuhyx/syncs'}), 200)
          : http.Response('{"message":"Not Found"}', 404);
    }

    final key = Uri.decodeFull(path.split('/contents/').last);

    if (request.method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final content = utf8.decode(base64.decode(body['content'] as String));
      puts.add(PutCall(key, content));
      files[key] = content;
      return http.Response(jsonEncode({'content': <String, dynamic>{}}), 201);
    }

    final listing = dirs[key];
    if (listing != null) {
      return http.Response(
        jsonEncode([
          for (final name in listing)
            {'name': name, 'path': '$key/$name', 'type': 'dir'},
        ]),
        200,
      );
    }

    final file = files[key];
    if (file != null) {
      return http.Response(
        jsonEncode({
          'content': base64.encode(utf8.encode(file)),
          'encoding': 'base64',
          'sha': 'deadbeef',
        }),
        200,
      );
    }

    return http.Response('{"message":"Not Found"}', 404);
  }
}
