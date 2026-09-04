import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import ".." as Cyber

// Replaces the old single-line Media.qml: reads its player from
// popups/MusicFlow.qml (musicflow.item) rather than recomputing its own
// filtered player list, the same cross-id-reference shape
// bar/NotifyChip.qml and bar/SystemHealthChip.qml already use -- so the
// chip and the panel's own multi-source selector can never disagree about
// which player is "active". Left-click opens the panel (track info,
// playback controls, source selector) instead of toggling play/pause
// directly here.
//
// Not a BarModule this time: the equalizer bars need to sit inside the
// pill alongside the icon/label, and BarModule's Row has no extension
// point for a third child. Everything else (radius, hover colour, click/
// wheel handling) is copied from it to stay visually identical to every
// other chip.
//
// The bars are real audio-reactive, not decorative: PwNodePeakMonitor is
// Quickshell's own local peak-level reader (the same Pipewire service
// bar/Audio.qml and popups/Mixer.qml already use for volume), not a
// subprocess and not a raw-audio read -- it exposes one aggregate `peak`
// float, already computed by Quickshell's own C++ code. This is scoped to
// the *default sink* as a whole, not the specific stream belonging to
// `player`: MPRIS and PipeWire are separate protocols with no built-in way
// to link "this MPRIS player" to "this PipeWire stream", so the bars
// reflect whatever's actually audible, which in practice is almost always
// the same thing while a single player has focus.
Rectangle {
    id: chip

    readonly property var player: musicflow.item ? musicflow.item.player : null
    readonly property bool playing: !!(player && player.isPlaying)

    visible: player !== null
    implicitWidth: row.implicitWidth + 14
    implicitHeight: Cyber.Theme.barHeight - 8
    radius: height / 2
    color: mouse.containsMouse ? Cyber.Theme.sel : "transparent"

    PwNodePeakMonitor {
        id: peakMon
        node: Pipewire.defaultAudioSink
        // Only subscribed while something is actually playing -- no peak
        // data is read at all the rest of the time.
        enabled: chip.playing
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: "\uf001" // fa-music
            textFormat: Text.PlainText
            color: Cyber.Theme.fg
            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
            anchors.verticalCenter: parent.verticalCenter
        }

        // Four-bar equalizer look from one aggregate peak value: fixed
        // per-bar weights (rather than real per-band data, which a single
        // amplitude reading cannot provide) give it an uneven, alive look
        // instead of four identical blocks moving in lockstep.
        Row {
            id: bars
            visible: chip.playing
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            readonly property var weights: [0.55, 1.0, 0.75, 0.45]
            readonly property real maxBarHeight: Cyber.Theme.fontSize + 2
            readonly property real minBarHeight: 2

            Repeater {
                model: bars.weights
                delegate: Rectangle {
                    id: bar
                    required property real modelData
                    required property int index
                    width: 3
                    radius: 1
                    color: Cyber.Theme.accent
                    anchors.bottom: parent.bottom
                    height: Math.max(bars.minBarHeight,
                        Math.min(bars.maxBarHeight, peakMon.peak * bars.maxBarHeight * bar.modelData))
                    Behavior on height {
                        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                    }
                }
            }
        }

        Text {
            text: chip.player ? chip.elide((chip.player.trackArtist ? chip.player.trackArtist + " - " : "") + chip.player.trackTitle, 35) : ""
            // Data this desktop does not control (MPRIS track metadata) --
            // same rule bar/BarModule.qml already applies to every other
            // chip's label, restated here since this chip builds its own
            // Text instead of using BarModule's.
            textFormat: Text.PlainText
            color: Cyber.Theme.fg
            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    function elide(text, max) {
        return text.length > max ? text.slice(0, max - 1) + "…" : text;
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: Quickshell.execDetached(["qs", "ipc", "call", "musicflow", "toggle"])
    }
}
