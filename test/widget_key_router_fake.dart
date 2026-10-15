// test/widget_key_router_fake.dart - a router's keys as the widget key service touches them (ID-407).
import 'package:cfg_pia_wg/widget_key_service.dart' show kAuthKeysUploadPath;

import 'watchdog_test_utils.dart';

/// A router's keys as the service touches them: the heredoc upload file, NVRAM's sshd_authkeys and
/// the live authorized_keys. With [keeps] false, the router takes the write and keeps nothing, as a
/// write that didn't land would leave it.
class FakeKeysRouter {
  FakeKeysRouter(this.nv, {this.keeps = true}) : live = nv;
  String nv, live;
  final bool keeps;
  String _file = '';
  late final RecordingSSHClient client = RecordingSSHClient(responder: _respond);

  String _respond(String cmd) {
    final up = RegExp("cat (>>?) '$kAuthKeysUploadPath' <<'WATCHDOG_EOF'\\n([\\s\\S]*)WATCHDOG_EOF\\n").firstMatch(cmd);
    if (up != null) {
      _file = up.group(1) == '>' ? up.group(2)! : _file + up.group(2)!;
      return '';
    }
    if (cmd.startsWith('nvram set sshd_authkeys="\$(cat $kAuthKeysUploadPath)"')) {
      if (keeps) nv = live = _file.trimRight();
      return '';
    }
    if (cmd == 'nvram get sshd_authkeys') return nv;
    if (cmd.startsWith('cat ~/.ssh/authorized_keys')) return live;
    return '';
  }
}

