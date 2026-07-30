import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/seerr_download_progress.dart';
import 'package:moonfin/data/viewmodels/seerr_media_detail_view_model.dart';

SeerrRequest _request({
  required int id,
  required int status,
  bool is4k = false,
  List<int> seasons = const [],
}) =>
    SeerrRequest(
      id: id,
      status: status,
      type: 'movie',
      is4k: is4k,
      seasons: seasons.isEmpty
          ? null
          : [
              for (final n in seasons)
                SeerrSeasonRequest(id: n, seasonNumber: n, status: 1),
            ],
    );

void main() {
  group('SeerrQualityStatus', () {
    test('routes status and status4k to their own tracks', () {
      const info = SeerrMediaInfo(status: 5, status4k: 1);
      final hd = SeerrQualityStatus.of(
        is4k: false,
        mediaInfo: info,
        canManageRequests: false,
      );
      final uhd = SeerrQualityStatus.of(
        is4k: true,
        mediaInfo: info,
        canManageRequests: false,
      );

      expect(hd.isFullyAvailable, isTrue);
      expect(hd.hasAnyState, isTrue);
      expect(uhd.isFullyAvailable, isFalse);
      expect(uhd.hasAnyState, isFalse);
    });

    test('partitions requests by is4k so each track has its own slot', () {
      final info = SeerrMediaInfo(
        status: 2,
        status4k: 2,
        requests: [
          _request(id: 1, status: SeerrRequest.statusApproved),
          _request(id: 2, status: SeerrRequest.statusPending, is4k: true),
        ],
      );
      final hd = SeerrQualityStatus.of(
        is4k: false,
        mediaInfo: info,
        canManageRequests: true,
      );
      final uhd = SeerrQualityStatus.of(
        is4k: true,
        mediaInfo: info,
        canManageRequests: true,
      );

      expect(hd.activeRequests.map((r) => r.id), [1]);
      expect(uhd.activeRequests.map((r) => r.id), [2]);
      expect(hd.hasExistingRequest, isTrue);
      expect(uhd.hasExistingRequest, isTrue);
      expect(hd.cancelableRequests.map((r) => r.id), [1]);
      expect(uhd.cancelableRequests.map((r) => r.id), [2]);
    });

    test('requestedSeasons only counts the track\'s own flavor', () {
      final info = SeerrMediaInfo(
        requests: [
          _request(id: 1, status: SeerrRequest.statusApproved, seasons: [1, 2]),
          _request(
            id: 2,
            status: SeerrRequest.statusPending,
            is4k: true,
            seasons: [1],
          ),
        ],
      );
      final hd = SeerrQualityStatus.of(
        is4k: false,
        mediaInfo: info,
        canManageRequests: false,
      );
      final uhd = SeerrQualityStatus.of(
        is4k: true,
        mediaInfo: info,
        canManageRequests: false,
      );

      expect(hd.requestedSeasons, {1, 2});
      expect(uhd.requestedSeasons, {1});
    });

    test('declined and failed requests are not active and free their seasons',
        () {
      final info = SeerrMediaInfo(
        requests: [
          _request(id: 1, status: SeerrRequest.statusDeclined, seasons: [1]),
          _request(id: 2, status: SeerrRequest.statusFailed, seasons: [2]),
          _request(id: 3, status: SeerrRequest.statusCompleted, seasons: [3]),
        ],
      );
      final hd = SeerrQualityStatus.of(
        is4k: false,
        mediaInfo: info,
        canManageRequests: true,
      );

      expect(hd.activeRequests, isEmpty);
      expect(hd.hasExistingRequest, isFalse);
      // Completed requests still hold their seasons, declined/failed do not.
      expect(hd.requestedSeasons, {3});
    });

    test('cancelableRequests is empty without manage permission', () {
      final info = SeerrMediaInfo(
        requests: [_request(id: 1, status: SeerrRequest.statusPending)],
      );
      final hd = SeerrQualityStatus.of(
        is4k: false,
        mediaInfo: info,
        canManageRequests: false,
      );

      expect(hd.activeRequests, hasLength(1));
      expect(hd.cancelableRequests, isEmpty);
    });

    test('null mediaInfo yields an inert track', () {
      final uhd = SeerrQualityStatus.of(
        is4k: true,
        mediaInfo: null,
        canManageRequests: false,
      );

      expect(uhd.status, 0);
      expect(uhd.hasAnyState, isFalse);
      expect(uhd.hasExistingRequest, isFalse);
      expect(uhd.requestedSeasons, isEmpty);
      expect(uhd.download, isNull);
    });

    test('download routes the flavor\'s own status and queue items', () {
      const item = SeerrDownloadingItem(size: 100, sizeLeft: 50);
      const info = SeerrMediaInfo(
        status: 5,
        status4k: 3,
        downloadStatus4k: [item],
      );
      final hd = SeerrQualityStatus.of(
        is4k: false,
        mediaInfo: info,
        canManageRequests: false,
      );
      final uhd = SeerrQualityStatus.of(
        is4k: true,
        mediaInfo: info,
        canManageRequests: false,
      );

      expect(hd.download, isNull);
      expect(uhd.download, isA<SeerrDownloadSummary>());
    });
  });

  group('SeerrMediaDetailState', () {
    test('a title with no 4K backend keeps the 4K track inert', () {
      final info = SeerrMediaInfo(
        status: 4,
        status4k: 1,
        requests: [_request(id: 1, status: SeerrRequest.statusApproved)],
      );
      final state = SeerrMediaDetailState(
        movie: SeerrMovieDetails(id: 1, title: 't', mediaInfo: info),
      );

      expect(state.hd.isPartiallyAvailable, isTrue);
      expect(state.hd.hasExistingRequest, isTrue);
      expect(state.uhd.hasExistingRequest, isFalse);
      expect(state.uhd.hasAnyState, isFalse);
      expect(state.allActiveRequests, hasLength(1));
      expect(state.isAvailableAnyQuality, isTrue);
    });

    test('isAvailableAnyQuality covers a title available only in 4K', () {
      const state = SeerrMediaDetailState();
      expect(state.isAvailableAnyQuality, isFalse);

      const info = SeerrMediaInfo(status: 1, status4k: 5);
      final state4k = SeerrMediaDetailState(
        movie: SeerrMovieDetails(id: 1, title: 't', mediaInfo: info),
      );
      expect(state4k.hd.isAvailable, isFalse);
      expect(state4k.isAvailableAnyQuality, isTrue);
    });
  });
}
