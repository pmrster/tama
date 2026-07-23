# Tama for Windows — install guide

Tama's Windows port is a tray app (WPF, .NET 8) with the same dashboard, pixel cat, and
safety model as the macOS app: **read-only, local-only, no network**. It reads your
coding agents' own log files and writes nothing outside `%APPDATA%\Tama\`.

> **Status:** there is an installer (`TamaSetup.exe`) but it is **not code-signed yet**, so
> SmartScreen still warns once on first run (see below). Most people want **Option A — the
> installer**. The **portable zip** and **from source** paths remain for people who prefer them.

## Requirements

- Windows 10 or 11, x64 (also installs on ARM64 Windows via x64 emulation).
- Nothing else for the installer or the portable zip — both bundle their own .NET runtime.
- Building from source additionally needs the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
  and git.

## Option A — installer (recommended)

1. Download **`TamaSetup.exe`** from the [latest release](https://github.com/pmrster/tama/releases/latest).
2. Optional but recommended — verify the checksum against `TamaSetup.exe.sha256` published
   next to it:

   ```
   certutil -hashfile TamaSetup.exe SHA256
   ```

3. Double-click `TamaSetup.exe`.
4. **SmartScreen will warn** ("Windows protected your PC") because the build is not
   code-signed yet. Click **More info → Run anyway**. Expected until a signed release exists;
   verify the checksum in step 2 if you want certainty.
5. Click through the installer (Install → Finish). It installs per-user to
   `%LOCALAPPDATA%\Programs\Tama` with **no admin prompt**, adds a **Tama** Start Menu entry,
   and offers a **"Launch Tama automatically when I sign in"** checkbox. Leave **"Run Tama now"**
   ticked on the last page to start it immediately.
6. Look for the pixel-cat icon in the notification area (bottom-right). Windows often tucks
   new icons behind the `^` overflow chevron — drag the cat onto the taskbar to keep it visible.

To remove it: **Settings → Apps → Installed apps → Tama → Uninstall** (or Add/Remove Programs).
The uninstaller also removes the run-at-login entry. Your saved state in `%APPDATA%\Tama\` is
left in place on purpose — delete that folder too for a clean wipe.

## Option B — portable zip (no install, no admin rights)

1. Get `Tama-win-x64.zip` from whoever built it (there is no public download yet —
   see "Building the zip yourself" below).
2. Optional but recommended — verify the checksum against the one published with the zip:

   ```
   certutil -hashfile Tama-win-x64.zip SHA256
   ```

3. Unzip the whole folder anywhere you like (Desktop is fine). Keep the folder
   together — `Tama.Tray.exe` needs the DLLs sitting next to it.
4. Double-click `Tama.Tray.exe`.
5. **SmartScreen will warn on first launch** ("Windows protected your PC") because the
   build is not code-signed yet. Click **More info → Run anyway**. This is expected
   until a signed release exists; if you want certainty, verify the checksum in step 2
   or build from source instead.
6. Look for the pixel-cat icon in the notification area (bottom-right). Windows often
   tucks new icons behind the `^` overflow chevron — drag the cat onto the taskbar to
   keep it visible.

There is no uninstaller because nothing is installed: to remove Tama, quit it from the
tray menu, delete the folder, and delete `%APPDATA%\Tama\` (its only saved state). If
you enabled **Run at login**, toggle it off in Settings first (it manages a single
`Tama` value under `HKCU\...\CurrentVersion\Run`).

## Option C — run from source

```
git clone https://github.com/pmrster/tama
cd tama
dotnet run --project windows/Tama.Tray -c Release
```

Same app, no SmartScreen prompt, always current with the repo. Run the test suite with
`dotnet test windows/Tama.sln`.

### Building the zip yourself

From the repo root, on any OS (the `EnableWindowsTargeting` flag is only needed when
publishing from macOS/Linux):

```
dotnet publish windows/Tama.Tray -c Release -r win-x64 --self-contained \
  -p:EnableWindowsTargeting=true -p:PublishSingleFile=true -o dist/win-x64
```

Zip the `dist/win-x64` folder and publish its SHA-256 alongside it.

### Building the installer yourself (maintainer)

Normally CI does this: push a tag `win-v<version>` and the
[`windows-release` workflow](../.github/workflows/windows-release.yml) publishes a
self-contained build, compiles the installer with [Inno Setup](https://jrsoftware.org/isinfo.php),
and attaches `TamaSetup.exe` (+ `.sha256`) to the matching GitHub Release. To trigger a build
without a release, run that workflow manually (**Actions → windows-release → Run workflow**) and
download the `TamaSetup` artifact.

To build it locally you need **Windows** with Inno Setup 6 installed (its `ISCC.exe` compiler is
Windows-only), then from the repo root:

```
dotnet publish windows\Tama.Tray -c Release -r win-x64 --self-contained -o dist\win-x64
iscc /DAppVersion=<version> windows\Packaging\Tama.iss
```

Output: `dist\installer\TamaSetup.exe`. The `.iss` script and the embedded app icon
(`windows\Packaging\tama.ico`) live in `windows\Packaging\`.

## What to expect

- **Launch is silent by design.** No window opens, nothing appears in the taskbar and
  no console flashes — the only sign of life is the tray icon. Check Task Manager if
  you're unsure it started.
- The tray cat sleeps when no agent has been active recently and walks while sessions
  are live. Left-click opens the dashboard popover, anchored near the tray corner; it
  closes when you click anywhere else. The theme follows Windows light/dark unless you
  force one in Settings. The tray menu has Pin, Settings, and Quit.
- Sessions and token totals come from the agents' local logs, refreshed every 7 seconds:

  | Provider | Log location |
  |---|---|
  | Claude Code | `%USERPROFILE%\.claude\projects\<project>\*.jsonl` |
  | Codex | `%USERPROFILE%\.codex\sessions\YYYY\MM\DD\rollout-*.jsonl` |
  | Gemini CLI | `%USERPROFILE%\.gemini\tmp\<hash>\.project_root` |
  | Antigravity | `%USERPROFILE%\.gemini\antigravity-cli\history.jsonl` |
  | Ollama | `%LOCALAPPDATA%\Ollama\server.log` |

- A machine where none of these agents have run today shows the empty state (count 0,
  napping cat). That's not a bug — run a Claude Code or Codex session and the project
  folder appears within seconds.
- With a live session open you'll see two token numbers that differ by orders of
  magnitude: the **ctx** gauge (how full the context window is right now) and the
  cumulative today total (which includes cache re-reads, so it looks huge). Both are
  real; they are deliberately different things.
- **Pin** turns the popover into a resizable always-on-top window; its size and
  position survive a restart, as do the font-size (S/M/L) and theme settings.
  **Run at login** manages a single `Tama` value under
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` — toggling it off removes the
  value. **Quit** from the tray menu exits cleanly, with no leftover process in Task
  Manager.
- Footprint: the app writes only to `%APPDATA%\Tama\` (plus the opt-in Run key above),
  opens agent logs strictly read-only, and makes zero network connections.

## Known rough edges — what to report

The Windows port is CI-tested (unit tests build and pass on `windows-latest`), but a
few things can only be proven on real hardware. If you hit one of these, please
[open an issue](https://github.com/pmrster/tama/issues) — they're the exact items the
maintainers' smoke checklist ([`SMOKE.md`](SMOKE.md)) tracks:

- **Popover position at 125 %/150 % display scaling** — if it opens far from the tray
  corner, report it with your scaling factor and monitor layout.
- **Tray icon rendering** — the cat should be a crisp pixel glyph, never a blank
  square.
- **Refresh vs. a live agent write** — opening the popover while an agent is
  mid-session must never block or crash either side; Windows file locking is the one
  part CI can't exercise realistically.
- **Ollama model attribution** — Windows Ollama logs say `llama runner` where macOS
  says `mlx`; per-model rows should still attribute activity correctly.
- **Antivirus false positives** — expected for an unsigned single-file exe, but worth
  reporting which product flagged it.

## Troubleshooting

- **No tray icon** — check the `^` overflow chevron; confirm `Tama.Tray.exe` is running
  in Task Manager.
- **Dashboard is empty** — no agent logs from today at the paths above. Start an agent
  session, or check the paths exist on this machine.
- **Popover opens in the wrong place or antivirus flags the exe** — see
  [Known rough edges](#known-rough-edges--what-to-report) above.

## Privacy & safety

Identical to the macOS app: logs are opened read-only, no process is ever spawned, and
no network connection exists. The app's only writes are its own state under
`%APPDATA%\Tama\` and, if you opt in, the Run-at-login registry value. See the
repository's `SECURITY.md` and `PRIVACY.md`.
