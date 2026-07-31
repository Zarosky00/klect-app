import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../calls/call_controller.dart';

/// Compact access to a call retained after the full-screen route is minimized.
class CallPill extends ConsumerWidget {
  /// Creates the pill.
  const CallPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeCallProvider);
    final callId = state.call?.id;
    if (!state.isBusy || callId == null) return const SizedBox.shrink();

    final colors = context.kc;
    final name = _boundedName(state.peer?.name ?? 'KLECT call');
    final detail = switch (state.phase) {
      CallPhase.active => 'In call · ${state.formattedElapsed}',
      CallPhase.reconnecting => 'Reconnecting · ${state.formattedElapsed}',
      CallPhase.dialing => 'Ringing',
      CallPhase.incoming => 'Incoming call',
      CallPhase.connecting => 'Connecting',
      CallPhase.idle || CallPhase.ended => 'Call',
    };

    return Material(
      color: Colors.transparent,
      child: KPressable(
        semanticLabel: '$name, $detail. Return to call',
        onTap: () => context.push('/call/$callId'),
        enforceMinTapTarget: false,
        child: Container(
          height: Layout.callPillHeight,
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          decoration: BoxDecoration(
            color: colors.surface3,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(color: colors.borderStrong, width: Strokes.thin),
            boxShadow: KlectTheme.shadow(Elevation.mid),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.call_rounded,
                size: Space.s5,
                color: colors.semanticSuccess,
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.kt.bodyStrong,
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.kt.count.copyWith(
                        color: state.phase == CallPhase.reconnecting
                            ? colors.semanticWarning
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_full_rounded,
                size: Space.s4,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _boundedName(String value) {
  final clusters = value.characters;
  return clusters.length <= 24 ? value : clusters.take(24).toString();
}
