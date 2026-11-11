import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Cyber

// Replaces the deleted `cliphist list | rofi -dmenu -p clipboard | cliphist
// decode | wl-copy` bind. Opened/closed via `qs ipc call clip toggle`
// (shell.qml's IpcHandler flips the owning LazyLoader's `active`) -- same
// shape as popups/EmojiPicker.qml: created fresh on every open, destroyed on
// every close, so the filter text and list selection always start over.
//
// The old bind was a shell PIPE, string-composed by Hyprland. That shape is
// never reproduced here: the selected cliphist LINE never touches a shell
// string. Instead the chain is two Processes, wired stdin-to-stdin in QML:
//   1. `cliphist list`      -- read via StdioCollector, parsed into rows.
//   2. `cliphist decode`    -- the selected FULL line ("<id>\t<preview>") is
//      written to ITS stdin via Process.write (never as an argv element,
//      never interpolated into a command string), collected via its own
//      StdioCollector.
//   3. once `decode` exits 0, its collected stdout is written to `wl-copy`'s
//      stdin the same way (mirrors EmojiPicker.qml's copyEmoji: write() then
//      stdinEnabled = false to signal EOF).
// No composed shell command string anywhere in this file -- every external
// boundary is an argv array or a stdin write.
PanelWindow {
    id: root

    signal closeRequested()

    // Fullscreen, transparent surface: the visible box below centres
    // itself instead of relying on the window's own size, so
    // Cyber.ClickOutside (this window's first child, right below) has a
    // real "outside" region to catch a click in -- a window sized to just
    // the popup itself has no such region.
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    focusable: true
    aboveWindows: true

    Cyber.ClickOutside { onOutsideClicked: root.closeRequested() }

    // The full parsed list, populated once when `cliphist list` returns.
    property var allEntries: []

    // `cliphist list` output is one entry per line: "<id>\t<preview>". The
    // id is only meaningful to cliphist itself -- what actually has to
    // travel to `cliphist decode` is the FULL original line (kept as
    // `entry.line`), not a reconstructed "<id>\t<preview>" string.
    function parseList(raw) {
        const lines = raw.split("\n");
        const rows = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.length === 0) continue;
            const tab = line.indexOf("\t");
            if (tab < 0) continue;
            rows.push({ line: line, preview: line.slice(tab + 1) });
        }
        return rows;
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.allEntries = root.parseList(text)
        }
    }

    // Filtered list, case-insensitive substring over the preview text. Plain
    // Array.filter() keeps the SAME object references for surviving rows,
    // which is what makes ScriptModel's ObjectComparison.Identity below
    // actually useful (same idiom as EmojiPicker.qml's `filtered`).
    readonly property var filtered: {
        const q = filterField.text.trim().toLowerCase();
        return q === "" ? root.allEntries : root.allEntries.filter(e => e.preview.toLowerCase().includes(q));
    }
    onFilteredChanged: list.currentIndex = filtered.length > 0 ? 0 : -1

    // Second half of the copy chain: the selected line's decoded bytes,
    // collected here, get written to wl-copy's stdin once decodeProc exits.
    Process {
        id: decodeProc
        command: ["cliphist", "decode"]
        stdinEnabled: true
        stdout: StdioCollector { id: decodeOut }
        onExited: exitCode => {
            if (exitCode === 0) {
                copyProc.running = true;
                copyProc.write(decodeOut.text);
                copyProc.stdinEnabled = false;
            }
            root.closeRequested();
        }
    }

    Process {
        id: copyProc
        command: ["wl-copy"]
        stdinEnabled: true
    }

    function copySelected(entry) {
        if (!entry) return;
        decodeProc.running = true;
        decodeProc.write(entry.line);
        decodeProc.stdinEnabled = false;
    }

    Rectangle {
        anchors.centerIn: parent
        width: 560
        height: 420
        radius: Cyber.Theme.radius
        color: Cyber.Theme.bg
        border.width: 1
        border.color: Cyber.Theme.border

        // Swallows a click on blank space inside the popup: a plain
        // Rectangle doesn't itself accept mouse events, so without this a
        // click here would fall through to Cyber.ClickOutside behind the
        // whole window and close the popup it landed inside.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            TextField {
                id: filterField
                Layout.fillWidth: true
                placeholderText: "Filter clipboard history..."
                placeholderTextColor: Cyber.Theme.muted
                color: Cyber.Theme.fg
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2 }
                selectByMouse: true
                background: Rectangle { color: "transparent" }

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Down:
                        list.incrementCurrentIndex();
                        event.accepted = true;
                        break;
                    case Qt.Key_Up:
                        list.decrementCurrentIndex();
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.copySelected(root.filtered[list.currentIndex]);
                        event.accepted = true;
                        break;
                    case Qt.Key_Escape:
                        root.closeRequested();
                        event.accepted = true;
                        break;
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                currentIndex: 0
                keyNavigationWraps: true

                model: ScriptModel {
                    values: root.filtered
                    comparisonMode: ObjectComparison.Identity
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 32

                    Rectangle {
                        anchors.fill: parent
                        radius: Cyber.Theme.radius / 2
                        color: row.index === list.currentIndex ? Cyber.Theme.sel : "transparent"

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                            text: row.modelData.preview
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: list.currentIndex = row.index
                            onClicked: {
                                list.currentIndex = row.index;
                                root.copySelected(row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        listProc.running = true;
        filterField.forceActiveFocus();
    }
}
