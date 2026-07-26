import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import 'profile_queries.dart';

/// Edit your own profile: banner, avatar, display name, handle, bio, links.
///
/// Uploads go straight into the `avatars` / `banners` buckets — the storage
/// policy requires the uploader's id as the first path segment, which
/// [KlectApi.upload] builds for you. The picker downscales and re-encodes on
/// device so a 12MP original never leaves the phone.
class EditProfileScreen extends ConsumerStatefulWidget {
  /// Creates the editor for [profile].
  const EditProfileScreen({required this.profile, super.key});

  /// The profile being edited — always the viewer's own.
  final Profile profile;

  /// Longest edge of an uploaded avatar, in pixels.
  static const double avatarMaxEdge = 1024;

  /// Longest edge of an uploaded banner, in pixels.
  static const double bannerMaxEdge = 2048;

  /// JPEG quality used for both. High enough to be invisible, low enough that
  /// a profile edit over cellular is instant.
  static const int uploadQuality = 88;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');
  static const Uuid _uuid = Uuid();

  late final TextEditingController _displayName = TextEditingController(
    text: widget.profile.displayName ?? '',
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.profile.username,
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.profile.bio ?? '',
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.profile.location ?? '',
  );
  late final TextEditingController _website = TextEditingController(
    text: widget.profile.website ?? '',
  );

  Timer? _usernameDebounce;
  String? _avatarPath;
  String? _bannerPath;
  bool _busy = false;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  bool _checkingUsername = false;
  String? _usernameError;
  String? _nameError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _avatarPath = widget.profile.avatarPath;
    _bannerPath = widget.profile.bannerPath;
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _displayName.dispose();
    _username.dispose();
    _bio.dispose();
    _location.dispose();
    _website.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _displayName.text.trim() != (widget.profile.displayName ?? '') ||
      _username.text.trim().toLowerCase() != widget.profile.username ||
      _bio.text.trim() != (widget.profile.bio ?? '') ||
      _location.text.trim() != (widget.profile.location ?? '') ||
      _website.text.trim() != (widget.profile.website ?? '') ||
      _avatarPath != widget.profile.avatarPath ||
      _bannerPath != widget.profile.bannerPath;

  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    setState(() => _usernameError = null);
    _usernameDebounce = Timer(KDurations.deliberate, () {
      unawaited(_checkUsername());
    });
  }

  Future<bool> _checkUsername() async {
    final value = _username.text.trim().toLowerCase();
    if (value == widget.profile.username) {
      setState(() => _usernameError = null);
      return true;
    }
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

  Future<void> _pick(StorageBucket bucket) async {
    final isAvatar = bucket == StorageBucket.avatars;
    setState(() {
      if (isAvatar) {
        _uploadingAvatar = true;
      } else {
        _uploadingBanner = true;
      }
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: isAvatar
            ? EditProfileScreen.avatarMaxEdge
            : EditProfileScreen.bannerMaxEdge,
        maxHeight: isAvatar
            ? EditProfileScreen.avatarMaxEdge
            : EditProfileScreen.bannerMaxEdge,
        imageQuality: EditProfileScreen.uploadQuality,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final key = await ref
          .read(klectApiProvider)
          .upload(
            bucket: bucket,
            objectPath: '${_uuid.v4()}.jpg',
            bytes: bytes,
            contentType: 'image/jpeg',
          );
      if (!mounted) return;
      setState(() {
        if (isAvatar) {
          _avatarPath = key;
        } else {
          _bannerPath = key;
        }
      });
    } on KlectError catch (error) {
      if (mounted) KToast.error(context, error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        KToast.error(
          context,
          error.code == 'photo_access_denied'
              ? 'KLECT needs photo access to change your picture.'
              : 'That image could not be read.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
          _uploadingBanner = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _displayName.text.trim();
    setState(() {
      _nameError = name.length >= 2 ? null : 'Tell us what to call you.';
      _submitError = null;
    });
    final usernameOk = await _checkUsername();
    if (!mounted || _nameError != null || !usernameOk) return;

    setState(() => _busy = true);
    try {
      await ref.read(klectApiProvider).updateMyProfile(<String, dynamic>{
        'display_name': name,
        'username': _username.text.trim().toLowerCase(),
        'bio': _emptyToNull(_bio.text),
        'location': _emptyToNull(_location.text),
        'website': _emptyToNull(_website.text),
        'avatar_path': _avatarPath,
        'banner_path': _bannerPath,
      });
      ref
        ..invalidate(myProfileProvider)
        ..invalidate(profileByIdProvider(widget.profile.id))
        ..invalidate(profileByUsernameProvider(widget.profile.username));
      if (!mounted) return;
      KToast.success(context, 'Profile updated.');
      Navigator.of(context).pop(true);
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() => _submitError = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _confirmDiscard(bool didPop, Object? result) async {
    if (didPop) return;
    final leave = await KConfirmDialog.show(
      context,
      title: 'Discard changes?',
      message: 'Your edits will not be saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);

    return KScaffold(
      canPop: !_dirty,
      onPopInvoked: _confirmDiscard,
      appBar: KFixedAppBar(
        title: 'Edit profile',
        showBack: true,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2),
            child: KButton(
              label: 'Save',
              size: KButtonSize.small,
              busy: _busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s4,
          Space.s5,
          Space.s12,
        ),
        children: <Widget>[
          _BannerPicker(
            url: bannerUrlOf(api, _bannerPath),
            busy: _uploadingBanner,
            onTap: () => _pick(StorageBucket.banners),
          ),
          const SizedBox(height: Space.s4),
          Row(
            children: <Widget>[
              Stack(
                alignment: Alignment.bottomRight,
                children: <Widget>[
                  KAvatar(
                    imageUrl: avatarUrlOf(api, _avatarPath),
                    name: _displayName.text,
                    size: Space.s20,
                  ),
                  Container(
                    padding: const EdgeInsets.all(Space.s1),
                    decoration: BoxDecoration(
                      color: colors.bgBase,
                      shape: BoxShape.circle,
                    ),
                    child: _uploadingAvatar
                        ? const SizedBox(
                            width: Space.s5,
                            height: Space.s5,
                            child: Padding(
                              padding: EdgeInsets.all(Space.s1),
                              child: CircularProgressIndicator(
                                strokeWidth: Strokes.thick,
                              ),
                            ),
                          )
                        : KIconButton(
                            icon: Icons.photo_camera_rounded,
                            semanticLabel: 'Change profile picture',
                            color: colors.accentDefault,
                            onPressed: () => _pick(StorageBucket.avatars),
                          ),
                  ),
                ],
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Text(
                  'A square photo works best. Everything is downscaled on '
                  'device before it leaves your phone.',
                  style: context.kt.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s6),
          KTextField(
            controller: _displayName,
            label: 'Display name',
            hint: 'Aria Vale',
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
            hint: 'aria',
            prefixIcon: Icons.alternate_email_rounded,
            textInputAction: TextInputAction.next,
            maxLength: 20,
            errorText: _usernameError,
            helper:
                'Your profile lives at '
                '${KlectLinks.displayOrigin}/u/${_username.text}',
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
          KTextField(
            controller: _bio,
            label: 'Bio',
            hint: 'What do you collect, and why?',
            maxLines: 4,
            minLines: 3,
            maxLength: 280,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: _location,
            label: 'Location',
            hint: 'Melbourne',
            prefixIcon: Icons.place_outlined,
            textInputAction: TextInputAction.next,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: _website,
            label: 'Link',
            hint: 'https://…',
            prefixIcon: Icons.link_rounded,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
          ),
          if (_submitError != null) ...<Widget>[
            const SizedBox(height: Space.s5),
            KInlineError(message: _submitError!),
          ],
        ],
      ),
    );
  }
}

class _BannerPicker extends StatelessWidget {
  const _BannerPicker({
    required this.url,
    required this.busy,
    required this.onTap,
  });

  final String? url;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: busy ? null : onTap,
      enforceMinTapTarget: false,
      semanticLabel: 'Change banner',
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AspectRatio(
            aspectRatio: Aspect.banner,
            child: url == null
                ? Container(
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(
                        color: colors.borderSubtle,
                        width: Strokes.thin,
                      ),
                    ),
                  )
                : KBlurhashImage(
                    url: url,
                    aspectRatio: Aspect.banner,
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s15,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceScrim,
              borderRadius: BorderRadius.circular(Radii.full),
            ),
            child: busy
                ? const SizedBox(
                    width: Space.s4,
                    height: Space.s4,
                    child: CircularProgressIndicator(
                      strokeWidth: Strokes.thick,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.image_outlined,
                        size: Space.s4,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: Space.s15),
                      Text(
                        'Change banner',
                        style: context.kt.label.copyWith(
                          color: colors.textPrimary,
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
