// Direct file access only exists off the web; everything else goes through the file picker.
export 'file_io_stub.dart' if (dart.library.io) 'file_io_native.dart';
