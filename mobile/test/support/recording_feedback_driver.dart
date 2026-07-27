import 'package:klect/core/feedback/interaction_feedback.dart';

/// Records effects without touching audio or haptic platform channels.
class RecordingFeedbackDriver implements InteractionFeedbackDriver {
  int preloadCalls = 0;
  int disposeCalls = 0;
  final List<InteractionFeedbackSound> sounds = <InteractionFeedbackSound>[];
  final List<InteractionFeedbackHaptic> haptics = <InteractionFeedbackHaptic>[];

  @override
  Future<void> preload() async {
    preloadCalls++;
  }

  @override
  Future<void> play(InteractionFeedbackSound sound) async {
    sounds.add(sound);
  }

  @override
  Future<void> haptic(InteractionFeedbackHaptic haptic) async {
    haptics.add(haptic);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
