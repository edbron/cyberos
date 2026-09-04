import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Cyber
import "SystemHealthModel.js" as Model

// CPU/memory/battery/disk-SMART health, entirely inside the bar (Task
// Manager style, no separate GUI window). All data collection happens in
// cyberos-systemhealth-state (CPU/RAM from /proc, battery from
// /sys/class/power_supply, disk SMART from UDisks2 over D-Bus, no root, no
// sudoers changes); this file only renders whatever that script reports.
//
// Unlike every other popup in this shell, this one is loaded once and stays
// loaded (shell.qml's `systemhealth` LazyLoader has `active: true` from
// startup, matching notify/NotifyPopups.qml), because bar/SystemHealthChip.qml
// needs a live overallStatus to colour itself even while the panel is
// closed. `visible: root.opened` (not the LazyLoader) is what actually
// shows/hides the window, following NotifyPopups.qml's own
// always-loaded/conditionally-visible shape.
PanelWindow {
    id: root

    // top/right stay permanently anchored (matches every closed-state
    // geometry this window has always had); left/bottom only join in
    // while actually open, so Cyber.ClickOutside gets a real "outside"
    // region to catch a click in without this always-loaded window (see
    // the file header: `active: true` in shell.qml, never destroyed)
    // turning into a permanent, invisible full-desktop click-blocker while
    // closed. When closed this is byte-for-byte the same small corner
    // window it always was.
    anchors { top: true; right: true; left: root.opened; bottom: root.opened }
    implicitWidth: 380
    implicitHeight: 560
    color: "transparent"
    focusable: true
    aboveWindows: true
    visible: root.opened

    property bool opened: false
    function open() { root.opened = true; root.refresh(); }
    function close() { root.opened = false; }
    function toggle() { root.opened ? root.close() : root.open(); }

    Cyber.ClickOutside { onOutsideClicked: root.close() }

    property var payload: null
    property bool loadFailed: false

    readonly property var cpu: payload ? payload.cpu : null
    readonly property var memory: payload ? payload.memory : null
    readonly property var battery: payload ? payload.battery : null
    readonly property var disks: (payload && payload.disks) ? payload.disks : []

    readonly property var summary: Model.summarize(payload)
    readonly property string overallStatus: summary.status

    function statusColor(status) {
        if (status === "bad") return Cyber.Theme.alert;
        if (status === "warn") return Cyber.Theme.accent2;
        return Cyber.Theme.fg;
    }

    function refresh() {
        if (!stateProc.running) stateProc.running = true;
    }

    Component.onCompleted: refresh()

    // Slow poll always (the bar chip reflects live status even closed);
    // fast poll while the panel is open so the numbers move while looking.
    Timer {
        interval: root.opened ? 3000 : 20000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    // Belt-and-suspenders cap on top of the helper's own MAX_SUBPROCESS_BYTES/
    // MAX_READ_BYTES limits: its JSON payload should never approach this, so
    // hitting it means something is behaving unexpectedly and the payload is
    // discarded rather than handed to JSON.parse.
    readonly property int maxPayloadBytes: 2 * 1024 * 1024

    // JS string length counts UTF-16 code units, not UTF-8 bytes -- a
    // multi-byte character in a disk/CPU model string counts as 1 toward
    // .length, so measure the actual byte length rather than relying on it.
    function utf8ByteLength(str) {
        let bytes = 0;
        for (let i = 0; i < str.length; i++) {
            const code = str.charCodeAt(i);
            if (code >= 0xD800 && code <= 0xDBFF && i + 1 < str.length) {
                const next = str.charCodeAt(i + 1);
                if (next >= 0xDC00 && next <= 0xDFFF) { bytes += 4; i++; continue; }
            }
            if (code <= 0x7F) bytes += 1;
            else if (code <= 0x7FF) bytes += 2;
            else bytes += 3;
        }
        return bytes;
    }

    Process {
        id: stateProc
        command: ["cyberos-systemhealth-state"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const raw = text || "null";
                if (root.utf8ByteLength(raw) > root.maxPayloadBytes) { root.loadFailed = true; return; }
                try {
                    root.payload = JSON.parse(raw);
                    root.loadFailed = root.payload === null;
                } catch (e) {
                    root.loadFailed = true;
                }
            }
        }
    }

    // One stat with a label, a value, and a coloured fill bar (CPU usage,
    // memory used, battery charge).
    component StatRow: ColumnLayout {
        required property string label
        required property string value
        property real barValue: 0
        property color barColor: Cyber.Theme.accent
        spacing: 2
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: label
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: value
                textFormat: Text.PlainText
                color: Cyber.Theme.fg
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 5
            radius: 2
            color: Cyber.Theme.surface
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * Math.max(0, Math.min(100, barValue)) / 100
                radius: parent.radius
                color: barColor
            }
        }
    }

    // A plain label/value line (frequency, governor, load average, ...).
    component KeyValueRow: RowLayout {
        required property string k
        required property string v
        property color vColor: Cyber.Theme.fg
        Layout.fillWidth: true
        Text {
            text: k
            textFormat: Text.PlainText
            color: Cyber.Theme.muted
            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
        }
        Item { Layout.fillWidth: true }
        Text {
            text: v
            textFormat: Text.PlainText
            color: vColor
            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
            elide: Text.ElideRight
            Layout.maximumWidth: 220
        }
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 44; rightMargin: 8 }
        width: 380
        height: 560
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
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "System Health"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.summary.label
                    textFormat: Text.PlainText
                    color: root.statusColor(root.overallStatus)
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3; bold: true }
                }
            }

            Text {
                visible: root.loadFailed
                text: "cyberos-systemhealth-state did not return usable data."
                color: Cyber.Theme.alert
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: col.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ColumnLayout {
                    id: col
                    width: parent.width
                    spacing: 10

                    // ---- CPU ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.cpu !== null

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "CPU"
                                color: Cyber.Theme.accent
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2; bold: true }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.cpu ? root.cpu.model : ""
                                textFormat: Text.PlainText
                                color: Cyber.Theme.muted
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4 }
                                elide: Text.ElideLeft
                                Layout.maximumWidth: 220
                            }
                        }

                        StatRow {
                            label: "Usage"
                            value: root.cpu && root.cpu.usagePercent !== null ? root.cpu.usagePercent.toFixed(0) + "%" : "-"
                            barValue: root.cpu ? (root.cpu.usagePercent || 0) : 0
                            barColor: root.statusColor(Model.cpuStatus(root.cpu))
                        }

                        // One thin bar per logical core, a compact strip
                        // rather than a per-core row each.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: !!(root.cpu && root.cpu.perCorePercent && root.cpu.perCorePercent.length > 1)

                            Repeater {
                                model: root.cpu ? root.cpu.perCorePercent : []
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 14
                                    radius: 2
                                    color: Cyber.Theme.surface
                                    Rectangle {
                                        anchors { left: parent.left; bottom: parent.bottom }
                                        width: parent.width
                                        height: parent.height * Math.max(0, Math.min(100, modelData)) / 100
                                        radius: parent.radius
                                        color: Cyber.Theme.accent
                                    }
                                }
                            }
                        }

                        KeyValueRow {
                            k: "Frequency"
                            v: (root.cpu ? Model.formatFreq(root.cpu.curFreqMhz) : "-") + " / " + (root.cpu ? Model.formatFreq(root.cpu.maxFreqMhz) : "-") + " max"
                        }
                        KeyValueRow { k: "Governor"; v: root.cpu && root.cpu.governor ? root.cpu.governor : "-" }
                        KeyValueRow { k: "Load avg (1/5/15m)"; v: root.cpu && root.cpu.loadAvg ? root.cpu.loadAvg.join(" / ") : "-" }
                        KeyValueRow {
                            k: "Temperature"
                            v: (root.cpu ? Model.formatTemp(root.cpu.packageTempC) : "-") + (root.cpu && root.cpu.throttled ? "  ·  THROTTLING" : "")
                            vColor: root.statusColor(Model.cpuStatus(root.cpu))
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Cyber.Theme.border }

                    // ---- Memory ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.memory !== null

                        Text {
                            text: "MEMORY"
                            color: Cyber.Theme.accent
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2; bold: true }
                        }

                        StatRow {
                            label: "Used"
                            value: (root.memory ? Model.formatGb(root.memory.usedKb) : "-") + " / " + (root.memory ? Model.formatGb(root.memory.totalKb) : "-")
                            barValue: (root.memory && root.memory.totalKb) ? (root.memory.usedKb / root.memory.totalKb * 100) : 0
                            barColor: root.statusColor(Model.memoryStatus(root.memory))
                        }

                        KeyValueRow {
                            k: "Swap"
                            v: root.memory ? (Model.formatGb(root.memory.swapUsedKb) + " / " + Model.formatGb(root.memory.swapTotalKb)) : "-"
                            visible: !!(root.memory && root.memory.swapTotalKb > 0)
                        }
                        KeyValueRow {
                            k: "Memory pressure (avg10)"
                            v: root.memory && root.memory.psi ? (root.memory.psi.someAvg10.toFixed(1) + "% some, " + root.memory.psi.fullAvg10.toFixed(1) + "% full") : "n/a"
                        }
                        KeyValueRow {
                            k: "OOM kills"
                            v: root.memory && root.memory.oomKills !== null ? String(root.memory.oomKills) : "n/a"
                            vColor: root.memory && root.memory.oomKills ? Cyber.Theme.alert : Cyber.Theme.fg
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: !!(root.memory && root.memory.topByMem && root.memory.topByMem.length > 0)

                            Text {
                                text: "TOP PROCESSES"
                                color: Cyber.Theme.muted
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4 }
                            }
                            Repeater {
                                model: root.memory ? root.memory.topByMem : []
                                KeyValueRow {
                                    required property var modelData
                                    k: modelData.name
                                    v: modelData.mem.toFixed(1) + "% mem, " + modelData.cpu.toFixed(1) + "% cpu"
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Cyber.Theme.border; visible: !!(root.battery && root.battery.present) }

                    // ---- Battery ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: !!(root.battery && root.battery.present)

                        Text {
                            text: "BATTERY"
                            color: Cyber.Theme.accent
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2; bold: true }
                        }

                        StatRow {
                            label: "Charge"
                            value: (root.battery ? Model.formatPercent(root.battery.percent) : "-") + (root.battery ? "  ·  " + root.battery.status : "")
                            barValue: root.battery ? (root.battery.percent || 0) : 0
                            barColor: Cyber.Theme.accent
                        }

                        KeyValueRow {
                            k: "Health (wear)"
                            v: root.battery && root.battery.wearPercent !== null
                               ? Model.formatPercent(root.battery.wearPercent, 1) + " of design, " + root.battery.healthLabel
                               : "n/a"
                            vColor: root.statusColor(Model.batteryStatus(root.battery))
                        }
                        KeyValueRow { k: "Cycle count"; v: root.battery && root.battery.cycleCount !== null ? String(root.battery.cycleCount) : "n/a" }
                        KeyValueRow {
                            k: "Capacity"
                            v: (root.battery && root.battery.fullCapacityMah ? root.battery.fullCapacityMah + " mAh" : "n/a")
                               + " / " + (root.battery && root.battery.designCapacityMah ? root.battery.designCapacityMah + " mAh design" : "n/a")
                        }
                        KeyValueRow {
                            k: "Power draw"
                            v: (root.battery && root.battery.powerW ? root.battery.powerW + " W" : "n/a")
                               + (root.battery && root.battery.voltageV ? "  ·  " + root.battery.voltageV + " V" : "")
                        }
                        KeyValueRow {
                            k: "Time remaining"
                            v: root.battery && root.battery.timeRemainingMin !== null ? Model.formatMinutes(root.battery.timeRemainingMin) : "n/a"
                            visible: !!(root.battery && root.battery.timeRemainingMin !== null)
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Cyber.Theme.border; visible: root.disks.length > 0 }

                    // ---- Disks ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.disks.length > 0

                        Text {
                            text: "DISK HEALTH (SMART)"
                            color: Cyber.Theme.accent
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2; bold: true }
                        }

                        Repeater {
                            model: root.disks
                            ColumnLayout {
                                id: diskCard
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: (diskCard.modelData.model || diskCard.modelData.device) + (diskCard.modelData.mediaType ? " · " + diskCard.modelData.mediaType : "")
                                        textFormat: Text.PlainText
                                        color: Cyber.Theme.fg
                                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2; bold: true }
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: diskCard.modelData.healthy === true ? "HEALTHY" : diskCard.modelData.healthy === false ? "ATTENTION" : "UNKNOWN"
                                        textFormat: Text.PlainText
                                        color: root.statusColor(Model.diskStatus(diskCard.modelData))
                                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4; bold: true }
                                    }
                                }

                                KeyValueRow {
                                    k: "Device"
                                    v: diskCard.modelData.device + (diskCard.modelData.size ? " · " + diskCard.modelData.size : "")
                                }
                                KeyValueRow {
                                    k: "Temperature"
                                    v: diskCard.modelData.temperatureC !== undefined && diskCard.modelData.temperatureC !== null ? Model.formatTemp(diskCard.modelData.temperatureC) : "n/a"
                                }
                                KeyValueRow {
                                    k: "Power-on time"
                                    v: diskCard.modelData.powerOnHours ? Model.formatHours(diskCard.modelData.powerOnHours) : "n/a"
                                }
                                KeyValueRow {
                                    k: "Warnings"
                                    v: (diskCard.modelData.warnings && diskCard.modelData.warnings.length > 0)
                                       ? diskCard.modelData.warnings.map(w => Model.warningLabel(w)).join(", ")
                                       : "none"
                                    vColor: (diskCard.modelData.warnings && diskCard.modelData.warnings.length > 0) ? Cyber.Theme.alert : Cyber.Theme.fg
                                    visible: diskCard.modelData.kind === "nvme"
                                }
                                KeyValueRow {
                                    k: "Bad sectors"
                                    v: diskCard.modelData.badSectors !== undefined && diskCard.modelData.badSectors !== null ? String(diskCard.modelData.badSectors) : "n/a"
                                    vColor: diskCard.modelData.badSectors ? Cyber.Theme.alert : Cyber.Theme.fg
                                    visible: diskCard.modelData.kind === "ata"
                                }
                                Text {
                                    text: "No SMART interface exposed by UDisks2 for this drive."
                                    textFormat: Text.PlainText
                                    visible: diskCard.modelData.kind === "unknown"
                                    color: Cyber.Theme.muted
                                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4 }
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: "Esc to close"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
            }
        }
    }
}
