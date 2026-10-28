import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/moonbase_endpoint.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:server_silo/server_silo.dart';

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'Moonfin',
  appVersion: '1.0.0',
);

/// Answers Silo's plugin listing with [plugins], counting the calls.
class _PluginList implements HttpClientAdapter {
  _PluginList(this.plugins);

  List<Map<String, Object>> plugins;
  int calls = 0;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path != '/api/v2/settings/plugins') {
      return ResponseBody.fromString('', 404);
    }
    calls++;
    last = options;
    return ResponseBody.fromString(
      jsonEncode({'items': plugins}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

SiloMediaServerClient _silo(String baseUrl) {
  final now = DateTime.now().toUtc();
  return SiloMediaServerClient(baseUrl: baseUrl, deviceInfo: _device)
    ..session.setTokens(
      SiloTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: now.add(const Duration(hours: 1)),
        lifetime: const Duration(hours: 1),
      ),
    )
    ..profileId = '7'
    ..profileToken = 'pin-proof';
}

Dio _dio(_PluginList server) => Dio()..httpClientAdapter = server;

void main() {
  test('Jellyfin serves Moonbase at its root with the MediaBrowser token',
      () async {
    final client = JellyfinMediaServerClient(
      baseUrl: 'https://jf.example',
      deviceInfo: _device,
    )..accessToken = 'token';
    final server = _PluginList(const []);

    final ep = await moonbaseEndpoint(client, _dio(server));

    expect(ep!.base, 'https://jf.example');
    expect(ep.headers['Authorization'], startsWith('MediaBrowser '));
    expect(server.calls, 0);
  });

  test('Silo finds Moonbase by plugin id and signs as the profile', () async {
    final client = _silo('https://silo-found.example');
    final server = _PluginList([
      {'id': '3', 'plugin_id': 'org.example.other'},
      {'id': '12', 'plugin_id': siloMoonbasePluginId},
    ]);

    final ep = await moonbaseEndpoint(client, _dio(server));

    expect(
      ep!.base,
      'https://silo-found.example/api/v2/plugin-content/plugins/12',
    );
    expect(ep.headers['Authorization'], 'Bearer access');
    expect(ep.headers['X-Profile-Id'], '7');
    expect(ep.headers['X-Profile-Token'], 'pin-proof');
    expect(server.last!.headers['Authorization'], 'Bearer access');

    // The id is kept, until a 404 says to look again.
    await moonbaseEndpoint(client, _dio(server));
    expect(server.calls, 1);
    forgetMoonbaseEndpoint(client);
    server.plugins = [
      {'id': '13', 'plugin_id': siloMoonbasePluginId},
    ];
    final again = await moonbaseEndpoint(client, _dio(server));
    expect(again!.base, endsWith('/plugins/13'));
    expect(server.calls, 2);
  });

  test('a Silo without Moonbase is not asked again straight away', () async {
    final client = _silo('https://silo-missing.example');
    final server = _PluginList(const []);

    expect(await moonbaseEndpoint(client, _dio(server)), isNull);
    expect(await moonbaseEndpoint(client, _dio(server)), isNull);
    expect(server.calls, 1);
  });
}
