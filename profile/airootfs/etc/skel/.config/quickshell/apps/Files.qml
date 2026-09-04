import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../" as Cyber

// Replaces dolphin. A real toplevel window (FloatingWindow), opened by
// Super+E and by `qs ipc call files open <path>`.
//
// v1 is deliberately browse-and-open: navigate, open with the registered
// handler, extract an archive, trash a file, open a terminal here, copy a
// path. Rename/copy/cut/paste and multi-select are NOT here -- a solid
// browser beats a half-built file-operations engine, and every destructive
// path goes through trash-put rather than rm.
//
// FolderListModel role names are load-bearing: fileName, filePath, fileIsDir
// and fileSuffix all resolve; the per-item file-URL role does NOT (it
// returns undefined).
FloatingWindow {
    id: root

    property string path: root.home

    title: "Files  —  " + root.path
    implicitWidth: 1000
    implicitHeight: 640
    minimumSize: Qt.size(560, 360)
    color: Cyber.Theme.bg

    readonly property string home: Quickshell.env("HOME") || "/"

    readonly property var places: [
        { name: "Home",      dir: root.home },
        { name: "Desktop",   dir: root.home + "/Desktop" },
        { name: "Documents", dir: root.home + "/Documents" },
        { name: "Downloads", dir: root.home + "/Downloads" },
        { name: "Pictures",  dir: root.home + "/Pictures" },
        { name: "Projects",  dir: root.home + "/Projects" }
    ]

    readonly property var archiveSuffixes: ["zip", "7z", "gz", "bz2", "xz", "tar", "rar", "tgz"]

    function enter(dirPath) { root.path = dirPath; }

    // Plain string slicing rather than dir.parentFolder: parentFolder is a
    // url whose toString() percent-encodes reserved characters, so a folder
    // named "My Documents" would come back as "My%20Documents" and the next
    // folder binding would fail to resolve. root.path is never encoded.
    function goUp() {
        if (root.path === "/") return;
        const cut = root.path.lastIndexOf("/");
        root.path = cut <= 0 ? "/" : root.path.substring(0, cut);
    }

    // Everything below is argv, never a shell string -- a filename with a
    // space or a quote in it is just one argument, not an injection.
    function openEntry(filePath, isDir) {
        if (isDir) root.enter(filePath);
        else Quickshell.execDetached(["xdg-open", filePath]);
    }
    function trashEntry(filePath) { Quickshell.execDetached(["trash-put", "--", filePath]); }
    function copyPath(filePath)   { Quickshell.execDetached(["wl-copy", "--", filePath]); }
    function terminalHere()       { Quickshell.execDetached(["foot", "-D", root.path]); }

    // 7z handles zip/7z/tar/gz/xz/rar alike; workingDirectory puts the output
    // beside the archive rather than wherever the shell happens to have been.
    //
    // Archives are exactly the kind of file this project's own users handle
    // routinely -- CTF challenges, malware samples, coursework downloads --
    // so "extract here" cannot trust an entry's own path. Whether the
    // installed 7z build refuses a traversal entry on its own varies by
    // version, so this lists the archive first (-slt: one "Path = " line per
    // entry, after the "----------" separator that ends the archive's own
    // header block) and refuses to extract anything containing a ".."
    // segment or an absolute path, rather than relying on the extractor's
    // own defaults.
    Process {
        id: listProc
        property string pendingArchive: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const archive = listProc.pendingArchive;
                listProc.pendingArchive = "";
                if (!archive) return;
                const lines = text.split("\n");
                const sep = lines.findIndex(l => l.startsWith("----------"));
                const entries = sep >= 0 ? lines.slice(sep + 1) : [];
                const paths = entries.filter(l => l.startsWith("Path = ")).map(l => l.slice(7));
                const unsafe = paths.some(p => p.startsWith("/") || p.split("/").includes(".."));
                if (unsafe) {
                    console.warn("Files: refused to extract " + archive + " -- an entry's path escapes the target directory");
                    return;
                }
                extractProc.workingDirectory = root.path;
                extractProc.exec(["7z", "x", "-y", "--", archive]);
            }
        }
    }
    Process { id: extractProc }
    function extract(filePath) {
        listProc.pendingArchive = filePath;
        listProc.exec(["7z", "l", "-slt", "--", filePath]);
    }

    FolderListModel {
        id: dir
        folder: "file://" + root.path
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------- sidebar ----------------
        Rectangle {
            Layout.preferredWidth: 180
            Layout.fillHeight: true
            color: Cyber.Theme.surface

            ColumnLayout {
                anchors { fill: parent; margins: 8 }
                spacing: 2

                Text {
                    text: "Places"
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                }
                Repeater {
                    model: root.places
                    delegate: Rectangle {
                        id: place
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Cyber.Theme.radius / 2
                        color: root.path === place.modelData.dir ? Cyber.Theme.sel
                            : placeMouse.containsMouse ? Cyber.Theme.bg : "transparent"

                        Text {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: place.modelData.name
                            color: Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
                        }
                        MouseArea {
                            id: placeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.enter(place.modelData.dir)
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        // ---------------- main pane ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // breadcrumb
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                color: Cyber.Theme.bg

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 6

                    Text {
                        text: "\uf062"   // arrow-up
                        color: Cyber.Theme.fg
                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                        MouseArea { anchors.fill: parent; onClicked: root.goUp() }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.path
                        color: Cyber.Theme.muted
                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
                        elide: Text.ElideMiddle
                    }
                    Text {
                        text: "\uf120"   // terminal
                        color: Cyber.Theme.fg
                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
                        MouseArea { anchors.fill: parent; onClicked: root.terminalHere() }
                    }
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 128
                cellHeight: 104
                model: dir

                // Backspace goes up a level; the view holds focus so this
                // works without a dedicated key-catcher item.
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace) { root.goUp(); event.accepted = true; }
                    else if (event.key === Qt.Key_Escape) { root.visible = false; event.accepted = true; }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        // Open whatever the arrow keys have selected. Without
                        // this the grid is mouse-only.
                        if (grid.currentIndex >= 0) {
                            root.openEntry(dir.get(grid.currentIndex, "filePath"),
                                           dir.get(grid.currentIndex, "fileIsDir"));
                        }
                        event.accepted = true;
                    }
                }

                delegate: Item {
                    id: cell
                    required property string fileName
                    required property string filePath
                    required property bool fileIsDir
                    required property string fileSuffix
                    width: grid.cellWidth
                    height: grid.cellHeight

                    readonly property bool isArchive:
                        !cell.fileIsDir && root.archiveSuffixes.indexOf(cell.fileSuffix.toLowerCase()) >= 0

                    Rectangle {
                        anchors { fill: parent; margins: 4 }
                        radius: Cyber.Theme.radius / 2
                        // Highlight the keyboard-focused cell as well as the
                        // hovered one, otherwise arrow-key navigation is
                        // invisible and Return has no discoverable target.
                        color: cellMouse.containsMouse || cell.GridView.isCurrentItem
                            ? Cyber.Theme.sel : "transparent"

                        ColumnLayout {
                            anchors { fill: parent; margins: 6 }
                            spacing: 4

                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 44
                                source: Quickshell.iconPath(
                                    cell.fileIsDir ? "folder" : "text-x-generic",
                                    "application-x-executable")
                            }
                            Text {
                                Layout.fillWidth: true
                                text: cell.fileName
                                textFormat: Text.PlainText
                                color: Cyber.Theme.fg
                                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onDoubleClicked: mouse => {
                                if (mouse.button === Qt.LeftButton)
                                    root.openEntry(cell.filePath, cell.fileIsDir);
                            }
                            onClicked: mouse => { if (mouse.button === Qt.RightButton) ctx.popup(); }
                        }

                        Menu {
                            id: ctx
                            MenuItem {
                                text: cell.fileIsDir ? "Open folder" : "Open"
                                onTriggered: root.openEntry(cell.filePath, cell.fileIsDir)
                            }
                            MenuItem {
                                text: "Extract here"
                                // Also gated on the shared extractProc being
                                // idle: one Process serves every delegate, so
                                // re-exec while it runs has no defined result.
                                enabled: cell.isArchive && !extractProc.running
                                onTriggered: root.extract(cell.filePath)
                            }
                            MenuItem { text: "Copy path"; onTriggered: root.copyPath(cell.filePath) }
                            MenuItem { text: "Move to Trash"; onTriggered: root.trashEntry(cell.filePath) }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 24
                color: Cyber.Theme.surface
                Text {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: dir.count + (dir.count === 1 ? " item" : " items")
                        + "  ·  double-click to open · right-click for actions · Backspace up"
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                }
            }
        }
    }
}
