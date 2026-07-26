import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../profile/person_row.dart';
import '../../profile/profile_queries.dart';

/// Multi-select people picker for group membership.
///
/// Zero-state is the people the viewer follows (the existing
/// `followingProvider` social query); typing searches everyone on KLECT
/// through `search_all`, same as the search tab. The current selection rides
/// on top as removable chips.
///
/// The widget is controlled: the parent owns [selected] and flips membership
/// in [onToggle], which is what lets the new-group flow keep its selection
/// while moving between steps, and lets callers enforce the member cap.
class MemberPicker extends ConsumerStatefulWidget {
  /// Creates a member picker.
  const MemberPicker({
    required this.selected,
    required this.onToggle,
    super.key,
    this.excludeIds = const <String>{},
  });

  /// The current selection, keyed by profile id, in pick order.
  final Map<String, Profile> selected;

  /// Adds or removes one person from the selection.
  final void Function(Profile profile) onToggle;

  /// People never offered — existing group members, typically.
  final Set<String> excludeIds;

  @override
  ConsumerState<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends ConsumerState<MemberPicker> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  String _term = '';
  bool _searching = false;
  List<Profile> _results = const <Profile>[];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(KDurations.medium, () => unawaited(_search(value)));
  }

  Future<void> _search(String value) async {
    final trimmed = value.trim();
    if (!mounted) return;
    setState(() {
      _term = trimmed;
      _results = const <Profile>[];
      _searching = trimmed.isNotEmpty;
    });
    if (trimmed.isEmpty) return;
    try {
      final results = await ref.read(klectApiProvider).searchAll(trimmed);
      if (!mounted || _term != trimmed) return;
      setState(() {
        _results = results.people;
        _searching = false;
      });
    } on KlectError catch (error) {
      if (!mounted || _term != trimmed) return;
      setState(() => _searching = false);
      KToast.error(context, error.message);
    }
  }

  bool _pickable(Profile profile, String? me) =>
      profile.id != me && !widget.excludeIds.contains(profile.id);

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.selected.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: <Widget>[
              for (final profile in widget.selected.values)
                KChip(
                  label: profile.name,
                  selected: true,
                  onRemove: () => widget.onToggle(profile),
                ),
            ],
          ),
          const SizedBox(height: Space.s3),
        ],
        KTextField(
          controller: _query,
          hint: 'Search collectors',
          prefixIcon: Icons.search_rounded,
          onChanged: _onQueryChanged,
        ),
        const SizedBox(height: Space.s3),
        Expanded(child: _buildList(me)),
      ],
    );
  }

  Widget _buildList(String? me) {
    if (_searching) {
      return const KSkeletonList(rows: 4, showMedia: false);
    }
    if (_term.isNotEmpty) {
      final people = <Profile>[
        for (final profile in _results)
          if (_pickable(profile, me)) profile,
      ];
      if (people.isEmpty) {
        return const KEmptyState(
          title: 'Nobody found',
          message: 'Try a different name or handle.',
          icon: Icons.person_search_rounded,
          compact: true,
        );
      }
      return _people(people);
    }

    if (me == null) return const SizedBox.shrink();
    final following = ref.watch(followingProvider(me));
    return following.when(
      loading: () => const KSkeletonList(rows: 4, showMedia: false),
      error: (error, _) => KErrorState(
        error: error,
        onRetry: () => ref.invalidate(followingProvider(me)),
      ),
      data: (profiles) {
        final people = <Profile>[
          for (final profile in profiles)
            if (_pickable(profile, me)) profile,
        ];
        if (people.isEmpty) {
          return const KEmptyState(
            title: 'Nobody to suggest',
            message: 'You are not following anyone who could join — '
                'search everyone on KLECT above.',
            icon: Icons.group_outlined,
            compact: true,
          );
        }
        return _people(people);
      },
    );
  }

  Widget _people(List<Profile> people) {
    final colors = context.kc;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: people.length,
      itemBuilder: (context, index) {
        final profile = people[index];
        final isSelected = widget.selected.containsKey(profile.id);
        return PersonRow(
          profile: profile,
          dense: true,
          showFollow: false,
          onTap: () => widget.onToggle(profile),
          trailing: Icon(
            isSelected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: Space.s6,
            color: isSelected ? colors.accentDefault : colors.textTertiary,
          ),
        );
      },
    );
  }
}

/// The member picker as a sheet — the "add people to this group" flow.
abstract final class MemberPickerSheet {
  /// Opens the picker and resolves with the chosen people, or null.
  static Future<List<Profile>?> show(
    BuildContext context, {
    String title = 'Add people',
    String confirmLabel = 'Add',
    Set<String> excludeIds = const <String>{},
    int maxSelectable = 64,
  }) =>
      KSheet.show<List<Profile>>(
        context: context,
        title: title,
        maxHeightFraction: 0.85,
        builder: (_) => _MemberPickerSheetBody(
          confirmLabel: confirmLabel,
          excludeIds: excludeIds,
          maxSelectable: maxSelectable,
        ),
      );
}

class _MemberPickerSheetBody extends StatefulWidget {
  const _MemberPickerSheetBody({
    required this.confirmLabel,
    required this.excludeIds,
    required this.maxSelectable,
  });

  final String confirmLabel;
  final Set<String> excludeIds;
  final int maxSelectable;

  @override
  State<_MemberPickerSheetBody> createState() => _MemberPickerSheetBodyState();
}

class _MemberPickerSheetBodyState extends State<_MemberPickerSheetBody> {
  final Map<String, Profile> _selected = <String, Profile>{};

  void _toggle(Profile profile) {
    if (!_selected.containsKey(profile.id) &&
        _selected.length >= widget.maxSelectable) {
      KToast.error(
        context,
        widget.maxSelectable <= 0
            ? 'This group is already full.'
            : 'Only ${widget.maxSelectable} more '
                '${widget.maxSelectable == 1 ? 'person fits' : 'people fit'} '
                'in this group.',
      );
      return;
    }
    setState(() {
      if (_selected.remove(profile.id) == null) {
        _selected[profile.id] = profile;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The sheet holds a text field; keep it above the keyboard.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: MemberPicker(
                selected: _selected,
                onToggle: _toggle,
                excludeIds: widget.excludeIds,
              ),
            ),
            const SizedBox(height: Space.s3),
            KButton(
              label: _selected.length > 1
                  ? '${widget.confirmLabel} (${_selected.length})'
                  : widget.confirmLabel,
              icon: Icons.person_add_alt_rounded,
              expand: true,
              onPressed: _selected.isEmpty
                  ? null
                  : () =>
                      Navigator.of(context).pop(<Profile>[..._selected.values]),
            ),
          ],
        ),
      ),
    );
  }
}
