// SPDX-License-Identifier: GPL-3.0-or-later
// The Files stack: places fan out of the Files icon like the macOS Dock and
// the original's Files stack (../dock-glass stack.js). Each item is a dark
// label left of its icon, highlighted on hover. Items spring out of the dock
// icon one after another, nearest first, and each label fades in once its
// icon has landed; closing runs the same in reverse: labels fade out first,
// then the items fly back into the icon, farthest first.
//
// A transparent layer-shell surface over the whole screen catches a click
// anywhere else, the dock icon included, and Escape, to close the stack.
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell

import "stackLayout.mjs" as StackLayout

Window {
    id: stack

    // Where the fan rises from, in this window: the top center of the dock
    // icon.
    property point origin
    // {name, icon, action} each, nearest the dock first.
    property var entries: []
    property bool closing: false

    // Emitted once the close animation is over, for the owner to drop it.
    signal closed

    // Fan: 48 px icons one step apart, bending right gently, as in the
    // original.
    readonly property int iconSize: 48
    readonly property int step: 58
    readonly property real bend: 0.00025
    readonly property int openMs: 260
    readonly property int openStaggerMs: 140
    readonly property int labelFadeMs: 100
    readonly property int closeMs: 230
    readonly property int closeStaggerMs: 90
    // Share of the close motion after which an item starts fading into the
    // icon.
    readonly property real closeFadeAt: 0.55
    readonly property var slots: StackLayout.fanSlots({count: entries.length, step: step, bend: bend})

    function close() {
        if (closing)
            return;
        closing = true;
        closeTimer.start();
    }

    function launch(action) {
        close();
        action();
    }

    LayerShell.Window.scope: "dockglass-stack"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
        | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive

    flags: Qt.FramelessWindowHint
    color: "transparent"

    Timer {
        id: closeTimer
        interval: stack.labelFadeMs + stack.closeStaggerMs + stack.closeMs + 20
        onTriggered: stack.closed()
    }

    // Takes clicks outside the items, and Escape.
    MouseArea {
        anchors.fill: parent
        focus: true
        onPressed: stack.close()
        Keys.onEscapePressed: stack.close()
    }

    Repeater {
        model: stack.entries

        delegate: Item {
            id: item

            required property var modelData
            required property int index

            readonly property real iconX: stack.origin.x + stack.slots[index].x
            readonly property real iconY: stack.origin.y + stack.slots[index].y
            // 0 inside the dock icon, 1 on its slot. Springing past 1 is the
            // overshoot of the open animation.
            property real progress: 0

            // The icon, on the right of its label, sits on the slot.
            x: iconX + stack.iconSize / 2 - width
            y: iconY - height / 2
            width: row.width
            height: row.height
            opacity: 0
            transform: [
                Scale {
                    origin.x: item.width - stack.iconSize / 2
                    origin.y: item.height / 2
                    xScale: 0.3 + 0.7 * item.progress
                    yScale: 0.3 + 0.7 * item.progress
                },
                Translate {
                    x: (stack.origin.x - item.iconX) * (1 - item.progress)
                    y: (stack.origin.y - item.iconY) * (1 - item.progress)
                }
            ]

            Row {
                id: row
                spacing: 10

                Rectangle {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(name.implicitWidth, 260) + 2 * 9
                    height: name.implicitHeight + 2 * 3
                    radius: 7
                    color: hover.hovered ? Qt.rgba(0.04, 0.52, 1, 0.92) : Qt.rgba(0.11, 0.11, 0.12, 0.82)
                    opacity: 0

                    Text {
                        id: name
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 260)
                        text: item.modelData.name
                        color: "white"
                        font.pointSize: 10
                        elide: Text.ElideRight
                    }
                }

                Kirigami.Icon {
                    source: item.modelData.icon
                    width: stack.iconSize
                    height: stack.iconSize
                }
            }

            HoverHandler {
                id: hover
            }

            TapHandler {
                enabled: !stack.closing
                onTapped: stack.launch(item.modelData.action)
            }

            // Springs out of the dock icon, nearest ones first. Opacity gets
            // its own ease, without the overshoot.
            SequentialAnimation {
                id: openAnimation
                running: true

                PauseAnimation {
                    duration: StackLayout.staggerDelay(item.index, stack.entries.length, stack.openStaggerMs)
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: item
                        property: "progress"
                        to: 1
                        duration: stack.openMs
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: item
                        property: "opacity"
                        to: 1
                        duration: stack.openMs / 2
                        easing.type: Easing.OutQuad
                    }
                    SequentialAnimation {
                        PauseAnimation {
                            duration: stack.openMs * 0.7
                        }
                        NumberAnimation {
                            target: label
                            property: "opacity"
                            to: 1
                            duration: stack.labelFadeMs
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }

            // Labels go first, then the items fly back, farthest first,
            // fading only as they arrive.
            SequentialAnimation {
                running: stack.closing

                // Closing mid-way takes over from wherever the item is.
                ScriptAction {
                    script: openAnimation.stop()
                }
                NumberAnimation {
                    target: label
                    property: "opacity"
                    to: 0
                    duration: stack.labelFadeMs
                    easing.type: Easing.OutQuad
                }
                PauseAnimation {
                    duration: StackLayout.staggerDelay(stack.entries.length - 1 - item.index, stack.entries.length,
                                                       stack.closeStaggerMs)
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: item
                        property: "progress"
                        to: 0
                        duration: stack.closeMs
                        easing.type: Easing.InOutCubic
                    }
                    SequentialAnimation {
                        PauseAnimation {
                            duration: stack.closeMs * stack.closeFadeAt
                        }
                        NumberAnimation {
                            target: item
                            property: "opacity"
                            to: 0
                            duration: stack.closeMs * (1 - stack.closeFadeAt)
                            easing.type: Easing.InQuad
                        }
                    }
                }
            }
        }
    }
}
