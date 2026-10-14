import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

/// One Silo household profile, as `GET /profiles` lists it.
///
/// Only the fields Moonfin decides on are typed; [json] keeps the whole
/// profile for the user and settings mappers (steps 2.6 and 2.7).
class SiloProfile {
  const SiloProfile({
    required this.id,
    required this.name,
    required this.isPrimary,
    required this.hasPin,
    required this.isChild,
    this.json = const {},
  });

  factory SiloProfile.fromJson(Map<String, dynamic> json) => SiloProfile(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    isPrimary: json['is_primary'] == true,
    hasPin: json['has_pin'] == true,
    isChild: json['is_child'] == true,
    json: json,
  );

  final String id;
  final String name;

  /// The account's main profile: created with the account, and the one
  /// Moonfin acts as until the optional profiles phase (decision D9).
  final bool isPrimary;

  /// Locked with a PIN: requests acting as it need an `X-Profile-Token`
  /// from `verify-pin` (phase 18).
  final bool hasPin;

  final bool isChild;

  /// The profile exactly as Silo sent it.
  final Map<String, dynamic> json;
}

/// The account's main profile is PIN-locked, and PIN entry only arrives with
/// the optional profiles phase (step 18.4). The app explains it (step 3.7).
class SiloMainProfileLockedError implements Exception {
  const SiloMainProfileLockedError(this.profile);

  final SiloProfile profile;

  @override
  String toString() =>
      'The main Silo profile "${profile.name}" is locked with a PIN, which '
      'Moonfin does not support yet';
}

/// Silo's household profiles. Not a Moonfin interface: Jellyfin and Emby have
/// no equivalent, so only Silo-aware code (the app's Silo sign-in) uses it.
class SiloProfilesApi {
  SiloProfilesApi(this._dio);

  final Dio _dio;

  /// Every profile on the signed-in account, in Silo's order.
  Future<List<SiloProfile>> list() async {
    final response = await _dio.get<dynamic>('/api/v2/profiles');
    final items = asJsonMap(response.data)?['items'];
    if (items is! List) {
      throw FormatException(
        'Expected a profile list from Silo, got ${response.data.runtimeType}',
      );
    }
    return [
      for (final item in items)
        if (asJsonMap(item) case final json?) SiloProfile.fromJson(json),
    ].where((p) => p.id.isNotEmpty).toList();
  }

  /// The account's primary profile.
  ///
  /// Throws [SiloMainProfileLockedError] when it has a PIN, and a
  /// [StateError] when Silo lists no primary profile (every account has one,
  /// so that means a broken server answer).
  Future<SiloProfile> mainProfile() async {
    final profiles = await list();
    final main = profiles.where((p) => p.isPrimary).firstOrNull;
    if (main == null) {
      throw StateError(
        'Silo listed ${profiles.length} profile(s) for this account but none '
        'is marked primary',
      );
    }
    if (main.hasPin) throw SiloMainProfileLockedError(main);
    return main;
  }
}
