import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".." as Cyber

// Replaces the deleted `rofi -show drun`. Opened/closed via
// `qs ipc call launcher toggle` (shell.qml's IpcHandler flips the owning
// LazyLoader's `active`), so -- same shape as PowerMenu.qml -- this
// component is created fresh on every open and destroyed on every close.
// That gives the filter text its "resets on every open" behaviour for
// free: `filterField.text` starts empty on every fresh instantiation, no
// manual reset needed. Closing from the inside (Escape, or after launching
// an app) goes through the `closeRequested` signal, wired in shell.qml
// where the `launcher` LazyLoader id is in scope (this file's own id
// namespace can't see it).
//
// Tab/Backtab flip `mode` between "apps" (the original launcher) and
// "files" -- a search-and-open feature over /usr, /etc, /var and $HOME
// (including dotdirs like ~/.config), backed by fd (already a shipped
// package). Directory browsing stays Files.qml's job:
// this only searches for and opens files (fd's -t f), so a matched
// directory never comes back and there's no folder-vs-file branch to get
// wrong. Every fd/xdg-open call here is argv, never a shell string,
// matching this file's own launch()/execute() and every other Process use
// in this shell.
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

    readonly property int rowHeight: 26

    // Category chips. First match in priority order wins; anything unmatched
    // lands in Utilities. freedesktop "Security" is a registered additional
    // category -- our own .desktop entries (metasploit.desktop) set it, and
    // nameOverrides catches shipped tools whose upstream Categories don't
    // (wireshark says Network;Monitor).
    readonly property var groups: ["All", "Security", "Development", "Internet",
        "Office", "Graphics", "Media", "System", "Utilities"]
    property string activeGroup: "All"

    // Left/Right drive this -- keyboard-only category switching, no
    // scrolling required to reach a chip off the edge of the panel's
    // width. catList (below) keeps the active chip in view itself.
    // Tab/Backtab used to double as category switching too; they now
    // switch modes instead (see toggleMode below), so a query typed for
    // files search can't accidentally jump categories on its way there.
    function cycleGroup(delta) {
        const i = root.groups.indexOf(root.activeGroup);
        root.activeGroup = root.groups[(i + delta + root.groups.length) % root.groups.length];
    }

    // ---- file search ("files" mode) ----
    // Tab/Backtab toggle `mode`; Left/Right stay category-only (apps mode
    // below), so no key means two different things depending on mode.
    // setMode() also backs the modeTabs segments below (click "Files"
    // while already in files mode is a no-op, not a bounce back to apps).
    property string mode: "apps"
    function setMode(m) {
        if (root.mode === m) return;
        root.mode = m;
        if (root.mode === "files") root.runFileSearch();
    }
    function toggleMode() {
        root.setMode(root.mode === "apps" ? "files" : "apps");
    }

    readonly property string homeRoot: Quickshell.env("HOME") || "/"
    readonly property string usrRoot: "/usr"
    readonly property string etcRoot: "/etc"
    readonly property string varRoot: "/var"
    property var fileResults: []

    // Bumped on every search, including the "query too short, clear
    // results" case in runFileSearch() below, so a slow fd run started by
    // an earlier keystroke can never overwrite what a faster, more recent
    // one already returned. fd's own walk of /usr has no upper bound on
    // how long a no-match query takes (worst case is a full tree walk),
    // which can outlast the 150ms debounce. fileSearchProc.forGen pins
    // each run to the generation it was started for; the result handler
    // drops anything that doesn't match the current one.
    property int searchGen: 0

    Timer {
        id: fileSearchDebounce
        interval: 150
        onTriggered: root.runFileSearch()
    }

    // fd -- already a shipped package (dev basics) -- searched by
    // fixed-string substring (-F), not its default regex mode: a search
    // box shouldn't turn a stray '.' or '*' into an unintended pattern,
    // and it rules out regex-complexity blowup on attacker-length input
    // for free. -i is case-insensitive, matching the app filter. `--`
    // before the query means a query starting with '-' is still taken
    // literally, never parsed as a flag. No -L/--follow: fd will not
    // traverse a symlink out of /usr, /etc, /var or $HOME, and can't loop
    // on one. -H/--hidden is what actually makes ~/.config reachable:
    // fd skips dotdirs by default, so without it $HOME was searched in
    // name only. --max-results bounds fd's own output; .slice() below
    // bounds it again client-side in case that flag is ever dropped by a
    // future edit. Bare "fd", not an absolute path: every other Process/
    // execDetached call in this shell (qalc, xdg-open, wl-copy, 7z,
    // trash-put) already relies on PATH the same way.
    //
    // /etc and /var carry permission-restricted subtrees this project's
    // own student user can't read (/etc/shadow, /etc/sudoers.d,
    // /var/lib/*): confirmed fd's own behaviour handles that the same way
    // as any other search tool, not a gap this shell needs to paper over
    // -- it skips an unreadable subdirectory and keeps walking the rest,
    // exit 0, no results from that branch. A search returning nothing is
    // already the correct, expected UI for "not present" and "present but
    // blocked" alike; there is no per-directory status surface here for
    // the two to diverge on.
    Process {
        id: fileSearchProc
        property int forGen: -1
        stdout: StdioCollector {
            onStreamFinished: {
                if (fileSearchProc.forGen !== root.searchGen) return;
                const trimmed = text.trim();
                root.fileResults = trimmed === "" ? [] : trimmed.split("\n").slice(0, 40);
                fileList.currentIndex = root.fileResults.length > 0 ? 0 : -1;
            }
        }
    }

    // Two-character floor: a one-character query against all of /usr is
    // both slow (barely narrows the walk) and not useful (thousands of
    // hits). Below it, results are cleared rather than left stale.
    function runFileSearch() {
        if (root.mode !== "files") return;
        const q = filterField.text.trim();
        root.searchGen++;
        if (q.length < 2) { root.fileResults = []; return; }
        fileSearchProc.forGen = root.searchGen;
        fileSearchProc.exec(["fd", "-i", "-F", "-H", "-a", "-t", "f",
            "--max-results", "40", "--", q,
            root.usrRoot, root.etcRoot, root.varRoot, root.homeRoot]);
    }

    // xdg-open, not Quickshell's own Files.qml directly: this is a file
    // search (fd's -t f), never a directory, so there is nothing here for
    // Files.qml to browse into -- the registered per-mimetype handler is
    // always the right one, the same call Files.qml itself makes to open
    // a file (see apps/Files.qml's openEntry()).
    function openFileResult(index) {
        if (index < 0 || index >= root.fileResults.length) return;
        Quickshell.execDetached(["xdg-open", root.fileResults[index]]);
        root.closeRequested();
    }

    readonly property var nameOverrides: ({
        "Wireshark": "Security",
        "Ghidra": "Security"
    })

    function groupOf(entry) {
        const o = nameOverrides[entry.name];
        if (o !== undefined) return o;
        const c = entry.categories;
        const has = list => list.some(x => c.includes(x));
        if (has(["Security"])) return "Security";
        if (has(["Development", "IDE", "Debugger", "RevisionControl"])) return "Development";
        if (has(["Network", "WebBrowser", "Email", "P2P"])) return "Internet";
        if (has(["Office", "WordProcessor", "Spreadsheet", "Presentation"])) return "Office";
        if (has(["Graphics", "Photography"])) return "Graphics";
        if (has(["AudioVideo", "Audio", "Video", "Player"])) return "Media";
        if (has(["System", "Settings", "HardwareSettings", "Monitor",
                 "TerminalEmulator", "FileManager", "Emulator"])) return "System";
        return "Utilities";
    }

    // Filtered + sorted app list. Recomputes whenever the filter text or
    // active category changes (the reads of `filterField.text` and
    // `root.activeGroup` below each establish a binding dependency);
    // noDisplay entries are dropped, case-insensitive substring match on
    // name, alphabetical order.
    readonly property var filtered: {
        const q = filterField.text.trim().toLowerCase();
        return DesktopEntries.applications.values
            .filter(a => !a.noDisplay
                && (root.activeGroup === "All" || root.groupOf(a) === root.activeGroup)
                && (q === "" || a.name.toLowerCase().includes(q)))
            .sort((a, b) => a.name.localeCompare(b.name));
    }
    // Re-select the first result whenever the filtered set changes (every
    // keystroke) -- matches rofi (typing always re-highlights the top hit).
    onFilteredChanged: list.currentIndex = filtered.length > 0 ? 0 : -1

    // No highlighted entry (empty filter results) is a no-op, not a close --
    // matches rofi: Return with nothing matched does nothing, it doesn't
    // dismiss the launcher.
    function launch(entry) {
        if (!entry) return;
        entry.execute();
        root.closeRequested();
    }

    // Sharp corners, a single hairline border, no chip/pill decoration below
    // -- a plain terminal box rather than the rest of the shell's rounded
    // Theme.radius look, deliberately: this is the one surface styled after
    // a minimal TUI launcher (dmenu/fzf), not the desktop chrome around it.
    // Border is Theme.accent (green), not the neutral Theme.border every
    // other panel uses: it ties the box outline to the same colour as the
    // prompt glyph and the selection/active-category markers inside it,
    // over Theme.accent2 (gold) which would compete with the launch icons'
    // own colours instead of framing them.
    Rectangle {
        anchors.centerIn: parent
        width: 360
        height: 560
        radius: 0
        color: Cyber.Theme.bg
        border.width: 1
        border.color: Cyber.Theme.accent

        // Swallows a click on blank space inside the popup: a plain
        // Rectangle doesn't itself accept mouse events, so without this a
        // click here would fall through to Cyber.ClickOutside behind the
        // whole window and close the popup it landed inside.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: ">"
                    color: Cyber.Theme.accent
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }

                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    placeholderText: root.mode === "apps" ? "search applications..." : "search /usr, /etc, /var, ~ ..."
                    placeholderTextColor: Cyber.Theme.muted
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2 }
                    selectByMouse: true
                    background: Rectangle { color: "transparent" }

                    // Only feeds the file-search debounce: the app list
                    // filters itself via `filtered`'s own live binding on
                    // this text, no explicit handler needed there.
                    onTextChanged: fileSearchDebounce.restart()

                    // List navigation, category switching and mode
                    // switching all live on the filter field, not on the
                    // ListViews themselves: the field holds focus for the
                    // whole time the launcher is open (typing always
                    // works) and forwards the keys they care about.
                    // Left/Right switch categories in apps mode rather
                    // than moving the text cursor -- a keyboard-only
                    // launcher has no scrollbar or wheel to reach for, so
                    // the arrow keys alone reach every category. In files
                    // mode they're left unhandled (event.accepted stays
                    // false) so the TextField's normal cursor movement
                    // works instead, since there's no chip strip to move
                    // through there.
                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Tab:
                        case Qt.Key_Backtab:
                            root.toggleMode();
                            event.accepted = true;
                            break;
                        case Qt.Key_Down:
                            (root.mode === "apps" ? list : fileList).incrementCurrentIndex();
                            event.accepted = true;
                            break;
                        case Qt.Key_Up:
                            (root.mode === "apps" ? list : fileList).decrementCurrentIndex();
                            event.accepted = true;
                            break;
                        case Qt.Key_Right:
                            if (root.mode === "apps") { root.cycleGroup(1); event.accepted = true; }
                            break;
                        case Qt.Key_Left:
                            if (root.mode === "apps") { root.cycleGroup(-1); event.accepted = true; }
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            if (root.mode === "apps") root.launch(root.filtered[list.currentIndex]);
                            else root.openFileResult(fileList.currentIndex);
                            event.accepted = true;
                            break;
                        case Qt.Key_Escape:
                            root.closeRequested();
                            event.accepted = true;
                            break;
                        }
                    }
                }
            }

            // Always visible in both modes, unlike catList below (which
            // only means something in apps mode): the one thing on this
            // panel that shows *which* search this is, and moves the
            // instant Tab switches it -- same bracket-highlight language
            // as the category chips, so the two "this is what's active"
            // affordances read as one language rather than two.
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: root.mode === "apps" ? "[Apps]" : "Apps"
                    color: root.mode === "apps" ? Cyber.Theme.accent : Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                    MouseArea { anchors.fill: parent; onClicked: root.setMode("apps") }
                }
                Text {
                    text: root.mode === "files" ? "[Files]" : "Files"
                    color: root.mode === "files" ? Cyber.Theme.accent : Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                    MouseArea { anchors.fill: parent; onClicked: root.setMode("files") }
                }
                Item { Layout.fillWidth: true }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Cyber.Theme.accent }

            // Horizontal ListView, not a RowLayout: nine chips plus brackets
            // on the active one don't fit the panel's narrow width, and a
            // RowLayout has no way to bring an off-screen chip into view.
            // No wheel/drag handling here on purpose -- Left/Right
            // (filterField's Keys.onPressed) is the only way to change
            // category, and positionViewAtIndex below keeps whichever one
            // is active on-screen, clipped or not.
            ListView {
                id: catList
                visible: root.mode === "apps"
                Layout.fillWidth: true
                Layout.preferredHeight: Cyber.Theme.fontSize + 8
                orientation: ListView.Horizontal
                clip: true
                spacing: 14
                interactive: false

                Connections {
                    target: root
                    function onActiveGroupChanged() {
                        catList.positionViewAtIndex(root.groups.indexOf(root.activeGroup), ListView.Contain);
                    }
                }

                model: root.groups
                delegate: Text {
                    id: chip
                    required property string modelData
                    text: root.activeGroup === chip.modelData ? "[" + chip.modelData + "]" : chip.modelData
                    color: root.activeGroup === chip.modelData ? Cyber.Theme.accent : Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.activeGroup = chip.modelData
                    }
                }
            }

            // Takes catList's row when it's hidden (files mode), so the
            // panel's height never jumps switching modes: same
            // Layout.preferredHeight, same font size.
            Text {
                visible: root.mode === "files"
                Layout.fillWidth: true
                Layout.preferredHeight: Cyber.Theme.fontSize + 8
                verticalAlignment: Text.AlignVCenter
                text: filterField.text.trim().length < 2
                    ? "/usr + ~  ·  type at least 2 characters"
                    : root.fileResults.length + (root.fileResults.length === 1 ? " match" : " matches") + "  ·  /usr + ~"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
            }

            ListView {
                id: list
                visible: root.mode === "apps"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: 0

                // A plain JS array bound straight to `model:` is treated as
                // a brand-new model on every reassignment -- QQmlDelegateModel
                // has no way to tell "same list, some entries added/removed"
                // from "unrelated new list", so it destroys and recreates
                // every delegate on every keystroke. Measured before this
                // fix (back when this was a GridView with icon delegates):
                // opening the launcher and typing two characters ("f" then
                // "fi") produced ~1250 delegate creations/destructions
                // total, including repeat churn for apps present in *both*
                // filter results -- a real flicker/lag risk under the spec's
                // safe-graphics (software rendering) constraint.
                //
                // ScriptModel (Quickshell core) exists precisely for this:
                // it wraps a JS array as a real QAbstractListModel and diffs
                // old vs new `values` to emit minimal insert/remove/move
                // signals instead of a full reset. `comparisonMode:
                // ObjectComparison.Identity` (set explicitly here, matching
                // the default) diffs by object identity, which is correct
                // for DesktopEntry: entries are stable QObjects owned by the
                // DesktopEntries singleton, never recreated between
                // keystrokes -- so an app present in both the old and new
                // filtered set is recognised as the *same* row and its
                // delegate is kept alive, not rebuilt.
                model: ScriptModel {
                    values: root.filtered
                    comparisonMode: ObjectComparison.Identity
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: list.width
                    height: root.rowHeight

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 8

                        Text {
                            text: cell.index === list.currentIndex ? ">" : " "
                            color: Cyber.Theme.accent
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                        }
                        IconImage {
                            implicitSize: 16
                            // Same fallback as the old grid delegate: an entry
                            // whose `icon` doesn't resolve in the icon theme
                            // gets a generic placeholder instead of a blank
                            // gap in the row.
                            source: Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
                        }
                        Text {
                            Layout.fillWidth: true
                            text: cell.modelData.name
                            textFormat: Text.PlainText
                            color: cell.index === list.currentIndex ? Cyber.Theme.fg : Cyber.Theme.muted
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: list.currentIndex = cell.index
                        onClicked: root.launch(cell.modelData)
                    }
                }
            }

            // Same row shape as `list` above (cursor marker, icon, name),
            // plus the containing directory in a second, independently
            // eliding Text -- both PlainText, matching the app row's
            // hardening: an fd result came from filenames this project
            // doesn't control, no different from a .desktop Name=.
            ListView {
                id: fileList
                visible: root.mode === "files"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: 0

                model: ScriptModel {
                    values: root.fileResults
                    comparisonMode: ObjectComparison.Identity
                }

                delegate: Item {
                    id: fcell
                    required property string modelData
                    required property int index
                    width: fileList.width
                    height: root.rowHeight

                    readonly property string baseName: {
                        const cut = fcell.modelData.lastIndexOf("/");
                        return cut >= 0 ? fcell.modelData.substring(cut + 1) : fcell.modelData;
                    }
                    readonly property string dirName: {
                        const cut = fcell.modelData.lastIndexOf("/");
                        return cut > 0 ? fcell.modelData.substring(0, cut) : "/";
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 8

                        Text {
                            text: fcell.index === fileList.currentIndex ? ">" : " "
                            color: Cyber.Theme.accent
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                        }
                        IconImage {
                            implicitSize: 16
                            source: Quickshell.iconPath("text-x-generic", "text-x-generic")
                        }
                        Text {
                            // Capped, not fillWidth: an absurd filename
                            // elides here instead of squeezing dirName's
                            // Text out to nothing or overflowing the row.
                            Layout.maximumWidth: 180
                            text: fcell.baseName
                            textFormat: Text.PlainText
                            color: fcell.index === fileList.currentIndex ? Cyber.Theme.fg : Cyber.Theme.muted
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: fcell.dirName
                            textFormat: Text.PlainText
                            color: Cyber.Theme.muted
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: fileList.currentIndex = fcell.index
                        onClicked: root.openFileResult(fcell.index)
                    }
                }
            }
        }
    }

    Component.onCompleted: filterField.forceActiveFocus()
}
