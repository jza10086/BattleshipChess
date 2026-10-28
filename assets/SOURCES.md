# Asset sources and licenses

This game uses actual 3D glTF models, not a raster or shader imitation of 3D.
No commercial-game rips, remote runtime downloads or third-party audio samples are used.

| Asset | Creator / source | License |
|---|---|---|
| Five playable ship models: ocean liner, cargo ship, two tugboats and speedboat | **Kenney**, Watercraft Pack 2.0; original author's [OpenGameArt upload](https://opengameart.org/content/watercraft-kit), [publisher page](https://kenney.nl/assets/watercraft-kit) | **CC0 1.0**; package notice in [`kenney-watercraft/LICENSE.txt`](kenney-watercraft/LICENSE.txt) |
| Four corner buoys per sea area, shared palette texture | Same Kenney Watercraft Pack | CC0 1.0 |
| Ocean mesh / animated water shader, submerged grid, targeting rings, flat red / blue shot-cell stencils, ship bobbing / sinking | Original Godot mesh, shader and animation work in `scripts/main.gd`, `scripts/ship_visual.gd`, `assets/shaders/` | Project MIT |
| `textures/ocean_fields.png`, `tools/generate_ocean_noise.py`, waterline ripple shader | Original deterministic seamless data texture and local-only shader work; [research and design references](../docs/OCEAN_ART.md) | Project MIT; no third-party shader/image copied |
| Placement, miss and hit sounds | Original deterministic waveform synthesis, `scripts/main.gd::_tone`; no recorded samples | Project MIT |
| `icon.svg` | Original vector drawing created for BattleshipChess | Project MIT |
| `fonts/SeaInterface.otf` | Subset of **Noto Sans CJK SC Regular**, Noto project (Google / Adobe and contributors); system source `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`, SC face 2. Renamed **Sea Interface** after subsetting. | **SIL OFL 1.1**, full notice in [`fonts/LICENSE.txt`](fonts/LICENSE.txt) |

The imported models are the principal playable fleet. Their toy-like civilian
silhouettes deliberately replace military illustrations; the familiar fleet
lengths 5 / 4 / 3 / 3 / 2 and guessing-game rules are unchanged. Runtime transforms
fit each hull into its cell footprint; the source GLBs and palette remain unchanged.

Exact download, checksum, retrieved date and included files are recorded in
[`kenney-watercraft/README.md`](kenney-watercraft/README.md). Credit is voluntary
under CC0 and included here. No endorsement by Kenney is implied.

Font upstream: https://github.com/notofonts/noto-cjk
Font license: https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE
The subset retains original copyright metadata. It includes the interface's
Chinese characters, ASCII addresses/ports and punctuation. Extend the subset when
adding new text. The font remains under OFL, not the project's MIT license.

Original code / ocean / sound work created with OpenAI Codex assistance,
2026-10-28. This independent implementation is not affiliated with a commercial
Battleship publisher.
