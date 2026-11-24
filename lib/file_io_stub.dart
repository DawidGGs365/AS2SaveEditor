import 'dart:typed_data';

Never _no() => throw UnsupportedError('Direct file access is not available on this platform.');

Future<Uint8List> readPath(String path) async => _no();
Future<void> writePath(String path, Uint8List bytes) async => _no();
Future<bool> pathExists(String path) async => _no();
Future<void> copyPath(String from, String to) async => _no();
