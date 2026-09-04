import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import ".." as Cyber

// Bluetooth panel -- replaces blueman-manager/blueman-applet. Opened via
// `qs ipc call bt toggle`, fresh instance per open (Launcher.qml pattern).
// QEMU VMs expose no adapter: the panel shows "No Bluetooth adapter".
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

    readonly property var adapter: Bluetooth.defaultAdapter
    // Connected first, then paired, then by name.
    readonly property var devices: {
        const list = (adapter?.devices.values ?? []).slice();
        return list.sort((a, b) => (b.connected - a.connected)
            || (b.paired - a.paired)
            || (a.name ?? "").localeCompare(b.name ?? ""));
    }

    // Discover while the panel is open (only when the radio is on).
    Component.onCompleted: if (adapter && adapter.enabled) adapter.discovering = true
    Component.onDestruction: if (adapter) adapter.discovering = false

    function activate(dev) {
        if (dev.connected)    { dev.disconnect(); return; }
        if (dev.pairing)      { dev.cancelPair(); return; }
        if (dev.paired || dev.bonded) { dev.connect(); return; }
        dev.pair();
    }
    function statusText(dev) {
        if (dev.pairing) return "pairing…";
        if (dev.state === BluetoothDeviceState.Connecting) return "connecting…";
        if (dev.connected) return dev.batteryAvailable
            ? "connected · " + Math.round(dev.battery * 100) + "%" : "connected";
        return dev.paired || dev.bonded ? "paired" : "";
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 44; rightMargin: 8 }
        width: 340
        height: 420
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
                    text: "Bluetooth"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }
                Item { Layout.fillWidth: true }
                Switch {
                    enabled: root.adapter !== null
                    checked: root.adapter?.enabled ?? false
                    onToggled: if (root.adapter) {
                        root.adapter.enabled = checked;
                        if (checked) root.adapter.discovering = true;
                    }
                }
            }

            Text {
                visible: root.adapter === null
                text: "No Bluetooth adapter"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
            }

            Text {
                visible: (root.adapter?.discovering ?? false)
                text: "Scanning…"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: ScriptModel {
                    values: root.devices
                    comparisonMode: ObjectComparison.Identity
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: 40
                    radius: Cyber.Theme.radius / 2
                    color: rowMouse.containsMouse ? Cyber.Theme.sel : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name || row.modelData.deviceName || row.modelData.address
                            textFormat: Text.PlainText
                            color: row.modelData.connected ? Cyber.Theme.accent : Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                            elide: Text.ElideRight
                        }
                        Text {
                            text: root.statusText(row.modelData)
                            textFormat: Text.PlainText
                            color: Cyber.Theme.muted
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (row.modelData.paired || row.modelData.bonded) row.modelData.forget();
                            } else {
                                root.activate(row.modelData);
                            }
                        }
                    }
                }
            }

            Text {
                text: "Click to connect/pair · right-click to forget · Esc to close"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
            }
        }
    }
}
