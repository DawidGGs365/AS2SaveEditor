// Convenience view over save objects: field access by name, typed get/set, List<T> helpers.
import 'dart:typed_data';

import 'graph.dart';
import 'nrbf.dart';
import 'save_doc.dart';

class O {
  final SaveDoc doc;
  final Rec rec;
  O(this.doc, this.rec);

  Graph get g => doc.graph;

  String get cls {
    final n = rec.ci?.nameStr ?? '';
    return n;
  }

  /// Short class name: "System.Collections.Generic.List`1[[PerkSaveInfo, ...]]" -> "List<PerkSaveInfo>".
  String get shortCls => shortClass(cls);

  bool has(String f) => rec.ci != null && rec.ci!.memberNames.contains(f) || rec.ci!.memberNames.contains('<$f>k__BackingField');

  String _name(String f) {
    final names = rec.ci!.memberNames;
    if (names.contains(f)) return f;
    final bf = '<$f>k__BackingField';
    if (names.contains(bf)) return bf;
    return f;
  }

  Slot? slot(String f) {
    if (rec.ci == null) return null;
    return g.member(rec, _name(f));
  }

  /// Child object (class / list / dict / array / string record), dereferenced.
  O? o(String f) {
    final s = slot(f);
    if (s == null || s.r == null) return null;
    final r = g.deref(s.r);
    return r == null ? null : O(doc, r);
  }

  O? path(String p) {
    O? cur = this;
    for (final part in p.split('/')) {
      cur = cur?.o(part);
      if (cur == null) return null;
    }
    return cur;
  }

  Prim? prim(String f) => slot(f)?.p;

  // ---------------- typed values

  String? str(String f) {
    final s = slot(f);
    if (s == null) return null;
    if (s.p != null) return primToText(s.p!);
    final r = g.deref(s.r);
    if (r == null) return null;
    if (r.t == 6) return r.stringValue;
    if (_isEnum(r)) return primToText(r.vals!.first.p!);
    return null;
  }

  /// Sets a string member; creates a new string record when the member was null.
  void setStr(String f, String v) {
    final s = slot(f);
    if (s == null) throw StateError('no field $f on $cls');
    final r = g.deref(s.r);
    if (r != null && r.t == 6) {
      if (r.stringValue == v) return;
      // BinaryFormatter shares equal string instances between objects: only edit in place when nobody else uses it
      if (g.useCount(r.oid) <= 1) {
        r.stringValue = v;
        return;
      }
    }
    final n = g.newString(v);
    g.setMember(rec, _name(f), Slot.rec(Rec(9)..ref = n.oid));
    doc.structural = true;
  }

  num? number(String f) {
    final p = prim(f) ?? _enumPrim(f);
    if (p == null) return null;
    final t = primToText(p);
    return t == null ? null : num.tryParse(t);
  }

  int? integer(String f) => number(f)?.toInt();
  double? dbl(String f) => number(f)?.toDouble();

  bool? boolean(String f) {
    final p = prim(f);
    return p == null ? null : p.raw[0] != 0;
  }

  bool setNum(String f, num v) {
    final p = prim(f) ?? _enumPrim(f);
    if (p == null) return false;
    final text = (p.type == 11 || p.type == 6) ? v.toDouble().toString() : v.round().toString();
    return primSetFromText(p, text);
  }

  void setBool(String f, bool v) {
    final p = prim(f);
    if (p != null) p.raw = Uint8List.fromList([v ? 1 : 0]);
  }

  Prim? _enumPrim(String f) {
    final c = o(f);
    if (c != null && _isEnum(c.rec)) return c.rec.vals!.first.p;
    return null;
  }

  static bool _isEnum(Rec r) =>
      (r.t == 1 || r.t == 4 || r.t == 5) && r.ci!.memberNames.length == 1 && r.ci!.memberNames.first == 'value__';

  bool get isEnum => _isEnum(rec);
  bool get isList => cls.startsWith('System.Collections.Generic.List`1');
  bool get isDict => cls.startsWith('System.Collections.Generic.Dictionary`2');

  // ---------------- List<T>

  /// Items of a List<T> member: objects (null entries skipped), or strings for List<string>.
  List<O> items([String? f]) {
    final l = f == null ? this : o(f);
    if (l == null || !l.isList) return const [];
    return [
      for (final s in g.listSlots(l.rec))
        if (s.r != null && g.deref(s.r) != null) O(doc, g.deref(s.r)!)
    ];
  }

  /// List<string> member as Dart strings (nulls kept as '').
  List<String> strings(String f) {
    final l = o(f);
    if (l == null || !l.isList) return const [];
    return [
      for (final s in g.listSlots(l.rec))
        s.p != null ? (primToText(s.p!) ?? '') : (g.deref(s.r)?.stringValue ?? '')
    ];
  }

  int length([String? f]) {
    final l = f == null ? this : o(f);
    return l == null || !l.isList ? 0 : g.listLength(l.rec);
  }

  void removeAt(String f, int i) {
    g.listRemoveAt(o(f)!.rec, i);
    doc.structural = true;
  }

  /// Removes the list item whose object is [item].
  bool removeItem(String f, O item) {
    final l = o(f);
    if (l == null) return false;
    final slots = g.listSlots(l.rec);
    for (var i = 0; i < slots.length; i++) {
      if (g.deref(slots[i].r) == item.rec) {
        removeAt(f, i);
        return true;
      }
    }
    return false;
  }

  void addString(String f, String v) {
    final n = g.newString(v);
    g.listAdd(o(f)!.rec, Slot.rec(Rec(9)..ref = n.oid));
    doc.structural = true;
  }

  void removeString(String f, String v) {
    final i = strings(f).indexOf(v);
    if (i >= 0) removeAt(f, i);
  }

  /// Appends a deep copy of [template] (any object of the list's element type) and returns the copy.
  O addClone(String f, O template) {
    final c = g.deepClone(template.rec);
    g.listAdd(o(f)!.rec, Slot.rec(Rec(9)..ref = objId(c)));
    doc.structural = true;
    return O(doc, c);
  }

  // ---------------- Dictionary<K,V>

  /// Key/value pairs (KeyValuePair objects) of a Dictionary member.
  List<O> pairs([String? f]) {
    final d = f == null ? this : o(f);
    if (d == null || !d.isDict) return const [];
    final a = g.dictPairsArray(d.rec);
    if (a == null) return const [];
    return [
      for (final s in a.items!)
        if (s.r != null && g.deref(s.r) != null) O(doc, g.deref(s.r)!)
    ];
  }

  @override
  bool operator ==(Object other) => other is O && other.rec == rec;
  @override
  int get hashCode => rec.hashCode;
}

String shortClass(String n) {
  final m = RegExp(r'^System\.Collections\.Generic\.(List|Dictionary)`\d\[(.*)\]$').firstMatch(n);
  if (m == null) return n;
  final args = <String>[];
  var depth = 0, start = 0;
  final inner = m.group(2)!;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (c == '[') {
      if (depth == 0) start = i + 1;
      depth++;
    } else if (c == ']') {
      depth--;
      if (depth == 0) args.add(shortClass(inner.substring(start, i).split(',').first.replaceFirst('System.', '')));
    }
  }
  return '${m.group(1)}<${args.join(', ')}>';
}
