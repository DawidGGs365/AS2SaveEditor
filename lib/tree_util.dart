import 'dart:typed_data';

import 'gamedb.dart';
import 'nrbf.dart';
import 'save_doc.dart';

/// Something the user can edit as text: a primitive or a string object.
class Editable {
  final String type;
  final String Function() get;
  final bool Function(String) set;
  final bool editable;
  final String? lockedReason;
  Editable(this.type, this.get, this.set, {this.editable = true, this.lockedReason});

  static Editable fromPrim(Prim p) {
    return Editable(primTypeName(p.type), () => primToText(p) ?? '?', (t) => primSetFromText(p, t),
        editable: primEditable(p));
  }

  static Editable fromString(Rec r) {
    return Editable('string', () => r.stringValue, (t) {
      r.stringValue = t;
      return true;
    });
  }
}

class DictEntry {
  final Slot? key;
  final Slot? value;
  DictEntry(this.key, this.value);
}

const _noiseFields = {'_version', '_size', 'Version', 'HashSize', 'Comparer', 'value__'};

String displayName(String raw) {
  final m = RegExp(r'^<(.+)>k__BackingField$').firstMatch(raw);
  return m != null ? m.group(1)! : raw;
}

bool isNoiseField(String name) =>
    name.startsWith('mRTL_') || name == 'm_DontLocalizeParameters';

extension TreeUtil on SaveDoc {
  Rec? deref(Rec? r) {
    if (r == null) return null;
    if (r.t == 9) return byId[r.ref];
    return r;
  }

  bool isClass(Rec r) => r.t == 1 || r.t == 4 || r.t == 5;

  String className(Rec r) => r.ci?.nameStr ?? '';

  bool isList(Rec r) => isClass(r) && className(r).startsWith('System.Collections.Generic.List`1');
  bool isDict(Rec r) => isClass(r) && className(r).startsWith('System.Collections.Generic.Dictionary`2');

  /// A class whose only field is `value__` is an enum.
  bool isEnum(Rec r) {
    if (!isClass(r)) return false;
    final n = r.ci!.memberNames;
    return n.length == 1 && n.first == 'value__';
  }

  Slot? slotOf(Rec obj, String name) {
    if (!isClass(obj) || obj.vals == null) return null;
    final i = obj.ci!.memberNames.indexOf(name);
    if (i < 0 || i >= obj.vals!.length) return null;
    return obj.vals![i];
  }

  Rec? child(Rec? obj, String name) {
    if (obj == null) return null;
    final s = slotOf(obj, name);
    return s?.r == null ? null : deref(s!.r);
  }

  Prim? primOf(Rec? obj, String name) => obj == null ? null : slotOf(obj, name)?.p;

  Rec? resolve(String path) {
    Rec? cur = root;
    for (final part in path.split('/')) {
      cur = child(cur, part);
      if (cur == null) return null;
    }
    return cur;
  }

  /// Resolves "A/B/Field" to an editable primitive or string.
  Editable? editableAt(String path, {Rec? from}) {
    final parts = path.split('/');
    final last = parts.removeLast();
    Rec? obj = from ?? root;
    for (final p in parts) {
      obj = child(obj, p);
    }
    if (obj == null) return null;
    final s = slotOf(obj, last);
    if (s == null) return null;
    if (s.p != null) return Editable.fromPrim(s.p!);
    final r = deref(s.r);
    if (r != null && r.t == 6) return Editable.fromString(r);
    return null;
  }

  int? intOf(Prim? p) {
    if (p == null || p.type != 8) return null;
    return ByteData.sublistView(p.raw).getInt32(0, Endian.little);
  }

  /// Turn a raw primitive array into per-element Prims so elements can be edited.
  void ensurePrimList(Rec r) {
    if (r.t != 15 || r.rawPrim == null) return;
    final size = primSize[r.pt]!;
    final raw = r.rawPrim!;
    r.primList = [
      for (var i = 0; i < r.n; i++) Prim(r.pt, Uint8List.fromList(raw.sublist(i * size, (i + 1) * size)))
    ];
    r.rawPrim = null;
  }

  /// Elements of a .NET List<T>, limited to its real length (`_size`).
  List<Slot?> listItems(Rec list) {
    final arr = child(list, '_items');
    if (arr == null) return const [];
    final size = intOf(primOf(list, '_size')) ?? 0;
    final out = <Slot?>[];
    if (arr.t == 15) {
      ensurePrimList(arr);
      for (final p in arr.primList ?? const <Prim>[]) {
        out.add(Slot.prim(p));
      }
    } else {
      for (final s in arr.items ?? const <Slot>[]) {
        final r = s.r;
        if (r != null && (r.t == 13 || r.t == 14)) {
          for (var k = 0; k < r.count; k++) {
            out.add(null);
          }
        } else if (r != null && r.t == 10) {
          out.add(null);
        } else {
          out.add(s);
        }
      }
    }
    return out.length > size ? out.sublist(0, size) : out;
  }

  List<DictEntry> dictEntries(Rec dict) {
    final arr = child(dict, 'KeyValuePairs');
    final out = <DictEntry>[];
    if (arr == null) return out;
    for (final s in arr.items ?? const <Slot>[]) {
      final kvp = deref(s.r);
      if (kvp == null || !isClass(kvp)) continue;
      out.add(DictEntry(slotOf(kvp, 'key'), slotOf(kvp, 'value')));
    }
    return out;
  }

  /// Short human label for a key/value slot.
  String slotText(Slot? s) {
    if (s == null) return 'null';
    if (s.p != null) return primToText(s.p!) ?? '?';
    final r = deref(s.r);
    if (r == null) return 'null';
    if (r.t == 6) return r.stringValue;
    if (r.t == 10 || r.t == 13 || r.t == 14) return 'null';
    if (isEnum(r)) return '#${primToText(r.vals!.first.p!)}';
    return summary(r) ?? className(r);
  }

  static const _nameFields = ['CustomName', 'Name', 'ShelterName', 'FirstName', 'mTerm'];
  static const _idFields = ['PetID', 'ID', 'SlotID'];

  /// "#23 Fluffy" style label for an object, or null when nothing useful is found.
  String? summary(Rec r) {
    final (id, name) = _parts(r, 0);
    final parts = [if (id != null) id, if (name != null) name];
    return parts.isEmpty ? null : parts.join(' ');
  }

  (String?, String?) _parts(Rec r, int depth) {
    if (!isClass(r) || r.vals == null) return (null, null);
    String? id;
    String? name;
    for (final f in _idFields) {
      final v = intOf(primOf(r, f));
      if (v != null) {
        id = '#$v';
        break;
      }
    }
    // A string field holding a GUID we know the meaning of (e.g. a pet command).
    for (final s in r.vals!) {
      String? t;
      if (s.p != null && s.p!.isString) t = primToText(s.p!);
      final rr = deref(s.r);
      if (rr != null && rr.t == 6) t = rr.stringValue;
      final k = t == null ? null : GameDb.instance?.name(t);
      if (k != null) {
        name = k;
        break;
      }
    }
    for (final f in _nameFields) {
      if (name != null) break;
      final s = slotOf(r, f);
      if (s == null) continue;
      String? t;
      if (s.p != null && s.p!.isString) t = primToText(s.p!);
      final rr = deref(s.r);
      if (rr != null && rr.t == 6) t = rr.stringValue;
      if (t != null && t.isNotEmpty) {
        name = t;
        break;
      }
    }
    if ((id == null || name == null) && depth < 3) {
      for (final s in r.vals!) {
        final c = deref(s.r);
        if (c == null || !isClass(c) || isList(c) || isDict(c)) continue;
        final (cid, cname) = _parts(c, depth + 1);
        id ??= cid;
        name ??= cname;
        if (id != null && name != null) break;
      }
    }
    return (id, name);
  }
}


class SearchHit {
  final String path;
  final String value;
  final Editable edit;
  SearchHit(this.path, this.value, this.edit);
}

/// Case-insensitive search over field names and values of the whole save.
List<SearchHit> searchSave(SaveDoc doc, String query, {int limit = 300}) {
  final q = query.trim().toLowerCase();
  final hits = <SearchHit>[];
  if (q.isEmpty) return hits;
  final visited = <int>{};

  void consider(String path, String name, Editable e) {
    if (hits.length >= limit) return;
    final v = e.get();
    if (name.toLowerCase().contains(q) || v.toLowerCase().contains(q)) {
      hits.add(SearchHit(path, v, e));
    }
  }

  late void Function(Rec, String, int) visitObj;

  void visitSlot(Slot? s, String path, String name, int depth) {
    if (s == null || hits.length >= limit || depth > 60) return;
    if (s.p != null) {
      consider(path, name, Editable.fromPrim(s.p!));
      return;
    }
    final r = doc.deref(s.r);
    if (r == null) return;
    if (r.t == 6) {
      consider(path, name, Editable.fromString(r));
      return;
    }
    if (r.t == 15) {
      return; // big primitive arrays are browsed, not searched
    }
    if (!doc.isClass(r) || !visited.add(r.oid == 0 ? r.ci!.oid : r.oid)) return;
    visitObj(r, path, depth + 1);
  }

  visitObj = (Rec r, String path, int depth) {
    if (doc.isList(r)) {
      final items = doc.listItems(r);
      for (var i = 0; i < items.length; i++) {
        final label = '[$i]${_sum(doc, items[i])}';
        visitSlot(items[i], '$path › $label', label, depth);
      }
    } else if (doc.isDict(r)) {
      for (final e in doc.dictEntries(r)) {
        final key = doc.slotText(e.key);
        visitSlot(e.value, '$path › $key', key, depth);
      }
    } else if (doc.isEnum(r)) {
      // shown as a value of its parent; nothing more to search
    } else {
      final names = r.ci!.memberNames;
      for (var i = 0; i < r.vals!.length && i < names.length; i++) {
        if (isNoiseField(names[i]) || _noiseFields.contains(names[i])) continue;
        final n = displayName(names[i]);
        visitSlot(r.vals![i], '$path › $n', n, depth);
      }
    }
  };

  final root = doc.root;
  if (root != null) visitObj(root, 'SaveData', 0);
  return hits;
}

String _sum(SaveDoc doc, Slot? s) {
  final r = s == null ? null : doc.deref(s.r);
  if (r == null) return '';
  final t = doc.summary(r);
  return t == null ? '' : ' $t';
}
