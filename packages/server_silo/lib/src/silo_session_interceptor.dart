import 'package:dio/dio.dart';

import 'silo_session.dart';

/// Keeps a Silo session's access token fresh around every request.
///
/// Before a request it refreshes a token that is about to expire. When an
/// authenticated request comes back `401`, it refreshes once and replays that
/// request once. Requests flagged [siloNoRefreshExtra] (sign-in, refresh, PIN
/// checks, device sign-in) are never replayed.
///
/// Refreshes go out on [_authDio], a client without this interceptor: sending
/// them through [_dio] would re-enter this interceptor mid-request. Replays go
/// through [_dio] so they pick up the new token from the header interceptor.
class SiloSessionInterceptor extends Interceptor {
  SiloSessionInterceptor(this._dio, this._authDio, this._session);

  final Dio _dio;
  final Dio _authDio;
  final SiloSession _session;

  static const _retriedExtra = 'silo.retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final skip = options.extra[siloNoRefreshExtra] == true ||
        options.extra[siloNoAuthExtra] == true;
    if (!skip && _session.needsRefresh) {
      await _session.refresh(_authDio);
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final eligible = options.extra[siloNoRefreshExtra] != true &&
        options.extra[siloNoAuthExtra] != true &&
        options.extra[_retriedExtra] != true &&
        options.headers['Authorization'] != null &&
        _session.canRefresh &&
        isSiloRefreshableAuthError(err);
    if (!eligible) return handler.next(err);

    final sentToken = options.headers['Authorization'];
    // Another request may already have refreshed while this one was in flight.
    final alreadyFresh = _session.accessToken != null &&
        sentToken != 'Bearer ${_session.accessToken}';
    final refreshed = alreadyFresh || await _session.refresh(_authDio);
    if (!refreshed) return handler.next(err);

    try {
      options.extra[_retriedExtra] = true;
      options.headers.remove('Authorization');
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
