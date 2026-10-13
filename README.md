# Omacast

A Raycast-style launcher for Omarchy v4, inspired by
[Tinycast](https://github.com/abue-ammar/tinycast). One hotkey opens a palette
that searches everything you reach for all day, with Clipboard, Snippets, Emoji
and AI views a Tab away, floating Markdown notes, and a full settings screen.

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
- Snippets, quicklinks and your own commands (with optional terminal output)
- Notes: search them, or `note groceries` to start one in the notes window
- Files with `fd`, from 3 characters, or `f <name>` for files only
- Fallbacks for any query: Ask AI, Search the web, Define word, Create note
- Favorites pinned to the top of the empty palette (→ or Ctrl+K → Add to
  Favorites, or Ctrl+Shift+F), each with its Super+1…9 shortcut, followed by
  recent items and open windows
- Hotkeys shown as keycaps on each row: ones you set in Omacast, and for apps
  the Hyprland binding that launches them (Super+Return for your terminal)

**Clipboard**: Omarchy's clipboard history with a text and image preview.
Enter pastes into the app you came from.

**Snippets**: search, paste, copy, edit, duplicate and create reusable text.
Placeholders follow Raycast: `{clipboard}`, `{date}`, `{time}`, `{datetime}`,
`{day}`, `{uuid}`, `{user}`, `{cursor}`, `{date format="EEE d MMM" offset="+1d"}`,
`{argument name="To" default="team"}` and `{argument name="Tone" options="formal,
casual"}` (asked for before pasting), `{snippet name="sig"}`, and modifiers such
as `{clipboard | trim | uppercase}`. Optional keyword expansion replaces a
keyword like `;sig` as you type it in any app (off by default; see below).

**Emoji**: a searchable grid. Arrow keys move, Enter types the emoji.

**AI**: quick chat with Claude through the Claude Code CLI, using your existing
login. Answers stream in, and follow-ups continue the conversation. Start a
question with `?` from Search to jump straight in.

**Notes** (Super+Alt+N): a floating, pinned window holding one Markdown note at
a time, like Raycast Notes. Formatting is live: type `# `, `- `, `1. `, `[] `,
`> ` or wrap words in `**`, `*`, `` ` `` or `~~`. Notes are plain `.md` files in
`~/notes` and save as you type.

| Notes key | Action |
| --- | --- |
| `Ctrl+N` / `Ctrl+P` | New note / browse and search notes |
| `Ctrl+B` `Ctrl+I` `Ctrl+E` `Ctrl+Shift+X` | Bold, italic, code, strikethrough |
| `Ctrl+Alt+1`–`3`, `Ctrl+Alt+0` | Heading 1–3, plain text |
| `Ctrl+Shift+7` / `8` / `9` | Numbered, bullet, task list |
| `Ctrl+Shift+B` / `Ctrl+Alt+C` | Quote / code block |
| `Ctrl+Enter` or click the box | Toggle a task |
| `Ctrl+L` | Link the selection to the URL on the clipboard |
| `Ctrl+=` / `Ctrl+-` / `Ctrl+0` | Zoom |
| `Esc` | Hide notes |

**Settings** (`Ctrl+,` or search "Settings"), modelled on Raycast and Tinycast:

- General: Omacast, Omarchy menu and notes hotkeys (recorded live), text size,
  expanded or compact window, which monitor, pop to root search delay, Escape
  behaviour
- Search: sensitivity, open windows, calculator, files, fallback commands, web
  search engine, reset ranking
- Extensions: an alias, a hotkey and an on/off switch for every command
- Snippets: keyword expansion, expand within words, disabled apps, Paste or Copy
- Quicklinks and Commands: add, edit and delete
- Notes, Clipboard and AI options; export and import; reset

## Keys

| Key | Action |
| --- | --- |
| `Super+Space` | Open / close Omacast |
| `Super+Alt+Space` | Omarchy menu |
| `↑` `↓` / `Ctrl+N` `Ctrl+P` | Move |
| `Enter` | Primary action |
| `Ctrl+Enter` | Secondary action |
| `→` or `Ctrl+K` | All actions for the selection (`←` closes) |
| `Ctrl+Shift+F` | Add to / remove from Favorites |
| `Ctrl+Alt+↑` / `↓` | Reorder a favorite |
| `Super+1` … `Super+9` | Open favorite 1–9 (while Omacast is open) |
| `Tab` / `Shift+Tab` | Search → Clipboard → Snippets → Emoji → AI |
| `Ctrl+,` | Settings |
| `Ctrl+N` / `Ctrl+E` / `Ctrl+X` (Snippets) | New / edit / delete snippet |
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
and enables it. The installer backs up `~/.config/hypr/bindings.lua` and adds a
small block that loads `~/.config/omacast/hyprland.lua`. Omacast writes that
file from its settings: the Super+Space launcher hotkey (the Omarchy menu moves
to Super+Alt+Space), Super+Alt+N for notes, per-command hotkeys, the notes
window rules and, if enabled, snippet keyword expansion. Running it again is
safe.

Quick AI also needs the [Claude Code](https://claude.com/claude-code) CLI,
signed in. Without it, the rest of Omacast works as usual.

## Update

```bash
omarchy plugin update stefans.omacast --yes
omarchy restart shell
```

## Configure

Use Settings (`Ctrl+,`). It writes `~/.config/omacast/config.jsonc`, which only
holds what you changed; everything else comes from `config.default.jsonc`.
You can also edit the file by hand, and it reloads live. Snippets live in
`~/.config/omacast/snippets.json`, notes in `~/notes`.

Give any command a hotkey in Settings › Extensions, or call it from your own
bindings with `omacast run <row id>` (for example `window.left-half` or
`system.lock`). `omacast clipboard`, `omacast snippets` and `omacast ai` open
Omacast straight into those views.

## Snippet keyword expansion

Off by default. When you turn it on (Settings › Snippets), Omacast loads a small
Hyprland Lua hook that watches key presses, keeps only the last few typed
characters in memory (never on disk), and replaces a snippet keyword with the
snippet as soon as you finish typing it. It skips the apps listed under
Disabled Apps (password managers by default), resets on Enter, Tab, shortcuts
and window switches, and maps keys with a US layout, so keywords typed on
other layouts may not match.

## Tests

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

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
