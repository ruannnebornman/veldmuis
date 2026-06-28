/*
 * SPDX-FileCopyrightText: no
 * SPDX-License-Identifier: CC0-1.0
 */

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root

    width: 780
    height: 500
    color: "#201411"

    property bool syncing: true
    readonly property var chooserConfig: typeof config === "undefined" ? null : config

    function updateSelection() {
        if (syncing || chooserConfig === null) {
            return
        }

        var selected = []
        if (gaming.checked) {
            selected.push("gaming")
        }
        if (qbittorrent.checked) {
            selected.push("qbittorrent")
        }
        if (syncthing.checked) {
            selected.push("syncthing")
        }
        if (code.checked) {
            selected.push("code")
        }
        chooserConfig.packageChoice = selected.join(",")
    }

    function loadSelection() {
        var selected = []
        if (chooserConfig !== null && chooserConfig.packageChoice.length > 0) {
            selected = chooserConfig.packageChoice.split(",")
        }

        gaming.checked = selected.indexOf("gaming") >= 0
                         || selected.indexOf("steam") >= 0
                         || selected.indexOf("lutris") >= 0
                         || selected.indexOf("discord") >= 0
        qbittorrent.checked = selected.indexOf("qbittorrent") >= 0
        syncthing.checked = selected.indexOf("syncthing") >= 0
        code.checked = selected.indexOf("code") >= 0
        syncing = false
    }

    Component.onCompleted: loadSelection()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Label {
                text: qsTr("Optional software")
                color: "#fff6ed"
                font.pixelSize: 28
                font.bold: true
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Choose any extras you want included in the installed system.")
                color: "#c9b8aa"
                font.pixelSize: 15
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            CheckBox {
                id: gaming

                Layout.fillWidth: true
                Layout.preferredHeight: 76
                hoverEnabled: true
                text: ""

                indicator: Rectangle {
                    width: 28
                    height: 28
                    x: 18
                    y: (gaming.height - height) / 2
                    radius: 5
                    color: gaming.checked ? "#e59c3f" : "#201411"
                    border.color: gaming.checked ? "#f5b85f" : "#80604d"
                    border.width: 2

                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 3
                        color: "#201411"
                        visible: gaming.checked
                    }
                }

                background: Rectangle {
                    radius: 6
                    color: gaming.checked ? "#3a271d"
                                            : (gaming.hovered ? "#32211c" : "#2a1b17")
                    border.color: gaming.checked ? "#e59c3f" : "#5a3a2a"
                    border.width: gaming.checked ? 2 : 1
                }

                Column {
                    anchors.left: gaming.indicator.right
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: qsTr("Gaming apps")
                        color: "#fff6ed"
                        font.pixelSize: 17
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: qsTr("Steam, Lutris, and Discord")
                        color: "#c9b8aa"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                onToggled: root.updateSelection()
            }

            CheckBox {
                id: qbittorrent

                Layout.fillWidth: true
                Layout.preferredHeight: 76
                hoverEnabled: true
                text: ""

                indicator: Rectangle {
                    width: 28
                    height: 28
                    x: 18
                    y: (qbittorrent.height - height) / 2
                    radius: 5
                    color: qbittorrent.checked ? "#e59c3f" : "#201411"
                    border.color: qbittorrent.checked ? "#f5b85f" : "#80604d"
                    border.width: 2

                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 3
                        color: "#201411"
                        visible: qbittorrent.checked
                    }
                }

                background: Rectangle {
                    radius: 6
                    color: qbittorrent.checked ? "#3a271d"
                                                : (qbittorrent.hovered ? "#32211c" : "#2a1b17")
                    border.color: qbittorrent.checked ? "#e59c3f" : "#5a3a2a"
                    border.width: qbittorrent.checked ? 2 : 1
                }

                Column {
                    anchors.left: qbittorrent.indicator.right
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: qsTr("Download tools")
                        color: "#fff6ed"
                        font.pixelSize: 17
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: qsTr("qBittorrent")
                        color: "#c9b8aa"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                onToggled: root.updateSelection()
            }

            CheckBox {
                id: syncthing

                Layout.fillWidth: true
                Layout.preferredHeight: 76
                hoverEnabled: true
                text: ""

                indicator: Rectangle {
                    width: 28
                    height: 28
                    x: 18
                    y: (syncthing.height - height) / 2
                    radius: 5
                    color: syncthing.checked ? "#e59c3f" : "#201411"
                    border.color: syncthing.checked ? "#f5b85f" : "#80604d"
                    border.width: 2

                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 3
                        color: "#201411"
                        visible: syncthing.checked
                    }
                }

                background: Rectangle {
                    radius: 6
                    color: syncthing.checked ? "#3a271d"
                                             : (syncthing.hovered ? "#32211c" : "#2a1b17")
                    border.color: syncthing.checked ? "#e59c3f" : "#5a3a2a"
                    border.width: syncthing.checked ? 2 : 1
                }

                Column {
                    anchors.left: syncthing.indicator.right
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: qsTr("Sync tools")
                        color: "#fff6ed"
                        font.pixelSize: 17
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: qsTr("Syncthing")
                        color: "#c9b8aa"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                onToggled: root.updateSelection()
            }

            CheckBox {
                id: code

                Layout.fillWidth: true
                Layout.preferredHeight: 76
                hoverEnabled: true
                text: ""

                indicator: Rectangle {
                    width: 28
                    height: 28
                    x: 18
                    y: (code.height - height) / 2
                    radius: 5
                    color: code.checked ? "#e59c3f" : "#201411"
                    border.color: code.checked ? "#f5b85f" : "#80604d"
                    border.width: 2

                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 3
                        color: "#201411"
                        visible: code.checked
                    }
                }

                background: Rectangle {
                    radius: 6
                    color: code.checked ? "#3a271d"
                                        : (code.hovered ? "#32211c" : "#2a1b17")
                    border.color: code.checked ? "#e59c3f" : "#5a3a2a"
                    border.width: code.checked ? 2 : 1
                }

                Column {
                    anchors.left: code.indicator.right
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: qsTr("Development tools")
                        color: "#fff6ed"
                        font.pixelSize: 17
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: qsTr("Code - OSS")
                        color: "#c9b8aa"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }

                onToggled: root.updateSelection()
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
