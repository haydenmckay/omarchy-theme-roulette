# CLAUDE.md

Guidance for Claude Code when working on this project.

## Project: omarchy-theme-roulette

**Type**: Omarchy Quickshell plugin + CLI
**Created**: 2026-08-16

## Development

```bash
./install.sh                        # sync into the live plugin dir + validate + symlink CLI
theme-roulette status               # inspect current state
theme-roulette reroll               # force a roll from a terminal
omarchy plugin validate ~/.config/omarchy/plugins/io.github.haydenmckay.theme-roulette
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Service.qml
```

## Architecture

Same CLI-owns-facts / QML-just-mirrors split as `omarchy-media-pip` and
`omarchy-agent-butler`. See README.md for the full design.

- `bin/theme-roulette` -- does everything real: picks a theme+wallpaper
  (avoiding repeats), applies via `omarchy theme set` / `omarchy theme bg
  set`, computes the next scheduled roll, writes
  `~/.local/state/omarchy-theme-roulette/state.json`.
- `Service.qml` -- mirrors state.json/config.json via FileView, polls
  `check-due` every 30s (that's what makes scheduled rolls fire on
  their own), self-stages the CLI (see below).
- `BarWidget.qml` -- dice icon; click reroll()s and opens Panel.qml.
- `Panel.qml` -- shows the roll, dice button to reroll again. Loaded via a
  `Loader` from BarWidget.qml, not declared as its own manifest "panel"
  kind -- see the note in BarWidget.qml's header comment; grepping every
  first-party manifest.json under `$OMARCHY_PATH/shell` found zero plugins
  that combine `bar-widget` with a standalone `panel` kind for this shape.

## Key gotcha: CLI must run from a staged copy, not the plugin dir

A companion CLI binary living inside an *installed* plugin's own directory
cannot be launched via Quickshell's `Process` when loaded through
`PluginRegistry.qml` -- fails with "Process failed to start, likely because
the binary could not be found" even though the exact same path runs fine
from a terminal. This was root-caused as far as `omarchy-media-pip` got
(not fully solved, see that project's notes) and the workaround is the same
here: `Service.qml.restage()` copies `bin/theme-roulette` to
`~/.local/state/omarchy-theme-roulette/.bin/theme-roulette` the instant
`manifest.__sourceDir` is known, and every `Process` invocation uses that
staged path, gated on `cliStaged`. Re-stages on every shell start so it
can't go stale across `omarchy plugin update`. If you add a new CLI
invocation, route it through `Service.run()` -- don't add a new `Process`
that points at `sourceDir` directly, it will silently fail to launch once
this is a real (non-symlinked) install.

## Notes

- `omarchy theme set <kebab-name>` is slow (10-20s): it runs a batch of
  app-restart hooks in parallel (terminal, btop, browser, vscode, etc.)
  before returning. That's expected -- don't add a timeout expecting it to
  return quickly, and don't background it, since the reroll needs it to
  have actually finished before recording state.
- Tested end-to-end on this machine with the real `$HOME` paths: reroll
  applies a real theme+wallpaper change, avoid-repeat correctly skips the
  immediately-previous theme, and all three schedule modes
  (`random-interval`, `fixed-daily`, `specific-days`) compute sane
  `nextRollAt` values. Do **not** re-test by overriding `XDG_CONFIG_HOME`/
  `XDG_STATE_HOME` globally in a shell that also runs `omarchy theme set` --
  that env var also redirects Brave's profile dir, which made
  `omarchy-theme-set-browser` spin up a brand-new browser profile from
  scratch mid-test and looked like a hang. Test config isolation some other
  way (e.g. read the script's `CONFIG_FILE`/`STATE_FILE` computation
  separately) if you need it, or just use the real `$HOME` -- the commands
  are safe, idempotent, and exactly what production use looks like.
- `omarchy theme dir <name>` and theme names throughout are kebab-case
  (e.g. `tokyo-night`); `omarchy theme set` itself lowercases and
  dash-joins whatever you pass it, so passing kebab through directly is a
  no-op conversion, not a workaround.
- `fixedTime` in config.json is passed straight to `date -d "today $fixedTime"`,
  so both `"9:00 AM"` and `"21:00"` work with no parsing of our own.
