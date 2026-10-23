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
    // mpc reports "playing", "paused", or "stopped".
    readonly property bool active: status.state === "playing" || status.state === "paused"
    readonly property string nowPlaying: active && status.current
        ? (status.state === "paused" ? "Paused: " : "") + status.current : "Nothing playing"
    readonly property string upNext: {
        if (!active) return "";
        const position = status.length > 1 ? "Song " + status.position + " of " + status.length + " · " : "";
        if (status.loop === "song") return position + "Repeating this song";
        if (status.next) return position + "Up next: " + status.next;
        return position + (status.loop === "playlist" ? "Then the queue starts again" : "Last song in the queue");
    }
    readonly property var loopModes: [
        {mode: "off", label: "No repeat", icon: "media-repeat-none"},
        {mode: "playlist", label: "Repeat all", icon: "media-repeat-all"},
        {mode: "song", label: "Repeat song", icon: "media-repeat-single"}
    ]
    readonly property string syncLabel: {
        if (status.mounted === false) return "Music drive is not mounted";
        if (status.syncing) return "Syncing YouTube Music…";
        const last = status.last_sync ? status.last_sync.replace("T", " ").slice(0, 16) : "never";
        return "Last sync " + last + " · " + (status.cached || 0) + " cached songs";
    }
    toolTipMainText: nowPlaying
    toolTipSubText: upNext ? upNext + "\n" + syncLabel : syncLabel
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
        // Not audio-headphones: the volume applet shows that icon for headphones.
        icon.name: "youtube-music"
        Accessible.name: "Blade Music: " + root.nowPlaying
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

    component Tile: QQC2.AbstractButton {
        id: tile
        property string subtitle: ""
        property bool selected: false
        hoverEnabled: true
        padding: Kirigami.Units.smallSpacing * 2
        Accessible.name: subtitle ? text + ", " + subtitle : text
        background: Surface {
            emphasised: tile.selected
            color: tile.selected ? Qt.alpha(Kirigami.Theme.highlightColor, 0.22)
                : Qt.alpha(Kirigami.Theme.textColor, tile.down ? 0.14 : tile.hovered ? 0.10 : 0.06)
        }
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing * 2
            opacity: tile.enabled ? 1 : 0.45
            Kirigami.Icon {
                source: tile.icon.name
                visible: source !== ""
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                QQC2.Label {
                    text: tile.text
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: tile.subtitle
                    visible: text.length > 0
                    font: Kirigami.Theme.smallFont
                    opacity: 0.65
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }

    fullRepresentation: ColumnLayout {
        id: popup
        spacing: Kirigami.Units.largeSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: implicitHeight

        // "Artist - Title" from mpc; show the title first when it splits cleanly.
        readonly property var track: {
            const current = root.active ? (root.status.current || "") : "";
            const split = current.indexOf(" - ");
            return split > 0 ? {title: current.slice(split + 3), artist: current.slice(0, split)}
                : {title: current || "Nothing playing", artist: ""};
        }

        Surface {
            Layout.fillWidth: true
            implicitHeight: nowPlaying.implicitHeight + Kirigami.Units.largeSpacing * 2

            ColumnLayout {
                id: nowPlaying
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: root.status.state === "playing" ? "Now playing" : root.status.state === "paused" ? "Paused" : "Blade Music"
                        font: Kirigami.Theme.smallFont
                        color: root.status.state === "playing" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: root.status.length > 1 ? root.status.position + " / " + root.status.length : ""
                        font: Kirigami.Theme.smallFont
                        opacity: 0.65
                    }
                }
                Kirigami.Heading {
                    level: 3
                    text: popup.track.title
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: popup.track.artist
                    visible: text.length > 0
                    opacity: 0.75
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    // upNext without the "Song n of m" prefix, which the corner shows.
                    text: root.upNext.replace(/^Song \d+ of \d+ · /, "")
                    visible: text.length > 0
                    font: Kirigami.Theme.smallFont
                    opacity: 0.65
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Segmented repeat control.
                Surface {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    implicitHeight: loopRow.implicitHeight + 4
                    color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.6)

                    RowLayout {
                        id: loopRow
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2
                        Repeater {
                            model: root.loopModes
                            delegate: QQC2.ToolButton {
                                required property var modelData
                                text: modelData.label
                                icon.name: modelData.icon
                                checkable: true
                                checked: root.status.loop === modelData.mode
                                onClicked: root.run(root.executable + " loop " + modelData.mode)
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }

        Kirigami.Heading {
            level: 5
            text: "Playlists"
            opacity: 0.75
        }
        GridLayout {
            columns: 2
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            Tile {
                text: "Shuffle everything"
                subtitle: (root.status.cached || 0) + " cached songs"
                icon.name: "media-playlist-shuffle"
                selected: true
                onClicked: root.run(root.executable + " play")
                Layout.columnSpan: 2
                Layout.fillWidth: true
            }
            Repeater {
                model: root.status.playlists || []
                delegate: Tile {
                    required property var modelData
                    text: modelData.name
                    subtitle: modelData.available === modelData.total
                        ? modelData.total + " songs" : modelData.available + " of " + modelData.total + " cached"
                    icon.name: "media-playlist-play"
                    enabled: modelData.available > 0
                    onClicked: root.run(root.executable + " play " + root.shellQuote(modelData.playlist))
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                }
            }
        }

        QQC2.Label {
            text: root.commandError
            visible: text.length > 0
            color: Kirigami.Theme.neutralTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                // Short form of syncLabel: the song count is on the shuffle tile.
                text: {
                    if (root.status.mounted === false || root.status.syncing || !root.status.last_sync) {
                        return root.syncLabel;
                    }
                    const when = new Date(root.status.last_sync);
                    const today = new Date().toDateString() === when.toDateString();
                    return "Synced " + (today ? "" : when.toLocaleDateString(Qt.locale(), "d MMM") + " ")
                        + when.toLocaleTimeString(Qt.locale(), "HH:mm");
                }
                font: Kirigami.Theme.smallFont
                opacity: 0.65
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.ToolButton {
                icon.name: "view-refresh"
                text: root.status.syncing ? "Syncing…" : "Sync"
                enabled: !root.status.syncing && root.status.mounted !== false
                onClicked: root.run(root.executable + " sync-now")
                QQC2.ToolTip.text: "Download new favourites now; the hourly sync does this when ~/storage is mounted"
                QQC2.ToolTip.visible: hovered
            }
            QQC2.ToolButton {
                icon.name: "multimedia-audio-player"
                text: "Player"
                onClicked: root.run('"$HOME/.local/bin/blade-music-web"')
                QQC2.ToolTip.text: "Open the myMPD web player"
                QQC2.ToolTip.visible: hovered
            }
        }
    }
}
