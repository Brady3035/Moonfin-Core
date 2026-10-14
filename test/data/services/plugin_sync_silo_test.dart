import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockSessionRepository extends Mock implements SessionRepository {}

/// Answers the plugin ping as installed and records every request.
class _RecordingAdapter implements HttpClientAdapter {
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.uri}');
    if (options.uri.path.endsWith('/Moonfin/Ping')) {
      return ResponseBody.fromString(
        jsonEncode({'installed': true, 'settingsSyncEnabled': true}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

_MockClient _client(ServerType type, String baseUrl) {
  final client = _MockClient();
  when(() => client.baseUrl).thenReturn(baseUrl);
  when(() => client.accessToken).thenReturn('token');
  when(() => client.serverType).thenReturn(type);
  when(() => client.deviceInfo).thenReturn(
    const DeviceInfo(
      id: 'dev1',
      name: 'test',
      appName: 'moonfin',
      appVersion: '0.0.0',
    ),
  );
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAdapter adapter;
  late PluginSyncService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);
    final session = _MockSessionRepository();
    when(() => session.activeUserId).thenReturn('user1');
    GetIt.instance.registerSingleton<SeerrPreferences>(
      SeerrPreferences(store, session),
    );

    adapter = _RecordingAdapter();
    service = PluginSyncService(
      prefs,
      store,
      dio: Dio()..httpClientAdapter = adapter,
    );
  });

  tearDown(() => GetIt.instance.reset());

  test('a Silo server is never pinged and reads as having no plugin', () async {
    final silo = _client(ServerType.silo, 'https://silo.example');
    expect(await service.refreshAvailability(silo), isFalse);
    expect(service.pluginAvailable, isFalse);
    expect(adapter.requests, isEmpty);
  });

  test('signing in to Silo after a server with the plugin sends nothing '
      'to the plugin', () async {
    // A Jellyfin session with the plugin leaves it marked available.
    final jellyfin = _client(ServerType.jellyfin, 'https://jf.example');
    expect(await service.refreshAvailability(jellyfin), isTrue);
    expect(service.pluginAvailable, isTrue);
    adapter.requests.clear();

    final silo = _client(ServerType.silo, 'https://silo.example');
    await service.syncOnLogin(silo, serverId: 'silo-1');
    await service.pushNotificationPrefs(silo);

    expect(service.pluginAvailable, isFalse);
    expect(
      adapter.requests.where((r) => r.contains('/Moonfin/')),
      isEmpty,
      reason: 'Silo has no Moonfin plugin',
    );
  });

  test('Jellyfin still pings the plugin', () async {
    final jellyfin = _client(ServerType.jellyfin, 'https://jf.example');
    expect(await service.refreshAvailability(jellyfin), isTrue);
    expect(adapter.requests, contains('GET https://jf.example/Moonfin/Ping'));
  });
}
