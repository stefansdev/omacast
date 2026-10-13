import QtQuick
import qs.Commons

// Omacast settings, modelled on Raycast/Tinycast: a section sidebar and a
// scrolling pane of rows. Every change is written straight to
// ~/.config/omacast/config.jsonc through host.setSetting().
Item {
  id: view
  property var host: null
  property string section: "general"
  property string fontFamily: "SF Pro Text"
  property string iconFamily: "JetBrainsMono Nerd Font"
  readonly property var cfg: host ? host.config : ({})
  readonly property string filter: host ? host.query.trim().toLowerCase() : ""

  readonly property var sections: [
    { id: "general", label: "General", glyph: "\uf013" },
    { id: "search", label: "Search", glyph: "" },
    { id: "extensions", label: "Extensions", glyph: "󰏗" },
    { id: "snippets", label: "Snippets", glyph: "󰅪" },
    { id: "quicklinks", label: "Quicklinks", glyph: "󰌷" },
    { id: "commands", label: "Commands", glyph: "\uf120" },
    { id: "notes", label: "Notes", glyph: "󱞁" },
    { id: "clipboard", label: "Clipboard", glyph: "󰅌" },
    { id: "ai", label: "AI", glyph: "󰚩" },
    { id: "advanced", label: "Advanced", glyph: "󰒓" },
    { id: "about", label: "About", glyph: "\uf05a" }
  ]

  function get(path, fallback) {
    var parts = path.split(".")
    var v = view.cfg
    for (var i = 0; i < parts.length; i++) {
      if (v === undefined || v === null) return fallback
      v = v[parts[i]]
    }
    return v === undefined ? fallback : v
  }

  function set(path, value) { if (view.host) view.host.setSetting(path, value) }

  function moveSection(delta) {
    var ids = view.sections.map(function(s) { return s.id })
    var at = ids.indexOf(view.section)
    view.section = ids[Math.max(0, Math.min(ids.length - 1, at + delta))]
    pane.contentY = 0
  }

  // -------------------------------------------------------------- sidebar
  Rectangle {
    id: sidebar
    width: 190
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    color: Util.alpha(Color.menu.text, 0.025)

    Column {
      anchors.fill: parent
      anchors.margins: 8
      spacing: 2
      Repeater {
        model: view.sections
        delegate: Rectangle {
          required property var modelData
          readonly property bool on: view.section === modelData.id
          width: parent.width
          height: 32
          radius: 7
          color: on ? Util.alpha(Color.menu.text, 0.1) : (m.containsMouse ? Util.alpha(Color.menu.text, 0.05) : "transparent")
          Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
              width: 16
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.glyph
              color: parent.parent.on ? Color.accent : Color.menu.text
              opacity: parent.parent.on ? 1 : 0.6
              font.family: view.iconFamily
              font.pixelSize: Style.font.body
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: Color.menu.text
              font.family: view.fontFamily
              font.pixelSize: Style.font.subtitle
              font.weight: parent.parent.on ? Font.Medium : Font.Normal
            }
          }
          MouseArea {
            id: m
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { view.section = modelData.id; pane.contentY = 0 }
          }
        }
      }
    }

    Rectangle {
      anchors.right: parent.right
      width: 1
      height: parent.height
      color: Util.alpha(Color.menu.text, 0.07)
    }
  }

  // ----------------------------------------------------------------- pane
  Flickable {
    id: pane
    anchors.left: sidebar.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    contentHeight: body.height + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: 24
      y: 18
      width: pane.width - 48
      spacing: 0

      Text {
        text: (view.sections.filter(function(s) { return s.id === view.section })[0] || {}).label || ""
        color: Color.menu.text
        font.family: view.fontFamily
        font.pixelSize: Style.font.heading + 2
        font.weight: Font.DemiBold
        bottomPadding: 6
      }

      // ================================================================ General
      Column {
        width: parent.width
        visible: view.section === "general"

        SettingRow {
          title: "Omacast Hotkey"
          description: "Opens the launcher from anywhere."
          HotkeyField {
            value: view.get("general.hotkey", "")
            onChanged: function(v) { view.set("general.hotkey", v) }
            onRecordingChanged2: function(on) { view.host.setRecording(on) }
          }
        }
        SettingRow {
          title: "Omarchy Menu Hotkey"
          description: "The Omarchy menu moves here when Omacast takes Super+Space."
          HotkeyField {
            value: view.get("general.menuHotkey", "")
            onChanged: function(v) { view.set("general.menuHotkey", v) }
            onRecordingChanged2: function(on) { view.host.setRecording(on) }
          }
        }
        SettingRow {
          title: "Text Size"
          Segmented {
            value: view.get("general.textSize", "default")
            options: [{ value: "default", label: "Default" }, { value: "large", label: "Large" }, { value: "larger", label: "Larger" }]
            onPicked: function(v) { view.set("general.textSize", v) }
          }
        }
        SettingRow {
          title: "Window Mode"
          description: "Compact shows only the search bar until you type."
          Segmented {
            value: view.get("general.windowMode", "expanded")
            options: [{ value: "expanded", label: "Expanded" }, { value: "compact", label: "Compact" }]
            onPicked: function(v) { view.set("general.windowMode", v) }
          }
        }
        SettingRow {
          title: "Show Favorites in Compact Mode"
          Switch {
            checked: view.get("general.showFavoritesInCompact", true)
            onToggled: function(c) { view.set("general.showFavoritesInCompact", c) }
          }
        }
        SettingRow {
          title: "Show Omacast On"
          Segmented {
            value: view.get("general.showOn", "focused")
            options: [{ value: "focused", label: "Focused Monitor" }, { value: "cursor", label: "Mouse Monitor" }, { value: "primary", label: "Primary" }]
            onPicked: function(v) { view.set("general.showOn", v) }
          }
        }
        SettingRow {
          title: "Pop to Root Search"
          description: "How long Omacast keeps your last query and view after closing."
          Segmented {
            value: view.get("general.popToRoot", 0)
            options: [{ value: 0, label: "Immediately" }, { value: 30, label: "30 s" }, { value: 90, label: "90 s" }, { value: 180, label: "3 min" }, { value: -1, label: "Never" }]
            onPicked: function(v) { view.set("general.popToRoot", v) }
          }
        }
        SettingRow {
          title: "Escape Key"
          Segmented {
            value: view.get("general.escapeBehavior", "back")
            options: [{ value: "back", label: "Clear, Go Back, Then Close" }, { value: "close", label: "Close Window" }]
            onPicked: function(v) { view.set("general.escapeBehavior", v) }
          }
        }
        SettingRow {
          title: "Theme"
          description: "Omacast follows your Omarchy theme. Change it with Omarchy › Style › Theme."
        }
      }

      // ================================================================= Search
      Column {
        width: parent.width
        visible: view.section === "search"

        SettingRow {
          title: "Search Sensitivity"
          description: "Low also matches scattered letters, like “ffx” for Firefox."
          Segmented {
            value: view.get("search.sensitivity", "medium")
            options: [{ value: "high", label: "High" }, { value: "medium", label: "Medium" }, { value: "low", label: "Low" }]
            onPicked: function(v) { view.set("search.sensitivity", v) }
          }
        }
        SettingRow {
          title: "Open Windows in Results"
          Switch { checked: view.get("search.windows", true); onToggled: function(c) { view.set("search.windows", c) } }
        }
        SettingRow {
          title: "Calculator"
          description: "Math, units and currency as you type, via qalc."
          Switch { checked: view.get("search.calculator", true); onToggled: function(c) { view.set("search.calculator", c) } }
        }
        SettingRow {
          title: "Files in Results"
          Switch { checked: view.get("search.files", true); onToggled: function(c) { view.set("search.files", c) } }
        }
        SettingRow {
          title: "Start File Search After"
          Segmented {
            value: view.get("search.fileMinChars", 3)
            options: [{ value: 2, label: "2 chars" }, { value: 3, label: "3 chars" }, { value: 4, label: "4 chars" }]
            onPicked: function(v) { view.set("search.fileMinChars", v) }
          }
        }
        SettingRow {
          title: "File Search Folders"
          description: "Comma-separated. Hidden files and .gitignore'd paths are skipped."
          stacked: true
          TextBox {
            width: parent.width
            text: (view.get("files.roots", ["~"]) || []).join(", ")
            onCommitted: function(t) { view.set("files.roots", t.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })) }
          }
        }
        SettingRow {
          title: "Fallback Commands"
          description: "Shown under every search."
          stacked: true
          Column {
            width: parent.width
            spacing: 6
            Repeater {
              model: [{ id: "ai", label: "Ask AI" }, { id: "web", label: "Search the Web" }, { id: "define", label: "Define Word" }, { id: "note", label: "Create Note" }]
              delegate: Row {
                required property var modelData
                spacing: 10
                Switch {
                  checked: (view.get("search.fallbacks", []) || []).indexOf(modelData.id) >= 0
                  onToggled: function(c) {
                    var list = (view.get("search.fallbacks", []) || []).filter(function(x) { return x !== modelData.id })
                    if (c) list.push(modelData.id)
                    view.set("search.fallbacks", list)
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: Color.menu.text
                  font.family: view.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
        SettingRow {
          title: "Web Search Engine"
          Segmented {
            value: view.get("search.url", "")
            options: [
              { value: "https://www.google.com/search?q={query}", label: "Google" },
              { value: "https://duckduckgo.com/?q={query}", label: "DuckDuckGo" },
              { value: "https://kagi.com/search?q={query}", label: "Kagi" },
              { value: "https://search.brave.com/search?q={query}", label: "Brave" }
            ]
            onPicked: function(v) { view.set("search.url", v) }
          }
        }
        SettingRow {
          title: "Reset Ranking"
          description: "Forget which results you pick most."
          PillButton { text: "Reset"; danger: true; confirmText: "Click again to reset"; onActivated: view.host.resetUsage() }
        }
      }

      // ============================================================= Extensions
      Column {
        width: parent.width
        visible: view.section === "extensions"
        spacing: 0

        Text {
          width: parent.width
          text: "Give any command an alias or a hotkey, or hide it. Type in the search bar to filter."
          color: Color.menu.text
          opacity: 0.5
          wrapMode: Text.Wrap
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption + 1
          bottomPadding: 10
        }

        Row {
          width: parent.width
          height: 24
          Text { width: parent.width - 390; text: "Command"; color: Color.menu.text; opacity: 0.45; font.family: view.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
          Text { width: 110; text: "Alias"; color: Color.menu.text; opacity: 0.45; font.family: view.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
          Text { width: 220; text: "Hotkey"; color: Color.menu.text; opacity: 0.45; font.family: view.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
          Text { width: 60; text: "Enabled"; color: Color.menu.text; opacity: 0.45; font.family: view.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
        }

        Repeater {
          model: view.section === "extensions" && view.host ? view.host.extensionRows(view.filter) : []
          delegate: Item {
            required property var modelData
            readonly property var ov: view.host.overrideFor(modelData.id)
            width: body.width
            height: modelData.kind === "group" ? 34 : 40

            Text {
              visible: modelData.kind === "group"
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 6
              text: modelData.title
              color: Color.menu.text
              opacity: 0.5
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.DemiBold
            }

            Row {
              visible: modelData.kind !== "group"
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              Row {
                width: parent.width - 390
                spacing: 10
                anchors.verticalCenter: parent.verticalCenter
                Item {
                  width: 18
                  height: 18
                  anchors.verticalCenter: parent.verticalCenter
                  Image {
                    anchors.fill: parent
                    visible: !!modelData.image && status === Image.Ready
                    source: modelData.image || ""
                    sourceSize.width: 36
                    sourceSize.height: 36
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: !modelData.image
                    text: modelData.glyph || ""
                    color: Color.accent
                    font.family: modelData.glyphFont || view.iconFamily
                    font.pixelSize: Style.font.body
                  }
                }
                Text {
                  width: parent.width - 30
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.title
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: Color.menu.text
                  opacity: ov.disabled ? 0.4 : 1
                  font.family: view.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
              Item {
                width: 110
                height: 28
                TextBox {
                  width: 96
                  height: 26
                  text: ov.alias || ""
                  placeholder: "Add alias"
                  onCommitted: function(t) { view.host.setOverride(modelData.id, "alias", t.trim()) }
                }
              }
              Item {
                width: 220
                height: 28
                HotkeyField {
                  width: 206
                  height: 26
                  value: ov.hotkey || ""
                  placeholder: "Record hotkey"
                  onChanged: function(v) { view.host.setOverride(modelData.id, "hotkey", v) }
                  onRecordingChanged2: function(on) { view.host.setRecording(on) }
                }
              }
              Item {
                width: 60
                height: 28
                Switch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: !ov.disabled
                  onToggled: function(c) { view.host.setOverride(modelData.id, "disabled", !c) }
                }
              }
            }
          }
        }
      }

      // =============================================================== Snippets
      Column {
        width: parent.width
        visible: view.section === "snippets"

        SettingRow {
          title: "Snippets"
          description: (view.host ? view.host.snippets.length : 0) + " snippets. Tab to Snippets in the launcher to search, paste, edit and create them."
          PillButton { text: "Open Snippets"; onActivated: view.host.setMode("snippets") }
        }
        SettingRow {
          title: "Expand Keywords as You Type"
          description: "Typing a snippet's keyword in any app replaces it with the snippet, like Raycast. Uses a Hyprland key hook with a US key map; typed keys stay in memory only."
          Switch { checked: view.get("snippetSettings.expansion", true); onToggled: function(c) { view.set("snippetSettings.expansion", c) } }
        }
        SettingRow {
          title: "Expand Within Words"
          description: "Off: a keyword only expands at the start of a word."
          Switch { checked: view.get("snippetSettings.withinWords", false); onToggled: function(c) { view.set("snippetSettings.withinWords", c) } }
        }
        SettingRow {
          title: "Disabled Apps"
          description: "Window classes where keywords never expand (comma-separated, partial match)."
          stacked: true
          TextBox {
            width: parent.width
            text: (view.get("snippetSettings.exclude", []) || []).join(", ")
            onCommitted: function(t) { view.set("snippetSettings.exclude", t.split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })) }
          }
        }
        SettingRow {
          title: "Primary Action"
          Segmented {
            value: view.get("snippetSettings.primaryAction", "paste")
            options: [{ value: "paste", label: "Paste" }, { value: "copy", label: "Copy" }]
            onPicked: function(v) { view.set("snippetSettings.primaryAction", v) }
          }
        }
        SettingRow {
          title: "Placeholders"
          stacked: true
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            color: Color.menu.text
            opacity: 0.7
            font.family: view.fontFamily
            font.pixelSize: Style.font.body
            text: "`{clipboard}` `{date}` `{time}` `{datetime}` `{day}` `{uuid}` `{user}` `{cursor}`  \n" +
              "`{date format=\"EEE d MMM\" offset=\"+1d\"}` · `{argument name=\"To\" default=\"team\"}` · " +
              "`{argument name=\"Tone\" options=\"formal, casual\"}` · `{snippet name=\"sig\"}`  \n" +
              "Modifiers: `{clipboard | trim | uppercase}` (uppercase, lowercase, trim, percent-encode, json-stringify)"
          }
        }
      }

      // ============================================================= Quicklinks
      ListEditor {
        width: parent.width
        visible: view.section === "quicklinks"
        host: view.host
        settingKey: "quicklinks"
        intro: "Type a quicklink's keyword followed by text, e.g. “gh quickshell”. {query} in the URL is replaced with that text."
        fields: [
          { key: "name", label: "Name", placeholder: "Search GitHub" },
          { key: "keyword", label: "Keyword", placeholder: "gh", width: 90 },
          { key: "url", label: "URL", placeholder: "https://github.com/search?q={query}", wide: true },
          { key: "icon", label: "Icon", placeholder: "Nerd Font glyph", width: 90 }
        ]
        titleKey: "name"
        subtitleKey: "url"
        badgeKey: "keyword"
        blank: ({ name: "", keyword: "", url: "https://", icon: "" })
      }

      // =============================================================== Commands
      ListEditor {
        width: parent.width
        visible: view.section === "commands"
        host: view.host
        settingKey: "commands"
        intro: "Your own shell commands, searchable from the launcher. Give them hotkeys in Extensions."
        fields: [
          { key: "name", label: "Name", placeholder: "Restart Waybar" },
          { key: "command", label: "Command", placeholder: "omarchy restart shell", wide: true, mono: true },
          { key: "icon", label: "Icon", placeholder: "Nerd Font glyph", width: 90 },
          { key: "terminal", label: "Run in terminal", toggle: true }
        ]
        titleKey: "name"
        subtitleKey: "command"
        blank: ({ name: "", command: "", icon: "", terminal: false })
      }

      // ================================================================== Notes
      Column {
        width: parent.width
        visible: view.section === "notes"

        SettingRow {
          title: "Notes Hotkey"
          description: "Shows or hides the floating notes window."
          HotkeyField {
            value: view.get("notes.hotkey", "")
            onChanged: function(v) { view.set("notes.hotkey", v) }
            onRecordingChanged2: function(on) { view.host.setRecording(on) }
          }
        }
        SettingRow {
          title: "Notes Folder"
          description: "Notes are plain Markdown files; the first line is the title."
          stacked: true
          TextBox {
            width: parent.width
            text: view.get("notes.dir", "~/notes")
            onCommitted: function(t) { if (t.trim()) view.set("notes.dir", t.trim()) }
          }
        }
        SettingRow {
          title: "Text Size"
          Segmented {
            value: view.get("notes.textSize", 15)
            options: [{ value: 13, label: "Small" }, { value: 15, label: "Default" }, { value: 17, label: "Large" }, { value: 19, label: "Larger" }]
            onPicked: function(v) { view.set("notes.textSize", v) }
          }
        }
        SettingRow {
          title: "Formatting Bar"
          Switch { checked: view.get("notes.formatBar", true); onToggled: function(c) { view.set("notes.formatBar", c) } }
        }
        SettingRow {
          title: "Escape Closes Notes"
          Switch { checked: view.get("notes.escapeCloses", true); onToggled: function(c) { view.set("notes.escapeCloses", c) } }
        }
        SettingRow {
          title: "Open Notes"
          PillButton { text: "Show Notes"; onActivated: { view.host.close(); view.host.toggleNotes() } }
        }
      }

      // ============================================================== Clipboard
      Column {
        width: parent.width
        visible: view.section === "clipboard"
        SettingRow {
          title: "Primary Action"
          description: "What Enter does in Clipboard History."
          Segmented {
            value: view.get("clipboard.primaryAction", "paste")
            options: [{ value: "paste", label: "Paste" }, { value: "copy", label: "Copy" }]
            onPicked: function(v) { view.set("clipboard.primaryAction", v) }
          }
        }
        SettingRow {
          title: "History"
          description: "Omacast shows Omarchy's clipboard history. Clear it from the Omarchy clipboard (Super+Ctrl+V)."
        }
      }

      // ===================================================================== AI
      Column {
        width: parent.width
        visible: view.section === "ai"
        SettingRow {
          title: "Quick AI"
          description: "Uses the Claude Code CLI with your existing login."
          Switch { checked: view.get("ai.enabled", true); onToggled: function(c) { view.set("ai.enabled", c) } }
        }
        SettingRow {
          title: "Model"
          Segmented {
            value: view.get("ai.model", "haiku")
            options: [{ value: "haiku", label: "Haiku" }, { value: "sonnet", label: "Sonnet" }, { value: "opus", label: "Opus" }]
            onPicked: function(v) { view.set("ai.model", v) }
          }
        }
        SettingRow {
          title: "Custom Instructions"
          description: "Added to every Quick AI question."
          stacked: true
          TextBox {
            width: parent.width
            multiline: true
            text: view.get("ai.instructions", "")
            placeholder: "e.g. Answer in British English. Prefer shell one-liners."
            onCommitted: function(t) { view.set("ai.instructions", t) }
          }
        }
      }

      // =============================================================== Advanced
      Column {
        width: parent.width
        visible: view.section === "advanced"
        SettingRow {
          title: "Configuration File"
          description: "~/.config/omacast/config.jsonc — edits apply live."
          PillButton { text: "Open"; onActivated: view.host.editFile(view.host.configPath) }
        }
        SettingRow {
          title: "Export Settings"
          description: "Saves settings and snippets to ~/omacast-backup-<date>.json."
          PillButton { text: "Export"; onActivated: view.host.exportBackup() }
        }
        SettingRow {
          title: "Import Settings"
          description: "Restores the newest ~/omacast-backup-*.json."
          PillButton { text: "Import"; confirmText: "Click again to import"; onActivated: view.host.importBackup() }
        }
        SettingRow {
          title: "Reapply Hotkeys"
          description: "Rewrites ~/.config/omacast/hyprland.lua and reloads Hyprland."
          PillButton { text: "Reapply"; onActivated: view.host.applyHyprland(true) }
        }
        SettingRow {
          title: "Reset All Settings"
          description: "Snippets and notes are kept."
          PillButton { text: "Reset"; danger: true; confirmText: "Click again to reset"; onActivated: view.host.resetSettings() }
        }
      }

      // ================================================================== About
      Column {
        width: parent.width
        visible: view.section === "about"
        spacing: 8
        topPadding: 6
        Text {
          text: "Omacast " + (view.host ? view.host.version : "")
          color: Color.menu.text
          font.family: view.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.Medium
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "A Raycast-style launcher for Omarchy, inspired by Raycast and Tinycast."
          color: Color.menu.text
          opacity: 0.6
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
        }
        PillButton { text: "GitHub"; onActivated: view.host.openUrl("https://github.com/stefansdev/omacast") }
      }
    }
  }
}
