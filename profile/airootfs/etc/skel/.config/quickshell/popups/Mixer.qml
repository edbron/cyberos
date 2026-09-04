import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import ".." as Cyber

// Replaces pavucontrol-qt. Opened via `qs ipc call mixer toggle` (shell.qml's
// IpcHandler flips the owning LazyLoader's `active`), so -- like every other
// popup here -- it is built fresh on open and destroyed on close.
//
// PwNodeType is a BITFLAG enum. Verified numerics: Audio=1, Video=2, Stream=4,
// Source=8, Sink=16, so AudioSink=17, AudioSource=9, AudioOutStream=21,
// AudioInStream=13. AudioOutStream therefore CARRIES THE SINK BIT: a playing
// application reports isSink === true exactly like a real sound card does, so
// filtering on isSink would list Firefox among the output devices. Every
// classification below compares `type` exactly for that reason.
PanelWindow {
    id: root

    signal closeRequested()

    // Fullscreen, transparent surface: the visible box below positions
    // itself via its own anchors/margins instead of the window's, so
    // Cyber.ClickOutside (this window's first child, right below) has a
    // real "outside" region to catch a click in -- a window sized to just
    // the popup itself has no such region.
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    focusable: true
    aboveWindows: true

    Cyber.ClickOutside { onOutsideClicked: root.closeRequested() }

    // Track EVERY node, not the filtered subset. PwNode.type stays
    // PwNodeType.Untracked (0) until something tracks the node, so filtering
    // first and tracking the result is circular: the filter matches nothing,
    // so nothing gets tracked, so the filter keeps matching nothing and the
    // panel is permanently empty. Verified: before tracking, Pipewire.nodes
    // is empty; after tracking all, types resolve to 17 (AudioSink) / 9
    // (AudioSource) / 21 (AudioOutStream).
    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property var sinks: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSink)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)
    readonly property var source: Pipewire.defaultAudioSource

    // Applications set application.name; fall back through description to the
    // raw node name so a stream is never rendered as a blank row.
    function labelFor(node) {
        return (node.properties && node.properties["application.name"])
            || node.description || node.name || "Unknown";
    }

    // One row per volume-bearing node. Inline component so the three sections
    // below share it instead of repeating the slider/mute/label block.
    component VolumeRow: RowLayout {
        id: row
        required property var node
        required property string label
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.preferredWidth: 96
            text: row.label
            textFormat: Text.PlainText
            color: Cyber.Theme.fg
            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
            elide: Text.ElideRight
        }
        Slider {
            id: slider
            Layout.fillWidth: true
            from: 0; to: 1
            value: row.node?.audio.volume ?? 0
            onMoved: if (row.node) row.node.audio.volume = value
            // Dragging writes `value` and severs the binding above, so an
            // external change (bar scroll chip, XF86 keys, another app) would
            // stop moving the slider for the rest of this panel's life.
            // Re-assert it whenever the node's own volume changes and the
            // user is not currently dragging. PwNodeAudio's `volume`
            // property shares its NOTIFY signal with `volumes`
            // (volumesChanged) -- there is no volumeChanged.
            Connections {
                target: row.node?.audio ?? null
                function onVolumesChanged() {
                    if (!slider.pressed) slider.value = row.node.audio.volume;
                }
            }
        }
        Text {
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: Math.round((row.node?.audio.volume ?? 0) * 100) + "%"
            color: Cyber.Theme.muted
            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
        }
        // volume-xmark / volume-up -- same glyphs as bar/Audio.qml.
        Text {
            text: (row.node?.audio.muted ?? false) ? "\ueee8" : "\uf028"
            color: (row.node?.audio.muted ?? false) ? Cyber.Theme.alert : Cyber.Theme.fg
            font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize }
            MouseArea {
                anchors.fill: parent
                onClicked: if (row.node) row.node.audio.muted = !row.node.audio.muted
            }
        }
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 44; rightMargin: 8 }
        width: 380
        height: 480
        radius: Cyber.Theme.radius
        color: Cyber.Theme.bg
        border.width: 1
        border.color: Cyber.Theme.border

        focus: true
        Keys.onEscapePressed: root.closeRequested()

        // Swallows a click on blank space inside the popup: a plain
        // Rectangle doesn't itself accept mouse events, so without this a
        // click here would fall through to Cyber.ClickOutside behind the
        // whole window and close the popup it landed inside.
        MouseArea { anchors.fill: parent }

        ScrollView {
            id: scroll
            anchors.fill: parent
            anchors.margins: 12

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 10

                Text {
                    text: "Sound"
                    color: Cyber.Theme.fg
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize + 2; bold: true }
                }

                // ---- output devices ----
                Text {
                    text: "Output"
                    color: Cyber.Theme.accent
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                }
                Text {
                    visible: root.sinks.length === 0
                    text: "No output devices"
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
                }
                Repeater {
                    model: root.sinks
                    delegate: ColumnLayout {
                        id: sinkEntry
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2

                        // The device-select click target is this name row ONLY,
                        // never the whole entry: a MouseArea covering the entry
                        // would sit over the volume slider below and eat its
                        // drag. The MouseArea is also parented to a plain Item,
                        // not to the RowLayout -- a MouseArea placed directly in
                        // a layout is laid out as a cell of it.
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 22

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6
                                // dot-circle when selected, circle when not; both
                                // cmap-verified in JetBrainsMono Nerd Font.
                                Text {
                                    text: Pipewire.defaultAudioSink === sinkEntry.modelData ? "\uf192" : "\uf111"
                                    color: Pipewire.defaultAudioSink === sinkEntry.modelData
                                        ? Cyber.Theme.accent : Cyber.Theme.muted
                                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.labelFor(sinkEntry.modelData)
                                    textFormat: Text.PlainText
                                    color: Cyber.Theme.fg
                                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: Pipewire.preferredDefaultAudioSink = sinkEntry.modelData
                            }
                        }
                        VolumeRow { node: sinkEntry.modelData; label: "" }
                    }
                }

                // ---- application streams ----
                Text {
                    text: "Applications"
                    color: Cyber.Theme.accent
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                }
                Text {
                    visible: root.streams.length === 0
                    text: "Nothing is playing"
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
                }
                Repeater {
                    model: root.streams
                    delegate: VolumeRow {
                        required property var modelData
                        node: modelData
                        label: root.labelFor(modelData)
                    }
                }

                // ---- input ----
                Text {
                    text: "Input"
                    color: Cyber.Theme.accent
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
                }
                VolumeRow {
                    visible: root.source !== null
                    node: root.source
                    label: root.source ? root.labelFor(root.source) : ""
                }
                Text {
                    visible: root.source === null
                    text: "No input device"
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 1 }
                }

                Item { Layout.fillHeight: true }

                Text {
                    text: "Click a device to make it default · Esc to close"
                    color: Cyber.Theme.muted
                    font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 3 }
                }
            }
        }
    }
}
