import 'package:flutter/material.dart';

import 'package:video_player_app/about/about_info.dart';
import 'package:video_player_app/about/about_widgets.dart';
import 'package:video_player_app/about/release_notes.dart';

/// "Check For Update": asks the GitHub releases for the newest version and compares it with the
/// installed one.
Future<void> checkForUpdate(BuildContext context) async {
  final rootNav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(width: 20),
          Expanded(child: Text('Checking for updates...')),
        ]),
      ),
    ),
  );
  final feed = await ReleaseNotes.load(refresh: true);
  rootNav.pop();
  if (!context.mounted) return;

  final latest = feed.latest;
  if (latest == null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Could not check for updates'),
        content: Text(feed.error != null ? '${feed.error}. Check your connection and try again.' : 'No release was found.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return;
  }

  final newer = compareVersions(latest.version, AboutInfo.displayVersion) > 0;
  if (!newer) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("You're up to date"),
        content: Text(
          '${AboutInfo.name} v${AboutInfo.displayVersion} is the latest version.'
          '${feed.fromCache ? '\n\n(${feed.error ?? 'Saved copy'} - this may be out of date.)' : ''}',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return;
  }

  final notes = plainNotes(latest.body).split('\n').where((l) => l.trim().isNotEmpty).take(10).join('\n');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Update available'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('v${latest.version}  (installed: v${AboutInfo.displayVersion})',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (notes.isNotEmpty) ...[const SizedBox(height: 12), Text(notes)],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            openExternal(latest.apkUrl ?? latest.url);
          },
          child: Text(latest.apkUrl != null ? 'Download' : 'View release'),
        ),
      ],
    ),
  );
}
