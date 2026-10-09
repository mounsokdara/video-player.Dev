import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:video_player_app/native/android_bridge.dart';

class _Cue {
  const _Cue(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

/// Live caption text for the video being played. Asks the native engine to transcribe the file
/// from the playhead, collects the returned cues and shows the one matching the position.
/// Place it inside an IgnorePointer at the bottom of the video.
class LiveCaptionOverlay extends StatefulWidget {
  const LiveCaptionOverlay({super.key, required this.path, required this.position});

  /// File being played.
  final String path;

  /// Playback position in milliseconds.
  final ValueListenable<int> position;

  @override
  State<LiveCaptionOverlay> createState() => _LiveCaptionOverlayState();
}

class _LiveCaptionOverlayState extends State<LiveCaptionOverlay> {
  final List<_Cue> _cues = [];
  StreamSubscription<Map<String, dynamic>>? _sub;
  String _state = '';
  String _text = '';
  int _lastPos = 0;
  int _lastSent = 0;
  bool _toastedError = false;

  @override
  void initState() {
    super.initState();
    _sub = AndroidBridge.captionEvents().listen(_onEvent);
    widget.position.addListener(_onPosition);
    _start(widget.position.value);
  }

  @override
  void didUpdateWidget(LiveCaptionOverlay old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
    }
    if (old.path != widget.path) {
      _cues.clear();
      _text = '';
      _start(widget.position.value);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    _sub?.cancel();
    unawaited(AndroidBridge.liveCaptionStop(release: true));
    super.dispose();
  }

  void _start(int ms) {
    _lastPos = ms;
    _lastSent = ms;
    _cues.removeWhere((c) => c.end >= ms - 500);
    unawaited(AndroidBridge.liveCaptionStart(widget.path, ms));
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['type']) {
      case 'cue':
        final start = (e['startMs'] as num?)?.toInt() ?? 0;
        final end = (e['endMs'] as num?)?.toInt() ?? start;
        final text = '${e['text'] ?? ''}'.trim();
        if (text.isEmpty) return;
        if (_cues.any((c) => c.start == start && c.text == text)) return;
        _cues.add(_Cue(start, end, text));
        if (_cues.length > 3000) _cues.removeRange(0, 500);
        _refreshText();
      case 'status':
        final st = '${e['state'] ?? ''}';
        if (st == 'error' && !_toastedError) {
          _toastedError = true;
          unawaited(AndroidBridge.toast('Live Caption: ${e['message'] ?? 'error'}'));
        }
        setState(() => _state = st);
    }
  }

  void _onPosition() {
    final ms = widget.position.value;
    final jump = ms - _lastPos;
    _lastPos = ms;
    if (jump.abs() > 2500) {
      // Seek: restart the engine from the new position.
      _start(ms);
    } else if ((ms - _lastSent).abs() > 1500) {
      _lastSent = ms;
      unawaited(AndroidBridge.liveCaptionPlayhead(ms));
    }
    _refreshText();
  }

  void _refreshText() {
    final ms = widget.position.value;
    String next = '';
    for (var i = _cues.length - 1; i >= 0; i--) {
      final c = _cues[i];
      if (c.start <= ms && ms <= c.end + 300) {
        next = c.text;
        break;
      }
    }
    if (next != _text && mounted) setState(() => _text = next);
  }

  @override
  Widget build(BuildContext context) {
    String? hint;
    if (_text.isEmpty) {
      if (_state == 'needs_model') {
        hint = 'Live Caption: download an AI model (Settings > Accessibility > Live Caption)';
      } else if (_state == 'loading') {
        hint = 'Live Caption: loading AI model...';
      }
    }
    final shown = _text.isNotEmpty ? _text : hint;
    if (shown == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xB8000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          shown,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: _text.isNotEmpty ? 18 : 13,
            height: 1.25,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
