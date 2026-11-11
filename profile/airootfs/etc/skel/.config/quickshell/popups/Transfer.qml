import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Cyber

// Bar chip + popup: monitor and control filetransferd's copy/move queue,
// talking to it purely through the `ftctl` CLI (short-lived subprocesses,
// no direct socket code here) -- vendored in Task 2 alongside the daemon.
// Inspired by the UX of github.com/DevInBlack001/arch-transfer-manager's
// own Panel.qml/Service.qml, but not a port of that QML: that plugin is
// built on Omarchy's own Quickshell-plugin component framework
// (`import qs.Commons`, a manifest-driven bar-widget loader) this shell
// doesn't have. The polling/parsing/control logic is reimplemented here
// natively, the same treatment popups/CloudDrives.qml gives the Omarchy
// cloud-drives plugin's Panel.qml (see that file's own header).
//
// Always loaded (shell.qml's `transfer` LazyLoader has `active: true`),
// matching popups/CloudDrives.qml: bar/TransferChip.qml needs live
// active-count/error state to colour itself even while this panel is
// closed. `visible: root.opened` is what actually shows the window.
PanelWindow {
    id: root

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

    property var jobs: []
    property bool lastOk: true
    property string lastError: ""
    property bool busy: false

    readonly property int activeCount: root.jobs.filter(j => j.state === "running" || j.state === "queued" || j.state === "paused").length
    readonly property bool hasError: !root.lastOk || root.jobs.some(j => j.state === "error")

    function baseName(path) {
        var parts = String(path || "").replace(/\/$/, "").split("/");
        return parts.pop() || String(path || "");
    }
    function jobTitle(job) {
        if (!job || !job.sources || job.sources.length === 0) return "Transfer";
        var first = root.baseName(job.sources[0]);
        var extra = job.sources.length - 1;
        return extra > 0 ? (first + " + " + extra + " more") : first;
    }
    function statusLabel(job) {
        switch (job.state) {
            case "queued": return "Queued";
            case "running": return "Transferring";
            case "paused": return "Paused";
            case "done": return "Done";
            case "error": return "Failed";
            case "cancelled": return "Cancelled";
            default: return job.state || "";
        }
    }
    function percentFor(job) {
        if (!job || !job.bytesTotal || job.bytesTotal <= 0) return -1;
        return Math.max(0, Math.min(100, Math.round((job.bytesDone / job.bytesTotal) * 100)));
    }

    function refresh() { if (!listProc.running) listProc.running = true; }

    function run(action, id) {
        if (root.busy) return;
        root.busy = true;
        actionProc.command = ["ftctl", action, id];
        actionProc.running = true;
    }
    function clearFinished() {
        if (root.busy) return;
        root.busy = true;
        actionProc.command = ["ftctl", "clear"];
        actionProc.running = true;
    }

    // Same poll cadence as popups/CloudDrives.qml.
    Timer {
        interval: root.opened ? 3000 : 20000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: root.refresh()

    Process {
        id: listProc
        command: ["ftctl", "list"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text || "{}");
                    root.lastOk = parsed.ok === true;
                    root.jobs = Array.isArray(parsed.jobs) ? parsed.jobs : [];
                    root.lastError = parsed.ok ? "" : (parsed.error || "Could not reach the transfer daemon");
                } catch (e) {
                    root.lastOk = false;
                    root.jobs = [];
                    root.lastError = "Could not reach the transfer daemon";
                }
            }
        }
    }

    Process {
        id: actionProc
        running: false
        command: []
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

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Transfers"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.fillWidth: true
                text: !root.lastOk
                    ? (root.lastError || "Daemon unreachable")
                    : (root.jobs.length === 0 ? "Nothing queued" : root.activeCount + " active")
                textFormat: Text.PlainText
                color: root.lastOk ? Cyber.Theme.muted : Cyber.Theme.alert
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Cyber.Theme.border }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Repeater {
                    model: root.jobs
                    delegate: ColumnLayout {
                        id: jobRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: root.jobTitle(jobRow.modelData)
                                textFormat: Text.PlainText
                                color: Cyber.Theme.fg
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                                elide: Text.ElideMiddle
                            }
                            Text {
                                text: root.statusLabel(jobRow.modelData)
                                textFormat: Text.PlainText
                                color: jobRow.modelData.state === "error" ? Cyber.Theme.alert : Cyber.Theme.muted
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: jobRow.modelData.state === "running" || jobRow.modelData.state === "queued" || jobRow.modelData.state === "paused"

                            Text {
                                text: jobRow.modelData.state === "paused" ? "Resume" : "Pause"
                                color: Cyber.Theme.accent
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.run(jobRow.modelData.state === "paused" ? "resume" : "pause", jobRow.modelData.id)
                                }
                            }
                            Text {
                                text: "Cancel"
                                color: Cyber.Theme.alert
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.run("cancel", jobRow.modelData.id)
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Text {
                    visible: root.jobs.some(j => j.state === "done" || j.state === "error" || j.state === "cancelled")
                    text: "Clear finished"
                    color: Cyber.Theme.accent
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                    MouseArea { anchors.fill: parent; onClicked: root.clearFinished() }
                }
            }
        }
    }
}
