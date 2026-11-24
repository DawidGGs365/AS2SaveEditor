// Game data extracted from Animal Shelter 2 (tools/save_re/build_db.py): every asset GUID that can appear in a
// save, its class, internal name and I2 localization terms, plus the game's full translation table.
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;

class GameAsset {
  final String guid;
  final String cls; // game class, e.g. Perk, ItemData, PetBreed
  final String internal; // Unity asset name, e.g. "Fav Toy Rabbit"
  final String? nameTerm;
  final String? descTerm;
  final String? plainName; // English-only name some assets carry instead of a term
  final Map<String, Object?> extra; // scalar fields (Perk type, Category, IsHidden, ...)
  const GameAsset(this.guid, this.cls, this.internal, this.nameTerm, this.descTerm, this.plainName, this.extra);
}

class GameLang {
  final String name;
  final String code;
  const GameLang(this.name, this.code);
}

class GameDb {
  final List<GameLang> langs;
  final Map<String, List<String?>> terms;
  final Map<String, GameAsset> byGuid;
  final Map<String, String> fieldClass; // "PerkSaveInfo.Guid" -> "Perk"
  final Map<String, Map<int, String>> enums; // enum type -> value -> name
  final Map<String, List<GameAsset>> _byClass = {};
  int lang = 0; // index into langs; 0 = English

  GameDb._(this.langs, this.terms, this.byGuid, this.fieldClass, this.enums) {
    for (final a in byGuid.values) {
      (_byClass[a.cls] ??= []).add(a);
    }
  }

  static GameDb? instance;
  static GameDb get I => instance!;

  static Future<GameDb> load() async {
    final raw = await rootBundle.loadString('assets/gamedb.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final langs = [
      for (final l in j['langs'] as List) GameLang(l['name'] as String, (l['code'] as String?) ?? ''),
    ];
    final terms = <String, List<String?>>{
      for (final e in (j['terms'] as Map<String, dynamic>).entries) e.key: (e.value as List).cast<String?>(),
    };
    final guids = <String, GameAsset>{};
    (j['guids'] as Map<String, dynamic>).forEach((g, v) {
      final m = v as Map<String, dynamic>;
      guids[g] = GameAsset(g, m['c'] as String, (m['n'] as String?) ?? '', m['t'] as String?, m['d'] as String?,
          m['p'] as String?, (m['x'] as Map<String, dynamic>?) ?? const {});
    });
    final fields = (j['fields'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    final enums = <String, Map<int, String>>{
      for (final e in ((j['enums'] as Map<String, dynamic>?) ?? const {}).entries)
        e.key: (e.value as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as String)),
    };
    final db = GameDb._(langs, terms, guids, fields, enums);
    db.lang = db.langForLocale(PlatformDispatcher.instance.locale.toLanguageTag());
    instance = db;
    return db;
  }

  /// Best matching game language for a BCP-47 tag ("pl-PL", "zh-Hant-TW", "pt-BR"), English otherwise.
  int langForLocale(String tag) {
    final t = tag.toLowerCase().replaceAll('_', '-');
    final lang = t.split('-').first;
    int? exact, base;
    for (var i = 0; i < langs.length; i++) {
      final c = langs[i].code.toLowerCase();
      final n = langs[i].name.toLowerCase();
      if (c.isNotEmpty && c == t) exact = i;
      if (lang == 'zh') {
        final trad = t.contains('hant') || t.endsWith('-tw') || t.endsWith('-hk') || t.endsWith('-mo');
        if (c == (trad ? 'zh-tw' : 'zh-cn')) base ??= i;
        continue;
      }
      if (c.isNotEmpty && c.split('-').first == lang) base ??= i;
      // languages without a code in the game's table
      if (c.isEmpty && lang == 'es' && n.startsWith('spanish')) base ??= i;
      if (c.isEmpty && lang == 'pt' && n.startsWith('portuguese')) base ??= i;
    }
    return exact ?? base ?? 0;
  }

  /// Translation of an I2 term in the current language, English if missing, null if the term is unknown.
  String? tr(String? term) {
    if (term == null || term.isEmpty) return null;
    final row = terms[term];
    if (row == null) return null;
    final v = lang < row.length ? row[lang] : null;
    if (v != null && v.trim().isNotEmpty) return _clean(v);
    final en = row.isNotEmpty ? row[0] : null;
    return en == null || en.trim().isEmpty ? null : _clean(en);
  }

  // I2 rich text / placeholders shown as plain text
  static final _tags = RegExp(r'<[^>]+>');
  String _clean(String s) => s.replaceAll(_tags, '').trim();

  /// "DisableAchievements" -> "Disable achievements"
  String enumName(String type, int v) {
    final n = enums[type]?[v];
    if (n == null) return '$v';
    return n.replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
  }

  GameAsset? asset(String? guid) => guid == null ? null : byGuid[guid];

  /// Display name for a GUID: localized name, plain name, readable internal name, or null when unknown.
  String? name(String? guid) {
    final a = asset(guid);
    if (a == null) return null;
    return tr(a.nameTerm) ?? a.plainName ?? _readable(a.internal);
  }

  String? description(String? guid) => tr(asset(guid)?.descTerm);

  /// "Fav Toy Rabbit" stays; "S_Weakened Immunity System" -> "Weakened Immunity System".
  /// "Human Trait Alone" -> "Alone" (adopter conditions without a translation term).
  static String _readable(String n) =>
      n.replaceFirst(RegExp(r'^[A-Z]_'), '').replaceFirst(RegExp(r'^Human Trait '), '').trim();

  List<GameAsset> ofClass(String cls) => _byClass[cls] ?? const [];

  /// Class of the assets a save field refers to ("PerkSaveInfo.Guid" -> "Perk").
  String? classForField(String owner, String field) => fieldClass['$owner.$field'];

  /// Candidates for a picker, sorted by display name; hides test / internal assets without any name.
  List<GameAsset> choices(String cls) {
    final l = [
      for (final a in ofClass(cls))
        if (!a.internal.toLowerCase().contains('test')) a
    ];
    l.sort((a, b) => (name(a.guid) ?? '').toLowerCase().compareTo((name(b.guid) ?? '').toLowerCase()));
    return l;
  }
}
