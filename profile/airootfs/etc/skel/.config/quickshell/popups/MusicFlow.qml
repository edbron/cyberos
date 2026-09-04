import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import ".." as Cyber

// Now-playing panel: track info, playback controls, a multi-source selector
// when more than one MPRIS player is active. Inspired by the UX of
// DevInBlack001/Omarchy-music-flow-copy (a fork of Clifford Baidoo's
// omarchy-music-flow), but not a port of it -- that plugin shells out for
// browser/PipeWire stream scraping and fetches album art from a CDN
// allowlist; everything this file needs (title/artist/album/art/playback
// state, next/previous/toggle) is already exposed locally over D-Bus by
// Quickshell's own Mpris service, so there is no subprocess, no network
// call and no scraping anywhere in this file.
//
// Always loaded (shell.qml's `musicflow` LazyLoader has `active: true`),
// matching notify/NotifyPopups.qml and popups/SystemHealth.qml: the bar
// chip reads `player` from here to colour/label itself even while this
// panel is closed, and both need to agree on which player is "active" when
// more than one is running. `visible: root.opened` is what actually shows
// the window.
PanelWindow {
    id: root

    // top/left stay permanently anchored (matches every closed-state
    // geometry this window has always had); right/bottom only join in
    // while actually open, so Cyber.ClickOutside gets a real "outside"
    // region to catch a click in without this always-loaded window (see
    // the file header: `active: true` in shell.qml, never destroyed)
    // turning into a permanent, invisible full-desktop click-blocker while
    // closed. When closed this is byte-for-byte the same small corner
    // window it always was.
    anchors { top: true; left: true; right: root.opened; bottom: root.opened }
    implicitWidth: 340
    implicitHeight: 280
    color: "transparent"
    focusable: true
    aboveWindows: true
    visible: root.opened

    property bool opened: false
    function open() { root.opened = true; }
    function close() { root.opened = false; }
    function toggle() { root.opened ? root.close() : root.open(); }

    Cyber.ClickOutside { onOutsideClicked: root.close() }

    // A browser MPRIS entry that is not currently playing is usually just a
    // background tab, not a deliberate "now playing" source, and can flicker
    // in and out as tabs open/close -- same exclusion bar/Media.qml (this
    // file's predecessor) used, now scoped to idle entries only: a browser
    // tab actively producing audio right now is exactly the kind of source
    // a student expects to see here, so playing overrides the exclusion.
    readonly property var browsers: ["firefox", "chromium", "brave"]
    function isBrowser(p) { return browsers.some(b => (p.desktopEntry ?? "").includes(b)); }
    readonly property var candidates: Mpris.players.values.filter(p => !isBrowser(p) || p.isPlaying)

    // Sticks to the user's explicit choice (by bus name, stable for a
    // player's lifetime) until that player disappears, then falls back to
    // whatever is first rather than silently landing on a different one.
    property string preferredId: ""
    readonly property var player: {
        if (root.preferredId) {
            const found = root.candidates.find(p => p.dbusName === root.preferredId);
            if (found) return found;
        }
        return root.candidates.length > 0 ? root.candidates[0] : null;
    }
    function selectPlayer(p) { root.preferredId = p.dbusName; }

    // Only ever a local file the player itself already has on disk -- never
    // an http(s) URL, so Image never makes a network request of its own.
    readonly property bool hasLocalArt:
        !!(root.player && root.player.trackArtUrl && root.player.trackArtUrl.startsWith("file://"))

    Rectangle {
        anchors { top: parent.top; left: parent.left; topMargin: 44; leftMargin: 8 }
        width: 340
        height: 280
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

            Text {
                text: "Music Flow"
                color: Cyber.Theme.fg
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
            }

            Text {
                visible: root.player === null
                text: "Nothing playing"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
            }

            RowLayout {
                visible: root.player !== null
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radius: Cyber.Theme.radius / 2
                    color: Cyber.Theme.surface
                    clip: true

                    Image {
                        anchors.fill: parent
                        visible: root.hasLocalArt
                        source: root.hasLocalArt ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.hasLocalArt
                        text: "\uf001" // fa-music
                        color: Cyber.Theme.muted
                        font { family: Cyber.Theme.fontFamily; pixelSize: 24 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.player ? root.player.trackTitle : ""
                        textFormat: Text.PlainText
                        color: Cyber.Theme.fg
                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize; bold: true }
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.player ? root.player.trackArtist : ""
                        textFormat: Text.PlainText
                        color: Cyber.Theme.muted
                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!(root.player && root.player.trackAlbum)
                        text: root.player ? root.player.trackAlbum : ""
                        textFormat: Text.PlainText
                        color: Cyber.Theme.muted
                        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4 }
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle {
                visible: !!(root.player && root.player.positionSupported && root.player.lengthSupported && root.player.length > 0)
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Cyber.Theme.surface

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * Math.max(0, Math.min(1,
                        (root.player && root.player.length > 0) ? root.player.position / root.player.length : 0))
                    radius: parent.radius
                    color: Cyber.Theme.accent
                }
            }

            RowLayout {
                visible: root.player !== null
                Layout.alignment: Qt.AlignHCenter
                spacing: 24

                Text {
                    text: "\uf048" // fa-step-backward
                    color: (root.player && root.player.canGoPrevious) ? Cyber.Theme.fg : Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 4 }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !!(root.player && root.player.canGoPrevious)
                        onClicked: root.player.previous()
                    }
                }
                Text {
                    text: (root.player && root.player.isPlaying) ? "\uf04c" : "\uf04b" // fa-pause / fa-play
                    color: (root.player && root.player.canTogglePlaying) ? Cyber.Theme.accent : Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 8 }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !!(root.player && root.player.canTogglePlaying)
                        onClicked: root.player.togglePlaying()
                    }
                }
                Text {
                    text: "\uf051" // fa-step-forward
                    color: (root.player && root.player.canGoNext) ? Cyber.Theme.fg : Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 4 }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !!(root.player && root.player.canGoNext)
                        onClicked: root.player.next()
                    }
                }
            }

            ColumnLayout {
                visible: root.candidates.length > 1
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4

                Rectangle { Layout.fillWidth: true; height: 1; color: Cyber.Theme.border }
                Text {
                    text: "SOURCE"
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 4 }
                }
                Repeater {
                    model: root.candidates
                    delegate: Rectangle {
                        id: srow
                        required property var modelData
                        readonly property bool selected: root.player === srow.modelData
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Cyber.Theme.radius / 2
                        color: srow.selected ? Cyber.Theme.sel : srowMouse.containsMouse ? Cyber.Theme.surface : "transparent"

                        Text {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: srow.modelData.identity || srow.modelData.desktopEntry || "Player"
                            textFormat: Text.PlainText
                            color: srow.selected ? Cyber.Theme.accent : Cyber.Theme.fg
                            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: srowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.selectPlayer(srow.modelData)
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Text {
                text: "Esc to close"
                color: Cyber.Theme.muted
                font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
            }
        }
    }
}
