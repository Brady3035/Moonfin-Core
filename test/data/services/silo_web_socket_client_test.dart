import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';

void main() {
  test('a Silo server gets the idle socket, which stays quiet', () async {
    final client = SiloMediaServerClient(
      baseUrl: 'https://silo.example',
      deviceInfo: const DeviceInfo(
        id: 'device',
        name: 'Device',
        appName: 'Moonfin',
        appVersion: '1.0.0',
      ),
    );
    final socket = ServerWebSocketClient.forServer(client);
    expect(socket, isA<SiloWebSocketClient>());

    var messages = 0;
    var connections = 0;
    final subs = [
      socket.messages.listen((_) => messages++),
      socket.connections.listen((_) => connections++),
    ];
    await socket.connect();
    socket.retryNow();
    await socket.disconnect();
    await Future<void>.delayed(Duration.zero);
    expect(messages, 0);
    expect(connections, 0);

    for (final s in subs) {
      await s.cancel();
    }
    socket.dispose();
    client.dispose();
  });
}
