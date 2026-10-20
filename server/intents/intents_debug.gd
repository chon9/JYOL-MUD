## （不設 class_name：GameHost 只在 debug_enabled（--debug-intents）時以路徑 load() 並註冊，M3A_PLAN 6.11）
extends RefCounted
## debug_set { key, value }：只給驗收 bot 用。沒有 --debug-intents 時根本不註冊（回 unknown_intent，與未註冊相同）。
## key：morality、killing_intent、pk、combat_xp、money、learn_points、attr:<id>、skill:<id>（等級）、flag:<name>、
## online_s_add（秒，快轉坐牢／中毒）、teleport（房間 id，只給 bot 回到起點）。
## 故事包（STORY_PLAN §4.15）：world_s_add（秒，快轉世界時鐘並跑分鐘與時辰的工作）、hour（時辰名或 0–11，跳到該時辰起點）、
## quest_stage（"<qid>:<stage>"，沒接就先接）、quest_reset（qid：清 active／done／cd）、lilian、fame、
## wander_place（"<wid>:<room>"，WanderSystem.debug_place）、rumor_flush（RumorSystem.debug_flush，清空傳聞節流）。
## 審查修正：option:<key>（整數伺服器選項，限 DEBUG_INT_OPTIONS；介面驗收拍惡人警告時把倒數拉長）。

const KEYS := ["morality", "killing_intent", "pk", "combat_xp", "money", "learn_points", "online_s_add", "teleport",
	"world_s_add", "hour", "quest_stage", "quest_reset", "lilian", "fame", "wander_place", "rumor_flush",
	# M3B_PLAN §6：sect_rank（自己本派的位階）、guild（不支援 → bad_key）、assembly_now（觸發一次聚會）、bank_clear（清自己的錢莊）
	"sect_rank", "guild", "assembly_now", "bank_clear",
	# M3b 審查 3（介面驗收補拍）：org_activate（自己的連署直接成立）、org_invite_demo（value＝組織名：建一個示範組織邀請自己）、
	# org_demo_clear（刪掉示範組織）、consign_demo（value＝物品 id：一筆寄給自己、在這座城等你領的貨，附 120 兩）
	"org_activate", "org_invite_demo", "org_demo_clear", "consign_demo",
	# M3C_PLAN §8：appearance（int）、give_item（"<item_id>:<n>"）、loot_force（item id；LootSystem.debug_force）、
	# rng_seed（int）、battle_monster（monster id；目前房間開一場 FIGHT）、encounter_next（bool：下一次可遇敵的移動必定遇敵）、
	# npc_respawn_now（npc id 或 "*"）、divine_grant（item id；LootSystem.grant_divine）
	"appearance", "give_item", "loot_force", "rng_seed", "battle_monster", "encounter_next", "npc_respawn_now", "divine_grant"]
## encounter_next 的旗標（Session 的 meta；RegionSystem.roll_encounter 讀）
const META_ENCOUNTER_NEXT := "dbg_encounter_next"
## vital:<jing|qi|shen|neili|food|water>（M3c 第二輪審查：介面驗收拍「氣血不足」「肚子餓了」等趕路停走原因）
const PREFIXES := ["attr:", "skill:", "flag:", "option:", "vital:"]
## option:<key>（審查修正）：只能改這幾個整數伺服器選項（測試用，只改記憶體）
const DEBUG_INT_OPTIONS := ["villain_warn_s", "newbie_pk_protect_xp", "rumor_min_gap_s", "rumor_chat_inner_min"]

static func register(host: GameHost) -> void:
	host.register(Protocol.I_DEBUG_SET, func(s: Session, a: Dictionary) -> Dictionary:
		return apply(host, s, str(a["key"]), a["value"]), GameHost.NEEDS_CHAR)

static func _int(v: Variant) -> int:
	return CharData.to_int(v)

## 快轉世界時鐘 add_s 秒（不受 time_scale 影響）：跑分鐘工作（腐壞、生日、屍體）、換時辰（quests.on_clock、惡人）與晝夜轉換
static func _advance_world(host: GameHost, add_s: float) -> void:
	if add_s <= 0.0:
		return
	host.ws.world["world_time_s"] = host.now_s() + add_s
	host.m2_call(host.get("wander"), "on_time_jump", [add_s])
	host._minute_jobs()
	host.check_clock()
	host._check_day_night()
	for o in host.sessions():
		if o.character != null:
			host.quests.on_clock(o)   # 快轉剛好整日（時辰沒變）時 WAIT days 也要重算
			o.sheet_dirty = true
			o.view_dirty = true

static func apply(host: GameHost, s: Session, key: String, value: Variant) -> Dictionary:
	var ch = s.character
	var state_trigger := ""
	match key:
		"morality":
			ch.morality = clampi(_int(value), Character.MORALITY_MIN, Character.MORALITY_MAX)
			state_trigger = "TICK"
		"killing_intent":
			ch.killing_intent = maxi(0, _int(value))
			state_trigger = "TICK"
		"pk":
			ch.pk = maxi(0, _int(value))
			ch.pk_stamp_s = ch.online_s
			state_trigger = "PK"
		"combat_xp":
			ch.combat_xp = maxi(0, _int(value))
		"money":
			ch.money = clampi(_int(value), 0, Character.MONEY_CAP)
		"learn_points":
			ch.learn_points = maxi(0, _int(value))
		"online_s_add":
			var add := maxf(0.0, CharData.to_float(value))
			ch.online_s += add
			ch.pk_stamp_s = minf(ch.pk_stamp_s, ch.online_s)
			if host.get("conditions") != null:
				host.conditions.check_now(s)
		"teleport":
			var room := str(value)
			if not host.index.has_room(room):
				return GameHost.fail("bad_value:value")
			host.regions.teleport(s, room, false)
		# ---- 故事包（§4.15） ----
		"world_s_add":
			var add_s := maxf(0.0, CharData.to_float(value))
			_advance_world(host, add_s)
		"hour":
			var idx := -1
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				idx = _int(value)
			else:
				idx = WorldClock.SHICHEN.find(str(value).trim_suffix("時"))
				if idx < 0 and str(value).is_valid_int():
					idx = str(value).to_int()
			if idx < 0 or idx > 11:
				return GameHost.fail("bad_value:value")
			var wait := WorldClock.seconds_until_shichen(host.now_s(), idx, host.day_s())
			if wait > 0.0:
				_advance_world(host, wait + 0.5)
		"quest_stage":
			var spec := str(value)
			var i := spec.find(":")
			if i <= 0:
				return GameHost.fail("bad_value:value")
			var r: Dictionary = host.quests.debug_stage(s, spec.substr(0, i), spec.substr(i + 1))
			if not r.get("ok", false):
				return r
		"quest_reset":
			if str(value) == "":
				return GameHost.fail("bad_value:value")
			host.quests.debug_reset(s, str(value))
		"lilian":
			ch.lilian = maxi(0, _int(value))
		"fame":
			ch.fame = _int(value)
		"wander_place":
			var spec2 := str(value)
			var j := spec2.find(":")
			if j <= 0 or not host.index.has_room(spec2.substr(j + 1)):
				return GameHost.fail("bad_value:value")
			var w = host.get("wander")
			var placed: Variant = host.m2_call(w, "debug_place" if w != null and w.has_method("debug_place") else "place",
				[spec2.substr(0, j), spec2.substr(j + 1)], null)
			if placed == null or placed == false:
				return GameHost.fail("bad_value:value")
		"rumor_flush":
			var rs = host.get("rumor")
			host.m2_call(rs, "debug_flush" if rs != null and rs.has_method("debug_flush") else "flush", [], null)
		# ---- M3B_PLAN §6 ----
		"sect_rank":
			if str(ch.sect) == "":
				return GameHost.fail("no_sect")
			ch.sect_rank = maxi(0, _int(value))
			ch.sect_rank_pending = {}
		"guild":
			return GameHost.fail("bad_value:key")   # 組織只能經 org_* intent 改（權威在 world.guilds）
		"assembly_now":
			if host.get("sects") == null:
				return GameHost.fail("bad_value:key")
			host.sects.hold_assembly()
		"org_activate":
			var os = host.get("orgs")
			if os == null:
				return GameHost.fail("bad_value:key")
			var pg: Dictionary = os.petition_of(str(ch.id))
			if pg.is_empty():
				return GameHost.fail("bad_value:value")
			os._activate(pg)
			s.sheet_dirty = true
		"org_invite_demo":
			var os2 = host.get("orgs")
			if os2 == null:
				return GameHost.fail("bad_value:key")
			var now: float = host.now_s()
			var ttl := 300
			var g := { "id": "debug_demo_org", "name": str(value), "status": "ACTIVE", "leader": "debug_demo_leader",
				"leader_name": "示範幫主", "created_s": now, "petition_until_s": 0.0, "signers": [], "signer_names": {},
				"members": { "debug_demo_leader": { "rank": 0, "title": "", "joined_s": now, "name": "示範幫主" } },
				"rank_names": OrgSystem.DEFAULT_RANK_NAMES.duplicate(), "invites": { str(ch.id): now + float(host.world_span(float(ttl))) },
				"fee": 0 }
			os2.guilds().append(g)
			os2._send_invite(s, g, "示範幫主", ttl)
		"org_demo_clear":
			var os3 = host.get("orgs")
			if os3 != null:
				var gl: Array = os3.guilds()
				for i in range(gl.size() - 1, -1, -1):
					if gl[i] is Dictionary and str(gl[i].get("id", "")).begins_with("debug_demo"):
						gl.remove_at(i)
		"consign_demo":
			var es = host.get("escort")
			if es == null:
				return GameHost.fail("bad_value:key")
			var iid := str(value)
			if not host.tables.get("items", {}).has(iid):
				return GameHost.fail("bad_value:value")
			var city := ""
			for nid in host.index.npcs_in(s.room_id()):
				if es.npc_city(str(nid)) != "":
					city = es.npc_city(str(nid))
			if city == "":
				return GameHost.fail("bad_value:value")
			var now2: float = host.now_s()
			es.all().append({ "id": host.new_id("cs_"), "from_char": "debug_demo_sender", "from_name": "示範寄件人",
				"to_char": str(ch.id), "to_name": str(ch.name), "from_city": city, "to_city": city,
				"items": [{ "id": iid, "n": 1, "born_s": now2, "lots": [] }], "money": 120, "fee": 0, "status": "READY",
				"sent_s": now2, "arrive_s": now2, "ready_s": now2 })
			s.sheet_dirty = true
		# ---- M3C_PLAN §8 ----
		"appearance":
			if not ("appearance" in ch):
				return GameHost.fail("bad_value:key")   # WP-LOOKS 的欄位還沒有
			ch.set("appearance", clampi(_int(value), 0, Protocol.LOOK_MAX))
		"give_item":
			var spec3 := str(value)
			var k3 := spec3.find(":")
			var iid3 := spec3 if k3 < 0 else spec3.substr(0, k3)
			var n3 := 1 if k3 < 0 else maxi(1, spec3.substr(k3 + 1).to_int())
			if not host.tables.get("items", {}).has(iid3):
				return GameHost.fail("bad_value:value")
			var g3: Dictionary = host.give_item(ch, iid3, n3)
			if not g3.get("ok", false):
				return GameHost.fail(str(g3.get("reason", "bad_value:value")))
			host.item_gain_event(s, iid3, n3)
		"loot_force":
			var ls = host.get("loot")
			if ls == null or not ls.has_method("debug_force"):
				return GameHost.fail("bad_key")
			if not host.tables.get("items", {}).has(str(value)):
				return GameHost.fail("bad_value:value")
			host.m2_call(ls, "debug_force", [s, str(value)])
		"divine_grant":
			var ls2 = host.get("loot")
			if ls2 == null or not ls2.has_method("grant_divine"):
				return GameHost.fail("bad_key")
			var gr: Variant = host.m2_call(ls2, "grant_divine", [s, str(value)], {})
			if gr is Dictionary and not bool((gr as Dictionary).get("ok", true)):
				return gr
		"rng_seed":
			host.rng.seed = _int(value)
		"battle_monster":
			var mid := str(value)
			if not host.tables.get("monsters", {}).has(mid):
				return GameHost.fail("bad_value:value")
			if s.battle_id != 0:
				return GameHost.fail("in_battle")
			host.battles.start(s, [mid], "FIGHT")
		"encounter_next":
			var on2: bool = value == true or (typeof(value) in [TYPE_INT, TYPE_FLOAT] and _int(value) != 0) 				or (value is String and str(value).to_lower() in ["true", "1", "yes", "on"])
			if on2:
				s.set_meta(META_ENCOUNTER_NEXT, true)
			elif s.has_meta(META_ENCOUNTER_NEXT):
				s.remove_meta(META_ENCOUNTER_NEXT)
		"npc_respawn_now":
			var na = host.get("npcpk")
			if na == null or not na.has_method("respawn_now"):
				return GameHost.fail("bad_key")
			host.m2_call(na, "respawn_now", [str(value)])
		"bank_clear":
			var b = host.get("bank")
			if b != null and b.has_method("clear"):
				b.clear(ch)
			else:
				ch.bank = Character.default_bank()
		_:
			if key.begins_with("attr:"):
				var attr := key.substr(5)
				if not (attr in Character.ATTR_IDS):
					return GameHost.fail("bad_value:key")
				ch.attrs[attr] = _int(value)
				ch.clamp_vitals(host.tables, host.options)
			elif key.begins_with("skill:"):
				var sid := key.substr(6)
				if SkillBook.kind_of(sid, host.tables) == "":
					return GameHost.fail("bad_value:key")
				ch.skills.set_level(sid, maxi(0, _int(value)), host.tables)
			elif key.begins_with("option:"):
				# 審查修正：介面驗收要拍惡人警告，倒數 3 秒來不及截圖 → 測試用暫時調整整數伺服器選項（只改記憶體，不寫 options.json）
				var ok_key := key.substr(7)
				if not (ok_key in DEBUG_INT_OPTIONS):
					return GameHost.fail("bad_value:key")
				host.options[ok_key] = _int(value)
			elif key.begins_with("vital:"):
				var vid := key.substr(6)
				if not (vid in Character.VITAL_IDS):
					return GameHost.fail("bad_value:key")
				ch.vitals[vid] = maxi(0, _int(value))
				ch.clamp_vitals(host.tables, host.options)
			elif key.begins_with("flag:"):
				var fl := key.substr(5)
				if fl == "":
					return GameHost.fail("bad_value:key")
				var on: bool = value == true or (typeof(value) in [TYPE_INT, TYPE_FLOAT] and _int(value) != 0) \
					or (value is String and str(value).to_lower() in ["true", "1", "yes", "on"])
				if on:
					ch.flags[fl] = true
				else:
					ch.flags.erase(fl)
			else:
				return GameHost.fail("bad_value:key")
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_DEBUG_SET, { "key": key, "value": str(value) })
	s.sheet_dirty = true
	s.view_dirty = true
	if state_trigger != "" and host.get("sects") != null and s.battle_id == 0:
		host.sects.check_state(s, state_trigger)
	return GameHost.ok()
