import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/models/models.dart';
import '../../../ui/ui.dart';

/// What happened when we asked for the microphone and camera.
enum CallPermissionResult {
  /// Everything the call needs was granted.
  granted,

  /// The user said no this time.
  denied,

  /// The user said no permanently — only Settings can undo it.
  permanentlyDenied,
}

/// Microphone and camera access for calls, asked for with a rationale.
///
/// The platform prompt is one line the user cannot argue with, so we explain
/// *why* first, in our own words, and only then trigger it. A user who declines
/// our sheet never sees the OS prompt at all, which keeps the "don't ask again"
/// budget intact for people who actually want the feature.
abstract final class CallPermissions {
  /// Asks for everything a [kind] call needs.
  ///
  /// Shows the rationale sheet, then requests. On a permanent denial it offers
  /// to open the app's settings page.
  static Future<CallPermissionResult> request(
    BuildContext context, {
    required CallKind kind,
    required bool outgoing,
  }) async {
    // Browsers gate `getUserMedia` themselves; permission_handler has no
    // meaningful web implementation, so let the media request do the asking.
    if (kIsWeb) return CallPermissionResult.granted;

    final needsCamera = kind == CallKind.video;
    if (await _alreadyGranted(needsCamera: needsCamera)) {
      return CallPermissionResult.granted;
    }
    if (!context.mounted) return CallPermissionResult.denied;

    final proceed = await KConfirmDialog.show(
      context,
      title: needsCamera ? 'Camera and microphone' : 'Microphone access',
      message: outgoing
          ? (needsCamera
              ? 'KLECT needs your camera and microphone to place a video call. '
                  'Nothing is recorded — the stream goes straight to the '
                  'person you are calling.'
              : 'KLECT needs your microphone to place a call. Nothing is '
                  'recorded — the audio goes straight to the person you are '
                  'calling.')
          : (needsCamera
              ? 'To answer with video, KLECT needs your camera and '
                  'microphone. Nothing is recorded.'
              : 'To answer, KLECT needs your microphone. Nothing is '
                  'recorded.'),
      confirmLabel: 'Continue',
      cancelLabel: 'Not now',
    );
    if (!proceed) return CallPermissionResult.denied;

    final requested = <Permission>[
      Permission.microphone,
      if (needsCamera) Permission.camera,
    ];
    final statuses = await requested.request();

    final permanentlyDenied = statuses.values.any(
      (status) => status.isPermanentlyDenied || status.isRestricted,
    );
    final allGranted =
        statuses.values.every((status) => status.isGranted || status.isLimited);

    if (allGranted) return CallPermissionResult.granted;

    if (permanentlyDenied && context.mounted) {
      final open = await KConfirmDialog.show(
        context,
        title: 'Permission is off',
        message: needsCamera
            ? 'Camera or microphone access is turned off for KLECT. Turn it '
                'back on in Settings to make calls.'
            : 'Microphone access is turned off for KLECT. Turn it back on in '
                'Settings to make calls.',
        confirmLabel: 'Open settings',
      );
      if (open) await openAppSettings();
      return CallPermissionResult.permanentlyDenied;
    }

    return CallPermissionResult.denied;
  }

  static Future<bool> _alreadyGranted({required bool needsCamera}) async {
    if (!await Permission.microphone.isGranted) return false;
    if (needsCamera && !await Permission.camera.isGranted) return false;
    return true;
  }
}
