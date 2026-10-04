// Material You colour plates + scheme generator, ported from the Khmer Calendar app
// (theme.dart + widgets/scheme_chips.dart) so every app shares the same palette.
//
//   materialYouScheme(seed, brightness, extraDark: ...)  -> ColorScheme
//   MaterialYouChips(selected: ..., onPick: ...)         -> the scrolling plate row
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

class SchemeChip {
  const SchemeChip(this.id, this.label, this.circle, this.hue, this.top, this.bot);
  final int id;
  final String label;
  final Color circle;
  final double hue;
  final Color top;
  final Color bot;
}

Color hexColor(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

double _jsMod(double a, double n) => a - (a / n).truncateToDouble() * n;

double hueFromHex(String hex) {
  final t = hex.replaceFirst('#', '').padRight(6, '0');
  final n = int.parse(t.substring(0, 6), radix: 16);
  final r = ((n >> 16) & 255) / 255.0;
  final g = ((n >> 8) & 255) / 255.0;
  final b = (n & 255) / 255.0;
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  if (max == min) return 0;
  final c = max - min;
  double h;
  if (max == r) {
    h = _jsMod((g - b) / c, 6);
  } else if (max == g) {
    h = (b - r) / c + 2;
  } else {
    h = (r - g) / c + 4;
  }
  h *= 60;
  return h < 0 ? h + 360 : h;
}

String _py(double h, double s, double l) {
  final sat = s / 100;
  final lit = l / 100;
  final a = sat * math.min(lit, 1 - lit);
  String f(double n) {
    final k = (n + h / 30) % 12;
    final v = lit - a * math.max(math.min(math.min(k - 3, 9 - k), 1.0), -1.0);
    return (255 * v).round().toRadixString(16).padLeft(2, '0');
  }

  return '#${f(0)}${f(8)}${f(4)}';
}

SchemeChip _chip(int id, String label, String circleHex) {
  final hue = hueFromHex(circleHex);
  return SchemeChip(
    id,
    label,
    hexColor(circleHex),
    hue,
    hexColor(_py(hue, 16, 94)),
    hexColor(_py((hue + 16) % 360, 34, 80)),
  );
}

/// Same 14 colours, in the same order, as the Khmer Calendar.
final schemeChips = <SchemeChip>[
  _chip(0, 'Red', '#9a3b38'),
  _chip(1, 'Purple', '#68509f'),
  _chip(2, 'Blue', '#38618d'),
  _chip(3, 'Teal', '#146781'),
  _chip(4, 'Green', '#036a62'),
  _chip(5, 'Violet', '#68548e'),
  _chip(6, 'Magenta', '#7c4e7e'),
  _chip(7, 'Burgundy', '#8c4a61'),
  _chip(8, 'Brown', '#8e4d33'),
  _chip(9, 'Amber', '#84541a'),
  _chip(10, 'Forest', '#40693f'),
  _chip(11, 'Olive', '#586424'),
  _chip(12, 'Navy', '#3d4c7a'),
  _chip(13, 'Coral', '#c45c4a'),
];

const _roseLight = <String, String>{
  'primary': '#9a3b38',
  'onPrimary': '#ffffff',
  'primaryContainer': '#ffdad6',
  'onPrimaryContainer': '#410003',
  'secondary': '#775652',
  'onSecondary': '#ffffff',
  'secondaryContainer': '#ffdad6',
  'onSecondaryContainer': '#2c1512',
  'tertiary': '#1b7a6e',
  'onTertiary': '#ffffff',
  'tertiaryContainer': '#c5ebe3',
  'onTertiaryContainer': '#00201c',
  'surface': '#fffbff',
  'onSurface': '#2b1b1a',
  'surfaceVariant': '#f5ddda',
  'onSurfaceVariant': '#5d403c',
  'surfaceContainerLowest': '#ffffff',
  'surfaceContainerLow': '#fff1ef',
  'surfaceContainer': '#f8edeb',
  'surfaceContainerHigh': '#f3e7e5',
  'surfaceContainerHighest': '#ede0de',
  'outline': '#926f6b',
  'outlineVariant': '#e7beba',
  'inverseSurface': '#412e2c',
  'onInverseSurface': '#fceeea',
  'inversePrimary': '#ffb3ad',
};

const _roseDark = <String, String>{
  'primary': '#ffb3ad',
  'onPrimary': '#5f1413',
  'primaryContainer': '#7c2a27',
  'onPrimaryContainer': '#ffdad6',
  'secondary': '#e7bdb7',
  'onSecondary': '#442926',
  'secondaryContainer': '#5d3f3b',
  'onSecondaryContainer': '#ffdad6',
  'tertiary': '#a9cfc7',
  'onTertiary': '#003731',
  'tertiaryContainer': '#0b534a',
  'onTertiaryContainer': '#c5ebe3',
  'surface': '#1c1110',
  'onSurface': '#f6ddda',
  'surfaceVariant': '#5d403c',
  'onSurfaceVariant': '#e7beba',
  'surfaceContainerLowest': '#160c0b',
  'surfaceContainerLow': '#251817',
  'surfaceContainer': '#2a1c1b',
  'surfaceContainerHigh': '#352625',
  'surfaceContainerHighest': '#41312f',
  'outline': '#ad8985',
  'outlineVariant': '#5d403c',
  'inverseSurface': '#f6ddda',
  'onInverseSurface': '#412e2c',
  'inversePrimary': '#9a3b38',
};

Map<String, String> _cy(String hex, double hue, bool dark) {
  final i = (hue + 145) % 360;
  if (dark) {
    return {
      'primary': _py(hue, 72, 82),
      'onPrimary': _py(hue, 40, 18),
      'primaryContainer': _py(hue, 32, 28),
      'onPrimaryContainer': _py(hue, 78, 90),
      'secondary': _py(hue, 28, 80),
      'onSecondary': _py(hue, 22, 18),
      'secondaryContainer': _py(hue, 18, 26),
      'onSecondaryContainer': _py(hue, 50, 90),
      'tertiary': _py(i, 42, 78),
      'onTertiary': _py(i, 40, 14),
      'tertiaryContainer': _py(i, 28, 22),
      'onTertiaryContainer': _py(i, 50, 88),
      'surface': _py(hue, 14, 10),
      'onSurface': _py(hue, 22, 92),
      'surfaceVariant': _py(hue, 14, 28),
      'onSurfaceVariant': _py(hue, 18, 78),
      'surfaceContainerLowest': _py(hue, 16, 7),
      'surfaceContainerLow': _py(hue, 12, 13),
      'surfaceContainer': _py(hue, 12, 16),
      'surfaceContainerHigh': _py(hue, 12, 20),
      'surfaceContainerHighest': _py(hue, 12, 24),
      'outline': _py(hue, 14, 60),
      'outlineVariant': _py(hue, 14, 28),
      'inverseSurface': _py(hue, 22, 92),
      'onInverseSurface': _py(hue, 18, 22),
      'inversePrimary': hex,
    };
  }
  return {
    'primary': hex,
    'onPrimary': '#ffffff',
    'primaryContainer': _py(hue, 82, 90),
    'onPrimaryContainer': _py(hue, 42, 16),
    'secondary': _py(hue, 22, 40),
    'onSecondary': '#ffffff',
    'secondaryContainer': _py(hue, 48, 90),
    'onSecondaryContainer': _py(hue, 26, 16),
    'tertiary': _py(i, 48, 32),
    'onTertiary': '#ffffff',
    'tertiaryContainer': _py(i, 50, 88),
    'onTertiaryContainer': _py(i, 40, 12),
    'surface': _py(hue, 40, 99),
    'onSurface': _py(hue, 18, 14),
    'surfaceVariant': _py(hue, 28, 90),
    'onSurfaceVariant': _py(hue, 16, 32),
    'surfaceContainerLowest': '#ffffff',
    'surfaceContainerLow': _py(hue, 50, 96.5),
    'surfaceContainer': _py(hue, 36, 94),
    'surfaceContainerHigh': _py(hue, 30, 92),
    'surfaceContainerHighest': _py(hue, 24, 90),
    'outline': _py(hue, 16, 50),
    'outlineVariant': _py(hue, 22, 80),
    'inverseSurface': _py(hue, 18, 22),
    'onInverseSurface': _py(hue, 30, 94),
    'inversePrimary': _py(hue, 70, 80),
  };
}

/// Pure-black surfaces for dark mode ("extra dark" / AMOLED).
Map<String, String> _wy(Map<String, String> tokens, double hue) => {
      ...tokens,
      'surface': '#000000',
      'surfaceContainerLowest': '#000000',
      'surfaceContainerLow': _py(hue, 10, 5),
      'surfaceContainer': _py(hue, 10, 8),
      'surfaceContainerHigh': _py(hue, 10, 12),
      'surfaceContainerHighest': _py(hue, 10, 16),
    };

ColorScheme _fromTokens(Map<String, String> tok, Brightness brightness) {
  Color c(String k) => hexColor(tok[k]!);
  final dark = brightness == Brightness.dark;
  return ColorScheme(
    brightness: brightness,
    primary: c('primary'),
    onPrimary: c('onPrimary'),
    primaryContainer: c('primaryContainer'),
    onPrimaryContainer: c('onPrimaryContainer'),
    secondary: c('secondary'),
    onSecondary: c('onSecondary'),
    secondaryContainer: c('secondaryContainer'),
    onSecondaryContainer: c('onSecondaryContainer'),
    tertiary: c('tertiary'),
    onTertiary: c('onTertiary'),
    tertiaryContainer: c('tertiaryContainer'),
    onTertiaryContainer: c('onTertiaryContainer'),
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    onError: dark ? const Color(0xFF690005) : const Color(0xFFFFFFFF),
    errorContainer: dark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6),
    onErrorContainer: dark ? const Color(0xFFFFDAD6) : const Color(0xFF410002),
    surface: c('surface'),
    onSurface: c('onSurface'),
    surfaceContainerLowest: c('surfaceContainerLowest'),
    surfaceContainerLow: c('surfaceContainerLow'),
    surfaceContainer: c('surfaceContainer'),
    surfaceContainerHigh: c('surfaceContainerHigh'),
    surfaceContainerHighest: c('surfaceContainerHighest'),
    onSurfaceVariant: c('onSurfaceVariant'),
    outline: c('outline'),
    outlineVariant: c('outlineVariant'),
    inverseSurface: c('inverseSurface'),
    onInverseSurface: c('onInverseSurface'),
    inversePrimary: c('inversePrimary'),
    surfaceTint: c('primary'),
  );
}

/// Khmer-Calendar-style Material You scheme for any seed colour. The 14 preset
/// colours give exactly the calendar's palette (red uses its hand-tuned tokens).
ColorScheme materialYouScheme(Color seed, Brightness brightness, {bool extraDark = false}) {
  final dark = brightness == Brightness.dark;
  final rgb = seed.toARGB32() & 0xFFFFFF;
  final hex = '#${rgb.toRadixString(16).padLeft(6, '0')}';
  final hue = hueFromHex(hex);
  var tokens = rgb == 0x9A3B38
      ? Map<String, String>.from(dark ? _roseDark : _roseLight)
      : _cy(hex, hue, dark);
  if (extraDark && dark) tokens = _wy(tokens, hue);
  return _fromTokens(tokens, brightness);
}

/// The scrolling row of Material You colour plates (replaces the old chips / circles).
class MaterialYouChips extends StatelessWidget {
  const MaterialYouChips({
    super.key,
    required this.selected,
    required this.onPick,
    this.enabled = true,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 6),
  });

  /// Colour of the currently selected plate (matched by RGB); null = none selected.
  final Color? selected;
  final ValueChanged<SchemeChip> onPick;
  final bool enabled;

  /// Row padding. The default matches the calendar's full-bleed lists; use
  /// `EdgeInsets.symmetric(vertical: 6)` inside an already-padded page.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final sel = selected == null ? null : selected!.toARGB32() & 0xFFFFFF;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: SizedBox(
        height: 76,
        // Let mouse / trackpad users drag the row too (needed on web).
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: ListView.separated(
            padding: padding,
            scrollDirection: Axis.horizontal,
            itemCount: schemeChips.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = schemeChips[i];
              return Tooltip(
                message: s.label,
                child: _Plate(
                  chip: s,
                  selected: sel == (s.circle.toARGB32() & 0xFFFFFF),
                  onTap: enabled ? () => onPick(s) : null,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({required this.chip, required this.selected, required this.onTap});
  final SchemeChip chip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.4)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: chip.top,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? chip.circle : Colors.transparent, width: 3),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                  child: Container(height: 32, color: chip.bot),
                ),
              ),
              Center(
                child: Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(color: chip.circle, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
