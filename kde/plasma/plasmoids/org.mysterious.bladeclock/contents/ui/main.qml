import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property color hourColor: "#AECBFA"
    readonly property color minuteColor: "#81C995"
    readonly property color foreground: "#F0F6FC"
    readonly property color muted: "#9AA7B5"
    property date currentDateTime: new Date()

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: Qt.formatTime(currentDateTime, "HH:mm")
    toolTipSubText: Qt.formatDate(currentDateTime, "dddd, MMMM d")

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentDateTime = new Date()
    }

    fullRepresentation: Item {
        id: face

        Layout.minimumWidth: 300
        Layout.minimumHeight: 430
        Layout.preferredWidth: 430
        Layout.preferredHeight: 600

        readonly property real unitScale: Math.max(0.68,
            Math.min(width / 430, height / 600))

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 22 * face.unitScale
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Row {
                height: 28 * face.unitScale
                spacing: 9 * face.unitScale

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7 * face.unitScale
                    height: width
                    radius: width / 2
                    color: root.minuteColor
                    opacity: 0.9
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BLADE  /  LOCAL TIME"
                    color: root.muted
                    font.family: "Noto Sans"
                    font.pixelSize: 12 * face.unitScale
                    font.bold: true
                    font.letterSpacing: 1.6 * face.unitScale
                    renderType: Text.NativeRendering
                }
            }

            Text {
                width: 310 * face.unitScale
                height: 166 * face.unitScale
                text: Qt.formatTime(root.currentDateTime, "HH")
                color: root.hourColor
                font.family: "Noto Sans"
                font.pixelSize: 174 * face.unitScale
                font.weight: Font.DemiBold
                font.letterSpacing: -7 * face.unitScale
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
                style: Text.Raised
                styleColor: "#78000000"
            }

            Text {
                width: 310 * face.unitScale
                height: 166 * face.unitScale
                text: Qt.formatTime(root.currentDateTime, "mm")
                color: root.minuteColor
                font.family: "Noto Sans"
                font.pixelSize: 174 * face.unitScale
                font.weight: Font.DemiBold
                font.letterSpacing: -7 * face.unitScale
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
                style: Text.Raised
                styleColor: "#78000000"
            }

            Item {
                width: 1
                height: 20 * face.unitScale
            }

            Rectangle {
                width: dateLabel.implicitWidth + 34 * face.unitScale
                height: 43 * face.unitScale
                radius: height / 2
                color: "#D90B1118"
                border.width: Math.max(1, face.unitScale)
                border.color: "#405B7895"

                Text {
                    id: dateLabel
                    anchors.centerIn: parent
                    text: Qt.formatDate(root.currentDateTime, "dddd, MMM d").toUpperCase()
                    color: root.foreground
                    font.family: "Noto Sans"
                    font.pixelSize: 12 * face.unitScale
                    font.bold: true
                    font.letterSpacing: 1.25 * face.unitScale
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
