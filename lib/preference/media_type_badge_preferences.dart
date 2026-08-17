import 'package:jellyfin_preference/jellyfin_preference.dart';

/// Controls when MOVIE / SERIES media-type badges appear on home-row cards.
enum MediaTypeBadgeBehavior { always, mixedRowsOnly, never }

class MediaTypeBadgePreferences {
  static final behavior = EnumPreference(
    key: 'pref_media_type_badge_behavior',
    defaultValue: MediaTypeBadgeBehavior.always,
    values: MediaTypeBadgeBehavior.values,
  );
}
