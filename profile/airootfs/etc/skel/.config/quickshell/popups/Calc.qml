import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Cyber

// Replaces the deleted `rofi -show calc -no-show-match -no-sort`. Opened/
// closed via `qs ipc call calc toggle` (shell.qml's IpcHandler flips the
// owning LazyLoader's `active`) -- same shape as popups/EmojiPicker.qml and
// popups/WinSwitch.qml: created fresh on every open, destroyed on every
// close, so the expression field and result always start over.
//
// Evaluation goes through `qalc` (libqalculate's CLI, previously pulled in
// only as rofi-calc's dependency -- now an explicit package since rofi-calc
// is gone). `-t` = terse: just the result, no "expr = " echo. The expression
// is passed as a SINGLE argv element (`["qalc", "-t", expr]`), never
// interpolated into a shell string -- this is argv, not shell text, so
// qalc's own parser sees exactly what the user typed, nothing more.
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

    property string resultText: ""

    // Debounce: typing restarts this 150ms timer on every keystroke, so a
    // burst of keystrokes spawns qalc once per pause rather than once per
    // character.
    Timer {
        id: debounce
        interval: 150
        onTriggered: root.evaluate()
    }

    // Re-run via exec() rather than setting `command` then `running = true`:
    // exec() takes the fresh argv and (re)starts the process outright, which
    // is what repeated debounced edits need -- there is no risk of two
    // overlapping qalc runs racing on this.resultText since qalc returns in
    // well under the 150ms debounce window.
    Process {
        id: calcProc
        stdout: StdioCollector {
            // `-t` (terse) is documented to print nothing but the answer --
            // but verified empirically (host smoke, see task-4-report.md)
            // that qalc still puts diagnostic lines (e.g. a failed
            // definitions/exchange-rate load) on STDOUT ahead of the actual
            // answer when something upstream of the calculation goes wrong.
            // The answer itself is always the last line, so take that
            // rather than the whole trimmed blob -- harmless when qalc's
            // output really is one line (the common case), correct when
            // it's not.
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.resultText = lines[lines.length - 1].trim();
            }
        }
    }

    function evaluate() {
        const expr = exprField.text.trim();
        if (expr === "") { root.resultText = ""; return; }
        calcProc.exec(["qalc", "-t", expr]);
    }

    // wl-copy via stdin, never argv and never a shell string (same idiom as
    // EmojiPicker.qml's copyEmoji): the result is written to the process's
    // stdin, then stdin is closed (stdinEnabled = false signals EOF) so
    // wl-copy reads exactly the one write and exits.
    Process {
        id: copyProc
        command: ["wl-copy"]
        stdinEnabled: true
    }

    function copyResult() {
        if (root.resultText === "") { root.closeRequested(); return; }
        copyProc.running = true;
        copyProc.write(root.resultText);
        copyProc.stdinEnabled = false;
        root.closeRequested();
    }

    Rectangle {
        anchors.centerIn: parent
        width: 420
        height: 130
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
                id: exprField
                Layout.fillWidth: true
                placeholderText: "Expression..."
                placeholderTextColor: Cyber.Theme.muted
                color: Cyber.Theme.fg
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2 }
                selectByMouse: true
                background: Rectangle { color: "transparent" }

                onTextChanged: debounce.restart()

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.copyResult();
                        event.accepted = true;
                        break;
                    case Qt.Key_Escape:
                        root.closeRequested();
                        event.accepted = true;
                        break;
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                color: Cyber.Theme.fg
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 4 }
                text: root.resultText
                elide: Text.ElideRight
            }
        }
    }

    Component.onCompleted: exprField.forceActiveFocus()
}
