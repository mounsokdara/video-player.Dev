import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player_app/accessibility/live_caption/live_caption_overlay.dart';
import 'package:video_player_app/playback/engine.dart';

import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/mini/mini_chrome.dart';
import 'package:video_player_app/mini/mini_geom.dart';
import 'package:video_player_app/player/player_picture.dart';
import 'package:video_player_app/playback/session.dart';
import 'package:video_player_app/settings/settings.dart';

class MiniPlayerOverlay extends StatefulWidget {
  const MiniPlayerOverlay({
    super.key,
    required this.pad,
    required this.bottomInset,
    required this.onExpand,
    required this.onClose,
    required this.onPrev,
    required this.onNext,
  });

  final EdgeInsets pad;

  /// Space under the content area that the mini player must stay clear of.
  /// 0 when an app navigation bar already sits below the content area.
  final double bottomInset;
  final VoidCallback onExpand;
  final Future<void> Function() onClose;
  final Future<void> Function() onPrev;
  final Future<void> Function() onNext;

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay>
    with TickerProviderStateMixin {
  Object? _capFor;
  EnginePositionListenable? _capPos;

  final GlobalKey _cardKey = GlobalKey();

  late final AnimationController _anim;
  Animation<Offset>? _posAnim;
  Animation<double>? _wAnim;

  double _w = MiniGeom.defW;
  Offset? _pos;
  var _parked = false;
  int _parkSide = 0;
  bool _dismissed = false;
  bool _wasPlayingBeforePark = false;
  bool _moved = false;
  bool _gestureActive = false;
  int _activePointers = 0;

  bool _arrowDragging = false;
  int _dragSide = 0;

  Size? _lastScreen;

  double _startW = MiniGeom.defW;
  Offset _startPos = Offset.zero;
  Offset _parentOrigin = Offset.zero;
  Offset _anchorInWidget = Offset.zero;

  PlaybackEngine? _ctrl;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    _anim.addListener(() {
      setState(() {
        if (_posAnim != null) _pos = _posAnim!.value;
        if (_wAnim != null) _w = _wAnim!.value;
      });
    });
    _bind();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  /// Called from build with the real size of the area this overlay fills.
  void _syncArea(Size area) {
    if (_lastScreen == null) {
      _lastScreen = area;
      _w = MiniPhysics.defaultW(area);
      MiniMemory.w = _w;
    } else if (_lastScreen != area) {
      final old = _lastScreen!;
      _lastScreen = area;
      _repositionForScreenChange(old, area);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    try {
      _ctrl?.removeListener(_onTick);
    } catch (_) {}
    super.dispose();
  }

  void _bind() {
    final next = PlaybackSession.controller;
    if (identical(next, _ctrl)) return;
    try {
      _ctrl?.removeListener(_onTick);
    } catch (_) {}
    _ctrl = next;
    _ctrl?.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    if (_gestureActive || _arrowDragging || _anim.isAnimating) return;
    final hi = MiniPhysics.maxWFor(_screen, _video);
    if (_w > hi + 2) {
      setState(() {
        _w = hi;
        MiniMemory.w = _w;
      });
      return;
    }
    setState(() {});
  }

  // Size of the area the overlay actually occupies (set by build).
  Size get _screen => _lastScreen ?? MediaQuery.sizeOf(context);

  Rect get _safe => MiniPhysics.safeZone(
        _screen,
        topInset: widget.pad.top,
        bottomInset: widget.bottomInset,
      );

  Size get _video => MiniPhysics.videoSize();

  double get _h => MiniPhysics.boxFor(_w, _video).height;

  Offset get _rawPos =>
      _pos ?? MiniPhysics.defaultPos(_screen, _w, _h, _safe);

  double _overhang(Offset pos) {
    if (_parked) return 0;
    final screenW = _screen.width;
    if (pos.dx < 0) return -pos.dx;
    if (pos.dx + _w > screenW) return pos.dx + _w - screenW;
    return 0;
  }

  int _sideFor(Offset pos) {
    if (_parked && _parkSide != 0) return _parkSide;
    if (_parked) {
      final screenW = _screen.width;
      if (pos.dx + _w / 2 < screenW / 2) return -1;
      return 1;
    }
    final screenW = _screen.width;
    if (pos.dx < 0) return -1;
    if (pos.dx + _w > screenW) return 1;
    return 0;
  }

  double _arrowWidthFor(Offset pos) {
    if (_parked) return MiniGeom.arrowMaxW;
    if (_overhang(pos) <= 0) return 0;
    final o = _overhang(pos);
    final full = MiniGeom.parkT * _w;
    return (MiniGeom.arrowMaxW * (o / full))
        .clamp(0.0, MiniGeom.arrowMaxW)
        .toDouble();
  }

  void _repositionForScreenChange(Size oldSize, Size newSize) {
    if (_dismissed) return;

    if (_anim.isAnimating) {
      _anim.stop();
    }
    _posAnim = null;
    _wAnim = null;

    final safe = MiniPhysics.safeZone(
      newSize,
      topInset: widget.pad.top,
      bottomInset: widget.bottomInset,
    );
    final video = MiniPhysics.videoSize();
    final newW = MiniPhysics.clampW(_w, newSize, video);
    final newH = MiniPhysics.boxFor(newW, video).height;

    if (_pos == null) {
      _w = newW;
      _pos = MiniPhysics.defaultPos(newSize, newW, newH, safe);
      return;
    }

    final current = _pos!;

    if (_parked) {
      final side = _parkSide != 0
          ? _parkSide
          : (current.dx + newW / 2 < newSize.width / 2 ? -1 : 1);
      final targetX = side < 0 ? -newW : newSize.width;
      final maxY = math.max(safe.top, safe.bottom - newH);
      final targetY = current.dy.clamp(safe.top, maxY).toDouble();
      _w = newW;
      _parked = true;
      _parkSide = side;
      _pos = Offset(targetX, targetY);
      return;
    }

    final maxX = math.max(safe.left, safe.right - newW);
    final maxY = math.max(safe.top, safe.bottom - newH);
    final x = current.dx.clamp(safe.left, maxX).toDouble();
    final y = current.dy.clamp(safe.top, maxY).toDouble();

    _w = newW;
    _pos = Offset(x, y);
  }

  void _pauseForPark() {
    final c = PlaybackSession.controller;
    if (c == null) return;
    try {
      if (c.value.isPlaying) {
        _wasPlayingBeforePark = true;
        unawaited(c.pause());
      }
    } catch (_) {}
  }

  void _resumeIfNeeded() {
    if (!_wasPlayingBeforePark) return;
    _wasPlayingBeforePark = false;
    final c = PlaybackSession.controller;
    if (c == null) return;
    unawaited(() async {
      try {
        await AndroidBridge.requestAudioFocus();
        await c.play();
      } catch (_) {}
      if (mounted) setState(() {});
    }());
  }

  Future<void> _togglePlay() async {
    if (_dismissed) return;
    final c = PlaybackSession.controller;
    if (c == null) return;
    try {
      if (c.value.isPlaying) {
        _wasPlayingBeforePark = false;
        await c.pause();
      } else {
        await AndroidBridge.requestAudioFocus();
        await c.play();
      }
      if (appSettings.backgroundPlay) {
        await PlaybackSession.syncNotification();
      } else {
        await AndroidBridge.stopBackground();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _handlePointerDown(PointerDownEvent _) {
    _activePointers++;
    if (_activePointers >= 2 && _gestureActive) {
      _moved = true;
    }
  }

  void _handlePointerUp(PointerUpEvent _) {
    _activePointers = math.max(0, _activePointers - 1);
    if (_activePointers == 0 && _gestureActive) {
      _finalizeGesture();
    }
  }

  void _handlePointerCancel(PointerCancelEvent _) {
    _activePointers = math.max(0, _activePointers - 1);
    if (_activePointers == 0 && _gestureActive) {
      _finalizeGesture();
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_dismissed) return;
    _anim.stop();
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final cardGlobal = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    _startW = _w;
    _startPos = _rawPos;
    _parentOrigin = cardGlobal - _startPos;
    final focalInParent = d.focalPoint - _parentOrigin;
    _anchorInWidget = focalInParent - _startPos;

    if (!_gestureActive) {
      _gestureActive = true;
      _moved = false;
    }
    if (d.pointerCount >= 2 || _activePointers >= 2) {
      _moved = true;
    }

    final wasParked = _parked;
    setState(() {
      _parked = false;
      _parkSide = 0;
      _dismissed = false;
    });
    if (wasParked) _resumeIfNeeded();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_dismissed) return;
    if (d.pointerCount >= 2 || _activePointers >= 2) {
      _moved = true;
    }
    final pinching = (d.scale - 1).abs() > 0.02 || d.pointerCount >= 2;
    if ((_startPos - _rawPos).distance > MiniGeom.tapSlop ||
        (d.focalPoint - (_parentOrigin + _startPos + _anchorInWidget))
                .distance >
            MiniGeom.tapSlop ||
        pinching) {
      _moved = true;
    }
    final hi = MiniPhysics.maxWFor(_screen, _video);
    final lo = math.min(MiniGeom.minW, hi);
    final targetW = MiniPhysics.softClamp(_startW * d.scale, lo, hi);
    final ratio = _startW == 0 ? 1.0 : targetW / _startW;
    final focalInParent = d.focalPoint - _parentOrigin;
    final newPos = focalInParent - _anchorInWidget * ratio;
    setState(() {
      _w = targetW;
      _pos = newPos;
      if (_parked) {
        _parked = false;
        _parkSide = 0;
        _resumeIfNeeded();
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dismissed) return;
    if (_activePointers > 0) return;
    _finalizeGesture();
  }

  void _finalizeGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    if (!_moved) {
      if (_parked) {
        _unpark();
      } else {
        widget.onExpand();
      }
      return;
    }
    _settle();
  }

  void _onArrowPanStart(DragStartDetails _) {
    if (_dismissed) return;
    _anim.stop();
    final wasParked = _parked;
    final oldSide = _parkSide;
    final effectiveSide = oldSide != 0 ? oldSide : _sideFor(_rawPos);
    setState(() {
      _parked = false;
      _parkSide = 0;
      _dismissed = false;
      _arrowDragging = true;
      _dragSide = effectiveSide == 0 ? 1 : effectiveSide;
    });
    if (wasParked && oldSide != 0) _resumeIfNeeded();
  }

  void _onArrowPanUpdate(DragUpdateDetails d) {
    if (!_arrowDragging) return;
    setState(() => _pos = _rawPos + d.delta);
  }

  void _onArrowPanEnd(DragEndDetails _) {
    if (!_arrowDragging) return;
    _arrowDragging = false;
    _dragSide = 0;
    _settle();
  }

  void _onArrowPanCancel() {
    if (!_arrowDragging) return;
    _arrowDragging = false;
    _dragSide = 0;
    _settle();
  }

  void _settle() {
    final screen = _screen;
    final video = _video;
    final settledW = MiniPhysics.clampW(_w, screen, video);
    final fromPos = _rawPos;
    final settledH = MiniPhysics.boxFor(settledW, video).height;
    final safe = _safe;
    final dismissThresholdY = screen.height - (settledH * 0.4);

    if (fromPos.dy >= dismissThresholdY) {
      _pauseForPark();
      final targetY = screen.height + 20;
      setState(() {
        _parked = false;
        _parkSide = 0;
        _dismissed = true;
      });
      _animate(fromPos, Offset(fromPos.dx, targetY), _w, settledW, 280, () {
        unawaited(widget.onClose());
      });
      return;
    }

    final overhang = _overhang(fromPos);
    final full = MiniGeom.parkT * settledW;
    late final Offset to;
    if (overhang >= full) {
      final side = fromPos.dx < 0 ? -1 : 1;
      _pauseForPark();
      final targetX = side < 0 ? -settledW : screen.width;
      final maxY = math.max(safe.top, safe.bottom - settledH);
      final targetY = fromPos.dy.clamp(safe.top, maxY).toDouble();
      to = Offset(targetX, targetY);
      setState(() {
        _parked = true;
        _parkSide = side;
      });
    } else {
      to = MiniPhysics.edgeTarget(fromPos, settledW, settledH, safe);
      setState(() {
        _parked = false;
        _parkSide = 0;
      });
    }
    final dist = (to - fromPos).distance;
    final ms = (220 + dist * 0.45).clamp(220, 700).round();
    _animate(fromPos, to, _w, settledW, ms, () {
      _pos = to;
      _w = settledW;
    });
  }

  void _unpark() {
    if (!_parked && _parkSide == 0) return;
    final side = _parkSide != 0 ? _parkSide : _sideFor(_rawPos);
    if (side == 0) return;
    final video = _video;
    final targetW = MiniPhysics.clampW(_w, _screen, video);
    final targetH = MiniPhysics.boxFor(targetW, video).height;
    final safe = _safe;
    final targetX =
        side < 0 ? safe.left : math.max(safe.left, safe.right - targetW);
    final maxY = math.max(safe.top, safe.bottom - targetH);
    final targetY = _rawPos.dy.clamp(safe.top, maxY).toDouble();
    final fromPos = _rawPos;
    final to = Offset(targetX, targetY);
    final dist = (to - fromPos).distance;
    final ms = (220 + dist * 0.45).clamp(220, 700).round();
    setState(() {
      _parked = false;
      _parkSide = 0;
    });
    _resumeIfNeeded();
    _animate(fromPos, to, _w, targetW, ms, () {
      _pos = to;
      _w = targetW;
    });
  }

  void _animate(
    Offset from,
    Offset to,
    double fromW,
    double toW,
    int ms,
    VoidCallback? onDone,
  ) {
    _posAnim = Tween<Offset>(begin: from, end: to).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _wAnim = Tween<double>(begin: fromW, end: toW).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _anim.duration = Duration(milliseconds: ms);
    _anim.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _pos = to;
      _w = toW;
      onDone?.call();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        if (!area.isFinite || area.isEmpty) return const SizedBox.shrink();
        _syncArea(area);
        return _buildOverlay(context);
      },
    );
  }

  Widget _buildOverlay(BuildContext context) {
    _bind();
    final pos = _rawPos;
    final side = _sideFor(pos);
    final arrowW = _arrowWidthFor(pos);
    final h = _h;
    final scheme = Theme.of(context).colorScheme;
    final stroke = scheme.outline.withValues(alpha: 0.55);
    final arrowStroke = scheme.outline.withValues(alpha: 0.85);

    final int renderSide = _arrowDragging && _dragSide != 0 ? _dragSide : side;
    final double visibleArrowW = arrowW;
    final double hitArrowW =
        _arrowDragging ? MiniGeom.arrowMaxW : visibleArrowW;

    final bool showArrow = !_dismissed &&
        (_arrowDragging || (renderSide != 0 && visibleArrowW > 0.5));

    final double arrowLeft;
    if (renderSide < 0) {
      arrowLeft = pos.dx + _w;
    } else if (renderSide > 0) {
      arrowLeft = pos.dx - hitArrowW;
    } else {
      arrowLeft = 0;
    }
    final arrowTop = pos.dy + h / 2 - MiniGeom.arrowH / 2;

    var dismissProgress = 1.0;
    if (pos.dy > _screen.height - h) {
      final beyond = pos.dy - (_screen.height - h);
      dismissProgress = (1.0 - (beyond / (h * 0.6))).clamp(0.0, 1.0).toDouble();
    }
    final opacity = _dismissed ? 0.0 : dismissProgress;

    final c = PlaybackSession.controller;
    final item = PlaybackSession.item;
    if (!identical(_capFor, c)) {
      _capFor = c;
      _capPos = c == null ? null : EnginePositionListenable(c, () => c.value.position.inMilliseconds);
    }
    var playing = false;
    var progress = 0.0;
    try {
      playing = c?.value.isPlaying ?? false;
      final dur = c?.value.duration.inMilliseconds ?? 0;
      if (dur > 0) {
        progress =
            (c!.value.position.inMilliseconds / dur).clamp(0.0, 1.0).toDouble();
      }
    } catch (_) {}

    Widget frame;
    try {
      if (c != null && c.video != null) {
        frame = VideoPicture(
          looks: PictureLooks.current(),
          child: ColoredBox(
            color: Colors.black,
            child: AppVideo(engine: c, fit: BoxFit.contain, showLog: false),
          ),
        );
      } else {
        frame = ColoredBox(
          color: const Color(0xFF05060A),
          child: Icon(
            Icons.play_circle,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        );
      }
    } catch (_) {
      frame = const ColoredBox(color: Color(0xFF05060A));
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: _w,
          height: h,
          child: Opacity(
            opacity: opacity,
            child: IgnorePointer(
              ignoring: _dismissed || opacity < 0.1,
              child: Listener(
                onPointerDown: _handlePointerDown,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerCancel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: Stack(
                    children: [
                      Material(
                        key: _cardKey,
                        color: scheme.surface,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: const Color(0xFF05060A),
                                    child: frame,
                                  ),
                                  if (appSettings.liveCaption && item != null && _capPos != null)
                                    Positioned(
                                      key: const ValueKey('mini-live-caption'),
                                      left: 6,
                                      right: 6,
                                      bottom: 8,
                                      child: IgnorePointer(
                                        child: LiveCaptionOverlay(
                                          path: item.path,
                                          position: _capPos!,
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: SizedBox(
                                      height: 3,
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 3,
                                        backgroundColor: Colors.white24,
                                        color: const Color(0xFF9E8CFF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            MiniTransportBar(
                              title: item?.title ?? '',
                              playing: playing,
                              onPrev: () => unawaited(widget.onPrev()),
                              onPlay: () => unawaited(_togglePlay()),
                              onNext: () => unawaited(widget.onNext()),
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: stroke, width: 1.2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showArrow)
          Positioned(
            left: arrowLeft,
            top: arrowTop,
            width: hitArrowW,
            height: MiniGeom.arrowH,
            child: IgnorePointer(
              ignoring: !_arrowDragging && hitArrowW < 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _unpark,
                onPanStart: _onArrowPanStart,
                onPanUpdate: _onArrowPanUpdate,
                onPanEnd: _onArrowPanEnd,
                onPanCancel: _onArrowPanCancel,
                child: Align(
                  alignment: renderSide < 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: SizedBox(
                    width: visibleArrowW.clamp(0.0, hitArrowW),
                    height: MiniGeom.arrowH,
                    child: Stack(
                      children: [
                        MiniStickyArrow(
                          side: renderSide == 0 ? 1 : renderSide,
                          width: visibleArrowW,
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  topLeft: renderSide > 0
                                      ? const Radius.circular(4)
                                      : Radius.zero,
                                  bottomLeft: renderSide > 0
                                      ? const Radius.circular(4)
                                      : Radius.zero,
                                  topRight: renderSide < 0
                                      ? const Radius.circular(4)
                                      : Radius.zero,
                                  bottomRight: renderSide < 0
                                      ? const Radius.circular(4)
                                      : Radius.zero,
                                ),
                                border:
                                    Border.all(color: arrowStroke, width: 1.2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
