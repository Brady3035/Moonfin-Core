import '../silo_image_registry.dart';
import 'silo_ids.dart';

/// A Silo person (`Person`: `name`, `bio`, `birth_date`, `death_date`,
/// `birthplace`, `photo_url`, provider ids) as the Jellyfin `Person` item
/// Moonfin's person page reads:
///
/// | Jellyfin | Silo |
/// |---|---|
/// | `Overview` | `bio` |
/// | `PremiereDate` | `birth_date` (born) |
/// | `EndDate` | `death_date` (died) |
/// | `ProductionLocations` | `[birthplace]` |
/// | `ProviderIds` | `imdb_id`, `tmdb_id`, `tvdb_id` |
/// | `ImageTags.Primary` | `photo_url`, registered under the person's id |
Map<String, dynamic> siloPersonToBaseItemDto(
  Map<String, dynamic> person, {
  SiloImageRegistry? images,
}) {
  String? text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  String? date(Object? v) {
    final parsed = v is String ? DateTime.tryParse(v) : null;
    if (parsed == null) return null;
    final d = DateTime.utc(parsed.year, parsed.month, parsed.day);
    return '${d.toIso8601String().substring(0, 19)}.0000000Z';
  }

  final id = siloIdOf(person['id']) ?? '';
  final name = text(person['name']) ?? '';
  images?.note(id);
  final photo = images?.register(
    id,
    SiloImageType.primary,
    person['photo_url'] as String?,
  );
  final birthplace = text(person['birthplace']);
  return {
    'Id': id,
    'Name': name,
    'SortName': name,
    'Type': 'Person',
    'IsFolder': false,
    'Overview': ?text(person['bio']),
    'PremiereDate': ?date(person['birth_date']),
    'EndDate': ?date(person['death_date']),
    'ProductionLocations': [?birthplace],
    'ProviderIds': {
      'Imdb': ?text(person['imdb_id']),
      'Tmdb': ?text(person['tmdb_id']),
      'Tvdb': ?text(person['tvdb_id']),
    },
    'ImageTags': {'Primary': ?photo},
    'BackdropImageTags': const <String>[],
    if (text(person['homepage']) case final home?)
      'ExternalUrls': [
        {'Name': 'Website', 'Url': home},
      ],
  };
}
