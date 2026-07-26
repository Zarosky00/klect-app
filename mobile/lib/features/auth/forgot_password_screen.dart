import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'auth_controller.dart';

/// Sends the password-reset email.
///
/// The copy never confirms whether an address has an account — that would be
/// an account-enumeration oracle.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  /// Creates the forgot-password screen.
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final TextEditingController _email = TextEditingController();
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _emailError = email.contains('@') && email.length > 3
          ? null
          : 'Enter the email you signed up with.';
    });
    if (_emailError != null) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final status = ref.watch(authControllerProvider);

    return KScaffold(
      appBar: const KFixedAppBar(showBack: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s6,
          vertical: Space.s6,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.readableMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Reset your password', style: context.kt.display3),
              const SizedBox(height: Space.s2),
              Text(
                'We will email you a link. Follow it and pick a new password.',
                style: context.kt.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.s8),
              KTextField(
                controller: _email,
                label: 'Email',
                hint: 'you@example.com',
                prefixIcon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.email],
                errorText: _emailError,
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
              if (status.error != null) ...<Widget>[
                const SizedBox(height: Space.s4),
                KInlineError(message: status.error!.message),
              ],
              if (status.message != null) ...<Widget>[
                const SizedBox(height: Space.s4),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: Space.s5,
                      color: colors.semanticSuccess,
                    ),
                    const SizedBox(width: Space.s2),
                    Expanded(
                      child: Text(
                        status.message!,
                        style: context.kt.callout
                            .copyWith(color: colors.semanticSuccess),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Space.s6),
              KButton(
                label: 'Send reset link',
                expand: true,
                size: KButtonSize.large,
                busy: status.busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
