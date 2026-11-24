// Run with:  SAVE_FILE=/path/to/AutoSave.save flutter test test/edit_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:asseditor/obj.dart';
import 'package:asseditor/references.dart';
import 'package:asseditor/save_doc.dart';

void main() {
  final path = Platform.environment['SAVE_FILE'];
  final skip = path == null ? 'set SAVE_FILE to a .save path' : false;
  Uint8List bytes() => Uint8List.fromList(File(path!).readAsBytesSync());

  test('untouched save round-trips byte for byte (header + body)', () {
    final d = SaveDoc.parse(bytes());
    expect(d.roundTrips, isTrue);
  }, skip: skip);

  test('structural edits survive a save / reload', () {
    final d = SaveDoc.parse(bytes());
    final root = O(d, d.root!);
    final pets = root.path('PetsSaveData')!.items('PetSaveInfos');
    final pet = pets.first;
    final ps = pet.o('PerksSaveInfo')!;
    final before = ps.length('PerksInfo');
    // remove first perk, add a clone with a new guid
    final first = ps.items('PerksInfo').first;
    final removedGuid = first.str('Guid');
    ps.removeItem('PerksInfo', first);
    final c = ps.addClone('PerksInfo', ps.items('PerksInfo').first);
    c.setStr('Guid', 'ffffffffffffffffffffffffffffffff');
    // rename the pet (shared empty string must not rename others)
    pet.o('PetStaticInfo')!.setStr('CustomName', 'Edited');
    // money + header
    root.setNum('MoneyAmount', 12345);
    root.o('TimeSaveData')!.setNum('Day', 77);
    d.syncHeader();
    // string list add/remove
    final unlocks = root.strings('UnlockedPadlocks').length;
    root.addString('UnlockedPadlocks', 'abc');
    expect(d.structural, isTrue);

    final out = d.build();
    final d2 = SaveDoc.parse(out);
    final r2 = O(d2, d2.root!);
    final pets2 = r2.path('PetsSaveData')!.items('PetSaveInfos');
    final ps2 = pets2.first.o('PerksSaveInfo')!;
    expect(ps2.length('PerksInfo'), before);
    expect(ps2.items('PerksInfo').map((p) => p.str('Guid')), contains('ffffffffffffffffffffffffffffffff'));
    expect(ps2.items('PerksInfo').first.str('Guid'), isNot(removedGuid));
    expect(pets2.first.o('PetStaticInfo')!.str('CustomName'), 'Edited');
    for (final p in pets2.skip(1)) {
      expect(p.o('PetStaticInfo')!.str('CustomName'), isNot('Edited'));
    }
    expect(r2.dbl('MoneyAmount'), 12345);
    expect(r2.strings('UnlockedPadlocks').length, unlocks + 1);
    expect(r2.strings('UnlockedPadlocks').last, 'abc');
    expect(SaveDoc.prim(d2.headerInfo, 'Day') != null, isTrue);
    expect(O(d2, d2.headerInfo!).integer('Day'), 77);
    // a second save of the reloaded file is stable
    final d3 = SaveDoc.parse(d2.build());
    expect(O(d3, d3.root!).dbl('MoneyAmount'), 12345);
  }, skip: skip);

  int cagesWith(O root, int id) {
    var n = 0;
    final d = root.doc;
    for (final r in d.byId.values) {
      if (r.ci?.nameStr == 'CageSaveInfo' && O(d, r).integer('AnimalID') == id) n++;
    }
    return n;
  }

  test('pet duplicate + delete, worker hire + fire survive a save / reload', () {
    final d = SaveDoc.parse(bytes());
    final root = O(d, d.root!);
    final ps = root.o('PetsSaveData')!;
    final pets = ps.items('PetSaveInfos');
    final n = pets.length;
    final caged = pets.firstWhere((p) => cagesWith(root, p.o('PetStaticInfo')!.integer('PetID')!) > 0, orElse: () => pets.first);
    final cagedId = caged.o('PetStaticInfo')!.integer('PetID')!;
    final copy = duplicatePet(d, pets.first);
    final copyId = copy.o('PetStaticInfo')!.integer('PetID')!;
    expect(pets.map((p) => p.o('PetStaticInfo')!.integer('PetID')), isNot(contains(copyId)));
    expect(petRemovalBlocker(d, caged), isNull);
    removePet(d, caged);

    final workers = root.o('Workers')!;
    final wn = workers.length('Workers');
    if (wn == 0) {
      final d2 = SaveDoc.parse(d.build());
      expect(O(d2, d2.root!).o('PetsSaveData')!.items('PetSaveInfos').length, n);
      return;
    }
    final items = root.o('ItemsSaveData')!.length('Items');
    final w = workers.items('Workers').first;
    duplicateWorker(d, w, 'Clone Worker');

    final d2 = SaveDoc.parse(d.build());
    final r2 = O(d2, d2.root!);
    final pets2 = r2.o('PetsSaveData')!.items('PetSaveInfos');
    expect(pets2.length, n); // +1 copy, -1 removed
    final ids = pets2.map((p) => p.o('PetStaticInfo')!.integer('PetID')).toList();
    expect(ids, contains(copyId));
    expect(ids, isNot(contains(cagedId)));
    expect(r2.o('PetsSaveData')!.integer('MaxPetID'), copyId);
    expect(cagesWith(r2, cagedId), 0);
    final ws2 = r2.o('Workers')!.items('Workers');
    expect(ws2.length, wn + 1);
    final clone = ws2.last;
    expect(clone.o('Settings')!.o('PersonalInfo')!.str('Name'), 'Clone Worker');
    expect(r2.o('Workers')!.integer('NextSettingsID'), clone.o('Settings')!.integer('ID')! + 1);
    final carried = clone.o('SLSaveData')!.o('Inventory')!.items('InventoryItemSlotSaveInfos').expand((s) => s.strings('Guids')).where((g) => g.isNotEmpty).toList();
    final allItems = r2.o('ItemsSaveData')!.items('Items').map((i) => i.str('PersonalGUID')).toSet();
    expect(r2.o('ItemsSaveData')!.length('Items'), items + carried.length);
    for (final g in carried) {
      expect(allItems, contains(g));
    }
    // fire the clone again: back to the original item count
    removeWorker(d2, clone);
    final d3 = SaveDoc.parse(d2.build());
    final r3 = O(d3, d3.root!);
    expect(r3.o('Workers')!.length('Workers'), wn);
    expect(r3.o('ItemsSaveData')!.length('Items'), items);
  }, skip: skip);
}
