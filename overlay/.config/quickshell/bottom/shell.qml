import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    // ── Dismiss overlay window ─────────────────────────────────────────────────
    // Anchored to top only — covers everything ABOVE the main panel (300 px).
    // This prevents the overlay from overlapping the context menu or bar buttons,
    // eliminating the same-layer surface conflict that made menu items unclickable.

    PanelWindow {
        visible: root.activeTid !== ""
        color: "transparent"
        exclusiveZone: 0
        implicitHeight: (screen?.height ?? 1080) - root.implicitHeight
        anchors { top: true; left: true; right: true }

        MouseArea {
            anchors.fill: parent
            onClicked: root.activeTid = ""
        }
    }

    // ── Main Panel ────────────────────────────────────────────────────────────

    PanelWindow {
        id: root

        // Window is taller than the visible bar so context menus can overflow upward.
        // The Wayland input region is restricted to the bar only when no menu is open,
        // so windows above the bar remain clickable without any surface resize.
        implicitHeight: barHeight + 240
        mask: Region {
            x: 0
            y: root.activeTid !== "" ? 0 : (root.implicitHeight - root.barHeight)
            width: root.width
            height: root.activeTid !== "" ? root.implicitHeight : root.barHeight
        }
        exclusiveZone: barHeight + barTopMargin
        color: "transparent"

        anchors {
            bottom: true
            left: true
            right: true
        }

        // ── Constants ─────────────────────────────────────────────────────────

        readonly property int barHeight:          55
        readonly property int barTopMargin:         0
        readonly property int barMargin:           0
        readonly property int barRadius:           0
        readonly property int sideMargin:          20
        readonly property int sectionSpacing:     10
        readonly property int actionButtonSize:   36
        readonly property int iconSize:           Math.round(actionButtonSize * 0.67)
        readonly property int buttonRadius:         6
        readonly property int taskSpacing:         4
        readonly property int taskMaxButtonWidth: 150
        readonly property int taskMinButtonWidth:  40
        readonly property int taskIconSize:       18

        // ── Color Palette ─────────────────────────────────────────────────────

        readonly property color clrBarBg:      Qt.rgba(0.00, 0.00, 0.00, 0.85)
        readonly property color clrBtnDefault: Qt.rgba(1.00, 1.00, 1.00, 0.07)
        readonly property color clrBtnHover:   Qt.rgba(1.00, 1.00, 1.00, 0.15)
        readonly property color clrBtnActive:  Qt.rgba(1.00, 1.00, 1.00, 0.25)
        readonly property color clrDivider:    Qt.rgba(1.00, 1.00, 1.00, 0.20)
        readonly property color clrTextFull:   "#ffffff"
        readonly property color clrTextDim:    Qt.rgba(1.00, 1.00, 1.00, 0.75)
        readonly property color clrTextMuted:  Qt.rgba(1.00, 1.00, 1.00, 0.60)

        // ── State ─────────────────────────────────────────────────────────────

        // tid of the task whose context menu is open; "" = none
        property string activeTid: ""

        // Stable string tid → ToplevelIface; survives ListModel reorders
        property var tasksMap: ({})

        // Show-desktop toggle state
        property bool showDesktopActive: false
        property var _savedMinStates: []
        property var _lastActiveToplevel: null

        // Monotonic counter for collision-free tid generation
        property int _tidSeq: 0

        // Wayfire IPC: mevcut çalışma alanındaki pencereler (app_id\ttitle listesi).
        // null = henüz sorgulanmadı (hepsini göster), [] = boş, [...] = sadece bunları göster
        property var _workspaceWindowKeys: null
        property bool _runWorkspaceQuery: false
        property string _workspaceScriptPath: ""

        // ── Helpers ───────────────────────────────────────────────────────────

        function closeLauncher() {
            launcherProcess.running = false
            root.activeTid = ""
        }

        Component.onCompleted: {
            const p = Qt.resolvedUrl("wayfire-workspace-windows").toString().replace("file://", "")
            if (p) {
                root._workspaceScriptPath = p
                root._runWorkspaceQuery = true  // ilk workspace listesini hemen al
            }
        }

        // ── Launcher Process ──────────────────────────────────────────────────

        Process {
            id: launcherProcess
            command: ["/usr/bin/quickshell", "-c", "launcher"]
        }

        // ── Drag State ────────────────────────────────────────────────────────

        QtObject {
            id: dragState
            property bool active: false
            property string tid: ""
        }

        // ── Task Model ────────────────────────────────────────────────────────

        ListModel { id: tasksModel }

        // Desktop entry lookup tablosu: launcher gibi tüm kayıtları indeksler.
        // heuristicLookup bazen appId'yi eşleştiremez (case, Flatpak, WM class farkları);
        // bu map fallback olarak kullanılır.
        property var _entryById: ({})

        function _rebuildEntryMap() {
            const m = {}
            for (let i = 0; i < entryBridge.count; i++) {
                const e = entryBridge.itemAt(i)?.modelData
                if (!e) continue
                const id = e.id || ""
                if (id) {
                    m[id.toLowerCase()] = e
                    const parts = id.split(".")
                    if (parts.length > 1) {
                        const last = parts[parts.length - 1].toLowerCase()
                        if (!m[last]) m[last] = e
                        const noHyphen = last.replace(/-/g, "").replace(/_/g, "").replace(/\s/g, "")
                        if (noHyphen && !m[noHyphen]) m[noHyphen] = e
                    }
                }
                if (e.wmClass) m[e.wmClass.toLowerCase()] = e
            }
            root._entryById = m
        }

        function lookupEntry(appId) {
            if (!appId) return null
            const entry = DesktopEntries.heuristicLookup(appId)
            if (entry) return entry
            const lower = appId.toLowerCase()
            const lastPart = lower.split(".").pop()
            const normalized = lastPart.replace(/-/g, "").replace(/_/g, "").replace(/\s/g, "")
            return root._entryById[lower]
                || root._entryById[lastPart]
                || (normalized !== lastPart ? root._entryById[normalized] : null)
                || root._entryById[lower.replace(/\s/g, "")]
                || null
        }

        // Ana süreçte XDG_DATA_DIRS Flatpak yollarını içermeyebilir; iconPath boş döner.
        // Launcher ile aynı davranış için mutlak yol döndür (file:// yok — Qt Image bazen file:// ile mor kare veriyor).
        function flatpakIconPath(iconName) {
            if (!iconName || iconName.indexOf(".") < 0) return ""
            const home = Quickshell.env("HOME") || ""
            if (!home || !home.startsWith("/")) return ""
            const path = home + "/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps/" + iconName + ".svg"
            return path
        }
        function flatpakIconPath48(iconName) {
            if (!iconName || iconName.indexOf(".") < 0) return ""
            const home = Quickshell.env("HOME") || ""
            if (!home || !home.startsWith("/")) return ""
            return home + "/.local/share/flatpak/exports/share/icons/hicolor/48x48/apps/" + iconName + ".png"
        }

        // ToplevelManager exposes a read-only C++ model. We observe it via a hidden
        // Repeater and reconcile our reorderable ListModel on every change.
        // Workspace değişiminde toplevel.screens güncellenir; bu tetiklenmeyebilir, Timer ile yenilenir.
        Item {
            visible: false

            // Desktop entry index (launcher'daki gibi tüm kayıtları izler)
            Repeater {
                id: entryBridge
                model: DesktopEntries.applications
                delegate: Item {
                    required property var modelData
                    visible: false; width: 0; height: 0
                }
                onCountChanged: Qt.callLater(root._rebuildEntryMap)
            }

            Repeater {
                id: bridge
                model: ToplevelManager.toplevels
                delegate: Item {
                    required property var modelData
                    visible: false; width: 0; height: 0
                }
                onCountChanged: Qt.callLater(root.syncTasks)
            }
            Timer {
                interval: 500
                running: true
                repeat: true
                onTriggered: {
                    Qt.callLater(root.syncTasks)
                    if (!root._runWorkspaceQuery && root._workspaceScriptPath)
                        root._runWorkspaceQuery = true
                }
            }

            // Workspace geçişinde aktif pencere değişir; hemen yenile (250ms beklemeden).
            Connections {
                target: ToplevelManager
                function onActiveToplevelChanged() {
                    if (root._workspaceScriptPath)
                        root._runWorkspaceQuery = true
                }
            }

            Process {
                id: workspaceScriptProcess
                running: root._runWorkspaceQuery && root._workspaceScriptPath !== ""
                // Rust binary: wayfire-workspace-windows (socket'i /tmp/wayfire-socket.$UID veya WAYFIRE_SOCKET'ten alır)
                command: [root._workspaceScriptPath]
                stdout: StdioCollector {
                    onStreamFinished: {
                        root._runWorkspaceQuery = false
                        const text = this.text || ""
                        if (text.indexOf("WAYFIRE_WORKSPACE_OK") < 0) return
                        let keys = text.split("\n")
                            .map(l => l.trim())
                            .filter(l => l !== "" && l !== "WAYFIRE_WORKSPACE_OK")
                            .map(l => {
                                const tab = l.indexOf("\t")
                                if (tab < 0) return { appId: l, title: "" }
                                return { appId: l.slice(0, tab), title: l.slice(tab + 1) }
                            })
                        root._workspaceWindowKeys = keys
                        Qt.callLater(root.syncTasks)
                    }
                }
            }
        }

        function buildLiveToplevels() {
            const all = []
            for (let i = 0; i < bridge.count; i++) {
                const tl = bridge.itemAt(i)?.modelData
                if (tl) all.push(tl)
            }

            // Wayfire'da toplevel.screens genelde workspace'e göre ayrışmaz (hepsi aynı output).
            // Sadece liste gerçekten daralıyorsa ekran filtresini kullan; yoksa IPC'ye güven.
            const active = ToplevelManager.activeToplevel
            let refScreens = (active && (active.screens ?? []).length > 0) ? (active.screens ?? []) : []
            if (refScreens.length === 0 && root.screen) refScreens = [root.screen]
            if (refScreens.length > 0) {
                const onScreen = all.filter(tl => {
                    const screens = tl.screens ?? []
                    return screens.length > 0 && screens.some(s => refScreens.indexOf(s) >= 0)
                })
                // Sadece gerçekten bir alt küme ise kullan (compositor workspace'e göre screens güncelliyorsa).
                if (onScreen.length > 0 && onScreen.length < all.length)
                    return onScreen
            }

            // Birincil kaynak: Wayfire IPC ile mevcut workspace pencereleri.
            // Script yoksa (null): sadece odaklı pencereyi göster; tüm liste diğer workspace'te de görünmesin.
            if (root._workspaceWindowKeys === null) {
                return active && all.includes(active) ? [active] : []
            }

            const matched = new Set()
            const result = []
            const quotaKeys = []

            for (const key of root._workspaceWindowKeys) {
                if (!key.title) {
                    quotaKeys.push(key)
                    continue
                }
                const tl = all.find(t =>
                    (t.appId || "").toLowerCase() === key.appId &&
                    (t.title || "").trim() === key.title &&
                    !matched.has(t)
                )
                if (tl) {
                    matched.add(tl)
                    result.push(tl)
                } else {
                    quotaKeys.push(key)
                }
            }

            const quota = {}
            for (const key of quotaKeys) {
                quota[key.appId] = (quota[key.appId] || 0) + 1
            }
            const used = {}
            for (const tl of all) {
                if (matched.has(tl)) continue
                const id = (tl.appId || "").toLowerCase()
                if (!quota[id]) continue
                if ((used[id] || 0) >= quota[id]) continue
                used[id] = (used[id] || 0) + 1
                matched.add(tl)
                result.push(tl)
            }

            // Script tüm pencereleri döndürdüyse (filtre başarısız): odaklı ile aynı ekranda olanları göster.
            if (result.length === all.length && all.length >= 2 && active) {
                const activeScreens = active.screens || []
                if (activeScreens.length > 0) {
                    const onSameScreen = all.filter(tl => {
                        const s = tl.screens || []
                        return s.length > 0 && s.some(sc => activeScreens.indexOf(sc) >= 0)
                    })
                    if (onSameScreen.length < all.length) return onSameScreen
                }
            }

            return result
        }

        function syncTasks() {
            const live = buildLiveToplevels()

            // Work on a local copy so QML sees a single reactive assignment at the end.
            const newMap = Object.assign({}, root.tasksMap)

            // Remove tasks whose toplevels have closed
            for (let i = tasksModel.count - 1; i >= 0; i--) {
                const tid = tasksModel.get(i).tid
                if (!newMap[tid] || !live.includes(newMap[tid])) {
                    delete newMap[tid]
                    tasksModel.remove(i)
                }
            }

            // Append newly opened toplevels — use a Set for O(n) lookup
            const tracked = new Set(Object.values(newMap))
            for (const tl of live) {
                if (!tracked.has(tl)) {
                    const tid = "t" + (++root._tidSeq)
                    newMap[tid] = tl
                    tasksModel.append({ tid })
                }
            }

            root.tasksMap = newMap
        }

        // Panel içindeki tüm boş alanlara tıklayınca menüyü ve launcher'ı kapat (en düşük z).
        MouseArea {
            anchors.fill: parent
            enabled: root.activeTid !== ""
            z: 0
            onClicked: closeLauncher()
        }

        // ── Top Shadow ────────────────────────────────────────────────────────

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: bar.top
            }
            height: 5
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
            }
        }

        // ── Bar Background ────────────────────────────────────────────────────

        Rectangle {
            id: bar
            height: root.barHeight
            radius: root.barRadius
            color: root.clrBarBg
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: root.barMargin
            }

            // Boş bar alanına tıklayınca menüyü ve launcher'ı kapat.
            // Bar'ın child'ı olduğundan leftSection/rightSection butonları
            // (sibling olarak üstte) tıklamaları önce alır.
            MouseArea {
                anchors.fill: parent
                enabled: root.activeTid !== "" || launcherProcess.running
                onClicked: closeLauncher()
            }
        }

        // ── Left Section: launcher → divider → task buttons ───────────────────

        Row {
            id: leftSection
            spacing: root.sectionSpacing
            anchors {
                left: bar.left
                leftMargin: root.sideMargin
                verticalCenter: bar.verticalCenter
            }

            BarButton {
                source: Qt.resolvedUrl("shipos.svg")
                active: launcherProcess.running
                onClicked: launcherProcess.running = !launcherProcess.running
            }

            Rectangle {
                width: 1; height: 24
                anchors.verticalCenter: parent.verticalCenter
                color: root.clrDivider
            }

            Item {
                id: taskBar
                height: root.actionButtonSize
                anchors.verticalCenter: parent.verticalCenter

                readonly property int count: tasksModel.count
                // leftSection içinde taskBar'dan önce gelen sabit genişlik:
                // launcher + row-spacing + divider(1) + row-spacing
                readonly property int leftPrefixWidth: root.actionButtonSize + root.sectionSpacing + 1 + root.sectionSpacing
                readonly property int available: Math.max(0, rightSection.x - leftSection.x - leftPrefixWidth)
                readonly property int buttonWidth: count > 0
                    ? Math.min(root.taskMaxButtonWidth,
                               Math.max(root.taskMinButtonWidth,
                                        Math.floor((available - root.taskSpacing * (count - 1)) / count)))
                    : 0

                width: count * buttonWidth + Math.max(0, count - 1) * root.taskSpacing

                Repeater {
                    model: tasksModel
                    delegate: TaskButton {}
                }
            }
        }

        // ── Right Section: clock → desktop button ─────────────────────────────

        Row {
            id: rightSection
            spacing: root.sectionSpacing
            anchors {
                right: bar.right
                rightMargin: root.sideMargin
                verticalCenter: bar.verticalCenter
            }

            // MouseArea positioner içinde fill anchor kullanamaz (binding loop → height sıfır).
            // Çözüm: Item sarmalayıcı + MouseArea overlay olarak.
            Item {
                width: clockCol.width
                height: clockCol.height
                anchors.verticalCenter: parent.verticalCenter

                Column {
                    id: clockCol
                    spacing: 0

                    Text {
                        id: clockLabel
                        color: root.clrTextFull
                        font.pixelSize: 16
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(new Date(), "hh:mm:ss")
                    }

                    Text {
                        id: dateLabel
                        color: root.clrTextMuted
                        font.pixelSize: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(new Date(), "dd MMM yyyy")
                    }

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        onTriggered: {
                            const now = new Date()
                            clockLabel.text = Qt.formatTime(now, "hh:mm:ss")
                            dateLabel.text  = Qt.formatDate(now, "dd MMM yyyy")
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: closeLauncher()
                }
            }

            BarButton {
                source: Qt.resolvedUrl("expo.svg")
                onClicked: {
                    root.closeLauncher()
                    const scriptPath = Qt.resolvedUrl("wayfire-ipc").toString().replace("file://", "");
                    Quickshell.execDetached([scriptPath, "expo/toggle"]);
                }
            }

            BarButton {
                source: Qt.resolvedUrl("desktop.svg")
                active: root.showDesktopActive
                onClicked: {
                    root.closeLauncher()
                    const toplevels = Object.values(root.tasksMap)
                    if (!root.showDesktopActive) {
                        root._lastActiveToplevel = toplevels.find(tl => tl.activated) ?? null
                        root._savedMinStates = toplevels.map(tl => ({ tl, min: tl.minimized }))
                        for (const tl of toplevels) tl.minimized = true
                        root.showDesktopActive = true
                    } else {
                        for (const item of root._savedMinStates) {
                            if (!item.min) item.tl.minimized = false
                        }
                        root._savedMinStates = []
                        root.showDesktopActive = false
                        if (root._lastActiveToplevel) {
                            root._lastActiveToplevel.activate()
                            root._lastActiveToplevel = null
                        }
                    }
                }
            }
        }

        // ── Inline Components ─────────────────────────────────────────────────

        // Generic icon button used in the launcher and desktop slots
        component BarButton: Rectangle {
            id: btn
            signal clicked()
            property alias source: icon.source
            property bool active: false

            width: root.actionButtonSize
            height: root.actionButtonSize
            radius: root.buttonRadius
            color: active ? root.clrBtnActive : (btnMouse.containsMouse ? root.clrBtnHover : root.clrBtnDefault)

            Behavior on color { ColorAnimation { duration: 150 } }

            Image {
                id: icon
                anchors.centerIn: parent
                width: root.iconSize; height: root.iconSize
                sourceSize: Qt.size(root.iconSize, root.iconSize)
                fillMode: Image.PreserveAspectFit
                opacity: btnMouse.containsMouse ? 1.0 : 0.85
                visible: status === Image.Ready
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: btn.clicked()
            }
        }

        // Single row item inside a context menu
        component MenuAction: Rectangle {
            id: action
            signal selected()
            property string label: ""
            property bool destructive: false

            width: parent.width
            height: 30
            radius: 4
            color: actionMouse.containsMouse
                ? (destructive ? Qt.rgba(1, 0, 0, 0.2) : Qt.rgba(1, 1, 1, 0.1))
                : "transparent"

            Text {
                anchors.centerIn: parent
                text: action.label
                font.pixelSize: 11
                font.bold: action.destructive
                color: action.destructive
                    ? (actionMouse.containsMouse ? "#ff5555" : "#ffaaaa")
                    : root.clrTextFull
            }

            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: action.selected()
            }
        }

        // Task button: Launcher'dan fark — launcher model=DesktopEntries.applications (doğrudan entry),
        // bottom model=ToplevelManager.toplevels (pencere); entry lookupEntry(toplevel.appId) ile bulunur.
        // Başlık: entry varsa entry.name (yerelleştirilmiş, örn. "Görev Yöneticisi"), yoksa toplevel.title (pencere başlığı).
        // İkon: aynı entry.icon + Quickshell.iconPath; ana süreçte XDG_DATA_DIRS wayfire autostart'ta export edilmeli (wayfire.ini).
        component TaskButton: Rectangle {
            id: taskBtn

            required property int index
            required property string tid

            readonly property var toplevel: root.tasksMap[tid] ?? null
            readonly property bool dragging: dragState.active && dragState.tid === tid

            width: taskBar.buttonWidth
            height: root.actionButtonSize
            radius: root.buttonRadius

            // Use taskBar.buttonWidth (target) instead of the animated `width`
            // to keep x and width animations independent and avoid cascading recalculation
            x: index * (taskBar.buttonWidth + root.taskSpacing)
            z: dragging ? 10 : 1

            color: {
                if (toplevel?.activated)                     return root.clrBtnActive
                if (taskMouse.containsMouse && !dragState.active) return root.clrBtnHover
                return root.clrBtnDefault
            }

            opacity: dragging ? 0.35 : 1.0
            scale:   dragging ? 1.05 : 1.0

            Behavior on x       { enabled: !dragging; NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
            Behavior on width   { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
            Behavior on color   { ColorAnimation  { duration: 150 } }
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Behavior on scale   { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

            Component.onDestruction: {
                if (dragState.tid === tid) { dragState.active = false; dragState.tid = "" }
            }

            // App icon veya baş harf (ikon yoksa title/appId ilk harfi)
            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
                spacing: 6

                Item {
                    Layout.preferredWidth: root.taskIconSize
                    Layout.preferredHeight: root.taskIconSize

                    readonly property var entry: taskBtn.toplevel
                        ? root.lookupEntry(taskBtn.toplevel.appId) : null
                    readonly property string iconName: entry?.icon || taskBtn.toplevel?.appId || ""
                    readonly property string _fallback: Quickshell.iconPath("application-x-executable") || ""
                    readonly property string _localFallback: Qt.resolvedUrl("application.svg")
                    // Launcher AppCell ile birebir: source = Quickshell.iconPath(entry.icon). Path'i olduğu gibi kullan (file:// ekleme); flatpakIconPath zaten file:// döndürüyor.
                    readonly property string _themePath: (entry && iconName)
                        ? (iconName.startsWith("/") ? iconName : (Quickshell.iconPath(iconName) || (iconName.indexOf(".") >= 0 ? root.flatpakIconPath(iconName) : "")))
                        : (taskBtn.toplevel?.appId ? (Quickshell.iconPath(taskBtn.toplevel.appId) || (String(taskBtn.toplevel.appId).indexOf(".") >= 0 ? root.flatpakIconPath(taskBtn.toplevel.appId) : "")) : "")
                    readonly property string iconSource: _themePath || _fallback || _localFallback
                    readonly property string _flatpakPngFallback: (entry && iconName && iconName.indexOf(".") >= 0) ? root.flatpakIconPath48(iconName) : ""
                    // appId sabit (sayfa başlığı değişse de harf değişmez)
                    readonly property string initial: {
                        const raw = taskBtn.toplevel?.appId ?? taskBtn.toplevel?.title ?? ""
                        return raw.length ? raw.charAt(0).toUpperCase() : "?"
                    }

                    Image {
                        id: taskIconImg
                        anchors.fill: parent
                        source: parent.iconSource !== "" ? parent.iconSource : ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(32, 32)
                        smooth: true
                        visible: parent.iconSource !== "" && status === Image.Ready
                    }
                    Image {
                        id: taskIconImgPng
                        anchors.fill: parent
                        source: parent._flatpakPngFallback
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(32, 32)
                        smooth: true
                        visible: source !== "" && status === Image.Ready && !taskIconImg.visible
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Math.min(width, height) / 4
                        color: taskBtn.toplevel?.activated ? root.clrBtnActive : root.clrBtnDefault
                        border.width: 1
                        border.color: root.clrDivider
                        visible: !taskIconImg.visible && !taskIconImgPng.visible

                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.initial
                            color: root.clrTextFull
                            font.pixelSize: Math.max(10, root.taskIconSize - 6)
                            font.bold: true
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.lookupEntry(taskBtn.toplevel?.appId)?.name ?? taskBtn.toplevel?.title ?? ""
                    color: taskBtn.toplevel?.activated ? root.clrTextFull : root.clrTextDim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            // Left-click: if minimized → activate; if visible → minimize. Right-click: context menu. Drag: reorder.
            MouseArea {
                id: taskMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property real pressX: 0

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        root.activeTid = (root.activeTid === tid) ? "" : tid
                    } else {
                        pressX = mouse.x
                        dragState.tid = tid
                        root.activeTid = ""
                    }
                }

                onPositionChanged: mouse => {
                    if (mouse.buttons & Qt.RightButton || dragState.tid !== tid) return

                    if (!dragState.active && Math.abs(mouse.x - pressX) > 8)
                        dragState.active = true

                    if (dragState.active) {
                        const posInBar = mapToItem(taskBar, mouse.x, 0).x
                        const target = Math.floor(posInBar / (taskBar.buttonWidth + root.taskSpacing))
                        if (target >= 0 && target < tasksModel.count && target !== index)
                            tasksModel.move(index, target, 1)
                    }
                }

                onReleased: mouse => {
                    if (mouse.button === Qt.RightButton) return
                    if (dragState.tid === tid && !dragState.active) {
                        root.closeLauncher()
                        if (taskBtn.toplevel) {
                            if (taskBtn.toplevel.minimized) {
                                taskBtn.toplevel.activate()
                            } else if (taskBtn.toplevel.activated) {
                                taskBtn.toplevel.minimized = true
                            } else {
                                taskBtn.toplevel.activate()
                            }
                        }
                    }
                    if (dragState.tid === tid) { dragState.active = false; dragState.tid = "" }
                }

                cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            }

            // Context menu — floats above the task button
            Rectangle {
                id: ctxMenu
                visible: root.activeTid === tid
                z: 10
                width: 160
                radius: 8
                color: Qt.rgba(0.12, 0.12, 0.12, 0.98)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.top
                    bottomMargin: 14
                }

                // Drop shadow
                Rectangle {
                    anchors { fill: parent; margins: -1 }
                    z: -1; radius: 8
                    color: "black"; opacity: 0.3
                }

                // Caret pointing at the task button below
                Rectangle {
                    width: 10; height: 10; rotation: 45
                    color: ctxMenu.color
                    border.color: ctxMenu.border.color
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        verticalCenter: parent.bottom
                    }
                    z: -1
                }

                Column {
                    id: ctxItems
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 4

                    MenuAction {
                        label: "Küçült"
                        onSelected: {
                            if (taskBtn.toplevel) taskBtn.toplevel.minimized = true
                            root.activeTid = ""
                        }
                    }

                    MenuAction {
                        label: taskBtn.toplevel?.maximized ? "Pencere Modu" : "Ekranı Kapla"
                        onSelected: {
                            if (taskBtn.toplevel) {
                                taskBtn.toplevel.activate()
                                taskBtn.toplevel.maximized = !taskBtn.toplevel.maximized
                            }
                            root.activeTid = ""
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Qt.rgba(1, 1, 1, 0.1)
                    }

                    MenuAction {
                        label: "Kapat"
                        destructive: true
                        onSelected: {
                            if (taskBtn.toplevel) taskBtn.toplevel.close()
                            root.activeTid = ""
                        }
                    }
                }

                height: ctxItems.height + 16
            }
        }
    }
}
