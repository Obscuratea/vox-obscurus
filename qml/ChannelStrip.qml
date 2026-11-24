import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// One channel as a vertical strip: an input (hardware or virtual) or an output (A or B).
// Full strips also carry the quick switches and the routing buttons; condensed strips and outputs keep to
// the fader, meter and mute, and the rest is in the inspector (click the name).
Card {
    id: strip
    property string kind: "strip"       // "strip" (an input) or "bus" (an output)
    property int slot: 0                // index into cfg.strips or cfg.buses
    property bool condensed: false

    readonly property bool isBus: kind === "bus"
    readonly property var ch: (isBus ? app.cfg.buses[slot] : app.cfg.strips[slot]) || app.blank
    readonly property bool virtualIn: !isBus && !!ch.virtual_input
    readonly property bool full: !condensed && !isBus
    readonly property bool stacked: !full
    readonly property bool tight: width < 84
    corner: Math.min(app.rCard, 16)
    readonly property var peaks: { const m = isBus ? app.meters.buses : app.meters.strips; return m && m[slot] ? m[slot] : [0, 0]; }
    readonly property string streamName: app.slug(ch.label)
    readonly property int playing: virtualIn ? app.streams.filter(s => s.target === streamName).length : 0
    readonly property bool echo: virtualIn && ch.label === "Apps" && app.bIdx.some(b => ch.routes[b])

    selected: app.inspShown && app.sel.kind === kind && app.sel.index === slot

    function set(mutate) {
        app.change(c => mutate(strip.isBus ? c.buses[strip.slot] : c.strips[strip.slot]));
    }

    // A click anywhere on the strip that isn't on one of its controls selects it.
    MouseArea {
        anchors.fill: parent
        onClicked: strip.app.selectChannel(strip.kind, strip.slot, true)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: strip.tight ? 6 : strip.stacked ? 10 : 12
        spacing: 8

        // Tag and name: click to open the inspector on this channel.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: strip.stacked ? 42 : 20
            Tag {
                id: tag
                app: strip.app
                text: strip.app.tagOf(strip.kind, strip.slot)
                x: strip.stacked ? (parent.width - width) / 2 : 0
            }
            Text {
                x: strip.stacked ? 0 : tag.width + 8
                y: strip.stacked ? 25 : 1
                width: parent.width - x - (warn.visible ? 18 : 0)
                horizontalAlignment: strip.stacked ? Text.AlignHCenter : Text.AlignLeft
                text: strip.app.nameOf(strip.kind, strip.slot)
                color: strip.app.ink
                font.family: strip.app.display
                font.pixelSize: strip.stacked ? 12 : 14
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            MouseArea {
                id: headMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: strip.app.selectChannel(strip.kind, strip.slot, true)
            }
            // Apps carries everything, voice chat included, so warn while it goes to a mic.
            Text {
                id: warn
                visible: strip.echo && !strip.stacked
                anchors.right: parent.right
                y: 1
                text: "⚠"
                color: strip.app.warning
                font.pixelSize: 13
                HoverHandler { id: echoHover }
                ToolTip.visible: echoHover.hovered
                ToolTip.text: "Voice chat playing through Apps also goes into this mic, so people may hear themselves"
            }
            ToolTip.visible: headMouse.containsMouse
            ToolTip.delay: 600
            ToolTip.text: strip.app.nameOf(strip.kind, strip.slot) + " · " + strip.app.subOf(strip.kind, strip.slot)
        }
        Text {
            visible: strip.full
            Layout.fillWidth: true
            text: strip.app.subOf(strip.kind, strip.slot)
            color: strip.app.dim
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 80
            spacing: strip.tight ? 4 : 10
            Item { Layout.fillWidth: true }
            Fader {
                app: strip.app
                Layout.fillHeight: true
                value: strip.ch.gain_db || 0
                onMoved: v => strip.set(s => s.gain_db = v)
            }
            LevelMeter {
                app: strip.app
                Layout.fillHeight: true
                peaks: strip.peaks
            }
            Item { Layout.fillWidth: true }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: strip.app.db(strip.ch.gain_db || 0)
            color: strip.ch.mute ? strip.app.dim : strip.app.ink
            font.family: strip.app.mono
            font.pixelSize: 12
        }

        // Quick switches on a full input strip.
        RowLayout {
            visible: strip.full
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 6
            Chip {
                visible: !strip.virtualIn
                Layout.fillWidth: true; Layout.preferredWidth: 20
                implicitHeight: 24
                app: strip.app
                text: strip.app.t("Gate")
                checked: !!strip.ch.gate_on
                tip: "Silences the mic between words"
                onToggled: strip.set(s => s.gate_on = !s.gate_on)
            }
            Chip {
                visible: !strip.virtualIn
                Layout.fillWidth: true; Layout.preferredWidth: 20
                implicitHeight: 24
                app: strip.app
                text: strip.app.t("Duck")
                checked: !!strip.ch.duck_on
                tip: "While you are talking, the virtual inputs dip so people hear you over them"
                onToggled: strip.set(s => s.duck_on = !s.duck_on)
            }
            Rectangle {
                visible: strip.virtualIn
                Layout.alignment: Qt.AlignVCenter
                width: 8; height: 8; radius: 4
                color: strip.playing > 0 ? strip.app.accent : strip.app.line
            }
            Text {
                visible: strip.virtualIn
                Layout.fillWidth: true
                text: strip.playing === 0 ? "Nothing playing" : strip.playing + " playing"
                color: strip.app.dim
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        // Where a full input strip goes: A outputs, then B mics.
        Repeater {
            model: strip.full ? [strip.app.aIdx, strip.app.bIdx] : []
            GridLayout {
                id: sends
                required property var modelData
                Layout.fillWidth: true
                columns: Math.min(Math.max(1, modelData.length), strip.width < 190 ? 3 : 5)
                columnSpacing: 6
                rowSpacing: 6
                Repeater {
                    model: sends.modelData
                    Chip {
                        required property int modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 20
                        implicitHeight: 26
                        app: strip.app
                        text: strip.app.tagOf("bus", modelData)
                        checked: !!strip.ch.routes[modelData]
                        tip: strip.app.busTip(modelData)
                        onToggled: strip.set(s => s.routes[modelData] = !s.routes[modelData])
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: strip.tight ? 1 : 2
            columnSpacing: 6
            rowSpacing: 5
            Chip {
                Layout.fillWidth: true; Layout.preferredWidth: 20
                implicitHeight: 28
                app: strip.app
                text: "M"
                checked: !!strip.ch.mute
                onColor: strip.app.danger
                tip: strip.ch.mute ? "Muted" : "Mute"
                onToggled: strip.set(s => s.mute = !s.mute)
            }
            Chip {
                visible: !strip.isBus
                Layout.fillWidth: true; Layout.preferredWidth: 20
                implicitHeight: 28
                app: strip.app
                text: "S"
                checked: !!strip.ch.solo
                onColor: strip.app.warning
                tip: "Solo: listen to just this strip on the A outputs. The B mics are not affected."
                onToggled: strip.set(s => s.solo = !s.solo)
            }
            Chip {
                visible: strip.isBus
                Layout.fillWidth: true; Layout.preferredWidth: 20
                implicitHeight: 28
                app: strip.app
                text: "EQ"
                checked: !!strip.ch.eq_on
                tip: "Parametric EQ on this output"
                onToggled: strip.app.openEq("bus", strip.slot)
            }
        }
    }

    // Drop a program here (dragged from a program list in the inspector) to send it to this strip.
    DropArea {
        id: drops
        anchors.fill: parent
        enabled: strip.virtualIn
        keys: ["vox-stream"]
        onDropped: drop => {
            const s = drop.source.stream;
            if (s && s.target !== strip.streamName)
                strip.app.moveStream(s.id, strip.streamName, strip.app.nameOf("strip", strip.slot));
        }
    }
    Rectangle {
        visible: drops.enabled && drops.containsDrag
        anchors.fill: parent
        radius: strip.radius
        color: Qt.alpha(strip.app.accent, 0.12)
        border.width: 2
        border.color: strip.app.accent
    }
}
