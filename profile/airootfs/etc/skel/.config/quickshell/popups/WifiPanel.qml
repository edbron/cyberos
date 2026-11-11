import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import ".." as Cyber

// Wi-Fi panel -- replaces nm-applet + nm-connection-editor. Opened/closed
// via `qs ipc call wifi toggle` (LazyLoader in shell.qml), created fresh on
// every open like Launcher.qml, so per-open state (the inline password
// prompt) resets for free. QEMU VMs have no Wi-Fi device: the panel then
// shows the wired status line and a "No Wi-Fi adapter" placeholder.
PanelWindow {
    id: root

    signal closeRequested()

    // Fullscreen, transparent surface: the visible box below positions
    // itself via its own anchors/margins instead of the window's, so
    // Cyber.ClickOutside (this window's first child, right below) has a
    // real "outside" region to catch a click in -- a window sized to just
    // the popup itself has no such region.
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    focusable: true
    aboveWindows: true

    Cyber.ClickOutside { onOutsideClicked: root.closeRequested() }

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    // Connected network first, then by signal strength.
    readonly property var networks: {
        const list = (wifiDevice?.networks.values ?? []).slice();
        return list.sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength));
    }
    // Name of the network whose inline password prompt is open ("" = none).
    property string pskFor: ""

    // Scan only while the panel is open.
    Component.onCompleted: if (wifiDevice) wifiDevice.scannerEnabled = true
    Component.onDestruction: if (wifiDevice) wifiDevice.scannerEnabled = false

    function needsPsk(net) {
        return !net.known
            && (net.security === WifiSecurityType.WpaPsk
             || net.security === WifiSecurityType.Wpa2Psk
             || net.security === WifiSecurityType.Sae);
    }
    function activate(net) {
        if (net.connected)      { net.disconnect(); return; }
        if (root.needsPsk(net)) { root.pskFor = net.name; return; }
        net.connect();
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 44; rightMargin: 8 }
        width: 360
        height: 440
        radius: Cyber.Theme.radius
        color: Cyber.Theme.bg
        border.width: 1
        border.color: Cyber.Theme.border

        focus: true
        Keys.onEscapePressed: root.closeRequested()

        // Swallows a click on blank space inside the popup: a plain
        // Rectangle doesn't itself accept mouse events, so without this a
        // click here would fall through to Cyber.ClickOutside behind the
        // whole window and close the popup it landed inside.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Wi-Fi"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }
                Item { Layout.fillWidth: true }
                Switch {
                    checked: Networking.wifiEnabled
                    enabled: Networking.wifiHardwareEnabled
                    onToggled: Networking.wifiEnabled = checked
                }
            }

            Text {
                visible: root.wiredDevice !== null
                text: (root.wiredDevice?.connected ?? false) ? "Wired: connected" : "Wired: no link"
                color: (root.wiredDevice?.connected ?? false) ? Cyber.Theme.accent : Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
            }

            Text {
                visible: root.wifiDevice === null
                text: "No Wi-Fi adapter"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: ScriptModel {
                    values: root.networks
                    comparisonMode: ObjectComparison.Identity
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: pskField.visible ? 72 : 40
                    radius: Cyber.Theme.radius / 2
                    color: rowMouse.containsMouse ? Cyber.Theme.sel : "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                textFormat: Text.PlainText
                                color: row.modelData.connected ? Cyber.Theme.accent : Cyber.Theme.fg
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                                elide: Text.ElideRight
                            }
                            Text {
                                // lock glyph for secured networks (FontAwesome nf-fa-lock)
                                visible: row.modelData.security !== WifiSecurityType.Open
                                      && row.modelData.security !== WifiSecurityType.Owe
                                text: "\uf023"
                                color: Cyber.Theme.muted
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                            }
                            Text {
                                text: row.modelData.state === ConnectionState.Connecting
                                    ? "…" : Math.round(row.modelData.signalStrength) + "%"
                                color: Cyber.Theme.muted
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                            }
                        }

                        TextField {
                            id: pskField
                            Layout.fillWidth: true
                            visible: root.pskFor === row.modelData.name
                            placeholderText: "Password"
                            placeholderTextColor: Cyber.Theme.muted
                            color: Cyber.Theme.fg
                            echoMode: TextInput.Password
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                            background: Rectangle {
                                color: Cyber.Theme.surface
                                radius: Cyber.Theme.radius / 2
                                border.width: 1
                                border.color: Cyber.Theme.border
                            }
                            onVisibleChanged: if (visible) forceActiveFocus()
                            onAccepted: {
                                row.modelData.connectWithPsk(text);
                                root.pskFor = "";
                            }
                            Keys.onEscapePressed: root.pskFor = ""
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Let clicks reach the password field when it is open.
                        enabled: !pskField.visible
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (row.modelData.known) row.modelData.forget();
                            } else {
                                root.activate(row.modelData);
                            }
                        }
                    }
                }
            }

            Text {
                text: "Click to connect · right-click to forget · Esc to close"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
            }
        }
    }
}
