part of 'player.dart';

extension PlayerGestures on _PlayerPageState {
  int get _fingers => _pts.length;

  void _trackPointerDown(PointerDownEvent e) {
    _pts[e.pointer] = e.localPosition;
  }

  void _trackPointerMove(PointerMoveEvent e) {
    _pts[e.pointer] = e.localPosition;
  }

  void _trackPointerUp(PointerEvent e) {
    _pts.remove(e.pointer);
  }

  void _onScaleStart(ScaleStartDetails d, Size size) {
    if (locked || _watch) return;
    DeveloperLog.gesture('scale start pointers=${d.pointerCount} zoom=${appSettings.allowZoom}');
    if (_gesture == 'hold' || _gesture == 'pinch' || _pinching) return;
    _gestureAt = DateTime.now();
    _sawTwo = d.pointerCount >= 2 || _fingers >= 2;
    panStart = d.focalPoint;
    panKind = '';
    if (_sawTwo && appSettings.allowZoom) {
      _ateTap = true;
      _abortPan();
      _beginPinch(d.focalPoint);
      return;
    }
    _gesture = 'wait';
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size, PlaybackEngine? c) {
    if (locked || _watch || _gesture == 'hold') return;
    final two = d.pointerCount >= 2 || _fingers >= 2;
    if (two) _sawTwo = true;
    final wantPinch = appSettings.allowZoom && two;

    if (_gesture == 'pinch' || _pinching) {
      if (appSettings.allowZoom) _applyPinch(d, size);
      return;
    }
    if (wantPinch) {
      _ateTap = true;
      _abortPan();
      _beginPinch(d.focalPoint, scale: d.scale);
      _applyPinch(d, size);
      return;
    }
    if (_gesture == 'pan') {
      if (c != null) _applyOneFinger(d.focalPoint, size, c);
      return;
    }
    if (two) return;
    if (c == null) return;
    if (!appSettings.gestureControl && _zoomScale <= 1.02) return;
    if (appSettings.allowZoom) {
      final waited = _gestureAt != null &&
          DateTime.now().difference(_gestureAt!) >= const Duration(milliseconds: 90);
      if (!waited) return;
    }
    panStart ??= d.focalPoint;
    _applyOneFinger(d.focalPoint, size, c);
  }

  Future<void> _onScaleEnd(PlaybackEngine? c) async {
    if (_gesture == 'hold') return;
    DeveloperLog.gesture('scale end gesture=$_gesture kind=$panKind');
    if (_gesture == 'pinch' || _pinching) {
      _pinching = false;
      if (_zoomScale < 0.011) {
        _zoomScale = 0.01;
        _zoomPan = Offset.zero;
      }
      _zoomHudTimer?.cancel();
      _zoomHudTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _showZoomHud = false);
      });
    } else if (!_sawTwo &&
        _gesture == 'pan' &&
        panKind == 'seek' &&
        _scrub != null &&
        c != null) {
      final dur = c.value.duration.inMilliseconds;
      final target = Duration(milliseconds: (_scrub! * dur).round());
      _posTick.value = target.inMilliseconds;
      unawaited(c.seekTo(target, fast: true));
    }
    panKind = '';
    panStart = null;
    _scrub = null;
    _previewBytes = null;
    _sawTwo = false;
    _gestureAt = null;
    if (_gesture != 'hold') _gesture = '';
    _pinching = false;
    if (mounted) setState(() {});
  }

  void _beginPinch(Offset focal, {double scale = 1}) {
    DeveloperLog.gesture('pinch begin scale=$scale');
    _gesture = 'pinch';
    _pinching = true;
    _sawTwo = true;
    final s = scale.abs() < 0.001 ? 1.0 : scale;
    _pinchBase = _zoomScale / s;
    _pinchBasePan = _zoomPan;
    _pinchStartFocal = focal;
    _showZoomHud = true;
    _zoomHudTimer?.cancel();
    if (mounted) setState(() {});
  }

  void _abortPan() {
    final had = _scrub != null || panKind.isNotEmpty || overlay.isNotEmpty;
    panKind = '';
    panStart = null;
    _scrub = null;
    _previewBytes = null;
    if (_gesture == 'pan' || _gesture == 'wait') _gesture = '';
    if (had) {
      overlayTimer?.cancel();
      overlay = '';
      if (mounted) setState(() {});
    }
  }

  void _applyPinch(ScaleUpdateDetails d, Size size) {
    final nextScale = (_pinchBase * d.scale).clamp(0.01, 10.0);
    final center = Offset(size.width / 2, size.height / 2);
    Offset nextPan;
    if (nextScale <= 1.001) {
      nextPan = Offset.zero;
    } else {
      final content = (_pinchStartFocal - center - _pinchBasePan) / (_pinchBase == 0 ? 1 : _pinchBase);
      nextPan = d.focalPoint - center - content * nextScale;
      final maxX = (nextScale - 1) * size.width / 2 + 48;
      final maxY = (nextScale - 1) * size.height / 2 + 48;
      nextPan = Offset(nextPan.dx.clamp(-maxX, maxX), nextPan.dy.clamp(-maxY, maxY));
    }
    if ((nextScale - _zoomScale).abs() > 0.004 || (nextPan - _zoomPan).distance > 0.5) {
      setState(() {
        _zoomScale = nextScale;
        _zoomPan = nextScale <= 0.011 ? Offset.zero : nextPan;
        _pinching = true;
        _showZoomHud = true;
        _gesture = 'pinch';
      });
    }
  }

  void _applyOneFinger(Offset focal, Size size, PlaybackEngine c) {
    final start = panStart ?? focal;
    final dx = focal.dx - start.dx;
    final dy = focal.dy - start.dy;
    if (panKind.isEmpty) {
      final slop = appSettings.allowZoom ? 36.0 : 24.0;
      if (Offset(dx, dy).distance <= slop) return;
      if (dx.abs() > dy.abs()) {
        if (!appSettings.gestureControl) return;
        _gesture = 'pan';
        _ateTap = true;
        panKind = 'seek';
        panBase = c.value.position.inMilliseconds.toDouble();
      } else {
        if (!appSettings.gestureControl) return;
        _gesture = 'pan';
        _ateTap = true;
        panKind = start.dx < size.width / 2 ? 'brightness' : 'volume';
        panBase = panKind == 'brightness' ? brightness : volume;
      }
    }
    if (_gesture != 'pan') return;
    if (panKind == 'seek') {
      final dur = c.value.duration.inMilliseconds.toDouble().clamp(1, double.infinity);
      final delta = (dx / size.width) * dur * 0.6;
      final next = (panBase + delta).clamp(0, dur);
      setState(() => _scrub = next / dur);
      _queuePreview((next / dur).toDouble());
      _flash(formatDuration(Duration(milliseconds: next.round())));
    } else if (panKind == 'brightness') {
      brightness = (panBase - dy / size.height).clamp(0.0, 1.0).toDouble();
      unawaited(ScreenBrightness().setApplicationScreenBrightness(brightness));
      if (appSettings.rememberBrightness) {
        appSettings.brightness = brightness;
      }
      _flash('Brightness ${(brightness * 100).round()}%');
      setState(() {});
    } else if (panKind == 'volume') {
      volume = (panBase - dy / size.height).clamp(0.0, 1.0).toDouble();
      try {
        VolumeController.instance.setVolume(volume);
      } catch (_) {}
      _flash('Volume ${(volume * 100).round()}%');
      setState(() {});
    }
  }

  bool _wouldBurst(Offset pos, Size size) {
    final now = DateTime.now();
    final zone = tapZoneFor(pos, size);
    final last = switch (zone) {
      TapZone.left => _leftTap,
      TapZone.right => _rightTap,
      TapZone.middle => _midTap,
    };
    final zoneOn = switch (zone) {
      TapZone.left => _leftOn,
      TapZone.right => _rightOn,
      TapZone.middle => _midOn,
    };
    return _activeRipples > 0 || now.difference(last) < const Duration(milliseconds: 320) || zoneOn;
  }

  void _armFirstTap(Offset pos, Size size) {
    final now = DateTime.now();
    final zone = tapZoneFor(pos, size);
    _uiBeforeTap = showUi;
    switch (zone) {
      case TapZone.left:
        _leftTap = now;
      case TapZone.right:
        _rightTap = now;
      case TapZone.middle:
        _midTap = now;
    }
  }

  void _onVideoTap(Offset pos, Size size) {
    DeveloperLog.gesture('tap x=${pos.dx.round()} y=${pos.dy.round()}');
    const tapWindow = Duration(milliseconds: 320);
    const hideDelay = Duration(milliseconds: 900);
    const midHide = Duration(milliseconds: 700);
    final now = DateTime.now();
    final zone = tapZoneFor(pos, size);
    final side = switch (zone) {
      TapZone.left => 'left',
      TapZone.right => 'right',
      TapZone.middle => 'mid',
    };
    final last = switch (zone) {
      TapZone.left => _leftTap,
      TapZone.right => _rightTap,
      TapZone.middle => _midTap,
    };
    final zoneOn = switch (zone) {
      TapZone.left => _leftOn,
      TapZone.right => _rightOn,
      TapZone.middle => _midOn,
    };
    final isDouble = now.difference(last) < tapWindow;
    final rippleActive = _activeRipples > 0;
    _tapPos = pos;

    if (!rippleActive && !isDouble && !zoneOn) {
      if (zone == TapZone.left) _leftTap = now;
      if (zone == TapZone.right) _rightTap = now;
      if (zone == TapZone.middle) _midTap = now;
      _uiBeforeTap = showUi;
      _setUi(!showUi);
      return;
    }

    _setUi(_uiBeforeTap);

    if (zone == TapZone.left || zone == TapZone.right) {
      if (!appSettings.doubleTapSeek) {
        _setUi(!showUi);
        return;
      }
      if (_currentSide != null && _currentSide != side) {
        _resetSide(_currentSide!);
        if (side == 'left') {
          _leftCount = 0;
        } else {
          _rightCount = 0;
        }
      }
      _currentSide = side;
      final step = appSettings.seekStepSeconds;
      if (zone == TapZone.left) {
        _leftTap = now;
        _leftCount += step;
        _leftOn = true;
        _spawnRipple(zone, pos, size);
        _leftHide?.cancel();
        _leftHide = Timer(hideDelay, () {
          if (!mounted) return;
          setState(() {
            _leftOn = false;
            _leftCount = 0;
            _leftTap = DateTime.fromMillisecondsSinceEpoch(0);
            if (_currentSide == 'left') _currentSide = null;
          });
        });
        DeveloperLog.gesture('double tap seek -$step');
        unawaited(_seekBy(-step));
      } else {
        _rightTap = now;
        _rightCount += step;
        _rightOn = true;
        _spawnRipple(zone, pos, size);
        _rightHide?.cancel();
        _rightHide = Timer(hideDelay, () {
          if (!mounted) return;
          setState(() {
            _rightOn = false;
            _rightCount = 0;
            _rightTap = DateTime.fromMillisecondsSinceEpoch(0);
            if (_currentSide == 'right') _currentSide = null;
          });
        });
        DeveloperLog.gesture('double tap seek +$step');
        unawaited(_seekBy(step));
      }
      setState(() {});
      return;
    }

    _midTap = now;
    _midOn = true;
    final playing = vc?.value.isPlaying ?? false;
    _togglePlay();
    _midPlayingIcon = !playing;
    _spawnRipple(TapZone.middle, pos, size);
    _midBursts.add(MidBurst(id: _rippleSeq, playing: !playing));
    _midHide?.cancel();
    _midHide = Timer(midHide, () {
      if (!mounted) return;
      setState(() {
        _midOn = false;
        _midTap = DateTime.fromMillisecondsSinceEpoch(0);
      });
    });
    setState(() {});
  }

  void _resetSide(String side) {
    if (side == 'left') {
      _leftHide?.cancel();
      _leftOn = false;
      _leftCount = 0;
      _leftTap = DateTime.fromMillisecondsSinceEpoch(0);
    } else if (side == 'right') {
      _rightHide?.cancel();
      _rightOn = false;
      _rightCount = 0;
      _rightTap = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  void _spawnRipple(TapZone zone, Offset pos, Size size) {
    final spec = makeRipple(id: _rippleSeq++, zone: zone, pos: pos, size: size);
    _ripples.add(spec);
    _activeRipples++;
  }
  void _queuePreview(double frac) {
    if (!appSettings.showSeekPreview) return;
    _previewWant = frac;
    if (_previewBusy) return;
    unawaited(_runPreview());
  }

  Future<void> _runPreview() async {
    _previewBusy = true;
    while (_previewWant != null && mounted && _scrub != null) {
      final frac = _previewWant!;
      _previewWant = null;
      final dur = vc?.value.duration.inMilliseconds ?? 0;
      if (dur <= 0) break;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final bytes = await AndroidBridge.previewFrame(
        path: item.path,
        positionMs: (frac.clamp(0.0, 1.0) * dur).round(),
        longEdge: (168 * dpr).round(),
      );
      // Keep the last frame if one fails, so the preview never blinks off mid-scrub.
      if (bytes != null && mounted && _scrub != null) {
        final sz = _jpegSize(bytes);
        setState(() {
          if (sz != null && sz.width > 0 && sz.height > 0) _previewAspect = sz.width / sz.height;
          _previewBytes = bytes;
        });
      }
    }
    _previewBusy = false;
  }
}

/// Reads width/height from a JPEG header without decoding it.
Size? _jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final m = b[i + 1];
    if (m == 0xFF) {
      i++;
      continue;
    }
    if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return Size(w.toDouble(), h.toDouble());
    }
    i += 2 + len;
  }
  return null;
}
