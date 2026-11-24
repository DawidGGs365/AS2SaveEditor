import 'package:material_ui/material_ui.dart';

import '../l10n.dart';
import '../gamedb.dart';
import '../obj.dart';
import '../save_doc.dart';
import '../ui_kit.dart';
import '../widgets.dart';

class ProgressView extends StatelessWidget {
  final SaveDoc doc;
  final VoidCallback onChanged;
  const ProgressView({super.key, required this.doc, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final root = O(doc, doc.root!);
    return ListView(padding: const EdgeInsets.only(top: 8, bottom: 110), children: [
      _unlocks(context, root),
      _quests(context, root),
    ]);
  }

  Widget _unlocks(BuildContext context, O root) {
    final db = GameDb.I;
    final have = root.strings('UnlockedPadlocks');
    final cls = db.classForField('SaveData', 'UnlockedPadlocks') ?? 'Padlock';
    final known = have.where((g) => db.asset(g) != null).toList()
      ..sort((a, b) => (db.name(a) ?? '').compareTo(db.name(b) ?? ''));
    final other = have.where((g) => db.asset(g) == null).length;
    return Section(
      title: t('Unlocks'),
      subtitle: t('Game progression locks (tutorial steps, pet types, features) that are open in this save'),
      trailing: FilledButton.tonalIcon(
          icon: const Icon(Icons.lock_open),
          label: Text(t('Unlock')),
          onPressed: () async {
            final pick = await pickAsset(context, t('Unlock'), db.choices(cls), exclude: have.toSet());
            if (pick == null) return;
            root.addString('UnlockedPadlocks', pick.guid);
            onChanged();
          }),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in known)
            AssetChip(
                guid: g,
                onDelete: () {
                  root.removeString('UnlockedPadlocks', g);
                  onChanged();
                }),
        ]),
        if (other > 0) emptyNote(context, t('+ {0} entries from mods or not in the game data (kept as they are)', [other])),
      ],
    );
  }

  Widget _quests(BuildContext context, O root) {
    final db = GameDb.I;
    final q = root.o('Quests');
    if (q == null) return const SizedBox.shrink();
    final done = q.items('CompletedQuests');
    final open = q.items('InProgressQuests');
    Widget list(List<O> l) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in l) Chip(label: Text(db.name(x.str('Guid')) ?? t('Unknown quest'))),
        ]);
    return Section(title: t('Quests'), subtitle: t('{0} completed · {1} in progress', [done.length, open.length]), children: [
      if (open.isNotEmpty) ...[
        Text(t('In progress'), style: context.tt.labelLarge?.copyWith(color: context.cs.primary)),
        const SizedBox(height: 4),
        list(open),
        const SizedBox(height: 12),
      ],
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(t('Completed'), style: context.tt.labelLarge?.copyWith(color: context.cs.primary)),
        children: [list(done)],
      ),
    ]);
  }
}
