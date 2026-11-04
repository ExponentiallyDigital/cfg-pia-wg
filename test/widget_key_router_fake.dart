// test/widget_key_router_fake.dart - a router's keys as the widget key service touches them (ID-407).
import 'package:cfg_pia_wg/widget_key_service.dart' show kAuthKeysUploadPath;

import 'watchdog_test_utils.dart';

/// A router's keys as the service touches them: the heredoc upload file, NVRAM's sshd_authkeys and
/// the live authorized_keys. With [keeps] false, the router takes the write and keeps nothing, as a
/// write that didn't land would leave it.
class FakeKeysRouter {
  FakeKeysRouter(this.nv, {this.keeps = true, String? script}) : live = nv {
    if (script != null) files[kScriptPath] = script;
  }
  String nv, live;
  final bool keeps;
  String _file = '';

  /// Files written with heredocs other than the key list, by path: the widget's read script (ID-467).
  final Map<String, String> files = {};
  static const kScriptPath = '/jffs/cfg-pia-wg/widget-read.sh';
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
    final other = RegExp("cat (>>?) '([^']+)' <<'WATCHDOG_EOF'\\n([\\s\\S]*)WATCHDOG_EOF\\n").firstMatch(cmd);
    if (other != null) {
      if (keeps) files[other.group(2)!] = other.group(1) == '>' ? other.group(3)! : (files[other.group(2)!] ?? '') + other.group(3)!;
      return '';
    }
    if (cmd == 'nvram get sshd_authkeys') return nv;
    if (cmd.startsWith('cat ~/.ssh/authorized_keys')) return live;
    final read = RegExp(r'^cat (\S+) 2>/dev/null$').firstMatch(cmd);
    if (read != null) return files[read.group(1)!] ?? '';
    return '';
  }
}

