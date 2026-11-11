import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import ".." as Cyber

// Replaces the deleted `rofi -show window`. Opened/closed via
// `qs ipc call winswitch toggle` (shell.qml's IpcHandler flips the owning
// LazyLoader's `active`) -- same shape as launcher/Launcher.qml and
// power/PowerMenu.qml: created fresh on every open, destroyed on every
// close, so `list.currentIndex` always starts back at 0 with no manual
// reset. Closing from the inside (Escape, or after focusing a window) goes
// through `closeRequested`, wired in shell.qml where the `winswitch`
// LazyLoader id is in scope.
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

    // Focusing a chosen toplevel: HyprlandToplevel (Quickshell 0.3.1) has NO
    // `activate()` method -- verified against the installed qs binary's Qt
    // metaobject strings (qs::hyprland::ipc::HyprlandToplevel exposes only
    // address/handle/wayland/title/activated/urgent/lastIpcObject/
    // workspace/monitor as properties, no invokable `activate`). Focus goes
    // through `Hyprland.dispatch()` instead, which forwards its argument to
    // the live Hyprland IPC socket as "dispatch <request>" (Quickshell
    // itself prepends "dispatch " -- confirmed from the same binary's
    // string table, so `request` must NOT repeat that prefix).
    //
    // The request grammar on the Hyprland build this shell targets is
    // Lua-call syntax (`hyprland.lua`'s "Lua replaces .conf in 0.57" era):
    // a plain classic dispatcher string like "focuswindow address:0x.."
    // fails outright --
    //   error: [string "return hl.dispatch(focuswindow address:0x...")"]:1:
    //   ')' expected near 'address'
    //   Note: dispatch in lua is a shorthand for hl.dispatch(...), your
    //   syntax might need to be updated.
    // -- i.e. the raw request is Lua-evaluated as the argument to
    // `hl.dispatch(...)`, so it must itself be a valid Lua expression. The
    // working form, verified live against the running Hyprland instance
    // with `hyprctl dispatch 'hl.dsp.focus({window="address:0x.."})'` and
    // `hyprctl activewindow` before/after (see task-2-report.md for the
    // full transcript): `hl.dsp.focus({window=...})` takes a window
    // *selector string* -- `"address:<addr>"`, matching Hyprland's classic
    // window-selector syntax embedded as a string argument -- not the bare
    // address. A bare `window=addr` (no "address:" selector prefix) was
    // tried first and rejected with "hl.focus: window not found".
    function focusToplevel(toplevel) {
        if (!toplevel || !toplevel.address) return;
        Hyprland.dispatch(`hl.dsp.focus({window="address:${toplevel.address}"})`);
    }

    function activateCurrent() {
        const item = list.currentItem;
        if (!item) return;
        root.focusToplevel(item.modelData);
        root.closeRequested();
    }

    Rectangle {
        anchors.centerIn: parent
        width: 560
        height: 340
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

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                currentIndex: 0
                keyNavigationWraps: true

                // ScriptModel diffs old vs new `values` by object identity
                // (comparisonMode: ObjectComparison.Identity, same idiom as
                // launcher/Launcher.qml's app grid) so a toplevel present
                // across two refreshes keeps its delegate alive instead of
                // being torn down and rebuilt -- HyprlandToplevel instances
                // are stable QObjects owned by the Hyprland module, not
                // recreated between polls.
                model: ScriptModel {
                    values: Hyprland.toplevels.values
                    comparisonMode: ObjectComparison.Identity
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 44

                    readonly property string appClass: row.modelData?.lastIpcObject?.class ?? "?"
                    readonly property var wsId: row.modelData?.workspace?.id ?? "?"

                    Rectangle {
                        anchors.fill: parent
                        radius: Cyber.Theme.radius / 2
                        color: row.index === list.currentIndex ? Cyber.Theme.sel : "transparent"

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                            text: `${row.modelData?.title ?? ""} \u2014 ${row.appClass} (ws ${row.wsId})`
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: list.currentIndex = row.index
                        onClicked: {
                            list.currentIndex = row.index;
                            root.activateCurrent();
                        }
                    }
                }
            }
        }
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true

        // Tab AND Down cycle forward (Tab is the natural window-switcher
        // key -- matches alt-tab-style expectations); Up cycles back.
        // `keyNavigationWraps: true` above makes both wrap at the ends.
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Tab:
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
                root.activateCurrent();
                event.accepted = true;
                break;
            case Qt.Key_Escape:
                root.closeRequested();
                event.accepted = true;
                break;
            }
        }
    }

    Component.onCompleted: keyHandler.forceActiveFocus()
}
