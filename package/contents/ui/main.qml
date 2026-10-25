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
import org.kde.taskmanager as TaskManager

import "magnifier.mjs" as Magnifier
import "places.mjs" as Places
import "stackLayout.mjs" as StackLayout

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
    // The bubble with the name of the icon under the pointer, above it.
    readonly property int labelHeight: 26
    readonly property int labelGap: 6
    // Room the overlay adds around the panel: icons spread up to
    // (peak - 1) * radius / 2 past each end, grow (peak - 1) * iconSize up,
    // can be mid-hop on top of that, and carry the name bubble.
    readonly property real sideRoom: Math.ceil((peak - 1) * radius / 2)
    readonly property real headroom: Math.ceil((peak - 1) * iconSize) + bounceHeight + labelGap + labelHeight

    property real pointerX: 0
    property bool pointerSeeded: false
    property real strength: 0
    // Over the pill as it is drawn now, not over the room around it.
    readonly property bool active: hover.hovered && pointerInPanel >= pillLeft && pointerInPanel <= pillRight
    // The pointer in the panel window. It comes from the window position,
    // which stays right while this item moves under a still pointer.
    readonly property real pointerInPanel: hover.point.scenePosition.x
    // The pointer on the rest layout while it is over the dock, or -1: the
    // icon whose rest slot holds it is the one drawn under it.
    readonly property real hoverX: active && restLeft >= 0 ? pointerInPanel - restLeft : -1
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
    // Where the rest layout's left edge is in the panel window. The rest
    // layout is centered in the panel, give or take the panel's own margins
    // (restOffset, read once at rest), so it follows a resize at once, even
    // while the pointer is over the dock: the panel grows when an app is
    // pinned by dropping it there. It does not need the pill, so the icons
    // show even if a Plasma version lays out its panel differently.
    property real restOffset: NaN
    readonly property real restLeft: panelWidth < 0 || isNaN(restOffset) ? -1
        : Math.round((panelWidth - restWidth) / 2 + restOffset)
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
        : (pillLeft + pillRight) / 2 - panelWidth / 2
    // Where the rest layout starts in this item.
    readonly property real restStart: (width - restWidth) / 2 - contentShift
    // Plasma's panel background, which KWin blurs, and where it goes in its
    // parent's coordinates. Found once the panel is up (findPill()); without
    // it the pill keeps Plasma's own size and place.
    property Item pill: null
    // Plasma's Panel.qml root, and a hover handler on it.
    property Item panelRoot: null
    property var panelHover: null
    // Plasma hides the dock's panel always (Auto hide, 1) or while a window
    // touches it (Dodge windows, 2), until the pointer pushes against the
    // screen edge and stays on the panel. The icons, in their own window,
    // go with it. While the stack is open, the panel stays.
    readonly property bool panelHidden: (panelVisibilityMode === 1
            || (panelVisibilityMode === 2 && (panelRoot?.touchingWindow ?? false)))
        && !(panelHover?.hovered ?? false) && !stackLoader.active
    property rect pillGeometry: Qt.rect(0, 0, 0, 0)
    property int pillSearches: 0
    // The panel window's place, width and visibility mode, as plain numbers
    // that keep their last values. When Plasma tears the panel down,
    // Window.window turns null first, and bindings on it reshaped and hid the
    // overlay window mid-teardown, which crashed plasmashell.
    property real panelX: 0
    property real panelY: 0
    property real panelWidth: -1
    property int panelVisibilityMode: 0

    function readPanelWindow() {
        const window = Window.window;
        if (!window)
            return;
        panelX = window.x;
        panelY = window.y;
        panelWidth = window.width;
        panelVisibilityMode = window.visibilityMode ?? 0;
    }

    Window.onWindowChanged: readPanelWindow()
    Component.onCompleted: readPanelWindow()

    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true

        function onXChanged() {
            root.readPanelWindow();
        }
        function onYChanged() {
            root.readPanelWindow();
        }
        function onWidthChanged() {
            root.readPanelWindow();
        }
        function onVisibilityModeChanged() {
            root.readPanelWindow();
        }
    }

    // Where the rest layout sits on screen: the panel window's position, which
    // Plasma sets, plus where the rest layout is in it. This item's top in
    // the window does not change while magnifying, so it is read once.
    property real restTopInWindow: -1
    readonly property point restOrigin: restLeft < 0 || restTopInWindow < 0
        ? Qt.point(-1, -1) : Qt.point(panelX + restLeft, panelY + restTopInWindow)
    property point pendingRest: Qt.point(-1, -1)

    onRestOriginChanged: {
        console.log("dockglass: rest layout at", restOrigin, "width", restWidth);
        if (!overlayStacked && restOrigin.y >= 0) {
            overlayStacked = true;
            firstRestack.start();
        }
    }
    // The overlay window is shown as soon as it loads, which can be before
    // Plasma shows the panels, and then the panels sit over it. Once the dock
    // has its place, a fresh copy goes on top; and again whenever Plasma
    // shows an auto-hidden panel, in case it went over the icons.
    property bool overlayStacked: false
    onPanelHiddenChanged: {
        if (!panelHidden)
            restackOverlay();
    }

    Timer {
        id: firstRestack
        interval: 300
        onTriggered: root.restackOverlay()
    }
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
        if (!panelRoot) {
            panelRoot = view;
            // Hovering anywhere on the panel window, its margins included:
            // after a push against the screen edge the pointer sits there.
            panelHover = Qt.createQmlObject("import QtQuick; HoverHandler {}", view, "panelHover");
        }
        for (const child of view.children) {
            if (child.imagePath === "widgets/panel-background" && child.anchors.fill)
                return child.anchors.fill;
        }
        return null;
    }

    function layoutPill() {
        if (!pill) {
            pill = findPill();
            // Said once, after five seconds of looking.
            if (!pill && ++pillSearches === 20)
                console.warn("dockglass: Plasma's panel background was not found;",
                             "the pill will not follow the icons");
        }
        if (!pill || restLeft < 0)
            return;
        const left = pill.parent.mapFromItem(null, pillLeft, 0).x;
        pillGeometry = Qt.rect(left, 0, pillRight - pillLeft, 0);
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
    // Keeps an auto-hiding panel shown while the stack is open.
    Plasmoid.status: stackLoader.active ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
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

    // The Files stack. A click on the file manager while it has no windows
    // fans out the places Dolphin shows, read from its bookmarks, with an
    // entry on top that opens the file manager itself, like the original.
    readonly property string placesFile: "$HOME/.local/share/user-places.xbel"

    function toggleStack(row) {
        if (stackLoader.active) {
            stackLoader.item.close();
            return;
        }
        stackRow = row;
        placesReader.connectSource("cat \"" + placesFile + "\"");
    }

    function openStack(xbel) {
        const row = stackRow;
        const index = tasksModel.makeModelIndex(row);
        const appName = tasksModel.data(index, TaskManager.AbstractTasksModel.AppName);
        // System places carry English titles that KIO translates.
        const places = Places.parsePlaces(xbel).slice(0, StackLayout.MAX_FAN_ITEMS - 1).map(place => ({
            name: place.system ? i18ndc("kio6", "KFile System Bookmarks", place.name) : place.name,
            icon: place.icon,
            action: () => Qt.openUrlExternally(place.url),
        }));
        places.push({
            // Translated through Dolphin's own "Open %1".
            name: i18ndc("dolphin", "@action:inmenu Tools", "Open %1", appName),
            icon: "folder-open",
            action: () => {
                tasksModel.requestActivate(index);
                startBounce(tasksModel.data(index, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon).toString());
            },
        });
        // In the stack's window, which covers the dock's screen.
        stackOrigin = Qt.point(restOrigin.x + taskLeft(row) + slot / 2 - Screen.virtualX,
                               restOrigin.y + height - iconBottomMargin - iconSize - Screen.virtualY);
        stackEntries = places;
        stackLoader.active = true;
    }

    property int stackRow: -1
    property point stackOrigin
    property var stackEntries: []

    P5Support.DataSource {
        id: placesReader
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.openStack(data.stdout ?? "");
        }
    }

    Loader {
        id: stackLoader
        active: false
        sourceComponent: Stack {
            screen: Qt.application.screens.find(screen => screen.name === root.Screen.name) ?? null
            origin: root.stackOrigin
            entries: root.stackEntries
            visible: true
            onClosed: stackLoader.active = false
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
                    if (hit.index === root.fileManagerRow && hit.model.IsWindow !== true) {
                        root.toggleStack(hit.index);
                        return;
                    }
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

    // The icons are drawn in an Overlay window. Panels share its layer, and
    // KWin puts a raised panel over it, which hid the icons under the pill.
    // A newly shown window goes on top of its layer, so restackOverlay()
    // shows a second copy and drops the first once the copy has drawn.
    property Loader overlayFront: overlayA
    // The copy being shown, until it has drawn its first frame.
    property Loader overlayBack: null

    function restackOverlay() {
        if (overlayBack)
            return;
        overlayBack = overlayFront === overlayA ? overlayB : overlayA;
        overlayBack.active = true;
    }

    function overlayDrawn(loader) {
        if (loader !== overlayBack)
            return;
        overlayFront.active = false;
        overlayFront = loader;
        overlayBack = null;
    }

    Loader {
        id: overlayA
        active: true
        sourceComponent: overlayComponent
        onLoaded: item.frameSwapped.connect(() => root.overlayDrawn(overlayA))
    }

    Loader {
        id: overlayB
        active: false
        sourceComponent: overlayComponent
        onLoaded: item.frameSwapped.connect(() => root.overlayDrawn(overlayB))
    }

    Component {
        id: overlayComponent

        Overlay {
            dock: root
            tasks: tasksModel
        }
    }

    // KWin raises the panel when it is activated, for one.
    Connections {
        target: root.Window.window

        function onActiveChanged() {
            root.restackOverlay();
        }
    }

    // The task under a point of the rest layout, or -1.
    function rowAt(x) {
        for (let row = 0; row < tasksModel.count; ++row) {
            const left = taskLeft(row);
            if (x >= left && x < left + slot)
                return row;
        }
        return -1;
    }

    // A launcher URL by its desktop file name, so applications:, file: and
    // the URLs TasksModel stores compare equal.
    function desktopName(url) {
        const text = url.toString();
        return text.substring(Math.max(text.lastIndexOf("/"), text.lastIndexOf(":")) + 1);
    }

    // Pins an app, or moves it if it is pinned already, to an app slot. The
    // order is set through the launcher list, which the dock's rows follow
    // and which is what gets saved; TasksModel.move() moved rows by one less
    // than asked when running apps sat out of the list's order.
    function pinApp(url, appSlot) {
        tasksModel.requestAddLauncher(url);
        const list = tasksModel.launcherList.slice();
        const from = list.findIndex(launcher => desktopName(launcher) === desktopName(url));
        if (from === -1)
            return;
        const [launcher] = list.splice(from, 1);
        // Before the appSlot-th app, skipping the file manager, which the dock
        // shows in its system group.
        let to = 0;
        for (let apps = 0; to < list.length; ++to) {
            if (list[to] === "preferred://filemanager")
                continue;
            if (apps++ === appSlot)
                break;
        }
        list.splice(to, 0, launcher);
        tasksModel.launcherList = list;
    }

    // Apps dropped on the dock are pinned at the slot they land on, and files
    // dropped on an app open with it, like Plasma's task manager. Without
    // this, Plasma added an icon widget to the panel next to the dock.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]

        onDropped: drop => {
            const x = drop.x - root.restStart;
            const apps = drop.urls.filter(url => {
                const text = url.toString();
                return text.startsWith("applications:") || text.endsWith(".desktop");
            });
            if (apps.length > 0) {
                const appSlot = Math.max(0, Math.min(root.appSlots, Math.round(x / root.slot)));
                apps.forEach((url, i) => root.pinApp(url, appSlot + i));
            } else {
                const row = root.rowAt(x);
                if (row !== -1)
                    tasksModel.requestOpenUrls(tasksModel.makeModelIndex(row), drop.urls);
            }
            drop.accept(Qt.CopyAction);
            root.restackOverlay();
        }
    }

    // Finds the pill, and reads the panel's margins at rest, once two readings
    // agree, since Plasma takes a few frames to lay out the panel.
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            root.layoutPill();
            if (!root.Window.window || root.panelWidth < 0 || root.strength > 0)
                return;
            const rest = root.mapToItem(null, root.restStart, 0);
            const reading = Qt.point(Math.round(rest.x - (root.panelWidth - root.restWidth) / 2),
                                     Math.round(root.mapToItem(null, 0, 0).y));
            const settled = reading.x === root.pendingRest.x && reading.y === root.pendingRest.y;
            root.pendingRest = reading;
            if (!settled)
                return;
            if (reading.x !== root.restOffset)
                root.restOffset = reading.x;
            if (reading.y !== root.restTopInWindow)
                root.restTopInWindow = reading.y;
        }
    }
}
