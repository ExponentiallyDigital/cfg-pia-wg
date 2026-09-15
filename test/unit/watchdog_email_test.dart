// test/unit/watchdog_email_test.dart - where a watchdog form's email fields come from (ID-050).
import 'package:cfg_pia_wg/watchdog_email.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = EmailSettings(from: 'a@x.com', to: 'you@x.com', subject: 'A', smtpServer: 'a.x.com:465', smtpUser: 'ua', smtpPass: 'pa');
const _b = EmailSettings(from: 'b@x.com', to: 'you@x.com', subject: 'B', smtpServer: 'b.x.com:587', smtpUser: 'ub', smtpPass: 'pb');
const _c = EmailSettings(from: 'c@x.com', to: 'you@x.com', subject: 'C', smtpServer: 'c.x.com:465', smtpUser: 'uc', smtpPass: 'pc');

void main() {
  group('which settings pre-fill the form', () {
    test("the slot's own come first", () {
      expect(firstEmailSettings(slot: 1, own: _a, session: _b, others: {2: _c}), same(_a));
    });

    test('then the ones entered this session', () {
      expect(firstEmailSettings(slot: 1, own: const EmailSettings(), session: _b, others: {2: _c}), same(_b));
    });

    test('then the lowest-numbered other slot that has some, never the slot itself', () {
      final others = {1: _a, 5: _c, 3: const EmailSettings(), 4: _b};
      expect(firstEmailSettings(slot: 1, others: others), same(_b), reason: 'slot 3 has none; 4 is next');
    });

    test('none anywhere is null, and the user types them', () {
      expect(firstEmailSettings(slot: 2, own: const EmailSettings(), others: {1: const EmailSettings()}), isNull);
    });

    test('a set with no server and no recipient counts as none', () {
      expect(const EmailSettings(from: 'a@x.com', subject: 'only these').isEmpty, isTrue);
      expect(const EmailSettings(smtpServer: 'mail.x.com:465').isEmpty, isFalse);
      expect(const EmailSettings(to: 'you@x.com').isEmpty, isFalse);
    });
  });

  group('reading every slot in one round trip', () {
    test('the command reads each key for slots 1 to 5', () {
      for (final key in kEmailSettingKeys) {
        expect(kEmailSettingsCommand, contains(key));
      }
      expect(kEmailSettingsCommand, startsWith('for s in 1 2 3 4 5; do'));
      expect(kEmailSettingsCommand, contains(r'nvram get "wgc${s}_wd_$k"'));
    });

    test('parses slot, key and value, keeping a value that contains a tab', () {
      final out = '3\temail_from\tme@x.com\n3\temail_to\tyou@x.com\n3\temail_subject\tMy prefix\n'
          '3\tsmtp_server\tmail.x.com:587\n3\tsmtp_user\tu3\n3\tsmtp_pass\tp\tw3\r\n'
          '4\temail_from\t\n4\tsmtp_server\t\nnot a line\n';
      final parsed = parseEmailSettings(out);
      final s3 = parsed[3]!;
      expect([s3.from, s3.to, s3.subject, s3.smtpServer, s3.smtpUser, s3.smtpPass],
          ['me@x.com', 'you@x.com', 'My prefix', 'mail.x.com:587', 'u3', 'p\tw3']);
      expect(parsed[4]!.isEmpty, isTrue);
      expect(parsed.keys, [3, 4]);
    });
  });
}
