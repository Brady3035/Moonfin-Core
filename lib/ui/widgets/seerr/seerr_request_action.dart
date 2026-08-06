import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';

/// What the request control does for one quality track right now.
enum SeerrRequestActionKind { none, request, requested, cancel }

class SeerrRequestAction {
  final SeerrRequestActionKind kind;
  final String label;

  const SeerrRequestAction(this.kind, this.label);

  static const none = SeerrRequestAction(SeerrRequestActionKind.none, '');
}

/// Works out what the request control offers for one quality track.
///
/// Cancel wins over requested, which wins over request, so a viewer who can
/// take an open request back is always offered that rather than being told
/// something they already know. A partially available series can still be
/// requested, which is how the missing seasons get asked for.
SeerrRequestAction seerrRequestActionFor(
  SeerrQualityStatus q,
  SeerrMediaDetailViewModel vm,
  AppLocalizations l10n,
) {
  final allowed = q.is4k ? vm.canRequest4k : vm.canRequest;
  final canShowRequest = allowed &&
      !q.isFullyAvailable &&
      (!q.hasExistingRequest || q.isPartiallyAvailable);
  final hasOpenRequest = q.activeRequests.isNotEmpty && !q.isFullyAvailable;

  if (hasOpenRequest && q.cancelableRequests.isNotEmpty) {
    return SeerrRequestAction(
      SeerrRequestActionKind.cancel,
      q.is4k ? l10n.cancelRequest4k : l10n.cancelRequest,
    );
  }
  if (hasOpenRequest) {
    return SeerrRequestAction(
      SeerrRequestActionKind.requested,
      q.is4k ? l10n.requested4k : l10n.seerrRequestedStatus,
    );
  }
  if (canShowRequest) {
    return SeerrRequestAction(
      SeerrRequestActionKind.request,
      q.isPartiallyAvailable
          ? (q.is4k ? l10n.requestMore4k : l10n.requestMore)
          : (q.is4k ? l10n.request4k : l10n.request),
    );
  }
  return SeerrRequestAction.none;
}

/// The season numbers a series actually has.
///
/// A provider that splits a run differently, like TVDB for anime, reports its
/// own season numbers, so counting off from one would offer seasons that
/// aren't there and request the wrong ones. The count is only a fallback for a
/// server that sends no season list.
List<int> seerrSeasonNumbersOf(
  List<SeerrSeason> seasons,
  int fallbackCount,
) {
  final reported = seasons
      .where((s) => s.seasonNumber > 0)
      .map((s) => s.seasonNumber)
      .toList();
  if (reported.isNotEmpty) return reported;
  return List.generate(fallbackCount, (i) => i + 1);
}
