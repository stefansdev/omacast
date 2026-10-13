import QtQuick
import qs.Commons

// Segmented picker: options = [{ value, label }]
Rectangle {
  id: seg
  property var options: []
  property var value: ""
  property string fontFamily: "SF Pro Text"
  signal picked(var value)
  height: 28
  width: row.implicitWidth + 4
  radius: 7
  color: Util.alpha(Color.menu.text, 0.07)

  Row {
    id: row
    x: 2
    y: 2
    spacing: 2
    Repeater {
      model: seg.options
      delegate: Rectangle {
        required property var modelData
        readonly property bool on: String(seg.value) === String(modelData.value)
        height: 24
        width: label.implicitWidth + 22
        radius: 5
        color: on ? Util.alpha(Color.menu.text, 0.16) : (m.containsMouse ? Util.alpha(Color.menu.text, 0.06) : "transparent")
        Text {
          id: label
          anchors.centerIn: parent
          text: modelData.label
          color: Color.menu.text
          opacity: parent.on ? 1 : 0.6
          font.family: seg.fontFamily
          font.pixelSize: Style.font.body
          font.weight: parent.on ? Font.Medium : Font.Normal
        }
        MouseArea {
          id: m
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { seg.value = modelData.value; seg.picked(modelData.value) }
        }
      }
    }
  }
}
