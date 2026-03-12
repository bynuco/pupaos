import QtQuick
import QtQuick.Layouts
import QtCore
import QtQuick.Effects


import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    aboveWindows: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "shipos-launcher"

    // ─── Tasarım sabitleri ────────────────────────────────────────────────────
    readonly property int _sideWidth: 260
    readonly property int _margin: 20
    readonly property int _cardRadius: 16
    readonly property int _iconSize: 48
    
    readonly property color _clrGlassBg:      Qt.rgba(1, 1, 1, 0.12)
    readonly property color _clrGlassBorder:  Qt.rgba(1, 1, 1, 0.20)
    readonly property color _clrCardBg:       Qt.rgba(1, 1, 1, 0.08)
    readonly property color _clrText:         "#ffffff"
    readonly property color _clrTextDim:      Qt.rgba(1, 1, 1, 0.70)
    readonly property color _clrAccent:       "#4AC0FF"
    readonly property color _clrHover:        Qt.rgba(1, 1, 1, 0.15)
    
    // ─── Kullanıcı Bilgileri ──────────────────────────────────────────────────
    property string _userName: Quickshell.env("USER") || ""
    property string _userFullName: ""

    Process {
        id: userFullNameProc
        command: ["sh", "-c", "getent passwd " + (_userName || "$USER") + " | cut -d ':' -f 5 | cut -d ',' -f 1"]
        running: true
        stdout: StdioCollector {
            onDataChanged: {
                var d = String(data).trim()
                if (d !== "") _userFullName = d
            }
        }
    }

    // ─── Arama metni ──────────────────────────────────────────────────────────
    property string searchText: ""
    property bool _powerMenuOpen: false

    // ─── Güç aksiyonları ──────────────────────────────────────────────────────

    ListModel {
        id: pwrModel
        Component.onCompleted: {
            append({ key: "reboot",   label: "Yeniden Başlat", icon: "system-reboot",   accent: "#FFB347" })
            append({ key: "suspend",  label: "Uyku",           icon: "system-suspend",  accent: "#7EC8FF" })
            append({ key: "poweroff", label: "Kapat",          icon: "system-shutdown", accent: "#FF6B6B" })
            append({ key: "logout",   label: "Oturumu Kapat",  icon: "system-log-out",  accent: "#A8FFB0" })
        }
    }

    // Void Linux — runit + elogind, login1 D-Bus kullan
    function _runPower(key) {
        if (!key) return
        var cmd = []
        if (key === "reboot") {
            cmd = ["/usr/bin/dbus-send", "--system", "--print-reply",
                "--dest=org.freedesktop.login1", "/org/freedesktop/login1",
                "org.freedesktop.login1.Manager.Reboot", "boolean:true"]
        } else if (key === "suspend") {
            cmd = ["/usr/bin/dbus-send", "--system", "--print-reply",
                "--dest=org.freedesktop.login1", "/org/freedesktop/login1",
                "org.freedesktop.login1.Manager.Suspend", "boolean:true"]
        } else if (key === "poweroff") {
            cmd = ["/usr/bin/dbus-send", "--system", "--print-reply",
                "--dest=org.freedesktop.login1", "/org/freedesktop/login1",
                "org.freedesktop.login1.Manager.PowerOff", "boolean:true"]
        } else if (key === "logout") {
            cmd = ["sh", "-c", "/usr/bin/loginctl terminate-user $(id -un)"]
        }
        if (cmd.length > 0) { Quickshell.execDetached(cmd); Qt.quit() }
    }

    property string _wallpaper: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        + "/Wallpapers/ship_bg.jpg"

    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }

    // ─── Arka plan: blur ──────────────────────────────────────────────────────
    Image {
        id: _wallSrc
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: root._wallpaper
        smooth: true
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        source: _wallSrc
        anchors.fill: parent
        blurEnabled: true
        blur: 1.0
        blurMax: 80
        saturation: 0.1
        brightness: -0.1
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    // Açılış Animasyonu
    property bool _shown: false
    Component.onCompleted: {
        _shown = true
        searchInput.forceActiveFocus()
    }
    
    // ─── Büyük Saat ──────────────────────────────────────────────────────────
    Text {
        id: bigClock
        anchors { left: parent.left; top: parent.top; leftMargin: _margin; topMargin: _margin }
        text: Qt.formatTime(new Date(), "HH:mm")
        font { pixelSize: 120; weight: Font.Bold; letterSpacing: -4 }
        color: _clrText
        opacity: _shown ? 0.9 : 0
        scale: _shown ? 1.0 : 0.8
        
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: bigClock.text = Qt.formatTime(new Date(), "HH:mm")
        }
    }

    // Dışarı tıklanınca kapat
    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: Qt.quit()
    }

    // ─── Ana İçerik ──────────────────────────────────────────────────────────
    Item {
        id: mainContent
        anchors.fill: parent
        anchors.margins: _margin
        anchors.topMargin: _margin + 160 // Saatin altına gelsin
        
        opacity: _shown ? 1.0 : 0.0
        scale: _shown ? 1.0 : 0.98
        transform: Translate { y: _shown ? 0 : 20 }
        
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        Behavior on transform { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }


        // ── Sidebar ──
        Rectangle {
            id: sideBar
            width: _sideWidth
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            radius: _cardRadius
            color: _clrGlassBg
            border { width: 1; color: _clrGlassBorder }

            Column {
                anchors { fill: parent; margins: 24 }
                spacing: 32

                // User Profile
                Row {
                    spacing: 16
                    Rectangle {
                        width: 54; height: 54; radius: 27
                        color: "transparent"
                        clip: true
                        Image {
                            anchors.centerIn: parent
                            width: 44; height: 44
                            sourceSize: Qt.size(width, height)
                            source: "icons/user.svg"
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { 
                            text: _userFullName !== "" ? _userFullName : (_userName !== "" ? _userName : "Kullanıcı")
                            color: _clrText; font { pixelSize: 18; weight: Font.Medium } 
                        }
                        Text { 
                            text: "@" + (_userName !== "" ? _userName : "admin")
                            color: _clrTextDim; font.pixelSize: 12 
                        }
                    }
                }

                // Links
                Column {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: ["File Center", "Instagram", "WhatsApp", "Facebook", "Games", "Music & Audio", "Pictures & Visuals", "Desktops"]
                        delegate: Rectangle {
                            width: parent.width; height: 44; radius: 12
                            color: _maSide.containsMouse ? _clrHover : "transparent"
                            Row {
                                anchors { fill: parent; leftMargin: 12 }
                                spacing: 12
                                Rectangle { width: 24; height: 24; radius: 6; color: _clrGlassBorder } // Icon placeholder
                                Text { text: modelData; color: _clrText; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { id: _maSide; anchors.fill: parent; hoverEnabled: true }
                        }
                    }
                }
            }
        }

        // ── Gri Alan (Cards) ──
        GridLayout {
            anchors { left: sideBar.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 32 }
            columns: 2
            columnSpacing: 24; rowSpacing: 24

            // Left Column
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 24

                // Microsoft Collection
                Card {
                    title: "Microsoft Collection"
                    Layout.fillWidth: true; Layout.preferredHeight: 220
                    Flow {
                        anchors.fill: parent
                        anchors.margins: 24
                        anchors.topMargin: 54
                        spacing: 20
                        Repeater {
                            model: 6
                            delegate: Rectangle { width: 54; height: 54; radius: 12; color: _clrGlassBorder }
                        }
                    }
                }

                // Uygulamalar (Applications)
                Card {
                    title: "Uygulamalar"
                    Layout.fillWidth: true; Layout.fillHeight: true
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        anchors.topMargin: 54
                        spacing: 16

                        // Search Bar inside card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: 12
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border { width: 1; color: searchInput.activeFocus ? _clrAccent : _clrGlassBorder }

                            TextInput {
                                id: searchInput
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 16
                                color: "white"
                                onTextChanged: root.searchText = text

                                Keys.onReturnPressed: {
                                    for (var i = 0; i < appFlow.children.length; i++) {
                                        var it = appFlow.children[i];
                                        if (it && it.visible) {
                                            // The first child of the delegate Item is the AppCell
                                            var cell = it.children[0];
                                            if (cell && cell.launch) {
                                                cell.launch();
                                                break;
                                            }
                                        }
                                    }
                                }
                                
                                Text {
                                    text: "Uygulama ara..."
                                    color: _clrTextDim
                                    font.pixelSize: 16
                                    visible: !parent.text && !parent.activeFocus
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: appFlow.height
                            clip: true

                            Flow {
                                id: appFlow
                                width: parent.width
                                spacing: 12

                                Repeater {
                                    model: DesktopEntries.applications
                                    delegate: Item {
                                        width: 80; height: 100
                                        visible: {
                                            var q = root.searchText.toLowerCase().trim()
                                            return q === "" || (modelData && modelData.name &&
                                                modelData.name.toLowerCase().indexOf(q) >= 0)
                                        }

                                        AppCell {
                                            anchors.fill: parent
                                            entry: modelData
                                            onLaunch: Qt.quit()
                                            
                                            // Scale down for the card view
                                            property real scaleFactor: 0.8
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Right Column
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 24

                // Recently Used
                Card {
                    title: "Recently Used"
                    Layout.fillWidth: true; Layout.preferredHeight: 340
                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        anchors.topMargin: 54
                        spacing: 16
                        Repeater {
                            model: [
                                { t: "Notifications", s: "Notification Alerts", i: "bell" },
                                { t: "System Setup", s: "Installed UI Elements", i: "settings" },
                                { t: "Accessibility", s: "Accessibility settings", i: "user" }
                            ]
                            delegate: Row {
                                spacing: 16
                                Rectangle { width: 48; height: 48; radius: 12; color: _clrGlassBorder }
                                Column {
                                    Text { text: modelData.t; color: _clrText; font.pixelSize: 15 }
                                    Text { text: modelData.s; color: _clrTextDim; font.pixelSize: 11 }
                                }
                            }
                        }
                    }
                }

                // Preview Card
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: _cardRadius
                    color: _clrGlassBg
                    border { width: 1; color: _clrGlassBorder }
                    clip: true


                }
            }
        }
    }



    // ── Power Button and Menu ───────────────────────────────────────────────
    Item {
        anchors { verticalCenter: bigClock.verticalCenter; right: parent.right; rightMargin: _margin }
        width: powerMenuContent.width + 54 + 16
        height: 54

        Row {
            id: powerMenuContent
            anchors { right: mainPowerBtn.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 12
            opacity: _powerMenuOpen ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            Repeater {
                model: pwrModel
                delegate: Rectangle {
                    height: 54; radius: 27
                    width: _powerMenuOpen ? 200 : 54
                    color: _maPwr.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : _clrGlassBg
                    border { width: 1; color: _clrGlassBorder }
                    clip: true

                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                    
                    // Animation
                    transform: Translate {
                        x: _powerMenuOpen ? 0 : 20
                        Behavior on x { NumberAnimation { duration: 300 + (index * 50); easing.type: Easing.OutBack } }
                    }
                    opacity: _powerMenuOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 + (index * 50) } }

                    Row {
                        anchors.centerIn: parent
                        height: parent.height
                        spacing: 8
                        
                        Item {
                            width: 26; height: 26
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Image {
                                id: pwrSubIcon
                                anchors.fill: parent
                                sourceSize: Qt.size(width, height)
                                visible: false
                                source: {
                                    if (model.key === "reboot") return "icons/reboot.svg"
                                    if (model.key === "suspend") return "icons/suspend.svg"
                                    if (model.key === "poweroff") return "icons/power.svg"
                                    if (model.key === "logout") return "icons/logout.svg"
                                    return ""
                                }
                            }

                            MultiEffect {
                                source: pwrSubIcon
                                anchors.fill: parent
                                colorization: 1.0
                                colorizationColor: _maPwr.containsMouse ? model.accent : "#ffffff"
                            }
                        }

                        Text {
                            text: model.label
                            color: "white"
                            font { pixelSize: 13; weight: Font.Medium }
                            anchors.verticalCenter: parent.verticalCenter
                            visible: _powerMenuOpen || width > 0
                            opacity: _powerMenuOpen ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }
                    }

                    MouseArea {
                        id: _maPwr
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root._runPower(model.key)
                    }
                }
            }
        }

        Rectangle {
            id: mainPowerBtn
            width: 54; height: 54; radius: 27
            anchors.right: parent.right
            color: _powerMenuOpen ? _clrAccent : _clrGlassBg
            border { width: 1; color: _clrGlassBorder }
            
            Item {
                anchors.centerIn: parent
                width: 26; height: 26
                
                Image {
                    id: mainIconImg
                    anchors.fill: parent
                    sourceSize: Qt.size(width, height)
                    visible: false
                    source: _powerMenuOpen ? "icons/close.svg" : "icons/power.svg"
                }

                MultiEffect {
                    source: mainIconImg
                    anchors.fill: parent
                    colorization: 1.0
                    colorizationColor: _powerMenuOpen ? "#000000" : "#ffffff"
                }
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: _powerMenuOpen = !_powerMenuOpen
            }
        }
    }

    // Component: Card helper
    component Card: Rectangle {
        property string title: ""
        radius: _cardRadius
        color: _clrGlassBg
        border { width: 1; color: _clrGlassBorder }
        
        Text {
            id: cardTitle
            anchors { left: parent.left; top: parent.top; margins: 24 }
            text: title
            color: _clrTextDim
            font { pixelSize: 13; weight: Font.Medium }
        }
    }




    // ─── Bileşenler ─────────────────────────────────────────────────────────

    // Component: Uygulama hücresi — ikon üstte, isim altta
    component AppCell: Rectangle {
        id: _ac
        property var entry: null
        signal launch()

        radius: 16
        color: _ma.containsMouse ? _clrHover : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        Column {
            anchors.centerIn: parent
            spacing: 8

            // İkon
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48; height: 48

                Image {
                    id: _ico
                    anchors.fill: parent
                    source: _ac.entry && _ac.entry.icon ? Quickshell.iconPath(_ac.entry.icon) : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent; radius: 12
                    color: _clrGlassBorder
                    visible: _ico.status !== Image.Ready
                    Text {
                        anchors.centerIn: parent
                        text: _ac.entry ? _ac.entry.name.charAt(0).toUpperCase() : "?"
                        font { pixelSize: 18; weight: Font.Bold }
                        color: "white"
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.parent.width - 8
                text: _ac.entry ? _ac.entry.name : ""
                font.pixelSize: 11
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                wrapMode: Text.WordWrap
            }
        }

        MouseArea {
            id: _ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (_ac.entry) { _ac.entry.execute(); _ac.launch() } }
        }
    }
}
