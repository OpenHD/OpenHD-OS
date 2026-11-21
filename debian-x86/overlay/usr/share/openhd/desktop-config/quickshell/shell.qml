import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

ShellRoot {
    id: shell
    property string networkState: "Checking"
    property string batteryState: ""
    property string clockText: Qt.formatDateTime(new Date(), "HH:mm")
    property string activeMenu: ""
    property string hudTitle: ""
    property int hudLevel: -1
    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property var networkItem: SystemTray.items.values.find(item => /^nm[-_]applet$/.test(item.id)) ?? null

    function toggleMenu(name) {
        activeMenu = activeMenu === name ? "" : name
    }

    function openNetwork() {
        activeMenu = ""
        if (networkItem?.hasMenu)
            networkMenu.open()
        else
            Quickshell.execDetached(["nm-connection-editor"])
    }

    function showHud(title, level) {
        hudTitle = title
        hudLevel = level
        hudTimeout.restart()
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    IpcHandler {
        target: "desktop"
        function power(): void { shell.toggleMenu("power") }
        function network(): void { shell.openNetwork() }
        function hud(title: string, level: int): void {
            shell.showHud(title, level)
        }
    }
    Timer { id: hudTimeout; interval: 1500 }

    FileView {
        id: appFile
        path: "/usr/share/openhd/launcher-apps.json"
        blockLoading: true
    }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: shell.clockText = Qt.formatDateTime(new Date(), "HH:mm") }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: { networkProbe.running = true; batteryProbe.running = true } }
    Component.onCompleted: { networkProbe.running = true; batteryProbe.running = true }

    PanelWindow {
        anchors { top: true; left: true; right: true; bottom: true }
        color: "#010409"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Background
        mask: Region {}
        AlbatrossBackdrop { anchors.fill: parent }
    }

    Process {
        id: networkProbe
        command: ["sh", "-c", "nmcli -t -f CONNECTIVITY general 2>/dev/null || true"]
        stdout: StdioCollector { id: networkOutput }
        onExited: (code) => { shell.networkState = code === 0 && networkOutput.text.trim() ? networkOutput.text.trim() : "Unavailable" }
    }
    Process {
        id: batteryProbe
        command: ["sh", "-c", "for p in /sys/class/power_supply/*; do [ -r \"$p/type\" ] && [ \"$(cat \"$p/type\")\" = Battery ] && [ -r \"$p/capacity\" ] && { cat \"$p/capacity\"; exit 0; }; done; exit 1"]
        stdout: StdioCollector { id: batteryOutput }
        onExited: (code) => { shell.batteryState = code === 0 ? batteryOutput.text.trim() : "" }
    }

    PanelWindow {
        id: topBar
        anchors { top: true; left: true; right: true }
        margins { top: 8; left: 12; right: 12 }
        implicitHeight: 48
        color: "transparent"
        exclusiveZone: 0
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: "#d9081422"
            border.width: 1
            border.color: "#553d6885"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10
                Button {
                    id: brandButton
                    Layout.fillHeight: true
                    horizontalPadding: 5
                    Accessible.name: "Power menu"
                    onClicked: shell.toggleMenu("power")
                    background: Rectangle { radius: 8; color: brandButton.hovered || shell.activeMenu === "power" ? "#294057" : "transparent" }
                    contentItem: RowLayout {
                        spacing: 6
                        Image {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            source: "file:///usr/share/openhd/brand/openhd-mark.png"
                            sourceSize: Qt.size(192, 192)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }
                        Text {
                            text: 'OpenHD<span style="color:#00c8f2">-OS</span>'
                            textFormat: Text.StyledText
                            color: "#f4f8fc"
                            font.family: "Inter"
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    id: networkButton
                    Layout.preferredWidth: 42
                    Layout.fillHeight: true
                    Accessible.name: "Network " + shell.networkState
                    onClicked: shell.openNetwork()
                    background: Rectangle { radius: 8; color: networkButton.hovered ? "#294057" : "transparent" }
                    contentItem: Text {
                        visible: !networkIcon.visible
                        text: "\uf1eb"
                        color: shell.networkState === "full" || shell.networkState === "limited" ? "#e9f2fb" : "#718093"
                        font.family: "FontAwesome"
                        font.pixelSize: 16
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Image {
                        id: networkIcon
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: shell.networkItem?.icon ?? ""
                        visible: status === Image.Ready
                    }
                }
                Button {
                    id: audioButton
                    Layout.preferredWidth: 42
                    Layout.fillHeight: true
                    Accessible.name: "Sound controls"
                    onClicked: shell.toggleMenu("audio")
                    background: Rectangle { radius: 8; color: audioButton.hovered || shell.activeMenu === "audio" ? "#294057" : "transparent" }
                    contentItem: Text {
                        text: shell.audio && !shell.audio.muted ? "\uf028" : "\uf026"
                        color: shell.audio ? "#e9f2fb" : "#718093"
                        font.family: "FontAwesome"
                        font.pixelSize: 16
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Text { visible: shell.batteryState !== ""; text: (Number(shell.batteryState) >= 90 ? "\uf240" : Number(shell.batteryState) >= 65 ? "\uf241" : Number(shell.batteryState) >= 40 ? "\uf242" : Number(shell.batteryState) >= 15 ? "\uf243" : "\uf244") + "  " + shell.batteryState + "%"; color: "#e9f2fb"; font.family: "FontAwesome"; font.pixelSize: 14; Accessible.name: "Battery " + shell.batteryState + " percent" }
                Rectangle { width: 1; height: 20; color: "#52667a"; Layout.leftMargin: 4; Layout.rightMargin: 4 }
                Text { text: shell.clockText; color: "#f4f8fc"; font.family: "Inter"; font.pixelSize: 16; Layout.minimumWidth: 48; horizontalAlignment: Text.AlignRight }
            }
        }
    }

    QsMenuAnchor {
        id: networkMenu
        menu: shell.networkItem?.menu ?? null
        anchor.item: networkButton
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
    }

    PanelWindow {
        id: launcherWindow
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        mask: Region { item: launcher }
        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { search.clear(); event.accepted = true }
                else if (event.key === Qt.Key_Left) { launcher.moveSelection(-1); event.accepted = true }
                else if (event.key === Qt.Key_Right) { launcher.moveSelection(1); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { launcher.launchSelected(); event.accepted = true }
            }
            Rectangle {
                id: launcher
                property var appData: JSON.parse(appFile.text())
                property var filteredApps: search.text.trim().length === 0
                    ? appData.filter(app => app.id !== "qgroundcontrol")
                    : appData.filter(app => app.name.toLowerCase().includes(search.text.trim().toLowerCase()))
                property int selectedIndex: 0
                function moveSelection(direction) {
                    if (filteredApps.length > 0) selectedIndex = (selectedIndex + direction + filteredApps.length) % filteredApps.length
                }
                function launchSelected() {
                    if (filteredApps.length === 0) return
                    launchApp(filteredApps[selectedIndex].id)
                }
                function launchApp(appId) {
                    if (!/^[a-z0-9-]+$/.test(appId)) return
                    // Hyprland starts XWayland after the shell's startup hook.
                    // Dispatch here so X11 apps inherit the current display.
                    Quickshell.execDetached(["hyprctl", "dispatch",
                        'hl.dsp.exec_cmd("/usr/local/sbin/openhd-desktop-app ' + appId + '")'])
                    search.clear()
                }
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.min(parent.height * 0.64 - height / 2, parent.height - height - 20)
                width: Math.min(860, parent.width - 32)
                height: 232
                radius: 20
                color: "#d90b1725"
                border.width: 1
                border.color: "#805184a3"
                focus: true
                Keys.forwardTo: [search]
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16
                    Rectangle {
                        Layout.fillWidth: true
                        height: 46
                        radius: 13
                        color: "#c9142233"
                        border.width: 1
                        border.color: search.activeFocus ? "#a300c8f2" : "#66456d88"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 10
                            Text { text: "⌕"; color: "#dce9f5"; font.pixelSize: 28; verticalAlignment: Text.AlignVCenter }
                            TextField {
                                id: search
                                Layout.fillWidth: true
                                placeholderText: "Applications..."
                                color: "#edf5fc"
                                placeholderTextColor: "#a9b8c9"
                                font.family: "Inter"
                                font.pixelSize: 16
                                background: Item {}
                                selectByMouse: true
                                onTextChanged: launcher.selectedIndex = 0
                                Keys.onReturnPressed: launcher.launchSelected()
                                Keys.onEnterPressed: launcher.launchSelected()
                                Keys.onEscapePressed: search.clear()
                                Keys.onLeftPressed: event => { if (cursorPosition === 0) { launcher.moveSelection(-1); event.accepted = true } }
                                Keys.onRightPressed: event => { if (cursorPosition === text.length) { launcher.moveSelection(1); event.accepted = true } }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: launcher.filteredApps
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 150
                                Layout.minimumWidth: 0
                                height: 132
                                radius: 15
                                color: index === launcher.selectedIndex ? "#bd092237" : "#aa102238"
                                border.width: index === launcher.selectedIndex ? 2 : 1
                                border.color: index === launcher.selectedIndex ? "#00c8f2" : "#443e6886"
                                Accessible.name: modelData.name
                                Accessible.role: Accessible.Button
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Image {
                                            anchors.centerIn: parent
                                            width: Math.min(parent.width, modelData.id === "qopenhd" ? 112 : 56)
                                            height: Math.min(parent.height, 56)
                                            source: modelData.icon.startsWith("/") ? "file://" + modelData.icon : Quickshell.iconPath(modelData.icon, "applications-science")
                                            sourceSize.width: modelData.id === "qopenhd" ? 560 : 192
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                        }
                                    }
                                    Text { Layout.fillWidth: true; text: modelData.name; color: "#f1f6fb"; font.family: "Inter"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                                }
                                TapHandler {
                                    onTapped: {
                                        launcher.selectedIndex = index
                                        launcher.launchApp(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
                Component.onCompleted: search.forceActiveFocus()
            }
        }
    }

    PopupWindow {
        id: controlsMenu
        visible: shell.activeMenu !== ""
        anchor.item: shell.activeMenu === "power" ? brandButton : audioButton
        anchor.edges: shell.activeMenu === "power" ? Edges.Bottom | Edges.Left : Edges.Bottom | Edges.Right
        anchor.gravity: shell.activeMenu === "power" ? Edges.Bottom | Edges.Right : Edges.Bottom | Edges.Left
        implicitWidth: 278
        implicitHeight: menuContents.implicitHeight + 28
        color: "transparent"

        HyprlandFocusGrab {
            windows: [topBar, controlsMenu]
            active: controlsMenu.visible
            onCleared: shell.activeMenu = ""
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: "#ed0b1725"
            border.width: 1
            border.color: "#805184a3"
            focus: true
            Keys.onEscapePressed: shell.activeMenu = ""
            ColumnLayout {
                id: menuContents
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 6
                Text { text: shell.activeMenu === "power" ? "Power" : "Sound"; color: "#f4f8fc"; font.family: "Inter"; font.pixelSize: 16; font.weight: Font.DemiBold }
                Button {
                    visible: shell.activeMenu === "power"
                    Layout.fillWidth: true
                    text: "Restart"
                    onClicked: powerAction.run("reboot")
                }
                Button {
                    visible: shell.activeMenu === "power"
                    Layout.fillWidth: true
                    text: "Shut down"
                    onClicked: powerAction.run("poweroff")
                }
                Text {
                    visible: shell.activeMenu === "audio"
                    text: !shell.audio ? "No audio output" : shell.audio.muted ? "Muted" : Math.round(shell.audio.volume * 100) + "%"
                    color: "#b6c7d8"
                    font.family: "Inter"
                }
                Slider {
                    visible: shell.activeMenu === "audio"
                    enabled: shell.audio !== null
                    Layout.fillWidth: true
                    Accessible.name: "Output volume"
                    value: shell.audio ? Math.min(1, shell.audio.volume) : 0
                    onMoved: if (shell.audio) shell.audio.volume = value
                }
                Button {
                    visible: shell.activeMenu === "audio"
                    enabled: shell.audio !== null
                    Layout.fillWidth: true
                    text: shell.audio?.muted ? "Unmute" : "Mute"
                    onClicked: if (shell.audio) shell.audio.muted = !shell.audio.muted
                }
                Button {
                    visible: shell.activeMenu === "audio"
                    Layout.fillWidth: true
                    text: "Sound settings"
                    onClicked: {
                        shell.activeMenu = ""
                        Quickshell.execDetached(["pavucontrol"])
                    }
                }
            }
        }
    }

    Process {
        id: powerAction
        function run(action) {
            shell.activeMenu = ""
            if (!running) {
                command = ["systemctl", action]
                running = true
            }
        }
        onExited: code => { if (code !== 0) shell.showHud("Power action failed", -1) }
    }

    PanelWindow {
        visible: hudTimeout.running
        anchors.bottom: true
        margins.bottom: 40
        implicitWidth: 276
        implicitHeight: 76
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region {}
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: "#ed0b1725"
            border.color: "#805184a3"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                Text {
                    text: shell.hudLevel < 0 ? shell.hudTitle : shell.hudTitle + "   " + shell.hudLevel + "%"
                    color: "#f4f8fc"
                    font.family: "Inter"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                ProgressBar {
                    visible: shell.hudLevel >= 0
                    Layout.fillWidth: true
                    to: 100
                    value: Math.min(100, shell.hudLevel)
                }
            }
        }
    }
}
