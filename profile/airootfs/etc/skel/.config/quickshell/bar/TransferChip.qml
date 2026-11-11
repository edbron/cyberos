import QtQuick
import Quickshell
import ".." as Cyber

// Reads the popup's own state (never disagrees on job count/failure) via
// the bare `transfer` id -- shell.qml's own LazyLoader, same as
// bar/CloudDrivesChip.qml reads `cloudDrives`. Toggles via IPC, matching
// every other chip here.
BarModule {
    id: chip
    readonly property int activeCount: transfer.item ? transfer.item.activeCount : 0
    readonly property bool hasError: transfer.item ? transfer.item.hasError : false

    // exchange -- \u escape only, no raw glyph byte (this shell's own PUA
    // policy).
    icon: "\uf0ec"
    iconColor: chip.hasError ? Cyber.Theme.alert : (chip.activeCount > 0 ? Cyber.Theme.accent : Cyber.Theme.fg)
    tooltip: chip.hasError
        ? "A transfer failed"
        : (chip.activeCount > 0 ? chip.activeCount + " active transfer" + (chip.activeCount === 1 ? "" : "s") : "No ongoing transfer")

    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "transfer", "toggle"])
}
