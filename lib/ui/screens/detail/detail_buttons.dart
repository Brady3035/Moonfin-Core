import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/hidden_buttons.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';

/// The details screen action buttons a user can switch off. Play, Restart and
/// Play Offline are absent on purpose, the row always keeps them, and the
/// layout math relies on Play sitting at the start of the row.
///
/// Ids are what gets stored, so renaming one drops whatever the user had
/// switched off for it.
enum DetailButton {
  shuffle('shuffle'),
  audio('audio'),
  subtitles('subtitles'),
  version('version'),
  cast('cast'),
  trailer('trailer'),
  watchWithGroup('watchWithGroup'),
  watched('watched'),
  favorite('favorite'),
  playlist('playlist'),
  download('download'),
  deleteFiles('deleteFiles'),
  goToSeries('goToSeries'),
  admin('admin');

  const DetailButton(this.id);

  final String id;

  /// Whether this device can put the button on screen at all. A button that
  /// never gets drawn here isn't worth offering a switch for.
  bool get isOffered => switch (this) {
    DetailButton.cast ||
    DetailButton.download ||
    DetailButton.deleteFiles => !PlatformDetection.isTV,
    _ => true,
  };

  IconData get icon => switch (this) {
    DetailButton.shuffle => Icons.shuffle_rounded,
    DetailButton.audio => Icons.audiotrack,
    DetailButton.subtitles => Icons.subtitles,
    DetailButton.version => Icons.video_file,
    DetailButton.cast => Icons.cast,
    DetailButton.trailer => Icons.movie_outlined,
    DetailButton.watchWithGroup => Icons.groups_rounded,
    DetailButton.watched => Icons.check_circle_outline,
    DetailButton.favorite => Icons.favorite_border,
    DetailButton.playlist => Icons.playlist_add,
    DetailButton.download => Icons.download,
    DetailButton.deleteFiles => Icons.delete_outline,
    DetailButton.goToSeries => Icons.tv,
    DetailButton.admin => Icons.settings,
  };

  String label(AppLocalizations l10n) => switch (this) {
    DetailButton.shuffle => l10n.shuffle,
    DetailButton.audio => l10n.audio,
    DetailButton.subtitles => l10n.subtitles,
    DetailButton.version => l10n.version,
    DetailButton.cast => l10n.cast,
    DetailButton.trailer => l10n.trailer,
    DetailButton.watchWithGroup => l10n.watchWithGroup,
    DetailButton.watched => l10n.watched,
    DetailButton.favorite => l10n.favorite,
    DetailButton.playlist => l10n.playlist,
    DetailButton.download => l10n.download,
    DetailButton.deleteFiles => l10n.deleteFiles,
    DetailButton.goToSeries => l10n.goToSeries,
    DetailButton.admin => l10n.admin,
  };
}

final hiddenDetailButtons = HiddenButtons(
  tv: UserPreferences.hiddenDetailButtonsTv,
  mobile: UserPreferences.hiddenDetailButtonsMobile,
  desktop: UserPreferences.hiddenDetailButtonsDesktop,
);
