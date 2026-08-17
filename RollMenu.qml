import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Right-click menu for the dice bar icon: schedule controls (mode + its
// parameter) and a rollback list of recent rolls. Wraps PopupCard behind a
// plain Item with ordinary (non-required) properties -- same shape our own
// Panel.qml uses around KeyboardPanel -- because BarWidget.qml wires
// anchorItem/bar/owner/svc in via `Binding` elements *after* this loads
// through a `Loader`, and PopupCard's own `anchorItem`/`bar` are `required
// property`, which must be satisfied inline at the point PopupCard itself
// is declared (below), not by an external Binding that only resolves once
// the Loader's item exists.
//
// Draft schedule fields are local and only synced from the service when the
// menu opens (see syncFromService/onOpenChanged), not bound live to
// svc.config -- otherwise a config-set landing mid-edit (or the 30s poll
// elsewhere) would yank a field out from under whatever the user is
// currently typing.
// Compact stepper: +/- buttons flanking a directly-editable, validated
// number, plus scroll-to-step and press-and-hold auto-repeat. Used for
// interval hours and the hour/minute segments of the fixed-time picker.
// Typing/backspace into the center number may not reliably work -- see the
// PopupCard.grabFocus note below for why (Qt::ToolTip windows, which is
// what this popup is, never receive keyboard focus at the platform level;
// the alternative, Qt::Popup, breaks the popup opening at all when
// anchored to the bar). The buttons/scroll/press-hold are fully
// MouseArea/WheelHandler-driven and don't depend on window keyboard focus,
// so treat those as the primary, reliable way to change a value here.
component Stepper: Item {
  id: stepper

  property int value: 0
  property int from: 0
  property int to: 59
  property int padDigits: 0
  property bool wrap: false
  property color foreground: Color.foreground
  signal modified(int value)

  implicitWidth: Style.space(60)
  implicitHeight: Style.spacing.controlHeight

  function clampValue(v) {
    if (stepper.wrap) {
      var span = stepper.to - stepper.from + 1
      return stepper.from + (((v - stepper.from) % span) + span) % span
    }
    return Math.max(stepper.from, Math.min(stepper.to, v))
  }

  function step(delta) {
    var next = stepper.clampValue(stepper.value + delta)
    if (next !== stepper.value) { stepper.value = next; stepper.modified(next) }
  }

  function displayText() {
    var s = String(stepper.value)
    while (s.length < stepper.padDigits) s = "0" + s
    return s
  }

  onValueChanged: if (!input.activeFocus) input.text = stepper.displayText()

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.rgba(0, 0, 0, input.activeFocus ? 0.25 : 0.15)
    border.width: input.activeFocus ? 1 : 0
    border.color: Color.accent
  }

  WheelHandler {
    onWheel: (event) => stepper.step(event.angleDelta.y > 0 ? 1 : -1)
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.space(2)
    spacing: 0

    Item {
      Layout.preferredWidth: Style.space(16)
      Layout.fillHeight: true

      Text {
        anchors.centerIn: parent
        text: "−"
        color: stepper.foreground
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: downArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: { stepper.step(-1); repeatTimer.direction = -1; repeatDelay.start() }
        onReleased: { repeatDelay.stop(); repeatTimer.stop() }
        onExited: { repeatDelay.stop(); repeatTimer.stop() }
      }
    }

    TextInput {
      id: input
      Layout.fillWidth: true
      Layout.fillHeight: true
      horizontalAlignment: TextInput.AlignHCenter
      verticalAlignment: TextInput.AlignVCenter
      text: stepper.displayText()
      color: stepper.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      selectByMouse: true
      validator: IntValidator { bottom: stepper.from; top: stepper.to }

      onEditingFinished: {
        var n = parseInt(input.text, 10)
        if (!isNaN(n)) {
          var c = stepper.clampValue(n)
          stepper.value = c
          stepper.modified(c)
        }
        input.text = stepper.displayText()
      }
    }

    Item {
      Layout.preferredWidth: Style.space(16)
      Layout.fillHeight: true

      Text {
        anchors.centerIn: parent
        text: "+"
        color: stepper.foreground
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: upArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: { stepper.step(1); repeatTimer.direction = 1; repeatDelay.start() }
        onReleased: { repeatDelay.stop(); repeatTimer.stop() }
        onExited: { repeatDelay.stop(); repeatTimer.stop() }
      }
    }
  }

  // Press-and-hold auto-repeat so reaching e.g. 168 hours doesn't take 168
  // individual clicks: a short initial delay, then repeats every 80ms.
  property int _repeatDirection: 0
  Timer {
    id: repeatDelay
    interval: 350
    onTriggered: repeatTimer.start()
  }
  Timer {
    id: repeatTimer
    property int direction: 0
    interval: 80
    repeat: true
    onTriggered: stepper.step(direction)
  }
}

Item {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property var svc: null
  property bool open: false

  function close() { card.close() }

  property string draftMode: "random-interval"
  property int draftIntervalMin: 4
  property int draftIntervalMax: 12
  property int draftHour: 9
  property int draftMinute: 0
  property string draftAmPm: "AM"
  property var draftDays: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

  // "9:00 AM" (what this menu writes) and "21:00" (a hand-edited 24h
  // config.json, since the CLI's `date -d "today $fixedTime"` accepts
  // either) both need to load correctly into the hour/minute/AM-PM
  // steppers below.
  function parseFixedTime(str) {
    var s = (str || "9:00 AM").toString().trim()
    var m = s.match(/^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?$/)
    if (!m) return { hour: 9, minute: 0, ampm: "AM" }
    var h = parseInt(m[1], 10)
    var min = parseInt(m[2], 10)
    var ap = m[3] ? m[3].toUpperCase() : null
    if (!ap) {
      ap = h >= 12 ? "PM" : "AM"
      h = h % 12
      if (h === 0) h = 12
    } else if (h === 0) {
      h = 12
    }
    if (isNaN(h) || h < 1 || h > 12) h = 9
    if (isNaN(min) || min < 0 || min > 59) min = 0
    return { hour: h, minute: min, ampm: ap }
  }

  function serializeFixedTime() {
    var mm = String(root.draftMinute)
    if (mm.length < 2) mm = "0" + mm
    return root.draftHour + ":" + mm + " " + root.draftAmPm
  }

  readonly property var allDays: [
    { key: "mon", label: "M" }, { key: "tue", label: "T" }, { key: "wed", label: "W" },
    { key: "thu", label: "T" }, { key: "fri", label: "F" }, { key: "sat", label: "S" },
    { key: "sun", label: "S" }
  ]

  function syncFromService() {
    if (!svc) return
    draftMode = svc.mode
    draftIntervalMin = svc.intervalMinHours
    draftIntervalMax = svc.intervalMaxHours
    var t = parseFixedTime(svc.fixedTime)
    draftHour = t.hour
    draftMinute = t.minute
    draftAmPm = t.ampm
    draftDays = (svc.days || []).slice()
  }

  function toggleDay(key) {
    var next = draftDays.slice()
    var i = next.indexOf(key)
    if (i >= 0) next.splice(i, 1)
    else next.push(key)
    draftDays = next
  }

  function applySchedule() {
    if (!svc) return
    var patch = { mode: draftMode }
    if (draftMode === "random-interval") {
      patch.intervalMinHours = draftIntervalMin
      patch.intervalMaxHours = draftIntervalMax
    } else if (draftMode === "fixed-daily") {
      patch.fixedTime = root.serializeFixedTime()
    } else if (draftMode === "specific-days") {
      patch.fixedTime = root.serializeFixedTime()
      patch.days = draftDays
    }
    svc.setConfig(patch)
  }

  // theme-roulette's history entries store kebab names (display strings are
  // only computed for the *current* pick, server-side, in title_case) --
  // title-case it here the same way for the rollback list.
  function titleCase(kebab) {
    if (!kebab) return ""
    return kebab.split("-").map(function(w) {
      return w.length ? w.charAt(0).toUpperCase() + w.slice(1) : w
    }).join(" ")
  }

  function relativeTime(iso) {
    if (!iso) return ""
    var then = Date.parse(iso)
    if (isNaN(then)) return ""
    var mins = Math.round((Date.now() - then) / 60000)
    if (mins < 1) return "just now"
    if (mins < 60) return mins + "m ago"
    var hours = Math.round(mins / 60)
    if (hours < 24) return hours + "h ago"
    return Math.round(hours / 24) + "d ago"
  }

  onOpenChanged: if (open) { syncFromService(); if (svc) svc.loadHistory() }

  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.owner
    open: root.open
    // grabFocus: true was tried here to fix keyboard input (see the Stepper
    // component's header comment) but reverted -- it flips Quickshell's
    // PopupWindow from Qt::ToolTip to Qt::Popup, which requests a native
    // xdg_popup grab. That grab appears to be incompatible with this
    // popup's transient parent being a layer-shell surface (the bar
    // itself): with grabFocus set, right-click stopped opening the menu at
    // all (almost certainly the compositor rejecting/immediately clearing
    // an xdg_popup grab whose parent isn't a plain xdg_surface toplevel).
    // A menu that won't open is worse than one that opens but can't always
    // be typed into, so this is reverted for now -- the Stepper's
    // buttons/scroll/press-hold are fully MouseArea/WheelHandler-driven and
    // don't depend on window keyboard focus at all, so they stay reliable
    // either way. Real fix would need a way to grant this window keyboard
    // focus without an xdg_popup grab tied to a layer-shell parent -- not
    // solved here.
    contentWidth: card.fittedContentWidth(Style.space(300))
    contentHeight: card.fittedContentHeight(menuColumn.implicitHeight)

    ColumnLayout {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: "Theme Roulette"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      PanelSectionHeader { Layout.fillWidth: true; text: "Schedule" }

      Dropdown {
        Layout.fillWidth: true
        showLabel: false
        value: root.draftMode
        options: [
          { value: "random-interval", label: "Random interval" },
          { value: "fixed-daily", label: "Fixed daily time" },
          { value: "specific-days", label: "Specific days" }
        ]
        onChanged: (value) => root.draftMode = value
      }

      RowLayout {
        visible: root.draftMode === "random-interval"
        Layout.fillWidth: true
        spacing: Style.space(16)

        ColumnLayout {
          spacing: Style.space(4)
          Text {
            text: "Min hours"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
          Stepper {
            from: 0
            to: 168
            value: root.draftIntervalMin
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onModified: (value) => root.draftIntervalMin = value
          }
        }

        ColumnLayout {
          spacing: Style.space(4)
          Text {
            text: "Max hours"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
          Stepper {
            from: 0
            to: 168
            value: root.draftIntervalMax
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onModified: (value) => root.draftIntervalMax = value
          }
        }
      }

      ColumnLayout {
        visible: root.draftMode === "fixed-daily" || root.draftMode === "specific-days"
        Layout.fillWidth: true
        spacing: Style.space(4)

        Text {
          text: "Time"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        RowLayout {
          spacing: Style.space(6)

          Stepper {
            from: 1
            to: 12
            wrap: true
            value: root.draftHour
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onModified: (value) => root.draftHour = value
          }

          Text {
            text: ":"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Stepper {
            from: 0
            to: 59
            padDigits: 2
            wrap: true
            value: root.draftMinute
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onModified: (value) => root.draftMinute = value
          }

          // Two-state AM/PM toggle -- a Dropdown would work but is
          // overkill for exactly two mutually exclusive values that
          // benefit from being visible/clickable at a glance.
          Rectangle {
            Layout.preferredWidth: Style.space(44)
            Layout.preferredHeight: Style.spacing.controlHeight
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.15)

            Text {
              anchors.centerIn: parent
              text: root.draftAmPm
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.draftAmPm = (root.draftAmPm === "AM" ? "PM" : "AM")
            }
          }
        }
      }

      RowLayout {
        visible: root.draftMode === "specific-days"
        Layout.fillWidth: true
        spacing: Style.space(4)

        Repeater {
          model: root.allDays
          Rectangle {
            readonly property bool active: root.draftDays.indexOf(modelData.key) >= 0
            Layout.preferredWidth: Style.space(24)
            Layout.preferredHeight: Style.space(24)
            radius: Style.cornerRadius
            color: active
              ? Color.accent
              : (dayHover.containsMouse ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent) : Qt.rgba(0, 0, 0, 0.15))

            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: active ? Color.background : (root.bar ? root.bar.foreground : Color.foreground)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: dayHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleDay(modelData.key)
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: applyLabel.implicitHeight + Style.space(12)
        radius: Style.cornerRadius
        color: applyHover.containsMouse
          ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
          : Qt.rgba(0, 0, 0, 0.15)

        Text {
          id: applyLabel
          anchors.centerIn: parent
          text: "Apply schedule"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: applyHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.applySchedule()
        }
      }

      PanelSeparator { Layout.fillWidth: true }

      PanelSectionHeader { Layout.fillWidth: true; text: "Roll back" }

      Text {
        visible: !root.svc || root.svc.historyList.length <= 1
        Layout.fillWidth: true
        text: "Nothing to roll back to yet"
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)

        // Index 0 is the current live pick, not something to roll back to --
        // skip it and offer the next few.
        Repeater {
          model: root.svc ? root.svc.historyList.slice(1, 6) : []

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: rollbackRow.implicitHeight + Style.space(10)
            radius: Style.cornerRadius
            color: rollbackHover.containsMouse
              ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
              : "transparent"

            RowLayout {
              id: rollbackRow
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(6)

              Text {
                Layout.fillWidth: true
                text: root.titleCase(modelData.theme)
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                text: root.relativeTime(modelData.at)
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: rollbackHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.svc) root.svc.restore(modelData.index)
                root.close()
              }
            }
          }
        }
      }
    }
  }
}
