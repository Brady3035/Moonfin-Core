import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/util/signed_in_server_features.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('anyServerTypeSupports', () {
    bool liveTv(Iterable<ServerType> types) =>
        anyServerTypeSupports(types, (f) => f.supportsLiveTv);

    test('no servers hides nothing', () {
      expect(liveTv(const []), isTrue);
    });

    test('Silo alone lacks Live TV', () {
      expect(liveTv(const [ServerType.silo]), isFalse);
    });

    test('any Jellyfin or Emby server brings it back', () {
      expect(liveTv(const [ServerType.silo, ServerType.emby]), isTrue);
      expect(liveTv(const [ServerType.jellyfin]), isTrue);
    });
  });

  group('liveTvOnAnySignedInServer', () {
    late AuthenticationStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = AuthenticationStore();
      await store.init();
    });

    Future<void> addServer(
      String id,
      ServerType type, {
      bool signedIn = true,
    }) async {
      await store.putServer(
        Server(
          id: id,
          name: id,
          address: 'https://$id.example',
          version: '1',
          serverType: type,
          dateAdded: DateTime.utc(2026, 10, 14),
        ),
      );
      if (signedIn) {
        await store.putUser(
          PrivateUser(
            id: 'user-$id',
            name: 'Brady',
            serverId: id,
            accessToken: 'token',
            lastUsed: DateTime.utc(2026, 10, 14),
          ),
        );
      }
    }

    test('only Silo signed in: off', () async {
      await addServer('silo', ServerType.silo);

      expect(liveTvOnAnySignedInServer(store: store), isFalse);
    });

    test('Silo and Emby signed in: on', () async {
      await addServer('silo', ServerType.silo);
      await addServer('emby', ServerType.emby);

      expect(liveTvOnAnySignedInServer(store: store), isTrue);
    });

    test('a server nobody is signed in to does not count', () async {
      await addServer('silo', ServerType.silo);
      await addServer('emby', ServerType.emby, signedIn: false);

      expect(liveTvOnAnySignedInServer(store: store), isFalse);
    });

    test('nobody signed in anywhere: on', () async {
      await addServer('silo', ServerType.silo, signedIn: false);

      expect(liveTvOnAnySignedInServer(store: store), isTrue);
    });
  });
}
