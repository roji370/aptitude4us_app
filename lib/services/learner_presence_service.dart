import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

/// Persisted consent decision for the learner-presence feature.
///
/// The decision is stored once and never asked again — the user can flip
/// it later through the inline UI (retry button on permission denial, or
/// the "Enable self-preview" chip shown when they previously declined).
enum LearnerPresenceConsent { unknown, granted, declined }

/// Thin persistence helper around [SharedPreferences] for the consent state.
class LearnerPresenceConsentStore {
  static const _key = 'learner_presence_consent_v1';

  static Future<LearnerPresenceConsent> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      switch (raw) {
        case 'granted':
          return LearnerPresenceConsent.granted;
        case 'declined':
          return LearnerPresenceConsent.declined;
        default:
          return LearnerPresenceConsent.unknown;
      }
    } catch (_) {
      return LearnerPresenceConsent.unknown;
    }
  }

  static Future<void> write(LearnerPresenceConsent value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        value == LearnerPresenceConsent.granted ? 'granted' : 'declined',
      );
    } catch (e) {
      Logger.w('LearnerPresence: could not persist consent: $e');
    }
  }
}

/// High-level state of the learner-presence feature.
///
/// Used by the UI layer to decide what to render (loading spinner,
/// permission denial fallback, error retry, or the live preview).
enum LearnerPresenceState {
  /// Feature has never been started in the current lifetime.
  idle,

  /// Camera permission is being requested from the OS.
  requestingPermission,

  /// User denied (or permanently denied) the camera permission.
  permissionDenied,

  /// Permission granted; the camera is being initialised.
  initializing,

  /// Live preview is running.
  ready,

  /// Camera has been temporarily paused (app backgrounded, screen lock,
  /// incoming call, audio session interruption …).
  paused,

  /// An unrecoverable error happened during initialise/recovery.
  error,

  /// The device exposes no usable front-facing camera.
  unsupported,
}

/// Production-grade controller that owns the front-camera lifecycle for the
/// "learner presence" overlay shown over a recorded lecture video.
///
/// Design notes
/// ────────────
/// * Singleton-per-screen: each lecture screen creates its own instance
///   in `initState` and disposes it in `dispose`. This guarantees that the
///   camera is released the moment the user leaves the screen.
/// * Observes `WidgetsBinding` lifecycle events so the camera is paused when
///   the app is backgrounded / screen-locked / interrupted, and re-initialised
///   on resume. This prevents the well-known "black preview" bug on Android
///   and crashes from holding a stale session on iOS.
/// * Uses [ResolutionPreset.low] to minimise battery / memory footprint.
/// * Audio capture is disabled (we never record) — important for both
///   permissions UX and not stealing the audio session from the video player.
/// * Front-camera mirroring is handled at the widget layer (Transform).
class LearnerPresenceController extends ChangeNotifier
    with WidgetsBindingObserver {
  LearnerPresenceController();

  // ─── Public state ────────────────────────────────────────────────────────
  LearnerPresenceState _state = LearnerPresenceState.idle;
  LearnerPresenceState get state => _state;

  CameraController? _cameraController;
  CameraController? get cameraController => _cameraController;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _disposed = false;

  /// Last known front-camera description, cached so that we don't re-query
  /// `availableCameras()` on every recovery attempt.
  CameraDescription? _frontCamera;

  /// Guards against concurrent (re-)initialisation.
  Future<void>? _initializingFuture;

  /// Monotonically increasing token used to cancel an in-flight
  /// [_initializeCamera] when the app is backgrounded or the controller is
  /// stopped/disposed. The token captured at the start of an init pass must
  /// still match [_initGeneration] when init finishes, otherwise the
  /// freshly-built camera is disposed instead of being adopted.
  int _initGeneration = 0;

  /// Hard cap on `CameraController.initialize()` so a hung native call
  /// surfaces as an error in the UI instead of spinning forever.
  static const Duration _initTimeout = Duration(seconds: 12);

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Starts the full flow: permission → camera init.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops while a
  /// previous start is still in flight or the camera is already running.
  Future<void> start() async {
    if (_disposed) return;
    if (_state == LearnerPresenceState.ready ||
        _state == LearnerPresenceState.initializing ||
        _state == LearnerPresenceState.requestingPermission) {
      return;
    }

    WidgetsBinding.instance.addObserver(this);

    _setState(LearnerPresenceState.requestingPermission);
    final granted = await _ensureCameraPermission();
    if (_disposed) return;

    if (!granted) {
      _setState(LearnerPresenceState.permissionDenied);
      return;
    }

    await _initializeCamera();
  }

  /// Re-runs permission + init. Used by the "Retry" button in the UI.
  Future<void> retry() async {
    _errorMessage = null;
    _setState(LearnerPresenceState.idle);
    await start();
  }

  /// Opens the OS settings page so the user can grant a permanently-denied
  /// camera permission. Returns immediately; the caller should re-check on
  /// resume via the lifecycle observer.
  Future<void> openSettings() => openAppSettings();

  /// Stops the camera and releases all native resources. Idempotent.
  Future<void> stop() async {
    // Cancel any in-flight init so it doesn't resurrect the camera right
    // after we tear it down. We then await the init future itself — once
    // it observes the bumped generation it will bail quickly. This is what
    // guarantees a clean `stop() → start()` sequence: by the time stop()
    // resolves, [_initializingFuture] is null and a fresh init is allowed.
    _initGeneration++;
    final pending = _initializingFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {/* errors are already logged in _initializeCamera */}
    }
    await _disposeCamera();
    if (!_disposed) {
      _setState(LearnerPresenceState.idle);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _initGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    // Fire and forget — the controller object is going away anyway.
    _disposeCamera();
    super.dispose();
  }

  // ─── WidgetsBindingObserver ──────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Critical: the camera plugin documentation explicitly requires apps to
    // dispose the controller on `inactive`/`paused` and re-create it on
    // `resumed`. Skipping this leads to black previews on Android and to
    // `CameraAccessException` on iOS when another app grabs the session.
    //
    // We must also react when an init pass is in flight (state ==
    // initializing / requestingPermission) so that the freshly-built camera
    // is never adopted while the app is hidden — the generation token below
    // takes care of that.
    switch (_state) {
      case LearnerPresenceState.idle:
      case LearnerPresenceState.unsupported:
        return; // feature inactive — nothing to do.
      default:
        break;
    }

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _handleAppBackgrounded();
        break;
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.detached:
        _initGeneration++;
        _disposeCamera();
        break;
    }
  }

  Future<void> _handleAppBackgrounded() async {
    if (_state == LearnerPresenceState.paused) return;
    Logger.i('LearnerPresence: backgrounded, releasing camera');
    // Invalidate any in-flight init so it doesn't adopt a controller after
    // the app went to background.
    _initGeneration++;
    await _disposeCamera(keepState: true);
    if (!_disposed) {
      _setState(LearnerPresenceState.paused);
    }
  }

  Future<void> _handleAppResumed() async {
    // Recover from any state that left the camera off: paused (normal
    // backgrounding), error (interruption), or permissionDenied (user may
    // have just granted access in OS Settings).
    if (_state != LearnerPresenceState.paused &&
        _state != LearnerPresenceState.error &&
        _state != LearnerPresenceState.permissionDenied) {
      return;
    }
    Logger.i('LearnerPresence: resumed, recovering camera');

    // Permission might have been revoked (or granted) while in background.
    //
    // Android quirk: when the user enables the permission in Settings and
    // the activity resumes, `Permission.camera.status` can briefly still
    // report `denied` for a few hundred ms before the platform propagates
    // the new grant. Reading it once would leave us stuck in
    // `permissionDenied` and force the user to tap Retry an extra time.
    // Poll a handful of times with a short backoff so the resume path
    // self-heals without any user intervention.
    final granted = await _waitForPermissionGrant();
    if (_disposed) return;
    if (!granted) {
      _setState(LearnerPresenceState.permissionDenied);
      return;
    }
    await _initializeCamera();
  }

  /// Polls [Permission.camera.status] briefly to absorb the Android
  /// propagation lag described in [_handleAppResumed]. Returns as soon as
  /// the permission flips to granted, or false after the budget elapses.
  Future<bool> _waitForPermissionGrant() async {
    const attempts = <Duration>[
      Duration.zero,
      Duration(milliseconds: 150),
      Duration(milliseconds: 300),
      Duration(milliseconds: 500),
    ];
    for (final delay in attempts) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (_disposed) return false;
      final status = await Permission.camera.status;
      if (status.isGranted) return true;
      // If the OS has already promoted to permanently denied we won't
      // recover by waiting — bail out early.
      if (status.isPermanentlyDenied || status.isRestricted) return false;
    }
    return false;
  }

  // ─── Internal helpers ────────────────────────────────────────────────────

  Future<bool> _ensureCameraPermission() async {
    try {
      var status = await Permission.camera.status;
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) return false;
      status = await Permission.camera.request();
      return status.isGranted;
    } catch (e) {
      Logger.e('LearnerPresence: permission check failed: $e');
      return false;
    }
  }

  Future<void> _initializeCamera() async {
    // Serialise: only one native init at a time. If a previous pass is still
    // draining (e.g. after a background event bumped the generation and it's
    // about to bail) we wait for it to finish rather than coalescing onto a
    // stale future. Coalescing would leave the caller observing the previous
    // pass's "stale exit" with no actual camera initialised.
    while (_initializingFuture != null) {
      try {
        await _initializingFuture;
      } catch (_) {/* errors are already surfaced via state */}
      if (_disposed) return;
    }
    final completer = Completer<void>();
    _initializingFuture = completer.future;

    // Capture the generation at the start: any backgrounding / stop / dispose
    // event during init will bump [_initGeneration], so we can detect that
    // we're about to adopt a stale controller and dispose it instead.
    final gen = ++_initGeneration;
    bool isStale() => _disposed || gen != _initGeneration;

    CameraController? built;
    try {
      _setState(LearnerPresenceState.initializing);

      // Always tear down any prior controller before creating a new one.
      await _disposeCamera(keepState: true);
      if (isStale()) return;

      _frontCamera ??= await _resolveFrontCamera();
      if (isStale()) return;
      if (_frontCamera == null) {
        _setError('No front-facing camera available on this device.',
            stateOverride: LearnerPresenceState.unsupported);
        return;
      }

      // ResolutionPreset.low is intentional: the preview is tiny (~96 px
      // wide), so anything higher just wastes battery and memory bandwidth.
      // Target FPS is limited to 15 to optimize battery drain.
      built = CameraController(
        _frontCamera!,
        ResolutionPreset.low,
        enableAudio: false,
        fps: 15,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      // Add the listener *before* initialize() so we don't miss an early
      // error event emitted during initialisation itself.
      built.addListener(_onCameraValueChanged);

      await built.initialize().timeout(
        _initTimeout,
        onTimeout: () => throw CameraException(
          'initializeTimeout',
          'Camera did not initialise within ${_initTimeout.inSeconds}s.',
        ),
      );

      if (isStale()) {
        // App went background / user navigated away / controller disposed
        // while we were awaiting initialize(). Drop the freshly-built
        // controller on the floor instead of leaking it.
        await _safeDispose(built);
        built = null;
        return;
      }

      _cameraController = built;
      built = null; // ownership transferred
      _setState(LearnerPresenceState.ready);
      Logger.i('LearnerPresence: camera ready (${_frontCamera!.name})');
    } on CameraException catch (e) {
      Logger.e('LearnerPresence: CameraException ${e.code} ${e.description}');
      await _safeDispose(built);
      if (!isStale()) _setError(_friendlyCameraError(e));
    } catch (e) {
      Logger.e('LearnerPresence: unexpected init error: $e');
      await _safeDispose(built);
      if (!isStale()) {
        _setError('Camera could not be started. Please try again.');
      }
    } finally {
      _initializingFuture = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _safeDispose(CameraController? c) async {
    if (c == null) return;
    try {
      c.removeListener(_onCameraValueChanged);
      await c.dispose();
    } catch (e) {
      Logger.w('LearnerPresence: orphan dispose failed (non-fatal): $e');
    }
  }

  Future<CameraDescription?> _resolveFrontCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return null;
      for (final c in cameras) {
        if (c.lensDirection == CameraLensDirection.front) return c;
      }
      return null; // No front camera (e.g. some tablets).
    } catch (e) {
      Logger.e('LearnerPresence: availableCameras() failed: $e');
      return null;
    }
  }

  void _onCameraValueChanged() {
    final c = _cameraController;
    if (c == null) return;
    // The camera plugin surfaces fatal errors (session disconnect, app pushed
    // into the background by the OS, camera grabbed by another app, …) via
    // `value.errorDescription`. When that happens we transition to `error`
    // and rely on the resume handler / retry button to recover.
    if (c.value.hasError) {
      Logger.w('LearnerPresence: camera error event: ${c.value.errorDescription}');
      _setError(c.value.errorDescription ??
          'Camera was interrupted by another app.');
    }
  }

  Future<void> _disposeCamera({bool keepState = false}) async {
    final c = _cameraController;
    _cameraController = null;
    if (c != null) {
      try {
        c.removeListener(_onCameraValueChanged);
        await c.dispose();
      } catch (e) {
        Logger.w('LearnerPresence: dispose error (non-fatal): $e');
      }
    }
    if (!keepState && !_disposed) {
      notifyListeners();
    }
  }

  String _friendlyCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is blocked. Enable it in Settings to continue.';
      case 'AudioAccessDenied':
        return 'Audio access denied (audio is not required, please retry).';
      case 'cameraNotReadable':
      case 'cameraPermission':
        return 'Camera is currently in use by another app.';
      default:
        return e.description ?? 'Camera initialisation failed.';
    }
  }

  void _setError(String message,
      {LearnerPresenceState stateOverride = LearnerPresenceState.error}) {
    _errorMessage = message;
    _setState(stateOverride);
  }

  void _setState(LearnerPresenceState newState) {
    if (_disposed || _state == newState) return;
    _state = newState;
    if (kDebugMode) {
      Logger.d('LearnerPresence → $newState');
    }
    notifyListeners();
  }
}
