import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_inventory/ui/theme.dart';

void main() {
  group('buildLightTheme', () {
    test('uses the shared paper/ink neutrals and the gold accent', () {
      final scheme = buildLightTheme().colorScheme;

      expect(scheme.brightness, Brightness.light);
      expect(scheme.surface, const Color(0xFFF6F4F3));
      expect(scheme.onSurface, const Color(0xFF211D1B));
      expect(scheme.primary, const Color(0xFFB8862E));
      expect(scheme.error, const Color(0xFFE2585F));
    });

    // Regression guard: leaving secondary/tertiary unset makes widgets that
    // reach for secondaryContainer (SegmentedButton's selected segment) fall
    // back to stock Material teal. Confirmed on-device in the todo app.
    test('mirrors the single accent into secondary and tertiary', () {
      final scheme = buildLightTheme().colorScheme;

      expect(scheme.secondary, scheme.primary);
      expect(scheme.tertiary, scheme.primary);
      expect(scheme.onSecondaryContainer, scheme.primary);
      expect(scheme.onTertiaryContainer, scheme.primary);
    });

    test('carries the light status colors', () {
      final status = buildLightTheme().extension<AppStatusColors>();

      expect(status, AppStatusColors.light);
    });
  });

  group('buildDarkTheme', () {
    test('uses the shared ink neutrals and the same gold accent', () {
      final scheme = buildDarkTheme().colorScheme;

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, const Color(0xFF211D1B));
      expect(scheme.surfaceContainerHigh, const Color(0xFF2B2624));
      expect(scheme.surfaceContainerHighest, const Color(0xFF38312E));
      expect(scheme.onSurface, const Color(0xFFECEAE9));
      expect(scheme.outline, const Color(0xFF463E3A));
      expect(scheme.primary, const Color(0xFFB8862E));
    });

    test('mirrors the single accent into secondary and tertiary', () {
      final scheme = buildDarkTheme().colorScheme;

      expect(scheme.secondary, scheme.primary);
      expect(scheme.tertiary, scheme.primary);
    });

    test('carries the dark status colors', () {
      final status = buildDarkTheme().extension<AppStatusColors>();

      expect(status, AppStatusColors.dark);
    });
  });

  group('theme wiring', () {
    test('scaffold background follows the surface token', () {
      final theme = buildDarkTheme();

      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
      expect(theme.useMaterial3, isTrue);
    });

    // bodyMedium is the fallback for a bare Text widget; M3 defaults it to
    // 14px, below the 16px reading floor the design system sets.
    test('body styles sit at the 16px reading floor', () {
      final text = buildDarkTheme().textTheme;

      expect(text.bodyLarge?.fontSize, AppTextSize.body);
      expect(text.bodyMedium?.fontSize, AppTextSize.body);
      expect(text.titleLarge?.fontSize, AppTextSize.title);
      expect(text.titleMedium?.fontSize, AppTextSize.subtitle);
      expect(text.labelMedium?.fontSize, AppTextSize.label);
      expect(text.labelSmall?.fontSize, AppTextSize.caption);
    });

    test('inputs are filled with an 8px radius and a 2px focus border', () {
      final theme = buildDarkTheme();
      final input = theme.inputDecorationTheme;

      expect(input.filled, isTrue);
      expect(input.fillColor, theme.colorScheme.surfaceContainerHighest);
      final focused = input.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, theme.colorScheme.primary);
      expect(focused.borderSide.width, 2);
      expect(
        focused.borderRadius,
        BorderRadius.circular(AppRadius.sm),
      );
    });

    test('dividers are hairlines on the outline token', () {
      final theme = buildDarkTheme();

      expect(theme.dividerTheme.color, theme.colorScheme.outline);
      expect(theme.dividerTheme.thickness, 1);
      expect(theme.dividerTheme.space, AppSpacing.md);
    });
  });

  group('AppStatusColors', () {
    test('light and dark share the same semantic fills', () {
      expect(AppStatusColors.light.success, AppStatusColors.dark.success);
      expect(AppStatusColors.light.warning, AppStatusColors.dark.warning);
      expect(AppStatusColors.dark.success, const Color(0xFF8A9A3C));
      expect(AppStatusColors.dark.warning, const Color(0xFFE0A63C));
    });

    // AppStatusColors deliberately has no `==` override (matching the shared
    // template), so a no-arg copyWith is a distinct instance carrying equal
    // fields — assert the fields, not identity.
    test('copyWith replaces only the named field', () {
      const base = AppStatusColors.dark;

      expect(base.copyWith().success, base.success);
      expect(base.copyWith().warning, base.warning);
      expect(
        base.copyWith(success: const Color(0xFF000001)).success,
        const Color(0xFF000001),
      );
      expect(
        base.copyWith(success: const Color(0xFF000001)).warning,
        base.warning,
      );
      expect(
        base.copyWith(warning: const Color(0xFF000002)).warning,
        const Color(0xFF000002),
      );
      expect(
        base.copyWith(warning: const Color(0xFF000002)).success,
        base.success,
      );
    });

    test('lerp interpolates both fields', () {
      const a = AppStatusColors(
        success: Color(0xFF000000),
        warning: Color(0xFF000000),
      );
      const b = AppStatusColors(
        success: Color(0xFFFFFFFF),
        warning: Color(0xFFFFFFFF),
      );

      final mid = a.lerp(b, 1);

      expect(mid.success, b.success);
      expect(mid.warning, b.warning);
    });

    // ThemeExtension.lerp is called with the *other* theme's extension, which
    // may be a different type mid-swap; the guard returns `this` unchanged.
    test('lerp against a foreign extension returns this', () {
      const base = AppStatusColors.dark;

      expect(base.lerp(null, 0.5), same(base));
    });
  });
}
