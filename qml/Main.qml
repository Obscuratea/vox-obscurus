import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtCore
import org.obscura.vox

ApplicationWindow {
    id: win
    // `--size 860x680` is a dev aid for screenshots.
    function arg(name, fallback) { const i = Qt.application.arguments.indexOf(name); return i >= 0 ? Qt.application.arguments[i + 1] : fallback; }
    width: parseInt(arg("--size", "1400x780").split("x")[0])
    height: parseInt(arg("--size", "1400x780").split("x")[1])
    minimumWidth: 360
    minimumHeight: 480
    visible: true
    title: "Vox Obscurus"
    // Glass themes leave the window see-through; KWin blurs the desktop behind it.
    color: glassy && !bgOn ? "transparent" : bg
    onGlassyChanged: blurTimer.restart()
    Timer { id: blurTimer; interval: 300; running: true; onTriggered: mixer.blurBehind(win.glassy && !win.bgOn) }
    onBgOnChanged: blurTimer.restart()

    // The theme picks the look. "Follow system" wears the default soft look (rounded, gradient fills) in the
    // Plasma colour scheme's colours (window, text, selection and the scheme's focus accent, re-read live).
    // The other themes bring their own colours and style. A --theme <id> argument overrides it for screenshots.
    SystemPalette { id: pal; colorGroup: SystemPalette.Active }
    Themes { id: themes }
    readonly property int themeArg: Qt.application.arguments.indexOf("--theme")
    readonly property string themeWanted: themeArg >= 0 ? Qt.application.arguments[themeArg + 1] : (cfg.theme || "default")
    readonly property var theme: themes.find(themeWanted) || themes.find("default")
    readonly property bool ownColors: theme.style !== "auto"
    // Follow system keeps the default (soft, gradient) look and only borrows the Plasma colours.
    readonly property string style: ownColors ? theme.style : "soft"
    readonly property bool soft: style === "soft"
    readonly property bool diamond: style === "diamond"
    // Follow system: the scheme's window colour with its tint removed, so a purple scheme doesn't paint Vox purple.
    readonly property color neutralWindow: Qt.hsla(0, 0, pal.window.hslLightness, 1)
    readonly property color baseWindow: ownColors ? theme.window : neutralWindow
    readonly property color baseText: ownColors ? theme.text : pal.windowText
    readonly property color baseHighlight: ownColors ? theme.highlight : pal.highlight
    readonly property color baseHighlightedText: ownColors ? theme.highlightedText : pal.highlightedText
    readonly property var themeList: themes.list
    readonly property color systemWindow: neutralWindow
    readonly property color systemText: pal.windowText
    readonly property color systemAccent: schemeAccent !== "" ? schemeAccent : pal.highlight
    readonly property color frame: "#8e7adf"
    readonly property color frameDim: "#3b2e63"
    readonly property color ember: "#feb963"
    readonly property int cut: 3
    // Label casing: sharp = UPPER, MatOS = as written, Diamond = lower.
    function t(s) { return soft ? s : diamond ? s.toLowerCase() : s.toUpperCase(); }
    readonly property color bg: baseWindow
    // Outlined themes (Pure Black) draw boxes and controls as thin outlines on the bare window instead of grey fills.
    readonly property bool outlined: ownColors && !!theme.outline
    readonly property color controlEdge: outlined ? Qt.alpha(baseText, 0.30) : "transparent"
    // Glass themes (Glass): translucent white cards on a gradient window, white hairline edges.
    readonly property bool dark: baseWindow.hslLightness < 0.5
    readonly property bool glassy: ownColors && !!theme.cardFill
    readonly property color panel: outlined ? "transparent" : glassy ? Qt.alpha(theme.cardFill, theme.cardAlpha) : Qt.tint(baseWindow, Qt.alpha(baseText, soft ? 0.055 : 0.035))
    // With a picture behind them the boxes turn translucent (and frosted, see Glass.qml).
    readonly property color panelFill: glassy ? panel : bgOn ? Qt.alpha(Qt.darker(baseWindow, 1.25), 0.52) : panel
    readonly property color tonal: outlined ? "transparent" : glassy ? Qt.alpha(theme.tonalFill, theme.tonalAlpha) : Qt.tint(baseWindow, Qt.alpha(baseText, 0.11))
    readonly property color edge: outlined ? Qt.alpha(baseText, 0.24) : glassy ? Qt.alpha(theme.cardEdge, theme.edgeAlpha) : bgOn ? Qt.alpha(baseText, 0.14) : soft ? "transparent" : line
    readonly property int rCard: soft ? 20 : 0
    readonly property int rBox: soft ? 14 : 0
    readonly property int rChip: soft ? 14 : diamond ? 0 : 4
    readonly property color ink: baseText
    readonly property color dim: Qt.alpha(baseText, 0.55)
    readonly property color line: diamond ? frameDim : Qt.alpha(baseText, 0.15)
    readonly property color hover: Qt.alpha(baseText, 0.06)
    // The accent is the scheme's focus colour (its selection colour is the deeper container tone).
    // Re-read while following the system, so a wallpaper-driven accent change shows up without a restart.
    property string schemeAccent: mixer.schemeAccent()
    Timer {
        interval: 1000; repeat: true; running: !win.ownColors
        onTriggered: { const a = mixer.schemeAccent(); if (a !== win.schemeAccent) win.schemeAccent = a; }
    }
    readonly property color accent: bgOn && imgReady && !glassy ? imgA : ownColors ? theme.accent : systemAccent
    readonly property color accentEnd: bgOn && imgReady && !glassy ? imgB : ownColors && theme.accentEnd ? theme.accentEnd : soft ? Qt.hsla(accent.hslHue + 0.045, accent.hslSaturation, accent.hslLightness, 1) : accent
    readonly property color onFill: soft ? baseHighlight : accent
    readonly property color select: diamond ? "#4b3a85" : baseHighlight
    readonly property color accentInk: baseHighlightedText
    readonly property color danger: "#e5484d"
    readonly property color ok: "#39d98a"
    readonly property color warning: "#f5a524"
    readonly property string mono: ownColors && theme.font ? theme.font : soft ? "Roboto Flex" : "Geist Mono"
    readonly property string display: ownColors && theme.font ? theme.font : soft ? "Roboto Flex" : diamond ? "Geist Mono" : "Archivo"

    Mixer { id: mixer }
    readonly property string version: mixer.version()
    function licensesText() { return mixer.licenses(); }

    // Updates (see updater.rs): the state is polled while anything is going on, and once at launch if allowed.
    property var update: ({ state: "idle", current: "", latest: "", notes: "", progress: 0, message: "" })
    function checkForUpdate() { mixer.updateCheck(); }
    function installUpdate() { mixer.updateInstall(); }
    function restartAfterUpdate() { mixer.updateRestart(); quitApp(); }
    Timer {
        interval: 700; repeat: true; running: win.awake
        onTriggered: {
            const json = mixer.updateStatus();
            if (json !== win.updateJson) { win.updateJson = json; win.update = JSON.parse(json); }
        }
    }
    property string updateJson: ""
    // Dev aid: a screenshot only captures `page`, so --licences moves the dialog layer into it.
    Component.onCompleted: {
        reshape()
        if (Qt.application.arguments.indexOf("--licences") >= 0) Overlay.overlay.parent = page
        if (cfg.check_updates !== false && Qt.application.arguments.indexOf("--screenshot") < 0) mixer.updateCheck()
    }

    // Picture background (Settings > Background). `--bg <file>` is a dev aid for screenshots.
    readonly property int bgArg: Qt.application.arguments.indexOf("--bg")
    readonly property string imgUrl: bgArg >= 0 ? "file://" + Qt.application.arguments[bgArg + 1] : (cfg.bg_enabled && cfg.bg_image ? cfg.bg_image : (cfg.bg_image || ""))
    readonly property bool bgOn: imgUrl !== "" && (bgArg >= 0 || !!cfg.bg_enabled)
    readonly property Item blurSource: blurLayer
    // The two colours the bars take from the picture.
    property color imgA: "#ff4fd8"
    property color imgB: "#8b5cff"
    property bool imgReady: false

    // Reads a 48x48 thumbnail of the picture (cropped like the background) and picks two vivid colours
    // of different hues: the most common vivid hue, then the most common one that is clearly another.
    function pickColors(data) {
        const BINS = 18;
        const w = new Array(BINS).fill(0), sum = new Array(BINS).fill(0);
        for (let i = 0; i < data.length; i += 4) {
            const r = data[i] / 255, g = data[i + 1] / 255, b = data[i + 2] / 255;
            const hi = Math.max(r, g, b), lo = Math.min(r, g, b), d = hi - lo;
            if (hi < 0.2 || d / hi < 0.18) continue;
            let h = d === 0 ? 0 : hi === r ? ((g - b) / d + 6) % 6 : hi === g ? (b - r) / d + 2 : (r - g) / d + 4;
            h /= 6;
            const weight = (d / hi) * hi;
            const bin = Math.min(BINS - 1, Math.floor(h * BINS));
            w[bin] += weight;
            sum[bin] += weight * h;
        }
        let a = 0;
        for (let i = 1; i < BINS; i++) if (w[i] > w[a]) a = i;
        if (w[a] <= 0) return false;          // a grey picture keeps the normal colours
        let b = -1;
        for (let i = 0; i < BINS; i++) {
            const dist = Math.min(Math.abs(i - a), BINS - Math.abs(i - a));
            if (dist >= 2 && w[i] >= w[a] * 0.2 && (b < 0 || w[i] > w[b])) b = i;
        }
        const hA = sum[a] / w[a];
        const hB = b >= 0 ? sum[b] / w[b] : (hA + 0.09) % 1;
        imgA = Qt.hsla(hA, 0.85, 0.64, 1);
        imgB = Qt.hsla(hB, 0.8, 0.58, 1);
        return true;
    }

    property var cfg: JSON.parse(mixer.settings())
    // Set while PipeWire can't be reached (see Mixer::engineStatus); shown in place of the status pill.
    property string engineError: ""
    // No point redrawing meters and program lists for a window nobody can see.
    readonly property bool awake: visibility !== Window.Minimized && visibility !== Window.Hidden
    property var devices: ({ sources: [], sinks: [] })
    property var meters: ({ strips: [], buses: [] })
    property string devicesJson: ""
    property var streams: []
    property string streamsJson: "[]"
    // ---- Layout: what is on screen, and how the window adapts to its size ----
    // Under 640 px wide each channel is a row and the pages sit in a bar along the bottom; from 1100 px the
    // inspector docks beside the mixer, below that it slides over it.
    readonly property bool mini: width < 640
    readonly property bool dockable: width >= 1100
    // "mixer", "routing", "eq" or "settings". `--view eq`, `--settings` and `--eq bus:0` are dev aids for screenshots.
    property string view: Qt.application.arguments.indexOf("--settings") >= 0 ? "settings" : arg("--eq", "") !== "" ? "eq" : arg("--view", "mixer")
    readonly property var ui: cfg.ui || ({})
    readonly property bool showInputs: ui.show_inputs !== false
    readonly property bool showVirtual: ui.show_virtual !== false
    readonly property bool showOutputs: ui.show_outputs !== false
    readonly property bool compact: !!ui.compact
    function setUi(mutate) { change(c => { c.ui = c.ui || {}; mutate(c.ui); }); }

    // The channel the inspector shows. `--sel bus:0` and `--insp 0|1` are dev aids for screenshots.
    property var sel: ({ kind: arg("--sel", "strip:0").split(":")[0], index: parseInt(arg("--sel", "strip:0").split(":")[1]) })
    property bool sheetOpen: arg("--insp", "") === "1"
    readonly property bool inspWanted: dockable ? (arg("--insp", "") !== "" ? arg("--insp", "") === "1" : ui.inspector !== false) : sheetOpen
    readonly property bool inspShown: view === "mixer" && inspWanted
    function selectChannel(kind, index, open) {
        sel = { kind: kind, index: index };
        if (!open) return;
        if (!dockable) sheetOpen = true;
        else if (ui.inspector === false) setUi(u => u.inspector = true);
    }
    function closeInspector() { if (dockable) setUi(u => u.inspector = false); else sheetOpen = false; }
    function toggleInspector() {
        if (view !== "mixer") { view = "mixer"; if (!inspWanted) selectChannel(sel.kind, sel.index, true); return; }
        if (inspWanted) closeInspector(); else selectChannel(sel.kind, sel.index, true);
    }
    // The output the EQ page is on.
    property int eqIndex: arg("--eq", "") !== "" ? parseInt(arg("--eq", "bus:0").split(":")[1]) : 0
    function openEq(kind, index) { eqIndex = index; view = "eq"; }

    // Which strips and outputs belong to each group, as indexes into cfg.strips and cfg.buses. They are only
    // replaced when the layout itself changes, so moving a fader doesn't rebuild every strip.
    property var hwIdx: []
    property var virtIdx: []
    property var aIdx: []
    property var bIdx: []
    property string shape: ""
    onCfgChanged: reshape()
    function reshape() {
        const now = cfg.strips.map(s => (s.virtual_input ? "v" : "h") + s.label).join(",") + "|" + cfg.buses.map(b => b.label).join(",");
        if (now === shape) return;
        shape = now;
        const pick = (list, test) => list.map((x, i) => test(x) ? i : -1).filter(i => i >= 0);
        // Outputs show in number order (A1, A2, A3) wherever they sit in the list.
        const byNumber = list => list.sort((i, j) => parseInt(cfg.buses[i].label.slice(1)) - parseInt(cfg.buses[j].label.slice(1)));
        hwIdx = pick(cfg.strips, s => !s.virtual_input);
        virtIdx = pick(cfg.strips, s => !!s.virtual_input);
        aIdx = byNumber(pick(cfg.buses, b => !b.virtual_output));
        bIdx = byNumber(pick(cfg.buses, b => !!b.virtual_output));
        if (!(sel.kind === "bus" ? cfg.buses[sel.index] : cfg.strips[sel.index])) sel = { kind: "strip", index: 0 };
    }

    // ---- Adding and removing channels ----
    // The most of each kind (the same numbers as MAX_* in settings.rs). At least one of each always stays.
    readonly property var limits: ({ hw: 5, virt: 6, a: 5, b: 3 })
    readonly property var hwLabels: ["Mic", "Input 2", "Input 3", "Input 4", "Input 5"]
    readonly property var virtLabels: ["Apps", "Media", "Game", "Chat", "Browser", "Aux"]
    function groupOf(kind, index) {
        if (kind === "bus") return (cfg.buses[index] || blank).virtual_output ? "b" : "a";
        return (cfg.strips[index] || blank).virtual_input ? "virt" : "hw";
    }
    function countOf(group) { return { hw: hwIdx, virt: virtIdx, a: aIdx, b: bIdx }[group].length; }
    // The device name part, as settings.rs `slug` makes it: "Apps" -> "apps".
    function slug(label) { return (label || "").replace(/[^A-Za-z0-9]/g, "_").toLowerCase(); }
    // A change that adds or removes channels: the engine settles labels and routes, so take its copy back.
    function restructure(mutate) {
        change(mutate);
        const settled = JSON.parse(mixer.settings());
        if (settled.strips.length === cfg.strips.length && settled.buses.length === cfg.buses.length) cfg = settled;
    }
    function addChannel(group) {
        if (countOf(group) >= limits[group]) return;
        restructure(c => {
            if (group === "hw" || group === "virt") {
                const pool = group === "hw" ? hwLabels : virtLabels;
                const label = pool.find(l => !c.strips.some(s => s.label === l));
                const routes = c.buses.map(() => false);
                // A new virtual input plays on the first listen output, so you hear what lands there.
                const firstA = c.buses.findIndex(b => !b.virtual_output);
                if (group === "virt" && firstA >= 0) routes[firstA] = true;
                c.strips.push({ label: label, virtual_input: group === "virt", routes: routes });
                selectChannel("strip", c.strips.length - 1, false);
            } else {
                const letter = group === "a" ? "A" : "B";
                let n = 1;
                while (c.buses.some(b => b.label === letter + n)) n++;
                c.buses.push({ label: letter + n, virtual_output: group === "b" });
                for (const s of c.strips) s.routes.push(false);
                selectChannel("bus", c.buses.length - 1, false);
            }
        });
    }
    function removeChannel(kind, index) {
        const group = groupOf(kind, index);
        removeAsk = "";
        if (countOf(group) <= 1) return;
        const gone = tagOf(kind, index) + " · " + nameOf(kind, index);
        if (sel.kind === kind && sel.index >= index) sel = { kind: kind, index: Math.max(0, sel.index - 1) };
        restructure(c => {
            if (kind === "bus") {
                c.buses.splice(index, 1);
                for (const s of c.strips) s.routes.splice(index, 1);
            } else {
                c.strips.splice(index, 1);
            }
        });
        // Keep the inspector on a channel of the same kind.
        const same = kind === "bus" ? (group === "a" ? aIdx : bIdx) : (group === "hw" ? hwIdx : virtIdx);
        sel = { kind: kind, index: same[Math.min(same.length - 1, Math.max(0, same.findIndex(i => i >= index)))] };
        flash(gone + " removed");
    }
    // "Remove this?" waiting for an answer, as "kind:index:label" of the channel (see Inspector), or "".
    // Picking another channel drops the question. `--ask 1` asks about the selected channel, for screenshots.
    property string removeAsk: arg("--ask", "") !== "" ? sel.kind + ":" + sel.index + ":" + ((sel.kind === "bus" ? cfg.buses : cfg.strips)[sel.index] || blank).label : ""
    onSelChanged: if (removeAsk !== "" && !removeAsk.startsWith(sel.kind + ":" + sel.index + ":")) removeAsk = ""
    // The − in a section header: show the group's last channel and ask before it goes.
    function askRemove(group) {
        const kind = group === "a" || group === "b" ? "bus" : "strip", index = lastOf(group);
        selectChannel(kind, index, true);
        removeAsk = kind + ":" + index + ":" + ((kind === "bus" ? cfg.buses : cfg.strips)[index] || blank).label;
    }
    // The last channel of the group in the order it is shown, for the − in a section header.
    function lastOf(group) { const list = { hw: hwIdx, virt: virtIdx, a: aIdx, b: bIdx }[group]; return list[list.length - 1]; }
    // Stands in for a channel that has just gone, until the views catch up.
    readonly property var blank: ({ label: "", name: "", routes: [], eq: [], gain_db: 0 })
    // The fixed badge: IN1, V2, A1, B1. Names can change; these never do, so buttons keep their size.
    function tagOf(kind, index) {
        if (kind === "bus") return (cfg.buses[index] || blank).label;
        const strip = cfg.strips[index] || blank;
        return strip.virtual_input ? "V" + (virtIdx.indexOf(index) + 1) : "IN" + (hwIdx.indexOf(index) + 1);
    }
    function shortDevice(text) { return text.replace(/ (Analog|Digital) (Stereo|Mono|Surround).*$/, "").replace(/ (Stereo|Mono)$/, ""); }
    function defaultName(kind, index) {
        if (kind !== "bus") return (cfg.strips[index] || blank).label;
        const bus = cfg.buses[index] || blank;
        if (bus.virtual_output) return "Virtual mic";
        return bus.device ? shortDevice(describe(devices.sinks, bus.device)) : "No device";
    }
    function nameOf(kind, index) {
        const ch = (kind === "bus" ? cfg.buses[index] : cfg.strips[index]) || blank;
        return ch.name ? ch.name : defaultName(kind, index);
    }
    // The line under the name: what the channel is connected to.
    function subOf(kind, index) {
        const ch = (kind === "bus" ? cfg.buses[index] : cfg.strips[index]) || blank;
        if (kind === "bus") return ch.virtual_output ? "Virtual mic for other programs" : ch.device ? shortDevice(describe(devices.sinks, ch.device)) : "No device";
        if (ch.virtual_input) return "Programs play here";
        return ch.source ? shortDevice(describe(devices.sources, ch.source)) : "No device";
    }
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
        const bus = cfg.buses[index] || blank;
        if (bus.virtual_output)
            return bus.name ? bus.label + " · " + bus.name : "Virtual mic " + bus.label;
        const what = bus.device ? describe(devices.sinks, bus.device) : "no device yet";
        return bus.label + " · " + (bus.name ? bus.name + " · " : "") + what;
    }

    function muteStream(id, muted) {
        mixer.muteStream(id, muted);
    }
    function moveStream(id, target, label) {
        mixer.moveStream(id, target);
        flash("Sent to " + label);
    }

    // Both virtual mics at once, for a quick "nobody can hear me" button.
    readonly property bool micsMuted: bIdx.length > 0 && bIdx.every(i => (cfg.buses[i] || blank).mute)
    function muteMics(muted) {
        change(c => { for (const i of bIdx) c.buses[i].mute = muted; });
    }

    // ---- Scenes: saved layouts of every strip and bus (not the look) ----
    readonly property var scenes: cfg.scenes || []
    function plain(x) { return JSON.parse(JSON.stringify(x)); }
    // The mixer as it is now, without the session-only solo flags. Names belong to the channels, not to a
    // scene, so they are left out too.
    function snapshot() {
        const strips = plain(cfg.strips), buses = plain(cfg.buses);
        for (const s of strips) { delete s.solo; s.name = ""; }
        for (const b of buses) b.name = "";
        return { strips: strips, buses: buses };
    }
    function same(a, b) {
        if (a === b) return true;
        if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return false;
        const ka = Object.keys(a), kb = Object.keys(b);
        return ka.length === kb.length && ka.every(k => same(a[k], b[k]));
    }
    function sceneActive(i) {
        const scene = scenes[i], now = snapshot();
        return !!scene && same(scene.strips, now.strips) && same(scene.buses, now.buses);
    }
    function saveScene(name) {
        const clean = name.trim();
        if (clean === "") return;
        const snap = snapshot();
        change(c => {
            c.scenes = c.scenes || [];
            const at = c.scenes.findIndex(s => s.name === clean);
            const scene = { name: clean, strips: snap.strips, buses: snap.buses };
            if (at >= 0) c.scenes[at] = scene; else if (c.scenes.length < 12) c.scenes.push(scene);
        });
    }
    function deleteScene(i) { change(c => c.scenes.splice(i, 1)); }
    // A scene is applied channel by channel, matched by label, so one saved with more or fewer channels than
    // there are now still fits: channels it doesn't know keep their settings, and its routes follow the labels.
    function applyScene(i) {
        const scene = scenes[i];
        if (!scene) return;
        change(c => {
            for (const s of c.strips) {
                const from = scene.strips.find(x => x.label === s.label && !!x.virtual_input === !!s.virtual_input);
                if (!from) continue;
                const keep = { label: s.label, name: s.name || "", virtual_input: s.virtual_input };
                Object.assign(s, plain(from), keep);
                s.routes = c.buses.map(b => {
                    const j = scene.buses.findIndex(x => x.label === b.label);
                    return j >= 0 && !!(from.routes || [])[j];
                });
            }
            for (const b of c.buses) {
                const from = scene.buses.find(x => x.label === b.label);
                if (from) Object.assign(b, plain(from), { label: b.label, name: b.name || "", virtual_output: b.virtual_output });
            }
        });
        flash("Scene: " + scene.name);
    }
    function flash(text) { status = text; statusTimer.restart(); }

    // ---- Global shortcuts (keys are kept by KDE's shortcut service) ----
    readonly property bool shortcutsOk: mixer.shortcutsAvailable()
    property int pttKey: mixer.shortcutKey("ptt")
    property int muteKey: mixer.shortcutKey("mute-mics")
    function setShortcut(action, key) {
        const got = mixer.setShortcutKey(action, key);
        if (got < 0) { flash("That key is already used by another shortcut."); return; }
        if (action === "ptt") pttKey = got; else muteKey = got;
    }
    // "Ctrl+Alt+F12" from a Qt key code.
    function keyText(code) {
        if (!code) return "";
        const names = { 0x20: "Space", 0x01000001: "Tab", 0x01000003: "Backspace", 0x01000004: "Return", 0x01000005: "Enter",
                        0x01000006: "Insert", 0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print", 0x01000010: "Home",
                        0x01000011: "End", 0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down",
                        0x01000016: "PgUp", 0x01000017: "PgDown", 0x01000024: "CapsLock", 0x01000025: "NumLock", 0x01000026: "ScrollLock" };
        const parts = [];
        if (code & 0x10000000) parts.push("Meta");
        if (code & 0x04000000) parts.push("Ctrl");
        if (code & 0x08000000) parts.push("Alt");
        if (code & 0x02000000) parts.push("Shift");
        const k = code & 0x01ffffff;
        parts.push(names[k] || (k >= 0x01000030 && k <= 0x01000047 ? "F" + (k - 0x01000030 + 1)
                  : k >= 0x21 && k <= 0x7e ? String.fromCharCode(k).toUpperCase() : "Key " + k.toString(16)));
        return parts.join("+");
    }
    // Requests from the desktop (the mute shortcut), picked up a few times a second.
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            for (const e of JSON.parse(mixer.takeEvents())) {
                if (e === "mute-mics") {
                    muteMics(!micsMuted);
                    flash(micsMuted ? "Microphones muted" : "Microphones live");
                }
            }
        }
    }

    // ---- Tray icon: show/hide, mute, scenes, quit ----
    readonly property bool trayOn: trayLoader.item ? trayLoader.item.available : false
    function quitApp() { mixer.persist(); Qt.quit(); }
    function toggleWindow() {
        if (visible) { hide(); return; }
        show(); raise(); requestActivate();
    }
    // Not made under the offscreen test platform, which has no native menus.
    Loader {
        id: trayLoader
        active: Qt.platform.pluginName !== "offscreen"
        sourceComponent: Component { Tray { app: win } }
    }

    function makeDefault(node, done) {
        status = mixer.makeDefault(node) ? done : "Couldn't change the system default.";
        statusTimer.restart();
    }

    Timer { id: saveTimer; interval: 600; onTriggered: mixer.persist() }
    Timer { id: statusTimer; interval: 4000; onTriggered: win.status = "" }
    Timer {
        interval: 33
        running: win.awake
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
            win.engineError = mixer.engineStatus();
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
        running: win.awake
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
    onClosing: close => {
        mixer.persist();
        if (cfg.close_to_tray && trayOn) { close.accepted = false; hide(); }
        else Qt.quit();
    }

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
        color: win.glassy && !win.bgOn ? "transparent" : win.bg
        gradient: win.glassy && !win.bgOn ? glassGradient : null
        Gradient {
            id: glassGradient
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: win.glassy ? Qt.alpha(theme.gradient[0], theme.windowAlpha) : "transparent" }
            GradientStop { position: 1; color: win.glassy ? Qt.alpha(theme.gradient[1], theme.windowAlpha) : "transparent" }
        }

        // The picture, cropped to fill (never squashed), a little darker so text stays readable. It is a bit
        // bigger than the window so the blurred copy has no faded edges where boxes sit near the border.
        Item {
            id: bgScene
            x: -80; y: -80
            width: page.width + 160
            height: page.height + 160
            visible: win.bgOn
            Image {
                id: bgImage
                anchors.fill: parent
                source: win.bgOn ? win.imgUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                autoTransform: true
                sourceSize.width: 2560
                onStatusChanged: if (status === Image.Ready) sampler.requestPaint()
            }
            Rectangle { anchors.fill: parent; color: Qt.alpha(win.bg, glassy ? theme.wash : 0.30) }
        }
        // The blurred copy the boxes show through (not too strong). It sits under the sharp picture.
        MultiEffect {
            id: blurLayer
            x: bgScene.x; y: bgScene.y; width: bgScene.width; height: bgScene.height
            z: -1
            source: bgScene
            visible: win.bgOn
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: win.glassy ? 1.0 : 0.8
        }
        // Glass themes: the window itself is frosted too (like Mica), so only soft colour shows, never the picture's detail.
        MultiEffect {
            x: bgScene.x; y: bgScene.y; width: bgScene.width; height: bgScene.height
            source: bgScene
            visible: win.bgOn && win.glassy
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: 1.0
        }
        Canvas {
            id: sampler
            width: 48; height: 48
            visible: false
            renderTarget: Canvas.Image
            readonly property url src: win.bgOn ? win.imgUrl : ""
            onSrcChanged: { win.imgReady = false; if (src.toString() !== "") loadImage(src); }
            onImageLoaded: requestPaint()
            onPaint: {
                if (src.toString() === "" || !isImageLoaded(src)) return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, 48, 48);
                ctx.drawImage(src, 0, 0, 48, 48);
                win.imgReady = win.pickColors(ctx.getImageData(0, 0, 48, 48).data);
            }
        }

        // A page button: in the rail down the left side, or in the bar along the bottom of a narrow window.
        component PageButton: Rectangle {
            id: pageButton
            property var app
            property string page
            property string icon
            property string label
            property bool dot: false
            readonly property bool current: app.view === page
            width: 56
            height: 52
            radius: app.soft ? 13 : 0
            color: current ? Qt.alpha(app.accent, 0.14) : pageMouse.containsMouse ? app.hover : "transparent"
            border.color: current && !app.soft ? app.accent : "transparent"
            Column {
                anchors.centerIn: parent
                spacing: 4
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: pageButton.icon; color: pageButton.current ? pageButton.app.accent : pageButton.app.dim; width: 20; height: 20 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: pageButton.label; color: pageButton.current ? pageButton.app.ink : pageButton.app.dim; font.pixelSize: 10; font.weight: Font.Medium }
            }
            Rectangle {
                visible: pageButton.dot
                x: parent.width - 16; y: 6
                width: 9; height: 9; radius: 5
                color: pageButton.app.accent
            }
            MouseArea { id: pageMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pageButton.app.view = pageButton.page }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---- Top bar: scenes, what is shown, the inspector, and the mic kill switch ----
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: win.soft ? 9 : 0
                        gradient: Gradient {
                            GradientStop { position: 0; color: win.accent }
                            GradientStop { position: 1; color: win.accentEnd }
                        }
                        Icon { anchors.centerIn: parent; name: "logo"; color: "#ffffff"; width: 18; height: 18 }
                    }
                    Text {
                        visible: !win.mini
                        text: "Vox"
                        color: win.ink
                        font.family: win.display
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        rightPadding: 6
                    }
                    // Saved scenes (make them in Settings): one click swaps in a whole layout.
                    Repeater {
                        model: win.width >= 900 ? Math.min(win.scenes.length, win.width >= 1300 ? 5 : 3) : 0
                        Chip {
                            required property int index
                            app: win
                            text: win.scenes[index].name
                            checked: win.sceneActive(index)
                            tip: "Scene: " + win.scenes[index].name
                            onToggled: win.applyScene(index)
                        }
                    }
                    Item { Layout.fillWidth: true }

                    // Show or hide a whole group of channels.
                    Repeater {
                        model: [{ key: "show_inputs", label: "Inputs", icon: "mic" }, { key: "show_virtual", label: "Virtual", icon: "app" }, { key: "show_outputs", label: "Outputs", icon: "out" }]
                        Rectangle {
                            id: show
                            required property var modelData
                            readonly property bool on: win.ui[modelData.key] !== false
                            readonly property bool wide: win.width >= 1180
                            function flip() { win.setUi(u => u[show.modelData.key] = !show.on); }
                            Layout.preferredHeight: 34
                            Layout.preferredWidth: win.mini ? 34 : showRow.implicitWidth + 20
                            radius: win.soft ? 11 : 0
                            color: win.mini && on ? Qt.alpha(win.accent, 0.16) : showMouse.containsMouse ? win.hover : win.soft ? win.tonal : "transparent"
                            border.color: win.mini && on ? Qt.alpha(win.accent, 0.5) : win.soft ? win.controlEdge : win.line
                            Row {
                                id: showRow
                                anchors.centerIn: parent
                                spacing: 8
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: show.modelData.icon; width: 16; height: 16; color: win.mini && show.on ? win.accent : win.mini ? win.dim : win.ink }
                                Text { visible: show.wide; anchors.verticalCenter: parent.verticalCenter; text: show.modelData.label; color: win.ink; font.pixelSize: 12; font.weight: Font.Medium }
                                Toggle { visible: !win.mini; anchors.verticalCenter: parent.verticalCenter; app: win; checked: show.on; onToggled: show.flip() }
                            }
                            MouseArea {
                                id: showMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: show.flip()
                            }
                            ToolTip.visible: showMouse.containsMouse
                            ToolTip.delay: 400
                            ToolTip.text: (show.on ? "Hide " : "Show ") + show.modelData.label.toLowerCase() + (show.modelData.key === "show_virtual" ? " inputs" : "")
                        }
                    }
                    IconButton {
                        visible: !win.mini
                        app: win
                        icon: "rows"
                        checked: win.compact
                        tip: win.compact ? "Show the full strips" : "Slim strips: fader, meter and mute only"
                        onClicked: win.setUi(u => u.compact = !win.compact)
                    }
                    IconButton {
                        app: win
                        icon: "panel"
                        checked: win.inspShown
                        tip: win.inspShown ? "Hide the inspector" : "Show the inspector"
                        onClicked: win.toggleInspector()
                    }
                    IconButton {
                        app: win
                        icon: "mic"
                        text: win.width >= 780 ? (win.micsMuted ? "Mics muted" : "Mics live") : ""
                        checked: true
                        tint: win.micsMuted ? win.danger : win.ok
                        tip: win.micsMuted ? "Every B mic is muted: nobody on a call or stream hears you. Click to go live." : "Mute every B mic at once, so nobody on a call or stream hears you"
                        onClicked: win.muteMics(!win.micsMuted)
                    }
                }
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: win.line }
            }

            // ---- The pages, with the rail on the left and the inspector on the right ----
            Item {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property bool docked: win.inspShown && win.dockable

                Item {
                    id: rail
                    visible: !win.mini
                    width: visible ? 72 : 0
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                        spacing: 4
                        PageButton { app: win; page: "mixer"; icon: "mixer"; label: "Mixer" }
                        PageButton { app: win; page: "routing"; icon: "grid"; label: "Routing" }
                        PageButton { app: win; page: "eq"; icon: "wave"; label: "EQ" }
                    }
                    PageButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        app: win; page: "settings"; icon: "gear"; label: "Settings"
                        dot: win.update.state === "available"
                    }
                    Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: win.line }
                }

                Item {
                    id: pages
                    anchors.left: rail.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.rightMargin: stage.docked ? inspector.width : 0

                    MixerView { anchors.fill: parent; visible: win.view === "mixer"; app: win }
                    Loader {
                        anchors.fill: parent
                        active: win.view === "routing"
                        sourceComponent: RoutingView { app: win }
                    }
                    Loader {
                        anchors.fill: parent
                        active: win.view === "eq"
                        sourceComponent: EqView { app: win }
                    }
                    Loader {
                        anchors.fill: parent
                        active: win.view === "settings"
                        sourceComponent: Item {
                            SettingsPanel {
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.topMargin: 16
                                width: Math.min(parent.width - 24, 760)
                                app: win
                            }
                        }
                    }
                }

                // In a window too small to dock it, the inspector slides over the mixer; a click beside it closes it.
                Rectangle {
                    visible: win.inspShown && !win.dockable
                    anchors.fill: parent
                    color: Qt.alpha("#000000", 0.45)
                    MouseArea { anchors.fill: parent; onClicked: win.closeInspector() }
                }
                Inspector {
                    id: inspector
                    visible: win.inspShown
                    app: win
                    width: win.mini ? parent.width : win.width >= 1500 ? 340 : 320
                    height: win.mini ? Math.round(parent.height * 0.8) : parent.height
                    x: parent.width - width
                    y: parent.height - height
                    Rectangle { visible: !win.mini; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: win.line }
                    Rectangle { visible: win.mini; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: win.line }
                }

                // What just happened ("Scene: Stream", "System output is now…"), for a few seconds.
                Rectangle {
                    visible: win.status !== ""
                    anchors.horizontalCenter: pages.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: Math.min(parent.width - 24, toastText.implicitWidth + 28)
                    height: 30
                    radius: win.soft ? 15 : 0
                    color: Qt.tint(win.bg, Qt.alpha(win.accent, 0.22))
                    border.color: Qt.alpha(win.accent, 0.6)
                    Text {
                        id: toastText
                        anchors.centerIn: parent
                        width: parent.width - 24
                        horizontalAlignment: Text.AlignHCenter
                        text: win.status
                        color: win.ink
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- Narrow window: the pages along the bottom ----
            Item {
                visible: win.mini
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: win.line }
                Row {
                    anchors.centerIn: parent
                    spacing: Math.max(4, (parent.width - 4 * 56) / 5)
                    PageButton { app: win; page: "mixer"; icon: "mixer"; label: "Mixer" }
                    PageButton { app: win; page: "routing"; icon: "grid"; label: "Routing" }
                    PageButton { app: win; page: "eq"; icon: "wave"; label: "EQ" }
                    PageButton { app: win; page: "settings"; icon: "gear"; label: "Settings"; dot: win.update.state === "available" }
                }
            }

            // ---- Status bar ----
            Item {
                visible: !win.mini
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: win.line }
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 4; color: win.engineError !== "" ? win.danger : win.ok }
                    Text { text: win.engineError !== "" ? win.engineError : "Engine running"; color: win.engineError !== "" ? win.danger : win.dim; font.pixelSize: 11 }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Vox Obscurus " + win.version
                    color: win.dim
                    font.pixelSize: 11
                }
            }
        }
    }
}
