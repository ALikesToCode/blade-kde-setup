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
    readonly property string executable: '"$HOME/.local/bin/blade-music"'
    readonly property string statusCommand: executable + " status"
    readonly property string nowPlaying: status.state === "play" || status.state === "pause"
        ? status.current : "Nothing playing"
    readonly property string syncLabel: {
        if (status.mounted === false) return "Music drive is not mounted";
        if (status.syncing) return "Syncing YouTube Music…";
        const last = status.last_sync ? status.last_sync.replace("T", " ").slice(0, 16) : "never";
        return "Last sync " + last + " · " + (status.cached || 0) + " cached songs";
    }
    toolTipMainText: nowPlaying
    toolTipSubText: syncLabel
    preferredRepresentation: compactRepresentation

    function shellQuote(text) {
        return "'" + text.replace(/'/g, "'\\''") + "'";
    }

    function run(command) {
        root.commandError = "";
        actions.connectSource(command);
    }

    Plasma5Support.DataSource {
        id: readings
        engine: "executable"
        connectedSources: [root.statusCommand]
        interval: 5000
        onNewData: function(source, data) {
            if (data["exit code"] !== 0) {
                root.commandError = data.stderr || "Could not read Blade Music status";
                return;
            }
            try {
                root.status = JSON.parse(data.stdout);
            } catch (error) {
                root.commandError = "Invalid response from Blade Music";
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
                root.commandError = data.stderr || "Command failed";
            }
            readings.disconnectSource(root.statusCommand);
            readings.connectSource(root.statusCommand);
        }
    }

    compactRepresentation: QQC2.ToolButton {
        icon.name: "audio-headphones"
        Accessible.name: "Blade Music: " + root.nowPlaying
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: implicitHeight

        Kirigami.Heading {
            level: 3
            text: root.nowPlaying
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: root.syncLabel
            opacity: 0.8
            Layout.fillWidth: true
        }
        Kirigami.Separator { Layout.fillWidth: true }
        Repeater {
            model: root.status.playlists || []
            delegate: QQC2.Button {
                required property var modelData
                text: modelData.name + "  ·  " + modelData.available + "/" + modelData.total
                enabled: modelData.available > 0
                icon.name: "media-playlist-play"
                onClicked: root.run(root.executable + " play " + root.shellQuote(modelData.playlist))
                Layout.fillWidth: true
            }
        }
        QQC2.Button {
            text: "Shuffle the whole library"
            icon.name: "media-playlist-shuffle"
            onClicked: root.run(root.executable + " play")
            Layout.fillWidth: true
        }
        Kirigami.Separator { Layout.fillWidth: true }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                text: root.status.syncing ? "Syncing…" : "Sync now"
                icon.name: "view-refresh"
                enabled: !root.status.syncing && root.status.mounted !== false
                onClicked: root.run(root.executable + " sync-now")
                Layout.fillWidth: true
            }
            QQC2.Button {
                text: "Open player"
                icon.name: "multimedia-audio-player"
                onClicked: root.run('"$HOME/.local/bin/blade-music-web"')
                Layout.fillWidth: true
            }
        }
        QQC2.Label {
            text: root.commandError
            visible: text.length > 0
            color: Kirigami.Theme.neutralTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: "Play, pause, and skip from the Media Player widget or media keys; "
                + "the hourly sync downloads new favourites when ~/storage is mounted."
            wrapMode: Text.WordWrap
            opacity: 0.8
            Layout.fillWidth: true
        }
    }
}
