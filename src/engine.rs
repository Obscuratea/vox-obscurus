//! The PipeWire side. Every input strip and output bus is a PipeWire stream:
//! - hardware strips capture from a source; the Apps and Media strips record the
//!   "Vox Obscurus Apps" / "Vox Obscurus Media" devices that programs play into
//! - A buses play to a hardware sink; B buses play into the "Vox Obscurus B1/B2" virtual mics
//!
//! All streams share one node group, so PipeWire schedules them on one clock, and one link
//! group, so WirePlumber never wires them into each other (no feedback loops through us).
//! Processing runs on this thread's main loop, so the stream callbacks and the command
//! handler share the mixer without locks. Strips write processed audio into ring buffers
//! and each bus reads from them, which costs at most one graph cycle of delay.

use crate::dsp::{SAMPLE_RATE, Voice, db_to_lin};
use crate::settings::{BUSES, STRIPS, Settings};
use pipewire as pw;
use pw::properties::properties;
use pw::spa;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

const GROUP: &str = "vox-obscurus";
const OWN_PREFIX: &str = "vox_obscurus";
const APPS_DEVICE: &str = "vox_obscurus_apps";

/// The devices other programs see: a sink to play into, and the B microphones.
/// (node.name, description, media.class)
const VIRTUAL_DEVICES: [(&str, &str, &str); 4] = [
    (APPS_DEVICE, "Vox Obscurus Apps", "Audio/Sink"),
    ("vox_obscurus_media", "Vox Obscurus Media", "Audio/Sink"),
    ("vox_obscurus_b1", "Vox Obscurus B1 (Mic)", "Audio/Source/Virtual"),
    ("vox_obscurus_b2", "Vox Obscurus B2 (Mic)", "Audio/Source/Virtual"),
];
const RING: usize = 16_384;
const STRIDE: usize = 2 * std::mem::size_of::<f32>();

/// Per-sample step toward a new gain, about 10 ms to settle, so faders and mutes don't click.
fn smoothing() -> f32 {
    1.0 - (-1.0 / (0.01 * SAMPLE_RATE)).exp()
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct Device {
    pub name: String,
    pub description: String,
}

#[derive(Default, serde::Serialize)]
pub struct Devices {
    pub sources: Vec<Device>,
    pub sinks: Vec<Device>,
}

/// State the UI thread reads.
pub struct Shared {
    pub strip_peaks: [[AtomicU32; 2]; STRIPS],
    pub bus_peaks: [[AtomicU32; 2]; BUSES],
    pub devices: Mutex<Devices>,
    /// node.name -> global id of the nodes we created, so they can be made system defaults.
    pub own_nodes: Mutex<HashMap<String, u32>>,
    /// Programs currently playing into Apps/Media or recording from B1/B2, as JSON.
    pub streams: Mutex<String>,
}

impl Shared {
    fn new() -> Self {
        Self {
            strip_peaks: std::array::from_fn(|_| std::array::from_fn(|_| AtomicU32::new(0))),
            bus_peaks: std::array::from_fn(|_| std::array::from_fn(|_| AtomicU32::new(0))),
            devices: Mutex::default(),
            own_nodes: Mutex::default(),
            streams: Mutex::new("[]".into()),
        }
    }
}

// Non-negative floats order the same as their bit patterns, so fetch_max works on the bits.
fn record_peak(cell: &AtomicU32, value: f32) {
    cell.fetch_max(value.to_bits(), Ordering::Relaxed);
}

/// The loudest sample since the last call.
pub fn take_peak(cell: &AtomicU32) -> f32 {
    f32::from_bits(cell.swap(0, Ordering::Relaxed))
}

pub enum Command {
    Apply(Settings),
    /// Mute or unmute one program's stream (by PipeWire node id).
    MuteStream(u32, bool),
}

pub struct Handle {
    pub shared: Arc<Shared>,
    pub sender: Mutex<pw::channel::Sender<Command>>,
}

pub fn start(settings: Settings) -> Handle {
    let shared = Arc::new(Shared::new());
    let (sender, receiver) = pw::channel::channel();
    let thread_shared = shared.clone();
    std::thread::Builder::new()
        .name("vox-pipewire".into())
        .spawn(move || {
            if let Err(e) = run(settings, thread_shared, receiver) {
                eprintln!("vox-obscurus: PipeWire engine stopped: {e}");
            }
        })
        .expect("failed to start the audio thread");
    Handle { shared, sender: Mutex::new(sender) }
}

struct Ring {
    frames: Vec<[f32; 2]>,
    write: u64,
}

impl Ring {
    fn push(&mut self, frame: [f32; 2]) {
        self.frames[(self.write % RING as u64) as usize] = frame;
        self.write += 1;
    }

    fn get(&self, pos: u64) -> [f32; 2] {
        self.frames[(pos % RING as u64) as usize]
    }
}

struct StripState {
    voice: Voice,
    ring: Ring,
    gain: f32,
}

struct BusState {
    /// How far this bus has read into each strip's ring.
    cursors: [u64; STRIPS],
    gain: f32,
}

struct Mixer {
    settings: Settings,
    strips: Vec<StripState>,
    buses: Vec<BusState>,
    scratch: Vec<[f32; 2]>,
    /// One cycle of a strip's audio while it goes through the voice processing.
    block: Vec<[f32; 2]>,
    shared: Arc<Shared>,
}

impl Mixer {
    fn new(shared: Arc<Shared>) -> Self {
        Self {
            settings: Settings::default(),
            strips: (0..STRIPS)
                .map(|_| StripState {
                    voice: Voice::default(),
                    ring: Ring { frames: vec![[0.0; 2]; RING], write: 0 },
                    gain: 0.0,
                })
                .collect(),
            buses: (0..BUSES).map(|_| BusState { cursors: [0; STRIPS], gain: 0.0 }).collect(),
            scratch: Vec::new(),
            block: Vec::new(),
            shared,
        }
    }

    fn capture(&mut self, index: usize, bytes: &[u8]) {
        let strip = &self.settings.strips[index];
        let target = if strip.mute { 0.0 } else { db_to_lin(strip.gain_db) };
        let gate = strip.gate_on.then(|| db_to_lin(strip.gate_threshold_db));
        let state = &mut self.strips[index];
        let step = smoothing();
        let mut peak = [0f32; 2];
        self.block.clear();
        for frame in bytes.chunks_exact(STRIDE) {
            let input = [read_f32(&frame[0..4]), read_f32(&frame[4..8])];
            self.block.push(state.voice.process(input, gate));
        }
        state.voice.shift(&mut self.block);
        for voiced in &self.block {
            state.gain += (target - state.gain) * step;
            let out = [voiced[0] * state.gain, voiced[1] * state.gain];
            peak[0] = peak[0].max(out[0].abs());
            peak[1] = peak[1].max(out[1].abs());
            state.ring.push(out);
        }
        for ch in 0..2 {
            record_peak(&self.shared.strip_peaks[index][ch], peak[ch]);
        }
    }

    fn playback(&mut self, index: usize, out: &mut [u8]) {
        let n = out.len() / STRIDE;
        self.scratch.clear();
        self.scratch.resize(n, [0.0; 2]);
        for (s, strip) in self.strips.iter().enumerate() {
            if !self.settings.strips[s].routes[index] {
                continue;
            }
            let cursor = &mut self.buses[index].cursors[s];
            let write = strip.ring.write;
            // Fallen too far behind (route just turned on, or clocks drifted): skip to near live.
            if write - *cursor > (3 * n).min(RING - n) as u64 {
                *cursor = write.saturating_sub(n as u64);
            }
            // Not enough new audio yet this cycle: leave this strip out rather than repeat old audio.
            if write - *cursor < n as u64 {
                continue;
            }
            for (k, mixed) in self.scratch.iter_mut().enumerate() {
                let frame = strip.ring.get(*cursor + k as u64);
                mixed[0] += frame[0];
                mixed[1] += frame[1];
            }
            *cursor += n as u64;
        }

        let bus = &self.settings.buses[index];
        let target = if bus.mute { 0.0 } else { db_to_lin(bus.gain_db) };
        let state = &mut self.buses[index];
        let step = smoothing();
        let mut peak = [0f32; 2];
        for (frame, bytes) in self.scratch.iter().zip(out.chunks_exact_mut(STRIDE)) {
            state.gain += (target - state.gain) * step;
            let l = frame[0] * state.gain;
            let r = frame[1] * state.gain;
            peak[0] = peak[0].max(l.abs());
            peak[1] = peak[1].max(r.abs());
            bytes[0..4].copy_from_slice(&l.to_le_bytes());
            bytes[4..8].copy_from_slice(&r.to_le_bytes());
        }
        for ch in 0..2 {
            record_peak(&self.shared.bus_peaks[index][ch], peak[ch]);
        }
    }
}

fn read_f32(bytes: &[u8]) -> f32 {
    f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

#[derive(Clone, Copy)]
enum Role {
    Strip(usize),
    Bus(usize),
}

struct Live {
    // Drop the listener before the stream it listens to.
    _listener: pw::stream::StreamListener<()>,
    _stream: pw::stream::StreamRc,
}

#[derive(Default)]
struct Streams {
    strips: Vec<Option<Live>>,
    buses: Vec<Option<Live>>,
}

fn format_param() -> Vec<u8> {
    let mut info = spa::param::audio::AudioInfoRaw::new();
    info.set_format(spa::param::audio::AudioFormat::F32LE);
    info.set_rate(SAMPLE_RATE as u32);
    info.set_channels(2);
    let mut position = [0u32; spa::sys::SPA_AUDIO_MAX_CHANNELS as usize];
    position[0] = spa::sys::SPA_AUDIO_CHANNEL_FL;
    position[1] = spa::sys::SPA_AUDIO_CHANNEL_FR;
    info.set_position(position);
    let object = spa::pod::Object {
        type_: spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
        id: spa::param::ParamType::EnumFormat.as_raw(),
        properties: info.into(),
    };
    spa::pod::serialize::PodSerializer::serialize(std::io::Cursor::new(Vec::new()), &spa::pod::Value::Object(object))
        .expect("audio format serializes")
        .0
        .into_inner()
}

/// Properties for each stream. Returns None when the stream shouldn't exist yet
/// (a hardware strip or bus with no device picked).
fn stream_props(role: Role, settings: &Settings) -> Option<pw::properties::PropertiesBox> {
    let mut props = properties! {
        "media.type" => "Audio",
        "node.group" => GROUP,
        "node.link-group" => GROUP,
        "audio.position" => "FL,FR",
    };
    let target = match role {
        Role::Strip(i) => {
            let strip = &settings.strips[i];
            props.insert("media.category", "Capture");
            props.insert("node.name", format!("{OWN_PREFIX}_in{}", i + 1));
            props.insert("node.description", format!("Vox Obscurus Input {}", i + 1));
            if strip.virtual_input {
                // Record what programs play into the virtual device named after the strip.
                props.insert("stream.capture.sink", "true");
                format!("{OWN_PREFIX}_{}", strip.label.to_lowercase())
            } else {
                strip.source.clone()
            }
        }
        Role::Bus(i) => {
            let bus = &settings.buses[i];
            let label = bus.label.to_lowercase();
            props.insert("media.category", "Playback");
            props.insert("node.name", format!("{OWN_PREFIX}_out_{label}"));
            props.insert("node.description", format!("Vox Obscurus {}", bus.label));
            if bus.virtual_output {
                // WirePlumber only links playback streams to sinks, so we link this one to
                // its virtual mic ourselves (see link_virtual_mics).
                return Some(props);
            }
            bus.device.clone()
        }
    };
    if target.is_empty() {
        return None;
    }
    props.insert("target.object", target);
    props.insert("node.dont-fallback", "true");
    props.insert("node.dont-reconnect", "true");
    Some(props)
}

fn open_stream(core: &pw::core::CoreRc, mixer: &Rc<RefCell<Mixer>>, role: Role) -> Option<Live> {
    let props = stream_props(role, &mixer.borrow().settings)?;
    let linked_by_us = matches!(role, Role::Bus(i) if mixer.borrow().settings.buses[i].virtual_output);
    let name = match role {
        Role::Strip(i) => format!("vox-strip-{i}"),
        Role::Bus(i) => format!("vox-bus-{i}"),
    };
    let result = (|| {
        let stream = pw::stream::StreamRc::new(core.clone(), &name, props)?;
        let mixer = mixer.clone();
        let listener = stream
            .add_local_listener_with_user_data(())
            .process(move |stream, _| {
                let Some(mut buffer) = stream.dequeue_buffer() else { return };
                let requested = buffer.requested() as usize;
                let datas = buffer.datas_mut();
                let Some(data) = datas.first_mut() else { return };
                match role {
                    Role::Strip(i) => {
                        let offset = data.chunk().offset() as usize;
                        let size = data.chunk().size() as usize;
                        if let Some(bytes) = data.data() {
                            let end = (offset + size).min(bytes.len());
                            mixer.borrow_mut().capture(i, &bytes[offset.min(end)..end]);
                        }
                    }
                    Role::Bus(i) => {
                        let mut frames = 0;
                        if let Some(bytes) = data.data() {
                            let max = bytes.len() / STRIDE;
                            frames = if requested == 0 { max } else { requested.min(max) };
                            mixer.borrow_mut().playback(i, &mut bytes[..frames * STRIDE]);
                        }
                        let chunk = data.chunk_mut();
                        *chunk.offset_mut() = 0;
                        *chunk.stride_mut() = STRIDE as _;
                        *chunk.size_mut() = (frames * STRIDE) as _;
                    }
                }
            })
            .register()?;
        let format = format_param();
        let mut params = [spa::pod::Pod::from_bytes(&format).expect("valid format pod")];
        let direction = match role {
            Role::Strip(_) => spa::utils::Direction::Input,
            Role::Bus(_) => spa::utils::Direction::Output,
        };
        let mut flags = pw::stream::StreamFlags::MAP_BUFFERS;
        if !linked_by_us {
            flags |= pw::stream::StreamFlags::AUTOCONNECT;
        }
        stream.connect(direction, None, flags, &mut params)?;
        Ok::<_, pw::Error>(Live { _listener: listener, _stream: stream })
    })();
    result.map_err(|e| eprintln!("vox-obscurus: could not open {name}: {e}")).ok()
}

/// Take new settings; reopen only the streams whose device changed.
fn apply(core: &pw::core::CoreRc, mixer: &Rc<RefCell<Mixer>>, streams: &mut Streams, new: Settings, first: bool) {
    let old = {
        let mut m = mixer.borrow_mut();
        for (state, strip) in m.strips.iter_mut().zip(&new.strips) {
            state.voice.configure(strip.bass_db, strip.brightness_db, strip.pitch_semitones);
        }
        std::mem::replace(&mut m.settings, new.clone())
    };
    for i in 0..STRIPS {
        if first || old.strips[i].source != new.strips[i].source {
            streams.strips[i] = None;
            streams.strips[i] = open_stream(core, mixer, Role::Strip(i));
        }
    }
    for i in 0..BUSES {
        if first || old.buses[i].device != new.buses[i].device {
            streams.buses[i] = None;
            streams.buses[i] = open_stream(core, mixer, Role::Bus(i));
        }
    }
}

struct NodeInfo {
    class: String,
    device: Device,
}

/// A program's playback or recording stream, so the UI can list who is using Apps, Media, B1 and B2.
struct AppStream {
    name: String,
    /// file:// URL of the program's icon in the user's icon theme; empty when none was found.
    icon: String,
    /// True for a recording stream (reads a B mic), false for a playback stream.
    capture: bool,
    muted: bool,
    node: pw::node::Node,
    _listener: pw::node::NodeListener,
}

type AppStreams = Rc<RefCell<HashMap<u32, AppStream>>>;
/// link id -> (output node, input node)
type Routes = Rc<RefCell<HashMap<u32, (u32, u32)>>>;

const PROP_MUTE: u32 = 0x10004;

fn read_mute(pod: &spa::pod::Pod) -> Option<bool> {
    let (_, value) = spa::pod::deserialize::PodDeserializer::deserialize_any_from(pod.as_bytes()).ok()?;
    let spa::pod::Value::Object(object) = value else { return None };
    object.properties.iter().find(|p| p.key == PROP_MUTE).and_then(|p| match p.value {
        spa::pod::Value::Bool(muted) => Some(muted),
        _ => None,
    })
}

fn set_mute(stream: &AppStream, muted: bool) {
    let object = spa::pod::Object {
        type_: spa::utils::SpaTypes::ObjectParamProps.as_raw(),
        id: spa::param::ParamType::Props.as_raw(),
        properties: vec![spa::pod::Property::new(PROP_MUTE, spa::pod::Value::Bool(muted))],
    };
    let Ok((cursor, _)) = spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &spa::pod::Value::Object(object),
    ) else {
        return;
    };
    if let Some(pod) = spa::pod::Pod::from_bytes(cursor.get_ref()) {
        stream.node.set_param(spa::param::ParamType::Props, 0, pod);
    }
}

/// Work out which of our devices each program is wired to, and hand the list to the UI.
fn publish_streams(apps: &AppStreams, routes: &Routes, shared: &Shared) {
    let own = shared.own_nodes.lock().unwrap().clone();
    let id_of = |label: &str| own.get(&format!("{OWN_PREFIX}_{label}")).copied();
    let targets = [("apps", id_of("apps")), ("media", id_of("media")), ("b1", id_of("b1")), ("b2", id_of("b2"))];
    let routes = routes.borrow();
    let mut list = Vec::new();
    for (&id, stream) in apps.borrow().iter() {
        for &(output, input) in routes.values() {
            let (mine, other) = if stream.capture { (input, output) } else { (output, input) };
            if mine != id {
                continue;
            }
            if let Some((label, _)) = targets.iter().find(|(_, node)| *node == Some(other)) {
                list.push(serde_json::json!({ "id": id, "name": stream.name, "icon": stream.icon, "target": label, "muted": stream.muted }));
                break;
            }
        }
    }
    list.sort_by_key(|item| (item["name"].as_str().unwrap_or_default().to_lowercase(), item["id"].as_u64()));
    *shared.streams.lock().unwrap() = serde_json::Value::Array(list).to_string();
}

struct PortInfo {
    node: u32,
    output: bool,
    channel: String,
}

/// Connect each B bus stream to its virtual mic, channel by channel, once both sides' ports exist.
fn link_virtual_mics(
    core: &pw::core::CoreRc,
    shared: &Shared,
    ports: &HashMap<u32, PortInfo>,
    links: &mut HashMap<(u32, u32), pw::link::Link>,
) {
    let own = shared.own_nodes.lock().unwrap();
    for label in ["b1", "b2"] {
        let (Some(&from), Some(&to)) =
            (own.get(&format!("{OWN_PREFIX}_out_{label}")), own.get(&format!("{OWN_PREFIX}_{label}")))
        else {
            continue;
        };
        for (&out_port, out) in ports.iter().filter(|(_, p)| p.node == from && p.output) {
            let Some((&in_port, _)) = ports.iter().find(|(_, p)| p.node == to && !p.output && p.channel == out.channel)
            else {
                continue;
            };
            if links.contains_key(&(out_port, in_port)) {
                continue;
            }
            let link = core.create_object::<pw::link::Link>(
                "link-factory",
                &properties! {
                    "link.output.node" => from.to_string(),
                    "link.output.port" => out_port.to_string(),
                    "link.input.node" => to.to_string(),
                    "link.input.port" => in_port.to_string(),
                },
            );
            match link {
                Ok(link) => {
                    links.insert((out_port, in_port), link);
                }
                Err(e) => eprintln!("vox-obscurus: could not link {label}: {e}"),
            }
        }
    }
}

fn publish_devices(nodes: &HashMap<u32, NodeInfo>, shared: &Shared) {
    let mut devices = Devices::default();
    for node in nodes.values() {
        match node.class.as_str() {
            "Audio/Sink" => devices.sinks.push(node.device.clone()),
            _ => devices.sources.push(node.device.clone()),
        }
    }
    devices.sources.sort_by(|a, b| a.description.cmp(&b.description));
    devices.sinks.sort_by(|a, b| a.description.cmp(&b.description));
    *shared.devices.lock().unwrap() = devices;
}

fn run(settings: Settings, shared: Arc<Shared>, receiver: pw::channel::Receiver<Command>) -> Result<(), pw::Error> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_rc(None)?;

    // Track the devices the user can pick, the ids of our own nodes, and ports for the B links.
    let nodes: Rc<RefCell<HashMap<u32, NodeInfo>>> = Rc::default();
    let ports: Rc<RefCell<HashMap<u32, PortInfo>>> = Rc::default();
    let links: Rc<RefCell<HashMap<(u32, u32), pw::link::Link>>> = Rc::default();
    let apps: AppStreams = Rc::default();
    let routes: Routes = Rc::default();
    let registry = core.get_registry_rc()?;
    let _registry_listener = registry
        .add_listener_local()
        .global({
            let nodes = nodes.clone();
            let ports = ports.clone();
            let links = links.clone();
            let shared = shared.clone();
            let core = core.clone();
            let apps = apps.clone();
            let routes = routes.clone();
            let registry = registry.clone();
            move |global| {
                let Some(props) = global.props else { return };
                if global.type_ == pw::types::ObjectType::Link {
                    let end = |key| props.get(key).and_then(|id| id.parse::<u32>().ok());
                    if let (Some(output), Some(input)) = (end("link.output.node"), end("link.input.node")) {
                        routes.borrow_mut().insert(global.id, (output, input));
                        publish_streams(&apps, &routes, &shared);
                    }
                    return;
                }
                if global.type_ == pw::types::ObjectType::Port {
                    let node = props.get("node.id").and_then(|id| id.parse().ok());
                    let (Some(node), Some(direction), Some(channel)) =
                        (node, props.get("port.direction"), props.get("audio.channel"))
                    else {
                        return;
                    };
                    let info = PortInfo { node, output: direction == "out", channel: channel.to_string() };
                    ports.borrow_mut().insert(global.id, info);
                    link_virtual_mics(&core, &shared, &ports.borrow(), &mut links.borrow_mut());
                    return;
                }
                if global.type_ != pw::types::ObjectType::Node {
                    return;
                }
                let name = props.get("node.name").unwrap_or_default();
                if name.starts_with(OWN_PREFIX) {
                    shared.own_nodes.lock().unwrap().insert(name.to_string(), global.id);
                    return;
                }
                let class = props.get("media.class").unwrap_or_default();
                if matches!(class, "Stream/Output/Audio" | "Stream/Input/Audio") {
                    let label = props
                        .get("application.name")
                        .or_else(|| props.get("node.description"))
                        .unwrap_or(name);
                    let Ok(node) = registry.bind::<pw::node::Node, _>(global) else { return };
                    let id = global.id;
                    let listener = node
                        .add_listener_local()
                        // The registry's copy of the properties lacks the icon, so read it from the node itself.
                        .info({
                            let apps = apps.clone();
                            let routes = routes.clone();
                            let shared = shared.clone();
                            move |info| {
                                let Some(props) = info.props() else { return };
                                let icon_name = props
                                    .get("application.icon-name")
                                    .or_else(|| props.get("application.icon_name"))
                                    .or_else(|| props.get("application.process.binary"))
                                    .unwrap_or_default()
                                    .to_lowercase();
                                // Later updates can come without these properties; keep what we found.
                                if icon_name.is_empty() {
                                    return;
                                }
                                let icon = crate::icons::lookup(&icon_name);
                                let changed = apps.borrow_mut().get_mut(&id).is_some_and(|stream| {
                                    let changed = stream.icon != icon;
                                    stream.icon = icon;
                                    changed
                                });
                                if changed {
                                    publish_streams(&apps, &routes, &shared);
                                }
                            }
                        })
                        .param({
                            let apps = apps.clone();
                            let routes = routes.clone();
                            let shared = shared.clone();
                            move |_, _, _, _, pod| {
                                let Some(muted) = pod.and_then(read_mute) else { return };
                                if let Some(stream) = apps.borrow_mut().get_mut(&id) {
                                    stream.muted = muted;
                                }
                                publish_streams(&apps, &routes, &shared);
                            }
                        })
                        .register();
                    node.subscribe_params(&[spa::param::ParamType::Props]);
                    let stream = AppStream {
                        name: label.to_string(),
                        icon: String::new(),
                        capture: class == "Stream/Input/Audio",
                        muted: false,
                        node,
                        _listener: listener,
                    };
                    apps.borrow_mut().insert(id, stream);
                    publish_streams(&apps, &routes, &shared);
                    return;
                }
                if !matches!(class, "Audio/Source" | "Audio/Source/Virtual" | "Audio/Sink") {
                    return;
                }
                let description =
                    props.get("node.description").or_else(|| props.get("node.nick")).unwrap_or(name);
                nodes.borrow_mut().insert(
                    global.id,
                    NodeInfo {
                        class: class.to_string(),
                        device: Device { name: name.to_string(), description: description.to_string() },
                    },
                );
                publish_devices(&nodes.borrow(), &shared);
            }
        })
        .global_remove({
            let nodes = nodes.clone();
            let shared = shared.clone();
            let apps = apps.clone();
            let routes = routes.clone();
            move |id| {
                let gone_stream = apps.borrow_mut().remove(&id).is_some();
                let gone_link = routes.borrow_mut().remove(&id).is_some();
                if gone_stream || gone_link {
                    publish_streams(&apps, &routes, &shared);
                }
                if nodes.borrow_mut().remove(&id).is_some() {
                    publish_devices(&nodes.borrow(), &shared);
                }
                shared.own_nodes.lock().unwrap().retain(|_, own| *own != id);
                if ports.borrow_mut().remove(&id).is_some() {
                    links.borrow_mut().retain(|&(out, input), _| out != id && input != id);
                }
            }
        })
        .register();

    // Created on the server (like EasyEffects does), and removed when we disconnect. They get no
    // link group, so WirePlumber is free to connect our streams to them.
    let _virtual_devices = VIRTUAL_DEVICES
        .iter()
        .map(|(name, description, class)| {
            core.create_object::<pw::node::Node>(
                "adapter",
                &properties! {
                    "factory.name" => "support.null-audio-sink",
                    "node.name" => *name,
                    "node.description" => *description,
                    "media.class" => *class,
                    "audio.position" => "FL,FR",
                    // So the system volume (on the Apps device) also turns the Apps strip down.
                    "monitor.channel-volumes" => "true",
                },
            )
        })
        .collect::<Result<Vec<_>, _>>()?;

    let mixer = Rc::new(RefCell::new(Mixer::new(shared)));
    let streams = Rc::new(RefCell::new(Streams {
        strips: (0..STRIPS).map(|_| None).collect(),
        buses: (0..BUSES).map(|_| None).collect(),
    }));
    apply(&core, &mixer, &mut streams.borrow_mut(), settings, true);

    let _commands = receiver.attach(mainloop.loop_(), {
        let core = core.clone();
        let apps = apps.clone();
        move |command| match command {
            Command::Apply(settings) => apply(&core, &mixer, &mut streams.borrow_mut(), settings, false),
            Command::MuteStream(id, muted) => {
                if let Some(stream) = apps.borrow().get(&id) {
                    set_mute(stream, muted);
                }
            }
        }
    });

    mainloop.run();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Feed a steady tone through strip 0 the way PipeWire does (256-frame cycles) with pitch on:
    /// every cycle must add exactly one cycle of audio to the strip's ring (so the buses never
    /// starve), and after the shifter's start-up delay the strip must be playing the tone.
    #[test]
    fn strip_with_pitch_keeps_a_steady_supply_of_sound() {
        let mut mixer = Mixer::new(Arc::new(Shared::new()));
        mixer.settings = Settings::default();
        mixer.strips[0].voice.configure(0.0, 0.0, 3.5);
        let mut loud_cycles = 0;
        for cycle in 0..400 {
            let mut bytes = Vec::new();
            for n in 0..256 {
                let t = (cycle * 256 + n) as f32 / SAMPLE_RATE;
                let x = 0.4 * (2.0 * std::f32::consts::PI * 180.0 * t).sin();
                bytes.extend_from_slice(&x.to_le_bytes());
                bytes.extend_from_slice(&x.to_le_bytes());
            }
            let before = mixer.strips[0].ring.write;
            mixer.capture(0, &bytes);
            assert_eq!(mixer.strips[0].ring.write - before, 256, "cycle {cycle} didn't supply a full cycle of audio");
            let ring = &mixer.strips[0].ring;
            let last: f32 = (0..256).map(|k| ring.get(ring.write - 256 + k)[0].abs()).fold(0.0, f32::max);
            if cycle > 100 && last > 0.05 {
                loud_cycles += 1;
            }
        }
        assert_eq!(loud_cycles, 299, "the shifted tone dropped out in {} cycles", 299 - loud_cycles);
    }
}
