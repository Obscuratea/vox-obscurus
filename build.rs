use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("org.obscura.vox").qml_files([
        "qml/Main.qml",
        "qml/StripCard.qml",
        "qml/BusRow.qml",
        "qml/Fader.qml",
        "qml/LevelMeter.qml",
        "qml/Chip.qml",
        "qml/DevicePicker.qml",
        "qml/TextButton.qml",
        "qml/ToneSlider.qml",
    ]))
    .file("src/bridge.rs")
    .build();
}
