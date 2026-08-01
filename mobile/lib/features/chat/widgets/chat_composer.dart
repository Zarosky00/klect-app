import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_error.dart';
import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../chat_models.dart';
import '../thread_controller.dart';
import 'entity_share_sheet.dart';

/// The message composer: text, photo, and share-a-collection.
///
/// Everything the user can send lives behind one row. The two attachment
/// affordances are icons, not a tray, because a tray is a wall of buttons —
/// and the send control only takes the oxblood accent when there is something to
/// send, so the user's own intent is the only colour on the bar.
class ChatComposer extends ConsumerStatefulWidget {
  /// Creates a composer.
  const ChatComposer({
    required this.conversationId,
    super.key,
    this.replyTo,
    this.editing,
    this.onCancelReply,
    this.onCancelEdit,
    this.enabled = true,
  });

  /// Which conversation this writes to.
  final String conversationId;

  /// The message being replied to, if any.
  final ChatMessage? replyTo;

  /// The message being edited, if any.
  final ChatMessage? editing;

  /// Clears the reply target.
  final VoidCallback? onCancelReply;

  /// Clears the edit target.
  final VoidCallback? onCancelEdit;

  /// False while the thread is still loading.
  final bool enabled;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;
  bool _hasText = false;

  ChatThreadController get _thread =>
      ref.read(chatThreadProvider(widget.conversationId).notifier);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _adoptEditing(null);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editing?.id != widget.editing?.id) {
      _adoptEditing(oldWidget.editing);
    }
    if (widget.replyTo != null && oldWidget.replyTo?.id != widget.replyTo?.id) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _adoptEditing(ChatMessage? previous) {
    final editing = widget.editing;
    if (editing == null) {
      if (previous != null) _controller.clear();
      return;
    }
    _controller.text = editing.message.body ?? '';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _focus.requestFocus();
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    if (has && widget.editing == null) _thread.notifyTyping();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    final editing = widget.editing;

    if (editing != null) {
      if (body.isEmpty) return;
      _controller.clear();
      widget.onCancelEdit?.call();
      await _thread.edit(editing.id, body);
      return;
    }

    if (body.isEmpty) return;
    final replyId = widget.replyTo?.id;
    _controller.clear();
    widget.onCancelReply?.call();
    await _thread.sendText(body: body, replyToId: replyId);
  }

  Future<void> _attachPhoto() async {
    final source = await KSheet.show<ImageSource>(
      context: context,
      title: 'Add a photo',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KButton(
            label: 'Take a photo',
            icon: Icons.photo_camera_outlined,
            variant: KButtonVariant.secondary,
            expand: true,
            onPressed: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          const SizedBox(height: Space.s2),
          KButton(
            label: 'Choose from library',
            icon: Icons.photo_library_outlined,
            variant: KButtonVariant.secondary,
            expand: true,
            onPressed: () =>
                Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      final limit = StorageBucket.chat.limitMb * 1024 * 1024;
      if (bytes.lengthInBytes > limit) {
        if (!mounted) return;
        KToast.error(
          context,
          'That photo is over ${StorageBucket.chat.limitMb} MB.',
        );
        return;
      }

      final size = await _decodeSize(bytes);
      final caption = _controller.text.trim();
      final replyId = widget.replyTo?.id;
      _controller.clear();
      widget.onCancelReply?.call();
      if (!mounted) return;

      await _thread.sendPhoto(
        bytes: bytes,
        width: size.width,
        height: size.height,
        contentType: _mimeFor(picked.name, picked.mimeType),
        extension: _extensionFor(picked.name),
        caption: caption.isEmpty ? null : caption,
        replyToId: replyId,
      );
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    } catch (_) {
      if (!mounted) return;
      KToast.error(context, 'That photo could not be attached.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareEntity() async {
    final selection = await EntityShareSheet.show(context);
    if (selection == null || !mounted) return;
    final body = _controller.text.trim();
    final replyId = widget.replyTo?.id;
    _controller.clear();
    widget.onCancelReply?.call();
    await _thread.sendText(
      body: body.isEmpty ? null : body,
      replyToId: replyId,
      sharedEntityType: selection.type,
      sharedEntityId: selection.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final editing = widget.editing;
    final replyTo = widget.replyTo;
    final canSend = _hasText && widget.enabled && !_busy;

    return Container(
      key: const ValueKey<String>('chat-composer'),
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: Strokes.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (editing != null)
              _ContextBanner(
                icon: Icons.edit_outlined,
                title: 'Editing',
                body: editing.message.body ?? '',
                onCancel: () {
                  _controller.clear();
                  widget.onCancelEdit?.call();
                },
              )
            else if (replyTo != null)
              _ContextBanner(
                icon: Icons.reply_rounded,
                title:
                    'Replying to '
                    '${replyTo.message.author?.name ?? 'message'}',
                body: replyTo.hasText
                    ? replyTo.message.body!
                    : (replyTo.attachments.isNotEmpty ? 'Photo' : 'Shared'),
                onCancel: widget.onCancelReply,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s2,
                Space.s2,
                Space.s2,
                Space.s2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (editing == null) ...<Widget>[
                    KIconButton(
                      icon: Icons.add_photo_alternate_outlined,
                      semanticLabel: 'Attach a photo',
                      onPressed: widget.enabled && !_busy ? _attachPhoto : null,
                    ),
                    KIconButton(
                      icon: Icons.grid_view_rounded,
                      semanticLabel: 'Share a collection',
                      onPressed: widget.enabled && !_busy ? _shareEntity : null,
                    ),
                  ],
                  Expanded(
                    child: KTextField(
                      key: const ValueKey<String>('chat-composer-field'),
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      hint: editing == null ? 'Message' : 'Edit message',
                      maxLines: 5,
                      minLines: 1,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  _SendButton(
                    enabled: canSend,
                    busy: _busy,
                    editing: editing != null,
                    onPressed: () => unawaited(_send()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<({int width, int height})> _decodeSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (width: descriptor.width, height: descriptor.height);
      descriptor.dispose();
      return size;
    } finally {
      buffer.dispose();
    }
  }

  static String _extensionFor(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _mimeFor(String name, String? declared) {
    if (declared != null && declared.startsWith('image/')) return declared;
    return switch (_extensionFor(name)) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' || 'heif' => 'image/heic',
      _ => 'image/jpeg',
    };
  }
}

class _ContextBanner extends StatelessWidget {
  const _ContextBanner({
    required this.icon,
    required this.title,
    required this.body,
    this.onCancel,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      key: const ValueKey<String>('chat-context-banner'),
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s2,
        Space.s2,
        Space.s0,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.borderSubtle,
            width: Strokes.hairline,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: Space.s4, color: colors.accentDefault),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: context.kt.micro.copyWith(color: colors.accentDefault),
                ),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.kt.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          KIconButton(
            icon: Icons.close_rounded,
            semanticLabel: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.busy,
    required this.editing,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final bool editing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      enforceMinTapTarget: false,
      semanticLabel: editing ? 'Save edit' : 'Send message',
      child: AnimatedContainer(
        duration: KMotion.duration(context, KDurations.fast),
        curve: Curves_.emphasized,
        width: Layout.tapTargetMin,
        height: Layout.tapTargetMin,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? colors.accentDefault : colors.surface3,
        ),
        child: busy
            ? SizedBox(
                width: Space.s4,
                height: Space.s4,
                child: CircularProgressIndicator(
                  strokeWidth: Strokes.thick,
                  color: colors.textOnAccent,
                ),
              )
            : Icon(
                editing ? Icons.check_rounded : Icons.arrow_upward_rounded,
                size: Space.s5,
                color: enabled ? colors.textOnAccent : colors.textTertiary,
              ),
      ),
    );
  }
}
