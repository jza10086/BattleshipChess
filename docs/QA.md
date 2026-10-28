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
- 1280×720, 960×960, 720×960 and 640×480 live layouts; deployment action fit at
  720×960 and 640×480; true 3D board corners inside every viewport; projection-to-ray
  picking round trips; open/close menu and F11 full-screen round trip.
- Real final victory, both rematch requests, clean deployment state, and host exit.
- Repeated connection attempts can be canceled using the entry button or Esc.

At the battle capture, the suite prints FPS, process time, draw calls and rendered
primitives to the external test log only, never on the gameplay screen.

At the optimized full-suite 1280×720 battle checkpoint on Mesa llvmpipe software
rendering (two CPU cores), the measured values were **7 FPS**, **147.303 ms** process
time, **120 draw calls** and **13,622 primitives**. A subsequent final hit-visibility
regression capture measured **6 FPS / 161.444 ms**, with the same draw-call and
primitive counts. These are individual checkpoints, not averaged benchmarks or
performance claims for hardware GPUs. The software renderer is not a 60 FPS
environment; hardware GPU performance remains unmeasured.

After the full suite, visual review found tall ocean-liner decks occluding hit
markers. A focused real two-process native rerun verified the final elevation fix:
four friendly liner hits are above the deck, unknown enemy hit elevations stay
generic (no hidden ship-type disclosure), and only the public sunk enemy vessel
is instantiated. The corrected battle screenshot was inspected and the targeted
run reported `TARGETED_HIT_CAPTURE_RESULT PASS`; both peers closed cleanly. These
height assertions are retained in the regular native test. The full network and
victory/rematch suites were not repeated after this rendering-only fix.

The recorded native run uses the existing dot cloud desktop with Mesa software
OpenGL, not a new X server. It may report a driver V-Sync warning outside the game;
no debug messages are drawn in the game. Captures and logs are intentionally
outside the Git project. Window resize and full-screen are verified, but mobile
exports, web export (ENet is not browser-compatible), controllers and touch-only
play are not claimed as tested.
