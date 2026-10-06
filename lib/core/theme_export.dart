import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Publishes the Dart-resolved color schemes (light + dark) to the shared prefs
/// store so every native XML activity themes itself from the exact same colors.
/// Dart (AppTheme / materialYouScheme) stays the single source of truth; the
/// native side only reads `themeScheme` (see ThemeBridge.kt).
class ThemeExport {
  ThemeExport._();

  static String? _last;

  static Map<String, int> _pack(ColorScheme s) => {
        'primary': s.primary.toARGB32(),
        'onPrimary': s.onPrimary.toARGB32(),
        'primaryContainer': s.primaryContainer.toARGB32(),
        'onPrimaryContainer': s.onPrimaryContainer.toARGB32(),
        'secondary': s.secondary.toARGB32(),
        'onSecondary': s.onSecondary.toARGB32(),
        'secondaryContainer': s.secondaryContainer.toARGB32(),
        'onSecondaryContainer': s.onSecondaryContainer.toARGB32(),
        'tertiary': s.tertiary.toARGB32(),
        'onTertiary': s.onTertiary.toARGB32(),
        'tertiaryContainer': s.tertiaryContainer.toARGB32(),
        'onTertiaryContainer': s.onTertiaryContainer.toARGB32(),
        'error': s.error.toARGB32(),
        'onError': s.onError.toARGB32(),
        'errorContainer': s.errorContainer.toARGB32(),
        'onErrorContainer': s.onErrorContainer.toARGB32(),
        'surface': s.surface.toARGB32(),
        'onSurface': s.onSurface.toARGB32(),
        'onSurfaceVariant': s.onSurfaceVariant.toARGB32(),
        'surfaceContainerLowest': s.surfaceContainerLowest.toARGB32(),
        'surfaceContainerLow': s.surfaceContainerLow.toARGB32(),
        'surfaceContainer': s.surfaceContainer.toARGB32(),
        'surfaceContainerHigh': s.surfaceContainerHigh.toARGB32(),
        'surfaceContainerHighest': s.surfaceContainerHighest.toARGB32(),
        'outline': s.outline.toARGB32(),
        'outlineVariant': s.outlineVariant.toARGB32(),
        'inverseSurface': s.inverseSurface.toARGB32(),
        'onInverseSurface': s.onInverseSurface.toARGB32(),
        'inversePrimary': s.inversePrimary.toARGB32(),
      };

  /// Cheap to call on every build: only writes when the schemes changed.
  static void publish(ColorScheme light, ColorScheme dark) {
    final json = jsonEncode({'light': _pack(light), 'dark': _pack(dark)});
    if (json == _last) return;
    _last = json;
    SharedPreferences.getInstance().then((p) => p.setString('themeScheme', json)).catchError((_) => false);
  }
}
