<h1 align="center">tmux-sensei</h1>

<p align="center">
  <em>A tmux config for people who live in scrollback — built for offensive security work, not screenshots.</em><br>
  No plugin manager · no patched font · no <code>curl | bash</code> in the config itself · two files and one auditable script.
</p>

---

## Install

**One line** (convenient):

```sh
curl -fsSL https://raw.githubusercontent.com/sudosuraj/tmux-sensei/main/install.sh | bash
```

**Read-it-first** (the way this config would want you to — see Law #1):

```sh
git clone https://github.com/sudosuraj/tmux-sensei
cd tmux-sensei
less install.sh          # audit it
./install.sh
```

Then:

```sh
exec $SHELL              # picks up PATH + `stty -ixon`
tmux                     # prefix is C-s
```

The installer is idempotent, backs up any existing `~/.config/tmux/tmux.conf`, works on Linux and macOS, and touches nothing outside `~/.config/tmux`, `~/.local/bin`, and two lines in your shell rc. Requires **tmux ≥ 3.3** (developed on 3.4) and bash.

Uninstall anytime: `./uninstall.sh` (restores your previous config from the backup it made).

---

## Why another tmux config

I didn't fork anyone's dotfiles. `tmux-sensei` is built from five opinions, and every default follows from them:

| # | Law | What it buys you |
|---|-----|------------------|
| 1 | **Auditable or it doesn't run.** One config + one script. | You can read the entire thing in an afternoon. No plugin manager pulling code you never see. |
| 2 | **Degrades to a serial console.** 256-colour indices, ASCII status, no glyphs. | Looks identical on your laptop and over a rescue shell into a box you're testing. |
| 3 | **tmux never presses Enter for you.** Anything aimed at a target is *staged*. | Scope mistakes are career events. The tool refuses to make one for you. |
| 4 | **Every session is a case file.** Per-session evidence logging, one keystroke. | Evidence is the default, not something you remember to enable at 3am. |
| 5 | **Experiments run on their own socket.** `tmux -L lab`, loud purple bar. | You break configs constantly and never touch a live engagement. |

---

## What's in the repo

| File | Installs to | Role |
|------|-------------|------|
| `tmux-sensei.conf` | `~/.config/tmux/tmux.conf` | the config |
| `sensei` | `~/.local/bin/sensei` | helper script (logging, cases, staging) |
| `lab.conf` | `~/.config/tmux/lab.conf` | the experiment socket |
| `install.sh` / `uninstall.sh` | — | setup / teardown |
| `local.conf` | `~/.config/tmux/local.conf` | **your** machine-local overrides (created empty, never overwritten) |

---

## The prefix, and nested tmux

`C-b` is gone. The prefix is **`C-s`** — dead weight once `stty -ixon` turns off terminal flow control, which the installer wires up for you.

- **`C-s C-s`** — send a literal prefix through to a nested or remote tmux.
- **`F12`** — hand the keyboard entirely to the inner session. The local tmux goes deaf and its status bar greys out, so you always know which multiplexer you're typing at. `F12` again to take control back.

---

## Key map

Movement is **prefix-free** (Alt) — paying a prefix just to move panes is a tax:

```
M-h M-j M-k M-l     move between panes            M-H M-J M-K M-L   resize
M-1 … M-5           jump to window N              M-o               last window
M-z                 zoom pane                     M-g               scratch popup (persistent)
```

Prefix layer — press **`C-s`** then:

```
|   -        split vertical / horizontal (inherit cwd)     R    reload config
c            new window                                     Q    kill pane   C-q  kill session
Space        enter the sensei MODAL layer (stays until Esc)
t            set @target  (shown in the status bar)        T    STAGE a recon burst for @target
C-l          toggle evidence logging (whole session)       P    dump this pane's scrollback → case file
N            case-notes popup                              C    new case skeleton
a   A        arm / disarm silence-watch (scan-done alert)
E   g        edit-config popup / git popup                 X    open lab socket   C-x  burn the lab
```

### The sensei modal layer (`C-s Space`)

tmux key-tables are the most underused feature in the program: a real modal mode, no plugin required. `C-s Space` enters it and it **stays** until you hit `Esc`, so a burst of window surgery costs one prefix instead of eight.

```
h j k l   move          H J K L   resize          x   kill pane
o         main-vertical  e        tiled            m   swap pane
Esc / q   leave
```

### Copy-mode is a grep layer

Scrollback is evidence. These are the things you actually hunt for in it — one key each, so you never pipe a pane through `grep` just to find an IP. Enter copy-mode with `C-s [`, then:

```
M-i   IPs (+ optional :port)          M-u   URLs
M-x   hashes (md5 / sha)              M-t   tokens & keys (JWT, AWS AKIA, GitHub, PEM)
M-s   secret-ish words (token, api_key, authorization, bearer, password)
M-e   errors (ERROR, Traceback, denied, refused, 403, 500)
v     select      C-v  block-select      y   copy (→ system clipboard via OSC 52, even over SSH)
```

---

## The `sensei` script

Every subcommand is safe to run by hand; the config just binds keys to them. Evidence lands under `~/loot/<session>/` (override with `SENSEI_LOOT`).

```
sensei case <name>            new session: recon / fuzz / shell / notes windows + a loot dir
sensei log toggle <sess>      arm / disarm per-session evidence logging (retro-fits every pane)
sensei dump <pane> <sess>     flush a pane's scrollback into the case dir
sensei burst <sess> <target>  STAGE subfinder → httpx → nuclei → ffuf across 4 panes — no Enter
sensei notes <sess>           open the case notebook (notes.md)
sensei save   [name]          snapshot layout + cwd of every session
sensei restore [name]         rebuild that layout (geometry + cwd only — processes are NOT re-run)
sensei strip <logfile>        ANSI-strip a log for a report
sensei vpn                    the tun/wg indicator shown in the status bar
```

### `sensei burst` — the whole safety philosophy in one command

`C-s t` sets a target; `C-s T` opens a tiled window and **types** a recon chain into four panes:

```
subfinder -silent -d TARGET | anew subs.txt
httpx -l subs.txt -sc -title -tech-detect -o http.txt
nuclei -l http.txt -severity medium,high,critical -o nuclei.txt
ffuf -u https://TARGET/FUZZ -w ~/wl/raft-small.txt -mc all -fc 404 -o ffuf.json
```

…and stops. Nothing runs. You read each command, fix the scope, and press Enter yourself. That's the point: the tool will lay the work out for you but will never fire a scan at a target because you fat-fingered a keybind.

---

## The status bar

Two lines, and the only things that get colour are the ones that can hurt you:

- **top:** a `^` when the prefix is armed · `sensei` + session name · short hostname · **`tgt:<target>`** (peach) when a target is set · **`REC`** (green) when logging is on · the VPN/interface indicator · clock.
- **bottom:** your windows, named by phase. A window that's gone quiet shows `(quiet)` if silence-watch is armed.

Pane borders carry state too: the border and title show what's running, tag `[remote]` on an `ssh` pane, and turn **red** the moment a pane is running `ssh` or `sudo`.

---

## Customising it

**Golden rule: never edit `tmux.conf` directly for machine-specific tweaks.** Put them in `~/.config/tmux/local.conf`, which is sourced last and is never touched by updates. That keeps your fork clean and lets a VPS differ from your laptop with no branch.

Common overrides — drop these in `local.conf`:

```tmux
# prefer a different prefix
set -g prefix C-a
unbind C-s
bind C-a send-prefix

# truecolor terminal? turn it on (kept off by default for Law #2)
set -ga terminal-overrides ',*256col*:Tc'

# move where evidence is written (also honoured by the sensei script via env)
# put `export SENSEI_LOOT=~/engagements` in your shell rc instead, for the script side

# your own colour taste
set -g status-style 'bg=colour236,fg=colour250'
```

Change the **staged recon chain** to match your own workflow: edit the `for c in …` list inside `cmd_burst()` in the `sensei` script. Same shape — one quoted command per pane, and **never add a trailing `\n` / `Enter`** unless you want to throw away Law #3.

Add your own **grep-layer hunts**: copy one of the `bind -T copy-mode-vi M-… search-backward '…'` lines in `tmux-sensei.conf` and swap the regex (tmux search is case-sensitive, so bake case into the pattern).

Add your own **modal keys**: extend the `bind -T sensei …` block. End each binding with `switch-client -T sensei` if you want the layer to stay open after the key.

Reload after any change with **`C-s R`**, or `C-s E` to open the config in an editor and reload on save.

---

## What it deliberately does NOT do

- **No process resurrection.** `restore` rebuilds geometry and cwd; *you* decide what re-runs against a live target.
- **No auto-run of anything network-facing.** `burst` stages and stops.
- **No telemetry, no phone-home, no plugin fetch.** Ever. The only network traffic is the one-time install download you can read first.

---

## Compatibility

Developed and tested on **tmux 3.4**. Uses `pane-border-format`, key-tables, `display-popup`, and two-line `status-format`, so **3.3 is the practical floor**. The `sensei` script needs bash + coreutils — already present on anything you'd run an engagement from. OSC 52 clipboard needs a terminal that supports it (iTerm2, kitty, WezTerm, Windows Terminal, recent xterm).

## License

MIT — do whatever you want, no warranty. If it stages a scan you then run at the wrong scope, that's on you, not the config.
