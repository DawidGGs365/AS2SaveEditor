import '../l10n.dart';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../gamedb.dart';
import '../obj.dart';
import '../save_doc.dart';
import '../ui_kit.dart';
import '../widgets.dart';

/// Random version-4 UUID, the format the game uses for item PersonalGUIDs.
String newPersonalGuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class InventoryView extends StatelessWidget {
  final SaveDoc doc;
  final VoidCallback onChanged;
  const InventoryView({super.key, required this.doc, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final root = O(doc, doc.root!);
    final players = root.path('PlayersData')?.pairs('PlayerSaveDatas') ?? const [];
    final items = root.o('ItemsSaveData');
    if (items == null || players.isEmpty) return Center(child: emptyNote(context, t('No player inventories in this save.')));
    final byGuid = <String, O>{for (final it in items.items('Items')) it.str('PersonalGUID') ?? '': it};
    var n = 0;
    return ListView(padding: const EdgeInsets.only(top: 8, bottom: 110), children: [
      for (final p in players) _player(context, root, items, byGuid, p, ++n),
    ]);
  }

  Widget _player(BuildContext context, O root, O items, Map<String, O> byGuid, O pair, int n) {
    final id = pair.str('key') ?? '';
    final inv = pair.o('value')?.o('InventorySaveData');
    final slots = inv?.items('InventoryItemSlotSaveInfos') ?? const [];
    return Section(
      title: n == 1 ? t('Player {0} (host)', [n]) : t('Player {0}', [n]),
      subtitle: t('Steam ID {0} · hotbar slots', [id]),
      children: [
        for (final s in slots) _slot(context, root, items, byGuid, s),
      ],
    );
  }

  Widget _slot(BuildContext context, O root, O items, Map<String, O> byGuid, O slot) {
    final db = GameDb.I;
    final guids = slot.strings('Guids').where((g) => g.isNotEmpty).toList();
    final first = guids.isEmpty ? null : byGuid[guids.first];
    final itemGuid = first?.str('ItemDataGUID');
    final label = guids.isEmpty
        ? t('Empty')
        : '${db.name(itemGuid) ?? 'Unknown item'}${guids.length > 1 ? '  ×${guids.length}' : ''}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 16, child: Text('${(slot.integer('SlotID') ?? 0) + 1}', style: context.tt.labelLarge)),
      title: Text(label, style: context.tt.bodyLarge?.copyWith(color: guids.isEmpty ? context.cs.onSurfaceVariant : null)),
      subtitle: itemGuid == null ? null : Text(db.description(itemGuid) ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: guids.isEmpty
          ? TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(t('Put item')),
              onPressed: () => _add(context, root, items, slot),
            )
          : IconButton(
              tooltip: t('Remove from inventory'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                for (final g in guids) {
                  final it = byGuid[g];
                  if (it != null) items.removeItem('Items', it);
                }
                while (slot.length('Guids') > 0) {
                  slot.removeAt('Guids', 0);
                }
                onChanged();
              },
            ),
    );
  }

  Future<void> _add(BuildContext context, O root, O items, O slot) async {
    final db = GameDb.I;
    final choices = [for (final a in db.choices('ItemData')) if (a.extra['inv'] == true && db.tr(a.nameTerm) != null) a];
    final pick = await pickAsset(context, t('Put item in slot {0}', [(slot.integer('SlotID') ?? 0) + 1]), choices,
        group: (a) => a.extra['price'] != null ? '\$${a.extra['price']}' : '');
    if (pick == null) return;
    // template: a stored copy of the same item (right save type for food bags, tools...), else a plain item
    final all = [...items.items('Items'), ...?root.o('ItemsOnScene')?.items('Items')];
    O? tpl;
    for (final it in all) {
      if (it.str('ItemDataGUID') == pick.guid) {
        tpl = it;
        break;
      }
    }
    tpl ??= all.firstWhere((it) => it.cls == 'ItemSaveData', orElse: () => all.first);
    final c = items.addClone('Items', tpl);
    final pg = newPersonalGuid();
    c.setStr('PersonalGUID', pg);
    c.setStr('ItemDataGUID', pick.guid);
    if (c.has('IsHanged')) c.setBool('IsHanged', false);
    slot.addString('Guids', pg);
    onChanged();
  }
}
