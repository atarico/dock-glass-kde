// SPDX-License-Identifier: GPL-3.0-or-later
// Spike (S3 in odd/tasks/plasma-port.md): a task strip that magnifies like
// the macOS Dock, drawn on our own glass pill inside a tall panel whose own
// background is hidden. The extra panel height above the pill is headroom
// for the magnified icons, which cannot draw outside the panel surface.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

import "magnifier.mjs" as Magnifier

PlasmoidItem {
    id: root

    readonly property int iconSize: 48
    readonly property int slot: 60
    readonly property int pillPadding: 8
    readonly property int pillHeight: iconSize + 2 * pillPadding
    readonly property real peak: 1.4
    readonly property real radius: 3 * slot
    readonly property int pointerSmoothingMs: 40
    readonly property int strengthSmoothingMs: 80
    // The pill widens by at most (peak - 1) * radius / 2 on each side.
    readonly property real sideRoom: Math.ceil((peak - 1) * radius / 2)
    readonly property real restStart: sideRoom
    readonly property real restEnd: sideRoom + tasksModel.count * slot

    property real pointerX: 0
    property bool pointerSeeded: false
    property real strength: 0

    readonly property bool active: hover.hovered
        && hover.point.position.x >= pill.x
        && hover.point.position.x <= pill.x + pill.width
        && hover.point.position.y >= height - pillHeight - iconSize * (peak - 1)

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Layout.preferredWidth: restEnd + sideRoom
    Layout.minimumWidth: Layout.preferredWidth
    Layout.fillHeight: true

    // Hide the panel's own background, so the only visible shape is our pill.
    Component.onCompleted: {
        if (Plasmoid.containment)
            Plasmoid.containment.backgroundHints = PlasmaCore.Types.NoBackground;
    }

    TaskManager.TasksModel {
        id: tasksModel
        groupMode: TaskManager.TasksModel.GroupApplications
        sortMode: TaskManager.TasksModel.SortManual
        separateLaunchers: false
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
                const target = hover.point.position.x;
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

    Rectangle {
        id: pill
        readonly property real start: root.restStart
            + Magnifier.displacementAt(root.restStart - root.pointerX, root.radius, root.peak, root.strength)
        readonly property real end: root.restEnd
            + Magnifier.displacementAt(root.restEnd - root.pointerX, root.radius, root.peak, root.strength)

        x: start
        width: end - start
        height: root.pillHeight
        anchors.bottom: parent.bottom
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g,
                       Kirigami.Theme.backgroundColor.b, 0.55)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.28)
    }

    Repeater {
        model: tasksModel

        delegate: Item {
            id: task

            required property int index
            required property var model

            readonly property real restCenter: root.restStart + (index + 0.5) * root.slot
            readonly property real offset: restCenter - root.pointerX
            readonly property real iconScale: Magnifier.scaleAt(offset, root.radius, root.peak, root.strength)

            x: restCenter + Magnifier.displacementAt(offset, root.radius, root.peak, root.strength) - width / 2
            width: root.slot
            height: root.pillHeight + root.iconSize * (root.peak - 1)
            anchors.bottom: parent.bottom

            Kirigami.Icon {
                id: icon
                source: task.model.decoration
                width: root.iconSize
                height: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.pillPadding
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
                anchors.bottomMargin: 1
            }

            TapHandler {
                onTapped: {
                    const index = tasksModel.makeModelIndex(task.index);
                    if (task.model.IsActive === true)
                        tasksModel.requestToggleMinimized(index);
                    else
                        tasksModel.requestActivate(index);
                }
            }
        }
    }
}
