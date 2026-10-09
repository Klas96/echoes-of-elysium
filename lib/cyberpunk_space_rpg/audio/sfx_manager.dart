// Web uses HTML AudioElement; desktop/mobile use audioplayers (Linux-capable).
export 'sfx_manager_native.dart' if (dart.library.html) 'sfx_manager_web.dart';
