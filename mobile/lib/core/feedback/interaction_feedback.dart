import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';

/// Social interactions whose server outcomes may create contextual notices.
enum InteractionFeedbackAction {
  /// Follow or unfollow a collector.
  follow,

  /// Like or unlike a social entity.
  like,

  /// Save or unsave a social entity.
  save,

  /// Repost or undo a repost.
  repost,
}

/// Where a server-backed interaction currently stands.
enum InteractionFeedbackResult {
  /// The tap was accepted and the optimistic visual state changed.
  intent,

  /// The server confirmed the final state.
  confirmed,

  /// The intent is durable and will replay when connectivity returns.
  queued,

  /// The action was rejected and its optimistic state was rolled back.
  failed,
}

/// One typed, one-shot social outcome event.
///
/// Tap feedback is intentionally independent from these events: the visible
/// control responds immediately, while server resolution stays silent.
@immutable
class InteractionFeedbackEvent {
  /// Creates an interaction event.
  const InteractionFeedbackEvent({
    required this.id,
    required this.action,
    required this.result,
    required this.targetKey,
    this.active,
    this.targetLabel,
    this.targetAvatarPath,
  });

  /// Unique id shared by the intent and its final resolution.
  final String id;

  /// The interaction being described.
  final InteractionFeedbackAction action;

  /// Current resolution.
  final InteractionFeedbackResult result;

  /// Stable entity/user key used to filter and deduplicate events.
  final String targetKey;

  /// Intended active state for toggle actions.
  final bool? active;

  /// Human-readable target supplied by the UI, used by follow notices.
  final String? targetLabel;

  /// Avatar storage path supplied by follow controls for contextual notices.
  final String? targetAvatarPath;

  /// Creates another phase of this interaction.
  InteractionFeedbackEvent resolve(InteractionFeedbackResult nextResult) =>
      InteractionFeedbackEvent(
        id: id,
        action: action,
        result: nextResult,
        targetKey: targetKey,
        active: active,
        targetLabel: targetLabel,
        targetAvatarPath: targetAvatarPath,
      );
}

/// Injectable boundary around the one platform-native tap effect.
abstract class InteractionFeedbackDriver {
  /// Performs the enabled portions of a deliberate in-app tap.
  Future<void> tap({required bool sound, required bool haptic});
}

/// Uses the device's own conventions instead of bundled audio.
///
/// Android provides its standard button click through [SystemSoundType.click].
/// iOS deliberately has no generic click sound, so it receives only the
/// selection haptic when enabled. All platform failures are non-blocking.
class PlatformInteractionFeedbackDriver implements InteractionFeedbackDriver {
  /// Creates the stateless platform driver.
  const PlatformInteractionFeedbackDriver();

  bool get _isForeground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.detached;
  }

  @override
  Future<void> tap({required bool sound, required bool haptic}) async {
    if (kIsWeb || !_isForeground) return;

    final platform = defaultTargetPlatform;
    final mobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (!mobile) return;

    await Future.wait<void>(<Future<void>>[
      if (sound && platform == TargetPlatform.android) _systemClick(),
      if (haptic) _selectionHaptic(),
    ]);
  }

  static Future<void> _systemClick() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } on Object {
      // Device touch sounds may be unavailable or disabled.
    }
  }

  static Future<void> _selectionHaptic() async {
    try {
      await HapticFeedback.selectionClick();
    } on Object {
      // Some devices expose no vibrator; the action still succeeds.
    }
  }
}

/// Platform boundary, overridable with a recording driver in tests.
final interactionFeedbackDriverProvider = Provider<InteractionFeedbackDriver>(
  (ref) => const PlatformInteractionFeedbackDriver(),
  name: 'interactionFeedbackDriver',
);

/// Coordinates the native tap effect and social outcome delivery.
class InteractionFeedbackController
    extends Notifier<InteractionFeedbackEvent?> {
  int _sequence = 0;

  @override
  InteractionFeedbackEvent? build() => null;

  /// Responds once to an accepted in-app control tap.
  Future<void> tap() {
    final settings = ref.read(appSettingsProvider);
    if (!settings.interactionSoundsEnabled && !settings.hapticsEnabled) {
      return Future<void>.value();
    }
    return ref
        .read(interactionFeedbackDriverProvider)
        .tap(
          sound: settings.interactionSoundsEnabled,
          haptic: settings.hapticsEnabled,
        );
  }

  /// Starts a social interaction without adding another platform effect.
  String begin({
    required InteractionFeedbackAction action,
    required String targetKey,
    bool? active,
    String? targetLabel,
    String? targetAvatarPath,
  }) {
    final id =
        '${action.name}:$targetKey:${DateTime.now().microsecondsSinceEpoch}:'
        '${_sequence++}';
    unawaited(
      dispatch(
        InteractionFeedbackEvent(
          id: id,
          action: action,
          result: InteractionFeedbackResult.intent,
          targetKey: targetKey,
          active: active,
          targetLabel: targetLabel,
          targetAvatarPath: targetAvatarPath,
        ),
      ),
    );
    return id;
  }

  /// Resolves a server-backed interaction with the same unique id.
  Future<void> resolve({
    required String id,
    required InteractionFeedbackAction action,
    required InteractionFeedbackResult result,
    required String targetKey,
    bool? active,
    String? targetLabel,
    String? targetAvatarPath,
  }) {
    return dispatch(
      InteractionFeedbackEvent(
        id: id,
        action: action,
        result: result,
        targetKey: targetKey,
        active: active,
        targetLabel: targetLabel,
        targetAvatarPath: targetAvatarPath,
      ),
    );
  }

  /// Delivers an outcome event. Resolution is intentionally effect-free.
  Future<void> dispatch(InteractionFeedbackEvent event) async {
    state = event;
  }
}

/// Fires the app's one native tap effect from a visible control.
///
/// Keeping this helper at the gesture boundary means Android system back,
/// route restoration and background synchronization never reach it.
void triggerInteractionTapFeedback(BuildContext context) {
  unawaited(
    ProviderScope.containerOf(
      context,
    ).read(interactionFeedbackProvider.notifier).tap(),
  );
}

/// Latest social outcome plus the app-wide tap feedback orchestrator.
final interactionFeedbackProvider =
    NotifierProvider<InteractionFeedbackController, InteractionFeedbackEvent?>(
      InteractionFeedbackController.new,
      name: 'interactionFeedback',
    );
