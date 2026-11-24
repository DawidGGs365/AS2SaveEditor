import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readPath(String path) async => Uint8List.fromList(await File(path).readAsBytes());
Future<void> writePath(String path, Uint8List bytes) => File(path).writeAsBytes(bytes, flush: true);
Future<bool> pathExists(String path) => File(path).exists();
Future<void> copyPath(String from, String to) async {
  await File(from).copy(to);
}
