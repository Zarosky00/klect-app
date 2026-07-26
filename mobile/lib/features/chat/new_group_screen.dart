import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import 'chat_api.dart';
import 'group_errors.dart';
import 'widgets/group_avatar.dart';
import 'widgets/member_picker.dart';

/// `create_group` caps the member array at this, owner excluded.
const int _maxMembers = 64;

/// The two-step "New group" flow.
///
/// Step one picks the people (those you follow, plus anyone via search);
/// step two names the group. `create_group` then makes the caller the owner,
/// writes the memberships and the birth system message in one transaction,
/// and this screen replaces itself with the new thread.
class NewGroupScreen extends ConsumerStatefulWidget {
  /// Creates the flow.
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final Map<String, Profile> _selected = <String, Profile>{};
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  bool _naming = false;
  bool _creating = false;
  bool _titleMissing = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _toggle(Profile profile) {
    if (!_selected.containsKey(profile.id) && _selected.length >= _maxMembers) {
      KToast.error(context, 'Groups max out at $_maxMembers people plus you.');
      return;
    }
    setState(() {
      if (_selected.remove(profile.id) == null) {
        _selected[profile.id] = profile;
      }
    });
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleMissing = true);
      return;
    }
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final description = _description.text.trim();
      final conversationId = await ref.read(chatApiProvider).createGroup(
            title: title,
            memberIds: <String>[..._selected.keys],
            description: description.isEmpty ? null : description,
          );
      if (!mounted) return;
      // The inbox adopts the new conversation over realtime; replacing this
      // route means back lands on the inbox, not on a spent form.
      context.pushReplacement('${Routes.messages}/$conversationId');
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() => _creating = false);
      KToast.error(context, groupErrorCopy(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KScaffold(
      // The Android back gesture steps the flow backwards before it leaves.
      canPop: !_naming,
      onPopInvoked: (didPop, _) {
        if (!didPop) setState(() => _naming = false);
      },
      appBar: KFixedAppBar(
        title: _naming ? 'Name the group' : 'New group',
        showBack: true,
        onBack: () {
          if (_naming) {
            setState(() => _naming = false);
          } else {
            Navigator.of(context).maybePop();
          }
        },
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s4,
          Space.s4,
        ),
        child: AnimatedSwitcher(
          duration: KMotion.duration(context, KDurations.base),
          switchInCurve: Curves_.standard,
          switchOutCurve: Curves_.standard,
          child: _naming ? _buildDetailsStep() : _buildMembersStep(),
        ),
      ),
    );
  }

  Widget _buildMembersStep() {
    return Column(
      key: const ValueKey<String>('members'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: MemberPicker(selected: _selected, onToggle: _toggle),
        ),
        const SizedBox(height: Space.s3),
        KButton(
          label: _selected.isEmpty
              ? 'Pick at least one person'
              : 'Next · ${_selected.length} '
                  '${_selected.length == 1 ? 'person' : 'people'}',
          trailingIcon: Icons.arrow_forward_rounded,
          expand: true,
          onPressed:
              _selected.isEmpty ? null : () => setState(() => _naming = true),
        ),
      ],
    );
  }

  Widget _buildDetailsStep() {
    final colors = context.kc;
    return ListView(
      key: const ValueKey<String>('details'),
      children: <Widget>[
        const SizedBox(height: Space.s4),
        const Center(child: GroupAvatar(size: Space.s20)),
        const SizedBox(height: Space.s6),
        KTextField(
          controller: _title,
          label: 'Group name',
          hint: 'What is this group about?',
          maxLength: 80,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          errorText: _titleMissing ? 'Give the group a name first.' : null,
          onChanged: (_) {
            if (_titleMissing) setState(() => _titleMissing = false);
          },
          onSubmitted: (_) => _create(),
        ),
        const SizedBox(height: Space.s4),
        KTextField(
          controller: _description,
          label: 'Description',
          hint: 'Optional — what belongs in here',
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: Space.s6),
        Text(
          'Starting with',
          style: context.kt.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: <Widget>[
            for (final profile in _selected.values)
              KChip(label: profile.name),
          ],
        ),
        const SizedBox(height: Space.s6),
        KButton(
          label: 'Create group',
          icon: Icons.group_add_rounded,
          expand: true,
          busy: _creating,
          onPressed: _creating ? null : _create,
        ),
      ],
    );
  }
}
