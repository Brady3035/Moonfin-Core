import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_media_source_mapper.dart';
import '../silo_problem.dart';
import 'silo_items_api.dart';
import 'silo_pending_api.dart';

/// Moonfin's `PlaybackApi` on Silo: the detail screen's media info (step
/// 6.18), and the wire calls of Silo's playback protocol for
/// `playback_silo`, which owns the protocol itself (phase 10).
class SiloPlaybackApi implements PlaybackApi {
  SiloPlaybackApi(this._items, this._dio, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final SiloItemsApi _items;
  final Dio _dio;
  final DateTime Function() _now;

  // --- capabilities (10.5) ----------------------------------------------------

  /// How long [capabilities] reuses an answer, as Silo's web player does.
  static const capabilitiesLifetime = Duration(minutes: 1);

  SiloPlaybackCapabilities? _capabilities;
  DateTime? _capabilitiesAt;
  Future<SiloPlaybackCapabilities>? _capabilitiesRead;

  /// `GET /api/v2/playback/capabilities` (step 10.5): whether this server
  /// plays, its installation id, its features and deliveries.
  ///
  /// Every playback mutation carries the [SiloPlaybackCapabilities.installationId]
  /// read here, so it is kept for [capabilitiesLifetime] and reads made
  /// meanwhile share one request. [refresh] reads it again now, which is
  /// what a `409 installation_changed` calls for ([isInstallationChanged]).
  Future<SiloPlaybackCapabilities> capabilities({bool refresh = false}) {
    final at = _capabilitiesAt;
    final kept = _capabilities;
    if (!refresh &&
        kept != null &&
        at != null &&
        _now().difference(at) < capabilitiesLifetime) {
      return Future.value(kept);
    }
    final pending = _capabilitiesRead;
    if (pending != null) return pending;
    final read = _readCapabilities();
    _capabilitiesRead = read;
    return read.whenComplete(() => _capabilitiesRead = null);
  }

  Future<SiloPlaybackCapabilities> _readCapabilities() async {
    final response = await _dio.get<dynamic>('/api/v2/playback/capabilities');
    final json = asJsonMap(response.data);
    if (json == null) {
      throw FormatException(
        'Expected playback capabilities from Silo, got '
        '${response.data.runtimeType}',
      );
    }
    final capabilities = SiloPlaybackCapabilities.fromJson(json);
    _capabilities = capabilities;
    _capabilitiesAt = _now();
    return capabilities;
  }

  /// Forgets the kept capabilities, so the next [capabilities] asks Silo.
  void forgetCapabilities() {
    _capabilities = null;
    _capabilitiesAt = null;
  }

  /// Whether [error] is Silo's `409 installation_changed`: the request
  /// carried the installation id of a server that has since been reset or
  /// replaced. The capabilities are read again and a new attempt started.
  static bool isInstallationChanged(Object error) =>
      error is DioException &&
      error.response?.statusCode == 409 &&
      SiloProblem.codeOf(error) == 'installation_changed';

  /// What the detail screen shows about how a version would play, **without
  /// starting playback** (step 6.18).
  ///
  /// Jellyfin's `PlaybackInfo` is a dry run; Silo has none. Its only
  /// decision is `POST /playback/start`, which opens a session (and may start
  /// a transcode), so it must never be called to fill a detail page. The
  /// answer is built from the item's versions instead (5.8): its
  /// `MediaSources`, the one asked for (`MediaSourceId`) first.
  ///
  /// `SupportsDirectPlay` is an **estimate** from the device profile the
  /// detail screen sends: a version can play directly when a direct-play
  /// profile takes its container, video codec and the chosen audio track's
  /// codec. Otherwise it says why (`ContainerNotSupported`,
  /// `VideoCodecNotSupported`, `AudioCodecNotSupported`), as Jellyfin does.
  /// Silo makes the real decision when playback starts (phase 10).
  @override
  Future<Map<String, dynamic>> getPlaybackInfo(
    String itemId, {
    Map<String, dynamic>? requestBody,
    String? userId,
    int? startTimeTicks,
    bool waitForMediaProbe = false,
  }) async {
    final wanted = requestBody?['MediaSourceId'] as String?;
    final item = await _items.getItem(itemId);
    final sources = [
      for (final s in (item['MediaSources'] as List?) ?? const [])
        if (s is Map) Map<String, dynamic>.of(s.cast<String, dynamic>()),
    ];
    final at = wanted == null
        ? -1
        : sources.indexWhere((s) => s['Id'] == wanted);
    if (at > 0) sources.insert(0, sources.removeAt(at));

    final profile = requestBody?['DeviceProfile'];
    final audioIndex = requestBody?['AudioStreamIndex'];
    for (final source in sources) {
      source.remove(siloTracksKey);
      final reasons = profile is Map
          ? siloDirectPlayReasons(
              source,
              profile.cast<String, dynamic>(),
              audioStreamIndex: audioIndex is int ? audioIndex : null,
            )
          : const <String>[];
      source['SupportsDirectPlay'] = reasons.isEmpty;
      if (reasons.isNotEmpty) source['TranscodingReasons'] = reasons;
    }
    return {'MediaSources': sources, 'PlaySessionId': null};
  }

  static const _steps = {
    'reportPlaybackStart': '10.6',
    'reportPlaybackProgress': '10.9',
    'reportPlaybackStopped': '10.10',
    'getStreamUrl': '10.6',
    'stopActiveEncodings': '10.10',
    'closeLiveStream': '10.10',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName
        .toString()
        .replaceFirst('Symbol("', '')
        .replaceFirst('")', '');
    throw SiloNotImplementedError('PlaybackApi', name, _steps[name] ?? '10.x');
  }
}

/// Why [source] can't play directly under [deviceProfile]'s direct-play
/// profiles, as Jellyfin's transcode reasons; empty when one profile takes
/// its container, video codec and the audio track [audioStreamIndex] (or
/// the default one).
List<String> siloDirectPlayReasons(
  Map<String, dynamic> source,
  Map<String, dynamic> deviceProfile, {
  int? audioStreamIndex,
}) {
  final profiles = [
    for (final p in (deviceProfile['DirectPlayProfiles'] as List?) ?? const [])
      if (p is Map && (p['Type'] ?? 'Video') == 'Video')
        p.cast<String, dynamic>(),
  ];
  final streams = [
    for (final s in (source['MediaStreams'] as List?) ?? const [])
      if (s is Map) s.cast<String, dynamic>(),
  ];
  final video = streams.where((s) => s['Type'] == 'Video').firstOrNull;
  final audioIndex = audioStreamIndex ?? source['DefaultAudioStreamIndex'];
  final audio =
      streams
          .where((s) => s['Type'] == 'Audio' && s['Index'] == audioIndex)
          .firstOrNull ??
      streams.where((s) => s['Type'] == 'Audio').firstOrNull;

  Set<String> list(Object? csv) => {
    if (csv is String)
      for (final v in csv.split(','))
        if (v.trim().isNotEmpty) v.trim().toLowerCase(),
  };
  bool takes(Object? csv, Object? value) {
    final allowed = list(csv);
    if (allowed.isEmpty) return true;
    if (value is! String) return false;
    final lower = value.toLowerCase();
    // A file's container can be named several ways (`mkv` vs `matroska`).
    return allowed.contains(lower) ||
        (lower == 'mkv' && allowed.contains('matroska')) ||
        (lower == 'matroska' && allowed.contains('mkv'));
  }

  if (profiles.isEmpty) return const ['ContainerNotSupported'];
  // The profile that comes closest names the reasons.
  List<String>? best;
  for (final p in profiles) {
    final reasons = [
      if (!takes(p['Container'], source['Container'])) 'ContainerNotSupported',
      if (video != null && !takes(p['VideoCodec'], video['Codec']))
        'VideoCodecNotSupported',
      if (audio != null && !takes(p['AudioCodec'], audio['Codec']))
        'AudioCodecNotSupported',
    ];
    if (reasons.isEmpty) return const [];
    if (best == null || reasons.length < best.length) best = reasons;
  }
  return best!;
}

/// Silo's answer to `GET /api/v2/playback/capabilities`.
class SiloPlaybackCapabilities {
  const SiloPlaybackCapabilities({
    required this.installationId,
    this.revision,
    this.state,
    this.allowed = false,
    this.protocolVersions = const [],
    this.features = const [],
    this.deliveries = const [],
  });

  factory SiloPlaybackCapabilities.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? value) => [
      if (value is List)
        for (final v in value)
          if (v is T) v,
    ];
    final id = json['installation_id'];
    final revision = json['revision'];
    final state = json['state'];
    return SiloPlaybackCapabilities(
      installationId: id is String ? id.trim() : '',
      revision: revision is String ? revision : null,
      state: state is String ? state : null,
      allowed: json['allowed'] == true,
      protocolVersions: list<int>(json['protocol_versions']),
      features: list<String>(json['features']),
      deliveries: list<String>(json['deliveries']),
    );
  }

  /// The server instance's UUID, which every playback mutation must carry.
  final String installationId;

  /// A digest of the rest; it changes when anything else here does.
  final String? revision;

  /// `available`, or `not_configured` on a server without playback.
  final String? state;
  final bool allowed;
  final List<int> protocolVersions;
  final List<String> features;

  /// The server's deliveries (`original_http`, `server_remux_progressive`,
  /// `server_remux_hls`, `server_transcode_hls` when it transcodes).
  final List<String> deliveries;

  /// Whether Moonfin can play from this server: playback is available and
  /// allowed, protocol v3 is offered, and there is an installation id.
  bool get playable =>
      state == 'available' &&
      allowed &&
      protocolVersions.contains(3) &&
      installationId.isNotEmpty;

  bool has(String feature) => features.contains(feature);
}
