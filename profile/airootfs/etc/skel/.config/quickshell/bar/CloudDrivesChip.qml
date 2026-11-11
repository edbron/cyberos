import QtQuick
import Quickshell
import ".." as Cyber

// Reads the panel's own state (never disagrees on how many drives are
// mounted) via the bare `cloudDrives` id -- shell.qml's own LazyLoader,
// visible here the same way bar/MonitorChip.qml sees `monitorArrange`.
// Toggles via IPC, matching every other chip here.
BarModule {
    id: chip
    readonly property int mountedCount: cloudDrives.item ? cloudDrives.item.mountedCount : 0

    // cloud-upload -- \u escape only, no raw glyph byte (this shell's own
    // PUA policy).
    icon: "\uf0ee"
    iconColor: chip.mountedCount > 0 ? Cyber.Theme.accent : Cyber.Theme.fg
    tooltip: chip.mountedCount > 0
        ? chip.mountedCount + " cloud drive" + (chip.mountedCount === 1 ? "" : "s") + " mounted"
        : "Cloud Drives"

    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "clouddrives", "toggle"])
}
