import 'package:material_ui/material_ui.dart';

import '../l10n.dart';
import '../gamedb.dart';
import '../obj.dart';
import '../save_doc.dart';
import '../widgets.dart';

class ShelterView extends StatelessWidget {
  final SaveDoc doc;
  final VoidCallback onChanged;
  const ShelterView({super.key, required this.doc, required this.onChanged});

  void _changed() {
    doc.syncHeader(); // the Load window reads these from the header
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final db = GameDb.I;
    final root = O(doc, doc.root!);
    final shelter = root.o('PlayerShelterInfo');
    final time = root.o('TimeSaveData');
    final iconCls = db.classForField('PlayerShelterInfo', 'ShelterIconGUID');
    final quests = root.o('Quests');
    final questChoices = [
      for (final q in quests?.items('InProgressQuests') ?? const <O>[])
        if (db.asset(q.str('Guid')) != null) db.asset(q.str('Guid'))!
    ];
    return ListView(padding: const EdgeInsets.only(top: 8, bottom: 110), children: [
      Section(title: t('Shelter'), children: [
        if (shelter != null)
          TextRow(
              label: t('Shelter name'),
              value: shelter.str('ShelterName') ?? '',
              maxLength: 40,
              onChanged: (v) {
                shelter.setStr('ShelterName', v);
                _changed();
              }),
        if (shelter != null && iconCls != null && db.choices(iconCls).length > 1)
          AssetDropdownRow(
              label: t('Shelter icon'),
              value: shelter.str('ShelterIconGUID'),
              choices: db.choices(iconCls),
              onChanged: (g) {
                shelter.setStr('ShelterIconGUID', g);
                _changed();
              }),
        NumRow(
            label: t('Money'),
            value: root.dbl('MoneyAmount') ?? 0,
            min: -1e9,
            max: 1e9,
            decimals: true,
            onChanged: (v) {
              root.setNum('MoneyAmount', v);
              _changed();
            }),
        NumRow(
            label: t('Reputation'),
            value: root.integer('Reputation') ?? 0,
            min: 0,
            max: 2000000000,
            onChanged: (v) {
              root.setNum('Reputation', v);
              _changed();
            }),
        if (time != null) ...[
          NumRow(
              label: t('Day'),
              value: time.integer('Day') ?? 1,
              min: 1,
              max: 100000,
              onChanged: (v) {
                time.setNum('Day', v);
                _changed();
              }),
          NumRow(
              label: t('Time of day'),
              hint: t('Hours, 0–24'),
              value: time.dbl('Time') ?? 8,
              min: 0,
              max: 23.99,
              decimals: true,
              slider: true,
              onChanged: (v) {
                time.setNum('Time', v);
                _changed();
              }),
        ],
        if (quests != null && questChoices.isNotEmpty)
          AssetDropdownRow(
              label: t('Tracked quest'),
              value: quests.str('ActiveQuestGuid'),
              choices: questChoices,
              onChanged: (g) {
                quests.setStr('ActiveQuestGuid', g);
                _changed();
              }),
      ]),
      _difficulty(context, root),
    ]);
  }

  Widget _difficulty(BuildContext context, O root) {
    final db = GameDb.I;
    final d = root.o('DifficultySettingsSaveData');
    if (d == null) return const SizedBox.shrink();
    final rows = <Widget>[];
    int keyOf(O pair) => O(doc, pair.o('key')!.rec).integer('value__') ?? -1;
    for (final kv in d.pairs('DifficultyBool')) {
      rows.add(SwitchRow(
          label: _settingLabel(db, keyOf(kv)),
          value: kv.boolean('value') ?? false,
          onChanged: (v) {
            kv.setBool('value', v);
            onChanged();
          }));
    }
    for (final kv in d.pairs('DifficultyFloat')) {
      rows.add(NumRow(
          label: _settingLabel(db, keyOf(kv)),
          hint: t('Multiplier'),
          value: kv.dbl('value') ?? 0,
          min: 0,
          max: 10,
          decimals: true,
          onChanged: (v) {
            kv.setNum('value', v);
            onChanged();
          }));
    }
    for (final kv in d.pairs('DifficultyInt')) {
      rows.add(NumRow(
          label: _settingLabel(db, keyOf(kv)),
          value: kv.integer('value') ?? 0,
          onChanged: (v) {
            kv.setNum('value', v);
            onChanged();
          }));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Section(title: t('Difficulty'), subtitle: t('Custom difficulty settings stored in this save'), children: rows);
  }
}

/// The game's own (translated) label for a difficulty setting; falls back to the enum name.
String _settingLabel(GameDb db, int v) {
  const terms = {
    'DifficultLevel': 'Menu/Settings/Difficulty/Description/OverallDifficultyLevel.',
    'Reputation': 'Menu/Settings/Difficulty/Description/ReputationAwardMltiplier',
    'TimeScaleSetings': 'Menu/Settings/Difficulty/Description/TimeElapsedMultiplier',
    'FundMultiplier': 'Menu/Settings/Difficulty/Description/FundMultiplier',
    'PriceMultiplier': 'Menu/Settings/Difficulty/Description/PriceMultiplier.',
    'AnimalStatDrop': 'Menu/Settings/Difficulty/Description/TheRateAtWhichAnimalStatsDrop.',
    'DisableAchievements': 'Menu/Settings/Difficulty/Description/DisableAchievements',
    'DisablePopups': 'Menu/Settings/Difficulty/Description/DisablePopups',
    'DisableMissions': 'Menu/Settings/Difficulty/Description/DisableMissions',
    'InfiniteFunds': 'Menu/Settings/Difficulty/Description/InfiniteFunds',
    'MaximumReputation': 'Menu/Settings/Difficulty/Description/MaximumReputation',
    'PetAgingSpeed': 'Menu/Settings/Pet Aging Speed',
    'ContagiousDiseaseSpreadSpeed': 'Menu/Settings/Contagious Diseases Spreading Speed',
  };
  final raw = db.enums['SettingName']?[v];
  return db.tr(terms[raw]) ?? db.enumName('SettingName', v);
}
