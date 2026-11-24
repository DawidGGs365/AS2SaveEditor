// Lossless reader/writer for the .NET BinaryFormatter wire format (MS-NRBF).
// Strings are kept as raw bytes so unchanged data is re-emitted byte-for-byte.
import 'dart:convert';
import 'dart:typed_data';

const Map<int, int> primSize = {
  1: 1, 2: 1, 6: 8, 7: 2, 8: 4, 9: 8, 10: 1, 11: 4, 12: 8, 13: 8, 14: 2, 15: 4, 16: 8,
};

class Prim {
  final int type;
  Uint8List raw; // for string-like types (18, 5): payload without length prefix
  Prim(this.type, this.raw);
  bool get isString => type == 18 || type == 5;
}

class Slot {
  final Prim? p;
  final Rec? r;
  Slot.prim(Prim this.p) : r = null;
  Slot.rec(Rec this.r) : p = null;
}

class ClassRef {
  final Uint8List name;
  final int lib;
  ClassRef(this.name, this.lib);
}

class TypeInfo {
  final int bt;
  final Object? extra; // int (primitive type) | Uint8List | ClassRef | null
  TypeInfo(this.bt, this.extra);
}

class ClassInfo {
  final int oid;
  final Uint8List name;
  final List<Uint8List> names;
  ClassInfo(this.oid, this.name, this.names);
  String get nameStr => utf8.decode(name, allowMalformed: true);
  List<String> get memberNames =>
      names.map((n) => utf8.decode(n, allowMalformed: true)).toList();
}

class ClassMeta {
  final ClassInfo ci;
  final List<TypeInfo> types;
  ClassMeta(this.ci, this.types);
}

class Rec {
  final int t;
  Rec(this.t);

  int oid = 0, mid = 0, lib = 0, count = 0, ref = 0, pt = 0, n = 0;
  int root = 0, hdr = 0, maj = 0, min = 0;
  int at = 0, rank = 0, bt = 0;
  Uint8List? s; // BinaryObjectString payload / BinaryLibrary name
  ClassInfo? ci;
  List<TypeInfo>? types;
  List<int>? bts;
  List<Slot>? vals; // class members
  List<Slot>? items; // arrays
  List<int>? lens;
  List<int>? lb;
  Object? extra;
  Uint8List? rawPrim; // primitive array fast path
  List<Prim>? primList; // primitive array of strings/chars

  String get stringValue => utf8.decode(s ?? Uint8List(0), allowMalformed: true);
  set stringValue(String v) => s = Uint8List.fromList(utf8.encode(v));
}

bool _isNullRun(Rec r) => r.t == 13 || r.t == 14;

class NrbfReader {
  final Uint8List b;
  final ByteData bd;
  int p;
  final Map<int, ClassMeta> meta = {};
  final Map<int, Rec> byId = {};
  NrbfReader(this.b, [this.p = 0]) : bd = ByteData.sublistView(b);

  int u8() => b[p++];
  int i32() {
    final v = bd.getInt32(p, Endian.little);
    p += 4;
    return v;
  }

  Uint8List raw(int n) {
    final v = Uint8List.fromList(Uint8List.sublistView(b, p, p + n));
    p += n;
    return v;
  }

  Uint8List lps() {
    var n = 0, sh = 0;
    while (true) {
      final c = u8();
      n |= (c & 0x7f) << sh;
      sh += 7;
      if (c & 0x80 == 0) break;
    }
    return raw(n);
  }

  Prim prim(int t) {
    if (t == 18 || t == 5) return Prim(t, lps());
    if (t == 3) {
      final first = b[p];
      final n = first < 0x80 ? 1 : first < 0xE0 ? 2 : first < 0xF0 ? 3 : 4;
      return Prim(t, raw(n));
    }
    final size = primSize[t];
    if (size == null) throw FormatException('Unsupported primitive type $t at $p');
    return Prim(t, raw(size));
  }

  Object? typeExtra(int bt) {
    if (bt == 0 || bt == 7) return u8();
    if (bt == 3) return lps();
    if (bt == 4) {
      final name = lps();
      return ClassRef(name, i32());
    }
    return null;
  }

  ClassInfo classInfo() {
    final oid = i32();
    final name = lps();
    final n = i32();
    final names = <Uint8List>[for (var i = 0; i < n; i++) lps()];
    return ClassInfo(oid, name, names);
  }

  List<Slot> members(ClassInfo ci, List<TypeInfo> types) {
    final out = <Slot>[];
    var i = 0;
    while (i < ci.names.length) {
      final ti = types[i];
      if (ti.bt == 0) {
        out.add(Slot.prim(prim(ti.extra as int)));
        i++;
      } else {
        final r = readRecord();
        out.add(Slot.rec(r));
        i += _isNullRun(r) ? r.count : 1;
      }
    }
    return out;
  }

  List<Slot> readItems(int bt, Object? extra, int total) {
    final items = <Slot>[];
    var i = 0;
    while (i < total) {
      if (bt == 0) {
        items.add(Slot.prim(prim(extra as int)));
        i++;
      } else {
        final r = readRecord();
        items.add(Slot.rec(r));
        i += _isNullRun(r) ? r.count : 1;
      }
    }
    return items;
  }

  Rec readRecord() {
    final t = u8();
    final r = Rec(t);
    switch (t) {
      case 0:
        r.root = i32();
        r.hdr = i32();
        r.maj = i32();
        r.min = i32();
        break;
      case 1:
        {
          r.oid = i32();
          r.mid = i32();
          final m = meta[r.mid];
          if (m == null) throw FormatException('ClassWithId refers to unknown class ${r.mid}');
          r.ci = m.ci;
          r.types = m.types;
          byId[r.oid] = r;
          r.vals = members(m.ci, m.types);
          break;
        }
      case 4:
      case 5:
        {
          final ci = classInfo();
          r.ci = ci;
          final bts = <int>[for (var i = 0; i < ci.names.length; i++) u8()];
          r.bts = bts;
          final types = [for (final bt in bts) TypeInfo(bt, typeExtra(bt))];
          if (t == 5) r.lib = i32();
          r.types = types;
          meta[ci.oid] = ClassMeta(ci, types);
          byId[ci.oid] = r;
          r.vals = members(ci, types);
          break;
        }
      case 6:
        r.oid = i32();
        r.s = lps();
        byId[r.oid] = r;
        break;
      case 7:
        {
          r.oid = i32();
          r.at = u8();
          r.rank = i32();
          r.lens = [for (var i = 0; i < r.rank; i++) i32()];
          if (r.at >= 3) r.lb = [for (var i = 0; i < r.rank; i++) i32()];
          r.bt = u8();
          r.extra = typeExtra(r.bt);
          var total = 1;
          for (final l in r.lens!) {
            total *= l;
          }
          byId[r.oid] = r;
          r.items = readItems(r.bt, r.extra, total);
          break;
        }
      case 8:
        r.pt = u8();
        r.items = [Slot.prim(prim(r.pt))];
        break;
      case 9:
        r.ref = i32();
        break;
      case 10:
      case 11:
        break;
      case 12:
        r.lib = i32();
        r.s = lps();
        break;
      case 13:
        r.count = u8();
        break;
      case 14:
        r.count = i32();
        break;
      case 15:
        {
          r.oid = i32();
          r.n = i32();
          r.pt = u8();
          byId[r.oid] = r;
          if (r.pt == 18 || r.pt == 5 || r.pt == 3) {
            r.primList = [for (var i = 0; i < r.n; i++) prim(r.pt)];
          } else {
            final size = primSize[r.pt];
            if (size == null) throw FormatException('Unsupported array primitive ${r.pt}');
            r.rawPrim = raw(size * r.n);
          }
          break;
        }
      case 16:
      case 17:
        r.oid = i32();
        r.n = i32();
        byId[r.oid] = r;
        r.items = readItems(t == 16 ? 2 : 1, null, r.n);
        break;
      default:
        throw FormatException('Unsupported record type $t at ${p - 1}');
    }
    return r;
  }
}

class NrbfWriter {
  final BytesBuilder o = BytesBuilder(copy: false);
  final Map<int, ClassMeta> meta = {};

  void u8(int v) => o.addByte(v);
  void i32(int v) {
    final d = ByteData(4)..setInt32(0, v, Endian.little);
    o.add(d.buffer.asUint8List());
  }

  void raw(Uint8List b) => o.add(b);
  void lps(Uint8List b) {
    var n = b.length;
    while (true) {
      final c = n & 0x7f;
      n >>= 7;
      if (n != 0) {
        o.addByte(c | 0x80);
      } else {
        o.addByte(c);
        break;
      }
    }
    o.add(b);
  }

  void prim(Prim p) {
    if (p.isString) {
      lps(p.raw);
    } else {
      raw(p.raw);
    }
  }

  void typeExtra(int bt, Object? x) {
    if (bt == 0 || bt == 7) {
      u8(x as int);
    } else if (bt == 3) {
      lps(x as Uint8List);
    } else if (bt == 4) {
      final c = x as ClassRef;
      lps(c.name);
      i32(c.lib);
    }
  }

  void classInfo(ClassInfo ci) {
    i32(ci.oid);
    lps(ci.name);
    i32(ci.names.length);
    for (final n in ci.names) {
      lps(n);
    }
  }

  void slots(List<Slot> vs) {
    for (final s in vs) {
      if (s.p != null) {
        prim(s.p!);
      } else {
        writeRecord(s.r!);
      }
    }
  }

  void writeRecord(Rec r) {
    u8(r.t);
    switch (r.t) {
      case 0:
        i32(r.root);
        i32(r.hdr);
        i32(r.maj);
        i32(r.min);
        break;
      case 1:
        i32(r.oid);
        i32(r.mid);
        slots(r.vals!);
        break;
      case 4:
      case 5:
        classInfo(r.ci!);
        for (final b in r.bts!) {
          u8(b);
        }
        for (final ti in r.types!) {
          typeExtra(ti.bt, ti.extra);
        }
        if (r.t == 5) i32(r.lib);
        slots(r.vals!);
        break;
      case 6:
        i32(r.oid);
        lps(r.s!);
        break;
      case 7:
        i32(r.oid);
        u8(r.at);
        i32(r.rank);
        for (final l in r.lens!) {
          i32(l);
        }
        if (r.lb != null) {
          for (final l in r.lb!) {
            i32(l);
          }
        }
        u8(r.bt);
        typeExtra(r.bt, r.extra);
        slots(r.items!);
        break;
      case 8:
        u8(r.pt);
        prim(r.items!.first.p!);
        break;
      case 9:
        i32(r.ref);
        break;
      case 12:
        i32(r.lib);
        lps(r.s!);
        break;
      case 13:
        u8(r.count);
        break;
      case 14:
        i32(r.count);
        break;
      case 15:
        i32(r.oid);
        i32(r.n);
        u8(r.pt);
        if (r.rawPrim != null) {
          raw(r.rawPrim!);
        } else {
          for (final p in r.primList!) {
            prim(p);
          }
        }
        break;
      case 16:
      case 17:
        i32(r.oid);
        i32(r.n);
        slots(r.items!);
        break;
      case 10:
      case 11:
        break;
      default:
        throw FormatException('Cannot write record type ${r.t}');
    }
  }
}

/// 64-bit values are handled through BigInt so the code also works on the web
/// (dart2js does not support ByteData.getInt64/setInt64).
BigInt _read64(Uint8List raw, {required bool signed}) {
  final d = ByteData.sublistView(raw);
  final lo = d.getUint32(0, Endian.little);
  final hi = d.getUint32(4, Endian.little);
  var v = (BigInt.from(hi) << 32) | BigInt.from(lo);
  if (signed && (hi & 0x80000000) != 0) v -= BigInt.one << 64;
  return v;
}

bool _write64(Prim p, BigInt v, {required bool signed}) {
  final one = BigInt.one;
  final min = signed ? -(one << 63) : BigInt.zero;
  final max = signed ? (one << 63) - one : (one << 64) - one;
  if (v < min || v > max) return false;
  final u = v < BigInt.zero ? v + (one << 64) : v;
  final mask = BigInt.from(0xFFFFFFFF);
  final d = ByteData(8)
    ..setUint32(0, (u & mask).toInt(), Endian.little)
    ..setUint32(4, ((u >> 32) & mask).toInt(), Endian.little);
  p.raw = Uint8List.fromList(d.buffer.asUint8List());
  return true;
}

/// ---- primitive value helpers (display + edit) ----

String? primToText(Prim p) {
  final d = ByteData.sublistView(p.raw);
  switch (p.type) {
    case 1:
      return p.raw[0] != 0 ? 'true' : 'false';
    case 2:
      return p.raw[0].toString();
    case 10:
      return d.getInt8(0).toString();
    case 6:
      return d.getFloat64(0, Endian.little).toString();
    case 11:
      return d.getFloat32(0, Endian.little).toString();
    case 7:
      return d.getInt16(0, Endian.little).toString();
    case 14:
      return d.getUint16(0, Endian.little).toString();
    case 8:
      return d.getInt32(0, Endian.little).toString();
    case 15:
      return d.getUint32(0, Endian.little).toString();
    case 9:
    case 12:
    case 13:
      return _read64(p.raw, signed: true).toString();
    case 16:
      return _read64(p.raw, signed: false).toString();
    case 18:
    case 5:
      return utf8.decode(p.raw, allowMalformed: true);
    case 3:
      return utf8.decode(p.raw, allowMalformed: true);
  }
  return null;
}

String primTypeName(int t) =>
    const {
      1: 'bool', 2: 'byte', 3: 'char', 5: 'decimal', 6: 'double', 7: 'int16', 8: 'int32',
      9: 'int64', 10: 'sbyte', 11: 'float', 12: 'timespan', 13: 'datetime', 14: 'uint16',
      15: 'uint32', 16: 'uint64', 18: 'string',
    }[t] ??
    'type$t';

bool primEditable(Prim p) => p.type != 13 && p.type != 12 && p.type != 5 && p.type != 3;

/// Returns true when [text] was valid and the value was changed.
bool primSetFromText(Prim p, String text) {
  final t = text.trim();
  final d = ByteData(8);
  try {
    switch (p.type) {
      case 1:
        if (t != 'true' && t != 'false') return false;
        p.raw = Uint8List.fromList([t == 'true' ? 1 : 0]);
        return true;
      case 2:
        final v = int.parse(t);
        if (v < 0 || v > 255) return false;
        p.raw = Uint8List.fromList([v]);
        return true;
      case 10:
        final v = int.parse(t);
        if (v < -128 || v > 127) return false;
        d.setInt8(0, v);
        p.raw = d.buffer.asUint8List(0, 1).sublist(0);
        return true;
      case 6:
        d.setFloat64(0, double.parse(t), Endian.little);
        p.raw = Uint8List.fromList(d.buffer.asUint8List(0, 8));
        return true;
      case 11:
        d.setFloat32(0, double.parse(t), Endian.little);
        p.raw = Uint8List.fromList(d.buffer.asUint8List(0, 4));
        return true;
      case 7:
        final v = int.parse(t);
        if (v < -32768 || v > 32767) return false;
        d.setInt16(0, v, Endian.little);
        p.raw = Uint8List.fromList(d.buffer.asUint8List(0, 2));
        return true;
      case 14:
        final v = int.parse(t);
        if (v < 0 || v > 65535) return false;
        d.setUint16(0, v, Endian.little);
        p.raw = Uint8List.fromList(d.buffer.asUint8List(0, 2));
        return true;
      case 8:
        final v = int.parse(t);
        if (v < -2147483648 || v > 2147483647) return false;
        d.setInt32(0, v, Endian.little);
        p.raw = Uint8List.fromList(d.buffer.asUint8List(0, 4));
        return true;
      case 15:
        final v = int.parse(t);
        if (v < 0 || v > 4294967295) return false;
        d.setUint32(0, v, Endian.little);
        p.raw = Uint8List.fromList(d.buffer.asUint8List(0, 4));
        return true;
      case 9:
        return _write64(p, BigInt.parse(t), signed: true);
      case 16:
        return _write64(p, BigInt.parse(t), signed: false);
      case 18:
        p.raw = Uint8List.fromList(utf8.encode(text));
        return true;
    }
  } on FormatException {
    return false;
  }
  return false;
}
