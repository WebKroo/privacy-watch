# Contributing

Small, focused improvements and reproducible bug reports are welcome. The project is licensed under AGPL-3.0-only; contributions should use that license. Read [LICENSE](LICENSE) before reusing or redistributing code.

For bugs, include the Privacy Watch version, macOS version, Mac architecture, expected behavior, actual behavior and the smallest reproducible steps. Report whether a deliberate sensor test produced a fresh Last verified update. For sleep problems, include approximate sleep/wake times and whether logging was intentionally paused.

Do not upload an unredacted activity history, administrator credentials, bookmarks, root policy files or personal screenshots. Use sample events where possible. See [SECURITY.md](SECURITY.md) for vulnerabilities.

Before a pull request, read [architecture](docs/ARCHITECTURE.md), run the tests relevant to the change, and update documentation when behavior changes. Keep the helper's fixed source and narrow interface, exact signing checks, console-user filtering, safe file handling and explicit Pause/Quit semantics intact. Never describe a simulated lifecycle test as an actual overnight sleep test.

Discuss larger changes before implementing them. A public issue can describe a feature request without including private activity data.
