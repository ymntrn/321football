# 321 Football — Figma screen spec

Last updated: 10 September 2026. File `321-Football-Mobile`, key
`UHMpbhjpqxQ94Xs1oD3Sfz`. 34 screens, tokenised and prototyped. All copy is
Turkish.

> Tokens, rules and component inventory only. **The Figma file itself is the
> source of truth for layout** — see `figma-to-flutter.md`.

---

## Canvas layout

| Row | Contents |
|---|---|
| y = 6 | PvP match loop, home, splash |
| y = 1009 | Practice, friend lobby, leaderboards, settings, profile |
| y = 2010 | Practice state frames |
| y = 3011 | PvP typing states |
| y = 4012 | Username, friends, privacy, support, shop tabs |
| y = 5013 | Tur Bitti (stalemate) |

Frames must not share a position — a duplicate x/y silently hides one screen
under another (this happened once to the privacy screen and is easy to miss,
since both frames still render fine in isolation).

---

## Design tokens — collection `321 Tokens`

51 variables, bound across ~2 400 fills and strokes, 730 corner radii, 340
gaps and 1 100 font sizes. Gradients are the one exception: Figma cannot bind
a variable to a gradient stop, so the orange, green and gold gradients remain
literal. Their endpoints are the `-koyu` tokens, so a Flutter theme can
reconstruct them.

### Colour

| Variable | Value | Used for |
|---|---|---|
| `color/zemin/ana` | `#0A0D3B` | screen background |
| `color/zemin/derin` | `#0C126B` | backing rectangle |
| `color/zemin/panel` | `#1620A7` | cards, chips, search bar |
| `color/zemin/klavye` | `#0E145A` | keyboard tray |
| `color/zemin/halka-1…4` | `#0A1059` → `#050938` | the four background rings |
| `color/zemin/avatar` | `#3321D9` | avatar fill |
| `color/marka/yesil` | `#4DFF44` | success, confirm, online |
| `color/marka/yesil-koyu` | `#39C831` | green gradient end |
| `color/marka/yesil-murekkep` | `#051705` | text on green |
| `color/marka/turuncu` | `#FFAD2B` | primary action, active tab |
| `color/marka/turuncu-koyu` | `#DE6B08` | orange gradient end |
| `color/marka/altin` | `#FFC72B` | coins, trophies, first place |
| `color/marka/kirmizi` | `#FF4444` | countdowns, VS, defeat |
| `color/beyaz/006 … 100` | white at 6/12/16/22/30/38/50/65/80/100 % | surfaces, borders, text |

The white ladder replaced roughly two dozen ad-hoc opacities. Everything
snapped to the nearest rung, so the ramp is now real: 06–16 are surfaces,
22–38 are borders, 50–100 are text.

### Radius, spacing, type

- `radius/tus` 11 · `sm` 12 · `md` 16 · `lg` 20 · `xl` 24 · `2xl` 30.
  Circles were deliberately left unbound — their radius is half their width,
  not a token.
- `space/hairline` 2 · `xxs` 4 · `xs` 6 · `sm` 8 · `md` 10 · `lg` 12 ·
  `xl` 14 · `2xl` 20.
- `type/11 · 13 · 15 · 17 · 19 · 20 · 22 · 24 · 34 · 40 · 96`. 20 is its own
  step because it is the keyboard letter size and should not drift.

**Snapping caveat:** rounding sizes to the ramp made a handful of fixed-width
labels reflow. All were found and repaired, but if you edit a label's text and
it suddenly wraps, widen the text box rather than shrinking the font — the
font size is now bound to a token and changing it breaks the ramp.

---

## Rules the UI encodes

**One mutual footballer ends the round — in both modes.** No "found players"
panel anywhere; practice shows a streak, and the correct answer is a
full-screen celebration with an auto-advance bar.

**Identity is username + auto-generated tag** (`Yaman#7K2M`). Backend
consequence: usernames need not be unique, the pair must be, and the tag has
to be stable for the life of the account since it is what people share.

**Practice has no clock; PvP has two** — 15 s to pick a club, 10 s to find the
player, both drawn as a red Jaro numeral inside a 158 px ring.

---

## Shared components (clone, don't rebuild)

**Keyboard `Klavye`** — custom Turkish QWERTY, identical on iOS and Android.
`QWERTYUIOPĞÜ` / `ASDFGHJKLŞİ` / `ZXCVBNMÖÇ` + backspace. White key faces,
navy PoetsenOne, hard 3 px shadow. The action key is green and relabels per
context: `GÖNDER`, `TAMAM`, `ARA`.

**Search bar `Arama Çubuğu`** — idle placeholder at `beyaz/050`; typing state
gets an 80 % stroke, green caret and ✕. The suggestion panel floats 12 px
above it and **tints the matched prefix green inside the name** (a text range
fill — a `TextSpan` split in Flutter).

Practice shows 4 suggestions, PvP only 3 plus a compact matchup strip, so the
panel never covers the crests during a ten-second round.

Suggestions come from a prefix search over `players.normalized_name` /
`player_aliases.normalized_alias` (or `clubs` / `club_aliases` on the team
picker), ordered by `fame_score DESC`. **Display aid only** — it must not
soften `validate_answer`, which stays exact-match.

**Bottom nav** on home, leaderboards, shop, settings, profile and friends;
sub-pages use the top-left back arrow.

---

## Leaderboards — the two tabs differ on purpose

- **Global**: pinned top-3 podium with gold / silver / bronze rows, a clipped
  scroll area for ranks 4–100, and the user's own row pinned above the nav.
- **Arkadaş**: no podium, no pinned row. One uniform scrollable list where the
  user is just another row, highlighted green. A friends list is short enough
  that pinning would mostly duplicate a row already on screen.

---

## Prototype

137 connections, four flow starting points: **Tam Akış** (splash), **Ana
Menü**, **PvP Maç Döngüsü**, **Alıştırma**.

The loop: splash → username → home → matchmaking → versus → team select →
typing → countdown → player search → typing → GOOOL → next round. Timeouts
drive the automatic beats (splash 1.5 s, matchmaking 2 s, versus 2 s,
countdown 1.6 s, GOOOL 2.5 s). The ten-second player-search timeout leads to
**Tur Bitti**, and a click on either round-end screen jumps to the win/lose
result so both endings are reachable in a demo.

Practice: difficulty → board → typing → correct → back to board; the Cevap
pill opens the coin confirmation, which opens the answer list.

**Not wired:** `PAS GEÇ`. Figma rejects a navigation whose destination is its
own frame, and a skip is by definition a reload of the same screen. In the app
it is a state change, not a navigation.

---

## Waiting on assets

Player banners, the 30 avatars and the logo are coming. When they land:

- The logo replaces the `321` Jaro wordmark on the username screen and can
  fill the empty upper half of the home screen.
- Avatars drop into the shop grid tiles (`Avatar/<name>` → `Görsel`) and into
  every avatar frame across leaderboards, friends, versus and results.
- Card frames replace the `Mini Kart` previews in the shop and the
  `Oyuncu Kartı` nodes on the Versus screen.
- Club crests fill the `Arma` slots from `clubs.crest_asset_url`.

## Still open

- Club names are `TAKIM 1` / `TAKIM 2` placeholders.
- Shop grids show 8 of 30 items each — enough to fix the pattern.
- The PvP no-answer rule is now drawn (Tur Bitti = void the round, no score)
  but not formally decided. *(Decided 13 Sep 2026: void the round.)*
