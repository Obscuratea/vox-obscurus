//! Per-strip voice processing: a noise gate, then a bass shelf and a brightness shelf.
//! Everything works on interleaved stereo frames at a fixed sample rate.

pub const SAMPLE_RATE: f32 = 48_000.0;

const BASS_HZ: f32 = 150.0;
const BRIGHTNESS_HZ: f32 = 4_500.0;

pub fn db_to_lin(db: f32) -> f32 {
    10f32.powf(db / 20.0)
}

/// RBJ cookbook shelf filter (shelf slope 1), transposed direct form II, one state per channel.
#[derive(Clone, Copy)]
pub struct Shelf {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    z1: [f32; 2],
    z2: [f32; 2],
}

impl Default for Shelf {
    fn default() -> Self {
        Self { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0, z1: [0.0; 2], z2: [0.0; 2] }
    }
}

impl Shelf {
    /// Recompute coefficients, keeping the filter state so changes don't click.
    pub fn set(&mut self, high: bool, freq: f32, gain_db: f32) {
        if gain_db.abs() < 0.05 {
            *self = Self { z1: self.z1, z2: self.z2, ..Self::default() };
            return;
        }
        let a = 10f32.powf(gain_db / 40.0);
        let w0 = 2.0 * std::f32::consts::PI * freq / SAMPLE_RATE;
        let (sin, cos) = w0.sin_cos();
        let alpha = sin / 2.0 * std::f32::consts::SQRT_2;
        let k = 2.0 * a.sqrt() * alpha;
        let (b0, b1, b2, a0, a1, a2) = if high {
            (
                a * ((a + 1.0) + (a - 1.0) * cos + k),
                -2.0 * a * ((a - 1.0) + (a + 1.0) * cos),
                a * ((a + 1.0) + (a - 1.0) * cos - k),
                (a + 1.0) - (a - 1.0) * cos + k,
                2.0 * ((a - 1.0) - (a + 1.0) * cos),
                (a + 1.0) - (a - 1.0) * cos - k,
            )
        } else {
            (
                a * ((a + 1.0) - (a - 1.0) * cos + k),
                2.0 * a * ((a - 1.0) - (a + 1.0) * cos),
                a * ((a + 1.0) - (a - 1.0) * cos - k),
                (a + 1.0) + (a - 1.0) * cos + k,
                -2.0 * ((a - 1.0) + (a + 1.0) * cos),
                (a + 1.0) + (a - 1.0) * cos - k,
            )
        };
        self.b0 = b0 / a0;
        self.b1 = b1 / a0;
        self.b2 = b2 / a0;
        self.a1 = a1 / a0;
        self.a2 = a2 / a0;
    }

    fn process(&mut self, ch: usize, x: f32) -> f32 {
        let y = self.b0 * x + self.z1[ch];
        self.z1[ch] = self.b1 * x - self.a1 * y + self.z2[ch];
        self.z2[ch] = self.b2 * x - self.a2 * y;
        y
    }
}

/// Noise gate: opens fast when the level crosses the threshold, holds briefly,
/// then fades out. Closes a few dB below the threshold so it doesn't chatter.
pub struct Gate {
    env: f32,
    gain: f32,
    hold: u32,
}

impl Default for Gate {
    fn default() -> Self {
        Self { env: 0.0, gain: 1.0, hold: 0 }
    }
}

fn coef(seconds: f32) -> f32 {
    (-1.0 / (seconds * SAMPLE_RATE)).exp()
}

impl Gate {
    fn process(&mut self, l: f32, r: f32, threshold: f32) -> f32 {
        let level = l.abs().max(r.abs());
        self.env = if level > self.env { level } else { self.env * coef(0.05) };
        let hold_frames = (0.1 * SAMPLE_RATE) as u32;
        if self.env > threshold {
            self.hold = hold_frames;
        } else if self.env < threshold * 0.7 && self.hold > 0 {
            self.hold -= 1;
        }
        let target = if self.hold > 0 { 1.0 } else { 0.0 };
        let c = if target > self.gain { coef(0.002) } else { coef(0.08) };
        self.gain = target + (self.gain - target) * c;
        self.gain
    }
}

/// How far a read head travels through the delay over its life.
const PITCH_SWEEP: f32 = 2048.0;
/// How far either side of its usual restart point a head may land, to match the other head.
const PITCH_SEARCH: i32 = 400;
/// How many samples are compared when matching.
const PITCH_MATCH: usize = 256;
/// Keeps the shortest delay at least 2 samples even when a head lands early.
const PITCH_MARGIN: f32 = PITCH_SEARCH as f32 + 2.0;
const PITCH_BUFFER: usize = 8192;

#[derive(Clone, Copy, Default)]
struct Head {
    delay: f32,
    /// 0..1 through the head's life; its volume follows a Hann curve over it.
    progress: f32,
}

/// Pitch shifter: two read heads move through a short delay line at the new speed, each
/// fading in and out, half a life apart. When a head restarts it lands where its waveform
/// best matches the other head's, so the two stay in phase and the crossfades don't detune.
/// Adds roughly 20-40 ms of delay while active, none at 0 semitones.
pub struct Pitch {
    buffer: Vec<[f32; 2]>,
    write: usize,
    ratio: f32,
    heads: [Head; 2],
}

impl Default for Pitch {
    fn default() -> Self {
        Self { buffer: vec![[0.0; 2]; PITCH_BUFFER], write: 0, ratio: 1.0, heads: [Head::default(); 2] }
    }
}

impl Pitch {
    pub fn set_semitones(&mut self, semitones: f32) {
        let ratio = 2f32.powf(semitones / 12.0);
        if ratio == self.ratio {
            return;
        }
        self.ratio = ratio;
        for (i, head) in self.heads.iter_mut().enumerate() {
            head.progress = i as f32 * 0.5;
        }
        self.heads = self.heads.map(|h| Head { delay: self.nominal_delay(h.progress), ..h });
    }

    /// Where a head at `progress` sits when no matching has moved it: going up in pitch the
    /// delay shrinks over its life, going down it grows.
    fn nominal_delay(&self, progress: f32) -> f32 {
        let travelled = if self.ratio > 1.0 { 1.0 - progress } else { progress };
        PITCH_MARGIN + PITCH_SWEEP * travelled
    }

    fn index(&self, delay: usize) -> usize {
        (self.write + 2 * PITCH_BUFFER - 1 - delay) % PITCH_BUFFER
    }

    /// The input `delay` samples ago, interpolated between samples.
    fn read(&self, delay: f32) -> [f32; 2] {
        let whole = delay.floor();
        let frac = delay - whole;
        let newer = self.buffer[self.index(whole as usize)];
        let older = self.buffer[self.index(whole as usize + 1)];
        [newer[0] + (older[0] - newer[0]) * frac, newer[1] + (older[1] - newer[1]) * frac]
    }

    fn mono(&self, delay: usize) -> f32 {
        let [l, r] = self.buffer[self.index(delay)];
        l + r
    }

    /// The restart delay near `nominal` whose recent waveform best matches the one at `other`.
    fn best_restart(&self, nominal: f32, other: f32) -> f32 {
        let other = other.round() as usize;
        let mut best = (f32::MIN, nominal);
        for offset in (-PITCH_SEARCH..=PITCH_SEARCH).step_by(2) {
            let candidate = nominal + offset as f32;
            let start = candidate.round() as usize;
            let (mut dot, mut energy) = (0.0, 1e-9);
            for k in 0..PITCH_MATCH {
                let x = self.mono(start + k);
                dot += x * self.mono(other + k);
                energy += x * x;
            }
            let score = dot / energy.sqrt();
            if score > best.0 {
                best = (score, candidate);
            }
        }
        best.1
    }

    fn process(&mut self, frame: [f32; 2]) -> [f32; 2] {
        self.buffer[self.write] = frame;
        self.write = (self.write + 1) % PITCH_BUFFER;
        if (self.ratio - 1.0).abs() < 1e-4 {
            return frame;
        }
        // Each sample the delay changes by (1 - ratio), so the heads read at `ratio` speed.
        let step = (self.ratio - 1.0).abs() / PITCH_SWEEP;
        let mut out = [0.0; 2];
        for i in 0..2 {
            let mut head = self.heads[i];
            head.delay += 1.0 - self.ratio;
            head.progress += step;
            if head.progress >= 1.0 {
                head.progress -= 1.0;
                head.delay = self.best_restart(self.nominal_delay(head.progress), self.heads[1 - i].delay);
            }
            self.heads[i] = head;
            let gain = (std::f32::consts::PI * head.progress).sin().powi(2);
            let sample = self.read(head.delay);
            out[0] += sample[0] * gain;
            out[1] += sample[1] * gain;
        }
        out
    }
}

#[derive(Default)]
pub struct Voice {
    bass: Shelf,
    brightness: Shelf,
    gate: Gate,
    pitch: Pitch,
}

impl Voice {
    pub fn configure(&mut self, bass_db: f32, brightness_db: f32, pitch_semitones: f32) {
        self.bass.set(false, BASS_HZ, bass_db);
        self.brightness.set(true, BRIGHTNESS_HZ, brightness_db);
        self.pitch.set_semitones(pitch_semitones);
    }

    /// `gate_threshold` is linear amplitude, or `None` with the gate off.
    pub fn process(&mut self, frame: [f32; 2], gate_threshold: Option<f32>) -> [f32; 2] {
        let g = match gate_threshold {
            Some(t) => self.gate.process(frame[0], frame[1], t),
            None => 1.0,
        };
        let mut out = [0.0; 2];
        for ch in 0..2 {
            let x = frame[ch] * g;
            out[ch] = self.brightness.process(ch, self.bass.process(ch, x));
        }
        self.pitch.process(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The strongest frequency between 50 and 1000 Hz, to the nearest Hz (Goertzel per bin).
    /// Zero-crossing counts are thrown off by the shifter's crossfades, so look at the spectrum.
    fn frequency(samples: &[f32]) -> f32 {
        let power = |freq: f32| {
            let coeff = 2.0 * (2.0 * std::f32::consts::PI * freq / SAMPLE_RATE).cos();
            let (mut s1, mut s2) = (0.0f32, 0.0f32);
            for &x in samples {
                let s0 = x + coeff * s1 - s2;
                s2 = s1;
                s1 = s0;
            }
            s1 * s1 + s2 * s2 - coeff * s1 * s2
        };
        (50..=1000).map(|f| f as f32).max_by(|a, b| power(*a).total_cmp(&power(*b))).unwrap()
    }

    fn shifted(semitones: f32) -> f32 {
        let mut pitch = Pitch::default();
        pitch.set_semitones(semitones);
        let out: Vec<f32> = (0..SAMPLE_RATE as usize)
            .map(|n| {
                let x = (2.0 * std::f32::consts::PI * 220.0 * n as f32 / SAMPLE_RATE).sin();
                pitch.process([x, x])[0]
            })
            .collect();
        frequency(&out[PITCH_BUFFER..])
    }

    #[test]
    fn pitch_moves_by_octaves() {
        assert!((shifted(12.0) - 440.0).abs() <= 2.0, "up an octave gave {}", shifted(12.0));
        assert!((shifted(-12.0) - 110.0).abs() <= 2.0, "down an octave gave {}", shifted(-12.0));
        assert!((shifted(5.0) - 293.7).abs() <= 2.0, "up a fourth gave {}", shifted(5.0));
    }

    #[test]
    fn pitch_at_zero_is_untouched() {
        let mut pitch = Pitch::default();
        assert_eq!(pitch.process([0.25, -0.5]), [0.25, -0.5]);
    }
}
