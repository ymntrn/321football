# Play Store listing — DRAFT

Draft text for Play Console → *Grow users → Store presence → Main store
listing*. Turkish is the default language; English is a translation added
under *Manage translations*. Character limits are Play's (title 30, short
description 80, full description 4000); the counts below were checked.

Nothing here promises a feature the app does not have: no shop, no
purchases, no country flags, no real club crests.

---

## Türkçe (varsayılan)

**Uygulama adı** (28/30)

> 321 Football: Futbol Bilgisi

**Kısa açıklama** (65/80)

> İki kulüp, bir futbolcu. Hızlı yaz, rakibini geç, kupaları topla!

**Tam açıklama**

> İki kulüp. On saniye. Her ikisinde de oynamış bir futbolcu bul.
>
> 321 Football, futbol bilgini rakiplerine karşı sınayan hızlı bir bilgi
> oyunu. Ekranda iki kulüp belirir; iki takımda da forma giymiş bir
> futbolcuyu ilk sen yazarsan gol senin. Üç golü ilk atan maçı kazanır.
>
> ⚽ HEMEN OYNA — SIRALI MAÇ
> Kupa puanına yakın rakiplerle eşleş. Kazan, kupa ve altın topla; küresel
> liderlik tablosunda yüksel.
>
> 👥 ARKADAŞ MAÇI
> Altı haneli bir oda kodu paylaş, arkadaşınla birebir kapış. Rövanş tek
> dokunuşla.
>
> 🎯 ALIŞTIRMA
> Süre yok, rakip yok. Kolay, orta ve zor seviyelerde binlerce kulüp
> eşleşmesiyle kendini geliştir — tamamen çevrimdışı.
>
> 🏆 PROFİL VE ARKADAŞLAR
> Kullanıcı adın#etiketinle arkadaş ekle, arkadaş sıralamasında yerini
> gör. Toplam maç, kazanma oranı, seri ve en hızlı cevabın profilinde.
>
> NEDEN 321 FOOTBALL?
> • 1990'dan bugüne on binlerce futbolcu ve 800'den fazla kulüp
> • Türkçe klavye ve Türkçe karakterlerle tam uyum (Özil = Ozil)
> • Tam adı veya bilinen takma adı yaz — yakın yazımlar kabul edilmez,
>   adil olsun diye
> • Kayıt yok, e-posta yok: aç ve oyna
> • Tek reklam, o da isteğe bağlı: sıralı galibiyetten sonra altınını ikiye
>   katlamak için
>
> Futbolcu ve transfer verisi Wikidata'dan (CC0) derlenmiştir. 321 Football
> hiçbir kulüp, lig veya federasyonla bağlantılı değildir; kulüp adları
> sahiplerinin markalarıdır.

---

## English

**App name** (29/30)

> 321 Football: Football Trivia

**Short description** (72/80)

> Two clubs, one player. Name him first, beat your rival, climb the ranks.

**Full description**

> Two clubs. Ten seconds. Name a player who played for both.
>
> 321 Football is a fast trivia game that puts your football knowledge
> head-to-head against real opponents. Two clubs appear; type a player
> who wore both shirts before your rival does and the goal is yours. First
> to three goals wins.
>
> ⚽ PLAY NOW — RANKED
> Get matched with players near your trophy count. Win trophies and coins
> and climb the global leaderboard.
>
> 👥 FRIEND MATCH
> Share a six-digit room code and go one-on-one with a friend. Rematch in
> one tap.
>
> 🎯 PRACTICE
> No clock, no opponent. Thousands of club pairings across easy, medium
> and hard — fully offline.
>
> 🏆 PROFILE & FRIENDS
> Add friends by name#tag and see where you stand among them. Matches,
> win rate, streak and fastest answer, all on your profile.
>
> WHY 321 FOOTBALL?
> • Tens of thousands of players and 800+ clubs, from 1990 to today
> • Accent-proof answers (Özil = Ozil), with a Turkish keyboard built in
> • Type the full name or a known nickname — no fuzzy matches, so every
>   goal is earned
> • No sign-up, no e-mail: open it and play
> • One ad, and it is optional: watch it after a ranked win to double your
>   coins
>
> Player and transfer data is compiled from Wikidata (CC0). 321 Football is
> not affiliated with any club, league or federation; club names are the
> trademarks of their owners.

---

## Other listing fields

| Field | Value |
|---|---|
| App category | Games → Trivia |
| Tags | Trivia, Football / Soccer, Sports, Multiplayer |
| Contact e-mail | `destek@321football.app` (TODO: make sure the mailbox exists — `SupportConfig.email`) |
| Website | optional — the page that hosts the privacy policy will do |
| Privacy policy URL | the public URL of `docs/privacy-policy.md` (release.md step 5) |
| Contains ads | **Yes** (one rewarded ad) |
| In-app purchases | No |

## Graphics still needed (not in the repo)

- App icon 512×512 PNG (the launcher icon is still Flutter's default —
  `android/app/src/main/res/mipmap-*`; replace it before release).
- Feature graphic 1024×500.
- At least 2 phone screenshots (16:9 or 9:16, 320–3840 px), e.g. from
  `app\tools\shot.ps1` on the emulator: Ana Sayfa, a match board, GOOOL,
  Kazandın with 2X Altın, the Global leaderboard, Practice.
