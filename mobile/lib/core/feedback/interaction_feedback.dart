import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';

/// The meaningful interactions allowed to produce premium feedback.
enum InteractionFeedbackAction {
  /// Follow or unfollow a collector.
  follow,

  /// Like or unlike a social entity.
  like,

  /// Save or unsave a social entity.
  save,

  /// Repost or undo a repost.
  repost,

  /// Open a card or image normally.
  imageOpen,

  /// Escalate an image into the immersive viewer.
  immersiveOpen,

  /// Open the long-press Peek surface.
  peekOpen,
}

/// Where a server-backed or local interaction currently stands.
enum InteractionFeedbackResult {
  /// The finger lifted and the optimistic visual state changed.
  intent,

  /// The server confirmed the final state, or a local gesture completed.
  confirmed,

  /// The intent is durable and will replay when connectivity returns.
  queued,

  /// The action was rejected and its optimistic state was rolled back.
  failed,
}

/// One typed, one-shot feedback event.
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

  /// Human-readable target supplied by the UI, used by follow toasts.
  final String? targetLabel;

  /// Creates another phase of this interaction.
  InteractionFeedbackEvent resolve(InteractionFeedbackResult nextResult) =>
      InteractionFeedbackEvent(
        id: id,
        action: action,
        result: nextResult,
        targetKey: targetKey,
        active: active,
        targetLabel: targetLabel,
      );
}

/// The small sound palette bundled with the app.
enum InteractionFeedbackSound { follow, like, save, repost, undo, focus, error }

/// Platform-adaptive tactile strengths.
enum InteractionFeedbackHaptic { selection, light, medium }

/// The effects, if any, attached to an event after preferences are applied.
@immutable
class InteractionFeedbackDirective {
  /// Creates a directive.
  const InteractionFeedbackDirective({this.sound, this.haptic});

  /// Sound to play.
  final InteractionFeedbackSound? sound;

  /// Haptic to perform.
  final InteractionFeedbackHaptic? haptic;

  /// Whether this directive is intentionally silent.
  bool get isEmpty => sound == null && haptic == null;
}

/// Pure policy used by production and tests.
InteractionFeedbackDirective feedbackDirectiveFor(
  InteractionFeedbackEvent event,
  AppSettings settings,
) {
  final soundEnabled = settings.interactionSoundsEnabled;
  final hapticsEnabled = settings.hapticsEnabled;

  switch (event.result) {
    case InteractionFeedbackResult.intent:
      return InteractionFeedbackDirective(
        haptic: hapticsEnabled
            ? switch (event.action) {
                InteractionFeedbackAction.save ||
                InteractionFeedbackAction.repost ||
                InteractionFeedbackAction.imageOpen =>
                  InteractionFeedbackHaptic.selection,
                InteractionFeedbackAction.follow ||
                InteractionFeedbackAction.like ||
                InteractionFeedbackAction.immersiveOpen =>
                  InteractionFeedbackHaptic.light,
                InteractionFeedbackAction.peekOpen =>
                  InteractionFeedbackHaptic.medium,
              }
            : null,
      );
    case InteractionFeedbackResult.confirmed:
      final localGesture =
          event.action == InteractionFeedbackAction.immersiveOpen ||
          event.action == InteractionFeedbackAction.peekOpen;
      return InteractionFeedbackDirective(
        sound: soundEnabled
            ? switch (event.action) {
                InteractionFeedbackAction.follow =>
                  event.active == false
                      ? InteractionFeedbackSound.undo
                      : InteractionFeedbackSound.follow,
                InteractionFeedbackAction.like =>
                  event.active == false
                      ? InteractionFeedbackSound.undo
                      : InteractionFeedbackSound.like,
                InteractionFeedbackAction.save =>
                  event.active == false
                      ? InteractionFeedbackSound.undo
                      : InteractionFeedbackSound.save,
                InteractionFeedbackAction.repost =>
                  event.active == false
                      ? InteractionFeedbackSound.undo
                      : InteractionFeedbackSound.repost,
                InteractionFeedbackAction.immersiveOpen ||
                InteractionFeedbackAction.peekOpen =>
                  InteractionFeedbackSound.focus,
                InteractionFeedbackAction.imageOpen => null,
              }
            : null,
        haptic: hapticsEnabled && localGesture
            ? event.action == InteractionFeedbackAction.peekOpen
                  ? InteractionFeedbackHaptic.medium
                  : InteractionFeedbackHaptic.light
            : null,
      );
    case InteractionFeedbackResult.queued:
      return const InteractionFeedbackDirective();
    case InteractionFeedbackResult.failed:
      return InteractionFeedbackDirective(
        sound: soundEnabled ? InteractionFeedbackSound.error : null,
        haptic: hapticsEnabled ? InteractionFeedbackHaptic.medium : null,
      );
  }
}

/// Injectable edge around audio and haptic platform channels.
abstract class InteractionFeedbackDriver {
  /// Preloads all bundled sounds.
  Future<void> preload();

  /// Plays one already-preloaded cue.
  Future<void> play(InteractionFeedbackSound sound);

  /// Performs one tactile response.
  Future<void> haptic(InteractionFeedbackHaptic haptic);

  /// Releases audio players.
  Future<void> dispose();
}

/// Platform implementation. Effects silently degrade when unsupported.
class PlatformInteractionFeedbackDriver implements InteractionFeedbackDriver {
  final Map<InteractionFeedbackSound, AudioPool> _pools =
      <InteractionFeedbackSound, AudioPool>{};
  Future<void>? _preloading;
  bool _disposed = false;

  bool get _supportsEffects =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationRingtone,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  @override
  Future<void> preload() {
    if (!_supportsEffects || _disposed) return Future<void>.value();
    return _preloading ??= _loadPools();
  }

  Future<void> _loadPools() async {
    for (final sound in InteractionFeedbackSound.values) {
      if (_disposed || _pools.containsKey(sound)) continue;
      try {
        final pool = await AudioPool.create(
          source: AssetSource('audio/${sound.name}.wav'),
          maxPlayers: 2,
          audioContext: _context,
        );
        if (_disposed) {
          await pool.dispose();
        } else {
          _pools[sound] = pool;
        }
      } on Object {
        // Feedback must never make the action itself fail.
      }
    }
  }

  @override
  Future<void> play(InteractionFeedbackSound sound) async {
    if (!_supportsEffects ||
        _disposed ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      await preload();
      await _pools[sound]?.start(volume: _volumeFor(sound));
    } on Object {
      // A missing audio service or interrupted session is a silent fallback.
    }
  }

  static double _volumeFor(InteractionFeedbackSound sound) => switch (sound) {
    InteractionFeedbackSound.error => 0.20,
    InteractionFeedbackSound.undo => 0.20,
    InteractionFeedbackSound.focus => 0.22,
    InteractionFeedbackSound.save => 0.22,
    InteractionFeedbackSound.like => 0.24,
    InteractionFeedbackSound.repost => 0.23,
    InteractionFeedbackSound.follow => 0.25,
  };

  @override
  Future<void> haptic(InteractionFeedbackHaptic haptic) async {
    if (!_supportsEffects ||
        _disposed ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      await switch (haptic) {
        InteractionFeedbackHaptic.selection => HapticFeedback.selectionClick(),
        InteractionFeedbackHaptic.light => HapticFeedback.lightImpact(),
        InteractionFeedbackHaptic.medium => HapticFeedback.mediumImpact(),
      };
    } on Object {
      // Some devices expose no vibrator; the interaction still succeeds.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(_pools.values.map((pool) => pool.dispose()));
    _pools.clear();
  }
}

/// Platform boundary, overridable with a recording driver in tests.
final interactionFeedbackDriverProvider = Provider<InteractionFeedbackDriver>((
  ref,
) {
  final driver = PlatformInteractionFeedbackDriver();
  ref.onDispose(() => unawaited(driver.dispose()));
  return driver;
}, name: 'interactionFeedbackDriver');

/// Coordinates ids, preference policy, cooldowns and one-shot event delivery.
class InteractionFeedbackController
    extends Notifier<InteractionFeedbackEvent?> {
  int _sequence = 0;
  final Map<String, DateTime> _lastEffectAt = <String, DateTime>{};

  @override
  InteractionFeedbackEvent? build() => null;

  /// Prewarms the audio pools without delaying first paint.
  Future<void> preload() =>
      ref.read(interactionFeedbackDriverProvider).preload();

  /// Starts an interaction and performs its immediate tactile response.
  String begin({
    required InteractionFeedbackAction action,
    required String targetKey,
    bool? active,
    String? targetLabel,
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
  }) => dispatch(
    InteractionFeedbackEvent(
      id: id,
      action: action,
      result: result,
      targetKey: targetKey,
      active: active,
      targetLabel: targetLabel,
    ),
  );

  /// Emits a completed local gesture, which gets sound and haptic together.
  Future<void> local({
    required InteractionFeedbackAction action,
    required String targetKey,
  }) => dispatch(
    InteractionFeedbackEvent(
      id:
          '${action.name}:$targetKey:'
          '${DateTime.now().microsecondsSinceEpoch}:${_sequence++}',
      action: action,
      result: InteractionFeedbackResult.confirmed,
      targetKey: targetKey,
    ),
  );

  /// Delivers [event] and applies the centralized effect policy.
  Future<void> dispatch(InteractionFeedbackEvent event) async {
    state = event;
    final directive = feedbackDirectiveFor(
      event,
      ref.read(appSettingsProvider),
    );
    if (directive.isEmpty) return;

    final effectKey =
        '${event.action.name}:${event.result.name}:'
        '${directive.sound?.name}:${directive.haptic?.name}';
    final now = DateTime.now();
    final previous = _lastEffectAt[effectKey];
    if (previous != null &&
        now.difference(previous) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastEffectAt[effectKey] = now;

    final driver = ref.read(interactionFeedbackDriverProvider);
    await Future.wait(<Future<void>>[
      if (directive.sound != null) driver.play(directive.sound!),
      if (directive.haptic != null) driver.haptic(directive.haptic!),
    ]);
  }
}

/// Latest one-shot event and the app-wide feedback orchestrator.
final interactionFeedbackProvider =
    NotifierProvider<InteractionFeedbackController, InteractionFeedbackEvent?>(
      InteractionFeedbackController.new,
      name: 'interactionFeedback',
    );
