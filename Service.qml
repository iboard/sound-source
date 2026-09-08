// Announce which application just started playing audio.
//
// The watching half of the plugin: it follows PipeWire for playback streams
// appearing, decides whether one is worth announcing, and summons the popup.
// SoundPopup.qml draws that popup; BarWidget.qml is the bar icon and the
// setup dialog.
//
// The mechanism is deliberately "a new stream appeared" rather than "this
// stream got loud". A discrete sound -- a notification ping, a chat alert, a
// system sound -- is played by opening a fresh playback stream, playing, and
// closing it, so a new node in the graph is exactly the event worth
// announcing. Watching levels instead would need a peak monitor running on
// every stream forever to catch the same thing. See README for the case this
// does not cover.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "SoundSource.js" as SoundSource

Item {
  id: root

  // Injected by shell.qml for every plugin declaring kind "service".
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "andi.sound-source"

  readonly property var defaultSettings: ({
    "duration": 2000,        // how long the popup stays, ms
    "repeatMs": 1500,        // ignore the same app again within this window
    "showRole": false,       // append PipeWire's media.role (Music, Notification, ...)
    "startupGraceMs": 2500,  // streams already playing at load are not announced
    "position": "top-center", // center | top-center | top-right | bottom-center
    "muted": false,          // toggled from the bar icon; survives restarts
    "ignore": [],            // app names that must not raise a popup
    "labels": ({})           // { "raw name": "Nicer name" }
  })

  readonly property var settings: SoundSource.settingsFrom(
    shell ? shell.shellConfig : null, pluginId, defaultSettings)

  readonly property var effectiveLabels: SoundSource.mergedLabels(settings.labels)

  // Read back out of shell.json, so the bar icon reflects the persisted state
  // rather than a copy of it.
  readonly property bool muted: settings.muted === true
  readonly property string position: SoundSource.normalizePosition(settings.position)

  // Every app the plugin has seen play since it loaded. The setup dialog
  // needs more than what is playing right now: an app you want silenced is
  // usually not making a noise at the moment you go looking for it.
  //
  // Mutated in place with a revision counter rather than rebuilt, so a stream
  // appearing does not churn a new object for a map nothing binds to directly.
  property var seenLabels: ({})
  property int seenRevision: 0

  function rememberLabel(label) {
    if (!label || seenLabels[label]) return
    seenLabels[label] = true
    seenRevision++
  }

  // What the dialog lists: playing now, seen earlier, plus anything already on
  // the ignore list so an entry can always be taken back off.
  readonly property var knownApps: {
    var rev = seenRevision   // establishes the dependency; value unused
    var out = []
    var seen = {}

    function push(value) {
      var name = String(value || "").trim()
      if (!name) return
      var key = name.toLowerCase()
      if (seen[key]) return
      seen[key] = true
      out.push(name)
    }

    var active = SoundSource.activeLabels(streams, effectiveLabels)
    for (var i = 0; i < active.length; i++) push(active[i])
    for (var label in seenLabels) push(label)

    var ignored = settings.ignore || []
    for (var j = 0; j < ignored.length; j++) push(ignored[j])

    out.sort(function(a, b) {
      var x = a.toLowerCase(), y = b.toLowerCase()
      return x < y ? -1 : (x > y ? 1 : 0)
    })
    return out
  }

  // Lets the setup dialog be opened without the mouse -- a keybinding, or the
  // Omarchy menu. Each bar instance listens and opens its own popup, which is
  // anchored to that monitor's bar.
  signal setupRequested()

  function isIgnoredApp(label) {
    return SoundSource.ignoreContains(settings.ignore, label)
  }

  function toggleIgnoredApp(label) {
    var want = !isIgnoredApp(label)
    setOption("ignore", SoundSource.withIgnored(settings.ignore, label, want))
    return want ? "ignored" : "announced"
  }

  // Only the keys actually written in shell.json, without the defaults merged
  // in. updateEntryInline replaces the entry with exactly what it is handed,
  // so persisting the merged settings would bake every default into the file.
  readonly property var rawSettings: SoundSource.entrySettings(
    shell ? shell.shellConfig : null, pluginId)

  // One writer for every persisted option: merge onto the keys already in
  // shell.json and hand that to updateEntryInline, which writes to whichever
  // entry holds this plugin -- bar layout while the icon is on the bar,
  // plugins[] otherwise.
  function setOption(key, value) {
    if (!shell) return

    var next = {}
    for (var k in rawSettings) next[k] = rawSettings[k]
    next[String(key)] = value
    shell.updateEntryInline(pluginId, next)
  }

  function setMuted(value) { setOption("muted", !!value) }
  function setPosition(value) { setOption("position", SoundSource.normalizePosition(value)) }

  function setDuration(value) {
    var v = Number(value)
    setOption("duration", isFinite(v) ? Math.max(0, Math.round(v)) : 2000)
  }

  // `muted` is a binding on shellConfig and only updates once the write has
  // been persisted and reloaded, so the caller is told the value we asked for
  // rather than the one still in effect.
  function toggleMuted() {
    var want = !muted
    setMuted(want)
    return want ? "muted" : "unmuted"
  }

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  readonly property var liveStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && SoundSource.isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }

  // PipeWire can remove a node while Quickshell is still dispatching the
  // removal signal, and rebuilding off the live list from inside that signal
  // has crashed the shell's PipeWire service before (see the note in the
  // first-party audio panel). Everything downstream reads this settled
  // snapshot instead, so each graph mutation lands before it is inspected.
  property var streams: []

  // Node ids already accounted for. Keyed by id so it survives a snapshot
  // being rebuilt -- the announcement must fire once per stream, not once per
  // time the list happens to be recomputed.
  property var seenIds: ({})

  // Announcement times keyed by label, so one app opening three streams at
  // once (browsers do) produces one popup.
  property var lastAnnouncedAt: ({})

  property string lastLabel: ""
  property bool primed: false
  property int drainAttempts: 0

  // seenIds and lastAnnouncedAt are bookkeeping that nothing binds to, so
  // they are mutated in place; rebuilding either on every stream change would
  // churn objects for no observer. knownApps does have observers, which is
  // why seenLabels carries a revision counter instead.

  onLiveStreamsChanged: settleTimer.restart()

  Timer {
    id: settleTimer
    interval: 120
    onTriggered: root.resnapshot()
  }

  // Streams appear in the graph before they are bound, and properties cannot
  // be read until then, so an unbound stream is retried rather than dropped.
  Timer {
    id: drainTimer
    interval: 80
    repeat: true
    onTriggered: root.drain()
  }

  Timer {
    id: primeTimer
    interval: Math.max(0, Number(root.settings.startupGraceMs))
    running: true
    onTriggered: root.primed = true
  }

  function resnapshot() {
    streams = liveStreams.slice()

    // A stream that went away should announce again if it comes back, so its
    // id is dropped once it is no longer in the graph.
    var present = {}
    for (var i = 0; i < streams.length; i++) {
      if (streams[i]) present[String(streams[i].id)] = true
    }
    for (var key in seenIds) {
      if (!present[key]) delete seenIds[key]
    }

    drainAttempts = 0
    drainTimer.restart()
    drain()
  }

  function drain() {
    drainAttempts++

    var unbound = 0
    for (var i = 0; i < streams.length; i++) {
      var n = streams[i]
      if (!n || seenIds[String(n.id)]) continue
      if (n.ready === true) noteStream(n)
      else unbound++
    }

    // Give up on a stream that never binds instead of polling forever; a
    // short-lived sound can be gone before it is ever readable.
    if (unbound === 0 || drainAttempts > 40) drainTimer.stop()
  }

  function noteStream(node) {
    seenIds[String(node.id)] = true

    var props = SoundSource.propsOf(node)
    if (SoundSource.isPlumbing(node, props)) return

    var label = SoundSource.friendlyLabel(SoundSource.rawLabel(node, props), effectiveLabels)
    if (!label) return

    // Recorded before the grace and ignore checks: an app the plugin stays
    // quiet about still belongs in the dialog's list.
    rememberLabel(label)

    if (!primed) return
    if (SoundSource.isIgnored(node, props, settings.ignore)) return

    announce(label, props)
  }

  function announce(label, props) {
    if (muted) return

    var now = Date.now()
    if (now - (lastAnnouncedAt[label] || 0) < Number(settings.repeatMs)) return
    lastAnnouncedAt[label] = now
    lastLabel = label

    showPopup(SoundSource.messageFor(label, props, settings.showRole === true),
      SoundSource.glyphFor(props))
  }

  // ------------------------------------------------------------------- popup
  //
  // The card is a separate `panel` entry point in this same plugin, summoned
  // with a payload, rather than a PanelWindow declared here. A service is
  // created into the shell's non-visual service host (`Item { visible: false }`)
  // and a Window nested under an invisible Item inherits that invisibility, so
  // a window declared in this file maps but never shows. Panels are mounted by
  // the shell's own Loader instead, which is where omarchy.osd lives too.
  //
  // The plugin is keepLoaded, so the panel stays mounted and each summon just
  // hands it new content.

  function showPopup(message, glyph) {
    if (!shell) return
    shell.summon(pluginId, JSON.stringify({
      message: String(message || ""),
      glyph: String(glyph || ""),
      duration: Number(settings.duration),
      position: position
    }))
  }

  // Bind the snapshot so node.properties becomes readable. Without a tracker
  // every stream stays unbound and every label falls back to nothing.
  PwObjectTracker { objects: root.streams }

  IpcHandler {
    target: "sound-source"

    // What is making noise right now, on demand -- bind it to a key or drop
    // it in the Omarchy menu.
    function now(): string {
      var labels = SoundSource.activeLabels(root.streams, root.effectiveLabels)
      var text = labels.length > 0 ? labels.join(", ") : "Nothing playing"
      root.showPopup(text, SoundSource.GLYPH_SPEAKER)
      return text
    }

    // Same list without showing a popup.
    function list(): string {
      return SoundSource.activeLabels(root.streams, root.effectiveLabels).join("\n")
    }

    function last(): string { return root.lastLabel }

    // Same switch the bar icon flips, for a keybinding or a menu entry.
    function toggle(): string { return root.toggleMuted() }
    function state(): string { return root.muted ? "muted" : "unmuted" }

    // The dialog's list, and its checkboxes, from a terminal.
    function apps(): string { return root.knownApps.join("\n") }
    function ignored(): string { return (root.settings.ignore || []).join("\n") }
    function ignoreApp(name: string): string { return root.toggleIgnoredApp(name) }
    function setup(): string { root.setupRequested(); return "ok" }

    function ping(): string { return "ok" }
  }
}
