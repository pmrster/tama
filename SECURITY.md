# Security Policy

Tama is a local-only macOS menu-bar app. Its security goal is simple: read local
agent logs without modifying files, executing commands, or sending data anywhere.

## Supported Versions

Only the latest published source is supported before a stable release process
exists.

## Reporting Issues

If you find a security issue, please use GitHub's private vulnerability reporting
for this repository if it is enabled. If private reporting is not available, open
a minimal public issue that says a security report is available, without posting
sensitive exploit details.

## Design Guarantees

- No network calls or telemetry.
- No shell command execution in the running app.
- No writes to agent log directories.
- No privileged helper, root requirement, or background daemon.
- File readers reject symlinks, non-regular files, and oversized logs.

These guarantees are covered by unit tests where practical.
