import QtQuick
import qs.Commons

// Single or multi-line text field. Emits committed(text) on Enter / focus loss.
Rectangle {
  id: box
  property string text: ""
  property string placeholder: ""
  property bool multiline: false
  property bool mono: false
  property string fontFamily: "SF Pro Text"
  property string monoFamily: "JetBrainsMono Nerd Font"
  readonly property alias input: loader.item
  readonly property bool editing: loader.item ? (loader.item.activeFocus || !!loader.item.editFocused) : false
  // Tab / Shift+Tab move to these (TextBox or anything with focusInput()).
  property var nextField: null
  property var prevField: null
  signal committed(string text)
  signal edited(string text)
  signal accepted()

  function focusNext(back) {
    var target = back ? box.prevField : box.nextField
    if (!target) return false
    if (target.focusInput) target.focusInput()
    else target.forceActiveFocus()
    return true
  }

  height: multiline ? 120 : 30
  radius: 7
  color: Util.alpha(Color.menu.text, 0.06)
  border.width: 1
  border.color: editing ? Util.alpha(Color.accent, 0.7) : Util.alpha(Color.menu.text, 0.1)

  function focusInput() { if (loader.item) loader.item.forceActiveFocus() }
  function insertAtCursor(t) { if (loader.item) loader.item.insertAtCursor(t) }
  function currentText() { return loader.item ? loader.item.text : box.text }

  Loader {
    id: loader
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    anchors.topMargin: box.multiline ? 8 : 0
    anchors.bottomMargin: box.multiline ? 8 : 0
    sourceComponent: box.multiline ? multiComp : singleComp
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.top: parent.top
    anchors.topMargin: box.multiline ? 8 : 0
    height: box.multiline ? implicitHeight : parent.height
    verticalAlignment: Text.AlignVCenter
    visible: loader.item && loader.item.text.length === 0
    text: box.placeholder
    color: Color.menu.text
    opacity: 0.35
    font.family: box.mono ? box.monoFamily : box.fontFamily
    font.pixelSize: Style.font.body
  }

  Component {
    id: singleComp
    TextInput {
      text: box.text
      verticalAlignment: TextInput.AlignVCenter
      color: Color.menu.text
      selectionColor: Util.alpha(Color.accent, 0.35)
      font.family: box.mono ? box.monoFamily : box.fontFamily
      font.pixelSize: Style.font.body
      clip: true
      selectByMouse: true
      onTextEdited: box.edited(text)
      onEditingFinished: box.committed(text)
      onAccepted: box.accepted()
      function insertAtCursor(t) { insert(cursorPosition, t); forceActiveFocus(); box.edited(text) }
      Keys.onTabPressed: function(e) { if (box.focusNext(false)) e.accepted = true }
      Keys.onBacktabPressed: function(e) { if (box.focusNext(true)) e.accepted = true }
    }
  }

  Component {
    id: multiComp
    Flickable {
      id: flick
      property alias text: area.text
      readonly property bool editFocused: area.activeFocus
      contentHeight: area.contentHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      function forceActiveFocus() { area.forceActiveFocus() }
      function insertAtCursor(t) { area.insert(area.cursorPosition, t); area.forceActiveFocus(); box.edited(area.text) }
      TextEdit {
        id: area
        width: flick.width
        text: box.text
        wrapMode: TextEdit.Wrap
        color: Color.menu.text
        selectionColor: Util.alpha(Color.accent, 0.35)
        font.family: box.mono ? box.monoFamily : box.fontFamily
        font.pixelSize: Style.font.body
        selectByMouse: true
        onTextChanged: if (activeFocus) box.edited(text)
        // Tab moves on, like Tinycast; Alt+Tab inserts a real tab.
        Keys.onPressed: function(e) {
          if (e.key === Qt.Key_Tab && (e.modifiers & Qt.AltModifier)) { area.insert(area.cursorPosition, "\t"); e.accepted = true }
          else if (e.key === Qt.Key_Tab && box.focusNext(false)) e.accepted = true
          else if (e.key === Qt.Key_Backtab && box.focusNext(true)) e.accepted = true
        }
        onActiveFocusChanged: if (!activeFocus) box.committed(text)
        onCursorRectangleChanged: {
          if (cursorRectangle.y < flick.contentY) flick.contentY = cursorRectangle.y
          else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
            flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height
        }
      }
    }
  }
}
