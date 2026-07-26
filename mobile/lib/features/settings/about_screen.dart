import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/links.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'settings_widgets.dart';

/// What this app is, and where to read the small print.
class AboutScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutScreen({super.key});

  /// Shipping version. Matches `pubspec.yaml`.
  static const String version = '1.0.0';

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;

    return KScaffold(
      appBar: const KFixedAppBar(title: 'About', showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s6,
          Space.s5,
          Space.s12,
        ),
        children: <Widget>[
          Text('KLECT', style: context.kt.display1),
          Text(
            'Version $version',
            style: context.kt.caption.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: Space.s6),
          Text(
            'A social network where the unit of content is a collection, not a '
            'post. Three levels, and every one of them can be liked, saved, '
            'reposted, commented on and shared.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.s6),
          const _HierarchyCard(),
          const SettingsSection(
            header: 'The small print',
            children: <Widget>[
              _LinkRow(
                icon: Icons.description_outlined,
                title: 'Terms of service',
                url: '${KlectLinks.webOrigin}/terms',
              ),
              _LinkRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy policy',
                url: '${KlectLinks.webOrigin}/privacy',
              ),
              _LinkRow(
                icon: Icons.gavel_rounded,
                title: 'Community guidelines',
                url: '${KlectLinks.webOrigin}/guidelines',
              ),
            ],
          ),
          const SettingsSectionHeader(
            label: 'Reporting',
            note: 'Every item, shelf, collection, post, comment, message and '
                'profile has a report action. Reporting the same thing twice '
                'tells you it is already with us — it never errors.',
          ),
        ],
      ),
    );
  }
}

class _HierarchyCard extends StatelessWidget {
  const _HierarchyCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
        boxShadow: KlectTheme.shadow(Elevation.low),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HierarchyLine(
            indent: 0,
            title: 'Collection',
            example: 'Anime',
          ),
          _HierarchyLine(
            indent: 1,
            title: 'Subcollection',
            example: 'JJK, One Piece',
          ),
          _HierarchyLine(
            indent: 2,
            title: 'Item',
            example: 'one thing, as many photos as it deserves',
          ),
        ],
      ),
    );
  }
}

class _HierarchyLine extends StatelessWidget {
  const _HierarchyLine({
    required this.indent,
    required this.title,
    required this.example,
  });

  final int indent;
  final String title;
  final String example;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: EdgeInsets.only(
        left: Space.s5 * indent,
        top: indent == 0 ? Space.s0 : Space.s2,
      ),
      child: Row(
        children: <Widget>[
          if (indent > 0) ...<Widget>[
            Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: Space.s4,
              color: colors.textTertiary,
            ),
            const SizedBox(width: Space.s1),
          ],
          Text(title, style: context.kt.bodyStrong),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(
              example,
              style: context.kt.caption.copyWith(color: colors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) => SettingsRow(
        icon: icon,
        title: title,
        subtitle: url,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (!context.mounted) return;
          KToast.show(
            context,
            'Link copied — open it in your browser.',
            kind: KToastKind.success,
            icon: Icons.link_rounded,
          );
        },
      );
}
