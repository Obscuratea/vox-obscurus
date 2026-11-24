use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("org.obscura.vox").qml_files([
        "qml/Main.qml",
        "qml/ChannelStrip.qml",
        "qml/ChannelRow.qml",
        "qml/MixerView.qml",
        "qml/RoutingView.qml",
        "qml/EqView.qml",
        "qml/Inspector.qml",
        "qml/Card.qml",
        "qml/Icon.qml",
        "qml/IconButton.qml",
        "qml/Toggle.qml",
        "qml/Tag.qml",
        "qml/Fader.qml",
        "qml/LevelMeter.qml",
        "qml/Chip.qml",
        "qml/Pill.qml",
        "qml/Knob.qml",
        "qml/Raised.qml",
        "qml/PeqCurve.qml",
        "qml/PeqEditor.qml",
        "qml/StreamList.qml",
        "qml/DevicePicker.qml",
        "qml/TextButton.qml",
        "qml/ToneSlider.qml",
        "qml/CutFrame.qml",
        "qml/Themes.qml",
        "qml/Glass.qml",
        "qml/SettingsPanel.qml",
        "qml/KeyCapture.qml",
        "qml/Tray.qml",
    ]))
    .file("src/bridge.rs")
    .build();

    // SoundTouch (the pitch engine EasyEffects uses) is C++, so it gets a small C shim.
    cc::Build::new().cpp(true).file("src/soundtouch_shim.cpp").compile("soundtouch_shim");
    println!("cargo:rerun-if-changed=src/soundtouch_shim.cpp");
    println!("cargo:rustc-link-lib=SoundTouch");

    // The QApplication (see qt_shim.cpp): the tray icon needs Qt Widgets.
    let mut qt = cc::Build::new();
    qt.cpp(true).file("src/qt_shim.cpp").flag_if_supported("-fPIC");
    println!("cargo:rustc-link-lib=Qt6Widgets");
    println!("cargo:rustc-link-lib=KF6WindowSystem");
    if let Ok(out) = std::process::Command::new("pkg-config").args(["--cflags", "Qt6Widgets", "Qt6Quick"]).output() {
        for flag in String::from_utf8_lossy(&out.stdout).split_whitespace() {
            qt.flag(flag);
        }
    }
    qt.flag("-I/usr/include/KF6/KWindowSystem");
    qt.compile("qt_shim");
    println!("cargo:rerun-if-changed=src/qt_shim.cpp");
}
