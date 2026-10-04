import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/settings/settings.dart';

class PictureLooks {
  const PictureLooks({
    required this.mirror,
    required this.invert,
    required this.grayscale,
    required this.colorCorrection,
    required this.contrast,
    required this.saturation,
    required this.deuteranopia,
    required this.protanopia,
    required this.tritanopia,
    required this.night,
    required this.nightWarmth,
    required this.extraDim,
  });

  final bool mirror;
  final bool invert;
  final bool grayscale;
  final bool colorCorrection;
  final double contrast;
  final double saturation;
  final bool deuteranopia;
  final bool protanopia;
  final bool tritanopia;
  final bool night;
  final double nightWarmth;
  final bool extraDim;

  factory PictureLooks.current({
    bool? invert,
    bool? mirror,
    bool? night,
  }) {
    final s = appSettings;
    return PictureLooks(
      mirror: mirror ?? s.mirror,
      invert: invert ?? s.invertColors,
      grayscale: s.grayscale,
      colorCorrection: s.colorCorrection,
      contrast: s.contrast,
      saturation: s.saturation,
      deuteranopia: s.colorBlindDeuteranopia,
      protanopia: s.colorBlindProtanopia,
      tritanopia: s.colorBlindTritanopia,
      night: night ?? s.nightMode,
      nightWarmth: s.nightWarmth,
      extraDim: s.extraDim,
    );
  }
}

class PictureMatrices {
  PictureMatrices._();

  static const invert = <double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];
  static const gray = <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];
  static const deut = <double>[
    0.625, 0.375, 0, 0, 0,
    0.7, 0.3, 0, 0, 0,
    0, 0.3, 0.7, 0, 0,
    0, 0, 0, 1, 0,
  ];
  static const prot = <double>[
    0.567, 0.433, 0, 0, 0,
    0.558, 0.442, 0, 0, 0,
    0, 0.242, 0.758, 0, 0,
    0, 0, 0, 1, 0,
  ];
  static const trit = <double>[
    0.95, 0.05, 0, 0, 0,
    0, 0.433, 0.567, 0, 0,
    0, 0.475, 0.525, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static List<double> contrastSaturation(double c, double s) {
    const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
    final sr = (1 - s) * lumR;
    final sg = (1 - s) * lumG;
    final sb = (1 - s) * lumB;
    final t = (1 - c) / 2 * 255;
    return [
      c * (sr + s), c * sg, c * sb, 0, t,
      c * sr, c * (sg + s), c * sb, 0, t,
      c * sr, c * sg, c * (sb + s), 0, t,
      0, 0, 0, 1, 0,
    ];
  }
}

class VideoPicture extends StatelessWidget {
  const VideoPicture({
    super.key,
    required this.child,
    required this.looks,
  });

  final Widget child;
  final PictureLooks looks;

  @override
  Widget build(BuildContext context) {
    Widget player = child;
    if (looks.mirror) {
      player = Transform.flip(flipX: true, child: player);
    }
    final filters = <ColorFilter>[];
    if (looks.invert) {
      filters.add(const ColorFilter.matrix(PictureMatrices.invert));
    }
    if (looks.grayscale) {
      filters.add(const ColorFilter.matrix(PictureMatrices.gray));
    }
    if (looks.colorCorrection && (looks.contrast != 1 || looks.saturation != 1)) {
      filters.add(ColorFilter.matrix(
          PictureMatrices.contrastSaturation(looks.contrast, looks.saturation)));
    }
    if (looks.deuteranopia) {
      filters.add(const ColorFilter.matrix(PictureMatrices.deut));
    }
    if (looks.protanopia) {
      filters.add(const ColorFilter.matrix(PictureMatrices.prot));
    }
    if (looks.tritanopia) {
      filters.add(const ColorFilter.matrix(PictureMatrices.trit));
    }
    for (final f in filters) {
      player = ColorFiltered(colorFilter: f, child: player);
    }
    if (looks.night) {
      player = ColorFiltered(
        colorFilter: ColorFilter.mode(
          Color.fromARGB((80 + looks.nightWarmth * 80).round(), 255, 140, 40),
          BlendMode.multiply,
        ),
        child: player,
      );
    }
    if (looks.extraDim) {
      player = ColorFiltered(
        colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken),
        child: player,
      );
    }
    return player;
  }
}


class VlcFit extends StatelessWidget {
  const VlcFit({
    super.key,
    required this.visW,
    required this.visH,
    required this.screen,
    required this.mode,
    required this.child,
  });

  final double visW;
  final double visH;
  final Size screen;
  final AspectMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sw = screen.width;
    final sh = screen.height;
    if (sw < 2 || sh < 2) return ClipRect(child: child);
    final vw = math.max(visW, 1.0);
    final vh = math.max(visH, 1.0);
    var dw = sw;
    var dh = sh;
    var ar = vw / vh;
    final dar = dw / dh;
    switch (mode) {
      case AspectMode.fit:
        if (dar < ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
      case AspectMode.zoom:
        if (dar >= ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
      case AspectMode.stretch:
        break;
      case AspectMode.original:
        dw = vw;
        dh = vh;
        final down = math.min(1.0, math.min(sw / dw, sh / dh));
        dw *= down;
        dh *= down;
      case AspectMode.ratio16_9:
        ar = 16 / 9;
        if (dar < ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
      case AspectMode.ratio4_3:
        ar = 4 / 3;
        if (dar < ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
      case AspectMode.ratio21_9:
        ar = 21 / 9;
        if (dar < ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
      case AspectMode.ratio2_35:
        ar = 2.35;
        if (dar < ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
      case AspectMode.ratio1_1:
        ar = 1;
        if (dar < ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
      case AspectMode.ratio9_16:
        ar = 9 / 16;
        if (dar < ar) {
          dh = dw / ar;
        } else {
          dw = dh * ar;
        }
    }
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: sw,
        height: sh,
        child: Center(
          child: SizedBox(width: dw, height: dh, child: child),
        ),
      ),
    );
  }
}
