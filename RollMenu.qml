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
  property string draftFixedTime: "9:00 AM"
  property var draftDays: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

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
    draftFixedTime = svc.fixedTime
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
      patch.fixedTime = draftFixedTime
    } else if (draftMode === "specific-days") {
      patch.fixedTime = draftFixedTime
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
        spacing: Style.space(10)

        NumberField {
          label: "Min hours"
          value: root.draftIntervalMin
          from: 0
          to: 168
          onModified: (value) => root.draftIntervalMin = value
        }

        NumberField {
          label: "Max hours"
          value: root.draftIntervalMax
          from: 0
          to: 168
          onModified: (value) => root.draftIntervalMax = value
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

        TextField {
          Layout.fillWidth: true
          text: root.draftFixedTime
          placeholderText: "9:00 AM"
          onEditingFinished: root.draftFixedTime = text
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
