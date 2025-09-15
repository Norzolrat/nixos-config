import QtQuick 2.15
import QtQuick.Controls 1.4
import QtQuick.Layouts 1.3
import SddmComponents 2.0
import "components"

Item {
    id: root
    width: 1920; height: 1080
    focus: true

    Background { anchors.fill: parent }

    Rectangle {
        id: panel
        width: Math.min(parent.width * 0.36, 640)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        color: "#1b1d24AA"
        border.width: 1; border.color: "#ffffff22"; radius: 16

        Column {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 18

            Login {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                onRequestLogin: function(user, password) {
                    sddm.login(user, password, "")
                }
            }
        }
    }

    Row {
        spacing: 12
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24

        Text {
            id: clock
            color: "white"; opacity: 0.9
            text: Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm")
            font.pixelSize: 16
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm")
            }
        }

        Button { text: "⭯";   onClicked: sddm.reboot() }
        Button { text: "⏻"; onClicked: sddm.powerOff() }
    }
}
