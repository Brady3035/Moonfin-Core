sealed class User {
  String get id;
  String get name;
  String get serverId;
  String? get imageTag;
  bool get isAdministrator;
  bool get canDownload;
  bool get canManageSubtitles;
  bool get canManageCollections;

  const User();
}

class PrivateUser extends User {
  @override
  final String id;
  @override
  final String name;
  @override
  final String serverId;
  final String accessToken;
  final DateTime lastUsed;
  @override
  final String? imageTag;
  @override
  final bool isAdministrator;
  @override
  final bool canDownload;
  @override
  final bool canManageSubtitles;
  @override
  final bool canManageCollections;

  /// On Silo, the account this user belongs to. A Silo login belongs to an
  /// account, and the Moonfin user is one of its household profiles (the main
  /// profile until the optional profiles phase; decision D9). Step 3.2 keys
  /// the stored tokens by it. Null on Jellyfin and Emby.
  final String? siloAccountId;

  /// Whether this is a Silo profile rather than a Jellyfin or Emby user.
  bool get isSiloProfile => siloAccountId != null;

  const PrivateUser({
    required this.id,
    required this.name,
    required this.serverId,
    required this.accessToken,
    required this.lastUsed,
    this.imageTag,
    this.isAdministrator = false,
    this.canDownload = false,
    this.canManageSubtitles = false,
    this.canManageCollections = false,
    this.siloAccountId,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'accessToken': accessToken,
        'lastUsed': lastUsed.toIso8601String(),
        'imageTag': imageTag,
        'isAdministrator': isAdministrator,
        'canDownload': canDownload,
        'canManageSubtitles': canManageSubtitles,
        'canManageCollections': canManageCollections,
        // Only written for Silo users, so Jellyfin and Emby entries are
        // exactly what they were.
        if (siloAccountId != null) 'siloAccountId': siloAccountId,
      };

  factory PrivateUser.fromJson(
    String id,
    String serverId,
    Map<String, dynamic> json,
  ) {
    return PrivateUser(
      id: id,
      name: json['name'] as String? ?? '',
      serverId: serverId,
      accessToken: json['accessToken'] as String? ?? '',
      lastUsed: DateTime.tryParse(json['lastUsed'] as String? ?? '') ??
          DateTime.now(),
      imageTag: json['imageTag'] as String?,
      isAdministrator: json['isAdministrator'] as bool? ?? false,
      canDownload: json['canDownload'] as bool? ?? false,
      canManageSubtitles: json['canManageSubtitles'] as bool? ?? false,
      canManageCollections: json['canManageCollections'] as bool? ?? false,
      siloAccountId: _nonEmpty(json['siloAccountId']),
    );
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  PrivateUser copyWith({
    String? id,
    String? name,
    String? serverId,
    String? accessToken,
    DateTime? lastUsed,
    String? imageTag,
    bool? isAdministrator,
    bool? canDownload,
    bool? canManageSubtitles,
    bool? canManageCollections,
    String? siloAccountId,
  }) {
    return PrivateUser(
      id: id ?? this.id,
      name: name ?? this.name,
      serverId: serverId ?? this.serverId,
      accessToken: accessToken ?? this.accessToken,
      lastUsed: lastUsed ?? this.lastUsed,
      imageTag: imageTag ?? this.imageTag,
      isAdministrator: isAdministrator ?? this.isAdministrator,
      canDownload: canDownload ?? this.canDownload,
      canManageSubtitles: canManageSubtitles ?? this.canManageSubtitles,
      canManageCollections: canManageCollections ?? this.canManageCollections,
      siloAccountId: siloAccountId ?? this.siloAccountId,
    );
  }
}

class PublicUser extends User {
  @override
  final String id;
  @override
  final String name;
  @override
  final String serverId;
  final bool hasPassword;
  @override
  final String? imageTag;
  @override
  final bool isAdministrator;
  @override
  final bool canDownload;
  @override
  final bool canManageSubtitles;
  @override
  final bool canManageCollections;

  const PublicUser({
    required this.id,
    required this.name,
    required this.serverId,
    required this.hasPassword,
    this.imageTag,
    this.isAdministrator = false,
    this.canDownload = false,
    this.canManageSubtitles = false,
    this.canManageCollections = false,
  });
}
