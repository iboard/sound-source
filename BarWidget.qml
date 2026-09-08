// Bar icon for io.github.iboard.sound-source.
//
//   left click   toggle the announcements on/off
//   right click  the setup dialog
//
// A plain BarIconButton, not the BarIndicator the stock toggles use. A
// BarIndicator hides itself while inactive unless the indicator area is
// hovered, which is right for a status light and wrong for a switch -- once
// off, there would be nothing left to click to turn it back on.

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "SoundSource.js" as SoundSource

BarWidget {
  id: root
  moduleName: "io.github.iboard.sound-source"

  readonly property var service: bar?.shell?.serviceFor(root.moduleName)
  readonly property bool muted: service ? service.muted === true : false

  // Read from the registry rather than kept in sync by hand, so the About
  // block cannot drift from the manifest.
  readonly property var meta: {
    var reg = bar?.shell?.pluginRegistry
    var installed = reg ? reg.installedPlugins : null
    return installed && installed[root.moduleName] ? installed[root.moduleName] : ({})
  }

  // Re-read on every settings change so the switches follow the persisted
  // list rather than their own click.
  readonly property var knownApps: service ? service.knownApps : []
  readonly property var ignoreList: service ? (service.settings.ignore || []) : []

  // Manifests in the wild set repository and homepage to the same URL; take
  // whichever is present. Shown without the scheme, which is noise in a
  // caption-sized line.
  readonly property string repoUrl: String(root.meta.repository || root.meta.homepage || "")
  readonly property string repoLabel: root.repoUrl.replace(/^https?:\/\//, "").replace(/\/$/, "")

  function isIgnored(name) {
    return SoundSource.ignoreContains(root.ignoreList, name)
  }

  property bool dialogOpen: false

  // PopupCard calls this on outside click, via `owner`.
  function close() { dialogOpen = false }

  // ignoreUnknownSignals because `service` is null while the shell is still
  // wiring plugins up, and Connections warns about the handler until the
  // target exists. It rebinds once the service arrives.
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onSetupRequested() { root.dialogOpen = true }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.centerIn: parent

    text: root.muted ? SoundSource.GLYPH_MUTED : SoundSource.GLYPH_SPEAKER
    tooltipText: (root.muted ? "Sound source popups off" : "Sound source popups on")
      + "  ·  right-click to set up"
    // Dimmed while off, matching how the stock indicators read as inactive,
    // but still drawn so it stays clickable.
    dimmed: root.muted
    active: !root.muted
    useActiveColor: false

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.dialogOpen = !root.dialogOpen
        return
      }
      if (root.service) root.service.toggleMuted()
    }
  }

  PopupCard {
    id: dialog
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.dialogOpen
    contentWidth: dialog.fittedContentWidth(Style.space(300))
    contentHeight: dialog.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      PanelSectionHeader {
        width: parent.width
        foreground: root.bar ? root.bar.foreground : Color.foreground
        text: "Announcements"
      }

      Toggle {
        width: parent.width
        label: root.muted ? "Off" : "On"
        description: "Popup naming the app that started playing"
        checked: !root.muted
        foreground: root.bar ? root.bar.foreground : Color.foreground
        onClicked: if (root.service) root.service.setMuted(!root.muted)
      }

      PanelSeparator {
        width: parent.width
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      PanelSectionHeader {
        width: parent.width
        foreground: root.bar ? root.bar.foreground : Color.foreground
        text: "Never announce"
      }

      Text {
        width: parent.width
        visible: root.knownApps.length === 0
        textFormat: Text.PlainText
        text: "Nothing seen yet. Apps show up here once they have played."
        color: root.bar ? root.bar.foreground : Color.foreground
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      // Every app the plugin has seen, each with a switch. Ticking one adds
      // its name to `ignore`; the list itself keeps ignored apps in it, so a
      // silenced app can always be brought back.
      Repeater {
        model: root.knownApps

        Item {
          required property string modelData
          width: column.width
          height: Style.spacing.controlHeight

          Text {
            anchors.left: parent.left
            anchors.right: appSwitch.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: modelData
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: root.isIgnored(modelData) ? 0.55 : 1
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
          }

          ToggleSwitch {
            id: appSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.isIgnored(modelData)
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onToggled: if (root.service) root.service.toggleIgnoredApp(modelData)
          }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      PanelSectionHeader {
        width: parent.width
        foreground: root.bar ? root.bar.foreground : Color.foreground
        text: "Popup"
      }

      Dropdown {
        width: parent.width
        label: "Position"
        options: ["top-center", "center", "top-right", "bottom-center"]
        value: root.service ? root.service.position : "top-center"
        foreground: root.bar ? root.bar.foreground : Color.foreground
        onChanged: function(option) { if (root.service) root.service.setPosition(option) }
      }

      Item {
        width: parent.width
        height: Style.spacing.controlHeight

        Text {
          id: durLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Duration"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Text {
          id: durValue
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(38)
          horizontalAlignment: Text.AlignRight
          text: (durSlider.liveValue / 1000).toFixed(1) + "s"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSlider {
          id: durSlider
          bar: root.bar
          anchors.left: durLabel.right
          anchors.right: durValue.left
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          minimum: 500
          maximum: 20000
          step: 500
          integer: true
          value: root.service ? Number(root.service.settings.duration) : 2000

          onReleased: function(v) { if (root.service) root.service.setDuration(v) }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      // About. Everything here comes out of manifest.json.
      Column {
        width: parent.width
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: (root.meta.name || "Sound Source") + "  " + (root.meta.version || "")
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.meta.description || ""
          color: root.bar ? root.bar.foreground : Color.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "by " + (root.meta.author || "andi")
            + (root.meta.license ? "  ·  " + root.meta.license : "")
          color: root.bar ? root.bar.foreground : Color.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // Repository link, also straight from the manifest. Hidden rather
        // than shown broken if a fork drops the field.
        Text {
          id: repoLink
          width: parent.width
          visible: root.repoUrl !== ""
          textFormat: Text.PlainText
          text: root.repoLabel
          color: repoMouse.containsMouse
            ? Color.accent
            : (root.bar ? root.bar.foreground : Color.foreground)
          opacity: repoMouse.containsMouse ? 1 : 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.underline: repoMouse.containsMouse
          elide: Text.ElideRight

          MouseArea {
            id: repoMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Util.execArgv, not execDetached: the URL comes out of a manifest
            // file, so it must never reach a shell as text to be re-tokenized.
            onClicked: Util.execArgv(["xdg-open", root.repoUrl])
          }
        }
      }
    }
  }
}
