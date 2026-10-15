import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import 'api/silo_account_api.dart';
import 'api/silo_instant_mix_api.dart';
import 'api/silo_items_api.dart';
import 'api/silo_user_library_api.dart';
import 'api/silo_live_tv_api.dart';
import 'api/silo_auth_api.dart';
import 'api/silo_image_api.dart';
import 'api/silo_images_api.dart';
import 'api/silo_pending_api.dart';
import 'api/silo_profiles_api.dart';
import 'api/silo_system_api.dart';
import 'api/silo_user_views_api.dart';
import 'api/silo_users_api.dart';
import 'mappers/silo_ids.dart';
import 'mappers/silo_item_mapper.dart';
import 'mappers/silo_library_mapper.dart';
import 'silo_image_registry.dart';
import 'silo_image_resolver.dart';
import 'silo_problem.dart';
import 'silo_session.dart';
import 'silo_session_interceptor.dart';

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

  /// Sends refreshes (and, from step 2.3, sign-in). It has the same headers,
  /// error parsing and redirect rule as [_dio] but no session interceptor, so
  /// a refresh never re-enters the request pipeline it is repairing.
  final Dio _authDio;

  @override
  final DeviceInfo deviceInfo;

  /// The platform name sent as `X-Silo-Device-Platform` (e.g. `macOS`,
  /// `Android TV`). Supplied by the app, which knows the platform.
  final String? platform;

  /// Sign-in state: the account's token pair (see [SiloSession]).
  final SiloSession session;

  /// [httpClientAdapter] replaces the network transport; tests use it to
  /// answer from captured server responses. [clock] lets tests move time.
  SiloMediaServerClient({
    required String baseUrl,
    required this.deviceInfo,
    this.platform,
    HttpClientAdapter? httpClientAdapter,
    DateTime Function()? clock,
  }) : session = SiloSession(clock: clock),
       _dio = _newDio(baseUrl),
       _authDio = _newDio(baseUrl) {
    _baseUrl = baseUrl;
    // The profile selection and its PIN proof belong to the login they were
    // made under, so they go when that login is replaced or ends. Callers
    // pick a profile after setting tokens.
    session.addAccountChangedListener(() {
      _profileId = null;
      _profileToken = null;
    });
    for (final dio in [_dio, _authDio]) {
      configureServerDio(dio);
      if (httpClientAdapter != null) dio.httpClientAdapter = httpClientAdapter;
    }
    _setupInterceptors();
    SiloImageResolution.register(imageResolver);
  }

  static Dio _newDio(String baseUrl) => Dio(
    BaseOptions(
      baseUrl: baseUrl,
      followRedirects: false,
      // Only the connect. Waiting for a free slot happens before this
      // starts, so it can stay short enough to give up on a hung host.
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(minutes: 3),
    ),
  );

  late String _baseUrl;
  String? _userId;
  String? _profileId;
  String? _profileToken;

  /// The household profile requests act as (`X-Profile-Id`).
  @override
  String? get profileId => _profileId;

  @override
  set profileId(String? id) {
    if (id == _profileId) return;
    _profileId = id;
    session.identityChanged();
  }

  /// Proof that a PIN-locked profile was unlocked (`X-Profile-Token`).
  @override
  String? get profileToken => _profileToken;

  @override
  set profileToken(String? token) {
    if (token == _profileToken) return;
    _profileToken = token;
    session.identityChanged();
  }

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
    accessToken: session.accessToken,
    profileId: _profileId,
    profileToken: _profileToken,
  );

  /// The same headers as [requestHeaders], for requests made outside this
  /// client's own HTTP stack (see [serverAuthHeaders]).
  @override
  Map<String, String> authHeaders() => requestHeaders;

  void _setupInterceptors() {
    for (final dio in [_dio, _authDio]) {
      // Requests carry the bearer token (and, at sign-in, the password), so
      // redirects are only followed within the same origin.
      dio.interceptors.add(redirectInterceptor(dio, sameOriginOnly: true));
      // Added before the logger so a failure is logged with Silo's problem
      // code and text (error interceptors run in the order they were added).
      dio.interceptors.add(siloProblemInterceptor());
      if (identical(dio, _dio)) {
        // Before the header interceptor, so a refresh made before sending is
        // in place when the bearer token is written into the request.
        dio.interceptors.add(SiloSessionInterceptor(_dio, _authDio, session));
      }
      dio.interceptors.add(_headersAndLogging());
    }
  }

  InterceptorsWrapper _headersAndLogging() => InterceptorsWrapper(
    onRequest: (options, handler) {
      final headers = requestHeaders;
      if (options.extra[siloNoAuthExtra] == true) {
        headers.remove('Authorization');
      }
      options.headers.addAll(headers);
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
  );

  /// Refreshes the session's tokens now, through the refresh client. The
  /// interceptor does this on its own; this is for the app (phase 3) when it
  /// restores a session whose access token has already expired.
  Future<bool> refreshSession() => session.refresh(_authDio);

  @override
  ServerType get serverType => ServerType.silo;

  @override
  String get baseUrl => _baseUrl;

  @override
  set baseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
    _authDio.options.baseUrl = url;
  }

  /// The account's current access token. Setting it from outside (the
  /// generic sign-in path) keeps the refresh token when the value matches the
  /// session's pair; restore a full pair with [SiloSession.setTokens].
  @override
  String? get accessToken => session.accessToken;

  @override
  set accessToken(String? token) => session.setAccessToken(token);

  @override
  String? get userId => _userId;

  @override
  set userId(String? id) => _userId = id;

  @override
  late final AuthApi authApi = SiloAuthApi(_dio, _authDio, session);

  @override
  late final UsersApi usersApi = SiloUsersApi(
    _dio,
    profilesApi,
    () => _profileId,
    images: images,
    onConfigurationUpdated: () => userViewsApi.invalidateCache(),
  );

  /// The artwork URLs seen in Silo's answers, by item and image type (see
  /// [SiloImageRegistry]); [imageApi] answers from it.
  late final SiloImageRegistry images = SiloImageRegistry(() => _baseUrl);

  /// Resolves the placeholder URLs [imageApi] hands out for items not read
  /// yet, by loading them (step 6.3).
  late final SiloImageResolver imageResolver = SiloImageResolver(
    registry: images,
    baseUrl: () => _baseUrl,
    load: _loadArtwork,
  );

  /// Reads what Silo has on [id] so its artwork is registered: a catalog
  /// item by its content id; otherwise a library, a profile (avatars) or a
  /// person, which have plain ids.
  Future<void> _loadArtwork(String id) async {
    if (parseSiloCollectionId(id) != null) {
      // A collection's artwork comes with its list (6.15).
      await itemsApi.getItem(id);
      return;
    }
    if (siloTypeOfId(id) != null) {
      final response = await _dio.get<dynamic>(
        '/api/v2/catalog/items/${Uri.encodeComponent(id)}',
        queryParameters: {'image_size': 'large'},
      );
      final item = asJsonMap(response.data);
      if (item != null) siloItemToBaseItemDto(item, images: images);
      return;
    }
    final libraries = await _dio.get<dynamic>('/api/v2/user/libraries');
    final libraryItems = asJsonMap(libraries.data)?['items'];
    if (libraryItems is List) {
      siloLibrariesToUserViews(
        libraryItems,
        images: images,
        supported: siloCollectionTypes.keys.toSet(),
      );
    }
    if (images.knows(id)) return;
    if (id.contains('-')) {
      // Profile ids are UUIDs; person and library ids are numbers.
      for (final profile in await profilesApi.list()) {
        images.note(profile.id);
        images.register(
          profile.id,
          SiloImageType.primary,
          profile.json['avatar_url'] as String?,
        );
      }
      return;
    }
    final person = await _dio.get<dynamic>(
      '/api/v2/catalog/people/${Uri.encodeComponent(id)}',
    );
    final json = asJsonMap(person.data);
    if (json != null) {
      images.note(id);
      images.register(id, SiloImageType.primary, json['photo_url'] as String?);
    }
  }

  @override
  late final SystemApi systemApi = SiloSystemApi(_dio);

  /// Silo's household profiles (no Moonfin interface; see [SiloProfilesApi]).
  late final SiloProfilesApi profilesApi = SiloProfilesApi(_dio);

  /// The signed-in account's own password (no Moonfin interface; see
  /// [SiloAccountApi]).
  late final SiloAccountApi accountApi = SiloAccountApi(_dio);

  /// Silo's image endpoints: the size buckets (no Moonfin interface; see
  /// [SiloImagesApi]).
  late final SiloImagesApi imagesApi = SiloImagesApi(_dio);

  /// Finds the account's main profile and acts as it from now on: every
  /// request carries its `X-Profile-Id` (decision D9). Silo keeps progress,
  /// favourites and home rows per profile, and refuses some requests without
  /// the header once a profile on the account has a PIN or restrictions.
  ///
  /// Throws [SiloMainProfileLockedError] when the main profile has a PIN; the
  /// client is then left without a profile.
  Future<SiloProfile> useMainProfile() async {
    // List without a profile: a stale id (say, a profile deleted on the web)
    // would get the listing itself refused.
    profileId = null;
    profileToken = null;
    final main = await profilesApi.mainProfile();
    profileId = main.id;
    return main;
  }

  @override
  late final SiloItemsApi itemsApi = SiloItemsApi(
    _dio,
    images: images,
    userViews: () => userViewsApi,
  );

  @override
  late final SiloUserViewsApi userViewsApi = SiloUserViewsApi(
    _dio,
    usersApi: () => usersApi,
    images: images,
  );

  @override
  late final UserLibraryApi userLibraryApi = SiloUserLibraryApi(itemsApi);

  @override
  final DisplayPreferencesApi displayPreferencesApi =
      const SiloPendingDisplayPreferencesApi();

  @override
  final PlaybackApi playbackApi = const SiloPendingPlaybackApi();

  @override
  final SessionApi sessionApi = const SiloPendingSessionApi();

  @override
  late final ImageApi imageApi = SiloImageApi(images, baseUrl: () => _baseUrl);

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
    SiloImageResolution.unregister(imageResolver);
    _dio.close();
    _authDio.close();
  }
}
