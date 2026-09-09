// Pure helpers for the sound-source announcer.
//
// No QML imports here on purpose: everything in this file is plain JS so the
// classification rules can be reasoned about (and tested) without a running
// shell.

// media.role values that are music-like enough to deserve the note glyph
// rather than the generic speaker.
var MUSIC_ROLES = { music: true, video: true, movie: true, game: true }

// Names that identify the player process rather than anything the user would
// recognise. Anything playing through the shell's own process (bar plugins,
// radio widgets) reports node.name=quickshell.
var DEFAULT_LABELS = {
  "quickshell": "Omarchy shell",
  "omarchy-shell": "Omarchy shell"
}

// Identify playback streams the way the first-party audio panel does:
// without reading node.properties. PwNode.properties is invalid until the
// node is bound, and reading it too early can destabilize Quickshell's
// PipeWire service, so classification has to work off the cheap properties.
function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

// Reading properties on an unbound node throws or returns garbage depending
// on the Quickshell build, so every read goes through here.
function propsOf(node) {
  if (!node) return {}
  try {
    return node.properties || {}
  } catch (e) {
    return {}
  }
}

function roleOf(props) {
  return String((props || {})["media.role"] || "")
}

// Same precedence the audio panel uses for its stream rows, so the popup and
// the panel agree on what an app is called.
function rawLabel(node, props) {
  var p = props || {}
  var label = p["application.name"]
    || (node ? node.description : "")
    || p["media.name"]
    || p["node.name"]
    || (node ? node.name : "")
  return String(label || "").trim()
}

function mergedLabels(userLabels) {
  var out = {}
  for (var k in DEFAULT_LABELS) out[k] = DEFAULT_LABELS[k]
  if (userLabels) for (var u in userLabels) out[u] = userLabels[u]
  return out
}

function friendlyLabel(label, labels) {
  var raw = String(label || "").trim()
  if (!raw) return ""

  var map = labels || {}
  var hit = map[raw]
  if (hit === undefined) hit = map[raw.toLowerCase()]
  return hit === undefined || hit === null ? raw : String(hit)
}

// Streams that are plumbing rather than an application. Announcing these
// would fire a second popup for every single sound: on a machine running the
// Omarchy parametric EQ, every app's audio is re-published by the EQ as its
// own playback stream.
//
// Kept separate from the user's ignore list on purpose. An ignored app is
// still a real app that is playing, so it has to stay visible as something
// that exists -- otherwise it could never be un-ignored from the dialog.
function isPlumbing(node, props) {
  var p = props || {}

  // The EQ, and any other filter chain, tags itself as DSP.
  if (roleOf(p).toLowerCase() === "dsp") return true

  var name = String(p["node.name"] || (node ? node.name : "") || "")
  if (name.indexOf("omarchy_speaker_tuning") === 0) return true
  if (name.indexOf("output.omarchy.") === 0) return true
  if (name.indexOf("input.omarchy.") === 0) return true
  return false
}

// The user's list. Substring matched against both the node name and the app
// name, so a hand-written partial entry still works, while the dialog only
// ever writes whole app names.
function isIgnored(node, props, ignore) {
  var list = ignore || []
  if (!list || typeof list.length !== "number" || list.length === 0) return false

  var p = props || {}
  var name = String(p["node.name"] || (node ? node.name : "") || "")
  var haystack = (name + " " + rawLabel(node, p)).toLowerCase()
  for (var i = 0; i < list.length; i++) {
    var needle = String(list[i] || "").trim().toLowerCase()
    if (needle && haystack.indexOf(needle) !== -1) return true
  }
  return false
}

// Whole-name membership, which is the question the dialog's checkboxes ask.
function ignoreContains(ignore, label) {
  var want = String(label || "").trim().toLowerCase()
  if (!want) return false

  var list = ignore || []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i] || "").trim().toLowerCase() === want) return true
  }
  return false
}

// A new list with `label` added or removed. Removal is by case-insensitive
// whole-name match, so ticking a box off always clears the entry the box put
// there.
function withIgnored(ignore, label, want) {
  var name = String(label || "").trim()
  var key = name.toLowerCase()
  var list = ignore || []
  var out = []

  for (var i = 0; i < list.length; i++) {
    if (String(list[i] || "").trim().toLowerCase() === key) continue
    out.push(list[i])
  }
  if (want && name) out.push(name)
  return out
}

// The popup draws its own glyph, so these are the characters themselves
// rather than OsdModel icon names. Built from codepoints so the source stays
// encoding-proof; both are the same Nerd Font glyphs the shell's OSD uses for
// volume and media.
var GLYPH_SPEAKER = String.fromCodePoint(0xf028)
var GLYPH_NOTE = String.fromCodePoint(0xf075a)

var GLYPH_MUTED = String.fromCodePoint(0xeee8)

function glyphFor(props) {
  return MUSIC_ROLES[roleOf(props).toLowerCase()] ? GLYPH_NOTE : GLYPH_SPEAKER
}

// Where the card sits. Anything unrecognised falls back to the middle of the
// screen rather than off-screen or silently unplaced.
var POSITIONS = ["center", "top-center", "top-right", "bottom-center"]

function normalizePosition(value) {
  var p = String(value || "").trim().toLowerCase()
  return POSITIONS.indexOf(p) === -1 ? "center" : p
}

function messageFor(label, props, showRole) {
  var text = label || "Audio"
  if (!showRole) return text

  var role = roleOf(props)
  return role ? text + "  ·  " + role : text
}

// A service plugin gets `shell` injected but not its own shell.json entry, so
// it reads the entry out of the effective config itself.
//
// The shell keeps a plugin's inline settings in exactly one place: its bar
// layout entry while it is on the bar, otherwise its plugins[] entry --
// findEntryLocation() returns one or the other, never both. Both are read here
// so the plugin behaves identically whichever place its entry lives in, and so
// taking the icon off the bar does not silently reset every setting.
function entrySettings(shellConfig, pluginId) {
  var cfg = shellConfig || {}
  var want = String(pluginId)
  var found = null

  // The shell hands a plugin `barConfig`, which is shell.json's `bar` subtree,
  // so the layout is at cfg.layout. A whole shell.json (cfg.bar.layout) is still
  // accepted: the tests use that shape, and it is what a caller would expect.
  var layout = cfg.bar && cfg.bar.layout ? cfg.bar.layout
    : (cfg.layout ? cfg.layout : {})
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = layout[sections[s]]
    if (!arr || typeof arr.length !== "number") continue
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] && String(arr[i].id) === want) found = arr[i]
    }
  }

  if (!found && cfg.plugins && typeof cfg.plugins.length === "number") {
    for (var j = 0; j < cfg.plugins.length; j++) {
      if (cfg.plugins[j] && String(cfg.plugins[j].id) === want) found = cfg.plugins[j]
    }
  }

  if (!found) return {}

  var out = {}
  for (var k in found) {
    if (k === "id") continue
    if (found[k] === null || found[k] === undefined) continue
    out[k] = found[k]
  }
  return out
}

// `overrides` wins over the persisted entry: the shell pushes a plugin's
// barConfig one config change behind, so a value just written is not in the
// entry yet. The writer keeps it here until the pushed config catches up.
function settingsFrom(shellConfig, pluginId, defaults, overrides) {
  var out = {}
  for (var d in defaults) out[d] = defaults[d]

  var entry = entrySettings(shellConfig, pluginId)
  for (var k in entry) out[k] = entry[k]

  for (var o in (overrides || {})) out[o] = overrides[o]
  return out
}

// Distinct app labels currently producing output. Ignored apps are included:
// suppressing a popup does not stop the app playing, and the setup dialog
// lists these so an entry can be taken back off the list.
function activeLabels(streams, labels) {
  var seen = {}
  var out = []
  for (var i = 0; i < streams.length; i++) {
    var n = streams[i]
    if (!n || n.ready !== true) continue

    var props = propsOf(n)
    if (isPlumbing(n, props)) continue

    var label = friendlyLabel(rawLabel(n, props), labels)
    if (!label || seen[label]) continue
    seen[label] = true
    out.push(label)
  }
  return out
}
