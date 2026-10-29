import QtQuick
import QtQuick.Layouts

// One input: where the sound comes from, how loud it is, where it goes, and voice shaping.
Rectangle {
    id: card
    required property var app
    required property int index
    readonly property var strip: app.cfg.strips[index]
    readonly property var peaks: app.meters.strips && app.meters.strips[index] ? app.meters.strips[index] : [0, 0]
    readonly property bool sendsToMic: strip.routes[3] || strip.routes[4]
    readonly property bool isApps: strip.virtual_input && strip.label === "Apps"
    // Voice effects live on the back of mic strips. The front only shows whether any of them is on.
    readonly property bool effectsOn: !strip.virtual_input
        && (strip.gate_on || strip.bass_db !== 0 || strip.brightness_db !== 0 || strip.pitch_semitones !== 0)
    // Virtual strips (Apps, Media) flip to the list of programs using them; the dot says someone is.
    readonly property var playing: strip.virtual_input ? app.streams.filter(s => s.target === (isApps ? "apps" : "media")) : []
    readonly property bool dotOn: strip.virtual_input ? playing.length > 0 : effectsOn
    property real turn: Qt.application.arguments.indexOf("--flip") >= 0 ? 180 : 0   // degrees; --flip is a dev aid for screenshots
    readonly property bool showingBack: turn >= 90
    readonly property int flipBelow: 70   // room under the flip/Done button, for the hint text on the front
    Behavior on turn { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
    transform: Rotation {
        origin.x: card.width / 2
        origin.y: card.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: card.turn < 90 ? card.turn : card.turn - 180
    }

    color: app.diamond ? "transparent" : app.panel
    radius: app.rCard
    border.color: app.diamond ? "transparent" : app.edge

    CutFrame { visible: card.app.diamond; anchors.fill: parent; cut: card.app.cut; fill: card.app.panel; stroke: card.app.frameDim }

    function set(mutate) {
        app.change(c => mutate(c.strips[card.index]));
    }

    ColumnLayout {
        id: front
        visible: !card.showingBack
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 18
                radius: card.app.diamond ? 0 : 9
                color: card.app.soft ? card.app.tonal : "transparent"
                border.color: card.app.edge
                Text {
                    anchors.centerIn: parent
                    text: "0" + (card.index + 1)
                    color: card.app.dim
                    font.family: card.app.mono
                    font.pixelSize: 11
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.app.t(card.strip.label)
                color: card.app.ink
                font.family: card.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: card.app.soft || card.app.diamond ? 0.5 : 2
                elide: Text.ElideRight
            }
        }

        DevicePicker {
            visible: !card.strip.virtual_input
            Layout.fillWidth: true
            app: card.app
            devices: card.app.devices.sources
            current: card.strip.source
            onPicked: name => card.set(s => s.source = name)
        }
        Item {
            visible: card.strip.virtual_input
            Layout.fillWidth: true
            Layout.preferredHeight: 30
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            Item { Layout.fillWidth: true }
            Fader {
                app: card.app
                Layout.fillHeight: true
                value: card.strip.gain_db
                onMoved: v => card.set(s => s.gain_db = v)
            }
            LevelMeter {
                app: card.app
                Layout.fillHeight: true
                peaks: card.peaks
            }
            Item { Layout.fillWidth: true }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: card.app.db(card.strip.gain_db)
            color: card.app.ink
            font.family: card.app.mono
            font.pixelSize: 12
        }

        Text {
            text: card.app.t("Listen on")
            color: card.app.dim
            font.family: card.app.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }
        RowLayout {
            spacing: 6
            Repeater {
                model: 3
                Chip {
                    required property int index
                    Layout.fillWidth: true
                    app: card.app
                    text: "A" + (index + 1)
                    checked: card.strip.routes[index]
                    tip: card.app.busTip(index)
                    onToggled: card.set(s => s.routes[index] = !s.routes[index])
                }
            }
        }

        Text {
            text: card.app.t("Send to mic")
            color: card.app.dim
            font.family: card.app.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }
        RowLayout {
            spacing: 6
            Repeater {
                model: 2
                Chip {
                    required property int index
                    readonly property int bus: index + 3
                    Layout.fillWidth: true
                    app: card.app
                    text: "B" + (index + 1)
                    checked: card.strip.routes[bus]
                    tip: card.app.busTip(bus)
                    onToggled: card.set(s => s.routes[bus] = !s.routes[bus])
                }
            }
        }

        Chip {
            Layout.fillWidth: true
            app: card.app
            text: card.strip.mute ? (card.app.t("Muted")) : (card.app.t("Mute"))
            checked: card.strip.mute
            onColor: card.app.danger
            onToggled: card.set(s => s.mute = !s.mute)
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: card.app.soft ? "transparent" : card.app.line }

        // Fixed height so every strip's fader lines up, with or without voice tools.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 170

            // One button to the back of the strip (voice tools, or the programs using it), with a dot when
            // something is on / playing.
            ColumnLayout {
                anchors.bottom: parent.bottom
                width: parent.width
                height: card.flipBelow
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: card.strip.virtual_input ? (card.isApps ? "Programs on the system output" : "Programs you sent here") : "Gate · Bass · Brightness · Pitch"
                    color: card.app.dim
                    font.pixelSize: 11
                }
                Text {
                    // Apps carries everything, voice chat included, so warn before it goes to a mic.
                    visible: card.strip.virtual_input && card.isApps && card.sendsToMic
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    text: "Voice chat playing here also goes into the mic, so people may hear themselves."
                    color: card.app.warning
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Rectangle {
        // One button for both faces, pinned to the same spot so flipping back is a double-click away.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14 + card.flipBelow
        width: 130
        height: 36
        radius: card.app.soft ? height / 2 : 0
        CutFrame { visible: card.app.diamond; anchors.fill: parent; cut: card.app.cut
            fill: flipMouse.pressed ? card.app.select : (flipMouse.containsMouse ? Qt.alpha(card.app.accent, 0.14) : "transparent")
            stroke: flipMouse.containsMouse ? card.app.accent : card.app.frameDim }
        color: card.app.diamond ? "transparent" : flipMouse.pressed ? card.app.onFill : flipMouse.containsMouse ? (card.app.soft ? Qt.tint(card.app.tonal, Qt.alpha(card.app.accent, 0.18)) : card.app.hover) : card.app.soft ? card.app.tonal : "transparent"
        border.color: card.app.soft || card.app.diamond ? "transparent" : flipMouse.containsMouse ? card.app.accent : card.app.line
        Rectangle {
            visible: card.dotOn && !card.showingBack
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: card.app.accent
        }
        Text {
            id: flipLabel
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: card.dotOn && !card.showingBack ? 6 : 0
            text: card.showingBack ? "Done  ⟲" : (card.strip.virtual_input ? "Apps" : "Voice") + "  ⟲"
            color: card.app.ink
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: flipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.turn = card.showingBack ? 0 : 180
        }
    }

    // Back face of mic strips: the voice tools.
    ColumnLayout {
        id: back
        visible: card.showingBack && !card.strip.virtual_input
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 14 + card.flipBelow + 36 + 12
        spacing: 12

        RowLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: card.app.t(card.strip.label + " · voice")
                color: card.app.ink
                font.family: card.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: card.app.soft || card.app.diamond ? 0.3 : 2
                elide: Text.ElideRight
            }
        }

        Chip {
            Layout.fillWidth: true
            app: card.app
            text: card.app.t("Gate")
            checked: card.strip.gate_on
            tip: "Silences the mic between words"
            onToggled: card.set(s => s.gate_on = !s.gate_on)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Gate threshold"
            enabled: card.strip.gate_on
            from: -80
            to: 0
            resetValue: -45
            value: card.strip.gate_threshold_db
            onMoved: v => card.set(s => s.gate_threshold_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Bass"
            value: card.strip.bass_db
            onMoved: v => card.set(s => s.bass_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Brightness"
            value: card.strip.brightness_db
            onMoved: v => card.set(s => s.brightness_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Pitch"
            format: card.app.semitones
            value: card.strip.pitch_semitones
            onMoved: v => card.set(s => s.pitch_semitones = v)
        }
        Text {
            Layout.fillWidth: true
            visible: card.strip.pitch_semitones !== 0
            text: "Pitch adds about 80 ms of delay while it is on."
            color: card.app.warning
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
        Item { Layout.fillHeight: true }
        Text {
            Layout.fillWidth: true
            text: "Double-click a slider to reset it."
            color: card.app.dim
            font.pixelSize: 11
        }
    }

    // Back face of Apps / Media: the programs using the strip, each with its own mute.
    ColumnLayout {
        id: appsBack
        visible: card.showingBack && card.strip.virtual_input
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 14 + card.flipBelow + 36 + 12
        spacing: 12

        RowLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: card.app.t(card.strip.label)
                color: card.app.ink
                font.family: card.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: card.app.soft || card.app.diamond ? 0.3 : 2
                elide: Text.ElideRight
            }
        }
        StreamList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            app: card.app
            target: card.isApps ? "apps" : "media"
            emptyText: card.isApps ? "Nothing playing. Programs that use the system output show up here." : "Nothing playing. Send a program here from Plasma's volume menu."
        }
    }
}
