import QtQuick
import qs.Commons
import qs.Ui

// Bar icon for Theme Roulette. Left-click = "feel like something
// different?" -- fires an immediate reroll (avoiding the last few
// theme/wallpaper picks, never repeating the one just applied) and opens
// the panel to show what landed. The panel's own dice button is the
// "reroll again" do-over if the result doesn't land, with no separate
// command behind it: rerolling again is exactly the same CLI action fired
// a second time (see Service.reroll()). Right-click opens a menu
// (RollMenu.qml) for schedule tweaks and rolling back to a past pick. A
// third surface, RollPrompt.qml, opens itself (no click needed) whenever a
// scheduled roll is awaiting "Ready to roll?" confirmation.
//
// Built on BarIconButton (the same base every first-party icon-only bar
// widget uses -- see DropboxIcon's iconComponent usage) rather than a bare
// MouseArea: WidgetButton registers itself with Bar.registerClickTarget,
// which is how Bar.qml's own slot-level press handling
// (pressModuleClickTarget, Bar.qml:1740) finds a `triggerPress` target to
// dispatch to. A widget with its own unregistered MouseArea sits outside
// that dispatch path and press delivery through it is not reliable -- this
// was the root cause of left-click intermittently doing nothing.
//
// Same Loader-forwarding shape as the built-in Weather widget
// (shell/plugins/panels/weather/BarWidget.qml): Panel.qml is loaded here via
// a Loader rather than declared as its own manifest "panel" kind, since the
// bar widget is the only thing that ever needs to summon it (gotchas.md:
// "only declare a kind when the shell needs to instantiate that surface
// directly" -- confirmed against every first-party manifest.json in
// $OMARCHY_PATH/shell, none of which combine bar-widget with a standalone
// panel kind for exactly this loaded-via-Loader shape).
BarWidget {
  id: root
  moduleName: "io.github.haydenmckay.theme-roulette"

  readonly property var svc: bar?.shell?.serviceFor("io.github.haydenmckay.theme-roulette")

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("svc" in target) target.svc = root.svc
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root) -- same contract
  // Weather's BarWidget.qml implements.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity, same reasoning as Weather's BarWidget.qml.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: svc !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Hover-reveal, wired to match the built-in Indicators widget it sits next
  // to in the center section (see Indicators.qml's revealInactiveIndicators):
  // that cluster reveals as soon as *anywhere* in the center section is
  // hovered, via bar.centerSectionRevealHeld (set by Bar.qml's own
  // center-section-wide HoverHandler, not a per-icon one) -- so vox/record
  // fade in together as a group whenever the pointer is anywhere near them.
  // Previously this widget only listened to its own tiny icon's hover, so it
  // never joined that group fade and looked detached/invisible even while
  // its neighbours were visible. groupRevealed mirrors that same bar-level
  // signal so it fades in alongside them. directRevealed goes further (own
  // hover, panel/menu open, a roll pending or actively applying) and takes
  // it to full opacity -- same as how an indicator goes from the 0.45
  // "revealed but inactive" tier up to 1.0 once truly active, see
  // BarIndicator.qml's syncIndicatorOpacity -- so it can't fade out
  // mid-interaction or hide a reroll that's visibly spinning.
  readonly property bool groupRevealed: root.bar && root.bar.centerSectionRevealHeld === true
    && root.bar.centerHoverRevealSuppressed !== true
  readonly property bool directRevealed: button.tooltipHovered || root.opened || root.menuOpen
    || (root.svc && (root.svc.pending === true || root.svc.rolling === true))
  opacity: directRevealed ? 1.0 : (groupRevealed ? 0.6 : 0.0)
  Behavior on opacity {
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  onBarChanged: injectPanel()

  // Right-click menu (schedule + rollback) -- separate open/close from the
  // left-click Panel above, with its own owner so PopupCard's outside-click
  // dismissal (HyprlandFocusGrab -> owner.close()) doesn't collide with
  // root.close(), which is already spoken for by the Panel forwarding
  // contract. Same pattern Tray.qml uses for its own right-click popup.
  property bool menuOpen: false
  QtObject {
    id: menuOwner
    function close() { root.menuOpen = false }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Loader {
    id: menuLoader
    active: true
    source: Qt.resolvedUrl("RollMenu.qml")
    visible: false
  }

  Binding { target: menuLoader.item; property: "anchorItem"; value: root; when: menuLoader.item !== null }
  Binding { target: menuLoader.item; property: "bar"; value: root.bar; when: menuLoader.item !== null }
  Binding { target: menuLoader.item; property: "owner"; value: menuOwner; when: menuLoader.item !== null }
  Binding { target: menuLoader.item; property: "svc"; value: root.svc; when: menuLoader.item !== null }
  Binding { target: menuLoader.item; property: "open"; value: root.menuOpen; when: menuLoader.item !== null }

  // "Ready to roll?" prompt -- purely reactive to svc.pending, no click
  // needed to open it. hover-mode PopupCard skips the outside-click focus
  // grab entirely (see PopupCard.qml), so it never steals focus and can't
  // block anything else on the desktop while it waits out its own
  // countdown -- it just goes away on its own via confirm-pending if
  // nobody responds.
  Loader {
    id: promptLoader
    active: true
    source: Qt.resolvedUrl("RollPrompt.qml")
    visible: false
  }

  Binding { target: promptLoader.item; property: "anchorItem"; value: root; when: promptLoader.item !== null }
  Binding { target: promptLoader.item; property: "bar"; value: root.bar; when: promptLoader.item !== null }
  Binding { target: promptLoader.item; property: "svc"; value: root.svc; when: promptLoader.item !== null }
  Binding { target: promptLoader.item; property: "open"; value: root.svc ? root.svc.pending : false; when: promptLoader.item !== null }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: (root.svc && root.svc.rolling)
      ? "Rolling…"
      : "Left-click: feel like something different? · Right-click: schedule & rollback"

    iconComponent: Component {
      Item {
        DiceIcon {
          id: diceIcon
          anchors.centerIn: parent
          iconSize: Style.bar.iconCanvas
          color: button.foreground

          RotationAnimator on rotation {
            running: root.svc ? root.svc.rolling === true : false
            from: 0; to: 360
            duration: 700
            loops: Animation.Infinite
          }
        }
      }
    }

    onPressed: function(pressedButton) {
      if (!root.svc) return
      if (pressedButton === Qt.RightButton) {
        root.menuOpen = !root.menuOpen
        return
      }
      root.svc.reroll()
      root.open()
    }
  }
}
