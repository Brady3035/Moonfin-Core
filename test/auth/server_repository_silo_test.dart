import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:server_core/server_core.dart';

class _AuthStore extends Fake implements AuthenticationStore {
  @override
  Future<void> putServer(Server server) async {}
}

class _ClientFactory extends Fake implements MediaServerClientFactory {}

void main() {
  // No TestWidgetsFlutterBinding: these tests talk to a real local server.
  late HttpServer server;
  late Map<String, Object> routes;

  setUp(() async {
    routes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = routes[request.uri.path];
      if (body == null) {
        // The native Silo host and many proxies answer anything else with
        // the web app's HTML.
        request.response
          ..headers.contentType = ContentType.html
          ..write('<!doctype html><html></html>');
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body));
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  ServerRepository repo() => ServerRepository(_AuthStore(), _ClientFactory());
  String address() => 'http://127.0.0.1:${server.port}';

  test('adding a Silo address saves a Silo server', () async {
    routes = {
      '/api/v2/system/info': {
        'server_version': '4b2e921c+dirty',
        'api_major': 2,
      },
      '/api/v2/system/identity': {
        'server_id': '7b72fbd5-e741-48f0-9d05-b438990f3a7e',
      },
      '/api/v2/theme/branding': {
        'server_name': 'Silo',
        'login_subtitle': 'Sign in with an existing account.',
      },
      '/api/v2/system/setup': {'needs_setup': false, 'wizard_completed': true},
    };

    final added = await repo().addServer(address());

    expect(added, isNotNull);
    expect(added!.serverType, ServerType.silo);
    expect(added.name, 'Silo');
    expect(added.version, '4b2e921c+dirty');
    expect(added.address, address());
    expect(added.loginDisclaimer, 'Sign in with an existing account.');
    expect(added.setupCompleted, isTrue);
  });
}
