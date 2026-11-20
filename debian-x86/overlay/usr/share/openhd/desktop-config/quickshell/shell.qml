import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell
    property string networkState: "Checking"
    property string volumeState: ""
    property string batteryState: ""
    property string clockText: Qt.formatDateTime(new Date(), "HH:mm")
    property bool launcherOpen: true
    property bool powerOpen: false

    FileView {
        id: appFile
        path: "/usr/share/openhd/launcher-apps.json"
        blockLoading: true
    }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: shell.clockText = Qt.formatDateTime(new Date(), "HH:mm") }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: { networkProbe.running = true; audioProbe.running = true; batteryProbe.running = true } }
    Component.onCompleted: { networkProbe.running = true; audioProbe.running = true; batteryProbe.running = true }

    PanelWindow {
        anchors { top: true; left: true; right: true; bottom: true }
        color: "#020711"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Background
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.02
            width: Math.min(parent.width * 0.65, parent.height * 0.50 * 1365 / 768)
            height: width * 768 / 1365
            source: "file:///usr/share/backgrounds/openhd-3.0.png"
            sourceSize.width: 1365
            sourceSize.height: 768
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    Process {
        id: networkProbe
        command: ["sh", "-c", "nmcli -t -f CONNECTIVITY general 2>/dev/null || true"]
        stdout: StdioCollector { id: networkOutput }
        onExited: (code) => { shell.networkState = code === 0 && networkOutput.text.trim() ? networkOutput.text.trim() : "Unavailable" }
    }
    Process {
        id: audioProbe
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true"]
        stdout: StdioCollector { id: audioOutput }
        onExited: (code) => { shell.volumeState = code === 0 ? audioOutput.text.trim() : "" }
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
                Image { source: "file:///usr/share/openhd/brand/openhd-mark.png"; sourceSize.width: 28; sourceSize.height: 28; fillMode: Image.PreserveAspectFit }
                Row {
                    spacing: 0
                    Text { text: "OpenHD"; color: "#f4f8fc"; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Text { text: "-OS"; color: "#00c8f2"; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "\uf1eb"
                    color: shell.networkState === "full" || shell.networkState === "limited" ? "#e9f2fb" : "#718093"
                    font.family: "FontAwesome"
                    font.pixelSize: 16
                    Accessible.name: "Network " + shell.networkState
                    TapHandler { onTapped: Quickshell.execDetached(["nm-connection-editor"]) }
                }
                Text { text: shell.volumeState.includes("MUTED") ? "\uf026" : "\uf028"; color: shell.volumeState ? "#e9f2fb" : "#718093"; font.family: "FontAwesome"; font.pixelSize: 16; Accessible.name: "Audio " + shell.volumeState }
                Text { visible: shell.batteryState !== ""; text: (Number(shell.batteryState) >= 90 ? "\uf240" : Number(shell.batteryState) >= 65 ? "\uf241" : Number(shell.batteryState) >= 40 ? "\uf242" : Number(shell.batteryState) >= 15 ? "\uf243" : "\uf244") + "  " + shell.batteryState + "%"; color: "#e9f2fb"; font.family: "FontAwesome"; font.pixelSize: 14; Accessible.name: "Battery " + shell.batteryState + " percent" }
                Rectangle { width: 1; height: 20; color: "#52667a"; Layout.leftMargin: 4; Layout.rightMargin: 4 }
                Text { text: shell.clockText; color: "#f4f8fc"; font.family: "Inter"; font.pixelSize: 16; Layout.minimumWidth: 48; horizontalAlignment: Text.AlignRight }
            }
        }
    }

    PanelWindow {
        id: launcherWindow
        visible: shell.launcherOpen
        focusable: shell.launcherOpen
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        Item {
            anchors.fill: parent
            focus: shell.launcherOpen
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { shell.launcherOpen = false; event.accepted = true }
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
                    Quickshell.execDetached(["/usr/local/sbin/openhd-desktop-app", filteredApps[selectedIndex].id])
                    shell.launcherOpen = false
                }
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.min(parent.height * 0.64 - height / 2, parent.height - height - 20)
                width: Math.min(860, parent.width - 32)
                height: 232
                radius: 20
                color: "#d90b1725"
                border.width: 1
                border.color: "#805184a3"
                focus: shell.launcherOpen
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
                                Keys.onEscapePressed: shell.launcherOpen = false
                                Keys.onLeftPressed: event => { if (cursorPosition === 0) { launcher.moveSelection(-1); event.accepted = true } }
                                Keys.onRightPressed: event => { if (cursorPosition === text.length) { launcher.moveSelection(1); event.accepted = true } }
                            }
                            Text { text: "Ctrl + Space"; color: "#a9b8c9"; font.family: "Inter"; font.pixelSize: 13 }
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
                                        Quickshell.execDetached(["/usr/local/sbin/openhd-desktop-app", modelData.id])
                                        shell.launcherOpen = false
                                    }
                                }
                            }
                        }
                    }
                }
                Component.onCompleted: search.forceActiveFocus()
            }
            IpcHandler {
                target: "launcher"
                function toggle(): void {
                    shell.launcherOpen = !shell.launcherOpen
                    if (shell.launcherOpen) search.forceActiveFocus()
                }
                function power(): void { shell.powerOpen = !shell.powerOpen }
            }
            MouseArea {
                anchors.fill: parent
                z: -1
                enabled: shell.launcherOpen
                onClicked: shell.launcherOpen = false
            }
        }
    }

    PanelWindow {
        visible: shell.powerOpen
        anchors { top: true; left: true; right: true; bottom: true }
        focusable: shell.powerOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            anchors.centerIn: parent
            width: 310
            height: 220
            radius: 18
            color: "#ed0b1725"
            border.width: 1
            border.color: "#805184a3"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                Text { text: "Power"; color: "#f4f8fc"; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.DemiBold }
                Button { Layout.fillWidth: true; text: "Restart"; onClicked: { Quickshell.execDetached(["systemctl", "reboot"]); shell.powerOpen = false } }
                Button { Layout.fillWidth: true; text: "Shut down"; onClicked: { Quickshell.execDetached(["systemctl", "poweroff"]); shell.powerOpen = false } }
                Button { Layout.fillWidth: true; text: "Cancel"; onClicked: shell.powerOpen = false }
            }
        }
    }
}
