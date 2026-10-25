import 'dart:async';
import 'package:flutter/widgets.dart';
import '../services/content_update_service.dart';
import '../services/subscription_service.dart';
import '../utils/logger.dart';

/// Centralised subscription and session-freshness state.
///
/// Lives in the provider tree; screens read it via `context.select` and never
/// call [SubscriptionService] directly.
///
/// Thread-safety invariants:
/// - Every async method captures [_sessionEpoch] at entry and discards its
///   result if the epoch changes (sign-out / re-login happened mid-flight).
/// - [checkSubscription] uses a [Completer]-based dedup so concurrent callers
///   for the same user share one network call.
/// - Callers for a *different* user wait in a `while` loop until the current
///   check finishes, then start their own.
class SessionProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// Injected via constructor so tests can supply a fake.
  final SubscriptionService _subscriptionService;

  SessionProvider({SubscriptionService? subscriptionService})
      : _subscriptionService = subscriptionService ?? SubscriptionService();

  // ── Subscription state ──
  bool _hasActiveSubscription = true; // optimistic default
  bool _hasCheckedOnce = false;
  String? _userId;

  // ── Deduplication ──
  Completer<void>? _checkCompleter;
  bool _inFlightIsForced = false;
  bool _needsForcedFollowUp = false;
  String? _inFlightUserId;

  // ── Session epoch — bumped by clear() and initialize().
  //    Every async exit path compares its captured epoch to this.
  int _sessionEpoch = 0;

  // ── Data freshness ──
  int _dataGeneration = 0;
  DateTime? _backgroundedAt;
  static const Duration staleThreshold = Duration(minutes: 15);

  // ── Lifecycle guard ──
  bool _observerRegistered = false;

  // ── Public getters ──
  bool get hasActiveSubscription => _hasActiveSubscription;
  bool get hasCheckedOnce => _hasCheckedOnce;
  int get dataGeneration => _dataGeneration;
  String? get userId => _userId;

  // ── App lifecycle ──

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    final d = _backgroundedAt != null
        ? DateTime.now().difference(_backgroundedAt!)
        : null;
    _backgroundedAt = null;

    if (d != null && d > staleThreshold) {
      Logger.i('🔄 Session stale (${d.inMinutes}m) — full refresh');
      refreshAll();
    } else {
      checkSubscription(forceRefresh: true);
    }
  }

  // ── Initialization ──

  /// Called once from splash after auth resolves.
  /// Safe to call again on re-login (bumps epoch, cancels old state).
  Future<void> initialize(String userId) async {
    _cancelInFlight();
    _sessionEpoch++;
    _userId = userId;
    _hasCheckedOnce = false;
    _hasActiveSubscription = true; // optimistic

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    final epoch = _sessionEpoch;

    // Fast path: valid local cache → don't block splash
    final localValid = _subscriptionService.isSubscriptionLocallyValid(userId);
    if (localValid == true) {
      _hasActiveSubscription = true;
      _hasCheckedOnce = true;
      _dataGeneration++;
      notifyListeners();
      // Fire-and-forget server confirmation
      unawaited(
        checkSubscription(forceRefresh: true).catchError((e) {
          Logger.e('Background subscription confirm failed: $e');
        }),
      );
      return;
    }

    // No local cache — must wait, but short timeout
    try {
      await checkSubscription(forceRefresh: true)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      Logger.w('⏰ initialize() timed out — proceeding optimistically');
      if (_sessionEpoch == epoch) {
        _hasCheckedOnce = true;
      }
    }

    if (_sessionEpoch == epoch) {
      _dataGeneration++;
      notifyListeners();
    }
  }

  // ── Cancellation ──

  /// Cancel any in-flight work. Completes the completer so awaiters are
  /// released, then nulls everything. Safe because the epoch guard
  /// prevents stale writes from the orphaned async work.
  void _cancelInFlight() {
    if (_checkCompleter != null && !_checkCompleter!.isCompleted) {
      _checkCompleter!.complete();
    }
    _checkCompleter = null;
    _inFlightUserId = null;
    _inFlightIsForced = false;
    _needsForcedFollowUp = false;
  }

  // ── Subscription check with Completer-based dedup ──

  Future<void> checkSubscription({bool forceRefresh = false}) async {
    if (_userId == null) return;
    final checkingUserId = _userId!;
    final epoch = _sessionEpoch;

    // If a check is in flight for a DIFFERENT user, wait for it to finish.
    // Use a while-loop: multiple callers can fall through here concurrently,
    // and the first one to exit the loop starts the new check; the rest
    // see that new completer and join it below.
    while (_checkCompleter != null && _inFlightUserId != checkingUserId) {
      await _checkCompleter!.future;
      if (_sessionEpoch != epoch) return; // session changed, bail
    }

    // Same user in flight — join it
    if (_checkCompleter != null) {
      if (forceRefresh && !_inFlightIsForced) {
        _needsForcedFollowUp = true;
      }
      return _checkCompleter!.future;
    }

    // Start a new check
    final completer = Completer<void>();
    _checkCompleter = completer;
    _inFlightIsForced = forceRefresh;
    _inFlightUserId = checkingUserId;

    try {
      // Local-first: skip server if cached endDate is in the future
      if (!forceRefresh) {
        final localValid =
            _subscriptionService.isSubscriptionLocallyValid(checkingUserId);
        if (localValid == true) {
          if (_sessionEpoch == epoch) _hasCheckedOnce = true;
          return; // exits to finally
        }
      }

      final result = await _subscriptionService
          .checkUserActiveSubscription(checkingUserId,
              forceRefresh: forceRefresh)
          .timeout(const Duration(seconds: 8));

      // Only apply if session hasn't changed
      if (_sessionEpoch != epoch) return;

      final changed = result != _hasActiveSubscription;
      _hasActiveSubscription = result;
      _hasCheckedOnce = true;
      if (changed) notifyListeners();
    } on TimeoutException {
      if (_sessionEpoch == epoch) _hasCheckedOnce = true;
    } catch (e) {
      Logger.e('❌ Subscription check failed: $e');
      if (_sessionEpoch == epoch) _hasCheckedOnce = true;
    } finally {
      // Complete this check's completer
      if (!completer.isCompleted) completer.complete();

      // Only reset shared fields if this is still the active check.
      // If _cancelInFlight() ran (re-login), it already nulled everything
      // and bumped the epoch, so this guard prevents double-null.
      if (identical(_checkCompleter, completer)) {
        _checkCompleter = null;
        _inFlightIsForced = false;
        _inFlightUserId = null;

        if (_needsForcedFollowUp && _sessionEpoch == epoch) {
          _needsForcedFollowUp = false;
          unawaited(checkSubscription(forceRefresh: true));
        } else {
          _needsForcedFollowUp = false;
        }
      }
    }
  }

  // ── Full refresh (stale resume) ──

  /// Refreshes custom claims and subscription state. Bumps [dataGeneration]
  /// so screens know to reload their data.
  ///
  /// Claims refresh is the responsibility of the caller (usually
  /// `AuthService.refreshClaimsIfAllowed()`), which should be called
  /// before this method. This provider only owns subscription state.
  Future<void> refreshAll() async {
    if (_userId == null) return;
    final epoch = _sessionEpoch;

    await checkSubscription(forceRefresh: true);
    if (_sessionEpoch != epoch) return; // signed out mid-refresh

    _dataGeneration++;
    notifyListeners();
  }

  // ── Sign-out ──

  /// Call on sign-out. Completes any in-flight work, bumps epoch to
  /// invalidate all running async operations, resets to defaults.
  void clear() {
    _cancelInFlight();
    _sessionEpoch++; // invalidate all in-flight work
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    _hasActiveSubscription = true; // back to optimistic default
    _hasCheckedOnce = false;
    _userId = null;
    _dataGeneration = 0;
    _backgroundedAt = null;
    ContentUpdateService.clearBadgeNotifiers();
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelInFlight();
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    super.dispose();
  }

  // ── Test helpers (package-private) ──

  @visibleForTesting
  int get sessionEpoch => _sessionEpoch;

  @visibleForTesting
  bool get hasInFlightCheck => _checkCompleter != null;
}
