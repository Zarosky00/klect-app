import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';

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

/// The Pulse composer: **text plus something you own**.
///
/// Klect's write surface has exactly one way to put a thing in front of the
/// people who follow you — `toggle_repost(p_type, p_id, p_quote)` — so that is
/// what the composer drives. Picking one of your collections, shelves or
/// things and adding a note publishes a quote repost; the RPC is idempotent,
/// so sharing something already in your Pulse takes it back out again and the
/// sheet says so rather than silently doing nothing.
abstract final class PulseComposer {
  /// Opens the composer. Resolves true when something was published.
  static Future<bool> show(BuildContext context) async {
    final result = await KSheet.show<bool>(
      context: context,
      title: 'Share to Pulse',
      builder: (sheetContext) => const _ComposerBody(),
    );
    return result ?? false;
  }
}

class _ComposerBody extends ConsumerStatefulWidget {
  const _ComposerBody();

  @override
  ConsumerState<_ComposerBody> createState() => _ComposerBodyState();
}

class _ComposerBodyState extends ConsumerState<_ComposerBody> {
  final TextEditingController _text = TextEditingController();
  PulseAttachment? _attachment;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await _EntityPicker.show(context);
    if (picked == null || !mounted) return;
    setState(() => _attachment = picked);
  }

  Future<void> _publish() async {
    final attachment = _attachment;
    if (attachment == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final note = _text.text.trim();
    try {
      final result = await ref.read(klectApiProvider).toggleRepost(
            attachment.type,
            attachment.id,
            quote: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      Navigator.of(context).pop(result.active);
      KToast.show(
        context,
        result.active
            ? 'Shared to Pulse'
            : 'Removed from Pulse — it was already there',
        kind: result.active ? KToastKind.success : KToastKind.neutral,
        icon: result.active ? Icons.bolt_rounded : Icons.undo_rounded,
      );
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final attachment = _attachment;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KTextField(
          controller: _text,
          hint: 'Say something about it',
          maxLines: 5,
          minLines: 3,
          maxLength: 500,
          autofocus: true,
        ),
        const SizedBox(height: Space.s4),
        if (attachment == null)
          KButton(
            label: 'Attach something you own',
            icon: Icons.add_photo_alternate_outlined,
            variant: KButtonVariant.secondary,
            expand: true,
            onPressed: () => unawaited(_pick()),
          )
        else
          _AttachmentPreview(
            attachment: attachment,
            onRemove: () => setState(() => _attachment = null),
            onChange: () => unawaited(_pick()),
          ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: Space.s3),
          Text(
            _error!,
            style: context.kt.caption.copyWith(color: colors.semanticDanger),
          ),
        ],
        const SizedBox(height: Space.s5),
        KButton(
          label: 'Share',
          icon: Icons.bolt_rounded,
          expand: true,
          busy: _busy,
          onPressed: attachment == null ? null : () => unawaited(_publish()),
        ),
        SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
      ],
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
                      style: context.kt.caption
                          .copyWith(color: colors.textSecondary),
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
          KInlineError(message: _error!, onRetry: () => unawaited(_loadCollections()))
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
          subtitle: '${formatCount(collection.subcollectionCount)} shelves · '
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
                      style: context.kt.caption
                          .copyWith(color: colors.textSecondary),
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
