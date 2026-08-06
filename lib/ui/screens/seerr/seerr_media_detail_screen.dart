import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/services/seerr/seerr_error.dart';
import '../../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/seerr_preferences.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/library_row.dart';
import '../../widgets/seerr/seerr_action_tile.dart';
import '../../widgets/seerr/seerr_approve_decline_buttons.dart';
import '../../widgets/seerr/seerr_cancel_request_dialog.dart';
import '../../widgets/seerr/seerr_cast_card.dart';
import '../../widgets/seerr/seerr_collection_banner.dart';
import '../../widgets/seerr/seerr_item_chips.dart';
import '../../widgets/seerr/seerr_image_urls.dart';
import '../../widgets/seerr/seerr_report_issue_dialog.dart';
import '../../widgets/seerr/seerr_request_action.dart';
import '../../widgets/seerr/seerr_request_dialog.dart';
import '../../widgets/seerr/seerr_stats_card.dart';
import '../../widgets/seerr/seerr_status_pill.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/seerr_download_progress_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/focus/request_initial_focus.dart';

class SeerrMediaDetailScreen extends StatefulWidget {
  final String itemId;
  final String? mediaType;
  // Only used to resolve an IMDb-keyed id by searching for it.
  final String? title;

  const SeerrMediaDetailScreen({
    super.key,
    required this.itemId,
    this.mediaType,
    this.title,
  });

  @override
  State<SeerrMediaDetailScreen> createState() => _SeerrMediaDetailScreenState();
}

class _SeerrMediaDetailScreenState extends State<SeerrMediaDetailScreen> {
  SeerrMediaDetailViewModel? _vm;
  bool _initializing = true;
  final _userPrefs = GetIt.instance<UserPreferences>();
  final FocusNode _firstActionFocusNode = FocusNode(
    debugLabel: 'seerr-first-action',
  );
  final FocusNode _overviewFocusNode = FocusNode(debugLabel: 'seerr-overview');
  final FocusNode _titleFocusNode = FocusNode(debugLabel: 'seerr-title-hidden');
  final ScrollController _wideScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final repo = await GetIt.instance.getAsync<SeerrRepository>();
    final prefs = GetIt.instance<SeerrPreferences>();
    final vm = SeerrMediaDetailViewModel(repo, prefs);
    vm.addListener(_onChanged);

    if (!mounted) {
      vm.dispose();
      return;
    }

    setState(() {
      _vm = vm;
      _initializing = false;
    });

    _loadDetails();
  }

  void _showFeedback(SeerrMediaDetailState s) {
    if (s.requestSuccess != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.requestSuccess!),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
      _vm?.clearFeedback();
    } else if (s.requestError != null) {
      final l10n = AppLocalizations.of(context);
      final message = switch (s.requestErrorKind) {
        SeerrRequestErrorKind.duplicate => l10n.requestErrorDuplicate,
        SeerrRequestErrorKind.quotaExceeded => l10n.requestErrorQuota,
        SeerrRequestErrorKind.blocklisted => l10n.requestErrorBlocklisted,
        SeerrRequestErrorKind.noSeasonsAvailable => l10n.requestErrorNoSeasons,
        SeerrRequestErrorKind.permission => l10n.requestErrorPermission,
        _ => s.requestError!,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
      _vm?.clearFeedback();
    } else if (s.watchlistError != null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.watchlistUpdateFailed),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
      _vm?.clearFeedback();
    }
  }

  void _loadDetails() {
    final vm = _vm;
    if (vm == null) return;
    vm.load(widget.itemId, widget.mediaType ?? 'movie', title: widget.title);
  }

  @override
  void dispose() {
    _vm?.removeListener(_onChanged);
    _vm?.dispose();
    _firstActionFocusNode.dispose();
    _overviewFocusNode.dispose();
    _titleFocusNode.dispose();
    _wideScrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final s = _vm?.state;
    if (s != null) _showFeedback(s);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        !_initializing &&
        _vm != null &&
        !_vm!.state.isLoading &&
        _vm!.state.error == null;
    return RequestInitialFocus(
      targetNode: (PlatformDetection.isTV && ready) ? _overviewFocusNode : null,
      child: _buildScreenContent(context),
    );
  }

  Widget _buildScreenContent(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: NavigationLayout(showBackButton: true, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    final vm = _vm;
    if (_initializing || vm == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final s = vm.state;

    if (s.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (s.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadDetails, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    return _buildContent(s);
  }

  Widget _buildContent(SeerrMediaDetailState s) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final useWideLayout =
        PlatformDetection.useDesktopUi ||
        PlatformDetection.isTV ||
        (PlatformDetection.useMobileUi && isLandscape);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (s.backdropPath != null)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: '$seerrBackdropBase${s.backdropPath}',
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: useWideLayout ? 0.35 : 0.7),
                  Colors.black.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.6],
              ),
            ),
          ),
        ),
        if (useWideLayout)
          _buildWideScroll(s, l10n)
        else
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(s)),
              SliverToBoxAdapter(child: _buildMetadata(s)),
              SliverToBoxAdapter(child: _buildRequestSection(s)),
              if (s.overview != null && s.overview!.isNotEmpty)
                SliverToBoxAdapter(child: _buildOverview(s.overview!)),
              if (s.credits != null && s.credits!.cast.isNotEmpty)
                SliverToBoxAdapter(child: _buildCastRow(s.credits!.cast, l10n)),
              if (s.similar.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildRelatedRow(l10n.similar, s.similar),
                ),
              if (s.recommendations.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildRelatedRow(
                    l10n.recommendations,
                    s.recommendations,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
      ],
    );
  }

  Widget _buildWideScroll(SeerrMediaDetailState s, AppLocalizations l10n) {
    final size = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final navbarIsTop =
        _userPrefs.get(UserPreferences.navbarPosition) == NavbarPosition.top;
    final navbarHeight = navbarIsTop
        ? (PlatformDetection.isTV
              ? 95.0
              : PlatformDetection.useMobileUi
              ? 60.0
              : 80.0)
        : 0.0;
    final hSidePad = PlatformDetection.isTV
        ? 56.0
        : PlatformDetection.useDesktopUi
        ? 64.0
        : 32.0;
    final heroHeight = (size.height * 0.62).clamp(360.0, 720.0);
    return CustomScrollView(
      controller: _wideScrollController,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroHeight,
            child: _buildWideHero(s, hSidePad, topPad + navbarHeight),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hSidePad, 24, hSidePad, 12),
            child: _buildWideOverviewAndStats(s, l10n),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hSidePad, 8, hSidePad, 16),
            child: _buildWideActions(s, l10n),
          ),
        ),
        if (s.credits != null && s.credits!.cast.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hSidePad),
              child: _buildCastRow(s.credits!.cast, l10n),
            ),
          ),
        if (s.similar.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hSidePad),
              child: _buildRelatedRow(l10n.similar, s.similar),
            ),
          ),
        if (s.recommendations.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hSidePad),
              child: _buildRelatedRow(l10n.recommendations, s.recommendations),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 60)),
      ],
    );
  }

  Widget _buildWideHero(
    SeerrMediaDetailState s,
    double hSidePad,
    double topInset,
  ) {
    final theme = Theme.of(context);
    final posterWidth = PlatformDetection.useDesktopUi ? 240.0 : 220.0;
    final posterHeight = posterWidth * 1.5;
    return Padding(
      padding: EdgeInsets.fromLTRB(hSidePad, topInset + 8, hSidePad, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (s.posterPath != null)
            ClipRRect(
              borderRadius: AppRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: '$seerrPosterBase${s.posterPath}',
                width: posterWidth,
                height: posterHeight,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  width: posterWidth,
                  height: posterHeight,
                  color: Colors.white12,
                ),
              ),
            ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SeerrStatusPills(state: s, solid: true),
                const SizedBox(height: 10),
                Focus(
                  focusNode: _titleFocusNode,
                  onFocusChange: (focused) {
                    if (focused) _scrollToTop();
                  },
                  onKeyEvent: _handleNavbarUpKey,
                  child: Text(
                    _titleWithYear(s),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _wideMetaLine(s),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (s.tagline != null && s.tagline!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '"${s.tagline!}"',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideOverviewAndStats(
    SeerrMediaDetailState s,
    AppLocalizations l10n,
  ) {
    final overviewText = (s.overview != null && s.overview!.isNotEmpty)
        ? Text(
            s.overview!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.5,
            ),
          )
        : null;
    final overviewCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.overview,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (overviewText != null)
          PlatformDetection.isTV
              ? Focus(
                  focusNode: _overviewFocusNode,
                  onFocusChange: (focused) {
                    if (focused) _scrollToTop();
                  },
                  onKeyEvent: _handleNavbarUpKey,
                  child: Builder(
                    builder: (ctx) {
                      final focused = Focus.of(ctx).hasFocus;
                      final focusColor = Color(
                        GetIt.instance<UserPreferences>()
                            .get(UserPreferences.focusColor)
                            .colorValue,
                      );
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.circular(8),
                          border: Border.fromBorderSide(
                            ThemeRegistry.active.borders.focusBorder.copyWith(
                              color: focused ? focusColor : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: overviewText,
                      );
                    },
                  ),
                )
              : overviewText,
        if (SeerrItemChips.hasContent(s)) ...[
          const SizedBox(height: 16),
          SeerrItemChips(state: s),
        ],
      ],
    );
    final stats = SeerrStatsCard(state: s);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [overviewCol, const SizedBox(height: 16), stats],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: overviewCol),
            const SizedBox(width: 32),
            Expanded(flex: 2, child: stats),
          ],
        );
      },
    );
  }

  Widget _buildWideActions(SeerrMediaDetailState s, AppLocalizations l10n) {
    final vm = _vm!;
    final hd = s.hd;
    final uhd = s.uhd;
    final hdAction = seerrRequestActionFor(hd, vm, l10n);
    final uhdAction = seerrRequestActionFor(uhd, vm, l10n);
    final canManage = vm.canManageRequests;
    final trailer = s.bestTrailer;
    final showTrailer = trailer != null;

    final tiles = <Widget>[];
    FocusNode? nextFirstNode = _firstActionFocusNode;
    FocusNode? takeFirst() {
      final n = nextFirstNode;
      nextFirstNode = null;
      return n;
    }

    void addActionTile(SeerrRequestAction action, {required bool is4k, required bool primary}) {
      switch (action.kind) {
        case SeerrRequestActionKind.none:
          break;
        case SeerrRequestActionKind.cancel:
          tiles.add(
            SeerrActionTile(
              icon: Icons.close,
              label: action.label,
              onTap: s.isRequesting
                  ? null
                  : () => showSeerrCancelRequestDialog(
                      context: context,
                      vm: vm,
                      is4k: is4k,
                    ),
              primary: primary,
              focusNode: takeFirst(),
            ),
          );
        case SeerrRequestActionKind.requested:
          // No focus node on purpose. _requestFirstActionFocus gives up when
          // the first action can't take focus, so a disabled tile must never
          // claim that slot.
          tiles.add(
            SeerrActionTile(
              icon: Icons.check,
              label: action.label,
              onTap: null,
              primary: false,
              focusNode: null,
            ),
          );
        case SeerrRequestActionKind.request:
          tiles.add(
            SeerrActionTile(
              icon: Icons.add,
              label: action.label,
              onTap: s.isRequesting ? null : () => showSeerrRequestDialog(context: context, vm: vm, is4k: is4k),
              primary: primary,
              focusNode: takeFirst(),
            ),
          );
      }
    }

    addActionTile(hdAction, is4k: false, primary: !hd.isAvailable);
    // Play takes the primary styling only when HD emitted no tile. Captured
    // before the 4K tile, which is never primary, so two tiles never compete
    // for it.
    final playIsPrimary = tiles.isEmpty;
    addActionTile(uhdAction, is4k: true, primary: false);
    if (s.isAvailableAnyQuality) {
      tiles.add(
        SeerrActionTile(
          icon: Icons.play_arrow,
          label: l10n.playInMoonfin,
          onTap: () => _playInMoonfin(s),
          primary: playIsPrimary,
          focusNode: takeFirst(),
        ),
      );
    }
    if (showTrailer) {
      tiles.add(
        SeerrActionTile(
          icon: Icons.movie_outlined,
          label: l10n.trailer,
          onTap: () => _openTrailer(trailer),
          focusNode: takeFirst(),
        ),
      );
    }
    if (vm.canReportIssue) {
      tiles.add(
        SeerrActionTile(
          icon: Icons.report_problem_outlined,
          label: l10n.reportIssue,
          onTap: s.isRequesting ? null : () => showSeerrReportIssueDialog(context: context, vm: vm),
          focusNode: takeFirst(),
        ),
      );
    }
    tiles.add(SeerrActionTile(
      icon: s.onUserWatchlist ? Icons.bookmark : Icons.bookmark_border,
      label: s.onUserWatchlist ? l10n.removeFromWatchlist : l10n.addToWatchlist,
      onTap: s.isTogglingWatchlist ? null : () => vm.toggleWatchlist(),
      focusNode: takeFirst(),
    ));

    final activeRequests = s.allActiveRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeRequests.isNotEmpty) ...[
          for (final req in activeRequests)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      seerrRequestedByLabel(req, l10n),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canManage &&
                      req.status == SeerrRequest.statusPending) ...[
                    const SizedBox(width: 8),
                    SeerrApproveDeclineButtons(
                      isLoading: s.isRequesting,
                      onApprove: () => vm.approveRequest(req.id),
                      onDecline: () => vm.declineRequest(req.id),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (tiles.isNotEmpty)
          Wrap(spacing: 16, runSpacing: 16, children: tiles),
        if (s.movie?.collection != null) ...[
          const SizedBox(height: 20),
          SeerrCollectionBanner(collection: s.movie!.collection!),
        ],
      ],
    );
  }

  KeyEventResult _handleNavbarUpKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final navbarPos = _userPrefs.get(UserPreferences.navbarPosition);
      if (navbarPos == NavbarPosition.top) {
        NavigationLayout.focusNavbarNotifier.value?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (identical(node, _titleFocusNode) && _requestFirstActionFocus()) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _requestFirstActionFocus() {
    if (!_firstActionFocusNode.canRequestFocus) return false;
    if (_firstActionFocusNode.context == null) return false;
    _firstActionFocusNode.requestFocus();
    return true;
  }

  void _scrollToTop() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_wideScrollController.hasClients) return;
      final position = _wideScrollController.position;
      if (position.pixels <= position.minScrollExtent) return;
      position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _titleWithYear(SeerrMediaDetailState s) {
    final year = _extractYear(s);
    if (year == null) return s.displayTitle;
    return '${s.displayTitle} ($year)';
  }

  String _wideMetaLine(SeerrMediaDetailState s) {
    final parts = <String>[];
    if (s.runtime != null && s.runtime! > 0) {
      parts.add('${s.runtime} min');
    }
    if (s.genres.isNotEmpty) {
      parts.addAll(s.genres.take(3).map((g) => g.name));
    } else if (s.isTv && s.tvStatus != null) {
      parts.add(s.tvStatus!);
    }
    return parts.join(' \u2022 ');
  }

  Future<void> _openTrailer(SeerrVideo video) async {
    final isYouTube = (video.site ?? '').toLowerCase() == 'youtube';
    final key = video.key;
    if (isYouTube && key != null && key.isNotEmpty) {
      await context.push(Destinations.trailer(videoId: key));
      return;
    }
    String? url = video.url;
    if ((url == null || url.isEmpty) && key != null && key.isNotEmpty) {
      url = 'https://www.youtube.com/watch?v=$key';
    }
    if (url == null || url.isEmpty) return;
    await context.push(Destinations.trailer(url: url));
  }

  Widget _buildHeader(SeerrMediaDetailState s) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.of(context).padding.top;
    final navbarIsTop =
        _userPrefs.get(UserPreferences.navbarPosition) == NavbarPosition.top;
    final navbarHeight = navbarIsTop
        ? (PlatformDetection.isTV
              ? 95.0
              : PlatformDetection.useMobileUi
              ? 60.0
              : 80.0)
        : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(32, topPad + navbarHeight + 16, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.posterPath != null)
            Center(
              child: ClipRRect(
                borderRadius: AppRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: '$seerrPosterBase${s.posterPath}',
                  width: 180,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const SizedBox(width: 180, height: 270),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            s.displayTitle,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (s.tagline != null && s.tagline!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              s.tagline!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white60,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          SeerrStatusPills(state: s),
          if (s.hdDownload != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 280,
              child: SeerrDownloadProgressBar(
                summary: s.hdDownload!,
                prefixLabel: s.download4k != null ? 'HD' : null,
              ),
            ),
          ],
          if (s.download4k != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 280,
              child: SeerrDownloadProgressBar(
                summary: s.download4k!,
                prefixLabel: '4K',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadata(SeerrMediaDetailState s) {
    final l10n = AppLocalizations.of(context);
    final chips = <Widget>[];

    final year = _extractYear(s);
    if (year != null) chips.add(_metaText(year));

    if (s.runtime != null && s.runtime! > 0) {
      chips.add(_metaText(seerrFormatRuntime(s.runtime!)));
    }

    if (s.voteAverage != null && s.voteAverage! > 0) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 16, color: Color(0xFFFFC107)),
            const SizedBox(width: 2),
            Text(
              s.voteAverage!.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (s.isTv) {
      if (s.numberOfSeasons != null) {
        final label = s.numberOfSeasons == 1 ? l10n.season : l10n.seasons;
        chips.add(_metaText(l10n.seasonsCount(s.numberOfSeasons!, label)));
      }
      if (s.tvStatus != null) {
        chips.add(_tvStatusBadge(s.tvStatus!));
      }
    }

    if (s.budget != null && s.budget! > 0) {
      chips.add(_metaText(l10n.budgetAmount(seerrFormatMoneyShort(s.budget!))));
    }
    if (s.revenue != null && s.revenue! > 0) {
      chips.add(_metaText(l10n.revenueAmount(seerrFormatMoneyShort(s.revenue!))));
    }

    final mediaType = s.isTv ? 'tv' : 'movie';

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: chips),
          if (s.genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: s.genres
                  .map(
                    (g) => ActionChip(
                      label: Text(g.name, style: const TextStyle(fontSize: 12)),
                      backgroundColor: Colors.white12,
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => context.push(
                        Destinations.seerrBrowseWith(
                          filterId: g.id.toString(),
                          filterName: g.name,
                          mediaType: mediaType,
                          filterType: 'genre',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (s.networks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: s.networks
                  .map(
                    (n) => ActionChip(
                      label: Text(
                        n.name,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                      backgroundColor: Colors.transparent,
                      side: ThemeRegistry.active.borders.chipBorder,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => context.push(
                        Destinations.seerrBrowseWith(
                          filterId: n.id.toString(),
                          filterName: n.name,
                          mediaType: mediaType,
                          filterType: 'network',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (s.keywords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: s.keywords
                  .map(
                    (k) => ActionChip(
                      label: Text(
                        k.name,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => context.push(
                        Destinations.seerrBrowseWith(
                          filterId: k.id.toString(),
                          filterName: k.name,
                          mediaType: mediaType,
                          filterType: 'keyword',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestSection(SeerrMediaDetailState s) {
    final l10n = AppLocalizations.of(context);
    final vm = _vm!;
    final hd = s.hd;
    final uhd = s.uhd;
    final hdAction = seerrRequestActionFor(hd, vm, l10n);
    final uhdAction = seerrRequestActionFor(uhd, vm, l10n);
    final canManage = vm.canManageRequests;
    final activeRequests = s.allActiveRequests;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activeRequests.isNotEmpty) ...[
            for (final req in activeRequests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        seerrRequestedByLabel(req, l10n),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (canManage &&
                        req.status == SeerrRequest.statusPending) ...[
                      const SizedBox(width: 8),
                      SeerrApproveDeclineButtons(
                        isLoading: s.isRequesting,
                        onApprove: () => vm.approveRequest(req.id),
                        onDecline: () => vm.declineRequest(req.id),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (s.isAvailableAnyQuality)
                ElevatedButton.icon(
                  onPressed: () => _playInMoonfin(s),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.playInMoonfin),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              if (hdAction.kind == SeerrRequestActionKind.request)
                ElevatedButton.icon(
                  onPressed:
                      s.isRequesting ? null : () => showSeerrRequestDialog(context: context, vm: vm, is4k: false),
                  icon: s.isRequesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(hdAction.label),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                  ),
                ),
              if (uhdAction.kind == SeerrRequestActionKind.request)
                OutlinedButton.icon(
                  onPressed:
                      s.isRequesting ? null : () => showSeerrRequestDialog(context: context, vm: vm, is4k: true),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(uhdAction.label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: ThemeRegistry.active.borders.chipBorder.copyWith(
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: s.isTogglingWatchlist ? null : () => vm.toggleWatchlist(),
                icon: Icon(
                  s.onUserWatchlist ? Icons.bookmark : Icons.bookmark_border,
                  size: 18,
                ),
                label: Text(s.onUserWatchlist ? l10n.removeFromWatchlist : l10n.addToWatchlist),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: ThemeRegistry.active.borders.chipBorder.copyWith(
                    color: Colors.white38,
                  ),
                ),
              ),
              if (hdAction.kind == SeerrRequestActionKind.cancel)
                OutlinedButton.icon(
                  onPressed:
                      s.isRequesting
                      ? null
                      : () => showSeerrCancelRequestDialog(
                          context: context,
                          vm: vm,
                          is4k: false,
                        ),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(hdAction.label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[300],
                    side: ThemeRegistry.active.borders.chipBorder.copyWith(
                      color: Colors.red[300]!,
                    ),
                  ),
                )
              else if (hdAction.kind == SeerrRequestActionKind.requested)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(hdAction.label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: ThemeRegistry.active.borders.chipBorder.copyWith(
                      color: Colors.white24,
                    ),
                  ),
                ),
              if (uhdAction.kind == SeerrRequestActionKind.cancel)
                OutlinedButton.icon(
                  onPressed:
                      s.isRequesting
                      ? null
                      : () => showSeerrCancelRequestDialog(
                          context: context,
                          vm: vm,
                          is4k: true,
                        ),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(uhdAction.label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[300],
                    side: ThemeRegistry.active.borders.chipBorder.copyWith(
                      color: Colors.red[300]!,
                    ),
                  ),
                )
              else if (uhdAction.kind == SeerrRequestActionKind.requested)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(uhdAction.label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: ThemeRegistry.active.borders.chipBorder.copyWith(
                      color: Colors.white24,
                    ),
                  ),
                ),
              if (vm.canReportIssue)
                OutlinedButton.icon(
                  onPressed: s.isRequesting
                      ? null
                      : () => showSeerrReportIssueDialog(context: context, vm: vm),
                  icon: const Icon(Icons.report_problem_outlined, size: 18),
                  label: Text(l10n.reportIssue),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber[300],
                    side: ThemeRegistry.active.borders.chipBorder.copyWith(
                      color: Colors.amber[300]!,
                    ),
                  ),
                ),
            ],
          ),
          if (s.movie?.collection != null) ...[
            const SizedBox(height: 16),
            SeerrCollectionBanner(collection: s.movie!.collection!),
          ],
        ],
      ),
    );
  }

  Widget _buildOverview(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.85),
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildCastRow(List<SeerrCastMember> cast, AppLocalizations l10n) {
    final visible = cast.length > 20 ? cast.sublist(0, 20) : cast;
    return LibraryRow(
      title: l10n.castMembers,
      rowHeight: 170,
      children: visible.asMap().entries.map((entry) {
        final index = entry.key;
        final m = entry.value;
        return SeerrCastCard(
          member: m,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                index == 0) {
              NavigationLayout.focusNavbarNotifier.value?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          onTap: () => context.push(Destinations.seerrPerson(m.id.toString())),
        );
      }).toList(),
    );
  }

  Widget _buildRelatedRow(String title, List<SeerrDiscoverItem> items) {
    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );
    final cardExpansion = GetIt.instance<UserPreferences>().get(
      UserPreferences.cardFocusExpansion,
    );
    return LibraryRow(
      title: title,
      rowHeight: 240,
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return MediaCard(
          title: item.displayTitle,
          subtitle: _yearFromItem(item),
          imageUrl: item.posterPath != null
              ? '$seerrPosterBase${item.posterPath}'
              : null,
          width: 130,
          aspectRatio: 2 / 3,
          seerrMediaType: item.mediaType,
          seerrStatus: item.mediaInfo?.status,
          focusColor: focusColor,
          cardFocusExpansion: cardExpansion,
          suppressFocusGlow: isNeon,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                index == 0) {
              NavigationLayout.focusNavbarNotifier.value?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          onTap: () {
            final mediaType = item.mediaType ?? 'movie';
            context.push(
              Destinations.seerrMedia(
                item.id.toString(),
                mediaType: mediaType,
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Future<void> _playInMoonfin(SeerrMediaDetailState s) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    final jellyfinId =
        s.mediaInfo?.jellyfinMediaId ?? s.mediaInfo?.jellyfinMediaId4k;
    if (jellyfinId != null) {
      context.push(Destinations.item(jellyfinId));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.itemNotFoundInLibrary),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static String? _extractYear(SeerrMediaDetailState s) {
    final date = s.releaseDate ?? s.firstAirDate;
    if (date == null || date.length < 4) return null;
    return date.substring(0, 4);
  }

  static String? _yearFromItem(SeerrDiscoverItem item) {
    final date = item.releaseDate ?? item.firstAirDate;
    if (date == null || date.length < 4) return null;
    return date.substring(0, 4);
  }

  static Widget _metaText(String text) =>
      Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13));

  static Widget _tvStatusBadge(String status) {
    final lower = status.toLowerCase();
    final Color bg;
    if (lower == 'returning series' || lower == 'continuing') {
      bg = Colors.green;
    } else if (lower == 'ended' || lower == 'canceled') {
      bg = Colors.red;
    } else {
      bg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: AppRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(color: bg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

}
