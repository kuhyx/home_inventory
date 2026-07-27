import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/ui/theme.dart';

/// Pumps [child] inside a themed [MaterialApp].
///
/// Always use this rather than building a `MaterialApp` inline: `StockBadge`
/// reads `Theme.of(context).extension<AppStatusColors>()!`, which throws a
/// null-check error under a bare `MaterialApp()` with no theme.
Future<void> pumpApp(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(theme: buildDarkTheme(), home: child));
