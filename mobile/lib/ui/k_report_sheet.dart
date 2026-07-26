import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_error.dart';
import '../core/api/klect_api.dart';
import '../core/models/models.dart';
import '../design/theme.dart';
import 'k_button.dart';
import 'k_pressable.dart';
import 'k_sheet.dart';
import 'k_text_field.dart';
import 'k_toast.dart';

/// Report, reachable from **every** surface: item, subcollection, collection,
/// post, comment, message and profile.
///
/// Reporting the same target twice is not an error — `submit_report` returns
/// `already_reported` and we say so.
abstract final class KReportSheet {
  /// Opens the reason picker for an entity.
  static Future<void> showForEntity(
    BuildContext context, {
    required EntityType type,
    required String entityId,
    String? subjectLabel,
  }) =>
      _show(context, type: type, entityId: entityId, subjectLabel: subjectLabel);

  /// Opens the reason picker for a person.
  static Future<void> showForUser(
    BuildContext context, {
    required String userId,
    String? subjectLabel,
  }) =>
      _show(context, userId: userId, subjectLabel: subjectLabel);

  static Future<void> _show(
    BuildContext context, {
    EntityType? type,
    String? entityId,
    String? userId,
    String? subjectLabel,
  }) =>
      KSheet.show<void>(
        context: context,
        title: subjectLabel == null ? 'Report' : 'Report $subjectLabel',
        builder: (sheetContext) => _KReportBody(
          type: type,
          entityId: entityId,
          userId: userId,
        ),
      );
}

class _KReportBody extends ConsumerStatefulWidget {
  const _KReportBody({this.type, this.entityId, this.userId});

  final EntityType? type;
  final String? entityId;
  final String? userId;

  @override
  ConsumerState<_KReportBody> createState() => _KReportBodyState();
}

class _KReportBodyState extends ConsumerState<_KReportBody> {
  ReportReason? _reason;
  final TextEditingController _details = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(klectApiProvider).submitReport(
            reason: reason,
            type: widget.type,
            entityId: widget.entityId,
            userId: widget.userId,
            details: _details.text.trim().isEmpty ? null : _details.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      KToast.show(
        context,
        result.alreadyReported
            ? 'You already reported this. We are on it.'
            : 'Thanks — our team will take a look.',
        kind: KToastKind.success,
        icon: Icons.flag_outlined,
      );
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
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
          'What is wrong with it?',
          style: context.kt.callout.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s3),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final reason in ReportReason.values)
                  _ReasonRow(
                    reason: reason,
                    selected: _reason == reason,
                    onTap: () => setState(() => _reason = reason),
                  ),
                if (_reason == ReportReason.other) ...<Widget>[
                  const SizedBox(height: Space.s3),
                  KTextField(
                    controller: _details,
                    hint: 'Tell us what happened',
                    maxLines: 3,
                    minLines: 2,
                    maxLength: 500,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: Space.s3),
          Text(
            _error!,
            style: context.kt.caption.copyWith(color: colors.semanticDanger),
          ),
        ],
        const SizedBox(height: Space.s5),
        KButton(
          label: 'Submit report',
          expand: true,
          busy: _busy,
          variant: KButtonVariant.danger,
          onPressed: _reason == null ? null : _submit,
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final ReportReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: selected ? '${reason.label}, selected' : reason.label,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.s2),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.semanticDangerSubtle : colors.surface2,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected ? colors.semanticDanger : colors.borderSubtle,
            width: Strokes.thin,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                reason.label,
                style: context.kt.body.copyWith(
                  color: selected ? colors.semanticDanger : colors.textPrimary,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: Space.s5,
              color: selected ? colors.semanticDanger : colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
