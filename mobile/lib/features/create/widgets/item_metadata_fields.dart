import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../create_providers.dart';

/// The mutable state of an item form.
///
/// Held by whichever screen or sheet is editing, so the field widgets stay
/// stateless and the same form serves both "new item" and "edit item".
class ItemDraft {
  /// Creates a draft, optionally pre-filled from an existing row.
  ItemDraft({ItemModel? from})
      : title = TextEditingController(text: from?.title ?? ''),
        description = TextEditingController(text: from?.description ?? ''),
        brand = TextEditingController(text: from?.brand ?? ''),
        model = TextEditingController(text: from?.model ?? ''),
        year = TextEditingController(text: from?.year?.toString() ?? ''),
        acquisitionPlace =
            TextEditingController(text: from?.acquisitionPlace ?? ''),
        price = TextEditingController(
          text: from?.purchasePrice == null
              ? ''
              : _trimZeros(from!.purchasePrice!),
        ),
        condition = from?.condition,
        rarity = from?.rarity,
        acquisitionDate = from?.acquisitionDate,
        currency = from?.currency ?? kCurrencyOptions.first,
        isFavorite = from?.isFavorite ?? false,
        visibility = from?.visibility,
        tags = <String>[...asStringList(from?.attributes['tags'])];

  /// Item title. Required.
  final TextEditingController title;

  /// Long description.
  final TextEditingController description;

  /// Maker or publisher.
  final TextEditingController brand;

  /// Model designation.
  final TextEditingController model;

  /// Year of manufacture or release.
  final TextEditingController year;

  /// Where it was acquired.
  final TextEditingController acquisitionPlace;

  /// What was paid, as typed.
  final TextEditingController price;

  /// Condition grade.
  String? condition;

  /// Rarity grade.
  String? rarity;

  /// When it was acquired.
  DateTime? acquisitionDate;

  /// ISO currency code for [price].
  String currency;

  /// Owner's favourite flag.
  bool isFavorite;

  /// Explicit visibility; null inherits from the subcollection.
  EntityVisibility? visibility;

  /// Free tags, stored under `attributes.tags`.
  List<String> tags;

  /// The parsed year, or null when the box is empty or nonsense.
  int? get yearValue {
    final text = year.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  /// The parsed price, or null when the box is empty or nonsense.
  double? get priceValue {
    final text = price.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  /// The `attributes` jsonb payload this draft produces.
  ///
  /// `entity_tags` has no write path in the client API contract, so tags live
  /// here — free-form, searchable through the item row, and losslessly
  /// round-tripped by the edit form.
  Map<String, dynamic> attributes(Map<String, dynamic> existing) {
    final next = Map<String, dynamic>.from(existing);
    if (tags.isEmpty) {
      next.remove('tags');
    } else {
      next['tags'] = tags;
    }
    return next;
  }

  /// True when the user has typed anything worth confirming a discard over.
  bool get isDirty =>
      title.text.trim().isNotEmpty ||
      description.text.trim().isNotEmpty ||
      brand.text.trim().isNotEmpty ||
      model.text.trim().isNotEmpty ||
      year.text.trim().isNotEmpty ||
      acquisitionPlace.text.trim().isNotEmpty ||
      price.text.trim().isNotEmpty ||
      condition != null ||
      rarity != null ||
      acquisitionDate != null ||
      tags.isNotEmpty;

  /// Releases the controllers.
  void dispose() {
    title.dispose();
    description.dispose();
    brand.dispose();
    model.dispose();
    year.dispose();
    acquisitionPlace.dispose();
    price.dispose();
  }

  static String _trimZeros(double value) {
    final text = value.toStringAsFixed(2);
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }
}

/// The optional half of an item form: everything below title and photos.
class ItemMetadataFields extends StatelessWidget {
  /// Creates the metadata block.
  const ItemMetadataFields({
    required this.draft,
    required this.onChanged,
    super.key,
    this.enabled = true,
    this.suggestedTags = const <String>[],
  });

  /// The form state this block mutates.
  final ItemDraft draft;

  /// Called after any mutation so the owner can `setState`.
  final VoidCallback onChanged;

  /// Disables interaction while a save is in flight.
  final bool enabled;

  /// Tags suggested by the collection's template.
  final List<String> suggestedTags;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: KTextField(
                controller: draft.brand,
                label: 'Maker',
                hint: 'Shueisha',
                enabled: enabled,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: KTextField(
                controller: draft.model,
                label: 'Model',
                hint: 'Vol. 11',
                enabled: enabled,
                maxLength: 80,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: Space.s24,
              child: KTextField(
                controller: draft.year,
                label: 'Year',
                hint: '2007',
                enabled: enabled,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: _AcquisitionDateField(
                value: draft.acquisitionDate,
                enabled: enabled,
                onChanged: (value) {
                  draft.acquisitionDate = value;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        KTextField(
          controller: draft.acquisitionPlace,
          label: 'Where it came from',
          hint: 'Mandarake, Nakano',
          enabled: enabled,
          maxLength: 120,
        ),
        const SizedBox(height: Space.s4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: KTextField(
                controller: draft.price,
                label: 'Paid',
                hint: '48',
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            _CurrencyField(
              value: draft.currency,
              enabled: enabled,
              onChanged: (value) {
                draft.currency = value;
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: Space.s5),
        _ChipGroup(
          label: 'Condition',
          options: kConditionOptions,
          selected: draft.condition,
          enabled: enabled,
          onSelected: (value) {
            draft.condition = value;
            onChanged();
          },
        ),
        const SizedBox(height: Space.s4),
        _ChipGroup(
          label: 'Rarity',
          options: kRarityOptions,
          selected: draft.rarity,
          enabled: enabled,
          onSelected: (value) {
            draft.rarity = value;
            onChanged();
          },
        ),
        const SizedBox(height: Space.s5),
        TagField(
          tags: draft.tags,
          suggestions: suggestedTags,
          enabled: enabled,
          onChanged: (next) {
            draft.tags = next;
            onChanged();
          },
        ),
        const SizedBox(height: Space.s4),
        Row(
          children: <Widget>[
            Icon(
              Icons.star_rounded,
              size: Space.s5,
              color: draft.isFavorite
                  ? colors.accentDefault
                  : colors.textTertiary,
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text('One of my favourites', style: context.kt.body),
            ),
            Switch(
              value: draft.isFavorite,
              onChanged: enabled
                  ? (value) {
                      draft.isFavorite = value;
                      onChanged();
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Free-text tags with template suggestions.
class TagField extends StatefulWidget {
  /// Creates a tag editor.
  const TagField({
    required this.tags,
    required this.onChanged,
    super.key,
    this.suggestions = const <String>[],
    this.enabled = true,
    this.maxTags = 12,
  });

  /// Current tags.
  final List<String> tags;

  /// Fired with the new list.
  final ValueChanged<List<String>> onChanged;

  /// Tags the collection's template suggests.
  final List<String> suggestions;

  /// Disables interaction while a save is in flight.
  final bool enabled;

  /// Ceiling, so the field cannot become a keyword dump.
  final int maxTags;

  @override
  State<TagField> createState() => _TagFieldState();
}

class _TagFieldState extends State<TagField> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    if (value.isEmpty ||
        widget.tags.contains(value) ||
        widget.tags.length >= widget.maxTags) {
      _input.clear();
      return;
    }
    widget.onChanged(<String>[...widget.tags, value]);
    _input.clear();
  }

  void _remove(String value) => widget.onChanged(
        <String>[
          for (final tag in widget.tags)
            if (tag != value) tag,
        ],
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final unused = <String>[
      for (final suggestion in widget.suggestions)
        if (!widget.tags.contains(suggestion)) suggestion,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Tags',
          style: context.kt.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s2),
        if (widget.tags.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: <Widget>[
              for (final tag in widget.tags)
                KChip(
                  label: '#$tag',
                  selected: true,
                  dense: true,
                  onRemove: widget.enabled ? () => _remove(tag) : null,
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
        ],
        KTextField(
          controller: _input,
          hint: 'Add a tag and press return',
          enabled: widget.enabled && widget.tags.length < widget.maxTags,
          textInputAction: TextInputAction.done,
          maxLength: 24,
          onSubmitted: _add,
          suffix: KIconButton(
            icon: Icons.add_rounded,
            semanticLabel: 'Add tag',
            onPressed: widget.enabled ? () => _add(_input.text) : null,
          ),
        ),
        if (unused.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.s2),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: <Widget>[
              for (final suggestion in unused)
                KChip(
                  label: '#$suggestion',
                  dense: true,
                  onTap: widget.enabled ? () => _add(suggestion) : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: context.kt.label.copyWith(color: colors.textSecondary)),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: <Widget>[
            for (final option in options)
              KChip(
                label: option,
                dense: true,
                selected: option == selected,
                onTap: enabled
                    ? () => onSelected(option == selected ? null : option)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _AcquisitionDateField extends StatelessWidget {
  const _AcquisitionDateField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final label = value == null
        ? 'Pick a date'
        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-'
            '${value!.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Acquired',
          style: context.kt.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s15),
        KPressable(
          enabled: enabled,
          semanticLabel: 'Acquisition date',
          enforceMinTapTarget: false,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 120),
              lastDate: now,
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            height: Space.s12,
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: colors.borderSubtle,
                width: Strokes.thin,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.event_rounded,
                  size: Space.s5,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text(
                    label,
                    style: context.kt.body.copyWith(
                      color: value == null
                          ? colors.textTertiary
                          : colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (value != null && enabled)
                  KIconButton(
                    icon: Icons.close_rounded,
                    semanticLabel: 'Clear date',
                    size: Space.s4,
                    onPressed: () => onChanged(null),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Currency',
          style: context.kt.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s15),
        Container(
          height: Space.s12,
          padding: const EdgeInsets.symmetric(horizontal: Space.s3),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              borderRadius: BorderRadius.circular(Radii.md),
              dropdownColor: colors.surface3,
              style: context.kt.body,
              icon: Icon(
                Icons.expand_more_rounded,
                size: Space.s5,
                color: colors.textTertiary,
              ),
              onChanged: enabled
                  ? (next) {
                      if (next != null) onChanged(next);
                    }
                  : null,
              items: <DropdownMenuItem<String>>[
                for (final code in kCurrencyOptions)
                  DropdownMenuItem<String>(value: code, child: Text(code)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
