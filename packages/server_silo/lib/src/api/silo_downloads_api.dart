import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

/// What Silo says about downloads for the acting profile
/// (`GET /capabilities/downloads`).
class SiloDownloadCapability {
  const SiloDownloadCapability({
    required this.state,
    required this.allowed,
    required this.enabled,
    required this.downloadAllowed,
    required this.qualityPresets,
    required this.qualityOptions,
    required this.prepareAgain,
  });

  factory SiloDownloadCapability.fromJson(Map<String, dynamic> json) {
    final presets = <String>[
      for (final p in json['quality_presets'] as List? ?? const [])
        if (p is String) p,
    ];
    final options = <SiloDownloadQualityOption>[
      for (final o in json['quality_options'] as List? ?? const [])
        if (asJsonMap(o) case final map? when map['preset'] is String)
          SiloDownloadQualityOption(
            preset: map['preset'] as String,
            bitrateKbps: (map['bitrate_kbps'] as num?)?.toInt(),
            maxHeight: (map['max_height'] as num?)?.toInt(),
          ),
    ];
    return SiloDownloadCapability(
      state: json['state'] as String? ?? 'unsupported',
      allowed: json['allowed'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
      downloadAllowed: json['download_allowed'] as bool? ?? false,
      qualityPresets: presets,
      qualityOptions: options,
      prepareAgain: json['prepare_again'] as bool? ?? false,
    );
  }

  /// Support and configuration state (`available`, `disabled`,
  /// `not_configured`, `unsupported`), not health.
  final String state;

  /// The answer for this login: `download_allowed` and not refused by the
  /// server's demo mode.
  final bool allowed;

  /// Downloads are switched on on the server.
  final bool enabled;

  /// The account may download at all.
  final bool downloadAllowed;

  /// The qualities this account may ask for now, best first (`original`,
  /// `20mbps` … `1mbps`). Empty when downloads are off for it.
  final List<String> qualityPresets;

  /// One entry per preset, in the same order: its video bitrate cap and the
  /// tallest picture it makes on this server (both absent for `original`).
  final List<SiloDownloadQualityOption> qualityOptions;

  /// The server can prepare a finished download's file again
  /// (`POST /downloads/{id}/prepare`) after cleaning it up.
  final bool prepareAgain;

  /// Whether the download actions should show: Silo's guide says to hide them
  /// unless downloads are enabled and allowed, and an empty preset list means
  /// the same.
  bool get permitsDownloads =>
      state == 'available' && enabled && allowed && qualityPresets.isNotEmpty;
}

/// One downloadable quality (`quality_options[]`).
class SiloDownloadQualityOption {
  const SiloDownloadQualityOption({
    required this.preset,
    this.bitrateKbps,
    this.maxHeight,
  });

  final String preset;
  final int? bitrateKbps;
  final int? maxHeight;
}

/// Silo's downloads (`/api/v2/downloads…`, `/capabilities/downloads`).
///
/// Moonfin's Silo client sends `X-Silo-Device-Id` and `X-Profile-Id` on every
/// request, so every download it makes is a **managed** entry of this device
/// and profile: Silo keeps a registry of what the device holds, serves a
/// manifest for it, and can revoke it (Silo's `docs/downloads-api.md`).
class SiloDownloadsApi {
  SiloDownloadsApi(this._dio, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _clock;

  /// How long a capability answer is reused. It changes when an admin
  /// changes the account's download permission or the server's download
  /// settings; the 13.4 access-change path clears it at once.
  static const capabilityTtl = Duration(minutes: 1);

  SiloDownloadCapability? _capability;
  DateTime? _capabilityReadAt;
  Future<SiloDownloadCapability>? _capabilityRead;

  /// The downloads capability for the acting profile, read at most once a
  /// minute (concurrent callers share one read). Throws when it can't be
  /// read.
  Future<SiloDownloadCapability> capability() {
    final cached = _capability;
    final readAt = _capabilityReadAt;
    if (cached != null &&
        readAt != null &&
        _clock().difference(readAt) < capabilityTtl) {
      return Future.value(cached);
    }
    return _capabilityRead ??= () async {
      try {
        final response = await _dio.get<dynamic>(
          '/api/v2/capabilities/downloads',
        );
        final json = asJsonMap(response.data);
        if (json == null) {
          throw FormatException(
            'Expected a download capability from Silo, got '
            '${response.data.runtimeType}',
          );
        }
        final capability = SiloDownloadCapability.fromJson(json);
        _capability = capability;
        _capabilityReadAt = _clock();
        return capability;
      } finally {
        _capabilityRead = null;
      }
    }();
  }

  /// Forgets the capability, so the next read asks Silo (the account's
  /// access changed, or the login did).
  void invalidateCapability() {
    _capability = null;
    _capabilityReadAt = null;
  }
}
