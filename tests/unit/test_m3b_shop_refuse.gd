extends "res://tests/unit/test_sect_m3b_fixture.gd"
## M3B_PLAN §4.8、§5.1.6、§11.1：shop.refuse_if（京城兵器鋪不賣丐幫弟子，O10）。
## 丐幫在拒賣的店 shop_refused；他派可買；沒有 refuse_if 的店照賣；shop_list 照樣列出但帶 refused。

func _refusing_shop() -> String:
	var shop: Dictionary = t()["npcs"][SHOPKEEPER].get("shop", {})
	shop["refuse_if"] = [ [ { "type": "sect", "sect": GB } ] ]
	shop["refuse_text"] = "tgb_smith_refuse"
	t()["npcs"][SHOPKEEPER]["shop"] = shop
	t()["text_templates"]["tgb_smith_refuse"] = { "id": "tgb_smith_refuse", "self": "{npc_name}捏著鼻子揮手：叫化子別來搗亂！",
		"era": "1.0A" }
	return str((shop.get("items", []) as Array)[0])

func test_gaibang_refused_other_sect_buys() -> void:
	if not game_ok():
		return
	install_gb({ "harass": [] })
	make_char("測買主")
	var item := _refusing_shop()
	ch().money = 100000
	goto("xx_smithy")
	join_gb()
	clear_events()
	var have := item_count(item)
	assert_eq(reason("buy", { "npc": SHOPKEEPER, "item": item }), "shop_refused", "丐幫弟子買不到")
	assert_eq(item_count(item), have)
	assert_false(evs("tgb_smith_refuse").is_empty(), "拒賣文字（refuse_text 模板）")
	clear_events()
	ok("shop_list", { "npc": SHOPKEEPER })
	var sl := lastp("shop_list")
	assert_true(bool(sl.get("refused", false)), "shop_list 照樣列出但帶 refused")
	assert_false((sl.get("items", []) as Array).is_empty())
	assert_true(str(sl.get("refuse_text", "")).contains("叫化子"))
	# 賣東西不受影響
	var uid := give("c_mantou", 1)
	if tables()["items"]["c_mantou"].get("no_sell", false) != true:
		ok("sell", { "npc": SHOPKEEPER, "item_uid": uid, "n": 1 })
	# 他派（或沒有門派）可以買
	ch().sect = ""
	ok("buy", { "npc": SHOPKEEPER, "item": item })
	assert_eq(item_count(item), have + 1)
	clear_events()
	ok("shop_list", { "npc": SHOPKEEPER })
	assert_false(bool(lastp("shop_list").get("refused", true)))

func test_shop_without_refuse_if_sells_to_gaibang() -> void:
	if not game_ok():
		return
	install_gb({ "harass": [] })
	make_char("測買主二")
	join_gb()
	ch().money = 100000
	var items: Array = t()["npcs"][SHOPKEEPER].get("shop", {}).get("items", [])
	goto("xx_smithy")
	ok("buy", { "npc": SHOPKEEPER, "item": str(items[0]) })

func test_refuse_if_needs_whole_group() -> void:
	if not game_ok():
		return
	install_gb({ "harass": [] })
	make_char("測買主三")
	join_gb()
	var shop: Dictionary = t()["npcs"][SHOPKEEPER].get("shop", {})
	shop["refuse_if"] = [ [ { "type": "sect", "sect": GB }, { "type": "morality_max", "value": -100 } ] ]
	ch().money = 100000
	goto("xx_smithy")
	ok("buy", { "npc": SHOPKEEPER, "item": str(shop["items"][0]) })
	ws.options["npc_reactions"] = "OFF"   # 不讓 AmbientSystem 因為善惡先拒絕
	ch().morality = -200
	assert_eq(reason("buy", { "npc": SHOPKEEPER, "item": str(shop["items"][0]) }), "shop_refused", "組內全成立才拒")
