import 'package:video_player/video_player.dart';
import '../models/content_model.dart';
import 'logger.dart';

/// Manages content state to prevent unnecessary reloading when navigating
/// between different content types in a module
class ContentStateManager {
  static final ContentStateManager _instance = ContentStateManager._internal();
  factory ContentStateManager() => _instance;
  ContentStateManager._internal();

  // State for the current module
  String? _currentModuleId;
  final Map<String, ContentState> _contentStates = {};

  /// Initialize content state manager for a specific module
  void initForModule(String moduleId) {
    if (_currentModuleId != moduleId) {
      // Clear previous module's content states
      _clearAllContentStates();
      _currentModuleId = moduleId;
      Logger.i('🔄 ContentStateManager initialized for NEW module: $moduleId');
    } else {
      Logger.i(
        '✅ ContentStateManager already initialized for module: $moduleId',
      );
      Logger.d('DEBUG: Existing content states: ${_contentStates.length}');
    }
  }

  /// Get or create content state for a specific content item
  ContentState getContentState(ContentModel content) {
    final key = _generateContentKey(content);

    if (!_contentStates.containsKey(key)) {
      _contentStates[key] = ContentState(
        content: content,
        createdAt: DateTime.now(),
      );
      Logger.i('Created new content state for: ${content.title}');
    }

    return _contentStates[key]!;
  }

  /// Update video controller state
  void setVideoController(
    ContentModel content,
    VideoPlayerController controller,
  ) {
    final state = getContentState(content);
    state.videoController = controller;
    state.lastAccessed = DateTime.now();
    Logger.i('✅ Video controller stored for: ${content.title}');
    Logger.d(
      'DEBUG: Controller initialized: ${controller.value.isInitialized}',
    );
    Logger.d('DEBUG: Total content states: ${_contentStates.length}');
  }

  /// Get existing video controller if available
  VideoPlayerController? getVideoController(ContentModel content) {
    final key = _generateContentKey(content);
    final state = _contentStates[key];

    Logger.d('DEBUG: Looking for controller with key: $key');
    Logger.d('DEBUG: Available keys: ${_contentStates.keys.toList()}');
    Logger.d('DEBUG: State exists: ${state != null}');
    Logger.d('DEBUG: Controller exists: ${state?.videoController != null}');

    if (state?.videoController != null) {
      state!.lastAccessed = DateTime.now();
      Logger.d('DEBUG: Returning existing controller for: ${content.title}');
      return state.videoController;
    }

    Logger.d('DEBUG: No existing controller found for: ${content.title}');
    return null;
  }

  /// Update PDF file path
  void setPdfPath(ContentModel content, String pdfPath) {
    final state = getContentState(content);
    state.pdfPath = pdfPath;
    state.lastAccessed = DateTime.now();
    Logger.i('PDF path set for: ${content.title}');
  }

  /// Get existing PDF path if available
  String? getPdfPath(ContentModel content) {
    final state = _contentStates[_generateContentKey(content)];
    if (state?.pdfPath != null) {
      state!.lastAccessed = DateTime.now();
      return state.pdfPath;
    }
    return null;
  }

  /// Check if content is currently loading
  bool isContentLoading(ContentModel content, String loadingType) {
    final state = _contentStates[_generateContentKey(content)];
    return state?.loadingStates[loadingType] ?? false;
  }

  /// Set content loading state
  void setContentLoading(
    ContentModel content,
    String loadingType,
    bool isLoading,
  ) {
    final state = getContentState(content);
    state.loadingStates[loadingType] = isLoading;
    if (isLoading) {
      Logger.i('Started loading $loadingType for: ${content.title}');
    } else {
      Logger.i('Finished loading $loadingType for: ${content.title}');
    }
  }

  /// Clear states for content older than the specified duration
  void clearOldContentStates({Duration maxAge = const Duration(minutes: 30)}) {
    final cutoffTime = DateTime.now().subtract(maxAge);
    final keysToRemove = <String>[];

    for (final entry in _contentStates.entries) {
      if (entry.value.lastAccessed.isBefore(cutoffTime)) {
        keysToRemove.add(entry.key);
        entry.value.dispose();
      }
    }

    for (final key in keysToRemove) {
      _contentStates.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      Logger.i('Cleared ${keysToRemove.length} old content states');
    }
  }

  /// Clear all content states (called when leaving module or app)
  void _clearAllContentStates() {
    for (final state in _contentStates.values) {
      state.dispose();
    }
    _contentStates.clear();
    _currentModuleId = null;
    Logger.i('Cleared all content states');
  }

  /// Dispose manager and clean up resources
  void dispose() {
    _clearAllContentStates();
  }

  /// Generate unique key for content item
  String _generateContentKey(ContentModel content) {
    final key = '${content.id}_${content.contentType}';
    Logger.d('DEBUG: Generated key for ${content.title}: $key');
    return key;
  }
}

/// State container for individual content items
class ContentState {
  final ContentModel content;
  final DateTime createdAt;
  DateTime lastAccessed;

  // Content-specific state
  VideoPlayerController? videoController;
  String? pdfPath;
  final Map<String, bool> loadingStates = {};
  final Map<String, dynamic> additionalData = {};

  ContentState({required this.content, required this.createdAt})
    : lastAccessed = createdAt;

  /// Dispose of any resources held by this content state
  void dispose() {
    videoController?.dispose();
    videoController = null;
    additionalData.clear();
    loadingStates.clear();
  }

  /// Check if this content state is still valid
  bool get isValid {
    final age = DateTime.now().difference(createdAt);
    return age.inHours < 2; // Content states valid for 2 hours
  }
}
