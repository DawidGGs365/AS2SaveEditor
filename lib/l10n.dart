// App UI translations. Keys are the English texts; assets/l10n.json maps game language name -> {english: translated}.
// The UI language is the same one chosen for game names (Settings), so the whole app speaks one language.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;

import 'gamedb.dart';

Map<String, Map<String, String>> _tables = const {};

Future<void> loadL10n() async {
  try {
    final j = jsonDecode(await rootBundle.loadString('assets/l10n.json')) as Map<String, dynamic>;
    _tables = {for (final e in j.entries) e.key: (e.value as Map<String, dynamic>).cast<String, String>()};
  } catch (_) {
    _tables = const {};
  }
}

/// Translates [en] into the current language (English if missing); `{0}`, `{1}`... are replaced by [args].
String t(String en, [List<Object?> args = const []]) {
  final db = GameDb.instance;
  var s = en;
  if (db != null && db.langs.isNotEmpty) s = _tables[db.langs[db.lang].name]?[en] ?? en;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Flutter locale for the current game language (for the framework's own texts: tooltips, menus, dialogs).
Locale currentLocale() {
  final db = GameDb.instance;
  final name = db == null || db.langs.isEmpty ? 'English' : db.langs[db.lang].name;
  return switch (name) {
    'Polish' => const Locale('pl'),
    'Simplified Chinese' => const Locale('zh', 'CN'),
    'Traditional Chinese' => const Locale('zh', 'TW'),
    'French' => const Locale('fr'),
    'Italian' => const Locale('it'),
    'German' => const Locale('de'),
    'Spanish - Spain' => const Locale('es', 'ES'),
    'Korean' => const Locale('ko'),
    'Russian' => const Locale('ru'),
    'Turkish' => const Locale('tr'),
    'Japanese' => const Locale('ja'),
    'Portuguese - Brazil' => const Locale('pt', 'BR'),
    _ => const Locale('en'),
  };
}

/// A game language name ("Polish") written in that language ("Polski"), for the language picker.
String nativeLangName(String name) => const {
      'English': 'English',
      'Polish': 'Polski',
      'Simplified Chinese': '简体中文',
      'Traditional Chinese': '繁體中文',
      'French': 'Français',
      'Italian': 'Italiano',
      'German': 'Deutsch',
      'Spanish - Spain': 'Español (España)',
      'Korean': '한국어',
      'Russian': 'Русский',
      'Turkish': 'Türkçe',
      'Japanese': '日本語',
      'Portuguese - Brazil': 'Português (Brasil)',
    }[name] ??
    name;
