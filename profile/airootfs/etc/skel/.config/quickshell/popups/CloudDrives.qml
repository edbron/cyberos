import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Cyber

// Bar chip + popup: connect Google Drive, OneDrive, and iCloud Drive as
// folders under ~/Cloud. Inspired by the UX of
// github.com/edbron/omarchy-cloud-drives, but not a port of its QML: that
// plugin's Panel.qml is built on Omarchy's own component framework and a
// keyboard-cursor system this shell doesn't have. All the real work --
// rclone, the encrypted config, the keyring secret, the systemd mount unit
// -- is unchanged, vendored as cyberos-cloud-drives (see that script's own
// header for the three places it had to diverge from the Omarchy-specific
// original); this file only draws state with Cyber.Theme and dispatches
// mouse clicks + Escape, matching every other popup here.
//
// connect/disconnect need a real interactive terminal (browser sign-in,
// 2FA, a confirm prompt) -- those two actions launch
// cyberos-cloud-drives in a floating foot window (see hyprland.lua's
// float-cloud-drives window_rule) and close this popup rather than trying
// to run interactively inside it. mount/unmount/open are silent, run
// in place, and the popup just waits for them and refreshes.
//
// Always loaded (shell.qml's `cloudDrives` LazyLoader has `active: true`),
// matching popups/SystemHealth.qml and popups/MonitorArrange.qml:
// bar/CloudDrivesChip.qml needs a live "any drive mounted" count to colour
// itself even while this panel is closed. `visible: root.opened` is what
// actually shows the window.
PanelWindow {
    id: root

    // top/right stay permanently anchored (matches every closed-state
    // geometry a freshly-opened window here would have); left/bottom only
    // join in while actually open, so Cyber.ClickOutside gets a real
    // "outside" region to catch a click in without this always-loaded
    // window (never destroyed) turning into a permanent, invisible
    // full-desktop click-blocker while closed.
    anchors { top: true; right: true; left: root.opened; bottom: root.opened }
    implicitWidth: 380
    implicitHeight: 360
    color: "transparent"
    focusable: true
    aboveWindows: true
    visible: root.opened

    property bool opened: false
    function open() { root.opened = true; root.refresh(); }
    function close() { root.opened = false; }
    function toggle() { root.opened ? root.close() : root.open(); }

    Cyber.ClickOutside { onOutsideClicked: root.close() }

    property bool rcloneInstalled: false
    property bool encrypted: false
    property bool keyring: false
    property string mountRoot: ""
    property var providers: []
    property bool busy: false

    readonly property int mountedCount: root.providers.filter(p => p.mounted).length
    readonly property int connectedCount: root.providers.filter(p => p.configured).length
    readonly property bool secure: root.rcloneInstalled && root.encrypted && root.keyring

    function actionsFor(p) {
        if (!p) return [];
        if (!p.configured) return ["connect"];
        const a = [p.mounted ? "unmount" : "mount"];
        if (p.mounted) a.unshift("open");
        a.push("disconnect");
        return a;
    }
    readonly property var actionLabels: ({
        connect: "Connect", open: "Open", mount: "Mount", unmount: "Unmount", disconnect: "Forget"
    })

    function refresh() { if (!stateProc.running) stateProc.running = true; }

    // connect/disconnect need a terminal (browser sign-in, 2FA, confirm);
    // mount/unmount/open are silent and stay in this popup.
    function run(action, id) {
        if (root.busy) return;
        if (action === "connect" || action === "disconnect") {
            Quickshell.execDetached(["cyberos-cloud-drives", "launch", action, id]);
            root.close();
            return;
        }
        root.busy = true;
        actionProc.exec(["cyberos-cloud-drives", action, id]);
    }

    // Same poll cadence as popups/SystemHealth.qml and popups/MonitorArrange.qml.
    Timer {
        interval: root.opened ? 3000 : 20000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: root.refresh()

    Process {
        id: stateProc
        command: ["cyberos-cloud-drives", "state"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const s = JSON.parse(text || "{}");
                    root.rcloneInstalled = !!s.rclone;
                    root.encrypted = !!s.encrypted;
                    root.keyring = !!s.keyring;
                    root.mountRoot = s.root || "";
                    root.providers = s.providers || [];
                } catch (e) {
                    root.providers = [];
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
        width: 380
        height: 360
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
                    text: "Cloud Drives"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.fillWidth: true
                text: root.connectedCount === 0
                    ? "No accounts connected"
                    : root.mountedCount + " of " + root.connectedCount + " mounted"
                        + " · " + (root.secure ? "keyring-encrypted" : "config not encrypted")
                textFormat: Text.PlainText
                color: root.secure || root.connectedCount === 0 ? Cyber.Theme.muted : Cyber.Theme.alert
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Cyber.Theme.border }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Repeater {
                    model: root.providers
                    delegate: ColumnLayout {
                        id: provRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: provRow.modelData.glyph
                                color: Cyber.Theme.accent
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: provRow.modelData.name
                                    textFormat: Text.PlainText
                                    color: Cyber.Theme.fg
                                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                                }
                                Text {
                                    text: !provRow.modelData.configured ? "Not connected"
                                        : provRow.modelData.mounted ? "Mounted at " + provRow.modelData.path
                                        : "Connected, not mounted"
                                    textFormat: Text.PlainText
                                    color: Cyber.Theme.muted
                                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 220
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.actionsFor(provRow.modelData)
                                delegate: Cyber.Pill {
                                    required property string modelData
                                    // No "active" highlight here (unlike
                                    // MonitorArrange's use of Pill): none of
                                    // these represent a current selection,
                                    // they're just the actions available
                                    // for this provider's current state.
                                    label: root.actionLabels[modelData]
                                    busy: root.busy
                                    onActivated: root.run(modelData, provRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !root.rcloneInstalled
                text: "rclone/fuse3 not found -- both should already be installed on this image."
                textFormat: Text.PlainText
                color: Cyber.Theme.alert
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                wrapMode: Text.Wrap
            }
        }
    }
}
