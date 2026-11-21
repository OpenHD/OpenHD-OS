import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Networking

ShellRoot {
    id: shell
    property string batteryState: ""
    property string clockText: Qt.formatDateTime(new Date(), "HH:mm")
    property string activeMenu: ""
    property string hudTitle: ""
    property int hudLevel: -1
    property real sessionCover: 1
    property string switchTarget: ""
    property bool leftDesktop: false
    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property var wifiDevices: Networking.devices.values.filter(
        device => device.type === DeviceType.Wifi && device.nmManaged)
    readonly property var wiredConnection: Networking.devices.values.find(
        device => device.type === DeviceType.Wired && device.connected)
    readonly property bool wifiConnected: wifiDevices.some(device => device.connected)

    readonly property var minimizedWindows: Hyprland.toplevels.values.filter(
        window => window.workspace?.name === "special:openhd-minimized"
    )

    function restoreWindow(window) {
        const address = window.address.replace(/^0x/, "")
        const workspace = Hyprland.focusedWorkspace?.id ?? 1
        if (!/^[a-fA-F0-9]+$/.test(address) || workspace < 1)
            return
        activeMenu = ""
        Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + workspace +
                          ', window = "address:0x' + address + '", follow = true })')
    }

    function toggleMenu(name) {
        activeMenu = activeMenu === name ? "" : name
    }

    function openNetwork() {
        toggleMenu("network")
    }

    function openNetworkSettings() {
        activeMenu = ""
        Quickshell.execDetached(["nm-connection-editor"])
    }

    function showHud(title, level) {
        hudTitle = title
        hudLevel = level
        hudTimeout.restart()
    }

    function switchSession(target) {
        if (switchTarget !== "" || sessionSwitch.running)
            return
        activeMenu = ""
        leftDesktop = false
        switchTarget = target
        revealSession.stop()
        coverSession.start()
    }

    function revealDesktop() {
        switchTarget = ""
        revealSession.restart()
    }

    FileView {
        id: currentView
        path: "/run/openhd-view/current"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (text().trim() !== "desktop")
                shell.leftDesktop = true
            else if (shell.switchTarget === "" || shell.leftDesktop)
                shell.revealDesktop()
        }
    }
    NumberAnimation {
        id: coverSession
        target: shell
        property: "sessionCover"
        to: 1
        duration: 240
        easing.type: Easing.InOutQuad
        onFinished: switchDelay.start()
    }
    NumberAnimation {
        id: revealSession
        target: shell
        property: "sessionCover"
        to: 0
        duration: 230
        easing.type: Easing.OutQuad
    }
    Timer {
        id: switchDelay
        interval: 45
        onTriggered: sessionSwitch.running = true
    }
    Process {
        id: sessionSwitch
        command: ["sudo", "-n", "/usr/local/sbin/openhd-switch-session", shell.switchTarget]
        stderr: StdioCollector { id: switchError }
        onExited: code => {
            if (code !== 0) {
                console.warn("OpenHD view switch failed:", shell.switchTarget, code, switchError.text.trim())
                shell.revealDesktop()
                shell.showHud("Could not switch view", -1)
            }
        }
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    IpcHandler {
        target: "desktop"
        function power(): void { shell.toggleMenu("power") }
        function network(): void { shell.openNetwork() }
        function flight(): void { shell.switchSession("flight") }
        function install(): void { shell.switchSession("install") }
        function taskManager(): void { Quickshell.execDetached(["/usr/local/sbin/openhd-task-manager"]) }
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
    Timer { interval: 10000; running: true; repeat: true; onTriggered: batteryProbe.running = true }
    Component.onCompleted: batteryProbe.running = true

    PanelWindow {
        anchors { top: true; left: true; right: true; bottom: true }
        color: "#010409"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Background
        mask: Region {}
        AlbatrossBackdrop { anchors.fill: parent }
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
        exclusionMode: ExclusionMode.Auto
        WlrLayershell.layer: WlrLayer.Top
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: "#d9081422"
            border.width: 1
            border.color: "#553d6885"
            RowLayout {
                id: barContents
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
                    id: minimizedButton
                    visible: shell.minimizedWindows.length > 0
                    text: "Minimized (" + shell.minimizedWindows.length + ")"
                    onClicked: shell.toggleMenu("minimized")
                }
                Button {
                    id: networkButton
                    Layout.preferredWidth: 42
                    Layout.fillHeight: true
                    Accessible.name: shell.wifiConnected ? "Wi-Fi connected" :
                                     shell.wiredConnection ? "Ethernet connected" : "Network controls"
                    onClicked: shell.openNetwork()
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: shell.openNetworkSettings()
                    }
                    background: Rectangle { radius: 8; color: networkButton.hovered || shell.activeMenu === "network" ? "#294057" : "transparent" }
                    contentItem: Text {
                        text: shell.wifiConnected || !shell.wiredConnection ? "\uf1eb" : "\uf0e8"
                        color: shell.wifiConnected || shell.wiredConnection ? "#e9f2fb" : "#718093"
                        font.family: "FontAwesome"
                        font.pixelSize: 16
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
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
                    ? appData.filter(app => !app.searchOnly && app.id !== "qgroundcontrol")
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
                    if (appId === "qopenhd") {
                        search.clear()
                        shell.switchSession("flight")
                        return
                    }
                    // Hyprland starts XWayland after the shell's startup hook.
                    // Dispatch here so X11 apps inherit the current display.
                    Quickshell.execDetached(["/usr/local/sbin/openhd-shell-action", "launch", appId])
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

    component MenuRow: ItemDelegate {
        id: row
        required property string glyph
        property string detail: ""
        Layout.fillWidth: true
        implicitHeight: 33
        leftPadding: 9
        rightPadding: 9
        hoverEnabled: true
        background: Rectangle {
            radius: 3
            color: row.down ? "#3a5672" : row.hovered || row.visualFocus ? "#334b64" : "transparent"
        }
        contentItem: RowLayout {
            spacing: 10
            Text {
                text: row.glyph
                color: row.enabled ? "#a9bfd3" : "#718093"
                font.family: "FontAwesome"
                font.pixelSize: 13
                Layout.preferredWidth: 16
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                text: row.text
                color: row.enabled ? "#edf4fa" : "#8290a0"
                font.family: "Inter"
                font.pixelSize: 13
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                visible: row.detail !== ""
                text: row.detail
                color: "#a9bfd3"
                font.family: "Inter"
                font.pixelSize: 11
            }
        }
    }

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.margins: 4
        color: "#495567"
    }

    component NetworkMenu: ColumnLayout {
        id: menu
        spacing: 1
        property var selectedNetwork: null
        property bool showPassword: false
        property string message: ""
        readonly property bool canSubmitPassword: selectedNetwork != null &&
            password.text.length >= (selectedNetwork.security === WifiSecurityType.Sae ? 1 : 8)
        readonly property var networks: {
            const entries = []
            for (const device of shell.wifiDevices) {
                if (device.mode === WifiDeviceMode.AccessPoint) continue
                for (const network of device.networks.values) {
                    if (network.name !== "") entries.push(network)
                }
            }
            entries.sort((a, b) => Number(b.connected) - Number(a.connected) ||
                                  b.signalStrength - a.signalStrength)
            const seen = new Set()
            return entries.filter(network => {
                const key = JSON.stringify([network.name, network.security])
                if (seen.has(key)) return false
                seen.add(key)
                return true
            })
        }

        function supportsPassword(network) {
            return [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae]
                .includes(network.security)
        }

        function choose(network) {
            selectedNetwork = network
            showPassword = false
            password.clear()
            message = ""
            if (network.connected)
                network.disconnect()
            else if (network.known || network.security === WifiSecurityType.Open ||
                     network.security === WifiSecurityType.Owe)
                network.connect()
            else if (supportsPassword(network)) {
                showPassword = true
                password.forceActiveFocus()
            } else
                message = "Use Edit connections to configure this network."
        }

        function connectWithPassword() {
            if (!showPassword || !canSubmitPassword)
                return
            const secret = password.text
            password.clear()
            showPassword = false
            message = ""
            selectedNetwork.connectWithPsk(secret)
        }

        onVisibleChanged: if (!visible) {
            selectedNetwork = null
            showPassword = false
            message = ""
            password?.clear()
        }

        Connections {
            target: menu.selectedNetwork
            function onConnectionFailed(reason) {
                if (!menu.visible || !menu.selectedNetwork)
                    return
                menu.message = "Could not connect to " + menu.selectedNetwork.name
                if (reason === ConnectionFailReason.NoSecrets && menu.supportsPassword(menu.selectedNetwork)) {
                    menu.showPassword = true
                    password.forceActiveFocus()
                }
            }
        }

        Repeater {
            model: shell.wifiDevices
            delegate: Item {
                required property var modelData
                visible: false
                Binding {
                    target: modelData
                    property: "scannerEnabled"
                    value: menu.visible && Networking.wifiEnabled && modelData.mode !== WifiDeviceMode.AccessPoint
                }
            }
        }

        MenuRow {
            visible: shell.wiredConnection != null
            glyph: "\uf0e8"
            text: "Ethernet"
            detail: "Connected"
            enabled: false
        }
        MenuRow {
            glyph: "\uf1eb"
            text: "Wi-Fi"
            detail: !Networking.wifiHardwareEnabled || shell.wifiDevices.length === 0 ? "Unavailable" :
                    Networking.wifiEnabled ? "On" : "Off"
            enabled: Networking.wifiHardwareEnabled && shell.wifiDevices.length > 0
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
        }
        MenuSeparator { visible: Networking.wifiEnabled && shell.wifiDevices.length > 0 }
        Text {
            visible: Networking.wifiEnabled && shell.wifiDevices.length > 0 && menu.networks.length === 0
            Layout.fillWidth: true
            Layout.margins: 9
            text: "Searching for networks…"
            color: "#a9bfd3"
            font.family: "Inter"
            font.pixelSize: 13
        }
        ListView {
            visible: Networking.wifiEnabled && menu.networks.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(5, count) * 33
            clip: true
            model: menu.networks
            ScrollBar.vertical: ScrollBar {}
            delegate: MenuRow {
                required property var modelData
                width: ListView.view.width
                text: modelData.name
                glyph: modelData.connected ? "\uf00c" :
                       modelData.security === WifiSecurityType.Open ? "\uf1eb" : "\uf023"
                detail: modelData.connected ? "Connected" :
                        modelData.stateChanging ? "Connecting…" : Math.round(modelData.signalStrength * 100) + "%"
                enabled: !modelData.stateChanging
                onClicked: menu.choose(modelData)
            }
        }
        Text {
            visible: menu.message !== ""
            Layout.fillWidth: true
            Layout.margins: 9
            wrapMode: Text.Wrap
            text: menu.message
            color: "#a9bfd3"
            font.family: "Inter"
            font.pixelSize: 12
        }
        RowLayout {
            visible: menu.showPassword
            Layout.fillWidth: true
            Layout.margins: 4
            TextField {
                id: password
                Layout.fillWidth: true
                implicitHeight: 32
                leftPadding: 9
                rightPadding: 9
                font.family: "Inter"
                font.pixelSize: 13
                color: "#edf4fa"
                placeholderTextColor: "#a9bfd3"
                selectionColor: "#334b64"
                echoMode: TextInput.Password
                placeholderText: "Wi-Fi password"
                Accessible.name: "Wi-Fi password"
                background: Rectangle {
                    radius: 4
                    color: "#182432"
                    border.width: 1
                    border.color: password.activeFocus ? "#73d7ee" : "#536275"
                }
                onAccepted: menu.connectWithPassword()
            }
            Button {
                id: connectButton
                implicitHeight: 32
                horizontalPadding: 10
                text: "Connect"
                enabled: menu.canSubmitPassword
                contentItem: Text {
                    text: connectButton.text
                    color: connectButton.enabled ? "#edf4fa" : "#8290a0"
                    font.family: "Inter"
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 4
                    color: connectButton.enabled ? (connectButton.hovered ? "#3a5672" : "#334b64") : "#222b36"
                    border.width: 1
                    border.color: connectButton.visualFocus ? "#73d7ee" : "#536275"
                }
                onClicked: menu.connectWithPassword()
            }
        }
        MenuSeparator {}
        MenuRow {
            glyph: "\uf013"
            text: "Edit connections"
            onClicked: shell.openNetworkSettings()
        }
    }

    PanelWindow {
        id: networkPopup
        visible: shell.activeMenu === "network"
        screen: topBar.screen
        anchors { top: true; right: true }
        margins {
            top: topBar.margins.top + topBar.height
            right: topBar.margins.right + topBar.width - barContents.x - networkButton.x - networkButton.width
        }
        implicitWidth: 278
        implicitHeight: networkMenu.implicitHeight + 10
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "transparent"

        HyprlandFocusGrab {
            windows: [networkPopup, topBar]
            active: networkPopup.visible
            onCleared: if (shell.activeMenu === "network") shell.activeMenu = ""
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: "#282e37"
            border { width: 1; color: "#536275" }
            focus: true
            Keys.onEscapePressed: shell.activeMenu = ""
            NetworkMenu {
                id: networkMenu
                visible: networkPopup.visible
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 5 }
            }
        }
    }

    PanelWindow {
        id: controlsMenu
        visible: shell.activeMenu !== "" && shell.activeMenu !== "network"
        screen: topBar.screen
        anchors { top: true; left: true }
        readonly property bool powerMenu: shell.activeMenu === "power"
        readonly property Item button: powerMenu ? brandButton :
                               shell.activeMenu === "minimized" ? minimizedButton : audioButton
        readonly property int inset: powerMenu ? 5 : 14
        margins {
            top: topBar.margins.top + topBar.height
            left: Math.max(0, topBar.margins.left + barContents.x + controlsMenu.button.x +
                           (controlsMenu.powerMenu ? 0 : controlsMenu.button.width - controlsMenu.implicitWidth))
        }
        implicitWidth: powerMenu ? 232 : 278
        implicitHeight: menuContents.implicitHeight + inset * 2
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "transparent"

        HyprlandFocusGrab {
            windows: [topBar, controlsMenu]
            active: controlsMenu.visible
            onCleared: if (shell.activeMenu !== "network") shell.activeMenu = ""
        }

        Rectangle {
            anchors.fill: parent
            radius: controlsMenu.powerMenu ? 6 : 14
            color: controlsMenu.powerMenu ? "#282e37" : "#ed0b1725"
            border.width: 1
            border.color: controlsMenu.powerMenu ? "#536275" : "#805184a3"
            focus: true
            Keys.onEscapePressed: shell.activeMenu = ""
            ColumnLayout {
                id: menuContents
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: controlsMenu.inset }
                spacing: controlsMenu.powerMenu ? 1 : 6
                Text { visible: !controlsMenu.powerMenu; text: shell.activeMenu === "minimized" ? "Minimized windows" : "Sound"; color: "#f4f8fc"; font.family: "Inter"; font.pixelSize: 16; font.weight: Font.DemiBold }
                Repeater {
                    model: shell.activeMenu === "minimized" ? shell.minimizedWindows : []
                    delegate: Button {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.title || "Window"
                        onClicked: shell.restoreWindow(modelData)
                    }
                }
                MenuRow {
                    visible: controlsMenu.powerMenu
                    glyph: "\uf019"
                    text: "Install OpenHD OS"
                    onClicked: shell.switchSession("install")
                }
                MenuRow {
                    visible: controlsMenu.powerMenu
                    glyph: "\uf080"
                    text: "Task Manager"
                    onClicked: {
                        shell.activeMenu = ""
                        Quickshell.execDetached(["/usr/local/sbin/openhd-task-manager"])
                    }
                }
                MenuSeparator {
                    visible: controlsMenu.powerMenu
                }
                MenuRow {
                    visible: controlsMenu.powerMenu
                    glyph: "\uf021"
                    text: "Restart"
                    onClicked: powerAction.run("reboot")
                }
                MenuRow {
                    visible: controlsMenu.powerMenu
                    glyph: "\uf011"
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
                command = ["sudo", "-n", "/usr/bin/systemctl", "--no-block", action]
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

    PanelWindow {
        visible: shell.sessionCover > 0
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        SessionCurtain {
            anchors.fill: parent
            coverage: shell.sessionCover
        }
    }
}
