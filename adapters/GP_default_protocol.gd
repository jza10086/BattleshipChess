extends RefCounted

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"dependencies": {}}

## Battleship publishes personal score rankings under the standard protocol only.
func check_request(request: Dictionary) -> Dictionary:
	if request.get("mode") != "standard":
		return {"ok": false, "code": "unsupported_mode", "message": "海战棋仅支持 standard 普通局"}
	return {"ok": true}

func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

func map_result(result: Dictionary, _request: Dictionary) -> Dictionary:
	return result.duplicate(true)
