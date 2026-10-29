//! The `Mixer` object QML talks to. QML keeps the settings as a plain JS object and hands
//! the whole thing back as JSON on every change; meters and devices come back as JSON too.

use crate::engine::{self, Command, Handle};
use crate::settings::{self, Settings};
use std::sync::{Mutex, OnceLock};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type Mixer = super::MixerRust;

        // The current settings as JSON.
        #[qinvokable]
        fn settings(self: &Mixer) -> QString;

        // `{sources: [...], sinks: [...]}`, each `{name, description}`.
        #[qinvokable]
        fn devices(self: &Mixer) -> QString;

        // Peak levels since the last call: `{strips: [[l, r], ...], buses: [[l, r], ...]}`.
        #[qinvokable]
        fn meters(self: &Mixer) -> QString;

        // Send new settings (JSON) to the engine.
        #[qinvokable]
        fn apply(self: &Mixer, json: &QString);

        // Write the current settings to disk.
        #[qinvokable]
        fn persist(self: &Mixer);

        // Programs using Apps, Media, B1 and B2: `[{id, name, target, muted}, ...]`.
        #[qinvokable]
        fn streams(self: &Mixer) -> QString;

        // Mute or unmute one program's stream by node id.
        #[qinvokable]
        #[cxx_name = "muteStream"]
        fn mute_stream(self: &Mixer, id: i32, muted: bool);

        // The Plasma colour scheme's name (e.g. "MatOSDark"), so the UI can pick its look.
        #[qinvokable]
        #[cxx_name = "colorScheme"]
        fn color_scheme(self: &Mixer) -> QString;

        // The scheme's accent (its window focus colour) as "#rrggbb", or "" if it can't be read.
        #[qinvokable]
        #[cxx_name = "schemeAccent"]
        fn scheme_accent(self: &Mixer) -> QString;

        // Make one of our nodes (by node.name) the system default output or microphone.
        #[qinvokable]
        #[cxx_name = "makeDefault"]
        fn make_default(self: &Mixer, node: &QString) -> bool;
    }
}

struct State {
    engine: Handle,
    current: Mutex<Settings>,
}

static STATE: OnceLock<State> = OnceLock::new();

/// Called once from main before the UI loads.
pub fn init(engine: Handle, settings: Settings) {
    let _ = STATE.set(State { engine, current: Mutex::new(settings) });
}

fn state() -> &'static State {
    STATE.get().expect("bridge::init runs before the UI")
}

fn read_kdeglobals() -> String {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")));
    base.and_then(|b| std::fs::read_to_string(b.join("kdeglobals")).ok()).unwrap_or_default()
}

#[derive(Default)]
pub struct MixerRust;

impl qobject::Mixer {
    fn settings(&self) -> qobject::QString {
        qobject::QString::from(&state().current.lock().unwrap().to_json())
    }

    fn devices(&self) -> qobject::QString {
        let devices = state().engine.shared.devices.lock().unwrap();
        qobject::QString::from(&serde_json::to_string(&*devices).unwrap_or_default())
    }

    fn streams(&self) -> qobject::QString {
        qobject::QString::from(&*state().engine.shared.streams.lock().unwrap())
    }

    fn mute_stream(&self, id: i32, muted: bool) {
        let _ = state().engine.sender.lock().unwrap().send(Command::MuteStream(id as u32, muted));
    }

    fn meters(&self) -> qobject::QString {
        let shared = &state().engine.shared;
        let pair = |cells: &[std::sync::atomic::AtomicU32; 2]| [engine::take_peak(&cells[0]), engine::take_peak(&cells[1])];
        let strips: Vec<_> = shared.strip_peaks.iter().map(pair).collect();
        let buses: Vec<_> = shared.bus_peaks.iter().map(pair).collect();
        let json = serde_json::json!({ "strips": strips, "buses": buses });
        qobject::QString::from(&json.to_string())
    }

    fn apply(&self, json: &qobject::QString) {
        let Some(settings) = Settings::from_json(&json.to_string()) else { return };
        let state = state();
        *state.current.lock().unwrap() = settings.clone();
        let _ = state.engine.sender.lock().unwrap().send(Command::Apply(settings));
    }

    fn persist(&self) {
        settings::save(&state().current.lock().unwrap());
    }

    fn color_scheme(&self) -> qobject::QString {
        let text = read_kdeglobals();
        let name = text.lines().find_map(|l| l.strip_prefix("ColorScheme=")).unwrap_or("");
        qobject::QString::from(name)
    }

    fn scheme_accent(&self) -> qobject::QString {
        let text = read_kdeglobals();
        let mut in_window = false;
        for line in text.lines() {
            if line.starts_with('[') {
                in_window = line.trim() == "[Colors:Window]";
            } else if let (true, Some(rgb)) = (in_window, line.strip_prefix("DecorationFocus=")) {
                let c: Vec<u8> = rgb.split(',').filter_map(|v| v.trim().parse().ok()).collect();
                if let [r, g, b] = c[..] {
                    return qobject::QString::from(&format!("#{r:02x}{g:02x}{b:02x}"));
                }
            }
        }
        qobject::QString::from("")
    }

    fn make_default(&self, node: &qobject::QString) -> bool {
        let id = state().engine.shared.own_nodes.lock().unwrap().get(&node.to_string()).copied();
        let Some(id) = id else { return false };
        std::process::Command::new("wpctl")
            .args(["set-default", &id.to_string()])
            .status()
            .is_ok_and(|s| s.success())
    }
}
