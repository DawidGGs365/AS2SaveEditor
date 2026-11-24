// Structural editing for the NRBF object graph: remove / insert list and dictionary entries, deep-clone objects,
// create strings, and re-serialise the whole graph from the root.
//
// The original reader keeps records exactly as they appeared in the file, which is perfect for in-place value
// edits (byte-identical output) but breaks as soon as something is removed: the removed entry may carry the class
// metadata later records point to (ClassWithId), or be the first occurrence of an object referenced later.
// [GraphWriter] therefore writes a fresh stream from the root (depth-first, every object inline at its first use,
// metadata on the first instance of each class), which BinaryFormatter reads the same way as the game's own output.
import 'dart:convert';
import 'dart:typed_data';

import 'nrbf.dart';

/// Content records (the ones that are objects with an id).
bool isObjRec(Rec r) => r.t == 1 || r.t == 4 || r.t == 5 || r.t == 6 || r.t == 7 || r.t == 15 || r.t == 16 || r.t == 17;
bool isNullRec(Rec r) => r.t == 10 || r.t == 13 || r.t == 14;

int objId(Rec r) => (r.t == 4 || r.t == 5) ? r.ci!.oid : r.oid;

class Graph {
  final Map<int, Rec> byId;
  final List<Rec> records; // original stream (for libraries + header)
  int _nextId;

  Graph(this.records, this.byId) : _nextId = _maxId(byId) + 1;

  static int _maxId(Map<int, Rec> m) {
    var mx = 0;
    for (final r in m.values) {
      final id = isObjRec(r) ? objId(r) : 0;
      if (id > mx) mx = id;
    }
    return mx;
  }

  int newId() => _nextId++;

  Slot nullSlot() => Slot.rec(Rec(10));

  /// How many places point at object [id] (its inline occurrence counts as one).
  int useCount(int id) {
    var n = 0;
    final seen = <Rec>{};
    void visit(Rec r) {
      if (!seen.add(r)) return;
      if (r.t == 9 && r.ref == id) n++;
      if (isObjRec(r) && objId(r) == id) n++;
      for (final s in [...?r.vals, if (r.t != 8 && r.t != 15) ...?r.items]) {
        if (s.r != null) visit(s.r!);
      }
    }
    for (final r in records) {
      visit(r);
    }
    for (final r in byId.values) {
      visit(r);
    }
    return n;
  }

  Rec? deref(Rec? r) {
    if (r == null) return null;
    if (r.t == 9) return byId[r.ref];
    if (isNullRec(r)) return null;
    return r;
  }

  /// Class metadata record (t 4/5) for a class instance.
  Rec metaOf(Rec r) => r.t == 1 ? byId[r.mid]! : r;

  /// Expands null runs (ObjectNullMultiple*) into one ObjectNull per slot, so slot index == member/item index.
  List<Slot> expandNulls(List<Slot> s) {
    if (!s.any((x) => x.r != null && (x.r!.t == 13 || x.r!.t == 14))) return s;
    final out = <Slot>[];
    for (final x in s) {
      if (x.r != null && (x.r!.t == 13 || x.r!.t == 14)) {
        for (var i = 0; i < x.r!.count; i++) {
          out.add(Slot.rec(Rec(10)));
        }
      } else {
        out.add(x);
      }
    }
    return out;
  }

  void normalize(Rec r) {
    if (r.vals != null) r.vals = expandNulls(r.vals!);
    if (r.items != null && r.t != 8) r.items = expandNulls(r.items!);
  }

  // ---------------------------------------------------------------- strings / clones

  Rec newString(String v) {
    final r = Rec(6)
      ..oid = newId()
      ..s = Uint8List.fromList(utf8.encode(v));
    byId[r.oid] = r;
    return r;
  }

  /// Deep copy of an object subtree: every reachable object gets a new id (shared sub-objects are copied once
  /// and stay shared inside the copy). Class metadata is shared through ClassWithId records.
  Rec deepClone(Rec src) {
    final map = <int, Rec>{};
    Rec copy(Rec r) {
      final id = objId(r);
      final done = map[id];
      if (done != null) return done;
      normalize(r);
      late Rec c;
      switch (r.t) {
        case 6:
          c = Rec(6)
            ..oid = newId()
            ..s = Uint8List.fromList(r.s!);
          break;
        case 1:
        case 4:
        case 5:
          final meta = metaOf(r);
          c = Rec(1)
            ..oid = newId()
            ..mid = objId(meta)
            ..ci = meta.ci
            ..types = meta.types;
          break;
        case 7:
          c = Rec(7)
            ..oid = newId()
            ..at = r.at
            ..rank = r.rank
            ..lens = List.of(r.lens!)
            ..lb = r.lb == null ? null : List.of(r.lb!)
            ..bt = r.bt
            ..extra = r.extra;
          break;
        case 15:
          c = Rec(15)
            ..oid = newId()
            ..n = r.n
            ..pt = r.pt
            ..rawPrim = r.rawPrim == null ? null : Uint8List.fromList(r.rawPrim!)
            ..primList = r.primList?.map((p) => Prim(p.type, Uint8List.fromList(p.raw))).toList();
          break;
        case 16:
        case 17:
          c = Rec(r.t)
            ..oid = newId()
            ..n = r.n;
          break;
        default:
          throw StateError('cannot clone record ${r.t}');
      }
      map[id] = c;
      byId[objId(c)] = c;
      List<Slot> cloneSlots(List<Slot> s) => [for (final x in s) cloneSlot(x, copy)];
      if (r.vals != null) c.vals = cloneSlots(r.vals!);
      if (r.items != null && r.t != 15) c.items = cloneSlots(r.items!);
      return c;
    }

    return copy(src);
  }

  Slot cloneSlot(Slot x, Rec Function(Rec) copy) {
    if (x.p != null) return Slot.prim(Prim(x.p!.type, Uint8List.fromList(x.p!.raw)));
    final r = x.r!;
    if (isNullRec(r)) return Slot.rec(Rec(10));
    if (r.t == 8) {
      final p = r.items!.first.p!;
      return Slot.rec(Rec(8)
        ..pt = r.pt
        ..items = [Slot.prim(Prim(p.type, Uint8List.fromList(p.raw)))]);
    }
    final target = r.t == 9 ? byId[r.ref]! : r;
    final c = copy(target);
    return Slot.rec(Rec(9)..ref = objId(c));
  }

  // ---------------------------------------------------------------- List<T>

  Slot? member(Rec obj, String name) {
    normalize(obj);
    final i = obj.ci!.memberNames.indexOf(name);
    return i < 0 ? null : obj.vals![i];
  }

  void setMember(Rec obj, String name, Slot v) {
    normalize(obj);
    final i = obj.ci!.memberNames.indexOf(name);
    if (i < 0) throw StateError('no member $name');
    obj.vals![i] = v;
  }

  int _i32(Prim p) => ByteData.sublistView(p.raw).getInt32(0, Endian.little);
  void _setI32(Prim p, int v) => p.raw = (ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List();

  /// The backing array of a List`1 and its logical size.
  (Rec arr, Prim size) listParts(Rec list) {
    final arr = deref(member(list, '_items')!.r)!;
    normalize(arr);
    return (arr, member(list, '_size')!.p!);
  }

  int listLength(Rec list) => _i32(listParts(list).$2);

  void _bumpVersion(Rec list) {
    final v = member(list, '_version')?.p;
    if (v != null) _setI32(v, _i32(v) + 1);
  }

  void listRemoveAt(Rec list, int index) {
    final (arr, sizeP) = listParts(list);
    final size = _i32(sizeP);
    if (index < 0 || index >= size) throw RangeError.index(index, size);
    if (arr.t == 15) {
      _primArrayRemove(arr, index, size);
    } else {
      arr.items!.removeAt(index);
      arr.items!.insert(size - 1, Slot.rec(Rec(10))); // keep capacity, null the freed slot
    }
    _setI32(sizeP, size - 1);
    _bumpVersion(list);
  }

  void _primArrayRemove(Rec arr, int index, int size) {
    if (arr.primList != null) {
      final it = arr.primList!.removeAt(index);
      arr.primList!.insert(size - 1, Prim(it.type, Uint8List(it.raw.length)));
      return;
    }
    final w = primSize[arr.pt]!;
    final raw = arr.rawPrim!;
    raw.setRange(index * w, (size - 1) * w, raw, (index + 1) * w);
    raw.fillRange((size - 1) * w, size * w, 0);
  }

  /// Appends [value] (an object/string record already registered, or a primitive) to a List`1.
  void listAdd(Rec list, Slot value) {
    final (arr, sizeP) = listParts(list);
    final size = _i32(sizeP);
    final cap = arr.t == 15 ? arr.n : arr.items!.length;
    if (size >= cap) _growArray(arr, cap == 0 ? 4 : cap * 2);
    if (arr.t == 15) {
      final p = value.p!;
      if (arr.primList != null) {
        arr.primList![size] = p;
      } else {
        final w = primSize[arr.pt]!;
        arr.rawPrim!.setRange(size * w, (size + 1) * w, p.raw);
      }
    } else {
      arr.items![size] = value;
    }
    _setI32(sizeP, size + 1);
    _bumpVersion(list);
  }

  void _growArray(Rec arr, int cap) {
    if (arr.t == 15) {
      final w = primSize[arr.pt];
      if (arr.primList != null) {
        arr.primList!.addAll(List.generate(cap - arr.n, (_) => Prim(arr.pt, Uint8List(0))));
      } else {
        final raw = Uint8List(cap * w!)..setRange(0, arr.rawPrim!.length, arr.rawPrim!);
        arr.rawPrim = raw;
      }
      arr.n = cap;
      return;
    }
    while (arr.items!.length < cap) {
      arr.items!.add(Slot.rec(Rec(10)));
    }
    if (arr.t == 7) {
      arr.lens = [cap];
    } else {
      arr.n = cap;
    }
  }

  /// Logical items of a List`1 (dereferenced; null entries stay null).
  List<Slot> listSlots(Rec list) {
    final (arr, sizeP) = listParts(list);
    final size = _i32(sizeP);
    if (arr.t == 15) {
      _ensurePrimList(arr);
      return [for (var i = 0; i < size; i++) Slot.prim(arr.primList![i])];
    }
    return arr.items!.sublist(0, size);
  }

  void _ensurePrimList(Rec r) {
    if (r.rawPrim == null) return;
    final w = primSize[r.pt]!;
    r.primList = [
      for (var i = 0; i < r.n; i++) Prim(r.pt, Uint8List.fromList(r.rawPrim!.sublist(i * w, (i + 1) * w)))
    ];
    r.rawPrim = null;
  }

  // ---------------------------------------------------------------- Dictionary<K,V>

  Rec? dictPairsArray(Rec dict) {
    final s = member(dict, 'KeyValuePairs');
    final a = s == null ? null : deref(s.r);
    if (a != null) normalize(a);
    return a;
  }

  void dictRemoveAt(Rec dict, int index) {
    final a = dictPairsArray(dict)!;
    a.items!.removeAt(index);
    if (a.t == 7) {
      a.lens = [a.items!.length];
    } else {
      a.n = a.items!.length;
    }
    final v = member(dict, 'Version')?.p;
    if (v != null) _setI32(v, _i32(v) + 1);
  }

  /// Adds a KeyValuePair by cloning an existing pair of the same dictionary and returning the copy for editing.
  Rec dictAddClone(Rec dict, int templateIndex) {
    final a = dictPairsArray(dict)!;
    final tpl = deref(a.items![templateIndex].r)!;
    final c = deepClone(tpl);
    a.items!.add(Slot.rec(Rec(9)..ref = objId(c)));
    if (a.t == 7) {
      a.lens = [a.items!.length];
    } else {
      a.n = a.items!.length;
    }
    final v = member(dict, 'Version')?.p;
    if (v != null) _setI32(v, _i32(v) + 1);
    return c;
  }
}

/// Writes a complete NRBF stream for the graph rooted at the header's root id.
class GraphWriter {
  final Graph g;
  final NrbfWriter w = NrbfWriter();
  final Set<int> _written = {};
  final Map<int, int> _metaWritten = {}; // original meta id -> id of the object that now carries it
  final Set<int> _libsWritten = {};
  final Map<int, Rec> _libs = {};

  GraphWriter(this.g) {
    for (final r in g.records) {
      if (r.t == 12) _libs[r.lib] = r;
    }
  }

  Uint8List write() {
    final header = g.records.first;
    w.writeRecord(header);
    // all assembly records up front (the editor's reader, unlike .NET, doesn't accept them between members)
    for (final id in _libs.keys) {
      _lib(id);
    }
    final root = g.byId[header.root]!;
    _obj(root);
    w.writeRecord(Rec(11));
    return w.o.toBytes();
  }

  void _lib(int id) {
    if (id == 0 || _libsWritten.contains(id)) return;
    final l = _libs[id];
    if (l == null) throw StateError('unknown library $id');
    _libsWritten.add(id);
    w.writeRecord(l);
  }

  void _libsForTypes(List<TypeInfo> types) {
    for (final t in types) {
      if (t.bt == 4) _lib((t.extra as ClassRef).lib);
    }
  }

  /// Writes an object record inline (first use).
  void _obj(Rec r) {
    final id = objId(r);
    _written.add(id);
    g.normalize(r);
    switch (r.t) {
      case 6:
        w.u8(6);
        w.i32(r.oid);
        w.lps(r.s!);
        return;
      case 1:
      case 4:
      case 5:
        final meta = g.metaOf(r);
        final metaId = objId(meta);
        final carrier = _metaWritten[metaId];
        if (carrier == null) {
          // first instance of this class: write full metadata with this object's id
          _libsForTypes(meta.types!);
          if (meta.t == 5) _lib(meta.lib);
          _metaWritten[metaId] = id;
          w.u8(meta.t);
          w.classInfo(ClassInfo(id, meta.ci!.name, meta.ci!.names));
          for (final b in meta.bts!) {
            w.u8(b);
          }
          for (final ti in meta.types!) {
            w.typeExtra(ti.bt, ti.extra);
          }
          if (meta.t == 5) w.i32(meta.lib);
        } else {
          w.u8(1);
          w.i32(id);
          w.i32(carrier);
        }
        _members(r.vals!, meta.types!);
        return;
      case 7:
        if (r.bt == 4) _lib((r.extra as ClassRef).lib);
        w.u8(7);
        w.i32(r.oid);
        w.u8(r.at);
        w.i32(r.rank);
        for (final l in r.lens!) {
          w.i32(l);
        }
        if (r.lb != null) {
          for (final l in r.lb!) {
            w.i32(l);
          }
        }
        w.u8(r.bt);
        w.typeExtra(r.bt, r.extra);
        _items(r.items!, r.bt, r.extra);
        return;
      case 15:
        w.u8(15);
        w.i32(r.oid);
        w.i32(r.n);
        w.u8(r.pt);
        if (r.rawPrim != null) {
          w.raw(r.rawPrim!);
        } else {
          for (final p in r.primList!) {
            w.prim(p);
          }
        }
        return;
      case 16:
      case 17:
        w.u8(r.t);
        w.i32(r.oid);
        w.i32(r.n);
        _items(r.items!, r.t == 16 ? 2 : 1, null);
        return;
    }
    throw StateError('cannot write record ${r.t}');
  }

  void _members(List<Slot> vals, List<TypeInfo> types) {
    for (var i = 0; i < vals.length; i++) {
      final s = vals[i];
      if (types[i].bt == 0) {
        w.prim(s.p!);
      } else {
        _value(s.r!);
      }
    }
  }

  void _items(List<Slot> items, int bt, Object? extra) {
    for (final s in items) {
      if (bt == 0) {
        w.prim(s.p!);
      } else {
        _value(s.r!);
      }
    }
  }

  /// A member/item value that is a record: null, primitive-typed, reference or inline object.
  void _value(Rec r) {
    if (isNullRec(r)) {
      w.u8(10);
      return;
    }
    if (r.t == 8) {
      w.writeRecord(r);
      return;
    }
    final target = r.t == 9 ? g.byId[r.ref] : r;
    if (target == null) throw StateError('dangling reference ${r.ref}');
    final id = objId(target);
    if (_written.contains(id)) {
      w.u8(9);
      w.i32(id);
    } else {
      _obj(target);
    }
  }
}
