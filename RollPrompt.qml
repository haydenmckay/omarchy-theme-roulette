import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// "Ready to roll?" prompt for a scheduled pick that's landed but hasn't
// been applied yet (see bin/theme-roulette's check-due/confirm-pending/
// skip-pending). triggerMode: "hover" on the inner PopupCard means it
// never engages PopupCard's HyprlandFocusGrab (see PopupCard.qml: "Skipped
// for hover-mode popups so the cursor can move freely between the trigger
// and the popup") -- it can't steal focus or block anything else on the
// desktop, and it needs no dismiss handling of its own: `open` just
// follows svc.pending, which the CLI itself clears once the roll resolves
// (explicit button, or Service.qml's own countdown Timer calling
// confirmPending() on timeout -- see Service.qml's pendingTick). That
// timeout is what makes "load it up and present it for my return" work
// with nobody there to click anything.
//
// Wrapped in a plain Item for the same reason as RollMenu.qml: PopupCard's
// anchorItem/bar are `required property`, which BarWidget.qml's deferred
// post-Loader `Binding` elements can't satisfy directly.
Item {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var svc: null
  property bool open: false

  readonly property bool rolling: svc ? svc.rolling : false

  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    open: root.open
    triggerMode: "hover"
    // 230 was too narrow for "Let it ride" / "I'm feeling this" side by side
    // at Style.font.bodySmall -- the button Rectangles (sized off their
    // label's implicitHeight only, not width) clipped the label text. Wider
    // card plus wrapping labels below means neither can clip again even if
    // the button copy changes later.
    contentWidth: card.fittedContentWidth(Style.space(280))
    contentHeight: card.fittedContentHeight(promptColumn.implicitHeight)

    ColumnLayout {
      id: promptColumn
      anchors.fill: parent
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        DiceIcon {
          iconSize: Style.font.title
          color: root.bar ? root.bar.foreground : Color.foreground
        }

        Text {
          text: "Ready to roll?"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          Layout.fillWidth: true
        }
      }

      Text {
        Layout.fillWidth: true
        text: root.svc ? root.svc.pendingTheme : ""
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        text: root.svc ? root.svc.pendingWallpaperName : ""
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        visible: !root.rolling
        text: root.svc ? "Auto-rolling in " + root.svc.pendingSecondsLeft + "s" : ""
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.rolling
        text: "Rolling…"
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      RowLayout {
        visible: !root.rolling
        Layout.fillWidth: true
        spacing: Style.space(8)

        // Both buttons share one height (max of the two labels', not each
        // sized off its own) -- otherwise a copy-length mismatch between
        // them makes one visibly taller/shorter than the other, which is
        // exactly what happened here before this was added.
        readonly property real buttonHeight: Math.max(rideLabel.implicitHeight, passLabel.implicitHeight) + Style.space(14)

        Rectangle {
          id: rideButton
          Layout.fillWidth: true
          Layout.preferredHeight: parent.buttonHeight
          radius: Style.cornerRadius
          color: rideHover.containsMouse ? Color.accent : Qt.rgba(0, 0, 0, 0.15)

          Text {
            id: rideLabel
            anchors.centerIn: parent
            width: parent.width - Style.space(8)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Roll the Dice"
            color: rideHover.containsMouse ? Color.background : (root.bar ? root.bar.foreground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          MouseArea {
            id: rideHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.svc) root.svc.confirmPending()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: parent.buttonHeight
          radius: Style.cornerRadius
          color: passHover.containsMouse
            ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
            : Qt.rgba(0, 0, 0, 0.15)

          Text {
            id: passLabel
            anchors.centerIn: parent
            width: parent.width - Style.space(8)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Still Feeling This"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: passHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.svc) root.svc.skipPending()
          }
        }
      }
    }
  }
}
