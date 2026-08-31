import QtQuick
import QtQuick.Layouts
import Quickshell
import "." as Cyber

PanelWindow {
    id: clockWidget

    anchors { top: true; right: true }
    margins { top: 60; right: 40 }

    implicitWidth: 220
    implicitHeight: 240
    color: "transparent"
    aboveWindows: false
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    SystemClock { id: sys; precision: SystemClock.Minutes }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Qt.alpha(Cyber.Theme.surface, 0.6)
        border.width: 1
        border.color: Qt.alpha(Cyber.Theme.border, 0.4)

        ColumnLayout {
            anchors.centerIn: parent
            spacing: -8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(sys.date, "HH")
                font {
                    family: Cyber.Theme.fontFamily
                    pixelSize: 68
                    bold: true
                }
                color: Cyber.Theme.fg
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(sys.date, "mm")
                font {
                    family: Cyber.Theme.fontFamily
                    pixelSize: 68
                    bold: true
                }
                color: Cyber.Theme.accent
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                implicitWidth: dateText.implicitWidth + 18
                implicitHeight: 26
                radius: 13
                color: Qt.alpha(Cyber.Theme.accent, 0.15)

                Text {
                    id: dateText
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(sys.date, "ddd, MMM d")
                    font {
                        family: Cyber.Theme.fontFamily
                        pixelSize: 12
                        bold: true
                    }
                    color: Cyber.Theme.accent
                }
            }
        }
    }
}
