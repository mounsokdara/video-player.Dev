import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/core/developer_log.dart';
import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/playback/render_profile.dart';
import 'package:video_player_app/settings/settings.dart';

class EngineValue {
  const EngineValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.hasError = false,
    this.completed = false,
    this.errorDescription,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.size = Size.zero,
  });

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool hasError;
  final bool completed;
  final String? errorDescription;
  final Duration position;
  final Duration duration;
  final Size size;

  EngineValue withPosition(Duration p) => EngineValue(
        isInitialized: isInitialized,
        isPlaying: isPlaying,
        isBuffering: isBuffering,
        hasError: hasError,
        completed: completed,
        errorDescription: errorDescription,
        position: p,
        duration: duration,
        size: size,
      );
}

/// Channel to our own playback engine (android/.../engine/NativePlayer.kt):
/// MediaExtractor -> MediaCodec (or FFmpeg software decode) -> Flutter texture, AudioTrack for sound.
/// There is one native player per Flutter engine, so the instance that opened last owns it.
class _NativeBus {
  static const method = MethodChannel('app.videoplayer/engine');
  static const events = EventChannel('app.videoplayer/engine_events');
  static StreamSubscription<dynamic>? _sub;
  static PlaybackEngine? owner;

  static void ensure() {
    _sub ??= events.receiveBroadcastStream().listen(
      (e) => owner?._onNative(e),
      onError: (Object _) {},
    );
  }

  static Future<T?> call<T>(String name, [Map<String, Object?>? args]) async {
    try {
      return await method.invokeMethod<T>(name, args);
    } on PlatformException catch (e) {
      DeveloperLog.append('engine $name failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class PlaybackEngine extends ChangeNotifier {
  static final _alive = <PlaybackEngine>{};

  EngineValue value = const EngineValue();
  bool _closed = false;
  bool _opened = false;
  Future<void>? _inFlight;
  double _rate = 1;
  bool _pitchShift = false;
  double _volume = 1;
  bool _looping = false;
  bool wantPlay = false;
  String debugInfo = '';

  // texture + decoder info (from the native open())
  int? textureId;
  int quarterTurns = 0;
  Size displaySize = Size.zero;
  String _decoder = '';
  bool _software = false;

  // live state (from native 'state' events)
  bool _nativePlaying = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _completed = false;
  bool _fatal = false;
  String? _fatalText;

  bool get hasPlayer => _opened && !_closed;

  bool get _mine => identical(_NativeBus.owner, this) && !_closed;

  /// The frame is not available to Dart (it lives in a GPU texture), so there is nothing to save
  /// here. The caller falls back to the native frame extractor (AndroidBridge.extractFrame).
  Future<String?> screenshotToFile(ScreenshotFormat format) async => null;

  String get hwdecName => _decoder.isEmpty ? 'unknown' : _decoder;

  /// True while the FFmpeg software decoder is producing the picture.
  bool get softwareDecode => _software;

  int _openSeq = 0;
  String? _pendingKey;
  Future<void>? _pendingOpen;

  Future<void> open(String path, {required String hwdec}) {
    final key = '$path|$hwdec';
    final pending = _pendingOpen;
    if (pending != null && _pendingKey == key && !_closed) {
      DeveloperLog.player('open skipped (duplicate in flight) path=$path');
      return pending;
    }
    DeveloperLog.player('open path=$path hwdec=$hwdec');
    final seq = ++_openSeq;
    final f = _queue(() async {
      if (seq != _openSeq) return;
      await _openBody(path, hwdec: hwdec);
    });
    _pendingKey = key;
    _pendingOpen = f;
    void clear() {
      if (identical(_pendingOpen, f)) {
        _pendingKey = null;
        _pendingOpen = null;
      }
    }

    f.then((_) => clear(), onError: (Object _) => clear());
    return f;
  }

  Future<void> _queue(Future<void> Function() job) async {
    while (_inFlight != null) {
      try {
        await _inFlight;
      } catch (_) {}
    }
    final gate = Completer<void>();
    _inFlight = gate.future;
    try {
      await job();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_inFlight, gate.future)) _inFlight = null;
    }
  }

  String _source(String path) {
    if (path.startsWith('content:') ||
        path.startsWith('http:') ||
        path.startsWith('https:') ||
        path.startsWith('file:')) {
      return path;
    }
    return path; // plain file path: the native side opens it directly
  }

  Future<void> _openBody(String path, {required String hwdec}) async {
    _closed = false;
    _alive.add(this);
    await _pauseOthers();
    _NativeBus.ensure();
    _NativeBus.owner = this;
    value = const EngineValue();
    _resetPerFile();
    notifyListeners();

    Map<dynamic, dynamic>? info;
    try {
      info = await _NativeBus.method.invokeMapMethod<dynamic, dynamic>('open', {
        'path': _source(path),
        'preferSoftware': hwdec == 'no',
      });
    } on PlatformException catch (e) {
      final text = e.message ?? 'Source error';
      value = EngineValue(hasError: true, errorDescription: text);
      notifyListeners();
      DeveloperLog.player('open error=$text');
      throw StateError(text);
    }
    if (_closed || !_mine) return;
    _opened = true;

    final i = info ?? const {};
    _dur = Duration(milliseconds: (i['durationMs'] as num?)?.toInt() ?? 0);
    final w = (i['width'] as num?)?.toInt() ?? 0;
    final h = (i['height'] as num?)?.toInt() ?? 0;
    quarterTurns = ((((i['rotation'] as num?)?.toInt() ?? 0) ~/ 90) % 4 + 4) % 4;
    final turned = quarterTurns.isOdd;
    displaySize = (w > 0 && h > 0) ? (turned ? Size(h.toDouble(), w.toDouble()) : Size(w.toDouble(), h.toDouble())) : Size.zero;
    final tex = (i['textureId'] as num?)?.toInt() ?? -1;
    textureId = tex >= 0 ? tex : null;
    _decoder = (i['decoder'] as String?) ?? '';
    _software = (i['software'] as bool?) ?? false;
    _src = _sourceFrom(i);
    await _prepareRender();

    await _NativeBus.call('setVolume', {'value': _volume});
    await _pushTempo();
    _emit();
    DeveloperLog.append('engine ready decoder=$_decoder software=$_software ${_src?.describe() ?? ''}');
  }

  // ---------- tempo ----------

  Future<void> applyTempo({required double rate, required bool pitchShift}) async {
    DeveloperLog.player('tempo rate=$rate pitchShift=$pitchShift');
    _rate = rate.clamp(0.25, 8.0).toDouble();
    _pitchShift = pitchShift;
    if (_mine) await _pushTempo();
  }

  // Pitch shift on: pitch follows speed (tape style). Off: pitch is preserved at any speed.
  Future<void> _pushTempo() async {
    final rate = _rate <= 0 ? 1.0 : _rate;
    await _NativeBus.call('setSpeed', {'value': rate});
    await _NativeBus.call('setPitch', {'value': _pitchShift ? rate : 1.0});
  }

  // ---------- render / HDR ----------

  SourceInfo? _src;
  bool _convert = false;
  bool _sdrMode = false;

  bool get hdrActive => _convert;

  bool get sdrMode => _sdrMode;

  SourceInfo? get source => _src;

  void _resetPerFile() {
    _src = null;
    _convert = false;
    debugInfo = '';
    textureId = null;
    _decoder = '';
    _software = false;
    _completed = false;
    _fatal = false;
    _fatalText = null;
    _pos = Duration.zero;
    _dur = Duration.zero;
    _nativePlaying = false;
    _seekTarget = null;
  }

  /// Translates what the native engine knows about the stream into the app's SourceInfo.
  SourceInfo _sourceFrom(Map<dynamic, dynamic> i) {
    final bits = (i['bitDepth'] as num?)?.toInt() ?? 8;
    final hasVideo = (i['hasVideo'] as bool?) ?? false;
    final transfer = (i['colorTransfer'] as num?)?.toInt();
    final std = (i['colorStandard'] as num?)?.toInt();
    final cll = (i['maxCll'] as num?)?.toDouble() ?? 0;
    final lum = (i['maxLuminance'] as num?)?.toDouble() ?? 0;
    final peak = cll > 0 ? cll : lum;
    String prim = '', matrix = '';
    switch (std) {
      case 6:
        prim = 'bt.2020';
        matrix = 'bt.2020-ncl';
      case 1:
        prim = 'bt.709';
        matrix = 'bt.709';
      case 2:
      case 4:
        prim = 'bt.601';
        matrix = 'bt.601';
    }
    final gamma = switch (transfer) {
      7 => 'hlg',
      6 => 'pq',
      3 => 'bt.1886',
      _ => hasVideo ? 'bt.1886' : '',
    };
    return SourceInfo(
      pix: !hasVideo ? '' : (bits >= 10 ? 'yuv420p10le' : 'yuv420p'),
      gamma: gamma,
      primaries: prim,
      matrix: matrix,
      sigPeak: peak > 0 ? (peak / 203).toStringAsFixed(2) : '',
      w: displaySize.width.round(),
      h: displaySize.height.round(),
      fps: (i['fps'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> _prepareRender() async {
    final rs = RenderSettings.instance;
    await rs.load();
    final src = _src;
    if (_closed || src == null) return;
    _convert = src.needsConvert;
    _sdrMode = appSettings.rememberHdr && !appSettings.hdrOn;
    DeveloperLog.append('video ${src.describe()} decoder=$_decoder');
    await _pushTuning();
    _describe();
  }

  void _describe() {
    final src = _src;
    if (src == null) return;
    final mode = _convert ? (_sdrMode ? 'HDR->SDR' : 'HDR look') : 'SDR source';
    debugInfo = '$mode | ${src.w}x${src.h} ${src.fps.toStringAsFixed(0)}fps | ${_software ? 'software' : 'hardware'} | ${src.describe()}';
    DeveloperLog.append('render $debugInfo');
    notifyListeners();
  }

  // The HDR "look" controls (peak / gamma) shape the software decoder's tone mapping.
  Future<void> _pushTuning() async {
    final t = RenderSettings.instance.tuning(sdr: _sdrMode);
    await _NativeBus.call('setTuning', {'peak': t.peak, 'gamma': t.gamma});
  }

  Future<void> retune() async {
    if (!_mine || !_convert) return;
    await _pushTuning();
  }

  Future<void> reapplyRender() async {
    if (!_mine) return;
    await _pushTuning();
    _describe();
  }

  Future<void> setSdrMode(bool sdr) async {
    _sdrMode = sdr;
    appSettings.hdrOn = !sdr;
    if (appSettings.rememberHdr) unawaited(appSettings.save());
    if (_mine && _convert) await _pushTuning();
    notifyListeners();
  }

  // ---------- native events ----------

  void _onNative(dynamic e) {
    if (e is! Map || _closed) return;
    switch (e['type']) {
      case 'state':
        _nativePlaying = (e['playing'] as bool?) ?? _nativePlaying;
        _pos = Duration(milliseconds: (e['positionMs'] as num?)?.toInt() ?? 0);
        final d = (e['durationMs'] as num?)?.toInt() ?? 0;
        if (d > 0) _dur = Duration(milliseconds: d);
        if (_nativePlaying) _completed = false;
        _emit();
      case 'decoder':
        _decoder = (e['name'] as String?) ?? _decoder;
        _software = _decoder.startsWith('software');
        DeveloperLog.append('decoder $_decoder');
        _describe();
      case 'ended':
        if (_looping) {
          unawaited(_NativeBus.call('play'));
        } else {
          _completed = true;
          _nativePlaying = false;
          _emit();
        }
      case 'error':
        final text = (e['message'] as String?) ?? 'Playback error';
        DeveloperLog.append('engine: $text');
        if (e['fatal'] == true) {
          _fatal = true;
          _fatalText = text;
          _emit();
        }
    }
  }

  // While a seek is in flight we show the target instead of the position that is about to be
  // replaced, so the seek bar does not jump back and forth. It settles near the target.
  Duration? _seekTarget;
  DateTime _seekAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _seekMinHold = Duration(milliseconds: 250);
  static const _seekMaxHold = Duration(milliseconds: 1200);
  static const _seekTolerance = Duration(milliseconds: 1200);

  Duration _shownPosition() {
    final real = _pos;
    final target = _seekTarget;
    if (target == null) return real;
    final age = DateTime.now().difference(_seekAt);
    if (age >= _seekMaxHold || (age >= _seekMinHold && (real - target).abs() <= _seekTolerance)) {
      _seekTarget = null;
      return real;
    }
    return target;
  }

  void _emit() {
    if (_closed) return;
    if (_fatal) {
      value = EngineValue(
        isInitialized: value.isInitialized,
        hasError: true,
        errorDescription: _fatalText,
        position: value.position,
        duration: value.duration,
        size: value.size,
      );
      notifyListeners();
      return;
    }
    value = EngineValue(
      isInitialized: _opened,
      isPlaying: _nativePlaying,
      isBuffering: false,
      hasError: false,
      completed: _completed,
      position: _completed ? _dur : _shownPosition(),
      duration: _dur,
      size: displaySize,
    );
    notifyListeners();
  }

  // ---------- transport ----------

  Future<void> play() async {
    DeveloperLog.player('play');
    wantPlay = true;
    _alive.add(this);
    await _pauseOthers();
    if (!_mine) return;
    await _NativeBus.call('play');
  }

  Future<void> pause() async {
    DeveloperLog.player('pause');
    wantPlay = false;
    if (_mine) await _NativeBus.call('pause');
  }

  Future<void> _pauseOthers() async {
    final others = _alive.where((e) => !identical(e, this) && !e._closed).toList();
    for (final e in others) {
      e.wantPlay = false;
      e._nativePlaying = false;
      e._emit();
    }
  }

  /// [fast] snaps to the nearest keyframe instead of decoding up to the exact
  /// frame. Use it for scrubbing; exact seeks are slow on long-GOP or
  /// software-decoded video.
  Future<void> seekTo(Duration d, {bool fast = false}) async {
    DeveloperLog.player('seek ${d.inMilliseconds}ms${fast ? ' (keyframe)' : ''}');
    if (!hasPlayer || !_mine) return;
    _seekTarget = d;
    _seekAt = DateTime.now();
    _completed = false;
    if (!value.hasError) {
      value = value.withPosition(d);
      notifyListeners();
    }
    await _NativeBus.call('seek', {'positionMs': d.inMilliseconds, 'accurate': !fast});
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0).toDouble();
    if (_mine) await _NativeBus.call('setVolume', {'value': _volume});
  }

  Future<void> setLooping(bool on) async {
    DeveloperLog.player('looping=$on');
    _looping = on;
  }

  Future<void> close() async {
    if (_closed) return;
    DeveloperLog.player('close');
    final wasOwner = identical(_NativeBus.owner, this);
    _closed = true;
    _seekTarget = null;
    wantPlay = false;
    _openSeq++;
    _alive.remove(this);
    final inFlight = _inFlight;
    if (inFlight != null) {
      try {
        await inFlight.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    // Only stop the native player if a newer engine did not already take it over.
    if (wasOwner && identical(_NativeBus.owner, this)) {
      _NativeBus.owner = null;
      await _NativeBus.call('stop');
    }
    _opened = false;
    textureId = null;
    value = const EngineValue();
    notifyListeners();
    super.dispose();
  }

  @override
  void dispose() {
    unawaited(close());
  }
}

class AppVideo extends StatefulWidget {
  const AppVideo({super.key, required this.engine, this.fit = BoxFit.fill, this.showLog = true});
  final PlaybackEngine engine;
  final BoxFit fit;

  /// The developer log overlay is far too big for small surfaces such as the mini player.
  final bool showLog;

  @override
  State<AppVideo> createState() => _AppVideoState();
}

class VideoLogOverlay extends StatelessWidget {
  const VideoLogOverlay({super.key, required this.engine});

  final PlaybackEngine engine;

  String _fmt(Duration d) {
    final ms = d.inMilliseconds;
    final h = ms ~/ 3600000;
    final m = (ms ~/ 60000) % 60;
    final s = (ms ~/ 1000) % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final v = engine.value;
    final src = engine.source;
    final screen = ScreenInfo.current();
    final lines = <String>['VIDEO LOG'];
    if (appSettings.videoLogShowState) {
      lines.add('STATE  ${v.isPlaying ? 'PLAYING' : 'PAUSED'}${v.isBuffering ? ' · BUFFERING' : ''}');
      lines.add('TIME   ${_fmt(v.position)} / ${_fmt(v.duration)}');
      lines.add('SIZE   ${v.size.width.round()}×${v.size.height.round()}  ${src?.fps.toStringAsFixed(2) ?? '--'} fps');
      lines.add('ERROR  ${v.hasError ? (v.errorDescription ?? 'unknown') : 'none'}');
    }
    if (appSettings.videoLogShowMedia && src != null) {
      lines.add('MEDIA  ${src.pix} · ${src.gamma}');
      lines.add('COLOR  ${src.primaries} · ${src.matrix} · peak=${src.sigPeak}');
      lines.add('HDR    ${src.hdr ? 'HDR' : 'SDR'} · deep=${src.deep}');
    }
    if (appSettings.videoLogShowRender) {
      lines.add('RENDER ${engine.sdrMode ? 'SDR' : 'HDR'} mode · ${engine.debugInfo.isEmpty ? '-' : engine.debugInfo}');
    }
    if (appSettings.videoLogShowDecoder) {
      lines.add('DECODER ${engine.hwdecName} · hw=${!engine.softwareDecode}');
    }
    if (appSettings.videoLogShowTiming) {
      lines.add('SCREEN ${screen.width.round()}×${screen.height.round()} · ${screen.hz.toStringAsFixed(1)}Hz');
    }
    return Positioned(
      left: 6,
      top: 40,
      right: 6,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: Colors.black.withValues(alpha: 0.58),
          child: Text(
            lines.join('\n'),
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 10,
              height: 1.2,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

class _AppVideoState extends State<AppVideo> {
  int? _texture;
  String _info = '';

  @override
  void initState() {
    super.initState();
    _texture = widget.engine.textureId;
    widget.engine.addListener(_onEngine);
  }

  @override
  void didUpdateWidget(covariant AppVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.engine, widget.engine)) {
      oldWidget.engine.removeListener(_onEngine);
      widget.engine.addListener(_onEngine);
      _texture = widget.engine.textureId;
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() {
    final next = widget.engine.textureId;
    final info = widget.engine.debugInfo;
    if (mounted && (next != _texture || info != _info)) {
      setState(() {
        _texture = next;
        _info = info;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _texture;
    if (id == null) return const ColoredBox(color: Colors.black);
    final size = widget.engine.displaySize;
    final w = size.width > 1 ? size.width : 16.0;
    final h = size.height > 1 ? size.height : 9.0;
    // The texture holds the coded frame; the codec's rotation is applied here.
    final video = ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: w,
          height: h,
          child: RotatedBox(
            quarterTurns: widget.engine.quarterTurns,
            child: Texture(textureId: id),
          ),
        ),
      ),
    );
    if (!widget.showLog || !appSettings.developerEnabled || !appSettings.videoLogOverlay) return video;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        video,
        VideoLogOverlay(engine: widget.engine),
      ],
    );
  }
}
