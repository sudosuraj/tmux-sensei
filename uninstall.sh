#!/usr/bin/env bash
# tmux-sensei uninstaller — removes what install.sh placed, restores backups.
set -eu
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
BIN_DIR="$HOME/.local/bin"
c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }

rm -f "$BIN_DIR/sensei" && c 32 "  ✓ removed sensei"
rm -f "$CFG_DIR/lab.conf"

# restore the most recent backup if one exists, else just remove our config
last="$(ls -1t "$CFG_DIR"/tmux.conf.pre-sensei.* 2>/dev/null | head -1 || true)"
if [ -n "${last:-}" ]; then
  mv "$last" "$CFG_DIR/tmux.conf"; c 32 "  ✓ restored previous config from $(basename "$last")"
else
  rm -f "$CFG_DIR/tmux.conf"; c 32 "  ✓ removed tmux.conf"
fi

c 33 "  ! left in place: $CFG_DIR/local.conf, $CFG_DIR/burst.conf and ~/loot (your overrides + evidence)"
c 33 "  ! remove the 'stty -ixon' / PATH lines from your shell rc by hand if you want them gone"
c 32 "tmux-sensei uninstalled."
if pgrep -x tmux >/dev/null 2>&1; then
  c 33 "  ! a tmux server is still running (this may include unrelated sessions on other sockets)."
  c 33 "    kill the ones you actually want gone yourself, e.g.: tmux kill-server"
fi
