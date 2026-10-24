// SPDX-License-Identifier: GPL-3.0-or-later
// Spike 2 (S3 in odd/tasks/plasma-port.md): the panel keeps Plasma's own
// background, so the panel itself is the pill and KWin blurs it. The icons
// are drawn in an input-transparent overlay window above the panel, which
// has room for them to grow past the panel's height. Hover and clicks still
// land on the panel at the rest layout: the spread keeps the point under the
// pointer fixed, so the icon drawn under the pointer is the one whose rest
// slot holds the pointer. Plasma moves and resizes a panel in separate
// frames, so a panel that followed the spread would jitter. Instead the panel
// keeps the width of the widest spread, and the pill, Plasma's panel
// background, is moved and sized inside it every frame to hug the icons, on
// each side as far as they spread, like the original.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.private.desktopcontainment.folder as Folder
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
    // Launch bounce, as in the original: a 22 px hop, eased out on the way up
    // and in on the way down, repeated until the app shows a window or 10 s.
    readonly property int bounceHeight: 22
    readonly property int bounceStepMs: 260
    readonly property int bounceTimeoutMs: 10000
    // Room the overlay adds around the panel: icons spread up to
    // (peak - 1) * radius / 2 past each end, grow (peak - 1) * iconSize up and
    // can be mid-hop on top of that.
    readonly property real sideRoom: Math.ceil((peak - 1) * radius / 2)
    readonly property real headroom: Math.ceil((peak - 1) * iconSize) + bounceHeight

    property real pointerX: 0
    property bool pointerSeeded: false
    property real strength: 0
    // Over the pill as it is drawn now, not over the room around it.
    readonly property bool active: hover.hovered && pointerInPanel >= pillLeft && pointerInPanel <= pillRight
    // The pointer in the panel's coordinates. It comes from the window
    // position, which stays right while this item moves under a still pointer.
    readonly property real pointerInPanel: pill ? pill.parent.mapFromItem(null, hover.point.scenePosition.x, 0).x : -1
    // The rest layout, left to right: apps, a separator, then the pinned
    // file manager (its row, or -1), the Trash and the app launcher, like
    // the folders and Trash of the macOS Dock.
    property int fileManagerRow: -1
    readonly property int separatorWidth: 24
    readonly property int appSlots: tasksModel.count - (fileManagerRow >= 0 ? 1 : 0)
    readonly property real separatorCenter: appSlots * slot + separatorWidth / 2
    readonly property real systemLeft: appSlots * slot + separatorWidth
    readonly property real trashLeft: systemLeft + (fileManagerRow >= 0 ? slot : 0)
    readonly property real launcherLeft: trashLeft + slot
    readonly property real restWidth: launcherLeft + slot
    // The most one end of the icons can spread: with the pointer at the other
    // end, at full strength. The panel keeps that much room on both sides.
    readonly property real maxGrow: Math.ceil(Magnifier.displacementAt(restWidth, radius, peak, 1))
    // Where the rest layout's left edge is in the panel (the parent of the
    // pill), read at rest. The panel window never moves or resizes, so this
    // stays put.
    property real restLeft: -1
    // How far the icons at each end spread; the left one is negative.
    readonly property real spreadLeft: Magnifier.displacementAt(-pointerX, radius, peak, strength)
    readonly property real spreadRight: Magnifier.displacementAt(restWidth - pointerX, radius, peak, strength)
    // The pill's ends in the panel: the rest layout plus padding, pushed out
    // by the spread at each end.
    readonly property int pillPadding: 8
    readonly property real pillLeft: Math.round(restLeft - pillPadding + spreadLeft)
    readonly property real pillRight: Math.round(restLeft + restWidth + pillPadding + spreadRight)
    // Panel.qml centers its content on the pill, whose own place is centered
    // in the panel, so moving the pill's center moves this item by as much.
    // The rest layout moves back by that, so it stays put on screen.
    readonly property real contentShift: restLeft < 0 || !pill ? 0
        : (pillLeft + pillRight) / 2 - pill.parent.width / 2
    // Where the rest layout starts in this item.
    readonly property real restStart: (width - restWidth) / 2 - contentShift
    // Plasma's panel background, which KWin blurs, and where it goes in its
    // parent's coordinates. Found once the panel is up (findPill()).
    property Item pill: null
    property rect pillGeometry: Qt.rect(0, 0, 0, 0)
    // Where the rest layout sits on screen. Wayland only tells us by mapping,
    // so the spike polls it, only at rest and only once two readings agree.
    property point restOrigin: Qt.point(-1, -1)
    property point pendingOrigin: Qt.point(-1, -1)
    // Launches still bouncing, as launcher URL -> start time in ms. Replaced
    // as a whole on every change, so bindings that read it update.
    property var bouncing: ({})
    // The task the context menu was opened for: its row, launcher URL and
    // whether it has windows and is pinned.
    property var menuTask: null

    // Where a task's slot starts in the rest layout.
    function taskLeft(row) {
        if (row === fileManagerRow)
            return systemLeft;
        return (fileManagerRow >= 0 && row > fileManagerRow ? row - 1 : row) * slot;
    }

    // Launchers come first and in order, so a launcher's position is its row.
    // launcherPosition() resolves preferred:// URLs in the list but not in its
    // argument, so the preferred file manager is looked up by hand.
    function updateFileManagerRow() {
        const preferred = tasksModel.launcherList.indexOf("preferred://filemanager");
        fileManagerRow = preferred !== -1 ? preferred
            : tasksModel.launcherPosition("applications:org.kde.dolphin.desktop");
    }

    function startBounce(url) {
        bouncing = Object.assign({}, bouncing, {[url]: Date.now()});
    }

    function stopBounce(url) {
        if (!(url in bouncing))
            return;
        const next = Object.assign({}, bouncing);
        delete next[url];
        bouncing = next;
    }

    // Plasma 6's Panel.qml draws the background as a FrameSvgItem of
    // widgets/panel-background (floatingTranslucentItem); its other background
    // items fill that one. Its root is the item that has panelMask.
    function findPill() {
        let view = root.parent;
        while (view && view.panelMask === undefined)
            view = view.parent;
        if (!view)
            return null;
        for (const child of view.children) {
            if (child.imagePath === "widgets/panel-background" && child.anchors.fill)
                return child.anchors.fill;
        }
        return null;
    }

    function layoutPill() {
        if (!pill)
            pill = findPill();
        if (!pill || restLeft < 0)
            return;
        pillGeometry = Qt.rect(pillLeft, 0, pillRight - pillLeft, 0);
    }

    onPillLeftChanged: layoutPill()
    onPillRightChanged: layoutPill()

    function openTaskMenu(item, row, model) {
        const url = model.LauncherUrlWithoutIcon;
        menuTask = {
            row,
            url,
            hasWindow: model.IsWindow === true,
            pinned: tasksModel.launcherPosition(url) !== -1,
        };
        taskMenu.visualParent = item;
        taskMenu.openRelative();
    }

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Layout.preferredWidth: restWidth + 2 * maxGrow
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
        // Pinned apps live in the widget's config, so pinning from the menu
        // survives a restart.
        Component.onCompleted: launcherList = Plasmoid.configuration.launchers
        onLauncherListChanged: {
            Plasmoid.configuration.launchers = launcherList;
            root.updateFileManagerRow();
        }
        onCountChanged: root.updateFileManagerRow()
    }

    // Whether the Trash has anything, for its icon. FolderModel has no count
    // property, so its rows are counted when they change.
    property bool trashFull: false

    Folder.FolderModel {
        id: trashModel
        url: "trash:/"
        usedByContainment: false

        function update() {
            root.trashFull = rowCount() > 0;
        }

        onListingCompleted: update()
        onRowsInserted: update()
        onRowsRemoved: update()
        onModelReset: update()
    }

    // Runs a command, here to ask Plasma for its launcher menu.
    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: sourceName => disconnectSource(sourceName)

        function run(command) {
            connectSource(command);
        }
    }

    PlasmaExtras.Menu {
        id: taskMenu

        placement: PlasmaExtras.Menu.TopPosedLeftAlignedPopup

        PlasmaExtras.MenuItem {
            text: i18n("New Window")
            icon: "window-new"
            visible: root.menuTask?.hasWindow === true
            onClicked: tasksModel.requestNewInstance(tasksModel.makeModelIndex(root.menuTask.row))
        }
        PlasmaExtras.MenuItem {
            text: root.menuTask?.pinned ? i18n("Unpin from Dock") : i18n("Pin to Dock")
            icon: root.menuTask?.pinned ? "window-unpin" : "window-pin"
            onClicked: {
                if (root.menuTask.pinned)
                    tasksModel.requestRemoveLauncher(root.menuTask.url);
                else
                    tasksModel.requestAddLauncher(root.menuTask.url);
            }
        }
        PlasmaExtras.MenuItem {
            separator: true
            visible: root.menuTask?.hasWindow === true
        }
        PlasmaExtras.MenuItem {
            text: i18n("Close")
            icon: "window-close"
            visible: root.menuTask?.hasWindow === true
            onClicked: tasksModel.requestClose(tasksModel.makeModelIndex(root.menuTask.row))
        }
    }

    // Ends bounces whose app never showed a window.
    Timer {
        interval: 500
        repeat: true
        running: Object.keys(root.bouncing).length > 0
        onTriggered: {
            const now = Date.now();
            for (const url in root.bouncing) {
                if (now - root.bouncing[url] > root.bounceTimeoutMs)
                    root.stopBounce(url);
            }
        }
    }

    HoverHandler {
        id: hover
    }

    // Drive the pill. When this widget goes away, the Bindings hand x and
    // width back to Panel.qml's own bindings.
    Binding {
        target: root.pill
        property: "x"
        value: root.pillGeometry.x
        when: root.pill !== null && root.pillGeometry.width > 0
    }
    Binding {
        target: root.pill
        property: "width"
        value: root.pillGeometry.width
        when: root.pill !== null && root.pillGeometry.width > 0
    }

    FrameAnimation {
        running: root.active || root.strength > 0
        onTriggered: {
            const dt = Math.min(frameTime * 1000, 50);
            if (root.active) {
                const target = root.pointerInPanel - root.restLeft;
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

            x: root.restStart + root.taskLeft(index)
            width: root.slot
            height: root.height

            TapHandler {
                onTapped: {
                    const index = tasksModel.makeModelIndex(hit.index);
                    if (hit.model.IsActive === true)
                        tasksModel.requestToggleMinimized(index);
                    else
                        tasksModel.requestActivate(index);
                    if (hit.model.IsWindow !== true)
                        root.startBounce(hit.model.LauncherUrlWithoutIcon.toString());
                }
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                // Grab the press, so the panel does not open its own menu, and
                // open ours once the grab is released, as Plasma's task
                // manager does.
                gesturePolicy: TapHandler.WithinBounds
                onPressedChanged: {
                    if (pressed)
                        Qt.callLater(root.openTaskMenu, hit, hit.index, hit.model);
                }
            }

            // Where KWin minimizes the app's windows to and restores them
            // from: the icon at rest.
            function publishGeometry() {
                const origin = mapToGlobal(0, 0);
                tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(index),
                    Qt.rect(Math.round(origin.x), Math.round(origin.y), width, height), hit);
            }

            onIndexChanged: publishGeometry()
            Component.onCompleted: publishGeometry()

            Connections {
                target: root

                function onRestOriginChanged() {
                    hit.publishGeometry();
                }
            }
        }
    }

    Item {
        x: root.restStart + root.trashLeft
        width: root.slot
        height: root.height

        TapHandler {
            onTapped: Qt.openUrlExternally("trash:/")
        }
    }

    Item {
        x: root.restStart + root.launcherLeft
        width: root.slot
        height: root.height

        TapHandler {
            onTapped: executable.run("dbus-send --session --type=method_call --dest=org.kde.plasmashell"
                + " /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu")
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

                delegate: DockIcon {
                    id: task

                    dock: root

                    required property int index
                    required property var model

                    restCenter: root.taskLeft(index) + root.slot / 2
                    source: model.decoration
                    running: model.IsWindow === true

                    readonly property string url: model.LauncherUrlWithoutIcon.toString()
                    // The launcher and the app's window rows share the URL, and
                    // a launch in place swaps one for the other.
                    readonly property bool bouncing: url in root.bouncing && model.IsWindow !== true

                    onBouncingChanged: {
                        if (!bouncing)
                            root.stopBounce(url);
                    }
                    // The app's window arrives as a new row, whose bouncing
                    // starts false and never changes, so end the bounce here.
                    Component.onCompleted: {
                        if (model.IsWindow === true)
                            root.stopBounce(url);
                    }

                    SequentialAnimation on hop {
                        running: task.bouncing
                        loops: Animation.Infinite
                        alwaysRunToEnd: true

                        NumberAnimation {
                            to: root.bounceHeight
                            duration: root.bounceStepMs
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            to: 0
                            duration: root.bounceStepMs
                            easing.type: Easing.InQuad
                        }
                    }
                }
            }

            // The separator moves with the spread but does not grow.
            Rectangle {
                width: 1
                height: Math.round(root.height * 0.6)
                x: root.sideRoom + root.separatorCenter - width / 2
                    + Magnifier.displacementAt(root.separatorCenter - root.pointerX, root.radius, root.peak,
                                               root.strength)
                y: parent.height - root.height + (root.height - height) / 2
                color: Qt.rgba(1, 1, 1, 0.35)
            }

            DockIcon {
                dock: root
                restCenter: root.trashLeft + root.slot / 2
                source: root.trashFull ? "user-trash-full" : "user-trash"
            }

            DockIcon {
                dock: root
                restCenter: root.launcherLeft + root.slot / 2
                source: "start-here-kde"
            }
        }
    }

    // Spike: follow the panel by polling, at rest and once two readings agree.
    // Logs once per change for the journal.
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            root.layoutPill();
            if (!root.pill || (root.strength > 0 && root.restLeft >= 0))
                return;
            const origin = root.mapToGlobal(root.restStart, 0);
            const x = Math.round(origin.x);
            const y = Math.round(origin.y);
            const settled = x === root.pendingOrigin.x && y === root.pendingOrigin.y;
            root.pendingOrigin = Qt.point(x, y);
            if (!settled)
                return;
            root.restLeft = Math.round(root.mapToItem(root.pill.parent, root.restStart, 0).x);
            if (x !== root.restOrigin.x || y !== root.restOrigin.y) {
                root.restOrigin = Qt.point(x, y);
                const rounded = root.restOrigin;
                console.log("dockglass: panel item", root.width, "x", root.height, "at", rounded,
                            "overlay", overlay.width, "x", overlay.height, "screen", overlay.Screen.height);
            }
        }
    }
}
