import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_marker_mapper.dart';

/// Silo's skip markers (intro, credits, recap, preview) as Moonfin's media
/// segments (step 11.1).
///
/// Silo keeps markers per **file**: `GET /markers/files/{file_id}` answers
/// one file, `GET /markers/items/{item_id}` the first file of an item the
/// profile may play. A film with two versions can have different markers
/// on each, so the segments come from the file that plays: the resolver
/// tells this class which one it started ([notePlayingFile]), and an item
/// with no file noted (its segments asked for before it plays) is read by
/// its id.
///
/// Answers are kept for [ttl] per file, since the player asks again for
/// each item of a queue and on each return to it; an edit in Silo's web app
/// shows on the next play after that.
class SiloMarkers {
  SiloMarkers(this._dio, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _clock;

  static const ttl = Duration(minutes: 5);

  /// The file each item plays (or last played) in this session.
  final _playing = <String, ({String fileId, num? runTimeSeconds})>{};

  final _cache =
      <String, ({DateTime at, Future<List<Map<String, dynamic>>> segments})>{};

  /// Called by the resolver when [itemId] starts playing [fileId] (the
  /// plan's effective file), with its length when known, which a credits
  /// marker without an end runs to.
  void notePlayingFile(String itemId, String fileId, {num? runTimeSeconds}) {
    _playing[itemId] = (fileId: fileId, runTimeSeconds: runTimeSeconds);
  }

  /// The segments of [itemId]'s playing file, or of its first file. A file
  /// without markers, or one Silo doesn't know, has none.
  Future<List<Map<String, dynamic>>> segmentsOf(String itemId) {
    final playing = _playing[itemId];
    final key = playing == null ? 'item:$itemId' : 'file:${playing.fileId}';
    final now = _clock();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.at) < ttl) {
      return cached.segments;
    }
    final path = playing == null
        ? '/api/v2/markers/items/${Uri.encodeComponent(itemId)}'
        : '/api/v2/markers/files/${Uri.encodeComponent(playing.fileId)}';
    final segments = _read(path, itemId, playing?.runTimeSeconds);
    _cache[key] = (at: now, segments: segments);
    // A failed read is not kept: the next play asks again.
    segments.catchError((Object _) {
      if (identical(_cache[key]?.segments, segments)) _cache.remove(key);
      return const <Map<String, dynamic>>[];
    });
    return segments;
  }

  Future<List<Map<String, dynamic>>> _read(
    String path,
    String itemId,
    num? runTimeSeconds,
  ) async {
    try {
      final response = await _dio.get<dynamic>(path);
      final markers = asJsonMap(response.data);
      if (markers == null) return const [];
      return siloMarkersToMediaSegments(
        markers,
        itemId: itemId,
        runTimeSeconds: runTimeSeconds,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return const [];
      rethrow;
    }
  }
}
