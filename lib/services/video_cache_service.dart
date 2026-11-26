import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

/// Private, in-app video cache (Android + iOS).
///
/// How it works
/// - First play streams from the network exactly as before. In parallel the
///   file is downloaded to the app's private cache directory.
/// - Later plays use the local file, so nothing is downloaded again.
///
/// Why users can't get the files out
/// - Files live in the app sandbox cache dir (`getApplicationCacheDirectory`):
///   not visible in Files / gallery / file managers, not included in
///   iCloud / Android backups, and the OS may purge them when storage is low.
/// - File names are opaque (`.v<hash>`, no extension), so they aren't picked
///   up as media by other apps.
/// - There is no share / export API on this class. [clearAll] wipes everything
///   on logout.
///
/// Limits: this cannot stop a user with a rooted/jailbroken device. For
/// stronger protection, use DRM (e.g. FairPlay / Widevine) with HLS.
class VideoCacheService {
  VideoCacheService._();
  static final VideoCacheService instance = VideoCacheService._();

  /// Max total size of cached videos. Least-recently-played files are evicted first.
  static const int maxCacheBytes = 1024 * 1024 * 1024; // 1 GB

  static const String _dirName = 'vc';
  static const String _prefix = '.v';
  static const String _partSuffix = '.part';

  final Dio _dio = Dio();
  final Map<String, CancelToken> _inFlight = {};
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// Stable key: content id + hash of the URL *path* (ignores the rotating
  /// signed-URL query string). If the admin uploads a new file for the same
  /// content, the path changes and the old cache entry is not reused.
  String _key(String contentId, String url) {
    final safeId = contentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '$_prefix${safeId}_${_fnv1a(Uri.parse(url).path)}';
  }

  String _idPrefix(String contentId) =>
      '$_prefix${contentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_';

  /// FNV-1a 32-bit — deterministic across launches (unlike String.hashCode).
  String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Returns the fully-downloaded cached file, or null if not cached.
  Future<File?> getCachedFile(String contentId, String url) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${_key(contentId, url)}');
      if (await file.exists() && await file.length() > 0) {
        // Mark as recently used for LRU eviction.
        await file.setLastModified(DateTime.now());
        return file;
      }
    } catch (e) {
      Logger.w('VideoCache: lookup failed: $e');
    }
    return null;
  }

  /// Starts a background download into the cache (no-op if already cached or
  /// already downloading). Never throws.
  Future<void> cacheInBackground(String contentId, String url) async {
    try {
      final dir = await _cacheDir();
      final key = _key(contentId, url);
      final finalFile = File('${dir.path}/$key');
      if (_inFlight.containsKey(key) || await finalFile.exists()) return;

      final partFile = File('${dir.path}/$key$_partSuffix');
      final cancel = CancelToken();
      _inFlight[key] = cancel;

      try {
        Logger.i('VideoCache: caching $contentId');
        final response = await _dio.download(
          url,
          partFile.path,
          cancelToken: cancel,
          deleteOnError: true,
        );

        // Verify we got the whole file before promoting it.
        final expected = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        );
        final actual = await partFile.length();
        if (response.statusCode != 200 ||
            actual == 0 ||
            (expected != null && expected > 0 && expected != actual)) {
          throw Exception('incomplete download ($actual/$expected)');
        }
        if (actual > maxCacheBytes) {
          throw Exception('video larger than cache limit');
        }

        // Remove stale versions of this same content, then promote atomically.
        await _deleteMatching((name) =>
            name.startsWith(_idPrefix(contentId)) && name != key);
        await partFile.rename(finalFile.path);
        Logger.i('VideoCache: cached $contentId ($actual bytes)');
        await _evictIfNeeded();
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) {
          Logger.i('VideoCache: download cancelled for $contentId');
        } else {
          Logger.w('VideoCache: caching failed for $contentId: $e');
        }
        if (await partFile.exists()) {
          try {
            await partFile.delete();
          } catch (_) {}
        }
      } finally {
        _inFlight.remove(key);
      }
    } catch (e) {
      Logger.w('VideoCache: cacheInBackground error: $e');
    }
  }

  /// Delete one video's cache (e.g. file failed to play / is corrupt).
  Future<void> remove(String contentId) async {
    await _deleteMatching((name) => name.startsWith(_idPrefix(contentId)));
  }

  /// Cancel downloads and delete every cached video. Call on logout.
  Future<void> clearAll() async {
    for (final token in _inFlight.values) {
      token.cancel('clearAll');
    }
    _inFlight.clear();
    await _deleteMatching((name) => name.startsWith(_prefix));
  }

  Future<void> _deleteMatching(bool Function(String name) test) async {
    try {
      final dir = await _cacheDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (test(name)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      Logger.w('VideoCache: delete failed: $e');
    }
  }

  /// Evict least-recently-played videos until under [maxCacheBytes].
  Future<void> _evictIfNeeded() async {
    try {
      final dir = await _cacheDir();
      final files = <File>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith(_partSuffix)) {
          files.add(entity);
          total += await entity.length();
        }
      }
      if (total <= maxCacheBytes) return;

      final stats = <File, DateTime>{};
      for (final f in files) {
        stats[f] = (await f.stat()).modified;
      }
      files.sort((a, b) => stats[a]!.compareTo(stats[b]!)); // oldest first
      for (final f in files) {
        if (total <= maxCacheBytes) break;
        final size = await f.length();
        try {
          await f.delete();
          total -= size;
        } catch (_) {}
      }
    } catch (e) {
      Logger.w('VideoCache: eviction failed: $e');
    }
  }
}

