import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'l10n.dart';
import 'app_settings.dart';
import 'browse.dart';
import 'file_io.dart';
import 'gamedb.dart';
import 'save_doc.dart';
import 'ui_kit.dart';
import 'views/inventory.dart';
import 'views/pets.dart';
import 'views/progress.dart';
import 'views/settings.dart';
import 'views/shelter.dart';
import 'views/workers.dart';

final settings = AppSettings();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GameDb.load();
  await settings.load();
  await loadL10n();
  runApp(const EditorApp());
}

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'AS2 Save Editor',
        locale: currentLocale(),
        supportedLocales: const [
          Locale('en'), Locale('pl'), Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('fr'), Locale('it'), Locale('de'),
          Locale('es', 'ES'), Locale('ko'), Locale('ru'), Locale('tr'), Locale('ja'), Locale('pt', 'BR'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const EditorPage(),
      ));
}

/// Windows / Linux / macOS: the picker returns the real file, so we can write in place.
/// Android / web: the picker returns a copy (or only bytes), so saving exports a new file.
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _Tab {
  final IconData icon;
  final String label;
  final Widget Function(SaveDoc d, VoidCallback changed) build;
  const _Tab(this.icon, this.label, this.build);
}

class _EditorPageState extends State<EditorPage> {
  final pathCtl = TextEditingController();
  SaveDoc? doc;
  String fileName = 'AutoSave.save';
  String? path; // only set on desktop, where it is the real file
  bool dirty = false;
  String status = t('Open a .save file to begin.');
  int tab = 0;
  int generation = 0; // bumps when the document is replaced or the language changes

  @override
  void initState() {
    super.initState();
    settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() => setState(() {
        generation++;
        if (tab >= _tabs.length) tab = 0;
      });

  List<_Tab> get _tabs => [
        _Tab(Icons.home_outlined, t('Shelter'), (d, c) => ShelterView(doc: d, onChanged: c)),
        _Tab(Icons.pets, t('Pets'), (d, c) => PetsView(doc: d, onChanged: c)),
        _Tab(Icons.badge_outlined, t('Workers'), (d, c) => WorkersView(doc: d, onChanged: c)),
        _Tab(Icons.backpack_outlined, t('Inventory'), (d, c) => InventoryView(doc: d, onChanged: c)),
        _Tab(Icons.flag_outlined, t('Progress'), (d, c) => ProgressView(doc: d, onChanged: c)),
        if (settings.advanced) ...[
          _Tab(Icons.account_tree_outlined, t('Browse'), (d, c) => BrowseView(doc: d, onChanged: c)),
          _Tab(Icons.search, t('Search'), (d, c) => SearchView(doc: d, onChanged: c)),
        ],
      ];

  void say(String m) => setState(() => status = m);

  Future<void> browse() async {
    try {
      final res = await FilePicker.platform.pickFiles(dialogTitle: t('Choose a .save file'), type: FileType.any, withData: true);
      final f = res?.files.single;
      if (f == null) return;
      Uint8List? bytes = f.bytes;
      if (bytes == null && isDesktop && f.path != null) bytes = await readPath(f.path!);
      if (bytes == null) {
        say(t('Could not read that file.'));
        return;
      }
      if (isDesktop && f.path != null) pathCtl.text = f.path!;
      load(bytes, f.name, isDesktop ? f.path : null);
    } catch (e) {
      say(t('Could not open file: {0}', [e]));
    }
  }

  Future<void> openTypedPath(String p) async {
    try {
      final bytes = await readPath(p);
      final name = p.split(RegExp(r'[\\/]')).last;
      load(bytes, name, p);
    } catch (e) {
      say(t('Could not open file: {0}', [e]));
    }
  }

  void load(Uint8List bytes, String name, String? realPath) {
    try {
      final d = SaveDoc.parse(bytes);
      // Safety: a clean re-serialise must match the original before we allow edits.
      if (!d.roundTrips) {
        say(t('Refusing to open: this file does not round-trip exactly, so saving could corrupt it.'));
        return;
      }
      setState(() {
        doc = d;
        fileName = name;
        path = realPath;
        dirty = false;
        generation++;
        status = t('Opened {0}.', [name]);
      });
    } catch (e) {
      say(t('Could not read this as a save file: {0}', [e]));
    }
  }

  Future<void> save() async {
    final d = doc;
    if (d == null) return;
    try {
      d.syncHeader();
      final out = d.build();
      SaveDoc.parse(out); // the written file must read back
      final p = path;
      if (isDesktop && p != null) {
        final bak = '$p.bak';
        if (!await pathExists(bak)) await copyPath(p, bak);
        await writePath(p, out);
        setState(() {
          dirty = false;
          status = t('Saved. The original was backed up once as {0}.', [bak.split(RegExp(r'[\\/]')).last]);
        });
      } else {
        final res = await FilePicker.platform.saveFile(dialogTitle: t('Save edited copy'), fileName: fileName, bytes: out);
        if (res == null && !kIsWeb) {
          say(t('Save cancelled.'));
          return;
        }
        setState(() {
          dirty = false;
          status = t('Saved an edited copy. Your original file was not touched; copy the new file over it to use it.');
        });
      }
    } catch (e) {
      say(t('Save failed: {0}', [e]));
    }
  }

  void changed() => setState(() => dirty = true);

  Widget header(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isDesktop)
                SizedBox(
                  width: 420,
                  child: TextField(
                    controller: pathCtl,
                    style: context.tt.bodyLarge,
                    decoration: InputDecoration(hintText: t('Path to .save file')),
                    onSubmitted: openTypedPath,
                  ),
                ),
              if (isDesktop)
                FilledButton.icon(
                    onPressed: () => openTypedPath(pathCtl.text), icon: const Icon(Icons.folder_open), label: Text(t('Open'))),
              FilledButton.tonalIcon(
                  onPressed: browse,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(isDesktop ? t('Browse…') : t('Choose .save file'))),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: context.cs.secondaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSecondaryContainer)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc;
    final tabs = _tabs;
    if (tab >= tabs.length) tab = 0;
    final wide = MediaQuery.of(context).size.width >= 840;
    final body = Column(children: [
      header(context),
      Expanded(
        child: d == null
            ? emptyHint(context, Icons.pets, t('Open a .save file to begin.\nClose the game before editing.'))
            : KeyedSubtree(key: ValueKey('$generation/$tab'), child: tabs[tab].build(d, changed)),
      ),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'AS2 Save Editor' : fileName),
        actions: [
          IconButton(
            tooltip: t('Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(settings: settings))),
          ),
        ],
      ),
      body: SafeArea(
        child: (wide && d != null)
            ? Row(children: [
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  labelType: NavigationRailLabelType.all,
                  indicatorShape: const StadiumBorder(),
                  destinations: [for (final x in tabs) NavigationRailDestination(icon: Icon(x.icon), label: Text(x.label))],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ])
            : body,
      ),
      bottomNavigationBar: (!wide && d != null)
          ? NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [for (final x in tabs) NavigationDestination(icon: Icon(x.icon), label: x.label)],
            )
          : null,
      floatingActionButton: dirty
          ? FloatingActionButton.extended(
              onPressed: save, icon: const Icon(Icons.save), label: Text(isDesktop ? t('Save') : t('Save copy')))
          : null,
    );
  }
}
