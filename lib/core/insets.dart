import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/native/android_bridge.dart';

class SystemBars {
  static int popupCount = 0;
  static bool alwaysHide = false;
  static Brightness iconBrightness = Brightness.light;

  /// Last `contrast` given to [apply]: false = transparent navigation bar (player), true = system default.
  static bool lastContrast = true;

  static EdgeInsets of(BuildContext context) => MediaQuery.viewPaddingOf(context);

  static EdgeInsets rawOf(BuildContext context) {
    return MediaQueryData.fromView(View.of(context)).viewPadding;
  }

  /// Bottom system bar height, taking the larger of the raw view padding and the (possibly
  /// consumed) MediaQuery value, so a sheet or page never ends up under the navigation bar.
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
      // Only without contrast (the player): a fully transparent bar. Everywhere else the color is
      // left to the system.
      systemNavigationBarColor: contrast ? null : Colors.transparent,
      systemNavigationBarDividerColor: contrast ? null : Colors.transparent,
      statusBarIconBrightness: status,
      statusBarBrightness: bar,
      systemNavigationBarIconBrightness: status,
      systemNavigationBarContrastEnforced: contrast,
      systemStatusBarContrastEnforced: false,
    );
  }

  static void apply({required Brightness icons, bool contrast = true, bool forceShow = false, bool? hide}) {
    iconBrightness = icons;
    lastContrast = contrast;
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

/// Keeps a page clear of the left / right system bars (navigation bar in landscape, cutouts).
///
/// It only pads [child] by those insets (and removes them from the [MediaQuery] it gives [child],
/// so nested zones never pad twice). The bar itself is left to the system: nothing is painted over
/// it. The bottom inset is not padded here, pages add it to their own list padding.
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
    if (route is PopupRoute) SystemBars.onPopup(true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) SystemBars.onPopup(false);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) SystemBars.onPopup(false);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PopupRoute) SystemBars.onPopup(false);
    if (newRoute is PopupRoute) SystemBars.onPopup(true);
  }
}
