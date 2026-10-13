import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Omarchy theme border, faded with a transparency gradient: full strength
// at the top-left, nearly clear through the middle, partly back toward the
// bottom-right. Drawn as an outline only (outer minus inner rounded rect), so
// translucent surfaces underneath are untouched.
Item {
  id: ring
  property real radius: Style.cornerRadius
  property real thickness: 1
  property color color: Color.menu.border
  // Opacity of the border colour at the three gradient stops.
  property real startOpacity: 0.6
  property real middleOpacity: 0.12
  property real endOpacity: 0.45

  function faded(k) { return Qt.rgba(ring.color.r, ring.color.g, ring.color.b, ring.color.a * k) }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillRule: ShapePath.OddEvenFill
      fillGradient: LinearGradient {
        x1: 0
        y1: 0
        // Mostly top-to-bottom with a slight lean, so the whole top edge
        // catches the light and the top-left corner most of all.
        x2: ring.width * 0.35
        y2: ring.height
        GradientStop { position: 0.0; color: ring.faded(ring.startOpacity) }
        GradientStop { position: 0.45; color: ring.faded(ring.middleOpacity) }
        GradientStop { position: 1.0; color: ring.faded(ring.endOpacity) }
      }

      PathRectangle {
        x: 0
        y: 0
        width: ring.width
        height: ring.height
        radius: ring.radius
      }
      PathRectangle {
        x: ring.thickness
        y: ring.thickness
        width: ring.width - ring.thickness * 2
        height: ring.height - ring.thickness * 2
        radius: Math.max(0, ring.radius - ring.thickness)
      }
    }
  }
}
