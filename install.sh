#!/usr/bin/env bash
# tmux-sensei installer
# Idempotent. Backs up whatever it replaces. Works from a git clone (uses local
# files) or piped from curl (downloads raw files). Linux + macOS, bash or zsh.
#
#   Convenience : curl -fsSL https://raw.githubusercontent.com/sudosuraj/tmux-sensei/main/install.sh | bash
#   Auditable   : git clone https://github.com/sudosuraj/tmux-sensei && cd tmux-sensei && ./install.sh
set -eu

# ── where the raw files live (only used when piped, not from a clone) ─────────
REPO="${SENSEI_REPO:-sudosuraj/tmux-sensei}"     # <-- override: SENSEI_REPO=you/tmux-sensei
BRANCH="${SENSEI_BRANCH:-main}"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# ── targets ───────────────────────────────────────────────────────────────────
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
BIN_DIR="$HOME/.local/bin"
STAMP="$(date -u +%Y%m%d%H%M%S)"

c()  { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok() { c '32' "  ✓ $1"; }
info(){ c '36' "→ $1"; }
warn(){ c '33' "  ! $1"; }
die(){ c '31' "✗ $1"; exit 1; }

info "tmux-sensei installer"

# ── 1. preflight ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null 2>&1 || die "tmux not found — install it first (apt/brew/pkg install tmux)"
TV="$(tmux -V | sed 's/tmux //; s/[a-z-].*//')"
case "$TV" in
  1.*|2.*|3.0|3.1|3.2) warn "tmux $TV detected — sensei targets >= 3.3; some features may misbehave" ;;
  *) ok "tmux $TV" ;;
esac
command -v bash >/dev/null 2>&1 || die "bash required for the sensei helper script"

# fetcher: prefer local clone, fall back to curl/wget
have_local=0
[ -f "./tmux-sensei.conf" ] && [ -f "./sensei" ] && have_local=1
DL=""
if [ "$have_local" -eq 0 ]; then
  if command -v curl >/dev/null 2>&1; then DL="curl -fsSL";
  elif command -v wget >/dev/null 2>&1; then DL="wget -qO-";
  else die "need curl or wget to download (or run this from a git clone)"; fi
fi

fetch() { # fetch <name> <dest>
  if [ "$have_local" -eq 1 ]; then cp "./$1" "$2";
  else $DL "$BASE/$1" > "$2" || die "download failed: $1 (check SENSEI_REPO=$REPO)"; fi
}

# ── 2. lay down files, backing up anything we overwrite ───────────────────────
mkdir -p "$CFG_DIR" "$BIN_DIR"

backup() { # backup <path>
  # skip if it's already ours (re-run) or absent; back up anything else
  if [ -e "$1" ] && [ ! -L "$1" ]; then
    if grep -qs 'tmux-sensei' "$1"; then return 0; fi
    mv "$1" "$1.pre-sensei.$STAMP"; warn "backed up existing $(basename "$1") -> $(basename "$1").pre-sensei.$STAMP";
  fi
}

backup "$CFG_DIR/tmux.conf"
fetch tmux-sensei.conf "$CFG_DIR/tmux.conf";   ok "config  -> $CFG_DIR/tmux.conf"
fetch lab.conf         "$CFG_DIR/lab.conf";     ok "lab     -> $CFG_DIR/lab.conf"
fetch sensei           "$BIN_DIR/sensei"; chmod +x "$BIN_DIR/sensei"; ok "script  -> $BIN_DIR/sensei"

# empty local override file so `source-file -q ~/.config/tmux/local.conf` never warns
[ -f "$CFG_DIR/local.conf" ] || { printf '# machine-local overrides — not tracked by the repo\n' > "$CFG_DIR/local.conf"; ok "created empty local.conf for your overrides"; }

# ── 3. shell wiring: PATH + free up C-s ───────────────────────────────────────
detect_rc() {
  case "${SHELL##*/}" in
    zsh)  printf '%s' "$HOME/.zshrc" ;;
    bash) [ -f "$HOME/.bashrc" ] && printf '%s' "$HOME/.bashrc" || printf '%s' "$HOME/.bash_profile" ;;
    *)    printf '%s' "$HOME/.profile" ;;
  esac
}
RC="$(detect_rc)"; touch "$RC"

add_line() { grep -qsF -- "$1" "$RC" || { printf '\n%s\n' "$1" >> "$RC"; ok "added to $(basename "$RC"): $2"; }; }

case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) add_line 'export PATH="$HOME/.local/bin:$PATH"' "~/.local/bin on PATH"; NEED_RELOAD=1 ;; esac
add_line 'stty -ixon 2>/dev/null   # free C-s for the tmux-sensei prefix' "stty -ixon (frees C-s)"

# ── 4. done ───────────────────────────────────────────────────────────────────
echo
c '32' "tmux-sensei installed."
echo
info "next:"
echo "   1. reload your shell:   exec \$SHELL     (picks up PATH + stty)"
echo "   2. start tmux:          tmux"
echo "   3. prefix is C-s. Try:  C-s ?   (all keys)   C-s Space  (sensei layer)"
echo "   4. first case:          sensei case acme.tld"
echo
[ "${NEED_RELOAD:-0}" = "1" ] && warn "~/.local/bin was added to PATH — run 'exec \$SHELL' before calling sensei"
c '90' "config: $CFG_DIR/tmux.conf   ·   overrides: $CFG_DIR/local.conf   ·   uninstall: see README"
