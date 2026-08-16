import QtQuick
import QtQuick.Shapes
import qs.Commons

// Outline-style die face (rounded square + five pips), recolors with the
// theme via `color` the same way every other bar icon does (see
// DropboxIcon.qml for the sibling pattern) -- unlike a fixed-palette emoji
// glyph, which can't pick up Theme.foreground at all.
//
// Depth is faked cheaply for a ~16px bar icon: a diagonal sheen on the body
// fill, a thin highlight rim offset up-left and a thin shadow rim offset
// down-right (classic tiny-icon bevel trick -- no blur/effects, just two
// extra stroked copies of the same outline), and a small radial highlight
// on each pip so they read as raised dots rather than flat discs.
Item {
  id: root

  property real iconSize: Style.bar.iconCanvas
  property color color: Color.foreground
  property real strokeWidth: 1.6

  readonly property color highlight: Qt.lighter(color, 1.7)
  readonly property color shadow: Qt.darker(color, 1.45)
  readonly property real rimOffset: iconSize * 0.05

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real inset: strokeWidth / 2
  readonly property real r: iconSize * 0.22

  // Shadow rim: offset down-right, reads as depth beneath the body.
  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    opacity: 0.5
    transform: Translate { x: root.rimOffset; y: root.rimOffset }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.shadow
      strokeWidth: root.strokeWidth * 0.8
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: root.inset + root.r
      startY: root.inset
      PathLine { x: root.width - root.inset - root.r; y: root.inset }
      PathArc { x: root.width - root.inset; y: root.inset + root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.width - root.inset; y: root.height - root.inset - root.r }
      PathArc { x: root.width - root.inset - root.r; y: root.height - root.inset; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.inset + root.r; y: root.height - root.inset }
      PathArc { x: root.inset; y: root.height - root.inset - root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.inset; y: root.inset + root.r }
      PathArc { x: root.inset + root.r; y: root.inset; radiusX: root.r; radiusY: root.r }
    }
  }

  // Main body: base stroke plus a soft diagonal sheen fill, and the pips.
  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillGradient: LinearGradient {
        x1: 0; y1: 0
        x2: root.iconSize; y2: root.iconSize
        GradientStop { position: 0.0; color: Qt.rgba(root.highlight.r, root.highlight.g, root.highlight.b, 0.30) }
        GradientStop { position: 1.0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.05) }
      }

      startX: root.inset + root.r
      startY: root.inset
      PathLine { x: root.width - root.inset - root.r; y: root.inset }
      PathArc { x: root.width - root.inset; y: root.inset + root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.width - root.inset; y: root.height - root.inset - root.r }
      PathArc { x: root.width - root.inset - root.r; y: root.height - root.inset; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.inset + root.r; y: root.height - root.inset }
      PathArc { x: root.inset; y: root.height - root.inset - root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.inset; y: root.inset + root.r }
      PathArc { x: root.inset + root.r; y: root.inset; radiusX: root.r; radiusY: root.r }
    }

    Pip { cx: root.width * 0.28; cy: root.height * 0.28 }
    Pip { cx: root.width * 0.72; cy: root.height * 0.28 }
    Pip { cx: root.width * 0.50; cy: root.height * 0.50 }
    Pip { cx: root.width * 0.28; cy: root.height * 0.72 }
    Pip { cx: root.width * 0.72; cy: root.height * 0.72 }
  }

  // Highlight rim: offset up-left, simulates a top-left light source.
  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    opacity: 0.4
    transform: Translate { x: -root.rimOffset; y: -root.rimOffset }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.highlight
      strokeWidth: root.strokeWidth * 0.7
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: root.inset + root.r
      startY: root.inset
      PathLine { x: root.width - root.inset - root.r; y: root.inset }
      PathArc { x: root.width - root.inset; y: root.inset + root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.width - root.inset; y: root.height - root.inset - root.r }
      PathArc { x: root.width - root.inset - root.r; y: root.height - root.inset; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.inset + root.r; y: root.height - root.inset }
      PathArc { x: root.inset; y: root.height - root.inset - root.r; radiusX: root.r; radiusY: root.r }
      PathLine { x: root.inset; y: root.inset + root.r }
      PathArc { x: root.inset + root.r; y: root.inset; radiusX: root.r; radiusY: root.r }
    }
  }

  component Pip: ShapePath {
    property real cx: 0
    property real cy: 0
    readonly property real pr: root.iconSize * 0.075

    strokeWidth: 0
    fillGradient: RadialGradient {
      centerX: cx; centerY: cy; centerRadius: pr
      focalX: cx - pr * 0.3; focalY: cy - pr * 0.3
      GradientStop { position: 0.0; color: root.highlight }
      GradientStop { position: 1.0; color: root.color }
    }
    startX: cx - pr
    startY: cy
    PathArc { x: cx + pr; y: cy; radiusX: pr; radiusY: pr }
    PathArc { x: cx - pr; y: cy; radiusX: pr; radiusY: pr }
  }
}
