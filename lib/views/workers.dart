import 'package:material_ui/material_ui.dart';

import '../l10n.dart';
import '../gamedb.dart';
import '../obj.dart';
import '../references.dart';
import '../save_doc.dart';
import '../widgets.dart';

class WorkersView extends StatelessWidget {
  final SaveDoc doc;
  final VoidCallback onChanged;
  const WorkersView({super.key, required this.doc, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final db = GameDb.I;
    final root = O(doc, doc.root!);
    final list = root.o('Workers');
    final workers = list?.items('Workers') ?? const [];
    final skillsAll = db.choices('WorkerSkillInfo');
    return ListView(padding: const EdgeInsets.only(top: 8, bottom: 110), children: [
      if (workers.isEmpty) Center(child: emptyNote(context, t('No workers hired in this save. Hire one in game first; after that you can add copies here.'))),
      for (final w in workers) _worker(context, w, skillsAll),
    ]);
  }

  Widget _worker(BuildContext context, O w, List<GameAsset> skillsAll) {
    final db = GameDb.I;
    final s = w.o('Settings')!;
    final info = s.o('PersonalInfo');
    final skills = s.o('Skills')?.items('Skills') ?? const [];
    final have = {for (final k in skills) k.str('SkillGuid') ?? ''};
    final missing = [for (final a in skillsAll) if (!have.contains(a.guid)) a];
    return Section(
      title: info?.str('Name') ?? t('Worker'),
      subtitle: s.boolean('Volunteer') == true ? t('Volunteer') : t('Employee'),
      trailing: PopupMenuButton<String>(
        tooltip: t('More'),
        onSelected: (v) => v == 'dup' ? _hireCopy(context, w) : _fire(context, w),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'dup', child: ListTile(leading: const Icon(Icons.person_add_alt), title: Text(t('Hire a copy')))),
          PopupMenuItem(value: 'del', child: ListTile(leading: const Icon(Icons.person_remove_outlined), title: Text(t('Fire worker')))),
        ],
      ),
      children: [
        if (info != null)
          TextRow(
              label: t('Name'),
              value: info.str('Name') ?? '',
              maxLength: 32,
              onChanged: (v) {
                if (v.trim().isEmpty) return;
                info.setStr('Name', v.trim());
                onChanged();
              }),
        NumRow(
            label: t('Daily wage'),
            value: s.dbl('Wage') ?? 0,
            min: 0,
            max: 100000,
            decimals: true,
            onChanged: (v) {
              s.setNum('Wage', v);
              onChanged();
            }),
        SwitchRow(
            label: t('Volunteer'),
            hint: t('Volunteers work without a wage'),
            value: s.boolean('Volunteer') ?? false,
            onChanged: (v) {
              s.setBool('Volunteer', v);
              onChanged();
            }),
        const SizedBox(height: 4),
        for (final k in skills)
          NumRow(
            label: db.name(k.str('SkillGuid')) ?? t('Unknown skill'),
            hint: db.description(k.str('SkillGuid')),
            value: k.integer('Level') ?? 0,
            min: 0,
            max: 100, // WorkerSkill.MaxLevel
            slider: true,
            onChanged: (v) {
              k.setNum('Level', v);
              onChanged();
            },
          ),
        if (missing.isNotEmpty && skills.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, children: [
              for (final m in missing)
                TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t('Add {0}', [db.name(m.guid) ?? 'skill'])),
                    onPressed: () {
                      final c = s.o('Skills')!.addClone('Skills', skills.first);
                      c.setStr('SkillGuid', m.guid);
                      c.setNum('Level', 0);
                      onChanged();
                    }),
            ]),
          ),
      ],
    );
  }

  Future<void> _hireCopy(BuildContext context, O w) async {
    final old = w.o('Settings')?.o('PersonalInfo')?.str('Name') ?? t('Worker');
    final ctl = TextEditingController(text: '$old 2');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Hire a copy')),
        content: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 32,
            decoration: InputDecoration(labelText: t('Name of the new worker'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(t('Hire'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    duplicateWorker(doc, w, name);
    onChanged();
  }

  Future<void> _fire(BuildContext context, O w) async {
    final why = workerRemovalBlocker(w);
    if (why != null) return toast(context, why);
    final name = w.o('Settings')?.o('PersonalInfo')?.str('Name') ?? t('this worker');
    if (!await confirm(context, t('Fire {0}?', [name]), t('The worker leaves and the items they were carrying are removed.'),
        ok: t('Fire'))) {
      return;
    }
    removeWorker(doc, w);
    onChanged();
  }
}
