import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

void main() {
  group('configureServerDio', () {
    late HttpServer server;
    StreamSubscription<HttpRequest>? requests;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      await requests?.cancel();
      await server.close(force: true);
      // The version is process-wide, so clear it to keep tests independent.
      setServerUserAgentVersion('');
    });

    // Answers one request and reports the user agent it arrived with.
    Future<String?> userAgentOfNextRequest() async {
      final received = Completer<String?>();
      requests = server.listen((request) async {
        if (!received.isCompleted) {
          received.complete(request.headers.value(HttpHeaders.userAgentHeader));
        }
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });

      final dio = Dio();
      configureServerDio(dio);

      try {
        await dio.get<void>('http://127.0.0.1:${server.port}/');
        return await received.future;
      } finally {
        dio.close(force: true);
      }
    }

    test('uses a browser-compatible Moonfin user agent', () async {
      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/Flutter)',
      );
    });

    test('includes the app version once startup records it', () async {
      setServerUserAgentVersion('2.3.2');

      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/2.3.2)',
      );
    });

    test('truncates at anything that would break the header', () async {
      setServerUserAgentVersion('2.3.2 (beta)\r\nX-Injected: 1');

      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/2.3.2)',
      );
    });

    test('falls back to an unversioned agent for a blank version', () async {
      setServerUserAgentVersion('   ');

      expect(
        await userAgentOfNextRequest(),
        'Mozilla/5.0 (compatible; Moonfin/Flutter)',
      );
    });
  });

  // Reaching the host is the part that has to fail fast. The caller's timeout
  // can't do that job, since it also covers queueing for a free slot.
  group('configureServerDio socket timeout', () {
    Duration socketTimeoutFor(Duration? dioTimeout) {
      final dio = Dio(BaseOptions(connectTimeout: dioTimeout));
      configureServerDio(dio);
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      return adapter.createHttpClient!().connectionTimeout!;
    }

    test('stays short whatever the caller allows for queueing', () {
      const short = Duration(seconds: 10);
      expect(socketTimeoutFor(const Duration(seconds: 30)), short);
      expect(socketTimeoutFor(const Duration(minutes: 3)), short);
      expect(socketTimeoutFor(null), short);
    });
  });

  // Waiting for one of the fifteen per host slots is ordinary queueing, but Dio
  // counts it against its connect timeout and calls it a connection timeout. A
  // screen that asks for more at once than the pool holds then fails on a link
  // where each request keeps its slot long enough for a queue to build.
  group('a full connection pool', () {
    late HttpServer server;
    const slowResponse = Duration(milliseconds: 300);
    const moreRequestsThanSlots = 60;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await Future<void>.delayed(slowResponse);
        request.response.statusCode = 200;
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<List<Object?>> fireConcurrently(Duration connectTimeout) {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://${server.address.address}:${server.port}',
          connectTimeout: connectTimeout,
          validateStatus: (_) => true,
        ),
      );
      configureServerDio(dio);
      return Future.wait(
        List.generate(
          moreRequestsThanSlots,
          (i) => dio
              .get<void>('/$i')
              .then<Object?>((r) => r)
              .catchError((Object e) => e),
        ),
      );
    }

    test('queues rather than failing when the caller allows for it', () async {
      final results = await fireConcurrently(const Duration(seconds: 30));
      expect(results.whereType<DioException>(), isEmpty);
    });

    test('is what a short connect timeout cuts off', () async {
      final results = await fireConcurrently(const Duration(milliseconds: 400));
      final timedOut = results
          .whereType<DioException>()
          .where((e) => e.type == DioExceptionType.connectionTimeout);
      expect(timedOut, isNotEmpty);
    });
  });
}
