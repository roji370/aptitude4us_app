import 'package:cloud_functions/cloud_functions.dart';
import '../models/content_model.dart';
import '../utils/logger.dart';

enum VideoUrlErrorType {
  noStoragePath,
  serverNoStoragePath,
  permissionDenied,
  unauthenticated,
  networkError,
  unknown,
}

class VideoUrlError {
  final VideoUrlErrorType type;
  final String message;

  VideoUrlError(this.type, this.message);

  /// Only fall back to legacy URL when the item has no storagePath.
  /// Never fall back on auth/permission/network errors.
  bool get shouldFallback =>
      type == VideoUrlErrorType.noStoragePath ||
      type == VideoUrlErrorType.serverNoStoragePath;

  @override
  String toString() => 'VideoUrlError($type): $message';
}

class VideoUrlService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  /// Returns a playable URL for the given video content.
  ///
  /// Flow:
  /// 1. If content has no storagePath → return legacy URL immediately.
  /// 2. Call getVideoUrl Cloud Function for a signed URL.
  /// 3. On function error:
  ///    - NOT_FOUND with 'no-storage-path' → fall back to legacy URL.
  ///    - PERMISSION_DENIED / UNAUTHENTICATED → throw (no fallback).
  ///    - Network error → throw (no fallback).
  static Future<String> getPlayableUrl({
    required ContentModel content,
    required String courseId,
    required String moduleId,
  }) async {
    // No storagePath → use legacy URL directly (supports old content)
    if (content.storagePath == null || content.storagePath!.isEmpty) {
      Logger.i('VideoUrlService: No storagePath, using legacy URL');
      final legacyUrl = content.originalUrl ?? content.content;
      if (legacyUrl.isEmpty) {
        throw VideoUrlError(
          VideoUrlErrorType.noStoragePath,
          'No video URL available',
        );
      }
      return legacyUrl;
    }

    try {
      Logger.i('VideoUrlService: Requesting signed URL for ${content.id}');
      final callable = _functions.httpsCallable('getVideoUrl');
      final result = await callable.call<Map<String, dynamic>>({
        'courseId': courseId,
        'moduleId': moduleId,
        'contentId': content.id,
      });

      final signedUrl = result.data['url'] as String?;
      if (signedUrl == null || signedUrl.isEmpty) {
        throw VideoUrlError(
          VideoUrlErrorType.unknown,
          'Function returned empty URL',
        );
      }

      Logger.i('VideoUrlService: Got signed URL (expires in 4h)');
      return signedUrl;
    } on FirebaseFunctionsException catch (e) {
      Logger.e('VideoUrlService: Function error: ${e.code} ${e.message}');
      throw _classifyFunctionsError(e);
    } catch (e) {
      Logger.e('VideoUrlService: Unexpected error: $e');
      // Network errors and other unexpected failures — no fallback
      if (e is VideoUrlError) rethrow;
      throw VideoUrlError(VideoUrlErrorType.networkError, e.toString());
    }
  }

  static VideoUrlError _classifyFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return VideoUrlError(
          VideoUrlErrorType.unauthenticated,
          'You are not signed in. Please sign in and try again.',
        );
      case 'permission-denied':
        return VideoUrlError(
          VideoUrlErrorType.permissionDenied,
          'You do not have access to this video.',
        );
      case 'not-found':
        // The function returns NOT_FOUND with 'no-storage-path' detail
        // when storagePath is missing server-side. Safe to fall back.
        final msg = e.message ?? '';
        if (msg.contains('no-storage-path')) {
          return VideoUrlError(
            VideoUrlErrorType.serverNoStoragePath,
            'Video not yet migrated, using legacy URL',
          );
        }
        return VideoUrlError(VideoUrlErrorType.unknown, msg);
      default:
        return VideoUrlError(
          VideoUrlErrorType.unknown,
          e.message ?? 'Unknown error',
        );
    }
  }
}

