mod bridge;
mod dsp;
mod engine;
mod settings;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};
use std::fs::{File, OpenOptions, TryLockError};
use std::path::PathBuf;

/// Only one copy may run: a second one would create a second set of devices with the same
/// names. The lock lasts as long as the returned file is open, and the OS drops it if we crash.
/// Returns None when another copy holds it; if the lock file can't be made, we run anyway.
fn claim_single_instance() -> Option<Option<File>> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let Ok(file) = OpenOptions::new().create(true).truncate(false).write(true).open(dir.join("vox-obscurus.lock"))
    else {
        return Some(None);
    };
    match file.try_lock() {
        Err(TryLockError::WouldBlock) => None,
        _ => Some(Some(file)),
    }
}

fn main() {
    let Some(_instance) = claim_single_instance() else {
        eprintln!("vox-obscurus: already running");
        // Launched from the app menu there's no terminal, so say it on the desktop too.
        let _ = std::process::Command::new("notify-send")
            .args(["--app-name=Vox Obscurus", "Vox Obscurus is already running"])
            .status();
        return;
    };

    let settings = settings::load();
    bridge::init(engine::start(settings.clone()), settings);

    let mut app = QGuiApplication::new();
    if let Some(app) = app.as_mut() {
        app.set_application_name(&QString::from("Vox Obscurus"));
    }
    let mut qml = QQmlApplicationEngine::new();
    if let Some(qml) = qml.as_mut() {
        qml.load(&QUrl::from("qrc:/qt/qml/org/obscura/vox/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
