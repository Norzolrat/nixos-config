import QtQuick 2.15
import QtQuick.Controls 1.4
import QtQuick.Layouts 1.3
import SddmComponents 2.0

Item {
    id: loginRoot
    signal requestLogin(string user, string password)

    width: parent ? parent.width : 480
    height: panel.implicitHeight

    function currentUserName() {
        if (!userList.model || userList.currentIndex < 0) return "";
        var obj = userModel.get(userList.currentIndex);
        return obj && obj.name ? obj.name : "";
    }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        color: "#000000AA"   // semi-transparent dark background
        radius: 10
        width: parent.width
        anchors.margins: 12

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // USER SELECTOR
            ListView {
                id: userList
                width: parent.width
                height: Math.min(56 * (model && model.count ? model.count : 0), 112)
                clip: true
                interactive: (model && model.count > 2)
                model: userModel
                currentIndex: (model && model.count > 0) ? 0 : -1
                boundsBehavior: Flickable.StopAtBounds

                highlightFollowsCurrentItem: true
                highlightMoveDuration: 120
                highlight: Rectangle {
                    width: userList.width
                    height: userList.currentItem ? userList.currentItem.height : 56
                    color: "#FFFFFF22"   // subtle translucent white instead of yellow
                    radius: 8
                }

                delegate: Rectangle {
                    width: userList.width
                    height: 56
                    color: "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        // circular avatar with fallback
                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: "transparent"
                            clip: true

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: {
                                    if (model.homeDirectory && model.homeDirectory !== "")
                                        return "file://" + model.homeDirectory + "/.face";
                                    else
                                        return Qt.resolvedUrl("../backgrounds/default-avatar.png");
                                }
                                onStatusChanged: if (status === Image.Error)
                                    source = Qt.resolvedUrl("../backgrounds/default-avatar.png");
                            }
                        }

                        // username text next to avatar
                        Text {
                            text: (typeof model.name !== "undefined") ? model.name : "user"
                            verticalAlignment: Text.AlignVCenter
                            color: (index === userList.currentIndex) ? "white" : "#CCCCCC"
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: userList.currentIndex = index
                    }
                }
            }

            // PASSWORD + LOGIN INLINE
            Row {
                width: parent.width
                spacing: 8

                TextField {
                    id: passwordField
                    width: parent.width - loginButton.width - 12
                    echoMode: TextInput.Password
                    placeholderText: "Password"
                    focus: true
                    Keys.onReturnPressed: loginRoot.requestLogin(loginRoot.currentUserName(), text)
                    Keys.onEnterPressed:  loginRoot.requestLogin(loginRoot.currentUserName(), text)
                }

                Button {
                    id: loginButton
                    text: "Login"
                    onClicked: loginRoot.requestLogin(loginRoot.currentUserName(), passwordField.text)
                }
            }
        }
    }
}
