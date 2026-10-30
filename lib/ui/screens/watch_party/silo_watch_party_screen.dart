import 'dart:async';

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
  late final Future<bool> _supported = _manager.inRoom
      ? Future.value(true)
      : _manager.serverSupportsRooms();

  @override
  void initState() {
    super.initState();
    _manager.roomScreenOpened();
  }

  @override
  void dispose() {
    _manager.roomScreenClosed();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
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

  Widget _buildCodeField(BuildContext context, AppLocalizations l10n) =>
      _TvAwareField(
        controller: _codeController,
        focusNode: _codeFocus,
        hint: l10n.watchPartyCodeOrLink,
        capitalize: true,
        onSubmitted: _join,
      );

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
              if (_manager.inviteUri case final invite?)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.link),
                    label: Text(l10n.watchPartyCopyInvite),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: invite.toString()),
                      );
                      messenger.showSnackBar(
                        SnackBar(content: Text(l10n.watchPartyInviteCopied)),
                      );
                    },
                  ),
                ),
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
              if (room.selectedContentId case final id?) ...[
                _ItemTitle(contentId: id, playing: room.isPlaying),
                _SubtitlePicker(contentId: id, fileId: room.selectedFileId),
              ] else if (!room.isVoting)
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
                // Silo switches modes only in the lobby.
                if (!room.isPlaying)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.watchPartyLetEveryoneVote),
                    value: room.isVoting,
                    onChanged: busy ? null : _manager.setVoting,
                  ),
              ],
              if (room.isVoting && !room.isPlaying)
                _VotePanel(manager: _manager, room: room),
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
    final item = await GetIt.instance<SiloWatchPartyManager>().selectedItem();
    final series = item?['SeriesName'];
    final name = item?['Name'];
    if (name is! String) return null;
    return series is String && series.isNotEmpty ? '$series: $name' : name;
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

/// The vote: the movies up for it with their tallies, a vote toggle for
/// everyone, and for the host a movie search to add more and a play
/// button on each.
class _VotePanel extends StatefulWidget {
  const _VotePanel({required this.manager, required this.room});

  final SiloWatchPartyManager manager;
  final SiloRoom room;

  @override
  State<_VotePanel> createState() => _VotePanelState();
}

class _VotePanelState extends State<_VotePanel> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'watch_party_search');
  String _lastSearch = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // The TV keyboard has no change callback; the controller covers both.
    _search.addListener(() {
      if (_search.text == _lastSearch) return;
      _lastSearch = _search.text;
      _onSearchChanged(_search.text);
    });
  }

  List<Map<String, dynamic>> _results = const [];
  int _query = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = ++_query;
      List<Map<String, dynamic>> results;
      try {
        results = await widget.manager.searchMovies(text);
      } catch (_) {
        results = const [];
      }
      if (mounted && query == _query) setState(() => _results = results);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final manager = widget.manager;
    final isHost = widget.room.isHost;
    final suggestions = manager.suggestions;
    final suggested = {for (final s in suggestions) s.contentId};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(
          isHost ? l10n.watchPartyVoteHelp : l10n.watchPartyGuestVoteHelp,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.watchPartyNoSuggestions),
          ),
        for (final suggestion in suggestions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(suggestion.title),
            subtitle: Text(
              [
                if (suggestion.subtitle.isNotEmpty) suggestion.subtitle,
                l10n.watchPartyVoteCount(suggestion.voteCount),
              ].join(' · '),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.watchPartyVoteCount(1),
                  icon: Icon(
                    suggestion.votedByMe
                        ? Icons.thumb_up_alt
                        : Icons.thumb_up_alt_outlined,
                  ),
                  color: suggestion.votedByMe
                      ? theme.colorScheme.primary
                      : null,
                  onPressed: () =>
                      manager.vote(suggestion, !suggestion.votedByMe),
                ),
                if (isHost) ...[
                  IconButton(
                    tooltip: l10n.play,
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: manager.busy
                        ? null
                        : () => manager.playSuggestion(suggestion),
                  ),
                  IconButton(
                    tooltip: l10n.remove,
                    icon: const Icon(Icons.close),
                    onPressed: () => manager.removeSuggestion(suggestion),
                  ),
                ],
              ],
            ),
          ),
        if (isHost) ...[
          const SizedBox(height: 8),
          _TvAwareField(
            controller: _search,
            focusNode: _searchFocus,
            hint: l10n.watchPartySearchMovies,
            icon: Icons.search,
          ),
          for (final movie in _results)
            if (!suggested.contains(movie['Id']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(movie['Name'] as String? ?? ''),
                subtitle: movie['ProductionYear'] == null
                    ? null
                    : Text('${movie['ProductionYear']}'),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.add),
                  onPressed: () => manager.suggestMovie(movie),
                ),
              ),
        ],
      ],
    );
  }
}

/// A text field that takes Moonfin's TV keyboard on TV (opened with
/// select, closed with back) and a plain field elsewhere.
class _TvAwareField extends StatefulWidget {
  const _TvAwareField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.icon,
    this.capitalize = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData? icon;
  final bool capitalize;
  final VoidCallback? onSubmitted;

  @override
  State<_TvAwareField> createState() => _TvAwareFieldState();
}

class _TvAwareFieldState extends State<_TvAwareField> {
  final _tvKey = GlobalKey<CustomTVTextFieldState>();

  @override
  void initState() {
    super.initState();
    widget.focusNode.onKeyEvent = _onKey;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!PlatformDetection.isTV) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = _tvKey.currentState;
    if (event.logicalKey.isBackKey && (keyboard?.isKeyboardVisible ?? false)) {
      keyboard?.closeKeyboard();
      node.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      keyboard?.openKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetection.isTV) {
      return TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textCapitalization: widget.capitalize
            ? TextCapitalization.characters
            : TextCapitalization.none,
        decoration: InputDecoration(
          prefixIcon: widget.icon == null ? null : Icon(widget.icon),
          labelText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => widget.onSubmitted?.call(),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: widget.focusNode,
      child: ListenableBuilder(
        listenable: widget.focusNode,
        builder: (_, _) {
          final focused = widget.focusNode.hasFocus;
          return CustomTVTextField(
            key: _tvKey,
            controller: widget.controller,
            isFocused: focused,
            inputPurpose: InputPurpose.text,
            keyboardStyle: GetIt.instance<UserPreferences>().get(
              UserPreferences.keyboardStyle,
            ),
            hint: widget.hint,
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
            onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          );
        },
      ),
    );
  }
}

/// Each member's own subtitles for the room's item. Audio isn't offered:
/// everyone hears the file's default track.
class _SubtitlePicker extends StatefulWidget {
  const _SubtitlePicker({required this.contentId, required this.fileId});

  final String contentId;
  final String? fileId;

  @override
  State<_SubtitlePicker> createState() => _SubtitlePickerState();
}

class _SubtitlePickerState extends State<_SubtitlePicker> {
  final _manager = GetIt.instance<SiloWatchPartyManager>();
  late Future<Map<String, dynamic>?> _item = _manager.selectedItem();

  @override
  void didUpdateWidget(_SubtitlePicker old) {
    super.didUpdateWidget(old);
    if (old.contentId != widget.contentId) _item = _manager.selectedItem();
  }

  String _label(Map<String, dynamic> stream) =>
      stream['DisplayTitle'] as String? ??
      stream['Language'] as String? ??
      '#${stream['Index']}';

  Future<void> _pick(
    BuildContext context,
    List<Map<String, dynamic>> tracks,
  ) async {
    final l10n = AppLocalizations.of(context);
    final current = _manager.subtitleStreamIndex;
    final options = <(int?, String)>[
      (null, l10n.defaultLabel),
      (-1, l10n.off),
      for (final t in tracks) (t['Index'] as int, _label(t)),
    ];
    final picked = await showDialog<(int?, String)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.subtitles),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option),
              child: Row(
                children: [
                  Icon(
                    option.$1 == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(option.$2)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) await _manager.setSubtitleStreamIndex(picked.$1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Map<String, dynamic>?>(
      future: _item,
      builder: (context, item) {
        final data = item.data;
        if (data == null) return const SizedBox.shrink();
        final tracks = SiloWatchPartyManager.streamsOf(
          SiloWatchPartyManager.partySource(data, widget.fileId),
          'Subtitle',
        );
        if (tracks.isEmpty) return const SizedBox.shrink();
        final current = _manager.subtitleStreamIndex;
        final currentLabel = switch (current) {
          null => l10n.defaultLabel,
          -1 => l10n.off,
          _ =>
            tracks
                    .where((t) => t['Index'] == current)
                    .map(_label)
                    .firstOrNull ??
                l10n.defaultLabel,
        };
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.subtitles_outlined),
          title: Text(l10n.subtitles),
          subtitle: Text(currentLabel),
          onTap: () => _pick(context, tracks),
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
