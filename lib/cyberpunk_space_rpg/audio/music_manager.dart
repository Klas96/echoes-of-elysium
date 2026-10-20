// Desktop/mobile: audioplayers. Web: HTMLAudioElement (see music_manager_web).
export 'sfx_manager.dart';
export 'music_manager_native.dart'
    if (dart.library.html) 'music_manager_web.dart';
