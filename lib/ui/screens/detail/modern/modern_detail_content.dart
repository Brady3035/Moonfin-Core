import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../data/viewmodels/item_detail_view_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../preference/user_preferences.dart';
import '../../../../util/platform_detection.dart';
import '../../../navigation/destinations.dart';
import '../../../widgets/logo_view.dart';
import '../../../widgets/media_card.dart';
import '../../../widgets/rating_display.dart';
import '../../../widgets/top_toolbar.dart';
import '../item_detail_screen.dart'
    show
        DetailActionButtons,
        DetailCastRow,
        DetailMetadataRow,
        DetailMetadataSection,
        DetailFeaturesRow,
        DetailEpisodeCard,
        DetailTrackList,
        selectedMediaSourceForItem;
import 'modern_landscape_layout.dart';
import 'modern_portrait_layout.dart';
import 'widgets/details_tab_bar.dart';
import 'widgets/season_card.dart';
import 'widgets/up_next_card.dart';

/// "Modern" detail-screen style: one responsive screen that chooses a landscape
/// (TV / desktop / any landscape device) or portrait (phone / tablet portrait)
/// layout. Selected globally via [UserPreferences.detailScreenStyle].
///
/// Mirrors the default content widget's constructor so the swap in
/// `_ItemDetailScreenState._buildBody` is a drop-in, and reuses the public
/// action/content widgets so playback and data logic are shared, not duplicated.
class ModernDetailContent extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final UserPreferences prefs;
  final String? backdropUrl;
  final String? selectedMediaSourceId;
  final ValueChanged<String?> onSelectedMediaSourceChanged;
  final FocusNode? initialFocusNode;
  final bool autoPlay;

  const ModernDetailContent({
    super.key,
    required this.viewModel,
    required this.prefs,
    this.backdropUrl,
    this.selectedMediaSourceId,
    required this.onSelectedMediaSourceChanged,
    this.initialFocusNode,
    this.autoPlay = false,
  });

  @override
  State<ModernDetailContent> createState() => _ModernDetailContentState();
}

class _ModernDetailContentState extends State<ModernDetailContent> {
  int _selectedTab = 0;
  bool _landscape = true;
  final Map<String, FocusNode> _trackFocusNodes = {};
  final List<FocusNode> _tabFocusNodes = [];
  final FocusNode _upNextFocusNode = FocusNode(debugLabel: 'modernUpNext');

  ItemDetailViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    for (final node in _trackFocusNodes.values) {
      node.dispose();
    }
    for (final node in _tabFocusNodes) {
      node.dispose();
    }
    _upNextFocusNode.dispose();
    super.dispose();
  }

  /// Right of the action buttons goes to the Up Next card when it's present,
  /// otherwise into the tab rail.
  void _focusRightOfActions() {
    if (_upNextFocusNode.context != null) {
      _upNextFocusNode.requestFocus();
    } else {
      _focusSelectedTab();
    }
  }

  FocusNode _tabNode(int index) {
    while (_tabFocusNodes.length <= index) {
      _tabFocusNodes.add(FocusNode());
    }
    return _tabFocusNodes[index];
  }

  void _focusSelectedTab() => _tabNode(_selectedTab).requestFocus();

  bool _isAudioItem(AggregatedItem item) {
    final mediaType = item.rawData['MediaType'] as String?;
    return item.type == 'Audio' ||
        item.type == 'AudioBook' ||
        mediaType == 'Audio';
  }

  bool _isAudiobook(AggregatedItem item) =>
      item.type == 'AudioBook' ||
      (item.type == 'Book' && item.rawData['MediaType'] == 'Audio');

  List<_ModernTab> _tabsFor(AggregatedItem item, AppLocalizations l10n) {
    final hasCast = _vm.actors.isNotEmpty;
    final hasSimilar = _vm.similar.isNotEmpty;
    final hasFeatures = _vm.features.isNotEmpty;
    final cast = _ModernTab(l10n.cast, _castTab);
    final details = _ModernTab(l10n.details, _detailsTab);
    final similar = _ModernTab(l10n.similar, (_, _) => _itemGrid(_vm.similar));

    switch (item.type) {
      case 'Series':
        return [
          if (_vm.seasons.isNotEmpty) _ModernTab(l10n.seasons, _seasonsTab),
          _ModernTab(l10n.episodes, _seriesEpisodesTab),
          if (hasCast) cast,
          details,
          if (hasSimilar) similar,
        ];
      case 'Season':
        return [
          if (_vm.episodes.isNotEmpty)
            _ModernTab(l10n.episodes, _episodeListTab),
          if (hasCast) cast,
          details,
        ];
      case 'Episode':
        return [
          if (_vm.episodes.isNotEmpty)
            _ModernTab(l10n.episodes, _episodeListTab),
          if (hasCast) cast,
          details,
          if (hasSimilar) similar,
        ];
      case 'MusicAlbum':
      case 'Playlist':
      case 'AudioBook':
        return [
          if (_vm.tracks.isNotEmpty) _ModernTab(l10n.trackList, _tracksTab),
          details,
          if (hasSimilar) similar,
        ];
      case 'MusicArtist':
        return [
          if (_vm.albums.isNotEmpty)
            _ModernTab(l10n.albums, (_, _) => _itemGrid(_vm.albums)),
          details,
          if (hasSimilar) similar,
        ];
      case 'Person':
        return [
          if (_vm.filmography.isNotEmpty)
            _ModernTab(l10n.appearances, (_, _) => _itemGrid(_vm.filmography)),
          details,
        ];
      case 'BoxSet':
        return [
          if (_vm.collectionItems.isNotEmpty)
            _ModernTab(l10n.items, (_, _) => _itemGrid(_vm.collectionItems)),
          if (hasCast) cast,
          details,
        ];
      default:
        return [
          if (hasCast) cast,
          details,
          if (hasFeatures) _ModernTab(l10n.extras, _extrasTab),
          if (hasSimilar) similar,
        ];
    }
  }

  Widget _seasonsTab(BuildContext context, AggregatedItem item) {
    final l10n = AppLocalizations.of(context);
    final counts = _episodeCountsBySeason();
    final cards = [
      for (final season in _vm.seasons)
        SeasonCard(
          title: season.name,
          subtitle: l10n.episodeCount(
            counts[season.id] ?? season.childCount ?? 0,
          ),
          imageUrl: _imageUrl(season),
          landscape: _landscape,
          onTap: () => context.push(
            Destinations.item(season.id, serverId: season.serverId),
          ),
        ),
    ];
    if (_landscape) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: card,
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: card,
          ),
      ],
    );
  }

  Widget _episodeListTab(BuildContext context, AggregatedItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final episode in _vm.episodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DetailEpisodeCard(
              episode: episode,
              imageApi: _vm.imageApi,
              onChanged: () => _vm.load(),
            ),
          ),
      ],
    );
  }

  Map<String, int> _episodeCountsBySeason() {
    final counts = <String, int>{};
    for (final e in _vm.seriesEpisodes) {
      final id = e.seasonId;
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// All episodes of a Series in one sequential list with a "Season N" header
  /// before each season group.
  Widget _seriesEpisodesTab(BuildContext context, AggregatedItem item) {
    final l10n = AppLocalizations.of(context);
    final episodes = _vm.seriesEpisodes;
    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final sorted = [...episodes]..sort((a, b) {
        final sa = a.parentIndexNumber ?? 0;
        final sb = b.parentIndexNumber ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        return (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
      });
    final children = <Widget>[];
    int? previousSeason;
    for (final episode in sorted) {
      final season = episode.parentIndexNumber;
      if (season != previousSeason) {
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(0, children.isEmpty ? 0 : 20, 0, 10),
            child: Text(
              l10n.seasonNumber(season ?? 0),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        );
        previousSeason = season;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DetailEpisodeCard(
            episode: episode,
            imageApi: _vm.imageApi,
            onChanged: () => _vm.load(),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _castTab(BuildContext context, AggregatedItem item) => SizedBox(
        height: 200,
        child: DetailCastRow(
          people: _vm.actors,
          imageApi: _vm.imageApi,
          serverId: item.serverId,
        ),
      );

  Widget _extrasTab(BuildContext context, AggregatedItem item) => SizedBox(
        height: 200,
        child: DetailFeaturesRow(
          items: _vm.features,
          imageApi: _vm.imageApi,
          prefs: widget.prefs,
        ),
      );

  Widget _detailsTab(BuildContext context, AggregatedItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailMetadataRow(
          item: item,
          selectedMediaSource:
              selectedMediaSourceForItem(item, widget.selectedMediaSourceId),
          technicalOnly: true,
        ),
        const SizedBox(height: 20),
        DetailMetadataSection(viewModel: _vm),
      ],
    );
  }

  Widget _itemGrid(List<AggregatedItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const desiredWidth = 150.0;
        final crossAxisCount =
            ((constraints.maxWidth + spacing) / (desiredWidth + spacing))
                .floor()
                .clamp(2, 8);
        final cellWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
                crossAxisCount;
        const cardRatio = 2 / 3;
        const textHeight = 44.0;
        final childAspectRatio =
            cellWidth / (cellWidth / cardRatio + textHeight);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, i) {
            final entry = items[i];
            return MediaCard(
              title: entry.name,
              imageUrl: _imageUrl(entry),
              width: double.infinity,
              aspectRatio: cardRatio,
              isPlayed: entry.isPlayed,
              isFavorite: entry.isFavorite,
              itemType: entry.type,
              watchedBehavior:
                  widget.prefs.get(UserPreferences.watchedIndicatorBehavior),
              onTap: () => context.push(
                Destinations.item(entry.id, serverId: entry.serverId),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tracksTab(BuildContext context, AggregatedItem item) {
    return DetailTrackList(
      tracks: _vm.tracks,
      imageApi: _vm.imageApi,
      isAudiobook: _isAudiobook(item),
      isPlaylist: item.type == 'Playlist',
      groupByDisc: item.type == 'MusicAlbum',
      getFocusNode: (id) =>
          _trackFocusNodes.putIfAbsent(id, () => FocusNode()),
      onPlayTrack: (index) => _playTrack(context, index),
    );
  }

  Future<void> _playTrack(BuildContext context, int index) async {
    final manager = GetIt.instance<PlaybackManager>();
    await manager.playItems(_vm.tracks, startIndex: index);
    if (!context.mounted) return;
    final isAudio = _vm.tracks.every(_isAudioItem);
    context.push(isAudio ? Destinations.audioPlayer : Destinations.videoPlayer);
  }

  /// In landscape the hero column is ~45% of the width. Size the visible action
  /// count so the Play pill, the circular buttons and the "More" toggle all stay
  /// on a single row (extras expand to a second row beneath). Reserves room for
  /// the Play pill (wider for "Resume from S#:E#" labels) plus More (~62); each
  /// circular button is ~62 wide.
  int? _actionButtonCap(BuildContext context, AggregatedItem item) {
    if (!_landscape) return null;
    final heroWidth =
        (MediaQuery.sizeOf(context).width * 0.45).clamp(360.0, 620.0);
    final pillWidth = switch (item.type) {
      'Series' || 'Season' || 'Episode' => 300.0,
      'MusicAlbum' || 'Playlist' || 'AudioBook' || 'MusicArtist' => 160.0,
      _ => 220.0,
    };
    final circles = ((heroWidth - pillWidth - 62) / 62).floor();
    return (circles + 2).clamp(2, 8);
  }

  Widget _buildHero(BuildContext context, AggregatedItem item) {
    final textTheme = Theme.of(context).textTheme;
    final isEpisode = item.type == 'Episode';
    final logoTag = item.logoImageTag;
    final overview = item.overview?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEpisode && item.seriesName != null)
          Text(
            item.seriesName!,
            style: textTheme.labelLarge?.copyWith(
              color: AppColorScheme.onSurface.withValues(alpha: 0.7),
              letterSpacing: 1.2,
            ),
          ),
        if (!isEpisode && logoTag != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: LogoView(
              imageUrl: _vm.imageApi
                  .getLogoImageUrl(item.id, maxWidth: 350, tag: logoTag),
              maxHeight: _landscape ? 90 : 64,
              maxWidth: _landscape ? 360 : 260,
            ),
          )
        else
          Text(
            item.name,
            style: (_landscape
                    ? textTheme.displaySmall
                    : textTheme.headlineMedium)
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 12),
        _metadataRow(context, item),
        const SizedBox(height: 12),
        RatingsRow(
          ratings: _vm.ratings,
          communityRating: item.communityRating,
          criticRating: item.criticRating,
          enableAdditionalRatings:
              widget.prefs.get(UserPreferences.enableAdditionalRatings),
          enabledRatings: widget.prefs.get(UserPreferences.enabledRatings),
        ),
        if (item.tagline != null && item.tagline!.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            item.tagline!.trim(),
            style: textTheme.titleSmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: AppColorScheme.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ],
        if (overview != null && overview.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            overview,
            maxLines: _landscape ? 4 : 6,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              height: 1.45,
              color: AppColorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
        const SizedBox(height: 18),
        DetailActionButtons(
          viewModel: _vm,
          itemId: item.id,
          selectedMediaSourceId: widget.selectedMediaSourceId,
          onSelectedMediaSourceChanged: widget.onSelectedMediaSourceChanged,
          tvPlayFocusNode: widget.initialFocusNode,
          autoPlay: widget.autoPlay,
          modernStyle: true,
          fullWidthPrimary: !_landscape,
          maxVisibleButtonsOverride: _actionButtonCap(context, item),
          onArrowRightAtEnd: _landscape ? _focusRightOfActions : null,
        ),
      ],
    );
  }

  Widget _metadataRow(BuildContext context, AggregatedItem item) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final muted = AppColorScheme.onSurface.withValues(alpha: 0.75);
    final style = textTheme.bodyMedium?.copyWith(color: muted);

    final pieces = <Widget>[];
    void addText(String? value) {
      if (value == null || value.isEmpty) return;
      pieces.add(Text(value, style: style));
    }

    addText(item.productionYear?.toString());
    addText(item.officialRating);
    if (item.type == 'Series' && item.childCount != null) {
      addText(l10n.seasonCount(item.childCount!));
    }
    final status = item.status;
    if (item.type == 'Series' && status != null && status.isNotEmpty) {
      pieces.add(_statusBadge(context, status));
    }
    final runtime = item.runtime;
    if (runtime != null && item.type != 'Series') {
      pieces.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: muted),
            const SizedBox(width: 4),
            Text(_formatDuration(runtime), style: style),
          ],
        ),
      );
      final position = item.playbackPosition ?? Duration.zero;
      var remaining = runtime - position;
      if (remaining.isNegative || remaining == Duration.zero) {
        remaining = runtime;
      }
      final end = DateTime.now().add(remaining);
      addText(l10n.endsAt(TimeOfDay.fromDateTime(end).format(context)));
    }
    if (item.genres.isNotEmpty) {
      addText(item.genres.take(3).join(' · '));
    }
    if (pieces.isEmpty) return const SizedBox.shrink();

    final separated = <Widget>[];
    for (var i = 0; i < pieces.length; i++) {
      if (i > 0) {
        separated.add(Text('·', style: style));
      }
      separated.add(pieces[i]);
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: separated,
    );
  }

  Widget _statusBadge(BuildContext context, String status) {
    final isEnded = status.toLowerCase() == 'ended';
    final color = isEnded
        ? Theme.of(context).colorScheme.error
        : AppColorScheme.statusAvailable;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: JellyfinTokens.shapes.smallRadius,
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget? _buildUpNext(BuildContext context, AggregatedItem item) {
    const supported = {'Series', 'Season', 'Episode'};
    if (!supported.contains(item.type)) return null;
    final episode = _vm.nextUp;
    if (episode == null) return null;
    final l10n = AppLocalizations.of(context);
    final s = episode.parentIndexNumber;
    final e = episode.indexNumber;
    final code = (s != null && e != null) ? 'S$s:E$e' : null;
    final title = code != null ? '$code - ${episode.name}' : episode.name;
    final progress = (episode.playedPercentage ?? 0) / 100.0;
    return UpNextCard(
      label: l10n.nextUp,
      title: title,
      description: episode.overview?.trim(),
      imageUrl: _imageUrl(episode),
      progress: progress,
      remainingLabel: _remainingLabel(episode, l10n),
      focusNode: _upNextFocusNode,
      onNavigateLeft: () => widget.initialFocusNode?.requestFocus(),
      onNavigateDown: _focusSelectedTab,
      onTap: () => context.push(
        Destinations.item(episode.id, serverId: episode.serverId),
      ),
    );
  }

  String? _remainingLabel(AggregatedItem episode, AppLocalizations l10n) {
    final runtime = episode.runtime;
    if (runtime == null || runtime.inSeconds <= 0) return null;
    final position = episode.playbackPosition ?? Duration.zero;
    final remaining = runtime - position;
    if (remaining.inMinutes <= 0) return null;
    return l10n.timeRemaining(_formatDuration(remaining));
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    return '${m}m';
  }

  /// Full-bleed cinematic backdrop owned by the Modern screen (deliberately
  /// ignores the global backdrop-hide / blur prefs; no blur). In landscape the
  /// image is right-aligned and embedded into the page with layered scrims: a
  /// strong left-to-right gradient keeping the left content readable, a
  /// bottom-to-top gradient blending the lower UI into the background, and a
  /// subtle edge vignette. In portrait it fades from the top into the content.
  Widget _buildBackdrop(bool landscape) {
    final base = AppColorScheme.background;
    final url = widget.backdropUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        if (url != null && url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            alignment:
                landscape ? Alignment.centerRight : Alignment.topCenter,
            fadeInDuration: const Duration(milliseconds: 250),
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
        if (landscape) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  base,
                  base.withValues(alpha: 0.55),
                  base.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.34, 0.62],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  base,
                  base.withValues(alpha: 0.55),
                  base.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.35, 0.68],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.05,
                colors: [
                  base.withValues(alpha: 0.0),
                  base.withValues(alpha: 0.0),
                  base.withValues(alpha: 0.32),
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
            ),
          ),
        ] else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  base.withValues(alpha: 0.15),
                  base.withValues(alpha: 0.55),
                  base,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
      ],
    );
  }

  String? _imageUrl(AggregatedItem item) {
    final tag = item.primaryImageTag;
    if (tag == null) return null;
    return _vm.imageApi.getPrimaryImageUrl(item.id, maxHeight: 360, tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    final item = _vm.item;
    if (item == null) return const SizedBox.shrink();

    if (item.type == 'Series') {
      _vm.loadAllSeriesEpisodes();
    }

    final l10n = AppLocalizations.of(context);
    _landscape = PlatformDetection.isTV ||
        PlatformDetection.useDesktopUi ||
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final tabs = _tabsFor(item, l10n);
    if (_selectedTab >= tabs.length) _selectedTab = 0;
    final tabContent = tabs.isEmpty
        ? const SizedBox.shrink()
        : tabs[_selectedTab].builder(context, item);

    final tabBar = DetailsTabBar(
      labels: [for (final t in tabs) t.label],
      selectedIndex: _selectedTab,
      onSelect: (i) => setState(() => _selectedTab = i),
      focusNodeFor: _tabNode,
      onExitLeft: () => widget.initialFocusNode?.requestFocus(),
    );

    final hero = _buildHero(context, item);
    final upNext = _buildUpNext(context, item);
    final backdrop = _buildBackdrop(_landscape);
    final topInset = TopToolbar.heightFor(context);

    return _landscape
        ? ModernLandscapeLayout(
            backdrop: backdrop,
            hero: hero,
            upNext: upNext,
            tabBar: tabBar,
            tabContent: tabContent,
            topInset: topInset,
          )
        : ModernPortraitLayout(
            backdrop: backdrop,
            hero: hero,
            upNext: upNext,
            tabBar: tabBar,
            tabContent: tabContent,
            topInset: topInset,
          );
  }
}

class _ModernTab {
  final String label;
  final Widget Function(BuildContext, AggregatedItem) builder;
  const _ModernTab(this.label, this.builder);
}
