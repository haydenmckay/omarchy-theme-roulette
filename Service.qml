import QtQuick
import Quickshell
import Quickshell.Io

// Headless service: owns shared roulette state for the bar widget/panel,
// mirrored from ~/.local/state/omarchy-theme-roulette/state.json (written by
// the `theme-roulette` CLI, which does all the real work -- picking, calling
// `omarchy theme set` / `omarchy theme bg set`, and computing the next roll
// time). Same split as omarchy-media-pip's Service.qml: this file never
// computes a roll or a schedule itself, it only reflects what the CLI wrote
// and pokes it on a timer.
//
// keepLoaded: true in manifest.json keeps this instance (and its Timer)
// alive even while the bar widget isn't visible/mounted -- required for
// scheduled rolls (random-interval / fixed-daily / specific-days) to ever
// fire on their own, not just on manual reroll.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/omarchy-theme-roulette/state.json"
  readonly property string configPath: home + "/.config/omarchy-theme-roulette/config.json"
  // Plugins find their own install directory via manifest.__sourceDir
  // (stamped in by services/PluginRegistry.qml) rather than a hardcoded
  // ~/Work path, so the CLI resolves correctly for any install location.
  readonly property string sourceDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : ""

  // A companion CLI living inside an *installed* plugin's own directory
  // cannot be launched via Quickshell's Process when loaded through
  // PluginRegistry.qml -- confirmed on omarchy-media-pip with a real
  // (non-dev-symlink) install: it fails with "Process failed to start,
  // likely because the binary could not be found" even though the exact
  // same path runs fine from a terminal. Root cause not found; the
  // documented workaround is to self-stage a copy outside the plugin
  // directory the instant sourceDir is known, and always invoke that copy.
  // `cp`/`chmod`/`mkdir` are themselves outside the plugin directory, so
  // *they* launch fine -- only the plugin's own CLI binary is affected.
  readonly property string stagingDir: home + "/.local/state/omarchy-theme-roulette/.bin"
  readonly property string stagedCliPath: stagingDir + "/theme-roulette"
  property bool cliStaged: false

  Process {
    id: stageProc
    onExited: (exitCode) => root.cliStaged = (exitCode === 0)
  }

  function restage() {
    if (sourceDir === "") return
    cliStaged = false
    stageProc.command = ["/bin/sh", "-c",
      "mkdir -p '" + stagingDir + "' && cp '" + sourceDir + "/bin/theme-roulette' '" + stagedCliPath + "' && chmod +x '" + stagedCliPath + "'"]
    stageProc.running = true
  }

  // Re-stage on every shell start (not just once) so the copy can't go
  // stale across an `omarchy plugin update`.
  onSourceDirChanged: restage()

  property var state: ({})
  property var config: ({})
  property bool stateLoaded: false

  readonly property string currentTheme: state.currentTheme || ""
  readonly property string currentWallpaper: state.currentWallpaper || ""
  readonly property string currentWallpaperName: {
    var w = currentWallpaper
    if (!w) return ""
    var slash = w.lastIndexOf("/")
    return slash >= 0 ? w.substring(slash + 1) : w
  }
  readonly property string nextRollAt: state.nextRollAt || ""
  readonly property string lastRollAt: state.lastRollAt || ""
  readonly property var history: state.history || []
  readonly property string mode: config.mode || "random-interval"
  readonly property int intervalMinHours: config.intervalMinHours !== undefined ? config.intervalMinHours : 4
  readonly property int intervalMaxHours: config.intervalMaxHours !== undefined ? config.intervalMaxHours : 12
  readonly property string fixedTime: config.fixedTime || "9:00 AM"
  readonly property var days: config.days || ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

  // ---- pending roll ("Ready to roll?") --------------------------------
  //
  // check-due picks a candidate but stops short of applying it; these
  // mirror that pending pick so the UI can show a confirm prompt instead
  // of the theme just changing out from under the user. confirmTimeout is
  // config-driven (default 60s) so an unattended prompt still resolves --
  // "Let it ride" -- instead of hanging forever.
  readonly property bool pending: state.pending === true
  readonly property string pendingTheme: state.pendingTheme || ""
  readonly property string pendingWallpaper: state.pendingWallpaper || ""
  readonly property string pendingWallpaperName: {
    var w = pendingWallpaper
    if (!w) return ""
    var slash = w.lastIndexOf("/")
    return slash >= 0 ? w.substring(slash + 1) : w
  }
  readonly property int confirmTimeoutSeconds: config.confirmTimeoutSeconds !== undefined ? config.confirmTimeoutSeconds : 60
  readonly property string pendingSince: state.pendingSince || ""
  property int pendingSecondsLeft: 0
  // Guards the auto-confirm so the 1s countdown Timer can't fire
  // confirm-pending more than once for the same pending roll (e.g. if
  // ticks keep landing at 0 while confirm-pending's own Process is still
  // running `omarchy theme set`, which takes 10-20s).
  property bool autoConfirmFired: false

  onPendingChanged: if (pending) autoConfirmFired = false

  Timer {
    id: pendingTick
    interval: 1000
    repeat: true
    running: root.pending
    triggeredOnStart: true
    onTriggered: {
      var deadline = Date.parse(root.pendingSince) + root.confirmTimeoutSeconds * 1000
      var left = Math.max(0, Math.round((deadline - Date.now()) / 1000))
      root.pendingSecondsLeft = left
      if (left <= 0 && !root.autoConfirmFired) {
        root.autoConfirmFired = true
        root.confirmPending()
      }
    }
  }

  // True while a reroll (or a pending roll being confirmed/skipped) is in
  // flight, so the bar/panel can show a spinner instead of letting a rapid
  // double-click queue up a second `omarchy theme set` on top of one still
  // running its restart hooks.
  readonly property bool rolling: rerollProc.running || confirmProc.running || skipProc.running || restoreProc.running

  function parseObject(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      return parsed && typeof parsed === "object" ? parsed : {}
    } catch (e) {
      return {}
    }
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.state = root.parseObject(text()); root.stateLoaded = true }
    onLoadFailed: { root.state = ({}); root.stateLoaded = true }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.config = root.parseObject(text())
      // A hand-edited config (new interval/schedule) should take effect
      // without waiting out whatever was already scheduled under the old
      // config -- reschedule immediately rather than on the next roll.
      root.recomputeNext()
    }
    onLoadFailed: root.config = ({})
  }

  function run(args, proc) {
    if (!cliStaged || proc.running) return
    proc.command = [root.stagedCliPath].concat(args)
    proc.running = true
  }

  // Manual trigger ("feel like something different?"), the panel's dice
  // "reroll again", and picking an item off the right-click menu's rollback
  // list all bypass the pending-confirmation flow -- an explicit user
  // action doesn't need a "ready to roll?" prompt in front of it.
  function reroll() { run(["reroll"], rerollProc) }
  Process { id: rerollProc }

  // Polled every 30s while the shell is running: cheap (a single
  // timestamp/pending-flag check) unless nextRollAt has actually arrived,
  // in which case it stashes a pending pick rather than applying it. This
  // is what makes random-interval/fixed-daily/specific-days fire on their
  // own -- scheduling only progresses while omarchy-shell is alive, which
  // is exactly while there's a desktop to theme.
  Timer {
    running: root.cliStaged
    interval: 30000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.run(["check-due"], scheduleProc)
  }
  Process { id: scheduleProc }

  // "Let it ride" -- applies the pending roll. Also what the countdown
  // Timer above calls on timeout, so an unattended prompt still resolves.
  function confirmPending() { run(["confirm-pending"], confirmProc) }
  Process { id: confirmProc }

  // "No, I'm feeling this" -- discards the pending roll and reschedules.
  function skipPending() { run(["skip-pending"], skipProc) }
  Process { id: skipProc }

  function recomputeNext() { run(["recompute-next"], recomputeProc) }
  Process { id: recomputeProc }

  // Shallow-merged into config.json; config.json's own FileView.onLoaded
  // (above) reschedules once the write lands, so nothing further to do
  // here on success.
  function setConfig(patch) { run(["config-set", JSON.stringify(patch)], configSetProc) }
  Process { id: configSetProc }

  // Rollback: re-applies a past roll from `history` by index without
  // disturbing history or the schedule.
  function restore(index) { run(["restore", String(index)], restoreProc) }
  Process { id: restoreProc }

  // Recent rolls for the right-click menu's rollback list, most recent
  // (index 0 -- the current live pick) first. Loaded on demand (when the
  // menu opens) rather than polled, since it only matters while that menu
  // is visible.
  property var historyList: []

  function loadHistory() { run(["history"], historyProc) }
  Process {
    id: historyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.historyList = Array.isArray(parsed) ? parsed : []
        } catch (e) {
          root.historyList = []
        }
      }
    }
  }
}
