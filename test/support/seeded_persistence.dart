import 'package:crdt_sync/crdt_sync.dart';

/// A persistence double that also lets a test seed a pre-existing payload,
/// which is how the load-time pruning path gets exercised.
class SeededPersistence implements LogPersistence {
  SeededPersistence([this._text]);

  String? _text;

  /// What is currently stored.
  String? get text => _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async => _text = text;
}

/// A fixed clock for seeding raw records.
Hlc hlc(int ms) => Hlc(wallTimeMs: ms, counter: 0, nodeId: 'n');
