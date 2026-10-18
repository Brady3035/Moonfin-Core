part of 'socket_handler.dart';

/// Silo's realtime socket (`/api/v2/events/ws`), on the same reconnect, close
/// and logging machinery as Jellyfin's and Emby's.
///
/// What differs is the handshake and the connection's life:
///
/// - Silo takes no token on the URL. Every connect first asks for a
///   single-use ticket (`POST /events/ws-ticket`, through the Silo client so
///   it carries the login and profile and can refresh a token that is due),
///   then offers the subprotocols `silo.events.v2` and `silo.ticket.<ticket>`.
/// - The channels are declared on the URL (`?channels=user_state,catalog`),
///   so no subscribe frame is owed; a server that still asks for one gets it.
/// - Silo ends every connection after five minutes, so the socket renews
///   itself shortly before that with a fresh ticket.
/// - A server that has the socket off (`GET /events/capabilities`) gets no
///   connection at all.
///
/// Frames are read here; what they mean for the app comes in step 13.3.
class SiloEventsSocketClient extends _ReconnectingWebSocketClient {
  SiloEventsSocketClient(
    MediaServerClient client, {
    super.connectTimeout,
    @visibleForTesting this.renewMargin = const Duration(seconds: 15),
  }) : super(client, 'Silo');

  /// How long before Silo's limit the connection is renewed: enough for a
  /// ticket and a handshake, so the old socket is replaced before Silo closes
  /// it.
  final Duration renewMargin;

  Timer? _renewTimer;
  Duration? _maxConnection;
  bool _renewing = false;

  /// Read once per client: whether the server has the socket on. Asked again
  /// after a failure or an answer of "off", on the next connect.
  SiloEventsCapabilities? _capabilities;

  SiloMediaServerClient? get _silo => siloClientOf(client);

  /// Silo connects through [openChannel]; there is no plain URL.
  @override
  Uri? buildUri() => null;

  @override
  Future<WebSocketChannel?> openChannel() async {
    final silo = _silo;
    if (silo == null || silo.accessToken == null) return null;
    final events = silo.eventsApi;

    final capabilities = _capabilities ??= await events.capabilities();
    if (!capabilities.available) {
      _capabilities = null;
      logLifecycle(
        'Silo events socket is off on this server '
        '(${capabilities.state}${capabilities.allowed ? '' : ', not allowed'})',
      );
      return null;
    }

    final opening = _disconnects;
    final ticket = await events.createTicket();
    // Called off while the ticket was on its way: open nothing.
    if (_disposed || opening != _disconnects) return null;
    _maxConnection = ticket.maxConnection;
    return WebSocketChannel.connect(
      events.socketUri(),
      protocols: ticket.offeredProtocols,
    );
  }

  @override
  void onConnected() {
    _renewTimer?.cancel();
    final limit = _maxConnection;
    if (limit == null) return;
    var due = limit - renewMargin;
    if (due < const Duration(seconds: 1)) due = const Duration(seconds: 1);
    _renewTimer = Timer(due, _renew);
  }

  /// Replaces the connection before Silo's limit ends it. A connect closes
  /// the old socket first and opens a new one with a fresh ticket.
  void _renew() {
    _renewTimer = null;
    _renewing = true;
    unawaited(connect().whenComplete(() => _renewing = false));
  }

  /// A renewal every five minutes would fill the network log with
  /// "connected" lines; only failures are logged while renewing.
  @override
  void logLifecycle(String message) {
    if (_renewing) return;
    super.logLifecycle(message);
  }

  @override
  void handleMessage(dynamic data) {
    final frame = SiloEventFrame.parse(data);
    if (frame == null) return;
    switch (frame.type) {
      case 'hello':
        // A declaration that took nothing leaves a subscribe frame owed, and
        // Silo closes a connection that doesn't send one within seconds.
        if (frame.requiredAction == 'subscribe') {
          channel?.sink.add(
            jsonEncode({
              'type': 'subscribe',
              'channels': SiloEventsApi.followedChannels,
            }),
          );
        }
      case 'subscribed':
        if (frame.rejected.isNotEmpty) {
          logLifecycle(
            'Silo events socket refused channels: ${frame.rejected.join(', ')}',
          );
        }
      case 'error':
        warn(
          'Silo events socket error',
          '${frame.code ?? 'unknown'}: ${frame.message ?? ''}',
        );
      default:
      // Snapshots and events are translated in step 13.3.
    }
  }

  /// Silo takes nothing but a subscribe frame on this socket, and Jellyfin's
  /// and Emby's feeds (`SessionsStart` and the like) mean nothing to it.
  @override
  void send(String messageType, [Object? data]) {}

  @override
  Future<void> disconnect() {
    _renewTimer?.cancel();
    _renewTimer = null;
    return super.disconnect();
  }
}
