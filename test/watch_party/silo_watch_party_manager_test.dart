import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/watch_party/silo_watch_party_manager.dart';

void main() {
  test('a clock sample takes out the server\'s own handling time', () {
    // Sent at 1000, received 40 ms later by a server whose clock runs 500 ms
    // ahead, answered 10 ms later, back at 1090.
    final sample = SiloWatchPartyManager.clockSample(1000, 1540, 1550, 1090);
    expect(sample.rttMs, 80);
    expect(sample.offsetMs, 500);
  });
}
