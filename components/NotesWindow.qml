import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Floating notes, Raycast Notes style: a small always-on-top panel holding one
// Markdown note at a time, with a notes browser, a formatting bar and autosave.
// Notes are plain .md files in the notes folder; the first line is the title.
Item {
  id: notes

  // Set by Omacast.
  property string notesDir: Quickshell.env("HOME") + "/notes"
  property string stateDir: Quickshell.env("HOME") + "/.local/state/omacast"
  property string fontFamily: "SF Pro Text"
  property string iconFamily: "JetBrainsMono Nerd Font"
  property string monoFamily: "JetBrainsMono Nerd Font"
  property real baseSize: Style.font.title
  property bool showFormatBar: true
  property bool escapeCloses: true
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent

  property bool opened: false
  property string currentPath: ""
  property var noteList: []
  property bool browsing: false
  property int browseIndex: 0
  property string browseQuery: ""
  property var contentMatches: ({})
  property string pendingDelete: ""
  property string status: ""
  property real zoom: 1.0
  property var geo: ({ x: -1, y: -1, w: 460, h: 420 })
  property var history: []


  signal listChanged()

  readonly property string title: {
    var _ = notes.titleSerial
    return editor.title() || "Untitled"
  }
  property int titleSerial: 0

  // ------------------------------------------------------------- lifecycle
  function toggle() {
    if (notes.opened) notes.close()
    else notes.open("")
  }

  function open(path) {
    notes.refreshList()
    var target = path || notes.currentPath
    notes.opened = true
    restoreTimer.restart()
    if (target && target !== notes.currentPath) notes.load(target)
    else if (!notes.currentPath) {
      if (notes.noteList.length > 0) notes.load(notes.noteList[0].path)
      else notes.newNote()
    }
    Qt.callLater(function() { editor.focusEnd() })
  }

  function close() {
    notes.flush()
    notes.browsing = false
    geoProc.running = true
  }

  // A real (floating, pinned) window rather than an overlay, so focus behaves
  // like any app: it takes focus when shown and gives it up when you click
  // elsewhere. Hyprland window rules from hyprland.lua float and pin it.
  readonly property string windowTitle: "Omacast Notes"

  // Remember where it was before hiding it.
  Process {
    id: geoProc
    command: ["bash", "-c", "hyprctl clients -j | jq -c --arg t \"$1\" 'first(.[] | select(.title == $t)) | {x: .at[0], y: .at[1], w: .size[0], h: .size[1]}'", "_", notes.windowTitle]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var g = JSON.parse(this.text)
          if (g && g.w > 100) { notes.geo = g; notes.saveState() }
        } catch (e) { }
        notes.opened = false
      }
    }
  }

  // Put it back where it was once Hyprland has mapped it.
  Timer {
    id: restoreTimer
    interval: 120
    onTriggered: {
      var g = notes.geo
      if (g.x < 0 || g.y < 0) return
      Quickshell.execDetached(["bash", "-c",
        "a=$(hyprctl clients -j | jq -r --arg t \"$1\" 'first(.[] | select(.title == $t)) | .address'); [ -n \"$a\" ] || exit 0; " +
        "hyprctl dispatch \"hl.dsp.window.resize({ window = \\\"address:$a\\\", x = $4, y = $5 })\" >/dev/null; " +
        "hyprctl dispatch \"hl.dsp.window.move({ window = \\\"address:$a\\\", x = $2, y = $3 })\" >/dev/null",
        "_", notes.windowTitle, String(g.x), String(g.y), String(g.w), String(g.h)])
    }
  }

  function newNote(initialTitle) {
    notes.flush()
    var stamp = new Date()
    var pad = function(n) { return n < 10 ? "0" + n : "" + n }
    var name = "note-" + stamp.getFullYear() + pad(stamp.getMonth() + 1) + pad(stamp.getDate())
      + "-" + pad(stamp.getHours()) + pad(stamp.getMinutes()) + pad(stamp.getSeconds()) + ".md"
    notes.currentPath = notes.notesDir + "/" + name
    editor.setMarkdown(initialTitle ? "# " + initialTitle + "\n\n" : "")
    notes.titleSerial++
    notes.status = ""
    notes.browsing = false
    notes.opened = true
    Qt.callLater(function() { editor.focusEnd() })
  }

  function load(path) {
    notes.flush()
    if (notes.currentPath && notes.currentPath !== path)
      notes.history = notes.history.concat([notes.currentPath]).slice(-30)
    notes.currentPath = path
    notes.status = ""
    noteFile.reload()
    notes.browsing = false
    notes.saveState()
  }

  // ------------------------------------------------------------ persistence
  property bool dirty: false

  function flush() {
    if (!notes.dirty || !notes.currentPath) return
    saveTimer.stop()
    notes.writeNow()
  }

  function writeNow() {
    var md = editor.markdown()
    // Never create a file for an empty, never-saved note.
    if (!md.trim() && !notes.fileExists) { notes.dirty = false; return }
    noteFile.setText(md)
    notes.fileExists = true
    notes.dirty = false
    notes.status = "Saved"
    statusTimer.restart()
    listRefresh.restart()
  }

  property bool fileExists: false

  FileView {
    id: noteFile
    path: notes.currentPath
    printErrors: false
    atomicWrites: true
    onLoaded: {
      notes.fileExists = true
      editor.setMarkdown(text())
      notes.titleSerial++
      notes.dirty = false
      Qt.callLater(function() { editor.focusEnd() })
    }
    onLoadFailed: {
      notes.fileExists = false
      editor.setMarkdown("")
      notes.titleSerial++
    }
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: notes.writeNow()
  }

  Timer {
    id: statusTimer
    interval: 1600
    onTriggered: notes.status = ""
  }

  Timer {
    id: listRefresh
    interval: 600
    onTriggered: notes.refreshList()
  }

  function onEdited() {
    notes.dirty = true
    notes.status = "Editing"
    notes.titleSerial++
    saveTimer.restart()
  }

  // ----------------------------------------------------------- note list
  function refreshList() {
    listProc.running = false
    listProc.running = true
  }

  Process {
    id: listProc
    command: ["bash", "-c",
      "mkdir -p \"$1\"; cd \"$1\" || exit 0; " +
      "find . -maxdepth 3 -name '*.md' -type f -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -500 | " +
      "while IFS=$'\\t' read -r t p; do " +
      "  title=$(grep -m1 -v '^[[:space:]]*$' \"$p\" 2>/dev/null | sed -E 's/^#+ +//; s/^[-*] +(\\[.\\] +)?//; s/\\\\([[:punct:]])/\\1/g' | cut -c1-120); " +
      "  body=$(grep -v '^[[:space:]]*$' \"$p\" 2>/dev/null | sed -n '2p' | sed -E 's/^#+ +//; s/^[-*] +(\\[.\\] +)?//' | cut -c1-120); " +
      "  printf '%s\\t%s\\t%s\\t%s\\n' \"${t%.*}\" \"$1/${p#./}\" \"$title\" \"$body\"; " +
      "done", "_", notes.notesDir]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = String(this.text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2 || !parts[1]) continue
          var file = parts[1].split("/").pop().replace(/\.md$/, "")
          out.push({
            path: parts[1],
            mtime: Number(parts[0]) * 1000,
            title: parts[2] || file.replace(/[-_]+/g, " "),
            preview: parts[3] || ""
          })
        }
        notes.noteList = out
        notes.listChanged()
      }
    }
  }

  // Body search for the browser: files whose content matches.
  Process {
    id: grepProc
    property string query: ""
    stdout: StdioCollector {
      onStreamFinished: {
        if (grepProc.query !== notes.browseQuery) return
        var set = ({})
        var lines = String(this.text || "").split("\n")
        for (var i = 0; i < lines.length; i++) if (lines[i]) set[lines[i]] = true
        notes.contentMatches = set
      }
    }
  }

  Timer {
    id: grepTimer
    interval: 120
    onTriggered: {
      if (!notes.browseQuery.trim()) { notes.contentMatches = ({}); return }
      grepProc.query = notes.browseQuery
      grepProc.command = ["rg", "-l", "-i", "-F", "--glob", "*.md", "--", notes.browseQuery.trim(), notes.notesDir]
      grepProc.running = true
    }
  }

  readonly property var browseRows: {
    var q = notes.browseQuery.trim().toLowerCase()
    var out = []
    for (var i = 0; i < notes.noteList.length; i++) {
      var n = notes.noteList[i]
      if (!q || n.title.toLowerCase().indexOf(q) >= 0 || notes.contentMatches[n.path]) out.push(n)
    }
    return out
  }

  function relativeTime(ms) {
    var diff = (Date.now() - ms) / 1000
    if (diff < 60) return "now"
    if (diff < 3600) return Math.floor(diff / 60) + "m"
    if (diff < 86400) return Math.floor(diff / 3600) + "h"
    if (diff < 86400 * 7) return Math.floor(diff / 86400) + "d"
    return new Date(ms).toLocaleDateString(Qt.locale(), "d MMM")
  }

  function deleteNote(path) {
    Quickshell.execDetached(["gio", "trash", path])
    if (path === notes.currentPath) {
      notes.currentPath = ""
      notes.dirty = false
      editor.setMarkdown("")
    }
    notes.pendingDelete = ""
    listRefresh.restart()
  }

  // ----------------------------------------------------------- state file
  FileView {
    id: stateFile
    path: notes.stateDir + "/notes.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var s = JSON.parse(text())
        if (s.geo) notes.geo = s.geo
        if (s.zoom) notes.zoom = s.zoom
        if (s.lastPath) notes.currentPath = s.lastPath
      } catch (e) { }
    }
  }

  Timer {
    id: stateTimer
    interval: 500
    onTriggered: stateFile.setText(JSON.stringify({ geo: notes.geo, zoom: notes.zoom, lastPath: notes.currentPath }) + "\n")
  }

  function saveState() { stateTimer.restart() }

  // -------------------------------------------------------------- window
  FloatingWindow {
    id: win
    visible: notes.opened
    title: notes.windowTitle
    implicitWidth: notes.geo.w
    implicitHeight: notes.geo.h
    color: "transparent"

    // A regular window: Hyprland draws Omarchy's border, rounding and
    // opacity around it, like every other app.
    Rectangle {
      id: card
      anchors.fill: parent
      radius: 0
      color: notes.background
      border.width: 0


      // ------------------------------------------------------- title bar
      Item {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 40

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.OpenHandCursor
          onPressed: titleBar.Window.window.startSystemMove()
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          IconButton { glyph: "󰍜"; tip: "Browse notes (Ctrl+P)"; active: notes.browsing; onClicked: notes.toggleBrowse() }
          IconButton { glyph: ""; tip: "Back (Ctrl+[)"; enabled: notes.history.length > 0; onClicked: notes.goBack() }
        }

        Text {
          anchors.centerIn: parent
          width: parent.width - 180
          horizontalAlignment: Text.AlignHCenter
          text: notes.browsing ? "Notes" : notes.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: notes.foreground
          opacity: 0.75
          font.family: notes.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          IconButton { glyph: ""; tip: "New note (Ctrl+N)"; onClicked: notes.newNote() }
          IconButton { glyph: ""; tip: "Close (Esc)"; onClicked: notes.close() }
        }

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: 1
          color: Util.alpha(notes.foreground, 0.07)
        }
      }

      // --------------------------------------------------------- editor
      MarkdownEditor {
        id: editor
        anchors.top: titleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: formatBar.visible ? formatBar.top : parent.bottom
        anchors.bottomMargin: formatBar.visible ? 0 : 8
        visible: !notes.browsing
        fontFamily: notes.fontFamily
        monoFamily: notes.monoFamily
        pixelSize: Math.round(notes.baseSize * notes.zoom)
        textColor: notes.foreground
        accentColor: notes.accent
        selectionColor: Util.alpha(notes.accent, 0.35)
        onEdited: notes.onEdited()
        onEscapePressed: if (notes.escapeCloses) notes.close()
        onShortcut: function(name) { notes.handleShortcut(name) }
      }

      // ------------------------------------------------------ format bar
      Rectangle {
        id: formatBar
        visible: notes.showFormatBar && !notes.browsing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 36
        color: Util.alpha(notes.foreground, 0.035)
        bottomLeftRadius: 0
        bottomRightRadius: 0

        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Util.alpha(notes.foreground, 0.07) }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: notes.status ? notes.status : (editor.wordCount + (editor.wordCount === 1 ? " word · " : " words · ") + editor.characterCount + (editor.characterCount === 1 ? " char" : " chars"))
          color: notes.foreground
          opacity: 0.45
          font.family: notes.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0
          IconButton { glyph: ""; tip: "Bold (Ctrl+B)"; small: true; onClicked: editor.toggleInline("bold") }
          IconButton { glyph: ""; tip: "Italic (Ctrl+I)"; small: true; onClicked: editor.toggleInline("italic") }
          IconButton { glyph: ""; tip: "Strikethrough (Ctrl+Shift+X)"; small: true; onClicked: editor.toggleInline("strike") }
          IconButton { glyph: ""; tip: "Code (Ctrl+E)"; small: true; onClicked: editor.toggleInline("code") }
          IconButton { glyph: "󰉫"; tip: "Heading (Ctrl+Alt+1)"; small: true; onClicked: editor.setBlockType("h1") }
          IconButton { glyph: ""; tip: "Bullet list (Ctrl+Shift+8)"; small: true; onClicked: editor.setBlockType("ul") }
          IconButton { glyph: ""; tip: "Numbered list (Ctrl+Shift+7)"; small: true; onClicked: editor.setBlockType("ol") }
          IconButton { glyph: ""; tip: "Task (Ctrl+Shift+9)"; small: true; onClicked: editor.setBlockType("task") }
          IconButton { glyph: ""; tip: "Quote (Ctrl+Shift+B)"; small: true; onClicked: editor.setBlockType("quote") }
        }
      }

      // -------------------------------------------------------- browser
      Item {
        id: browser
        visible: notes.browsing
        anchors.top: titleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8

        Rectangle {
          id: searchBox
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 34
          radius: 8
          color: Util.alpha(notes.foreground, 0.06)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: notes.foreground
            opacity: 0.4
            font.family: notes.iconFamily
            font.pixelSize: Style.font.body
          }

          TextInput {
            id: searchInput
            anchors.fill: parent
            anchors.leftMargin: 32
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: notes.foreground
            font.family: notes.fontFamily
            font.pixelSize: Style.font.subtitle
            selectionColor: Util.alpha(notes.accent, 0.35)
            clip: true
            onTextEdited: {
              notes.browseQuery = text
              notes.browseIndex = 0
              notes.pendingDelete = ""
              grepTimer.restart()
            }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: !searchInput.text
              text: "Search notes…"
              color: notes.foreground
              opacity: 0.35
              font: searchInput.font
            }

            Keys.onPressed: function(event) {
              var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              var rows = notes.browseRows
              if (event.key === Qt.Key_Escape) { notes.toggleBrowse(); event.accepted = true }
              else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) { notes.browseIndex = Math.min(rows.length - 1, notes.browseIndex + 1); browseList.positionViewAtIndex(notes.browseIndex, ListView.Contain); event.accepted = true }
              else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) { notes.browseIndex = Math.max(0, notes.browseIndex - 1); browseList.positionViewAtIndex(notes.browseIndex, ListView.Contain); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (rows[notes.browseIndex]) notes.load(rows[notes.browseIndex].path)
                else if (searchInput.text.trim()) notes.newNote(searchInput.text.trim())
                event.accepted = true
              }
              else if (ctrl && event.key === Qt.Key_Backspace) {
                var row = rows[notes.browseIndex]
                if (row) {
                  if (notes.pendingDelete === row.path) notes.deleteNote(row.path)
                  else notes.pendingDelete = row.path
                }
                event.accepted = true
              }
            }
          }
        }

        ListView {
          id: browseList
          anchors.top: searchBox.bottom
          anchors.topMargin: 6
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: browserHint.top
          clip: true
          spacing: 2
          model: notes.browseRows
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool selected: index === notes.browseIndex
            readonly property bool current: modelData.path === notes.currentPath
            readonly property bool deleting: modelData.path === notes.pendingDelete
            width: ListView.view.width
            height: 46
            radius: 8
            color: deleting ? Util.alpha("#e5484d", 0.18) : (selected ? Util.alpha(notes.foreground, 0.085) : "transparent")

            Rectangle {
              visible: current
              width: 3
              height: 18
              radius: 2
              color: notes.accent
              anchors.left: parent.left
              anchors.leftMargin: 3
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.right: timeText.left
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              Text {
                width: parent.width
                text: deleting ? "Press Ctrl+Backspace again to move to Trash" : modelData.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: notes.foreground
                font.family: notes.fontFamily
                font.pixelSize: Style.font.subtitle
                font.weight: Font.Medium
              }
              Text {
                width: parent.width
                visible: text.length > 0
                text: deleting ? modelData.title : modelData.preview
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: notes.foreground
                opacity: 0.45
                font.family: notes.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              id: timeText
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: notes.relativeTime(modelData.mtime)
              color: notes.foreground
              opacity: 0.35
              font.family: notes.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: notes.browseIndex = index
              onClicked: notes.load(modelData.path)
            }
          }
        }

        Text {
          anchors.centerIn: browseList
          visible: notes.browseRows.length === 0
          text: notes.browseQuery ? "No notes match. Enter creates “" + notes.browseQuery + "”." : "No notes yet"
          color: notes.foreground
          opacity: 0.45
          font.family: notes.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: browserHint
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          height: 22
          verticalAlignment: Text.AlignVCenter
          text: "↵ open · Ctrl+⌫ trash · Esc back"
          color: notes.foreground
          opacity: 0.35
          font.family: notes.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // --------------------------------------------------------- resize
      MouseArea {
        width: 16
        height: 16
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        cursorShape: Qt.SizeFDiagCursor
        onPressed: parent.Window.window.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
      }
    }
  }

  // ------------------------------------------------------------ helpers
  function toggleBrowse() {
    notes.browsing = !notes.browsing
    notes.pendingDelete = ""
    if (notes.browsing) {
      notes.flush()
      notes.refreshList()
      searchInput.text = ""
      notes.browseQuery = ""
      notes.browseIndex = 0
      Qt.callLater(function() { searchInput.forceActiveFocus() })
    } else {
      Qt.callLater(function() { editor.focusEnd() })
    }
  }

  function editorHasFocus() { return editor.editor.activeFocus }

  function goBack() {
    if (notes.history.length === 0) return
    var prev = notes.history[notes.history.length - 1]
    notes.history = notes.history.slice(0, -1)
    notes.flush()
    notes.currentPath = prev
    noteFile.reload()
  }

  function handleShortcut(name) {
    if (name === "new") notes.newNote()
    else if (name === "browse" || name === "find") notes.toggleBrowse()
    else if (name === "close") notes.close()
    else if (name === "zoom-in") { notes.zoom = Math.min(2, notes.zoom + 0.1); notes.saveState() }
    else if (name === "zoom-out") { notes.zoom = Math.max(0.7, notes.zoom - 0.1); notes.saveState() }
    else if (name === "zoom-reset") { notes.zoom = 1; notes.saveState() }
    else if (name === "link") linkProc.running = true
  }

  // Ctrl+L: link the selection to the URL on the clipboard.
  Process {
    id: linkProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      onStreamFinished: {
        var url = String(this.text || "").trim()
        editor.insertLink(/^https?:\/\//.test(url) ? url : "https://")
      }
    }
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", notes.notesDir, notes.stateDir])
    notes.refreshList()
  }
}
