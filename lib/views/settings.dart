import 'package:material_ui/material_ui.dart';

import '../l10n.dart';
import '../app_settings.dart';
import '../gamedb.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final db = GameDb.I;
    return Scaffold(
      appBar: AppBar(title: Text(t('Settings'))),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: [
          Section(title: t('Language'), subtitle: t('Language of the editor and of pet names, perks, items and everything else from the game'), children: [
            DropdownButtonFormField<String>(
              initialValue: settings.lang,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                    value: '',
                    child: Text(t('System language ({0})', [nativeLangName(db.langs[db.langForLocale(WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag())].name)]))),
                for (final l in db.langs) DropdownMenuItem(value: l.name, child: Text(nativeLangName(l.name))),
              ],
              onChanged: (v) => settings.setLang(v ?? ''),
            ),
            const SizedBox(height: 8),
            Text(t('Missing translations fall back to English.'), style: Theme.of(context).textTheme.bodySmall),
          ]),
          Section(title: t('Advanced'), children: [
            SwitchRow(
              label: t('Advanced mode'),
              hint: t('Shows the Browse and Search tabs: the raw save tree, where every value can be edited and list '
                  'entries duplicated or deleted. Changes there are not checked against the game\'s rules.'),
              value: settings.advanced,
              onChanged: (v) async {
                if (!v) return settings.setAdvanced(false);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    icon: const Icon(Icons.warning_amber_rounded, size: 36),
                    title: Text(t('Turn on Advanced mode?')),
                    content: Text([
                      t('Advanced mode lets you change any value in the save and duplicate or delete any list entry, '
                          'including ones other parts of the save depend on.'),
                      t('Nothing there is checked against the game\'s rules. A wrong change can make the save fail to '
                          'load or behave strangely in game.'),
                      t('Keep a copy of your save before editing. The editor also keeps one .bak copy of each file '
                          'the first time you save it.'),
                    ].join('\n\n')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('I understand, turn on'))),
                    ],
                  ),
                );
                if (ok == true) settings.setAdvanced(true);
              },
            ),
          ]),
        ]),
      ),
    );
  }
}
