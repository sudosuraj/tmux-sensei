<h1 align="center">tmux-sensei</h1>

<p align="center">
  <em>A tmux config for people who live in scrollback — built for offensive security work, not screenshots.</em><br>
  No plugin manager · no patched font · no <code>curl | bash</code> in the config itself · two files and one auditable script.
</p>

<p align="center">
  <img src="wiki/images/demo.gif" alt="sensei's dynamic Tab-completion, live in tmux" width="720">
</p>

<p align="center">
  📖 <strong><a href="wiki/tmux-sensei-blog.md">Read the full walkthrough</a></strong> — philosophy, every feature, every keybind, with screenshots.
</p>

---

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/sudosuraj/tmux-sensei/main/install.sh | bash
```

Prefer to read it first (see Law #1 in the wiki)?

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

Idempotent, backs up any existing `~/.config/tmux/tmux.conf`, Linux + macOS, touches nothing outside `~/.config/tmux`, `~/.local/bin`, and two lines in your shell rc. Requires **tmux ≥ 3.3** (developed on 3.4) and bash. Uninstall anytime with `./uninstall.sh`.

---

## What it is, in one breath

Five opinions drive every default — full reasoning in the [wiki](wiki/tmux-sensei-blog.md):

1. **Auditable or it doesn't run** — one config, one script, readable in an afternoon.
2. **Degrades to a serial console** — 256-colour, ASCII, no glyphs.
3. **tmux never presses Enter for you** — anything aimed at a target is staged, never fired.
4. **Every session is a case file** — evidence logging is one keystroke.
5. **Experiments run on their own socket** — break things without touching a live engagement.

On top of that: a modal pane-management layer, per-session evidence logging, staged recon chains (`sensei burst`), a grep-layer for scrollback (IPs, hashes, tokens, secrets, errors — one key each), and fully dynamic, zero-config argument help — `sensei args` / `C-s H` / real Tab-completion that works on *any* tool on your `$PATH` by asking the tool itself, with no built-in list to maintain.

For the full keymap, every `sensei` subcommand, and how to customise it — see the **[wiki](wiki/tmux-sensei-blog.md)**.

---

## What's in the repo

| File | Installs to | Role |
|------|-------------|------|
| `tmux-sensei.conf` | `~/.config/tmux/tmux.conf` | the config |
| `sensei` | `~/.local/bin/sensei` | helper script |
| `lab.conf` | `~/.config/tmux/lab.conf` | the experiment socket |
| `install.sh` / `uninstall.sh` | — | setup / teardown |

## Compatibility

tmux **≥ 3.3** (developed on 3.4), bash + coreutils. OSC 52 clipboard needs a terminal that supports it (iTerm2, kitty, WezTerm, Windows Terminal, recent xterm).

## License

MIT — do whatever you want, no warranty. If it stages a scan you then run at the wrong scope, that's on you, not the config.
