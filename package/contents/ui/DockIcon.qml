// SPDX-License-Identifier: GPL-3.0-or-later
// One icon as drawn in the dock's overlay: grown around its rest center from
// its bottom edge and pushed aside by the spread, with its name in a bubble
// above it while the pointer is on it.
import QtQuick
import org.kde.kirigami as Kirigami

import "magnifier.mjs" as Magnifier

Item {
    id: dockIcon

    // The dock (main.qml), for its sizes and the magnification state.
    property Item dock
    property real restCenter: 0
    property var source
    property bool running: false
    property real hop: 0
    property string label
    readonly property bool hovered: dock.hoverX >= restCenter - dock.slot / 2 && dock.hoverX < restCenter + dock.slot / 2
    readonly property real offset: restCenter - dock.pointerX
    readonly property real iconScale: Magnifier.scaleAt(offset, dock.radius, dock.peak, dock.strength)

    x: dock.sideRoom + restCenter + Magnifier.displacementAt(offset, dock.radius, dock.peak, dock.strength)
        - width / 2
    width: dock.slot
    height: parent.height

    Kirigami.Icon {
        id: icon
        source: dockIcon.source
        width: dockIcon.dock.iconSize
        height: dockIcon.dock.iconSize
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dockIcon.dock.iconBottomMargin + dockIcon.hop
        transform: Scale {
            origin.x: icon.width / 2
            origin.y: icon.height
            xScale: dockIcon.iconScale
            yScale: dockIcon.iconScale
        }
    }

    // The running dot.
    Rectangle {
        visible: dockIcon.running
        width: 5
        height: 5
        radius: 2.5
        color: Kirigami.Theme.textColor
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(1, dockIcon.dock.iconBottomMargin / 2 - 2.5)
    }

    Rectangle {
        id: bubble

        visible: opacity > 0
        opacity: dockIcon.hovered && dockIcon.label !== "" ? 1 : 0
        width: name.implicitWidth + 2 * 10
        height: dockIcon.dock.labelHeight
        radius: height / 2
        color: Qt.rgba(0.11, 0.11, 0.12, 0.82)
        anchors.horizontalCenter: parent.horizontalCenter
        // Above the icon as drawn: grown and mid-hop.
        y: parent.height - dockIcon.dock.iconBottomMargin - dockIcon.hop
            - icon.height * dockIcon.iconScale - dockIcon.dock.labelGap - height

        Behavior on opacity {
            NumberAnimation {
                duration: 100
            }
        }

        Text {
            id: name
            anchors.centerIn: parent
            text: dockIcon.label
            color: "white"
            font.pointSize: 10
        }
    }
}
