import QtQuick
import Quickshell
import ".." as Cyber

// Colour reflects the same worst-of-CPU/memory/battery/disks status the
// popup's hero line shows -- shell.qml owns the live payload (systemhealth
// LazyLoader's item), the same cross-id-reference shape bar/NotifyChip.qml
// already uses for shell.dnd/notifServer.
BarModule {
    id: chip

    icon: "\uf2db" // fa-microchip, verified present in the shipped Nerd Font's cmap
    iconColor: systemhealth.item && systemhealth.item.overallStatus !== "good"
        ? (systemhealth.item.overallStatus === "bad" ? Cyber.Theme.alert : Cyber.Theme.accent2)
        : Cyber.Theme.fg
    tooltip: "System Health"

    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "systemhealth", "toggle"])
}
