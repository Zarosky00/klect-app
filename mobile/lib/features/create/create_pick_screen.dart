import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../library/library_providers.dart';
import '../library/widgets/library_chrome.dart';
import 'create_item_flow_screen.dart';
import 'create_providers.dart';
import 'media/upload_controller.dart';
import 'media/upload_journal.dart';
import 'pick/pick_grid.dart';
import 'widgets/save_bar.dart';

const Uuid _uuid = Uuid();

/// What the Create tab makes.
enum _CreateIntent {
  /// A thing with photos — the default, and the only media-first path.
  item(Icons.add_a_photo_rounded, 'Item'),

  /// A theme inside a shelf.
  group(Icons.create_new_folder_rounded, 'Group'),

  /// A whole new thing you collect.
  shelf(Icons.collections_bookmark_rounded, 'Shelf');

  const _CreateIntent(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The Create tab — PICK, the first beat of the media-first flow.
///
/// Opens straight onto a full-bleed photo grid: camera tile, library tile,
/// and everything picked so far with selection counts. The entity choice is
/// one intent row that defaults to Item; Group and Shelf hop to their own
/// short forms. Photos start preparing the moment they land, so FRAME opens
/// with real pixels.
class CreatePickScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreatePickScreen({super.key});

  @override
  ConsumerState<CreatePickScreen> createState() => _CreatePickScreenState();
}

class _CreatePickScreenState extends ConsumerState<CreatePickScreen> {
  String _draftId = _uuid.v4();

  /// Cached instance, not a live read: after the flow consumes a draft its
  /// key is invalidated, and a rebuild must not resurrect state under it.
  late MediaUploadController _uploads =
      ref.read(mediaUploadControllerProvider(_draftId));

  @override
  void initState() {
    super.initState();
    // First Library/Create surface to mount reconciles anything an
    // interrupted upload left behind.
    ref.read(mediaRecoveryProvider);
  }

  String _flowRoute() {
    final defaults = ref.read(createDefaultsProvider);
    final shelves =
        ref.read(myCollectionsProvider).value ?? const <CollectionModel>[];
    final remembered = defaults.collectionId;
    final exists = shelves.any((shelf) => shelf.id == remembered);
    final buffer = StringBuffer('/create/item?draft=$_draftId');
    if (exists && remembered != null) {
      buffer.write('&collection=$remembered');
      final subcollection = defaults.subcollectionId;
      if (subcollection != null) {
        buffer.write('&subcollection=$subcollection');
      }
    }
    return buffer.toString();
  }

  Future<void> _next() async {
    final result = await context.push<String>(_flowRoute());
    if (!mounted) return;
    if (result != CreateFlowResult.kept) {
      // The draft ended in the flow (saved, discarded, or uploading in the
      // background) — start a clean one for the next thing.
      setState(() {
        _draftId = _uuid.v4();
        _uploads = ref.read(mediaUploadControllerProvider(_draftId));
      });
    } else {
      setState(() {});
    }
  }

  void _onIntent(_CreateIntent intent) {
    switch (intent) {
      case _CreateIntent.item:
        break;
      case _CreateIntent.group:
        unawaited(context.push<void>('/create/subcollection'));
      case _CreateIntent.shelf:
        unawaited(context.push<void>('/create/collection'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final uploads = _uploads;

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Create'),
      bottomBar: ListenableBuilder(
        listenable: uploads,
        builder: (context, _) => CreateSaveBar(
          label: uploads.isEmpty
              ? 'Pick a photo to start'
              : 'Frame ${plural(uploads.length, 'photo')}',
          enabled: !uploads.isEmpty,
          note: uploads.isEmpty
              ? 'Shoot it or pick it — filing takes ten seconds at the end.'
              : null,
          onSave: _next,
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s2,
              Space.s4,
              Space.s3,
            ),
            child: Row(
              children: <Widget>[
                for (final intent in _CreateIntent.values) ...<Widget>[
                  KChip(
                    label: intent.label,
                    icon: intent.icon,
                    selected: intent == _CreateIntent.item,
                    onTap: () => _onIntent(intent),
                  ),
                  const SizedBox(width: Space.s2),
                ],
                const Spacer(),
                ListenableBuilder(
                  listenable: uploads,
                  builder: (context, _) => Text(
                    '${uploads.length}/${MediaUploadController.maxPhotos}',
                    style:
                        context.kt.count.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: PickGrid(controller: uploads)),
        ],
      ),
    );
  }
}
