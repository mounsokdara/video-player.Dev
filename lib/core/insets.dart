import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/native/android_bridge.dart';

class SystemBars {
  static int popupCount = 0;
  static bool alwaysHide = false;
  static Brightness iconBrightness = Brightness.light;

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

  static SystemUiOverlayStyle overlay({required Brightness icons, bool contrast = false}) {
    final status = icons;
    final bar = icons == Brightness.light ? Brightness.dark : Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: status,
      statusBarBrightness: bar,
      systemNavigationBarIconBrightness: status,
      systemNavigationBarContrastEnforced: contrast,
      systemStatusBarContrastEnforced: false,
    );
  }

  static void apply({required Brightness icons, bool contrast = false, bool forceShow = false, bool? hide}) {
    iconBrightness = icons;
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
          contrast: false,
          hide: true,
        ));
      }
    });
  }

  static void onPopup(bool open) {
    if (open) {
      popupCount++;
      apply(icons: iconBrightness, forceShow: true);
    } else {
      if (popupCount > 0) popupCount--;
      apply(icons: iconBrightness);
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

/// Keeps a page clear of the system navigation bar and display cutouts and makes those areas solid.
///
/// The app draws edge to edge, so the (transparent) navigation bar sits on top of the page. In
/// landscape it is on the left or right, where an explicit list padding does not add an inset, and
/// content scrolls underneath it. This widget:
///  - pads [child] by the left / right system insets (and removes them from the [MediaQuery] it
///    gives [child], so nested zones never pad twice), and
///  - paints solid [color] (default: the theme surface) over the left, right and bottom bar areas,
///    so content never shows through the bar. The bottom strip is skipped while the keyboard is up.
///
/// The bottom inset is deliberately not padded here: pages already add it to their list padding.
class SystemBarSafeZone extends StatelessWidget {
  const SystemBarSafeZone({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context);
    final fill = color ?? Theme.of(context).colorScheme.surface;
    final keyboard = MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(left: pad.left, right: pad.right),
          child: MediaQuery.removeViewPadding(
            context: context,
            removeLeft: true,
            removeRight: true,
            child: child,
          ),
        ),
        if (pad.left > 0)
          Positioned(left: 0, top: 0, bottom: 0, width: pad.left, child: IgnorePointer(child: ColoredBox(color: fill))),
        if (pad.right > 0)
          Positioned(right: 0, top: 0, bottom: 0, width: pad.right, child: IgnorePointer(child: ColoredBox(color: fill))),
        if (pad.bottom > 0 && !keyboard)
          Positioned(left: 0, right: 0, bottom: 0, height: pad.bottom, child: IgnorePointer(child: ColoredBox(color: fill))),
      ],
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
