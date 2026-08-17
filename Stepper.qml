import QtQuick
import QtQuick.Layouts
import qs.Commons

// Compact stepper: +/- buttons flanking a directly-editable, validated
// number, plus scroll-to-step and press-and-hold auto-repeat. Used for
// interval hours and the hour/minute segments of the fixed-time picker in
// RollMenu.qml.
//
// A standalone file, not an inline `component Stepper: Item {...}` block --
// this codebase has hit inline `component` declarations misbehaving twice
// now (DiceIcon.qml's own header comment documents a runtime
// ReferenceError from one; RollMenu.qml briefly had this exact Stepper as
// an inline component and it failed to load at all with a QML syntax
// error, silently breaking the right-click menu since the whole file
// failed to parse). No first-party file under $OMARCHY_PATH/shell uses
// inline `component` either. Extracting to its own file, the same pattern
// DiceIcon.qml already uses, is the proven-working shape here.
//
// Typing/backspace into the center number may not reliably work -- see
// RollMenu.qml's PopupCard.grabFocus note for why (Qt::ToolTip windows,
// which is what that popup is, never receive keyboard focus at the
// platform level; the alternative, Qt::Popup, breaks the popup opening at
// all when anchored to the bar). The buttons/scroll/press-hold are fully
// MouseArea/WheelHandler-driven and don't depend on window keyboard focus,
// so treat those as the primary, reliable way to change a value here.
Item {
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
