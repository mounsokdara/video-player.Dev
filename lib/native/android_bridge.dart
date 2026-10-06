import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:video_player_app/core/models.dart';

class AndroidBridge {
  AndroidBridge._();
  static const _ch = MethodChannel('app.videoplayer/android');
  static const _ev = EventChannel('app.videoplayer/events');

  static Stream<Map<String, dynamic>>? _events;

  static Stream<Map<String, dynamic>> events() {
    if (_events == null) {
      final raw = _ev.receiveBroadcastStream().map((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return <String, dynamic>{'type': '$e'};
      }).handleError((_) {});
      _events = raw.asBroadcastStream(onCancel: (_) {});
      _events!.listen((_) {});
    }
    return _events!;
  }

  static Future<int> sdkInt() async {
    try {
      return await _ch.invokeMethod<int>('sdkInt') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> hasAllFilesAccess() async {
    try {
      return await _ch.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAllFilesAccess() async {
    try {
      await _ch.invokeMethod('requestAllFilesAccess');
    } catch (_) {}
  }

  static Future<bool> canManageMedia() async {
    try {
      return await _ch.invokeMethod<bool>('canManageMedia') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestManageMedia() async {
    try {
      await _ch.invokeMethod('requestManageMedia');
    } catch (_) {}
  }

  static Future<List<StorageVolumeInfo>> listStorageVolumes() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listStorageVolumes') ?? [];
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return StorageVolumeInfo(
          path: m['path'] as String? ?? '',
          description: m['description'] as String? ?? 'Storage',
          isPrimary: m['isPrimary'] as bool? ?? false,
          isRemovable: m['isRemovable'] as bool? ?? false,
          isSd: m['isSd'] as bool? ?? false,
          isUsb: m['isUsb'] as bool? ?? false,
          state: m['state'] as String? ?? 'mounted',
        );
      }).where((v) => v.path.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> listVideoFiles(
    String path, {
    bool includeHidden = false,
    bool hiddenOnly = false,
    bool skipNomedia = true,
  }) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listVideoFiles', {
        'path': path,
        'includeHidden': includeHidden,
        'hiddenOnly': hiddenOnly,
        'skipNomedia': skipNomedia,
      }) ?? [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> deletePath(String path) async {
    try {
      return await _ch.invokeMethod<bool>('deletePath', {'path': path}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deletePaths(List<String> paths) async {
    if (paths.isEmpty) return true;
    try {
      return await _ch.invokeMethod<bool>('deletePaths', {'paths': paths}) ?? false;
    } catch (_) {
      var ok = true;
      for (final path in paths) {
        if (!await deletePath(path)) ok = false;
      }
      return ok;
    }
  }

  static Future<String?> renamePath(String path, String name) async {
    try {
      return await _ch.invokeMethod<String>('renamePath', {'path': path, 'name': name});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> copyPath(String src, String dest) async {
    try {
      return await _ch.invokeMethod<bool>('copyPath', {'src': src, 'dest': dest}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> movePath(String src, String dest) async {
    try {
      return await _ch.invokeMethod<String>('movePath', {'src': src, 'dest': dest});
    } catch (_) {
      return null;
    }
  }

  static Future<int> fileSize(String path) async {
    try {
      return await _ch.invokeMethod<int>('fileSize', {'path': path}) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> listIndexedVideos() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listIndexedVideos') ?? [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setOrientation(String mode) async {
    try {
      await _ch.invokeMethod('setOrientation', {'mode': mode});
    } catch (_) {}
  }

  static Future<void> setKeepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {}
  }

  static Future<void> enterPip() async {
    try {
      await _ch.invokeMethod('enterPip');
    } catch (_) {}
  }

  static Future<void> setPipEnabled(bool on) async {
    try {
      await _ch.invokeMethod('setPipEnabled', {'on': on});
    } catch (_) {}
  }

  static Future<void> setPlaying(bool on) async {
    try {
      await _ch.invokeMethod('setPlaying', {'on': on});
    } catch (_) {}
  }

  static Future<void> applyEqualizer({
    required bool enabled,
    required List<int> bands,
    required bool bassOn,
    required int bass,
    required bool surroundOn,
    required int surround,
  }) async {
    try {
      await _ch.invokeMethod('applyEqualizer', {
        'enabled': enabled,
        'bands': bands,
        'bassOn': bassOn,
        'bass': bass,
        'surroundOn': surroundOn,
        'surround': surround,
      });
    } catch (_) {}
  }

  static Future<void> preparePreview(String path) async {
    try {
      await _ch.invokeMethod('preparePreview', {'path': path});
    } catch (_) {}
  }

  static Future<void> requestAudioFocus() async {
    try {
      await _ch.invokeMethod('requestAudioFocus');
    } catch (_) {}
  }

  static Future<void> abandonAudioFocus() async {
    try {
      await _ch.invokeMethod('abandonAudioFocus');
    } catch (_) {}
  }

  static Future<void> setStereoVolume(double left, double right) async {
    try {
      await _ch.invokeMethod('setStereoVolume', {
        'left': left.clamp(0.0, 1.0).toDouble(),
        'right': right.clamp(0.0, 1.0).toDouble(),
      });
    } catch (_) {}
  }

  static Future<void> startBackground({
    required String title,
    String? artist,
    bool playing = true,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    try {
      await _ch.invokeMethod('startBackground', {
        'title': title,
        'artist': artist ?? 'Video Player',
        'playing': playing,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
    } catch (_) {}
  }

  static Future<void> updateBackground({
    required String title,
    String? artist,
    bool playing = true,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    try {
      await _ch.invokeMethod('updateBackground', {
        'title': title,
        'artist': artist ?? 'Video Player',
        'playing': playing,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
    } catch (_) {}
  }

  static Future<void> stopBackground() async {
    try {
      await _ch.invokeMethod('stopBackground');
    } catch (_) {}
  }

  static Future<String?> screenshotWindow({String? title, String? path, int positionMs = 0}) async {
    try {
      return await _ch.invokeMethod<String>('screenshotWindow', {
        'title': title ?? 'frame',
        if (path != null) 'path': path,
        'positionMs': positionMs,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> thumbnailBytes(String path, {int size = 240}) async {
    try {
      final raw = await _ch.invokeMethod('thumbnailBytes', {
        'path': path,
        'size': size,
      });
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
    } catch (_) {}
    return null;
  }

  static Future<Uint8List?> previewFrame({required String path, required int positionMs, int longEdge = 180}) async {
    try {
      final raw = await _ch.invokeMethod('previewFrame', {
        'path': path,
        'positionMs': positionMs,
        'longEdge': longEdge,
      });
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> mediaInfo(String path) async {
    try {
      final raw = await _ch.invokeMethod('mediaInfo', {'path': path});
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }

  static Future<String?> pendingOpen() async {
    try {
      return await _ch.invokeMethod<String>('pendingOpen');
    } catch (_) {
      return null;
    }
  }

  static Future<void> toast(String msg) async {
    try {
      await _ch.invokeMethod('toast', {'msg': msg});
    } catch (_) {}
  }

  static Future<String?> lastCrash() async {
    try {
      return await _ch.invokeMethod<String>('lastCrash');
    } catch (_) {
      return null;
    }
  }

  static Future<void> applySystemBars({required bool lightIcons, required bool contrast, required bool hide}) async {
    try {
      await _ch.invokeMethod('applySystemBars', {
        'lightIcons': lightIcons,
        'contrast': contrast,
        'hide': hide,
      });
    } catch (_) {}
  }

  static Future<void> openCrashReport({String? report}) async {
    try {
      await _ch.invokeMethod('openCrashReport', {'report': report});
    } catch (_) {}
  }

  static Future<void> debugLog(String line) async {
    try {
      await _ch.invokeMethod('debugLog', {'line': line});
    } catch (_) {}
  }

  static Future<void> clearLogs() async {
    try {
      await _ch.invokeMethod('clearLogs');
    } catch (_) {}
  }

  static Future<void> breadcrumb(String action) async {
    try {
      await _ch.invokeMethod('breadcrumb', {'action': action});
    } catch (_) {}
  }

  static Future<bool> pickerAllowMultiple() async {
    try {
      return await _ch.invokeMethod<bool>('pickerAllowMultiple') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> completePick({String? path, List<String>? paths}) async {
    try {
      return await _ch.invokeMethod<bool>('completePick', {
            'path': path,
            'paths': paths,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancelPick() async {
    try {
      await _ch.invokeMethod('cancelPick');
    } catch (_) {}
  }
}
