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

    fn make_default(&self, node: &qobject::QString) -> bool {
        let id = state().engine.shared.own_nodes.lock().unwrap().get(&node.to_string()).copied();
        let Some(id) = id else { return false };
        std::process::Command::new("wpctl")
            .args(["set-default", &id.to_string()])
            .status()
            .is_ok_and(|s| s.success())
    }
}
