# Pixiball pitch haptics

This directory keeps baseball meaning separate from controller hardware.
Gameplay and prediction models emit semantic dictionaries; the composer turns
them into bounded left/right timelines; the director schedules those timelines
through a selected backend.

```gdscript
var haptics := PixiballHapticDirector.new()
add_child(haptics)

var started := haptics.play_kind("corner_paint", {
    "pitch_serial": 14,
    "event_time_sec": 0.91,
    "plate_side": -1.0, # Player-view left.
    "corner_proximity": 0.96,
    "zone_probability": 0.82,
    "confidence": 0.91,
})
```

The seven cue kinds are `release`, `tunnel`, `frontdoor`, `backdoor`,
`corner_paint`, `called_k`, and `swinging_k`. Horizontal values use player
screen space (`-1` left, `+1` right), and prediction fields are normalized to
`0..1`. `PixiballPitchFeedback.describe_schema()` returns the machine-readable
contract.

`HapticDirector.play_feedback()`, `play_kind()`, `stop_all()`, and settings
methods return semantic lifecycle events. `drain_events()` returns queued
events, while `diagnostic_state()` reports the selected device, capabilities,
active cues, gain, last output, and backend diagnostics. Runtime code may let
the node process normally; tests and agent scenarios can disable processing and
call `advance(delta)` at an exact timestep.

Backends:

- `GodotRumbleBackend` calls `Input.start_joy_vibration`. It maps semantic left
  predominantly to Godot's strong/low-frequency channel and semantic right
  predominantly to the weak/high-frequency channel, with 14% crossfeed. This
  makes frontdoor/backdoor and corner cues distinguishable on standard rumble
  hardware, but it is a frequency-encoded hint rather than physical left/right
  localization. On an official DualSense or DualSense Edge handled by SDL's PS5
  driver, the same backend also maps sufficiently directional samples to short,
  quantized L2/R2 vibration effects. A frontdoor/backdoor sweep can therefore
  move between the physical triggers while portable body rumble remains active.
  Diagnostics report both paths, including accepted and failed native sends.
- `RecordingBackend` captures every sample and stop request without hardware.
- `NullBackend` safely discards output.

In auto-select mode the director chooses the first connected controller that
reports vibration support, avoiding virtual or input-only devices when another
usable pad is present. Explicit `select_device(id)` selection is still honored.

## Controller layout

The project input map supports both keyboard and SDL-standard controllers:

| Gameplay action | Keyboard | Gamepad |
| --- | --- | --- |
| Aim / move | W A S D | Left stick or d-pad |
| Pitch / swing / confirm | Space | R2 / right trigger |
| Pitch 1–4 / throw home–third | 1–4 | Cross/A, Circle/B, Triangle/Y, Square/X |
| Pitch 5 | 5 | R1 / RB |
| Cycle fielder | Q | L1 / LB |
| Start / title confirm | Enter | Options/Menu or Cross/A |
| Restart | R | Create/View/Back |
| Lighting mood | M | R3 |

The primary action intentionally uses the right trigger instead of a face
button. Pitch selection and primary are evaluated in the same ready-state tick;
sharing Cross/A would select a pitch and immediately throw it.

## DualSense boundary

This fork adds a narrow native API:

```gdscript
if Input.has_joy_adaptive_triggers(device_id):
    Input.set_joy_adaptive_trigger_effect(
        device_id,
        Input.JOY_ADAPTIVE_TRIGGER_RIGHT,
        Input.JOY_ADAPTIVE_TRIGGER_EFFECT_VIBRATION,
        3, # Start control position, 0..9.
        0, # Unused by vibration mode.
        6, # Amplitude, 0..8.
        110, # Frequency, 0..255 Hz.
    )

# Always restore both triggers after a bounded cue.
Input.stop_joy_adaptive_triggers(device_id)
```

Only the official `OFF`, `FEEDBACK`, `WEAPON`, and `VIBRATION` trigger modes are
exposed. Every position, strength, amplitude, and frequency is validated before
the SDL driver receives a 47-byte common effect state. Game scripts cannot send
raw HID data. SDL's in-tree PS5 driver continues to own USB/Bluetooth report
selection, CRC generation, enhanced-mode negotiation, queueing, and device I/O.
Capability detection is intentionally restricted to Sony vendor ID `0x054c`
with DualSense `0x0ce6` or DualSense Edge `0x0df2`; repeated native send failures
disable the capability until reconnect while ordinary rumble continues.

This path gives real left/right *trigger* locality, so supported-device
diagnostics report `spatial_scope=left_right_triggers`. It does not claim that
the two body actuators reproduce a spatial waveform. DualSense voice-coil PCM,
controller audio-device association, and speaker routing remain unsupported and
are reported as `advanced_body_haptics=false`. Those features need a separate
audio output layer and hardware validation, not raw HID packets.

All cues are capped at 0.60 seconds, 0.95 peak amplitude, and 0.34
amplitude-seconds of energy. Accessibility gain clamps to `0..1`; disabling,
zero gain, focus loss, selected-device disconnect, backend changes, and leaving
the scene tree all stop output synchronously.

Run the hardware-independent suite from the repository root:

```sh
bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://presentation/haptics/tests/test_haptics.gd

bin/godot.macos.editor.dev.arm64 --headless --path games/pixiball \
  --script res://gameplay/tests/test_controller_input.gd
```
