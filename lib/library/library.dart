import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:video_player_app/native/android_bridge.dart';
import 'package:video_player_app/core/models.dart';
import 'package:video_player_app/settings/settings.dart';

class LibraryService {
  LibraryService(this.settings);

  final AppSettings settings;
  final List<VideoItem> videos = [];
  final List<FolderNode> folders = [];
  final List<StorageVolumeInfo> volumes = [];
  bool permissionReady = false;
  bool allFiles = false;
  bool manageMedia = false;

  bool _scanning = false;
  bool get scanning => _scanning;
  final Map<String, Uint8List?> _thumbs = {};
  final Map<String, DateTime> _thumbMiss = {};
  String? clipPath;
  bool clipCut = false;
  List<String> clipPaths = [];

  bool get hasClipboard => clipPaths.isNotEmpty || (clipPath != null && clipPath!.isNotEmpty);

  void clearClipboard() {
    clipPath = null;
    clipCut = false;
    clipPaths = [];
  }

  void copyEntry(String path) => copyEntries([path]);

  void cutEntry(String path) => cutEntries([path]);

  void copyEntries(Iterable<String> paths) {
    clipPaths = paths.where((e) => e.isNotEmpty).toSet().toList();
    clipPath = clipPaths.isEmpty ? null : clipPaths.first;
    clipCut = false;
  }

  void cutEntries(Iterable<String> paths) {
    clipPaths = paths.where((e) => e.isNotEmpty).toSet().toList();
    clipPath = clipPaths.isEmpty ? null : clipPaths.first;
    clipCut = true;
  }

  Future<bool> pasteInto(String dir) async {
    final sources = clipPaths.isNotEmpty
        ? List<String>.from(clipPaths)
        : (clipPath == null || clipPath!.isEmpty ? <String>[] : [clipPath!]);
    if (sources.isEmpty) return false;
    var ok = true;
    for (final src in sources) {
      if (!await _pasteOne(dir, src)) ok = false;
    }
    clearClipboard();
    return ok;
  }

  Future<bool> _pasteOne(String dir, String src) async {
    if (src.isEmpty) return false;
    final name = p.basename(src);
    var dest = p.join(dir, name);
    if (dest == src) return false;
    if (File(dest).existsSync() || Directory(dest).existsSync()) {
      final stem = p.basenameWithoutExtension(name);
      final ext = p.extension(name);
      dest = p.join(dir, '${stem}_copy$ext');
    }
    if (clipCut) {
      final moved = await AndroidBridge.movePath(src, dest);
      if (moved == null) return false;
      final i = videos.indexWhere((v) => v.path == src);
      if (i >= 0) {
        videos[i] = videos[i].copyWith(path: moved, title: p.basename(moved));
      }
      _rebuildFolders();
      return true;
    }
    final copied = await AndroidBridge.copyPath(src, dest);
    if (copied) {
      VideoItem? srcItem;
      for (final v in videos) {
        if (v.path == src) srcItem = v;
      }
      videos.add(
        VideoItem(
          id: dest,
          path: dest,
          title: p.basename(dest),
          folder: dir,
          size: srcItem?.size ?? File(dest).lengthSync(),
          modified: DateTime.now(),
          duration: srcItem?.duration ?? Duration.zero,
        ),
      );
      _rebuildFolders();
    }
    return copied;
  }

  bool _askedAllFiles = false;

  Future<void> requestPermissions() async {
    await Permission.notification.request();

    final sdk = await AndroidBridge.sdkInt();
    if (sdk >= 30) {
      allFiles = await AndroidBridge.hasAllFilesAccess();
      if (!allFiles && !_askedAllFiles) {
        _askedAllFiles = true;
        await AndroidBridge.requestAllFilesAccess();
        allFiles = await AndroidBridge.hasAllFilesAccess();
      }
    } else {
      await Permission.storage.request();
      allFiles = await AndroidBridge.hasAllFilesAccess();
    }
    permissionReady = allFiles;
    manageMedia = await AndroidBridge.canManageMedia();
  }

  Future<void> ensureAllFiles() async {
    allFiles = await AndroidBridge.hasAllFilesAccess();
    if (!allFiles) await AndroidBridge.requestAllFilesAccess();
  }

  Future<void> scan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      await _scanBody();
    } finally {
      _scanning = false;
    }
  }

  Future<void> applyHidden(bool on) async {
    settings.showHiddenFolders = on;
    if (!on) {
      videos.removeWhere((v) => _isHiddenPath(v.path));
      _rebuildFolders();
      return;
    }
    while (_scanning) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    _scanning = true;
    try {
      if (volumes.isEmpty) {
        volumes
          ..clear()
          ..addAll(await AndroidBridge.listStorageVolumes());
      }
      final seen = videos.map((v) => v.path).toSet();
      await _collectHidden(videos, seen);
      _rebuildFolders();
    } finally {
      _scanning = false;
    }
  }

  Future<void> _scanBody() async {
    final next = <VideoItem>[];
    final seen = <String>{};
    final hidden = settings.showHiddenFolders;

    volumes
      ..clear()
      ..addAll(await AndroidBridge.listStorageVolumes());

    try {
      final indexed = await AndroidBridge.listIndexedVideos();
      for (final m in indexed) {
        final path = m['path'] as String? ?? '';
        if (path.isEmpty || seen.contains(path)) continue;
        if (!looksLikeVideo(path, mime: m['mime'] as String?)) continue;
        if (!hidden && _isHiddenPath(path)) continue;
        if (settings.skipNomedia && _underNomedia(path)) continue;
        seen.add(path);
        final durMs = (m['durationMs'] as num?)?.toInt() ?? 0;
        next.add(
          VideoItem(
            id: '${m['id'] ?? path}',
            path: path,
            title: m['name'] as String? ?? p.basename(path),
            folder: m['folder'] as String? ?? p.dirname(path),
            size: (m['size'] as num?)?.toInt() ?? 0,
            modified: DateTime.fromMillisecondsSinceEpoch((m['modified'] as num?)?.toInt() ?? 0),
            duration: Duration(milliseconds: durMs),
            width: (m['width'] as num?)?.toInt() ?? 0,
            height: (m['height'] as num?)?.toInt() ?? 0,
            mime: m['mime'] as String?,
            assetId: m['id']?.toString(),
            progress: settings.resumeMap[path] ?? 0,
            bookmarked: settings.bookmarks.contains(path),
          ),
        );
      }
    } catch (_) {}

    if (next.isEmpty) {
      try {
        final paths = await PhotoManager.getAssetPathList(
          type: RequestType.video,
          hasAll: true,
          onlyAll: true,
        );
        for (final album in paths) {
          final count = await album.assetCountAsync;
          for (var start = 0; start < count; start += 120) {
            final end = (start + 120).clamp(0, count);
            final assets = await album.getAssetListRange(start: start, end: end);
            for (final a in assets) {
              final path = _assetPath(a);
              if (path == null || path.isEmpty || seen.contains(path)) continue;
              if (!looksLikeVideo(path, mime: a.mimeType)) continue;
              if (!hidden && _isHiddenPath(path)) continue;
              if (settings.skipNomedia && _underNomedia(path)) continue;
              seen.add(path);
              next.add(
                VideoItem(
                  id: a.id,
                  path: path,
                  title: p.basename(path),
                  folder: p.dirname(path),
                  size: 0,
                  modified: a.modifiedDateTime,
                  created: a.createDateTime,
                  duration: a.duration > 0 ? Duration(seconds: a.duration) : Duration.zero,
                  width: a.width,
                  height: a.height,
                  mime: a.mimeType,
                  assetId: a.id,
                  progress: settings.resumeMap[path] ?? 0,
                  bookmarked: settings.bookmarks.contains(path),
                ),
              );
            }
          }
        }
      } catch (_) {}
    }

    final nativeTargets = <StorageVolumeInfo>[
      ...volumes.where((v) => v.path.isNotEmpty && !v.isPrimary),
      if (next.isEmpty) ...volumes.where((v) => v.path.isNotEmpty && v.isPrimary),
    ];
    for (final vol in nativeTargets) {
      if (vol.path.isEmpty) continue;
      final extra = await AndroidBridge.listVideoFiles(
        vol.path,
        includeHidden: hidden,
        skipNomedia: settings.skipNomedia,
      );
      _mergeNative(next, seen, extra);
    }
    if (hidden) {
      await _collectHidden(next, seen);
    }

    videos
      ..clear()
      ..addAll(next);
    _thumbs.removeWhere((k, _) => videos.every((v) => v.id != k && !k.startsWith('${v.id}:')));
    _thumbMiss.removeWhere((k, _) => videos.every((v) => v.id != k && !k.startsWith('${v.id}:')));
    _rebuildFolders();
  }

  Future<void> _collectHidden(List<VideoItem> into, Set<String> seen) async {
    for (final vol in volumes) {
      if (vol.path.isEmpty) continue;
      final extra = await AndroidBridge.listVideoFiles(
        vol.path,
        includeHidden: true,
        hiddenOnly: true,
        skipNomedia: settings.skipNomedia,
      );
      _mergeNative(into, seen, extra);
    }
  }

  void _mergeNative(List<VideoItem> into, Set<String> seen, List<Map<String, dynamic>> extra) {
    for (final m in extra) {
      final path = m['path'] as String? ?? '';
      if (path.isEmpty || seen.contains(path)) continue;
      if (!looksLikeVideo(path)) continue;
      if (!settings.showHiddenFolders && _isHiddenPath(path)) continue;
      if (settings.skipNomedia && _underNomedia(path)) continue;
      seen.add(path);
      final name = m['name'] as String? ?? p.basename(path);
      into.add(
        VideoItem(
          id: path,
          path: path,
          title: name,
          folder: m['folder'] as String? ?? p.dirname(path),
          size: (m['size'] as num?)?.toInt() ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch((m['modified'] as num?)?.toInt() ?? 0),
          duration: Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
          width: (m['width'] as num?)?.toInt() ?? 0,
          height: (m['height'] as num?)?.toInt() ?? 0,
          mime: m['mime'] as String?,
          progress: settings.resumeMap[path] ?? 0,
          bookmarked: settings.bookmarks.contains(path),
        ),
      );
    }
  }

  String? _assetPath(AssetEntity a) {
    final title = a.title;
    final rel = a.relativePath;
    if (title == null || title.isEmpty || rel == null || rel.isEmpty) return null;
    final prefix = rel.startsWith('/') ? rel : '/storage/emulated/0/$rel';
    final base = prefix.endsWith('/') ? prefix : '$prefix/';
    return '$base$title';
  }

  bool _isHiddenPath(String path) {
    return p.split(path).any((s) => s.startsWith('.'));
  }

  bool _underNomedia(String path) {
    try {
      var dir = p.dirname(path);
      var hops = 0;
      while (dir.isNotEmpty && hops < 16) {
        if (File(p.join(dir, '.nomedia')).existsSync()) return true;
        final parent = p.dirname(dir);
        if (parent == dir) break;
        dir = parent;
        hops++;
      }
    } catch (_) {}
    return false;
  }

  void _rebuildFolders() {
    folders.clear();
    final map = <String, FolderNode>{};
    for (final v in videos) {
      final node = map.putIfAbsent(
        v.folder,
        () => FolderNode(path: v.folder, name: v.folderName),
      );
      node.videoCount += 1;
      node.size += v.size;
    }
    folders.addAll(map.values);
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<VideoItem> sorted(SortBy sort, {bool desc = true, String query = '', String filter = 'all'}) {
    var list = List<VideoItem>.from(videos);
    if (filter == 'bookmarked') {
      list = list.where((v) => settings.bookmarks.contains(v.path) || v.bookmarked).toList();
    } else if (filter == 'pinned') {
      list = list.where((v) => settings.pinned.contains(v.path)).toList();
    }
    if (query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((v) => v.title.toLowerCase().contains(q) || v.folder.toLowerCase().contains(q)).toList();
    }
    int cmp(VideoItem a, VideoItem b) {
      final ap = settings.pinned.contains(a.path) ? 1 : 0;
      final bp = settings.pinned.contains(b.path) ? 1 : 0;
      if (ap != bp) return bp.compareTo(ap);
      final ab = (settings.bookmarks.contains(a.path) || a.bookmarked) ? 1 : 0;
      final bb = (settings.bookmarks.contains(b.path) || b.bookmarked) ? 1 : 0;
      if (filter == 'all' && ab != bb) return bb.compareTo(ab);
      switch (sort) {
        case SortBy.name:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case SortBy.date:
          return a.modified.compareTo(b.modified);
        case SortBy.size:
          return a.size.compareTo(b.size);
        case SortBy.duration:
          return a.duration.compareTo(b.duration);
        case SortBy.folder:
          return a.folder.toLowerCase().compareTo(b.folder.toLowerCase());
      }
    }

    list.sort(cmp);
    if (desc && sort != SortBy.name && sort != SortBy.folder) {
      final pins = list.where((v) => settings.pinned.contains(v.path)).toList();
      final rest = list.where((v) => !settings.pinned.contains(v.path)).toList().reversed.toList();
      return [...pins, ...rest];
    }
    return list;
  }

  int get totalBytes => videos.fold(0, (a, b) => a + b.size);

  Future<Uint8List?> thumbnailFor(VideoItem item, {int size = 240}) async {
    final key = '${item.id}:${item.modified.millisecondsSinceEpoch}:${item.size}';
    if (_thumbs.containsKey(key)) return _thumbs[key];
    final missed = _thumbMiss[key];
    if (missed != null && DateTime.now().difference(missed) < const Duration(seconds: 20)) {
      return null;
    }
    Uint8List? data;
    if (item.assetId != null) {
      try {
        final asset = await AssetEntity.fromId(item.assetId!);
        if (asset != null) {
          data = await asset.thumbnailDataWithSize(ThumbnailSize(size, size));
        }
      } catch (_) {}
    }
    if (data == null || data.isEmpty) {
      try {
        data = await AndroidBridge.thumbnailBytes(item.path, size: size);
      } catch (_) {}
    }
    if (data == null || data.isEmpty) {
      _thumbMiss[key] = DateTime.now();
      return null;
    }
    _thumbs[key] = data;
    _thumbMiss.remove(key);
    return data;
  }

  Future<bool> deleteVideos(List<VideoItem> items) async {
    if (items.isEmpty) return true;
    final paths = items.map((v) => v.path).where((p) => p.isNotEmpty).toList();
    await AndroidBridge.deletePaths(paths);
    var leftover = items.where((v) => File(v.path).existsSync()).toList();
    if (leftover.isNotEmpty) {
      manageMedia = await AndroidBridge.canManageMedia();
      if (!manageMedia) {
        await AndroidBridge.requestManageMedia();
      }
      await AndroidBridge.deletePaths(leftover.map((v) => v.path).toList());
      leftover = leftover.where((v) => File(v.path).existsSync()).toList();
    }
    var ok = leftover.isEmpty;
    for (final v in items) {
      if (!File(v.path).existsSync()) {
        videos.removeWhere((x) => x.id == v.id || x.path == v.path);
      } else {
        ok = false;
      }
    }
    _rebuildFolders();
    return ok;
  }

  Future<VideoItem?> rename(VideoItem item, String newName) async {
    final dest = await AndroidBridge.renamePath(item.path, newName);
    if (dest == null) return null;
    final next = item.copyWith(title: newName, path: dest);
    final i = videos.indexWhere((v) => v.id == item.id);
    if (i >= 0) videos[i] = next;
    return next;
  }

  Future<bool> deletePath(String path) async {
    final ok = await AndroidBridge.deletePath(path);
    videos.removeWhere((v) => v.path == path);
    _rebuildFolders();
    return ok;
  }

  List<FileSystemEntity> listDir(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return [];
    try {
      final ents = dir.listSync();
      ents.sort((a, b) {
        final ad = a is Directory;
        final bd = b is Directory;
        if (ad != bd) return ad ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      return ents.where((e) {
        final name = p.basename(e.path);
        if (!settings.showHiddenFolders && name.startsWith('.')) return false;
        if (e is Directory) {
          if (settings.skipNomedia && File(p.join(e.path, '.nomedia')).existsSync()) return false;
          return true;
        }
        if (settings.skipNomedia && _underNomedia(e.path)) return false;
        return looksLikeVideo(e.path);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

const videoExtensions = {
  '.mp4',
  '.mkv',
  '.webm',
  '.avi',
  '.mov',
  '.m4v',
  '.3gp',
  '.3gpp',
  '.3g2',
  '.3gp2',
  '.flv',
  '.wmv',
  '.asf',
  '.mpeg',
  '.mpg',
  '.mpe',
  '.m1v',
  '.m2v',
  '.mpv',
  '.mp2v',
  '.m2ts',
  '.mts',
  '.m2t',
  '.vob',
  '.f4v',
  '.ogv',
  '.ogm',
  '.ogx',
  '.rm',
  '.rmvb',
  '.divx',
  '.xvid',
  '.tod',
  '.vro',
  '.nsv',
  '.nuv',
  '.rec',
  '.wtv',
  '.amv',
  '.dv',
  '.mxf',
  '.gxf',
  '.h264',
  '.h265',
  '.hevc',
  '.264',
  '.265',
  '.qt',
  '.mp4v',
  '.mpeg1',
  '.mpeg2',
  '.mpeg4',
  '.ts',
  '.tts',
};

const skipExtensions = {
  '.tsx',
  '.js',
  '.jsx',
  '.mjs',
  '.cjs',
  '.json',
  '.txt',
  '.md',
  '.css',
  '.html',
  '.htm',
  '.xml',
  '.svg',
  '.map',
  '.yml',
  '.yaml',
  '.py',
  '.java',
  '.kt',
  '.dart',
  '.c',
  '.h',
  '.cpp',
  '.go',
  '.rs',
  '.sh',
  '.log',
  '.csv',
  '.toml',
  '.ini',
  '.cfg',
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.heic',
  '.heif',
  '.ico',
  '.tif',
  '.tiff',
  '.mp3',
  '.wav',
  '.flac',
  '.ogg',
  '.m4a',
  '.aac',
  '.wma',
  '.opus',
  '.oga',
  '.pdf',
  '.doc',
  '.docx',
  '.xls',
  '.xlsx',
  '.ppt',
  '.pptx',
  '.apk',
  '.zip',
  '.rar',
  '.7z',
};

bool looksLikeVideo(String path, {String? mime}) {
  if (path.startsWith('content:')) {
    final m = (mime ?? '').toLowerCase();
    if (m.isEmpty) return true;
    if (m.startsWith('video/')) return true;
    return false;
  }
  final name = p.basename(path).toLowerCase();
  if (name.endsWith('.d.ts')) return false;
  try {
    final f = File(path);
    if (f.existsSync() && f.lengthSync() <= 0) return false;
  } catch (_) {}
  final ext = p.extension(name).toLowerCase();
  final m = (mime ?? '').toLowerCase();
  if (m.startsWith('video/')) {
    if (ext == '.ts' && !m.contains('mp2t') && m != 'video/mp2t') {
      return _isMpegTsFile(path);
    }
    if (_isPlainTextFile(path)) return false;
    return true;
  }
  if (m.startsWith('image/') || m.startsWith('audio/') || m.startsWith('text/')) return false;
  if (ext == '.ts') return _isMpegTsFile(path);
  if (skipExtensions.contains(ext)) return false;
  if (_isPlainTextFile(path)) return false;
  if (videoExtensions.contains(ext)) return true;
  return _hasVideoMagic(path);
}

bool _hasVideoMagic(String path) {
  try {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() < 4) return false;
    final raf = f.openSync();
    final b = raf.readSync(16);
    raf.closeSync();
    if (b.length < 4) return false;
    if (b.length >= 8 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return true;
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) return true;
    if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) {
      final kind = String.fromCharCodes(b.sublist(8, 12));
      if (kind == 'AVI ' || kind == 'AVIX') return true;
    }
    if (b[0] == 0x46 && b[1] == 0x4C && b[2] == 0x56) return true;
    if (b[0] == 0 && b[1] == 0 && b[2] == 1 && (b[3] == 0xBA || b[3] == 0xB3)) return true;
    if (b.length >= 8 && b[0] == 0x30 && b[1] == 0x26 && b[2] == 0xB2 && b[3] == 0x75) return true;
    if (b[0] == 0x47) return _isMpegTsFile(path);
    return false;
  } catch (_) {
    return false;
  }
}

bool _isMpegTsFile(String path) {
  try {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() < 188) return false;
    final raf = f.openSync();
    final b = raf.readByteSync();
    raf.closeSync();
    return b == 0x47;
  } catch (_) {
    return false;
  }
}

bool _isPlainTextFile(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return false;
    final len = f.lengthSync();
    if (len <= 0) return false;
    final raf = f.openSync();
    final b = raf.readSync(len < 512 ? len : 512);
    raf.closeSync();
    return _bytesArePlainText(b);
  } catch (_) {
    return false;
  }
}

bool _bytesArePlainText(List<int> b) {
  final n = b.length;
  if (n <= 0) return false;
  final b0 = b[0] & 0xFF;
  final b1 = n > 1 ? b[1] & 0xFF : 0;
  if (n >= 2 && ((b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF))) return true;
  var i = 0;
  if (n >= 3 && b0 == 0xEF && b1 == 0xBB && (b[2] & 0xFF) == 0xBF) {
    i = 3;
    if (i >= n) return true;
  }
  var nul = 0;
  var ctrl = 0;
  var text = 0;
  var high = 0;
  for (var j = i; j < n; j++) {
    final u = b[j] & 0xFF;
    if (u == 0) {
      nul++;
    } else if (u == 0x09 || u == 0x0A || u == 0x0D || (u >= 0x20 && u <= 0x7E)) {
      text++;
    } else if (u < 0x20 || u == 0x7F) {
      ctrl++;
    } else {
      high++;
    }
  }
  final len = n - i;
  if (len <= 0) return true;
  if (nul > 0) return nul * 5 >= len * 2 && text * 5 >= len * 2;
  if (ctrl * 20 > len) return false;
  if (text * 100 >= len * 85) return true;
  return ctrl == 0 && high > 0 && text + high == len && _utf8LooksValid(b, i);
}

bool _utf8LooksValid(List<int> b, int start) {
  var i = start;
  while (i < b.length) {
    final c = b[i] & 0xFF;
    final need = c < 0x80
        ? 0
        : (c >= 0xC2 && c <= 0xDF)
            ? 1
            : (c >= 0xE0 && c <= 0xEF)
                ? 2
                : (c >= 0xF0 && c <= 0xF4)
                    ? 3
                    : -1;
    if (need < 0) return false;
    if (i + need >= b.length) return true;
    for (var k = 1; k <= need; k++) {
      if (b[i + k] & 0xC0 != 0x80) return false;
    }
    i += 1 + need;
  }
  return true;
}

String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '${d.inMinutes}:$s';
}
