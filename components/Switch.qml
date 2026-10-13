import QtQuick
import qs.Commons

// Pill switch.
Rectangle {
  id: sw
  property bool checked: false
  signal toggled(bool checked)
  width: 36
  height: 20
  radius: 10
  color: checked ? Color.accent : Util.alpha(Color.menu.text, 0.18)
  Behavior on color { ColorAnimation { duration: 120 } }

  Rectangle {
    width: 16
    height: 16
    radius: 8
    y: 2
    x: sw.checked ? sw.width - width - 2 : 2
    color: "white"
    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: { sw.checked = !sw.checked; sw.toggled(sw.checked) }
  }
}
