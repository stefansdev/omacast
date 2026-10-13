import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "lib/Engine.js" as Engine
import "lib/Snippets.js" as Snippets
import "components"
import "file:///usr/share/omarchy/shell/plugins/menu/MenuModel.js" as MenuModel
import "file:///usr/share/omarchy/shell/services/AppSearch.js" as AppSearch

// Omacast — a Raycast/Tinycast-style launcher for Omarchy.
//
// One palette that searches apps, open windows, Omarchy commands, window
// layouts, system actions, quicklinks, snippets, custom commands, notes and
// files, with an inline calculator and fallbacks (AI, web, dictionary). Tab
// cycles to the Clipboard, Emoji and AI views. Ctrl+K opens the action panel.
Item {
  id: root

  // Injected by omarchy-shell.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property var shell: null
  property var manifest: null

  // Apps come straight from DesktopEntries with Omarchy's own hidden-entry
  // rules, launch command and uninstall script, so Omacast does not depend on
  // the host's scoped app-library facade.
  property var hiddenAppIds: ({})
  property var configuredHiddenIds: ({})
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omacast/config.jsonc"
  readonly property string snippetsPath: home + "/.config/omacast/snippets.json"
  readonly property string hyprPath: home + "/.config/omacast/hyprland.lua"
  readonly property string version: "0.2.0"
  readonly property string stateDir: home + "/.local/state/omacast"

  function bin(name) {
    return decodeURIComponent(String(Qt.resolvedUrl("bin/" + name)).replace(/^file:\/\//, ""))
  }

  // ------------------------------------------------------------- appearance
  readonly property string fontFamily: (root.config.ui && root.config.ui.font) || Quickshell.env("OMACAST_FONT") || "SF Pro Text"
  readonly property string monoFamily: "JetBrainsMono Nerd Font"
  readonly property string iconFamily: "JetBrainsMono Nerd Font"
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color faint: Util.alpha(foreground, 0.08)
  readonly property color hover: Util.alpha(foreground, 0.085)
  // Text size setting: Default / Large / Larger.
  readonly property real ts: {
    var size = (root.config.general && root.config.general.textSize) || "default"
    return size === "larger" ? 1.25 : (size === "large" ? 1.12 : 1.0)
  }
  function fs(px) { return Math.round(px * root.ts) }
  readonly property bool wideMode: root.mode === "settings" || root.mode === "snippet-edit"
  readonly property bool compact: ((root.config.general && root.config.general.windowMode) === "compact")
    && root.mode === "search" && root.query.length === 0
    && !(root.config.general.showFavoritesInCompact !== false && root.favoriteRows().length > 0)
  readonly property int cardWidth: Math.min(Style.space(root.wideMode ? 980 : 780) * (root.wideMode ? 1 : root.ts), panel.width - Style.space(40))
  readonly property int fullHeight: Math.min(Style.space(root.wideMode ? 640 : 520) * (root.wideMode ? 1 : Math.min(root.ts, 1.15)), panel.height - Style.space(80))
  readonly property int cardHeight: root.compact ? root.headerHeight + Border.top(root.borderSpec) + Border.bottom(root.borderSpec) : root.fullHeight
  readonly property int cardRadius: Style.cornerRadius
  // The theme's menu border (colour and width). Surfaces keep its widths as
  // insets but draw it themselves as a fading GradientBorder.
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property var insetSpec: ({ color: "transparent", widths: root.borderSpec.widths, gradient: null })
  readonly property color borderColor: Border.color(root.borderSpec)
  readonly property real borderWidth: Border.top(root.borderSpec)
  readonly property int headerHeight: Math.round(Style.space(58) * Math.min(root.ts, 1.15))
  readonly property int footerHeight: Style.space(42)
  readonly property int rowHeight: Math.round(Style.space(44) * root.ts)
  readonly property int sectionHeight: Style.space(30)
  readonly property int calcHeight: Style.space(88)
  readonly property int emojiColumns: 10

  // ------------------------------------------------------------------ state
  property bool opened: false
  property string mode: "search" // search | clipboard | snippets | emoji | ai | detail | settings | snippet-edit | snippet-args
  readonly property var tabs: [
    { mode: "search", label: "Search", glyph: "" },
    { mode: "clipboard", label: "Clipboard", glyph: "󰅌" },
    { mode: "snippets", label: "Snippets", glyph: "󰅪" },
    { mode: "emoji", label: "Emoji", glyph: "󰞅" },
    { mode: "ai", label: "AI", glyph: "󰚩" }
  ]
  property string query: ""
  property var rows: []
  property int selectedIndex: -1
  property bool actionsOpen: false
  property int actionIndex: 0
  property var pendingConfirm: null

  property var config: ({})
  property var defaultConfig: ({})
  property var userConfig: ({})
  property var usage: ({})

  property var appRows: []
  property var windowRows: []
  property var omarchyRows: []
  property var configRows: []
  property var noteRows: []
  property var fileRows: []
  property string fileRowsQuery: ""
  property bool filesBusy: false
  readonly property var layoutRows: Engine.windowLayoutRows()
  readonly property var systemRows: Engine.systemRows()
  property var appIconByClass: ({})
  property var appNameByClass: ({})
  property var runningClasses: ({})
  property string targetAddress: ""
  property string targetTitle: ""

  property var calc: null

  property var clipboardHistory: []
  property var emojiData: []
  property var emojiResults: []

  property var menuDefaultItems: []
  property var menuUserItems: []
  property var menuWhen: ({})
  property var menuChecked: ({})

  // Snippets live in their own file so the settings UI can rewrite config
  // without touching them.
  property var snippets: []
  property bool snippetsLoaded: false
  property var snippetDraft: null       // { index, name, keyword, text }
  property var snippetArgs: []          // [{ name, value, options }]
  property var snippetPending: null     // { snippet, delete }
  property bool recording: false
  property var hyprBinds: ({})      // lowercased description → "SUPER + SHIFT + B"
  property var defaultApps: ({})    // browser / terminal / files → desktop id
  property real closedAt: 0
  property string lastMode: "search"
  property string lastQuery: ""

  property var conversation: []
  property string aiSession: ""
  property bool aiBusy: false
  property string aiStatus: ""

  property string detailTitle: ""
  property string detailText: ""
  property bool detailBusy: false

  readonly property var selectedRow: (root.selectedIndex >= 0 && root.selectedIndex < root.rows.length) ? root.rows[root.selectedIndex] : null
  readonly property var selectedActions: {
    if (root.mode === "ai") return root.aiActions()
    if (root.mode === "detail") return [
      { title: "Copy Definition", op: "copy", arg: root.detailText },
      { title: "Back to Search", op: "mode", arg: "search" }
    ]
    if (root.mode === "emoji") {
      var e = root.emojiResults[root.selectedIndex]
      return e ? [
        { title: "Insert Emoji", op: "emoji", arg: e.e },
        { title: "Copy Emoji", op: "copy", arg: e.e }
      ] : []
    }
    var row = root.selectedRow
    return row && row.actions ? row.actions : []
  }

  // ---------------------------------------------------------- lifecycle
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.actionsOpen = false
    root.pendingConfirm = null

    // Pop to root: keep the last view and query for a while after closing.
    var keep = (root.config.general && root.config.general.popToRoot) || 0
    var elapsed = (Date.now() - root.closedAt) / 1000
    var restore = (keep < 0 || (keep > 0 && elapsed < keep)) && !payload.mode && !payload.query
    if (!restore || root.lastMode === "snippet-args" || root.lastMode === "snippet-edit") {
      root.calc = null
      root.fileRows = []
      root.fileRowsQuery = ""
      root.mode = "search"
      root.query = ""
      input.text = ""
    }
    root.pickScreen()
    root.opened = true
    root.enterLauncherSubmap(true)
    bindsProc.running = true

    root.buildApps()
    clientsProc.running = false
    clientsProc.running = true
    notesWin.refreshList()

    var requested = String(payload.mode || "search")
    if (requested !== "search") root.setMode(requested)
    if (payload.query) {
      input.text = String(payload.query)
      root.setQuery(input.text)
    }
    if (payload.ask) root.perform(null, { op: "ai", arg: String(payload.ask) })
    if (payload.define) root.define(String(payload.define))
    root.rebuild()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    // A running AI answer keeps streaming; it is there when you come back.
    if (root.recording) root.setRecording(false)
    if (root.opened) root.enterLauncherSubmap(false)
    root.opened = false
    root.actionsOpen = false
    root.pendingConfirm = null
    root.closedAt = Date.now()
    root.lastMode = root.mode
  }

  // Show on: focused monitor (default), the monitor under the mouse, or primary.
  property var targetScreen: null
  function pickScreen() {
    var where = (root.config.general && root.config.general.showOn) || "focused"
    var screens = Quickshell.screens || []
    if (screens.length === 0) return
    if (where === "primary") { root.targetScreen = screens[0]; return }
    var name = ""
    if (where === "cursor") {
      cursorMonitorProc.running = true
      return
    }
    var focused = Hyprland.focusedMonitor
    name = focused ? focused.name : ""
    root.targetScreen = screens.filter(function(s) { return s.name === name })[0] || screens[0]
  }

  Process {
    id: cursorMonitorProc
    command: ["bash", "-c", "read -r x y < <(hyprctl cursorpos | tr -d ','); hyprctl monitors -j | jq -r --argjson x \"$x\" --argjson y \"$y\" 'first(.[] | select($x >= .x and $x < .x + .width / .scale and $y >= .y and $y < .y + .height / .scale)) | .name'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var name = String(this.text || "").trim()
        var screens = Quickshell.screens || []
        root.targetScreen = screens.filter(function(s) { return s.name === name })[0] || screens[0]
      }
    }
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // `omarchy-shell shell call stefans.omacast run '<row id>'` runs a command
  // without showing the palette, so any result can get its own hotkey.
  function run(id) {
    // No palette means no captured target: window actions use the focused window.
    root.targetAddress = ""
    root.buildApps()
    var rows = root.catalog()
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id === id && rows[i].actions && rows[i].actions.length) {
        root.perform(rows[i], rows[i].actions[0])
        return "ok"
      }
    }
    return "unknown"
  }

  function ping() { return "ok" }

  // Used by bin/install: write ~/.config/omacast/hyprland.lua now.
  function writeHyprland() {
    var lua = root.hyprLua()
    root.lastHyprLua = lua
    hyprFile.setText(lua)
    return "ok"
  }

  function settings(section) {
    root.open("{}")
    root.setMode("settings")
    if (section) settingsView.section = section
    return "ok"
  }

  // -------------------------------------------------------------- catalog
  function rawCatalog() {
    return root.appRows.concat(root.windowRows, root.omarchyRows, root.configRows,
      root.noteRows, root.layoutRows, root.systemRows)
  }

  // The searchable catalog: hidden commands removed, aliases added as
  // keywords, and the shared Favorites / Configure actions appended.
  function catalog() {
    var rows = root.rawCatalog()
    var overrides = root.config.overrides || {}
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var ov = overrides[row.id]
      if (ov && ov.disabled) continue
      out.push(root.decorate(row, ov))
    }
    return out
  }

  function decorate(row, ov) {
    if (row.kind === "window" || row.kind === "file" || row.kind === "clip") return row
    var copy = {}
    for (var k in row) copy[k] = row[k]
    if (ov && ov.alias) {
      copy.alias = ov.alias
      copy.keywords = (row.keywords || []).concat([ov.alias])
    }
    // Favorites sit right after the primary and secondary actions, like Raycast.
    var base = row.actions || []
    var fav = root.isFavorite(row.id)
    var favActions = [{ title: fav ? "Remove from Favorites" : "Add to Favorites", op: "favorite", arg: row.id, key: "Ctrl ⇧ F" }]
    if (fav) {
      favActions.push({ title: "Move Up in Favorites", op: "favorite-move", arg: row.id, arg2: -1, key: "Ctrl Alt ↑" })
      favActions.push({ title: "Move Down in Favorites", op: "favorite-move", arg: row.id, arg2: 1, key: "Ctrl Alt ↓" })
    }
    copy.actions = base.slice(0, 2).concat(favActions, base.slice(2), [
      { title: "Configure Alias & Hotkey…", op: "configure", arg: row.title }
    ])
    return copy
  }

  // ---------------------------------------------------- shortcut keycaps
  // A row's hotkey: Super+N for the first nine favorites, then one set in
  // Omacast, then (apps only) a Hyprland binding whose description names the
  // app — your "Ghostty" binding, or Omarchy's Browser / Terminal / File
  // manager bindings for the default apps.
  function hotkeyFor(row) {
    if (!row) return ""
    if (row.favIndex) return "SUPER + " + row.favIndex
    var ov = (root.config.overrides || {})[row.id]
    if (ov && ov.hotkey) return ov.hotkey
    var title = String(row.title || "").toLowerCase()
    if (row.kind === "app") {
      var base = String(row.appId || "").replace(/\.desktop$/, "")
      if (base && base === root.defaultApps.browser && root.hyprBinds["browser"]) return root.hyprBinds["browser"]
      if (base && base === root.defaultApps.terminal && root.hyprBinds["terminal"]) return root.hyprBinds["terminal"]
      if (base && base === root.defaultApps.files && root.hyprBinds["file manager"]) return root.hyprBinds["file manager"]
      return root.hyprBinds[title] || root.hyprBinds[title.replace(/ browser$/, "")] || ""
    }
    // Commands only show hotkeys set in Omacast: matching Hyprland bindings by
    // name gives false hits (Omarchy's "Grok" default-agent row vs. the Grok app).
    return ""
  }

  function keyParts(keys) {
    return String(keys || "").split("+").map(function(p) { return p.trim() }).filter(function(p) { return p.length > 0 })
  }

  function prettyKey(part) {
    var p = String(part).toUpperCase()
    var map = { "SUPER": "Super", "CTRL": "Ctrl", "CONTROL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift",
      "SPACE": "Space", "RETURN": "↵", "ENTER": "↵", "ESCAPE": "Esc", "PERIOD": ".", "COMMA": ",", "SLASH": "/",
      "SEMICOLON": ";", "MINUS": "-", "EQUAL": "=", "BRACKETLEFT": "[", "BRACKETRIGHT": "]", "BACKSLASH": "\\",
      "GRAVE": "`", "APOSTROPHE": "'", "LEFT": "←", "RIGHT": "→", "UP": "↑", "DOWN": "↓", "TAB": "Tab",
      "DELETE": "Del", "BACKSPACE": "⌫", "PRINT": "Print", "PRIOR": "PgUp", "NEXT": "PgDn" }
    return map[p] || (p.length === 1 ? p : String(part).charAt(0).toUpperCase() + String(part).substring(1).toLowerCase())
  }

  function bindKeys(b) {
    var mods = []
    var m = b.modmask || 0
    if (m & 64) mods.push("SUPER")
    if (m & 4) mods.push("CTRL")
    if (m & 8) mods.push("ALT")
    if (m & 1) mods.push("SHIFT")
    var key = String(b.key || "")
    var code = key.match(/^code:(\d+)$/)
    if (code) {
      var digits = { "10": "1", "11": "2", "12": "3", "13": "4", "14": "5", "15": "6", "16": "7", "17": "8", "18": "9", "19": "0", "20": "MINUS", "21": "EQUAL", "49": "GRAVE", "59": "COMMA", "60": "PERIOD", "61": "SLASH" }
      key = digits[code[1]] || ""
    }
    if (!key || key.indexOf("mouse") === 0) return ""
    return mods.concat([key.toUpperCase()]).join(" + ")
  }

  Process {
    id: bindsProc
    command: ["bash", "-c", "hyprctl binds -j; echo '@@OMACAST@@'; xdg-settings get default-web-browser 2>/dev/null; grep -v '^#' \"$HOME/.config/xdg-terminals.list\" 2>/dev/null | head -1; xdg-mime query default inode/directory 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(this.text || "").split("@@OMACAST@@")
        var binds = []
        try { binds = JSON.parse(parts[0]) } catch (e) { binds = [] }
        var map = ({})
        var rank = ({})
        for (var i = 0; i < binds.length; i++) {
          var b = binds[i]
          if (b.submap || !b.description || b.release || b.mouse) continue
          var keys = root.bindKeys(b)
          if (!keys) continue
          var d = String(b.description).toLowerCase()
          // Later definitions (your own bindings) win over Omarchy's defaults.
          var order = Number(b.arg) || i
          if (rank[d] === undefined || order >= rank[d]) { map[d] = keys; rank[d] = order }
        }
        root.hyprBinds = map
        var lines = (parts[1] || "").trim().split("\n")
        var strip = function(v) { return String(v || "").trim().replace(/\.desktop$/, "") }
        root.defaultApps = { browser: strip(lines[0]), terminal: strip(lines[1]), files: strip(lines[2]) }
      }
    }
  }

  // Super+1…9 run favorites while Omacast is open. Hyprland normally takes
  // Super+digit for workspaces, so the launcher enters a small submap
  // ("omacast", defined in hyprland.lua) while it is visible.
  function enterLauncherSubmap(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", on ? "hl.dsp.submap(\"omacast\")" : "hl.dsp.submap(\"reset\")"])
  }

  function openFavorite(n) {
    var favs = root.favoriteRows()
    var row = favs[Number(n) - 1]
    if (!row || !row.actions || row.actions.length === 0) return "unknown"
    root.perform(row, row.actions[0])
    return "ok"
  }

  function moveFavorite(id, delta) {
    var fav = (root.config.favorites || []).slice()
    var at = fav.indexOf(id)
    var to = at + delta
    if (at < 0 || to < 0 || to >= fav.length) return
    fav.splice(at, 1)
    fav.splice(to, 0, id)
    root.setSetting("favorites", fav)
  }

  // Rebuild and put the cursor back on the row with this id.
  function rebuildKeeping(id) {
    root.rebuild()
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].id === id) {
        root.selectedIndex = i
        resultList.positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
  }

  // Rows the Extensions settings list (grouped, filterable).
  function extensionRows(filter) {
    var groups = [
      { title: "Applications", kinds: ["app"] },
      { title: "Omacast", kinds: ["builtin"] },
      { title: "Omarchy", kinds: ["command", "menu"] },
      { title: "Window Management", kinds: ["window-action"] },
      { title: "System", kinds: ["system"] },
      { title: "Quicklinks", kinds: ["quicklink"] },
      { title: "Snippets", kinds: ["snippet"] },
      { title: "Commands", kinds: ["custom"] }
    ]
    var rows = root.rawCatalog()
    var q = String(filter || "").toLowerCase()
    var out = []
    for (var g = 0; g < groups.length; g++) {
      var items = rows.filter(function(r) {
        if (groups[g].kinds.indexOf(r.kind) < 0) return false
        return !q || String(r.title).toLowerCase().indexOf(q) >= 0 || String(r.subtitle || "").toLowerCase().indexOf(q) >= 0
      })
      if (items.length === 0) continue
      out.push({ id: "group." + g, kind: "group", title: groups[g].title + " (" + items.length + ")" })
      out = out.concat(items.slice(0, q ? 200 : 120))
    }
    return out
  }

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    return value.slice(-8) === ".desktop" ? value.slice(0, -8) : value
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  function buildApps() {
    var values = DesktopEntries.applications.values || []
    var list = AppSearch.sortedEntries(values, "", function(entry) {
      var id = root.normalizeDesktopId(entry && entry.id)
      return root.hiddenAppIds[id] === true || root.configuredHiddenIds[id] === true
    })
    var out = []
    var byClass = ({})
    var names = ({})
    for (var i = 0; i < list.length; i++) {
      var entry = list[i].entry
      var id = String(entry.id || "")
      if (!id) continue
      var src = root.iconSource(entry.icon)
      var base = root.normalizeDesktopId(id).toLowerCase()
      if (src) byClass[base] = src
      var startup = String(entry.startupClass || "").toLowerCase()
      if (startup && src) byClass[startup] = src
      var keywords = [base]
      try {
        if (entry.keywords) for (var k = 0; k < entry.keywords.length; k++) keywords.push(String(entry.keywords[k]))
      } catch (err) { }
      var name = AppSearch.entryName(entry)
      if (src) byClass["name:" + name.toLowerCase()] = src
      names[base] = name
      if (startup) names[startup] = name
      out.push({
        id: "app." + id,
        kind: "app",
        appId: id,
        classKeys: [base, startup],
        title: name,
        subtitle: AppSearch.entrySubtext(entry),
        accessory: "Application",
        image: src,
        keywords: keywords,
        actions: [
          { title: "Open Application", op: "app", arg: id },
          { title: "Copy Desktop ID", op: "copy", arg: id },
          { title: "Uninstall Application…", op: "uninstall", arg: id }
        ]
      })
    }
    root.appRows = out
    root.appIconByClass = byClass
    root.appNameByClass = names
  }

  function launchApp(id, name) {
    var desktopId = root.normalizeDesktopId(id)
    if (!desktopId) return
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(desktopId + ".desktop"))
  }

  function removeApp(id, name) {
    var desktopId = root.normalizeDesktopId(id)
    if (!desktopId) return
    Util.execDetached(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(desktopId) + " " + Util.shellQuote(String(name || desktopId)))
  }

  function prettyClass(cls) {
    var parts = String(cls || "").split(".")
    var last = parts[parts.length - 1] || cls
    return last.charAt(0).toUpperCase() + last.substring(1)
  }

  function applyClients(raw) {
    var split = String(raw || "").split("@@OMACAST@@")
    var active = null
    var clients = []
    try { active = JSON.parse(split[0]) } catch (e) { active = null }
    try { clients = JSON.parse(split[1] || "[]") } catch (e) { clients = [] }

    root.targetAddress = active && active.address ? String(active.address) : ""
    root.targetTitle = active && active.title ? String(active.title) : ""

    clients.sort(function(a, b) { return (a.focusHistoryID || 0) - (b.focusHistoryID || 0) })
    var rows = []
    var running = ({})
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      if (c.hidden || c.mapped === false) continue
      var cls = String(c.class || "")
      if (!cls) continue
      running[cls.toLowerCase()] = true
      var key = cls.toLowerCase()
      var src = root.appIconByClass[key] || root.appIconByClass[key.split(".").pop()]
        || root.appIconByClass["name:" + String(c.initialTitle || "").toLowerCase()] || ""
      var ws = c.workspace && c.workspace.name ? String(c.workspace.name) : ""
      rows.push({
        id: "win." + c.address,
        kind: "window",
        title: String(c.title || cls),
        subtitle: (root.appNameByClass[key] || root.prettyClass(cls)) + (ws ? " · Workspace " + ws : ""),
        accessory: "Window",
        image: src,
        glyph: "󰖯",
        keywords: [cls, root.appNameByClass[key] || root.prettyClass(cls)],
        actions: [
          { title: "Switch to Window", op: "focus", arg: c.address },
          { title: "Bring to This Workspace", op: "window-at", arg: "bring-here", arg2: c.address },
          { title: "Close Window", op: "window-at", arg: "close", arg2: c.address },
          { title: "Quit " + (root.appNameByClass[key] || root.prettyClass(cls)), op: "window-at", arg: "quit-app", arg2: c.address }
        ]
      })
    }
    root.windowRows = rows
    root.runningClasses = running
    root.refreshKeepingSelection()
  }

  function isRunning(row) {
    if (!row || row.kind !== "app" || !row.classKeys) return false
    for (var i = 0; i < row.classKeys.length; i++) {
      var key = row.classKeys[i]
      if (key && root.runningClasses[key]) return true
    }
    return false
  }

  function menuVisible(items, order, entry) {
    var current = entry
    var guard = 0
    while (current && current.id !== "root" && guard++ < 32) {
      if (current.when && root.menuWhen[current.id] === false) return false
      current = items[current.parent]
    }
    return MenuModel.isVisible(items, order, root.menuWhen, entry)
  }

  function buildOmarchyRows() {
    var merged = MenuModel.mergeMenuSources(root.menuDefaultItems, root.menuUserItems)
    var items = merged.items
    var order = merged.itemOrder
    var rows = []
    for (var i = 0; i < order.length; i++) {
      var id = order[i]
      var e = items[id]
      if (!e || id === "root" || id === "apps" || id.indexOf("apps.") === 0) continue
      if (e.provider) continue
      if (!root.menuVisible(items, order, e)) continue
      var path = MenuModel.parentPathFor(items, id)
      var label = MenuModel.labelFor(e, root.menuChecked)
      var keywords = (e.aliases || []).concat([e.description || "", path, "omarchy"])
      if (e.kind === "action") {
        rows.push({
          id: "omarchy." + id,
          kind: "command",
          title: label,
          subtitle: path ? "Omarchy › " + path : "Omarchy",
          accessory: "Command",
          glyph: e.icon,
          glyphFont: e.iconFont,
          keywords: keywords,
          actions: [
            { title: "Run Command", op: "exec", arg: e.action },
            { title: "Copy Shell Command", op: "copy", arg: e.action }
          ]
        })
      } else {
        rows.push({
          id: "omarchy." + id,
          kind: "menu",
          title: label,
          subtitle: path ? "Omarchy › " + path : "Omarchy",
          accessory: "Menu",
          glyph: e.icon,
          glyphFont: e.iconFont,
          keywords: keywords,
          actions: [{ title: "Open in Omarchy Menu", op: "menu", arg: e.kind === "link" ? e.target : id }]
        })
      }
    }
    root.omarchyRows = rows
    if (root.opened) root.refreshKeepingSelection()
  }

  function homepage(url) {
    var m = String(url || "").match(/^https?:\/\/[^\/?#]+/)
    return m ? m[0] : String(url || "")
  }

  function buildConfigRows() {
    var c = root.config
    var rows = []
    var i

    var quicklinks = c.quicklinks || []
    for (i = 0; i < quicklinks.length; i++) {
      var q = quicklinks[i]
      rows.push({
        id: "quicklink." + (q.keyword || Engine.slug(q.name)),
        kind: "quicklink",
        title: q.name,
        subtitle: q.keyword ? "Type “" + q.keyword + " …”" : "Quicklink",
        accessory: "Quicklink",
        glyph: q.icon || "󰌷",
        keywords: [q.keyword || "", "link search"],
        actions: [
          { title: "Search…", op: "prefill", arg: (q.keyword || q.name) + " " },
          { title: "Open Homepage", op: "url", arg: root.homepage(q.url) }
        ]
      })
    }

    for (i = 0; i < root.snippets.length; i++)
      rows.push(root.snippetRow(root.snippets[i], i))

    var commands = c.commands || []
    for (i = 0; i < commands.length; i++) {
      var cmd = commands[i]
      rows.push({
        id: "custom." + (cmd.id || Engine.slug(cmd.name)),
        kind: "custom",
        title: cmd.name,
        subtitle: cmd.command,
        accessory: "Command",
        glyph: cmd.icon || "\uf120",
        keywords: [cmd.keyword || "", "custom"],
        actions: [
          { title: "Run Command", op: cmd.terminal ? "terminal" : "exec", arg: cmd.command },
          { title: "Copy Shell Command", op: "copy", arg: cmd.command }
        ]
      })
    }

    rows.push({ id: "mode.clipboard", kind: "builtin", title: "Clipboard History", subtitle: "Search and paste what you copied", accessory: "Omacast", glyph: "󰅌", keywords: ["paste history copy"], actions: [{ title: "Open Clipboard History", op: "mode", arg: "clipboard" }] })
    rows.push({ id: "mode.emoji", kind: "builtin", title: "Search Emoji", subtitle: "Insert emoji into the focused app", accessory: "Omacast", glyph: "󰞅", keywords: ["emoji smiley symbols"], actions: [{ title: "Open Emoji Picker", op: "mode", arg: "emoji" }] })
    rows.push({ id: "mode.ai", kind: "builtin", title: "Ask AI", subtitle: "Chat with Claude", accessory: "Omacast", glyph: "󰚩", keywords: ["ai chat claude question"], actions: [{ title: "Open AI Chat", op: "mode", arg: "ai" }] })
    rows.push({ id: "builtin.note", kind: "builtin", title: "Create Note", subtitle: "Type “note …”", accessory: "Omacast", glyph: "󱞁", keywords: ["note new markdown"], actions: [{ title: "Create Note…", op: "prefill", arg: "note " }] })
    rows.push({ id: "builtin.define", kind: "builtin", title: "Define Word", subtitle: "Type “define …”", accessory: "Omacast", glyph: "󰂺", keywords: ["dictionary meaning"], actions: [{ title: "Define…", op: "prefill", arg: "define " }] })
    rows.push({ id: "builtin.files", kind: "builtin", title: "Search Files", subtitle: "Type “f …”", accessory: "Omacast", glyph: "󰈞", keywords: ["find file folder"], actions: [{ title: "Search Files…", op: "prefill", arg: "f " }] })
    rows.push({ id: "mode.snippets", kind: "builtin", title: "Search Snippets", subtitle: "Paste, edit and create snippets", accessory: "Omacast", glyph: "󰅪", keywords: ["snippet text expander"], actions: [{ title: "Open Snippets", op: "mode", arg: "snippets" }] })
    rows.push({ id: "builtin.snippet-new", kind: "builtin", title: "Create Snippet", subtitle: "Reusable text with placeholders", accessory: "Omacast", glyph: "󰅪", keywords: ["new snippet"], actions: [{ title: "Create Snippet", op: "snippet-new" }] })
    rows.push({ id: "builtin.notes", kind: "builtin", title: "Notes", subtitle: "Floating Markdown notes", accessory: "Omacast", glyph: "󱞁", keywords: ["notes scratchpad markdown floating"], actions: [{ title: "Show Notes", op: "notes" }, { title: "Create Note", op: "note-create", arg: "" }] })
    rows.push({ id: "builtin.notes-search", kind: "builtin", title: "Search Notes", subtitle: "Browse your notes", accessory: "Omacast", glyph: "󱞁", keywords: ["find notes"], actions: [{ title: "Browse Notes", op: "notes-browse" }] })
    rows.push({ id: "mode.settings", kind: "builtin", title: "Omacast Settings", subtitle: "Hotkeys, search, snippets, notes, AI", accessory: "Omacast", glyph: "\uf013", keywords: ["preferences config extensions"], actions: [{ title: "Open Settings", op: "mode", arg: "settings" }, { title: "Edit Config File", op: "edit-file", arg: root.configPath }] })

    root.configRows = rows
    if (root.opened) root.refreshKeepingSelection()
  }

  function snippetRow(s, i) {
    var copyFirst = (root.config.snippetSettings || {}).primaryAction === "copy"
    var paste = { title: "Paste Snippet", op: "snippet", arg: i }
    var copy = { title: "Copy Snippet", op: "snippet-copy", arg: i }
    return {
      id: "snippet." + (s.keyword || Engine.slug(s.name)),
      kind: "snippet",
      index: i,
      title: s.name,
      subtitle: Snippets.preview(s.text),
      accessory: s.keyword ? s.keyword : "Snippet",
      glyph: "󰅪",
      text: s.text,
      keywords: [s.keyword || "", "snippet"],
      actions: (copyFirst ? [copy, paste] : [paste, copy]).concat([
        { title: "Edit Snippet", op: "snippet-edit", arg: i },
        { title: "Duplicate Snippet", op: "snippet-duplicate", arg: i },
        { title: "Create Snippet", op: "snippet-new" },
        { title: "Delete Snippet…", op: "snippet-delete", arg: i }
      ])
    }
  }

  // Favorites are row ids; plain desktop ids from older configs still work.
  function favoriteRows() {
    var fav = root.config.favorites || []
    if (fav.length === 0) return []
    var rows = root.catalog()
    var byId = ({})
    for (var r = 0; r < rows.length; r++) byId[rows[r].id] = rows[r]
    var out = []
    for (var i = 0; i < fav.length; i++) {
      var id = String(fav[i])
      var row = byId[id] || byId["app." + id] || byId["app." + id + ".desktop"]
      if (row) out.push(row)
    }
    return out
  }

  // ------------------------------------------------------------- rebuilds
  function header(title) {
    return { id: "header." + title, kind: "header", title: title }
  }

  function pushSection(out, title, list) {
    if (!list || list.length === 0) return
    out.push(root.header(title))
    for (var i = 0; i < list.length; i++) out.push(list[i])
  }

  function rebuild() {
    if (root.mode === "search") root.rebuildSearch()
    else if (root.mode === "clipboard") root.rebuildClipboard()
    else if (root.mode === "snippets") root.rebuildSnippets()
    else if (root.mode === "emoji") root.rebuildEmoji()
  }

  function rebuildSnippets() {
    var q = root.query.trim().toLowerCase()
    var rows = []
    for (var i = 0; i < root.snippets.length; i++) {
      var s = root.snippets[i]
      var hay = (s.name + " " + (s.keyword || "") + " " + s.text).toLowerCase()
      if (q && hay.indexOf(q) < 0) continue
      rows.push(root.snippetRow(s, i))
    }
    rows.push({
      id: "snippet-create",
      kind: "builtin",
      title: q ? "Create Snippet “" + root.query.trim() + "”" : "Create Snippet",
      subtitle: "Ctrl+N",
      glyph: "\uf067",
      actions: [{ title: "Create Snippet", op: "snippet-new" }]
    })
    root.setRows(rows)
  }

  function rebuildSearch() {
    var q = root.query.trim()
    var out = []

    if (!q) {
      var seen = ({})
      var fav = root.favoriteRows().map(function(r, n) {
        var c = {}
        for (var k in r) c[k] = r[k]
        if (n < 9) c.favIndex = n + 1
        return c
      })
      for (var f = 0; f < fav.length; f++) seen[fav[f].id] = true
      root.pushSection(out, "Favorites", fav)
      var recentAll = Engine.recentRows(root.catalog(), root.usage, 14)
      var recent = []
      for (var r = 0; r < recentAll.length && recent.length < 7; r++) {
        if (recentAll[r].kind === "window" || seen[recentAll[r].id]) continue
        recent.push(recentAll[r])
      }
      root.pushSection(out, "Recent", recent)
      if (root.searchOpt("windows", true)) root.pushSection(out, "Open Windows", root.windowRows.slice(0, 8))
      var suggestions = []
      for (var s = 0; s < root.configRows.length; s++) {
        if (root.configRows[s].kind === "builtin" && suggestions.length < 4) suggestions.push(root.configRows[s])
      }
      root.pushSection(out, "Suggestions", suggestions)
      root.setRows(out)
      return
    }

    var kw = Engine.splitKeyword(q)
    var keyword = kw.keyword.toLowerCase()
    var lead = []
    if (kw.rest) {
      var quicklinks = root.config.quicklinks || []
      for (var i = 0; i < quicklinks.length; i++) {
        var ql = quicklinks[i]
        if (String(ql.keyword || "").toLowerCase() !== keyword) continue
        var url = Engine.fillTemplate(ql.url, kw.rest)
        lead.push({
          id: "quicklink." + ql.keyword,
          kind: "quicklink",
          title: ql.name + ": " + kw.rest,
          subtitle: url,
          accessory: "Quicklink",
          glyph: ql.icon || "󰌷",
          actions: [
            { title: "Open in Browser", op: "url", arg: url },
            { title: "Copy URL", op: "copy", arg: url }
          ]
        })
      }
      if (keyword === "define") lead.push(root.defineRow(kw.rest))
      if (keyword === "note") lead.push(root.createNoteRow(kw.rest))
      if (keyword === "ai" || keyword === "ask") lead.push(root.askRow(kw.rest))
    }
    if (q[0] === "?" && q.length > 1) lead.push(root.askRow(q.substring(1).trim()))

    if (root.searchOpt("calculator", true) && root.calc && root.calc.query === q) {
      out.push(root.header("Calculator"))
      out.push({
        id: "calc",
        kind: "calc",
        title: root.calc.result,
        subtitle: root.calc.input,
        actions: [
          { title: "Copy Answer", op: "copy", arg: root.calc.value },
          { title: "Paste Answer", op: "paste", arg: root.calc.value },
          { title: "Copy Expression", op: "copy", arg: root.calc.input + " = " + root.calc.result }
        ]
      })
    }
    root.pushSection(out, "Quick Action", lead)

    var filesOnly = keyword === "f" && kw.rest.length > 0
    var pool = root.catalog()
    if (!root.searchOpt("windows", true)) pool = pool.filter(function(r) { return r.kind !== "window" })
    if (!filesOnly) root.pushSection(out, "Results", Engine.rank(pool, q, root.usage, 40, root.searchOpt("sensitivity", "medium")))
    if (root.fileRows.length > 0 && root.fileRowsQuery === root.fileQuery()) root.pushSection(out, "Files", root.fileRows)

    var enabled = root.searchOpt("fallbacks", ["ai", "web", "define", "note"])
    var fallbacks = []
    if (enabled.indexOf("ai") >= 0 && (root.config.ai === undefined || root.config.ai.enabled !== false)) fallbacks.push(root.askRow(q))
    var searchUrl = Engine.fillTemplate((root.config.search && root.config.search.url) || "https://www.google.com/search?q={query}", q)
    if (enabled.indexOf("web") >= 0) fallbacks.push({
      id: "fallback.web",
      kind: "fallback",
      title: "Search the Web for “" + q + "”",
      subtitle: root.homepage(searchUrl).replace(/^https?:\/\//, ""),
      accessory: "Web",
      glyph: "󰖟",
      actions: [{ title: "Search the Web", op: "url", arg: searchUrl }]
    })
    if (enabled.indexOf("define") >= 0 && /^[A-Za-z][A-Za-z'\-]{1,40}$/.test(q)) fallbacks.push(root.defineRow(q))
    if (enabled.indexOf("note") >= 0 && keyword !== "note") fallbacks.push(root.createNoteRow(q))
    root.pushSection(out, "Use “" + (q.length > 32 ? q.substring(0, 32) + "…" : q) + "” with…", fallbacks)

    root.setRows(out)
  }

  function searchOpt(key, fallback) {
    var s = root.config.search || {}
    return s[key] === undefined ? fallback : s[key]
  }

  function askRow(text) {
    return {
      id: "fallback.ai",
      kind: "fallback",
      title: "Ask AI “" + text + "”",
      subtitle: "Claude " + ((root.config.ai && root.config.ai.model) || "haiku"),
      accessory: "AI",
      glyph: "󰚩",
      actions: [{ title: "Ask AI", op: "ai", arg: text }]
    }
  }

  function defineRow(word) {
    return {
      id: "fallback.define",
      kind: "fallback",
      title: "Define “" + word + "”",
      subtitle: "Dictionary",
      accessory: "Dictionary",
      glyph: "󰂺",
      actions: [{ title: "Show Definition", op: "define", arg: word }]
    }
  }

  function createNoteRow(title) {
    return {
      id: "fallback.note",
      kind: "fallback",
      title: "Create Note “" + title + "”",
      subtitle: root.notesDir().replace(root.home, "~"),
      accessory: "Note",
      glyph: "󱞁",
      actions: [{ title: "Create Note", op: "note-create", arg: title }]
    }
  }

  function rebuildClipboard() {
    var q = root.query.trim().toLowerCase()
    var out = []
    var history = root.clipboardHistory
    for (var i = 0; i < history.length && out.length < 200; i++) {
      var e = history[i]
      if (e.type === "image") {
        if (q && "image".indexOf(q) < 0) continue
        out.push({
          id: "clip." + i, kind: "clip", clipType: "image", index: i,
          title: "Image", subtitle: e.capturedAt || "", glyph: "󰋩",
          image: Util.fileUrl(e.path), path: e.path, mime: e.mime,
          actions: [
            { title: "Paste Image", op: "clip-paste", arg: i },
            { title: "Copy to Clipboard", op: "clip-copy", arg: i },
            { title: "Open Image", op: "open-file", arg: e.path }
          ]
        })
      } else {
        var text = String(e.text || "")
        if (q && text.toLowerCase().indexOf(q) < 0) continue
        var line = text.replace(/^\s+/, "").split("\n")[0].substring(0, 160)
        var lines = text.split("\n").length
        var isUrl = /^https?:\/\/\S+$/.test(text.trim())
        var actions = root.clipCopyFirst()
          ? [{ title: "Copy to Clipboard", op: "clip-copy", arg: i }, { title: "Paste", op: "clip-paste", arg: i }]
          : [{ title: "Paste", op: "clip-paste", arg: i }, { title: "Copy to Clipboard", op: "clip-copy", arg: i }]
        if (isUrl) actions.push({ title: "Open Link", op: "url", arg: text.trim() })
        out.push({
          id: "clip." + i, kind: "clip", clipType: "text", index: i,
          title: line || "(whitespace)",
          subtitle: text.length + " characters" + (lines > 1 ? " · " + lines + " lines" : ""),
          glyph: isUrl ? "󰌷" : "󰦨",
          text: text,
          actions: actions
        })
      }
    }
    root.setRows(out)
  }

  function clipCopyFirst() {
    return (root.config.clipboard || {}).primaryAction === "copy"
  }

  function rebuildEmoji() {
    var words = root.query.trim().toLowerCase().split(/\s+/).filter(function(w) { return w.length > 0 })
    var out = []
    for (var i = 0; i < root.emojiData.length && out.length < 600; i++) {
      var item = root.emojiData[i]
      var ok = true
      for (var w = 0; w < words.length; w++) {
        if (item.k.indexOf(words[w]) < 0) { ok = false; break }
      }
      if (ok) out.push(item)
    }
    root.emojiResults = out
    root.rows = []
    root.selectedIndex = out.length > 0 ? 0 : -1
    emojiGrid.positionViewAtBeginning()
  }

  // Results that arrive late (files, calculator, window list) must not yank
  // the cursor or close the action panel; a new query or view resets both.
  property bool keepSelection: false

  function refreshKeepingSelection() {
    root.keepSelection = true
    root.rebuild()
    root.keepSelection = false
  }

  function setRows(out) {
    var prevId = root.selectedRow ? root.selectedRow.id : ""
    var keep = root.keepSelection && prevId !== ""
    var contentY = resultList.contentY
    root.rows = out
    root.selectedIndex = -1
    if (keep) {
      for (var k = 0; k < out.length; k++) {
        if (out[k].id === prevId && out[k].kind !== "header") { root.selectedIndex = k; break }
      }
    }
    if (root.selectedIndex >= 0) {
      Qt.callLater(function() { resultList.contentY = contentY })
      return
    }
    for (var i = 0; i < out.length; i++) {
      if (out[i].kind !== "header") { root.selectedIndex = i; break }
    }
    root.actionsOpen = false
    Qt.callLater(function() { resultList.positionViewAtBeginning() })
  }

  // ------------------------------------------------------------ navigation
  function move(delta) {
    if (root.mode === "emoji") {
      var count = root.emojiResults.length
      if (count === 0) return
      root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + delta))
      emojiGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
      return
    }
    if (root.rows.length === 0) return
    var i = root.selectedIndex
    var step = delta > 0 ? 1 : -1
    var remaining = Math.abs(delta)
    var guard = 0
    while (remaining > 0 && guard++ < 500) {
      var next = i + step
      if (next < 0 || next >= root.rows.length) {
        if (Math.abs(delta) > 1) break
        next = next < 0 ? root.rows.length - 1 : 0
      }
      i = next
      if (root.rows[i].kind !== "header") remaining--
    }
    if (root.rows[i] && root.rows[i].kind !== "header") root.selectedIndex = i
    if (root.selectedIndex <= 1) resultList.positionViewAtBeginning()
    else resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setMode(next) {
    if (next === root.mode) return
    if (root.recording) root.setRecording(false)
    root.mode = next
    root.actionsOpen = false
    if (next !== "detail") {
      input.text = ""
      root.query = ""
    }
    if (next === "snippet-edit") Qt.callLater(function() { snippetName.focusInput() })
    if (next === "snippet-args") Qt.callLater(function() { argsRepeater.focusFirst() })
    if (next === "emoji" && root.emojiData.length === 0) emojiFile.reload()
    root.rebuild()
    if (next !== "snippet-edit" && next !== "snippet-args") Qt.callLater(function() { input.forceActiveFocus() })
  }

  function cycleMode(delta) {
    var modes = root.tabs.map(function(t) { return t.mode })
    var base = (root.mode === "detail" || root.mode === "settings") ? "search"
      : (root.mode === "snippet-edit" || root.mode === "snippet-args") ? "snippets" : root.mode
    var at = modes.indexOf(base)
    root.setMode(modes[(at + delta + modes.length) % modes.length])
  }

  function setQuery(text) {
    root.query = text
    if (root.mode === "ai" || root.mode === "detail") return
    root.rebuild()
    if (root.mode !== "search") return

    var q = text.trim()
    if (root.searchOpt("calculator", true) && Engine.isCalcQuery(q)) calcTimer.restart()
    else root.calc = null

    var fq = root.fileQuery()
    if (root.searchOpt("files", true) && fq.length >= root.searchOpt("fileMinChars", 3)) fileTimer.restart()
    else { root.fileRows = []; root.fileRowsQuery = "" }
  }

  function fileQuery() {
    var q = root.query.trim()
    var kw = Engine.splitKeyword(q)
    var keyword = kw.keyword.toLowerCase()
    if (keyword === "f" && kw.rest) return kw.rest
    if (q[0] === "?" || Engine.isCalcQuery(q)) return ""
    if (kw.rest) {
      if (["define", "note", "ai", "ask"].indexOf(keyword) >= 0) return ""
      var quicklinks = root.config.quicklinks || []
      for (var i = 0; i < quicklinks.length; i++)
        if (String(quicklinks[i].keyword || "").toLowerCase() === keyword) return ""
    }
    return q
  }

  // --------------------------------------------------------------- actions
  function activate(secondary) {
    if (root.mode === "ai") {
      var prompt = root.query.trim()
      if (prompt && !root.aiBusy) {
        input.text = ""
        root.query = ""
        root.ask(prompt)
      }
      return
    }
    var actions = root.selectedActions
    if (!actions || actions.length === 0) return
    var action = secondary && actions.length > 1 ? actions[1] : actions[0]
    root.perform(root.mode === "emoji" ? null : root.selectedRow, action)
  }

  function recordUsage(row) {
    if (!row || !row.id || row.kind === "window" || row.kind === "header" || row.kind === "clip"
        || row.kind === "fallback" || row.kind === "calc") return
    var next = ({})
    for (var key in root.usage) next[key] = root.usage[key]
    var prev = next[row.id] || { count: 0, last: 0 }
    next[row.id] = { count: (prev.count || 0) + 1, last: Date.now() }
    root.usage = next
    usageFile.setText(JSON.stringify(next) + "\n")
  }

  function exec(command) {
    Quickshell.execDetached(["bash", "-lc", command])
  }

  function notesDir() {
    return Engine.expandHome((root.config.notes && root.config.notes.dir) || "~/notes", root.home)
  }

  function perform(row, action) {
    if (!action) return
    var op = action.op
    var keepOpen = op === "mode" || op === "prefill" || op === "ai" || op === "define"
      || op === "uninstall" || op === "confirm-exec" || op === "favorite" || op === "favorite-move" || op === "configure"
      || op === "snippet" || op === "snippet-copy" || op === "snippet-edit" || op === "snippet-new"
      || op === "snippet-duplicate" || op === "snippet-delete" || op === "snippet-delete-now"
    if (op === "snippet" || op === "snippet-copy") root.recordUsage(row)
    if (!keepOpen) {
      root.recordUsage(row)
      root.close()
    }

    switch (op) {
    case "app":
      root.launchApp(action.arg, row ? row.title : "")
      break
    case "exec":
      root.exec(action.arg)
      break
    case "terminal":
      Quickshell.execDetached(["xdg-terminal-exec", "bash", "-lc", action.arg + "; echo; read -n1 -rsp 'Press any key to close…'"])
      break
    case "confirm-exec":
      root.pendingConfirm = { message: row.title + "?", confirmText: row.title, row: row, action: { op: "exec", arg: action.arg } }
      break
    case "uninstall":
      root.pendingConfirm = { message: "Uninstall " + row.title + "?", confirmText: "Uninstall", row: row, action: { op: "uninstall-now", arg: action.arg } }
      break
    case "uninstall-now":
      root.removeApp(action.arg, row ? row.title : "")
      break
    case "url":
      Quickshell.execDetached(["xdg-open", action.arg])
      break
    case "menu":
      Quickshell.execDetached(["omarchy-menu", "summon", action.arg])
      break
    case "window":
      Quickshell.execDetached([root.bin("omacast-window"), action.arg, root.targetAddress, action.arg2 || ""])
      break
    case "window-at":
      Quickshell.execDetached([root.bin("omacast-window"), action.arg, action.arg2 || "", ""])
      break
    case "focus":
      Quickshell.execDetached([root.bin("omacast-window"), "focus", action.arg])
      break
    case "copy":
      Quickshell.execDetached(["wl-copy", "--", String(action.arg)])
      break
    case "paste":
      Quickshell.execDetached([root.bin("omacast-paste"), String(action.arg)])
      break
    case "copy-expand":
      Quickshell.execDetached([root.bin("omacast-paste"), "--copy-only", String(action.arg)])
      break
    case "clip-paste":
    case "clip-copy":
      var e = root.clipboardHistory[action.arg]
      if (!e) break
      var copyOnly = op === "clip-copy"
      if (e.type === "image") {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file"].concat(copyOnly ? ["--copy-only"] : []).concat([e.mime, e.path]))
      } else {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", copyOnly ? "--copy-only" : "--shift-insert", "--history-index", String(action.arg)])
      }
      break
    case "emoji":
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-menu-emoji-insert", action.arg])
      break
    case "open-file":
      Quickshell.execDetached(["xdg-open", action.arg])
      break
    case "exec-copy-file":
      Quickshell.execDetached(["bash", "-c", "wl-copy < \"$1\"", "_", action.arg])
      break
    case "reveal":
      Quickshell.execDetached(["nautilus", "--select", action.arg])
      break
    case "edit-file":
      root.exec("omarchy-launch-editor " + Engine.shellQuote(action.arg))
      break
    case "note-create":
      notesWin.newNote(String(action.arg || ""))
      break
    case "note-open":
      notesWin.open(action.arg)
      break
    case "notes":
      notesWin.open("")
      break
    case "notes-browse":
      notesWin.open("")
      Qt.callLater(function() { if (!notesWin.browsing) notesWin.toggleBrowse() })
      break
    case "favorite":
      root.toggleFavorite(action.arg)
      root.rebuildKeeping(action.arg)
      break
    case "favorite-move":
      root.moveFavorite(action.arg, action.arg2)
      root.rebuildKeeping(action.arg)
      break
    case "configure":
      root.setMode("settings")
      settingsView.section = "extensions"
      input.text = action.arg
      root.query = action.arg
      break
    case "snippet":
    case "snippet-copy":
      var snip = root.snippets[action.arg]
      if (snip) root.useSnippet(snip, { copy: op === "snippet-copy" })
      break
    case "snippet-new":
      root.editSnippet(-1)
      break
    case "snippet-edit":
      root.editSnippet(action.arg)
      break
    case "snippet-duplicate":
      root.duplicateSnippet(action.arg)
      break
    case "snippet-delete":
      root.pendingConfirm = { message: "Delete snippet “" + row.title + "”?", confirmText: "Delete", row: row, action: { op: "snippet-delete-now", arg: action.arg } }
      break
    case "snippet-delete-now":
      root.deleteSnippet(action.arg)
      break
    case "mode":
      root.setMode(action.arg)
      break
    case "prefill":
      if (root.mode !== "search") root.setMode("search")
      input.text = action.arg
      input.cursorPosition = input.text.length
      root.setQuery(input.text)
      break
    case "ai":
      root.setMode("ai")
      root.ask(action.arg)
      break
    case "ai-new":
      root.newChat()
      break
    case "define":
      root.define(action.arg)
      break
    }
  }

  function confirmPending() {
    var pending = root.pendingConfirm
    root.pendingConfirm = null
    if (!pending) return
    root.perform(pending.row, pending.action)
  }

  // -------------------------------------------------------------------- AI
  function aiActions() {
    var last = ""
    for (var i = root.conversation.length - 1; i >= 0; i--) {
      if (root.conversation[i].role === "assistant") { last = root.conversation[i].text; break }
    }
    var out = []
    if (last) {
      out.push({ title: "Copy Answer", op: "copy", arg: last })
      out.push({ title: "Paste Answer", op: "paste", arg: last })
    }
    out.push({ title: "New Chat", op: "ai-new" })
    return out
  }

  function newChat() {
    if (aiProc.running) aiProc.running = false
    root.conversation = []
    root.aiSession = ""
    root.aiBusy = false
    root.aiStatus = ""
    input.forceActiveFocus()
  }

  function ask(prompt) {
    var text = String(prompt || "").trim()
    if (!text) return
    if (aiProc.running) aiProc.running = false
    var next = root.conversation.concat([{ role: "user", text: text }, { role: "assistant", text: "" }])
    root.conversation = next
    root.aiBusy = true
    root.aiStatus = "Thinking…"
    var args = [root.bin("omacast-ai"), "--model", (root.config.ai && root.config.ai.model) || "haiku"]
    if (root.aiSession) args = args.concat(["--resume", root.aiSession])
    var instructions = (root.config.ai && root.config.ai.instructions) || ""
    if (instructions.trim()) args = args.concat(["--instructions", instructions])
    aiProc.command = args.concat([text])
    aiProc.running = true
  }

  function appendAnswer(chunk, replace) {
    var next = root.conversation.slice()
    var last = next[next.length - 1]
    if (!last || last.role !== "assistant") return
    next[next.length - 1] = { role: "assistant", text: replace ? chunk : last.text + chunk }
    root.conversation = next
    Qt.callLater(function() { aiFlick.contentY = Math.max(0, aiFlick.contentHeight - aiFlick.height) })
  }

  function handleAiLine(line) {
    var data = null
    // Only stream-json events carry the answer; anything else is noise.
    try { data = JSON.parse(line) } catch (e) { return }
    if (!data || typeof data !== "object") return
    if (data.type === "system" && data.subtype === "init" && data.session_id) {
      root.aiSession = data.session_id
    } else if (data.type === "stream_event" && data.event && data.event.type === "content_block_delta"
               && data.event.delta && data.event.delta.type === "text_delta") {
      root.aiStatus = "Writing…"
      root.appendAnswer(data.event.delta.text, false)
    } else if (data.type === "result") {
      var current = root.conversation[root.conversation.length - 1]
      if (data.is_error) root.appendAnswer("**Error:** " + (data.result || "the request failed"), true)
      else if (current && !current.text && data.result) root.appendAnswer(data.result, true)
      if (data.session_id) root.aiSession = data.session_id
    } else if (data.type === "error") {
      root.appendAnswer("**Error:** " + (data.message || "unknown error"), true)
    }
  }

  // ------------------------------------------------------------ dictionary
  function define(word) {
    root.detailTitle = word
    root.detailText = ""
    root.detailBusy = true
    input.text = ""
    root.query = ""
    root.mode = "detail"
    root.actionsOpen = false
    defineProc.command = [root.bin("omacast-define"), word]
    defineProc.running = true
  }

  // -------------------------------------------------------------- processes
  Process {
    id: clientsProc
    command: ["bash", "-c", "hyprctl activewindow -j; printf '\\n@@OMACAST@@\\n'; hyprctl clients -j"]
    stdout: StdioCollector {
      onStreamFinished: root.applyClients(this.text)
    }
  }

  Timer {
    id: calcTimer
    interval: 40
    onTriggered: {
      var q = root.query.trim()
      if (!Engine.isCalcQuery(q)) return
      if (calcProc.running) { calcProc.pending = true; calcProc.running = false; return }
      calcProc.input = q
      calcProc.command = ["qalc", "-t", "-m", "1500", Engine.calcExpression(q)]
      calcProc.running = true
    }
  }

  Process {
    id: calcProc
    property string input: ""
    property bool pending: false
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(this.text || "").trim().split("\n")
        var result = lines[lines.length - 1] || ""
        if (calcProc.input === root.query.trim() && Engine.acceptCalcResult(calcProc.input, result)) {
          // Copy the bare number for plain math; keep units for conversions.
          root.calc = { query: calcProc.input, input: calcProc.input.replace(/^=/, "").trim(), result: result.trim(), value: result.trim() }
        } else if (calcProc.input === root.query.trim()) {
          root.calc = null
        }
        if (root.mode === "search") root.refreshKeepingSelection()
      }
    }
    onExited: if (pending) { pending = false; calcTimer.restart() }
  }

  Timer {
    id: fileTimer
    interval: 180
    onTriggered: {
      var fq = root.fileQuery()
      if (fq.length < 3) return
      if (filesProc.running) { filesProc.pending = true; filesProc.running = false; return }
      var files = root.config.files || {}
      var roots = (files.roots || ["~"]).map(function(r) { return Engine.expandHome(r, root.home) })
      filesProc.query = fq
      filesProc.command = ["fd", "--absolute-path", "--max-results", String(files.maxResults || 12),
        "-i", "-F", "--exclude", "node_modules", "--exclude", ".cache", "--", fq].concat(roots)
      root.filesBusy = true
      filesProc.running = true
    }
  }

  Process {
    id: filesProc
    property string query: ""
    property bool pending: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.filesBusy = false
        if (filesProc.query !== root.fileQuery()) return
        var lines = String(this.text || "").split("\n")
        var rows = []
        for (var i = 0; i < lines.length; i++) {
          var path = lines[i]
          if (!path) continue
          var isDir = path[path.length - 1] === "/"
          var clean = isDir ? path.substring(0, path.length - 1) : path
          var name = clean.split("/").pop()
          var parent = clean.substring(0, clean.length - name.length - 1).replace(root.home, "~")
          rows.push({
            id: "file." + clean,
            kind: "file",
            title: name,
            subtitle: parent,
            accessory: isDir ? "Folder" : "File",
            glyph: isDir ? "󰉋" : "󰈔",
            actions: [
              { title: isDir ? "Open Folder" : "Open File", op: "open-file", arg: clean },
              { title: "Show in Files", op: "reveal", arg: clean },
              { title: "Open in Editor", op: "edit-file", arg: clean },
              { title: "Copy Path", op: "copy", arg: clean }
            ]
          })
        }
        root.fileRows = rows
        root.fileRowsQuery = filesProc.query
        if (root.mode === "search") root.refreshKeepingSelection()
      }
    }
    onExited: {
      if (pending) { pending = false; fileTimer.restart() }
      else root.filesBusy = false
    }
  }

  // ------------------------------------------------------------- notes
  NotesWindow {
    id: notesWin
    notesDir: root.notesDir()
    stateDir: root.stateDir
    fontFamily: root.fontFamily
    baseSize: (root.config.notes && root.config.notes.textSize) || 15
    showFormatBar: !root.config.notes || root.config.notes.formatBar !== false
    escapeCloses: !root.config.notes || root.config.notes.escapeCloses !== false
    onListChanged: root.buildNoteRows()
  }

  function buildNoteRows() {
    var list = notesWin.noteList
    var rows = []
    for (var i = 0; i < list.length; i++) {
      var n = list[i]
      rows.push({
        id: "note." + n.path,
        kind: "note",
        title: n.title,
        subtitle: n.preview || "Note",
        accessory: "Note",
        glyph: "󱞁",
        keywords: ["note"],
        actions: [
          { title: "Open in Notes", op: "note-open", arg: n.path },
          { title: "Open in Editor", op: "edit-file", arg: n.path },
          { title: "Show in Files", op: "reveal", arg: n.path },
          { title: "Copy Contents", op: "exec-copy-file", arg: n.path }
        ]
      })
    }
    root.noteRows = rows
  }

  function toggleNotes() {
    notesWin.toggle()
    return "ok"
  }

  function openNotes(path) {
    notesWin.open(String(path || ""))
    return "ok"
  }

  Process {
    id: aiProc
    stdout: SplitParser {
      onRead: function(line) { if (line.trim()) root.handleAiLine(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { if (line.trim()) console.warn("omacast ai: " + line) }
    }
    onExited: function(code) {
      root.aiBusy = false
      root.aiStatus = ""
      var last = root.conversation[root.conversation.length - 1]
      if (last && last.role === "assistant" && !last.text)
        root.appendAnswer(code === 0 ? "*(no answer)*" : "**Error:** the AI command exited with code " + code + ".", true)
    }
  }

  Process {
    id: defineProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.detailText = String(this.text || "").trim() || "No definition found."
        root.detailBusy = false
      }
    }
  }

  Process {
    id: guardProc
    stdout: StdioCollector {
      onStreamFinished: {
        var when = ({})
        var checked = ({})
        var lines = String(this.text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          var colon = line.lastIndexOf(":")
          if (colon < 0) continue
          var value = line.substring(colon + 1) === "1"
          var rest = line.substring(0, colon)
          var tagAt = rest.lastIndexOf(":")
          if (tagAt < 0) continue
          var id = rest.substring(0, tagAt)
          var tag = rest.substring(tagAt + 1)
          if (tag === "w") when[id] = value
          else if (tag === "c") checked[id] = value
        }
        root.menuWhen = when
        root.menuChecked = checked
        root.buildOmarchyRows()
      }
    }
  }

  function evaluateMenu() {
    root.buildOmarchyRows()
    var merged = MenuModel.mergeMenuSources(root.menuDefaultItems, root.menuUserItems)
    var script = MenuModel.guardScript(merged.items)
    if (!script || guardProc.running) return
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Timer {
    id: guardRefresh
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.evaluateMenu()
  }

  // ------------------------------------------------------------------ files
  FileView {
    id: defaultConfigFile
    path: decodeURIComponent(String(Qt.resolvedUrl("config.default.jsonc")).replace(/^file:\/\//, ""))
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultConfig = Engine.parseConfig(text()); root.applyConfig() }
    onFileChanged: reload()
  }

  FileView {
    id: userConfigFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userConfig = Engine.parseConfig(text()); root.applyConfig() }
    onLoadFailed: {
      root.userConfig = ({})
      root.applyConfig()
      // First run: seed an editable copy of the defaults.
      Quickshell.execDetached(["bash", "-c", "mkdir -p \"$(dirname \"$2\")\" && cp -n \"$1\" \"$2\"", "_", defaultConfigFile.path, root.configPath])
    }
    onFileChanged: reload()
  }

  function applyConfig() {
    root.config = Engine.mergeConfig(root.defaultConfig, root.userConfig)
    root.buildConfigRows()
    root.migrateSnippets()
    hyprTimer.restart()
  }

  // ------------------------------------------------------------ settings
  function cloneJson(v) { return JSON.parse(JSON.stringify(v === undefined ? null : v)) }

  // Set a dotted path (e.g. "general.hotkey") in the user config and save.
  function setSetting(path, value) {
    var next = root.cloneJson(root.userConfig) || {}
    var parts = path.split(".")
    var o = next
    for (var i = 0; i < parts.length - 1; i++) {
      if (typeof o[parts[i]] !== "object" || o[parts[i]] === null || Array.isArray(o[parts[i]])) {
        // Start from the merged value so siblings keep their defaults.
        var merged = root.config
        for (var j = 0; j <= i; j++) merged = merged ? merged[parts[j]] : undefined
        o[parts[i]] = (merged && typeof merged === "object" && !Array.isArray(merged)) ? root.cloneJson(merged) : {}
      }
      o = o[parts[i]]
    }
    o[parts[parts.length - 1]] = value
    root.writeUserConfig(next)
  }

  function writeUserConfig(next) {
    root.userConfig = next
    root.applyConfig()
    userConfigFile.setText("// Omacast settings. Edited by Omacast Settings; unset keys use the defaults.\n"
      + JSON.stringify(next, null, 2) + "\n")
  }

  function overrideFor(id) {
    var o = root.config.overrides || {}
    return o[id] || {}
  }

  function setOverride(id, field, value) {
    var all = root.cloneJson(root.config.overrides || {})
    var entry = all[id] || {}
    if (value === "" || value === false || value === null) delete entry[field]
    else entry[field] = value
    if (Object.keys(entry).length === 0) delete all[id]
    else all[id] = entry
    root.setSetting("overrides", all)
  }

  function isFavorite(id) {
    return (root.config.favorites || []).indexOf(id) >= 0
  }

  function toggleFavorite(id) {
    var fav = (root.config.favorites || []).slice()
    var at = fav.indexOf(id)
    if (at >= 0) fav.splice(at, 1)
    else fav.push(id)
    root.setSetting("favorites", fav)
  }

  function resetUsage() {
    root.usage = ({})
    usageFile.setText("{}\n")
  }

  function resetSettings() {
    root.writeUserConfig({})
  }

  function editFile(path) {
    root.close()
    root.exec("omarchy-launch-editor " + Engine.shellQuote(path))
  }

  function openUrl(url) {
    root.close()
    Quickshell.execDetached(["xdg-open", url])
  }

  function exportBackup() {
    var stamp = new Date().toISOString().substring(0, 10)
    var path = root.home + "/omacast-backup-" + stamp + ".json"
    var data = JSON.stringify({ omacast: root.version, config: root.userConfig, snippets: root.snippets }, null, 2)
    Quickshell.execDetached(["bash", "-c", "printf '%s\\n' \"$1\" > \"$2\" && notify-send 'Omacast' \"Settings exported to $2\"", "_", data, path])
  }

  function importBackup() {
    importProc.running = true
  }

  Process {
    id: importProc
    command: ["bash", "-c", "f=$(ls -t \"$HOME\"/omacast-backup-*.json 2>/dev/null | head -1); [ -n \"$f\" ] && cat \"$f\""]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(this.text)
          if (data.config) root.writeUserConfig(data.config)
          if (Array.isArray(data.snippets)) root.saveSnippets(data.snippets)
          Quickshell.execDetached(["notify-send", "Omacast", "Settings imported"])
        } catch (e) {
          Quickshell.execDetached(["notify-send", "Omacast", "No backup found in your home folder"])
        }
      }
    }
  }

  // ------------------------------------------------------------- snippets
  FileView {
    id: snippetsFile
    path: root.snippetsPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.snippets = Array.isArray(parsed) ? parsed : []
      } catch (e) { root.snippets = [] }
      root.snippetsLoaded = true
      root.buildConfigRows()
      hyprTimer.restart()
      if (root.opened && root.mode === "snippets") root.rebuild()
    }
    onLoadFailed: {
      root.snippetsLoaded = true
      root.migrateSnippets()
    }
    onFileChanged: reload()
  }

  // First run: seed snippets.json from an older config's "snippets" array,
  // or from a few useful examples.
  function migrateSnippets() {
    if (!root.snippetsLoaded || root.snippets.length > 0 || snippetsFile.loaded) return
    var legacy = Array.isArray(root.userConfig.snippets) ? root.userConfig.snippets : null
    var seed = legacy || [
      { name: "Today's Date", keyword: ";date", text: "{date}" },
      { name: "Timestamp", keyword: ";now", text: "{datetime}" },
      { name: "Shrug", keyword: ";shrug", text: "¯\\_(ツ)_/¯" },
      { name: "Email Reply", keyword: ";re", text: "Hi {argument name=\"Name\" default=\"there\"},\n\n{cursor}\n\nBest,\n{user}" }
    ]
    root.saveSnippets(seed)
  }

  function saveSnippets(list) {
    root.snippets = list
    snippetsFile.setText(JSON.stringify(list, null, 2) + "\n")
    root.buildConfigRows()
    hyprTimer.restart()
  }

  function snippetIndex(s) {
    for (var i = 0; i < root.snippets.length; i++) if (root.snippets[i] === s) return i
    return -1
  }

  function editSnippet(index) {
    var src = index >= 0 ? root.snippets[index] : { name: "", keyword: "", text: "" }
    root.snippetDraft = { index: index, name: src.name || "", keyword: src.keyword || "", text: src.text || "" }
    root.setMode("snippet-edit")
  }

  function saveSnippetDraft() {
    var d = root.snippetDraft
    if (!d || !String(d.name || "").trim() || !String(d.text || "").length) return false
    var list = root.snippets.slice()
    var entry = { name: d.name.trim(), keyword: String(d.keyword || "").replace(/\s+/g, ""), text: d.text }
    if (d.index >= 0) list[d.index] = entry
    else list.push(entry)
    root.saveSnippets(list)
    root.snippetDraft = null
    root.setMode("snippets")
    return true
  }

  function deleteSnippet(index) {
    var list = root.snippets.slice()
    list.splice(index, 1)
    root.saveSnippets(list)
    root.rebuild()
  }

  function duplicateSnippet(index) {
    var s = root.snippets[index]
    var list = root.snippets.slice()
    list.splice(index + 1, 0, { name: s.name + " Copy", keyword: "", text: s.text })
    root.saveSnippets(list)
    root.rebuild()
  }

  function latestClipboardText() {
    for (var i = 0; i < root.clipboardHistory.length; i++)
      if (root.clipboardHistory[i].type !== "image") return String(root.clipboardHistory[i].text || "")
    return ""
  }

  // Paste (or copy) a snippet; asks for {argument}s first when it has any.
  function useSnippet(snippet, opts) {
    var o = opts || {}
    var args = Snippets.argumentsOf(snippet.text, root.snippets)
    if (args.length > 0 && !o.arguments) {
      root.snippetArgs = args
      root.snippetPending = { snippet: snippet, copy: !!o.copy, del: o.del || 0 }
      root.opened = true
      root.setMode("snippet-args")
      return
    }
    var out = Snippets.expand(snippet.text, {
      snippets: root.snippets,
      clipboard: root.latestClipboardText(),
      user: Quickshell.env("USER"),
      arguments: o.arguments || {}
    })
    root.close()
    if (o.copy) {
      Quickshell.execDetached(["wl-copy", "--", out.text])
      return
    }
    var argv = [root.bin("omacast-paste")]
    if (o.del) argv = argv.concat(["--delete", String(o.del)])
    if (out.cursorBack) argv = argv.concat(["--cursor-back", String(out.cursorBack)])
    Quickshell.execDetached(argv.concat([out.text]))
  }

  function submitSnippetArgs() {
    var p = root.snippetPending
    if (!p) return
    var values = {}
    for (var i = 0; i < root.snippetArgs.length; i++) values[root.snippetArgs[i].name] = root.snippetArgs[i].value
    root.snippetPending = null
    root.useSnippet(p.snippet, { arguments: values, copy: p.copy, del: p.del })
  }

  // Called by the Hyprland key hook when a keyword was typed in any app.
  function expandKeyword(keyword) {
    var kw = String(keyword || "")
    // Typing a keyword into Omacast's own search box should just search.
    if (root.opened) return "ignored"
    for (var i = 0; i < root.snippets.length; i++) {
      var s = root.snippets[i]
      if (!s.keyword || s.keyword !== kw) continue
      // Expand in place. Only arguments without a default need a prompt.
      var args = Snippets.argumentsOf(s.text, root.snippets)
      var values = {}
      var needsPrompt = false
      for (var a = 0; a < args.length; a++) {
        values[args[a].name] = args[a].value
        if (!args[a].value) needsPrompt = true
      }
      root.useSnippet(s, needsPrompt ? { del: kw.length } : { del: kw.length, arguments: values })
      return "ok"
    }
    return "unknown"
  }

  // ------------------------------------------------- Hyprland integration
  // Omacast owns ~/.config/omacast/hyprland.lua: launcher/notes/menu hotkeys,
  // per-command hotkeys and the snippet keyword hook. bindings.lua loads it.
  Timer {
    id: hyprTimer
    interval: 700
    onTriggered: root.applyHyprland(false)
  }

  property string lastHyprLua: ""

  function luaString(s) {
    return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\""
  }

  function hyprLua() {
    var g = root.config.general || {}
    var n = root.config.notes || {}
    var ss = root.config.snippetSettings || {}
    var shellCall = "omarchy-shell shell "
    var lines = [
      "-- Generated by Omacast. Change these in Omacast Settings, not here.",
      "local function bind(keys, desc, cmd)",
      "  if not keys or keys == \"\" then return end",
      "  pcall(hl.unbind, keys)",
      "  local ok, err = pcall(hl.bind, keys, hl.dsp.exec_cmd(cmd), { description = desc })",
      "  if not ok then io.stderr:write(\"omacast: cannot bind \" .. keys .. \": \" .. tostring(err) .. \"\\n\") end",
      "end",
      "",
      "pcall(hl.define_submap, \"omacast-record\", function() end)",
      "",
      "-- Floating notes: a pinned floating window above everything.",
      "local notes = { title = \"^Omacast Notes$\" }",
      "pcall(hl.window_rule, { match = notes, float = true, pin = true, size = { 460, 420 }, move = { \"(monitor_w-window_w-40)\", \"(monitor_h*0.06)\" } })",
      ""
    ]
    lines.push("bind(" + root.luaString(g.hotkey || "") + ", \"Omacast\", " + root.luaString(shellCall + "toggle stefans.omacast '{}'") + ")")
    // While Omacast is open: Super+1…9 open favorites, the hotkey still closes
    // it, and Super+Escape always gets you out of the submap.
    lines.push("pcall(hl.define_submap, \"omacast\", function()")
    lines.push("  for i = 1, 9 do")
    lines.push("    pcall(hl.bind, \"SUPER + \" .. i, hl.dsp.exec_cmd(" + root.luaString(shellCall + "call stefans.omacast openFavorite ") + " .. i), { description = \"Omacast favorite \" .. i })")
    lines.push("  end")
    if (g.hotkey) lines.push("  pcall(hl.bind, " + root.luaString(g.hotkey) + ", hl.dsp.exec_cmd(" + root.luaString(shellCall + "hide stefans.omacast") + "), { description = \"Close Omacast\" })")
    lines.push("  pcall(hl.bind, \"SUPER + ESCAPE\", hl.dsp.submap(\"reset\"), { description = \"Leave Omacast submap\" })")
    // Keys that should keep working while Omacast is open (e.g. screenshots)
    // can be bound from bindings.lua by defining omacast_submap_binds().
    lines.push("  if type(omacast_submap_binds) == \"function\" then pcall(omacast_submap_binds) end")
    lines.push("end)")
    lines.push("bind(" + root.luaString(g.menuHotkey || "") + ", \"Omarchy menu\", \"omarchy-menu toggle root\")")
    lines.push("bind(" + root.luaString(n.hotkey || "") + ", \"Omacast Notes\", " + root.luaString(shellCall + "call stefans.omacast toggleNotes ''") + ")")

    var overrides = root.config.overrides || {}
    var runBin = root.bin("omacast")
    for (var id in overrides) {
      var hk = overrides[id] && overrides[id].hotkey
      if (!hk) continue
      lines.push("bind(" + root.luaString(hk) + ", " + root.luaString("Omacast: " + id) + ", " + root.luaString(runBin + " run " + Engine.shellQuote(id)) + ")")
    }

    if (ss.expansion) {
      var keywords = root.snippets.map(function(s) { return s.keyword }).filter(function(k) { return k && k.length >= 2 })
      lines.push("")
      lines.push("omacast_expansion = {")
      lines.push("  keywords = { " + keywords.map(root.luaString).join(", ") + " },")
      lines.push("  exclude = { " + (ss.exclude || []).map(root.luaString).join(", ") + " },")
      lines.push("  within_words = " + (ss.withinWords ? "true" : "false") + ",")
      lines.push("}")
      lines.push("pcall(dofile, " + root.luaString(decodeURIComponent(String(Qt.resolvedUrl("hypr/expand.lua")).replace(/^file:\/\//, ""))) + ")")
    }
    return lines.join("\n") + "\n"
  }

  function applyHyprland(force) {
    if (!root.snippetsLoaded || !defaultConfigFile.loaded) return
    var lua = root.hyprLua()
    if (!force && lua === root.lastHyprLua) return
    var first = root.lastHyprLua === ""
    root.lastHyprLua = lua
    hyprFile.setText(lua)
    // Reload Hyprland unless this is the startup write of an unchanged file.
    if (!first || force) Quickshell.execDetached(["bash", "-c", "sleep 0.2; hyprctl reload >/dev/null"])
  }

  FileView {
    id: hyprFile
    path: root.hyprPath
    printErrors: false
    atomicWrites: true
    onLoaded: if (root.lastHyprLua === "") root.lastHyprLua = text()
  }

  // While a hotkey field records, a bind-less submap lets every key reach us.
  function setRecording(on) {
    root.recording = on
    Quickshell.execDetached(["hyprctl", "dispatch", on ? "hl.dsp.submap(\"omacast-record\")"
      : (root.opened ? "hl.dsp.submap(\"omacast\")" : "hl.dsp.submap(\"reset\")")])
  }

  FileView {
    id: usageFile
    path: root.stateDir + "/usage.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { root.usage = JSON.parse(text()) || ({}) } catch (e) { root.usage = ({}) }
    }
  }

  FileView {
    id: clipboardFile
    path: root.home + "/.local/state/omarchy/clipboard-history.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.clipboardHistory = Array.isArray(parsed) ? parsed : []
      } catch (e) { root.clipboardHistory = [] }
      if (root.opened && root.mode === "clipboard") root.rebuildClipboard()
    }
    onFileChanged: reload()
  }

  FileView {
    id: emojiFile
    path: root.omarchyPath + "/shell/plugins/emojis/emojis.json"
    printErrors: false
    onLoaded: {
      try { root.emojiData = JSON.parse(text()) } catch (e) { root.emojiData = [] }
      if (root.opened && root.mode === "emoji") root.rebuildEmoji()
    }
  }

  FileView {
    id: menuDefaultFile
    path: root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.menuDefaultItems = MenuModel.parseMenuJsonc(text()); root.evaluateMenu() }
    onFileChanged: reload()
  }

  FileView {
    id: menuUserFile
    path: root.home + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.menuUserItems = MenuModel.parseMenuJsonc(text()); root.evaluateMenu() }
    onLoadFailed: { root.menuUserItems = []; root.evaluateMenu() }
    onFileChanged: reload()
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
    // Never leave Hyprland stuck in the launcher submap after a shell restart.
    Quickshell.execDetached(["bash", "-c", "[ \"$(hyprctl submap 2>/dev/null)\" = omacast ] && hyprctl dispatch 'hl.dsp.submap(\"reset\")'"])
    bindsProc.running = true
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenScan.running = true
      if (root.opened) { root.buildApps(); root.rebuild() }
    }
  }

  Process {
    id: hiddenScan
    running: true
    command: ["bash", "-c", Util.shellQuote(root.omarchyPath + "/shell/services/hidden-entries.sh") + " " + Util.shellQuote([Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":"))]
    stdout: StdioCollector {
      onStreamFinished: root.hiddenAppIds = root.idSet(this.text)
    }
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.configuredHiddenIds = root.idSet(text())
    onFileChanged: reload()
  }

  function idSet(raw) {
    var next = ({})
    var lines = String(raw || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id) next[id] = true
    }
    return next
  }

  // ===================================================================== UI
  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    property real openProgress: 1
    onVisibleChanged: if (visible) openAnim.restart()
    NumberAnimation {
      id: openAnim
      target: panel
      property: "openProgress"
      from: 0
      to: 1
      duration: 150
      easing.type: Easing.OutCubic
    }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.18)
      opacity: panel.openProgress
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    RectangularShadow {
      anchors.fill: card
      radius: card.radius
      blur: Style.space(52)
      offset.y: Style.space(20)
      color: Qt.rgba(0, 0, 0, 0.5)
      opacity: card.opacity
      scale: card.scale
      transformOrigin: Item.Top
    }

    // Omarchy's own surface: the theme's menu border (colour, width, gradient)
    // and Hyprland's corner rounding, exactly like the Omarchy menu.
    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cardRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(Style.space(20), Math.round(panel.height * 0.18))
      color: root.background
      borderSpec: root.insetSpec
      opacity: panel.openProgress
      scale: 0.97 + 0.03 * panel.openProgress
      transformOrigin: Item.Top

      MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

      GradientBorder {
        anchors.fill: parent
        z: 100
        radius: card.radius
        thickness: root.borderWidth
        color: root.borderColor
      }


      Column {
        id: layout
        anchors.fill: parent
        anchors.topMargin: card.borderTop
        anchors.rightMargin: card.borderRight
        anchors.bottomMargin: card.borderBottom
        anchors.leftMargin: card.borderLeft

        // ---------------------------------------------------- search bar
        Item {
          id: header
          width: parent.width
          height: root.headerHeight

          Rectangle {
            id: backButton
            visible: root.mode !== "search"
            width: Style.space(28)
            height: Style.space(28)
            radius: Style.space(7)
            color: backMouse.containsMouse ? Util.alpha(root.foreground, 0.16) : root.faint
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: ""
              color: root.foreground
              opacity: 0.85
              font.family: root.iconFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: backMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setMode("search")
            }
          }

          Text {
            visible: !backButton.visible
            width: Style.space(28)
            horizontalAlignment: Text.AlignHCenter
            text: ""
            color: root.foreground
            opacity: 0.45
            font.family: root.iconFamily
            font.pixelSize: Style.font.heading
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
          }

          TextInput {
            id: input
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16 + 28 + 12)
            anchors.right: tabRow.left
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: Util.alpha(root.accent, 0.35)
            selectedTextColor: root.foreground
            cursorDelegate: Rectangle {
              width: Style.space(2)
              color: root.accent
              visible: input.cursorVisible
              radius: 1
            }
            font.family: root.fontFamily
            font.pixelSize: root.fs(Math.round(Style.font.heading * 1.18))
            clip: true
            focus: true
            readOnly: root.mode === "detail" || root.mode === "snippet-edit" || root.mode === "snippet-args"
            onTextEdited: root.setQuery(text)

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: input.text.length === 0
              text: root.mode === "clipboard" ? "Search clipboard history…"
                : root.mode === "snippets" ? "Search snippets…"
                : root.mode === "settings" ? "Search settings and commands…"
                : root.mode === "snippet-edit" ? (root.snippetDraft && root.snippetDraft.index >= 0 ? "Edit Snippet" : "Create Snippet")
                : root.mode === "snippet-args" ? ((root.snippetPending && root.snippetPending.snippet.name) || "Snippet")
                : root.mode === "emoji" ? "Search emoji…"
                : root.mode === "ai" ? (root.conversation.length ? "Ask a follow-up…" : "Ask Claude anything…")
                : root.mode === "detail" ? root.detailTitle
                : "Search apps, commands, windows and files…"
              color: root.foreground
              opacity: root.mode === "detail" ? 0.9 : 0.38
              font: input.font
              elide: Text.ElideRight
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { root.handleKey(event) }
          }

          Row {
            id: tabRow
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Repeater {
              model: root.tabs
              delegate: Rectangle {
                required property var modelData
                readonly property bool active: root.mode === modelData.mode || (root.mode === "detail" && modelData.mode === "search")
                height: Style.space(28)
                width: tabContent.implicitWidth + Style.space(active ? 18 : 14)
                radius: Style.space(7)
                color: active ? Util.alpha(root.accent, 0.18) : (tabMouse.containsMouse ? root.faint : "transparent")

                Row {
                  id: tabContent
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.glyph
                    color: parent.parent.active ? root.accent : root.foreground
                    opacity: parent.parent.active ? 1 : 0.55
                    font.family: root.iconFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.parent.active
                    text: modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Font.Medium
                  }
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setMode(modelData.mode)
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: Util.alpha(root.foreground, 0.1)
          visible: !root.compact
        }

        // ------------------------------------------------------ content
        Item {
          id: content
          visible: !root.compact
          width: parent.width
          height: card.height - root.headerHeight - root.footerHeight - Style.spacing.hairline - card.borderTop - card.borderBottom

          // List (search + clipboard)
          ListView {
            id: resultList
            visible: root.mode === "search" || root.mode === "clipboard" || root.mode === "snippets"
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.topMargin: Style.space(6)
            anchors.bottomMargin: Style.space(6)
            anchors.leftMargin: Style.space(8)
            width: (root.mode === "clipboard" || root.mode === "snippets") ? Math.round(parent.width * 0.44) : parent.width - Style.space(16)
            model: root.rows
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0

            delegate: Item {
              id: row
              required property var modelData
              required property int index
              readonly property bool isHeader: modelData.kind === "header"
              readonly property bool isCalc: modelData.kind === "calc"
              readonly property bool selected: index === root.selectedIndex
              readonly property bool hasImage: !!modelData.image

              width: ListView.view.width
              height: isHeader ? root.sectionHeight : (isCalc ? root.calcHeight : root.rowHeight)

              Text {
                visible: row.isHeader
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(6)
                text: row.modelData.title
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.DemiBold
              }

              Rectangle {
                visible: !row.isHeader
                anchors.fill: parent
                radius: Style.space(8)
                color: row.selected ? root.hover : "transparent"

                // Calculator card
                Row {
                  visible: row.isCalc
                  anchors.centerIn: parent
                  spacing: Style.space(26)

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: row.isCalc ? row.modelData.subtitle : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.display
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                      width: Math.min(implicitWidth, resultList.width * 0.4)
                      horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "Question"
                      color: root.foreground
                      opacity: 0.45
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: root.foreground
                    opacity: 0.35
                    font.family: root.iconFamily
                    font.pixelSize: Style.font.heading
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: row.isCalc ? row.modelData.title : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.display
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                      width: Math.min(implicitWidth, resultList.width * 0.4)
                      horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "Answer"
                      color: root.foreground
                      opacity: 0.45
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                // Regular row
                Rectangle {
                  id: tile
                  visible: !row.isCalc
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: Style.space(7)
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  color: (row.hasImage && iconImage.status === Image.Ready) ? "transparent"
                    : Util.alpha(root.accent, row.selected ? 0.24 : 0.14)

                  Text {
                    visible: !(row.hasImage && iconImage.status === Image.Ready)
                    anchors.centerIn: parent
                    text: row.modelData.glyph || (row.modelData.kind === "app" ? "󰣆" : "")
                    color: root.accent
                    font.family: row.modelData.glyphFont || root.iconFamily
                    font.pixelSize: Style.font.title
                  }

                  Image {
                    id: iconImage
                    anchors.fill: parent
                    visible: row.hasImage && status === Image.Ready
                    source: row.hasImage ? row.modelData.image : ""
                    fillMode: row.modelData.kind === "clip" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    asynchronous: true
                  }
                }

                Text {
                  id: titleText
                  visible: !row.isCalc
                  anchors.left: tile.right
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, row.width - Style.space(60) - accessoryRow.width - (root.mode === "clipboard" ? 0 : Style.space(80)))
                  text: row.modelData.title || ""
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.weight: row.selected ? Font.Medium : Font.Normal
                  elide: Text.ElideRight
                }

                Text {
                  visible: !row.isCalc && root.mode !== "clipboard"
                  anchors.left: titleText.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: accessoryRow.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.subtitle || ""
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: 0.42
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  elide: Text.ElideRight
                }

                Row {
                  id: accessoryRow
                  visible: !row.isCalc
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Repeater {
                    model: root.mode === "search" ? root.keyParts(root.hotkeyFor(row.modelData)) : []
                    delegate: Rectangle {
                      required property var modelData
                      anchors.verticalCenter: parent.verticalCenter
                      height: Style.space(20)
                      width: Math.max(height, capLabel.implicitWidth + Style.space(10))
                      radius: Style.space(5)
                      color: Util.alpha(root.foreground, row.selected ? 0.14 : 0.08)
                      Text {
                        id: capLabel
                        anchors.centerIn: parent
                        text: root.prettyKey(modelData)
                        color: root.foreground
                        opacity: row.selected ? 0.85 : 0.6
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption + 1
                        font.weight: Font.Medium
                      }
                    }
                  }

                  Item { width: Style.space(4); height: 1; visible: root.hotkeyFor(row.modelData) !== "" }

                  Rectangle {
                    visible: root.isRunning(row.modelData)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(6)
                    height: width
                    radius: width / 2
                    color: root.accent
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode === "clipboard" ? "" : (root.isRunning(row.modelData) ? "Running" : (row.modelData.accessory || ""))
                    visible: text.length > 0
                    color: root.foreground
                    opacity: row.selected ? 0.55 : 0.35
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.modelData.kind === "menu"
                    text: ""
                    color: root.foreground
                    opacity: 0.3
                    font.family: root.iconFamily
                    font.pixelSize: Style.font.body
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  property point last: Qt.point(-1, -1)
                  onPositionChanged: function(mouse) {
                    if (last.x >= 0 && (Math.abs(mouse.x - last.x) > 2 || Math.abs(mouse.y - last.y) > 2))
                      root.selectedIndex = row.index
                    last = Qt.point(mouse.x, mouse.y)
                  }
                  onExited: last = Qt.point(-1, -1)
                  onClicked: {
                    root.selectedIndex = row.index
                    root.activate(false)
                  }
                }
              }
            }
          }

          // Clipboard / snippet preview pane
          Item {
            visible: root.mode === "clipboard" || root.mode === "snippets"
            anchors.left: resultList.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Style.spacing.hairline
              color: Util.alpha(root.foreground, 0.08)
            }

            Flickable {
              id: clipFlick
              anchors.fill: parent
              anchors.margins: Style.space(18)
              clip: true
              contentHeight: clipText.visible ? clipText.implicitHeight : height
              boundsBehavior: Flickable.StopAtBounds
              visible: !!root.selectedRow && (root.selectedRow.kind === "clip" || root.selectedRow.kind === "snippet")

              Text {
                id: clipText
                visible: !!root.selectedRow && (root.selectedRow.clipType === "text" || root.selectedRow.kind === "snippet")
                width: parent.width
                text: visible ? String(root.selectedRow.text).substring(0, 6000) : ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                color: root.foreground
                opacity: 0.9
                font.family: root.monoFamily
                font.pixelSize: Style.font.body
              }

              Image {
                visible: !!root.selectedRow && root.selectedRow.clipType === "image"
                width: clipFlick.width
                height: clipFlick.height
                fillMode: Image.PreserveAspectFit
                source: visible ? root.selectedRow.image : ""
                asynchronous: true
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.mode === "clipboard" && root.rows.length === 0
              text: root.query ? "No matches" : "Clipboard history is empty"
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          // Settings
          SettingsView {
            id: settingsView
            anchors.fill: parent
            visible: root.mode === "settings"
            host: root
            fontFamily: root.fontFamily
          }

          // Snippet editor
          FocusScope {
            id: snippetForm
            visible: root.mode === "snippet-edit"
            anchors.fill: parent
            anchors.margins: Style.space(20)

            function update(key, value) {
              if (!root.snippetDraft) return
              var d = root.snippetDraft
              d[key] = value
              root.snippetDraft = d
            }

            property string error: ""

            function save() {
              snippetForm.update("name", snippetName.currentText())
              snippetForm.update("keyword", snippetKeyword.currentText())
              snippetForm.update("text", snippetText.currentText())
              var d = root.snippetDraft || {}
              if (!String(d.name || "").trim()) { snippetForm.error = "Give the snippet a name."; snippetName.focusInput(); return }
              if (!String(d.text || "").length) { snippetForm.error = "The snippet text is empty."; snippetText.focusInput(); return }
              var kw = String(d.keyword || "").replace(/\s+/g, "")
              for (var i = 0; i < root.snippets.length; i++) {
                if (i !== d.index && kw && root.snippets[i].keyword === kw) {
                  snippetForm.error = "“" + root.snippets[i].name + "” already uses " + kw + "."
                  snippetKeyword.focusInput()
                  return
                }
              }
              snippetForm.error = ""
              root.saveSnippetDraft()
            }

            function cancel() {
              snippetForm.error = ""
              root.snippetDraft = null
              root.setMode("snippets")
            }

            // The editor opens with the cursor in Name; a short delay lets the
            // view finish switching before focus moves.
            onVisibleChanged: if (visible) { snippetForm.error = ""; focusTimer.restart() }
            Timer { id: focusTimer; interval: 60; onTriggered: snippetName.focusInput() }

            Keys.onPressed: function(event) {
              var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              if (event.key === Qt.Key_Escape) {
                snippetForm.cancel()
                event.accepted = true
              } else if (ctrl && (event.key === Qt.Key_S || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                snippetForm.save()
                event.accepted = true
              }
            }

            Column {
              anchors.fill: parent
              spacing: Style.space(12)

              Row {
                width: parent.width
                spacing: Style.space(12)
                Text { width: Style.space(80); anchors.verticalCenter: parent.verticalCenter; text: "Name"; color: root.foreground; opacity: 0.7; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                TextBox {
                  id: snippetName
                  width: parent.width - Style.space(92)
                  text: root.snippetDraft ? root.snippetDraft.name : ""
                  placeholder: "Email Signature"
                  nextField: snippetKeyword
                  prevField: saveButton
                  onEdited: function(t) { snippetForm.update("name", t) }
                  onAccepted: snippetKeyword.focusInput()
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(12)
                Text { width: Style.space(80); anchors.verticalCenter: parent.verticalCenter; text: "Keyword"; color: root.foreground; opacity: 0.7; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                TextBox {
                  id: snippetKeyword
                  width: Style.space(160)
                  mono: true
                  text: root.snippetDraft ? root.snippetDraft.keyword : ""
                  placeholder: ";sig"
                  nextField: snippetText
                  prevField: snippetName
                  onEdited: function(t) { snippetForm.update("keyword", t) }
                  onAccepted: snippetText.focusInput()
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(264)
                  wrapMode: Text.Wrap
                  text: (root.config.snippetSettings && root.config.snippetSettings.expansion)
                    ? "Type it in any app to expand the snippet, e.g. ;sig"
                    : "Keyword expansion is off (Settings › Snippets)."
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption + 1
                }
              }
              TextBox {
                id: snippetText
                width: parent.width
                height: parent.height - Style.space(200)
                nextField: cancelButton
                prevField: snippetKeyword
                multiline: true
                mono: true
                text: root.snippetDraft ? root.snippetDraft.text : ""
                placeholder: "Hi {argument name=\"Name\"},\n\n{cursor}\n\nBest,\n{user}"
                onEdited: function(t) { snippetForm.update("text", t) }
              }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Text { text: "Insert:"; color: root.foreground; opacity: 0.5; font.family: root.fontFamily; font.pixelSize: Style.font.caption + 1; height: Style.space(24); verticalAlignment: Text.AlignVCenter }
                Repeater {
                  model: ["{clipboard}", "{date}", "{time}", "{datetime}", "{day}", "{cursor}", "{argument name=\"Name\"}", "{uuid}", "{user}"]
                  delegate: Rectangle {
                    required property var modelData
                    height: Style.space(24)
                    width: chipText.implicitWidth + Style.space(14)
                    radius: Style.space(6)
                    color: chipMouse.containsMouse ? Util.alpha(root.accent, 0.25) : Util.alpha(root.accent, 0.12)
                    Text { id: chipText; anchors.centerIn: parent; text: modelData; color: root.foreground; font.family: root.monoFamily; font.pixelSize: Style.font.caption }
                    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: snippetText.insertAtCursor(modelData) }
                  }
                }
              }
              Item {
                width: parent.width
                height: Style.space(30)
                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - buttons.width - Style.space(12)
                  elide: Text.ElideRight
                  text: snippetForm.error || "Tab moves between fields · Alt+Tab inserts a tab · Ctrl+S saves"
                  color: snippetForm.error ? "#e5484d" : root.foreground
                  opacity: snippetForm.error ? 1 : 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption + 1
                }
                Row {
                  id: buttons
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)
                  PillButton {
                    id: cancelButton
                    text: "Cancel"
                    nextField: saveButton
                    prevField: snippetText
                    onActivated: snippetForm.cancel()
                  }
                  PillButton {
                    id: saveButton
                    text: "Save Snippet"
                    primary: true
                    nextField: snippetName
                    prevField: cancelButton
                    onActivated: snippetForm.save()
                  }
                }
              }
            }
          }

          // Snippet arguments, asked before pasting
          FocusScope {
            id: argsForm
            visible: root.mode === "snippet-args"
            anchors.fill: parent
            anchors.margins: Style.space(24)

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { root.snippetPending = null; root.setMode("search"); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitSnippetArgs(); event.accepted = true }
            }

            Column {
              id: argsRepeater
              width: parent.width
              spacing: Style.space(14)

              function focusFirst() {
                for (var i = 0; i < children.length; i++) {
                  var c = children[i]
                  if (c.focusField) { c.focusField(); return }
                }
              }

              Text {
                text: "Fill in the snippet, then press Enter to paste."
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: root.mode === "snippet-args" ? root.snippetArgs : []
                delegate: Row {
                  required property var modelData
                  required property int index
                  width: argsRepeater.width
                  spacing: Style.space(12)
                  function focusField() { if (field.visible) field.focusInput() }
                  Text { width: Style.space(120); anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.weight: Font.Medium }
                  TextBox {
                    id: field
                    visible: !modelData.options || modelData.options.length === 0
                    width: parent.width - Style.space(132)
                    text: modelData.value
                    onEdited: function(t) { var a = root.snippetArgs; a[index].value = t; root.snippetArgs = a }
                    onAccepted: root.submitSnippetArgs()
                  }
                  Segmented {
                    visible: !!modelData.options && modelData.options.length > 0
                    options: (modelData.options || []).map(function(o) { return { value: o, label: o } })
                    value: modelData.value
                    onPicked: function(v) { var a = root.snippetArgs; a[index].value = v; root.snippetArgs = a }
                  }
                }
              }
            }
          }

          // Emoji grid
          GridView {
            id: emojiGrid
            visible: root.mode === "emoji"
            anchors.fill: parent
            anchors.margins: Style.space(12)
            model: root.mode === "emoji" ? root.emojiResults : []
            cellWidth: Math.floor(width / root.emojiColumns)
            cellHeight: cellWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              required property var modelData
              required property int index
              width: emojiGrid.cellWidth
              height: emojiGrid.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                radius: Style.space(10)
                color: index === root.selectedIndex ? Util.alpha(root.accent, 0.22) : (emojiMouse.containsMouse ? root.faint : "transparent")
                border.width: index === root.selectedIndex ? Style.spacing.hairline : 0
                border.color: Util.alpha(root.accent, 0.6)
              }

              Text {
                anchors.centerIn: parent
                text: modelData.e
                font.pixelSize: Math.round(emojiGrid.cellWidth * 0.46)
              }

              MouseArea {
                id: emojiMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.selectedIndex = index; root.activate(false) }
              }
            }
          }

          // AI chat
          Flickable {
            id: aiFlick
            visible: root.mode === "ai"
            anchors.fill: parent
            anchors.margins: Style.space(18)
            clip: true
            contentHeight: aiColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: aiColumn
              width: aiFlick.width
              spacing: Style.space(14)

              Repeater {
                model: root.conversation
                delegate: Item {
                  required property var modelData
                  required property int index
                  width: aiColumn.width
                  height: bubble.height

                  Rectangle {
                    id: bubble
                    readonly property bool mine: modelData.role === "user"
                    anchors.right: mine ? parent.right : undefined
                    anchors.left: mine ? undefined : parent.left
                    width: mine ? Math.min(parent.width * 0.8, userText.implicitWidth + Style.space(24)) : parent.width
                    height: (mine ? userText.implicitHeight : answerText.implicitHeight) + Style.space(mine ? 16 : 4)
                    radius: Style.space(10)
                    color: mine ? Util.alpha(root.accent, 0.16) : "transparent"

                    Text {
                      id: userText
                      visible: bubble.mine
                      anchors.centerIn: parent
                      width: Math.min(implicitWidth, aiColumn.width * 0.8 - Style.space(24))
                      text: modelData.text
                      textFormat: Text.PlainText
                      wrapMode: Text.Wrap
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }

                    Text {
                      id: answerText
                      visible: !bubble.mine
                      width: parent.width
                      text: modelData.text || (root.aiBusy && index === root.conversation.length - 1 ? "…" : "")
                      textFormat: Text.MarkdownText
                      wrapMode: Text.Wrap
                      color: root.foreground
                      linkColor: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      lineHeight: 1.15
                      onLinkActivated: function(link) { Quickshell.execDetached(["xdg-open", link]) }
                    }
                  }
                }
              }
            }
          }

          Column {
            visible: root.mode === "ai" && root.conversation.length === 0
            anchors.centerIn: parent
            spacing: Style.space(10)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰚩"
              color: root.accent
              font.family: root.iconFamily
              font.pixelSize: Style.font.displayLarge
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Ask Claude anything. Answers stream in here."
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Follow-ups keep the conversation · Ctrl+N starts a new chat"
              color: root.foreground
              opacity: 0.35
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          // Definition / detail view
          Flickable {
            id: detailFlick
            visible: root.mode === "detail"
            anchors.fill: parent
            anchors.margins: Style.space(22)
            clip: true
            contentHeight: detailBody.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Text {
              id: detailBody
              width: detailFlick.width
              text: root.detailBusy ? "Looking up “" + root.detailTitle + "”…" : root.detailText
              textFormat: Text.MarkdownText
              wrapMode: Text.Wrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              lineHeight: 1.2
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.mode === "search" && root.query.trim().length > 0 && root.rows.length === 0
            text: "No results"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            anchors.centerIn: parent
            visible: root.mode === "emoji" && root.emojiResults.length === 0
            text: root.emojiData.length ? "No emoji found" : "Loading emoji…"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        // ------------------------------------------------------- footer
        Rectangle {
          visible: !root.compact
          width: parent.width
          height: root.footerHeight
          color: Util.alpha(root.foreground, 0.035)
          bottomLeftRadius: Math.max(0, root.cardRadius - card.borderBottom)
          bottomRightRadius: Math.max(0, root.cardRadius - card.borderBottom)

          Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: Style.spacing.hairline
            color: Util.alpha(root.foreground, 0.08)
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: hintRow.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(9)
            clip: true

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              color: root.accent
              font.family: "omarchy"
              font.pixelSize: Style.font.title
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.statusText
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Row {
            id: hintRow
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Repeater {
              model: root.footerHints
              delegate: Row {
                required property var modelData
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(7)

                Rectangle {
                  visible: index > 0
                  width: Style.spacing.hairline
                  height: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  color: Util.alpha(root.foreground, 0.14)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: root.foreground
                  opacity: index === 0 ? 0.95 : 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.weight: index === 0 ? Font.Medium : Font.Normal
                }

                Repeater {
                  model: modelData.keys
                  delegate: Rectangle {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.space(21)
                    width: Math.max(height, keyLabel.implicitWidth + Style.space(12))
                    radius: Style.space(5)
                    color: Util.alpha(root.foreground, 0.1)
                    Text {
                      id: keyLabel
                      anchors.centerIn: parent
                      text: modelData
                      color: root.foreground
                      opacity: 0.8
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.weight: Font.Medium
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ------------------------------------------------- action panel
      BorderSurface {
        id: actionPanel
        visible: root.actionsOpen && root.selectedActions.length > 0
        z: 30
        width: Style.space(320)
        height: actionColumn.implicitHeight + Style.space(12)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.footerHeight + Style.space(4)
        radius: Math.max(0, root.cardRadius - Style.space(2))
        color: Qt.lighter(root.background, 1.25)
        borderSpec: root.insetSpec

        GradientBorder {
          anchors.fill: parent
          z: 100
          radius: parent.radius
          thickness: root.borderWidth
          color: root.borderColor
        }


        RectangularShadow {
          z: -1
          anchors.fill: parent
          radius: parent.radius
          blur: Style.space(30)
          offset.y: Style.space(8)
          color: Qt.rgba(0, 0, 0, 0.45)
        }

        Column {
          id: actionColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(6)
          spacing: Style.space(2)

          Text {
            text: root.mode === "emoji" ? "Emoji" : (root.mode === "ai" ? "AI Chat" : (root.selectedRow ? root.selectedRow.title : ""))
            textFormat: Text.PlainText
            width: parent.width - Style.space(16)
            x: Style.space(8)
            height: Style.space(26)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
          }

          Repeater {
            model: root.actionsOpen ? root.selectedActions : []
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: actionColumn.width
              height: Style.space(34)
              radius: Style.space(7)
              color: index === root.actionIndex ? root.hover : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
              }

              Rectangle {
                visible: index < 2 || !!modelData.key
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(20)
                width: Math.max(height, shortcut.implicitWidth + Style.space(10))
                radius: Style.space(5)
                color: Util.alpha(root.foreground, 0.1)
                Text {
                  id: shortcut
                  anchors.centerIn: parent
                  text: index === 0 ? "↵" : (index === 1 ? "Ctrl ↵" : (modelData.key || ""))
                  color: root.foreground
                  opacity: 0.75
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.actionIndex = index
                onClicked: {
                  root.actionsOpen = false
                  root.perform(root.mode === "emoji" ? null : root.selectedRow, modelData)
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 40
        opened: root.pendingConfirm !== null
        message: root.pendingConfirm ? root.pendingConfirm.message : ""
        confirmText: root.pendingConfirm ? root.pendingConfirm.confirmText : "Confirm"
        background: root.background
        foreground: root.foreground
        scrim: Util.alpha(root.background, 0.7)
        selectedBackground: root.hover
        selectedText: root.accent
        fontFamily: root.fontFamily
        cornerRadius: root.cardRadius
        onCanceled: { root.pendingConfirm = null; input.forceActiveFocus() }
        onConfirmed: root.confirmPending()
      }
    }
  }

  // ------------------------------------------------------------- footer
  readonly property string statusText: {
    if (root.mode === "ai") return root.aiBusy ? root.aiStatus : ("Claude " + ((root.config.ai && root.config.ai.model) || "haiku"))
    if (root.mode === "clipboard") return root.rows.length + " items"
    if (root.mode === "emoji") return root.emojiResults.length + " emoji"
    if (root.mode === "detail") return "Dictionary"
    if (root.mode === "snippets") return root.snippets.length + " snippets"
    if (root.mode === "settings") return "Settings"
    if (root.mode === "snippet-edit") return "Snippet"
    if (root.mode === "snippet-args") return "Snippet"
    if (root.filesBusy) return "Searching files…"
    return "Omacast"
  }

  readonly property var footerHints: {
    var primary = ""
    var actions = root.selectedActions
    if (root.mode === "ai") primary = root.aiBusy ? "Answering…" : "Ask"
    else if (actions.length > 0) primary = actions[0].title
    if (root.mode === "snippet-edit") return [{ label: "Save", keys: ["Ctrl", "S"] }, { label: "Cancel", keys: ["Esc"] }]
    if (root.mode === "snippet-args") return [{ label: "Paste", keys: ["↵"] }, { label: "Cancel", keys: ["Esc"] }]
    if (root.mode === "settings") return [{ label: "Back", keys: ["Esc"] }]
    var hints = []
    if (primary) hints.push({ label: primary, keys: root.mode === "ai" && root.aiBusy ? [] : ["↵"] })
    if (actions.length > 0) hints.push({ label: "Actions", keys: ["Ctrl", "K"] })
    if (root.mode === "snippets") hints.push({ label: "New", keys: ["Ctrl", "N"] })
    if (root.mode === "search" && !root.query) hints.push({ label: "Modes", keys: ["Tab"] })
    return hints
  }

  // --------------------------------------------------------------- keys
  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var key = event.key

    if (root.pendingConfirm) {
      if (confirmDialog.handleKey(event)) event.accepted = true
      return
    }

    if (root.actionsOpen) {
      var count = root.selectedActions.length
      if (key === Qt.Key_Escape || key === Qt.Key_Left || (ctrl && key === Qt.Key_K)) root.actionsOpen = false
      else if (key === Qt.Key_Right) { /* already open */ }
      else if (key === Qt.Key_Down || (ctrl && (key === Qt.Key_N || key === Qt.Key_J))) root.actionIndex = (root.actionIndex + 1) % count
      else if (key === Qt.Key_Up || (ctrl && (key === Qt.Key_P || key === Qt.Key_K))) root.actionIndex = (root.actionIndex - 1 + count) % count
      else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        var chosen = root.selectedActions[root.actionIndex]
        root.actionsOpen = false
        root.perform(root.mode === "emoji" ? null : root.selectedRow, chosen)
      } else return
      event.accepted = true
      return
    }

    if (root.mode === "snippet-edit") {
      if (key === Qt.Key_Escape) { snippetForm.cancel(); event.accepted = true; return }
      if (ctrl && (key === Qt.Key_S || key === Qt.Key_Return || key === Qt.Key_Enter)) { snippetForm.save(); event.accepted = true; return }
      if (key === Qt.Key_Tab) { snippetName.focusInput(); event.accepted = true; return }
    }

    var closeOnEscape = root.config.general && root.config.general.escapeBehavior === "close"
    if (key === Qt.Key_Escape) {
      if (closeOnEscape) root.close()
      else if (root.mode === "detail") root.setMode("search")
      else if (input.text) { input.text = ""; root.setQuery("") }
      else if (root.mode !== "search") root.setMode("search")
      else root.close()
      event.accepted = true
    } else if (ctrl && key === Qt.Key_Comma) {
      root.setMode("settings")
      event.accepted = true
    } else if (root.mode === "settings" && (key === Qt.Key_Up || key === Qt.Key_Down) && !input.text) {
      settingsView.moveSection(key === Qt.Key_Up ? -1 : 1)
      event.accepted = true
    } else if (root.mode === "snippets" && ctrl && key === Qt.Key_N) {
      root.editSnippet(-1)
      if (input.text.trim() && root.snippetDraft) { var dn = root.snippetDraft; dn.name = input.text.trim(); root.snippetDraft = dn }
      event.accepted = true
    } else if (root.mode === "snippets" && ctrl && key === Qt.Key_E && root.selectedRow && root.selectedRow.kind === "snippet") {
      root.editSnippet(root.selectedRow.index)
      event.accepted = true
    } else if (root.mode === "snippets" && ctrl && (key === Qt.Key_X || key === Qt.Key_Backspace) && root.selectedRow && root.selectedRow.kind === "snippet") {
      root.perform(root.selectedRow, { op: "snippet-delete", arg: root.selectedRow.index })
      event.accepted = true
    } else if (key === Qt.Key_Tab && !ctrl) {
      root.cycleMode(1)
      event.accepted = true
    } else if (key === Qt.Key_Backtab) {
      root.cycleMode(-1)
      event.accepted = true
    } else if ((ctrl && key === Qt.Key_K)
               || (key === Qt.Key_Right && !ctrl && !shift && root.mode !== "emoji" && root.mode !== "settings"
                   && input.cursorPosition === input.text.length && root.selectedActions.length > 0)) {
      // Right arrow at the end of the query opens the actions, like Raycast.
      if (root.selectedActions.length > 0) { root.actionIndex = 0; root.actionsOpen = true }
      event.accepted = true
    } else if (ctrl && shift && key === Qt.Key_F && root.selectedRow && root.mode === "search"
               && ["window", "file", "clip", "fallback", "calc", "header"].indexOf(root.selectedRow.kind) < 0) {
      root.perform(root.selectedRow, { op: "favorite", arg: root.selectedRow.id })
      event.accepted = true
    } else if (ctrl && (event.modifiers & Qt.AltModifier) && (key === Qt.Key_Up || key === Qt.Key_Down)
               && root.selectedRow && root.isFavorite(root.selectedRow.id)) {
      root.perform(root.selectedRow, { op: "favorite-move", arg: root.selectedRow.id, arg2: key === Qt.Key_Up ? -1 : 1 })
      event.accepted = true
    } else if (ctrl && key === Qt.Key_N && root.mode === "ai") {
      root.newChat()
      event.accepted = true
    } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      root.activate(ctrl)
      event.accepted = true
    } else if (key === Qt.Key_Backspace && !input.text && root.mode !== "search") {
      root.setMode("search")
      event.accepted = true
    } else if (root.mode === "emoji" && (key === Qt.Key_Left || key === Qt.Key_Right)) {
      root.move(key === Qt.Key_Left ? -1 : 1)
      event.accepted = true
    } else if (key === Qt.Key_Down || (ctrl && (key === Qt.Key_N || key === Qt.Key_J))) {
      if (root.mode === "ai") aiFlick.contentY = Math.min(aiFlick.contentY + Style.space(60), Math.max(0, aiFlick.contentHeight - aiFlick.height))
      else if (root.mode === "detail") detailFlick.contentY = Math.min(detailFlick.contentY + Style.space(60), Math.max(0, detailFlick.contentHeight - detailFlick.height))
      else root.move(root.mode === "emoji" ? root.emojiColumns : 1)
      event.accepted = true
    } else if (key === Qt.Key_Up || (ctrl && key === Qt.Key_P)) {
      if (root.mode === "ai") aiFlick.contentY = Math.max(0, aiFlick.contentY - Style.space(60))
      else if (root.mode === "detail") detailFlick.contentY = Math.max(0, detailFlick.contentY - Style.space(60))
      else root.move(root.mode === "emoji" ? -root.emojiColumns : -1)
      event.accepted = true
    } else if (key === Qt.Key_PageDown) {
      root.move(root.mode === "emoji" ? root.emojiColumns * 4 : 8)
      event.accepted = true
    } else if (key === Qt.Key_PageUp) {
      root.move(root.mode === "emoji" ? -root.emojiColumns * 4 : -8)
      event.accepted = true
    }
  }
}
