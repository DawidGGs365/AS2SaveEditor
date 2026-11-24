import 'package:material_ui/material_ui.dart';

import '../l10n.dart';
import '../gamedb.dart';
import '../obj.dart';
import '../references.dart';
import '../save_doc.dart';
import '../ui_kit.dart';
import '../widgets.dart';

/// Display name of a pet: custom name if set, otherwise the game's localized name term.
String petName(O pet) {
  final st = pet.o('PetStaticInfo');
  final custom = st?.str('CustomName') ?? '';
  if (custom.trim().isNotEmpty) return custom;
  final term = st?.o('PetName')?.str('mTerm');
  return GameDb.I.tr(term) ?? term ?? t('Pet #{0}', [st?.integer('PetID') ?? '?']);
}

String petBreed(O pet) => GameDb.I.name(pet.o('PetStaticInfo')?.str('PetBreedGuid')) ?? t('Unknown breed');

class PetsView extends StatefulWidget {
  final SaveDoc doc;
  final VoidCallback onChanged;
  const PetsView({super.key, required this.doc, required this.onChanged});
  @override
  State<PetsView> createState() => _PetsViewState();
}

class _PetsViewState extends State<PetsView> {
  O? open;

  @override
  Widget build(BuildContext context) {
    final root = O(widget.doc, widget.doc.root!);
    final pets = root.path('PetsSaveData')?.items('PetSaveInfos') ?? const [];
    if (open != null && pets.contains(open)) {
      return PetEditor(
        doc: widget.doc,
        pet: open!,
        onChanged: () {
          widget.onChanged();
          setState(() {});
        },
        onBack: () => setState(() => open = null),
        onOpen: (p) => setState(() => open = p),
      );
    }
    if (pets.isEmpty) return Center(child: emptyNote(context, t('No pets in this save.')));
    return ListView(padding: const EdgeInsets.only(top: 8, bottom: 110), children: [
      for (final p in pets) _petCard(context, p),
    ]);
  }

  Widget _petCard(BuildContext context, O p) {
    final db = GameDb.I;
    final st = p.o('PetStaticInfo');
    final stage = db.name(p.o('PetAgeSaveData')?.str('StageGuid'));
    final disease = db.name(p.o('DiseaseSaveInfo')?.str('Guid'));
    final perks = p.o('PerksSaveInfo')?.items('PerksInfo') ?? const [];
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(child: Text(petName(p).characters.first.toUpperCase())),
        title: Text(petName(p), style: context.tt.titleMedium),
        subtitle: Text([
          petBreed(p),
          if (stage != null) stage,
          t('{0} perks', [perks.length]),
          if (disease != null) '🩺 $disease',
          if (st?.boolean('AdoptedByPlayer') == true || p.boolean('AdoptedByPlayer') == true) t('adopted by you'),
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => open = p),
      ),
    );
  }
}

class PetEditor extends StatelessWidget {
  final SaveDoc doc;
  final O pet;
  final VoidCallback onChanged;
  final VoidCallback onBack;
  final ValueChanged<O?> onOpen;
  const PetEditor(
      {super.key, required this.doc, required this.pet, required this.onChanged, required this.onBack, required this.onOpen});

  GameDb get db => GameDb.I;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(top: 4, bottom: 110), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Row(children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back), tooltip: t('All pets')),
          Expanded(child: Text(petName(pet), style: context.tt.headlineSmall)),
          Text(petBreed(pet), style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
          PopupMenuButton<String>(
            tooltip: t('More'),
            onSelected: (v) => v == 'dup' ? _duplicate(context) : _delete(context),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'dup', child: ListTile(leading: const Icon(Icons.copy), title: Text(t('Duplicate pet')))),
              PopupMenuItem(value: 'del', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(t('Remove pet')))),
            ],
          ),
        ]),
      ),
      _identity(context),
      _perks(context),
      _needs(context),
      _commands(context),
      _health(context),
      _adopters(context),
      _looks(context),
    ]);
  }

  void _duplicate(BuildContext context) {
    final c = duplicatePet(doc, pet);
    onChanged();
    onOpen(c);
    toast(context, t('Copy added. It isn\'t in a cage yet - the game places it like a newly arrived pet.'));
  }

  Future<void> _delete(BuildContext context) async {
    final why = petRemovalBlocker(doc, pet);
    if (why != null) return toast(context, why);
    final ok = await confirm(context, t('Remove {0}?', [petName(pet)]),
        t('The pet is removed from the shelter, its cage is freed and any ads, adopter picks and items tied to it are cleared.'));
    if (!ok) return;
    removePet(doc, pet);
    onChanged();
    onOpen(null);
  }

  // ---------------------------------------------------------------- identity

  Widget _identity(BuildContext context) {
    final st = pet.o('PetStaticInfo')!;
    final term = st.o('PetName')?.str('mTerm');
    final gameName = db.tr(term) ?? term ?? '';
    final age = pet.o('PetAgeSaveData');
    final stages = db.choices('PetLifeStage');
    return Section(title: t('Pet'), children: [
      TextRow(
        label: t('Name'),
        hint: t('Empty = the game\'s name "{0}"', [gameName]),
        value: st.str('CustomName') ?? '',
        maxLength: 40,
        onChanged: (v) {
          st.setStr('CustomName', v.trim());
          if (v.trim().isNotEmpty && st.has('NameRevealed')) st.setBool('NameRevealed', true);
          onChanged();
        },
      ),
      if (age != null && stages.isNotEmpty)
        AssetDropdownRow(
          label: t('Age stage'),
          value: age.str('StageGuid'),
          choices: stages,
          onChanged: (g) {
            age.setStr('StageGuid', g);
            age.setNum('CurrentStageAge', 0);
            onChanged();
          },
        ),
      if (age != null)
        NumRow(
            label: t('Days in this stage'),
            value: age.integer('CurrentStageAge') ?? 0,
            min: 0,
            max: 365,
            onChanged: (v) {
              age.setNum('CurrentStageAge', v);
              onChanged();
            }),
      NumRow(
          label: t('Difficulty'),
          hint: t('How hard the pet is to care for'),
          value: st.integer('PetDifficultyLevel') ?? 0,
          min: 0,
          max: 5,
          slider: true,
          onChanged: (v) {
            st.setNum('PetDifficultyLevel', v);
            onChanged();
          }),
      if (pet.o('SaveOverallState') != null)
        NumRow(
            label: t('Overall condition'),
            hint: t('Points that reveal the pet\'s tasks'),
            value: pet.o('SaveOverallState')!.dbl('Points') ?? 0,
            min: 0,
            max: 100,
            decimals: true,
            slider: true,
            onChanged: (v) {
              pet.o('SaveOverallState')!.setNum('Points', v);
              onChanged();
            }),
    ]);
  }

  // ---------------------------------------------------------------- perks

  Widget _perks(BuildContext context) {
    final ps = pet.o('PerksSaveInfo');
    if (ps == null) return const SizedBox.shrink();
    final perks = ps.items('PerksInfo');
    String type(O p) => db.enumName('PerkType', (db.asset(p.str('Guid'))?.extra['type'] as num?)?.toInt() ?? 1);
    final groups = <String, List<O>>{};
    for (final p in perks) {
      final cat = (db.asset(p.str('Guid'))?.extra['Category'] as num?)?.toInt();
      final key = cat == 2 ? 'Disease symptoms' : type(p);
      (groups[key] ??= []).add(p);
    }
    final order = ['Good', 'Neutral', 'Bad', 'Disease symptoms'];
    return Section(
      title: t('Perks'),
      subtitle: t('Tap a perk to show or hide it in the game · eye = hidden until discovered'),
      trailing: FilledButton.tonalIcon(
        icon: const Icon(Icons.add),
        label: Text(t('Add perk')),
        onPressed: perks.isEmpty && _anyTemplate('PerkSaveInfo') == null ? null : () => _addPerk(context, ps, perks),
      ),
      children: [
        if (perks.isEmpty) emptyNote(context, t('No perks.')),
        for (final k in [...order.where(groups.containsKey), ...groups.keys.where((k) => !order.contains(k))]) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(t(k), style: context.tt.labelLarge?.copyWith(color: context.cs.primary)),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in groups[k]!)
              AssetChip(
                guid: p.str('Guid') ?? '',
                avatar: Icon(p.boolean('Hidden') == true ? Icons.visibility_off : Icons.visibility, size: 18),
                onTap: () {
                  p.setBool('Hidden', !(p.boolean('Hidden') ?? false));
                  onChanged();
                },
                onDelete: () {
                  ps.removeItem('PerksInfo', p);
                  onChanged();
                },
              ),
          ]),
        ],
      ],
    );
  }

  O? _anyTemplate(String cls) {
    final root = O(doc, doc.root!);
    for (final p in root.path('PetsSaveData')?.items('PetSaveInfos') ?? const <O>[]) {
      if (cls == 'PerkSaveInfo') {
        final l = p.o('PerksSaveInfo')?.items('PerksInfo');
        if (l != null && l.isNotEmpty) return l.first;
      } else if (cls == 'AICommand') {
        final l = p.o('Commands')?.items('Commands');
        if (l != null && l.isNotEmpty) return l.first;
      }
    }
    return null;
  }

  Future<void> _addPerk(BuildContext context, O ps, List<O> perks) async {
    final have = {for (final p in perks) p.str('Guid') ?? ''};
    final choices = [
      for (final a in db.choices('Perk'))
        if ((a.extra['Category'] as num?)?.toInt() != 2 && db.tr(a.nameTerm) != null) a
    ];
    final pick = await pickAsset(context, t('Add perk'), choices,
        exclude: have,
        group: (a) =>
            '${db.enumName('PerkType', (a.extra['type'] as num?)?.toInt() ?? 1)} · ${db.enumName('PerkCategory', (a.extra['Category'] as num?)?.toInt() ?? 1)}');
    if (pick == null) return;
    final tpl = perks.isNotEmpty ? perks.first : _anyTemplate('PerkSaveInfo')!;
    final c = ps.addClone('PerksInfo', tpl);
    c.setStr('Guid', pick.guid);
    c.setNum('Strenght', (pick.extra['Strength'] as num?) ?? 1);
    c.setBool('Hidden', false);
    onChanged();
  }

  // ---------------------------------------------------------------- needs

  Widget _needs(BuildContext context) {
    final states = pet.o('SaveAIInternalStates')?.items('StatesInfo') ?? const [];
    if (states.isEmpty) return const SizedBox.shrink();
    final named = [...states]..sort((a, b) => (db.name(a.str('Guid')) ?? '').compareTo(db.name(b.str('Guid')) ?? ''));
    return Section(title: t('Needs'), subtitle: t('Current values of the pet\'s needs'), children: [
      for (final s in named)
        NumRow(
          label: db.name(s.str('Guid')) ?? t('Unknown need'),
          value: s.dbl('Value') ?? 0,
          min: (db.asset(s.str('Guid'))?.extra['DefaultMinValue'] as num?) ?? 0,
          max: (db.asset(s.str('Guid'))?.extra['DefaultMaxValue'] as num?) ?? 100,
          decimals: true,
          slider: true,
          onChanged: (v) {
            s.setNum('Value', v);
            onChanged();
          },
        ),
    ]);
  }

  // ---------------------------------------------------------------- commands

  Widget _commands(BuildContext context) {
    final co = pet.o('Commands');
    if (co == null) return const SizedBox.shrink();
    final cmds = co.items('Commands');
    final have = {for (final c in cmds) c.str('Guid') ?? ''};
    final missing = [for (final a in db.choices('AICommandInfo')) if (!have.contains(a.guid)) a];
    final tpl = cmds.isNotEmpty ? cmds.first : _anyTemplate('AICommand');
    return Section(
      title: t('Tricks'),
      subtitle: t('Training progress, 100% = learned'),
      trailing: missing.isEmpty || tpl == null
          ? null
          : FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: Text(t('Add trick')),
              onPressed: () async {
                final pick = await pickAsset(context, t('Add trick'), missing);
                if (pick == null) return;
                final c = co.addClone('Commands', tpl);
                c.setStr('Guid', pick.guid);
                c.setNum('Progress', 0);
                onChanged();
              }),
      children: [
        if (cmds.isEmpty) emptyNote(context, t('No tricks yet.')),
        for (final c in cmds)
          Row(children: [
            Expanded(
              child: NumRow(
                label: db.name(c.str('Guid')) ?? t('Unknown trick'),
                value: ((c.dbl('Progress') ?? 0) * 100).clamp(0, 100),
                min: 0,
                max: 100,
                slider: true,
                onChanged: (v) {
                  c.setNum('Progress', v / 100);
                  onChanged();
                },
              ),
            ),
            IconButton(
              tooltip: t('Remove trick'),
              icon: const Icon(Icons.close),
              onPressed: () {
                co.removeItem('Commands', c);
                onChanged();
              },
            ),
          ]),
      ],
    );
  }

  // ---------------------------------------------------------------- health

  Widget _health(BuildContext context) {
    final d = pet.o('DiseaseSaveInfo');
    final temp = pet.o('BodyTemperature');
    final vacc = d?.o('PetVaccineSaveData');
    final psych = pet.o('PsycholgicalProblemSaveInfo');
    final diseaseGuid = d?.str('Guid') ?? '';
    final vaccines = vacc?.strings('VaccinesGuids') ?? const <String>[];
    final allVaccines = db.choices('VaccineData');
    return Section(title: t('Health'), children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(t('Disease'), style: context.tt.bodyLarge),
        subtitle: Text(diseaseGuid.isEmpty
            ? t('Healthy')
            : '${db.name(diseaseGuid) ?? 'Unknown disease'}${d!.boolean('IsDiseaseDiagnosed') == true ? ' (diagnosed)' : ' (not diagnosed yet)'}'),
        trailing: diseaseGuid.isEmpty
            ? null
            : FilledButton.tonal(
                onPressed: () {
                  _cure(d!);
                  onChanged();
                },
                child: Text(t('Cure'))),
      ),
      if (psych != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t('Behavioural problem'), style: context.tt.bodyLarge),
          subtitle: Text(db.name(psych.str('Guid')) ?? t('Unknown problem')),
          trailing: FilledButton.tonal(
              onPressed: () {
                pet.g.setMember(pet.rec, 'PsycholgicalProblemSaveInfo', pet.g.nullSlot());
                doc.structural = true;
                onChanged();
              },
              child: Text(t('Remove'))),
        ),
      if (vacc != null) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(children: [
            Expanded(child: Text(t('Vaccines'), style: context.tt.bodyLarge)),
            for (final v in allVaccines)
              if (!vaccines.contains(v.guid))
                TextButton.icon(
                    onPressed: () {
                      vacc.addString('VaccinesGuids', v.guid);
                      onChanged();
                    },
                    icon: const Icon(Icons.vaccines, size: 18),
                    label: Text(t('Give {0}', [db.name(v.guid) ?? 'vaccine']))),
          ]),
        ),
        Wrap(spacing: 8, children: [
          if (vaccines.isEmpty) emptyNote(context, t('Not vaccinated.')),
          for (final v in vaccines)
            AssetChip(
                guid: v,
                onDelete: () {
                  vacc.removeString('VaccinesGuids', v);
                  onChanged();
                }),
        ]),
      ],
      if (temp != null)
        NumRow(
            label: t('Body temperature'),
            hint: '°C',
            value: temp.dbl('Temperature') ?? 38.5,
            min: 30,
            max: 45,
            decimals: true,
            onChanged: (v) {
              temp.setNum('Temperature', v);
              onChanged();
            }),
    ]);
  }

  /// Same as the game's PetDiseaseController.CureDisease: no disease, no treatment step or dose times, healing
  /// progress 0, symptom and diagnosis lists emptied and the symptom perks removed. Medicine toxicity is left alone
  /// (the game doesn't reset it on cure either).
  void _cure(O d) {
    d.setStr('Guid', '');
    for (final l in ['VisibleSyndromes', 'HiddenSyndromes', 'ExcludedSyndromes', 'UsedDiagnostics']) {
      final list = d.o(l);
      if (list == null || !list.isList) continue;
      while (list.length() > 0) {
        d.removeAt(l, 0);
      }
    }
    for (final f in ['HealingProgress', 'TreatmentStepIndex', 'DosesLeft']) {
      d.setNum(f, 0);
    }
    for (final f in ['TimeOfLastDosage', 'TimeOfNextDosage']) {
      if (d.has(f) && d.o(f) != null) {
        d.g.setMember(d.rec, f, d.g.nullSlot());
        doc.structural = true;
      }
    }
    d.setBool('IsDiseaseDiagnosed', false);
    final ps = pet.o('PerksSaveInfo');
    if (ps != null) {
      for (final p in ps.items('PerksInfo')) {
        if ((db.asset(p.str('Guid'))?.extra['Category'] as num?)?.toInt() == 2) ps.removeItem('PerksInfo', p);
      }
    }
  }

  // ---------------------------------------------------------------- adopter preferences

  Widget _adopters(BuildContext context) {
    final want = pet.strings('AdopterConditionsPreferences');
    final unwanted = pet.strings('UnwantedAdopterConditions');
    final cls = db.classForField('PetSaveInfo', 'AdopterConditionsPreferences') ?? 'AdopterHomeCondition';
    final choices = db.choices(cls);
    Widget block(String title, String field, List<String> vals) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(children: [
              Expanded(child: Text(title, style: context.tt.labelLarge?.copyWith(color: context.cs.primary))),
              if (choices.isNotEmpty)
                TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t('Add')),
                    onPressed: () async {
                      final pick = await pickAsset(context, title, choices, exclude: {...want, ...unwanted});
                      if (pick == null) return;
                      pet.addString(field, pick.guid);
                      onChanged();
                    }),
            ]),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (vals.isEmpty) emptyNote(context, 'None.'),
            for (final g in vals)
              AssetChip(
                  guid: g,
                  onDelete: () {
                    pet.removeString(field, g);
                    onChanged();
                  }),
          ]),
        ]);
    return Section(title: t('Adoption'), subtitle: t('Home conditions this pet wants or refuses in an adopter'), children: [
      block(t('Wants'), 'AdopterConditionsPreferences', want),
      block(t('Refuses'), 'UnwantedAdopterConditions', unwanted),
    ]);
  }

  // ---------------------------------------------------------------- looks

  Widget _looks(BuildContext context) {
    final cur = pet.o('VisualStateSaveInfo')?.o('CurrentValues');
    if (cur == null) return const SizedBox.shrink();
    const dirt = ['FurDirt', 'FurMud', 'FurWetness', 'FurSnow', 'FurShampoo', 'FurHeat'];
    String label(String f) => f.replaceFirst('Fur', '').replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]}');
    final fields = cur.rec.ci!.memberNames;
    return Section(
      title: t('Coat'),
      subtitle: t('0 = none, 1 = full'),
      trailing: FilledButton.tonal(
          onPressed: () {
            for (final f in dirt) {
              if (fields.contains(f)) cur.setNum(f, 0);
            }
            if (fields.contains('FurCombing')) cur.setNum('FurCombing', 1);
            onChanged();
          },
          child: Text(t('Groom & clean'))),
      children: [
        for (final f in fields)
          NumRow(
            label: label(f),
            value: cur.dbl(f) ?? 0,
            min: 0,
            max: 1,
            decimals: true,
            slider: true,
            onChanged: (v) {
              cur.setNum(f, v);
              onChanged();
            },
          ),
      ],
    );
  }
}
