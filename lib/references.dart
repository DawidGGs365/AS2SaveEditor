// Adding / removing pets and workers together with everything in the save that points at them by ID.
//
// Pet IDs (PetSaveStaticInfo.PetID) are referenced by: CageSaveInfo.AnimalID / MultiCageAnimalIDs (cage cells, -1 =
// empty), AIStationSaveData.PetID, ItemWithPetReferenceSaveData.ReferencedPet (items bound to a pet),
// AdopterSettingsSaveData.PrioritizedPetID, AdSaveData.PetID (newspaper ads), AIAdopterChoiceResultPetSaveData.PetID
// (an adopter's pending decision), BigParkSaveData.PetIds, PetsSaveData.PlayerAdoptedPetID, SyncPet.PetID (pets the
// players adopted) and WorkerSettingsSaveData.PetTakenOutID (a worker walking the pet).
// Workers: WorkerSettingsSaveData.ID (next one = WorkerListSaveData.NextSettingsID); their carried items live in
// ItemsSaveData.Items, keyed by the PersonalGUIDs in the worker's inventory slots.
import 'l10n.dart';
import 'nrbf.dart';
import 'obj.dart';
import 'save_doc.dart';
import 'views/inventory.dart' show newPersonalGuid;

Iterable<O> _objects(SaveDoc doc, String cls) sync* {
  final seen = <Rec>{};
  for (final r in doc.byId.values.toList()) {
    if ((r.t == 1 || r.t == 4 || r.t == 5) && r.ci?.nameStr == cls && seen.add(r)) yield O(doc, r);
  }
}

/// Removes all occurrences of [v] from a List<int> member.
void _removeInt(O owner, String field, int v) {
  final l = owner.o(field);
  if (l == null || !l.isList) return;
  for (var i = l.length() - 1; i >= 0; i--) {
    final slots = owner.g.listSlots(l.rec);
    final p = slots[i].p;
    if (p != null && int.tryParse(primToText(p) ?? '') == v) owner.removeAt(field, i);
  }
}

/// Why a pet can't be removed right now, or null.
String? petRemovalBlocker(SaveDoc doc, O pet) {
  final id = pet.o('PetStaticInfo')?.integer('PetID');
  if (id == null) return t('This pet has no ID.');
  for (final w in _objects(doc, 'WorkerSettingsSaveData')) {
    if (w.integer('PetTakenOutID') == id) return t('A worker is walking this pet right now. Wait until it is back.');
  }
  return null;
}

/// Deletes a pet and clears every reference to its ID.
void removePet(SaveDoc doc, O pet) {
  final root = O(doc, doc.root!);
  final id = pet.o('PetStaticInfo')!.integer('PetID')!;
  root.o('PetsSaveData')!.removeItem('PetSaveInfos', pet);

  for (final c in _objects(doc, 'CageSaveInfo')) {
    if (c.integer('AnimalID') == id) c.setNum('AnimalID', -1);
    _removeInt(c, 'MultiCageAnimalIDs', id);
  }
  for (final s in _objects(doc, 'AIStationSaveData')) {
    if (s.integer('PetID') == id) s.setNum('PetID', -1);
  }
  for (final it in _objects(doc, 'ItemWithPetReferenceSaveData')) {
    _removeInt(it, 'ReferencedPet', id);
  }
  for (final a in _objects(doc, 'AdopterSettingsSaveData')) {
    if (a.integer('PrioritizedPetID') == id) a.setNum('PrioritizedPetID', -1);
  }
  final ads = root.o('Ads');
  if (ads != null) {
    for (final ad in ads.items('AdList')) {
      if (ad.integer('PetID') == id) ads.removeItem('AdList', ad);
    }
  }
  // pending adoption decisions of adopters currently in the shelter
  for (final adopter in root.o('Adopters')?.items('Adopters') ?? const <O>[]) {
    final res = adopter.o('AdoptionResult');
    if (res == null) continue;
    for (final f in res.rec.ci!.memberNames) {
      final l = res.o(f);
      if (l == null || !l.isList) continue;
      for (final x in l.items()) {
        if (x.cls == 'AIAdopterChoiceResultPetSaveData' && x.integer('PetID') == id) res.removeItem(f, x);
      }
    }
  }
  final park = root.o('BigParkSaveData');
  if (park != null) _removeInt(park, 'PetIds', id);
  final ps = root.o('PetsSaveData')!;
  if (ps.integer('PlayerAdoptedPetID') == id) ps.setNum('PlayerAdoptedPetID', -1);
  for (final kv in root.o('PlayerAdoptedPets')?.pairs('PlayerPets') ?? const <O>[]) {
    final list = kv.o('value');
    if (list == null) continue;
    final slots = list.g.listSlots(list.rec);
    for (var i = slots.length - 1; i >= 0; i--) {
      final r = list.g.deref(slots[i].r);
      if (r != null && O(doc, r).integer('PetID') == id) list.g.listRemoveAt(list.rec, i);
    }
  }
  doc.structural = true;
}

/// Adds a copy of [pet] with a new ID. The copy keeps perks, needs, tricks and looks, starts outside any cage and
/// isn't tied to adopters, ads or items.
O duplicatePet(SaveDoc doc, O pet) {
  final root = O(doc, doc.root!);
  final ps = root.o('PetsSaveData')!;
  final c = ps.addClone('PetSaveInfos', pet);
  final pets = ps.items('PetSaveInfos');
  var next = (ps.integer('MaxPetID') ?? 0) + 1;
  for (final p in pets) {
    final pid = p.o('PetStaticInfo')?.integer('PetID') ?? 0;
    if (pid >= next) next = pid + 1;
  }
  c.o('PetStaticInfo')!.setNum('PetID', next);
  ps.setNum('MaxPetID', next);
  final lost = c.o('LostPetInfo');
  if (lost != null) {
    lost.setBool('IsLost', false);
    lost.setNum('LostPetID', -1);
  }
  c.setBool('AdoptedByPlayer', false);
  final name = c.o('PetStaticInfo')!;
  final custom = name.str('CustomName') ?? '';
  if (custom.isNotEmpty) name.setStr('CustomName', '$custom 2');
  return c;
}

/// Why a worker can't be removed right now, or null.
String? workerRemovalBlocker(O worker) {
  final s = worker.o('Settings');
  if ((s?.integer('PetTakenOutID') ?? -1) != -1) return t('This worker is walking a pet right now. Wait until it is back.');
  return null;
}

List<String> _inventoryGuids(O worker) {
  final inv = worker.o('SLSaveData')?.o('Inventory');
  return [
    for (final slot in inv?.items('InventoryItemSlotSaveInfos') ?? const <O>[])
      for (final g in slot.strings('Guids'))
        if (g.isNotEmpty) g
  ];
}

/// Fires a worker: removes them and the items they were carrying.
void removeWorker(SaveDoc doc, O worker) {
  final root = O(doc, doc.root!);
  final carried = _inventoryGuids(worker).toSet();
  root.o('Workers')!.removeItem('Workers', worker);
  final items = root.o('ItemsSaveData');
  if (items != null) {
    for (final it in items.items('Items')) {
      if (carried.contains(it.str('PersonalGUID'))) items.removeItem('Items', it);
    }
  }
  doc.structural = true;
}

/// Hires a copy of [worker] with a new ID and name; the copy's carried items are copied too (with new item IDs).
O duplicateWorker(SaveDoc doc, O worker, String name) {
  final root = O(doc, doc.root!);
  final list = root.o('Workers')!;
  final c = list.addClone('Workers', worker);
  final next = list.integer('NextSettingsID') ?? 0;
  c.o('Settings')!.setNum('ID', next);
  list.setNum('NextSettingsID', next + 1);
  c.o('Settings')!.o('PersonalInfo')?.setStr('Name', name);
  c.o('Settings')!.setNum('PetTakenOutID', -1);
  c.o('Settings')!.setBool('AwaitingReturn', false);
  // carried items: give the copy its own item records
  final items = root.o('ItemsSaveData');
  final byGuid = <String, O>{for (final it in items?.items('Items') ?? const <O>[]) it.str('PersonalGUID') ?? '': it};
  final inv = c.o('SLSaveData')?.o('Inventory');
  for (final slot in inv?.items('InventoryItemSlotSaveInfos') ?? const <O>[]) {
    final gs = slot.strings('Guids');
    for (var i = gs.length - 1; i >= 0; i--) {
      slot.removeAt('Guids', i);
    }
    for (final g in gs) {
      final src = byGuid[g];
      if (src == null || items == null) continue;
      final copy = items.addClone('Items', src);
      final ng = newPersonalGuid();
      copy.setStr('PersonalGUID', ng);
      slot.addString('Guids', ng);
    }
  }
  return c;
}

