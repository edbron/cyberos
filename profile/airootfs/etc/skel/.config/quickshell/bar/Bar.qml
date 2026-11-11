import QtQuick
import QtQuick.Layouts
import Quickshell
import ".." as Cyber

PanelWindow {
    id: bar
    anchors { left: true; right: true; top: true }
    implicitHeight: Cyber.Theme.barHeight
    margins { left: 0; right: 0; top: 0 }
    exclusiveZone: implicitHeight
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 0
        color: "transparent"
        border.width: 0

        RowLayout {                       // left
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
            spacing: 8
            BarModule { icon: "\uf00a"; tooltip: "Applications"; onClicked: launcher.activeAsync = true }
            InstallButton {}
            MusicFlowChip {}
        }

        Workspaces {                      // center
            anchors.centerIn: parent
        }

        RowLayout {                       // right
            id: right
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
            spacing: 8
            Tray {}
            BluetoothChip {}
            Audio {}
            Network {}
            Battery {}
            MonitorChip {}
            CloudDrivesChip {}
            SystemHealthChip {}
            NotifyChip {}
            BarModule { icon: "\uf011"; onClicked: powerMenu.activeAsync = true }
        }
    }
}
