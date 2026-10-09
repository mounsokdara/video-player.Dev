import 'package:flutter/material.dart';

import 'package:video_player_app/core/insets.dart';
import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/settings/settings.dart';
import 'package:video_player_app/settings/settings_ui.dart' show settingsBackLeading;

/// Accessibility > Live Caption (`/live-caption`, hosted by `LiveCaptionActivity`).
/// Toggle for the player's live captions, a shortcut to the system caption style screen, and the
/// entry to the classic "Manage AI model" screens (download and defaults).
class LiveCaptionPage extends StatefulWidget {
  const LiveCaptionPage({super.key});

  @override
  State<LiveCaptionPage> createState() => _LiveCaptionPageState();
}

class _LiveCaptionPageState extends State<LiveCaptionPage> with WidgetsBindingObserver {
  bool _ready = false;
  String _model = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final st = await AndroidBridge.liveCaptionStatus();
    if (!mounted) return;
    setState(() {
      _ready = st['ready'] == true;
      _model = '${st['model'] ?? ''}';
    });
  }

  String get _modelLabel => switch (_model) {
        'base' => 'Whisper Base',
        'small' => 'Whisper Small',
        _ => _model,
      };

  @override
  Widget build(BuildContext context) {
    final s = appSettings;
    final pad = MediaQuery.viewPaddingOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final scheme = Theme.of(context).colorScheme;
    return SystemBarSafeZone(
      child: Scaffold(
        appBar: AppBar(leading: settingsBackLeading(context), title: const Text('Live Caption')),
        body: ListView(
          padding: EdgeInsets.only(bottom: insets.bottom + pad.bottom + 24),
          children: [
            SwitchListTile(
              title: const Text('Enable Live Caption'),
              subtitle: const Text('Show captions of the spoken words while a video plays'),
              value: s.liveCaption,
              onChanged: (v) {
                setState(() => s.liveCaption = v);
                s.save();
              },
            ),
            if (!_ready)
              ListTile(
                leading: Icon(Icons.info_outline, color: scheme.primary),
                title: const Text('AI model needed'),
                subtitle: const Text('Download the speech engine and an AI model under Manage AI model.'),
              ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Caption preferences'),
              subtitle: const Text('Open system settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: AndroidBridge.openCaptionSettings,
            ),
            ListTile(
              title: const Text('Manage AI model'),
              subtitle: Text(_ready ? 'Ready: $_modelLabel' : 'No AI model downloaded'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AndroidBridge.openRoute('/live-caption/ai-model'),
            ),
          ],
        ),
      ),
    );
  }
}
