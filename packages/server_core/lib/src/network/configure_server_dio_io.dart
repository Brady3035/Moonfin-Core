import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'server_user_agent.dart';

/// How long one socket may spend reaching the host.
///
/// Not tied to the caller's timeout. Dio bills the wait for a free slot in the
/// pool below to its own connect timeout, and queueing isn't a connection
/// problem, so the caller's has to be generous. Reaching a host either happens
/// quickly or isn't going to, and giving up here first hands the slot back.
const _socketConnectTimeout = Duration(seconds: 10);

void configureServerDio(Dio dio) {
  dio.transformer = FusedTransformer(contentLengthIsolateThreshold: 50 * 1024);

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();

      client.userAgent = serverUserAgent;

      client.badCertificateCallback = (_, _, _) => true;

      client.connectionTimeout = _socketConnectTimeout;
      client.idleTimeout = const Duration(seconds: 120);

      client.maxConnectionsPerHost = 15;

      return client;
    },
  );
}
