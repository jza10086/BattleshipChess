# Ocean art direction and implementation

Researched on 2026-10-28. The ocean remains a full-frame, opaque 3D surface, but
is no longer a nearly constant turquoise plane. Its calm low-poly treatment is
chosen to leave the Kenney hulls, grid lines and red/blue shot cells readable.

## Primary examples studied

| Author / example | Technique studied | What this project uses |
|---|---|---|
| [NekotoArts — Wind Waker Water (Godot)](https://godotshaders.com/shader/wind-waker-water-no-textures-needed/) | Two water colors, broken light foam and vertex waves without a depth texture | Broad teal/cyan fields and sparse mint accents; **not** its dense interconnected foam or expensive procedural implementation |
| [Roystan — Toon Water (Unity)](https://roystan.net/articles/toon-water/) | Scrolling/distorted noise and thresholded foam | Two slowly crossing noise layers and anti-aliased, interrupted crest accents; **not** its depth/normal-based shoreline foam |
| [Catlike Coding — Waves](https://catlikecoding.com/unity/tutorials/flow/waves/) | Crossing wave directions and analytical surface derivatives | Two small vertex waves and analytical fragment normals; no Unity or Gerstner code copied |
| [Thomas ten Cate / Frozen Fractal — Making waves (Godot)](https://frozenfractal.com/blog/2024/5/31/around-the-world-15-making-waves/) | Moving beyond a single corrugated sine wave using crossed waves and analytic normals | Crossed low-frequency swells rather than one repeating stripe direction |
| [Godot 4.7 spatial shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html) | Spatial shader built-ins, normal coordinate space, alpha pipeline | World-XZ sampling, view-space normals and an opaque ocean; no ALPHA write in the ocean shader |

These are **design references, not imported shader assets**. All shader code and
the small noise texture are original project work under the project MIT license.
No reference screenshots, tutorial text, sample meshes or third-party shader code
are distributed. For clarity, the NekotoArts code is offered as CC0 (not its
screenshots); [Roystan's example repository is Unlicense](https://github.com/IronWarrior/ToonWaterShader/blob/master/LICENSE);
[Catlike Coding code is MIT-0, while tutorial text/images have a separate CC BY-NC-SA license](https://catlikecoding.com/unity/tutorials/license/).
No reuse license is assumed for the Frozen Fractal article or its illustrations.

## Render budget and legibility

- `assets/textures/ocean_fields.png` is a deterministic, seamless 256 × 256 RGB
  data texture: broad currents, medium breakup and smaller ripple variation.
  Rebuild with `python3 tools/generate_ocean_noise.py` (Pillow is a development-only
  dependency). The texture has mipmaps and filtered repeating sampling.
- The opaque shader makes **two texture samples**, no loops, no scene-depth or
  screen texture reads, no SSR/refraction and no Forward+ requirement. Larger
  teal/cyan patches imply depth **artistically**; they do not represent hidden
  ships, a simulated seabed or gameplay information.
- Two crossing analytic normals make directional light move over the surface.
  Diffuse-only Lambert lighting avoids costly water specular highlights while
  retaining the fleet’s real shadows.
  A restrained stepped color layer echoes the low-poly models. Sparse derivative-
  softened mint crest accents move in a third, slightly different direction.
- Ocean mesh subdivision remains unchanged. Vertical displacement is bounded by
  ±0.013 around y=-0.055, so its highest point (-0.042) stays below waterline
  effects (-0.018), grid geometry (0.010–0.018) and shot planes (0.025).
  The grid, shot marks and picking plane do not move with the water.
- `waterline.gd` makes one local quad per **instantiated visible hull or buoy**.
  Short broken capsule rings suggest stationary contact, not long moving wakes.
  Ship effects follow preview translation/rotation but stay at water height.
  Sunk-ship ripples dim; no outline floats above the sinking hull.
- Waterline quads remain depth-tested and unshaded; public shot stencils retain
  their existing priority and through-hull readability. No raised arrows, HUD,
  extra buttons or gameplay changes were introduced.

## Hidden-information boundary

The ocean shader has only a noise sampler and color uniforms. It receives no
ship positions. The local waterline shader has only `footprint`, `patch_size`,
`phase`, `opacity` and `foam_color`, all belonging to its parent visible object.
A ship's effect is created inside `ShipVisual.setup`; the existing scene creates
opponent `ShipVisual` nodes only for public sunk ships, or after game over.
Buoy effects are children of their board and inherit its visibility. Removing a
visible ship/board removes its waterline too; there is no separate position cache
that could retain hidden fleet data. `rules.gd` and `network.gd` are untouched.

See [QA.md](QA.md) for the exact tested engine, native captures, software-renderer
comparison and limitations. Rendering motion offline at a fixed step is visual
verification, not a claim that the software desktop renders at that frame rate.
