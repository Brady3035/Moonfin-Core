import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../../auth/services/silo_token_storage.dart';

/// Where a server's Moonbase routes start, and the headers that sign a
/// request to them. Append `/Moonfin/...` to [base].
typedef MoonbaseEndpoint = ({String base, Map<String, String> headers});

/// The plugin id Moonbase for Silo installs under.
const siloMoonbasePluginId = 'moonfin.moonbase';

/// Silo installation ids of Moonbase, by server base URL, and when a server
/// last answered that it has none, which holds until [_missingRetry] passes.
final Map<String, String> _siloInstallations = {};
final Map<String, DateTime> _siloMissingAt = {};
const _missingRetry = Duration(minutes: 5);

/// The Moonbase endpoint for [client], or null when there is none to call.
///
/// Jellyfin and Emby serve Moonbase at the server root and take the
/// MediaBrowser token. Silo serves a plugin under its installation id
/// (`/api/v2/plugin-content/plugins/<id>`), found through
/// `GET /api/v2/settings/plugins`, and takes Silo's own headers: the bearer
/// token and the profile with its PIN proof.
Future<MoonbaseEndpoint?> moonbaseEndpoint(
  MediaServerClient client,
  Dio dio,
) async {
  final features = FeatureDetector(
    serverType: client.serverType,
    serverVersion: '',
  );
  if (!features.supportsMoonfinPlugin) return null;
  final silo = siloClientOf(client);
  if (client.serverType == ServerType.silo && silo == null) return null;
  if (silo == null) {
    final token = client.accessToken;
    if (token == null || token.isEmpty) return null;
    return (
      base: client.baseUrl,
      headers: {
        'Authorization': buildServerAuthorizationHeader(
          scheme: 'MediaBrowser',
          deviceInfo: client.deviceInfo,
          accessToken: token,
        ),
      },
    );
  }

  // These requests go out on Moonfin's own Dio, past the Silo client's
  // refresh interceptor, so an expiring token is refreshed here first.
  if (silo.session.needsRefresh) await silo.refreshSession();
  final token = silo.accessToken;
  if (token == null || token.isEmpty) return null;
  final headers = silo.requestHeaders;

  final base = silo.baseUrl;
  String? id = _siloInstallations[base];
  if (id == null) {
    final missingAt = _siloMissingAt[base];
    if (missingAt != null &&
        DateTime.now().difference(missingAt) < _missingRetry) {
      return null;
    }
    try {
      id = await _findSiloInstallation(dio, base, headers);
    } catch (_) {
      // Unreachable is not the same as not installed: ask again next time.
      return null;
    }
    if (id == null) {
      _siloMissingAt[base] = DateTime.now();
      return null;
    }
    _siloInstallations[base] = id;
    _siloMissingAt.remove(base);
  }
  return (base: '$base/api/v2/plugin-content/plugins/$id', headers: headers);
}

/// Whether [client]'s server is Silo and recently answered that it has no
/// Moonbase installed. A server that couldn't be reached doesn't count.
bool moonbaseKnownMissing(MediaServerClient client) {
  final missingAt = _siloMissingAt[client.baseUrl];
  return missingAt != null &&
      DateTime.now().difference(missingAt) < _missingRetry;
}

/// Forgets where Moonbase was on [client]'s server, so the next call looks it
/// up again. For when its routes answer 404: the plugin was removed or
/// reinstalled under a new id.
void forgetMoonbaseEndpoint(MediaServerClient client) {
  _siloInstallations.remove(client.baseUrl);
  _siloMissingAt.remove(client.baseUrl);
}

Future<String?> _findSiloInstallation(
  Dio dio,
  String base,
  Map<String, String> headers,
) async {
  final response = await dio.get(
    '$base/api/v2/settings/plugins',
    options: Options(headers: headers),
  );
  final data = response.data;
  final items = data is Map ? data['items'] : null;
  if (items is! List) return null;
  for (final item in items) {
    if (item is Map && item['plugin_id'] == siloMoonbasePluginId) {
      final id = item['id'];
      if (id != null && '$id'.isNotEmpty) return '$id';
    }
  }
  return null;
}
