import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import ".." as Cyber

// The battery chip's panel: what the battery is doing right now, and which
// power profile the machine is running. Opened via `qs ipc call powerprofile
// toggle`, built fresh on open like every other popup here.
//
// This deliberately does NOT offer sleep/lock/restart/shutdown -- the bar has a
// dedicated power button for those, and the battery chip used to open that same
// menu, which told a student nothing about their battery.
//
// Profiles come from power-profiles-daemon over D-Bus; PowerProfiles.profile is
// writable, so selecting a row is a plain assignment. `changeRate` is UPower's
// charge/discharge figure in watts.
//
// NOT named PowerProfile.qml: a file's own name becomes a component type in its
// directory, which would shadow Quickshell's PowerProfile singleton and make
// every `PowerProfile.PowerSaver` resolve to this file instead -- silently
// undefined at runtime. qmllint catches it as a missing-property warning.
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

    readonly property var dev: UPower.displayDevice
    readonly property bool haveBattery: dev?.isLaptopBattery ?? false
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
    // changeRate is unsigned: the direction comes from the state, not the sign.
    readonly property real watts: dev?.changeRate ?? 0
    readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)

    // timeToEmpty/timeToFull are seconds; 0 means "not known yet", which UPower
    // reports for a while after a state change, so render nothing rather than
    // a confident "0m".
    function humanTime(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    readonly property string remaining:
        root.charging ? root.humanTime(root.dev?.timeToFull ?? 0)
                      : root.humanTime(root.dev?.timeToEmpty ?? 0)

    function setProfile(p) { PowerProfiles.profile = p; }

    // One row per selectable profile. Inline component so the three rows and
    // their selected/hover states are defined once.
    component ProfileRow: Rectangle {
        id: prow
        required property int value
        required property string title
        required property string subtitle
        readonly property bool selected: PowerProfiles.profile === prow.value
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Cyber.Theme.radius / 2
        color: prow.selected ? Cyber.Theme.sel
             : rowMouse.containsMouse ? Cyber.Theme.surface : "transparent"

        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 8
            // dot-circle when active, plain circle when not.
            Text {
                text: prow.selected ? "\uf192" : "\uf111"
                color: prow.selected ? Cyber.Theme.accent : Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: prow.title
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                }
                Text {
                    text: prow.subtitle
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4 }
                }
            }
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.setProfile(prow.value)
        }
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 44; rightMargin: 8 }
        width: 340
        height: 300
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
            anchors { fill: parent; margins: 12 }
            spacing: 8

            // ---- what the battery is doing ----
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.haveBattery ? root.pct + "%" : "Power"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 4; bold: true }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.haveBattery && root.watts > 0
                    text: root.watts.toFixed(1) + " W"
                    color: root.charging ? Cyber.Theme.accent : Cyber.Theme.accent2
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.haveBattery
                text: {
                    const dir = root.charging ? "charging" : "discharging";
                    return root.remaining !== ""
                        ? dir + " · " + root.remaining + (root.charging ? " until full" : " remaining")
                        : dir;
                }
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                elide: Text.ElideRight
            }
            Text {
                visible: !root.haveBattery
                text: "No battery detected · running on AC"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Cyber.Theme.border
            }

            Text {
                text: "Power mode"
                color: Cyber.Theme.accent
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
            }

            ProfileRow {
                value: PowerProfile.PowerSaver
                title: "Power Saver"
                subtitle: "Longest battery life"
            }
            ProfileRow {
                value: PowerProfile.Balanced
                title: "Balanced"
                subtitle: "Default"
            }
            // Plenty of laptops expose no performance profile; showing a row
            // that cannot be selected would just look broken.
            ProfileRow {
                visible: PowerProfiles.hasPerformanceProfile
                value: PowerProfile.Performance
                title: "Performance"
                subtitle: "Highest speed, more heat"
            }

            // Firmware throttling (lap detection, thermals) explains why
            // Performance may not take effect.
            Text {
                Layout.fillWidth: true
                visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                text: "Performance limited: "
                    + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
                color: Cyber.Theme.alert
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                wrapMode: Text.Wrap
            }

            Item { Layout.fillHeight: true }

            Text {
                text: "Esc to close"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
            }
        }
    }
}
