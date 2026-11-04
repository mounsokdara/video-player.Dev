import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

class HdrTuning {
  const HdrTuning(this.peak, this.gamma);
  final int peak;
  final int gamma;
}

class RenderSettings {
  RenderSettings._();
  static final RenderSettings instance = RenderSettings._();

  static const defaultPeakHdr = 203;
  static const defaultPeakSdr = 203;

  int peakHdr = defaultPeakHdr;
  int gammaHdr = 0;
  int peakSdr = defaultPeakSdr;
  int gammaSdr = 0;

  bool _loaded = false;

  HdrTuning tuning({required bool sdr}) =>
      sdr ? HdrTuning(peakSdr, gammaSdr) : HdrTuning(peakHdr, gammaHdr);

  void setTuning({required bool sdr, int? peak, int? gamma}) {
    if (sdr) {
      if (peak != null) peakSdr = peak.clamp(50, 2000);
      if (gamma != null) gammaSdr = gamma.clamp(-100, 100);
    } else {
      if (peak != null) peakHdr = peak.clamp(50, 2000);
      if (gamma != null) gammaHdr = gamma.clamp(-100, 100);
    }
  }

  void resetTuning({required bool sdr}) {
    if (sdr) {
      peakSdr = defaultPeakSdr;
      gammaSdr = 0;
    } else {
      peakHdr = defaultPeakHdr;
      gammaHdr = 0;
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      peakHdr = (p.getInt('rs_peakHdr') ?? p.getInt('hdrPeak') ?? defaultPeakHdr).clamp(50, 2000);
      gammaHdr = (p.getInt('rs_gammaHdr') ?? p.getInt('hdrGamma') ?? 0).clamp(-100, 100);
      peakSdr = (p.getInt('rs_peakSdr') ?? defaultPeakSdr).clamp(50, 2000);
      gammaSdr = (p.getInt('rs_gammaSdr') ?? 0).clamp(-100, 100);
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('rs_peakHdr', peakHdr);
      await p.setInt('rs_gammaHdr', gammaHdr);
      await p.setInt('rs_peakSdr', peakSdr);
      await p.setInt('rs_gammaSdr', gammaSdr);
      await p.remove('rs_resMode');
      await p.remove('rs_resValue');
    } catch (_) {}
  }
}

class SourceInfo {
  const SourceInfo({
    required this.pix,
    required this.gamma,
    required this.primaries,
    required this.matrix,
    required this.sigPeak,
    required this.w,
    required this.h,
    required this.fps,
  });

  final String pix;
  final String gamma;
  final String primaries;
  final String matrix;
  final String sigPeak;
  final int w;
  final int h;
  final double fps;

  bool get decoded => pix.isNotEmpty;

  bool get hdr {
    if (gamma.contains('hlg') ||
        gamma.contains('pq') ||
        gamma.contains('st2084') ||
        gamma.contains('smpte2084') ||
        gamma.contains('bt.2100')) {
      return true;
    }
    if (primaries.contains('2020')) {
      final peak = double.tryParse(sigPeak);
      if (peak != null && peak > 1.1) return true;
      if (deep) return true;
    }
    return matrix.contains('2020');
  }

  bool get deep => RegExp(r'p0(10|12|16)|p(10|12|14|16)(le|be)?$').hasMatch(pix);

  bool get needsConvert => hdr || deep;

  String describe() =>
      'pix=$pix gamma=$gamma prim=$primaries matrix=$matrix peak=$sigPeak size=${w}x$h fps=${fps.toStringAsFixed(2)} hdr=$hdr deep=$deep';
}

class ScreenInfo {
  const ScreenInfo(this.width, this.height, this.hz);
  final double width;
  final double height;
  final double hz;

  static ScreenInfo current() {
    try {
      final view = ui.PlatformDispatcher.instance.views.first;
      final size = view.physicalSize;
      final hz = view.display.refreshRate;
      return ScreenInfo(size.width, size.height, hz >= 1 ? hz : 60);
    } catch (_) {
      return const ScreenInfo(0, 0, 60);
    }
  }
}

class RenderCaps {
  const RenderCaps._();
  static bool? scale;

  static bool? of(String token) => token == 'scale' ? scale : null;

  static void set(String token, bool value) {
    if (token == 'scale') scale = value;
  }
}

class RenderPlan {
  const RenderPlan({required this.baseline, required this.extras});

  final String baseline;
  final List<String> extras;

  String get key => [...extras, if (baseline.isNotEmpty) baseline].join(',');

  String describe(SourceInfo src) =>
      '${src.w}x${src.h} ${src.fps.toStringAsFixed(0)}fps vf=${key.isEmpty ? '-' : key}';
}

class RenderProfile {
  const RenderProfile._();

  static RenderPlan plan({required RenderSettings settings, required SourceInfo src}) {
    return RenderPlan(
      baseline: src.needsConvert ? 'format=yuv420p' : '',
      extras: const [],
    );
  }
}
