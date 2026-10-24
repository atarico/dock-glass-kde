// SPDX-License-Identifier: GPL-3.0-or-later
// Spike 2 (S3 in odd/tasks/plasma-port.md): the panel keeps Plasma's own
// background, so the panel itself is the pill and KWin blurs it. The icons
// are drawn in an input-transparent overlay window above the panel, which
// has room for them to grow past the panel's height. Hover and clicks still
// land on the panel at the rest layout: the spread keeps the point under the
// pointer fixed, so the icon drawn under the pointer is the one whose rest
// slot holds the pointer. While magnifying, this item widens evenly around
// the rest layout, so the pill grows enough to hold the spread icons and the
// rest layout stays put on screen.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import org.kde.taskmanager as TaskManager

import "magnifier.mjs" as Magnifier

PlasmoidItem {
    id: root

    readonly property int iconSize: 48
    readonly property int slot: 60
    readonly property real peak: 1.4
    readonly property real radius: 3 * slot
    readonly property int pointerSmoothingMs: 40
    readonly property int strengthSmoothingMs: 80
    readonly property real iconBottomMargin: Math.max(0, (height - iconSize) / 2)
    // Room the overlay adds around the panel: icons spread up to
    // (peak - 1) * radius / 2 past each end and grow (peak - 1) * iconSize up.
    readonly property real sideRoom: Math.ceil((peak - 1) * radius / 2)
    readonly property real headroom: Math.ceil((peak - 1) * iconSize)

    property real pointerX: 0
    property bool pointerSeeded: false
    property real strength: 0
    readonly property bool active: hover.hovered
    readonly property real restWidth: tasksModel.count * slot
    // How far each end of the pill moves out. The icons spread unevenly, but
    // a centered panel grows the same on both sides, so both ends take the
    // larger spread and no icon spills past the pill.
    readonly property real grow: Math.max(
        -Magnifier.displacementAt(-pointerX, radius, peak, strength),
        Magnifier.displacementAt(restWidth - pointerX, radius, peak, strength))
    // Where the rest layout starts in this item, from the width the panel
    // actually gave us, so it moves together with the panel.
    readonly property real restStart: Math.max(0, (width - restWidth) / 2)
    // Where the rest layout sits on screen. Wayland only tells us by mapping,
    // so the spike polls it, and only at rest: while magnifying, the panel
    // resizes around the rest layout every frame.
    property point restOrigin: Qt.point(-1, -1)

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Layout.preferredWidth: restWidth + 2 * Math.ceil(grow)
    Layout.minimumWidth: Layout.preferredWidth
    Layout.fillHeight: true

    TaskManager.TasksModel {
        id: tasksModel
        groupMode: TaskManager.TasksModel.GroupApplications
        sortMode: TaskManager.TasksModel.SortManual
        // launchInPlace only keeps a running app in its launcher's slot while
        // launchers stay separate; with false the app jumped to the end.
        separateLaunchers: true
        launchInPlace: true
        launcherList: [
            "preferred://filemanager",
            "preferred://browser",
            "applications:org.kde.konsole.desktop",
            "applications:systemsettings.desktop",
        ]
    }

    HoverHandler {
        id: hover
    }

    FrameAnimation {
        running: root.active || root.strength > 0
        onTriggered: {
            const dt = Math.min(frameTime * 1000, 50);
            if (root.active) {
                const target = hover.point.position.x - root.restStart;
                root.pointerX = root.pointerSeeded
                    ? Magnifier.approach(root.pointerX, target, dt, root.pointerSmoothingMs)
                    : target;
                root.pointerSeeded = true;
            }
            const strength = Magnifier.approach(root.strength, root.active ? 1 : 0, dt, root.strengthSmoothingMs);
            if (!root.active && strength < 0.002) {
                root.strength = 0;
                root.pointerSeeded = false;
            } else {
                root.strength = strength;
            }
        }
    }

    // Click targets at the rest layout. What they show is drawn in the overlay.
    Repeater {
        model: tasksModel

        delegate: Item {
            id: hit

            required property int index
            required property var model

            x: root.restStart + index * root.slot
            width: root.slot
            height: root.height

            TapHandler {
                onTapped: {
                    const index = tasksModel.makeModelIndex(hit.index);
                    if (hit.model.IsActive === true)
                        tasksModel.requestToggleMinimized(index);
                    else
                        tasksModel.requestActivate(index);
                }
            }
        }
    }

    // A layer-shell surface anchored to the bottom edge across the whole
    // screen width, so its position is ours to choose. It takes no input.
    // KWin puts the top layer above panels but below menus and popups; the
    // overlay layer drew the icons over the panel's own context menu.
    Window {
        id: overlay

        LayerShell.Window.scope: "dockglass-overlay"
        LayerShell.Window.layer: LayerShell.Window.LayerTop
        LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
            | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

        flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
        color: "transparent"
        width: Screen.width
        height: Math.max(1, Screen.height - root.restOrigin.y + root.headroom)
        visible: root.restOrigin.y >= 0 && root.restWidth > 0

        Item {
            x: root.restOrigin.x - root.sideRoom
            y: 0
            width: root.restWidth + 2 * root.sideRoom
            height: root.height + root.headroom

            Repeater {
                model: tasksModel

                delegate: Item {
                    id: task

                    required property int index
                    required property var model

                    readonly property real restCenter: (index + 0.5) * root.slot
                    readonly property real offset: restCenter - root.pointerX
                    readonly property real iconScale: Magnifier.scaleAt(offset, root.radius, root.peak, root.strength)

                    x: root.sideRoom + restCenter
                        + Magnifier.displacementAt(offset, root.radius, root.peak, root.strength) - width / 2
                    width: root.slot
                    height: parent.height

                    Kirigami.Icon {
                        id: icon
                        source: task.model.decoration
                        width: root.iconSize
                        height: root.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.iconBottomMargin
                        transform: Scale {
                            origin.x: icon.width / 2
                            origin.y: icon.height
                            xScale: task.iconScale
                            yScale: task.iconScale
                        }
                    }

                    Rectangle {
                        visible: task.model.IsWindow === true
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Kirigami.Theme.textColor
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.max(1, root.iconBottomMargin / 2 - 2.5)
                    }
                }
            }
        }
    }

    // Spike: follow the panel by polling. Logs once per change for the journal.
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (root.strength > 0)
                return;
            const origin = root.mapToGlobal(root.restStart, 0);
            const x = Math.round(origin.x);
            const y = Math.round(origin.y);
            if (x !== root.restOrigin.x || y !== root.restOrigin.y) {
                root.restOrigin = Qt.point(x, y);
                const rounded = root.restOrigin;
                console.log("dockglass: panel item", root.width, "x", root.height, "at", rounded,
                            "overlay", overlay.width, "x", overlay.height, "screen", overlay.Screen.height);
            }
        }
    }
}
