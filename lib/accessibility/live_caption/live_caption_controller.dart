import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:video_player_app/native/android_bridge.dart';

class CaptionCue {
  const CaptionCue(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

/// Owns the live caption session for the current video. It lives outside any widget, so the
/// captions survive hiding or showing the controls, switching between the full player and the mini
/// player, and leaving the player: overlays only attach to it and draw what it holds.
class LiveCaptionController extends ChangeNotifier {
  LiveCaptionController._();
  static final LiveCaptionController instance = LiveCaptionController._();

  final List<CaptionCue> _cues = [];
  final Set<String> _keys = {};
  StreamSubscription<Map<String, dynamic>>? _sub;
  ValueListenable<int>? _position;
  Object? _owner;
  String? _path;
  bool _running = false;
  bool _notifyQueued = false;
  bool _toastedError = false;
  int _lastPos = 0;
  int _lastSent = 0;
  Timer? _debounce;
  Timer? _stopTimer;
  Timer? _readyTimer;

  String state = '';
  String message = '';
  int coveredMs = 0;
  int durationMs = 0;
  bool showReady = false;

  /// 0..1 share of the video whose captions are extracted, or null when the length is unknown.
  double? get progress => durationMs > 0 ? (coveredMs / durationMs).clamp(0.0, 1.0) : null;

  /// Status line for the small chip above the captions, or null to show nothing.
  String? get chipText {
    switch (state) {
      case 'needs_model':
        return 'Download an AI model (Settings > Accessibility > Live Caption)';
      case 'error':
        return 'Live Caption error: $message';
      case 'loading':
        return message.isEmpty ? 'Loading...' : message;
      case 'running':
      case 'waiting':
        final p = progress;
        final pct = p == null ? '' : ' ${(p * 100).floor()}%';
        return state == 'waiting' ? 'Captions$pct (ready ahead of playback)' : 'Extracting captions$pct';
      case 'done':
        return showReady ? 'Captions ready' : null;
    }
    return null;
  }

  /// Progress bar value for the chip (only while extracting).
  double? get chipProgress => (state == 'running' || state == 'waiting') ? progress : null;

  String textAt(int ms) {
    for (var i = _cues.length - 1; i >= 0; i--) {
      final c = _cues[i];
      if (c.start <= ms && ms <= c.end + 300) return c.text;
    }
    return '';
  }

  void attach(Object owner, String path, ValueListenable<int> position) {
    _stopTimer?.cancel();
    _sub ??= AndroidBridge.captionEvents().listen(_onEvent);
    _position?.removeListener(_onPosition);
    _owner = owner;
    _position = position;
    position.addListener(_onPosition);
    _lastPos = position.value;
    _lastSent = _lastPos;
    if (_path != path) {
      _path = path;
      _reset();
      _running = false;
    }
    if (!_running) _requestStart(delayMs: 500);
  }

  void detach(Object owner) {
    if (_owner != owner) return;
    _position?.removeListener(_onPosition);
    _position = null;
    _owner = null;
    _debounce?.cancel();
    // Keep working briefly: the mini player or the player may attach right after.
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(seconds: 5), () {
      if (_owner == null && _running) {
        _running = false;
        unawaited(AndroidBridge.liveCaptionStop(release: true));
      }
    });
  }

  void _reset() {
    _cues.clear();
    _keys.clear();
    state = '';
    message = '';
    coveredMs = 0;
    durationMs = 0;
    showReady = false;
    _toastedError = false;
    _readyTimer?.cancel();
    _queueNotify();
  }

  void _queueNotify() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      notifyListeners();
    });
  }

  /// Starts (or restarts) the engine once the position has settled, so a burst of position changes
  /// never restarts it over and over.
  void _requestStart({int delayMs = 400}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: delayMs), () {
      final p = _position;
      if (p != null) _start(p.value);
    });
  }

  void _start(int ms) {
    final path = _path;
    if (path == null) return;
    _running = true;
    _lastPos = ms;
    _lastSent = ms;
    unawaited(AndroidBridge.liveCaptionStart(path, ms));
  }

  void _onPosition() {
    final ms = _position?.value ?? 0;
    final jump = ms - _lastPos;
    _lastPos = ms;
    if (jump.abs() > 2500) {
      _requestStart(); // seek
    } else if ((ms - _lastSent).abs() > 1500) {
      _lastSent = ms;
      unawaited(AndroidBridge.liveCaptionPlayhead(ms));
    }
  }

  bool _addCue(int start, int end, String text) {
    final t = text.trim();
    if (t.isEmpty || !_keys.add('$start|$t')) return false;
    _cues.add(CaptionCue(start, end, t));
    if (_cues.length > 6000) {
      final drop = _cues.sublist(0, 1000);
      _cues.removeRange(0, 1000);
      for (final c in drop) {
        _keys.remove('${c.start}|${c.text}');
      }
    }
    return true;
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['path'] != _path) return; // stale event from another video
    switch (e['type']) {
      case 'cues':
        final list = e['list'];
        if (list is List) {
          for (final m in list) {
            if (m is Map) {
              _addCue((m['s'] as num?)?.toInt() ?? 0, (m['e'] as num?)?.toInt() ?? 0, '${m['t'] ?? ''}');
            }
          }
          _queueNotify();
        }
      case 'cue':
        final s = (e['startMs'] as num?)?.toInt() ?? 0;
        if (_addCue(s, (e['endMs'] as num?)?.toInt() ?? s, '${e['text'] ?? ''}')) _queueNotify();
      case 'progress':
        coveredMs = (e['coveredMs'] as num?)?.toInt() ?? coveredMs;
        durationMs = (e['durationMs'] as num?)?.toInt() ?? durationMs;
        _queueNotify();
      case 'status':
        state = '${e['state'] ?? ''}';
        message = '${e['message'] ?? ''}';
        if (state == 'done') {
          showReady = true;
          _readyTimer?.cancel();
          _readyTimer = Timer(const Duration(seconds: 4), () {
            showReady = false;
            _queueNotify();
          });
        }
        if (state == 'error' && !_toastedError) {
          _toastedError = true;
          unawaited(AndroidBridge.toast('Live Caption: $message'));
        }
        _queueNotify();
    }
  }
}
