import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:server_core/server_core.dart';

class _FakeClient implements MediaServerClient {
  _FakeClient({this.baseUrl = 'http://server'});

  @override
  final String baseUrl;

  @override
  ServerType get serverType => ServerType.jellyfin;

  @override
  String? get accessToken => 'token';

  @override
  DeviceInfo get deviceInfo => const DeviceInfo(
    id: 'device 1',
    name: 'Device',
    appName: 'Moonfin',
    appVersion: '1.0.0',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSocket implements ServerWebSocketClient {
  final _messages = StreamController<ServerWebSocketMessage>.broadcast();
  final _connections = StreamController<void>.broadcast();

  int connectCalls = 0;
  int retryCalls = 0;
  bool disposed = false;

  @override
  Stream<ServerWebSocketMessage> get messages => _messages.stream;

  @override
  Stream<void> get connections => _connections.stream;

  @override
  Future<void> connect() async => connectCalls++;

  @override
  Future<void> disconnect() async {}

  @override
  void retryNow() => retryCalls++;

  final sent = <(String, Object?)>[];

  @override
  void send(String messageType, [Object? data]) =>
      sent.add((messageType, data));

  @override
  void dispose() {
    disposed = true;
    _messages.close();
    _connections.close();
  }

  void announceConnected() => _connections.add(null);
}

void main() {
  late _FakeSocket socket;
  late SocketHandler handler;

  setUp(() {
    socket = _FakeSocket();
    handler = SocketHandler(clientFactory: (_) => socket);
  });

  test('connecting opens the socket', () {
    handler.connectTo(_FakeClient());
    expect(socket.connectCalls, 1);
  });

  test('every open reaches the listeners, not just the first', () async {
    var opens = 0;
    handler.connectTo(_FakeClient());
    handler.connections.listen((_) => opens++);

    socket.announceConnected();
    socket.announceConnected();
    await Future<void>.delayed(Duration.zero);

    expect(opens, 2);
  });

  test('an immediate retry reaches the socket', () {
    handler.connectTo(_FakeClient());
    handler.retryNow();
    expect(socket.retryCalls, 1);
  });

  test('a retry with no socket does nothing rather than throwing', () {
    expect(handler.retryNow, returnsNormally);
  });

  test('disconnecting drops the socket and stops forwarding', () async {
    var opens = 0;
    handler.connectTo(_FakeClient());
    handler.connections.listen((_) => opens++);
    handler.disconnect();

    expect(socket.disposed, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(opens, 0);
  });

  test('a feed starts once and stops when its last holder lets go', () {
    handler.connectTo(_FakeClient());
    handler.subscribe('Sessions');
    handler.subscribe('Sessions');
    handler.unsubscribe('Sessions');
    expect(socket.sent, [('SessionsStart', '0,1000')]);

    handler.unsubscribe('Sessions');
    expect(socket.sent.last, ('SessionsStop', null));
  });

  test('held feeds are asked for again on every reconnect', () async {
    handler.connectTo(_FakeClient());
    handler.subscribe('ScheduledTasksInfo');
    socket.sent.clear();

    socket.announceConnected();
    await Future<void>.delayed(Duration.zero);

    expect(socket.sent, [('ScheduledTasksInfoStart', '0,1000')]);
  });

  test('a feed taken before connecting is sent once the socket opens', () async {
    handler.subscribe('Sessions');
    handler.connectTo(_FakeClient());
    socket.announceConnected();
    await Future<void>.delayed(Duration.zero);

    expect(socket.sent, [('SessionsStart', '0,1000')]);
  });

  test('a message sent while the socket is still opening is dropped', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <String>[];
    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((frame) =>
          received.add((jsonDecode('$frame') as Map)['MessageType'] as String));
    });
    final client = JellyfinWebSocketClient(
      _FakeClient(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    addTearDown(client.dispose);

    final opened = client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    client.send('SessionsStart', '0,1000');
    await opened;
    client.send('ScheduledTasksInfoStart', '0,1000');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(received, ['ScheduledTasksInfoStart']);
  });

  group('a server that accepts and never answers', () {
    late ServerSocket server;
    late List<Socket> accepted;

    setUp(() async {
      accepted = [];
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(accepted.add);
    });

    tearDown(() async {
      for (final socket in accepted) {
        socket.destroy();
      }
      await server.close();
    });

    JellyfinWebSocketClient buildClient() {
      final client = JellyfinWebSocketClient(
        _FakeClient(baseUrl: 'http://127.0.0.1:${server.port}'),
        connectTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(client.dispose);
      return client;
    }

    test('a stalled attempt is given up on and another follows', () async {
      unawaited(buildClient().connect());
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(
        accepted.length,
        greaterThan(1),
        reason:
            'one attempt that never answered used to stop the client for '
            'the life of the process',
      );
    });

    test('an immediate retry lands once a stalled attempt gave up', () async {
      final client = buildClient();
      unawaited(client.connect());
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final beforeRetry = accepted.length;

      client.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        accepted.length,
        greaterThan(beforeRetry),
        reason: 'a stale channel left behind reads as a live connection',
      );
    });
  });

  // Dart's Uri has no default port for ws and wss, so `wss://server/socket`
  // reported port 0, and dart:io connected to exactly that and failed with
  // "Can't assign requested address" for every server without a port in its
  // address.
  group('the socket address carries the port', () {
    test('Jellyfin', () {
      Uri uri(String baseUrl) =>
          JellyfinWebSocketClient(_FakeClient(baseUrl: baseUrl)).buildUri()!;

      expect(
        uri('https://jellyfin.example').toString(),
        'wss://jellyfin.example:443/socket?ApiKey=token',
      );
      expect(uri('http://jellyfin.example').port, 80);
      expect(uri('https://jellyfin.example:8920').port, 8920);
      expect(uri('https://example.com/jellyfin').path, '/jellyfin/socket');
    });

    test('Emby', () {
      Uri uri(String baseUrl) =>
          EmbyWebSocketClient(_FakeClient(baseUrl: baseUrl)).buildUri()!;

      final secure = uri('https://emby.example');
      expect(
        secure.toString(),
        'wss://emby.example:443/embywebsocket?api_key=token&deviceId=device%201',
      );
      expect(Uri.parse(secure.toString()).port, 443);
      expect(uri('http://emby.example:8096').port, 8096);
    });
  });
}
