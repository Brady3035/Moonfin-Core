/// Optional extra for an `ItemsApi` whose server has no batch read of user
/// data (Silo reads one item at a time, step 9.4).
///
/// After a change, `UserDataSync.refreshFromServer` asks the server again for
/// every item a screen holds, which on Jellyfin and Emby is one request per
/// hundred items. A server without a batch read would answer with a request
/// per item, so it narrows the list to the items whose user data may have
/// changed (those this client changed, and their parents and children). The
/// app checks for it with `itemsApi is UserDataRefreshScope`; servers
/// without one get every id, as before.
abstract interface class UserDataRefreshScope {
  /// Of [itemIds], those worth asking the server about again.
  List<String> userDataMayHaveChanged(Iterable<String> itemIds);
}
