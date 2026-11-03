/// PIN enrolment tests.
///
/// The quick-switch PIN is only useful if it is actually written when the
/// clinician enrols one, so these exercise the store end to end over the
/// platform channel's mock.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/security/pin_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('an enrolled PIN verifies and is not stored in the clear', () async {
    const PinStore store = PinStore();
    await store.set('2468');

    expect(await store.hasPin, isTrue);
    expect(await store.verify('2468'), isTrue);
    expect(await store.verify('1357'), isFalse);

    final String? raw = await const FlutterSecureStorage().read(
      key: 'nodex.session.pin_digest',
    );
    expect(raw, isNotNull);
    expect(raw, isNot(contains('2468')));
  });

  test('an unacceptable PIN is refused before anything is written', () async {
    const PinStore store = PinStore();
    await expectLater(store.set('1111'), throwsArgumentError);
    expect(await store.hasPin, isFalse);
  });

  test('clearing removes the PIN', () async {
    const PinStore store = PinStore();
    await store.set('2468');
    await store.clear();

    expect(await store.hasPin, isFalse);
    expect(await store.verify('2468'), isFalse);
  });
}
