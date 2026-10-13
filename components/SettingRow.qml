import QtQuick
import qs.Commons

// One settings row: title + optional description on the left, control on the right.
Item {
  id: row
  property string title: ""
  property string description: ""
  property string fontFamily: "SF Pro Text"
  property bool stacked: false        // control below the text (wide controls)
  default property alias content: slot.data

  width: parent ? parent.width : 400
  height: stacked ? textCol.height + slot.childrenRect.height + 22 : Math.max(textCol.height, slot.childrenRect.height) + 20

  Column {
    id: textCol
    anchors.left: parent.left
    anchors.right: row.stacked ? parent.right : slot.left
    anchors.rightMargin: row.stacked ? 0 : 16
    y: row.stacked ? 10 : (row.height - height) / 2
    spacing: 3
    Text {
      width: parent.width
      text: row.title
      color: Color.menu.text
      font.family: row.fontFamily
      font.pixelSize: Style.font.subtitle
      font.weight: Font.Medium
      wrapMode: Text.Wrap
    }
    Text {
      width: parent.width
      visible: row.description.length > 0
      text: row.description
      color: Color.menu.text
      opacity: 0.5
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption + 1
      wrapMode: Text.Wrap
    }
  }

  Item {
    id: slot
    anchors.right: parent.right
    width: row.stacked ? parent.width : childrenRect.width
    height: childrenRect.height
    y: row.stacked ? textCol.height + 16 : (row.height - height) / 2
  }

  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: Util.alpha(Color.menu.text, 0.06)
  }
}
