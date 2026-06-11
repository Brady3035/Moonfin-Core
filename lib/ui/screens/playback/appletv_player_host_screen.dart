import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:playback_core/playback_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../playback/appletv_mpv_backend.dart';
import '../../../preference/user_preferences.dart';

class AppleTvPlayerHostScreen extends StatefulWidget {
  const AppleTvPlayerHostScreen({super.key});

  @override
  State<AppleTvPlayerHostScreen> createState() =>
      _AppleTvPlayerHostScreenState();
}

class _AppleTvPlayerHostScreenState extends State<AppleTvPlayerHostScreen> {
  StreamSubscription<void>? _exitSub;
  StreamSubscription<void>? _queueSub;
  StreamSubscription<void>? _sessionEndedSub;
  StreamSubscription<PlaybackBringupState>? _bringupSub;
  StreamSubscription<Map<String, dynamic>>? _actionSub;
  bool _exiting = false;

  AppleTvMpvBackend? get _backend {
    try {
      return GetIt.instance<AppleTvMpvBackend>();
    } catch (_) {
      return null;
    }
  }

  PlaybackManager? get _manager {
    try {
      return GetIt.instance<PlaybackManager>();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _exitSub = _backend?.userExitStream.listen((_) => _handleExit());
    _actionSub = _backend?.uiActionStream.listen(_handleUiAction);
    final manager = _manager;
    if (manager != null) {
      _queueSub = manager.queueService.queueChangedStream.listen(
        (_) => _pushMetadata(),
      );
      _sessionEndedSub = manager.sessionEndedStream.listen(
        (_) => _handleExit(),
      );
      _bringupSub = manager.bringupStateStream.listen((_) => _pushMetadata());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushMetadata());
  }

  List<Map<String, dynamic>> _trackOptions(
    List<Map<String, dynamic>> streams,
    int? selectedIndex, {
    required bool audio,
  }) {
    final options = <Map<String, dynamic>>[];
    for (final s in streams) {
      final index = (s['Index'] as int?) ?? -1;
      final displayTitle = s['DisplayTitle'] as String?;
      final title = s['Title'] as String?;
      final language = s['Language'] as String?;
      final codec = s['Codec'] as String?;
      final label = displayTitle ?? title ?? language ?? 'Track';
      final String subtitle;
      if (audio) {
        subtitle = [
          if (language != null && displayTitle != null) language,
          if (codec != null) codec.toUpperCase(),
          if (s['Channels'] != null) '${s['Channels']}ch',
        ].join(' · ');
      } else {
        final subtitleType =
            ((codec == null || codec.isEmpty) ? 'Unknown' : codec)
                .toUpperCase();
        final deliveryMethod = (s['DeliveryMethod'] as String?)
            ?.trim()
            .toLowerCase();
        final location = s['IsExternal'] == true
            ? 'External'
            : (deliveryMethod == 'embed' ? 'Embedded' : 'Internal');
        subtitle = '$subtitleType · $location';
      }
      options.add({
        'index': index,
        'label': label,
        'subtitle': subtitle,
        'selected': index == selectedIndex,
      });
    }
    return options;
  }

  void _pushMetadata() {
    final manager = _manager;
    final backend = _backend;
    if (manager == null || backend == null) return;

    final item = manager.queueService.currentItem;
    final chapters = <Map<String, dynamic>>[];

    List<Map<String, dynamic>>? rawChapters;
    if (item is AggregatedItem) {
      rawChapters = item.chapters;
    } else if (item is String) {
      rawChapters = (manager.currentOfflineMetadata?['Chapters'] as List?)
          ?.cast<Map<String, dynamic>>();
    }

    if (rawChapters != null) {
      for (var i = 0; i < rawChapters.length; i++) {
        final chapter = rawChapters[i];
        final ticks = (chapter['StartPositionTicks'] as int?) ?? 0;
        final startMs = ticks ~/ 10000;
        final title = (chapter['Name'] as String?)?.trim();
        chapters.add({
          'title': (title != null && title.isNotEmpty)
              ? title
              : 'Chapter ${i + 1}',
          'startMs': startMs,
        });
      }
    }

    String topTitle = '';
    String topSubtitle = '';
    if (item is AggregatedItem) {
      final episodeInfo = item.indexNumber != null
          ? 'S${item.parentIndexNumber ?? '?'}:E${item.indexNumber}'
          : null;
      topSubtitle = item.seriesName ?? '';
      topTitle = [
        ?episodeInfo,
        item.name,
      ].where((s) => s.isNotEmpty).join(' - ');
    } else if (item is Map) {
      final title = (item['Name'] as String?) ?? '';
      final series = (item['SeriesName'] as String?) ?? '';
      final idx = item['IndexNumber'];
      final episodeInfo = idx != null
          ? 'S${item['ParentIndexNumber'] ?? '?'}:E$idx'
          : null;
      topSubtitle = series;
      topTitle = [?episodeInfo, title].where((s) => s.isNotEmpty).join(' - ');
    } else if (item is String) {
      final meta = manager.currentOfflineMetadata;
      final title = (meta?['Name'] as String?) ?? item.split('/').last;
      final series = (meta?['SeriesName'] as String?) ?? '';
      final idx = meta?['IndexNumber'] as int?;
      final parentIdx = meta?['ParentIndexNumber'] as int?;
      final episodeInfo = idx != null ? 'S${parentIdx ?? '?'}:E$idx' : null;
      topSubtitle = series;
      topTitle = [?episodeInfo, title].where((s) => s.isNotEmpty).join(' - ');
    }

    final allStreams =
        manager.currentResolution?.mediaStreams ??
        (manager.currentOfflineMetadata?['MediaStreams'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final audioStreams = allStreams
        .where((s) => s['Type'] == 'Audio')
        .toList();
    final subtitleStreams = allStreams
        .where((s) => s['Type'] == 'Subtitle')
        .toList();

    final skipForwardMs = _prefInt(
      UserPreferences.skipForwardLength,
      defaultValue: 30000,
    );
    final skipBackMs = _prefInt(
      UserPreferences.skipBackLength,
      defaultValue: 10000,
    );

    backend.setUiMetadata(
      topTitle: topTitle,
      topSubtitle: topSubtitle,
      chapters: chapters,
      hasPrevious: manager.queueService.hasPrevious,
      hasNext: manager.queueService.hasNext,
      skipForwardMs: skipForwardMs,
      skipBackMs: skipBackMs,
      audioTracks: _trackOptions(
        audioStreams,
        manager.audioStreamIndex,
        audio: true,
      ),
      subtitleTracks: _trackOptions(
        subtitleStreams,
        manager.subtitleStreamIndex,
        audio: false,
      ),
    );
  }

  int _prefInt(Preference<int> pref, {required int defaultValue}) {
    try {
      return GetIt.instance<UserPreferences>().get(pref);
    } catch (_) {
      return defaultValue;
    }
  }

  void _handleUiAction(Map<String, dynamic> action) {
    final manager = _manager;
    if (manager == null) return;
    switch (action['event']?.toString()) {
      case 'next':
        unawaited(manager.next());
      case 'previous':
        unawaited(manager.previous());
      case 'selectAudio':
        final index = (action['index'] as num?)?.toInt();
        if (index != null) {
          unawaited(manager.changeAudioTrack(index));
        }
      case 'selectSubtitle':
        final index = (action['index'] as num?)?.toInt();
        if (index == null) break;
        if (index < 0) {
          unawaited(manager.disableSubtitles());
        } else {
          unawaited(manager.changeSubtitleTrack(index));
        }
    }
    Future<void>.delayed(const Duration(milliseconds: 300), _pushMetadata);
  }

  void _handleExit() {
    if (_exiting || !mounted) return;
    _exiting = true;
    unawaited(_backend?.dismissPlayer() ?? Future<void>.value());
    if (context.canPop()) {
      context.pop();
    }
  }

  @override
  void dispose() {
    _exitSub?.cancel();
    _queueSub?.cancel();
    _sessionEndedSub?.cancel();
    _bringupSub?.cancel();
    _actionSub?.cancel();
    unawaited(_backend?.dismissPlayer() ?? Future<void>.value());
    try {
      GetIt.instance<PlaybackManager>().stop(userInitiated: true);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(),
    );
  }
}
