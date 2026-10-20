extends "res://tests/test_case.gd"
## WP-UI：TextRenderer（M1_PLAN 3.12、6.1）：UI-only 事件不顯示；self／target／other 選擇；render_reason 查表規則

var tpl := {
	"atk_fist": { "self": "你打中{def}（-{dmg}）", "target": "{atk}打中你（-{dmg}）", "other": "{atk}打中{def}" },
	"battle_kill": { "other": "{name}倒地不起。" },
	"buy": { "self": "你花了 {cost} 兩買下{item_name} ×{n}。" },
	"pong": { "self": "延遲 {rtt_ms}" },
	"err_not_here": { "self": "這裡沒有這個人。" },
	"err_bad_args": { "self": "指令格式不對。" },
	"err_req_gender": { "self": "性別不符。" },
}

func _hit(atk_peer: int, def_peer: int) -> Dictionary:
	return { "ch": "BATTLE", "key": "atk_fist", "bid": 1,
		"p": { "atk": "甲", "def": "乙", "atk_peer": atk_peer, "def_peer": def_peer, "dmg": 9, "atk_uid": 1, "def_uid": 2, "def_qi": 50 } }

func test_ui_only_events_hidden() -> void:
	var e := { "ch": "SYSTEM", "key": "npc_menu", "p": { "npc": "n_x" }, "ui": true }
	assert_eq(TextRenderer.render_plain(e, 1, tpl), "")
	assert_eq(TextRenderer.render(e, 1, tpl), "")
	# 即使有同名模板，ui 事件也不顯示
	var e2 := { "ch": "SYSTEM", "key": "buy", "p": { "peer": 1 }, "ui": true }
	assert_eq(TextRenderer.render(e2, 1, tpl), "")

func test_variant_self_target_other() -> void:
	assert_eq(TextRenderer.render_plain(_hit(1, 0), 1, tpl), "你打中乙（-9）")
	assert_eq(TextRenderer.render_plain(_hit(0, 1), 1, tpl), "甲打中你（-9）")
	assert_eq(TextRenderer.render_plain(_hit(2, 3), 1, tpl), "甲打中乙")

func test_missing_variant_is_empty() -> void:
	# 只有 self 的模板，別人的事件不顯示
	var e := { "ch": "SYSTEM", "key": "buy", "p": { "peer": 2, "cost": 5, "item_name": "饅頭", "n": 1 } }
	assert_eq(TextRenderer.render_plain(e, 1, tpl), "")
	assert_eq(TextRenderer.render(e, 1, tpl), "")
	# 只有 other 的模板：怪物 peer 0
	var k := { "ch": "BATTLE", "key": "battle_kill", "p": { "uid": 2, "name": "野兔", "peer": 0, "by": 1 } }
	assert_eq(TextRenderer.render_plain(k, 1, tpl), "野兔倒地不起。")

func test_self_fill_and_int_formatting() -> void:
	var e := { "ch": "SYSTEM", "key": "buy", "p": { "peer": 1, "cost": 10.0, "item_name": "饅頭", "n": 2 } }
	assert_eq(TextRenderer.render_plain(e, 1, tpl), "你花了 10 兩買下饅頭 ×2。")

func test_unknown_key_keeps_m0_debug_output() -> void:
	var s := TextRenderer.render_plain({ "key": "no_such_key", "p": { "a": 1 } }, 1, tpl)
	assert_true(s.begins_with("no_such_key"), s)

func test_m0_event_without_peer_falls_back_to_self() -> void:
	var e := { "ch": "SYSTEM", "key": "pong", "p": { "nonce": 1, "rtt_ms": 12 } }
	assert_eq(TextRenderer.render_plain(e, 1, tpl), "延遲 12")

func test_render_reason_rules() -> void:
	assert_eq(TextRenderer.render_reason("not_here", tpl), "這裡沒有這個人。")
	assert_eq(TextRenderer.render_reason("bad_value:birth_city", tpl), "指令格式不對。")
	assert_eq(TextRenderer.render_reason("missing_arg:npc", tpl), "指令格式不對。")
	assert_eq(TextRenderer.render_reason("bad_type:n", tpl), "指令格式不對。")
	assert_eq(TextRenderer.render_reason("req_gender", tpl), "性別不符。")
	assert_eq(TextRenderer.render_reason("drop:rate", tpl), "")
	assert_eq(TextRenderer.render_reason("", tpl), "")
	assert_eq(TextRenderer.render_reason("totally_new", tpl), "【系統】無法執行（totally_new）")

func test_render_reason_real_templates_fallback() -> void:
	# 真實資料若尚未提供 err_*，仍要回傳可讀文字
	var t: Dictionary = tree.root.get_node("GameData").tables.get("text_templates", {})
	var s := TextRenderer.render_reason("not_here", t)
	assert_true(s != "", "non-empty")

func test_inline_reason_drops_channel_tag() -> void:
	assert_eq(TextRenderer.strip_channel_tag("【系統】 你已經學會了。"), "你已經學會了。")
	assert_eq(TextRenderer.strip_channel_tag("【系統】任務還沒有完成。"), "任務還沒有完成。")
	assert_eq(TextRenderer.strip_channel_tag("沒有標籤。"), "沒有標籤。")
	assert_eq(TextRenderer.render_reason_inline("totally_new", tpl), "無法執行（totally_new）")
	assert_eq(TextRenderer.render_reason_inline("drop:rate", tpl), "")
	# 真實資料：每個 err_* 的內嵌版都不帶「【」開頭
	var t: Dictionary = tree.root.get_node("GameData").tables.get("text_templates", {})
	var n := 0
	for k in t:
		if str(k).begins_with("err_") and not str(k).contains(":"):
			n += 1
			var inline := TextRenderer.render_reason_inline(str(k).substr(4), t)
			assert_false(inline.begins_with("【"), "%s -> %s" % [k, inline])
	assert_true(n > 10, "real err_* templates checked: %d" % n)

## 審查：送信酬勞印成「實戰經驗 +0、學習點數 +0、銀兩 +100」→ 只列非 0 的項目，全部是 0 就整行不顯示
func test_reward_list_skips_zero_entries() -> void:
	var t := { "reward": { "self": "你獲得 {reward_list}。" } }
	var e := { "ch": "SYSTEM", "key": "reward", "p": { "combat_xp": 0, "learn_points": 0, "money": 100, "fame": 2, "morality": 0 } }
	assert_eq(TextRenderer.render_plain(e, 1, t), "你獲得 銀兩 +100、聲望 +2。")
	e["p"] = { "combat_xp": 0.0, "learn_points": 0, "money": 0 }
	assert_eq(TextRenderer.render_plain(e, 1, t), "")
	e["p"] = { "combat_xp": 12, "learn_points": 3, "money": 0 }
	assert_eq(TextRenderer.render_plain(e, 1, t), "你獲得 實戰經驗 +12、學習點數 +3。")
