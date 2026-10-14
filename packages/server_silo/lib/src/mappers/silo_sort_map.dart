/// Moonfin's sort fields (Jellyfin `ItemSortBy`) and Silo's `sort` values.
///
/// Silo sorts by one term, `field` or `-field` for descending. The fields
/// its contract names are `title`, `year`, `release_date`, `added_at`,
/// `rating`, `runtime` and `random`; only those are mapped. A Moonfin field
/// with no Silo equivalent maps to nothing, and the request then leaves
/// `sort` out so Silo applies the list's saved or default order, rather than
/// risk an error for a field Silo doesn't know.
library;

/// Jellyfin sort field (lower-cased) → Silo sort field.
const Map<String, String> siloSortFields = {
  'sortname': 'title',
  'name': 'title',
  'seriessortname': 'title',
  'productionyear': 'year',
  'premieredate': 'release_date',
  'datecreated': 'added_at',
  // A series' "last episode added"; Silo dates a series by when it changed.
  'datelastcontentadded': 'added_at',
  'communityrating': 'rating',
  'runtime': 'runtime',
  'random': 'random',
};

/// Silo's `sort` value for Moonfin's [sortBy] and [sortOrder], or null to
/// leave `sort` out.
///
/// Moonfin sends a comma-separated list (`ProductionYear,SortName`), and
/// Silo takes one term, so only the **first** counts. When the first has no
/// Silo equivalent the answer is null rather than the next term: an episode
/// list asked for in `ParentIndexNumber,IndexNumber,SortName` order must
/// keep Silo's natural episode order, not be sorted by title. `Descending`
/// (the first of [sortOrder]'s terms) gives `-field`; `random` has no
/// direction.
String? siloSortFor({String? sortBy, String? sortOrder}) {
  final first = _firstTerm(sortBy);
  if (first == null) return null;
  final field = siloSortFields[first.toLowerCase()];
  if (field == null) return null;
  if (field == 'random') return field;
  final descending = _firstTerm(sortOrder)?.toLowerCase() == 'descending';
  return descending ? '-$field' : field;
}

/// Moonfin's sort field and order for Silo's [sort] value (`-added_at`), or
/// null for a field Moonfin has no name for. For showing the order Silo
/// applied (`effective_sort`) in Moonfin's sort menu.
({String sortBy, String sortOrder})? jellyfinSortForSilo(String? sort) {
  final term = sort?.trim();
  if (term == null || term.isEmpty) return null;
  final descending = term.startsWith('-');
  final field = descending ? term.substring(1) : term;
  final sortBy = _jellyfinNames[field.toLowerCase()];
  if (sortBy == null) return null;
  return (sortBy: sortBy, sortOrder: descending ? 'Descending' : 'Ascending');
}

const _jellyfinNames = {
  'title': 'SortName',
  'year': 'ProductionYear',
  'release_date': 'PremiereDate',
  'added_at': 'DateCreated',
  'rating': 'CommunityRating',
  'runtime': 'Runtime',
  'random': 'Random',
};

String? _firstTerm(String? list) {
  if (list == null) return null;
  for (final term in list.split(',')) {
    final t = term.trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}
