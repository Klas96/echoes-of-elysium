// Picks the web implementation on Flutter web, native (audioplayers) elsewhere.
export 'sfx_manager_native.dart' if (dart.library.html) 'sfx_manager_web.dart';
