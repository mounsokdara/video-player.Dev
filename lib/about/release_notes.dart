import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:video_player_app/about/about_info.dart';

/// One published GitHub release of the app.
class ReleaseNote {
  const ReleaseNote({
    required this.tag,
    required this.title,
    required this.body,
    required this.url,
    this.apkUrl,
    this.publishedAt,
    this.prerelease = false,
  });

  final String tag;
  final String title;
  final String body;
  final String url;
  final String? apkUrl;
  final DateTime? publishedAt;
  final bool prerelease;

  /// Tag without the leading "v" (`v1.0.2.4` -> `1.0.2.4`).
  String get version => tag.replaceFirst(RegExp(r'^[vV]'), '');

  factory ReleaseNote.fromJson(Map<String, dynamic> j) {
    String? apk;
    for (final a in (j['assets'] as List<dynamic>? ?? const [])) {
      final m = a as Map<String, dynamic>;
      final name = (m['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apk = m['browser_download_url'] as String?;
        break;
      }
    }
    final tag = (j['tag_name'] as String?) ?? '';
    final name = (j['name'] as String?)?.trim() ?? '';
    return ReleaseNote(
      tag: tag,
      title: name.isEmpty ? tag : name,
      body: ((j['body'] as String?) ?? '').replaceAll('\r', '').trim(),
      url: (j['html_url'] as String?) ?? AboutInfo.releasesUrl,
      apkUrl: apk ?? (j['apkUrl'] as String?),
      publishedAt: DateTime.tryParse((j['published_at'] as String?) ?? ''),
      prerelease: (j['prerelease'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'tag_name': tag,
        'name': title,
        'body': body,
        'html_url': url,
        'apkUrl': apkUrl,
        'published_at': publishedAt?.toUtc().toIso8601String(),
        'prerelease': prerelease,
      };
}

/// Result of [ReleaseNotes.load].
class ReleaseFeed {
  const ReleaseFeed({required this.releases, required this.fromCache, this.error, this.savedAt});

  /// Newest first, as GitHub returns them.
  final List<ReleaseNote> releases;

  /// True when the list is the saved copy (offline or the request failed).
  final bool fromCache;
  final String? error;

  /// When the saved copy was fetched from GitHub.
  final DateTime? savedAt;

  /// Highest stable version published (falls back to any release when there is no stable one).
  ReleaseNote? get latest {
    ReleaseNote? best;
    for (final stable in const [true, false]) {
      for (final r in releases) {
        if (stable && r.prerelease) continue;
        if (_parse(r.version).isEmpty) continue;
        if (best == null || compareVersions(r.version, best.version) > 0) best = r;
      }
      if (best != null) return best;
    }
    return null;
  }
}

List<int> _parse(String v) =>
    RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();

/// Compares dotted versions numerically (`1.0.2.10` > `1.0.2.9`); missing parts count as 0.
int compareVersions(String a, String b) {
  final x = _parse(a), y = _parse(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p.compareTo(q);
  }
  return 0;
}

/// Release notes straight from the GitHub releases of the app (not the CHANGELOG.md in the repo).
/// The last successful answer is saved in the app's own cache directory (app data, internal
/// storage: never Android/data), so the changelog also opens offline.
class ReleaseNotes {
  ReleaseNotes._();

  static const _fileName = 'release_notes.json';
  static const _freshFor = Duration(hours: 1);

  static Future<File> _file() async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<ReleaseFeed?> _readSaved() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final list = (j['releases'] as List<dynamic>)
          .map((e) => ReleaseNote.fromJson(e as Map<String, dynamic>))
          .toList();
      return ReleaseFeed(
        releases: list,
        fromCache: true,
        savedAt: DateTime.tryParse((j['fetchedAt'] as String?) ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(List<ReleaseNote> list) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
        'releases': [for (final r in list) r.toJson()],
      }));
    } catch (_) {}
  }

  /// Returns the saved copy while it is younger than an hour, otherwise asks GitHub. [refresh]
  /// always asks GitHub. When GitHub cannot be reached the saved copy (if any) is returned with
  /// [ReleaseFeed.fromCache] set.
  static Future<ReleaseFeed> load({bool refresh = false}) async {
    final saved = await _readSaved();
    if (!refresh && saved != null && saved.savedAt != null) {
      if (DateTime.now().toUtc().difference(saved.savedAt!) < _freshFor) return saved;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(
        'https://api.github.com/repos/${AboutInfo.repoSlug}/releases?per_page=100',
      ));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'video-player-app');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
      final list = <ReleaseNote>[
        for (final e in jsonDecode(body) as List<dynamic>)
          if ((e as Map<String, dynamic>)['draft'] != true) ReleaseNote.fromJson(e),
      ];
      await _save(list);
      return ReleaseFeed(releases: list, fromCache: false, savedAt: DateTime.now().toUtc());
    } catch (e) {
      final msg = e is SocketException || e is TimeoutException ? 'No connection to GitHub' : 'Could not read GitHub releases';
      if (saved != null) return ReleaseFeed(releases: saved.releases, fromCache: true, error: msg, savedAt: saved.savedAt);
      return ReleaseFeed(releases: const [], fromCache: false, error: msg);
    } finally {
      client.close(force: true);
    }
  }
}

/// Release-note markdown reduced to readable plain text (links, bold, code marks removed).
String plainNotes(String md) {
  var s = md;
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!);
  s = s.replaceAll(RegExp(r'(\*\*|__|`)'), '');
  return s;
}
