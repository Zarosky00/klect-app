import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'auth_controller.dart';

/// The interest templates offered in step 2.
final onboardingTemplatesProvider = FutureProvider<List<CollectionTemplate>>(
  (ref) => ref.watch(klectApiProvider).fetchCollectionTemplates(),
  name: 'onboardingTemplates',
);

/// The collectors offered in step 3.
final suggestedCollectorsProvider = FutureProvider<List<Profile>>(
  (ref) => ref.watch(klectApiProvider).fetchSuggestedCollectors(),
  name: 'suggestedCollectors',
);

/// Three steps, then the app.
///
/// 1. who you are — display name + username (checked for availability);
/// 2. what you collect — pick at least three interest templates, each of which
///    becomes a real collection so the account is never an empty shell;
/// 3. who to watch — follow a few collectors.
///
/// Finishing stamps `profiles.onboarded_at`, which is what the router's guard
/// reads to stop sending the user back here.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Creates the onboarding flow.
  const OnboardingScreen({super.key});

  /// How many interests must be picked before step 2 can be left.
  static const int minimumInterests = 3;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final Set<String> _interests = <String>{};
  final Set<String> _follows = <String>{};

  /// Template ids whose collection was already created, so a retry after a
  /// mid-flight failure never duplicates a shelf.
  final Set<String> _createdTemplates = <String>{};

  /// Users already followed by a previous attempt, for the same reason.
  final Set<String> _followed = <String>{};

  int _step = 0;
  bool _busy = false;
  bool _checkingUsername = false;
  String? _nameError;
  String? _usernameError;
  String? _submitError;
  Timer? _usernameDebounce;

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _displayName.dispose();
    _username.dispose();
    super.dispose();
  }

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

  Future<void> _next() async {
    if (_step == 0) {
      final name = _displayName.text.trim();
      setState(
        () =>
            _nameError = name.length >= 2 ? null : 'Tell us what to call you.',
      );
      final usernameOk = await _checkUsername();
      if (!mounted || _nameError != null || !usernameOk) return;
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      if (_interests.length < OnboardingScreen.minimumInterests) return;
      setState(() => _step = 2);
      return;
    }
    await _finish();
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  /// Finishes onboarding. **Idempotent**: created template ids and applied
  /// follows are tracked, so a retry after a partial failure only performs
  /// what is still missing — no duplicate shelves, no un-followed follows.
  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _submitError = null;
    });
    final api = ref.read(klectApiProvider);
    try {
      await api.completeOnboarding(
        displayName: _displayName.text.trim(),
        username: _username.text.trim().toLowerCase(),
      );

      // Each chosen interest becomes a real collection, so the new account
      // opens onto shelves rather than an empty state. The creations are
      // independent of each other, so they run in parallel.
      final templates =
          ref.read(onboardingTemplatesProvider).value ??
          const <CollectionTemplate>[];
      await Future.wait(<Future<void>>[
        for (final template in templates)
          if (_interests.contains(template.id) &&
              !_createdTemplates.contains(template.id))
            api
                .createCollection(
                  name: template.name,
                  description: template.description,
                  templateId: template.id,
                  accentColor: template.accentColor,
                )
                .then((_) => _createdTemplates.add(template.id)),
      ]);

      // Follows converge: only toggle when the relationship is missing.
      await Future.wait(<Future<void>>[
        for (final userId in _follows)
          if (!_followed.contains(userId)) _follow(api, userId),
      ]);

      ref.invalidate(myProfileProvider);
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() => _submitError = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _follow(KlectApi api, String userId) async {
    if (!await api.hasFollowed(userId)) {
      await api.toggleFollow(userId);
    }
    _followed.add(userId);
  }

  /// The escape hatch: onboarding must never trap an account. Signing out
  /// returns to the auth screen via the router's guard.
  Future<void> _signOut() async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Sign out?',
      message: 'You can finish setting up next time you sign in.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed || !mounted) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  bool get _canAdvance => switch (_step) {
    0 => !_checkingUsername,
    1 => _interests.length >= OnboardingScreen.minimumInterests,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;

    return KScaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s6,
                Space.s4,
                Space.s6,
                Space.s2,
              ),
              child: Row(
                children: <Widget>[
                  for (var index = 0; index < 3; index++) ...<Widget>[
                    if (index > 0) const SizedBox(width: Space.s2),
                    Expanded(
                      child: AnimatedContainer(
                        duration: KMotion.duration(context, KDurations.base),
                        curve: Curves_.standard,
                        height: Space.s1,
                        decoration: BoxDecoration(
                          color: index <= _step
                              ? colors.accentDefault
                              : colors.surface3,
                          borderRadius: BorderRadius.circular(Radii.full),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: Space.s3),
                  KIconButton(
                    icon: Icons.logout_rounded,
                    semanticLabel: 'Sign out',
                    onPressed: _busy ? null : () => unawaited(_signOut()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: KMotion.duration(context, KDurations.medium),
                switchInCurve: Curves_.emphasized,
                child: KeyedSubtree(
                  key: ValueKey<int>(_step),
                  child: switch (_step) {
                    0 => _IdentityStep(
                      displayName: _displayName,
                      username: _username,
                      nameError: _nameError,
                      usernameError: _usernameError,
                      checking: _checkingUsername,
                      onUsernameChanged: _onUsernameChanged,
                    ),
                    1 => _InterestsStep(
                      selected: _interests,
                      onToggle: (id) => setState(() {
                        if (!_interests.remove(id)) _interests.add(id);
                      }),
                    ),
                    _ => _FollowStep(
                      selected: _follows,
                      onToggle: (id) => setState(() {
                        if (!_follows.remove(id)) _follows.add(id);
                      }),
                    ),
                  },
                ),
              ),
            ),
            if (_submitError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                child: KInlineError(message: _submitError!),
              ),
            Padding(
              padding: const EdgeInsets.all(Space.s6),
              child: Row(
                children: <Widget>[
                  if (_step > 0)
                    KButton(
                      label: 'Back',
                      variant: KButtonVariant.ghost,
                      onPressed: _busy ? null : _back,
                    ),
                  const Spacer(),
                  KButton(
                    label: _step == 2 ? 'Start collecting' : 'Continue',
                    size: KButtonSize.large,
                    busy: _busy,
                    onPressed: _canAdvance ? _next : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.displayName,
    required this.username,
    required this.nameError,
    required this.usernameError,
    required this.checking,
    required this.onUsernameChanged,
  });

  final TextEditingController displayName;
  final TextEditingController username;
  final String? nameError;
  final String? usernameError;
  final bool checking;
  final ValueChanged<String> onUsernameChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s6,
        vertical: Space.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Who is collecting?', style: context.kt.display2),
          const SizedBox(height: Space.s2),
          Text(
            'Your display name is what people see. Your handle is how they '
            'find you.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.s8),
          KTextField(
            controller: displayName,
            label: 'Display name',
            hint: 'Aria Vale',
            prefixIcon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            errorText: nameError,
            autofocus: true,
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: username,
            label: 'Handle',
            hint: 'aria',
            prefixIcon: Icons.alternate_email_rounded,
            textInputAction: TextInputAction.done,
            maxLength: 20,
            errorText: usernameError,
            helper: 'Lowercase letters, numbers and underscores.',
            onChanged: onUsernameChanged,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
            ],
            suffix: checking
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
        ],
      ),
    );
  }
}

class _InterestsStep extends ConsumerWidget {
  const _InterestsStep({required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final templates = ref.watch(onboardingTemplatesProvider);
    final remaining = OnboardingScreen.minimumInterests - selected.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s6,
        vertical: Space.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('What do you collect?', style: context.kt.display2),
          const SizedBox(height: Space.s2),
          Text(
            remaining > 0
                ? 'Pick at least $remaining more. Each one becomes a shelf you '
                      'can fill straight away.'
                : 'Nice. Add more any time.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.s6),
          templates.when(
            loading: () => const KShimmer(
              child: Wrap(
                spacing: Space.s2,
                runSpacing: Space.s2,
                children: <Widget>[
                  KSkeleton(width: Space.s20, height: Space.s8),
                  KSkeleton(width: Space.s24, height: Space.s8),
                  KSkeleton(width: Space.s16, height: Space.s8),
                  KSkeleton(width: Space.s20, height: Space.s8),
                ],
              ),
            ),
            error: (error, _) => KErrorState(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(onboardingTemplatesProvider),
            ),
            data: (items) => Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: <Widget>[
                for (final template in items)
                  KChip(
                    label: template.name,
                    selected: selected.contains(template.id),
                    onTap: () => onToggle(template.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowStep extends ConsumerWidget {
  const _FollowStep({required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final collectors = ref.watch(suggestedCollectorsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s6,
        vertical: Space.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Follow a few collectors', style: context.kt.display2),
          const SizedBox(height: Space.s2),
          Text(
            'Their shelves will show up in Pulse. You can unfollow any time.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.s6),
          collectors.when(
            loading: () => const KSkeletonList(rows: 4, showMedia: false),
            error: (error, _) => KErrorState(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(suggestedCollectorsProvider),
            ),
            data: (people) => people.isEmpty
                ? const KEmptyState(
                    title: 'You are early',
                    message:
                        'Nobody to suggest yet — you get first pick of '
                        'the handles.',
                    compact: true,
                  )
                : Column(
                    children: <Widget>[
                      for (final person in people)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.s3),
                          child: Row(
                            children: <Widget>[
                              KAvatar(
                                imageUrl: ref
                                    .read(klectApiProvider)
                                    .publicUrl(
                                      person.avatarPath,
                                      bucket: StorageBucket.avatars,
                                    ),
                                name: person.name,
                                isVerified: person.isVerified,
                              ),
                              const SizedBox(width: Space.s3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      person.name,
                                      style: context.kt.bodyStrong,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      person.handle,
                                      style: context.kt.caption.copyWith(
                                        color: colors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: Space.s3),
                              KButton(
                                label: selected.contains(person.id)
                                    ? 'Following'
                                    : 'Follow',
                                size: KButtonSize.small,
                                variant: selected.contains(person.id)
                                    ? KButtonVariant.secondary
                                    : KButtonVariant.primary,
                                onPressed: () => onToggle(person.id),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
