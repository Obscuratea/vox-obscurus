use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("org.obscura.vox").qml_files([
        "qml/Main.qml",
        "qml/StripCard.qml",
        "qml/BusRow.qml",
        "qml/Fader.qml",
        "qml/LevelMeter.qml",
        "qml/Chip.qml",
        "qml/StreamList.qml",
        "qml/DevicePicker.qml",
        "qml/TextButton.qml",
        "qml/ToneSlider.qml",
        "qml/CutFrame.qml",
        "qml/Themes.qml",
        "qml/SettingsPanel.qml",
    ]))
    .file("src/bridge.rs")
    .build();

    // SoundTouch (the pitch engine EasyEffects uses) is C++, so it gets a small C shim.
    cc::Build::new().cpp(true).file("src/soundtouch_shim.cpp").compile("soundtouch_shim");
    println!("cargo:rerun-if-changed=src/soundtouch_shim.cpp");
    println!("cargo:rustc-link-lib=SoundTouch");
}
