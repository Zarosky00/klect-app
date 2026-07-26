import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/fill_viewport.dart';
import 'settings_widgets.dart';

/// Name, handle, email, password.
///
/// The identity fields write to `profiles`; email and password go through
/// Supabase Auth, which is the same path `features/auth/` already uses — the
/// PostgREST surface never sees credentials.
class AccountSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState
    extends ConsumerState<AccountSettingsScreen> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _username = TextEditingController();
  Timer? _usernameDebounce;

  bool _seeded = false;
  bool _busy = false;
  bool _checkingUsername = false;
  String? _nameError;
  String? _usernameError;

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _displayName.dispose();
    _username.dispose();
    super.dispose();
  }

  void _seed(Profile me) {
    if (_seeded) return;
    _seeded = true;
    _displayName.text = me.displayName ?? '';
    _username.text = me.username;
  }

  bool _dirty(Profile me) =>
      _displayName.text.trim() != (me.displayName ?? '') ||
      _username.text.trim().toLowerCase() != me.username;

  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    setState(() => _usernameError = null);
    _usernameDebounce = Timer(KDurations.deliberate, () {
      unawaited(_checkUsername());
    });
  }

  Future<bool> _checkUsername() async {
    final value = _username.text.trim().toLowerCase();
    if (!_usernamePattern.hasMatch(value)) {
      setState(
        () => _usernameError =
            '3–20 characters: lowercase letters, numbers, underscore.',
      );
      return false;
    }
    setState(() => _checkingUsername = true);
    try {
      final free = await ref.read(klectApiProvider).isUsernameAvailable(value);
      if (!mounted) return false;
      setState(() => _usernameError = free ? null : 'That handle is taken.');
      return free;
    } on KlectError catch (error) {
      if (!mounted) return false;
      setState(() => _usernameError = error.message);
      return false;
    } finally {
      if (mounted) setState(() => _checkingUsername = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _displayName.text.trim();
    setState(() => _nameError = name.length >= 2 ? null : 'Name is required.');
    final usernameOk = await _checkUsername();
    if (!mounted || _nameError != null || !usernameOk) return;

    setState(() => _busy = true);
    try {
      await ref.read(klectApiProvider).updateMyProfile(<String, dynamic>{
        'display_name': name,
        'username': _username.text.trim().toLowerCase(),
      });
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      KToast.success(context, 'Account updated.');
    } on KlectError catch (error) {
      if (mounted) KToast.error(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final profile = ref.watch(myProfileProvider);
    final email = ref.watch(sessionProvider)?.user.email;

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Account', showBack: true),
      body: profile.when(
        loading: () => const FillViewport(
          child: KSkeletonList(rows: 4, showMedia: false),
        ),
        error: (error, _) => FillViewport(
          child: KErrorState(
            error: error,
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
        ),
        data: (me) {
          if (me == null) {
            return const FillViewport(
              child: KEmptyState(
                title: 'Not signed in',
                message: 'There is no account to show.',
                icon: Icons.lock_outline_rounded,
              ),
            );
          }
          _seed(me);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s4,
              Space.s5,
              Space.s12,
            ),
            children: <Widget>[
              const SettingsSectionHeader(label: 'Identity'),
              KTextField(
                controller: _displayName,
                label: 'Display name',
                prefixIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 40,
                errorText: _nameError,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Space.s4),
              KTextField(
                controller: _username,
                label: 'Handle',
                prefixIcon: Icons.alternate_email_rounded,
                textInputAction: TextInputAction.done,
                maxLength: 20,
                errorText: _usernameError,
                helper: 'Changing this changes every link to your profile.',
                onChanged: (value) {
                  setState(() {});
                  _onUsernameChanged(value);
                },
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
                ],
                suffix: _checkingUsername
                    ? const Padding(
                        padding: EdgeInsets.all(Space.s3),
                        child: SizedBox(
                          width: Space.s4,
                          height: Space.s4,
                          child: CircularProgressIndicator(
                            strokeWidth: Strokes.thick,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: Space.s4),
              KButton(
                label: 'Save changes',
                expand: true,
                busy: _busy,
                onPressed: _dirty(me) ? _save : null,
              ),
              SettingsSection(
                header: 'Profile',
                children: <Widget>[
                  SettingsRow(
                    icon: Icons.image_outlined,
                    title: 'Banner, avatar, bio and links',
                    subtitle: 'The parts of you people actually see.',
                    onTap: () => Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (routeContext) =>
                            EditProfileScreen(profile: me),
                      ),
                    ),
                  ),
                ],
              ),
              SettingsSection(
                header: 'Sign-in',
                note: 'Changing either of these sends a confirmation to your '
                    'inbox before it takes effect.',
                children: <Widget>[
                  SettingsRow(
                    icon: Icons.mail_outline_rounded,
                    title: 'Email',
                    value: email == null ? 'Unknown' : _mask(email),
                    onTap: () =>
                        _ChangeEmailSheet.show(context, current: email),
                  ),
                  SettingsRow(
                    icon: Icons.key_outlined,
                    title: 'Password',
                    subtitle: 'Set a new one.',
                    onTap: () => _ChangePasswordSheet.show(context),
                  ),
                ],
              ),
              const SizedBox(height: Space.s6),
              Text(
                'Account id ${me.id}',
                style: context.kt.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          );
        },
      ),
    );
  }

  /// `a•••@example.com` — enough to recognise, not enough to shoulder-surf.
  static String _mask(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}•••${email.substring(at)}';
  }
}

class _ChangeEmailSheet extends ConsumerStatefulWidget {
  const _ChangeEmailSheet({this.current});

  final String? current;

  static Future<void> show(BuildContext context, {String? current}) =>
      KSheet.show<void>(
        context: context,
        title: 'Change email',
        builder: (sheetContext) => _ChangeEmailSheet(current: current),
      );

  @override
  ConsumerState<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends ConsumerState<_ChangeEmailSheet> {
  final TextEditingController _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _email.text.trim();
    if (!next.contains('@') || next.length < 5) {
      setState(() => _error = 'That does not look like an email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supabaseClientProvider).auth.updateUser(
            UserAttributes(email: next),
          );
      if (!mounted) return;
      KToast.show(
        context,
        'Confirm the change from the link we just sent to $next.',
        kind: KToastKind.success,
        icon: Icons.mark_email_read_outlined,
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = KlectError.from(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.current == null
              ? 'Enter the address you want to sign in with.'
              : 'You currently sign in with ${widget.current}.',
          style: context.kt.callout.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s4),
        KTextField(
          controller: _email,
          label: 'New email',
          hint: 'you@example.com',
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          autofocus: true,
          errorText: _error,
        ),
        const SizedBox(height: Space.s5),
        KButton(
          label: 'Send confirmation',
          expand: true,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  /// The floor the auth service enforces.
  static const int minimumLength = 8;

  static Future<void> show(BuildContext context) => KSheet.show<void>(
        context: context,
        title: 'Change password',
        builder: (sheetContext) => const _ChangePasswordSheet(),
      );

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _password.text;
    if (value.length < _ChangePasswordSheet.minimumLength) {
      setState(
        () => _error = 'At least '
            '${_ChangePasswordSheet.minimumLength} characters.',
      );
      return;
    }
    if (value != _confirm.text) {
      setState(() => _error = 'Those do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok =
        await ref.read(authControllerProvider.notifier).updatePassword(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      KToast.success(context, 'Password updated.');
      Navigator.of(context).pop();
    } else {
      setState(
        () => _error =
            ref.read(authControllerProvider).error?.message ?? 'That failed.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KTextField(
            controller: _password,
            label: 'New password',
            obscureText: _obscure,
            autofocus: true,
            autofillHints: const <String>[AutofillHints.newPassword],
            errorText: _error,
            suffix: KIconButton(
              icon: _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              semanticLabel: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: _confirm,
            label: 'Confirm password',
            obscureText: _obscure,
            autofillHints: const <String>[AutofillHints.newPassword],
          ),
          const SizedBox(height: Space.s5),
          KButton(
            label: 'Update password',
            expand: true,
            busy: _busy,
            onPressed: _submit,
          ),
        ],
      );
}
