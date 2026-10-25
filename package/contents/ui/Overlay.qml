// SPDX-License-Identifier: GPL-3.0-or-later
// The dock's icons, drawn magnified in a layer-shell surface anchored to the
// bottom edge across the whole screen width, so their position is ours to
// choose. It takes no input. KWin puts the top layer above panels but below
// menus and popups; the overlay layer drew the icons over the panel's own
// context menu. Panels share the top layer, so main.qml shows a fresh copy
// whenever the panel may have been raised over it.
import QtQuick
import org.kde.kirigami as Kirigami
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
    // Not a transient of the panel: Plasma never auto-hides a panel while a
    // transient window of it is visible, and the overlay always is.
    transientParent: null
    color: "transparent"
    width: Screen.width
    height: Math.max(1, Screen.height - dock.restOrigin.y + dock.headroom)
    // Always shown while loaded; the content hides instead. Hiding the window
    // from a binding crashed plasmashell when the panel was torn down.
    visible: true

    Item {
        id: content

        visible: dock.restOrigin.y >= 0 && dock.restWidth > 0
        x: dock.restOrigin.x - dock.sideRoom
        // Slides below the screen edge while Plasma hides the panel, as far
        // and as fast as KWin slides the panel, so the pill and the icons
        // move together. KWin's Sliding Popups moves the panel by its height
        // in 200 ms scaled by the animation speed, on an OutCubic timeline
        // that runs forward to show it and backward to hide it: fast first
        // when it comes in, fast last when it goes out (InCubic).
        y: 0
        width: dock.restWidth + 2 * dock.sideRoom
        height: dock.height + dock.headroom

        states: State {
            name: "hidden"
            when: dock.panelHidden

            PropertyChanges {
                target: content
                y: dock.panelHeight
            }
        }

        transitions: [
            Transition {
                to: "hidden"

                NumberAnimation {
                    property: "y"
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.InCubic
                }
            },
            Transition {
                from: "hidden"

                NumberAnimation {
                    property: "y"
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
        ]

        Repeater {
            model: overlay.tasks

            delegate: DockIcon {
                id: task

                dock: overlay.dock

                required property int index
                required property var model

                restCenter: dock.taskLeft(index) + dock.slot / 2
                source: model.decoration
                // The app's name; a window's display is its title.
                label: model.AppName || model.display
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
            // Names from Plasma's own Trash and launcher widgets, which come
            // translated; in English if a Plasma version changes them.
            label: i18ndc("plasma_applet_org.kde.plasma.trash", "@title the name of the Trash widget", "Trash")
        }

        DockIcon {
            dock: overlay.dock
            restCenter: dock.launcherLeft + dock.slot / 2
            source: "start-here-kde"
            label: i18ndc("plasma_applet_org.kde.plasma.kickoff", "@title:tab kickoff sidebar tab", "Applications")
        }
    }
}
