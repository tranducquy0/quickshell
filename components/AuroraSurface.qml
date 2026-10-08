import QtQuick 6.10
import "../services" as QsServices

Item {
    id: root

    property color color: pywal.surfaceContainer
    property color strokeColor: pywal.outlineVariant
    property color accentColor: pywal.primary
    property color shadowColor: pywal.shadow
    // Desktop-software surfaces: square corners and a visible frame instead of floating cards.
    property real radius: 2
    property real borderWidth: 1
    property int elevation: 2
    property real accentOpacity: 0.10
    property real highlightOpacity: 0.08
    property bool hovered: false
    property bool highlighted: false
    property bool clipContent: true

    readonly property var pywal: QsServices.Pywal
    default property alias content: contentItem.data
    readonly property alias backgroundItem: surface

    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    readonly property color resolvedSurfaceColor: root.highlighted
        ? pywal.surfaceContainerHighest
        : root.hovered
            ? pywal.surfaceContainerHigh
            : root.color
    readonly property color resolvedBorderColor: root.highlighted
        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
        : root.hovered
            ? Qt.rgba(pywal.outline.r, pywal.outline.g, pywal.outline.b, 0.7)
            : root.strokeColor
    readonly property real stateLayerOpacity: root.highlighted
        ? root.accentOpacity
        : root.hovered
            ? root.highlightOpacity
            : 0

    Elevation {
        // Keep the old API, but make the 90s desktop treatment flat and legible.
        level: 0
        target: surface
        radius: surface.radius
        shadowColor: Qt.rgba(root.shadowColor.r, root.shadowColor.g, root.shadowColor.b, 0)
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Math.min(root.radius, 2)
        color: root.resolvedSurfaceColor
        border.width: Math.max(root.borderWidth, 1)
        border.color: root.resolvedBorderColor
        clip: root.clipContent

        Behavior on color {
            ColorAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: root.borderWidth
            radius: Math.max(0, parent.radius - root.borderWidth)
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.stateLayerOpacity)
            opacity: root.stateLayerOpacity > 0 ? 1 : 0

            Behavior on color {
                ColorAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }

        Item {
            id: contentItem
            anchors.fill: parent
        }
    }
}