import 'dart:async';

import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/models/media_segment.dart';
import '../../../../data/utils/media_segment_actions.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../preference/preference_constants.dart';
import '../../../../preference/user_preferences.dart';
import '../../../../util/platform_detection.dart';
import '../../../widgets/bounded_network_image.dart';
import '../../../widgets/settings/settings_preview_scope.dart';
import '../../setup/setup_wizard_previews.dart';

String settingsPreviewSceneName(
  AppLocalizations l10n,
  SettingsPreviewScene scene,
) => switch (scene) {
  SettingsPreviewScene.home => l10n.home,
  SettingsPreviewScene.details => l10n.detailsPage,
  SettingsPreviewScene.player => l10n.player,
  SettingsPreviewScene.search => l10n.search,
};

/// The scenes this device has settings for. Keyboard Style is a TV setting,
/// so only a TV gets the search keyboard.
List<SettingsPreviewScene> get settingsPreviewScenes => [
  SettingsPreviewScene.home,
  SettingsPreviewScene.details,
  SettingsPreviewScene.player,
  if (PlatformDetection.useLeanbackUi) SettingsPreviewScene.search,
];

/// The player lays out landscape even on a phone, where playback rotates.
Size get _playerDesignSize {
  if (PlatformDetection.useLeanbackUi) return const Size(960, 540);
  if (PlatformDetection.useMobileUi) return const Size(844, 390);
  return const Size(1280, 800);
}

double settingsPreviewAspect(SettingsPreviewScene scene) =>
    scene == SettingsPreviewScene.player
    ? _playerDesignSize.aspectRatio
    : setupPreviewAspect();

Listenable _previewListenable(SettingsPreviewController controller) =>
    Listenable.merge([
      controller,
      if (GetIt.instance.isRegistered<UserPreferences>())
        GetIt.instance<UserPreferences>(),
      ?SetupPreviewData.listenable,
    ]);

/// The live preview: scene chips over a mock of the screen the focused setting
/// changes, drawn with the saved values or the option a picker is trying.
class SettingsLivePreview extends StatefulWidget {
  /// Hides the header so a phone can lay the chips out itself.
  final bool showHeader;

  const SettingsLivePreview({super.key, this.showHeader = true});

  @override
  State<SettingsLivePreview> createState() => _SettingsLivePreviewState();
}

class _SettingsLivePreviewState extends State<SettingsLivePreview> {
  @override
  void initState() {
    super.initState();
    unawaited(SetupPreviewData.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final controller = SettingsPreviewScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _previewListenable(controller),
      builder: (context, _) {
        final scene = controller.scene;
        final frame = AspectRatio(
          aspectRatio: settingsPreviewAspect(scene),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: AppRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: ClipRRect(
              borderRadius: AppRadius.circular(14),
              child: ColoredBox(
                color: AppColorScheme.background,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(scene),
                    child: ExcludeFocus(
                      child: IgnorePointer(
                        child: _sceneWidget(controller, scene),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        if (!widget.showHeader) return frame;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsPreviewSceneChips(controller: controller),
            const SizedBox(height: 10),
            Flexible(child: Center(child: frame)),
          ],
        );
      },
    );
  }

  Widget _sceneWidget(
    SettingsPreviewController controller,
    SettingsPreviewScene scene,
  ) {
    final key = controller.focused?.prefKey;
    return switch (scene) {
      SettingsPreviewScene.home => switch (key) {
        'mediaBarMode' || 'mediaBarOverlayColor' || 'mediaBarOverlayOpacity' =>
          Builder(
            builder: (context) => mediaBarPreview(
              previewValue(context, UserPreferences.mediaBarMode),
            ),
          ),
        'pref_bottom_navbar_style' => Builder(
          builder: (context) => bottomNavbarStylePreview(
            previewValue(context, UserPreferences.bottomNavbarStyle),
          ),
        ),
        _ => settingsHomePreview(),
      },
      SettingsPreviewScene.details => Builder(
        builder: (context) => detailStylePreview(
          previewValue(context, UserPreferences.detailScreenStyle),
        ),
      ),
      SettingsPreviewScene.player => SettingsPlayerPreview(focusedKey: key),
      SettingsPreviewScene.search => const SettingsSearchPreview(),
    };
  }
}

/// The "Live preview" label and the chips that switch scenes by hand. The
/// chips take clicks and taps only. A TV follows the focused setting.
class SettingsPreviewSceneChips extends StatelessWidget {
  final SettingsPreviewController controller;

  const SettingsPreviewSceneChips({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final scene in settingsPreviewScenes) ...[
          const SizedBox(width: 6),
          _SceneChip(
            label: settingsPreviewSceneName(l10n, scene),
            selected: controller.scene == scene,
            onTap: () => controller.showScene(scene),
          ),
        ],
      ],
    );
    // A phone has room for the chips or the label, and the chips matter more.
    final phone = PlatformDetection.useMobileUi;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColorScheme.accent,
          ),
        ),
        const SizedBox(width: 8),
        if (!phone) ...[
          Flexible(
            child: Text(
              l10n.settingsLivePreview.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Align(
            alignment: phone ? Alignment.centerLeft : Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: !phone,
              child: PlatformDetection.useLeanbackUi
                  ? ExcludeFocus(child: chips)
                  : chips,
            ),
          ),
        ),
      ],
    );
  }
}

class _SceneChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SceneChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.22),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected
                  ? AppColors.black
                  : AppColorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// The focused setting spelled out under the preview: its name, its full
/// description, whether the preview shows it, and every choice a picker
/// offers with the saved one and the one being tried.
class SettingsPreviewInspector extends StatelessWidget {
  const SettingsPreviewInspector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SettingsPreviewScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _previewListenable(controller),
      builder: (context, _) => _build(context, controller),
    );
  }

  Widget _build(BuildContext context, SettingsPreviewController controller) {
    final entry = controller.focused;
    if (entry == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scene = SettingsPreviewController.sceneForKey(entry.prefKey);
    final muted = AppColorScheme.onSurface.withValues(alpha: 0.6);
    final key = entry.prefKey;
    final saved = entry.currentIndex?.call() ?? -1;
    final live = (key == null ? null : controller.tryingIndex(key)) ?? saved;
    final trying = key != null && controller.isTrying(key) && live != saved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // A link opens a screen of its own settings, so it has no status to
        // report.
        if (key != null) ...[
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scene != null ? AppColorScheme.accent : muted,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  scene != null
                      ? l10n.settingsPreviewShowsOn(
                          settingsPreviewSceneName(l10n, scene),
                        )
                      : l10n.settingsPreviewNotShown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scene != null ? AppColorScheme.onSurface : muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColorScheme.onSurface,
          ),
        ),
        if (entry.description != null && entry.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            entry.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: muted),
          ),
        ],
        if (entry.options.isNotEmpty && entry.options.length <= 8) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < entry.options.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _OptionChip(
                    label: entry.options[i],
                    live: i == live,
                    savedTag: trying && i == saved
                        ? l10n.settingsPreviewSaved
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool live;
  final String? savedTag;

  const _OptionChip({required this.label, required this.live, this.savedTag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: live ? Colors.white : Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadius.circular(999),
        border: Border.all(
          color: live
              ? Colors.white
              : savedTag != null
              ? AppColorScheme.accent
              : Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: live ? AppColors.black : AppColorScheme.onSurface,
            ),
          ),
          if (savedTag != null) ...[
            const SizedBox(width: 6),
            Text(
              savedTag!.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _art(String? url) {
  if (url == null || url.isEmpty) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColorScheme.accent.withValues(alpha: 0.55),
            AppColorScheme.surfaceVariant,
          ],
        ),
      ),
    );
  }
  return BoundedNetworkImage(imageUrl: url, fit: BoxFit.cover);
}

/// Lays [child] out at [size] and scales it into whatever the preview frame
/// gives it, so every measurement is the real screen's.
Widget _designCanvas(Size size, Widget child) => FittedBox(
  fit: BoxFit.contain,
  child: SizedBox.fromSize(size: size, child: child),
);

enum _PlayerMoment { intro, middle, end }

/// The player mid-episode with its controls up: the zoom mode, subtitles,
/// skip lengths and paused description in the middle of a title, the intro
/// prompt at its start and Next Up at its end.
class SettingsPlayerPreview extends StatelessWidget {
  final String? focusedKey;

  const SettingsPlayerPreview({super.key, this.focusedKey});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = _playerDesignSize;
    final u = size.width / 960;
    final items = SetupPreviewData.items;
    final item = items.isEmpty ? null : items.first;
    final next = items.length > 1 ? items[1] : item;

    final moment = switch (focusedKey) {
      'media_segment_actions' => _PlayerMoment.intro,
      'next_up_behavior' => _PlayerMoment.end,
      _ => _PlayerMoment.middle,
    };
    final zoom = previewValue(context, UserPreferences.playerZoomMode);
    final introAction =
        parseMediaSegmentActions(
          previewValue(context, UserPreferences.mediaSegmentActions),
        )[MediaSegmentType.intro] ??
        MediaSegmentAction.askToSkip;
    final nextUp = previewValue(context, UserPreferences.nextUpBehavior);
    final paused =
        moment == _PlayerMoment.middle &&
        previewValue(context, UserPreferences.showDescriptionOnPause);
    final subtitles =
        !paused &&
        previewValue(context, UserPreferences.subtitleMode) != SubtitleMode.none;
    final back = previewValue(context, UserPreferences.skipBackLength) ~/ 1000;
    final forward =
        previewValue(context, UserPreferences.skipForwardLength) ~/ 1000;
    final (time, progress) = switch (moment) {
      _PlayerMoment.intro =>
        introAction == MediaSegmentAction.skip ? ('1:30', 0.15) : ('0:42', 0.07),
      _PlayerMoment.middle => ('4:12', 0.42),
      _PlayerMoment.end => ('9:58', 0.99),
    };

    TextStyle text(double size, {FontWeight weight = FontWeight.w500}) =>
        TextStyle(
          fontSize: size * u,
          fontWeight: weight,
          color: Colors.white,
          shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
        );

    Widget circle(Widget child, {bool filled = false}) => Container(
      width: 46 * u,
      height: 46 * u,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? Colors.white : Colors.white.withValues(alpha: 0.08),
        border: filled
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
      ),
      child: child,
    );

    return _designCanvas(
      size,
      ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: FittedBox(
                fit: switch (zoom) {
                  ZoomMode.fit => BoxFit.contain,
                  ZoomMode.autoCrop => BoxFit.cover,
                  ZoomMode.stretch => BoxFit.fill,
                },
                child: SizedBox(
                  width: 2390,
                  height: 1000,
                  child: _art(item?.backdropUrl),
                ),
              ),
            ),
            if (paused) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 48 * u,
                top: 110 * u,
                width: 460 * u,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.paused.toUpperCase(),
                      style: text(13, weight: FontWeight.w700),
                    ),
                    SizedBox(height: 8 * u),
                    Text(
                      item?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text(32, weight: FontWeight.w700),
                    ),
                    SizedBox(height: 8 * u),
                    Text(
                      item?.overview ?? '',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: text(15).copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
            if (subtitles)
              Positioned(
                left: 0,
                right: 0,
                bottom: 132 * u,
                child: Text(
                  _subtitleLine(
                    previewValue(context, UserPreferences.defaultSubtitleLanguage),
                  ),
                  textAlign: TextAlign.center,
                  style: text(24),
                ),
              ),
            if (moment == _PlayerMoment.intro &&
                introAction == MediaSegmentAction.askToSkip)
              Positioned(
                right: 36 * u,
                bottom: 126 * u,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20 * u,
                    vertical: 10 * u,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.circular(999),
                  ),
                  child: Text(
                    l10n.skipSegment(MediaSegmentType.intro.displayName),
                    style: TextStyle(
                      fontSize: 15 * u,
                      fontWeight: FontWeight.w700,
                      color: AppColors.black,
                    ),
                  ),
                ),
              ),
            if (moment == _PlayerMoment.end &&
                nextUp == NextUpBehavior.extended)
              Positioned(
                right: 32 * u,
                top: 28 * u,
                width: 270 * u,
                child: ClipRRect(
                  borderRadius: AppRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.85),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 140 * u,
                          width: double.infinity,
                          child: _art(next?.backdropUrl),
                        ),
                        Padding(
                          padding: EdgeInsets.all(12 * u),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.upNext.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11 * u,
                                  fontWeight: FontWeight.w700,
                                  color: AppColorScheme.accent,
                                ),
                              ),
                              SizedBox(height: 4 * u),
                              Text(
                                next?.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text(16, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (moment == _PlayerMoment.end && nextUp == NextUpBehavior.minimal)
              Positioned(
                right: 32 * u,
                top: 28 * u,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 * u,
                    vertical: 9 * u,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: AppRadius.circular(999),
                  ),
                  child: Text(
                    '${l10n.upNext}: ${next?.title ?? ''}',
                    style: text(14, weight: FontWeight.w600),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 118 * u,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32 * u, 0, 32 * u, 16 * u),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Text(time, style: text(13)),
                          SizedBox(width: 12 * u),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: AppRadius.circular(3),
                              child: SizedBox(
                                height: 5 * u,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(
                                      color: Colors.white.withValues(alpha: 0.25),
                                    ),
                                    FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: progress,
                                      child: ColoredBox(
                                        color: AppColorScheme.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12 * u),
                          Text('10:04', style: text(13)),
                        ],
                      ),
                      SizedBox(height: 12 * u),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          circle(
                            Text('-$back', style: text(14, weight: FontWeight.w700)),
                          ),
                          SizedBox(width: 20 * u),
                          circle(
                            Icon(
                              paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              size: 28 * u,
                              color: AppColors.black,
                            ),
                            filled: true,
                          ),
                          SizedBox(width: 20 * u),
                          circle(
                            Text(
                              '+$forward',
                              style: text(14, weight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitleLine(String language) => switch (language) {
    'jpn' => '待って、今の聞こえた？',
    'spa' => 'Espera, ¿oíste eso?',
    'fre' || 'fra' => 'Attends, tu as entendu ça ?',
    'ger' || 'deu' => 'Warte, hast du das gehört?',
    _ => 'Wait, did you hear that?',
  };
}

/// Search with its keyboard open. Classic, Glass and Docked are the app's own
/// keyboard drawn at the TV's size. Native stands in for the TV's system
/// keyboard, which the app hands typing to instead.
class SettingsSearchPreview extends StatefulWidget {
  const SettingsSearchPreview({super.key});

  @override
  State<SettingsSearchPreview> createState() => _SettingsSearchPreviewState();
}

class _SettingsSearchPreviewState extends State<SettingsSearchPreview> {
  // One per style, set before the keyboard first listens, since switching a
  // live controller's style would rebuild the keyboard mid-build.
  final _keyboards = <KeyboardStyle, KeyboardController>{};
  final _keyboardFocus = FocusNode(debugLabel: 'SettingsSearchPreviewKeys');

  @override
  void dispose() {
    for (final keyboard in _keyboards.values) {
      keyboard.dispose();
    }
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = Size(960, 540);
    const query = 'Spri';
    final style = previewValue(context, UserPreferences.keyboardStyle);
    final keyboard = _keyboards.putIfAbsent(
      style,
      () => KeyboardController()
        ..style = style
        ..setText(query)
        ..show(),
    );
    final items = SetupPreviewData.items;
    final docked = style == KeyboardStyle.docked;

    final field = Container(
      width: 420,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColorScheme.surfaceVariant,
        borderRadius: AppRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 22,
            color: AppColorScheme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),
          Text(
            query,
            style: TextStyle(fontSize: 17, color: AppColorScheme.onSurface),
          ),
          Container(width: 2, height: 20, color: AppColorScheme.accent),
        ],
      ),
    );

    final results = Row(
      children: [
        for (final item in items.take(4)) ...[
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  height: 138,
                  child: ClipRRect(
                    borderRadius: ThemeRegistry.active.borders.cardRadius,
                    child: _art(item.posterUrl),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
        ],
      ],
    );

    return _designCanvas(
      size,
      Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColorScheme.background),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 28, 48, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!docked) Center(child: field),
                const SizedBox(height: 22),
                results,
              ],
            ),
          ),
          if (style == KeyboardStyle.native)
            const Align(
              alignment: Alignment.bottomCenter,
              child: _SystemKeyboard(),
            )
          else
            MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: Material(
                type: MaterialType.transparency,
                child: Center(
                  child: CustomKeyboard(
                    key: ValueKey(style),
                    keyboardController: keyboard,
                    focusNode: _keyboardFocus,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A plain light keyboard standing in for the one the TV itself draws.
class _SystemKeyboard extends StatelessWidget {
  const _SystemKeyboard();

  @override
  Widget build(BuildContext context) {
    const rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(80, 18, 80, 22),
      color: const Color(0xFFE8EAED),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final key in row.split(''))
                    Container(
                      width: 56,
                      height: 42,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: key == 'n'
                            ? const Color(0xFF1A73E8)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        key,
                        style: TextStyle(
                          fontSize: 18,
                          color: key == 'n'
                              ? Colors.white
                              : const Color(0xFF202124),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
