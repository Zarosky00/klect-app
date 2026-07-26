import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../chat_models.dart';
import '../thread_controller.dart';

/// One photo inside a bubble.
///
/// The `chat` bucket is **private**, so a stored attachment is only reachable
/// through a signed URL — [chatAttachmentUrlProvider] mints and caches one per
/// object. While a photo is still uploading there is no object yet, so we paint
/// the bytes we already hold: the bubble is never a spinner.
///
/// The box is reserved from the attachment's intrinsic pixels before anything
/// loads, so the thread never reflows under the user's thumb.
class ChatPhoto extends ConsumerWidget {
  /// Creates a chat photo.
  const ChatPhoto({
    required this.attachment,
    super.key,
    this.localBytes,
    this.borderRadius,
    this.onTap,
    this.maxWidth = Space.s24 * 3,
  });

  /// The descriptor from `messages.attachments`.
  final ChatAttachment attachment;

  /// Bytes held in memory while the upload is in flight.
  final Uint8List? localBytes;

  /// Corner rounding, matched to the bubble.
  final BorderRadius? borderRadius;

  /// Opens the photo full screen.
  final VoidCallback? onTap;

  /// Ceiling on the bubble width.
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius =
        borderRadius ?? const BorderRadius.all(Radius.circular(Radii.md));

    Widget content;
    final bytes = localBytes;
    if (bytes != null) {
      content = ClipRRect(
        borderRadius: radius,
        child: Image.memory(bytes, fit: BoxFit.cover),
      );
    } else if (attachment.storagePath.isEmpty) {
      content = KShimmer(
        child: KSkeleton(borderRadius: radius),
      );
    } else {
      final url = ref.watch(chatAttachmentUrlProvider(attachment.storagePath));
      content = url.when(
        data: (value) => KBlurhashImage(
          url: value,
          blurhash: attachment.blurhash,
          borderRadius: radius,
          fit: BoxFit.cover,
          semanticLabel: 'Shared photo',
          memCacheWidth: (maxWidth * 2).round(),
        ),
        loading: () => KShimmer(child: KSkeleton(borderRadius: radius)),
        error: (_, _) => _Unavailable(radius: radius),
      );
    }

    final box = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AspectRatio(aspectRatio: attachment.aspect, child: content),
    );

    if (onTap == null) return box;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: 'Open photo',
      child: box,
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.radius});

  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: radius,
        border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: Space.s6,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

/// A photo opened full screen from a bubble.
///
/// Deliberately simple: chat photos are not KLECT entities, so they do not get
/// the closeup / immersive gesture contract — a tap in, a tap out.
class ChatPhotoViewer extends ConsumerWidget {
  /// Creates a viewer.
  const ChatPhotoViewer({required this.attachment, super.key, this.localBytes});

  /// The photo.
  final ChatAttachment attachment;

  /// Bytes, when the upload has not finished.
  final Uint8List? localBytes;

  /// Pushes the viewer as an opaque route.
  static Future<void> open(
    BuildContext context, {
    required ChatAttachment attachment,
    Uint8List? localBytes,
  }) =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ChatPhotoViewer(
            attachment: attachment,
            localBytes: localBytes,
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    return KScaffold(
      backgroundColor: colors.bgSunken,
      appBar: const KFixedAppBar(showBack: true, transparent: true),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: ChatPhoto(
            attachment: attachment,
            localBytes: localBytes,
            maxWidth: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    );
  }
}
