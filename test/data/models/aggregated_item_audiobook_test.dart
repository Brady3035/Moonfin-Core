import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';

AggregatedItem _item(Map<String, dynamic> raw) =>
    AggregatedItem(id: 'i1', serverId: 's1', rawData: raw);

void main() {
  group('AggregatedItem.isAudiobook', () {
    test('a readable book in a books library stays a book', () {
      final item = _item({
        'Type': 'Book',
        'MediaType': 'Book',
        'CollectionType': 'books',
      });

      expect(item.isAudiobook, isFalse);
    });

    test('a readable book under a books parent stays a book', () {
      final item = _item({
        'Type': 'Book',
        'ParentCollectionType': 'books',
      });

      expect(item.isAudiobook, isFalse);
    });

    test('an audio file typed as a book is an audiobook', () {
      final item = _item({
        'Type': 'Book',
        'MediaType': 'Audio',
        'CollectionType': 'books',
      });

      expect(item.isAudiobook, isTrue);
    });

    test('the server type wins on its own', () {
      expect(_item({'Type': 'AudioBook'}).isAudiobook, isTrue);
    });

    test('audio in a books library is an audiobook', () {
      final item = _item({
        'Type': 'Audio',
        'MediaType': 'Audio',
        'CollectionType': 'books',
      });

      expect(item.isAudiobook, isTrue);
    });

    test('a long audio file with chapters is an audiobook', () {
      final item = _item({
        'Type': 'Audio',
        'MediaType': 'Audio',
        'Chapters': [
          {'Name': 'One'},
        ],
        'RunTimeTicks': const Duration(hours: 2).inMicroseconds * 10,
      });

      expect(item.isAudiobook, isTrue);
    });

    test('an ordinary song is not an audiobook', () {
      final item = _item({
        'Type': 'Audio',
        'MediaType': 'Audio',
        'RunTimeTicks': const Duration(minutes: 3).inMicroseconds * 10,
      });

      expect(item.isAudiobook, isFalse);
    });
  });
}
