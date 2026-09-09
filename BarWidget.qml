// Bar icon for io.github.iboard.sound-source.
//
//   left click   toggle the announcements on/off
//   right click  the setup dialog
//
// The icon sits with the stock hide-when-inactive indicators: while
// announcements are off it is concealed and its slot collapses, and it comes
// back -- dimmed and clickable -- on the same hover that reveals the rest of
// them.
//
// It cannot be listed in `omarchy.indicators`' own `items`: that widget
// resolves each entry to a file in the shell's packaged `indicators/`
// directory, so a plugin id there loads nothing. Borrowing that widget's
// reveal state is how a plugin joins the group from its own bar slot.

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

  // Read from the manifest rather than kept in sync by hand, so the About
  // block cannot drift from it.
  //
  // The shell injects the full manifest into every plugin declaring kind
  // "service", which is the only route a bar widget has to it: the widget's
  // `shell` is a capability-scoped PluginShellApi with no pluginRegistry. The
  // registry lookup stays as a fallback for a host that does expose one.
  readonly property var meta: {
    var fromService = root.service ? root.service.manifest : null
    if (fromService) return fromService
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

  // The marketplace listing is addressed by plugin id, so this follows a fork
  // to its own listing rather than pointing back here. moduleName is that id.
  readonly property string marketplaceUrl:
    "https://omarchyplugins.com/plugin.html?id=" + root.moduleName
  readonly property string marketplaceLabel: "omarchyplugins.com"

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

  // The live omarchy.indicators widget on this bar, whose
  // `revealInactiveIndicators` decides when inactive icons are shown. Read
  // out of the host's slot list rather than held, so it rebinds when the bar
  // is rebuilt; null when the bar carries no indicators widget.
  readonly property var indicatorsHost: {
    var slots = bar ? bar.moduleSlots : null
    if (!slots) return null
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (slot && slot.moduleName === "omarchy.indicators" && slot.activeItem
          && "revealInactiveIndicators" in slot.activeItem) return slot.activeItem
    }
    return null
  }

  readonly property bool indicatorsRevealed: !!indicatorsHost && indicatorsHost.revealInactiveIndicators === true

  // Concealed only while a reveal is actually reachable. With no indicators
  // widget on the bar there is no hover that would bring the icon back, and a
  // switch nothing can click on is a switch stuck off -- so there it keeps the
  // old behaviour and merely dims. An open dialog holds the icon out too: the
  // card anchors to this slot, and collapsing the slot under it would drag the
  // card sideways.
  readonly property bool iconConcealed: root.muted && !!indicatorsHost
    && !root.indicatorsRevealed && !root.dialogOpen

  implicitWidth: iconArea.implicitWidth
  implicitHeight: iconArea.implicitHeight

  // Collapses along the bar while concealed, the way the indicators' own
  // inactive block does, so the bar closes the gap instead of holding an empty
  // slot. Clipped, because the icon keeps painting -- it fades rather than
  // vanishing -- inside an area that is by then zero-sized.
  Item {
    id: iconArea
    anchors.centerIn: parent

    implicitWidth: root.vertical ? button.implicitWidth : (root.iconConcealed ? 0 : button.implicitWidth)
    implicitHeight: root.vertical ? (root.iconConcealed ? 0 : button.implicitHeight) : button.implicitHeight
    width: implicitWidth
    height: implicitHeight
    clip: true

    BarIconButton {
      id: button
      anchors.centerIn: parent

      text: root.muted ? SoundSource.GLYPH_MUTED : SoundSource.GLYPH_SPEAKER
      tooltipText: (root.muted ? "Sound source popups off" : "Sound source popups on")
        + "  ·  right-click to set up"
      // Dimmed while off and revealed, gone while off and not: the same two
      // states the stock indicators show. WidgetButton turns `concealed` into
      // opacity 0 with the same fade it uses for them.
      dimmed: root.muted
      concealed: root.iconConcealed
      interactive: !root.iconConcealed
      active: !root.muted
      useActiveColor: false
      // Hovering the icon holds the whole group revealed, so it cannot slide
      // out from under the pointer on the way to a click.
      maintainIndicatorReveal: true
      revealHost: root.indicatorsHost

      onPressed: function(mouseButton) {
        if (mouseButton === Qt.RightButton) {
          root.dialogOpen = !root.dialogOpen
          return
        }
        if (root.service) root.service.toggleMuted()
      }
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
          text: "by " + (root.meta.author || "iboard")
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

        // Marketplace listing. Always shown: the URL is built from the plugin
        // id, which every manifest has, rather than an optional field.
        Text {
          id: marketplaceLink
          width: parent.width
          textFormat: Text.PlainText
          text: root.marketplaceLabel
          color: marketplaceMouse.containsMouse
            ? Color.accent
            : (root.bar ? root.bar.foreground : Color.foreground)
          opacity: marketplaceMouse.containsMouse ? 1 : 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.underline: marketplaceMouse.containsMouse
          elide: Text.ElideRight

          MouseArea {
            id: marketplaceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Util.execArgv(["xdg-open", root.marketplaceUrl])
          }
        }
      }
    }
  }
}
