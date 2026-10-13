import QtQuick
import qs.Commons

// Small Nerd Font icon button used in the notes window and settings.
Rectangle {
  id: btn
  property string glyph: ""
  property string tip: ""
  property bool active: false
  property bool small: false
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property string iconFamily: "JetBrainsMono Nerd Font"
  signal clicked()

  width: small ? 28 : 30
  height: small ? 26 : 28
  radius: 6
  opacity: enabled ? 1 : 0.35
  color: active ? Util.alpha(accent, 0.2) : (mouse.containsMouse ? Util.alpha(foreground, 0.1) : "transparent")

  Text {
    anchors.centerIn: parent
    text: btn.glyph
    color: btn.active ? btn.accent : btn.foreground
    opacity: btn.active ? 1 : 0.75
    font.family: btn.iconFamily
    font.pixelSize: btn.small ? 12 : 13
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (btn.enabled) btn.clicked()
  }
}
