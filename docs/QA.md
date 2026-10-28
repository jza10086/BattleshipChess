# Verification

## Automated rules and real network tests

Run from the project directory with a Godot 4.x binary:

```sh
GODOT_BIN=/path/to/godot ./tests/run_tests.sh
```

The aggregate command imports the project, checks the import log for script errors,
runs the deterministic rules suite, and starts genuinely separate localhost ENet
processes. It creates a unique temporary directory for logs and writable Godot
user/cache/config data. Python 3 is required for the process coordinator. The
network runner caps each scenario at 32 seconds and terminates hung children.
No production AI, fake network snapshots, or direct referee mutations are used.
Test-only scripts submit ordinary player intentions through the production API.

For just the real-process integration suite:

```sh
python3 tests/run_network_tests.py --godot /path/to/godot
```

### Rules coverage

- Seeded generation of 200 fleets, each valid and containing exactly 17 distinct cells.
- Both orientations, exact edges, overlapping and out-of-bounds placements.
- Touching vessels intentionally accepted, fixed lengths 5 / 4 / 3 / 3 / 2.
- Malformed coordinates, non-Boolean orientation, wrong lengths and invalid players.
- Input and snapshot copies cannot mutate the authoritative fleet or shot history.
- A player cannot move a fleet after readiness, or shoot before both players are ready.
- A valid hit **and** a valid miss switch the turn; invalid, duplicate and out-of-turn
  shots do not change state or consume the turn.
- Sinking, exactly 17 successful hits, final victory, and no shots after victory.
- Both rematch votes required; new round clears fleets, shots, readiness, votes and
  opponent disclosure. Starting player alternates by round.

### Real-process integration coverage

The match scenario starts a host and guest, with deliberately different fleet
layouts (horizontal host, vertical guest), plus separate full-lobby and midgame
rejection probes. It checks:

- Native ENet handshake, per-recipient state, readiness, live shot replication.
- Exactly 33 alternating shots: 17 host hits and 16 guest misses.
- Sinking all five ships, victory, both rematch votes, clean new-round state.
- All 34 public battle/finished snapshots identical between the actual peers.
- Every live state uses a field allowlist; no opponent fleet appears before game
  over, and each disclosed sunk-ship cell was already a public hit.
- Each process receives its own **distinct** submitted fleet, not the other player's.
- Malformed ready packets, malformed shot payloads, out-of-turn fire, invalid
  coordinates and duplicate shots cannot change the expected progression.
- Third peers rejected both before and during battle receive **zero snapshots**.
- Host departure clears client connection and local state.

A second real-process scenario has the guest leave an active match. The host
stays available but clears the round, preventing a later guest from inheriting
any previous player's fleet or readiness.

### Recorded results

- Engine: Godot **4.7.2.stable.official.ed1daf0bf**.
- Date: **2026-10-28** (UTC).
- **529 deterministic rule checks** and **1,851 real-process network checks** passed with no script errors.
- Both network scenarios passed. The final native desktop run also reported
  `NATIVE_UI_RESULT PASS`, including the complete match/rematch, 3D projection/picking,
  cancellation, four window sizes and F11 checks described below.

### Scope and limitations

These are actual local UDP/ENet processes, not evidence of Internet/NAT traversal,
router configuration, or connectivity between arbitrary physical machines. No
relay, matchmaking server or NAT hole-punching service is included. A reachable
host IP and permitted UDP port are required. Host-side authority prevents client
rule manipulation but the host process must know both fleets to referee; this is
not a cryptographic anti-cheat system against a malicious host.

## Native desktop rendering and input

`tests/native_capture.gd` is a bounded native-window run. It opens the normal
**Node3D / Camera3D** main scene, clicks and drags the actual controls and projected
grids via Godot input events, and launches
`tests/native_peer.gd` as a separate headless ENet participant. Both scripts live
only under `tests/`; no test driver runs in the normal game. Fleet locations and
shot choices are deterministic test-player intentions, not forged snapshots or
a visual fixture. Captures come from the rendered viewport.

On an existing graphical desktop (not `--headless`):

```sh
BATTLE_CAPTURE_DIR=/absolute/path/to/screenshots \
  godot --path . --rendering-method gl_compatibility \
  --script res://tests/native_capture.gd
```

The native suite has a 180-second deadline with peer cleanup. It uses UDP port
19777 for its actual match and 19778 for canceled connection attempts. Run it only when these ports are unused. It verifies:

- Entry, real host creation, second-process handshake, and a valid editable default fleet.
- Keyboard selection, R/right-click rotation, projected-grid placement, actual drag /
  repeat-drag repositioning, and moving across a vessel's previous own footprint.
- Readiness is hidden while a vessel preview is selected; invalid placement cannot
  replace the saved fleet or expose readiness; Escape restores the saved valid
  fleet and its ready action.
- No hidden enemy vessel meshes instantiated before any sinking; exactly one mesh
  after one enemy vessel sinks, then none again on rematch. Network privacy is
  independently covered by the real-process snapshot tests above.
- Live hit, miss, sink and duplicate rejection; placement controls disappear in battle.
- One horizontal plane per public shot, centered on its cell at y=0.025; blue
  misses and red own/enemy/sunk hits. No arrow, flame or raised hit geometry.
- 1280×720, 960×960, 720×960 and 640×480 live layouts; deployment action fit at
  720×960 and 640×480; true 3D board corners inside every viewport; projection-to-ray
  picking round trips; open/close menu and F11 full-screen round trip.
- Real final victory, both rematch requests, clean deployment state, and host exit.
- Repeated connection attempts can be canceled using the entry button or Esc.

At the battle capture, the suite prints FPS, process time, draw calls and rendered
primitives to the external test log only, never on the gameplay screen.

Before the flat-cell marker update, at the full-suite 1280×720 battle checkpoint on Mesa llvmpipe software
rendering (two CPU cores), the measured values were **7 FPS**, **147.303 ms** process
time, **120 draw calls** and **13,622 primitives**. A subsequent final hit-visibility
regression capture measured **6 FPS / 161.444 ms**, with the same draw-call and
primitive counts. These are individual checkpoints, not averaged benchmarks or
performance claims for hardware GPUs. The software renderer is not a 60 FPS
environment; hardware GPU performance remains unmeasured.

The latest rendering-only update replaces raised hit geometry and pale miss rings
with flat red/blue cell stencils. A focused real two-process native run on
2026-10-28 passed marker counts, plane-only geometry, grid placement and colors,
duplicate-shot rejection, and hidden-enemy checks. Both 1280×720 and 720×960
captures were inspected: four friendly liner hits remain legible through the
hull, blue misses are distinct, and the only revealed enemy vessel is already
sunk with its cells still red. The depth-disabled translucent stencil is limited
to public shot cells and never samples enemy fleet data. The native run reported
`FLAT_SHOT_CAPTURE_RESULT PASS` and both peers closed cleanly. These marker
assertions replace the obsolete height checks in the regular native test.

Godot 4.7.2 import and all 529 deterministic rule checks were rerun successfully.
The full network and victory/rematch suites were not repeated for this cosmetic
change; `rules.gd` and `network.gd` are unchanged.

The recorded native run uses the existing dot cloud desktop with Mesa software
OpenGL, not a new X server. It may report a driver V-Sync warning outside the game;
no debug messages are drawn in the game. Captures and logs are intentionally
outside the Git project. Window resize and full-screen are verified, but mobile
exports, web export (ENet is not browser-compatible), controllers and touch-only
play are not claimed as tested.

## Layered ocean regression (2026-10-28)

The ocean update adds an original noise texture and shaders; the referee and
network scripts remain byte-for-byte unchanged. Run the focused test on an
existing graphical desktop:

```sh
BATTLE_CAPTURE_DIR=/absolute/path/to/ocean-captures \
  godot --path . --rendering-method gl_compatibility \
  --script res://tests/ocean_capture.gd
```

It uses the same separate real ENet peer and unused UDP port 19777 as the native
suite. It exercises actual placement/ready/fire/leave intentions, not forged game
state. In addition to the existing flat-shot assertions, it verifies:

- No opponent hull or waterline before a public sink; exactly one afterward.
- Ocean and waterline shader uniform allowlists contain no fleet/position arrays.
- One local waterline per visible hull, four buoy waterlines per board; a lifted
  preview stays at sea height and Escape restores its saved placement.
- Wave height stays strictly below waterlines, stable grid and planar shot cells.
- Opaque ocean does not use screen/depth textures; no Forward+ dependency.
- Blue misses, red own/enemy hits and sunk-cell marks remain horizontal planes.
- 1280×720 and 720×960 native captures; portrait projection/picking round trips.
- Leaving destroys the revealed enemy waterline and hides enemy buoy ripples;
  the separate peer exits cleanly.

Godot 4.7.2 import and **529 deterministic rule checks** passed. The final focused
native run reports `OCEAN_CAPTURE_RESULT PASS`, with no shader/script errors.
The full unchanged network, victory/rematch and F11 suites were not rerun for this
cosmetic update; their earlier results above must not be read as a new full pass.

For a six-second rendered motion sample, add `--fixed-fps 20` and the environment
variable `OCEAN_CAPTURE_MOTION=1`. The native test saves 120 consecutive viewport
frames and checks that a hull-free open-water pixel region changes. Fixed-step
capture is an offline visual test, **not** evidence of real-time 20 FPS performance.
The recorded motion run also reports `OCEAN_CAPTURE_RESULT PASS`: all 120 frames
were saved, and its open-water change metric was 176.392 (threshold > 10).
The six-second, 20 FPS GIF is encoded from these actual frames, not generated art
or interpolation.
Captures, the original-shader comparison fixture and logs stay outside the repo.

### Software-renderer comparison

Same 1280×720 scene, same process, same two CPU cores and `LP_NUM_THREADS=2`,
Godot 4.7.2 Compatibility on Mesa llvmpipe. The external comparison alternates
old / new / new / old, restoring the original ocean shader and hiding only the
new waterline quads for the old variant. Each block warms for 12 frames and then
samples 32 process-time values. Final diffuse-only water results:

| Block | Median process time | Min–max | Checkpoint FPS |
|---|---:|---:|---:|
| Old ocean 1 | 292.108 ms | 161.641–574.322 ms | 4 |
| New ocean 1 | 188.643 ms | 175.440–217.255 ms | 5 |
| New ocean 2 | 190.857 ms | 179.851–251.447 ms | 6 |
| Old ocean 2 | 172.899 ms | 158.838–604.502 ms | 2 |

A separate original-ocean baseline median was 166.392 ms; the final new shader's
pre-comparison checkpoint was 176.253 ms. The cloud software renderer has large
scheduling/driver variation, so this is a **small diagnostic sample**, not a
precise speedup/regression estimate or a claim of unchanged performance. The new
water increases this identical scene from **93 to 107 draw calls** and **12,090 to
12,118 primitives**; the ocean mesh itself is unchanged. Hardware GPU performance
is unmeasured. No real-time 20/60 FPS claim is made.
