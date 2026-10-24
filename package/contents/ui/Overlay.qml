// SPDX-License-Identifier: GPL-3.0-or-later
// The dock's icons, drawn magnified in a layer-shell surface anchored to the
// bottom edge across the whole screen width, so their position is ours to
// choose. It takes no input. KWin puts the top layer above panels but below
// menus and popups; the overlay layer drew the icons over the panel's own
// context menu. Panels share the top layer, so main.qml shows a fresh copy
// whenever the panel may have been raised over it.
import QtQuick
import org.kde.layershell as LayerShell

import "magnifier.mjs" as Magnifier

Window {
    id: overlay

    // The dock (main.qml), for its layout and state, and its tasks.
    property Item dock
    property var tasks

    LayerShell.Window.scope: "dockglass-overlay"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
        | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    width: Screen.width
    height: Math.max(1, Screen.height - dock.restOrigin.y + dock.headroom)
    visible: dock.restOrigin.y >= 0 && dock.restWidth > 0

    Item {
        x: dock.restOrigin.x - dock.sideRoom
        y: 0
        width: dock.restWidth + 2 * dock.sideRoom
        height: dock.height + dock.headroom

        Repeater {
            model: overlay.tasks

            delegate: DockIcon {
                id: task

                dock: overlay.dock

                required property int index
                required property var model

                restCenter: dock.taskLeft(index) + dock.slot / 2
                source: model.decoration
                running: model.IsWindow === true

                readonly property string url: model.LauncherUrlWithoutIcon.toString()
                // The launcher and the app's window rows share the URL, and
                // a launch in place swaps one for the other.
                readonly property bool bouncing: url in dock.bouncing && model.IsWindow !== true

                onBouncingChanged: {
                    if (!bouncing)
                        dock.stopBounce(url);
                }
                // The app's window arrives as a new row, whose bouncing
                // starts false and never changes, so end the bounce here.
                Component.onCompleted: {
                    if (model.IsWindow === true)
                        dock.stopBounce(url);
                }

                SequentialAnimation on hop {
                    running: task.bouncing
                    loops: Animation.Infinite
                    alwaysRunToEnd: true

                    NumberAnimation {
                        to: dock.bounceHeight
                        duration: dock.bounceStepMs
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        to: 0
                        duration: dock.bounceStepMs
                        easing.type: Easing.InQuad
                    }
                }
            }
        }

        // The separator moves with the spread but does not grow.
        Rectangle {
            width: 1
            height: Math.round(dock.height * 0.6)
            x: dock.sideRoom + dock.separatorCenter - width / 2
                + Magnifier.displacementAt(dock.separatorCenter - dock.pointerX, dock.radius, dock.peak,
                                           dock.strength)
            y: parent.height - dock.height + (dock.height - height) / 2
            color: Qt.rgba(1, 1, 1, 0.35)
        }

        DockIcon {
            dock: overlay.dock
            restCenter: dock.trashLeft + dock.slot / 2
            source: dock.trashFull ? "user-trash-full" : "user-trash"
        }

        DockIcon {
            dock: overlay.dock
            restCenter: dock.launcherLeft + dock.slot / 2
            source: "start-here-kde"
        }
    }
}
