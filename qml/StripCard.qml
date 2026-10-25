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

    color: app.panel
    border.color: app.line

    function set(mutate) {
        app.change(c => mutate(c.strips[card.index]));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            spacing: 8
            Text {
                text: "0" + (card.index + 1)
                color: card.app.dim
                font.family: card.app.mono
                font.pixelSize: 11
            }
            Text {
                Layout.fillWidth: true
                text: card.strip.label.toUpperCase()
                color: card.app.ink
                font.family: card.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 2
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
            text: "LISTEN ON"
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
            text: "SEND TO MIC"
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
            text: card.strip.mute ? "MUTED" : "MUTE"
            checked: card.strip.mute
            onColor: card.app.danger
            onToggled: card.set(s => s.mute = !s.mute)
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: card.app.line }

        // Fixed height so every strip's fader lines up, with or without voice tools.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 170

            ColumnLayout {
                visible: !card.strip.virtual_input
                anchors.fill: parent
                spacing: 8

                RowLayout {
                    spacing: 10
                    Chip {
                        app: card.app
                        text: "GATE"
                        checked: card.strip.gate_on
                        tip: "Silences the mic between words"
                        onToggled: card.set(s => s.gate_on = !s.gate_on)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: card.app
                        label: "Threshold"
                        enabled: card.strip.gate_on
                        from: -80
                        to: 0
                        resetValue: -45
                        value: card.strip.gate_threshold_db
                        onMoved: v => card.set(s => s.gate_threshold_db = v)
                    }
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
            }

            Text {
                // Apps carries everything, voice chat included, so warn before it goes to a mic.
                visible: card.strip.virtual_input && card.isApps && card.sendsToMic
                anchors.fill: parent
                text: "Voice chat playing here also goes into the mic, so people may hear themselves."
                color: card.app.warning
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
