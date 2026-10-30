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

  test('everyone gets the pinned file\'s default audio track', () {
    final pinned = SiloWatchPartyManager.partySource(_item, '5');
    expect(SiloWatchPartyManager.defaultAudioIndex(pinned), 2);
    expect(
      SiloWatchPartyManager.streamsOf(pinned, 'Subtitle').single['Index'],
      3,
    );
    // No default flagged: the first audio track.
    final other = SiloWatchPartyManager.partySource(_item, '9');
    expect(SiloWatchPartyManager.defaultAudioIndex(other), 1);
    // No pin, or a pin Moonfin doesn't list: the first file.
    expect(SiloWatchPartyManager.partySource(_item, null)?['Id'], '5');
    expect(SiloWatchPartyManager.partySource(_item, '404')?['Id'], '5');
  });
}

const _item = {
  'MediaSources': [
    {
      'Id': '5',
      'MediaStreams': [
        {'Type': 'Video', 'Index': 0},
        {'Type': 'Audio', 'Index': 1, 'IsDefault': false},
        {'Type': 'Audio', 'Index': 2, 'IsDefault': true},
        {'Type': 'Subtitle', 'Index': 3, 'DisplayTitle': 'English'},
      ],
    },
    {
      'Id': '9',
      'MediaStreams': [
        {'Type': 'Audio', 'Index': 1},
      ],
    },
  ],
};
