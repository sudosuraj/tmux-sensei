#!/usr/bin/env bash
# tmux-sensei installer / updater
#
# Safe by construction: everything is downloaded to a temp dir FIRST. If any file
# fails to fetch, nothing installed is touched — no half-updated state. On a
# re-run it acts as an updater: only files that actually changed are swapped, and
# if nothing changed it says so and exits. Linux + macOS, bash or zsh.
#
#   Install / update : curl -fsSL https://raw.githubusercontent.com/sudosuraj/tmux-sensei/main/install.sh | bash
#   Audit first      : git clone https://github.com/sudosuraj/tmux-sensei && cd tmux-sensei && ./install.sh
#   Or once installed: sensei update
set -eu

# ── where the raw files live (only used when piped, not from a clone) ─────────
REPO="${SENSEI_REPO:-sudosuraj/tmux-sensei}"     # override: SENSEI_REPO=you/tmux-sensei
BRANCH="${SENSEI_BRANCH:-main}"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

FILES="tmux-sensei.conf lab.conf sensei"

# ── targets ───────────────────────────────────────────────────────────────────
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
BIN_DIR="$HOME/.local/bin"
STAMP="$(date -u +%Y%m%d%H%M%S)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-sensei.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

c()   { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok()  { c '32' "  ✓ $1"; }
info(){ c '36' "→ $1"; }
warn(){ c '33' "  ! $1"; }
die() { c '31' "✗ $1"; exit 1; }

# map a shipped filename to where it gets installed
dest_of() {
  case "$1" in
    sensei) printf '%s/sensei' "$BIN_DIR" ;;
    tmux-sensei.conf) printf '%s/tmux.conf' "$CFG_DIR" ;;
    *) printf '%s/%s' "$CFG_DIR" "$1" ;;
  esac
}

# ── 1. preflight ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null 2>&1 || die "tmux not found — install it first (apt/brew/pkg install tmux)"
TV="$(tmux -V | sed 's/tmux //; s/[a-z-].*//')"
case "$TV" in
  1.*|2.*|3.0|3.1|3.2) warn "tmux $TV — sensei targets >= 3.3; some features may misbehave" ;;
  *) ok "tmux $TV" ;;
esac
command -v bash >/dev/null 2>&1 || die "bash required for the sensei helper script"

# detect a fresh install vs an update
MODE="install"
[ -f "$BIN_DIR/sensei" ] && grep -qs 'tmux-sensei' "$CFG_DIR/tmux.conf" 2>/dev/null && MODE="update"
[ "$MODE" = "update" ] && info "existing install found — checking for updates" || info "tmux-sensei installer"

# fetcher: prefer a local clone, else curl/wget
have_local=0
[ -f "./tmux-sensei.conf" ] && [ -f "./sensei" ] && have_local=1
DL=""
if [ "$have_local" -eq 0 ]; then
  if command -v curl >/dev/null 2>&1; then DL="curl -fsSL";
  elif command -v wget >/dev/null 2>&1; then DL="wget -qO-";
  else die "need curl or wget (or run this from a git clone)"; fi
fi

# ── 2. STAGE everything to temp first — a failure here touches nothing installed ─
for f in $FILES; do
  if [ "$have_local" -eq 1 ]; then
    [ -f "./$f" ] || die "missing local file: $f (incomplete clone?)"
    cp "./$f" "$TMP/$f"
  else
    $DL "$BASE/$f" > "$TMP/$f" || die "download failed: $f (check SENSEI_REPO=$REPO branch=$BRANCH)"
    [ -s "$TMP/$f" ] || die "downloaded empty file: $f (does it exist on '$BRANCH'?)"
  fi
done
ok "fetched $(echo $FILES | wc -w | tr -d ' ') files to a staging dir"

# ── 3. diff staged vs installed; build the changed list ───────────────────────
changed=""
for f in $FILES; do
  d="$(dest_of "$f")"
  if [ ! -f "$d" ] || ! cmp -s "$TMP/$f" "$d"; then changed="$changed $f"; fi
done
changed="${changed# }"

if [ "$MODE" = "update" ] && [ -z "$changed" ]; then
  ok "already up to date — nothing changed"
  exit 0
fi

# ── 4. lay files down (back up only a FOREIGN pre-existing config) ────────────
mkdir -p "$CFG_DIR" "$BIN_DIR"
backup() {
  if [ -e "$1" ] && [ ! -L "$1" ] && ! grep -qs 'tmux-sensei' "$1"; then
    mv "$1" "$1.pre-sensei.$STAMP"
    warn "backed up your existing $(basename "$1") -> $(basename "$1").pre-sensei.$STAMP"
  fi
}
backup "$CFG_DIR/tmux.conf"

for f in $changed; do
  d="$(dest_of "$f")"
  m=644; [ "$f" = sensei ] && m=755
  install -m "$m" "$TMP/$f" "$d"
  verb="installed"; [ "$MODE" = update ] && verb="updated"
  ok "$verb: ${d/#$HOME/~}"
done

# never overwrite the user's overrides file
[ -f "$CFG_DIR/local.conf" ] || {
  printf '# machine-local overrides — never touched by updates. Put your tweaks here.\n' > "$CFG_DIR/local.conf"
  ok "created local.conf for your overrides"
}

# burst.conf: your own recon chains for `sensei burst` (prefix T). Created once,
# never touched by updates, and ships with NO active profile — sensei has no
# opinion about which tools you run. Uncomment the example or write your own.
[ -f "$CFG_DIR/burst.conf" ] || {
  cat > "$CFG_DIR/burst.conf" <<'BURSTEOF'
# tmux-sensei burst profiles — created once, never touched by updates.
#
# `sensei burst` (prefix T) stages a chain of commands into tiled panes for
# whatever @target you've set. Nothing here ever runs on its own — tmux only
# *types* these commands (Law #3): you read them, fix the scope, and press
# Enter yourself.
#
# Format:
#   [profile-name]
#   one command per line — {target} is replaced with your @target
#   lines starting with # and blank lines are ignored
#
# One pane opens per command line — as many or as few as you write. Define as
# many [profiles] as you want (web, ad, internal, whatever fits the engagement)
# and burst will offer a pick-list whenever more than one exists.
#
# Nothing is active by default. Uncomment to try the example, or replace it
# with your own from scratch.
#
# [web]
# subfinder -silent -d {target} | anew subs.txt
# httpx -l subs.txt -sc -title -tech-detect -o http.txt
# nuclei -l http.txt -severity medium,high,critical -o nuclei.txt
# ffuf -u https://{target}/FUZZ -w ~/wl/raft-small.txt -mc all -fc 404 -o ffuf.json
#
# [ad]
# nmap -sC -sV -oA nmap-{target} {target}
# netexec smb {target} -u '' -p '' --shares
# enum4linux-ng -A {target}
BURSTEOF
  ok "created burst.conf (no active profile — see the file for the format)"
}

# ── 5. shell wiring (idempotent — added once, ever) ───────────────────────────
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

# ── 6. live-reload a running tmux, so an update takes effect now ───────────────
if tmux info >/dev/null 2>&1; then
  tmux source-file "$CFG_DIR/tmux.conf" 2>/dev/null && ok "reloaded your running tmux server"
fi

# ── 7. done ───────────────────────────────────────────────────────────────────
echo
if [ "$MODE" = "update" ]; then
  c '32' "tmux-sensei updated: $changed"
  echo
  info "the new sensei script is live immediately."
  echo "   if you were inside tmux, press  C-s R  to load new key bindings."
else
  c '32' "tmux-sensei installed."
  echo
  info "next:"
  echo "   1. reload your shell:   exec \$SHELL     (picks up PATH + stty)"
  echo "   2. start tmux:          tmux"
  echo "   3. prefix is C-s. Try:  C-s ?   (all keys)   C-s Space  (sensei layer)"
  echo "   4. first case:          sensei case acme.tld"
  echo "   5. update later:        sensei update"
fi
echo
[ "${NEED_RELOAD:-0}" = "1" ] && warn "~/.local/bin was just added to PATH — run 'exec \$SHELL' before calling sensei"
c '90' "config: $CFG_DIR/tmux.conf   ·   overrides: $CFG_DIR/local.conf   ·   update: sensei update"
