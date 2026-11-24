import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gamedb.dart';

/// User preferences: Advanced mode (raw Browse / Search tabs) and the language used for game names.
class AppSettings extends ChangeNotifier {
  static const _kAdvanced = 'advanced';
  static const _kLang = 'lang'; // game language code/name, '' = follow the system

  bool advanced = false;
  String lang = '';
  SharedPreferences? _p;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      advanced = _p!.getBool(_kAdvanced) ?? false;
      lang = _p!.getString(_kLang) ?? '';
    } catch (_) {/* preferences unavailable: defaults */}
    _applyLang();
  }

  void setAdvanced(bool v) {
    advanced = v;
    _p?.setBool(_kAdvanced, v);
    notifyListeners();
  }

  void setLang(String v) {
    lang = v;
    _p?.setString(_kLang, v);
    _applyLang();
    notifyListeners();
  }

  void _applyLang() {
    final db = GameDb.instance;
    if (db == null) return;
    if (lang.isEmpty) {
      db.lang = db.langForLocale(PlatformDispatcher.instance.locale.toLanguageTag());
    } else {
      final i = db.langs.indexWhere((l) => l.name == lang);
      db.lang = i < 0 ? 0 : i;
    }
  }
}
