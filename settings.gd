extends RefCounted
## Host rules captured at round start.
static func schema() -> Dictionary:
	return {"schema_format": 3, "settings_version": 1,
		"fields": {"vote_seconds": {"type": "int", "default": 20, "title": "每轮投票时间（秒）",
			"audience": "room", "apply": "next_round", "min": 5, "max": 90, "control": "number"}},
		"layout": [{"id": "room", "title": "游戏规则", "expanded": true,
			"children": [{"field": "vote_seconds"}]}]}
