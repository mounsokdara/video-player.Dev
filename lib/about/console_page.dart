import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player_app/core/developer_log.dart';
import 'package:video_player_app/core/slide_snackbar.dart';
import 'package:video_player_app/native/android_bridge.dart';

/// Debug log + crash breadcrumbs. Pure Dart (replaces the old native ConsoleActivity).
/// The log text itself still lives in app storage on the native side, so it survives restarts.
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  static const _emptyDebug = 'No debug lines yet. Turn on Log debug and use the player.';
  String _body = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final debug = (await AndroidBridge.readDebugLog()).trim();
    final crash = (await AndroidBridge.peekCrash()).trim();
    if (!mounted) return;
    setState(() {
      _body = '=== debug ===\n${debug.isEmpty ? _emptyDebug : debug}\n\n=== crash ===\n$crash';
      _loaded = true;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _body));
    if (!mounted) return;
    SlideSnackBar.show(context, message: 'Copied', behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2));
  }

  Future<void> _clear() async {
    DeveloperLog.clear();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(tooltip: 'Copy', icon: const Icon(Icons.content_copy), onPressed: _loaded ? _copy : null),
          IconButton(tooltip: 'Clear', icon: const Icon(Icons.delete_outline), onPressed: _loaded ? _clear : null),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 24),
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(_body, style: const TextStyle(fontSize: 12, height: 1.35, fontFamily: 'monospace')),
                ),
              ),
            ),
    );
  }
}
