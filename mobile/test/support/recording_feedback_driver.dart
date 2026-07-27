import 'package:klect/core/feedback/interaction_feedback.dart';

/// One invocation of the platform-native tap boundary.
class RecordedTapFeedback {
  /// Creates a recorded call.
  const RecordedTapFeedback({required this.sound, required this.haptic});

  /// Whether the Android system click was requested.
  final bool sound;

  /// Whether the light selection haptic was requested.
  final bool haptic;
}

/// Records effects without touching platform channels.
class RecordingFeedbackDriver implements InteractionFeedbackDriver {
  /// Every accepted tap in call order.
  final List<RecordedTapFeedback> taps = <RecordedTapFeedback>[];

  @override
  Future<void> tap({required bool sound, required bool haptic}) async {
    taps.add(RecordedTapFeedback(sound: sound, haptic: haptic));
  }
}
