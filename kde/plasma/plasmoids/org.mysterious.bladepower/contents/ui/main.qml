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
        icon.name: root.status.source === "battery" ? "battery" : "battery-charging"
        display: QQC2.AbstractButton.TextBesideIcon
        Accessible.name: root.sourceLabel
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: implicitHeight

        Kirigami.Heading {
            level: 3
            text: root.sourceLabel
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Repeater {
            model: root.status.batteries || []
            delegate: QQC2.Label {
                required property var modelData
                text: modelData.status + " · " + (modelData.capacity === null ? "?" : modelData.capacity) + "%"
                    + (modelData.net_watts === null ? "" : " · " + modelData.net_watts + " W net battery flow")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
        QQC2.Label {
            text: "Brightness target: " + (root.status.brightness_percent ?? "?") + "% · "
                + (root.status.power_profile || "unknown profile")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: root.status.service_active ? "Automatic switching is running" : "Automatic switching is not running"
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: root.commandError || root.status.last_error || root.status.warning || ""
            visible: text.length > 0
            color: Kirigami.Theme.neutralTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: "Automatic detection"
            checkable: true
            checked: root.status.selection === "auto"
            onClicked: root.selectMode("auto")
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: "400 W main charger — normal mode"
            enabled: root.status.detected === "external" || root.status.detected === "usb"
            onClicked: root.selectMode("main")
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: "100 W USB-C charger — saving mode"
            enabled: root.status.detected === "external" || root.status.detected === "usb"
            onClicked: root.selectMode("usb")
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: "Manual charger choices reset when the service observes a disconnect or you log out. "
                + "Select again if you swap chargers without disconnecting power. "
                + "Use the adjacent brightness control for manual adjustments. "
                + "Battery flow is not charger wattage; heavy workloads can still drain the battery on USB-C."
            wrapMode: Text.WordWrap
            opacity: 0.8
            Layout.fillWidth: true
        }
    }
}
