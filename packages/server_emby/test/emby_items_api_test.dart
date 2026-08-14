import 'package:dio/dio.dart';
import 'package:server_emby/src/api/emby_items_api.dart';
import 'package:test/test.dart';

class _FakeServer extends Interceptor {
  _FakeServer(this.handle);

  final void Function(RequestOptions options, RequestInterceptorHandler handler)
  handle;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handle(options, handler);
}

(Dio, RequestOptions? Function()) _recordingDio() {
  RequestOptions? request;
  final dio = Dio()
    ..interceptors.add(
      _FakeServer((options, handler) {
        request = options;
        handler.resolve(
          Response(requestOptions: options, data: <String, dynamic>{}),
        );
      }),
    );
  return (dio, () => request);
}

void main() {
  test('genres drop the ItemCounts field Emby has no name for', () async {
    final (dio, request) = _recordingDio();

    await EmbyItemsApi(dio, () => 'user-1').getGenres(
      fields: 'ItemCounts,PrimaryImageAspectRatio',
      recursive: true,
    );

    expect(request()?.path, '/Genres');
    expect(request()?.queryParameters['Fields'], 'PrimaryImageAspectRatio');
  });

  test('studios drop ItemCounts too', () async {
    final (dio, request) = _recordingDio();

    await EmbyItemsApi(
      dio,
      () => 'user-1',
    ).getStudios(fields: 'ChildCount,ItemCounts,PrimaryImageTag');

    expect(request()?.queryParameters['Fields'], 'ChildCount,PrimaryImageTag');
  });

  test('a request asking only for it sends no Fields at all', () async {
    final (dio, request) = _recordingDio();

    await EmbyItemsApi(dio, () => 'user-1').getGenres(fields: 'ItemCounts');

    expect(request()?.queryParameters.containsKey('Fields'), isFalse);
  });

  test('fields Emby does know are passed through untouched', () async {
    final (dio, request) = _recordingDio();

    await EmbyItemsApi(
      dio,
      () => 'user-1',
    ).getGenres(fields: 'PrimaryImageTag,ImageTags');

    expect(request()?.queryParameters['Fields'], 'PrimaryImageTag,ImageTags');
  });
}
