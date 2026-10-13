import QtQuick
import qs.Commons

// Editable list of objects stored at config[settingKey] (quicklinks, commands).
Column {
  id: le
  property var host: null
  property string settingKey: ""
  property string intro: ""
  property var fields: []
  property string titleKey: "name"
  property string subtitleKey: ""
  property string badgeKey: ""
  property var blank: ({})
  property string fontFamily: "SF Pro Text"
  property int editing: -1
  property var draft: ({})

  readonly property var items: le.host && le.host.config[le.settingKey] ? le.host.config[le.settingKey] : []

  function startEdit(index) {
    le.editing = index
    var src = index >= 0 ? le.items[index] : le.blank
    var copy = {}
    for (var k in src) copy[k] = src[k]
    le.draft = copy
  }

  function save() {
    var list = le.items.slice()
    if (!String(le.draft[le.titleKey] || "").trim()) return
    if (le.editing >= 0) list[le.editing] = le.draft
    else list.push(le.draft)
    le.host.setSetting(le.settingKey, list)
    le.editing = -2
  }

  function remove(index) {
    var list = le.items.slice()
    list.splice(index, 1)
    le.host.setSetting(le.settingKey, list)
    le.editing = -2
  }

  spacing: 0

  Row {
    width: parent.width
    height: 40
    Text {
      width: parent.width - addBtn.width
      anchors.verticalCenter: parent.verticalCenter
      text: le.intro
      wrapMode: Text.Wrap
      color: Color.menu.text
      opacity: 0.5
      font.family: le.fontFamily
      font.pixelSize: Style.font.caption + 1
    }
    PillButton { id: addBtn; anchors.verticalCenter: parent.verticalCenter; text: "+ Add"; primary: true; onActivated: le.startEdit(-1) }
  }

  Repeater {
    model: le.items.length + 1
    delegate: Column {
      required property int index
      readonly property bool isNew: index === le.items.length
      readonly property var item: isNew ? null : le.items[index]
      readonly property bool open: isNew ? le.editing === -1 : le.editing === index
      width: le.width
      visible: !isNew || open

      Item {
        visible: !parent.isNew
        width: parent.width
        height: 44
        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          width: parent.width - actions.width - 10
          Text {
            width: 20
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: item && item.icon ? item.icon : ""
            color: Color.accent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.body
          }
          Column {
            width: parent.width - 30
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Row {
              spacing: 8
              Text {
                text: item ? String(item[le.titleKey] || "") : ""
                textFormat: Text.PlainText
                color: Color.menu.text
                font.family: le.fontFamily
                font.pixelSize: Style.font.subtitle
                font.weight: Font.Medium
              }
              Rectangle {
                visible: le.badgeKey && item && item[le.badgeKey]
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                width: badge.implicitWidth + 10
                radius: 4
                color: Util.alpha(Color.menu.text, 0.1)
                Text { id: badge; anchors.centerIn: parent; text: item && le.badgeKey ? String(item[le.badgeKey] || "") : ""; color: Color.menu.text; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption }
              }
            }
            Text {
              width: parent.width
              text: item && le.subtitleKey ? String(item[le.subtitleKey] || "") : ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Color.menu.text
              opacity: 0.45
              font.family: le.fontFamily
              font.pixelSize: Style.font.caption + 1
            }
          }
        }
        Row {
          id: actions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          PillButton { text: "Edit"; onActivated: le.startEdit(index) }
          PillButton { text: "Delete"; danger: true; confirmText: "Sure?"; onActivated: le.remove(index) }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Util.alpha(Color.menu.text, 0.06) }
      }

      // Inline form
      Rectangle {
        visible: parent.open
        width: parent.width
        height: visible ? form.height + 24 : 0
        radius: 10
        color: Util.alpha(Color.menu.text, 0.04)
        border.width: 1
        border.color: Util.alpha(Color.menu.text, 0.08)

        Column {
          id: form
          x: 12
          y: 12
          width: parent.width - 24
          spacing: 10
          Repeater {
            model: parent.parent.visible ? le.fields : []
            delegate: Row {
              required property var modelData
              width: form.width
              spacing: 12
              Text {
                width: 110
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: Color.menu.text
                opacity: 0.7
                font.family: le.fontFamily
                font.pixelSize: Style.font.body
              }
              TextBox {
                visible: !modelData.toggle
                width: modelData.width ? modelData.width : form.width - 122
                text: String(le.draft[modelData.key] || "")
                placeholder: modelData.placeholder || ""
                mono: !!modelData.mono
                onEdited: function(t) { var d = le.draft; d[modelData.key] = t; le.draft = d }
                onCommitted: function(t) { var d = le.draft; d[modelData.key] = t; le.draft = d }
                onAccepted: le.save()
              }
              Switch {
                visible: !!modelData.toggle
                anchors.verticalCenter: parent.verticalCenter
                checked: !!le.draft[modelData.key]
                onToggled: function(c) { var d = le.draft; d[modelData.key] = c; le.draft = d }
              }
            }
          }
          Row {
            spacing: 8
            anchors.right: parent.right
            PillButton { text: "Cancel"; onActivated: le.editing = -2 }
            PillButton { text: "Save"; primary: true; onActivated: le.save() }
          }
        }
      }
    }
  }
}
