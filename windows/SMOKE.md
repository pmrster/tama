# Tama for Windows — laptop smoke checklist (Plan C, Task 7)

Manual verification on a real Windows machine (office laptop). Everything below is the part
CI cannot cover: pixels, tray behavior, real log paths, live file locking. Run once after
Plan C merges; failures become fix commits. Record results inline (✅/❌ + notes) and commit.

## 0. Build & launch

- [ ] `git clone https://github.com/pmrster/tama && cd tama`
- [ ] `dotnet run --project windows/Tama.Tray -c Release`
      (or download the CI artifact once Plan D publishes one)
- [ ] Tray icon appears in the notification area (pixel cat glyph, not a blank square).
      With no agent activity today it shows the sleeping variant.

## 1. Popover basics

- [ ] Left-click tray icon → popover opens anchored near the tray corner
      **at 100% AND at 125%/150% display scaling** (DPI positioning was a known carry —
      if the popover opens far from the corner at >100% scaling, file it).
- [ ] Click anywhere else → popover closes (focus-loss).
- [ ] Left-click tray icon twice quickly (open→close) repeatedly ×10 → no crash
      (reentrancy guard under real WM_ACTIVATE ordering).
- [ ] Pixel cat animates: napping (z's drifting) with no activity; walks with an active session.
- [ ] Light/dark: matches OS theme by default; Settings → Light/Dark forces it; popover
      reopen keeps the explicit choice.

## 2. Real log paths (spec/log-formats.md "verify-on-target")

Confirm each path exists on a machine where the agent has actually run; where it differs,
correct `ActiveSessionsScanner.CreateDefault` / `OllamaReader.DefaultLogPath` (one line)
AND `spec/log-formats.md` + the design doc table:

- [ ] `%USERPROFILE%\.claude\projects\<proj>\*.jsonl` (run one Claude Code session first)
- [ ] `%USERPROFILE%\.codex\sessions\YYYY\MM\DD\rollout-*.jsonl`
- [ ] `%USERPROFILE%\.gemini\tmp\<hash>\.project_root`
- [ ] `%USERPROFILE%\.gemini\antigravity-cli\history.jsonl`
- [ ] `%LOCALAPPDATA%\Ollama\server.log`

## 3. Live data

- [ ] Run a Claude Code session on the laptop → its project folder appears in the dashboard;
      tokens tick upward at the 7 s cadence while the popover stays open.
- [ ] TODAY bar reflects usage; cost figure plausible for the model tier used.
- [ ] Ctx gauge fills as the session's context grows; two-numbers rule sane
      (cumulative tokens ≫ ctx occupancy).
- [ ] While the agent is mid-write: popover refresh never blocks or crashes the agent
      (FileShare semantics under real Windows locking).

## 4. Ollama (if installed)

- [ ] Ollama group hidden when server not running; appears when `ollama serve`
      (or the tray app) runs.
- [ ] Inspect a real `%LOCALAPPDATA%\Ollama\server.log`: note the exact runner start/stop
      line wording. Expected: start lines match `runner subprocess` + `starting` + `model=`;
      stop lines on Windows likely say `stopping llama runner subprocess` (NOT `mlx`) —
      confirm segmentation still attributes correctly via start-line handover. If real logs
      break attribution, that's a spec/log-formats.md Ollama-section fix, both readers.
- [ ] Per-model rows show ctx gauge/tok-s (llama.cpp slot lines exist on Windows).

## 5. Safety spot-checks

- [ ] `mklink /J %USERPROFILE%\.claude\projects\evil C:\Windows` (junction) → app ignores it,
      no crash, nothing read behind it. Delete the junction after.
- [ ] Process Monitor (optional): filter Tama.Tray writes → only `%APPDATA%\Tama\*` ever written.
- [ ] No outbound network connections (Resource Monitor / TCPView while app runs).

## 6. Pinned window + settings persistence

- [ ] Pin (footer button or tray menu) → resizable always-on-top window; popover behavior
      unaffected; polling stays at 7 s while pinned open even after opening/closing the popover.
- [ ] Resize + move pinned window → quit → relaunch → frame restored.
- [ ] Change display config trick (if possible, unplug external monitor) → frame clamps
      back on-screen, never opens invisible.
- [ ] Settings: font size S/M/L visibly rescales; persists across restart.
- [ ] Run at login: toggle on → `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` gains
      `Tama` with quoted exe path (check with `reg query`); sign out/in → app starts; toggle
      off → value gone.
- [ ] Quit from tray menu → process exits cleanly (no ghost in Task Manager).

## 7. Floating cat

- [ ] Fresh state (delete `%APPDATA%\Tama\settings.json` first) → launch → the pixel cat appears
      bottom-right of the primary screen's work area (16 px inset), ~120×68, no ground line, no
      "meow~"/z's; walks while a session is live, nap pose otherwise. Not in Alt-Tab, not in the
      taskbar.
- [ ] Left-click the cat → popover opens **beside it** (above; below when the cat is at the top
      edge; left/right on a very short screen). Check at 100 % **and 125 % / 150 %** scaling — the
      popover must be fully on-screen and hugging the cat, and the click must never activate the
      cat (the foreground app's title bar stays lit / its caret keeps blinking).
- [ ] With the popover open: click the desktop → popover closes; click the cat → popover closes
      (toggle) and does NOT immediately reopen.
- [ ] Press-and-release with < 4 px movement = click; ≥ 4 px = drag (no popover toggle). Drag
      by the transparent corner of the 120×68 box (not just the cat's body) also works.
- [ ] Drag to another monitor (mixed DPI if available) → quit → relaunch → same spot. Then
      unplug that monitor → relaunch → cat clamps back onto a connected screen (or the default
      corner) — never invisible. NOTE: if the drag activates the window (popover closes mid-drag)
      or the cat jumps during the drag on 125 %+, report it: this is the DragMove-on-NOACTIVATE
      risk in FloatingCatWindow.xaml.cs.
- [ ] Right-click the cat → the tray's menu (Open / Pin window / ☑ Show floating cat / Settings /
      About / Quit) at the cursor; clicking anywhere outside (including into another app)
      dismisses it. If the menu STAYS open after an outside click, report it (fallback is a
      WPF ContextMenu).
- [ ] Toggle off via the tray item → cat disappears, tray check clears, Settings → WIDGET shows ☐.
      Toggle on via Settings → cat reappears at its last spot, tray check set. Quit → relaunch →
      the chosen state persists. Hidden cat → Task Manager CPU for Tama stays ~0 % (sprite timer
      stopped).

## Results

| Section | Result | Notes |
|---|---|---|
| 0 Build & launch | | |
| 1 Popover | | |
| 2 Log paths | | |
| 3 Live data | | |
| 4 Ollama | | |
| 5 Safety | | |
| 6 Pinned + settings | | |
| 7 Floating cat | | |
