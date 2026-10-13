import QtQuick
import qs.Commons

// Hyprland hotkey recorder. Shows "SUPER + ALT + N" as keycaps; click to record
// (the host pauses Hyprland's own shortcuts meanwhile), Backspace clears,
// Escape cancels.
FocusScope {
  id: field
  property string value: ""
  property string fontFamily: "SF Pro Text"
  property bool recording: false
  property string placeholder: "Record Hotkey"
  signal changed(string value)
  signal recordingChanged2(bool on)

  width: 190
  height: 28

  function start() {
    field.recording = true
    catcher.forceActiveFocus()
    field.recordingChanged2(true)
  }

  function stop() {
    if (!field.recording) return
    field.recording = false
    field.recordingChanged2(false)
  }

  readonly property var shiftedToBase: ({
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    "_": "minus", "+": "equal", "{": "bracketleft", "}": "bracketright", "|": "backslash",
    ":": "semicolon", "\"": "apostrophe", "<": "comma", ">": "period", "?": "slash", "~": "grave"
  })

  function keyName(event) {
    var k = event.key
    if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k)
    if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k)
    if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1)
    var named = {}
    named[Qt.Key_Space] = "SPACE"; named[Qt.Key_Return] = "RETURN"; named[Qt.Key_Enter] = "RETURN"
    named[Qt.Key_Tab] = "TAB"; named[Qt.Key_Backtab] = "TAB"; named[Qt.Key_Left] = "LEFT"; named[Qt.Key_Right] = "RIGHT"
    named[Qt.Key_Up] = "UP"; named[Qt.Key_Down] = "DOWN"; named[Qt.Key_Home] = "HOME"; named[Qt.Key_End] = "END"
    named[Qt.Key_PageUp] = "PRIOR"; named[Qt.Key_PageDown] = "NEXT"; named[Qt.Key_Delete] = "DELETE"
    named[Qt.Key_Insert] = "INSERT"; named[Qt.Key_Period] = "PERIOD"; named[Qt.Key_Comma] = "COMMA"
    named[Qt.Key_Slash] = "SLASH"; named[Qt.Key_Semicolon] = "SEMICOLON"; named[Qt.Key_Minus] = "MINUS"
    named[Qt.Key_Equal] = "EQUAL"; named[Qt.Key_BracketLeft] = "BRACKETLEFT"; named[Qt.Key_BracketRight] = "BRACKETRIGHT"
    named[Qt.Key_Backslash] = "BACKSLASH"; named[Qt.Key_QuoteLeft] = "GRAVE"; named[Qt.Key_Apostrophe] = "APOSTROPHE"
    named[Qt.Key_Print] = "PRINT"; named[Qt.Key_Escape] = "ESCAPE"
    if (named[k]) return named[k]
    var base = field.shiftedToBase[event.text]
    if (base) return base.toUpperCase()
    return ""
  }

  function caps(value) {
    return String(value || "").split("+").map(function(p) { return p.trim() }).filter(function(p) { return p.length > 0 })
  }

  function pretty(part) {
    var p = part.toUpperCase()
    var map = { "SUPER": "Super", "CTRL": "Ctrl", "CONTROL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift",
      "SPACE": "Space", "RETURN": "Return", "ESCAPE": "Esc", "PERIOD": ".", "COMMA": ",", "SLASH": "/",
      "SEMICOLON": ";", "MINUS": "-", "EQUAL": "=", "BRACKETLEFT": "[", "BRACKETRIGHT": "]",
      "BACKSLASH": "\\", "GRAVE": "`", "APOSTROPHE": "'", "LEFT": "←", "RIGHT": "→", "UP": "↑", "DOWN": "↓",
      "PRIOR": "PgUp", "NEXT": "PgDn", "TAB": "Tab", "DELETE": "Del" }
    return map[p] || part
  }

  Rectangle {
    anchors.fill: parent
    radius: 7
    color: field.recording ? Util.alpha(Color.accent, 0.14) : Util.alpha(Color.menu.text, 0.06)
    border.width: 1
    border.color: field.recording ? Util.alpha(Color.accent, 0.8) : Util.alpha(Color.menu.text, 0.1)

    Row {
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4
      visible: !field.recording && field.value.length > 0
      Repeater {
        model: field.caps(field.value)
        delegate: Rectangle {
          required property var modelData
          height: 20
          width: Math.max(20, capText.implicitWidth + 10)
          radius: 4
          color: Util.alpha(Color.menu.text, 0.12)
          Text {
            id: capText
            anchors.centerIn: parent
            text: field.pretty(modelData)
            color: Color.menu.text
            font.family: field.fontFamily
            font.pixelSize: Style.font.caption + 1
            font.weight: Font.Medium
          }
        }
      }
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      visible: field.recording || field.value.length === 0
      text: field.recording ? "Press keys… (Esc cancels, ⌫ clears)" : field.placeholder
      color: field.recording ? Color.accent : Color.menu.text
      opacity: field.recording ? 1 : 0.4
      font.family: field.fontFamily
      font.pixelSize: Style.font.caption + 1
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      visible: !field.recording && field.value.length > 0 && hover.containsMouse
      text: ""
      color: Color.menu.text
      opacity: 0.55
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Style.font.caption
      MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: { field.value = ""; field.changed("") }
      }
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      anchors.rightMargin: 22
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: field.recording ? field.stop() : field.start()
    }
  }

  Item {
    id: catcher
    focus: true
    onActiveFocusChanged: if (!activeFocus) field.stop()
    Keys.onPressed: function(event) {
      if (!field.recording) return
      event.accepted = true
      var mods = event.modifiers
      if (event.key === Qt.Key_Escape && mods === Qt.NoModifier) { field.stop(); return }
      if (event.key === Qt.Key_Backspace && mods === Qt.NoModifier) {
        field.value = ""
        field.stop()
        field.changed("")
        return
      }
      var modifierKeys = [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_AltGr]
      if (modifierKeys.indexOf(event.key) >= 0) return
      var name = field.keyName(event)
      if (!name) return
      var parts = []
      if (mods & Qt.MetaModifier) parts.push("SUPER")
      if (mods & Qt.ControlModifier) parts.push("CTRL")
      if (mods & Qt.AltModifier) parts.push("ALT")
      if (mods & Qt.ShiftModifier) parts.push("SHIFT")
      parts.push(name)
      field.value = parts.join(" + ")
      field.stop()
      field.changed(field.value)
    }
  }
}
