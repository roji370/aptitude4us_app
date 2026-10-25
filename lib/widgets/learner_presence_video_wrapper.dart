import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

import '../services/learner_presence_service.dart';
import '../utils/logger.dart';
import 'learner_presence_consent_dialog.dart';
import 'learner_presence_overlay.dart';

/// Drop-in wrapper that adds the learner-presence (front-camera self-preview)
/// overlay above any video [child], **and enforces** that the camera is
/// actually live before the student can watch the lecture.
///
/// Enforcement model
/// ─────────────────
/// * The consent dialog has only an "Enable Camera" CTA — there is no
///   "Not now" path. Tap-outside and back-gesture are both suppressed.
/// * The video is rendered under a full-screen blocking veil whenever the
///   camera is not live (consent never granted, OS permission denied,
///   camera errored, controller initialising, …). The veil intercepts taps
///   so the underlying play button can't be triggered.
/// * The only graceful escape hatch is [LearnerPresenceState.unsupported]
///   (device has no front camera at all) — we don't punish students for
///   hardware they can't change.
/// * The camera-ready *grant* is persisted via [LearnerPresenceConsentStore].
///   Decline / dismiss is **never** persisted, so any future open of a
///   lecture re-prompts.
class LearnerPresenceVideoWrapper extends StatefulWidget {
  const LearnerPresenceVideoWrapper({
    super.key,
    required this.child,
    required this.contentKey,
  });

  /// The actual video player widget (rendered full-size under the veil).
  final Widget child;

  /// Stable identifier for the current lecture. Used to reset wrapper state
  /// when the user navigates between lectures within the same screen.
  final String contentKey;

  @override
  State<LearnerPresenceVideoWrapper> createState() =>
      _LearnerPresenceVideoWrapperState();
}

class _LearnerPresenceVideoWrapperState
    extends State<LearnerPresenceVideoWrapper> {
  late final LearnerPresenceController _controller;
  OverlayEntry? _overlayEntry;

  bool _bootstrapped = false;
  bool _consentGranted = false;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = LearnerPresenceController();
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didUpdateWidget(covariant LearnerPresenceVideoWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey != widget.contentKey && _bootstrapped) {
      _restartCamera();
    }
  }

  Future<void> _restartCamera() async {
    await _controller.stop();
    if (!mounted) return;
    if (_consentGranted) {
      await _controller.start();
    }
  }

  @override
  void deactivate() {
    // Stop camera and remove overlay when navigating away.
    // Must happen here (not dispose) because Overlay.of(context)
    // may not be available in dispose().
    _removeOverlay();
    _controller.stop();
    super.deactivate();
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final s = _controller.state;
    final shouldShow = s != LearnerPresenceState.idle &&
        s != LearnerPresenceState.unsupported;
    if (shouldShow && _overlayEntry == null) {
      _insertOverlay();
    } else if (!shouldShow && _overlayEntry != null) {
      _removeOverlay();
    }
    if (mounted) setState(() {});
  }

  // ─── Bootstrap & consent ─────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final stored = await LearnerPresenceConsentStore.read();
    if (!mounted) return;

    _bootstrapped = true;
    _consentGranted = stored == LearnerPresenceConsent.granted;

    if (_consentGranted) {
      await _controller.start();
    } else {
      // Either the user has never seen the dialog, or they previously chose
      // "decline" under an older build. Either way, we re-prompt now — the
      // camera is required.
      await _promptConsent();
    }
  }

  Future<void> _promptConsent() async {
    if (!mounted || _dialogVisible) return;
    _dialogVisible = true;
    try {
      final accepted = await LearnerPresenceConsentDialog.show(context);
      if (!mounted) return;
      if (accepted) {
        await LearnerPresenceConsentStore.write(
          LearnerPresenceConsent.granted,
        );
        setState(() => _consentGranted = true);
        await _controller.start();
      } else {
        // The only way to land here is if the host route was popped while
        // the dialog was up. We do nothing — the wrapper is being torn down
        // anyway and the veil will have kept the video covered.
        Logger.w('LearnerPresence: consent dialog dismissed without accept');
      }
    } finally {
      _dialogVisible = false;
    }
  }

  // ─── Veil interactions ───────────────────────────────────────────────────

  Future<void> _onEnablePressed() async {
    final s = _controller.state;
    if (s == LearnerPresenceState.permissionDenied) {
      // The veil's CTA in this state is "Open Settings" — match that
      // contract literally. Re-prompting the OS dialog from here is
      // unreliable on Android (a single "Don't allow" still reports as
      // plain `denied`, and `request()` may be silently suppressed),
      // so the only deterministic recovery path is the Settings deep
      // link. Permission re-check happens automatically on resume.
      await _controller.openSettings();
      return;
    }
    if (s == LearnerPresenceState.error) {
      await _controller.retry();
      return;
    }
    // Otherwise we haven't yet asked, or an old user dismissed before — show
    // the consent dialog (which itself triggers the OS prompt on accept).
    if (!_consentGranted) {
      await _promptConsent();
      return;
    }
    await _controller.start();
  }

  // ─── Overlay plumbing ────────────────────────────────────────────────────

  void _insertOverlay() {
    try {
      final overlay = Overlay.of(context, rootOverlay: true);
      _overlayEntry = OverlayEntry(
        builder: (_) => Material(
          type: MaterialType.transparency,
          child: LearnerPresenceOverlay(controller: _controller),
        ),
      );
      overlay.insert(_overlayEntry!);
    } catch (e) {
      Logger.w('LearnerPresence: could not insert overlay entry: $e');
      _overlayEntry = null;
    }
  }

  void _removeOverlay() {
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  /// The video is allowed to be visible/interactive only when the feature is
  /// either fully running or genuinely cannot run on this hardware.
  bool get _videoUnblocked {
    if (!_bootstrapped) return false;
    final s = _controller.state;
    return s == LearnerPresenceState.ready ||
        s == LearnerPresenceState.paused ||
        s == LearnerPresenceState.unsupported;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_videoUnblocked)
          _Veil(
            state: _controller.state,
            bootstrapped: _bootstrapped,
            errorMessage: _controller.errorMessage,
            onEnable: _onEnablePressed,
          ),
      ],
    );
  }
}

/// Full-cover veil that hides and gates interaction with the underlying video
/// while the camera is not live. Renders different copy depending on the
/// controller's current state.
class _Veil extends StatelessWidget {
  const _Veil({
    required this.state,
    required this.bootstrapped,
    required this.errorMessage,
    required this.onEnable,
  });

  final LearnerPresenceState state;
  final bool bootstrapped;
  final String? errorMessage;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final copy = _resolveCopy();
    // We need the veil to swallow taps so the underlying play button can't
    // be hit, *but* the CTA button must still be tappable. AbsorbPointer
    // can't do both — `absorbing: true` short-circuits hit-testing for the
    // entire subtree, and a nested `absorbing: false` does not undo that
    // (an earlier version of this file relied on exactly that misconception,
    // which is why the "Open Settings" CTA looked dead). A
    // `GestureDetector` with opaque hit-test behaviour absorbs the
    // background tap at this node while still allowing descendants to
    // receive their own gestures.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (copy.spinner)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            else
              Icon(copy.icon, color: Colors.white, size: 44),
            const SizedBox(height: 18),
            Text(
              copy.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              copy.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            if (copy.cta != null) ...[
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: onEnable,
                icon: const Icon(Icons.videocam_rounded, size: 18),
                label: Text(copy.cta!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _VeilCopy _resolveCopy() {
    if (!bootstrapped) {
      return const _VeilCopy(
        title: 'Preparing lecture…',
        body: '',
        spinner: true,
      );
    }
    switch (state) {
      case LearnerPresenceState.idle:
        return const _VeilCopy(
          icon: Icons.videocam_rounded,
          title: 'Camera required to watch',
          body: 'This lecture requires your front camera to be on while you '
              'watch. The preview stays on your device and is never recorded '
              'or uploaded.',
          cta: 'Enable Camera',
        );
      case LearnerPresenceState.requestingPermission:
      case LearnerPresenceState.initializing:
        return const _VeilCopy(
          title: 'Starting camera…',
          body: 'Please allow camera access in the system prompt.',
          spinner: true,
        );
      case LearnerPresenceState.permissionDenied:
        return const _VeilCopy(
          icon: Icons.videocam_off_rounded,
          title: 'Camera access blocked',
          body: 'Watching this lecture requires camera access. Please enable '
              'it in Settings to continue.',
          cta: 'Open Settings',
        );
      case LearnerPresenceState.error:
        return _VeilCopy(
          icon: Icons.error_outline_rounded,
          title: 'Camera could not start',
          body: errorMessage ??
              'Something went wrong while starting the camera. Please retry.',
          cta: 'Retry',
        );
      // The ready / paused / unsupported branches never render a veil — the
      // wrapper short-circuits before constructing one.
      case LearnerPresenceState.ready:
      case LearnerPresenceState.paused:
      case LearnerPresenceState.unsupported:
        return const _VeilCopy(title: '', body: '');
    }
  }
}

class _VeilCopy {
  const _VeilCopy({
    required this.title,
    required this.body,
    this.icon = Icons.videocam_rounded,
    this.cta,
    this.spinner = false,
  });
  final IconData icon;
  final String title;
  final String body;
  final String? cta;
  final bool spinner;
}
