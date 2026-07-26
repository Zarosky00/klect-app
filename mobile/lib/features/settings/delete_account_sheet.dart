import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';

/// Deleting an account, with a confirmation that is actually a confirmation.
///
/// What this does, exactly — the sheet says the same thing:
///  * every collection you own is deleted, which cascades through its
///    subcollections, items and photos and purges the polymorphic likes,
///    saves, reposts, comments, views and tags attached to all of them;
///  * your profile is emptied and set to private, and messaging is closed;
///  * you are signed out.
///
/// The `auth.users` row itself can only be removed with the service-role key,
/// which is deliberately absent from this app — that final step belongs to a
/// server-side `delete_account` RPC or edge function. Until that exists the
/// sheet says so rather than implying otherwise.
abstract final class DeleteAccountFlow {
  /// Opens the deletion sheet.
  static Future<void> start(BuildContext context, {required Profile profile}) =>
      KSheet.show<void>(
        context: context,
        title: 'Delete account',
        isDismissible: false,
        builder: (sheetContext) => _DeleteAccountBody(profile: profile),
      );
}

class _DeleteAccountBody extends ConsumerStatefulWidget {
  const _DeleteAccountBody({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_DeleteAccountBody> createState() => _DeleteAccountBodyState();
}

class _DeleteAccountBodyState extends ConsumerState<_DeleteAccountBody> {
  final TextEditingController _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;
  String _progress = '';

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  bool get _canDelete =>
      _confirmation.text.trim().toLowerCase() ==
      widget.profile.username.toLowerCase();

  Future<void> _delete() async {
    if (_busy || !_canDelete) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Deleting your collections…';
    });

    final api = ref.read(klectApiProvider);
    try {
      final collections = await api.fetchCollections(widget.profile.id);
      for (var index = 0; index < collections.length; index++) {
        if (!mounted) return;
        setState(
          () => _progress =
              'Deleting ${index + 1} of ${collections.length} collections…',
        );
        await api.deleteCollection(collections[index].id);
      }

      if (mounted) setState(() => _progress = 'Clearing your profile…');
      await api.updateMyProfile(<String, dynamic>{
        'display_name': 'Deleted account',
        'bio': null,
        'location': null,
        'website': null,
        'avatar_path': null,
        'banner_path': null,
        'account_visibility': AccountVisibility.private.wire,
        'allow_messages_from': AllowMessagesFrom.nobody.wire,
        'show_similarity': false,
      });

      if (mounted) setState(() => _progress = 'Signing you out…');
      await ref.read(authControllerProvider.notifier).signOut();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
        _progress = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: colors.semanticDangerSubtle,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: colors.semanticDanger,
              width: Strokes.thin,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'This cannot be undone.',
                style: context.kt.bodyStrong
                    .copyWith(color: colors.semanticDanger),
              ),
              const SizedBox(height: Space.s2),
              _Bullet(
                text: '${widget.profile.collectionCount} collections and '
                    '${widget.profile.itemCount} items are deleted, along with '
                    'every photo, comment, like and save attached to them.',
              ),
              const _Bullet(
                text: 'Your profile is emptied, set to private, and messaging '
                    'is closed.',
              ),
              const _Bullet(text: 'You are signed out on every device.'),
              const _Bullet(
                text: 'Removing the sign-in record itself needs our team — '
                    'the app never holds the key that can do it.',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s5),
        KTextField(
          controller: _confirmation,
          label: 'Type ${widget.profile.username} to confirm',
          hint: widget.profile.username,
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        if (_progress.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.s4),
          Row(
            children: <Widget>[
              const SizedBox(
                width: Space.s4,
                height: Space.s4,
                child: CircularProgressIndicator(strokeWidth: Strokes.thick),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Text(
                  _progress,
                  style: context.kt.caption
                      .copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: Space.s4),
          KInlineError(message: _error!),
        ],
        const SizedBox(height: Space.s5),
        Row(
          children: <Widget>[
            Expanded(
              child: KButton(
                label: 'Keep my account',
                variant: KButtonVariant.secondary,
                expand: true,
                onPressed:
                    _busy ? null : () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: KButton(
                label: 'Delete',
                variant: KButtonVariant.danger,
                expand: true,
                busy: _busy,
                onPressed: _canDelete ? _delete : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '·',
            style: context.kt.body.copyWith(color: colors.semanticDanger),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(
              text,
              style: context.kt.caption.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
