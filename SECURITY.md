# Security Policy

Tama is a local-only macOS menu-bar app. Its security goal is simple: read local
agent logs without modifying files, executing commands, or sending data anywhere.
The app does not phone home; the only network-adjacent behavior is when a user clicks
an About-window link and macOS opens GitHub in the user's browser.

## Supported Versions

Only the latest published source is supported before a stable release process
exists.

## Reporting Issues

If you find a security issue, please use GitHub's private vulnerability reporting
for this repository if it is enabled. If private reporting is not available, open
a minimal public issue that says a security report is available, without posting
sensitive exploit details.

## Design Guarantees

- No automatic network calls, telemetry, or update checks.
- No shell command execution in the running app.
- No writes to agent log directories.
- No privileged helper, root requirement, or background daemon.
- File readers reject symlinks, non-regular files, and oversized logs.

These guarantees are covered by unit tests where practical.

For data-handling details, see [PRIVACY.md](PRIVACY.md).
