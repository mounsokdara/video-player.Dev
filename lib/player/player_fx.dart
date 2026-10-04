import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

enum TapZone { left, middle, right }

TapZone tapZoneFor(Offset pos, Size size) {
  if (pos.dx < size.width * 0.30) return TapZone.left;
  if (pos.dx > size.width * 0.70) return TapZone.right;
  return TapZone.middle;
}

class RippleSpec {
  RippleSpec({
    required this.id,
    required this.local,
    required this.radius,
    required this.zone,
  });
  final int id;
  final Offset local;
  final double radius;
  final TapZone zone;
}

class MidBurst {
  MidBurst({required this.id, required this.playing});
  final int id;
  final bool playing;
}

class PlayerRippleLayer extends StatelessWidget {
  const PlayerRippleLayer({
    super.key,
    required this.size,
    required this.ripples,
    required this.leftCount,
    required this.rightCount,
    required this.leftOn,
    required this.rightOn,
    required this.midBursts,
    required this.reduceMotion,
    required this.onRippleDone,
    required this.onMidDone,
  });

  final Size size;
  final List<RippleSpec> ripples;
  final int leftCount;
  final int rightCount;
  final bool leftOn;
  final bool rightOn;
  final List<MidBurst> midBursts;
  final bool reduceMotion;
  final ValueChanged<int> onRippleDone;
  final ValueChanged<int> onMidDone;

  @override
  Widget build(BuildContext context) {
    final leftW = size.width * 0.30;
    final rightW = size.width * 0.30;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final r in ripples.where((e) => e.zone == TapZone.middle))
                  _RippleBlob(
                    key: ValueKey(r.id),
                    spec: r,
                    reduceMotion: reduceMotion,
                    onDone: () => onRippleDone(r.id),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: leftW,
            child: ClipPath(
              clipper: const _DPadClipper(fromLeft: true),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final r in ripples.where((e) => e.zone == TapZone.left))
                    _RippleBlob(
                      key: ValueKey(r.id),
                      spec: r,
                      reduceMotion: reduceMotion,
                      onDone: () => onRippleDone(r.id),
                    ),
                  _SeekIndicator(seconds: leftCount, left: true, wide: size.width >= 700, visible: leftOn),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: rightW,
            child: ClipPath(
              clipper: const _DPadClipper(fromLeft: false),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final r in ripples.where((e) => e.zone == TapZone.right))
                    _RippleBlob(
                      key: ValueKey(r.id),
                      spec: r,
                      reduceMotion: reduceMotion,
                      onDone: () => onRippleDone(r.id),
                    ),
                  _SeekIndicator(seconds: rightCount, left: false, wide: size.width >= 700, visible: rightOn),
                ],
              ),
            ),
          ),
          for (final b in midBursts)
            _PlayPauseBurst(
              key: ValueKey(b.id),
              playing: b.playing,
              wide: size.width >= 700,
              onDone: () => onMidDone(b.id),
            ),
        ],
      ),
    );
  }
}

class _DPadClipper extends CustomClipper<Path> {
  const _DPadClipper({required this.fromLeft});
  final bool fromLeft;

  @override
  Path getClip(Size size) {
    final r = Radius.elliptical(size.width * 0.5, size.height * 0.5);
    final rect = Offset.zero & size;
    final rrect = fromLeft
        ? RRect.fromRectAndCorners(rect, topRight: r, bottomRight: r)
        : RRect.fromRectAndCorners(rect, topLeft: r, bottomLeft: r);
    return Path()..addRRect(rrect);
  }

  @override
  bool shouldReclip(covariant _DPadClipper old) => old.fromLeft != fromLeft;
}

class _RippleBlob extends StatefulWidget {
  const _RippleBlob({
    super.key,
    required this.spec,
    required this.reduceMotion,
    required this.onDone,
  });
  final RippleSpec spec;
  final bool reduceMotion;
  final VoidCallback onDone;

  @override
  State<_RippleBlob> createState() => _RippleBlobState();
}

class _RippleBlobState extends State<_RippleBlob> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 1150),
    );
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final d = spec.radius * 2;
    return Positioned(
      left: spec.local.dx - spec.radius,
      top: spec.local.dy - spec.radius,
      width: d,
      height: d,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          final scale = t < 0.70 ? const Cubic(0.18, 0.62, 0.30, 1).transform(t / 0.70) : 1.0;
          final opacity = t < 0.70 ? 0.55 : 0.55 * (1 - (t - 0.70) / 0.30);
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x4DFFFFFF),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SeekIndicator extends StatefulWidget {
  const _SeekIndicator({required this.seconds, required this.left, required this.wide, required this.visible});
  final int seconds;
  final bool left;
  final bool wide;
  final bool visible;

  @override
  State<_SeekIndicator> createState() => _SeekIndicatorState();
}

class _SeekIndicatorState extends State<_SeekIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 390));
    if (widget.visible) _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant _SeekIndicator old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      _c.duration = const Duration(milliseconds: 390);
      _c.forward();
    } else if (!widget.visible && old.visible) {
      _c.duration = const Duration(milliseconds: 390);
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gap = widget.wide ? 16.0 : 14.0;
    final chevs = _Chevrons(left: widget.left, wide: widget.wide);
    final secs = _PopSecs(key: ValueKey(widget.seconds), value: widget.seconds, wide: widget.wide);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = const Cubic(0.2, 0.8, 0.2, 1).transform(_c.value);
          // HTML: opacity 280ms ease, transform 390ms cubic-bezier(0.2, 0.8, 0.2, 1)
          final opacity = Curves.ease.transform(_c.value.clamp(0.0, 1.0));
          return Opacity(
            opacity: opacity,
            child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
          );
        },
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: widget.left ? [secs, SizedBox(width: gap), chevs] : [chevs, SizedBox(width: gap), secs],
          ),
        ),
      ),
    );
  }
}

class _PopSecs extends StatefulWidget {
  const _PopSecs({super.key, required this.value, required this.wide});
  final int value;
  final bool wide;

  @override
  State<_PopSecs> createState() => _PopSecsState();
}

class _PopSecsState extends State<_PopSecs> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 340))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        final s = t < 0.45 ? 1 + 0.18 * (t / 0.45) : 1.18 - 0.18 * ((t - 0.45) / 0.55);
        return Transform.scale(scale: s, child: child);
      },
      child: Text(
        '${widget.value}',
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.wide ? 30 : 26,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 2))],
        ),
      ),
    );
  }
}

class _Chevrons extends StatelessWidget {
  const _Chevrons({required this.left, required this.wide});
  final bool left;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final angle = left ? -135 * math.pi / 180 : 45 * math.pi / 180;
    final s = wide ? 14.0 : 12.0;
    Widget chev(double opacity) {
      return Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: s,
            height: s,
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              border: const Border(
                top: BorderSide(color: Colors.white, width: 3),
                right: BorderSide(color: Colors.white, width: 3),
              ),
            ),
          ),
        ),
      );
    }

    final kids = [chev(0.55), chev(0.78), chev(1)];
    return Row(mainAxisSize: MainAxisSize.min, children: left ? kids.reversed.toList() : kids);
  }
}

class _PlayPauseBurst extends StatefulWidget {
  const _PlayPauseBurst({super.key, required this.playing, required this.wide, required this.onDone});
  final bool playing;
  final bool wide;
  final VoidCallback onDone;

  @override
  State<_PlayPauseBurst> createState() => _PlayPauseBurstState();
}

class _PlayPauseBurstState extends State<_PlayPauseBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // HTML: spring-in 480ms Cubic(0.34,1.75,0.64,1), hold until 700ms,
    // then hide transform 200ms Cubic(0.4,0,1,0.6) + opacity 90ms linear.
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.wide ? 104.0 : 88.0;
    final barW = widget.wide ? 11.0 : 9.0;
    final barH = widget.wide ? 38.0 : 32.0;
    final playW = widget.wide ? 30.0 : 26.0;
    final playH = widget.wide ? 38.0 : 32.0;
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final ms = _c.value * 900;
            late final double scale;
            late final double opacity;
            if (ms <= 480) {
              final u = (ms / 480).clamp(0.0, 1.0);
              scale = const Cubic(0.34, 1.75, 0.64, 1).transform(u);
              opacity = Curves.ease.transform(u);
            } else if (ms <= 700) {
              scale = 1;
              opacity = 1;
            } else {
              final hide = ((ms - 700) / 200).clamp(0.0, 1.0);
              scale = 1 - const Cubic(0.4, 0, 1, 0.6).transform(hide);
              opacity = 1 - ((ms - 700) / 90).clamp(0.0, 1.0);
            }
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale.clamp(0.0, 1.35),
                child: Container(
                  width: box,
                  height: box,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.30),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 8))],
                  ),
                  child: Center(
                    child: widget.playing
                        ? Padding(
                            padding: EdgeInsets.only(left: widget.wide ? 8 : 7),
                            child: CustomPaint(size: Size(playW, playH), painter: _PlayPainter()),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PauseBar(width: barW, height: barH),
                              const SizedBox(width: 9),
                              _PauseBar(width: barW, height: barH),
                            ],
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PauseBar extends StatelessWidget {
  const _PauseBar({this.width = 9, this.height = 32});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
    );
  }
}

class _PlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

RippleSpec makeRipple({
  required int id,
  required TapZone zone,
  required Offset pos,
  required Size size,
}) {
  final layer = switch (zone) {
    TapZone.left => Rect.fromLTWH(0, 0, size.width * 0.30, size.height),
    TapZone.right => Rect.fromLTWH(size.width * 0.70, 0, size.width * 0.30, size.height),
    TapZone.middle => Rect.fromLTWH(0, 0, size.width, size.height),
  };
  final local = Offset(pos.dx - layer.left, pos.dy - layer.top);
  final dx = math.max(local.dx, layer.width - local.dx);
  final dy = math.max(local.dy, layer.height - local.dy);
  return RippleSpec(id: id, local: local, radius: math.sqrt(dx * dx + dy * dy), zone: zone);
}
