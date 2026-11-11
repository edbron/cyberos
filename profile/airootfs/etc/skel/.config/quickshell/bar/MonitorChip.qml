import QtQuick
import Quickshell
import ".." as Cyber

// Reads the panel's own state (never disagrees on whether an external
// monitor is connected) via the bare `monitorArrange` id -- shell.qml's own
// LazyLoader, visible here the same way bar/MusicFlowChip.qml sees
// `musicflow` (see shell.qml's comment on why that resolves from bar/*.qml).
// Toggles via IPC, matching every other chip here.
BarModule {
    id: chip
    readonly property int externalCount: monitorArrange.item ? monitorArrange.item.externals.length : 0

    // tv (external display present) / monitor (internal only) -- \u escapes
    // only, no raw glyph byte (this shell's own PUA policy); the monitor
    // glyph is outside the BMP, so it's a UTF-16 surrogate pair, same shape
    // as bar/BluetoothChip.qml's own off-state glyph.
    icon: chip.externalCount > 0 ? "\uf26c" : "\udb80\udd79"
    iconColor: chip.externalCount > 0 ? Cyber.Theme.accent : Cyber.Theme.fg
    tooltip: chip.externalCount > 0 ? "External display connected" : "Arrange displays"

    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "monitorarrange", "toggle"])
}
