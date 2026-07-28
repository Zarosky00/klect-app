import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/updates/update_checker.dart';
import '../../core/updates/update_installer.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';

/// A slim, dismissible strip above the bottom bar when a newer sideloaded
/// build exists: "Klect x.y.z is available · View".
///
/// Renders nothing at all—not even reserved space—when there is no update,
/// when the check is still in flight, or on any platform except Android.
class UpdateBanner extends ConsumerWidget {
  /// Creates the banner.
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(availableUpdateProvider).value;
    if (update == null) return const SizedBox.shrink();

    final colors = context.kc;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: Strokes.hairline),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s2,
        Space.s2,
        Space.s2,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.system_update_alt_rounded,
            size: Space.s5,
            color: colors.accentDefault,
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text(
              'Klect ${update.version} is available',
              style: context.kt.callout.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Space.s2),
          KButton(
            label: 'View',
            variant: KButtonVariant.secondary,
            size: KButtonSize.small,
            onPressed: () => UpdateSheet.show(context, update),
          ),
          KIconButton(
            icon: Icons.close_rounded,
            semanticLabel: 'Dismiss update banner',
            onPressed: () =>
                ref.read(availableUpdateProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }
}

/// The release sheet: version, notes, in-app download, install, and skip.
abstract final class UpdateSheet {
  /// Opens the sheet for [update].
  static Future<void> show(BuildContext context, AvailableUpdate update) =>
      KSheet.show<void>(
        context: context,
        title: 'Klect ${update.version}',
        maxHeightFraction: 0.85,
        builder: (sheetContext) => _UpdateSheetBody(update: update),
      );
}

class _UpdateSheetBody extends ConsumerStatefulWidget {
  const _UpdateSheetBody({required this.update});

  final AvailableUpdate update;

  @override
  ConsumerState<_UpdateSheetBody> createState() => _UpdateSheetBodyState();
}

class _UpdateSheetBodyState extends ConsumerState<_UpdateSheetBody> {
  late final UpdateInstaller _installer = UpdateInstaller();
  File? _apk;
  double? _progress;
  bool _busy = false;

  Future<void> _updateNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _apk ??= await _installer.download(
        widget.update,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      final apk = _apk;
      if (!mounted || apk == null) return;

      final result = await _installer.install(apk);
      if (!mounted) return;
      switch (result) {
        case InstallRequestResult.installerOpened:
          Navigator.of(context).pop();
        case InstallRequestResult.permissionRequired:
          KToast.show(
            context,
            'Allow updates from KLECT, then return and tap Continue install.',
            kind: KToastKind.warning,
            icon: Icons.security_rounded,
            duration: const Duration(seconds: 6),
          );
      }
    } on UpdateInstallException catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final update = widget.update;
    final progress = _progress;
    final progressPercent = progress == null ? null : (progress * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'You have $kAppVersion. KLECT downloads and verifies the update '
          'here, then Android asks you to approve the installation.',
          style: context.kt.caption.copyWith(color: colors.textSecondary),
        ),
        if (update.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.s4),
          Flexible(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.s4),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: colors.borderSubtle,
                  width: Strokes.thin,
                ),
              ),
              child: SingleChildScrollView(
                child: Text(
                  update.notes,
                  style: context.kt.body.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: Space.s5),
        if (_busy && progress != null) ...<Widget>[
          Semantics(
            label: 'Downloading update',
            value: '$progressPercent percent',
            child: LinearProgressIndicator(
              value: progress,
              minHeight: Space.s1,
              color: colors.accentDefault,
              backgroundColor: colors.surface3,
              borderRadius: BorderRadius.circular(Radii.full),
            ),
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Downloading… $progressPercent%',
            style: context.kt.caption.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s3),
        ],
        KButton(
          label: _apk == null ? 'Update in KLECT' : 'Continue install',
          size: KButtonSize.large,
          expand: true,
          icon: _apk == null
              ? Icons.download_rounded
              : Icons.install_mobile_rounded,
          busy: _busy,
          animateChanges: true,
          onPressed: _updateNow,
        ),
        const SizedBox(height: Space.s2),
        KButton(
          label: 'Skip this version',
          variant: KButtonVariant.ghost,
          expand: true,
          onPressed: _busy
              ? null
              : () async {
                  await ref
                      .read(updateCheckerProvider)
                      .skip(widget.update.version);
                  ref.read(availableUpdateProvider.notifier).dismiss();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
        ),
      ],
    );
  }
}
