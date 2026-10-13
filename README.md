# Omacast

A Raycast-style launcher for Omarchy v4, inspired by
[Tinycast](https://github.com/abue-ammar/tinycast). One hotkey opens a palette
that searches everything you reach for all day, with Clipboard, Emoji and AI
views a Tab away.

## What it does

**Search** (Super+Space)

- Apps, with a "Running" marker for apps that have open windows
- Open windows: switch to them, bring them here, close, or quit the app
- Every Omarchy menu command and submenu, with live ✓ state
- Window layouts: halves, quarters, thirds, maximize, center, fullscreen,
  float/tile, pin, move to workspace 1–9, next display
- System: lock, sleep, restart, shut down, log out, mute, mic, nightlight, idle,
  Bluetooth, empty trash, screenshot
- Calculator with units and currency, powered by `qalc`: `5 km to mi`,
  `12% of 340`, `100 usd to eur`
- Quicklinks: `gh quickshell`, `yt lofi`, `aw hyprland`, `aur helium`
- Snippets that paste into the focused app, with `{date}`, `{clipboard}` and
  other placeholders
- Your own commands, with optional terminal output
- Notes (Markdown in `~/notes`): `note groceries` creates one and opens your editor
- Files with `fd`, from 3 characters, or `f <name>` for files only
- Fallbacks for any query: Ask AI, Search the web, Define word, Create note
- Recent items and favorites when the query is empty

**Clipboard**: Omarchy's clipboard history with a text and image preview.
Enter pastes into the app you came from.

**Emoji**: a searchable grid. Arrow keys move, Enter types the emoji.

**AI**: quick chat with Claude through the Claude Code CLI, using your existing
login. Answers stream in, and follow-ups continue the conversation. Start a
question with `?` from Search to jump straight in.

## Keys

| Key | Action |
| --- | --- |
| `Super+Space` | Open / close Omacast |
| `Super+Alt+Space` | Omarchy menu |
| `↑` `↓` / `Ctrl+N` `Ctrl+P` | Move |
| `Enter` | Primary action |
| `Ctrl+Enter` | Secondary action |
| `Ctrl+K` | All actions for the selection |
| `Tab` / `Shift+Tab` | Search → Clipboard → Emoji → AI |
| `Esc` | Clear the query, go back, then close |
| `Ctrl+N` (AI) | New chat |

## Install

```bash
omarchy pkg add libqalculate fd wtype wl-clipboard jq curl
omarchy plugin add https://github.com/stefansdev/omacast.git --enable --yes
~/.config/omarchy/plugins/stefans.omacast/bin/install
```

The first command installs the requirements (most are already on Omarchy).
The second clones the plugin into `~/.config/omarchy/plugins/stefans.omacast`
and enables it. The installer backs up `~/.config/hypr/bindings.lua`, binds
Super+Space (moving the Omarchy menu to Super+Alt+Space), links `omacast` into
`~/.local/bin` and seeds `~/.config/omacast/config.jsonc`. Running it again is
safe.

Quick AI also needs the [Claude Code](https://claude.com/claude-code) CLI,
signed in. Without it, the rest of Omacast works as usual.

## Update

```bash
omarchy plugin update stefans.omacast --yes
omarchy restart shell
```

## Configure

Edit `~/.config/omacast/config.jsonc` (or search "Omacast Settings"). It
reloads live. You can set quicklinks, snippets, custom commands, favorite
apps, file search roots, the notes folder, the AI model, and the web search
URL. See `config.default.jsonc` for the full format.

## Hotkeys for anything

Any result can be run directly, so you can bind it in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + LEFT", "Left half", "omacast run window.left-half")
o.bind("SUPER + CTRL + V", "Clipboard", "omacast clipboard")
o.bind("SUPER + CTRL + A", "Ask AI", "omacast ai")
```

Row ids look like `window.left-half`, `system.lock`, `custom.<name-slug>`,
`snippet.<keyword>`, `omarchy.<menu id>` and `app.<desktop id>`.

## Develop

To work from a local checkout instead, link it into place:

```bash
git clone git@github.com:stefansdev/omacast.git ~/Work/omarchy/omacast
ln -sfn ~/Work/omarchy/omacast ~/.config/omarchy/plugins/stefans.omacast
omarchy plugin enable stefans.omacast
```

Omacast is a `keepLoaded` plugin, so code changes need `omarchy restart shell`.
Config changes apply live.

## Remove

```bash
~/.config/omarchy/plugins/stefans.omacast/bin/uninstall
omarchy plugin remove stefans.omacast --yes
```

## License

MIT
