import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/profile.dart';
import '../net/account.dart';
import '../net/identity.dart';
import '../net/social_repository.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/screen_background.dart';
import 'nav.dart';

/// `Arkadaşlar` (Figma 92:230) with the `Arkadaş Ekle` popup (97:306).
///
/// Differences from the frame:
///  * Requests have no frame. Incoming requests sit at the top under
///    `İSTEKLER`, in the same rows, with ✓ (green, the `Meydan Oku` tile)
///    and ✕; requests this player sent show `bekliyor` and ✕ to withdraw.
///  * The ⚔ `Meydan Oku` (challenge) tile and the green online dot are left
///    out: there is no challenge flow and no presence yet. Its slot holds ✕
///    (remove), which asks first.
///  * The id field uses the system keyboard, not the custom one with `ARA`:
///    a tag has digits and the custom keyboard has none.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<FriendEntry> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await SocialRepository.instance.friends();
    if (!mounted) return;
    setState(() {
      _all = rows;
      _loading = false;
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } on SocialException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'Bağlantı kurulamadı');
    }
    await _load();
  }

  Future<void> _confirmRemove(FriendEntry f) async {
    final yes = await AppPopup.show<bool>(
      context,
      AppPopup(
        title: 'ARKADAŞI SİL',
        children: [
          Text(
            '${f.username}#${f.tag} arkadaş listenden çıkarılsın mı?',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t15,
              color: T.beyaz065,
            ),
          ),
          Builder(
            builder: (context) => WideButton(
              label: 'SİL',
              tone: WideButtonTone.orange,
              fontSize: T.t22,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ),
          Builder(
            builder: (context) => QuietButton(
              label: 'VAZGEÇ',
              onTap: () => Navigator.of(context).pop(false),
            ),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _act(() => SocialRepository.instance.remove(f.id));
    }
  }

  Future<void> _add() async {
    await AppPopup.show<void>(context, const _AddFriendPopup());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _all.where((f) => !f.accepted && f.incoming).toList();
    final outgoing = _all.where((f) => !f.accepted && !f.incoming).toList();
    final friends = _all.where((f) => f.accepted).toList();

    return Scaffold(
      body: ScreenBackground(
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          const Positioned(left: -15, top: 0, child: UndoButton()),
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: ScreenTitle('Arkadaşlar'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: T.s2xl),
                      const _IdentityCard(),
                      const SizedBox(height: 20),
                      WideButton(
                        label: 'ARKADAŞ EKLE',
                        leading: '+',
                        tone: WideButtonTone.green,
                        fontSize: T.t22,
                        onTap: _add,
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: _loading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: T.turuncu,
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView(
                                  padding: const EdgeInsets.only(bottom: T.sLg),
                                  children: [
                                    if (incoming.isNotEmpty) ...[
                                      _Header('İSTEKLER', incoming.length),
                                      for (final f in incoming)
                                        _gap(_row(f, [
                                          RowIconButton(
                                            glyph: '✓',
                                            active: true,
                                            onTap: () => _act(() =>
                                                SocialRepository.instance
                                                    .respond(f.id, accept: true)),
                                          ),
                                          RowIconButton(
                                            glyph: '✕',
                                            onTap: () => _act(() =>
                                                SocialRepository.instance
                                                    .respond(f.id, accept: false)),
                                          ),
                                        ])),
                                      const SizedBox(height: T.sLg),
                                    ],
                                    _Header('ARKADAŞLARIN', friends.length),
                                    if (friends.isEmpty && outgoing.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 30),
                                        child: Text(
                                          'Henüz arkadaşın yok.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: T.fontUi,
                                            fontSize: T.t15,
                                            color: T.beyaz050,
                                          ),
                                        ),
                                      ),
                                    for (final f in friends)
                                      _gap(_row(f, [
                                        _Trophies(f.trophies),
                                        RowIconButton(
                                          glyph: '✕',
                                          onTap: () => _confirmRemove(f),
                                        ),
                                      ])),
                                    for (final f in outgoing)
                                      _gap(_row(f, [
                                        const Text(
                                          'bekliyor',
                                          style: TextStyle(
                                            fontFamily: T.fontUi,
                                            fontSize: T.t13,
                                            color: T.beyaz050,
                                          ),
                                        ),
                                        RowIconButton(
                                          glyph: '✕',
                                          onTap: () => _act(() =>
                                              SocialRepository.instance
                                                  .remove(f.id)),
                                        ),
                                      ])),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const TabNavBar(),
          ],
        ),
      ),
    );
  }

  Widget _gap(Widget w) =>
      Padding(padding: const EdgeInsets.only(bottom: T.sSm), child: w);

  /// `Arkadaş/Emir` (96:192): 42pt avatar, name over #tag, then [trailing].
  Widget _row(FriendEntry f, List<Widget> trailing) => PlayerRow(
        name: f.username,
        tag: f.tag,
        avatarSize: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        trailing: trailing,
      );
}

class _Header extends StatelessWidget {
  const _Header(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, T.sSm),
      child: Row(
        children: [
          Expanded(child: SectionCaption(label, color: T.beyaz050)),
          SectionCaption('$count', color: T.beyaz050),
        ],
      ),
    );
  }
}

/// `Kupa` (96:199): 🏆 and the count in gold.
class _Trophies extends StatelessWidget {
  const _Trophies(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🏆', style: TextStyle(fontSize: T.t13)),
        const SizedBox(width: T.sXxs),
        Text(
          '$n',
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t15,
            color: T.altin.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

/// `Kimliğim` (95:191): this player's own id, with the copy button.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Profile?>(
      valueListenable: Account.instance.profile,
      builder: (context, p, _) {
        final name = p?.username ?? Identity.instance.name;
        final tag = p?.tag ?? Identity.instance.tag;
        Future<void> copy() async {
          if (tag == null) return;
          await Clipboard.setData(ClipboardData(text: '$name#$tag'));
          if (context.mounted) showToast(context, 'Kimliğin kopyalandı');
        }

        return GestureDetector(
          onTap: copy,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(T.sXl),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.rXl),
              border: Border.all(color: T.beyaz030, width: 1.5),
              gradient: const LinearGradient(
                colors: [Color(0xFF2933C7), Color(0xFF171C80)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: T.golgeCubuk,
                  offset: Offset(0, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                InitialsAvatar(
                  name: name,
                  size: 56,
                  radius: T.rLg,
                  border: T.beyaz038,
                  borderWidth: 1.5,
                  fontSize: T.t24,
                ),
                const SizedBox(width: T.sXl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: T.fontUi,
                          fontSize: T.t22,
                          color: T.beyaz100,
                        ),
                      ),
                      const SizedBox(height: T.sHairline),
                      Row(
                        children: [
                          Text(
                            tag == null ? '#••••' : '#$tag',
                            style: TextStyle(
                              fontFamily: T.fontUi,
                              fontSize: T.t15,
                              color: T.yesil.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(width: T.sSm),
                          const Text(
                            'kopyala',
                            style: TextStyle(
                              fontFamily: T.fontUi,
                              fontSize: T.t11,
                              color: T.beyaz038,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // `Kopyala` (95:199): two outlined sheets in a 44pt tile.
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: T.beyaz016,
                    borderRadius: BorderRadius.circular(T.rMd),
                    border: Border.all(color: T.beyaz030),
                  ),
                  child: Stack(
                    children: [
                      Positioned(left: 10, top: 8, child: _sheet(null)),
                      Positioned(
                        left: 16,
                        top: 14,
                        child: _sheet(const Color(0xFF171C80)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _sheet(Color? fill) => Container(
        width: 15,
        height: 18,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: T.beyaz080, width: 2),
        ),
      );
}

/// `Arkadaş Ekle Popup` (97:306): the id field, the match (`Sonuç`) with
/// EKLE, and KAPAT.
class _AddFriendPopup extends StatefulWidget {
  const _AddFriendPopup();

  @override
  State<_AddFriendPopup> createState() => _AddFriendPopupState();
}

class _AddFriendPopupState extends State<_AddFriendPopup> {
  final TextEditingController _field = TextEditingController();
  Timer? _debounce;
  Profile? _found;
  String? _message;
  bool _messageOk = false;
  bool _searching = false;
  int _token = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    setState(() {
      _found = null;
      _message = null;
    });
    final handle = Profile.parseHandle(text);
    if (handle == null) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search());
  }

  Future<void> _search() async {
    final handle = Profile.parseHandle(_field.text);
    if (handle == null) {
      setState(() {
        _message = 'Kimlik şöyle yazılır: Kerem_07#B3D2';
        _messageOk = false;
      });
      return;
    }
    final token = ++_token;
    setState(() => _searching = true);
    try {
      final p = await SocialRepository.instance
          .findPlayer(handle.username, handle.tag);
      if (!mounted || token != _token) return;
      setState(() {
        _found = p;
        _message = p == null ? 'Böyle bir oyuncu yok' : null;
        _messageOk = false;
      });
    } on SocialException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Bağlantı kurulamadı');
    } finally {
      if (mounted && token == _token) setState(() => _searching = false);
    }
  }

  Future<void> _send(Profile p) async {
    try {
      final r = await SocialRepository.instance.sendRequest(p.username, p.tag);
      if (!mounted) return;
      setState(() {
        _messageOk = true;
        _message = switch (r) {
          FriendRequestResult.sent => 'İstek gönderildi',
          FriendRequestResult.accepted => 'Artık arkadaşsınız',
          FriendRequestResult.alreadySent => 'İstek zaten gönderildi',
          FriendRequestResult.alreadyFriends => 'Zaten arkadaşsınız',
        };
        _found = null;
      });
    } on SocialException catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message;
          _messageOk = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return AppPopup(
      title: 'ARKADAŞ EKLE',
      children: [
        const Text(
          'Arkadaşının kimliğini yaz (kullanıcı adı + etiket)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: T.fontUi,
            fontSize: T.t13,
            color: T.beyaz050,
          ),
        ),
        PanelTextField(
          controller: _field,
          hint: 'Kerem_07#B3D2',
          height: 58,
          fontSize: T.t20,
          autofocus: true,
          maxLength: 22,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          onSubmitted: (_) => _search(),
          trailing: _searching
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: T.yesil,
                  ),
                )
              : null,
        ),
        if (found != null)
          // `Sonuç` (97:312).
          Container(
            padding: const EdgeInsets.all(T.sMd),
            decoration: BoxDecoration(
              color: T.beyaz012,
              borderRadius: BorderRadius.circular(T.rLg),
              border: Border.all(
                color: T.yesil.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                InitialsAvatar(
                  name: found.username,
                  size: 44,
                  radius: T.rMd,
                  border: T.beyaz030,
                  fontSize: T.t19,
                ),
                const SizedBox(width: T.sLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        found.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: T.fontUi,
                          fontSize: T.t19,
                          color: T.beyaz100,
                        ),
                      ),
                      Text(
                        '#${found.tag} · ${found.trophies} 🏆',
                        style: const TextStyle(
                          fontFamily: T.fontUi,
                          fontSize: T.t11,
                          color: T.beyaz050,
                        ),
                      ),
                    ],
                  ),
                ),
                SmallGoButton(
                  label: 'EKLE',
                  onTap: found.id == Account.instance.profile.value?.id
                      ? null
                      : () => _send(found),
                ),
              ],
            ),
          ),
        if (_message != null)
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: T.fontUi,
              fontSize: T.t13,
              color: _messageOk ? T.yesil : T.kirmizi,
            ),
          ),
        QuietButton(label: 'KAPAT', onTap: () => Navigator.of(context).pop()),
      ],
    );
  }
}
