import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../navigation/destinations.dart';
import 'seerr_browse_chip.dart';

/// Seerr's genres, networks and keywords for a title, each leading into Seerr
/// browse filtered by it.
///
/// Kept apart from the library's own genres, which lead into library browse.
/// They look alike but land somewhere else, so folding them together would
/// break one of the two.
class SeerrItemChips extends StatelessWidget {
  final SeerrMediaDetailState state;

  const SeerrItemChips({super.key, required this.state});

  /// Whether there is anything to file this title under, so a caller can drop
  /// the heading and spacing around it too.
  static bool hasContent(SeerrMediaDetailState s) =>
      s.genres.isNotEmpty || s.networks.isNotEmpty || s.keywords.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final mediaType = state.isTv ? 'tv' : 'movie';

    void open(String id, String name, String filterType) => context.push(
          Destinations.seerrBrowseWith(
            filterId: id,
            filterName: name,
            mediaType: mediaType,
            filterType: filterType,
          ),
        );

    final rows = <Widget>[
      if (state.genres.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in state.genres)
              SeerrBrowseChip(
                label: g.name,
                onTap: () => open(g.id.toString(), g.name, 'genre'),
              ),
          ],
        ),
      if (state.networks.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final n in state.networks)
              SeerrBrowseChip(
                label: n.name,
                color: Colors.transparent,
                borderColor: Colors.white24,
                labelColor: Colors.white70,
                onTap: () => open(n.id.toString(), n.name, 'network'),
              ),
          ],
        ),
      if (state.keywords.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in state.keywords)
              SeerrBrowseChip(
                label: k.name,
                color: Colors.white.withValues(alpha: 0.05),
                labelColor: Colors.white60,
                dense: true,
                onTap: () => open(k.id.toString(), k.name, 'keyword'),
              ),
          ],
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }
}
