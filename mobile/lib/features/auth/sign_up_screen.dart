import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'auth_controller.dart';

/// Create an account. Display name, username and interests come next, in
/// onboarding — this screen asks for the two things auth actually needs.
class SignUpScreen extends ConsumerStatefulWidget {
  /// Creates the sign-up screen.
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;

  /// Supabase's own floor; the dashboard's leaked-password check runs on top.
  static const int _minPasswordLength = 8;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _emailError =
          email.contains('@') && email.length > 3 ? null : 'Enter a real email.';
      _passwordError = password.length >= _minPasswordLength
          ? null
          : 'At least $_minPasswordLength characters.';
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).signUp(
          email: _email.text,
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final status = ref.watch(authControllerProvider);

    return KScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s6,
              vertical: Space.s10,
            ),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: Layout.readableMaxWidth),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('Start collecting', style: context.kt.display2),
                    const SizedBox(height: Space.s2),
                    Text(
                      'One account, unlimited shelves.',
                      style: context.kt.body
                          .copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: Space.s8),
                    KTextField(
                      controller: _email,
                      label: 'Email',
                      hint: 'you@example.com',
                      prefixIcon: Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.email],
                      errorText: _emailError,
                      autofocus: true,
                    ),
                    const SizedBox(height: Space.s4),
                    KTextField(
                      controller: _password,
                      label: 'Password',
                      hint: 'At least $_minPasswordLength characters',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.newPassword],
                      errorText: _passwordError,
                      onSubmitted: (_) => _submit(),
                      suffix: KIconButton(
                        icon: _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        semanticLabel:
                            _obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    if (status.error != null) ...<Widget>[
                      const SizedBox(height: Space.s4),
                      KInlineError(message: status.error!.message),
                    ],
                    if (status.message != null) ...<Widget>[
                      const SizedBox(height: Space.s4),
                      Text(
                        status.message!,
                        style: context.kt.callout
                            .copyWith(color: colors.semanticSuccess),
                      ),
                    ],
                    const SizedBox(height: Space.s6),
                    KButton(
                      label: 'Create account',
                      expand: true,
                      size: KButtonSize.large,
                      busy: status.busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: Space.s4),
                    Text(
                      'By continuing you agree to keep it civil. '
                      'Everything is reportable, and we act on reports.',
                      textAlign: TextAlign.center,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                    const SizedBox(height: Space.s5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          'Already collecting?',
                          style: context.kt.callout
                              .copyWith(color: colors.textSecondary),
                        ),
                        KButton(
                          label: 'Sign in',
                          variant: KButtonVariant.ghost,
                          size: KButtonSize.small,
                          onPressed: () {
                            ref.read(authControllerProvider.notifier).clear();
                            context.go('/signin');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
