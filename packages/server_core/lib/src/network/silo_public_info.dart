/// Silo's public, unauthenticated system info endpoint (native API).
const siloSystemInfoPath = '/api/v2/system/info';

/// Whether [data] is the body of Silo's `GET /api/v2/system/info`.
bool isSiloSystemInfo(Map<String, dynamic>? data) =>
    data != null &&
    data['api_major'] is num &&
    data['server_version'] is String;

/// Folds Silo's public endpoints into the Jellyfin `PublicSystemInfo` keys
/// Moonfin reads: `Id`, `ServerName`, `Version`, `ProductName`,
/// `StartupWizardCompleted` and `LoginDisclaimer`. The native values stay
/// available under `Silo*` keys.
///
/// - [systemInfo]: `GET /api/v2/system/info` (required).
/// - [identity]: `GET /api/v2/system/identity`. `Id` is its `server_id`, the
///   native v2 identity. (Silo's legacy v1 health route reports a different
///   id; it must never be used.)
/// - [branding]: `GET /api/v2/theme/branding`, for the server name and the
///   sign-in subtitle.
/// - [setup]: `GET /api/v2/system/setup`.
///
/// The last three are optional because they are cosmetic once the server is
/// known to be Silo; callers fetch them best effort.
Map<String, dynamic> siloPublicInfoToJellyfinShape({
  required Map<String, dynamic> systemInfo,
  Map<String, dynamic>? identity,
  Map<String, dynamic>? branding,
  Map<String, dynamic>? setup,
}) {
  String? text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  final wizardCompleted = setup?['wizard_completed'];
  final needsSetup = setup?['needs_setup'];
  final loginSubtitle = text(branding?['login_subtitle']);
  return {
    'Id': text(identity?['server_id']),
    'ServerName': text(branding?['server_name']) ?? 'Silo',
    // A git short hash such as "4b2e921c+dirty", not a semantic version.
    // Display it, never parse it; compatibility is decided by SiloApiMajor.
    'Version': systemInfo['server_version'],
    'ProductName': 'Silo',
    'StartupWizardCompleted': wizardCompleted is bool
        ? wizardCompleted
        : (needsSetup is bool ? !needsSetup : true),
    if (loginSubtitle != null) 'LoginDisclaimer': loginSubtitle,
    'SiloApiMajor': systemInfo['api_major'],
    'SiloContractDigest': systemInfo['contract_digest'],
  };
}
