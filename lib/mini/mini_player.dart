import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:video_player_app/accessibility/live_caption/live_caption_overlay.dart';
import 'package:video_player_app/core/developer_log.dart';
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

  // Touch state. Raw pointers only: no gesture arena, no scale recognizer.
  final Map<int, Offset> _fingers = <int, Offset>{};
  final ValueNotifier<bool> _capture = ValueNotifier<bool>(false);
  bool _controlTouched = false; // set by a transport button right before the card sees the same touch
  bool _downOnControl = false;
  bool _dragArmed = true;
  Offset _gStartFocal = Offset.zero;
  double _baseSpan = 0;

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
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
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
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    _capture.dispose();
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

  // ---- touch handling --------------------------------------------------------------------
  //
  // Same feel as YouTube's mini player:
  //  * the first finger lands on the card and drags it 1:1 straight away (no touch slop);
  //  * every other finger may land ANYWHERE on screen (a capture layer sits under the card and
  //    keeps the page below still) and joins the same gesture;
  //  * two or more fingers move the card by their centre and resize it by their spread;
  //  * lifting a finger carries on with the rest without a jump; the card settles when the last
  //    finger is up. A tap (no movement) expands; a tap on a transport button is the button's own.

  void _markControlDown() => _controlTouched = true;

  Offset get _focal {
    var sum = Offset.zero;
    for (final p in _fingers.values) {
      sum += p;
    }
    return sum / _fingers.length.toDouble();
  }

  double get _span {
    if (_fingers.length < 2) return 0;
    final f = _focal;
    var total = 0.0;
    for (final p in _fingers.values) {
      total += (p - f).distance;
    }
    return total / _fingers.length;
  }

  /// Re-anchor the card to the fingers as they are now (first touch, finger added or lifted).
  void _rebase() {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final cardGlobal = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    _startW = _w;
    _startPos = _rawPos;
    _parentOrigin = cardGlobal - _startPos;
    _anchorInWidget = _focal - _parentOrigin - _startPos;
    _baseSpan = _span;
  }

  void _onFingerDown(PointerDownEvent e, {required bool onCard}) {
    final control = _controlTouched;
    _controlTouched = false;
    if (_dismissed) return;
    _fingers[e.pointer] = e.position;
    if (_fingers.length == 1) {
      _anim.stop();
      _gestureActive = true;
      _moved = false;
      _gStartFocal = e.position;
      _downOnControl = onCard && control;
      _dragArmed = !_downOnControl; // a button press only turns into a drag after the slop
      _capture.value = true;
      final wasParked = _parked;
      if (wasParked || _parkSide != 0) {
        setState(() {
          _parked = false;
          _parkSide = 0;
        });
        if (wasParked) _resumeIfNeeded();
      }
    } else {
      _moved = true;
      _dragArmed = true;
      DeveloperLog.append('mini: finger ${_fingers.length} down${onCard ? '' : ' outside the card'}');
    }
    _rebase();
  }

  void _onFingerMove(PointerMoveEvent e) {
    if (!_gestureActive || _dismissed || !_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.position;
    final focal = _focal;
    if (!_dragArmed) {
      if ((focal - _gStartFocal).distance <= MiniGeom.tapSlop) return;
      _dragArmed = true;
      _rebase(); // start following from here, no jump
    }
    if ((focal - _gStartFocal).distance > MiniGeom.tapSlop) _moved = true;

    var targetW = _startW;
    if (_fingers.length >= 2 && _baseSpan > 0) {
      _moved = true;
      final hi = MiniPhysics.maxWFor(_screen, _video);
      final lo = math.min(MiniGeom.minW, hi);
      targetW = MiniPhysics.softClamp(_startW * (_span / _baseSpan), lo, hi);
    }
    final ratio = _startW == 0 ? 1.0 : targetW / _startW;
    final newPos = focal - _parentOrigin - _anchorInWidget * ratio;
    setState(() {
      _w = targetW;
      _pos = newPos;
    });
  }

  void _onFingerUp(PointerEvent e) {
    if (_fingers.remove(e.pointer) == null) return;
    if (e is PointerCancelEvent) _moved = true; // never expand from a cancelled touch
    if (_fingers.isNotEmpty) {
      _rebase();
      return;
    }
    _capture.value = false;
    _finalizeGesture();
  }

  /// Every move/up/cancel of a finger we track, wherever it is, even if the widget it landed on is gone.
  void _onGlobalPointer(PointerEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    if (e is PointerMoveEvent) {
      _onFingerMove(e);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _onFingerUp(e);
    }
  }

  void _finalizeGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    if (!_moved) {
      if (_downOnControl) return; // the button handles its own tap
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
        // Under the card, over the page: while a finger is down on the card it swallows every other
        // touch (so the page below stays still) and feeds it to the same gesture. Always mounted,
        // only switched on and off, so the card is never rebuilt in the middle of a touch.
        Positioned.fill(
          key: const ValueKey('mini-capture'),
          child: ValueListenableBuilder<bool>(
            valueListenable: _capture,
            builder: (context, on, _) => IgnorePointer(
              ignoring: !on,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _onFingerDown(e, onCard: false),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Positioned(
          key: const ValueKey('mini-card'),
          left: pos.dx,
          top: pos.dy,
          width: _w,
          height: h,
          child: Opacity(
            opacity: opacity,
            child: IgnorePointer(
              ignoring: _dismissed || opacity < 0.1,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _onFingerDown(e, onCard: true),
                child: KeyedSubtree(
                  key: const ValueKey('mini-card-body'),
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
                              onControlDown: _markControlDown,
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
