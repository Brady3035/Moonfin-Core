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
