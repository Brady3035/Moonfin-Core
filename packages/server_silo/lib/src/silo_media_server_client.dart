import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import 'api/silo_instant_mix_api.dart';
import 'api/silo_live_tv_api.dart';
import 'api/silo_pending_api.dart';
import 'api/silo_system_api.dart';
import 'silo_problem.dart';

/// Moonfin's client for a Silo server, speaking Silo's native `/api/v2`.
///
/// [baseUrl] is the server origin (plus any reverse-proxy prefix) without
/// `/api/v2`; each API class adds the full path itself.
///
/// Every request carries Silo's headers (see [buildSiloRequestHeaders]): the
/// bearer token once signed in, the household profile, and this device and
/// app. On Silo, Moonfin's user is a household profile, so [userId] and
/// [profileId] normally hold the same id; they are kept apart because
/// signing in happens before a profile is chosen.
///
/// Most APIs are placeholders that throw [SiloNotImplementedError] naming the
/// roadmap step that replaces them. Live TV and Instant Mix are permanently
/// empty: Silo has neither.
class SiloMediaServerClient extends MediaServerClient
    implements ProfileAwareClient {
  final Dio _dio;

  @override
  final DeviceInfo deviceInfo;

  /// The platform name sent as `X-Silo-Device-Platform` (e.g. `macOS`,
  /// `Android TV`). Supplied by the app, which knows the platform.
  final String? platform;

  /// [httpClientAdapter] replaces the network transport; tests use it to
  /// answer from captured server responses.
  SiloMediaServerClient({
    required String baseUrl,
    required this.deviceInfo,
    this.platform,
    HttpClientAdapter? httpClientAdapter,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           followRedirects: false,
           // Only the connect. Waiting for a free slot happens before this
           // starts, so it can stay short enough to give up on a hung host.
           connectTimeout: const Duration(seconds: 8),
           receiveTimeout: const Duration(minutes: 3),
         ),
       ) {
    _baseUrl = baseUrl;
    configureServerDio(_dio);
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
    _setupInterceptors();
  }

  late String _baseUrl;
  String? _accessToken;
  String? _userId;

  /// The household profile requests act as (`X-Profile-Id`).
  @override
  String? profileId;

  /// Proof that a PIN-locked profile was unlocked (`X-Profile-Token`).
  @override
  String? profileToken;

  // Progress goes out every few seconds and would fill the report inside an
  // hour, so only one answer a minute is kept. A ping that fails still goes
  // through onError.
  static const _progressPingLogInterval = 12;
  int _progressPings = 0;

  static final _progressPath = RegExp(r'/api/v2/playback/[^/]+/progress$');

  bool _isProgressPing(Uri uri) => _progressPath.hasMatch(uri.path);

  bool _progressPingIsDue() {
    _progressPings++;
    return _progressPings % _progressPingLogInterval == 1;
  }

  /// The headers Silo expects on every request, for the current sign-in and
  /// profile.
  Map<String, String> get requestHeaders => buildSiloRequestHeaders(
    deviceInfo: deviceInfo,
    platform: platform,
    accessToken: _accessToken,
    profileId: profileId,
    profileToken: profileToken,
  );

  /// The same headers as [requestHeaders], for requests made outside this
  /// client's own HTTP stack (see [serverAuthHeaders]).
  @override
  Map<String, String> authHeaders() => requestHeaders;

  void _setupInterceptors() {
    _dio.interceptors.add(redirectInterceptor(_dio));
    // Added before the logger so a failure is logged with Silo's problem code
    // and text (error interceptors run in the order they were added).
    _dio.interceptors.add(siloProblemInterceptor());
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll(requestHeaders);
          if (!_isProgressPing(options.uri)) {
            ServerLog.network('→ ${options.method} ${options.uri}');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          final uri = response.requestOptions.uri;
          if (!_isProgressPing(uri) || _progressPingIsDue()) {
            ServerLog.network(
              '← ${response.statusCode} ${response.requestOptions.method} $uri',
            );
          }
          handler.next(response);
        },
        onError: (error, handler) {
          ServerLog.network(
            '✗ ${error.requestOptions.method} ${error.requestOptions.uri} '
            '(${error.response?.statusCode ?? error.type.name})',
            level: ServerLogLevel.error,
            error: error.message ?? error.toString(),
          );
          handler.next(error);
        },
      ),
    );
  }

  @override
  ServerType get serverType => ServerType.silo;

  @override
  String get baseUrl => _baseUrl;

  @override
  set baseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
  }

  @override
  String? get accessToken => _accessToken;

  @override
  set accessToken(String? token) => _accessToken = token;

  @override
  String? get userId => _userId;

  @override
  set userId(String? id) => _userId = id;

  @override
  final AuthApi authApi = const SiloPendingAuthApi();

  @override
  final UsersApi usersApi = const SiloPendingUsersApi();

  @override
  late final SystemApi systemApi = SiloSystemApi(_dio);

  @override
  final ItemsApi itemsApi = const SiloPendingItemsApi();

  @override
  final UserViewsApi userViewsApi = const SiloPendingUserViewsApi();

  @override
  final UserLibraryApi userLibraryApi = const SiloPendingUserLibraryApi();

  @override
  final DisplayPreferencesApi displayPreferencesApi =
      const SiloPendingDisplayPreferencesApi();

  @override
  final PlaybackApi playbackApi = const SiloPendingPlaybackApi();

  @override
  final SessionApi sessionApi = const SiloPendingSessionApi();

  @override
  final ImageApi imageApi = const SiloPendingImageApi();

  @override
  final LiveTvApi liveTvApi = const SiloLiveTvApi();

  @override
  final InstantMixApi instantMixApi = const SiloInstantMixApi();

  // Silo's admin API is unrelated to Jellyfin's; Silo is administered from
  // its own web app, and FeatureDetector.supportsAdmin hides Moonfin's panel.
  static Never _noAdmin() =>
      throw UnsupportedError('Admin is not supported on Silo');

  @override
  AdminSystemApi get adminSystemApi => _noAdmin();

  @override
  AdminUsersApi get adminUsersApi => _noAdmin();

  @override
  AdminLibraryApi get adminLibraryApi => _noAdmin();

  @override
  AdminEnvironmentApi get adminEnvironmentApi => _noAdmin();

  @override
  AdminTasksApi get adminTasksApi => _noAdmin();

  @override
  AdminPluginsApi get adminPluginsApi => _noAdmin();

  @override
  AdminDevicesApi get adminDevicesApi => _noAdmin();

  @override
  AdminApiKeysApi get adminApiKeysApi => _noAdmin();

  @override
  AdminBackupApi get adminBackupApi => _noAdmin();

  @override
  AdminLiveTvApi get adminLiveTvApi => _noAdmin();

  @override
  AdminItemsApi get adminItemsApi => _noAdmin();

  @override
  void dispose() {
    _dio.close();
  }
}
