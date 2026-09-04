import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import ".." as Cyber

// Replaces the deleted rofi/powermenu.sh. Opened/closed via
// `qs ipc call power toggle` (shell.qml's IpcHandler flips the owning
// LazyLoader's `active`), so this component is created fresh on every open
// and destroyed on every close -- there is no persistent "shown" state to
// manage here. Closing from the inside (Escape, or after running an action)
// is done through the `closeRequested` signal: shell.qml wires that signal
// to `powerMenu.active = false` where the `powerMenu` id is in scope (this
// file's own id namespace does not see the LazyLoader's id).
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

    // Hibernate writes the whole of RAM out to swap, so it is only offered
    // when swap can actually hold that: read live from /proc/meminfo rather
    // than trusting the installer's own partitioning choice, since a swap
    // file/zram can be resized long after install and this project has no
    // other place that re-checks it. No FileView.text() binding (same
    // reason popups/EmojiPicker.qml doesn't): parsed imperatively in
    // onTextChanged into plain properties instead.
    property int memKb: 0
    property int swapKb: 0
    readonly property bool hibernateOk: root.swapKb > 0 && root.swapKb >= root.memKb

    FileView {
        id: meminfoFile
        path: "/proc/meminfo"
        onTextChanged: {
            const t = text();
            const mem = t.match(/^MemTotal:\s+(\d+) kB/m);
            const swap = t.match(/^SwapTotal:\s+(\d+) kB/m);
            root.memKb = mem ? parseInt(mem[1], 10) : 0;
            root.swapKb = swap ? parseInt(swap[1], 10) : 0;
        }
    }

    // Hibernate is spliced in only when hibernateOk, right after Sleep, so
    // the list length (and implicitHeight above) both react to it appearing
    // or disappearing rather than reserving a row that silently does nothing.
    function buildActions() {
        const list = [
            { icon: "\uf023", label: "Lock",      run: () => Quickshell.execDetached(["hyprlock"]) },
            { icon: "\uf186", label: "Sleep",     run: () => Quickshell.execDetached(["systemctl", "suspend"]) }
        ];
        if (root.hibernateOk) {
            list.push({ icon: "\uf236", label: "Hibernate", run: () => Quickshell.execDetached(["systemctl", "hibernate"]) });
        }
        list.push(
            { icon: "\uf2f5", label: "Log out",   run: () => Hyprland.dispatch("hl.dsp.exit()") },
            { icon: "\uf2f9", label: "Reboot",    run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
            { icon: "\uf011", label: "Shut down", run: () => Quickshell.execDetached(["systemctl", "poweroff"]) }
        );
        return list;
    }
    readonly property var actions: root.buildActions()
    property int selected: 0

    function activate(idx) {
        root.actions[idx].run();
        root.closeRequested();
    }

    Rectangle {
        anchors.centerIn: parent
        width: 260
        height: 20 + root.actions.length * 50
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
            spacing: 4

            Repeater {
                model: root.actions

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Cyber.Theme.radius / 2
                    color: index === root.selected ? Cyber.Theme.sel : "transparent"
                    border.width: index === root.selected ? 1 : 0
                    border.color: Cyber.Theme.accent

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10

                        Text {
                            text: modelData.icon
                            color: Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2 }
                        }
                        Text {
                            text: modelData.label
                            color: Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.selected = index
                        onClicked: root.activate(index)
                    }
                }
            }
        }
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) {
                root.selected = (root.selected + 1) % root.actions.length;
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.selected = (root.selected - 1 + root.actions.length) % root.actions.length;
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate(root.selected);
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.closeRequested();
                event.accepted = true;
            }
        }
    }

    Component.onCompleted: keyHandler.forceActiveFocus()
}
