import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'auth_controller.dart';

/// Email + password sign in.
class SignInScreen extends ConsumerStatefulWidget {
  /// Creates the sign-in screen.
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;

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
      _emailError = email.contains('@') && email.length > 3
          ? null
          : 'Enter the email you signed up with.';
      _passwordError = password.isEmpty ? 'Enter your password.' : null;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).signIn(
          email: _email.text,
          password: _password.text,
        );
    // Navigation is the router's job: the redirect guard reacts to the session.
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
                    Text('Welcome back', style: context.kt.display2),
                    const SizedBox(height: Space.s2),
                    Text(
                      'Your shelves are where you left them.',
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
                      hint: '••••••••',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
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
                    const SizedBox(height: Space.s2),
                    Align(
                      alignment: Alignment.centerRight,
                      child: KButton(
                        label: 'Forgot password?',
                        variant: KButtonVariant.ghost,
                        size: KButtonSize.small,
                        onPressed: () => context.push('/forgot-password'),
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
                      label: 'Sign in',
                      expand: true,
                      size: KButtonSize.large,
                      busy: status.busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: Space.s5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          'New here?',
                          style: context.kt.callout
                              .copyWith(color: colors.textSecondary),
                        ),
                        KButton(
                          label: 'Create an account',
                          variant: KButtonVariant.ghost,
                          size: KButtonSize.small,
                          onPressed: () {
                            ref.read(authControllerProvider.notifier).clear();
                            context.go('/signup');
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
