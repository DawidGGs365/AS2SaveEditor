import 'dart:convert';
import 'dart:typed_data';

import 'graph.dart';
import 'nrbf.dart';

/// A parsed Animal Shelter 2 .save file:
///   [header stream: SaveFileHeaderData][zero padding up to bodyOffset][body stream: SaveData]
/// The header holds a copy of day, time, shelter name/icon, active quest and reputation, shown in the game's Load
/// window; [syncHeader] keeps it in step with the body.
///
/// Value edits change records in place, so an untouched file re-serialises byte for byte. Once something is added or
/// removed ([structural]), the body is re-written from the root by [GraphWriter].
class SaveDoc {
  final Uint8List original;
  final int bodyOffset;
  final int bodyEnd;
  final List<Rec> records;
  final Map<int, Rec> byId;
  final List<Rec> headerRecords;
  final Map<int, Rec> headerById;
  final int headerEnd;
  late final Graph graph = Graph(records, byId);
  bool structural = false;

  SaveDoc._(this.original, this.bodyOffset, this.bodyEnd, this.records, this.byId, this.headerRecords, this.headerById,
      this.headerEnd);

  static const _sig = [0x00, 0x01, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff];

  static int _findBody(Uint8List b, int from) {
    for (var i = from; i + _sig.length <= b.length; i++) {
      var ok = true;
      for (var j = 0; j < _sig.length; j++) {
        if (b[i + j] != _sig[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    throw const FormatException('Could not find the body stream in this file.');
  }

  static SaveDoc parse(Uint8List bytes) {
    final hr = NrbfReader(bytes, 0);
    final hrecs = <Rec>[];
    while (true) {
      final r = hr.readRecord();
      hrecs.add(r);
      if (r.t == 11) break;
    }
    final bodyOffset = _findBody(bytes, hr.p);
    final reader = NrbfReader(bytes, bodyOffset);
    final recs = <Rec>[];
    while (reader.p < bytes.length) {
      final r = reader.readRecord();
      recs.add(r);
      if (r.t == 11) break; // MessageEnd
    }
    return SaveDoc._(bytes, bodyOffset, reader.p, recs, reader.byId, hrecs, hr.byId, hr.p);
  }

  /// The object the stream header points at (SaveData).
  Rec? get root => byId[records.first.root];

  /// SaveFileHeaderData.AdditionalInfo (AdditionalSaveInfo).
  Rec? get headerInfo {
    final h = headerById[headerRecords.first.root];
    if (h == null) return null;
    final i = h.ci!.memberNames.indexOf('AdditionalInfo');
    if (i < 0) return null;
    final s = h.vals![i].r;
    return s == null ? null : (s.t == 9 ? headerById[s.ref] : s);
  }

  Uint8List build() {
    final hw = NrbfWriter();
    for (final r in headerRecords) {
      hw.writeRecord(r);
    }
    final header = hw.o.toBytes();
    if (header.length > bodyOffset) {
      throw StateError('The save header grew past $bodyOffset bytes (shelter name too long?).');
    }
    final Uint8List body;
    if (structural) {
      body = GraphWriter(graph).write();
    } else {
      final w = NrbfWriter();
      for (final r in records) {
        w.writeRecord(r);
      }
      body = w.o.toBytes();
    }
    final out = BytesBuilder(copy: false)
      ..add(header)
      ..add(Uint8List(bodyOffset - header.length)) // zero padding, as the game writes it
      ..add(body)
      ..add(Uint8List.sublistView(original, bodyEnd));
    return out.toBytes();
  }

  /// True when an untouched rebuild reproduces the file exactly (safety check before allowing edits).
  bool get roundTrips {
    final b = build();
    if (b.length != original.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (b[i] != original[i]) return false;
    }
    return true;
  }

  /// Finds a primitive member of a class record by field name.
  static Prim? prim(Rec? obj, String name) {
    if (obj == null || obj.ci == null || obj.vals == null) return null;
    final names = obj.ci!.memberNames;
    final i = names.indexOf(name);
    if (i < 0 || i >= obj.vals!.length) return null;
    return obj.vals![i].p;
  }

  /// Copies Day, Time, ShelterName, ShelterIconGUID, QuestGUID and Reputation from the body into the header.
  void syncHeader() {
    final info = headerInfo;
    final r = root;
    if (info == null || r == null) return;
    Rec? child(Rec o, String n) {
      final i = o.ci!.memberNames.indexOf(n);
      if (i < 0 || i >= o.vals!.length) return null;
      final s = o.vals![i].r;
      return s == null ? null : (s.t == 9 ? byId[s.ref] : s);
    }

    void copyPrim(Rec? from, String fromName, String toName) {
      final a = prim(from, fromName), b = prim(info, toName);
      if (a != null && b != null && a.type == b.type) b.raw = Uint8List.fromList(a.raw);
    }

    void copyStr(String? v, String toName) {
      if (v == null) return;
      final i = info.ci!.memberNames.indexOf(toName);
      if (i < 0) return;
      final s = info.vals![i].r;
      final target = s == null ? null : (s.t == 9 ? headerById[s.ref] : s);
      if (target != null && target.t == 6) target.s = Uint8List.fromList(utf8.encode(v));
    }

    String? strOf(Rec? o, String n) {
      if (o == null) return null;
      final c = child(o, n);
      return c != null && c.t == 6 ? c.stringValue : null;
    }

    final time = child(r, 'TimeSaveData');
    copyPrim(time, 'Day', 'Day');
    copyPrim(time, 'Time', 'Time');
    copyPrim(r, 'Reputation', 'ReputationAmount');
    final shelter = child(r, 'PlayerShelterInfo');
    copyStr(strOf(shelter, 'ShelterName'), 'ShelterName');
    copyStr(strOf(shelter, 'ShelterIconGUID'), 'ShelterIconGUID');
    copyStr(strOf(child(r, 'Quests'), 'ActiveQuestGuid'), 'QuestGUID');
  }
}
