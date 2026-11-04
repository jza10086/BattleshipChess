# 正式资源来源

- `yamato/`：本项目原创 Blender 大和号完好和损毁模型。两个 GLB 共用棋盘坐标、舰首方向和水线，仅导出舰体集合。
- `fleet/`：本项目原创 Blender 福特号、企业号、贝尔法斯特号、基德号及各自的损毁模型，按棋盘比例导出。
- `impact/star_05.png`：Kenney Particle Pack 的 `star_05.png`，用于炮击闪光，CC0。来源见 [Godot Asset Library](https://godotengine.org/asset-library/asset/784)，许可见 `impact/LICENSE.txt`。火团、碎片与烟团由 `shell_burst.gd` 生成。

- `kenney-watercraft/`：Kenney Watercraft Kit 五艘舰船及色板，CC0；[来源](https://kenney.nl/assets/watercraft-kit)，许可见 `kenney-watercraft/LICENSE.txt`。
- `fonts/SeaInterface.otf`：Noto Sans CJK SC 子集，SIL OFL 1.1；[来源](https://github.com/notofonts/noto-cjk)，许可见 `fonts/LICENSE.txt`。
- `shaders/ocean.gdshader`、`shaders/waterline.gdshader`、`textures/ocean_fields.png`：原海战棋项目的 MIT 资源，从 `prototype/assets/` 复用；设计说明见 `../docs/OCEAN_ART.md`。

模型与海面资源保留原数据；正式入口只调整局内显示、缩放和材质参数。完整原型来源说明保留在 `../prototype/assets/SOURCES.md`。
