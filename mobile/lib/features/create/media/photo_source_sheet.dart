import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// Where a photo came from.
enum PhotoSource {
  /// Shot right now with the camera.
  camera,

  /// Chosen from the device library, possibly several at once.
  library,
}

/// The one sheet that offers **camera capture and multi-select from the
/// library**, per `docs/CHECKLIST.md` §A.
///
/// Permission refusal is never a dead end: a denial explains what the
/// permission is for and, when the OS will no longer prompt, hands the user a
/// button straight into the app's settings page.
abstract final class PhotoSourceSheet {
  /// Presents the sheet and returns whatever the user picked.
  ///
  /// Returns an empty list when the user cancels or a permission is refused —
  /// callers never have to distinguish "cancelled" from "denied", because the
  /// explanation has already been shown.
  static Future<List<XFile>> pick(
    BuildContext context, {
    int? limit,
  }) async {
    final source = await KSheet.show<PhotoSource>(
      context: context,
      title: 'Add photos',
      builder: (sheetContext) => const _SourceOptions(),
    );
    if (source == null || !context.mounted) return const <XFile>[];
    return capture(context, source, limit: limit);
  }

  /// Runs one source directly, skipping the chooser.
  ///
  /// Used by the "replace cover" affordances, which only ever want a single
  /// photo and already know where it should come from.
  static Future<List<XFile>> capture(
    BuildContext context,
    PhotoSource source, {
    int? limit,
  }) async {
    final picker = ImagePicker();
    try {
      if (source == PhotoSource.camera) {
        if (!await _ensureCamera(context)) return const <XFile>[];
        final shot = await picker.pickImage(source: ImageSource.camera);
        return shot == null ? const <XFile>[] : <XFile>[shot];
      }
      // The Android photo picker and iOS `PHPicker` both run out-of-process and
      // need no permission at all, so we do not ask for one up front — we only
      // interpret a refusal if the platform actually raises one.
      final picked = await picker.pickMultiImage(
        limit: limit != null && limit > 1 ? limit : null,
      );
      return picked;
    } on PlatformException catch (error) {
      if (!context.mounted) return const <XFile>[];
      await _explainFailure(context, source, error);
      return const <XFile>[];
    }
  }

  /// True when the camera may be used; shows the explanation when it may not.
  static Future<bool> _ensureCamera(BuildContext context) async {
    if (kIsWeb) return true;
    if (!_isMobile) return true;

    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }
    if (status.isGranted || status.isLimited) return true;
    if (!context.mounted) return false;
    await _showDenied(
      context,
      title: 'Camera access is off',
      message: 'KLECT uses the camera only to photograph the things you are '
          'adding to a collection. Nothing is uploaded until you tap Save.',
      canOpenSettings: status.isPermanentlyDenied || status.isRestricted,
    );
    return false;
  }

  static Future<void> _explainFailure(
    BuildContext context,
    PhotoSource source,
    PlatformException error,
  ) async {
    final looksLikePermission = error.code.toLowerCase().contains('access') ||
        error.code.toLowerCase().contains('permission') ||
        (error.message ?? '').toLowerCase().contains('permission');

    if (!looksLikePermission) {
      KToast.error(context, error.message ?? 'That did not work. Try again.');
      return;
    }

    final permission =
        source == PhotoSource.camera ? Permission.camera : Permission.photos;
    final status = _isMobile && !kIsWeb
        ? await permission.status
        : PermissionStatus.denied;
    if (!context.mounted) return;

    await _showDenied(
      context,
      title: source == PhotoSource.camera
          ? 'Camera access is off'
          : 'Photo access is off',
      message: source == PhotoSource.camera
          ? 'KLECT uses the camera only to photograph the things you are '
              'adding to a collection.'
          : 'KLECT reads the photos you pick, and nothing else in your '
              'library. Grant access to choose the shots for this item.',
      canOpenSettings: status.isPermanentlyDenied || status.isRestricted,
    );
  }

  static Future<void> _showDenied(
    BuildContext context, {
    required String title,
    required String message,
    required bool canOpenSettings,
  }) =>
      KSheet.show<void>(
        context: context,
        title: title,
        builder: (sheetContext) => _PermissionExplainer(
          message: message,
          canOpenSettings: canOpenSettings,
        ),
      );

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether the camera option is worth offering on this platform.
  static bool get cameraAvailable => kIsWeb || _isMobile;
}

class _SourceOptions extends StatelessWidget {
  const _SourceOptions();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (PhotoSourceSheet.cameraAvailable)
            _SourceRow(
              icon: Icons.photo_camera_rounded,
              title: 'Take a photo',
              subtitle: 'Shoot it now, straight into this item.',
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
          _SourceRow(
            icon: Icons.photo_library_rounded,
            title: 'Choose from library',
            subtitle: 'Pick several at once — the first becomes the cover.',
            onTap: () => Navigator.of(context).pop(PhotoSource.library),
          ),
        ],
      );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: KPressable(
        onTap: onTap,
        semanticLabel: title,
        child: Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: colors.borderSubtle,
              width: Strokes.thin,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: Space.s10,
                height: Space.s10,
                decoration: BoxDecoration(
                  color: colors.accentSubtle,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(icon, size: Space.s5, color: colors.accentDefault),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: context.kt.bodyStrong),
                    const SizedBox(height: Space.sPx),
                    Text(
                      subtitle,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: Space.s5,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionExplainer extends StatelessWidget {
  const _PermissionExplainer({
    required this.message,
    required this.canOpenSettings,
  });

  final String message;
  final bool canOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          message,
          style: context.kt.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s5),
        if (canOpenSettings) ...<Widget>[
          KButton(
            label: 'Open settings',
            icon: Icons.settings_rounded,
            expand: true,
            onPressed: () async {
              final navigator = Navigator.of(context);
              await openAppSettings();
              if (navigator.canPop()) navigator.pop();
            },
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Turn the permission on, then come back — your draft is still here.',
            style: context.kt.caption.copyWith(color: colors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ] else
          KButton(
            label: 'Not now',
            variant: KButtonVariant.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }
}
