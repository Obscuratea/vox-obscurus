//! The mixer layout the user builds, saved as JSON in ~/.config/vox-obscurus/settings.json.
//! The UI owns the settings and sends a full copy to the engine on every change.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const STRIPS: usize = 4;
pub const BUSES: usize = 5;

/// One input: a hardware source, or a virtual device programs play into ("Apps" for
/// everything, "Media" for the programs you pick).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Strip {
    pub label: String,
    /// The app bus is a virtual device we create; it has no source to pick.
    pub virtual_input: bool,
    /// PipeWire node.name of the source, empty for none.
    pub source: String,
    pub gain_db: f32,
    pub mute: bool,
    /// Which outputs this strip feeds, in bus order: A1, A2, A3, B1, B2.
    pub routes: [bool; BUSES],
    pub gate_on: bool,
    pub gate_threshold_db: f32,
    pub bass_db: f32,
    pub brightness_db: f32,
    pub pitch_semitones: f32,
}

impl Default for Strip {
    fn default() -> Self {
        Self {
            label: String::new(),
            virtual_input: false,
            source: String::new(),
            gain_db: 0.0,
            mute: false,
            routes: [false; BUSES],
            gate_on: false,
            gate_threshold_db: -45.0,
            bass_db: 0.0,
            brightness_db: 0.0,
            pitch_semitones: 0.0,
        }
    }
}

/// One output: A buses play on hardware, B buses are virtual mics other programs record from.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Bus {
    pub label: String,
    pub virtual_output: bool,
    /// PipeWire node.name of the sink for A buses, empty for none.
    pub device: String,
    pub gain_db: f32,
    pub mute: bool,
}

impl Default for Bus {
    fn default() -> Self {
        Self { label: String::new(), virtual_output: false, device: String::new(), gain_db: 0.0, mute: false }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Settings {
    pub strips: Vec<Strip>,
    pub buses: Vec<Bus>,
}

impl Default for Settings {
    fn default() -> Self {
        let strip = |label: &str, virtual_input, routes| Strip {
            label: label.into(),
            virtual_input,
            routes,
            ..Strip::default()
        };
        let bus = |label: &str, virtual_output| Bus { label: label.into(), virtual_output, ..Bus::default() };
        Self {
            strips: vec![
                // A mic goes to the virtual mic by default, apps go to your headphones.
                strip("Mic", false, [false, false, false, true, false]),
                strip("Input 2", false, [false; BUSES]),
                strip("Apps", true, [true, false, false, false, false]),
                strip("Media", true, [true, false, false, false, false]),
            ],
            buses: vec![bus("A1", false), bus("A2", false), bus("A3", false), bus("B1", true), bus("B2", true)],
        }
    }
}

impl Settings {
    /// Saved files from older or hand-edited versions may have the wrong shape; fall back
    /// to defaults for anything that doesn't match the fixed strip and bus layout.
    fn sanitized(self) -> Self {
        let defaults = Self::default();
        if self.strips.len() > STRIPS || self.buses.len() != BUSES {
            return defaults;
        }
        let mut s = self;
        // Saves from before a strip existed are shorter; new strips start from their defaults.
        s.strips.extend(defaults.strips[s.strips.len()..].iter().cloned());
        for (strip, d) in s.strips.iter_mut().zip(&defaults.strips) {
            strip.virtual_input = d.virtual_input;
            if d.virtual_input {
                // The label names the virtual device, so it can't change.
                strip.label = d.label.clone();
            }
            strip.gain_db = strip.gain_db.clamp(-60.0, 12.0);
            strip.gate_threshold_db = strip.gate_threshold_db.clamp(-80.0, 0.0);
            strip.bass_db = strip.bass_db.clamp(-12.0, 12.0);
            strip.brightness_db = strip.brightness_db.clamp(-12.0, 12.0);
            strip.pitch_semitones = strip.pitch_semitones.clamp(-12.0, 12.0);
        }
        for (bus, d) in s.buses.iter_mut().zip(&defaults.buses) {
            bus.virtual_output = d.virtual_output;
            bus.label = d.label.clone();
            bus.gain_db = bus.gain_db.clamp(-60.0, 12.0);
        }
        s
    }

    pub fn from_json(json: &str) -> Option<Self> {
        serde_json::from_str::<Self>(json).ok().map(Self::sanitized)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

fn path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("vox-obscurus").join("settings.json"))
}

pub fn load() -> Settings {
    path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|json| Settings::from_json(&json))
        .unwrap_or_default()
}

pub fn save(settings: &Settings) {
    let Some(p) = path() else { return };
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(json) = serde_json::to_string_pretty(settings) {
        let _ = std::fs::write(p, json);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn older_saves_gain_the_media_strip_and_keep_their_values() {
        let old = r#"{"strips":[{"label":"Mic","source":"quadcast","gain_db":-6.0},{"label":"Input 2"},{"label":"Apps"}],
                      "buses":[{"label":"A1"},{"label":"A2"},{"label":"A3"},{"label":"B1"},{"label":"B2"}]}"#;
        let s = Settings::from_json(old).expect("old save loads");
        assert_eq!(s.strips.len(), STRIPS);
        assert_eq!((s.strips[0].source.as_str(), s.strips[0].gain_db), ("quadcast", -6.0));
        assert_eq!(s.strips[3], Settings::default().strips[3]);
    }
}
