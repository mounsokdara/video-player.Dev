import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';

import 'package:video_player_app/about/about_info.dart';

class _Pkg {
  _Pkg(this.name);
  final String name;
  final Set<String> texts = <String>{};
}

/// Every Dart / plugin license Flutter bundled into the app (LicenseRegistry), grouped by package.
Future<List<_Pkg>> _loadPackages() async {
  final map = <String, _Pkg>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs
        .map((p) => '${p.indent > 0 ? '    ' * p.indent : ''}${p.text}')
        .join('\n\n')
        .trim();
    if (text.isEmpty) continue;
    for (final name in entry.packages) {
      map.putIfAbsent(name, () => _Pkg(name)).texts.add(text);
    }
  }
  final list = map.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Open source licenses. Pure Dart (replaces the old native LicensesActivity).
class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key});

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  late final Future<List<_Pkg>> _packages = _loadPackages();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      body: CustomScrollView(slivers: [
        const SliverAppBar(pinned: true, title: Text('Open source licenses')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${AboutInfo.name} ${AboutInfo.displayVersion}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Created by ${AboutInfo.author}.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
        FutureBuilder<List<_Pkg>>(
          future: _packages,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
            }
            final items = snap.data ?? const <_Pkg>[];
            if (items.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('License text is not available in this build.')),
              );
            }
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 24),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final p = items[i];
                  final first = i == 0, last = i == items.length - 1;
                  const big = Radius.circular(20), small = Radius.circular(4);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.vertical(
                        top: first ? big : small,
                        bottom: last ? big : small,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(p.texts.length == 1 ? '1 license' : '${p.texts.length} licenses'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => _LicenseDetailPage(pkg: p)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _LicenseDetailPage extends StatelessWidget {
  const _LicenseDetailPage({required this.pkg});
  final _Pkg pkg;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(pkg.name)),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 24),
        child: SelectableText(
          pkg.texts.join('\n\n--------\n\n'),
          style: const TextStyle(fontSize: 12.5, height: 1.4, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
