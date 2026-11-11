import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Cyber

// Replaces the deleted `rofi -show emoji`. Opened/closed via
// `qs ipc call emoji toggle` (shell.qml's IpcHandler flips the owning
// LazyLoader's `active`) -- same shape as launcher/Launcher.qml and
// popups/WinSwitch.qml: created fresh on every open, destroyed on every
// close, so the filter text and grid selection always start over. Closing
// from the inside (Escape, or after copying an emoji) goes through
// `closeRequested`, wired in shell.qml where the `emoji` LazyLoader id is
// in scope.
//
// Data: ../emoji.txt, vendored ONCE from rofi-emoji's all_emojis.txt (see
// that file's own header comment for the CC-BY-4.0 Unicode attribution).
// The glyphs in emoji.txt are literal UTF-8 Unicode characters -- real
// emoji, not Nerd-Font PUA codepoints -- so the shell's \uXXXX-escape
// policy does not apply to that data file (ruling R-s1). It DOES apply to
// this file: this file's own string literals contain no raw glyphs at all
// (the emoji shown in the grid come from the FileView's text, never from a
// literal in this source), so there is nothing here to escape.
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

    readonly property int columns: 8

    // The full parsed list, built once when emoji.txt finishes loading.
    property var allEmojis: []

    // FileView reads emoji.txt exactly once (no watchChanges: it's static
    // skel data installed at build time, never rewritten live -- unlike
    // Theme.qml's theme.json there is no live-reload contract for it).
    // Same env-truthiness path construction as Theme.qml: Quickshell.env()
    // returns null (not "") for an unset var, so a `!== ""` guard would be
    // dead code -- checked here as plain truthiness instead (session rule).
    FileView {
        id: emojiFile
        path: {
            const c = Quickshell.env("XDG_CONFIG_HOME");
            return (c ? c : Quickshell.env("HOME") + "/.config") + "/quickshell/emoji.txt";
        }
        onTextChanged: root.allEmojis = root.parseEmojis(text())
    }

    // Parses emoji.txt's "<emoji> <searchable text>" lines (one space after
    // the glyph, everything after it lowercased for the filter). Skips
    // header/attribution comment lines.
    //
    // A naive `line[0] === "#"` comment check would silently drop two real
    // rows: the keycap sequences U+0023 U+FE0F U+20E3 and U+0023 U+20E3
    // (both "keycap: #" in emoji.txt's search text) both start with the
    // literal "#" character (kept as codepoints here rather than the raw
    // glyphs, so this comment stays byte-clean per the shell's glyph
    // policy). Every comment line this shell writes is "# text" (hash then
    // a space), while those two emoji rows' second codepoint is a
    // variation selector / combining-enclosing-keycap mark -- never
    // whitespace. Checking line[1] for whitespace as well as line[0] for
    // "#" tells the two apart correctly.
    function parseEmojis(raw) {
        const lines = raw.split("\n");
        const rows = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.length === 0) continue;
            if (line[0] === "#" && (line.length === 1 || /\s/.test(line[1]))) continue;
            const sp = line.indexOf(" ");
            if (sp < 0) continue;
            rows.push({ emoji: line.slice(0, sp), text: line.slice(sp + 1).toLowerCase() });
        }
        return rows;
    }

    // Filtered list. Recomputes whenever the filter text changes; plain
    // Array.filter() keeps the SAME object references for surviving rows
    // (it never clones), which is what makes ScriptModel's
    // ObjectComparison.Identity below actually useful -- an entry present
    // in both the old and new filtered set is recognised as the same row,
    // same idiom as launcher/Launcher.qml's `filtered`.
    readonly property var filtered: {
        const q = filterField.text.trim().toLowerCase();
        return q === "" ? root.allEmojis : root.allEmojis.filter(e => e.text.includes(q));
    }
    // Typing always re-highlights the first result, matching rofi.
    onFilteredChanged: grid.currentIndex = filtered.length > 0 ? 0 : -1

    // wl-copy via stdin, never argv and never a shell string: the emoji is
    // written to the process's stdin, then stdin is closed (stdinEnabled =
    // false signals EOF) so wl-copy reads exactly the one write and exits,
    // landing the glyph on the Wayland clipboard regardless of what
    // characters it contains.
    Process {
        id: copyProc
        command: ["wl-copy"]
        stdinEnabled: true
    }

    function copyEmoji(entry) {
        if (!entry) return;
        copyProc.running = true;
        copyProc.write(entry.emoji);
        copyProc.stdinEnabled = false;
        root.closeRequested();
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
                placeholderText: "Search emoji..."
                placeholderTextColor: Cyber.Theme.muted
                color: Cyber.Theme.fg
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2 }
                selectByMouse: true
                background: Rectangle { color: "transparent" }

                // Same shape as Launcher.qml: the filter field holds focus
                // for the whole time the picker is open and forwards grid
                // navigation to GridView's own moveCurrentIndex*() methods.
                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Down:
                        grid.moveCurrentIndexDown();
                        event.accepted = true;
                        break;
                    case Qt.Key_Up:
                        grid.moveCurrentIndexUp();
                        event.accepted = true;
                        break;
                    case Qt.Key_Left:
                        grid.moveCurrentIndexLeft();
                        event.accepted = true;
                        break;
                    case Qt.Key_Right:
                        grid.moveCurrentIndexRight();
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.copyEmoji(root.filtered[grid.currentIndex]);
                        event.accepted = true;
                        break;
                    case Qt.Key_Escape:
                        root.closeRequested();
                        event.accepted = true;
                        break;
                    }
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: width / root.columns
                cellHeight: 56
                currentIndex: 0

                // Plain JS objects, not QObjects -- but ObjectComparison.
                // Identity still works: it compares by JS reference (===),
                // and `filtered` above never clones a surviving row, so a
                // glyph present in both the old and new filtered set keeps
                // its delegate alive across keystrokes (the ~5000-row
                // dataset stays smooth: GridView virtualises the ones off
                // screen regardless, this just avoids needless rebuild
                // churn for the ones still visible).
                model: ScriptModel {
                    values: root.filtered
                    comparisonMode: ObjectComparison.Identity
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Cyber.Theme.radius / 2
                        color: cell.index === grid.currentIndex ? Cyber.Theme.sel : "transparent"

                        Text {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font { family: Cyber.Theme.fontFamily; pixelSize: 26 }
                            text: cell.modelData.emoji
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: grid.currentIndex = cell.index
                            onClicked: {
                                grid.currentIndex = cell.index;
                                root.copyEmoji(cell.modelData);
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: filterField.forceActiveFocus()
}
