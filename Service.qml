import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// State owner for the voxtype polish-mode switcher.
//
// Unlike local.vpn there is no Process here at all: the whole state is one
// small text file, so FileView both reads it (with watchChanges, so an
// external `echo local > polish-mode` or `omarchy-shell local.voxtype ...`
// updates the bar immediately) and writes it.
Item {
  id: root

  // Injected by Panel.qml, which itself gets it from Bar.qml injectProps().
  // Note barWidget.defaults in manifest.json is catalog metadata only and is
  // NOT merged into `settings` (shell.qml:689-701 registers it, nothing reads
  // it back), so every default has to be applied here.
  property var settings: ({})

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }
  // shell.json values arrive as raw JSON: the user already has
  // "refreshIntervalSec": "5" (a string) on local.vpn, so never trust the type.
  function boolSetting(name, fallback) {
    var v = setting(name, fallback)
    if (typeof v === "boolean") return v
    var s = String(v).trim().toLowerCase()
    if (s === "true" || s === "1" || s === "yes" || s === "on") return true
    if (s === "false" || s === "0" || s === "no" || s === "off") return false
    return fallback
  }
  function stringSetting(name, fallback) {
    var v = String(setting(name, "")).trim()
    return v === "" ? fallback : v
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/voxtype"
  readonly property string modePath: stringSetting("modePath", configDir + "/polish-mode")

  // Single source of truth for every visual in Panel.qml. setMode() moves it
  // optimistically so the bar icon flips on the click instead of waiting for
  // the write -> inotify -> reload round trip; onLoaded then reconciles it
  // with whatever is actually on disk. Same shape as local.vpn's `_desired`
  // overlay, minus the bookkeeping, because here the write cannot "fail to
  // take effect" the way bringing up tun0 can.
  property string mode: Model.DEFAULT_MODE

  // false = the file is missing/unreadable. Painel e wrapper caem no MESMO
  // default nesse caso — Model.DEFAULT_MODE aqui, DEFAULT_SPEC no
  // voxtype-punct, e os dois valem `sed+qwen`. Ancorado na constante de
  // propósito: a versão anterior deste comentário dizia "auto", que é o apelido
  // da spec COM nuvem, e a string do painel copiou o erro e passou a prometer
  // ao usuário que um arquivo sumido mandava o ditado pro Google.
  // Este flag só liga o aviso "file missing" no hero do painel.
  property bool fileReadable: false

  readonly property var entry: Model.entryFor(mode)
  readonly property string glyph: entry.glyph
  readonly property string label: entry.label
  readonly property string hint: entry.hint

  readonly property bool colorize: boolSetting("colorize", true)
  readonly property var modeColors: {
    var v = setting("modeColors", null)
    return (v && typeof v === "object") ? v : ({})
  }

  // Per-mode override from shell.json, e.g. { "off": "#a55555" }. Returns ""
  // when unset so Panel.qml can fall back to a theme-derived color.
  function colorOverride(code) {
    if (!colorize) return ""
    var v = modeColors[code]
    return (typeof v === "string" && v.length > 0) ? v : ""
  }

  function setMode(code) {
    if (!Model.isValid(code)) return
    mode = code
    modeFile.setText(code + "\n")
  }
  function cycle(step) { setMode(Model.nextMode(mode, step === undefined ? 1 : step)) }
  function reload() { modeFile.reload() }

  FileView {
    id: modeFile
    path: root.modePath
    watchChanges: true
    // Same combination shell.qml:126-129 uses for ~/.config/omarchy/shell.json,
    // which is proven in-tree to keep watching after the file is replaced by a
    // rename (that is exactly how omarchy-shell-config commits its edits).
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.fileReadable = true
      root.mode = Model.parseMode(text())
    }
    onFileChanged: reload()
    onLoadFailed: function(error) {
      root.fileReadable = false
      root.mode = Model.DEFAULT_MODE
    }
    onSaveFailed: function(error) {
      console.warn("local.voxtype: write failed for " + root.modePath + " (error " + error + ")")
      reload()   // snap the UI back to whatever is really on disk
    }
  }

  // FileView cannot watch a path that does not exist yet, so watch the parent
  // directory too and re-read when anything in it changes. Mirrors
  // plugins/bar/Bar.qml:831-836, which watches the toggles dir for the same
  // reason. Cheap: polish-mode is 5 bytes and the dir changes ~never.
  FileView {
    path: root.configDir
    watchChanges: true
    printErrors: false
    onFileChanged: modeFile.reload()
  }
}
