import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// How many characters of context may precede the first match before the
/// snippet clips into it. Character counts, not layout — deliberately not a
/// spacing token.
const int _snippetLead = 32;

/// Where a clipped snippet restarts, just before the match.
const int _snippetBacktrack = 24;

/// The inline search field that replaces the thread app bar.
///
/// Back closes the search; the trailing control clears the term without
/// leaving it.
class ThreadSearchBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the search bar.
  const ThreadSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  /// Owns the query text.
  final TextEditingController controller;

  /// Fired on every keystroke — the screen debounces.
  final ValueChanged<String> onChanged;

  /// Leaves search mode.
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(Layout.topBarHeight);

  @override
  Widget build(BuildContext context) => KFixedAppBar(
        leading: KIconButton(
          icon: Icons.arrow_back_rounded,
          semanticLabel: 'Close search',
          onPressed: onClose,
        ),
        titleWidget: KTextField(
          controller: controller,
          hint: 'Search this conversation',
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: onChanged,
        ),
        actions: <Widget>[
          KIconButton(
            icon: Icons.close_rounded,
            semanticLabel: 'Clear search',
            onPressed: () {
              controller.clear();
              onChanged('');
            },
          ),
        ],
      );
}

/// The results panel drawn over the thread while a term is live.
///
/// Tapping a row jumps the thread to that message with the same
/// scroll-and-pulse mechanic as tapping a quote.
class ThreadSearchResults extends StatelessWidget {
  /// Creates the results panel.
  const ThreadSearchResults({
    required this.term,
    required this.loading,
    required this.results,
    required this.onTap,
    super.key,
  });

  /// The live search term, used to highlight matches.
  final String term;

  /// A query is in flight.
  final bool loading;

  /// Matches, newest first.
  final List<MessageModel> results;

  /// Jump to a result.
  final void Function(MessageModel message) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return ColoredBox(
      color: colors.bgBase,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (loading) return const KSkeletonList(rows: 5, showMedia: false);
    if (results.isEmpty) {
      return const KEmptyState(
        title: 'No matches',
        message: 'Nothing in this conversation says that.',
        icon: Icons.search_off_rounded,
        compact: true,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: Space.s2, bottom: Space.s6),
      itemCount: results.length,
      separatorBuilder: (context, _) => Divider(
        height: Strokes.hairline,
        indent: Space.s4,
        endIndent: Space.s4,
        color: context.kc.borderSubtle,
      ),
      itemBuilder: (context, index) => _ResultRow(
        message: results[index],
        term: term,
        onTap: () => onTap(results[index]),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.message,
    required this.term,
    required this.onTap,
  });

  final MessageModel message;
  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final author = message.author?.name ?? 'Someone';
    final when = message.createdAt;

    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: 'Jump to $author: ${message.body ?? ''}',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    author,
                    style: text.label.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (when != null)
                  Text(
                    timeago.format(when, locale: 'en_short'),
                    style: text.micro.copyWith(color: colors.textTertiary),
                  ),
              ],
            ),
            const SizedBox(height: Space.s05),
            RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: text.callout.copyWith(color: colors.textPrimary),
                children: _highlight(context, message.body ?? '', term),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clips long bodies so the first match is visible, then paints every
  /// occurrence of [term] in the accent.
  static List<TextSpan> _highlight(
    BuildContext context,
    String body,
    String term,
  ) {
    final colors = context.kc;
    final text = context.kt;
    final needle = term.toLowerCase();
    if (needle.isEmpty) return <TextSpan>[TextSpan(text: body)];

    var display = body;
    final first = display.toLowerCase().indexOf(needle);
    if (first > _snippetLead) {
      display = '…${display.substring(first - _snippetBacktrack)}';
    }

    final lower = display.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (true) {
      final index = lower.indexOf(needle, cursor);
      if (index == -1) {
        if (cursor < display.length) {
          spans.add(TextSpan(text: display.substring(cursor)));
        }
        break;
      }
      if (index > cursor) {
        spans.add(TextSpan(text: display.substring(cursor, index)));
      }
      spans.add(
        TextSpan(
          text: display.substring(index, index + needle.length),
          style: text.bodyStrong.copyWith(color: colors.accentDefault),
        ),
      );
      cursor = index + needle.length;
    }
    return spans;
  }
}
