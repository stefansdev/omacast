import QtQuick

// A live-formatting Markdown editor, Raycast Notes style.
//
// The document is a QTextDocument in Markdown mode: what you see is formatted,
// what `markdown` returns (and what gets saved) is plain Markdown. Typing
// Markdown syntax converts in place: "# " / "## " / "### " headings, "- " or
// "* " bullets, "1. " numbers, "[] " or "- [ ] " tasks, "> " quotes, "```" code
// blocks, and **bold**, *italic*, `code`, ~~strike~~ once the
// closing marker is followed by a space.
//
// Pure QtQuick on purpose, so it runs under qmltestrunner (tests/).
Flickable {
  id: root

  property string fontFamily: "SF Pro Text"
  property string monoFamily: "JetBrainsMono Nerd Font"
  property int pixelSize: 15
  property color textColor: "#e6e6e6"
  property color accentColor: "#e68e0d"
  property color selectionColor: Qt.rgba(0.9, 0.55, 0.05, 0.35)
  property real padding: 18
  property bool readOnly: false

  readonly property alias editor: ed
  readonly property int characterCount: Math.max(0, ed.length - root.blockCount() + 1)
  readonly property int wordCount: {
    var t = ed.getText(0, ed.length).replace(/[\u2029\u2028]/g, " ").trim()
    return t ? t.split(/\s+/).length : 0
  }

  property bool _loading: false
  signal edited()
  signal escapePressed()
  signal shortcut(string name)

  // ------------------------------------------------------------ public API
  function setMarkdown(md) {
    root._loading = true
    ed.text = String(md || "")
    ed.cursorPosition = 0
    root.contentY = 0
    root._loading = false
  }

  function markdown() {
    return ed.text
  }

  function focusEnd() {
    ed.forceActiveFocus()
    ed.cursorPosition = ed.length
  }

  function blockCount() {
    var t = ed.getText(0, ed.length)
    return (t.match(/\u2029/g) || []).length + 1
  }

  // First non-empty line as plain text, for titles.
  function title() {
    var lines = ed.getText(0, Math.min(ed.length, 400)).split(/[\u2029\u2028\n]/)
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i].trim()
      if (l) return l
    }
    return ""
  }

  // ------------------------------------------------------------- blocks
  function isSep(c) { return c === "\u2029" || c === "\n" || c === "\u2028" }

  function range(pos) {
    var all = ed.getText(0, ed.length)
    var p = Math.max(0, Math.min(pos, all.length))
    var s = p
    while (s > 0 && !isSep(all[s - 1])) s--
    var e = p
    while (e < all.length && !isSep(all[e])) e++
    return { start: s, end: e }
  }

  // Markdown of one block, including its list/heading/quote prefix.
  function blockMarkdown(r) {
    var md = r.start > 0 ? ed.getFormattedText(r.start - 1, r.end) : ed.getFormattedText(0, r.end)
    return String(md || "").replace(/^\n+|\n+$/g, "")
  }

  readonly property var prefixPatterns: [
    { type: "task-done", re: /^\s*[-*+] \[[xX]\] / },
    { type: "task", re: /^\s*[-*+] \[ \] / },
    { type: "ul", re: /^\s*[-*+] / },
    { type: "ol", re: /^\s*\d+[.)] +/ },
    { type: "h1", re: /^# / },
    { type: "h2", re: /^## / },
    { type: "h3", re: /^###+ / },
    { type: "quote", re: /^> ?/ }
  ]

  function blockType(md) {
    if (/^```/.test(md)) return "code"
    for (var i = 0; i < prefixPatterns.length; i++)
      if (prefixPatterns[i].re.test(md)) return prefixPatterns[i].type
    return "p"
  }

  function stripPrefix(md) {
    var s = md
    if (/^```/.test(s)) return s.replace(/^```[^\n]*\n?/, "").replace(/\n?```\s*$/, "")
    for (var i = 0; i < prefixPatterns.length; i++) {
      if (prefixPatterns[i].re.test(s)) return s.replace(prefixPatterns[i].re, "")
    }
    return s
  }

  function prefixFor(type) {
    switch (type) {
    case "h1": return "# "
    case "h2": return "## "
    case "h3": return "### "
    case "ul": return "- "
    case "ol": return "1. "
    case "task": return "- [ ] "
    case "task-done": return "- [x] "
    case "quote": return "> "
    }
    return ""
  }

  // Replace a block with new Markdown, keeping the caret `offset` characters
  // into the block's text.
  function replaceBlock(r, md, offset) {
    root._loading = true
    if (r.start > 0) {
      ed.remove(r.start - 1, r.end)
      ed.insert(r.start - 1, "\n" + md)
    } else {
      var rest = ed.length > r.end
      ed.insert(0, md + (rest ? "\n" : ""))
      if (rest) {
        var all = ed.getText(0, ed.length)
        var next = all.indexOf("\u2029") + 1
        var old = root.range(next)
        ed.remove(old.start - 1, old.end)
      } else {
        // The inserted block came before the (now empty) original one.
        var tail = root.range(ed.length)
        if (tail.start > 0 && tail.end === tail.start) ed.remove(tail.start - 1, tail.end)
      }
    }
    root._loading = false
    var nr = root.range(r.start)
    ed.cursorPosition = Math.min(nr.start + Math.max(0, offset || 0), nr.end)
    root.edited()
  }

  function setBlockType(type) {
    var r = root.range(ed.cursorPosition)
    var md = root.blockMarkdown(r)
    var current = root.blockType(md)
    var content = root.stripPrefix(md)
    var offset = ed.cursorPosition - r.start
    var target = current === type ? "p" : type
    // An empty heading or list item exports as nothing, so build the block
    // around a placeholder character and delete it once the format exists.
    var placeholder = content.length === 0 && target !== "p"
    if (placeholder) content = "x"
    if (target === "code") root.replaceBlock(r, "```\n" + content + "\n```", offset)
    else root.replaceBlock(r, root.prefixFor(target) + content, offset)
    if (placeholder) {
      var nr = root.range(ed.cursorPosition)
      root._loading = true
      ed.remove(nr.start, nr.end)
      root._loading = false
      ed.cursorPosition = nr.start
    }
  }

  function toggleTask() {
    var r = root.range(ed.cursorPosition)
    var md = root.blockMarkdown(r)
    var type = root.blockType(md)
    if (type !== "task" && type !== "task-done") return false
    root.replaceBlock(r, root.prefixFor(type === "task" ? "task-done" : "task") + root.stripPrefix(md), ed.cursorPosition - r.start)
    return true
  }

  // ------------------------------------------------------------ inline
  function toggleInline(kind) {
    var s = ed.selectionStart
    var e = ed.selectionEnd
    if (s === e) return
    var sel = ed.cursorSelection
    if (kind === "bold") sel.font.bold = !sel.font.bold
    else if (kind === "italic") sel.font.italic = !sel.font.italic
    else if (kind === "strike") sel.font.strikeout = !sel.font.strikeout
    else if (kind === "underline") sel.font.underline = !sel.font.underline
    else if (kind === "code") {
      var md = ed.getFormattedText(s, e).replace(/\n+$/, "")
      var isCode = /^`[^`]*`$/.test(md)
      root._loading = true
      ed.remove(s, e)
      ed.insert(s, isCode ? md.replace(/^`|`$/g, "") : "`" + md.replace(/`/g, "") + "`")
      root._loading = false
    }
    root.edited()
  }

  function insertLink(url) {
    var s = ed.selectionStart
    var e = ed.selectionEnd
    var label = s === e ? url : ed.getText(s, e)
    root._loading = true
    if (s !== e) ed.remove(s, e)
    ed.insert(s, "[" + label.replace(/[\[\]]/g, "") + "](" + url + ")")
    root._loading = false
    root.edited()
  }

  // ------------------------------------------------------- autoformat
  readonly property var blockTriggers: [
    { marker: "- [ ] ", type: "task" }, { marker: "- [x] ", type: "task-done" },
    { marker: "[] ", type: "task" }, { marker: "[ ] ", type: "task" },
    { marker: "### ", type: "h3" }, { marker: "## ", type: "h2" }, { marker: "# ", type: "h1" },
    { marker: "- ", type: "ul" }, { marker: "* ", type: "ul" }, { marker: "+ ", type: "ul" },
    { marker: "1. ", type: "ol" }, { marker: "1) ", type: "ol" },
    { marker: "> ", type: "quote" }
  ]

  // Called right after a space was typed.
  function autoformatAfterSpace() {
    var pos = ed.cursorPosition
    var r = root.range(pos)
    var typed = ed.getText(r.start, pos)

    // Block markers typed at the very start of a plain paragraph.
    if (root.blockType(root.blockMarkdown(r)) === "p" || /^(- )?\[[ x]?\] $/.test(typed)) {
      for (var i = 0; i < blockTriggers.length; i++) {
        var t = blockTriggers[i]
        if (typed === t.marker) {
          root._loading = true
          ed.remove(r.start, pos)
          root._loading = false
          root.setBlockType(t.type)
          return true
        }
      }
    }

    // Inline: **bold** *italic* _italic_ `code` ~~strike~~ followed by the space.
    var patterns = [
      /(\*\*|__)([^\s*_](?:[^*_]*[^\s*_])?)\1 $/,
      /~~([^\s~](?:[^~]*[^\s~])?)~~ $/,
      /`([^`]+)` $/,
      /(^|[^*\w])\*([^\s*](?:[^*]*[^\s*])?)\* $/,
      /(^|[^_\w])_([^\s_](?:[^_]*[^\s_])?)_ $/
    ]
    for (var p = 0; p < patterns.length; p++) {
      var m = typed.match(patterns[p])
      if (!m) continue
      var lead = (p >= 3) ? m[1].length : 0
      var raw = m[0].substring(lead, m[0].length - 1)
      // Reformat only the marked run; the space just typed stays as it is,
      // unformatted, so typing after it continues in plain text.
      var from = pos - 1 - raw.length
      root._loading = true
      ed.remove(from, pos - 1)
      ed.insert(from, raw)
      root._loading = false
      ed.cursorPosition = from + root.plainLength(raw) + 1
      root.edited()
      return true
    }
    return false
  }

  function plainLength(md) {
    return md.replace(/^(\*\*|__|~~|`|\*|_)|(\*\*|__|~~|`|\*|_)$/g, "").length
  }

  // Return on an empty list/task/quote item leaves the list instead.
  function handleReturn() {
    var r = root.range(ed.cursorPosition)
    if (r.end !== r.start) return false
    var type = root.blockType(root.blockMarkdown(r))
    if (type === "p" || type === "h1" || type === "h2" || type === "h3") return false
    root.replaceBlock(r, "", 0)
    // An empty paragraph exports as nothing; keep a visible empty line.
    return true
  }

  // ---------------------------------------------------------------- view
  contentWidth: width
  contentHeight: ed.contentHeight + root.padding * 2
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height

  function ensureVisible(rect) {
    if (rect.y < root.contentY) root.contentY = rect.y
    else if (rect.y + rect.height + root.padding * 2 > root.contentY + root.height)
      root.contentY = rect.y + rect.height + root.padding * 2 - root.height
  }

  TextEdit {
    id: ed
    x: root.padding
    y: root.padding
    width: root.width - root.padding * 2
    textFormat: TextEdit.MarkdownText
    wrapMode: TextEdit.Wrap
    color: root.textColor
    selectionColor: root.selectionColor
    selectedTextColor: root.textColor
    font.family: root.fontFamily
    font.pixelSize: root.pixelSize
    selectByMouse: true
    persistentSelection: true
    readOnly: root.readOnly
    focus: true
    cursorDelegate: Rectangle {
      width: 2
      radius: 1
      color: root.accentColor
      visible: ed.cursorVisible
    }

    onCursorRectangleChanged: root.ensureVisible(cursorRectangle)
    onTextChanged: if (!root._loading) root.edited()
    onLinkActivated: function(link) { Qt.openUrlExternally(link) }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
      var shift = (event.modifiers & Qt.ShiftModifier) !== 0
      var alt = (event.modifiers & Qt.AltModifier) !== 0
      var key = event.key

      if (key === Qt.Key_Escape) { root.escapePressed(); event.accepted = true; return }

      if (ctrl && alt) {
        if (key === Qt.Key_1) root.setBlockType("h1")
        else if (key === Qt.Key_2) root.setBlockType("h2")
        else if (key === Qt.Key_3) root.setBlockType("h3")
        else if (key === Qt.Key_0) root.setBlockType("p")
        else if (key === Qt.Key_C) root.setBlockType("code")
        else return
        event.accepted = true
        return
      }
      if (ctrl && shift) {
        if (key === Qt.Key_7 || key === Qt.Key_Ampersand) root.setBlockType("ol")
        else if (key === Qt.Key_8 || key === Qt.Key_Asterisk) root.setBlockType("ul")
        else if (key === Qt.Key_9 || key === Qt.Key_ParenLeft) root.setBlockType("task")
        else if (key === Qt.Key_B) root.setBlockType("quote")
        else if (key === Qt.Key_X || key === Qt.Key_S) root.toggleInline("strike")
        else return
        event.accepted = true
        return
      }
      if (ctrl) {
        if (key === Qt.Key_B) root.toggleInline("bold")
        else if (key === Qt.Key_I) root.toggleInline("italic")
        else if (key === Qt.Key_U) root.toggleInline("underline")
        else if (key === Qt.Key_E) root.toggleInline("code")
        else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.toggleTask()
        else if (key === Qt.Key_N) root.shortcut("new")
        else if (key === Qt.Key_P) root.shortcut("browse")
        else if (key === Qt.Key_L) root.shortcut("link")
        else if (key === Qt.Key_W) root.shortcut("close")
        else if (key === Qt.Key_F) root.shortcut("find")
        else if (key === Qt.Key_Equal || key === Qt.Key_Plus) root.shortcut("zoom-in")
        else if (key === Qt.Key_Minus) root.shortcut("zoom-out")
        else if (key === Qt.Key_0) root.shortcut("zoom-reset")
        else return
        event.accepted = true
        return
      }
      if ((key === Qt.Key_Return || key === Qt.Key_Enter) && !shift) {
        if (root.handleReturn()) event.accepted = true
        return
      }
      if (key === Qt.Key_Space && !root.readOnly) {
        // Let the space land first, then look at what was typed.
        Qt.callLater(root.autoformatAfterSpace)
      }
    }

    // Clicking a task's checkbox (left of its text) toggles it.
    TapHandler {
      acceptedButtons: Qt.LeftButton
      grabPermissions: PointerHandler.TakeOverForbidden
      onTapped: function(point) {
        var pos = ed.positionAt(point.position.x, point.position.y)
        var r = root.range(pos)
        var type = root.blockType(root.blockMarkdown(r))
        if (type !== "task" && type !== "task-done") return
        var start = ed.positionToRectangle(r.start)
        if (point.position.x < start.x - 2) {
          ed.cursorPosition = r.start
          root.toggleTask()
        }
      }
    }
  }
}
