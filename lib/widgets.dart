import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'gamedb.dart';
import 'ui_kit.dart';

/// Card with a title and rows.
class Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;
  const Section({super.key, required this.title, this.subtitle, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.tt.titleMedium),
                  if (subtitle != null)
                    Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}

/// Label + number box (+ optional slider). Calls [onChanged] with the parsed, clamped value.
class NumRow extends StatefulWidget {
  final String label;
  final String? hint;
  final num value;
  final num? min, max;
  final bool decimals;
  final bool slider;
  final ValueChanged<num> onChanged;
  const NumRow(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.min,
      this.max,
      this.decimals = false,
      this.slider = false,
      this.hint});

  @override
  State<NumRow> createState() => _NumRowState();
}

class _NumRowState extends State<NumRow> {
  late final TextEditingController c = TextEditingController(text: _fmt(widget.value));
  final focus = FocusNode();

  String _fmt(num v) => widget.decimals ? _trim(v.toDouble()) : v.round().toString();
  static String _trim(double d) {
    var s = d.toStringAsFixed(2);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s;
  }

  @override
  void didUpdateWidget(NumRow old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && old.value != widget.value) c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    c.dispose();
    focus.dispose();
    super.dispose();
  }

  num _clamp(num v) {
    if (widget.min != null && v < widget.min!) v = widget.min!;
    if (widget.max != null && v > widget.max!) v = widget.max!;
    return v;
  }

  void _commit() {
    final v = num.tryParse(c.text.replaceAll(',', '.').trim());
    if (v == null) {
      c.text = _fmt(widget.value);
      return;
    }
    final cl = _clamp(widget.decimals ? v : v.round());
    c.text = _fmt(cl);
    if (cl != widget.value) widget.onChanged(cl);
  }

  @override
  Widget build(BuildContext context) {
    final showSlider = widget.slider && widget.min != null && widget.max != null && widget.max! > widget.min!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: context.tt.bodyLarge),
            if (widget.hint != null)
              Text(widget.hint!, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ]),
        ),
        if (showSlider)
          Expanded(
            flex: 5,
            child: Slider(
              value: _clamp(widget.value).toDouble(),
              min: widget.min!.toDouble(),
              max: widget.max!.toDouble(),
              onChanged: (v) {
                final nv = widget.decimals ? double.parse(v.toStringAsFixed(2)) : v.round();
                c.text = _fmt(nv);
                widget.onChanged(nv);
              },
            ),
          ),
        SizedBox(
          width: 112,
          child: TextField(
            controller: c,
            focusNode: focus,
            textAlign: TextAlign.end,
            keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals, signed: (widget.min ?? -1) < 0),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) {
              if (focus.hasFocus) {
                _commit();
                focus.unfocus();
              }
            },
          ),
        ),
      ]),
    );
  }
}

/// Label + text box.
class TextRow extends StatefulWidget {
  final String label;
  final String? hint;
  final String value;
  final ValueChanged<String> onChanged;
  final int? maxLength;
  const TextRow({super.key, required this.label, required this.value, required this.onChanged, this.hint, this.maxLength});

  @override
  State<TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<TextRow> {
  late final TextEditingController c = TextEditingController(text: widget.value);
  final focus = FocusNode();

  @override
  void didUpdateWidget(TextRow old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && old.value != widget.value) c.text = widget.value;
  }

  @override
  void dispose() {
    c.dispose();
    focus.dispose();
    super.dispose();
  }

  void _commit() {
    if (c.text != widget.value) widget.onChanged(c.text);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label, style: context.tt.bodyLarge),
              if (widget.hint != null)
                Text(widget.hint!, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
            ]),
          ),
          Expanded(
            flex: 6,
            child: TextField(
              controller: c,
              focusNode: focus,
              maxLength: widget.maxLength,
              decoration: const InputDecoration(
                  isDense: true, counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) {
                if (focus.hasFocus) {
                  _commit();
                  focus.unfocus();
                }
              },
            ),
          ),
        ]),
      );
}

class SwitchRow extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: context.tt.bodyLarge),
        subtitle: hint == null ? null : Text(hint!, style: context.tt.bodySmall),
        value: value,
        onChanged: onChanged,
      );
}

/// Label + dropdown of game assets.
class AssetDropdownRow extends StatelessWidget {
  final String label;
  final String? value; // guid
  final List<GameAsset> choices;
  final ValueChanged<String> onChanged;
  final String? hint;
  const AssetDropdownRow(
      {super.key, required this.label, required this.value, required this.choices, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) {
    final db = GameDb.I;
    final known = choices.any((a) => a.guid == value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: context.tt.bodyLarge),
            if (hint != null) Text(hint!, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ]),
        ),
        Expanded(
          flex: 6,
          child: DropdownButtonFormField<String>(
            key: ValueKey(value),
            initialValue: known ? value : null,
            isExpanded: true,
            hint: Text(value == null || value!.isEmpty ? t('None') : (db.name(value) ?? value!)),
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            items: [
              for (final a in choices)
                DropdownMenuItem(value: a.guid, child: Text(db.name(a.guid) ?? a.internal, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null && v != value) onChanged(v);
            },
          ),
        ),
      ]),
    );
  }
}

/// Removable chip showing a game asset by name, description as tooltip.
class AssetChip extends StatelessWidget {
  final String guid;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final Widget? avatar;
  final String? suffix;
  const AssetChip({super.key, required this.guid, this.onDelete, this.onTap, this.avatar, this.suffix});

  @override
  Widget build(BuildContext context) {
    final db = GameDb.I;
    final n = db.name(guid) ?? (guid.isEmpty ? t('(empty)') : t('Unknown {0}…', [guid.substring(0, guid.length.clamp(0, 8))]));
    final d = db.description(guid);
    final chip = InputChip(
      avatar: avatar,
      label: Text(suffix == null ? n : '$n  $suffix'),
      onDeleted: onDelete,
      onPressed: onTap,
      deleteButtonTooltipMessage: t('Remove'),
    );
    return d == null ? chip : Tooltip(message: d, waitDuration: const Duration(milliseconds: 400), child: chip);
  }
}

/// Searchable list of game assets; returns the picked one.
Future<GameAsset?> pickAsset(BuildContext context, String title, List<GameAsset> choices,
    {Set<String> exclude = const {}, String Function(GameAsset)? group}) {
  return showDialog<GameAsset>(
    context: context,
    builder: (ctx) => _PickerDialog(title: title, choices: [for (final a in choices) if (!exclude.contains(a.guid)) a], group: group),
  );
}

class _PickerDialog extends StatefulWidget {
  final String title;
  final List<GameAsset> choices;
  final String Function(GameAsset)? group;
  const _PickerDialog({required this.title, required this.choices, this.group});

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final db = GameDb.I;
    final ql = q.toLowerCase();
    final list = [
      for (final a in widget.choices)
        if (ql.isEmpty ||
            (db.name(a.guid) ?? '').toLowerCase().contains(ql) ||
            a.internal.toLowerCase().contains(ql) ||
            (db.description(a.guid) ?? '').toLowerCase().contains(ql))
          a
    ];
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('Search')),
            onChanged: (v) => setState(() => q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(t('Nothing matches.')))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final a = list[i];
                      final d = db.description(a.guid);
                      final g = widget.group?.call(a);
                      return ListTile(
                        title: Text(db.name(a.guid) ?? a.internal),
                        subtitle: Text([if (g != null) g, if (d != null) d].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, a),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Cancel')))],
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String text, {String? ok}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok ?? t('Remove'))),
      ],
    ),
  );
  return r == true;
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

Widget emptyNote(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
    );
