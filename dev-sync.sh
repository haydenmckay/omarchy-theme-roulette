#!/usr/bin/env bash
# Local dev loop only -- a real user runs `omarchy plugin add <repo-url>
# --enable`, which does a plain `git clone` of this whole repo into the
# destination below. This mirrors that shape via copy instead of clone, so
# edits here don't need a push+reclone cycle to test.
#
# Omarchy's plugin loader rejects symlinks inside a plugin folder (including
# the folder itself being one), so the copy is real -- must re-run after
# editing anything.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/io.github.haydenmckay.theme-roulette"

mkdir -p "$DEST/bin"
cp "$SCRIPT_DIR"/*.json "$SCRIPT_DIR"/*.qml "$DEST"/
cp "$SCRIPT_DIR/bin/theme-roulette" "$DEST/bin/theme-roulette"
chmod +x "$DEST/bin/theme-roulette"
# Convenience symlink onto $PATH for testing `theme-roulette <command>`
# directly from a terminal on this dev machine -- the plugin itself doesn't
# depend on it (Service.qml resolves the CLI from manifest.__sourceDir).
ln -sf "$SCRIPT_DIR/bin/theme-roulette" "$HOME/.local/bin/theme-roulette"

omarchy plugin validate "$DEST"
echo "Installed. Run 'omarchy plugin enable io.github.haydenmckay.theme-roulette' if not already enabled."
