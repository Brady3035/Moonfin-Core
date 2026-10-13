import 'package:server_core/server_core.dart';

/// Thrown by a Silo API that Moonfin doesn't implement yet.
///
/// Every placeholder class in this file names the roadmap step that replaces
/// it (docs/silo/ROADMAP.md) and is deleted when that step lands. They let the
/// Silo client be built and wired into the app before every API is
/// translated, and turn a call that comes too early into a readable error
/// instead of a crash.
class SiloNotImplementedError extends UnimplementedError {
  /// The Moonfin API class that was called, e.g. `ItemsApi`.
  final String api;

  /// The method or getter that was called.
  final String member;

  /// The roadmap step that implements it, e.g. `6.5`.
  final String step;

  SiloNotImplementedError(this.api, this.member, this.step)
    : super('Silo $api.$member is not implemented yet (roadmap step $step)');
}

/// Answers every member of the interface it implements by throwing
/// [SiloNotImplementedError], so a placeholder doesn't have to spell out each
/// method of a 40-method interface.
abstract class _Pending {
  const _Pending(this._api, this._step);

  final String _api;
  final String _step;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName
        .toString()
        .replaceFirst('Symbol("', '')
        .replaceFirst('")', '')
        .replaceFirst('=', '');
    throw SiloNotImplementedError(_api, name, _step);
  }
}

class SiloPendingAuthApi extends _Pending implements AuthApi {
  const SiloPendingAuthApi() : super('AuthApi', '2.3');
}

class SiloPendingUsersApi extends _Pending implements UsersApi {
  const SiloPendingUsersApi() : super('UsersApi', '2.7');
}

class SiloPendingSystemApi extends _Pending implements SystemApi {
  const SiloPendingSystemApi() : super('SystemApi', '1.6');
}

class SiloPendingItemsApi extends _Pending implements ItemsApi {
  const SiloPendingItemsApi() : super('ItemsApi', '6.5');
}

class SiloPendingUserViewsApi extends _Pending implements UserViewsApi {
  const SiloPendingUserViewsApi() : super('UserViewsApi', '6.4');
}

class SiloPendingUserLibraryApi extends _Pending implements UserLibraryApi {
  const SiloPendingUserLibraryApi() : super('UserLibraryApi', '6.6 and 9.x');
}

class SiloPendingDisplayPreferencesApi extends _Pending
    implements DisplayPreferencesApi {
  const SiloPendingDisplayPreferencesApi()
    : super('DisplayPreferencesApi', '6.19');
}

class SiloPendingPlaybackApi extends _Pending implements PlaybackApi {
  const SiloPendingPlaybackApi() : super('PlaybackApi', '6.18 and 10.6');
}

class SiloPendingSessionApi extends _Pending implements SessionApi {
  const SiloPendingSessionApi() : super('SessionApi', 'phase 3 and 13.6');
}

/// Image URLs are built synchronously while widgets render, so this
/// placeholder answers with no URL (the UI shows its placeholder art) instead
/// of throwing. Replaced by the image registry in step 6.1.
class SiloPendingImageApi implements ImageApi {
  const SiloPendingImageApi();

  @override
  String getPrimaryImageUrl(
    String itemId, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  }) => '';

  @override
  String getBackdropImageUrl(
    String itemId, {
    int? maxWidth,
    int? index,
    String? tag,
  }) => '';

  @override
  String getLogoImageUrl(String itemId, {int? maxWidth, String? tag}) => '';

  @override
  String getBannerImageUrl(String itemId, {int? maxWidth, String? tag}) => '';

  @override
  String getThumbImageUrl(String itemId, {int? maxWidth, String? tag}) => '';

  @override
  String getChapterImageUrl(
    String itemId, {
    required int index,
    int? maxWidth,
    String? tag,
  }) => '';

  @override
  String getUserImageUrl(String userId) => '';

  @override
  String getTrickplayTileImageUrl(
    String itemId, {
    required int width,
    required int index,
    String? mediaSourceId,
  }) => '';
}
