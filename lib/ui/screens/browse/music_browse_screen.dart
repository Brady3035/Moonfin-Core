import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/background_service.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/viewmodels/music_browse_view_model.dart';
import '../../../preference/user_preferences.dart';
import '../../../ui/mixins/focus_state_mixin.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/focusable_toolbar_button.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../../l10n/app_localizations.dart';
import '../../util/home_row_title_localizer.dart';

Color get _navyBackground => AppColorScheme.background;
const _cardSize = 140.0;
const _horizontalPadding = 20.0;
const _cardSpacing = 12.0;

class MusicBrowseScreen extends StatefulWidget {
  final String libraryId;

  const MusicBrowseScreen({super.key, required this.libraryId});

  @override
  State<MusicBrowseScreen> createState() => _MusicBrowseScreenState();
}

class _MusicBrowseScreenState extends State<MusicBrowseScreen> {
  late final MusicBrowseViewModel _vm;
  final _backgroundService = GetIt.instance<BackgroundService>();

  @override
  void initState() {
    super.initState();
    _vm = MusicBrowseViewModel(
      libraryId: widget.libraryId,
      dataSource: GetIt.instance<RowDataSource>(),
      client: GetIt.instance<MediaServerClient>(),
    );
    _vm.addListener(_onChanged);
    _vm.load();
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onItemFocused(AggregatedItem item) {
    _vm.setFocusedItem(item);
    _backgroundService.setBackground(item);
  }

  void _onItemTap(AggregatedItem item) {
    context.push(Destinations.item(item.id, serverId: item.serverId));
  }

  void _onRandomAlbum() async {
    try {
      final client = GetIt.instance<MediaServerClient>();
      final response = await client.itemsApi.getItems(
        parentId: widget.libraryId,
        includeItemTypes: ['MusicAlbum'],
        sortBy: 'Random',
        sortOrder: 'Ascending',
        recursive: true,
        limit: 1,
      );
      final items = (response['Items'] as List?) ?? [];
      if (items.isNotEmpty && mounted) {
        final id = items.first['Id']?.toString() ?? '';
        context.push(Destinations.itemListOf(id));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) =>
      RequestInitialFocus(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: _navyBackground,
      body: Stack(
        children: [
          Container(color: _navyBackground.withAlpha(191)),
          Column(
            children: [
              _MusicHeader(
                libraryName: _vm.libraryName,
                focusedItem: _vm.focusedItem,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _vm.isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColorScheme.accent,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _vm.refresh,
                        child: ListView(
                          padding: const EdgeInsets.only(top: 4, bottom: 32),
                          children: [
                            _MusicViewsRow(
                              libraryId: widget.libraryId,
                              onRandomAlbum: _onRandomAlbum,
                            ),
                            ..._vm.rows.map(
                              (row) => _MusicItemRow(
                                title: localizeHomeRowTitle(
                                  row: row,
                                  l10n: l10n,
                                ),
                                items: row.items,
                                imageApi: _vm.imageApi,
                                getSubtitle: _vm.getMusicSubtitle,
                                getImageUrl: _vm.getMusicImageUrl,
                                onFocused: _onItemFocused,
                                onTap: _onItemTap,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MusicHeader extends StatelessWidget {
  final String libraryName;
  final AggregatedItem? focusedItem;

  const _MusicHeader({required this.libraryName, this.focusedItem});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        topPad + 8,
        _horizontalPadding,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Text(
              libraryName,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w300,
                color: AppColorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: focusedItem != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        focusedItem!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.05,
                          color: AppColorScheme.onSurface,
                        ),
                      ),
                      if (focusedItem!.productionYear != null)
                        Text(
                          '${focusedItem!.productionYear}',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.0,
                            color: AppColorScheme.onSurface.withAlpha(179),
                          ),
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FocusableToolbarButton(
                icon: Icons.home,
                size: 52,
                iconSize: 28,
                variant: ToolbarButtonVariant.translucent,
                scaleOnFocus:
                    GetIt.instance<UserPreferences>().get(
                      UserPreferences.cardFocusExpansion,
                    )
                    ? 1.05
                    : 1.0,
                onTap: () => context.go(Destinations.home),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MusicViewsRow extends StatelessWidget {
  final String libraryId;
  final VoidCallback onRandomAlbum;

  const _MusicViewsRow({required this.libraryId, required this.onRandomAlbum});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _horizontalPadding,
            12,
            _horizontalPadding,
            8,
          ),
          child: Text(
            AppLocalizations.of(context).views,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColorScheme.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(
              _horizontalPadding,
              4,
              _horizontalPadding,
              6,
            ),
            children: [
              _ViewButton(
                icon: Icons.album,
                label: AppLocalizations.of(context).albums,
                onTap: () => context.push(
                  Destinations.library(
                    libraryId,
                    includeItemTypes: ['MusicAlbum'],
                  ),
                ),
              ),
              const SizedBox(width: _cardSpacing),
              _ViewButton(
                icon: Icons.person,
                label: AppLocalizations.of(context).albumArtists,
                onTap: () => context.push(
                  Destinations.library(
                    libraryId,
                    includeItemTypes: ['AlbumArtist'],
                  ),
                ),
              ),
              const SizedBox(width: _cardSpacing),
              _ViewButton(
                icon: Icons.groups,
                label: AppLocalizations.of(context).artists,
                onTap: () => context.push(
                  Destinations.library(
                    libraryId,
                    includeItemTypes: ['MusicArtist'],
                  ),
                ),
              ),
              const SizedBox(width: _cardSpacing),
              _ViewButton(
                icon: Icons.album,
                label: AppLocalizations.of(context).genres,
                onTap: () =>
                    context.push(Destinations.libraryGenresOf(libraryId)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ViewButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ViewButton> createState() => _ViewButtonState();
}

class _ViewButtonState extends State<_ViewButton> with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final cardExpansion = GetIt.instance<UserPreferences>().get(
      UserPreferences.cardFocusExpansion,
    );
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        onFocusChange: (hasFocus) => setFocused(hasFocus),
        onKeyEvent: (_, event) {
          if (isActivateKey(event)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: cardExpansion && showFocusBorder ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _cardSize,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColorScheme.onSurface.withAlpha(focused ? 51 : 20),
                borderRadius: BorderRadius.circular(8),
                border: showFocusBorder
                    ? Border.fromBorderSide(
                        ThemeRegistry.active.borders.focusBorder.copyWith(
                          color: focusColor,
                          width: 2.4,
                        ),
                      )
                    : null,
                boxShadow: showFocusBorder
                    ? [
                        BoxShadow(
                          color: AppColorScheme.accent.withAlpha(140),
                          blurRadius: 14,
                          spreadRadius: 1.2,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    size: 30,
                    color: AppColorScheme.onSurface.withAlpha(
                      focused ? 255 : 153,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: focused ? FontWeight.w600 : FontWeight.normal,
                      color: AppColorScheme.onSurface.withAlpha(
                        focused ? 255 : 179,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MusicItemRow extends StatelessWidget {
  final String title;
  final List<AggregatedItem> items;
  final ImageApi imageApi;
  final String Function(AggregatedItem) getSubtitle;
  final String? Function(AggregatedItem) getImageUrl;
  final ValueChanged<AggregatedItem> onFocused;
  final ValueChanged<AggregatedItem> onTap;

  const _MusicItemRow({
    required this.title,
    required this.items,
    required this.imageApi,
    required this.getSubtitle,
    required this.getImageUrl,
    required this.onFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _horizontalPadding,
            16,
            _horizontalPadding,
            8,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColorScheme.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: _cardSize + 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(_horizontalPadding, 6, 24, 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: _cardSpacing),
            itemBuilder: (_, i) {
              final item = items[i];
              return _MusicSquareCard(
                title: item.name,
                subtitle: getSubtitle(item),
                imageUrl: getImageUrl(item),
                onFocus: () => onFocused(item),
                onTap: () => onTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MusicSquareCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback? onFocus;
  final VoidCallback? onTap;

  const _MusicSquareCard({
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.onFocus,
    this.onTap,
  });

  @override
  State<_MusicSquareCard> createState() => _MusicSquareCardState();
}

class _MusicSquareCardState extends State<_MusicSquareCard>
    with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final cardExpansion = GetIt.instance<UserPreferences>().get(
      UserPreferences.cardFocusExpansion,
    );
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );
    return SizedBox(
      width: _cardSize,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setHovered(true),
        onExit: (_) => setHovered(false),
        child: Focus(
          onFocusChange: (hasFocus) {
            setFocused(hasFocus);
            if (hasFocus) widget.onFocus?.call();
          },
          onKeyEvent: (_, event) {
            if (isActivateKey(event)) {
              widget.onTap?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: AnimatedScale(
                scale: cardExpansion && showFocusBorder ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: showFocusBorder
                            ? Border.fromBorderSide(
                                ThemeRegistry.active.borders.focusBorder
                                    .copyWith(color: focusColor, width: 2.4),
                              )
                            : null,
                        boxShadow: showFocusBorder
                            ? [
                                BoxShadow(
                                  color: AppColorScheme.accent.withAlpha(150),
                                  blurRadius: 16,
                                  spreadRadius: 1.4,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: _cardSize,
                          height: _cardSize,
                          color: AppColorScheme.onSurface.withAlpha(
                            focused ? 36 : 15,
                          ),
                          child: widget.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: widget.imageUrl!,
                                  fit: BoxFit.cover,
                                  fadeInDuration: const Duration(
                                    milliseconds: 200,
                                  ),
                                  errorWidget: (_, _, _) => _albumPlaceholder(),
                                )
                              : _albumPlaceholder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                        color: AppColorScheme.onSurface,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        color: AppColorScheme.onSurface.withAlpha(128),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _albumPlaceholder() {
    return Center(
      child: Icon(
        Icons.album,
        size: 48,
        color: AppColorScheme.onSurface.withAlpha(51),
      ),
    );
  }
}
