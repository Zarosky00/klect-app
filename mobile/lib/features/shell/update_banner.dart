import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_version.dart';
import '../../core/updates/update_checker.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';

/// A slim, dismissible strip above the bottom bar when a newer sideloaded
/// build exists: "Klect x.y.z is available · View".
///
/// Renders nothing at all — not even reserved space — when there is no
/// update, when the check is still in flight, or on any platform that is not
/// Android.
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

/// The release sheet: version, scrollable notes, update / skip.
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

class _UpdateSheetBody extends ConsumerWidget {
  const _UpdateSheetBody({required this.update});

  final AvailableUpdate update;

  Future<void> _updateNow(BuildContext context) async {
    // The browser downloads the APK and Android's installer takes over —
    // deliberately no in-app installer plumbing.
    final opened = await launchUrl(
      Uri.parse(UpdateChecker.apkUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;
    if (!opened) {
      KToast.error(context, 'Could not open the download link');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'You have $kAppVersion. The update downloads in your browser and '
          'Android installs it from there.',
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
        KButton(
          label: 'Update now',
          size: KButtonSize.large,
          expand: true,
          icon: Icons.download_rounded,
          onPressed: () => _updateNow(context),
        ),
        const SizedBox(height: Space.s2),
        KButton(
          label: 'Skip this version',
          variant: KButtonVariant.ghost,
          expand: true,
          onPressed: () async {
            await ref.read(availableUpdateProvider.notifier).skip();
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
