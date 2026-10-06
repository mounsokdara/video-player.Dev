import 'dart:async';

import 'package:flutter/material.dart';

import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/settings/settings_ui.dart' show settingsBackLeading;

/// Open in app: which links / files / share targets Android sends to this app. The list is built
/// at runtime from what the system resolves for this app (its real manifest intent filters).
class OpenInAppPage extends StatefulWidget {
  const OpenInAppPage({super.key});

  @override
  State<OpenInAppPage> createState() => _OpenInAppPageState();
}

class _OpenInAppPageState extends State<OpenInAppPage> with WidgetsBindingObserver {
  static const _labels = <String, (IconData, String, String)>{
    'view_content': (Icons.video_file_outlined, 'Videos from other apps', 'Files, galleries and browsers (content://)'),
    'view_file': (Icons.folder_open, 'Video files', 'Direct file paths (file://)'),
    'send': (Icons.share_outlined, 'Share to this app', 'Share sheet, video/*'),
    'get_content': (Icons.attach_file, 'Pick a video for another app', 'Open from / Get content'),
    'pick': (Icons.ads_click, 'Video picker', 'Pick a video for another app'),
  };

  late Future<List<Map<String, dynamic>>> _entries = AndroidBridge.openInAppInfo();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The default may have changed in the system settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _entries = AndroidBridge.openInAppInfo());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(leading: settingsBackLeading(context), title: const Text('Open in app')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _entries,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          return ListView(
            padding: EdgeInsets.only(bottom: pad.bottom + 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'What Android opens in this app, read from the system. To make this app the default '
                  'for videos, choose "Always" in the system chooser or open the system settings.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ),
              for (final e in list) _tile(context, e),
              if (list.isEmpty)
                const ListTile(title: Text('Nothing to show'), subtitle: Text('Android did not return any entries.')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(AndroidBridge.openByDefaultSettings()),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open by default settings'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> e) {
    final cs = Theme.of(context).colorScheme;
    final id = e['id'] as String;
    final handled = e['handled'] == true;
    final isDefault = e['isDefault'] == true;
    final meta = _labels[id];
    final isView = id.startsWith('view');
    final status = !handled
        ? 'Not available'
        : isView
            ? (isDefault ? 'Default app' : 'Asks every time')
            : 'Available';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: handled ? cs.primaryContainer : cs.surfaceContainerHighest,
        foregroundColor: handled ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        child: Icon(meta?.$1 ?? Icons.open_in_new),
      ),
      title: Text(meta?.$2 ?? id),
      subtitle: Text(meta?.$3 ?? ''),
      trailing: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: handled && isDefault ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
