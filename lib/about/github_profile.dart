import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Public GitHub profile of the app author, fetched live (one request,
/// cached for the rest of the session).
class GithubProfile {
  const GithubProfile({required this.login, this.name, this.bio, this.avatarUrl});
  final String login;
  final String? name;
  final String? bio;
  final String? avatarUrl;

  static Future<GithubProfile?>? _cached;

  static Future<GithubProfile?> load(String login) {
    return _cached ??= _fetch(login).then((p) {
      if (p == null) _cached = null; // retry next time after a failure
      return p;
    });
  }

  static Future<GithubProfile?> _fetch(String login) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/users/$login'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'video-player-app');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      String? clean(Object? v) {
        final s = (v as String?)?.replaceAll('\r', '').replaceAll(RegExp(r'\n{2,}'), '\n').trim();
        return s == null || s.isEmpty ? null : s;
      }
      return GithubProfile(
        login: (j['login'] as String?) ?? login,
        name: clean(j['name']),
        bio: clean(j['bio']),
        avatarUrl: j['avatar_url'] == null ? null : '${j['avatar_url']}&s=160',
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
