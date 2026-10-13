import QtQuick
import qs.Commons

// Rounded text button. With confirmText set, the first click arms it and the
// second (within 3 s) fires.
Rectangle {
  id: b
  property string text: ""
  property string confirmText: ""
  property bool danger: false
  property bool primary: false
  property string fontFamily: "SF Pro Text"
  property bool armed: false
  signal activated()

  height: 28
  width: label.implicitWidth + 24
  radius: 7
  activeFocusOnTab: true
  Keys.onReturnPressed: b.activate()
  Keys.onEnterPressed: b.activate()
  Keys.onSpacePressed: b.activate()
  function focusInput() { b.forceActiveFocus() }
  property var nextField: null
  property var prevField: null
  Keys.onTabPressed: function(e) { if (b.nextField) { b.nextField.focusInput ? b.nextField.focusInput() : b.nextField.forceActiveFocus(); e.accepted = true } }
  Keys.onBacktabPressed: function(e) { if (b.prevField) { b.prevField.focusInput ? b.prevField.focusInput() : b.prevField.forceActiveFocus(); e.accepted = true } }
  function activate() {
    if (b.confirmText && !b.armed) { b.armed = true; disarm.restart(); return }
    b.armed = false
    b.activated()
  }
  border.width: activeFocus ? 2 : 0
  border.color: Util.alpha(Color.accent, 0.9)
  color: b.armed ? Util.alpha("#e5484d", 0.85)
    : b.primary ? (m.containsMouse ? Qt.lighter(Color.accent, 1.1) : Color.accent)
    : (m.containsMouse ? Util.alpha(Color.menu.text, 0.16) : Util.alpha(Color.menu.text, 0.09))

  Text {
    id: label
    anchors.centerIn: parent
    text: b.armed ? b.confirmText : b.text
    color: b.armed || b.primary ? "white" : (b.danger ? "#e5484d" : Color.menu.text)
    font.family: b.fontFamily
    font.pixelSize: Style.font.body
    font.weight: Font.Medium
  }

  Timer { id: disarm; interval: 3000; onTriggered: b.armed = false }

  MouseArea {
    id: m
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: b.activate()
  }
}
