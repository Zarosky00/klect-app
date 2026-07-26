import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// One owner-only row inside the peek.
@immutable
class QuickOwnerAction {
  /// Creates an owner action.
  const QuickOwnerAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  /// Glyph.
  final IconData icon;

  /// Row label.
  final String label;

  /// Fired after the sheet closes, so the caller can push a route safely.
  final VoidCallback onSelected;

  /// Renders in `semantic.danger`.
  final bool destructive;
}

/// **The long-press peek** from `docs/DESIGN_SYSTEM.md` §4.
///
/// Like · save · repost · share · report, one gesture away, with the owner's
/// management actions underneath. Nothing here is ever a visible row of buttons
/// at rest — that is the whole point.
abstract final class QuickActionsSheet {
  /// Opens the peek for [entity].
  static Future<void> show(
    BuildContext context, {
    required EntityRef entity,
    required String title,
    InteractionState? seed,
    bool isOwner = false,
    List<QuickOwnerAction> ownerActions = const <QuickOwnerAction>[],
  }) async {
    unawaited(HapticFeedback.mediumImpact());
    final chosen = await KSheet.show<QuickOwnerAction>(
      context: context,
      title: title,
      builder: (sheetContext) => _QuickActionsBody(
        entity: entity,
        title: title,
        seed: seed,
        isOwner: isOwner,
        ownerActions: ownerActions,
      ),
    );
    chosen?.onSelected();
  }
}

/// The owner's management menu, opened from the header overflow.
///
/// Distinct from the peek: the peek is about *reacting* to something, this is
/// about *changing* it. Both are hidden until asked for.
abstract final class OwnerMenuSheet {
  /// Opens the menu and runs whichever action the user chose, after the sheet
  /// has closed so the callback can safely push a route.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<QuickOwnerAction> actions,
  }) async {
    final chosen = await KSheet.show<QuickOwnerAction>(
      context: context,
      title: title,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final action in actions)
            _OwnerRow(
              action: action,
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
        ],
      ),
    );
    chosen?.onSelected();
  }
}

class _QuickActionsBody extends ConsumerStatefulWidget {
  const _QuickActionsBody({
    required this.entity,
    required this.title,
    required this.seed,
    required this.isOwner,
    required this.ownerActions,
  });

  final EntityRef entity;
  final String title;
  final InteractionState? seed;
  final bool isOwner;
  final List<QuickOwnerAction> ownerActions;

  @override
  ConsumerState<_QuickActionsBody> createState() => _QuickActionsBodyState();
}

class _QuickActionsBodyState extends ConsumerState<_QuickActionsBody> {
  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null) {
      ref.read(interactionSeedStoreProvider).put(widget.entity, seed);
    }
    unawaited(_hydrateViewerState());
  }

  /// A card row carries counters but not the viewer's own like/save/repost
  /// booleans, so the peek confirms them against `get_closeup` the moment it
  /// opens. [InteractionController.hydrate] leaves any action with an RPC in
  /// flight alone, so this can never clobber a tap the user already made.
  Future<void> _hydrateViewerState() async {
    try {
      final closeup = await ref
          .read(klectApiProvider)
          .getCloseup(widget.entity.type, widget.entity.id);
      if (!mounted) return;
      _controller.hydrateFromCloseup(closeup);
    } on KlectError {
      // The peek still works from the seeded counters.
    }
  }

  InteractionController get _controller =>
      ref.read(interactionProvider(widget.entity).notifier);

  Future<void> _share() async {
    // Take the navigator before popping — the chooser outlives this sheet.
    final navigator = Navigator.of(context);
    final entity = widget.entity;
    final title = widget.title;
    await navigator.maybePop();
    final host = navigator.context;
    if (!host.mounted) return;
    await KShareSheet.show(
      host,
      entityType: entity.type,
      entityId: entity.id,
      title: title,
    );
  }

  void _report() {
    Navigator.of(context).maybePop();
    unawaited(
      KReportSheet.showForEntity(
        context,
        type: widget.entity.type,
        entityId: widget.entity.id,
        subjectLabel: widget.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final state = ref.watch(interactionProvider(widget.entity));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _PeekAction(
              icon: Icons.favorite_border_rounded,
              activeIcon: Icons.favorite_rounded,
              label: 'Like',
              active: state.liked,
              color: colors.actionLike,
              onTap: _controller.toggleLike,
            ),
            _PeekAction(
              icon: Icons.bookmark_border_rounded,
              activeIcon: Icons.bookmark_rounded,
              label: 'Save',
              active: state.saved,
              color: colors.actionSave,
              onTap: () => _controller.toggleSave(),
            ),
            _PeekAction(
              icon: Icons.repeat_rounded,
              activeIcon: Icons.repeat_on_rounded,
              label: 'Repost',
              active: state.reposted,
              color: colors.actionRepost,
              onTap: () => _controller.toggleRepost(),
            ),
            _PeekAction(
              icon: Icons.ios_share_rounded,
              activeIcon: Icons.ios_share_rounded,
              label: 'Share',
              active: false,
              color: colors.actionShare,
              onTap: _share,
            ),
            _PeekAction(
              icon: Icons.flag_outlined,
              activeIcon: Icons.flag_rounded,
              label: 'Report',
              active: false,
              color: colors.semanticDanger,
              onTap: _report,
            ),
          ],
        ),
        if (widget.isOwner && widget.ownerActions.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.s4),
          Divider(color: colors.borderSubtle, height: Strokes.hairline),
          const SizedBox(height: Space.s2),
          for (final action in widget.ownerActions)
            _OwnerRow(
              action: action,
              onTap: () => Navigator.of(context).pop(action),
            ),
        ],
      ],
    );
  }
}

class _PeekAction extends StatelessWidget {
  const _PeekAction({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      semanticLabel: label,
      enforceMinTapTarget: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedContainer(
            duration: KMotion.duration(context, KDurations.fast),
            curve: KCurves.emphasized,
            width: Space.s14,
            height: Space.s14,
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: Opacities.ghost)
                  : colors.surface3,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? color : colors.borderSubtle,
                width: active ? Strokes.thick : Strokes.thin,
              ),
            ),
            child: Icon(
              active ? activeIcon : icon,
              size: Space.s6,
              color: active ? color : colors.textSecondary,
            ),
          ),
          const SizedBox(height: Space.s15),
          Text(
            label,
            style: context.kt.micro.copyWith(
              color: active ? color : colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.action, required this.onTap});

  final QuickOwnerAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = action.destructive
        ? colors.semanticDanger
        : colors.textPrimary;
    return KPressable(
      onTap: onTap,
      semanticLabel: action.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Row(
          children: <Widget>[
            Icon(action.icon, size: Space.s5, color: tint),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                action.label,
                style: context.kt.body.copyWith(color: tint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
