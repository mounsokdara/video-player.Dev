import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/native/android_bridge.dart';

class SystemBars {
  static int popupCount = 0;
  static bool alwaysHide = false;
  static Brightness iconBrightness = Brightness.light;

  static bool lastContrast = true;

  static final ValueNotifier<bool> solidNav = ValueNotifier<bool>(true);

  static final ValueNotifier<Color?> stripColor = ValueNotifier<Color?>(null);

  static Color? homeStrip;

  static final ValueNotifier<List<PopupRoute<dynamic>>> popups = ValueNotifier<List<PopupRoute<dynamic>>>(const []);

  static void _popupOpened(PopupRoute<dynamic> r) {
    if (popups.value.contains(r)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!popups.value.contains(r)) popups.value = [...popups.value, r];
    });
  }

  static void _popupClosed(PopupRoute<dynamic> r) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (popups.value.contains(r)) popups.value = popups.value.where((e) => e != r).toList();
    });
  }

  static Color dimmed(Color base) {
    var c = base;
    for (final r in popups.value) {
      final b = r.barrierColor;
      if (b == null) continue;
      final t = r.animation?.value ?? 1.0;
      c = Color.alphaBlend(b.withValues(alpha: b.a * t.clamp(0.0, 1.0)), c);
    }
    return c;
  }

  static void setStrip(Color? c) {
    if (stripColor.value == c) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => stripColor.value = c);
  }

  static void _setSolidNav(bool v) {
    if (solidNav.value == v) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => solidNav.value = v);
  }

  static EdgeInsets of(BuildContext context) => MediaQuery.viewPaddingOf(context);

  static EdgeInsets rawOf(BuildContext context) {
    return MediaQueryData.fromView(View.of(context)).viewPadding;
  }

  static double bottomInset(BuildContext context) {
    final raw = rawOf(context).bottom;
    final mq = MediaQuery.viewPaddingOf(context).bottom;
    return raw > mq ? raw : mq;
  }

  static SystemUiOverlayStyle overlay({required Brightness icons, bool contrast = true}) {
    final status = icons;
    final bar = icons == Brightness.light ? Brightness.dark : Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: status,
      statusBarBrightness: bar,
      systemNavigationBarIconBrightness: status,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  static void apply({required Brightness icons, bool contrast = true, bool forceShow = false, bool? hide}) {
    iconBrightness = icons;
    lastContrast = contrast;
    _setSolidNav(contrast);
    final shouldHide = hide ?? (alwaysHide && popupCount <= 0 && !forceShow);
    _ensureUiCallback();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(overlay(icons: icons, contrast: contrast));
    unawaited(AndroidBridge.applySystemBars(
      lightIcons: icons == Brightness.light,
      contrast: contrast,
      hide: shouldHide,
    ));
  }

  static bool _cbBound = false;

  static void _ensureUiCallback() {
    if (_cbBound) return;
    _cbBound = true;
    SystemChrome.setSystemUIChangeCallback((visible) async {
      if (visible && alwaysHide && popupCount <= 0) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        unawaited(AndroidBridge.applySystemBars(
          lightIcons: iconBrightness == Brightness.light,
          contrast: lastContrast,
          hide: true,
        ));
      }
    });
  }

  static void onPopup(bool open) {
    if (open) {
      popupCount++;
      apply(icons: iconBrightness, contrast: lastContrast, forceShow: true);
    } else {
      if (popupCount > 0) popupCount--;
      apply(icons: iconBrightness, contrast: lastContrast);
    }
  }

  static Future<T?> modal<T>(Future<T?> Function() run) async {
    onPopup(true);
    try {
      return await run();
    } finally {
      onPopup(false);
    }
  }
}

class SolidNavBarStrip extends StatelessWidget {
  const SolidNavBarStrip({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        ListenableBuilder(
          listenable: Listenable.merge([SystemBars.solidNav, SystemBars.stripColor, SystemBars.popups]),
          builder: (context, _) {
            final animations = <Listenable>[
              for (final r in SystemBars.popups.value)
                if (r.animation != null) r.animation!,
            ];
            return ListenableBuilder(
              listenable: Listenable.merge(animations),
              builder: (context, _) {
                final h = SystemBars.rawOf(context).bottom;
                final side = MediaQuery.orientationOf(context) == Orientation.landscape;
                if (!SystemBars.solidNav.value || h <= 0 || side) return const SizedBox.shrink();
                final base = SystemBars.stripColor.value ?? Theme.of(context).colorScheme.surface;
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: h,
                  child: IgnorePointer(child: ColoredBox(color: SystemBars.dimmed(base))),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class SystemBarSafeZone extends StatelessWidget {
  const SystemBarSafeZone({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context);
    return Padding(
      padding: EdgeInsets.only(left: pad.left, right: pad.right),
      child: MediaQuery.removeViewPadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        child: child,
      ),
    );
  }
}

class SystemBarObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      SystemBars._popupOpened(route);
      SystemBars.onPopup(true);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      SystemBars._popupClosed(route);
      SystemBars.onPopup(false);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      SystemBars._popupClosed(route);
      SystemBars.onPopup(false);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PopupRoute) {
      SystemBars._popupClosed(oldRoute);
      SystemBars.onPopup(false);
    }
    if (newRoute is PopupRoute) {
      SystemBars._popupOpened(newRoute);
      SystemBars.onPopup(true);
    }
  }
}
