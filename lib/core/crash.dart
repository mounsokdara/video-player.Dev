import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/core/developer_log.dart';

final appNavigator = GlobalKey<NavigatorState>();

class CrashLog {
  CrashLog._();

  static final reports = <String>[];
  static const _max = 16;
  static bool _showing = false;
  static bool _queued = false;
  static String lastAction = '';
  static String? _lastFingerprint;
  static StreamSubscription<Map<String, dynamic>>? _events;

  static String get text {
    final buf = StringBuffer();
    if (lastAction.isNotEmpty) {
      buf.writeln('Last action: $lastAction');
      buf.writeln();
    }
    if (reports.isEmpty) {
      buf.writeln('No crash captured in this session.');
      buf.writeln('If the app closed by itself, copy this screen anyway - the last action is the clue.');
      return buf.toString();
    }
    for (final r in reports) {
      buf.writeln(r);
      buf.writeln();
    }
    return buf.toString().trim();
  }

  static Future<void> install() async {
    FlutterError.onError = (details) {
      record('FLUTTER', details.exceptionAsString(), details.stack);
      FlutterError.presentError(details);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      record('PLATFORM', '$error', stack);
      return true;
    };
    ErrorWidget.builder = (details) {
      record('WIDGET', details.exceptionAsString(), details.stack);
      return Material(
        color: Colors.black,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'UI error\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    };
    _events ??= AndroidBridge.events().listen((e) {
      if (e['type'] == 'crash') {
        record('NATIVE', '${e['message'] ?? 'native crash'}', null, extra: '${e['stack'] ?? ''}');
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      lastAction = prefs.getString('lastAction') ?? lastAction;
      final native = await AndroidBridge.lastCrash();
      if (native != null && native.trim().isNotEmpty) {
        record('LAST_LAUNCH', native.trim(), null);
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    reports.clear();
    lastAction = '';
    _lastFingerprint = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastAction');
    } catch (_) {}
    await AndroidBridge.clearLogs();
  }

  static Future<void> breadcrumb(String action) async {
    lastAction = '${DateTime.now().toIso8601String()}  $action';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastAction', lastAction);
      await AndroidBridge.breadcrumb(lastAction);
    } catch (_) {}
  }

  static void record(String kind, String message, StackTrace? stack, {String? extra}) {
    final fp = '$kind|$message';
    if (fp == _lastFingerprint) return;
    _lastFingerprint = fp;
    final buf = StringBuffer()
      ..writeln('===== $kind ${DateTime.now().toIso8601String()} =====')
      ..writeln(message);
    if (stack != null) buf.writeln(stack);
    if (extra != null && extra.trim().isNotEmpty) buf.writeln(extra.trim());
    reports.add(buf.toString().trim());
    if (reports.length > _max) reports.removeAt(0);
    DeveloperLog.append('$kind $message');
    const autoShow = {
      'PLAY',
      'EQ',
      'NATIVE',
      'PLATFORM',
      'ZONE',
      'LAST_LAUNCH',
      'LIBRARY',
      'WIDGET',
      'FLUTTER',
      'VIDEO_WIDGET',
    };
    if (autoShow.contains(kind)) {
      final low = message.toLowerCase();
      if (low.contains('no active player') ||
          low.contains('no active stream to cancel') ||
          low.contains('source error') ||
          low.contains('exoplaybackexception') ||
          low.contains('process_died') ||
          low.contains('flutterjni is not attached') ||
          low.contains('flutterjni is not attached to native') ||
          low.contains('cannot execute operation because flutterjni') ||
          low.contains('startforegroundservice() did not then call') ||
          low.contains('did not then call service.startforeground') ||
          low.contains('remoteserviceexception')) {
        return;
      }
      scheduleShow();
    }
  }

  static void scheduleShow() {
    if (_showing || _queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      show();
    });
  }

  static Future<void> show() async {
    final ctx = appNavigator.currentContext;
    if (ctx == null) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_showing) show();
      });
      return;
    }
    if (_showing) return;
    _showing = true;
    try {
      final log = text;
      await showDialog<void>(
        context: ctx,
        barrierDismissible: true,
        builder: (c) {
          return AlertDialog(
            title: const Text('Crash report'),
            content: SizedBox(
              width: 460,
              height: 380,
              child: SingleChildScrollView(
                child: SelectableText(
                  log,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: log));
                  if (c.mounted) {
                    SlideSnackBar.show(c, message: 'Copied. Paste it in chat.', behavior: SnackBarBehavior.floating);
                  }
                },
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (_) {
    } finally {
      _showing = false;
    }
  }
}
