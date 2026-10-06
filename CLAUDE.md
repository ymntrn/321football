# 321 Football Challenge

Mobile football trivia game: two clubs, type a player who played for both.
Practice mode (offline) is done; Friend Match (online, Supabase) runs end to
end. As of 6 Oct 2026 every match screen (board, Versus, GOOOL, Tur Bitti,
win/lose) and Practice's popups are built from Figma on branch
`screens-from-figma` — **not yet checked on the emulator** (`docs/TESTING.md`).

## Read before doing anything

1. `docs/friend-match.md` — the live working doc and the current status.
   **Its decisions supersede the open questions in `pvp-handoff.md` and
   `project-state.md`** (no-answer rule = void the round; backend = Supabase).
2. `docs/figma-to-flutter.md` — before touching any screen.
3. `docs/flutter-app.md` — app architecture, tools/ scripts, this machine's limits.
4. `docs/project-state.md` — the database and the data rules.
5. `docs/pvp-handoff.md`, `docs/game-screens-ui.md` — background.
6. `docs/TESTING.md` — the emulator checklist for the unverified screens.

## Layout

| Folder | What |
|---|---|
| `321_football_db/` | Python scraper/builder for the football SQLite DB |
| `app/` | Flutter client |
| `supabase/` | SQL migrations, smoke tests, `bot.py` second player |
| `docs/` | The project docs above |

## Rules that bite

- **The Figma file is the source of truth for layout**, not the written spec.
  File key `UHMpbhjpqxQ94Xs1oD3Sfz`. Load the `figma-design-to-code` skill
  before `get_design_context`.
- Static analysis proves nothing about a UI. Verify on the emulator with
  `app/tools/shot.ps1` screenshots.
- 7.7 GB RAM. Cold builds need the emulator off (`build_apk.ps1`). Never let a
  Flutter upgrade restore the 8 GB Gradle heap.
- Never `LIKE 'x%'` on the SQLite DB — use range comparisons.
- No anti-cheat code, ever (Yaman's decision).
- Bump `AppDatabase.assetVersion` whenever a new database is dropped in.

## Git

Repo: https://github.com/ymntrn/321football (public — that's fine).
`.gitignore` keeps out `supabase/.pgpass.local` (DB password — **never commit**),
the `.venv`, build output, and all `*.db` files (too big for GitHub; back them
up separately). Commit after each piece of work that runs.

## Keeping docs current

`docs/` is now the canonical copy. When something lands or a decision is made,
update the relevant doc in the same commit.
