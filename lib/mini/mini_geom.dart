import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:video_player_app/playback/session.dart';

class MiniGeom {
  MiniGeom._();
  static const defW = 168.0;
  static const minW = 96.0;
  static const maxW = 420.0;
  static const fallbackAr = 16 / 9;
  static const barH = 40.0;
  // Gap kept between the mini player and every edge of the content area.
  // 16 matches the page padding used by the video list.
  static const safeInset = 16.0;
  // Extra gap under the status bar (the status bar inset is added on top).
  static const topGap = 8.0;
  // Below this width the title is dropped and the 3 buttons are spread out.
  static const compactW = 200.0;
  static const arrowMaxW = 28.0;
  static const arrowH = 96.0;
  static const parkT = 0.6;
  static const rubber = 0.35;
  static const tapSlop = 5.0;
  // Smallest finger spread used as the pinch baseline (stops a tiny starting spread from
  // turning a small finger move into a huge resize).
  static const minPinchSpan = 24.0;
}

class MiniPhysics {
  MiniPhysics._();

  static Size videoSize() {
    try {
      final s = PlaybackSession.controller?.value.size;
      if (s != null && s.width > 1 && s.height > 1) return s;
    } catch (_) {}
    final item = PlaybackSession.item;
    if (item != null && item.width > 1 && item.height > 1) {
      return Size(item.width.toDouble(), item.height.toDouble());
    }
    return const Size(216, 122);
  }

  static double aspect(Size video) {
    if (video.width <= 0 || video.height <= 0) return MiniGeom.fallbackAr;
    if (video.height >= video.width) return 9 / 16;
    return 16 / 9;
  }

  static Size boxFor(double w, Size video) {
    final ar = aspect(video);
    return Size(w, w / ar + MiniGeom.barH);
  }

  /// [area] is the real size of the region the mini player lives in (the
  /// Scaffold body), not the whole screen.
  static double maxWFor(Size area, [Size? video]) {
    final v = video ?? videoSize();
    final short = math.min(area.width, area.height);
    final ar = aspect(v);
    final minBoxH = MiniGeom.barH + 80;
    final capH = math.max(minBoxH, area.height - MiniGeom.safeInset * 2 - MiniGeom.topGap);
    final maxBoxH = math.max(minBoxH, math.min(area.height * 0.6, capH));
    final fromH = (maxBoxH - MiniGeom.barH) * ar;
    final fromW = math.min(area.width - MiniGeom.safeInset * 2, short * 0.72);
    final hi = math.min(MiniGeom.maxW, math.min(fromH, fromW));
    return math.max(72.0, hi);
  }

  static double defaultW(Size screen, [Size? video]) {
    final short = math.min(screen.width, screen.height);
    return clampW(short * 0.36, screen, video);
  }

  static double clampW(double w, Size screen, [Size? video]) {
    final hi = maxWFor(screen, video);
    final lo = math.min(MiniGeom.minW, hi);
    return w.clamp(lo, hi).toDouble();
  }

  static double softClamp(double v, double lo, double hi, [double k = MiniGeom.rubber]) {
    if (v < lo) return lo - (lo - v) * k;
    if (v > hi) return hi + (v - hi) * k;
    return v;
  }

  /// Rectangle (in [area] coordinates) where the mini player may rest.
  /// [area] already excludes the bottom navigation bar and the left / right
  /// system insets, because it is measured from the Scaffold body.
  /// [topInset] is the status bar height; [bottomInset] is only non-zero
  /// when the body runs under the system navigation bar (no app nav bar).
  static Rect safeZone(Size area, {required double topInset, required double bottomInset}) {
    const m = MiniGeom.safeInset;
    final l = m;
    final t = topInset + MiniGeom.topGap;
    final r = math.max(l, area.width - m);
    final b = math.max(t, area.height - m - bottomInset);
    return Rect.fromLTRB(l, t, r, b);
  }

  static Offset edgeTarget(Offset p, double w, double h, Rect safe) {
    final leftX = safe.left;
    final rightX = math.max(safe.left, safe.right - w);
    final goLeft = (p.dx + w / 2) < (safe.left + safe.right) / 2;
    final maxY = math.max(safe.top, safe.bottom - h);
    return Offset(goLeft ? leftX : rightX, p.dy.clamp(safe.top, maxY).toDouble());
  }

  static Offset defaultPos(Size screen, double w, double h, Rect safe) {
    return Offset(
      math.max(safe.left, safe.right - w),
      math.max(safe.top, safe.bottom - h),
    );
  }
}
