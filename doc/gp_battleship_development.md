# M17 海战棋　B

来源：2026-11-07 架构审查及其最后实施记录。整理日期：2026-11-14。下列待办保留原状态；实施前核对本包源码与工作区，不以历史检查代替本次验收。

[共享 G01–G03 任务](../../../protocols/godot_party_default_protocol/doc/godot_party_default_protocol_development.md) · [包说明](gp_battleship_guide.md)


包：`gp_battleship`。定位：[party_round.gd](../party_round.gd)、[battle_view.gd](../battle_view.gd) 的 `_rebuild_ships()`、[ship_display.tscn](../ship_display.tscn)。

2026-11-07 已实施，子模块提交 `57e09c7`。Godot 4.7.2 定向验证：既有三客户端真实大厅联机通过（私有视图、布阵归属、抢选、齐射和结算）；1920×1080 实际渲染/鼠标操作检查通过并查看截图；五组残骸切换、水线实例隔离、名字牌编辑值和默认翻译检查通过。结果边界/生命周期自动检查覆盖非房主消息、无效结果、观战房主无隐藏舰船节点、末轮弹着后结算、延迟期间取消、重复停止及唯一提交，均通过。

检查脚本及输出在 `tmp/test/battleship/`：`preview.gd`、`network.gd`、`architecture_display.gd`、`architecture_lifecycle.gd`。观战房主本批为定向 API/视图检查，尚未做完整观战房主多端人工验收；真人操作手感、跨机器/外网和导出包验收仍待进行。原有 `ocean_fields.png.import` 改动未纳入提交。

## 人工验收待办

保留自 2026-11-05 场景审查，后续记录未明确关闭的人工事项：实际多席位投票及鼠标摆舰待人工验收。
