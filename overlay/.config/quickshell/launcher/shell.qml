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
    readonly property int _sideWidth:  260
    readonly property int _margin:     20
    readonly property int _cardRadius: 16
    readonly property int _iconSize:   48

    readonly property color _clrGlassBg:     Qt.rgba(1, 1, 1, 0.12)
    readonly property color _clrGlassBorder: Qt.rgba(1, 1, 1, 0.20)
    readonly property color _clrText:        "#ffffff"
    readonly property color _clrTextDim:     Qt.rgba(1, 1, 1, 0.70)
    readonly property color _clrAccent:      "#4AC0FF"
    readonly property color _clrHover:       Qt.rgba(1, 1, 1, 0.15)

    // ─── Kullanıcı bilgileri ──────────────────────────────────────────────────
    readonly property string _userName: Quickshell.env("USER") || ""
    property string _userFullName: ""

    // FIX: Kullanıcı adı shell string'e gömülmüyor — positional arg olarak geçiliyor
    Process {
        id: userFullNameProc
        command: ["sh", "-c",
            "getent passwd \"$1\" | cut -d: -f5 | cut -d, -f1",
            "--", root._userName]
        running: root._userName !== ""
        stdout: StdioCollector { id: _userNameOut }
        // FIX: onDataChanged yerine onExited — output tamamlandığında okunuyor
        onExited: (code) => {
            if (code === 0) {
                var name = _userNameOut.text.trim()
                if (name !== "") root._userFullName = name
            }
        }
    }

    // ─── Durum ────────────────────────────────────────────────────────────────
    property string searchText: ""
    property bool _powerMenuOpen: false
    property bool _shown: false

    // FIX: Her delegate'te tekrar hesaplanmak yerine bir kez cache'leniyor
    readonly property string _searchLower: searchText.toLowerCase().trim()

    // ─── Güç aksiyonları ──────────────────────────────────────────────────────
    ListModel {
        id: pwrModel
        Component.onCompleted: {
            append({ key: "reboot",   label: "Yeniden Başlat", icon: "reboot",   accent: "#FFB347" })
            append({ key: "suspend",  label: "Uyku",           icon: "suspend",  accent: "#7EC8FF" })
            append({ key: "poweroff", label: "Kapat",          icon: "power",    accent: "#FF6B6B" })
            append({ key: "logout",   label: "Oturumu Kapat",  icon: "logout",   accent: "#A8FFB0" })
        }
    }

    // Void Linux — runit + elogind, login1 D-Bus
    function _runPower(key) {
        if (!key) return
        var cmd = []
        switch (key) {
            case "reboot":
                cmd = ["/usr/bin/dbus-send", "--system", "--print-reply",
                       "--dest=org.freedesktop.login1", "/org/freedesktop/login1",
                       "org.freedesktop.login1.Manager.Reboot", "boolean:true"]
                break
            case "suspend":
                cmd = ["/usr/bin/dbus-send", "--system", "--print-reply",
                       "--dest=org.freedesktop.login1", "/org/freedesktop/login1",
                       "org.freedesktop.login1.Manager.Suspend", "boolean:true"]
                break
            case "poweroff":
                cmd = ["/usr/bin/dbus-send", "--system", "--print-reply",
                       "--dest=org.freedesktop.login1", "/org/freedesktop/login1",
                       "org.freedesktop.login1.Manager.PowerOff", "boolean:true"]
                break
            case "logout":
                // FIX: shell interpolation yok — username doğrudan argüman olarak geçiliyor
                cmd = ["/usr/bin/loginctl", "terminate-user", root._userName]
                break
        }
        if (cmd.length > 0) {
            Quickshell.execDetached(cmd)
            _close()
        }
    }

    // FIX: Qt.quit() çağrıları merkezi bir fonksiyonda toplandı
    function _close() { Qt.quit() }

    readonly property string _wallpaper: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        + "/Wallpapers/ship_bg.jpg"

    Shortcut { sequence: "Escape"; onActivated: _close() }

    Component.onCompleted: {
        _shown = true
        searchInput.forceActiveFocus()
    }

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

    // ─── Büyük saat ───────────────────────────────────────────────────────────
    Text {
        id: bigClock
        anchors { left: parent.left; top: parent.top; leftMargin: _margin; topMargin: _margin }
        font { pixelSize: 120; weight: Font.Bold; letterSpacing: -4 }
        color: _clrText
        opacity: _shown ? 0.9 : 0
        scale:   _shown ? 1.0 : 0.8

        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 600; easing.type: Easing.OutBack  } }

        // FIX: triggeredOnStart: true — ilk tick'i beklemeden saat hemen gösterilir
        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: bigClock.text = Qt.formatTime(new Date(), "HH:mm")
        }
    }

    // Dışarı tıklanınca kapat
    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: _close()
    }

    // ─── Ana içerik ───────────────────────────────────────────────────────────
    Item {
        id: mainContent
        anchors { fill: parent; margins: _margin; topMargin: _margin + 160 }
        opacity: _shown ? 1.0 : 0.0
        scale:   _shown ? 1.0 : 0.98

        // FIX: "Behavior on transform" kaldırıldı — list property'e behavior uygulanamaz,
        //      QML bunu sessizce görmezden gelir. scale + opacity animasyonu yeterli.
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        // ── Sidebar ──────────────────────────────────────────────────────────
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

                // Kullanıcı profili
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
                            text: _userFullName !== "" ? _userFullName
                                : (_userName !== "" ? _userName : "Kullanıcı")
                            color: _clrText
                            font { pixelSize: 18; weight: Font.Medium }
                        }
                        Text {
                            text: "@" + (_userName !== "" ? _userName : "admin")
                            color: _clrTextDim
                            font.pixelSize: 12
                        }
                    }
                }

                // Bağlantılar
                Column {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: ["File Center", "Instagram", "WhatsApp", "Facebook",
                                "Games", "Music & Audio", "Pictures & Visuals", "Desktops"]
                        delegate: Rectangle {
                            width: parent.width; height: 44; radius: 12
                            color: _maSide.containsMouse ? _clrHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                anchors { fill: parent; leftMargin: 12 }
                                spacing: 12
                                Rectangle {
                                    width: 24; height: 24; radius: 6
                                    color: _clrGlassBorder
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData
                                    color: _clrText
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            MouseArea { id: _maSide; anchors.fill: parent; hoverEnabled: true }
                        }
                    }
                }
            }
        }

        // ── İçerik ızgarası ──────────────────────────────────────────────────
        GridLayout {
            anchors {
                left: sideBar.right; right: parent.right
                top: parent.top; bottom: parent.bottom
                leftMargin: 32
            }
            columns: 2
            columnSpacing: 24
            rowSpacing: 24

            // Sol sütun
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 24

                Card {
                    title: "Microsoft Collection"
                    Layout.fillWidth: true; Layout.preferredHeight: 220
                    Flow {
                        anchors { fill: parent; margins: 24; topMargin: 54 }
                        spacing: 20
                        Repeater {
                            model: 6
                            delegate: Rectangle {
                                width: 54; height: 54; radius: 12
                                color: _clrGlassBorder
                            }
                        }
                    }
                }

                Card {
                    title: "Uygulamalar"
                    Layout.fillWidth: true; Layout.fillHeight: true

                    ColumnLayout {
                        anchors { fill: parent; margins: 24; topMargin: 54 }
                        spacing: 16

                        // Arama çubuğu
                        Rectangle {
                            Layout.fillWidth: true
                            height: 48; radius: 12
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border {
                                width: 1
                                color: searchInput.activeFocus ? _clrAccent : _clrGlassBorder
                            }

                            Text {
                                text: "Uygulama ara..."
                                color: _clrTextDim
                                font.pixelSize: 16
                                visible: searchInput.text === "" && !searchInput.activeFocus
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left; leftMargin: 16
                                }
                            }

                            TextInput {
                                id: searchInput
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 16
                                color: "white"
                                onTextChanged: root.searchText = text

                                // FIX: children DOM traversal yerine Repeater.itemAt() kullanılıyor
                                Keys.onReturnPressed: {
                                    for (var i = 0; i < appRepeater.count; i++) {
                                        var cell = appRepeater.itemAt(i)
                                        if (cell && cell.visible) {
                                            if (cell.entry) cell.entry.execute()
                                            _close()
                                            break
                                        }
                                    }
                                }
                            }
                        }

                        Flickable {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentHeight: appFlow.height
                            clip: true

                            Flow {
                                id: appFlow
                                width: parent.width
                                spacing: 12

                                // FIX: Gereksiz wrapper Item kaldırıldı — AppCell doğrudan delegate
                                Repeater {
                                    id: appRepeater
                                    model: DesktopEntries.applications
                                    delegate: AppCell {
                                        width: 80; height: 100
                                        entry: modelData
                                        // FIX: _searchLower cached property kullanılıyor
                                        visible: root._searchLower === "" ||
                                                 (modelData && modelData.name &&
                                                  modelData.name.toLowerCase().indexOf(root._searchLower) >= 0)
                                        onLaunch: _close()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Sağ sütun
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 24

                Card {
                    title: "Son Kullanılanlar"
                    Layout.fillWidth: true; Layout.preferredHeight: 340
                    Column {
                        anchors { fill: parent; margins: 24; topMargin: 54 }
                        spacing: 16
                        Repeater {
                            model: [
                                { t: "Notifications", s: "Notification Alerts",   i: "bell"     },
                                { t: "System Setup",  s: "Installed UI Elements", i: "settings" },
                                { t: "Accessibility", s: "Accessibility settings", i: "user"    }
                            ]
                            delegate: Row {
                                spacing: 16
                                Rectangle { width: 48; height: 48; radius: 12; color: _clrGlassBorder }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { text: modelData.t; color: _clrText;    font.pixelSize: 15 }
                                    Text { text: modelData.s; color: _clrTextDim; font.pixelSize: 11 }
                                }
                            }
                        }
                    }
                }

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

    // ── Güç butonu ve menü ────────────────────────────────────────────────────
    // FIX: Circular width binding kaldırıldı — Row layout kendi genişliğini hesaplar
    Row {
        id: powerRow
        anchors { verticalCenter: bigClock.verticalCenter; right: parent.right; rightMargin: _margin }
        spacing: 16
        layoutDirection: Qt.RightToLeft

        Rectangle {
            id: mainPowerBtn
            width: 54; height: 54; radius: 27
            color: _powerMenuOpen ? _clrAccent : _clrGlassBg
            border { width: 1; color: _clrGlassBorder }

            Behavior on color { ColorAnimation { duration: 200 } }

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

        Row {
            id: powerMenuContent
            layoutDirection: Qt.RightToLeft
            spacing: 12
            opacity: _powerMenuOpen ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            Repeater {
                model: pwrModel
                delegate: Rectangle {
                    height: 54; width: 200; radius: 27
                    color: _maPwr.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : _clrGlassBg
                    border { width: 1; color: _clrGlassBorder }
                    clip: true

                    opacity: _powerMenuOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 + (index * 50) } }

                    // Slide-in animasyonu — Translate.x üzerinde Behavior geçerlidir
                    transform: Translate {
                        x: _powerMenuOpen ? 0 : 20
                        Behavior on x { NumberAnimation { duration: 300 + (index * 50); easing.type: Easing.OutBack } }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Item {
                            width: 26; height: 26
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: pwrSubIcon
                                anchors.fill: parent
                                sourceSize: Qt.size(width, height)
                                visible: false
                                // FIX: icon adı model'den alınıyor — her key için ayrı if-else yok
                                source: "icons/" + model.icon + ".svg"
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
                            // FIX: "|| width > 0" kaldırıldı — width > 0 her zaman true'dur,
                            //      görünürlük parent'ın opacity animasyonuyla yönetiliyor
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
    }

    // ─── Card bileşeni ────────────────────────────────────────────────────────
    component Card: Rectangle {
        property string title: ""
        radius: _cardRadius
        color: _clrGlassBg
        border { width: 1; color: _clrGlassBorder }

        Text {
            anchors { left: parent.left; top: parent.top; margins: 24 }
            text: parent.title
            color: _clrTextDim
            font { pixelSize: 13; weight: Font.Medium }
        }
    }

    // ─── AppCell bileşeni — ikon üstte, isim altta ────────────────────────────
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
                        // FIX: name boş string ise charAt(0) undefined döner — null guard eklendi
                        text: (_ac.entry && _ac.entry.name && _ac.entry.name.length > 0)
                              ? _ac.entry.name.charAt(0).toUpperCase() : "?"
                        font { pixelSize: 18; weight: Font.Bold }
                        color: "white"
                    }
                }
            }

            Text {
                // FIX: parent.parent.width yerine _ac.width — zincir referans kırıldı
                width: _ac.width - 8
                text: _ac.entry ? (_ac.entry.name || "") : ""
                font.pixelSize: 11
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        MouseArea {
            id: _ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (_ac.entry) {
                    _ac.entry.execute()
                    _ac.launch()
                }
            }
        }
    }
}
