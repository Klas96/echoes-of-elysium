import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_audio_port.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/audio/sfx_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_sfx_port.dart';

/// Shared conditional export API — on VM this is the native manager.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SfxManager sfx;

  setUp(() {
    SfxManager.portFactory = () => RecordingSfxPort();
    SfxManager.globalContextSetter = (_) async {};
    sfx = SfxManager();
    sfx.debugReset();
  });

  tearDown(() {
    sfx.debugReset();
    SfxManager.portFactory = AudioplayersSfxPort.new;
    SfxManager.globalContextSetter = defaultSfxGlobalContextSetter;
  });

  test('shared API methods exist and are safe when muted', () async {
    await sfx.applyUserVolume(0, enabled: true);
    await sfx.init();
    await sfx.unlockAfterGesture();
    await sfx.playFootstep();
    await sfx.playDamage();
    await sfx.playPortal();
    await sfx.playShoot();
    await sfx.playChime();
    await sfx.playHeal();
    await sfx.playVoice('audio/voices/x.mp3');
    await sfx.stopVoice();
    await sfx.pauseForAppLifecycle();
    await sfx.resumeForAppLifecycle();
  });
}
