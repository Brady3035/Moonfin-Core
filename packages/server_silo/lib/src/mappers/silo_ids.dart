/// Item ids between Silo and Moonfin.
///
/// Moonfin treats an item id as an opaque string, so Silo's ids pass through
/// unchanged: content ids such as `movie-imdb-tt0295701`, numeric person and
/// library ids (sent as strings, sometimes as numbers).
///
/// Jellyfin also gives **genres and studios** ids, and Moonfin opens a genre or
/// studio page by id. Silo names them only, so Moonfin makes a synthetic id
/// from the name: `silo-genre:<name>` and `silo-studio:<name>`, with the name
/// percent-encoded so any character survives the round trip. The Silo client
/// recognises these ids and turns them back into a name filter.
library;

/// Prefix of a synthetic genre id.
const siloGenreIdPrefix = 'silo-genre:';

/// Prefix of a synthetic studio id.
const siloStudioIdPrefix = 'silo-studio:';

/// A Silo id as Moonfin's string id: numbers become their decimal text,
/// strings are trimmed, and anything empty or missing is null.
String? siloIdOf(Object? raw) {
  if (raw == null) return null;
  final text = raw is num ? raw.toString() : raw.toString().trim();
  return text.isEmpty ? null : text;
}

/// The synthetic id of the genre [name].
String siloGenreId(String name) =>
    '$siloGenreIdPrefix${Uri.encodeComponent(name)}';

/// The synthetic id of the studio [name].
String siloStudioId(String name) =>
    '$siloStudioIdPrefix${Uri.encodeComponent(name)}';

/// The genre name in a synthetic genre id, or null when [id] isn't one.
String? siloGenreNameOf(String id) => _nameAfter(siloGenreIdPrefix, id);

/// The studio name in a synthetic studio id, or null when [id] isn't one.
String? siloStudioNameOf(String id) => _nameAfter(siloStudioIdPrefix, id);

/// Whether [id] is one of the synthetic genre or studio ids.
bool isSyntheticSiloId(String id) =>
    id.startsWith(siloGenreIdPrefix) || id.startsWith(siloStudioIdPrefix);

String? _nameAfter(String prefix, String id) {
  if (!id.startsWith(prefix)) return null;
  final encoded = id.substring(prefix.length);
  if (encoded.isEmpty) return null;
  try {
    return Uri.decodeComponent(encoded);
  } on ArgumentError {
    // Not percent-encoded by us; take it as written.
    return encoded;
  }
}
