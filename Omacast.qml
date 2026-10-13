import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "lib/Engine.js" as Engine
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
  readonly property int cardWidth: Math.min(Style.space(780), panel.width - Style.space(40))
  readonly property int cardHeight: Math.min(Style.space(520), panel.height - Style.space(80))
  readonly property int cardRadius: Style.space(14)
  readonly property int headerHeight: Style.space(58)
  readonly property int footerHeight: Style.space(42)
  readonly property int rowHeight: Style.space(44)
  readonly property int sectionHeight: Style.space(30)
  readonly property int calcHeight: Style.space(88)
  readonly property int emojiColumns: 10

  // ------------------------------------------------------------------ state
  property bool opened: false
  property string mode: "search" // search | clipboard | emoji | ai | detail
  readonly property var tabs: [
    { mode: "search", label: "Search", glyph: "" },
    { mode: "clipboard", label: "Clipboard", glyph: "󰅌" },
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
    root.calc = null
    root.fileRows = []
    root.fileRowsQuery = ""
    root.mode = "search"
    root.query = ""
    input.text = ""
    root.opened = true

    root.buildApps()
    clientsProc.running = false
    clientsProc.running = true
    notesProc.load()

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
    root.opened = false
    root.actionsOpen = false
    root.pendingConfirm = null
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

  // -------------------------------------------------------------- catalog
  function catalog() {
    return root.appRows.concat(root.windowRows, root.omarchyRows, root.configRows,
      root.noteRows, root.layoutRows, root.systemRows)
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
    root.rebuild()
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
    if (root.opened) root.rebuild()
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

    var snippets = c.snippets || []
    for (i = 0; i < snippets.length; i++) {
      var s = snippets[i]
      rows.push({
        id: "snippet." + (s.keyword || Engine.slug(s.name)),
        kind: "snippet",
        title: s.name,
        subtitle: String(s.text || "").replace(/\s+/g, " ").substring(0, 80),
        accessory: "Snippet",
        glyph: s.icon || "󰅪",
        keywords: [s.keyword || "", "snippet text"],
        boost: 0,
        actions: [
          { title: "Paste Snippet", op: "paste", arg: s.text },
          { title: "Copy Snippet", op: "copy-expand", arg: s.text }
        ]
      })
    }

    var commands = c.commands || []
    for (i = 0; i < commands.length; i++) {
      var cmd = commands[i]
      rows.push({
        id: "custom." + (cmd.id || Engine.slug(cmd.name)),
        kind: "custom",
        title: cmd.name,
        subtitle: cmd.command,
        accessory: "Command",
        glyph: cmd.icon || "",
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
    rows.push({ id: "builtin.config", kind: "builtin", title: "Omacast Settings", subtitle: "~/.config/omacast/config.jsonc", accessory: "Omacast", glyph: "", keywords: ["preferences config quicklinks snippets"], actions: [{ title: "Edit Config", op: "edit-file", arg: root.configPath }] })

    root.configRows = rows
    if (root.opened) root.rebuild()
  }

  function favoriteRows() {
    var fav = root.config.favorites || []
    var out = []
    for (var i = 0; i < fav.length; i++) {
      var id = String(fav[i]).replace(/\.desktop$/, "")
      for (var j = 0; j < root.appRows.length; j++) {
        var a = root.appRows[j]
        if (a.appId === id || a.appId === id + ".desktop") { out.push(a); break }
      }
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
    else if (root.mode === "emoji") root.rebuildEmoji()
  }

  function rebuildSearch() {
    var q = root.query.trim()
    var out = []

    if (!q) {
      var seen = ({})
      var fav = root.favoriteRows()
      for (var f = 0; f < fav.length; f++) seen[fav[f].id] = true
      root.pushSection(out, "Favorites", fav)
      var recentAll = Engine.recentRows(root.catalog(), root.usage, 14)
      var recent = []
      for (var r = 0; r < recentAll.length && recent.length < 7; r++) {
        if (recentAll[r].kind === "window" || seen[recentAll[r].id]) continue
        recent.push(recentAll[r])
      }
      root.pushSection(out, "Recent", recent)
      root.pushSection(out, "Open Windows", root.windowRows.slice(0, 8))
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

    if (root.calc && root.calc.query === q) {
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
    if (!filesOnly) root.pushSection(out, "Results", Engine.rank(root.catalog(), q, root.usage, 40))
    if (root.fileRows.length > 0 && root.fileRowsQuery === root.fileQuery()) root.pushSection(out, "Files", root.fileRows)

    var fallbacks = []
    if (root.config.ai === undefined || root.config.ai.enabled !== false) fallbacks.push(root.askRow(q))
    var searchUrl = Engine.fillTemplate((root.config.search && root.config.search.url) || "https://www.google.com/search?q={query}", q)
    fallbacks.push({
      id: "fallback.web",
      kind: "fallback",
      title: "Search the Web for “" + q + "”",
      subtitle: root.homepage(searchUrl).replace(/^https?:\/\//, ""),
      accessory: "Web",
      glyph: "󰖟",
      actions: [{ title: "Search the Web", op: "url", arg: searchUrl }]
    })
    if (/^[A-Za-z][A-Za-z'\-]{1,40}$/.test(q)) fallbacks.push(root.defineRow(q))
    if (keyword !== "note") fallbacks.push(root.createNoteRow(q))
    root.pushSection(out, "Use “" + (q.length > 32 ? q.substring(0, 32) + "…" : q) + "” with…", fallbacks)

    root.setRows(out)
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
        var actions = [
          { title: "Paste", op: "clip-paste", arg: i },
          { title: "Copy to Clipboard", op: "clip-copy", arg: i }
        ]
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

  function setRows(out) {
    root.rows = out
    root.selectedIndex = -1
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
    root.mode = next
    root.actionsOpen = false
    if (next !== "detail") {
      input.text = ""
      root.query = ""
    }
    if (next === "emoji" && root.emojiData.length === 0) emojiFile.reload()
    root.rebuild()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function cycleMode(delta) {
    var modes = root.tabs.map(function(t) { return t.mode })
    var at = modes.indexOf(root.mode === "detail" ? "search" : root.mode)
    root.setMode(modes[(at + delta + modes.length) % modes.length])
  }

  function setQuery(text) {
    root.query = text
    if (root.mode === "ai" || root.mode === "detail") return
    root.rebuild()
    if (root.mode !== "search") return

    var q = text.trim()
    if (Engine.isCalcQuery(q)) calcTimer.restart()
    else root.calc = null

    var fq = root.fileQuery()
    if (fq.length >= 3) fileTimer.restart()
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
      || op === "uninstall" || op === "confirm-exec"
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
      var dir = root.notesDir()
      var file = dir + "/" + Engine.slug(action.arg) + ".md"
      root.exec("mkdir -p " + Engine.shellQuote(dir) + " && { [ -e " + Engine.shellQuote(file) + " ] || printf '# %s\\n\\n' " + Engine.shellQuote(action.arg) + " > " + Engine.shellQuote(file) + "; } && omarchy-launch-editor " + Engine.shellQuote(file))
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
        if (root.mode === "search") root.rebuildSearch()
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
        if (root.mode === "search") root.rebuildSearch()
      }
    }
    onExited: {
      if (pending) { pending = false; fileTimer.restart() }
      else root.filesBusy = false
    }
  }

  Process {
    id: notesProc
    function load() {
      var dir = root.notesDir()
      notesProc.command = ["bash", "-c", "[ -d \"$1\" ] && fd -e md -t f --max-depth 4 --absolute-path . \"$1\"", "_", dir]
      notesProc.running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(this.text || "").split("\n")
        var rows = []
        var dir = root.notesDir()
        for (var i = 0; i < lines.length; i++) {
          var path = lines[i]
          if (!path) continue
          var base = path.split("/").pop().replace(/\.md$/, "")
          var title = base.replace(/[-_]+/g, " ")
          title = title.charAt(0).toUpperCase() + title.substring(1)
          rows.push({
            id: "note." + path,
            kind: "note",
            title: title,
            subtitle: path.replace(dir + "/", "").replace(/[^\/]+$/, "").replace(/\/$/, "") || "Notes",
            accessory: "Note",
            glyph: "󱞁",
            keywords: ["note", base],
            actions: [
              { title: "Open Note", op: "edit-file", arg: path },
              { title: "Copy Contents", op: "exec-copy-file", arg: path },
              { title: "Show in Files", op: "reveal", arg: path }
            ]
          })
        }
        root.noteRows = rows
      }
    }
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

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

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

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cardRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(Style.space(20), Math.round(panel.height * 0.18))
      color: root.background
      border.width: Style.spacing.hairline
      border.color: Util.alpha(root.foreground, 0.13)
      opacity: panel.openProgress
      scale: 0.97 + 0.03 * panel.openProgress
      transformOrigin: Item.Top

      MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

      Column {
        id: layout
        anchors.fill: parent
        anchors.margins: card.border.width

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
            font.pixelSize: Math.round(Style.font.heading * 1.18)
            clip: true
            focus: true
            readOnly: root.mode === "detail"
            onTextEdited: root.setQuery(text)

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: input.text.length === 0
              text: root.mode === "clipboard" ? "Search clipboard history…"
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
        }

        // ------------------------------------------------------ content
        Item {
          id: content
          width: parent.width
          height: card.height - root.headerHeight - root.footerHeight - Style.spacing.hairline - card.border.width * 2

          // List (search + clipboard)
          ListView {
            id: resultList
            visible: root.mode === "search" || root.mode === "clipboard"
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.topMargin: Style.space(6)
            anchors.bottomMargin: Style.space(6)
            anchors.leftMargin: Style.space(8)
            width: root.mode === "clipboard" ? Math.round(parent.width * 0.44) : parent.width - Style.space(16)
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

          // Clipboard preview pane
          Item {
            visible: root.mode === "clipboard"
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
              visible: !!root.selectedRow && root.selectedRow.kind === "clip"

              Text {
                id: clipText
                visible: !!root.selectedRow && root.selectedRow.clipType === "text"
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
              visible: root.rows.length === 0
              text: root.query ? "No matches" : "Clipboard history is empty"
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
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
          width: parent.width
          height: root.footerHeight
          color: Util.alpha(root.foreground, 0.035)
          bottomLeftRadius: root.cardRadius - card.border.width
          bottomRightRadius: root.cardRadius - card.border.width

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
      Rectangle {
        id: actionPanel
        visible: root.actionsOpen && root.selectedActions.length > 0
        z: 30
        width: Style.space(320)
        height: actionColumn.implicitHeight + Style.space(12)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.footerHeight + Style.space(4)
        radius: Style.space(12)
        color: Qt.lighter(root.background, 1.25)
        border.width: Style.spacing.hairline
        border.color: Util.alpha(root.foreground, 0.16)

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
                visible: index < 2
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
                  text: index === 0 ? "↵" : "Ctrl ↵"
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
    if (root.filesBusy) return "Searching files…"
    return "Omacast"
  }

  readonly property var footerHints: {
    var primary = ""
    var actions = root.selectedActions
    if (root.mode === "ai") primary = root.aiBusy ? "Answering…" : "Ask"
    else if (actions.length > 0) primary = actions[0].title
    var hints = []
    if (primary) hints.push({ label: primary, keys: root.mode === "ai" && root.aiBusy ? [] : ["↵"] })
    if (actions.length > 0) hints.push({ label: "Actions", keys: ["Ctrl", "K"] })
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
      if (key === Qt.Key_Escape || (ctrl && key === Qt.Key_K)) root.actionsOpen = false
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

    if (key === Qt.Key_Escape) {
      if (root.mode === "detail") root.setMode("search")
      else if (input.text) { input.text = ""; root.setQuery("") }
      else if (root.mode !== "search") root.setMode("search")
      else root.close()
      event.accepted = true
    } else if (key === Qt.Key_Tab && !ctrl) {
      root.cycleMode(1)
      event.accepted = true
    } else if (key === Qt.Key_Backtab) {
      root.cycleMode(-1)
      event.accepted = true
    } else if (ctrl && key === Qt.Key_K) {
      if (root.selectedActions.length > 0) { root.actionIndex = 0; root.actionsOpen = true }
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
