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

    // The theme picks the look. "Follow system" takes colours from the Plasma colour scheme (dark/light and
    // accent); MatOS gets the soft look (rounded, tonal, no outlines, gradient meters), CachyOS Diamond gets
    // 1px violet outlines with 3px cut corners in lowercase mono (btop), any other scheme the sharp one.
    // The other themes bring their own colours. A --theme <id> argument overrides it for screenshots.
    SystemPalette { id: pal; colorGroup: SystemPalette.Active }
    Themes { id: themes }
    readonly property int themeArg: Qt.application.arguments.indexOf("--theme")
    readonly property string themeWanted: themeArg >= 0 ? Qt.application.arguments[themeArg + 1] : (cfg.theme || "system")
    readonly property var theme: themes.find(themeWanted) || themes.find("system")
    readonly property bool ownColors: theme.style !== "auto"
    readonly property string scheme: mixer.colorScheme()
    readonly property string style: ownColors ? theme.style : scheme.indexOf("MatOS") === 0 ? "soft" : scheme.indexOf("CachyOSDiamond") === 0 ? "diamond" : "sharp"
    readonly property bool soft: style === "soft"
    readonly property bool diamond: style === "diamond"
    readonly property color baseWindow: ownColors ? theme.window : pal.window
    readonly property color baseText: ownColors ? theme.text : pal.windowText
    readonly property color baseHighlight: ownColors ? theme.highlight : pal.highlight
    readonly property color baseHighlightedText: ownColors ? theme.highlightedText : pal.highlightedText
    readonly property var themeList: themes.list
    readonly property color systemWindow: pal.window
    readonly property color systemText: pal.windowText
    readonly property color systemAccent: (scheme.indexOf("MatOS") === 0 || scheme.indexOf("CachyOSDiamond") === 0) && schemeAccent !== "" ? schemeAccent : pal.highlight
    readonly property color frame: "#8e7adf"
    readonly property color frameDim: "#3b2e63"
    readonly property color ember: "#feb963"
    readonly property int cut: 3
    // Label casing: sharp = UPPER, MatOS = as written, Diamond = lower.
    function t(s) { return soft ? s : diamond ? s.toLowerCase() : s.toUpperCase(); }
    readonly property color bg: baseWindow
    readonly property color panel: Qt.tint(baseWindow, Qt.alpha(baseText, soft ? 0.055 : 0.035))
    readonly property color tonal: Qt.tint(baseWindow, Qt.alpha(baseText, 0.11))
    readonly property color edge: soft ? "transparent" : line
    readonly property int rCard: soft ? 20 : 0
    readonly property int rBox: soft ? 14 : 0
    readonly property int rChip: soft ? 14 : diamond ? 0 : 4
    readonly property color ink: baseText
    readonly property color dim: Qt.alpha(baseText, 0.55)
    readonly property color line: diamond ? frameDim : Qt.alpha(baseText, 0.15)
    readonly property color hover: Qt.alpha(baseText, 0.06)
    // MatOS: the accent is the scheme's focus colour (its selection colour is the deeper container tone).
    readonly property string schemeAccent: mixer.schemeAccent()
    readonly property color accent: ownColors ? theme.accent : (soft || diamond) && schemeAccent !== "" ? schemeAccent : pal.highlight
    readonly property color accentEnd: soft ? Qt.hsla(accent.hslHue + 0.045, accent.hslSaturation, accent.hslLightness, 1) : accent
    readonly property color onFill: soft ? baseHighlight : accent
    readonly property color select: diamond ? "#4b3a85" : baseHighlight
    readonly property color accentInk: baseHighlightedText
    readonly property color danger: "#e5484d"
    readonly property color warning: "#f5a524"
    readonly property string mono: soft ? "Roboto Flex" : "Geist Mono"
    readonly property string display: soft ? "Roboto Flex" : diamond ? "Geist Mono" : "Archivo"

    Mixer { id: mixer }

    property var cfg: JSON.parse(mixer.settings())
    property var devices: ({ sources: [], sinks: [] })
    property var meters: ({ strips: [], buses: [] })
    property string devicesJson: ""
    property var streams: []
    property string streamsJson: "[]"
    property string status: Qt.application.arguments.indexOf("--status") >= 0 ? "System output is now Vox Obscurus Apps." : ""

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

    // "01   INPUTS" (sharp), "Inputs" (MatOS), "01 inputs" with an amber first letter (Diamond; rich text).
    function sectionLabel(num, name) {
        if (soft) return name;
        if (!diamond) return num + "   " + name.toUpperCase();
        const n = name.toLowerCase();
        return num + "  <font color=\"" + ember + "\">" + n[0] + "</font>" + n.slice(1);
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

    function muteStream(id, muted) {
        mixer.muteStream(id, muted);
    }

    // Both virtual mics at once, for a quick "nobody can hear me" button.
    readonly property bool micsMuted: cfg.buses[3].mute && cfg.buses[4].mute
    function muteMics(muted) {
        change(c => { c.buses[3].mute = muted; c.buses[4].mute = muted; });
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
    Timer {
        // Programs come and go quickly (a mute button should show its state at once), so poll faster.
        interval: 300
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const json = mixer.streams();
            if (json !== win.streamsJson) {
                win.streamsJson = json;
                win.streams = JSON.parse(json);
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
                Layout.fillHeight: true
                spacing: 24

                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 12

                    Text {
                        text: win.sectionLabel("01", "Inputs")
                        color: win.dim
                        textFormat: Text.StyledText
                        font.family: win.mono
                        font.pixelSize: win.soft ? 12 : 11
                        font.weight: win.soft ? Font.Medium : Font.Normal
                        font.letterSpacing: win.soft || win.diamond ? 0.3 : 2
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

                Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: win.soft ? "transparent" : win.line }

                // The right-hand side flips to the settings (gear button, bottom right) and back.
                Item {
                    id: rightSide
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    property real turn: Qt.application.arguments.indexOf("--settings") >= 0 ? 180 : 0   // --settings is a dev aid for screenshots
                    readonly property bool showingBack: turn >= 90
                    Behavior on turn { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
                    transform: Rotation {
                        origin.x: rightSide.width / 2
                        origin.y: rightSide.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: rightSide.turn < 90 ? rightSide.turn : rightSide.turn - 180
                    }

                    ColumnLayout {
                        visible: !rightSide.showingBack
                        anchors.fill: parent
                        spacing: 10

                        Text {
                            text: win.sectionLabel("02", "Listen  ·  A")
                            color: win.dim
                            textFormat: Text.StyledText
                            font.family: win.mono
                            font.pixelSize: win.soft ? 12 : 11
                            font.weight: win.soft ? Font.Medium : Font.Normal
                            font.letterSpacing: win.soft || win.diamond ? 0.3 : 2
                        }
                        Repeater {
                            model: 3
                            BusRow { app: win; Layout.fillWidth: true }
                        }

                        Item { Layout.preferredHeight: 8 }

                        Text {
                            text: win.sectionLabel("03", "Send as mic  ·  B")
                            color: win.dim
                            textFormat: Text.StyledText
                            font.family: win.mono
                            font.pixelSize: win.soft ? 12 : 11
                            font.weight: win.soft ? Font.Medium : Font.Normal
                            font.letterSpacing: win.soft || win.diamond ? 0.3 : 2
                        }
                        Repeater {
                            model: 2
                            BusRow { app: win; offset: 3; Layout.fillWidth: true }
                        }

                        Item { Layout.preferredHeight: 8 }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 110
                            color: win.diamond ? "transparent" : win.panel
                            radius: win.rCard
                            border.color: win.diamond ? "transparent" : win.edge

                            CutFrame { visible: win.diamond; anchors.fill: parent; cut: win.cut; fill: win.panel; stroke: win.frameDim }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: win.t("Used by")
                                        color: win.dim
                                        font.family: win.mono
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                    }
                                    Chip {
                                        app: win
                                        text: win.micsMuted ? win.t("Mics muted") : win.t("Mute all mics")
                                        checked: win.micsMuted
                                        onColor: win.danger
                                        tip: "Mutes B1 and B2 together, so nobody on a call or stream hears you"
                                        onToggled: win.muteMics(!win.micsMuted)
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 16
                                    Repeater {
                                        model: ["b1", "b2"]
                                        ColumnLayout {
                                            required property string modelData
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 6
                                            Text {
                                                text: modelData.toUpperCase()
                                                color: win.accent
                                                font.family: win.mono
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                            }
                                            StreamList {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                app: win
                                                target: modelData
                                                mutable: false
                                                emptyText: "Nobody is using this mic"
                                            }
                                        }
                                    }
                                }

                                // Result of the two buttons below, right above them.
                                Rectangle {
                                    visible: win.status !== ""
                                    Layout.alignment: Qt.AlignRight
                                    implicitWidth: statusText.implicitWidth + 24
                                    implicitHeight: 24
                                    radius: win.diamond ? 0 : 12
                                    color: Qt.alpha(win.accent, 0.15)
                                    border.color: win.soft ? "transparent" : win.accent
                                    Text {
                                        id: statusText
                                        anchors.centerIn: parent
                                        text: win.status
                                        color: win.accent
                                        font.pixelSize: 12
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Item { Layout.fillWidth: true }
                                    TextButton {
                                        app: win
                                        text: win.diamond ? "use as system output" : "Use as system output"
                                        tip: "Programs play into the Apps strip, like setting Voicemeeter as your Windows output"
                                        onClicked: win.makeDefault("vox_obscurus_apps", "System output is now Vox Obscurus Apps.")
                                    }
                                    TextButton {
                                        app: win
                                        text: win.diamond ? "use b1 as system mic" : "Use B1 as system mic"
                                        tip: "Programs that use the default microphone hear B1"
                                        onClicked: win.makeDefault("vox_obscurus_b1", "System microphone is now Vox Obscurus B1.")
                                    }
                                    Item { Layout.preferredWidth: 30; Layout.preferredHeight: 32 }   // the gear sits here
                                }
                            }
                        }
                    }

                    SettingsPanel {
                        visible: rightSide.showingBack
                        anchors.fill: parent
                        app: win
                    }

                    // Same spot on both faces, so the gear and "Done" are one click apart.
                    TextButton {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        width: rightSide.showingBack ? implicitWidth : 30
                        app: win
                        text: rightSide.showingBack ? "Done  ⟲" : "⚙"
                        tip: rightSide.showingBack ? "Back to the mixer" : "Settings and themes"
                        onClicked: rightSide.turn = rightSide.showingBack ? 0 : 180
                    }
                }
            }
        }
    }
}
