# Privacy Policy

Last updated: 2026-06-21

Tama is a local-only macOS menu-bar app. It does not collect, transmit, sell, rent,
or share personal data.

## What Tama Reads

Tama reads local AI coding-agent logs on your Mac to show active sessions, project
folders, token counts, context usage, model names, and estimated API cost.

The currently supported local paths are:

- `~/.claude/projects/`
- `~/.codex/sessions/`
- `~/.gemini/tmp/`
- `~/.gemini/antigravity-cli/history.jsonl`

These logs can contain project paths, prompt snippets, model names, and token metadata
created by the agent tools you run locally.

## What Tama Sends

Nothing. Tama has no telemetry, analytics, automatic update checks, or in-app network
requests. It does not send log content, usage data, crash reports, identifiers, or
settings to the developer or to any third party.

The About window includes GitHub links. Those links only open when you click them, and
macOS hands the URL to your browser.

## Storage

Tama stores only local UI preferences in macOS `UserDefaults`, such as appearance and
text size. Tama does not create an account, store credentials, or maintain a server-side
profile.

## Control

Because Tama does not collect or receive your data, there is no server-side account,
export, or deletion request to process. You control the local logs through the AI agent
tools that created them, and you can remove Tama by deleting the app from your Mac.

## Contact

Report security issues through the process in [SECURITY.md](SECURITY.md). For other
privacy questions, open a GitHub issue in the repository.
