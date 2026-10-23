pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root
    property var status: ({})
    property string commandError: ""
    readonly property string executable: '"$HOME/.local/bin/blade-power"'
    readonly property string statusCommand: executable + " status --json"
    readonly property string sourceLabel: status.label || "Reading power source…"
    readonly property string shortLabel: {
        switch (status.source) {
        case "main": return "400 W*";
        case "usb": return status.selection === "usb" ? "USB-C*" : "USB-C";
        case "external": return "AC ?";
        case "battery": return "BAT";
        default: return "POWER";
        }
    }
    toolTipMainText: sourceLabel
    toolTipSubText: status.warning || "Click for charger settings. * means manually selected."
    preferredRepresentation: compactRepresentation

    function selectMode(mode) {
        actions.connectSource(executable + " mode " + mode);
    }

    Plasma5Support.DataSource {
        id: readings
        engine: "executable"
        connectedSources: [root.statusCommand]
        interval: 5000
        onNewData: function(source, data) {
            if (data["exit code"] !== 0) {
                root.commandError = data.stderr || "Could not read Blade Power status";
                return;
            }
            try {
                root.status = JSON.parse(data.stdout);
                root.commandError = "";
            } catch (error) {
                root.commandError = "Invalid response from Blade Power";
            }
        }
    }

    Plasma5Support.DataSource {
        id: actions
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                root.commandError = data.stderr || "Charger selection failed";
                return;
            }
            try {
                root.status = JSON.parse(data.stdout);
            } catch (error) {
                root.commandError = "Invalid response from Blade Power";
            }
        }
    }

    compactRepresentation: QQC2.ToolButton {
        text: root.shortLabel
        // Not a battery icon: the tray battery already sits beside this widget.
        icon.name: "preferences-system-power"
        // The tray already shows the battery; spell out only the saving
        // charger or a manual choice.
        display: root.status.source === "usb" || root.shortLabel.endsWith("*")
            ? QQC2.AbstractButton.TextBesideIcon : QQC2.AbstractButton.IconOnly
        Accessible.name: root.sourceLabel
        onClicked: root.expanded = !root.expanded
    }

    // A rounded, softly tinted surface shared by the cards and tiles below.
    component Surface: Rectangle {
        property bool emphasised: false
        radius: Kirigami.Units.largeSpacing
        color: emphasised ? Qt.alpha(Kirigami.Theme.highlightColor, 0.22) : Qt.alpha(Kirigami.Theme.textColor, 0.06)
        border.width: 1
        border.color: emphasised ? Qt.alpha(Kirigami.Theme.highlightColor, 0.55) : Qt.alpha(Kirigami.Theme.textColor, 0.08)
    }

    component Stat: Surface {
        id: stat
        property alias label: statLabel.text
        property alias value: statValue.text
        property string detail: ""
        implicitHeight: statColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1

        ColumnLayout {
            id: statColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: 0
            QQC2.Label {
                id: statLabel
                font: Kirigami.Theme.smallFont
                opacity: 0.65
                Layout.fillWidth: true
            }
            Kirigami.Heading {
                id: statValue
                level: 3
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: stat.detail
                visible: text.length > 0
                font: Kirigami.Theme.smallFont
                opacity: 0.65
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    component ModeTile: QQC2.AbstractButton {
        id: tile
        property string subtitle: ""
        property bool selected: false
        hoverEnabled: true
        padding: Kirigami.Units.largeSpacing
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Accessible.name: text + ", " + subtitle
        background: Surface {
            emphasised: tile.selected
            color: tile.selected ? Qt.alpha(Kirigami.Theme.highlightColor, 0.22)
                : Qt.alpha(Kirigami.Theme.textColor, tile.down ? 0.14 : tile.hovered ? 0.10 : 0.06)
        }
        contentItem: ColumnLayout {
            spacing: 0
            opacity: tile.enabled ? 1 : 0.45
            QQC2.Label {
                text: tile.text
                font.bold: tile.selected
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: tile.subtitle
                font: Kirigami.Theme.smallFont
                opacity: 0.65
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }
    }

    fullRepresentation: ColumnLayout {
        id: popup
        spacing: Kirigami.Units.largeSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: implicitHeight

        readonly property var battery: (root.status.batteries || [])[0] || null
        readonly property bool canChoose: root.status.detected === "external" || root.status.detected === "usb"

        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true
            Kirigami.Icon {
                source: "preferences-system-power"
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: root.sourceLabel
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        implicitWidth: Kirigami.Units.smallSpacing * 2
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: root.status.service_active ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                    }
                    QQC2.Label {
                        text: root.status.service_active ? "Automatic switching is running" : "Automatic switching is not running"
                        font: Kirigami.Theme.smallFont
                        opacity: 0.75
                    }
                }
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            Stat {
                label: "Battery"
                value: popup.battery && popup.battery.capacity !== null
                    ? Math.round(popup.battery.capacity) + "%" : "?"
                detail: !popup.battery ? "" : popup.battery.status
                    + (popup.battery.net_watts === null ? "" : " · " + popup.battery.net_watts + " W")
            }
            Stat {
                label: "Brightness"
                value: (root.status.brightness_percent ?? "?") + "%"
                detail: "target"
            }
            Stat {
                label: "Profile"
                value: root.status.power_profile || "unknown"
            }
        }

        QQC2.Label {
            text: root.commandError || root.status.last_error || root.status.warning || ""
            visible: text.length > 0
            color: Kirigami.Theme.neutralTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            level: 5
            text: "Charger"
            opacity: 0.75
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            ModeTile {
                text: "Automatic"
                subtitle: "detect"
                selected: root.status.selection === "auto"
                onClicked: root.selectMode("auto")
            }
            ModeTile {
                text: "400 W"
                subtitle: "normal mode"
                selected: root.status.selection === "main"
                enabled: popup.canChoose
                onClicked: root.selectMode("main")
            }
            ModeTile {
                text: "USB-C 100 W"
                subtitle: "saving mode"
                selected: root.status.selection === "usb"
                enabled: popup.canChoose
                onClicked: root.selectMode("usb")
            }
        }

        QQC2.Label {
            text: "Manual choices reset when power disconnects or you log out; pick again after swapping chargers "
                + "without unplugging. Battery flow is not charger wattage, so heavy work can still drain the battery on USB-C."
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            Layout.fillWidth: true
        }
    }
}
