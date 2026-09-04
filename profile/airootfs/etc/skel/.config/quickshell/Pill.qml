import QtQuick
import "." as Cyber

// A small labeled, clickable pill: highlighted when active, dimmed and
// unclickable while busy. Shared by popups/MonitorArrange.qml (direction/
// refresh-rate buttons) and popups/CloudDrives.qml (per-provider actions)
// so the visual definition of "a small action/state button" lives in one
// place instead of two near-identical inline `component Pill` copies.
Rectangle {
    id: pill
    required property string label
    property bool active: false
    property bool busy: false
    signal activated()

    implicitWidth: pillText.implicitWidth + 20
    implicitHeight: 28
    radius: Cyber.Theme.radius / 2
    color: pill.active ? Cyber.Theme.sel
         : pillMouse.containsMouse ? Cyber.Theme.surface : "transparent"
    border.width: 1
    border.color: pill.active ? Cyber.Theme.accent : Cyber.Theme.border
    opacity: pill.busy ? 0.5 : 1

    Text {
        id: pillText
        anchors.centerIn: parent
        text: pill.label
        textFormat: Text.PlainText
        color: pill.active ? Cyber.Theme.accent : Cyber.Theme.fg
        font { family: Cyber.Theme.fontFamily; pixelSize: Cyber.Theme.fontSize - 2 }
    }
    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !pill.busy
        onClicked: pill.activated()
    }
}
