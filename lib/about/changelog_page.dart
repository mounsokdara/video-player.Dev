import 'package:flutter/material.dart';

import 'package:video_player_app/about/about_info.dart';
import 'package:video_player_app/about/about_widgets.dart';
import 'package:video_player_app/about/release_notes.dart';
import 'package:video_player_app/core/insets.dart';

/// Every release note of the app, read from the GitHub releases (saved in the app's cache folder
/// for offline use).
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  ReleaseFeed? _feed;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    final feed = await ReleaseNotes.load(refresh: refresh);
    if (!mounted) return;
    setState(() {
      _feed = feed;
      _loading = false;
    });
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[l.month - 1]} ${l.day}, ${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = SystemBars.bottomInset(context);
    final feed = _feed;
    final releases = feed?.releases ?? const <ReleaseNote>[];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              leading: standaloneBack(context),
              title: const Text('Changelog'),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : () => _load(refresh: true),
                ),
              ],
            ),
            if (_loading && feed == null)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else ...[
              if (feed != null && (feed.error != null || feed.fromCache))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      feed.error != null
                          ? '${feed.error}${releases.isEmpty ? '.' : ' - showing the saved copy.'}'
                          : 'Showing the saved copy.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              if (releases.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(feed?.error == null ? 'No releases published yet.' : 'Release notes are not available right now.'),
                        const SizedBox(height: 12),
                        TextButton(onPressed: () => openExternal(AboutInfo.releasesUrl), child: const Text('Open on GitHub')),
                      ]),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: releases.length,
                  itemBuilder: (context, i) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, i == releases.length - 1 ? bottom + 24 : 8),
                        child: _ReleaseCard(note: releases[i], date: _date(releases[i].publishedAt)),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.note, required this.date});
  final ReleaseNote note;
  final String date;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lines = plainNotes(note.body).split('\n');
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openExternal(note.url),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(note.title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              if (note.prerelease)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
                  child: Text('Pre-release', style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer)),
                ),
            ]),
            if (date.isNotEmpty) Text(date, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            if (note.body.isEmpty)
              Text('No release notes.', style: TextStyle(color: cs.onSurfaceVariant))
            else
              for (final raw in lines) _line(context, raw),
          ]),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String raw) {
    final cs = Theme.of(context).colorScheme;
    final line = raw.trimRight();
    if (line.trim().isEmpty) return const SizedBox(height: 6);
    final heading = RegExp(r'^\s*#{1,6}\s+(.*)$').firstMatch(line);
    if (heading != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(heading.group(1)!, style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
      );
    }
    final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      final indent = bullet.group(1)!.length >= 2 ? 16.0 : 0.0;
      return Padding(
        padding: EdgeInsets.only(left: indent, top: 1, bottom: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('\u2022  '),
          Expanded(child: Text(bullet.group(2)!)),
        ]),
      );
    }
    return Text(line.trim());
  }
}
