import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#05070a"

    readonly property color surface: "#0A0E14"
    readonly property color surfaceRaised: "#101722"
    readonly property color surfaceHover: "#14263A"
    readonly property color surfacePressed: "#09131F"
    readonly property color primaryButton: "#0D2A45"
    readonly property color primaryButtonHover: "#143E63"
    readonly property color primaryButtonPressed: "#081A2A"
    readonly property color primary: "#8AB4F8"
    readonly property color softBlue: "#AECBFA"
    readonly property color softGreen: "#81C995"
    readonly property color foreground: "#F0F6FC"
    readonly property color muted: "#8B949E"
    readonly property color selection: "#274C77"
    readonly property color errorColor: "#F28B82"

    // Background
    Image {
        id: backgroundImage
        anchors.fill: parent
        source: (Screen.width / Math.max(1, Screen.height)) > 2.0
            ? "login-ultrawide-3440x1440.png"
            : "login-16x10-3840x2400.png"
        fillMode: Image.PreserveAspectCrop
        opacity: 1
    }

    Rectangle {
        anchors.fill: parent
        color: "#07111D"
        opacity: 0.08
    }

    readonly property real s: Screen.height / 768
    property bool isQuickshell: typeof sddm === "undefined" || sddm.hostName === undefined
    property int sessionIndex: (typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0) ? sessionModel.lastIndex : 0
    property int userIndex: (typeof userModel !== "undefined" && userModel.lastIndex >= 0) ? userModel.lastIndex : 0

    // UI States
    property real ui1: 0
    property real ui2: 0
    property string errorMessage: ""

    // Portable system font; installed by the package manifest.
    readonly property string sansFont: "Noto Sans"

    ListView {
        id: sessionHelper
        model: typeof sessionModel !== "undefined" ? sessionModel : null
        currentIndex: root.sessionIndex
        opacity: 0
        width: 100
        height: 100
        z: -100
        delegate: Item {
            property string sName: model.name || ""
        }
    }

    ListView {
        id: userHelper
        model: typeof userModel !== "undefined" ? userModel : null
        currentIndex: root.userIndex
        opacity: 0
        width: 100
        height: 100
        z: -100
        delegate: Item {
            property string uName: model.realName || model.name || ""
            property string uLogin: model.name || ""
        }
    }

    Timer {
        id: focusTimer
        interval: 300
        running: true
        onTriggered: pwd.forceActiveFocus()
    }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null
        function onLoginFailed() {
            root.errorMessage = "ACCESS DENIED";
            pwd.text = "";
            shakeAnim.start();
            errTimer.start();
        }
    }

    Timer {
        id: errTimer
        interval: 3000
        onTriggered: root.errorMessage = ""
    }

    Component.onCompleted: {
        fadeAnim.start();
        if (typeof keyboard !== "undefined") keyboard.numLock = true;
    }

    SequentialAnimation {
        id: fadeAnim
        PauseAnimation { duration: 500 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "ui1"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "ui2"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shakeTranslate; property: "x"; to: 15*s; duration: 50 }
        NumberAnimation { target: shakeTranslate; property: "x"; to: -15*s; duration: 50 }
        NumberAnimation { target: shakeTranslate; property: "x"; to: 15*s; duration: 50 }
        NumberAnimation { target: shakeTranslate; property: "x"; to: -15*s; duration: 50 }
        NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 50 }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.ArrowCursor
        z: -1
        onClicked: pwd.forceActiveFocus()
    }

    // Layout Row
    Row {
        id: mainLayout
        anchors.centerIn: parent
        spacing: 96 * s
        opacity: root.ui1
        scale: 0.96 + (0.04 * root.ui1)
        transform: Translate { y: (1 - root.ui1) * 30 * s }

        // Left Section
        Column {
            spacing: 24 * s
            anchors.verticalCenter: parent.verticalCenter

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    let d = new Date();
                    hText.text = Qt.formatTime(d, "hh");
                    mText.text = Qt.formatTime(d, "mm");
                    dateChipText.text = Qt.formatDate(d, "dddd, MMM d").toUpperCase();
                }
            }

            // Clock
            Column {
                spacing: -24 * s

                Text {
                    id: hText
                    text: Qt.formatTime(new Date(), "hh")
                    font.family: root.sansFont
                    font.pixelSize: 140 * s
                    font.weight: Font.Bold
                    color: root.softBlue
                }

                Text {
                    id: mText
                    text: Qt.formatTime(new Date(), "mm")
                    font.family: root.sansFont
                    font.pixelSize: 140 * s
                    font.weight: Font.Bold
                    color: root.softGreen
                }
            }

            // Date Pill
            Rectangle {
                width: dateChipText.implicitWidth + 32 * s
                height: 44 * s
                radius: 22 * s
                color: root.surfaceHover

                Text {
                    id: dateChipText
                    anchors.centerIn: parent
                    text: Qt.formatDate(new Date(), "dddd, MMM d").toUpperCase()
                    font.family: root.sansFont
                    font.pixelSize: 11 * s
                    font.bold: true
                    font.letterSpacing: 1 * s
                    color: root.foreground
                }
            }
        }

        // Right Section
        Column {
            spacing: 24 * s
            anchors.verticalCenter: parent.verticalCenter

            // Settings Title
            Text {
                text: "QUICK SETTINGS"
                font.family: root.sansFont
                font.pixelSize: 11 * s
                font.bold: true
                font.letterSpacing: 1.5 * s
                color: root.muted
            }

            // Settings Grid
            Grid {
                columns: 2
                spacing: 16 * s

                // Power
                Rectangle {
                    id: powerTile
                    width: 180 * s; height: 76 * s; radius: 38 * s
                    color: powerMouse.pressed ? root.surfacePressed : (powerMouse.containsMouse ? root.surfaceHover : root.surface)
                    scale: powerMouse.pressed ? 0.95 : (powerMouse.containsMouse ? 1.03 : 1.0)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16 * s
                        anchors.rightMargin: 16 * s
                        spacing: 12 * s

                        Rectangle {
                            width: 48 * s; height: 48 * s; radius: 24 * s
                            color: root.surfaceHover
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                source: "icons/power.svg"
                                anchors.centerIn: parent
                                width: 22 * s
                                height: 22 * s
                                sourceSize.width: 44 * s
                                sourceSize.height: 44 * s
                                opacity: powerMouse.containsMouse ? 1 : 0.82
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2 * s

                            Text {
                                text: "POWER"
                                font.family: root.sansFont
                                font.pixelSize: 12 * s
                                font.bold: true
                                color: powerMouse.containsMouse ? root.softBlue : root.foreground
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Text {
                                text: "SHUT DOWN"
                                font.family: root.sansFont
                                font.pixelSize: 9 * s
                                color: powerMouse.containsMouse ? root.foreground : root.muted
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }

                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!root.isQuickshell) sddm.powerOff();
                    }
                }

                // Session
                Rectangle {
                    id: sessionTile
                    width: 180 * s; height: 76 * s; radius: 38 * s
                    color: sessionMouse.pressed ? root.surfacePressed : (sessionMouse.containsMouse ? root.surfaceHover : root.surface)
                    scale: sessionMouse.pressed ? 0.95 : (sessionMouse.containsMouse ? 1.03 : 1.0)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16 * s
                        anchors.rightMargin: 16 * s
                        spacing: 12 * s

                        Rectangle {
                            width: 48 * s; height: 48 * s; radius: 24 * s
                            color: root.surfaceHover
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                source: "icons/session.svg"
                                anchors.centerIn: parent
                                width: 22 * s
                                height: 22 * s
                                sourceSize.width: 44 * s
                                sourceSize.height: 44 * s
                                opacity: sessionMouse.containsMouse ? 1 : 0.82
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2 * s

                            Text {
                                text: "SESSION"
                                font.family: root.sansFont
                                font.pixelSize: 12 * s
                                font.bold: true
                                color: sessionMouse.containsMouse ? root.softBlue : root.foreground
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Text {
                                text: ((sessionHelper.currentItem && sessionHelper.currentItem.sName) ? sessionHelper.currentItem.sName : "PLASMA").toUpperCase()
                                font.family: root.sansFont
                                font.pixelSize: 9 * s
                                color: sessionMouse.containsMouse ? root.foreground : root.muted
                                Behavior on color { ColorAnimation { duration: 150 } }
                                elide: Text.ElideRight
                                width: 90 * s
                            }
                        }
                    }

                    MouseArea {
                        id: sessionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.isQuickshell && typeof sessionModel !== "undefined" && sessionModel.rowCount() > 0) {
                                root.sessionIndex = (root.sessionIndex + 1) % sessionModel.rowCount();
                            }
                        }
                    }
                }

                // Reboot
                Rectangle {
                    id: rebootTile
                    width: 180 * s; height: 76 * s; radius: 38 * s
                    color: rebootMouse.pressed ? root.surfacePressed : (rebootMouse.containsMouse ? root.surfaceHover : root.surface)
                    scale: rebootMouse.pressed ? 0.95 : (rebootMouse.containsMouse ? 1.03 : 1.0)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16 * s
                        anchors.rightMargin: 16 * s
                        spacing: 12 * s

                        Rectangle {
                            width: 48 * s; height: 48 * s; radius: 24 * s
                            color: root.surfaceHover
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                source: "icons/reboot.svg"
                                anchors.centerIn: parent
                                width: 22 * s
                                height: 22 * s
                                sourceSize.width: 44 * s
                                sourceSize.height: 44 * s
                                opacity: rebootMouse.containsMouse ? 1 : 0.82
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2 * s

                            Text {
                                text: "REBOOT"
                                font.family: root.sansFont
                                font.pixelSize: 12 * s
                                font.bold: true
                                color: rebootMouse.containsMouse ? root.softBlue : root.foreground
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Text {
                                text: "RESTART"
                                font.family: root.sansFont
                                font.pixelSize: 9 * s
                                color: rebootMouse.containsMouse ? root.foreground : root.muted
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }

                    MouseArea {
                        id: rebootMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!root.isQuickshell) sddm.reboot();
                    }
                }

                // Sleep
                Rectangle {
                    id: suspendTile
                    width: 180 * s; height: 76 * s; radius: 38 * s
                    color: suspendMouse.pressed ? root.surfacePressed : (suspendMouse.containsMouse ? root.surfaceHover : root.surface)
                    scale: suspendMouse.pressed ? 0.95 : (suspendMouse.containsMouse ? 1.03 : 1.0)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16 * s
                        anchors.rightMargin: 16 * s
                        spacing: 12 * s

                        Rectangle {
                            width: 48 * s; height: 48 * s; radius: 24 * s
                            color: root.surfaceHover
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                source: "icons/sleep.svg"
                                anchors.centerIn: parent
                                width: 22 * s
                                height: 22 * s
                                sourceSize.width: 44 * s
                                sourceSize.height: 44 * s
                                opacity: suspendMouse.containsMouse ? 1 : 0.82
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2 * s

                            Text {
                                text: "SLEEP"
                                font.family: root.sansFont
                                font.pixelSize: 12 * s
                                font.bold: true
                                color: suspendMouse.containsMouse ? root.softBlue : root.foreground
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Text {
                                text: "SUSPEND"
                                font.family: root.sansFont
                                font.pixelSize: 9 * s
                                color: suspendMouse.containsMouse ? root.foreground : root.muted
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }

                    MouseArea {
                        id: suspendMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!root.isQuickshell) sddm.suspend();
                    }
                }
            }

            // Login Card
            Rectangle {
                id: notificationCard
                width: 376 * s
                height: 180 * s
                radius: 32 * s
                color: root.surface
                transform: Translate { id: shakeTranslate }

                Column {
                    anchors.fill: parent
                    anchors.margins: 20 * s
                    spacing: 12 * s

                    // Header
                    Row {
                        width: parent.width
                        spacing: 8 * s

                        Item {
                            width: 12 * s
                            height: 12 * s
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                id: lockIcon
                                source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><rect x='3' y='11' width='18' height='11' rx='2' ry='2'></rect><path d='M7 11V7a5 5 0 0 1 10 0v4'></path></svg>"
                                anchors.fill: parent
                                sourceSize.width: 24 * s
                                sourceSize.height: 24 * s
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: lockIcon
                                source: lockIcon
                                color: root.muted
                            }
                        }
                        Text {
                            text: "SYSTEM UI"
                            font.family: root.sansFont
                            font.pixelSize: 10 * s
                            font.bold: true
                            font.letterSpacing: 1 * s
                            color: root.muted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "•  now"
                            font.family: root.sansFont
                            font.pixelSize: 10 * s
                            color: root.muted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Password Box
                    Rectangle {
                        width: parent.width
                        height: 52 * s
                        radius: 26 * s
                        color: root.surfaceRaised
                        border.color: root.errorMessage !== "" ? root.errorColor : (pwd.activeFocus ? root.primary : "transparent")
                        border.width: pwd.activeFocus ? 2 * s : 0
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextInput {
                            id: pwd
                            anchors.fill: parent
                            anchors.leftMargin: 20 * s
                            anchors.rightMargin: 20 * s
                            font.family: root.sansFont
                            font.pixelSize: 18 * s
                            font.letterSpacing: 6 * s
                            color: root.foreground
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true

                            cursorVisible: false
                            cursorDelegate: Item { width: 0; height: 0 }
                            selectionColor: root.selection

                            property bool wasClicked: false
                            onActiveFocusChanged: if (!activeFocus && text.length === 0) wasClicked = false

                            Text {
                                anchors.centerIn: parent
                                text: root.errorMessage !== "" ? root.errorMessage : "PASSWORD REQUIRED"
                                font.family: root.sansFont
                                font.pixelSize: 11 * s
                                font.bold: true
                                font.letterSpacing: 1.5 * s
                                color: root.errorMessage !== "" ? root.errorColor : root.muted
                                opacity: pwd.text === "" && (!pwd.activeFocus || (!pwd.wasClicked && pwd.text.length === 0)) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }

                            // Cursor
                            Rectangle {
                                id: customCursor
                                width: 2 * s
                                height: 18 * s
                                color: root.foreground
                                anchors.verticalCenter: parent.verticalCenter
                                x: pwd.cursorRectangle.x
                                visible: pwd.activeFocus && (pwd.text.length > 0 || pwd.wasClicked) && root.errorMessage === ""

                                SequentialAnimation {
                                    loops: Animation.Infinite
                                    running: customCursor.visible
                                    NumberAnimation { target: customCursor; property: "opacity"; from: 1; to: 0; duration: 400; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: customCursor; property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.InOutQuad }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: {
                                    pwd.wasClicked = true;
                                    pwd.forceActiveFocus();
                                }
                            }

                            onAccepted: {
                                if (!root.isQuickshell && pwd.text !== "") {
                                    let currentUser = userHelper.currentItem ? userHelper.currentItem.uLogin : userModel.lastUser;
                                    sddm.login(currentUser, pwd.text, root.sessionIndex);
                                }
                            }
                        }
                    }

                    // Bottom Row
                    Row {
                        width: parent.width
                        spacing: 12 * s

                        // User Switch
                        Rectangle {
                            width: userText.implicitWidth + 32 * s
                            height: 38 * s
                            radius: 19 * s
                            color: userMouse.pressed ? root.surfacePressed : (userMouse.containsMouse ? root.surfaceHover : root.surfaceRaised)
                            scale: userMouse.pressed ? 0.95 : (userMouse.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                            Text {
                                id: userText
                                anchors.centerIn: parent
                                text: ((userHelper.currentItem && userHelper.currentItem.uName) ? userHelper.currentItem.uName : (userModel.lastUser || "USER")).toUpperCase()
                                font.family: root.sansFont
                                font.pixelSize: 10 * s
                                font.bold: true
                                font.letterSpacing: 1 * s
                                color: root.foreground
                            }

                            MouseArea {
                                id: userMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.isQuickshell && typeof userModel !== "undefined" && userModel.rowCount() > 0) {
                                        root.userIndex = (root.userIndex + 1) % userModel.rowCount();
                                    }
                                }
                            }
                        }

                        // Unlock Pill
                        Item {
                            width: parent.width - (userText.implicitWidth + 32 * s) - 12 * s
                            height: 38 * s

                            Rectangle {
                                anchors.right: parent.right
                                width: parent.width
                                height: 38 * s
                                radius: 19 * s
                                color: loginMouse.pressed ? root.primaryButtonPressed : (loginMouse.containsMouse ? root.primaryButtonHover : root.primaryButton)
                                scale: loginMouse.pressed ? 0.95 : (loginMouse.containsMouse ? 1.02 : 1.0)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6 * s

                                    Text {
                                        text: "UNLOCK"
                                        font.family: root.sansFont
                                        font.pixelSize: 10 * s
                                        font.bold: true
                                        font.letterSpacing: 1.5 * s
                                        color: root.softBlue
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "➔"
                                        font.family: root.sansFont
                                        font.pixelSize: 11 * s
                                        color: root.softBlue
                                        anchors.verticalCenter: parent.verticalCenter
                                        transform: Translate {
                                            x: loginMouse.containsMouse ? 3 * s : 0
                                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: loginMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pwd.accepted()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
