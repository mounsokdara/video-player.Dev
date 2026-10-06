import 'dart:io';

enum PlayMode { order, loopAll, repeatOne, shuffle, noAutoplay }

enum LayoutMode { list, grid }

enum SortBy { name, date, size, duration, folder }

enum AspectMode {
  fit,
  zoom,
  stretch,
  original,
  ratio16_9,
  ratio4_3,
  ratio21_9,
  ratio1_1,
  ratio2_35,
  ratio9_16,
}

enum RotationLock {
  auto,
  autoVideo,
  landscape,
  portrait,
  landscapeNormal,
  landscapeReverse,
  portraitNormal,
  portraitReverse,
  none,
}

extension RotationLockLabel on RotationLock {
  String get label => switch (this) {
        RotationLock.none => 'None',
        RotationLock.auto => 'Auto rotate sensor',
        RotationLock.autoVideo => 'Auto rotate to video resolution',
        RotationLock.landscape => 'Lock landscape',
        RotationLock.portrait => 'Lock portrait',
        RotationLock.landscapeNormal => 'Lock normal landscape',
        RotationLock.landscapeReverse => 'Lock upside-down landscape',
        RotationLock.portraitNormal => 'Lock portrait normal',
        RotationLock.portraitReverse => 'Lock portrait upside-down',
      };
}

enum DecoderMode { auto, hw, sw }

enum ThemeModePref { system, light, dark }

enum PlaylistUiStyle { sheet, youtube }

class VideoItem {
  VideoItem({
    required this.id,
    required this.path,
    required this.title,
    required this.folder,
    required this.size,
    required this.modified,
    this.created,
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
    this.mime,
    this.thumbnail,
    this.progress = 0,
    this.bookmarked = false,
    this.assetId,
    this.fps,
    this.bitrate,
    this.frameCount,
  });

  final String id;
  final String path;
  final String title;
  final String folder;
  final int size;
  final DateTime modified;
  final DateTime? created;
  final Duration duration;
  final int width;
  final int height;
  final String? mime;
  final String? thumbnail;
  double progress;
  bool bookmarked;
  final String? assetId;
  final double? fps;
  final int? bitrate;
  final int? frameCount;

  String get folderName {
    final parts = folder.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? folder : parts.last;
  }

  String get extension {
    final i = title.lastIndexOf('.');
    return i == -1 ? '' : title.substring(i + 1).toLowerCase();
  }

  bool get exists => File(path).existsSync();

  String get resolutionLabel {
    if (width <= 0 || height <= 0) return 'Unknown';
    final gcd = _gcd(width, height);
    return '$width×$height  (${width ~/ gcd}:${height ~/ gcd})';
  }

  String get fpsLabel {
    if (fps == null || fps! <= 0) return '-';
    final v = fps!;
    if ((v - v.round()).abs() < 0.05) return '${v.round()} fps';
    return '${v.toStringAsFixed(2)} fps';
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a == 0 ? 1 : a;
  }

  VideoItem copyWith({
    Duration? duration,
    int? width,
    int? height,
    String? thumbnail,
    double? progress,
    bool? bookmarked,
    String? title,
    String? path,
    String? folder,
    int? size,
    double? fps,
    int? bitrate,
    int? frameCount,
  }) {
    return VideoItem(
      id: id,
      path: path ?? this.path,
      title: title ?? this.title,
      folder: folder ?? this.folder,
      size: size ?? this.size,
      modified: modified,
      created: created,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      mime: mime,
      thumbnail: thumbnail ?? this.thumbnail,
      progress: progress ?? this.progress,
      bookmarked: bookmarked ?? this.bookmarked,
      assetId: assetId,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      frameCount: frameCount ?? this.frameCount,
    );
  }
}

class FolderNode {
  FolderNode({
    required this.path,
    required this.name,
    this.isRoot = false,
    this.isSd = false,
    this.isUsb = false,
    this.videoCount = 0,
    this.size = 0,
  });

  final String path;
  final String name;
  final bool isRoot;
  final bool isSd;
  final bool isUsb;
  int videoCount;
  int size;
}

class StorageVolumeInfo {
  StorageVolumeInfo({
    required this.path,
    required this.description,
    required this.isPrimary,
    required this.isRemovable,
    required this.isSd,
    required this.isUsb,
    this.state = 'mounted',
  });

  final String path;
  final String description;
  final bool isPrimary;
  final bool isRemovable;
  final bool isSd;
  final bool isUsb;
  final String state;
}
