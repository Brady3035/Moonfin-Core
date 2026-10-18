/// A server that prepares downloads itself and keeps a registry of the files
/// each device holds (Silo's managed downloads).
///
/// Moonfin's download service builds Jellyfin and Emby download URLs itself.
/// For a server whose client provides this API ([ServerDownloadsProvider]),
/// it asks the server for the file to fetch instead ([prepareDownload]), and
/// tells it when the file is on the device ([downloadFinished]) or gone again
/// ([downloadsRemoved]). Everything else (the transfer engines, storage,
/// offline catalog) stays the same.
abstract interface class ServerDownloadsApi {
  /// Registers the download of [request]'s item with the server and answers
  /// the file to fetch once the server has it ready.
  ///
  /// A converted file takes the server a while to make: until it is ready,
  /// [onPreparing] hears how far along it is, and [isCancelled] is asked
  /// between checks; once it answers true the wait ends with
  /// [ServerDownloadCancelled].
  ///
  /// Throws [ServerDownloadRefused] when the server won't provide this
  /// download (no file, a quality it can't make, downloads switched off),
  /// with its reason; other failures (network, server errors) as they come.
  Future<ServerDownloadTicket> prepareDownload(
    ServerDownloadRequest request, {
    void Function(ServerDownloadPreparation preparation)? onPreparing,
    bool Function()? isCancelled,
  });

  /// A link a browser can open to download [request]'s item, for the web
  /// build, where downloads go through the browser and carry no headers.
  /// Null when the server has none for this request.
  Future<Uri?> browserDownloadUrl(ServerDownloadRequest request);

  /// The file of [ticket] is complete on the device.
  Future<void> downloadFinished(ServerDownloadTicket ticket);

  /// The downloads of [itemIds] were deleted from the device (movies and
  /// episodes; a deleted season or series names each of its episodes).
  Future<void> downloadsRemoved(Iterable<String> itemIds);
}

/// A client that offers [ServerDownloadsApi].
abstract interface class ServerDownloadsProvider {
  ServerDownloadsApi get serverDownloads;
}

/// What to download.
class ServerDownloadRequest {
  const ServerDownloadRequest({
    required this.itemId,
    this.seriesId,
    this.mediaSourceId,
    this.maxVideoBitrate,
    this.maxWidth,
  });

  /// The movie or episode.
  final String itemId;

  /// The series of an episode.
  final String? seriesId;

  /// The version (media source) to download; null lets the server choose.
  final String? mediaSourceId;

  /// Video bitrate cap in bits per second; null for the original file.
  final int? maxVideoBitrate;

  /// Width cap in pixels; null for the original file.
  final int? maxWidth;

  /// Whether this asks for the original file rather than a converted one.
  bool get original => maxVideoBitrate == null;
}

/// A file the server has ready for download.
class ServerDownloadTicket {
  const ServerDownloadTicket({
    required this.id,
    required this.itemId,
    required this.url,
    required this.headers,
    this.revision,
    this.sizeBytes,
    this.container,
  });

  /// The server's id of this download.
  final String id;

  /// The movie or episode it is for.
  final String itemId;

  /// Where to fetch the file; supports ranged requests.
  final Uri url;

  /// Headers every request for [url] needs (credentials).
  final Map<String, String> headers;

  /// The server's revision of the download entry, when it keeps one.
  final int? revision;

  /// The file's size in bytes, when the server knows it.
  final int? sizeBytes;

  /// The file's container (`mp4`), when it isn't the source's own.
  final String? container;
}

/// The server won't provide a download.
class ServerDownloadRefused implements Exception {
  const ServerDownloadRefused(this.message, {this.reason});

  /// Readable text for the person (the server's, when it gave one).
  final String message;

  /// The server's code for why (`no_file`, `quality_unavailable`…).
  final String? reason;

  @override
  String toString() => message;
}

/// How far the server has got making a converted file.
class ServerDownloadPreparation {
  const ServerDownloadPreparation({
    this.progress,
    this.remainingSeconds,
    this.queuePosition,
  });

  /// Fraction made, 0 to 1, while the server reports it.
  final double? progress;

  /// Estimated seconds left, while the server reports it.
  final int? remainingSeconds;

  /// Place in the server's queue while it waits to start.
  final int? queuePosition;
}

/// The wait for a server-prepared file ended because the download was
/// cancelled.
class ServerDownloadCancelled implements Exception {
  const ServerDownloadCancelled();

  @override
  String toString() => 'ServerDownloadCancelled';
}
