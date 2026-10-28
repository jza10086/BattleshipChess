# Asset sources and licenses

All game art was made for this project. There are no ripped sprites, commercial
board-game illustrations, third-party sound samples, remote runtime assets, or
AI-generated raster assets.

| Asset | Creator / source | License |
|---|---|---|
| Edge-to-edge ocean currents, contour lines, compass, grid and coordinates | Original procedural Godot drawing, `scripts/main.gd` | Project MIT |
| Five top-view vessel designs (carrier, battleship, cruiser, submarine, destroyer) | Original polygon / primitive artwork, `scripts/main.gd::_draw_ship` | Project MIT |
| Placement ghost, targeting reticle, hit markers, miss ripples and sink presentation | Original procedural drawing / animation, `scripts/main.gd` | Project MIT |
| Placement, water impact and hit sounds | Original deterministic waveform synthesis, `scripts/main.gd::_tone`; no recorded samples | Project MIT |
| `icon.svg` | Original vector drawing created for BattleshipChess | Project MIT |
| `fonts/SeaInterface.otf` | Subset of **Noto Sans CJK SC Regular**, Noto project (Google / Adobe and contributors). System package source: `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`, SC face index 2. Renamed to **Sea Interface** after subsetting. | SIL Open Font License 1.1; full notice in `fonts/LICENSE.txt` |

Font upstream: https://github.com/notofonts/noto-cjk

Verified upstream font license:
https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE

The font retains original copyright metadata. Only the characters needed by the
Chinese interface, ASCII addresses/ports, and punctuation are bundled. The font
remains under OFL, not the project's MIT license. If adding interface text, extend
the subset or replace it with a complete appropriately licensed CJK font.

Art / audio authorship: original project work created with OpenAI Codex assistance,
2026-10-28. Asset ownership follows the project license, not the classic game's
branding. This is an independent implementation of the familiar naval guessing
rules and is not affiliated with a commercial Battleship publisher.
