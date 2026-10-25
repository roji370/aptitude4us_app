import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xfini_academy/providers/session_provider.dart';
import 'package:xfini_academy/services/subscription_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake SubscriptionService — uses `implements` to avoid Firebase constructor.
// ─────────────────────────────────────────────────────────────────────────────

class FakeSubscriptionService implements SubscriptionService {
  final List<Completer<bool>> _completers = [];
  int checkCallCount = 0;
  String? lastCheckedUserId;
  bool? localValidityOverride;

  /// Returns the most recent pending completer.
  Completer<bool> get pendingCheck {
    assert(_completers.isNotEmpty, 'No pending check');
    return _completers.last;
  }

  /// Returns all pending completers (for multi-check scenarios).
  List<Completer<bool>> get allPendingChecks => List.unmodifiable(_completers);

  @override
  Future<bool> checkUserActiveSubscription(
    String userId, {
    bool forceRefresh = false,
  }) async {
    checkCallCount++;
    lastCheckedUserId = userId;
    final c = Completer<bool>();
    _completers.add(c);
    return c.future;
  }

  @override
  bool? isSubscriptionLocallyValid(String userId) => localValidityOverride;

  @override
  Future<List<Map<String, dynamic>>> getUserSubscriptions(String userId,
          {bool forceRefresh = false}) async =>
      [];

  @override
  Future<bool> hasAccessToCourse(String userId, String courseId,
          {bool forceRefresh = false}) async =>
      false;

  @override
  DateTime? getActiveSubscriptionEndDate(String userId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Helper: create a provider pre-initialized for a user so standalone
/// checkSubscription tests don't hit the _userId == null early return.
Future<SessionProvider> _makeProvider(FakeSubscriptionService svc, String userId) async {
  final p = SessionProvider(subscriptionService: svc);
  // Set local validity to true so initialize completes via the fast path.
  svc.localValidityOverride = true;
  await p.initialize(userId);
  // initialize's fast path fires a fire-and-forget checkSubscription.
  // Give it a tick to start, then complete it so it's not in flight during the test.
  await Future.delayed(Duration.zero);
  if (svc._completers.isNotEmpty && !svc._completers.last.isCompleted) {
    svc._completers.last.complete(true);
  }
  await Future.delayed(Duration.zero);
  // Reset the fake state so test starts clean
  svc.checkCallCount = 0;
  svc.lastCheckedUserId = null;
  svc.localValidityOverride = null;
  svc._completers.clear();
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSubscriptionService fakeService;

  setUp(() {
    fakeService = FakeSubscriptionService();
  });

  group('Dedup — same user', () {
    test('concurrent callers share one network call', () async {
      final provider = await _makeProvider(fakeService, 'user_a');

      final f1 = provider.checkSubscription(forceRefresh: true);
      await Future.delayed(Duration.zero);
      final f2 = provider.checkSubscription(forceRefresh: true);

      expect(fakeService.checkCallCount, 1);

      fakeService.pendingCheck.complete(true);
      await f1;
      await f2;

      expect(fakeService.checkCallCount, 1);
      expect(provider.hasActiveSubscription, true);
      expect(provider.hasCheckedOnce, true);

      provider.dispose();
    });

    test('forced follow-up fires after non-forced check', () async {
      final provider = await _makeProvider(fakeService, 'user_a');

      unawaited(provider.checkSubscription(forceRefresh: false));
      await Future.delayed(Duration.zero);
      expect(fakeService.checkCallCount, 1);

      unawaited(provider.checkSubscription(forceRefresh: true));

      fakeService.pendingCheck.complete(true);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(fakeService.checkCallCount, 2);

      fakeService.pendingCheck.complete(false);
      await Future.delayed(Duration.zero);

      expect(provider.hasActiveSubscription, false);

      provider.dispose();
    });
  });

  group('Dedup — different users', () {
    test('re-login cancels old user check via epoch', () async {
      fakeService.localValidityOverride = null;

      final provider = SessionProvider(subscriptionService: fakeService);

      unawaited(provider.initialize('user_a'));
      await Future.delayed(Duration.zero);
      expect(fakeService.lastCheckedUserId, 'user_a');
      expect(provider.userId, 'user_a');

      fakeService.localValidityOverride = true;
      await provider.initialize('user_b');

      fakeService.allPendingChecks.first.complete(false);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.hasActiveSubscription, true);
      expect(provider.userId, 'user_b');

      provider.dispose();
    });
  });

  group('clear() mid-flight', () {
    test('does not leak state into next session', () async {
      final provider = await _makeProvider(fakeService, 'user_a');

      unawaited(provider.checkSubscription(forceRefresh: true));
      await Future.delayed(Duration.zero);
      expect(fakeService.checkCallCount, 1);

      final epochBefore = provider.sessionEpoch;

      provider.clear();

      expect(provider.sessionEpoch, epochBefore + 1);
      expect(provider.hasCheckedOnce, false);
      expect(provider.hasActiveSubscription, true);
      expect(provider.hasInFlightCheck, false);

      fakeService.pendingCheck.complete(false);
      await Future.delayed(Duration.zero);

      expect(provider.hasActiveSubscription, true);
      expect(provider.hasCheckedOnce, false);

      provider.dispose();
    });

    test('does not hang awaiters — joiners released, originator finishes after service call', () async {
      final provider = await _makeProvider(fakeService, 'user_a');

      // Start a check (this is the originator)
      final checkFuture = provider.checkSubscription(forceRefresh: true);
      await Future.delayed(Duration.zero);

      // Start a second check (this is a joiner)
      final joinerFuture = provider.checkSubscription(forceRefresh: true);

      // clear() releases the joiner by completing _checkCompleter
      provider.clear();

      // Joiner should complete immediately
      await joinerFuture.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('joiner hung after clear()'),
      );

      // Originator is still blocked on the service call — complete it
      fakeService.pendingCheck.complete(false);
      await checkFuture.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('originator hung after service completed'),
      );

      // The false result should NOT have been applied (epoch changed)
      expect(provider.hasActiveSubscription, true); // still optimistic default from clear()

      provider.dispose();
    });
  });

  group('Timeout and error handling', () {
    test('error in check preserves last known subscription state', () async {
      final provider = await _makeProvider(fakeService, 'user_a');

      unawaited(provider.checkSubscription(forceRefresh: true));
      await Future.delayed(Duration.zero);
      fakeService.pendingCheck.complete(true);
      await Future.delayed(Duration.zero);
      expect(provider.hasActiveSubscription, true);

      unawaited(provider.checkSubscription(forceRefresh: true));
      await Future.delayed(Duration.zero);
      fakeService.pendingCheck.completeError(Exception('network error'));
      await Future.delayed(Duration.zero);

      expect(provider.hasActiveSubscription, true);
      expect(provider.hasCheckedOnce, true);

      provider.dispose();
    });
  });

  group('initialize()', () {
    test('fast path with valid local cache does not block', () async {
      fakeService.localValidityOverride = true;
      final provider = SessionProvider(subscriptionService: fakeService);

      await provider.initialize('user_a');

      expect(provider.hasActiveSubscription, true);
      expect(provider.hasCheckedOnce, true);
      expect(provider.dataGeneration, 1);

      provider.dispose();
    });

    test('bumps epoch on re-login', () async {
      fakeService.localValidityOverride = true;
      final provider = SessionProvider(subscriptionService: fakeService);

      await provider.initialize('user_a');
      final epochAfterA = provider.sessionEpoch;

      await provider.initialize('user_b');
      expect(provider.sessionEpoch, greaterThan(epochAfterA));

      provider.dispose();
    });
  });

  group('refreshAll()', () {
    test('bumps dataGeneration', () async {
      final provider = await _makeProvider(fakeService, 'user_a');
      final genBefore = provider.dataGeneration;

      unawaited(provider.refreshAll());
      await Future.delayed(Duration.zero);
      fakeService.pendingCheck.complete(true);
      await Future.delayed(Duration.zero);

      expect(provider.dataGeneration, genBefore + 1);

      provider.dispose();
    });

    test('does not bump generation if signed out mid-refresh', () async {
      final provider = await _makeProvider(fakeService, 'user_a');

      unawaited(provider.refreshAll());
      await Future.delayed(Duration.zero);

      provider.clear();
      expect(provider.dataGeneration, 0);

      fakeService.pendingCheck.complete(true);
      await Future.delayed(Duration.zero);

      expect(provider.dataGeneration, 0);

      provider.dispose();
    });
  });
}
