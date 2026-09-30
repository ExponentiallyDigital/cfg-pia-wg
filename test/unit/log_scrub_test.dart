// Secrets never reach the app log, whatever carries them in (ID-323, ID-324).
//
// Redacting commands by key was the only filter until build 478, so stderr, secrets passed as
// arguments, and exceptions that quote a URL or a command reached the log - which is shown on
// screen and copied into bug reports (claims audit #17, #18). Every test here puts a sentinel
// secret into the log the way a real failure would, and fails if the sentinel survives.
import 'package:cfg_pia_wg/router_command.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/watchdog_email.dart';
import 'package:flutter_test/flutter_test.dart';

const piaPass = 'Pia-Sentinel-7731';
const piaUser = 'p987654321';
const sshPass = 'Ssh-Sentinel-4410';
const smtpPass = 'smtp-sentinel-app-pw';

SessionController session() => SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {})
  ..piaPassword = piaPass
  ..piaUsername = piaUser
  ..sshUsername = 'admin'
  ..sshPassword = sshPass
  ..watchdogEmail = const EmailSettings(
      from: 'a@example.com', to: 'b@example.com', subject: 's', smtpServer: 'smtp.example.com:465', smtpUser: 'u', smtpPass: smtpPass);

void main() {
  test('stderr that echoes a secret is scrubbed on its way into the log', () {
    final c = session();
    const r = RouterResult(stdout: '', stderr: 'sendmail: -ap$smtpPass rejected', exitCode: 1);
    c.logEntry('router command failed (${r.failureDetail}): x', isError: true);
    expect(c.log.last.message, isNot(contains(smtpPass)));
    c.dispose();
  });

  test('secrets passed as arguments are redacted from a command', () {
    for (final cmd in [
      "/jffs/cfg-pia-wg/mailsend-go -ssl -smtp s -port 465 auth -user 'me@x.com' -pass '$smtpPass'",
      '/usr/sbin/sendmail -H "exec openssl" -aume@x.com -ap$smtpPass -fme@x.com',
      'curl -s -u $piaUser:$piaPass https://www.privateinternetaccess.com/gtoken/generateToken',
    ]) {
      final r = redactCommand(cmd, maxLength: 1000);
      expect(r, isNot(contains(smtpPass)), reason: cmd);
      expect(r, isNot(contains(piaPass)), reason: cmd);
    }
  });

  test('an exception that quotes a secret is scrubbed, as AppErrors logs it raw', () {
    final c = session();
    c.logEntry('Exception: SSH login failed for admin with $sshPass', isError: true);
    c.logEntry('HttpException: Connection closed, uri = https://10.0.0.2:1337/addKey?pt=TOKEN123abc&pubkey=x');
    c.logEntry('Generated: [Interface]\nPrivateKey = kQ1zSentinelPrivateKeyValue=\nAddress = 10.0.0.2/32');
    c.logEntry('PIA refused $piaUser / $piaPass');
    final all = c.log.map((e) => e.message).join('\n');
    for (final secret in [sshPass, 'TOKEN123abc', 'kQ1zSentinelPrivateKeyValue', piaUser, piaPass]) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
    c.dispose();
  });

  test('ordinary words are left alone: a login of "admin" does not eat "administrator"', () {
    final c = session();
    c.logEntry('Ask your administrator; the admin login was refused.');
    expect(c.log.last.message, contains('administrator'));
    expect(c.log.last.message, contains('the <redacted> login'));
    c.dispose();
  });

  test('with no session secrets, nothing is redacted', () {
    final c = SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});
    c.logEntry('Reading router configuration...');
    expect(c.log.last.message, endsWith('Reading router configuration...'));
    c.dispose();
  });
}
