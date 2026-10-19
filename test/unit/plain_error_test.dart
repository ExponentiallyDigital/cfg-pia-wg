// test/unit/plain_error_test.dart - an exception's message as a user reads it (ID-041 step 1).
import 'package:flutter_test/flutter_test.dart';
import 'package:cfg_pia_wg/plain_error.dart';

void main() {
  test("takes Dart's 'Exception: ' off the front of the message", () {
    expect(plainError(Exception('router refused the login')), 'router refused the login');
  });

  test('takes it off wherever it appears, as every copy it replaced did', () {
    expect(plainError(Exception('Exception: nested')), 'nested');
    expect(plainError('wrapped: Exception: inner'), 'wrapped: inner');
  });

  test('leaves any other error as it reads', () {
    expect(plainError(StateError('bad state')), 'Bad state: bad state');
    expect(plainError('plain text'), 'plain text');
  });
}
