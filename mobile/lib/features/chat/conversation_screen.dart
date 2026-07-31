import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import 'calls/call_availability.dart';
import 'calls/call_controller.dart';
import 'calls/call_permissions.dart';
import 'chat_api.dart';
import 'chat_models.dart';
import 'error_copy.dart';
import 'inbox_controller.dart';
import 'thread_controller.dart';
import 'widgets/chat_composer.dart';
import 'widgets/forward_sheet.dart';
import 'widgets/group_avatar.dart';
import 'widgets/message_actions_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/thread_search.dart';
import 'widgets/typing_indicator.dart';

/// Messages closer together than this belong to one visual group.
const Duration _groupWindow = Duration(minutes: 5);

/// How close to the top of the history the user gets before the next page
/// starts loading.
const double _paginationThreshold = Space.s24 * 4;

/// How many older pages a jump may fetch while hunting for a message that is
/// not loaded yet.
const int _jumpPageCap = 10;

/// How many scroll-and-settle steps a jump may take before giving up — the
/// lazy list needs a frame per step to build rows near the new offset.
const int _jumpScrollAttempts = 24;

/// One conversation.
///
/// Grouped bubbles, date separators, quoted replies, long-press reactions,
/// edit and delete for your own messages, read receipts, and a typing indicator
/// fed by Realtime broadcast — no `typing` table anywhere.
class ConversationScreen extends ConsumerStatefulWidget {
  /// Creates the thread.
  const ConversationScreen({required this.conversationId, super.key});

  /// Route parameter.
  final String conversationId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();

  ChatMessage? _replyTo;
  ChatMessage? _editing;

  /// One stable key per message id, so a jump can find the bubble's render
  /// object once the lazy list has built it.
  final Map<String, GlobalKey> _bubbleKeys = <String, GlobalKey>{};
  String? _highlightedId;
  Timer? _pulseTimer;
  bool _jumping = false;

  bool _searching = false;
  final TextEditingController _searchQuery = TextEditingController();
  Timer? _searchDebounce;
  String _searchTerm = '';
  bool _searchLoading = false;
  List<MessageModel> _searchResults = const <MessageModel>[];
  bool _startInFlight = false;

  ChatThreadController get _thread =>
      ref.read(chatThreadProvider(widget.conversationId).notifier);

  ChatThreadState get _threadState =>
      ref.read(chatThreadProvider(widget.conversationId));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseTimer?.cancel();
    _searchDebounce?.cancel();
    _searchQuery.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Coming back to a thread that is on screen means the user has seen
    // whatever arrived while they were away.
    if (lifecycle == AppLifecycleState.resumed) unawaited(_thread.markRead());
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - _paginationThreshold) {
      unawaited(_thread.loadMore());
    }
  }

  // ────────────────────────────────────────────────────────────── actions ──

  Future<void> _startCall(CallKind kind, Profile? peer) async {
    if (_startInFlight ||
        !ref.read(callAvailabilityProvider) ||
        ref.read(activeCallProvider).isBusy) {
      return;
    }

    setState(() => _startInFlight = true);
    CallModel? call;
    try {
      final permission = await CallPermissions.request(
        context,
        kind: kind,
        outgoing: true,
      );
      if (!mounted) return;
      if (permission != CallPermissionResult.granted) {
        final permissionName = kind == CallKind.video
            ? 'Camera and microphone permission'
            : 'Microphone permission';
        final callName = kind == CallKind.video ? 'video call' : 'audio call';
        KToast.show(
          context,
          '$permissionName is needed to start a $callName.',
          kind: KToastKind.error,
          actionLabel: 'Open settings',
          onAction: () => unawaited(CallPermissions.openSettings()),
        );
        return;
      }

      call = await ref
          .read(activeCallProvider.notifier)
          .place(conversationId: widget.conversationId, kind: kind, peer: peer);
      if (!mounted) return;
      if (call == null) {
        final failure = ref.read(activeCallProvider).error;
        KToast.error(
          context,
          failure == null
              ? stableErrorIdentifierCopy('unknown')
              : chatErrorCopy(failure),
        );
        return;
      }
    } finally {
      if (mounted) setState(() => _startInFlight = false);
    }

    if (mounted) await context.push('/call/${call.id}');
  }

  void _openActions(ChatMessage message, {required bool isMine}) {
    unawaited(
      MessageActionsSheet.show(
        context,
        message: message,
        isMine: isMine,
        viewerId: ref.read(currentUserIdProvider),
        onReact: (emoji) =>
            unawaited(_thread.toggleReaction(message.id, emoji)),
        onReply: () => _armReply(message),
        onForward: message.pending || message.failed
            ? null
            : () => unawaited(_forward(message)),
        onEdit: () => setState(() {
          _editing = message;
          _replyTo = null;
        }),
        onDeleteForEveryone: () => unawaited(_deleteForEveryone(message.id)),
        onDeleteForMe: () => unawaited(_hideForMe(message.id)),
      ),
    );
  }

  /// Deletes a message for every participant, showing the one error indication
  /// the failure path asks for — and it carries the retry, which re-runs this
  /// very method, so a timeout is one tap from a second attempt (11.12).
  Future<void> _deleteForEveryone(String messageId) async {
    final failure = await _thread.deleteForEveryone(messageId);
    if (failure == null || !mounted) return;
    KToast.show(
      context,
      failure.message,
      kind: KToastKind.error,
      icon: Icons.error_outline_rounded,
      actionLabel: 'Retry',
      onAction: () => unawaited(_deleteForEveryone(messageId)),
    );
  }

  Future<void> _hideForMe(String messageId) async {
    final failure = await _thread.hideForMe(messageId);
    if (failure == null || !mounted) return;
    KToast.show(
      context,
      failure.message,
      kind: KToastKind.error,
      icon: Icons.error_outline_rounded,
      actionLabel: 'Retry',
      onAction: () => unawaited(_hideForMe(messageId)),
    );
  }

  /// The one path into the composer's reply target — the long-press sheet's
  /// Reply and the swipe gesture both land here.
  void _armReply(ChatMessage message) => setState(() {
    _replyTo = message;
    _editing = null;
  });

  // ────────────────────────────────────────────────────────────── forward ──

  Future<void> _forward(ChatMessage message) async {
    final targets = await ForwardSheet.show(context);
    if (targets == null || targets.isEmpty || !mounted) return;
    final api = ref.read(chatApiProvider);
    final failures = <String>[];
    for (final target in targets) {
      try {
        await api.forwardMessage(
          message: message,
          targetConversationId: target.id,
        );
      } on KlectError {
        failures.add(target.conversation.displayTitle);
      }
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      KToast.success(
        context,
        targets.length == 1
            ? 'Forwarded to ${targets.first.conversation.displayTitle}'
            : 'Forwarded to ${targets.length} conversations',
      );
    } else {
      KToast.error(context, 'Could not forward to ${failures.join(', ')}.');
    }
  }

  // ──────────────────────────────────────────────────────── jump-and-pulse ──

  GlobalKey _keyFor(String messageId) =>
      _bubbleKeys.putIfAbsent(messageId, GlobalKey.new);

  int _messageIndexOf(String messageId) =>
      _threadState.messages.indexWhere((message) => message.id == messageId);

  /// Scrolls to [messageId], paging older history (capped) when it is not
  /// loaded yet, then plays a brief highlight pulse on the bubble.
  Future<void> _jumpToMessage(String messageId) async {
    if (_jumping) return;
    _jumping = true;
    try {
      var index = _messageIndexOf(messageId);
      var pages = 0;
      while (index == -1 && pages < _jumpPageCap) {
        final state = _threadState;
        if (state.loadingMore) {
          // Somebody else's page is in flight; let it land, then re-check.
          await Future<void>.delayed(KDurations.instant);
        } else if (state.hasMore) {
          await _thread.loadMore();
          pages++;
        } else {
          break;
        }
        if (!mounted) return;
        index = _messageIndexOf(messageId);
      }
      if (index == -1) {
        if (mounted) {
          KToast.error(context, 'That message is too far back to reach.');
        }
        return;
      }
      await _revealMessage(messageId);
      if (!mounted) return;
      _pulse(messageId);
    } finally {
      _jumping = false;
    }
  }

  /// Steps the reversed lazy list towards the bubble until it is built, then
  /// settles it into the centre of the viewport.
  Future<void> _revealMessage(String messageId) async {
    final key = _keyFor(messageId);
    for (var attempt = 0; attempt < _jumpScrollAttempts; attempt++) {
      if (!mounted) return;
      final bubbleContext = key.currentContext;
      if (bubbleContext != null && bubbleContext.mounted) {
        await Scrollable.ensureVisible(
          bubbleContext,
          alignment: 0.5,
          duration: KMotion.duration(context, KDurations.base),
          curve: Curves_.standard,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final index = _messageIndexOf(messageId);
      if (index == -1) return;
      final position = _scroll.position;
      final total = _threadState.messages.length;
      // The list is lazy, so the extent is an estimate that self-corrects as
      // rows build; re-derive it every step.
      final estimatedExtent =
          (position.maxScrollExtent + position.viewportDimension) / (total + 1);
      final estimated =
          (estimatedExtent * index - position.viewportDimension / 2).clamp(
            0.0,
            position.maxScrollExtent,
          );
      final delta = estimated - position.pixels;
      final step = delta.abs() <= position.viewportDimension
          ? estimated
          : position.pixels + delta.sign * position.viewportDimension;
      _scroll.jumpTo(step.clamp(0.0, position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _pulse(String messageId) {
    _pulseTimer?.cancel();
    setState(() => _highlightedId = messageId);
    _pulseTimer = Timer(KDurations.deliberate, () {
      if (!mounted) return;
      setState(() => _highlightedId = null);
    });
  }

  // ─────────────────────────────────────────────────────────────── search ──

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchQuery.clear();
    setState(() {
      _searching = false;
      _searchTerm = '';
      _searchLoading = false;
      _searchResults = const <MessageModel>[];
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      KDurations.medium,
      () => unawaited(_runSearch(value)),
    );
  }

  Future<void> _runSearch(String value) async {
    final trimmed = value.trim();
    if (!mounted) return;
    setState(() {
      _searchTerm = trimmed;
      _searchResults = const <MessageModel>[];
      _searchLoading = trimmed.isNotEmpty;
    });
    if (trimmed.isEmpty) return;
    try {
      final results = await ref
          .read(chatApiProvider)
          .searchMessages(widget.conversationId, trimmed);
      if (!mounted || _searchTerm != trimmed) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } on KlectError catch (error) {
      if (!mounted || _searchTerm != trimmed) return;
      setState(() => _searchLoading = false);
      KToast.error(context, error.message);
    }
  }

  void _openSearchResult(MessageModel message) {
    _closeSearch();
    unawaited(_jumpToMessage(message.id));
  }

  /// The group info screen — the group counterpart of "view profile".
  void _openGroupInfo() =>
      context.push('${Routes.messages}/${widget.conversationId}/info');

  Future<void> _openOverflow(
    ChatThreadState state,
    Profile? peer, {
    required bool isGroup,
  }) async {
    final api = ref.read(chatApiProvider);
    await KSheet.show<void>(
      context: context,
      title: state.conversation?.displayTitle ?? 'Conversation',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isGroup)
            _OverflowRow(
              icon: Icons.info_outline_rounded,
              label: 'Group info',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openGroupInfo();
              },
            ),
          if (peer != null)
            _OverflowRow(
              icon: Icons.person_outline_rounded,
              label: 'View profile',
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(KlectLinks.profilePath(peer.username));
              },
            ),
          _OverflowRow(
            icon: Icons.notifications_off_outlined,
            label: 'Mute for a week',
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(
                ref
                    .read(chatInboxProvider.notifier)
                    .toggleMute(widget.conversationId),
              );
            },
          ),
          if (peer != null) ...<Widget>[
            _OverflowRow(
              icon: Icons.flag_outlined,
              label: 'Report ${peer.name}',
              destructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  reportMessageAuthor(
                    context,
                    authorId: peer.id,
                    subjectLabel: peer.name,
                  ),
                );
              },
            ),
            _OverflowRow(
              icon: Icons.block_rounded,
              label: 'Block ${peer.name}',
              destructive: true,
              onTap: () async {
                final navigator = Navigator.of(sheetContext);
                final confirmed = await KConfirmDialog.show(
                  context,
                  title: 'Block ${peer.name}?',
                  message:
                      'You stop seeing each other everywhere on KLECT, '
                      'and neither of you can message the other.',
                  confirmLabel: 'Block',
                  destructive: true,
                );
                if (!confirmed) return;
                navigator.pop();
                try {
                  await api.api.blockUser(peer.id);
                  if (!mounted) return;
                  KToast.success(context, '${peer.name} is blocked.');
                  context.pop();
                } on KlectError catch (error) {
                  if (!mounted) return;
                  KToast.error(context, error.message);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────── build ──

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatThreadProvider(widget.conversationId));
    final viewerId = ref.watch(currentUserIdProvider);
    final isGroup = state.conversation?.kind == ConversationKind.group;
    final callsEnabled = ref.watch(callAvailabilityProvider);
    final activeCall = ref.watch(activeCallProvider);
    final showCallActions = !isGroup && callsEnabled;
    final canCall = showCallActions && !activeCall.isBusy && !_startInFlight;
    String? viewerRole;
    for (final member in state.members) {
      if (member.userId == viewerId &&
          member.isActive &&
          member.requestState == 'accepted') {
        viewerRole = member.role;
        break;
      }
    }
    final groupSendScope = state.conversation?.groupPolicy.sendMessages;
    final groupSendAllowed =
        !isGroup || (groupSendScope?.allows(viewerRole) ?? false);
    // A group has no single "peer": every peer-shaped affordance (profile
    // push, call, block, report) is DM-only.
    final peer = isGroup ? null : state.otherMember(viewerId)?.profile;

    ref.listen(
      chatThreadProvider(widget.conversationId).select((s) => s.error),
      (_, error) {
        if (error == null || !mounted) return;
        KToast.error(context, KlectError.from(error).message);
        _thread.clearError();
      },
    );

    final topBar = _searching
        ? ThreadSearchBar(
            controller: _searchQuery,
            onChanged: _onSearchChanged,
            onClose: _closeSearch,
          )
        : _ThreadAppBar(
            state: state,
            peer: peer,
            isGroup: isGroup,
            showCallActions: showCallActions,
            canCall: canCall,
            onCall: (kind) => unawaited(_startCall(kind, peer)),
            onSearch: _openSearch,
            onOverflow: () =>
                unawaited(_openOverflow(state, peer, isGroup: isGroup)),
            onOpenInfo: isGroup ? _openGroupInfo : null,
          );

    return KScaffold(
      appBar: topBar,
      // The composer belongs to the resizable body, not Scaffold's
      // bottomNavigationBar. Scaffold now owns the keyboard inset exactly
      // once, so Gboard cannot cover the caret or typed text.
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                _ThreadBody(
                  state: state,
                  viewerId: viewerId,
                  scroll: _scroll,
                  highlightedId: _highlightedId,
                  keyFor: _keyFor,
                  onLongPress: _openActions,
                  onQuickReact: (message) => unawaited(
                    _thread.toggleReaction(message.id, kQuickReactions.first),
                  ),
                  onSwipeReply: _armReply,
                  onReplyTap: (replyToId) =>
                      unawaited(_jumpToMessage(replyToId)),
                  onRetry: (message) => unawaited(_thread.retry(message.id)),
                  onDiscard: (message) => _thread.discard(message.id),
                  onReaction: (message, emoji) =>
                      unawaited(_thread.toggleReaction(message.id, emoji)),
                  localPreview: _thread.localPreview,
                  onRefresh: () => unawaited(_thread.refresh()),
                ),
                if (_searching && (_searchTerm.isNotEmpty || _searchLoading))
                  Positioned.fill(
                    child: ThreadSearchResults(
                      term: _searchTerm,
                      loading: _searchLoading,
                      results: _searchResults,
                      onTap: _openSearchResult,
                    ),
                  ),
              ],
            ),
          ),
          TypingIndicator(typing: state.typing),
          if (!groupSendAllowed && groupSendScope != null)
            _ComposerLock(scopeLabel: groupSendScope.label)
          else
            ChatComposer(
              conversationId: widget.conversationId,
              replyTo: _replyTo,
              editing: _editing,
              enabled: !state.loading || state.messages.isNotEmpty,
              onCancelReply: () => setState(() => _replyTo = null),
              onCancelEdit: () => setState(() => _editing = null),
            ),
        ],
      ),
    );
  }
}

class _ComposerLock extends StatelessWidget {
  const _ComposerLock({required this.scopeLabel});

  final String scopeLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    readOnly: true,
    label: 'Messaging is limited to $scopeLabel',
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s3,
      ),
      decoration: BoxDecoration(
        color: context.kc.surface1,
        border: Border(
          top: BorderSide(
            color: context.kc.borderSubtle,
            width: Strokes.hairline,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Text(
          'Only $scopeLabel can send messages in this group.',
          textAlign: TextAlign.center,
          style: context.kt.callout.copyWith(color: context.kc.textSecondary),
        ),
      ),
    ),
  );
}

class _ThreadAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _ThreadAppBar({
    required this.state,
    required this.peer,
    required this.isGroup,
    required this.showCallActions,
    required this.canCall,
    required this.onCall,
    required this.onSearch,
    required this.onOverflow,
    this.onOpenInfo,
  });

  final ChatThreadState state;
  final Profile? peer;
  final bool isGroup;
  final bool showCallActions;
  final bool canCall;
  final void Function(CallKind kind) onCall;
  final VoidCallback onSearch;
  final VoidCallback onOverflow;

  /// Opens the group info screen — the header tap for groups, where a DM
  /// pushes the peer's profile instead.
  final VoidCallback? onOpenInfo;

  @override
  Size get preferredSize => const Size.fromHeight(Layout.topBarHeight);

  int get _activeMemberCount {
    var count = 0;
    for (final member in state.members) {
      if (member.isActive) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final title =
        state.conversation?.displayTitle ?? peer?.name ?? 'Conversation';
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(
          isGroup ? state.conversation?.avatarPath : peer?.avatarPath,
          bucket: StorageBucket.avatars,
        );
    final memberCount = isGroup ? _activeMemberCount : 0;

    return KFixedAppBar(
      showBack: true,
      titleWidget: KPressable(
        enforceMinTapTarget: false,
        semanticLabel: isGroup
            ? 'Open group info'
            : peer == null
            ? title
            : 'Open $title profile',
        onTap: isGroup
            ? onOpenInfo
            : peer == null
            ? null
            : () => context.push(KlectLinks.profilePath(peer!.username)),
        child: Row(
          children: <Widget>[
            if (isGroup)
              GroupAvatar(size: Space.s8, imageUrl: avatarUrl, name: title)
            else
              KAvatar(
                size: Space.s8,
                imageUrl: avatarUrl,
                name: title,
                isVerified: peer?.isVerified ?? false,
              ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: context.kt.title3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isGroup)
                    Text(
                      memberCount > 0
                          ? '$memberCount '
                                '${memberCount == 1 ? 'member' : 'members'}'
                          : 'Group',
                      style: context.kt.micro.copyWith(
                        color: colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (peer != null)
                    Text(
                      state.isPresent(peer!.id)
                          ? 'Active now'
                          : '@${peer!.username}',
                      style: context.kt.micro.copyWith(
                        color: state.isPresent(peer!.id)
                            ? colors.semanticSuccess
                            : colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        if (showCallActions) ...<Widget>[
          KIconButton(
            icon: Icons.call_rounded,
            semanticLabel: 'Start an audio call',
            onPressed: canCall ? () => onCall(CallKind.audio) : null,
          ),
          KIconButton(
            icon: Icons.videocam_rounded,
            semanticLabel: 'Start a video call',
            onPressed: canCall ? () => onCall(CallKind.video) : null,
          ),
        ],
        KIconButton(
          icon: Icons.search_rounded,
          semanticLabel: 'Search this conversation',
          onPressed: onSearch,
        ),
        KIconButton(
          icon: Icons.more_horiz_rounded,
          semanticLabel: 'More',
          onPressed: onOverflow,
        ),
      ],
    );
  }
}

class _ThreadBody extends ConsumerWidget {
  const _ThreadBody({
    required this.state,
    required this.viewerId,
    required this.scroll,
    required this.highlightedId,
    required this.keyFor,
    required this.onLongPress,
    required this.onQuickReact,
    required this.onSwipeReply,
    required this.onReplyTap,
    required this.onRetry,
    required this.onDiscard,
    required this.onReaction,
    required this.localPreview,
    required this.onRefresh,
  });

  final ChatThreadState state;
  final String? viewerId;
  final ScrollController scroll;
  final String? highlightedId;
  final GlobalKey Function(String messageId) keyFor;
  final void Function(ChatMessage message, {required bool isMine}) onLongPress;
  final void Function(ChatMessage message) onQuickReact;
  final void Function(ChatMessage message) onSwipeReply;
  final void Function(String replyToId) onReplyTap;
  final void Function(ChatMessage message) onRetry;
  final void Function(ChatMessage message) onDiscard;
  final void Function(ChatMessage message, String emoji) onReaction;
  final Uint8ListResolver localPreview;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading && state.messages.isEmpty) {
      return const KSkeletonList(rows: 6);
    }
    if (state.error != null && state.messages.isEmpty) {
      return KErrorState(error: state.error, onRetry: onRefresh);
    }
    if (state.messages.isEmpty) {
      return const KEmptyState(
        title: 'Say something',
        message:
            'Share a collection, or just start talking. '
            'Nothing here yet.',
        icon: Icons.chat_bubble_outline_rounded,
      );
    }

    final api = ref.watch(klectApiProvider);
    final rows = _buildRows(state.messages);
    final peerReadAt = state.peerReadAt(viewerId);
    final receiptId = _newestOwnMessageId(state.messages, viewerId);
    final isGroup = state.conversation?.kind == ConversationKind.group;

    return ListView.builder(
      controller: scroll,
      reverse: true,
      padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s2),
      itemCount: rows.length + (state.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= rows.length) {
          return const Padding(
            padding: EdgeInsets.all(Space.s4),
            child: Center(child: KSkeleton.text(width: Space.s20)),
          );
        }
        final row = rows[index];
        if (row.separator != null) {
          return ChatDateSeparator(date: row.separator!);
        }
        final message = row.message!;
        final isMine = message.authorId == viewerId;
        final kind = message.message.kind;
        // Deleted rows never reach the list; system and call_event rows render
        // as notices, so only real utterances take the swipe gesture.
        final swipeable =
            (kind == MessageKind.text || kind == MessageKind.image) &&
            !message.pending &&
            !message.failed;
        final replyToId = message.message.replyToId;
        final parentReachable =
            replyToId != null &&
            message.replyTo != null &&
            message.replyTo!.deletedAt == null;
        return MessageBubble(
          key: keyFor(message.id),
          message: message,
          isMine: isMine,
          viewerId: viewerId,
          avatarUrl: api.publicUrl(
            message.message.author?.avatarPath,
            bucket: StorageBucket.avatars,
          ),
          isFirstOfGroup: row.isFirstOfGroup,
          isLastOfGroup: row.isLastOfGroup,
          showAuthorName: isGroup,
          showReceipt: message.id == receiptId,
          seen: peerReadAt != null && !peerReadAt.isBefore(message.createdAt),
          localPreview: localPreview(message.id),
          highlighted: message.id == highlightedId,
          onLongPress: () => onLongPress(message, isMine: isMine),
          onDoubleTap: () => onQuickReact(message),
          onSwipeReply: swipeable ? () => onSwipeReply(message) : null,
          onReplyTap: parentReachable ? () => onReplyTap(replyToId) : null,
          onRetry: () => onRetry(message),
          onDiscard: () => onDiscard(message),
          onReactionTap: (emoji) => onReaction(message, emoji),
        );
      },
    );
  }

  static String? _newestOwnMessageId(
    List<ChatMessage> messages,
    String? viewerId,
  ) {
    for (final message in messages) {
      if (message.authorId == viewerId && !message.pending && !message.failed) {
        return message.id;
      }
    }
    return null;
  }

  /// Flattens the newest-first message list into renderable rows, inserting a
  /// date separator *after* the oldest message of each day so that a reversed
  /// list draws it above.
  static List<_ThreadRow> _buildRows(List<ChatMessage> messages) {
    final rows = <_ThreadRow>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final newer = i == 0 ? null : messages[i - 1];
      final older = i == messages.length - 1 ? null : messages[i + 1];

      rows.add(
        _ThreadRow.message(
          message,
          isFirstOfGroup: !_sameGroup(older, message),
          isLastOfGroup: !_sameGroup(message, newer),
        ),
      );

      final olderDay = older == null ? null : _dayOf(older.createdAt);
      final day = _dayOf(message.createdAt);
      if (olderDay == null || olderDay != day) {
        rows.add(_ThreadRow.separator(day));
      }
    }
    return rows;
  }

  static bool _sameGroup(ChatMessage? earlier, ChatMessage? later) {
    if (earlier == null || later == null) return false;
    if (earlier.message.kind != later.message.kind) return false;
    if (earlier.message.kind == MessageKind.callEvent ||
        earlier.message.kind == MessageKind.system) {
      return false;
    }
    if (earlier.authorId != later.authorId) return false;
    if (_dayOf(earlier.createdAt) != _dayOf(later.createdAt)) return false;
    return later.createdAt.difference(earlier.createdAt).abs() <= _groupWindow;
  }

  static DateTime _dayOf(DateTime at) => DateTime(at.year, at.month, at.day);
}

/// Looks a message's in-flight photo bytes up by id.
typedef Uint8ListResolver = Uint8List? Function(String messageId);

class _ThreadRow {
  const _ThreadRow.message(
    this.message, {
    required this.isFirstOfGroup,
    required this.isLastOfGroup,
  }) : separator = null;

  const _ThreadRow.separator(this.separator)
    : message = null,
      isFirstOfGroup = false,
      isLastOfGroup = false;

  final ChatMessage? message;
  final DateTime? separator;
  final bool isFirstOfGroup;
  final bool isLastOfGroup;
}

class _OverflowRow extends StatelessWidget {
  const _OverflowRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = destructive ? colors.semanticDanger : colors.textPrimary;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Row(
          children: <Widget>[
            Icon(icon, size: Space.s5, color: tint),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Text(label, style: context.kt.body.copyWith(color: tint)),
            ),
          ],
        ),
      ),
    );
  }
}
