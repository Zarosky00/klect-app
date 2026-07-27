import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../auth/auth_controller.dart';
import '../../create/frame/crop_frame.dart';
import '../../create/media/image_pipeline.dart';
import '../../create/media/photo_source_sheet.dart';
import '../data/pulse_feed_controller.dart';
import 'pulse_target_card.dart';

const Uuid _uuid = Uuid();

/// Something the viewer owns, chosen to be shared into Pulse.
@immutable
class PulseAttachment {
  /// Creates an attachment reference.
  const PulseAttachment({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.coverPath,
    this.blurhash,
  });

  /// Which level it is.
  final EntityType type;

  /// Entity id.
  final String id;

  /// Display name.
  final String title;

  /// Secondary line.
  final String? subtitle;

  /// Cover path.
  final String? coverPath;

  /// Blurhash of the cover.
  final String? blurhash;
}

/// The Pulse composer — X parity, driven by `create_post` (0018).
///
/// Text-only posts, up to four photos (prepared by the same pipeline the
/// create flow uses, uploaded to `{uid}/posts/{draft}/{uuid}.jpg` in the
/// `media` bucket, then handed to the RPC as descriptors), an optional
/// entity share card, and quote mode (`entity_type = 'post'`) opened from the
/// repost chooser with the subject embedded.
/// The immutable thing shown under a quote draft.
@immutable
class PulseComposerSubject {
  /// Creates a subject with optional already-loaded presentation data.
  const PulseComposerSubject({
    required this.entity,
    this.preview,
    this.media = const <ItemMedia>[],
  });

  /// Stable target written to `create_post`.
  final EntityRef entity;

  /// Immediate embedded preview supplied by a feed or thread caller.
  final PulseTarget? preview;

  /// Original post media, separate from the new draft's four-photo allowance.
  final List<ItemMedia> media;
}

abstract final class PulseComposer {
  /// Opens the composer. [subject] pre-embeds a thing being quoted or shared
  /// — pass `EntityRef.post(id)` for an X-style quote.
  ///
  /// Resolves with the new post's pulse envelope, or null when nothing was
  /// published. The envelope is also prepended to the Following stream, so
  /// callers only need the return value if they render the post themselves.
  static Future<PulseEntry?> show(
    BuildContext context, {
    PulseComposerSubject? subject,
  }) => Navigator.of(context, rootNavigator: true).push<PulseEntry>(
    MaterialPageRoute<PulseEntry>(
      // Drag-to-dismiss pops the route without consulting PopScope, which
      // would silently skip the "Discard post?" confirm — so the composer
      // closes via back / barrier tap only, both of which PopScope guards.
      fullscreenDialog: true,
      builder: (_) => _ComposerBody(subject: subject),
    ),
  );
}

/// One photo in the composer tray: prepared on-device, uploaded at publish.
class _DraftPhoto {
  _DraftPhoto({required this.sourceBytes, required this.prepared});

  final String id = _uuid.v4();
  final Uint8List sourceBytes;
  PreparedImage prepared;
  Rect? cropRect;
  int quarterTurns = 0;

  bool get edited => cropRect != null || quarterTurns != 0;
}

class _ComposerBody extends ConsumerStatefulWidget {
  const _ComposerBody({this.subject});

  final PulseComposerSubject? subject;

  @override
  ConsumerState<_ComposerBody> createState() => _ComposerBodyState();
}

class _ComposerBodyState extends ConsumerState<_ComposerBody> {
  /// `create_post` refuses more than four descriptors.
  static const int maxPhotos = 4;

  /// `posts.body` is capped at 2,000 characters server-side.
  static const int maxBody = 2000;

  /// Where the plain composer's body survives a close or a process death.
  static const String draftKey = 'pulse.composer.draft';

  final TextEditingController _text = TextEditingController();
  final String _draftId = _uuid.v4();
  final List<_DraftPhoto> _photos = <_DraftPhoto>[];

  PulseAttachment? _attachment;
  bool _preparing = false;
  bool _busy = false;
  String? _progress;
  String? _error;

  bool get _hasContent =>
      _text.text.trim().isNotEmpty ||
      _photos.isNotEmpty ||
      _attachment != null ||
      widget.subject != null;

  /// True when closing would lose something the user made here. A quote or
  /// entity subject alone is not "content" — dismissing it loses nothing.
  bool get _dirty =>
      _text.text.trim().isNotEmpty || _photos.isNotEmpty || _attachment != null;

  /// Drafts only apply to the plain composer; a quote's text belongs to the
  /// thing being quoted and must not leak into the next plain post.
  bool get _draftable => widget.subject == null;

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  void initState() {
    super.initState();
    // The publish button's enabled state follows the text; the draft follows
    // every keystroke so a killed process never loses words.
    _text.addListener(_onTextChanged);
    if (_draftable) {
      final draft = _store.getString(draftKey);
      if (draft != null && draft.trim().isNotEmpty) _text.text = draft;
    }
  }

  void _onTextChanged() {
    setState(() {});
    if (!_draftable) return;
    final body = _text.text;
    if (body.trim().isEmpty) {
      unawaited(_store.remove(draftKey));
    } else {
      unawaited(_store.setString(draftKey, body));
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await KConfirmDialog.show(
      context,
      title: 'Discard post?',
      message: 'What you wrote here will be gone.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!discard || !mounted) return;
    if (_draftable) unawaited(_store.remove(draftKey));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final remaining = maxPhotos - _photos.length;
    if (remaining <= 0 || _preparing || _busy) return;
    final picked = await PhotoSourceSheet.pick(context, limit: remaining);
    if (picked.isEmpty || !mounted) return;

    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      for (final file in picked.take(remaining)) {
        final raw = await file.readAsBytes();
        final prepared = await ImagePipeline.prepare(raw);
        if (!mounted) return;
        setState(
          () => _photos.add(_DraftPhoto(sourceBytes: raw, prepared: prepared)),
        );
      }
    } on ImagePreparationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read that photo.');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _removePhoto(String id) =>
      setState(() => _photos.removeWhere((photo) => photo.id == id));

  void _reorderPhotos(int oldIndex, int newIndex) {
    if (_busy || _preparing) return;
    setState(() {
      final photo = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, photo);
    });
  }

  Future<void> _editPhoto(_DraftPhoto photo) async {
    if (_busy || _preparing) return;
    final edit = await _ComposerPhotoEditor.show(context, photo: photo);
    if (edit == null || !mounted) return;

    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final prepared = await ImagePipeline.prepare(
        photo.sourceBytes,
        cropRect: edit.cropRect,
        quarterTurns: edit.quarterTurns,
      );
      if (!mounted) return;
      setState(() {
        photo
          ..prepared = prepared
          ..cropRect = edit.cropRect
          ..quarterTurns = edit.quarterTurns;
      });
    } on ImagePreparationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not apply those photo edits.');
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _pickAttachment() async {
    final picked = await _EntityPicker.show(context);
    if (picked == null || !mounted) return;
    setState(() => _attachment = picked);
  }

  (EntityType, String)? get _target {
    final subject = widget.subject;
    if (subject != null) {
      return (subject.entity.type, subject.entity.id);
    }
    final attachment = _attachment;
    if (attachment != null) return (attachment.type, attachment.id);
    return null;
  }

  Future<void> _publish() async {
    if (_busy || _preparing || !_hasContent) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final api = ref.read(klectApiProvider);
    final uploaded = <String>[];
    try {
      // 1. Photos land in the media bucket under the draft's folder —
      //    {uid}/posts/{draftId}/{uuid} — which create_post validates.
      final descriptors = <Map<String, dynamic>>[];
      for (var index = 0; index < _photos.length; index++) {
        final prepared = _photos[index].prepared;
        if (mounted && _photos.length > 1) {
          setState(
            () => _progress =
                'Uploading photo ${index + 1} of ${_photos.length}…',
          );
        }
        final key = await api.upload(
          bucket: StorageBucket.media,
          objectPath: 'posts/$_draftId/${_uuid.v4()}.${prepared.extension}',
          bytes: prepared.bytes,
          contentType: prepared.mimeType,
        );
        uploaded.add(key);
        descriptors.add(<String, dynamic>{
          'storage_path': key,
          'width': prepared.width,
          'height': prepared.height,
          'blurhash': prepared.blurhash.isEmpty ? null : prepared.blurhash,
          'mime_type': prepared.mimeType,
          'bytes': prepared.byteLength,
          'position': index,
        });
      }

      if (mounted) setState(() => _progress = 'Publishing…');

      // 2. The one insert path for posts.
      final target = _target;
      final body = _text.text.trim();
      final entry = await api.createPost(
        body: body.isEmpty ? null : body,
        kind: target != null && target.$1 == EntityType.post
            ? PostKind.quote
            : PostKind.post,
        entityType: target?.$1,
        entityId: target?.$2,
        media: descriptors.isEmpty ? null : descriptors,
      );

      // 3. Prepend the returned envelope so the stream shows it instantly —
      //    own posts always belong to the Following feed.
      ref.read(pulseFeedProvider(PulseMode.following).notifier).prepend(entry);

      if (!mounted) return;
      if (_draftable) unawaited(_store.remove(draftKey));
      Navigator.of(context).pop(entry);
    } on KlectError catch (error) {
      // Best effort: a failed publish must not leave orphan blobs behind.
      for (final key in uploaded) {
        unawaited(
          api.removeUpload(StorageBucket.media, key).catchError((_) {}),
        );
      }
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final subject = widget.subject;
    final attachment = _attachment;
    final isQuote = subject != null;
    final me = ref.watch(myProfileProvider).value;
    final avatarUrl = me?.avatarPath == null
        ? null
        : ref
              .watch(klectApiProvider)
              .publicUrl(me?.avatarPath, bucket: StorageBucket.avatars);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmDiscard());
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: colors.surface1,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s3,
                  Space.s2,
                  Space.s3,
                  Space.s2,
                ),
                child: Row(
                  children: <Widget>[
                    KButton(
                      key: const ValueKey<String>('pulse-cancel'),
                      label: 'Cancel',
                      variant: KButtonVariant.ghost,
                      size: KButtonSize.small,
                      onPressed: _busy
                          ? null
                          : () {
                              if (_dirty) {
                                unawaited(_confirmDiscard());
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                    ),
                    const Spacer(),
                    KButton(
                      key: const ValueKey<String>('pulse-submit'),
                      label: isQuote ? 'Quote' : 'Post',
                      size: KButtonSize.small,
                      busy: _busy,
                      onPressed: _hasContent && !_preparing
                          ? () => unawaited(_publish())
                          : null,
                    ),
                  ],
                ),
              ),
              Divider(
                height: Strokes.hairline,
                thickness: Strokes.hairline,
                color: colors.borderSubtle,
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey<String>('pulse-composer-scroll'),
                  padding: const EdgeInsets.all(Space.s4),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        KAvatar(
                          imageUrl: avatarUrl,
                          name: me?.name,
                          size: Space.s10,
                        ),
                        const SizedBox(width: Space.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextField(
                                key: const ValueKey<String>(
                                  'pulse-composer-text',
                                ),
                                controller: _text,
                                autofocus: true,
                                minLines: 3,
                                maxLines: null,
                                maxLength: maxBody,
                                keyboardType: TextInputType.multiline,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: context.kt.body,
                                cursorColor: colors.accentDefault,
                                decoration: InputDecoration(
                                  hintText: isQuote
                                      ? 'Add your take'
                                      : 'What is on your shelf today?',
                                  hintStyle: context.kt.body.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  counterText: '',
                                  filled: false,
                                ),
                              ),
                              if (_photos.isNotEmpty || _preparing) ...<Widget>[
                                const SizedBox(height: Space.s3),
                                _PhotoTray(
                                  photos: _photos,
                                  preparing: _preparing,
                                  onEdit: _busy || _preparing
                                      ? null
                                      : (photo) => unawaited(_editPhoto(photo)),
                                  onRemove: _busy || _preparing
                                      ? null
                                      : _removePhoto,
                                  onReorder: _busy || _preparing
                                      ? null
                                      : _reorderPhotos,
                                ),
                              ],
                              if (subject != null) ...<Widget>[
                                const SizedBox(height: Space.s3),
                                _ComposerSubjectPreview(subject: subject),
                              ],
                              if (subject == null &&
                                  attachment != null) ...<Widget>[
                                const SizedBox(height: Space.s3),
                                _AttachmentPreview(
                                  attachment: attachment,
                                  onRemove: () =>
                                      setState(() => _attachment = null),
                                  onChange: () => unawaited(_pickAttachment()),
                                ),
                              ],
                              if (_error != null) ...<Widget>[
                                const SizedBox(height: Space.s3),
                                Text(
                                  _error!,
                                  style: context.kt.caption.copyWith(
                                    color: colors.semanticDanger,
                                  ),
                                ),
                              ],
                              if (_progress != null) ...<Widget>[
                                const SizedBox(height: Space.s3),
                                Text(
                                  _progress!,
                                  style: context.kt.caption.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: Space.s4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                key: const ValueKey<String>('pulse-media-toolbar'),
                padding: const EdgeInsets.fromLTRB(
                  Space.s4,
                  Space.s2,
                  Space.s4,
                  Space.s2,
                ),
                decoration: BoxDecoration(
                  color: colors.surface1,
                  border: Border(
                    top: BorderSide(
                      color: colors.borderSubtle,
                      width: Strokes.hairline,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    KButton(
                      key: const ValueKey<String>('pulse-add-photos'),
                      label: 'Add photo',
                      icon: Icons.add_photo_alternate_outlined,
                      variant: KButtonVariant.ghost,
                      size: KButtonSize.small,
                      onPressed:
                          _photos.length >= maxPhotos || _preparing || _busy
                          ? null
                          : () => unawaited(_addPhotos()),
                    ),
                    if (subject == null) ...<Widget>[
                      const SizedBox(width: Space.s1),
                      KIconButton(
                        icon: Icons.collections_bookmark_outlined,
                        semanticLabel: attachment == null
                            ? 'Add something you own'
                            : 'Change shared collection or item',
                        onPressed: _busy
                            ? null
                            : () => unawaited(_pickAttachment()),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${_text.text.length}/$maxBody',
                      style: context.kt.micro.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _LoadedComposerSubject {
  const _LoadedComposerSubject({required this.target, required this.media});

  final PulseTarget target;
  final List<ItemMedia> media;
}

final _composerSubjectProvider = FutureProvider.autoDispose
    .family<_LoadedComposerSubject, EntityRef>((ref, entity) async {
      final target = await ref.watch(pulseTargetProvider(entity).future);
      final media = entity.type == EntityType.post && !target.unavailable
          ? await ref.watch(klectApiProvider).fetchPostMedia(entity.id)
          : const <ItemMedia>[];
      return _LoadedComposerSubject(target: target, media: media);
    }, name: 'pulseComposerSubject');

final _composerSubjectMediaProvider = FutureProvider.autoDispose
    .family<List<ItemMedia>, EntityRef>((ref, entity) async {
      if (entity.type != EntityType.post) return const <ItemMedia>[];
      return ref.watch(klectApiProvider).fetchPostMedia(entity.id);
    }, name: 'pulseComposerSubjectMedia');

class _ComposerSubjectPreview extends ConsumerWidget {
  const _ComposerSubjectPreview({required this.subject});

  final PulseComposerSubject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final immediate = subject.preview;
    if (immediate != null) {
      final needsCompletePostMedia =
          subject.entity.type == EntityType.post &&
          subject.media.isEmpty &&
          immediate.coverPath != null;
      final fallbackMedia = needsCompletePostMedia
          ? ref.watch(_composerSubjectMediaProvider(subject.entity)).value
          : null;
      return PulseTargetCard(
        key: const ValueKey<String>('pulse-quoted-preview'),
        target: immediate,
        media: fallbackMedia ?? subject.media,
        interactive: false,
      );
    }

    final async = ref.watch(_composerSubjectProvider(subject.entity));
    final loaded = async.value;
    if (loaded != null) {
      return PulseTargetCard(
        key: const ValueKey<String>('pulse-quoted-preview'),
        target: loaded.target,
        media: loaded.media,
        interactive: false,
      );
    }
    if (async.hasError) {
      return PulseTargetCard(
        key: const ValueKey<String>('pulse-quoted-preview'),
        target: PulseTarget(
          id: subject.entity.id,
          type: subject.entity.type,
          unavailable: true,
        ),
        interactive: false,
      );
    }
    return const KShimmer(
      child: KSkeleton(
        key: ValueKey<String>('pulse-quoted-preview-loading'),
        borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        height: PulseTargetCard.thumb,
      ),
    );
  }
}

/// The horizontal strip of prepared photos, with remove buttons.
class _PhotoTray extends StatelessWidget {
  const _PhotoTray({
    required this.photos,
    required this.preparing,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  final List<_DraftPhoto> photos;
  final bool preparing;
  final ValueChanged<_DraftPhoto>? onEdit;
  final void Function(String id)? onRemove;
  final ReorderCallback? onReorder;

  static const double _tile = Space.s20;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return SizedBox(
      height: _tile,
      child: Row(
        children: <Widget>[
          if (photos.isNotEmpty)
            Expanded(
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: onReorder != null,
                itemCount: photos.length,
                onReorderItem: onReorder ?? (_, _) {},
                proxyDecorator: (child, _, animation) => FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: KCurves.emphasized,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    elevation: Elevation.mid.y,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: child,
                  ),
                ),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return Padding(
                    key: ValueKey<String>(photo.id),
                    padding: const EdgeInsets.only(right: Space.s2),
                    child: SizedBox(
                      width: _tile,
                      height: _tile,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: KPressable(
                              semanticLabel: photo.edited
                                  ? 'Edit cropped photo ${index + 1}'
                                  : 'Edit photo ${index + 1}',
                              onTap: onEdit == null
                                  ? null
                                  : () => onEdit!(photo),
                              enforceMinTapTarget: false,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(Radii.md),
                                child: Image.memory(
                                  photo.prepared.bytes,
                                  width: _tile,
                                  height: _tile,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: Space.s1,
                            bottom: Space.s1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.s2,
                                vertical: Space.s05,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceScrim,
                                borderRadius: BorderRadius.circular(Radii.full),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    photo.edited
                                        ? Icons.crop_rounded
                                        : Icons.edit_rounded,
                                    size: Space.s3,
                                    color: colors.textPrimary,
                                  ),
                                  const SizedBox(width: Space.s1),
                                  Text(
                                    photo.edited ? 'Edited' : 'Edit',
                                    style: context.kt.micro.copyWith(
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (onRemove != null)
                            Positioned(
                              top: Space.s05,
                              right: Space.s05,
                              child: KIconButton(
                                icon: Icons.close_rounded,
                                semanticLabel: 'Remove photo ${index + 1}',
                                size: Space.s4,
                                color: colors.textPrimary,
                                background: colors.surfaceScrim,
                                onPressed: () => onRemove!(photo.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (preparing)
            Container(
              width: _tile,
              height: _tile,
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Center(
                child: SizedBox(
                  width: Space.s5,
                  height: Space.s5,
                  child: CircularProgressIndicator(
                    strokeWidth: Strokes.thick,
                    color: colors.accentDefault,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

@immutable
class _ComposerPhotoEditResult {
  const _ComposerPhotoEditResult({
    required this.cropRect,
    required this.quarterTurns,
  });

  final Rect? cropRect;
  final int quarterTurns;
}

class _ComposerPhotoEditor extends StatefulWidget {
  const _ComposerPhotoEditor({required this.photo});

  final _DraftPhoto photo;

  static Future<_ComposerPhotoEditResult?> show(
    BuildContext context, {
    required _DraftPhoto photo,
  }) =>
      Navigator.of(context, rootNavigator: true).push<_ComposerPhotoEditResult>(
        MaterialPageRoute<_ComposerPhotoEditResult>(
          fullscreenDialog: true,
          builder: (_) => _ComposerPhotoEditor(photo: photo),
        ),
      );

  @override
  State<_ComposerPhotoEditor> createState() => _ComposerPhotoEditorState();
}

class _ComposerPhotoEditorState extends State<_ComposerPhotoEditor> {
  Rect? _cropRect;
  late int _turns;
  late CropPreset _preset;

  @override
  void initState() {
    super.initState();
    _cropRect = widget.photo.cropRect;
    _turns = widget.photo.quarterTurns;
    _preset = _inferPreset(widget.photo.cropRect);
  }

  int get _baseWidth => widget.photo.prepared.sourceWidth;
  int get _baseHeight => widget.photo.prepared.sourceHeight;

  static CropPreset _inferPreset(Rect? crop) {
    if (crop == null || crop.height <= 0) return CropPreset.original;
    final ratio = crop.width / crop.height;
    for (final preset in CropPreset.values) {
      final aspect = preset.aspect;
      if (aspect != null && (ratio - aspect).abs() / aspect < 0.01) {
        return preset;
      }
    }
    return CropPreset.original;
  }

  (double, double) get _turnedDimensions => _turns.isOdd
      ? (_baseHeight.toDouble(), _baseWidth.toDouble())
      : (_baseWidth.toDouble(), _baseHeight.toDouble());

  void _applyPreset(CropPreset preset) {
    final dimensions = _turnedDimensions;
    setState(() {
      _preset = preset;
      _cropRect = preset.aspect == null
          ? null
          : maxCenteredCrop(dimensions.$1, dimensions.$2, preset.aspect!);
    });
  }

  void _rotate() {
    final oldHeight = _turnedDimensions.$2;
    final rotatedCrop = _cropRect == null
        ? null
        : ImagePipeline.rotateCropRect(_cropRect!, height: oldHeight);
    setState(() {
      _turns = (_turns + 1) % 4;
      _cropRect = rotatedCrop;
      _preset = switch (_preset) {
        CropPreset.tall => CropPreset.wide,
        CropPreset.wide => CropPreset.tall,
        final preset => preset,
      };
    });
  }

  void _finish() {
    Navigator.of(
      context,
    ).pop(_ComposerPhotoEditResult(cropRect: _cropRect, quarterTurns: _turns));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Scaffold(
      backgroundColor: colors.surface1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s3,
                Space.s2,
                Space.s3,
                Space.s2,
              ),
              child: Row(
                children: <Widget>[
                  KButton(
                    label: 'Cancel',
                    variant: KButtonVariant.ghost,
                    size: KButtonSize.small,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text('Edit photo', style: context.kt.title3),
                  const Spacer(),
                  KButton(
                    key: const ValueKey<String>('composer-photo-edit-done'),
                    label: 'Done',
                    size: KButtonSize.small,
                    onPressed: _finish,
                  ),
                ],
              ),
            ),
            Divider(
              height: Strokes.hairline,
              thickness: Strokes.hairline,
              color: colors.borderSubtle,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.s3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  child: CropEditor(
                    bytes: widget.photo.sourceBytes,
                    baseWidth: _baseWidth,
                    baseHeight: _baseHeight,
                    quarterTurns: _turns,
                    cropRect: _cropRect,
                    lockedAspect: _preset.aspect,
                    onCropChanged: (rect) => setState(() => _cropRect = rect),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                Space.s4,
                Space.s2,
                Space.s3,
                Space.s3,
              ),
              decoration: BoxDecoration(
                color: colors.surface1,
                border: Border(
                  top: BorderSide(
                    color: colors.borderSubtle,
                    width: Strokes.hairline,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          for (final preset in CropPreset.values) ...<Widget>[
                            KChip(
                              label: preset.label,
                              selected: _preset == preset,
                              onTap: () => _applyPreset(preset),
                            ),
                            const SizedBox(width: Space.s2),
                          ],
                        ],
                      ),
                    ),
                  ),
                  KIconButton(
                    icon: Icons.rotate_90_degrees_cw_rounded,
                    semanticLabel: 'Rotate a quarter turn',
                    onPressed: _rotate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreview extends ConsumerWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.onRemove,
    required this.onChange,
  });

  final PulseAttachment attachment;
  final VoidCallback onRemove;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final url = ref.watch(klectApiProvider).publicUrl(attachment.coverPath);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderSubtle, width: Strokes.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: Space.s16,
            height: Space.s16,
            child: KBlurhashImage(
              url: url,
              blurhash: attachment.blurhash,
              borderRadius: BorderRadius.zero,
              semanticLabel: attachment.title,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    attachment.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.kt.bodyStrong,
                  ),
                  if (attachment.subtitle != null)
                    Text(
                      attachment.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.kt.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          KIconButton(
            icon: Icons.swap_horiz_rounded,
            semanticLabel: 'Change attachment',
            onPressed: onChange,
          ),
          KIconButton(
            icon: Icons.close_rounded,
            semanticLabel: 'Remove attachment',
            onPressed: onRemove,
          ),
          const SizedBox(width: Space.s2),
        ],
      ),
    );
  }
}

/// Drill-down picker over the viewer's own collections → shelves → things.
abstract final class _EntityPicker {
  static Future<PulseAttachment?> show(BuildContext context) =>
      KSheet.show<PulseAttachment>(
        context: context,
        title: 'Pick something of yours',
        maxHeightFraction: 0.8,
        builder: (sheetContext) => const _PickerBody(),
      );
}

class _PickerBody extends ConsumerStatefulWidget {
  const _PickerBody();

  @override
  ConsumerState<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends ConsumerState<_PickerBody> {
  List<CollectionModel> _collections = const <CollectionModel>[];
  List<SubcollectionModel> _subcollections = const <SubcollectionModel>[];
  List<ItemModel> _items = const <ItemModel>[];

  CollectionModel? _collection;
  SubcollectionModel? _subcollection;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCollections());
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await body();
    } on KlectError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCollections() => _run(() async {
    final api = ref.read(klectApiProvider);
    final userId = api.currentUserId;
    if (userId == null) {
      throw const KlectError(KlectErrorKind.auth, 'You need to sign in.');
    }
    final collections = await api.fetchCollections(userId);
    if (!mounted) return;
    setState(() {
      _collections = collections;
      _collection = null;
      _subcollection = null;
    });
  });

  Future<void> _openCollection(CollectionModel collection) => _run(() async {
    final subs = await ref
        .read(klectApiProvider)
        .fetchSubcollections(collection.id);
    if (!mounted) return;
    setState(() {
      _collection = collection;
      _subcollection = null;
      _subcollections = subs;
    });
  });

  Future<void> _openSubcollection(SubcollectionModel sub) => _run(() async {
    final items = await ref
        .read(klectApiProvider)
        .fetchItems(subcollectionId: sub.id);
    if (!mounted) return;
    setState(() {
      _subcollection = sub;
      _items = items;
    });
  });

  void _choose(PulseAttachment attachment) =>
      Navigator.of(context).pop(attachment);

  void _up() {
    if (_subcollection != null) {
      setState(() => _subcollection = null);
      return;
    }
    if (_collection != null) {
      setState(() => _collection = null);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final crumb =
        _subcollection?.name ?? _collection?.name ?? 'Your collections';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            KIconButton(
              icon: Icons.arrow_back_rounded,
              semanticLabel: 'Back',
              onPressed: _up,
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                crumb,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.kt.title3,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        if (_error != null)
          KInlineError(
            message: _error!,
            onRetry: () => unawaited(_loadCollections()),
          )
        else if (_loading)
          const KSkeletonList(rows: 3, showMedia: false)
        else
          Flexible(child: _list()),
      ],
    );
  }

  Widget _list() {
    if (_subcollection != null) {
      if (_items.isEmpty) {
        return _empty('No things on this shelf yet.');
      }
      return ListView.builder(
        shrinkWrap: true,
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _PickerRow(
            title: item.title,
            subtitle: item.brand,
            coverPath: item.coverPath,
            blurhash: item.coverBlurhash,
            icon: Icons.photo_library_rounded,
            onSelect: () => _choose(
              PulseAttachment(
                type: EntityType.item,
                id: item.id,
                title: item.title,
                subtitle: item.brand,
                coverPath: item.coverPath,
                blurhash: item.coverBlurhash,
              ),
            ),
          );
        },
      );
    }

    if (_collection != null) {
      final collection = _collection!;
      return ListView(
        shrinkWrap: true,
        children: <Widget>[
          _PickerRow(
            title: 'Share “${collection.name}” itself',
            subtitle: '${formatCount(collection.itemCount)} things',
            coverPath: collection.coverPath,
            blurhash: collection.coverBlurhash,
            icon: Icons.collections_bookmark_rounded,
            onSelect: () => _choose(
              PulseAttachment(
                type: EntityType.collection,
                id: collection.id,
                title: collection.name,
                subtitle: collection.description,
                coverPath: collection.coverPath,
                blurhash: collection.coverBlurhash,
              ),
            ),
          ),
          if (_subcollections.isEmpty)
            _empty('No shelves in this collection yet.')
          else
            for (final sub in _subcollections)
              _PickerRow(
                title: sub.name,
                subtitle: '${formatCount(sub.itemCount)} things',
                coverPath: sub.coverPath,
                blurhash: sub.coverBlurhash,
                icon: Icons.layers_rounded,
                onOpen: () => unawaited(_openSubcollection(sub)),
                onSelect: () => _choose(
                  PulseAttachment(
                    type: EntityType.subcollection,
                    id: sub.id,
                    title: sub.name,
                    subtitle: sub.description,
                    coverPath: sub.coverPath,
                    blurhash: sub.coverBlurhash,
                  ),
                ),
              ),
        ],
      );
    }

    if (_collections.isEmpty) {
      return _empty('You have not started a collection yet.');
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _collections.length,
      itemBuilder: (context, index) {
        final collection = _collections[index];
        return _PickerRow(
          title: collection.name,
          subtitle:
              '${formatCount(collection.subcollectionCount)} shelves · '
              '${formatCount(collection.itemCount)} things',
          coverPath: collection.coverPath,
          blurhash: collection.coverBlurhash,
          icon: Icons.collections_bookmark_rounded,
          onOpen: () => unawaited(_openCollection(collection)),
          onSelect: () => _choose(
            PulseAttachment(
              type: EntityType.collection,
              id: collection.id,
              title: collection.name,
              subtitle: collection.description,
              coverPath: collection.coverPath,
              blurhash: collection.coverBlurhash,
            ),
          ),
        );
      },
    );
  }

  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s6),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: context.kt.callout.copyWith(color: context.kc.textTertiary),
    ),
  );
}

class _PickerRow extends ConsumerWidget {
  const _PickerRow({
    required this.title,
    required this.icon,
    required this.onSelect,
    this.subtitle,
    this.coverPath,
    this.blurhash,
    this.onOpen,
  });

  final String title;
  final String? subtitle;
  final String? coverPath;
  final String? blurhash;
  final IconData icon;
  final VoidCallback onSelect;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final url = ref.watch(klectApiProvider).publicUrl(coverPath);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: Space.s12,
            height: Space.s12,
            child: KBlurhashImage(
              url: url,
              blurhash: blurhash,
              borderRadius: BorderRadius.circular(Radii.sm),
              semanticLabel: title,
            ),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: KPressable(
              onTap: onOpen ?? onSelect,
              enforceMinTapTarget: false,
              semanticLabel: title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(icon, size: Space.s3, color: colors.textTertiary),
                      const SizedBox(width: Space.s1),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.kt.bodyStrong,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.kt.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          KButton(
            label: 'Attach',
            size: KButtonSize.small,
            variant: KButtonVariant.ghost,
            onPressed: onSelect,
          ),
        ],
      ),
    );
  }
}
