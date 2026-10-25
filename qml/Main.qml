import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import org.obscura.vox

ApplicationWindow {
    id: win
    width: 1400
    height: 780
    minimumWidth: 1300
    minimumHeight: 720
    visible: true
    title: "Vox Obscurus"
    color: bg

    // Colours follow the Plasma colour scheme, so dark/light and the accent come from the system.
    SystemPalette { id: pal; colorGroup: SystemPalette.Active }
    readonly property color bg: pal.window
    readonly property color panel: Qt.tint(pal.window, Qt.alpha(pal.windowText, 0.035))
    readonly property color ink: pal.windowText
    readonly property color dim: Qt.alpha(pal.windowText, 0.55)
    readonly property color line: Qt.alpha(pal.windowText, 0.15)
    readonly property color hover: Qt.alpha(pal.windowText, 0.06)
    readonly property color accent: pal.highlight
    readonly property color accentInk: pal.highlightedText
    readonly property color danger: "#e5484d"
    readonly property color warning: "#f5a524"
    readonly property string mono: "Geist Mono"
    readonly property string display: "Archivo"

    Mixer { id: mixer }

    property var cfg: JSON.parse(mixer.settings())
    property var devices: ({ sources: [], sinks: [] })
    property var meters: ({ strips: [], buses: [] })
    property string devicesJson: ""
    property string status: ""

    // Every edit goes through here. It edits a copy and swaps it in: a binding that gets back the
    // same object it had before doesn't update, so editing in place left buttons and sliders stale.
    function change(mutate) {
        const next = JSON.parse(JSON.stringify(cfg));
        mutate(next);
        cfg = next;
        mixer.apply(JSON.stringify(next));
        saveTimer.restart();
    }

    function semitones(value) {
        const sign = value > 0 ? "+" : value < 0 ? "−" : "";
        return sign + Math.abs(value).toFixed(1) + " st";
    }

    function db(value) {
        const sign = value > 0 ? "+" : value < 0 ? "−" : "";
        return sign + Math.abs(value).toFixed(1) + " dB";
    }

    function describe(list, name) {
        for (const device of list)
            if (device.name === name)
                return device.description;
        return name;
    }

    function busTip(index) {
        const bus = cfg.buses[index];
        if (bus.virtual_output)
            return "Virtual mic " + bus.label;
        return bus.device !== "" ? bus.label + " · " + describe(devices.sinks, bus.device) : bus.label + " has no device yet";
    }

    function makeDefault(node, done) {
        status = mixer.makeDefault(node) ? done : "Couldn't change the system default.";
        statusTimer.restart();
    }

    Timer { id: saveTimer; interval: 600; onTriggered: mixer.persist() }
    Timer { id: statusTimer; interval: 4000; onTriggered: win.status = "" }
    Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: win.meters = JSON.parse(mixer.meters())
    }
    Timer {
        // Only replace the device lists when they actually change, so open dropdowns stay open.
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const json = mixer.devices();
            if (json !== win.devicesJson) {
                win.devicesJson = json;
                win.devices = JSON.parse(json);
            }
        }
    }
    onClosing: mixer.persist()

    // Developer aid: `vox-obscurus --screenshot out.png` saves the window and quits.
    Timer {
        readonly property int flag: Qt.application.arguments.indexOf("--screenshot")
        interval: 2000
        running: flag >= 0
        onTriggered: page.grabToImage(result => {
            result.saveToFile(Qt.application.arguments[flag + 1]);
            Qt.quit();
        })
    }

    Rectangle {
        id: page
        anchors.fill: parent
        color: win.bg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "VOX OBSCURUS"
                        color: win.ink
                        font.family: win.display
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        font.letterSpacing: 4
                    }
                    Text {
                        text: "Where sound goes to get organized."
                        color: win.dim
                        font.pixelSize: 12
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: win.status !== ""
                    text: win.status
                    color: win.accent
                    font.pixelSize: 12
                }
                TextButton {
                    app: win
                    text: "Use as system output"
                    tip: "Programs play into the Apps strip, like setting Voicemeeter as your Windows output"
                    onClicked: win.makeDefault("vox_obscurus_apps", "System output is now Vox Obscurus Apps.")
                }
                TextButton {
                    app: win
                    text: "Use B1 as system mic"
                    tip: "Programs that use the default microphone hear B1"
                    onClicked: win.makeDefault("vox_obscurus_b1", "System microphone is now Vox Obscurus B1.")
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: win.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24

                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 12

                    Text {
                        text: "01   INPUTS"
                        color: win.dim
                        font.family: win.mono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                    }
                    RowLayout {
                        Layout.fillHeight: true
                        spacing: 12
                        Repeater {
                            model: 4
                            StripCard {
                                app: win
                                Layout.fillHeight: true
                                Layout.preferredWidth: 212
                            }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: win.line }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    Text {
                        text: "02   LISTEN  ·  A"
                        color: win.dim
                        font.family: win.mono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                    }
                    Repeater {
                        model: 3
                        BusRow { app: win; Layout.fillWidth: true }
                    }

                    Item { Layout.preferredHeight: 8 }

                    Text {
                        text: "03   SEND AS MIC  ·  B"
                        color: win.dim
                        font.family: win.mono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                    }
                    Repeater {
                        model: 2
                        BusRow { app: win; offset: 3; Layout.fillWidth: true }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
