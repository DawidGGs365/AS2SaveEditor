import 'l10n.dart';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'graph.dart';
import 'widgets.dart' show confirm;

import 'gamedb.dart';
import 'nrbf.dart';
import 'save_doc.dart';
import 'tree_util.dart';
import 'ui_kit.dart';

Future<String?> askText(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        style: ctx.tt.bodyLarge,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t('Apply'))),
      ],
    ),
  );
}

/// Builds the editable rows/nodes for any part of the save tree.
class TreeUi {
  final SaveDoc doc;
  final VoidCallback onChanged;
  final VoidCallback refresh;
  TreeUi(this.doc, this.onChanged, this.refresh);

  static const maxItems = 300;

  Future<void> edit(BuildContext c, String title, Editable e) async {
    if (!e.editable) return;
    final v = await askText(c, '$title (${e.type})', e.get());
    if (v == null || !c.mounted) return;
    apply(c, e, v);
  }

  void apply(BuildContext c, Editable e, String v) {
    if (e.set(v)) {
      onChanged();
      refresh();
    } else if (c.mounted) {
      ScaffoldMessenger.of(c)
          .showSnackBar(SnackBar(content: Text(t('That value is not valid here.'))));
    }
  }

  Widget editRow(BuildContext c, String label, Editable e, {String? subtitle, int depth = 0}) {
    if (subtitle == null && e.type == 'string') {
      final n = GameDb.instance?.name(e.get());
      final cls = GameDb.instance?.asset(e.get())?.cls;
      if (n != null) subtitle = '$n · $cls';
    }
    final isBool = e.type == 'bool' && e.editable;
    if (isBool) {
      final on = e.get() == 'true';
      return LeafRow(
        depth: depth,
        title: label,
        subtitle: subtitle ?? e.lockedReason ?? e.type,
        trailing: Switch(value: on, onChanged: (v) => apply(c, e, v ? 'true' : 'false')),
        onTap: () => apply(c, e, on ? 'false' : 'true'),
      );
    }
    return LeafRow(
      depth: depth,
      title: label,
      subtitle: subtitle ?? e.lockedReason ?? e.type,
      trailing: ValuePill(e.get()),
      onTap: e.editable ? () => edit(c, label, e) : null,
    );
  }

  Widget nullRow(String label, int depth) => LeafRow(
      depth: depth, title: label, trailing: const ValuePill('null', muted: true));

  Widget note(String text, int depth) =>
      LeafRow(depth: depth, title: text, trailing: const SizedBox.shrink());

  Widget slotRow(BuildContext c, String label, Slot? s, {int depth = 0}) {
    if (s == null) return nullRow(label, depth);
    if (s.p != null) return editRow(c, label, Editable.fromPrim(s.p!), depth: depth);
    final r = doc.deref(s.r);
    if (r == null) return nullRow(label, depth);
    return recRow(c, label, r, depth: depth);
  }

  String _short(String n) => n.contains('[[') ? n.substring(0, n.indexOf('[[')) : n;

  Widget recRow(BuildContext c, String label, Rec r, {int depth = 0}) {
    switch (r.t) {
      case 6:
        return editRow(c, label, Editable.fromString(r), depth: depth);
      case 10:
      case 13:
      case 14:
        return nullRow(label, depth);
      case 15:
        return TreeNode(
          depth: depth,
          title: label,
          subtitle: t('{0} array · {1} values', [primTypeName(r.pt), r.n]),
          build: () {
            doc.ensurePrimList(r);
            final list = r.primList ?? const <Prim>[];
            return [
              for (var i = 0; i < list.length && i < maxItems; i++)
                editRow(c, '[$i]', Editable.fromPrim(list[i]), depth: depth + 1),
              if (list.length > maxItems) note(t('… {0} more not shown', [list.length - maxItems]), depth + 1),
            ];
          },
        );
      case 7:
      case 16:
      case 17:
        final items = r.items ?? const <Slot>[];
        return TreeNode(
          depth: depth,
          title: label,
          subtitle: t('array · {0} items', [items.length]),
          build: () => [
            for (var i = 0; i < items.length && i < maxItems; i++)
              slotRow(c, '[$i]', items[i], depth: depth + 1),
            if (items.length > maxItems) note(t('… {0} more not shown', [items.length - maxItems]), depth + 1),
          ],
        );
    }
    if (!doc.isClass(r)) return nullRow(t('{0} (record {1})', [label, r.t]), depth);

    if (doc.isEnum(r)) {
      final en = _short(doc.className(r));
      final v = int.tryParse(primToText(r.vals!.first.p!) ?? '');
      final nm = v == null ? null : GameDb.instance?.enums[en]?[v];
      return editRow(c, label, Editable.fromPrim(r.vals!.first.p!),
          subtitle: nm == null ? t('enum {0}', [en]) : t('{0} · enum {1}', [nm, en]), depth: depth);
    }
    if (doc.isList(r)) {
      final items = doc.listItems(r);
      return TreeNode(
        depth: depth,
        title: label,
        subtitle: t('list · {0} items', [items.length]),
        build: () => [
          for (var i = 0; i < items.length && i < maxItems; i++) _listItem(c, r, i, items[i], depth + 1),
          if (items.length > maxItems) note(t('… {0} more not shown', [items.length - maxItems]), depth + 1),
        ],
      );
    }
    if (doc.isDict(r)) {
      final entries = doc.dictEntries(r);
      return TreeNode(
        depth: depth,
        title: label,
        subtitle: t('dictionary · {0} entries', [entries.length]),
        build: () => [
          for (var i = 0; i < entries.length && i < maxItems; i++)
            slotRow(c, doc.slotText(entries[i].key), entries[i].value, depth: depth + 1),
          if (entries.length > maxItems) note(t('… {0} more not shown', [entries.length - maxItems]), depth + 1),
        ],
      );
    }
    final names = r.ci!.memberNames;
    return TreeNode(
      depth: depth,
      title: label,
      subtitle: [_short(doc.className(r)), doc.summary(r)].whereType<String>().join(' · '),
      build: () => [
        for (var i = 0; i < r.vals!.length && i < names.length; i++)
          if (!isNoiseField(names[i]))
            slotRow(c, displayName(names[i]), r.vals![i], depth: depth + 1),
      ],
    );
  }

  Widget _listItem(BuildContext c, Rec list, int i, Slot? s, int depth) {
    final rr = s == null ? null : doc.deref(s.r);
    final sum = rr == null ? null : doc.summary(rr);
    final row = slotRow(c, sum == null ? '[$i]' : '[$i]  $sum', s, depth: depth);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: row),
      PopupMenuButton<String>(
        tooltip: t('List entry'),
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (a) async {
          final g = doc.graph;
          if (a == 'delete') {
            if (!await confirm(c, t('Delete entry'), t('Remove entry [{0}] from this list?', [i]))) return;
            g.listRemoveAt(list, i);
          } else if (a == 'dup') {
            if (rr == null) {
              g.listAdd(list, Slot.rec(Rec(10)));
            } else if (s!.p != null) {
              g.listAdd(list, Slot.prim(Prim(s.p!.type, Uint8List.fromList(s.p!.raw))));
            } else if (rr.t == 6) {
              g.listAdd(list, Slot.rec(Rec(9)..ref = g.newString(rr.stringValue).oid));
            } else {
              g.listAdd(list, Slot.rec(Rec(9)..ref = objId(g.deepClone(rr))));
            }
          }
          doc.structural = true;
          onChanged();
          refresh();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'dup', child: Text(t('Duplicate'))),
          PopupMenuItem(value: 'delete', child: Text(t('Delete'))),
        ],
      ),
    ]);
  }
}

Widget emptyHint(BuildContext c, IconData icon, String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: c.cs.outline),
          const SizedBox(height: 16),
          Text(text,
              textAlign: TextAlign.center,
              style: c.tt.bodyLarge?.copyWith(color: c.cs.onSurfaceVariant)),
        ]),
      ),
    );

const _listPad = EdgeInsets.only(top: 8, bottom: 110);

class BrowseView extends StatefulWidget {
  final SaveDoc doc;
  final VoidCallback onChanged;
  const BrowseView({super.key, required this.doc, required this.onChanged});
  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final root = doc.root;
    if (root == null) return emptyHint(context, Icons.error_outline, t('No root object found.'));
    final ui = TreeUi(doc, widget.onChanged, () => setState(() {}));
    final names = root.ci!.memberNames;
    return ListView(padding: _listPad, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            for (var i = 0; i < root.vals!.length && i < names.length; i++)
              ui.slotRow(context, displayName(names[i]), root.vals![i]),
          ]),
        ),
      ),
    ]);
  }
}

/// ---------------- Search ----------------
class SearchView extends StatefulWidget {
  final SaveDoc doc;
  final VoidCallback onChanged;
  const SearchView({super.key, required this.doc, required this.onChanged});
  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final ctl = TextEditingController();
  List<SearchHit> hits = const [];
  String lastQuery = '';

  void run(String q) {
    lastQuery = q;
    setState(() => hits = q.trim().length < 2 ? const [] : searchSave(widget.doc, q));
  }

  @override
  Widget build(BuildContext context) {
    final ui = TreeUi(widget.doc, widget.onChanged, () => run(lastQuery));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: TextField(
          controller: ctl,
          style: context.tt.bodyLarge,
          decoration: InputDecoration(
            hintText: t('Search field names and values'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: run,
        ),
      ),
      Expanded(
        child: hits.isEmpty
            ? emptyHint(context, Icons.search,
                lastQuery.trim().length < 2 ? t('Type at least 2 letters.') : t('Nothing found.'))
            : ListView.builder(
                padding: _listPad,
                itemCount: hits.length + (hits.length >= 300 ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i == hits.length) {
                    return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(t('Showing the first 300 matches. Narrow the search.'),
                            style: c.tt.bodyMedium));
                  }
                  final h = hits[i];
                  return Card(
                    child: InkWell(
                      onTap: h.edit.editable
                          ? () => ui.edit(c, h.path.split(' › ').last, h.edit)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(h.value.isEmpty ? t('(empty)') : h.value,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: c.tt.titleMedium),
                          const SizedBox(height: 4),
                          Text('${h.path}  ·  ${h.edit.type}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: c.tt.bodySmall?.copyWith(color: c.cs.onSurfaceVariant)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
