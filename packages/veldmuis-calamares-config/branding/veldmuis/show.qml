import QtQuick 2.15

Rectangle {
    width: 800
    height: 520
    color: "#1c100e"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#3a2319" }
            GradientStop { position: 0.52; color: "#1f1210" }
            GradientStop { position: 1.0; color: "#100908" }
        }
    }

    Rectangle {
        x: -90
        y: 345
        width: 520
        height: 220
        radius: 110
        rotation: -9
        color: "#3f2418"
        opacity: 0.45
    }

    Rectangle {
        x: 510
        y: -95
        width: 360
        height: 360
        radius: 180
        color: "#d58b35"
        opacity: 0.12
    }

    Rectangle {
        anchors.centerIn: parent
        width: 620
        height: 330
        radius: 28
        color: "#211513"
        border.color: "#5a3a2a"
        border.width: 1
        opacity: 0.96
    }

    Column {
        anchors.centerIn: parent
        width: 500
        spacing: 24

        Text {
            width: parent.width
            text: "Installing Veldmuis"
            color: "#fff6ed"
            font.pixelSize: 44
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: "Downloading packages, writing the system, and preparing boot."
            color: "#e7d7c9"
            font.pixelSize: 20
            lineHeight: 1.25
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            width: 360
            height: 1
            color: "#7c5235"
            opacity: 0.8
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            width: parent.width
            text: "This can take several minutes depending on the network. Use Debug below if you want to inspect detailed install logs."
            color: "#c9b8aa"
            font.pixelSize: 15
            lineHeight: 1.35
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
