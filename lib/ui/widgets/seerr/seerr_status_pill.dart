import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';
import 'seerr_status_dot.dart';

/// One quality track worth showing a status for, and the label that
/// disambiguates it.
typedef SeerrStatusTrack = (SeerrQualityStatus track, String? label);

/// The tracks to show for a title. HD alone unless the 4K track has something
/// of its own to say, which is the usual case on servers without a 4K backend.
List<SeerrStatusTrack> seerrStatusTracks(
  SeerrMediaDetailState state,
  AppLocalizations l10n,
) {
  final uhd = state.uhd;
  if (!uhd.hasAnyState) return [(state.hd, null)];
  return [(state.hd, 'HD'), (uhd, l10n.uhd4k)];
}

String seerrStatusLabel(SeerrQualityStatus q, AppLocalizations l10n) {
  if (q.isFullyAvailable) return l10n.seerrAvailableStatus;
  if (q.isPartiallyAvailable) return l10n.partiallyAvailable;
  if (q.isProcessing) return l10n.seerrRequestedStatus;
  if (q.isPending) return l10n.pendingStatus;
  if (q.isBlacklisted) return l10n.blocklistedStatus;
  if (q.isDeleted) return l10n.deletedStatus;
  if (q.hasExistingRequest) return l10n.seerrRequestedStatus;
  return l10n.notRequestedStatus;
}

/// The Seerr status of one quality track, as a chip.
class SeerrStatusPill extends StatelessWidget {
  final SeerrQualityStatus track;

  /// Prefixed onto the label, so two tracks read as "HD Available" and
  /// "4K Requested" rather than twice the same word.
  final String? qualityLabel;

  /// The rounded, filled treatment the wide hero uses, instead of the bordered
  /// chip that sits inline with metadata.
  final bool solid;

  const SeerrStatusPill({
    super.key,
    required this.track,
    this.qualityLabel,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = seerrStatusLabel(track, AppLocalizations.of(context));
    final text = qualityLabel == null ? label : '$qualityLabel · $label';

    if (solid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: AppRadius.circular(999),
        ),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
    }

    final color = seerrStatusColor(_effectiveStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.fromBorderSide(
          ThemeRegistry.active.borders.chipBorder.copyWith(color: color),
        ),
        borderRadius: AppRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  /// A track with no media status of its own but an open request still reads as
  /// requested, matching what [seerrStatusLabel] says.
  int get _effectiveStatus {
    if (track.status > SeerrMediaStatus.unknown) return track.status;
    return track.hasExistingRequest
        ? SeerrMediaStatus.processing
        : SeerrMediaStatus.unknown;
  }
}
