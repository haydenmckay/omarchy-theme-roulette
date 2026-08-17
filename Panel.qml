import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Small popup showing the current theme+wallpaper roll with a dice button
// to reroll again -- the "if you don't like it, roll again" flow. Opened by
// BarWidget.qml right after it fires the initial reroll, so the very first
// thing a user sees after clicking the bar icon is what they just got.
//
// Extends the shared Panel base (qs.Ui.Panel), which already implements
// open()/close()/toggle()/closeForPopoutSwitch() and the opened/popoutSwitch*
// properties BarWidget.qml forwards -- nothing here needs to override them,
// unlike Weather's Panel.qml which layers extra side effects (data refresh,
// hover-reveal suppression) onto open(). manageIpc: false because the bar
// widget owns IPC/interaction (gotchas.md); this panel is only ever reached
// through BarWidget.qml's Loader, never summoned standalone.
Panel {
  id: root
  moduleName: "io.github.haydenmckay.theme-roulette"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null
  readonly property var barIdentity: hostWidget || root

  readonly property string themeName: svc ? svc.currentTheme : ""
  readonly property string wallpaperName: svc ? svc.currentWallpaperName : ""
  readonly property bool rolling: svc ? svc.rolling : false
  readonly property string mode: svc ? svc.mode : "random-interval"

  function modeLabel() {
    switch (mode) {
      case "fixed-daily": return "Rolls daily"
      case "specific-days": return "Rolls on schedule"
      default: return "Rolls on a random interval"
    }
  }

  // svc.nextRollAt is ISO-8601 with an explicit offset (see bin/theme-roulette's
  // `date --iso-8601=seconds`), which QML's Date constructor parses directly.
  function nextRollLabel() {
    if (!svc || !svc.nextRollAt) return ""
    var d = new Date(svc.nextRollAt)
    if (isNaN(d.getTime())) return ""
    return Qt.formatDateTime(d, "ddd d MMM, h:mm AP")
  }

  KeyboardPanel {
    id: card
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: card.fittedContentWidth(Style.space(240))
    contentHeight: card.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onReturnRequested: if (!root.rolling && root.svc) root.svc.reroll()

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          DiceIcon {
            iconSize: Style.font.title
            color: root.bar ? root.bar.foreground : Color.foreground
          }

          Text {
            text: "Theme Roulette"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.themeName || "—"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.wallpaperName || "—"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        PanelSeparator {
          Layout.fillWidth: true
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            text: root.modeLabel()
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.nextRollLabel() !== ""
            text: "Next: " + root.nextRollLabel()
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          id: rerollButton
          Layout.fillWidth: true
          Layout.preferredHeight: rerollRow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: rerollHover.containsMouse
            ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
            : Qt.rgba(0, 0, 0, 0.15)
          opacity: root.rolling ? 0.6 : 1.0

          Row {
            id: rerollRow
            anchors.centerIn: parent
            spacing: Style.space(8)

            DiceIcon {
              iconSize: Style.font.body
              color: root.bar ? root.bar.foreground : Color.foreground

              RotationAnimator on rotation {
                running: root.rolling
                from: 0; to: 360
                duration: 700
                loops: Animation.Infinite
              }
            }

            Text {
              text: root.rolling ? "Rolling…" : "Reroll again"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          MouseArea {
            id: rerollHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !root.rolling
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.svc) root.svc.reroll()
          }
        }
      }
    }
  }
}
