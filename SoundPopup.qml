// The popup card for andi.sound-source.
//
// A `panel` entry point rather than a window inside Service.qml: services are
// created into the shell's non-visual host (`Item { visible: false }`), and a
// Window nested under an invisible Item inherits that invisibility, so a
// window declared there maps but never shows. Panels are mounted by the
// shell's own Loader, which is where omarchy.osd draws from.
//
// It deliberately does not reuse omarchy.osd. That OSD is shared with volume,
// brightness and media and is anchored bottom-centre, so repositioning this
// popup by moving the OSD would move all of them. The styling here comes from
// the same tokens and border spec, so it still reads as one shell.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "SoundSource.js" as SoundSource

Item {
  id: root

  // Injected by the shell's panel Loader.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string message: ""
  property string glyph: ""
  property int duration: 2000
  property string position: "center"

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      message = String(p.message || "")
      glyph = String(p.glyph || "")
      var d = Number(p.duration)
      duration = isFinite(d) && d >= 0 ? d : 2000
      position = SoundSource.normalizePosition(p.position)
      opened = true
      if (duration > 0) hideTimer.restart()
      else hideTimer.stop()
    } catch (e) {
      console.warn("andi.sound-source: bad popup payload:", e)
    }
  }

  function close() {
    opened = false
    hideTimer.stop()
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  // Clear the bar so the card lands just below it at the right-hand end --
  // under the audio icon rather than on top of it. Measured off the live bar
  // so a hidden or repositioned bar still lines up.
  readonly property string barPosition: shell && shell.barConfig
    ? String(shell.barConfig.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int defaultBarSize: barVertical
    ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int liveBarSize: shell && shell.bar && !shell.bar.barHidden
    ? Math.max(0, shell.bar.barSize) : defaultBarSize
  readonly property int topMargin: (barPosition === "top" ? liveBarSize : 0) + Style.gapsOut
  readonly property int rightMargin: (barPosition === "right" ? liveBarSize : 0) + Style.gapsOut
  readonly property int bottomMargin: (barPosition === "bottom" ? liveBarSize : 0) + Style.space(67)

  readonly property int pad: Style.space(14)
  readonly property int gap: Style.space(10)
  readonly property int maxTextWidth: Style.space(320)

  // Nerd Font glyphs draw well outside their monospace cell, so the glyph
  // column is measured by ink rather than by advance width.
  TextMetrics {
    id: glyphMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    text: root.glyph
  }

  TextMetrics {
    id: textMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
  }

  readonly property int glyphInk: Math.ceil(glyphMetrics.tightBoundingRect.width)
  readonly property int textWidth: Math.min(Math.ceil(textMetrics.advanceWidth), maxTextWidth)

  // One surface per monitor. The shell's OSD maps a single PanelWindow and so
  // lands on whichever screen Quickshell picks first -- fine for a volume
  // readout you already know you asked for, wrong for a popup whose whole job
  // is to be noticed on the screen you happen to be looking at.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: panel.modelData
      visible: root.opened
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "andi-sound-source"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Visual only. An empty input region matters more here than it does for
      // the OSD: `duration` can put this card on screen for many seconds, and
      // it must never swallow a click meant for the window underneath.
      mask: Region {}

      BorderSurface {
        id: card

        // Placed with x/y rather than anchors: an anchor left over from a
        // previous position would fight the new one, and QML resolves that by
        // warning and ignoring rather than by moving the card.
        x: root.position === "top-right"
          ? parent.width - card.width - root.rightMargin
          : Math.round((parent.width - card.width) / 2)
        y: {
          if (root.position === "center") return Math.round((parent.height - card.height) / 2)
          if (root.position === "bottom-center") return parent.height - card.height - root.bottomMargin
          return root.topMargin
        }

        width: card.borderLeft + root.pad + root.glyphInk
          + root.gap + root.textWidth + root.pad + card.borderRight
        height: card.borderTop + root.pad + Style.font.displayLarge
          + root.pad + card.borderBottom

        color: Util.alpha(Color.background, 0.97)
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border,
          Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        Row {
          anchors.fill: parent
          anchors.topMargin: card.borderTop + root.pad
          anchors.rightMargin: card.borderRight + root.pad
          anchors.bottomMargin: card.borderBottom + root.pad
          anchors.leftMargin: card.borderLeft + root.pad
          spacing: root.gap

          Item {
            width: root.glyphInk
            height: parent.height

            Text {
              textFormat: Text.PlainText
              x: -glyphMetrics.tightBoundingRect.x
              anchors.verticalCenter: parent.verticalCenter
              text: root.glyph
              font: glyphMetrics.font
              color: Color.popups.text
            }
          }

          Text {
            textFormat: Text.PlainText
            width: root.textWidth
            anchors.verticalCenter: parent.verticalCenter
            text: root.message
            font: textMetrics.font
            color: Color.popups.text
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }
    }
  }
}
