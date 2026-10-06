# Figma → Flutter: how the UI gets built

**Rule: the Figma file is the source of truth for layout. `game-screens-ui.md`
is not.**

This exists because the first build of Practice mode got this wrong. The UI
was written from the written spec in `game-screens-ui.md` — which documents
the token system, the behavioural rules and the component inventory — as if it
described the composition. It doesn't. The result was a screen that used the
right colours and the right rules and looked nothing like the design.

What the spec doc gives you: colour/radius/spacing/type tokens, the rules
("one mutual footballer ends the round", "Practice has no clock"), which
components are shared, what is waiting on assets. Use it for all of that.

What only the Figma file gives you: the actual composition. Read it.

---

## The workflow

1. Load the `figma-design-to-code` skill. It is a **mandatory** prerequisite
   for `get_design_context` and the tool says so.
2. `get_metadata` on the page to find node IDs. On this file that response is
   ~288k characters and will not fit in context — save it and grep it:

   ```
   python3 -c "...re.finditer(r'<frame id=\"([^\"]+)\" name=\"([^\"]+)\"', t)"
   ```

3. `get_design_context` per frame. It returns React + Tailwind reference code,
   a screenshot, and asset URLs. Treat the code as a reference to translate,
   never as something to transliterate.

File key: `UHMpbhjpqxQ94Xs1oD3Sfz`. Design frame is **430 × 932**.

### Practice mode frame IDs

| Node | Frame |
|---|---|
| `11:62` | Alıştırma - Zorluk Seçme |
| `50:353` | Alıştırma - Oyuncu Bulma (Boş) |
| `78:356` | Alıştırma - Yazarken (Öneriler) |
| `78:483` | Alıştırma - Cevabı Göster |
| `78:610` | Alıştırma - Doğru Cevap |
| `82:338` | Alıştırma - Cevap Onayı |

The last three are **not yet built** — the current celebration overlay and
answer sheet are approximations written before the Figma file was read. Do
those properly from `78:610` and `82:338` before calling Practice finished.

---

## Assets

Figma's MCP asset URLs **expire after about 7 days**, so exports are committed
rather than linked. `tools/fetch_assets.ps1` re-downloads them; update the URLs
in it after re-exporting.

Committed in `assets/img/`: `undo.png`, `lightbulb.png`, `coin.png`,
`search.svg`, plus `rings.svg` and `glow.svg` kept as reference (see below).

### Two Figma SVGs that flutter_svg cannot render

Both background decorations failed silently and had to be painted by hand in
`ScreenBackground`. The geometry and colours were read out of the SVG source,
so this is a faithful reproduction, not a guess — but know why:

**`rings.svg` (the `masking` layer)** wraps four concentric ellipses in
`<mask mask-type="alpha">` over a rect filled `#0A0D3B`. flutter_svg treats
that mask as luminance; `#0A0D3B` is nearly black, so the whole layer was
masked out and the background rendered flat. The four ellipses are centred
(215, 465.5) with radii 445 / 397 / 332 / 259 and fills `#0A1059`, `#070B4A`,
`#060A3F`, `#050938`. Note these differ slightly from the `halka-1…4` values
in the token doc — **the SVG is right**.

**`glow.svg` (`Ellipse 5`)** is one hard ellipse (`#EFD959` at 20%) whose
entire appearance comes from `feGaussianBlur stdDeviation="100"`. flutter_svg
does not implement SVG filters, so it drew the raw ellipse — a grey blob on
screen. Reproduced as a radial falloff spanning the ellipse radius plus twice
the blur.

**Check any Figma SVG with a `<mask>` or `<filter>` before trusting it.**

---

## Translation notes that keep coming up

**Elliptical radial gradients.** Figma writes them as a `gradientTransform`
matrix. Flutter's `RadialGradient` is always circular against the *shortest*
side, so on a 341×90 button it renders as a small circle in the middle.
`T.wideRadial` is a `GradientTransform` that stretches X to span the box; use
it with `radius: 0.5`.

**Hard shadows.** The design uses zero-blur offset shadows throughout
(`0 3px 0 #4d579e` on keys, `0 4px 0 #040629` on the search bar and pills,
`0 4px 0 #176b0f` on GÖNDER). A blurred shadow reads as a completely different,
softer, cheaper UI. Keep `blurRadius: 0`.

**Inset shadows** have no Flutter equivalent. They are approximated with a
short top-edge gradient inside the same rounded rect.

**Fixed pixel widths do not always fit.** The keyboard's twelve 31.3pt keys
plus gaps need 419pt; a Pixel 6 viewport is 411pt. Derive key width from the
available width and keep the proportions instead of hard-coding.

**`RichText` does not inherit the ambient font.** Unlike `Text`, it ignores
`DefaultTextStyle`, so any span-based text needs an explicit `fontFamily` or it
silently drops to the system sans.

---

## Where the build knowingly differs from the design

- **`ARMA` crest slot** shows club initials on a name-derived colour rather
  than the literal "ARMA" placeholder. Crests are deferred and will be two
  colour stripes (no trademarked art). Only `_ArmaSlot` changes when they land.
- **Suggestion sub-line** reads `nationality · years` where the design shows
  `Forvet · 1988–2005`. **The database has no position column.** The years are
  derived from the player's spells. Add a position upstream to match exactly.
- **Name order.** The design shows `Batistuta, Gabriel` (surname first); the
  database stores `Gabriel Batistuta`. Left as-is because reordering names is a
  product decision, not a rendering one. Worth settling.
- **`TAKIM 1` / `TAKIM 2`** are placeholders in Figma; the app shows real club
  names, which are longer and wrap to two lines.
