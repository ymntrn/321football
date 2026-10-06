import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/room.dart';
import '../net/account.dart';
import '../net/identity.dart';
import '../net/room_repository.dart';
import '../net/server_clock.dart';
import '../theme/tokens.dart';
import '../widgets/lobby_chrome.dart';
import '../widgets/screen_background.dart';
import 'match_screen.dart';

/// `Arkadaş Maçı - Oda Kur` (51:471) and `Odaya Katıl` (51:524).
///
/// One screen, two modes, because the design draws both tabs on both frames.
/// The host creates a room and starts it; the guest types the code and waits
/// — which is why the guest's button is orange and says
/// `Başlatma Bekleniyor` rather than being a green thing to press.
class FriendMatchScreen extends StatefulWidget {
  const FriendMatchScreen({super.key});

  @override
  State<FriendMatchScreen> createState() => _FriendMatchScreenState();
}

enum _Mode { create, join }

class _FriendMatchScreenState extends State<FriendMatchScreen> {
  late final SupabaseClient _supabase = Supabase.instance.client;
  late final ServerClock _clock = ServerClock(_supabase);
  late final RoomRepository _rooms = RoomRepository(_supabase, _clock);

  /// Null until the player picks a side. The panel below the two buttons does
  /// not exist yet at that point: there is nothing true to put in it, and an
  /// empty room card with a row of dashes invites the reading that a room has
  /// already been made.
  _Mode? _mode;
  Room? _room;
  Seat? _seat;
  String? _error;
  bool _busy = false;

  StreamSubscription<Room>? _sub;
  Timer? _heartbeat;
  final TextEditingController _codeField = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Measured once here rather than at the start of every round: the offset
    // is a property of the two clocks, not of the match, and taking it now
    // means the first countdown is already accurate.
    _clock.sync();
    _resume();
  }

  /// Drop straight back into a match this device was already in.
  ///
  /// The player id survives an app restart, so a crash mid-match does not
  /// have to cost the match. That matters much more now that walking out
  /// actually forfeits: without this, every crash would be a loss.
  Future<void> _resume() async {
    try {
      if (!await Account.instance.ensureOnline()) return;
      final room = await _rooms.activeRoomFor(Identity.instance.playerId);
      if (!mounted || room == null) return;
      final seat = room.seatOf(Identity.instance.playerId);
      if (seat == null) return;
      setState(() => _mode = seat == Seat.host ? _Mode.create : _Mode.join);
      _listen(room, seat);
      if (room.phase != MatchPhase.lobby) _enterMatch(room);
    } catch (e) {
      debugPrint('resume check failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _heartbeat?.cancel();
    _codeField.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _listen(Room room, Seat seat) {
    _sub?.cancel();
    _heartbeat?.cancel();
    setState(() {
      _room = room;
      _seat = seat;
      _error = null;
    });

    _sub = _rooms.watch(room.code).listen((r) {
      if (!mounted) return;
      setState(() => _room = r);
      if (r.phase != MatchPhase.lobby) _enterMatch(r);
    });

    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      _rooms.touchSeen(code: room.code, seat: seat);
    });
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Account.instance.ensureOnline()) {
        throw const AccountException('offline');
      }
      final room = await _rooms.create(
        playerId: Identity.instance.playerId,
        name: Identity.instance.name,
      );
      _listen(room, Seat.host);
    } catch (e) {
      setState(() => _error = 'Oda kurulamadı. Bağlantını kontrol et.');
      debugPrint('create room failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _codeField.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Oda kodu 6 hanelidir');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Account.instance.ensureOnline()) {
        throw const JoinException(JoinFailure.network);
      }
      final room = await _rooms.join(
        code: code,
        playerId: Identity.instance.playerId,
        name: Identity.instance.name,
      );
      _listen(room, Seat.guest);
    } on JoinException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Bağlantı kurulamadı');
      debugPrint('join failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final room = _room;
    if (room == null || !room.hasGuest) return;
    setState(() => _busy = true);
    try {
      final started = await _rooms.startMatch(room.code);
      if (!mounted) return;
      setState(() => _room = started);
      if (started.phase != MatchPhase.lobby) _enterMatch(started);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _entered = false;

  /// The match has begun. Both clients arrive here from the same row change,
  /// the host a round trip earlier than the guest.
  void _enterMatch(Room room) {
    if (_entered) return;
    _entered = true;
    _sub?.cancel();
    _heartbeat?.cancel();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MatchScreen(
          initial: room,
          seat: _seat!,
          clock: _clock,
          rooms: _rooms,
        ),
      ),
    );
  }

  void _switchTo(_Mode mode) {
    if (_room != null) return; // already committed to a room
    setState(() {
      _mode = mode;
      _error = null;
    });
    if (mode == _Mode.create) {
      // Choosing "Oda Kur" IS the decision to host, so the room is made
      // immediately and the code is there to share. Nothing else to ask.
      _create();
    }
    // "Odaya Katıl" deliberately does NOT raise the keyboard. An earlier
    // version focused the field on arrival, which meant the panel appeared
    // already half-covered and a player who only wanted to paste, or to look
    // at the screen first, had to dismiss a keyboard nobody asked for. It
    // opens when the field is tapped, like any other field.
  }

  /// Fills the field from the clipboard. A code arrives by message, so
  /// pasting is the common case and long-pressing a text field to find the
  /// paste menu is a poor way to make someone discover it.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final code = digits.length > 6 ? digits.substring(0, 6) : digits;
    setState(() {
      _codeField.text = code;
      _error = null;
    });
    _codeField.selection =
        TextSelection.collapsed(offset: _codeField.text.length);
    if (code.length == 6) _join();
  }

  @override
  Widget build(BuildContext context) {
    // The design frame is 430 wide: the tab buttons are 306 (so 62 of inset
    // each side) and the panel is 364 (33 each side). Those insets are kept
    // as FRACTIONS rather than fixed points, because a Pixel 6 viewport is
    // 411pt and hard-coding 62 would squeeze the buttons noticeably narrower
    // than drawn.
    final width = MediaQuery.sizeOf(context).width;
    final tabInset = width * 62 / 430;
    final panelInset = width * 33 / 430;
    // The panel is 364x506 on a 430-wide frame, so its height follows the
    // width rather than filling whatever is left. Filling was what broke
    // here: with the keyboard raised there is nothing like 506pt left, the
    // panel was squeezed to about 140, and its contents overflowed it by 209
    // pixels. A fixed height plus a scroll view lets the keyboard push the
    // whole screen up instead of crushing one box inside it.
    final panelHeight = width * 506 / 430;

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              children: [
              Align(
                alignment: Alignment.centerLeft,
                child: UndoButton(onTap: () => Navigator.of(context).maybePop()),
              ),
              const Text(
                'Arkadaş Maçı',
                style: TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t40,
                  color: T.beyaz100,
                ),
              ),
              const SizedBox(height: T.s2xl),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tabInset),
                child: Column(
                  children: [
                    LobbyTabButton(
                      label: 'Oda Kur',
                      selected: _mode == _Mode.create,
                      onTap: () => _switchTo(_Mode.create),
                    ),
                    const SizedBox(height: T.lobbyTabGap),
                    LobbyTabButton(
                      label: 'Odaya Katıl',
                      selected: _mode == _Mode.join,
                      onTap: () => _switchTo(_Mode.join),
                    ),
                  ],
                ),
              ),
                const SizedBox(height: T.s2xl),
                // Nothing below the two buttons until one of them is pressed.
                if (_mode != null)
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(panelInset, 0, panelInset, T.sLg),
                    child: SizedBox(
                      height: panelHeight,
                      child: LobbyPanel(child: _panelBody()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelBody() {
    final room = _room;
    final seat = _seat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (room == null && _mode == _Mode.join)
          _codeEntry()
        else
          _codeRow(room),
        if (_error != null) ...[
          const SizedBox(height: T.sLg),
          Text(
            _error!,
            style: const TextStyle(fontSize: T.t15, color: T.kirmizi),
          ),
        ],
        const Spacer(flex: 2),
        // Which seat is "me" depends on the mode, and before a room exists
        // only one of the two names is known. Showing this device's name in
        // the host slot while it is waiting to JOIN somebody else's room
        // would be a straightforward lie about who is hosting.
        _seatRow(
          name: room?.hostName ??
              (_mode == _Mode.create
                  ? Identity.instance.name
                  : 'Bekleniyor...'),
          host: true,
          present: room != null || _mode == _Mode.create,
        ),
        const Spacer(flex: 2),
        _seatRow(
          name: room?.guestName ??
              (_mode == _Mode.join ? Identity.instance.name : 'Bekleniyor...'),
          host: false,
          present: room?.hasGuest == true ||
              (room == null && _mode == _Mode.join),
        ),
        const Spacer(flex: 3),
        _action(room, seat),
      ],
    );
  }

  Widget _seatRow({
    required String name,
    required bool host,
    required bool present,
  }) {
    return Row(
      children: [
        PlayerNameStrip(name: name, host: host, waiting: !present),
        const Spacer(),
        LobbyAvatar(
          initials: present ? _initials(name) : '?',
          present: present,
        ),
      ],
    );
  }

  Widget _action(Room? room, Seat? seat) {
    if (room == null) {
      return LobbyButton(
        label: _mode == _Mode.join ? 'Katıl' : 'Oda Kur',
        onTap: _busy ? null : (_mode == _Mode.join ? _join : _create),
      );
    }
    if (seat == Seat.guest) {
      // The guest never starts the match, so this is a status, not a control.
      return const LobbyButton(
        label: 'Başlatma Bekleniyor',
        tone: LobbyButtonTone.waiting,
      );
    }
    return LobbyButton(
      label: 'Başlat',
      onTap: (room.hasGuest && !_busy) ? _start : null,
    );
  }

  Widget _codeRow(Room? room) {
    final code = room?.code ?? '------';
    return Row(
      children: [
        Expanded(
          child: Text(
            code,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t34,
              color: T.beyaz100,
              letterSpacing: 2,
            ),
          ),
        ),
        if (room != null) ...[
          _IconButton(
            asset: 'assets/img/copy.png',
            width: 51,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: room.code));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: T.zeminPanel,
                  duration: Duration(seconds: 2),
                  content: Text(
                    'Oda kodu kopyalandı',
                    style: TextStyle(fontFamily: T.fontUi),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: T.sMd),
          _IconButton(
            asset: 'assets/img/share.png',
            width: 55,
            onTap: () => SharePlus.instance.share(
              ShareParams(
                text: '321 Football maçıma katıl! Oda kodu: ${room.code}',
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The code entry. This is the ONE place in the app that uses the system
  /// keyboard rather than the custom Turkish one: the code is six digits, the
  /// custom keyboard has no digits, and a system numeric pad brings paste
  /// with it — which is what someone does with a code a friend just sent
  /// them. Building a bespoke numeric keypad would look more consistent and
  /// be strictly worse to use.
  Widget _codeEntry() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: T.beyaz080,
              borderRadius: BorderRadius.circular(23),
            ),
            alignment: Alignment.center,
            child: TextField(
              controller: _codeField,
              focusNode: _codeFocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _join(),
              // Six digits is the whole code, so there is nothing to confirm
              // once the last one lands.
              onChanged: (value) {
                if (value.length == 6) _join();
              },
              style: const TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t22,
                color: T.zeminAna,
                letterSpacing: 4,
              ),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                isDense: true,
                hintText: 'Oda Kodu Gir',
                hintStyle: TextStyle(
                  fontFamily: T.fontUi,
                  fontSize: T.t19,
                  color: Color(0xFF6B6B7B),
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: T.sSm),
        GestureDetector(
          onTap: _paste,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: T.sXl),
            decoration: BoxDecoration(
              color: T.beyaz016,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: T.beyaz038),
            ),
            alignment: Alignment.center,
            child: const Text(
              'YAPIŞTIR',
              style: TextStyle(
                fontFamily: T.fontUi,
                fontSize: T.t13,
                color: T.beyaz080,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final digits = RegExp(r'\d+').firstMatch(clean)?.group(0);
    if (digits != null) return '${clean[0].toUpperCase()}$digits';
    return clean.substring(0, clean.length < 2 ? 1 : 2).toUpperCase();
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.asset,
    required this.width,
    required this.onTap,
  });

  final String asset;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(T.sXxs),
        child: Image.asset(asset, width: width, height: 48),
      ),
    );
  }
}


