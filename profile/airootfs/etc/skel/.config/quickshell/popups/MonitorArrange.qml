import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Cyber

// Bar chip + popup: place an external monitor around the internal display
// and set each monitor's refresh rate. Inspired by the UX of
// github.com/edbron/omarchy-monitor-placement-refresh-rate, but not a port
// of its QML: that plugin's Panel.qml is built entirely on Omarchy's own
// shell framework (a qs.Ui/qs.Commons component library, a multi-section
// h/j/k/l keyboard-cursor state machine) that this shell doesn't have. All
// the real work -- reading hyprctl, computing placement, persisting to
// monitors.lua -- is unchanged, vendored as cyberos-monitor-arrange
// (bin/omarchy-monitor-arrange with one hardening fix, see that script's
// own header comment); this file only draws state with Cyber.Theme and
// dispatches mouse clicks + Escape, matching every other popup in this
// shell rather than reproducing the source plugin's own keyboard-cursor
// system.
//
// Always loaded (shell.qml's `monitorArrange` LazyLoader has `active: true`),
// matching popups/SystemHealth.qml: bar/MonitorChip.qml needs live "any
// external connected" state to pick its icon even while this panel is
// closed. `visible: root.opened` is what actually shows the window.
PanelWindow {
    id: root

    // top/right stay permanently anchored (matches every closed-state
    // geometry a freshly-opened window here would have); left/bottom only
    // join in while actually open, so Cyber.ClickOutside gets a real
    // "outside" region to catch a click in without this always-loaded
    // window (never destroyed) turning into a permanent, invisible
    // full-desktop click-blocker while closed.
    anchors { top: true; right: true; left: root.opened; bottom: root.opened }
    implicitWidth: 360
    implicitHeight: 460
    color: "transparent"
    focusable: true
    aboveWindows: true
    visible: root.opened

    property bool opened: false
    function open() { root.opened = true; root.refresh(); }
    function close() { root.opened = false; }
    function toggle() { root.opened ? root.close() : root.open(); }

    Cyber.ClickOutside { onOutsideClicked: root.close() }

    readonly property var directions: ["left", "right", "top", "bottom"]
    readonly property var directionLabels: ({ left: "Left", right: "Right", top: "Above", bottom: "Below" })

    property string internalMonitor: ""
    property var externals: []
    property var monitors: []
    property int targetIndex: 0
    readonly property var target: root.externals.length > 0 && root.targetIndex < root.externals.length
        ? root.externals[root.targetIndex] : null
    property bool busy: false

    function refresh() { if (!stateProc.running) stateProc.running = true; }
    onExternalsChanged: if (root.targetIndex >= root.externals.length) root.targetIndex = 0;

    function arrange(direction) {
        if (!root.target || root.busy) return;
        root.busy = true;
        actionProc.exec(["cyberos-monitor-arrange", direction, root.target.name]);
    }
    function setRate(name, hz) {
        if (!name || root.busy) return;
        root.busy = true;
        actionProc.exec(["cyberos-monitor-arrange", "rate", name, String(hz)]);
    }

    // Same poll cadence as popups/SystemHealth.qml: a display can be
    // plugged/unplugged while this panel is closed, and the bar chip's icon
    // needs to track that.
    Timer {
        interval: root.opened ? 3000 : 20000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: root.refresh()

    Process {
        id: stateProc
        command: ["cyberos-monitor-arrange", "state"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const s = JSON.parse(text || "{}");
                    root.internalMonitor = s.internal || "";
                    root.externals = s.externals || [];
                    root.monitors = s.monitors || [];
                } catch (e) {
                    root.externals = [];
                    root.monitors = [];
                }
            }
        }
    }

    // No output is read from this one -- only whether/when it finishes.
    Process {
        id: actionProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 44; rightMargin: 8 }
        width: 360
        height: 460
        radius: Cyber.Theme.radius
        color: Cyber.Theme.bg
        border.width: 1
        border.color: Cyber.Theme.border

        focus: true
        Keys.onEscapePressed: root.close()

        // Swallows a click on blank space inside the popup: a plain
        // Rectangle doesn't itself accept mouse events, so without this a
        // click here would fall through to Cyber.ClickOutside behind the
        // whole window and close the popup it landed inside.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Monitor Arrange"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.fillWidth: true
                text: root.target
                    ? root.target.name + (root.target.placement
                        ? " · " + root.directionLabels[root.target.placement].toLowerCase() + " of " + root.internalMonitor
                        : " · overlapping " + root.internalMonitor)
                    : "No external display connected"
                textFormat: Text.PlainText
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Cyber.Theme.border }

            // ---- external monitor picker (only with several) ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.externals.length > 1
                spacing: 4

                Text {
                    text: "EXTERNAL DISPLAY"
                    color: Cyber.Theme.accent
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                }
                Repeater {
                    model: root.externals
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Cyber.Theme.radius / 2
                        color: index === root.targetIndex ? Cyber.Theme.sel : "transparent"
                        Text {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: modelData.name
                            textFormat: Text.PlainText
                            color: Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.targetIndex = index
                        }
                    }
                }
            }

            // ---- placement ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.externals.length > 0
                spacing: 4

                Text {
                    text: "PLACE"
                    color: Cyber.Theme.accent
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.directions
                        delegate: Cyber.Pill {
                            required property string modelData
                            label: root.directionLabels[modelData]
                            active: !!(root.target && root.target.placement === modelData)
                            busy: root.busy
                            onActivated: root.arrange(modelData)
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Cyber.Theme.border; visible: root.monitors.length > 0 }

            // ---- refresh rate, one row per monitor ----
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: root.monitors.length > 0

                ColumnLayout {
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: root.monitors
                        delegate: ColumnLayout {
                            id: rateRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: rateRow.modelData.name + (rateRow.modelData.internal ? " · built-in" : "")
                                    textFormat: Text.PlainText
                                    color: Cyber.Theme.muted
                                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3; bold: true }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: rateRow.modelData.refreshRate + " Hz"
                                    color: Cyber.Theme.muted
                                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3; bold: true }
                                }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: rateRow.modelData.rates || []
                                    delegate: Cyber.Pill {
                                        required property var modelData
                                        label: modelData + " Hz"
                                        active: modelData === rateRow.modelData.refreshRate
                                        busy: root.busy
                                        onActivated: root.setRate(rateRow.modelData.name, modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.externals.length === 0
                text: "Connect an external monitor to arrange it around "
                    + (root.internalMonitor || "the internal display") + "."
                textFormat: Text.PlainText
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
                wrapMode: Text.Wrap
            }

            Item { Layout.fillHeight: true; visible: root.externals.length === 0 }
        }
    }
}
