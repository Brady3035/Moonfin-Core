import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_silo/server_silo.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/platform_detection.dart';
import '../../../watch_party/silo_watch_party_manager.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/settings/clean_settings_typography.dart';

/// Silo's Watch Party: start a room or join one with its code, then see who
/// is in it and, as host, start or stop what everyone watches. Jellyfin
/// servers get [SyncPlayScreen] instead.
class SiloWatchPartyScreen extends StatefulWidget {
  const SiloWatchPartyScreen({super.key});

  @override
  State<SiloWatchPartyScreen> createState() => _SiloWatchPartyScreenState();
}

class _SiloWatchPartyScreenState extends State<SiloWatchPartyScreen> {
  final _manager = GetIt.instance<SiloWatchPartyManager>();
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode(debugLabel: 'watch_party_code');
  final _tvFieldKey = GlobalKey<CustomTVTextFieldState>();
  late final Future<bool> _supported = _manager.inRoom
      ? Future.value(true)
      : _manager.serverSupportsRooms();

  @override
  void initState() {
    super.initState();
    _codeFocus.onKeyEvent = _onCodeKey;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onCodeKey(FocusNode node, KeyEvent event) {
    if (!PlatformDetection.isTV) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey.isBackKey &&
        (_tvFieldKey.currentState?.isKeyboardVisible ?? false)) {
      _tvFieldKey.currentState?.closeKeyboard();
      node.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      _tvFieldKey.currentState?.openKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    if (await _manager.join(code)) _codeController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: AppBar(title: Text(l10n.watchParty)),
        body: FutureBuilder<bool>(
          future: _supported,
          builder: (context, supported) {
            if (supported.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (supported.data != true) {
              return _Message(message: l10n.watchPartyUnavailable);
            }
            return ListenableBuilder(
              listenable: _manager,
              builder: (context, _) => _buildBody(context, l10n),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final room = _manager.room;
    return RequestInitialFocus(
      targetNode: PlatformDetection.isTV && room == null ? _codeFocus : null,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_manager.error case final error?) _Banner(message: error),
          if (room == null && _manager.endedReason != null)
            _Banner(
              message: _manager.endedReason == 'closed'
                  ? l10n.watchPartyEnded
                  : _manager.endedReason!,
            ),
          if (room == null) ..._buildEntry(context, l10n),
          if (room != null) ..._buildRoom(context, l10n, room),
        ],
      ),
    );
  }

  List<Widget> _buildEntry(BuildContext context, AppLocalizations l10n) {
    final busy = _manager.busy;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.watchPartyRoomCode,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _buildCodeField(context, l10n),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: busy ? null : _join,
                  icon: const Icon(Icons.login),
                  label: Text(l10n.syncPlayJoin),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.groups_rounded),
          title: Text(l10n.watchPartyStart),
          subtitle: Text(l10n.watchPartyPickTitle),
          onTap: busy ? null : () => _manager.create(),
        ),
      ),
    ];
  }

  Widget _buildCodeField(BuildContext context, AppLocalizations l10n) {
    if (!PlatformDetection.isTV) {
      return TextField(
        controller: _codeController,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: l10n.watchPartyRoomCode,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _join(),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _codeFocus,
      child: ListenableBuilder(
        listenable: _codeFocus,
        builder: (_, _) {
          final focused = _codeFocus.hasFocus;
          return CustomTVTextField(
            key: _tvFieldKey,
            controller: _codeController,
            isFocused: focused,
            inputPurpose: InputPurpose.text,
            keyboardStyle: GetIt.instance<UserPreferences>().get(
              UserPreferences.keyboardStyle,
            ),
            hint: l10n.watchPartyRoomCode,
            textFieldType: TextFieldType.other,
            keyboardType: KeyboardType.alphabetic,
            filled: true,
            fillColor: focused
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest.scaleAlpha(0.6),
            borderColor: colorScheme.outline,
            focusedBorderColor: colorScheme.primary,
            hintStyle: TextStyle(
              fontFamily: kCleanSettingsFontFamily,
              color: colorScheme.onSurface.withValues(alpha: 0.65),
            ),
            textStyle: TextStyle(
              fontFamily: kCleanSettingsFontFamily,
              color: colorScheme.onSurface,
            ),
            popParentOnKeyboardClose: false,
            onFieldSubmitted: (_) => _join(),
          );
        },
      ),
    );
  }

  List<Widget> _buildRoom(
    BuildContext context,
    AppLocalizations l10n,
    SiloRoom room,
  ) {
    final theme = Theme.of(context);
    final busy = _manager.busy;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.watchPartyRoomCode,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    label: Text(
                      _manager.connected
                          ? _stateLabel(l10n, room)
                          : l10n.watchPartyReconnecting,
                    ),
                  ),
                ],
              ),
              SelectableText(
                room.code,
                style: theme.textTheme.displaySmall?.copyWith(
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.watchPartyShareCode),
              const Divider(height: 24),
              Text(
                l10n.syncPlayParticipantCount(
                  room.members.where((m) => m.connected).length,
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final member in room.members)
                    Chip(
                      avatar: member.isHost
                          ? const Icon(Icons.star_rounded, size: 18)
                          : null,
                      label: Text(
                        member.connected
                            ? member.displayName
                            : '${member.displayName} (${l10n.watchPartyOffline})',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (room.selectedContentId case final id?)
                _ItemTitle(contentId: id, playing: room.isPlaying)
              else
                Text(
                  room.isHost
                      ? l10n.watchPartyPickTitle
                      : l10n.watchPartyWaitingForHost,
                ),
              if (room.isPlaying) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _manager.openPlayer,
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(l10n.syncPlayPlayNow),
                ),
              ],
              if (room.isHost) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (room.isStaged)
                      FilledButton.icon(
                        onPressed: busy ? null : _manager.startPlayback,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(l10n.watchPartyStartForEveryone),
                      ),
                    if (room.isPlaying)
                      OutlinedButton.icon(
                        onPressed: busy ? null : _manager.stopPlayback,
                        icon: const Icon(Icons.stop_rounded),
                        label: Text(l10n.watchPartyBackToLobby),
                      ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.watchPartyGuestsCanPause),
                  value: room.guestControlPolicy == 'guest_play_pause',
                  onChanged: busy ? null : _manager.setGuestsCanPause,
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: room.isHost
            ? TextButton.icon(
                onPressed: busy ? null : _manager.end,
                icon: const Icon(Icons.close),
                label: Text(l10n.watchPartyEnd),
              )
            : TextButton.icon(
                onPressed: _manager.leave,
                icon: const Icon(Icons.logout),
                label: Text(l10n.syncPlayLeaveGroup),
              ),
      ),
    ];
  }

  String _stateLabel(AppLocalizations l10n, SiloRoom room) {
    if (!room.isPlaying) return l10n.syncPlayStateIdle;
    return switch (room.playbackState) {
      'waiting' => l10n.syncPlayStateWaiting,
      'paused' => l10n.syncPlayStatePaused,
      _ => l10n.syncPlayStatePlaying,
    };
  }
}

/// The staged or playing item's name, read from the server.
class _ItemTitle extends StatefulWidget {
  const _ItemTitle({required this.contentId, required this.playing});

  final String contentId;
  final bool playing;

  @override
  State<_ItemTitle> createState() => _ItemTitleState();
}

class _ItemTitleState extends State<_ItemTitle> {
  late Future<String?> _title = _load();

  @override
  void didUpdateWidget(_ItemTitle old) {
    super.didUpdateWidget(old);
    if (old.contentId != widget.contentId) _title = _load();
  }

  Future<String?> _load() async {
    final client = GetIt.instance<SiloWatchPartyManager>().activeSiloClient;
    try {
      final item = await client?.itemsApi.getItem(widget.contentId);
      final series = item?['SeriesName'];
      final name = item?['Name'];
      if (name is! String) return null;
      return series is String && series.isNotEmpty ? '$series: $name' : name;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String?>(
      future: _title,
      builder: (context, title) {
        final name = title.data ?? '';
        return Text(
          widget.playing ? name : l10n.watchPartyUpNext(name),
          style: Theme.of(context).textTheme.titleMedium,
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
