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

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#2a1b17"
            border.color: "#5a3a2a"
            border.width: 1
            radius: 6

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: qsTr("Gaming apps")
                        color: "#e59c3f"
                        font.pixelSize: 17
                        font.bold: true
                    }

                    CheckBox {
                        id: gaming

                        Layout.fillWidth: true
                        text: qsTr("Steam, Lutris, and Discord")
                        font.pixelSize: 16
                        contentItem: Text {
                            leftPadding: gaming.indicator.width + gaming.spacing
                            text: gaming.text
                            color: "#ffffff"
                            font: gaming.font
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        onToggled: root.updateSelection()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#4a3025"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: qsTr("Download tools")
                        color: "#e59c3f"
                        font.pixelSize: 17
                        font.bold: true
                    }

                    CheckBox {
                        id: qbittorrent

                        Layout.fillWidth: true
                        text: qsTr("qBittorrent")
                        font.pixelSize: 16
                        contentItem: Text {
                            leftPadding: qbittorrent.indicator.width + qbittorrent.spacing
                            text: qbittorrent.text
                            color: "#ffffff"
                            font: qbittorrent.font
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        onToggled: root.updateSelection()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#4a3025"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: qsTr("Sync tools")
                        color: "#e59c3f"
                        font.pixelSize: 17
                        font.bold: true
                    }

                    CheckBox {
                        id: syncthing

                        Layout.fillWidth: true
                        text: qsTr("Syncthing")
                        font.pixelSize: 16
                        contentItem: Text {
                            leftPadding: syncthing.indicator.width + syncthing.spacing
                            text: syncthing.text
                            color: "#ffffff"
                            font: syncthing.font
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        onToggled: root.updateSelection()
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
