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
