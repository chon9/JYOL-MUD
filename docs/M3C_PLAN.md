# M3c 實作計畫：美術登記、初始造型、跨區趕路與地圖美術、攻擊 NPC、裝備與打寶、武器特效（M3C_PLAN）

> 版本：2026-10-20（開工版）。協調者撰寫；實作中只由協調者（整合者）修改本文件。
> 上游：GDD §2.4、§5、§6、§9；M3B_PLAN §1.2（M3c 延後清單）；M3A_PLAN（門派框架、門規、公敵、監獄）；M2_PLAN（強制 PK、守城官兵、善惡殺氣）；STORY_PLAN（任務引擎，任務 NPC 不可被破壞）；AUTHENTIC_UI_SPEC；ART_REQUEST §7（第四批）、§9（初始造型）、§10（地圖美術）、§11（空手人物＋武器特效）。
> 研究：`docs/research/verified_research.md` 的「M3c 研究」章（以下簡稱「研究」；分節：攻擊 NPC、裝備與打寶）。研究與本文件不一致時，以本文件的「擁有者決定」（§1.3）為準，並在 `src_note` 寫明。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

M3c 由 6 個工作包（WP-ART、WP-LOOKS、WP-NAV、WP-NPCPK、WP-LOOT、WP-FX）**同時**在同一個工作目錄實作，最後由整合者驗收。實作者之間不溝通。規則沿用 M3B_PLAN 0.1：

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent、事件 key、原因碼、伺服器選項 key、規則 key、存檔欄位、資料列 id、art.json 鍵、檔名**都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定。
3. 優先順序：本文件 > M3B_PLAN > STORY_PLAN > M3A_PLAN > WORLD_2001 > M2_PLAN > M1_PLAN > GDD > TECH_ARCH。偏差列在 §1.4。
4. 發現缺漏：照「最不意外」實作，程式裡寫 `# M3C_PLAN 缺漏：……`，交付說明列出；**不要**改別人的檔案（共用熱檔照 §11.2 的切分）。

### 0.2 標記

沿用 GDD 第 0 章：【已證實】【後期版】【待考證】【設計提案】【設計提案・非原作】。`era` = 這個東西在哪個版本**已經存在**；`src` = 這一列細節的出處（`verified`／`later`／`proposal`）。本文件新增的數值一律【設計提案】（`src: "proposal"`），有研究依據的在 `src_note` 註明（例：`"src_note": "研究 裝備：jyfree jy1_3_1 單刀 +10／重 6"`）。
擁有者明確要求、但原作 2001 沒有的東西（秘笈系統、稀有掉落廣播、神兵掉落）一律標【設計提案・非原作】，並用規則開關讓 `classic_strict` 可以關掉（§4.11）。

### 0.3 全域規則

M1_PLAN G1–G10、M2_PLAN H1–H6、M3A_PLAN K1–K6、STORY_PLAN §0.3、M3B_PLAN L1–L8 全部繼續有效（主機權威、離線同一路徑、`core/**` 純邏輯、JSON 數字轉 int、**不 commit**、測完關掉 godot 並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認、新增 `class_name` 後先 `--import`、不新增 Autoload、不改 `project.godot`、不新增 `@rpc` 方法、新系統容錯接線）。M3c 另加：

| # | 規則 |
|---|---|
| N1 | `Protocol.VERSION` **維持 5**：M3c 只新增 intent、可選參數、事件、原因碼、`SLOTS` 列舉值、快照與選單欄位，RPC 簽名不變（比照 M3b L1）。舊客戶端不會送新參數；新舊混用由 `content_hash` 擋。 |
| N2 | **一個檔案只有一個擁有者**（§11.1）。少數共用熱檔照 §11.2 切到「函式／欄位／附加區塊」層級；不在表上的修改一律禁止。 |
| N3 | **共用 JSON 的寫法**：只用 Edit 工具做局部取代（每次 Edit 前重新 Read），**不得整檔重寫、不得重新排版**。新列一律插在檔尾 `\n  ]\n}` 之前（以這段當錨點）；改既有列只改 §11.2 准許的欄位。不得用 `json.dump` 重寫 `data/*.json`（會改掉手排的格式、造成其他 WP 的錨點失效）。 |
| N4 | **新主機系統**（`NpcAttackSystem`、`LootSystem`）照 M3A K3：`extends RefCounted`、`_init(p_host: GameHost)`、`GameHost` 以路徑 `load()` 建立（WP-NPCPK Day-0 寫好載入行），失敗時為 `null`，所有呼叫點用 `host.m2_call(...)`。 |
| N5 | **測試資料隔離**（M3b L4）：測試、bot、驗收只能寫測試根目錄（`DataRoot.test_root()` = `K:\Project\JY-Mini-OL-Work\testdata\`）或 `--data-root=<K: 上的絕對路徑>`；**絕對不碰擁有者存檔**（`JY-Mini-OL-Work\userdata\`、`JY-Mini-OL-Release\userdata\`、`appdata_old*`）。不寫 C:。截圖 `K:\Project\JY-Mini-OL-Work\shots\`、log `...\logs\`、暫存 `...\tmp\`、美術備份 `...\art_backup\<YYYY-MM-DD>\`。 |
| N6 | **不刪任何東西**（`K:\Project\JY-Mini-OL-Work\tmp` 以外）：要淘汰的檔案搬到 `K:\Project\JY-Mini-OL-Work\tmp\m3c_moved\<WP>\`。`assets/art/**` 被覆寫前一律先備份（§2.5）。 |
| N7 | 新 id 一律用本文件的前綴：WP-NPCPK `n_na_*`（新 NPC）、`m_npc_*`（NPC 戰鬥單位）、`*_r_attack_npc`／`*_r_kill_good_npc`（門規列）；WP-LOOT `w_lt_*`、`a_lt_*`、`bk_*`（秘笈）、`w_sb_*`（神兵）、`lt_*`（掉落表）；模板前綴 WP-LOOKS `look_*`、WP-NPCPK `na_*`、WP-LOOT `lt_*`；原因碼模板 `err_<reason>`。 |
| N8 | **不改既有戰鬥公式**（`core/battle/battle_formulas.gd` 凍結）。唯一的戰鬥事件形狀變更是 WP-FX 的純表現欄位（§7.2），金檔由 WP-FX 重產並在交付說明列出差異。WP-LOOT 對 `armor_power` 的改動在 `derived_stats.gd`（加總 7 個防具欄），不是公式本身。 |
| N9 | 1.0A-only 世界（`--eras=1.0A`）與 `classic_strict` 必須完整可玩；所有新資料列都有 `era`、`src`；1.0B 的 NPC 不能被 1.0A 房間引用（M3b L7 照舊）。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=m3c]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500
"$G" --headless --path . --script res://tests/ui/ui_playthrough.gd -- --no-steam
"$G" --headless --path . -- --no-steam --offline --world=w_m3c_m1 --profile=m1bot --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
"$G" --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3a_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3b_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/story_acceptance.gd -- --no-steam --all
"$G" --headless --path . --script res://tools/m3c_acceptance.gd -- --no-steam [--only=looks] [--timeout=2400]
"$G" --headless --path . --script res://tools/net_smoke.gd -- --no-steam
"$G" --headless --path . -- --no-steam --offline --world=close_x --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=wm --time-scale=50 --quit-after=300
"$G" --headless --path . -- --no-steam --offline --world=close_y --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=quit --time-scale=50 --quit-after=300
python -I tools/import_art.py --inbox <dir> --out <dir> --art-json <file> --no-json-update --backup-root K:/Project/JY-Mini-OL-Work/tmp/m3c_art_test/backup   # 測試用
python -I tools/art_contact_sheet.py --out K:/Project/JY-Mini-OL-Work/shots/m3c_art_contact.png
```

---

## 1. 範圍

### 1.1 M3c 要做（逐項打勾；括號是負責 WP；每項附驗收準則）

**A. 美術登記（WP-ART）**
- [ ] A1 第四批已處理好的圖（`assets/art/units`、`assets/art/bg`）在 `data/art.json` 從 `alias` 換成 `sprite`／`bg`：§2.1 表的 34 個單位＋3 張背景，附顯示比例。**驗收**：`data_lint` 0 錯誤；`tools/art_contact_sheet.py` 產出聯絡表（每張圖依 `scale` 與 1.0 的人並排），擁有者肉眼可比；`test_art_registry.gd` 抽查 5 個條目 `ArtRegistry.unit_texture(id,"","idle")` 回的是自己的檔。
- [ ] A2 16 個初始造型 `look_m01..08`、`look_f01..08`（只有 idle）登記為 `sprite`。**驗收**：同上；`ArtRegistry.unit_texture("look_m05","PLAYER","attack") == null`（沒有出招圖時呼叫端用 idle＋程式動畫，不借別人的圖）。
- [ ] A3 `art.json` 新區塊 `map`、`map_icons`、`weapon_fx`、`weapon_icons`（§2.3）＋`ArtRegistry` 新 API（§2.4）；`import_art.py` 支援 `map_*.png`、`fx_weapon_*.png`、`fx_skill_*.png`、`icon_weapon_*.png`；`art_register.py` 同步支援。**驗收**：單元測試用暫存目錄餵每一類各一張假圖，輸出尺寸、目錄、`placeholder` 旗標正確。
- [ ] A4 覆寫備份（§2.5）：`import_art.py` 覆寫 `assets/art/**` 任何內容不同的檔之前，先備份到 `K:/Project/JY-Mini-OL-Work/art_backup/<YYYY-MM-DD>/<子目錄>/<檔名>`；另做一次「空手重畫前」快照。**驗收**：單元測試覆寫一張圖後備份檔存在且位元組等於舊檔；快照路徑寫在交付說明。
- [ ] A5 為 WP-NPCPK 的新 id（§5.9 表）加 `alias` 條目（lint 要求每隻怪、每個定點戰鬥 NPC 都有條目）。

**B. 初始造型（WP-LOOKS）**
- [ ] B1 創角畫面有**大型造型選擇器**（依性別過濾；0 號＝布衣 `player_m`／`player_f`，1–8 號＝§3.1 名稱）。**驗收**：`test_ui_m3c_looks.gd` 切換性別時選項換成該性別的 9 張、送出的 `char_create` 帶 `look`。
- [ ] B2 角色存 `appearance`（int，存檔欄位 `"appearance"`，舊角色預設 0）。**驗收**：舊存檔載入 `appearance == 0`；存讀往返不變。
- [ ] B3 未入派：戰鬥圖與立繪用造型；入派後門派服裝優先（既有行為）；離派回到造型。**驗收**：`Character.battle_look()` 單元測試涵蓋 3 種狀態；驗收劇本 `looks`。
- [ ] B4 屬性視窗可以免費更換造型（純外觀）；主機驗證 `look` 範圍。**驗收**：`set_look` 0–8 成功、9 回 `bad_value:look`、戰鬥中回 `in_battle`（既有 IDLE 旗標的原因碼；整合紀錄 I2）。
- [ ] B5 協定純新增（`char_create.look` 可選、`set_look` 新 intent）。

**C. 導航（WP-NAV）**
- [ ] C1 **跨區自動趕路**：在江湖全圖點地區、或在區域圖點房間 → 只走**探索過的房間**的最短路（跨區域）；目標沒探索 → 走到「最接近目標的已探索房間」並說明。**驗收**：`test_m3c_route.gd`（純函式）；驗收劇本 `nav_walk`。
- [ ] C2 **快捷目的地**：記錄點、最近的客棧／茶棚／綠洲（有 `INN` 服務 NPC 的房間）、本派山門、出生城、目前任務目標。不能去的灰掉並寫原因。
- [ ] C3 **進度列**「趕路中：往X（剩N步）」＋「停止」鈕＋Esc；小地圖也顯示。
- [ ] C4 **遇敵獲勝後自動繼續**（系統選項「趕路遇敵獲勝後繼續趕路」，預設開）；死亡、逃跑、氣 < 30%、飽食或飲水 < 20、前方鎖住或「要自己決定」的房間（§4.4）一律停，並寫原因。每一步仍是主機驗證的 `move`。
- [ ] C5 **擁有者回報的 bug**：小地圖與區域圖的邊緣節點「往XXX」點了要把畫面切到那個鄰區，那區探索過的房間可以點來趕路；有「返回目前區域」。**驗收**：`test_ui_m3c_nav.gd`、介面驗收截圖。
- [ ] C6 **地圖美術就緒**：有 §10 的圖就用（全圖底圖對齊 `world_pos`、區域圖底紋平鋪、房間框 9 宮格、圖示、你在這裡、羅盤、標題框），沒有就保持現在的程式繪圖。**驗收**：單元測試用假的 2400×1800 底圖確認站點座標＝§4.6 的轉換；沒有圖時畫面與現在一致（現有地圖測試全綠）。

**D. 攻擊 NPC（WP-NPCPK；M3c 項目 ATTACK_SECT_NPC＋一般 NPC PK）**
- [ ] D1 對標了 `attack` 的 NPC：Ctrl+點 NPC 名字（同強制 PK 的連結鍵）→ 確認框（寫出善惡、門派後果）→ `npc_attack`。對話選單另有「滅派」（武當知客道長、古墓孫婆婆、全真知客道長）。**驗收**：`test_m3c_npc_attack.gd` 全部原因碼。
- [ ] D2 哪些可打、哪些受保護依研究（§5.2 表）；師父、商人、任務給予者預設不能動手；可打的師父／門派 NPC **永遠不會真的消失**（`CHALLENGE`，打的是另一組戰鬥單位，任務、教學不受影響）；一般居民與動物 `KILL`，暫時消失、依類別重生。**驗收**：lint 檢查 `KILL` 的 NPC 不是任何任務、商店、教學、記錄點的對象；驗收劇本 `npc_good` 重生。
- [ ] D3 善惡、殺氣依 NPC 類別（§5.4 表）；城內殺善良／中立 NPC 招來守城官兵；殺 NPC 不加 PK值【待考證】。
- [ ] D4 門派後果：本派弟子攻擊同門 NPC＝違反門規（`ATTACK_SECT_NPC`）；外人攻擊門派知客／守門／孫婆婆或選「滅派」＝該派公敵（既有 `hostile_entry` 接手、執法者捉拿、監獄）；本派弟子對丁春秋／血刀老祖下手＝叛派；華山、恆山「不可殺善良 NPC」＝違規；少林佛法、恆山慈悲在殺善良 NPC 時降級。**驗收**：驗收劇本 `npc_sect`。
- [ ] D5 主機權威、多人安全：同一 NPC 同時只能有一場攻擊戰；第二人回 `npc_busy`（可用既有 `battle_join` 加入）；擊殺、重生、善惡只結算一次。

**E. 裝備與打寶（WP-LOOT）**
- [ ] E1 **原作裝備**：官方 jyfree 的武器（刀、劍、鞭、杖、空手）與防具（衣、帽、護腕、戒、披風、鞋、項鍊）數值入庫（§6.2），既有 25 列修正（第二個數字是重量）。
- [ ] E2 **8 個裝備欄**（1 武器＋7 防具）：`HEAD NECK WRIST CLOAK RING BOOTS` 加入；`armor_power` 加總；舊存檔相容。
- [ ] E3 **裝備條件**：性別（官方）；條件不合不能裝，背包與裝備視窗顯示數值、部位、條件（不合紅字）、稀有度、屬性加成。
- [ ] E4 **秘笈**：用讀書識字讀（`manual_read`），讀書識字是門檻也是上限【設計提案・非原作】。
- [ ] E5 **神兵利器**：全服唯一、極稀有（`divine_source`）、PvP 打死持有者自動轉給殺手【研究：設計文字】。
- [ ] E6 **頭目／精英掉落表**：稀有度 5 級、必掉＋機率掉；**稀有掉落【江湖傳聞】**；戰鬥結果畫面依稀有度上色。
- [ ] E7 平衡：`balance_sim` 新案例（§12.2）不破壞經濟；資料每列有 `src`／`src_note`。

**F. 武器出招特效（WP-FX；擁有者決定，ART_REQUEST §11）**
- [ ] F1 出招時依攻擊者**實際裝備的武器類型**（劍、刀、棍、鞭、拳掌、爪）或所用武功類別（刺、暗器、內功、毒、醫、陣）畫特效，從前手往目標、依方向旋轉翻轉。
- [ ] F2 名牌旁的武器小圖示。
- [ ] F3 沒有 `fx_weapon_*`／`fx_skill_*`／`icon_weapon_*` 圖時有像樣的程式繪製備援。
- [ ] F4 戰鬥快照與事件的純表現欄位（§7.2），金檔重產。**驗收**：`test_m3c_weapon_fx.gd`（依武器類型選特效的戰鬥畫面單元測試）。
- [ ] F5 玩家圖之後換成同檔名的空手版：程式不必改（WP-ART 的備份保證舊圖不遺失）。

### 1.2 M3c 不做（仍延後）

- **M3 剩餘（M3d 或更後）**：懸賞名單與賞金獵人牌照（捕快、衙門佈告欄）；合體技與玉女素心劍法；輕功「輕」與 2001「閃」；門派比武；劫鏢；血刀『恐嚇』與血池、威嚇的戰鬥效果；NPC 執法者野外追捕；剩下的門派武功鏈（全真重陽劍法、靈鷲八荒、星宿煉毒、滅絕 cap-1 自修、峨嵋四象掌、全真空明拳、血魔刀法）；黑龍潭 1.0B；京城半仙（消 PK值）與天師消殺氣；無敵落跑鞋、夜明珠；丐幫跑腿（柯鎮惡、三八紅、武林帖、英雄帖）；全真殺古墓弟子額外殺氣與「殺古墓 10 人坐牢」；裝備 2 秒間隔（2001-10-09）。
- **M5**：武林大會（神兵的正式來源）、總壇裝備與強化、婚姻、傭兵、攻城。
- **後期版（不做）**：耐久與修理、七彩／震天、鑲嵌、精化、屬性石、殘章／秘本／寶典／槧本分級、生生造化丹等「所有 NPC 都會掉」系統。
- **殺白猿、黃兔扣善惡**（M3c 第三輪審查；【待考證】）：鐵心 FAQ 說大理後沙漠山洞的白猿「扣善惡度」、2002-06-17 17173 說殺黃兔會降善惡。本作沒有沙漠山洞，也沒有「黃兔」這種怪（野兔不是黃兔）；`m_wd_baiyuan` 是龍門任務必殺的七獸之一，扣善惡會讓善惡 0 的武當弟子進城被官兵追殺，量也沒有出處 → 暫不扣（善惡 0），等做沙漠山洞時一起處理。
- **新手裝換成 2001-06-30 官方清單**：會動到 M1 驗收與新手平衡，本包只加資料列（傳家寶刀／寶甲／寶鞋），不換預設（§14 開放問題 Q1）。

### 1.3 擁有者決定（擁有者已預先授權本里程碑；以下是選定的預設值，建造者照做）

| # | 決定 | 理由（研究） | 本文落點 |
|---|---|---|---|
| O1 | 第四批單位顯示比例依 §2.1 表（蟲蛇小、人 1.0）；初始造型一律 1.0（玩家外觀不影響公平）；聯絡表看過後 WP-ART 可在 ±0.1 內微調人物、±0.15 內微調動物 | ART_REQUEST 常見問題「大小由我在資料裡設定」 | §2.1 |
| O2 | 造型 0–8 兩性同編號；入派後門派服裝**永遠**優先（既有行為）；離派、被逐回到造型；更換免費、隨時（戰鬥中除外） | ART_REQUEST §9 | §3 |
| O3 | 自動趕路只走探索過的房間；遇敵獲勝後自動續走預設開；停走門檻 氣 < 30%、飽食或飲水 < 20【設計提案】 | 擁有者需求 | §4 |
| O4 | NPC 攻擊兩種模式：`KILL`（一般居民、動物、守衛、惡人：死了暫時消失）與 `CHALLENGE`（師父、門派、劇情：NPC 不會消失，打的是另一組戰鬥單位）【設計提案；研究「門派 NPC 不會永久消失」為推論】 | 研究 攻擊 NPC：孫婆婆可重複點、闖少林、武當大廳 | §5 |
| O5 | 預設**不能**動手：商人、師父（武館武師例外）、任務給予者、記錄點、驛站、錢莊、鏢局、監獄看守、葉二娘與南海鱷神（已有遊蕩惡人流程） | 研究：只有少數有記載；不能讓任務與商店壞掉 | §5.2 |
| O6 | 善惡、殺氣依類別（§5.4），每殺一個結算一次（不是每場）；殺 NPC 不加 PK值 | 研究：數值未公布、PK 加法有兩說【待考證】 | §5.4 |
| O7 | 城內（`CITY` 且有官兵）殺善良／中立 NPC → 立刻 1 名守城官兵（殺的是守衛 → 2 名） | news_4-2「守衛追殺」；人數【設計提案】 | §5.5 |
| O8 | 外人攻擊門派知客／守門／孫婆婆、或選「滅派」＝該派公敵（2001 規則；孫婆婆的 2002 重複刷法照樣可刷，但會是公敵——研究「矛盾」採 2001 規則） | mengpai/2、5、6、7 | §5.6 |
| O9 | 本派弟子攻擊同門 NPC＝`ATTACK_SECT_NPC` 違規（出處：武當「攻擊武當門人」坐牢、峨嵋「PK 同門 NPC＝叛派」；其他派比照同門相殘【設計提案】）；結果依世界的 `sect_violation_mode`（2001-11-15 後 JAIL 1 遊戲日；`classic_strict` EXPEL） | 研究 門派監獄 | §5.6 |
| O10 | 本派弟子對丁春秋、血刀老祖下手＝**叛派**（武功減半、公敵）；外人＝公敵 | 官方 2001/8/7「對丁春秋／血刀老祖下PK指令」 | §5.6 |
| O11 | 少林佛法、恆山慈悲：每殺一個善良 NPC 降 1 級【待考證：量；比照官方吃肉＝佛法 −1 級】；華山、恆山「不可殺善良 NPC」＝違規 | mengpai/1、7、9；jyfree jy1_1_1 | §5.6 |
| O12 | NPC 重生時間依類別（§5.4）【待考證：原作無資料】；伺服器選項 `npc_respawn_pct` 可調 | — | §5.4 |
| O13 | 裝備正典＝jyfree 官方「攻擊力／重量」「防禦力／重量」；本作戰鬥值 `atk`＝官方攻擊力、`def`＝⌈官方防禦力 ÷ 5⌉、`weight`＝⌈官方重量 ÷ 2⌉（與既有資料一致：木刀 4／2、粗布道袍 4）；原值存在 `official` | 研究 裝備 owner_decisions (e) | §6.2 |
| O14 | 8 個裝備欄（1 武器＋7 防具）；`armor_power` = 7 個防具欄 `def` 加總；只有**性別**是有出處的裝備條件，其他條件只用在【設計提案】的稀有品 | 研究 裝備欄、裝備條件 | §6.3 |
| O15 | 神兵：全服每把唯一；規則 `divine_source` 預設 `BOSS_DROP`（3 個最強頭目各 0.2%）【設計提案・非原作】，`classic_strict`、`later_official` 為 `NONE`（只能由管理員／除錯給，等 M5 武林大會）；PvP 打死持有者（任何 PvP 方式）自動轉給殺手；神兵不能賣、丟、存、死亡不掉 | 研究 神兵（2002 武林大會；xinshou/11 轉移） | §6.5 |
| O16 | 神兵戰鬥攻擊＝⌊官方 × 0.4⌋（倚天 80、玄鐵重劍 86、屠龍刀 84【設計提案：屠龍官方數值未知】） | 防止一擊斃命；balance_sim `divine_duel` | §6.5 |
| O17 | 秘笈【設計提案・非原作】（2002-08-21 系統，依擁有者要求提前）：具名秘笈對應基本技能；讀書識字是**門檻**（`literacy_min`）也是**上限**（讀到的等級 ≤ 讀書識字等級）；不消耗；規則 `manuals`（`classic_strict` 關） | 官方技能頁「目不視丁…無法透過秘笈自己修練」；上限關聯【待考證】 | §6.4 |
| O18 | 稀有度 5 級（凡品、良品、精品、珍品、神兵）；珍品以上發【江湖傳聞】【設計提案・非原作：2001–2003 官方沒有】；規則 `loot_broadcast`（`classic_strict` 關） | 研究 其他掉落 | §6.6 |
| O19 | 武器特效依「實際裝備的武器類型」；用了刺／暗器／內功／毒／醫／陣法類武功時用武功類別特效；非人形怪（獸、蟲）維持既有的打擊火花 | ART_REQUEST §11 | §7 |
| O20 | 新手裝不換（Q1）；傳家寶刀／寶甲／寶鞋只建資料列（`era 1.0A`、名稱【已證實】、數值【設計提案】≤ 木刀／粗布道袍／皮靴） | 研究 新手裝 | §6.2 |

### 1.4 與 GDD／既有文件的偏差（M3c 決議；整合者同步）

| # | 偏差 | 理由 |
|---|---|---|
| F1 | GDD §9.2 武器表第二個值「意義不明」→ 是**重量**；既有武器列的 `def` 改 0 | 研究 官方武器數值 |
| F2 | GDD §9.2「神兵是頂級掉落」→ 神兵來自武林大會（M5）；M3c 的掉落是擁有者要求的【設計提案・非原作】且可關 | O15 |
| F3 | GDD.md:165 新手裝（精藥水x5、銀兩、布衣、木刀）標 ZOL 2006 → 註明 2001 官方清單（研究 新手裝），預設暫不換（Q1） | 研究 |
| F4 | GDD 裝備欄（武器＋衣服兩格）→ 8 格 | O14 |
| F5 | M3B_PLAN §1.2 M3c 清單的 `ATTACK_SECT_NPC`、神兵 PvP 轉移 → 本包完成；其他照 §1.2 仍延後 | — |
| F6 | ART_REQUEST §7（第四批）、§9、§10、§11 的「我會一起登記」→ 已登記／程式已就緒；§11.0 第 5 點「舊圖會先備份」→ 備份位置 `K:\Project\JY-Mini-OL-Work\art_backup\<日期>\` | §2 |

---

## 2. A：美術登記（WP-ART）

### 2.1 第四批：把 alias 換成正式圖

照現有 `sprite` 條目形狀：`{ "sprite": "<id>", "scale": <num>, "y_offset": 0, "required": false, "placeholder": false }`（背景：`{ "bg": "<id>", "required": false, "placeholder": false }`）。比例【設計提案】，聯絡表後可依 O1 微調。

| 類 | id（`assets/art/units/unit_<id>_idle.png` 已存在） | scale |
|---|---|---|
| 蟲蛇（小） | `m_lf_zhizhu` 0.35、`m_lf_xiezi` 0.40、`m_lf_wugong` 0.45、`m_lf_qingshe` 0.50 | 見左 |
| 戰鬥人形 | `m_dl_mingjiao`、`m_hn_mojiao`、`m_xx_laodenuo` 1.0；`m_ym_qiangdao` 1.05 | 見左 |
| NPC（壯） | `n_xx_qiaofeng` 1.10；`n_amb_etou_xe`、`n_amb_etou_dlw`、`n_amb_etou_ss`、`n_ym_qiangdao`、`n_ym_hufei`、`n_wd_yuanye`、`n_xx_palace_guard_l`、`n_xx_palace_guard_r` 1.05 | 見左 |
| NPC（少年） | `n_hn_longmen` 0.95 | |
| NPC（一般） | `n_dl_cunmin`、`n_dl_limochou`、`n_dl_wangbutou`、`n_dlw_guiyi`、`n_hg_lincai`、`n_hn_dizi`、`n_hn_liugongzi`、`n_hn_lulianrong`、`n_hn_mimike`、`n_hn_moda`、`n_hn_teaman`、`n_hs_chengbuyou`、`n_hs_lanyihan`、`n_hs_linghuchong`、`n_lf_lanfenghuang`、`n_lj_baiyong`、`n_sl_daopin`、`n_wd_yuanyin`、`n_wd_zhaomin`、`n_xd_pantu`、`n_xx_abao`、`n_xx_ada`、`n_xx_azi`、`n_xx_laodenuo`、`n_xx_litaian`、`n_xx_xuzhu`、`n_xx_yuner`、`n_xx_zhangbao`、`n_ym_lingzhi` | 1.0 |
| 背景 | `yanmen`、`hengshan_s`、`hengshan_s_road`（`assets/art/bg/bg_<id>.png` 已存在） | — |

上表 34 個單位＋3 背景以外的條目一律不動（擁有者擁有的現況）。完成後跑 `data_lint`。

### 2.2 初始造型（16 張 idle）

新增 `look_m01`…`look_m08`、`look_f01`…`look_f08`：`{ "sprite": "look_m01", "scale": 1.0, "y_offset": 0, "required": false, "placeholder": false }`。`player_fallback` 不動。造型沒有 `attack`／`hurt` 圖：`ArtRegistry.unit_texture` 既有規則（第一個有 idle 的角色沒有該姿勢就回 null）不改。

### 2.3 `data/art.json` 新區塊（純表現；不進 `content_hash`）

```json
"map": {
  "world_base":   { "file": "map_world_base",   "required": false, "placeholder": true },
  "region_bg":    { "file": "map_region_bg",    "required": false, "placeholder": true },
  "node_room":    { "file": "map_node_room",    "required": false, "placeholder": true },
  "node_current": { "file": "map_node_current", "required": false, "placeholder": true },
  "node_fog":     { "file": "map_node_fog",     "required": false, "placeholder": true },
  "marker_here":  { "file": "map_marker_here",  "required": false, "placeholder": true },
  "compass":      { "file": "map_compass",      "required": false, "placeholder": true },
  "frame_title":  { "file": "map_frame_title",  "required": false, "placeholder": true }
},
"map_icons": { "city": { "file": "map_icon_city", "required": false, "placeholder": true }, "…": "…" },
"weapon_fx": {
  "sword": { "file": "fx_weapon_sword", "required": false, "placeholder": true }, "…": "…",
  "inner": { "file": "fx_skill_inner",  "required": false, "placeholder": true }, "…": "…"
},
"weapon_icons": { "sword": { "file": "icon_weapon_sword", "required": false, "placeholder": true }, "…": "…" }
```

- `map_icons` 鍵（16）：`city sect cave wild station inn shop master record field wood water stove danger quest exit`（檔名 `map_icon_<鍵>`）。
- `weapon_fx` 鍵（12）：`sword blade staff whip fist claw stab hidden`（檔名 `fx_weapon_<鍵>`）、`inner poison medic formation`（檔名 `fx_skill_<鍵>`）。
- `weapon_icons` 鍵（6）：`sword blade staff whip claw fist`（檔名 `icon_weapon_<鍵>`）。
- 目錄：`assets/art/map/`、`assets/art/fx/`（與既有 fx 同目錄）、`assets/art/icons/`。
- 沒有暫代圖：`placeholder: true` 時 `ArtRegistry` 回 null，呼叫端畫程式備援（WP-NAV、WP-FX）。`import_art.py --placeholders` **不**為新區塊產圖。
- `core/data/data_schema.gd`：`ART_SECTIONS` 加這 4 個鍵；`check_art()` 檢查每個條目有 `file`、鍵在上列清單內、`file` 符合命名（WP-ART 擁有 `check_art`、`_art_cycle`、`ART_*` 常數，§11.2）。舊的 art.json 沒有新區塊時 `check_art` 視為錯誤（本包把區塊加齊）。

### 2.4 `ui/common/art_registry.gd` 新 API（簽名綁定；WP-ART Day-0 先交出空殼）

```gdscript
const MAP_KEYS := ["world_base", "region_bg", "node_room", "node_current", "node_fog", "marker_here", "compass", "frame_title"]
const MAP_ICON_KEYS := ["city", "sect", "cave", "wild", "station", "inn", "shop", "master", "record", "field", "wood", "water", "stove", "danger", "quest", "exit"]
const WEAPON_FX_KEYS := ["sword", "blade", "staff", "whip", "fist", "claw", "stab", "hidden", "inner", "poison", "medic", "formation"]
const WEAPON_ICON_KEYS := ["sword", "blade", "staff", "whip", "claw", "fist"]
static func map_texture(key: String) -> Texture2D        # 沒有圖 → null
static func map_icon(key: String) -> Texture2D           # 沒有圖 → null
static func has_map_art() -> bool                         # world_base 有正式圖
static func weapon_fx_texture(key: String) -> Texture2D  # 沒有圖 → null
static func weapon_icon(key: String) -> Texture2D        # 沒有圖 → null
```

查表一律走 art.json（`file` 欄），找 `res://assets/art/{map,fx,icons}/<file>.png`；結果快取（沿用 `_tex_cache`）；`use_config()` 測試注入照舊可用。

### 2.5 `tools/import_art.py`、`tools/art_register.py`

1. **分類**（`classify`）：`map_world_base`、`map_region_bg`、`map_node_{room,current,fog}`、`map_marker_here`、`map_compass`、`map_frame_title`、`map_icon_<16 鍵>` → `map`；`fx_weapon_<8 鍵>`、`fx_skill_<4 鍵>` → `weapon_fx`；`icon_weapon_<6 鍵>` → `weapon_icon`。其他不認得的檔名照舊警告略過。
2. **處理規格**：

| 類 | 輸出 | 規則 |
|---|---|---|
| `map_world_base` | `map/map_world_base.png` 2400×1800 RGB(A) | 比例偏離 4:3 超過 1% 警告；cover 縮放置中裁切；**不得**裁邊或位移以外的變形（站點對齊靠比例） |
| `map_region_bg` | `map/` 1024×1024 | cover；可無 alpha |
| `map_node_*` | `map/` 384×192 RGBA | 要透明；**不裁邊**（框的邊距是 9 宮格的一部分）；contain 置中 |
| `map_marker_here`、`map_icon_*` | `map/` 256×256 RGBA | 要透明；裁邊後 contain 置中 |
| `map_compass` | `map/` 512×512 RGBA | 同上 |
| `map_frame_title` | `map/` 1024×256 RGBA | 不裁邊；contain |
| `fx_weapon_*`、`fx_skill_*` | `fx/` 1024×512 RGBA | 要透明；裁邊後**靠左、垂直置中** contain（特效的起點＝手的位置＝圖的左緣中點；WP-FX 依此對位） |
| `icon_weapon_*` | `icons/` 256×256 RGBA | 要透明；裁邊後 contain 置中 |

3. **覆寫備份**：寫任何輸出檔之前，若目的檔存在且位元組不同 → 先複製到 `<backup_root>/<YYYY-MM-DD>/<子目錄 units|bg|fx|map|icons>/<檔名>`；同名已存在時檔名加 `-HHMMSS`。參數 `--backup-root`（預設 `K:/Project/JY-Mini-OL-Work/art_backup`）、`--no-backup`（只給單元測試）。備份失敗＝該檔不覆寫並記錯誤。
4. **空手重畫前快照**（WP-ART 交付時執行一次）：`--snapshot` 把 `assets/art/units/unit_{player,look,shaolin,huashan,wudang,quanzhen,xuedao,xingxiu,emei,hengshan,gumu,lingjiu,gaibang}_*.png` 與 `assets/art_in/` 裡同樣前綴的原圖複製到 `<backup_root>/<日期>/snapshot_units/`；交付說明寫實際路徑與檔數。
5. `update_placeholder_flags`、`print_report` 涵蓋新區塊；`--no-json-update` 時一律不寫 art.json。
6. `art_register.py`：多認 `map_*`、`fx_weapon_*`、`fx_skill_*`、`icon_weapon_*` → 把對應條目的 `placeholder` 改 false（條目不存在時照 §2.3 建立）。
7. 新工具 `tools/art_contact_sheet.py`（WP-ART）：Pillow；每列一個條目：idle 圖依 `scale` 縮放，旁邊放 `player_m` 1.0 當比例尺，底下寫 id 與 scale；預設涵蓋 §2.1＋§2.2 的 50 條，`--all` 涵蓋全部 sprite 條目；輸出到 `--out`（預設 `K:/Project/JY-Mini-OL-Work/shots/m3c_art_contact.png`，太長自動分頁 `_2.png`…）。

### 2.6 WP-NPCPK 新 id 的 art 條目（A5）

全部 `alias`，`required: false`、`placeholder: false`：`m_npc_civilian`→`n_dl_cunmin`、`m_npc_child`→`n_hn_longmen`、`m_npc_animal`→`m_wolf`、`m_npc_worker`→`n_xe_miner`、`m_npc_wushi`→`n_xx_wushi`、`m_npc_villain`→`n_bandit_chief`、`m_npc_sl_wuseng`→`n_sl_zhike`、`m_npc_sunpopo`→`n_gm_sunpopo`、`m_npc_dingchunqiu`→`n_xh_dingchunqiu`、`m_npc_xd_laozu`→`n_xd_laozu`；`n_na_xx_huanggou`→`m_wolf`、`n_na_xw_yang`→`m_boar`、`n_na_dl_xiaohai`→`n_hn_longmen`、`n_na_xx_jumin`→`n_dl_cunmin`、`n_na_xe_kuangshi`→`n_xe_miner`、`n_na_xx_eba`→`n_bandit_chief`。（戰鬥時 NPC 攻擊戰的單位圖用 NPC 自己的 id，§5.7；這些條目只是 lint 與後援。）

---

## 3. B：初始造型（WP-LOOKS）

### 3.1 造型表（`core/character/looks.gd`，`class_name Looks`，新檔）

| 編號 | 男（`look_mNN`） | 女（`look_fNN`） |
|---|---|---|
| 0 | 布衣（`player_m`） | 布衣（`player_f`） |
| 1 | 書生 | 俠女 |
| 2 | 獵戶 | 村姑 |
| 3 | 浪子 | 千金小姐 |
| 4 | 少年俠客 | 江湖女子 |
| 5 | 壯漢 | 少女 |
| 6 | 刀客 | 女刀客 |
| 7 | 富家公子 | 醫女 |
| 8 | 西域旅人 | 苗疆少女 |

```gdscript
class_name Looks
extends RefCounted
const LOOK_MAX := 8
const NAMES_M := ["布衣", "書生", "獵戶", "浪子", "少年俠客", "壯漢", "刀客", "富家公子", "西域旅人"]
const NAMES_F := ["布衣", "俠女", "村姑", "千金小姐", "江湖女子", "少女", "女刀客", "醫女", "苗疆少女"]
static func valid(look: int) -> bool                       # 0 ≤ look ≤ LOOK_MAX
static func art_ref(gender: String, look: int) -> String   # 0 → "player_m"/"player_f"；n → "look_m%02d"/"look_f%02d"；不合法 → 0 號
static func battle_look(sect: String, gender: String, look: int) -> String   # sect != "" → "<sect>_<m|f>"；否則 art_ref
static func name_of(gender: String, look: int) -> String
```

### 3.2 角色（`core/character/character.gd`；WP-LOOKS 只動 §11.2 列的地方）

- `var appearance: int = 0`；`from_dict`：`appearance = d.get("appearance", 0)` 轉 int，`Looks.valid` 不過 → 0；`to_dict`：`"appearance": appearance`。
- `battle_look()` 改成 `return Looks.battle_look(sect, gender, appearance)`（戰鬥快照 `look` 自動跟著變）。
- `to_sheet` 加 `"look": battle_look()`、`"appearance": appearance`；`to_summary` 加 `"look": battle_look()`（選角畫面用）。
- 護照：`appearance` 隨角色資料走；`Inventory.to_dict(legacy)` 不受影響。WP-LOOKS 跑既有護照測試確認舊簽章仍驗得過。

### 3.3 主機

- `CharacterFactory.create`（`core/character/character_factory.gd`，WP-LOOKS）：讀 `p.get("look", 0)` 設 `appearance`。
- `server/intents/intents_char.gd`（WP-LOOKS）：`char_create` 帶 `look` 時先 `Looks.valid`，不過回 `bad_look`（範圍檢查已由 `Protocol.INT_RANGES` 擋成 `bad_value:look`，這裡是第二道）；新處理器 `set_look { look }`，旗標 `IDLE`（處理器自己檢查角色；不掛 `NEEDS_CHAR` 才不會被坐牢閘擋下，整合紀錄 I2）：`appearance = look` → 送 `look_changed`（self：`{ look, look_name, shown }`，`shown` = 目前實際顯示的 `battle_look()`）→ `s.sheet_dirty = true`、存檔。坐牢中也可以換。
- 模板（WP-LOOKS 追加到 `text_templates.json`）：`look_changed`（self：「你換上了{look_name}的打扮。」；入派中加一句「（拜在門下時仍穿門派服裝）」用 `{note}` 參數）、`err_bad_look`。

### 3.4 介面

1. 新 `ui/game/char/look_picker.gd`（`class_name LookPicker extends Control`）：3×3 大格，每格 ≥ 150×150 的 idle 立繪（`ArtRegistry.unit_texture(Looks.art_ref(g, i), "PLAYER", "idle")`）＋名稱；選中框朱紅；`signal look_selected(look: int)`；`func set_gender(g: String)`、`func set_selected(i: int)`；鍵盤 1–9 選、方向鍵移動。
2. `char_create.gd`：表單右側放 LookPicker（1280×720 時至少佔右半邊）；性別切換會 `set_gender` 並把選擇重設為 0；`build_args()` 加 `"look": picker.selected`。
3. `attributes_panel.gd`：頭像區顯示目前 `sheet.look` 立繪與「造型：X」；按鈕「更換造型」→ 發 `signal look_change_requested` → 主畫面開 `ui/game/char/look_dialog.gd`（LookPicker＋「確定／取消」，送 `set_look`；入派中顯示提示「拜入門派期間戰鬥中顯示門派服裝」）。
4. `skills_panel.gd` 的人像已讀 `sheet.look`（不改）；`char_select.gd` 用 `summary.look` 顯示（沒有就 0 號）；`learn_dialog.gd`、`npc_dialog.gd`、`story_dialog.gd` 的剪影後援改成 `sheet.look`（取不到用 `player_m`）。
5. 測試：`tests/unit/test_m3c_looks.gd`（`Looks`、`battle_look` 三狀態、存讀、`set_look` 原因碼）、`tests/unit/test_ui_m3c_looks.gd`（LookPicker 過濾、`build_args`、更換造型送出的 intent 形狀）。

---

## 4. C：導航（WP-NAV）

### 4.1 路徑規劃（`ui/game/map/route_planner.gd`，`class_name RoutePlanner`，純靜態、可在 `--script` 跑）

```gdscript
## 全世界房間圖（用目前生效的 tables 的 maps 與 exits；忽略 U/D/IN/OUT 以外的方向沒有差別，全部方向都算）
static func graph(tables: Dictionary) -> Dictionary                  # room_id -> [{ "dir", "to" }]
## 只走 known 裡的房間（起點一定算 known）；回 [from, …, to] 或 []
static func find_path(g: Dictionary, from: String, to: String, known: Dictionary) -> Array
## 目標沒探索：在全圖（含未探索）上從 target 做 BFS，依距離由近到遠找第一個「已探索且從 from 走得到」的房間
static func nearest_known_toward(g: Dictionary, from: String, target: String, known: Dictionary) -> Dictionary   # { "room", "path", "exact": bool }
## 地區目標：該地區已探索房間中離 from 最近的；沒有 → nearest_known_toward(地區的 birth_room 或第一間)
static func region_target(tables: Dictionary, g: Dictionary, from: String, region_id: String, known: Dictionary) -> Dictionary
```

- 迷霧：路徑只含已探索房間；`nearest_known_toward` 只把「目標」當成 BFS 起點，不會把未探索房間放進路徑。
- `exits[].locked` 只在主機的 `view` 裡有；規劃不看，執行時遇到才停（§4.4）。

### 4.2 執行（`ui/game/map/auto_walker.gd` 擴充；狀態機抽成 `ui/game/map/auto_walk_core.gd`，`class_name AutoWalkCore extends RefCounted`，不依賴場景樹，驗收工具直接用）

```gdscript
func start(path: Array, cur_room: String, dest_name: String) -> void
func next_step(view: Dictionary, sheet: Dictionary) -> Dictionary   # { "action": "MOVE", "dir" } | { "action": "WAIT" } | { "action": "STOP", "reason": String } | { "action": "ARRIVED" }
func on_move_result(ok: bool, reason: String) -> void
func on_battle_start() -> void
func on_battle_end(result: String, resume_enabled: bool) -> void    # result：VICTORY / DEFEAT / FLED / ALL_FLED
func remaining() -> int
func progress_text() -> String                                       # 「趕路中：往{dest}（剩{n}步）」
```

### 4.3 快捷目的地（地圖頁尾的「快捷」下拉＋小地圖右鍵選單）

| 項目 | 目標房間 | 不能去的原因 |
|---|---|---|
| 記錄點 | `sheet.respawn.room` | 「還沒設記錄點」 |
| 最近的客棧／茶棚／綠洲 | 已探索房間中、房內有 `INN` 服務 NPC、路徑最短的一間；名稱寫 NPC 所在房間名 | 「附近沒有探索過的客棧」 |
| 本派山門 | `sects[sheet.sect].gate_room` | 「你沒有門派」 |
| 出生城 | `regions[sheet.birth_city].birth_room` | — |
| 任務目標 | `MapPanel.quest_mark` | 「沒有標記任務地點」 |

每項目標沒探索 → 照 `nearest_known_toward`，進度列寫「（只能走到 X，再往前沒去過）」。

### 4.4 停走與續走規則（綁定；`AutoWalkCore.next_step` 依序檢查，第一個成立就停）

| 順序 | 條件 | 原因文字 |
|---|---|---|
| 1 | 戰鬥結果 `DEFEAT`（死亡） | 「你倒下了，停止趕路。」 |
| 2 | 戰鬥結果 `FLED`／`ALL_FLED` 中我方逃走 | 「你逃離了戰鬥，停止趕路。」 |
| 3 | 戰鬥 `VICTORY` 但續走選項關 | 「戰鬥結束，停止趕路。」 |
| 4 | `sheet.qi < sheet.qi_max × 0.30` | 「氣血不足三成，先休息吧。」 |
| 5 | `sheet.food < 20` 或 `sheet.water < 20` | 「又餓又渴，先吃點東西。」（缺哪個寫哪個） |
| 6 | 下一步的出口在 `view.exits` 是 `locked` | 「前方{room}去不了：{lock_reason}」 |
| 7 | 下一間是「要自己決定」的房間且不是終點：房間 `requires` 非空；`jail: true`；是某派 `gate_room` 而玩家不是該派弟子；房內有 `GUIDE` 服務 NPC | 「前方是{room}，請自己決定要不要進去。」 |
| 8 | `move` 被主機拒絕 | 「趕路中斷：{原因碼文字}」 |
| 9 | 坐牢中（`sheet.jail` 非空） | 「身在牢中，無法趕路。」 |

- **續走**：只在「趕路中被遇敵打斷、結果 `VICTORY`、續走選項開、且 4–5 兩條都不成立」時，戰鬥畫面收起後 0.5 秒自動續走（從目前房間重新規劃到原目標）。
- 系統選項：`UiSettings` 新鍵 `"nav.auto_resume"`（bool，預設 true），系統頁「選項」加一列「趕路遇敵獲勝後繼續趕路」。
- Esc：正在趕路且沒有在打字 → Esc **先**停止趕路（「已停止趕路。」），不關視窗也不收燈籠。

### 4.5 「往XXX」邊緣節點（擁有者回報的 bug）

- `RegionMapView` 新 `signal region_clicked(region_id: String)`：點「往XXX」箭頭／標籤 → 發出。`MiniMap` 轉發同名 signal。
- `MapPanel.show_region(region_id: String)`：區域圖改顯示該區（用同一份 `MapMemory.visited` 迷霧），標題「{區名}（瀏覽中）」，頁尾出現「返回目前區域」鈕；點該區已探索房間 → 跨區趕路（§4.1）；玩家移動到別間後畫面**不**自動跳回（直到按返回或抵達）。小地圖相同（標題列多一個「⟲」返回鈕）。
- 目前區域的「往XXX」若那區完全沒探索 → 仍切過去（全是霧），頁尾「那裡還沒去過」。

### 4.6 地圖美術（有圖用圖，沒圖保持現狀）

- **江湖全圖**：`ArtRegistry.has_map_art()` 時：畫面鎖 4:3，底圖畫滿地圖框（不再 `MAX_STRETCH`）；站點像素座標＝`tools/make_map_layout_guide.py` 同一轉換：`x = rect.x + (60/1600 + wp.x/1000 × 1480/1600) × rect.w`、`y = rect.y + (60/1200 + wp.y/1000 × 1080/1200) × rect.h`；城市印章、文字、路線照舊疊上；`compass` 有圖就畫在右下（取代程式羅盤），`frame_title` 有圖就當標題底。沒有底圖 → 現行羊皮紙程式繪圖完全不變。
- **區域圖／小地圖**：`region_bg` 平鋪當底；房間框用 `node_room`／`node_current`／`node_fog` 以 9 宮格（四邊邊距 = 原圖尺寸的 1/6 寬、1/4 高）伸縮到 `BOX`；徽章（田、林、水、灶、驛站、客棧、商店、師父、查小鏞、會遇敵、任務、出口）有 `map_icon_*` 就畫 18–22px 圖示，沒有就用現在的字；「你在這裡」有 `marker_here` 就畫在房間框上方。
- 所有圖都沒有時，既有地圖測試（`test_ui_map_layout.gd`、`test_ui_map_panel.gd`、`test_ui_review_round4.gd`、`test_ui_review_w2001.gd` 的地圖部分）必須照舊通過（畫面行為不變）。

### 4.7 檔案與測試

WP-NAV 擁有 `ui/game/map/**`（含新 `route_planner.gd`、`auto_walk_core.gd`）、`ui/common/ui_settings.gd`、`ui/game/panels/system_panel.gd`、`ui/game/main/mini_map.gd`、`ui/game/main/main_screen.gd`（§11.2 其他 WP 的掛點除外）。測試：`tests/unit/test_m3c_route.gd`（跨區最短路、迷霧、目標未探索、地區目標、快捷目的地挑選）、`tests/unit/test_m3c_autowalk.gd`（§4.4 每一條停走、勝利續走、選項關閉不續走、Esc）、`tests/unit/test_ui_m3c_nav.gd`（「往XXX」切區與返回、全圖有／無底圖的站點座標）。

---

## 5. D：攻擊 NPC（WP-NPCPK；也是 core 擁有者）

### 5.1 NPC 資料欄位（`data/npcs.json`，可選欄位 `attack`）

```json
"attack": {
  "mode": "KILL",                 // KILL：NPC 被殺會暫時消失、依 respawn 重生；CHALLENGE：NPC 永不消失，只「敗走」
  "category": "CIVILIAN",         // §5.4 表
  "monster": "m_npc_civilian",    // 戰鬥單位用的怪物列（數值、掉落、善惡殺氣）；單位圖用 NPC 自己的 id（§5.7）
  "group": [ { "monster": "m_wd_guard", "count": [3, 3] } ],   // 選填：同時出場的其他單位（滅派、門人）
  "group_repeat": [ { "monster": "m_gm_guard", "count": [4, 4] } ],  // 選填：同一角色第二次以後改用這組（引擎支援；第二輪審查後沒有資料使用）
  "via": "CTRL",                  // CTRL：Ctrl+點；MENU：只在對話選單（「滅派」）；BOTH
  "menu_label": "滅派",           // via 含 MENU 時必填
  "sect": "wudang",               // 選填：門派後果用；省略＝SectSystem.npc_sect(npc)
  "event": "",                    // 選填："MIEPAI" | "ATTACK_MASTER"；省略＝依 category 推（§5.6）
  "requires": [],                 // 選填：動手條件（Requirements 條件組；例 滅派要 no_sect 或 sect_not）
  "respawn": 3,                   // KILL 才有：重生的時辰數（1 時辰 = 遊戲 2 小時）；省略＝類別預設
  "src": "verified", "src_note": "…"
}
```

### 5.2 誰可以打（綁定清單；WP-NPCPK 照填，其他 NPC 一律沒有 `attack`）

| NPC | 名稱 | mode | category | 戰鬥單位 | via | 出處 |
|---|---|---|---|---|---|---|
| `n_dl_cunmin` | 大理村民 | CHALLENGE | CIVILIAN | `m_npc_civilian` | CTRL | 官方「城市居民」；任務有引用 → 不消失 |
| `n_dl_furen` | 婦人 | CHALLENGE | CIVILIAN | `m_npc_civilian` | CTRL | 同上（任務、環境句有引用） |
| `n_xx_caishang` | 菜商 | CHALLENGE | CIVILIAN | `m_npc_civilian` | CTRL | 同上（任務有引用） |
| `n_xe_miner` | 老礦工 | CHALLENGE | WORKER | `m_npc_worker` | CTRL | 2002「採礦師」；環境句有引用 → 不消失 |
| `n_na_xe_kuangshi`（新） | 採礦師 | KILL | WORKER | `m_npc_worker` | CTRL | 2002「採礦師」；放 `xe_mine` |
| `n_na_xx_jumin`（新） | 城市居民 | KILL | CIVILIAN | `m_npc_civilian` | CTRL | 官方「城市居民」；放 `xx_minfang` |
| `n_na_dl_xiaohai`（新） | 小孩 | KILL | CHILD | `m_npc_child` | CTRL | 官方「小孩」；放 `dl_square` |
| `n_na_xx_huanggou`（新） | 黃狗 | KILL | ANIMAL | `m_npc_huanggou`（第二輪審查；掉黃狗肉） | CTRL | 2001-10 丐幫心得「小黃狗…西夏、大理最兇」→ **era 1.0B**（第二輪審查）；2003 FAQ「黃狗 PK 戰鬥模式」；放 `xx_street`（揚州不存在） |
| `n_na_xw_yang`（新） | 羊 | KILL | ANIMAL | `m_npc_animal` | CTRL | 2002「羊」；放西夏城外有草地的野外房間（`xw_grass`；不存在則選最近的西夏郊外房間並寫 src_note） |
| `n_xx_guard`、`n_dl_guard`、`n_jc_guard`、`n_jc_guard_n` | 城門守衛 | KILL | GUARD | `m_city_guard` ×2 | CTRL | news_4-2「城中的守衛」 |
| `n_xx_wushi`、`n_dl_wushi` | 武館教頭 | CHALLENGE | WUSHI | `m_npc_wushi` | CTRL | news_4-2「武館的武師」 |
| `n_na_xx_eba`（新） | 街頭惡霸 | KILL | VILLAIN | `m_npc_villain` | CTRL | 官方「惡人、強盜」；放 `xx_street`；名稱【設計提案】（惡人頭子 `n_amb_etou_*` 屬遊蕩惡人系統，照 O5 不加 attack） |
| `n_wd_zhike` | 武當知客道長 | CHALLENGE | SECT_GATE | `m_wd_guard` ×3 | MENU「滅派」 | mengpai/2；`requires: [{ "type": "sect_not", "sect": "wudang" }]`（孫婆婆、全真知客同理） |
| `n_gm_sunpopo` | 孫婆婆 | CHALLENGE | SECT_GATE | `m_npc_sunpopo`＋`m_npc_gm_dizi` ×5（每次；第二輪審查拿掉「再次 ×3」） | MENU「滅派」 | mengpai/5（動手＝公敵，2001）；2002 攻略 6→4 在 2001 規則下走不到 |
| `n_qz_zhike` | 全真知客道長 | CHALLENGE | SECT_GATE | `m_npc_qz_gate` ×4（第二輪審查：有獎勵的門口列） | BOTH「硬闖」 | mengpai/6、gaoshou/31（一場 160 學點） |
| `n_hg_zhike` | 恆山知客弟子 | CHALLENGE | SECT_GATE | `m_npc_hg_gate` ×2 | CTRL | mengpai/7 |
| `n_sl_zhike` | 少林知客僧 | CHALLENGE | SECT_GATE | `m_npc_sl_wuseng` ×3 | CTRL | mengpai/1「打知客僧＝硬闖少林」 |
| `n_em_gatedizi` | 峨嵋弟子 | CHALLENGE | SECT_GATE | `m_npc_em_gate` ×2 | CTRL | 2002 攻略「點門口峨嵋弟子」（公敵【設計提案】比照全真／恆山） |
| `n_lj_zhike` | 靈鷲守門女弟子 | CHALLENGE | SECT_GATE | `m_npc_lj_gate` ×2 | CTRL | 比照【設計提案】 |
| `n_xh_menren` | 星宿門人 | CHALLENGE | SECT_DISCIPLE | `m_npc_xh_gate` ×2 | CTRL | 比照血刀「硬闖」【設計提案】（不設公敵） |
| `n_xd_guard` | 血刀弟子 | CHALLENGE | SECT_DISCIPLE | `m_npc_xd_gate` ×2 | CTRL | mengpai/4「硬闖」（不設公敵）；gaoshou/31 血刀派一場 60 學點 |
| `n_wd_beizhong`、`n_wd_zhongfei`、`n_wd_nanyu`、`n_wd_xiyun` | 武當弟子 | CHALLENGE | SECT_DISCIPLE | `m_wd_guard` ×1 | CTRL | 官方「攻擊武當門人」；2002「武當大廳隨機弟子」 |
| `n_xh_dingchunqiu` | 丁春秋 | CHALLENGE | SECT_MASTER | `m_npc_dingchunqiu` | CTRL | 官方 2001/8/7「對丁春秋下PK指令」；`event: "ATTACK_MASTER"` |
| `n_xd_laozu` | 血刀老祖 | CHALLENGE | SECT_MASTER | `m_npc_xd_laozu` | CTRL | 同上；`event: "ATTACK_MASTER"` |

- 新 NPC（`n_na_*`）：`kind: "STORY"`、`services: []`、`talk` 模板（`talk_n_na_*`，一兩句）、`era: "1.0A"`、`src: "proposal"`、`src_note` 寫研究出處；WP-NPCPK 同時把 id 加進該房間 `data/maps/<region>.json` 的 `npcs`。
- 受保護（O5）：清單以外一律不能打；Ctrl+點受保護 NPC → 本機直接顯示「{name}不是你能動手的對象。」（`npc_not_attackable`）。

### 5.3 主機：`server/npc_attack_system.gd`（`class_name NpcAttackSystem`，`GameHost.npcpk`）

```gdscript
func attack(s: Session, npc_id: String, mode: String) -> Dictionary     # npc_attack 的處理器；mode "ATTACK"（Ctrl）或 "MIEPAI"（選單）
func view_entry(s: Session, npc_id: String) -> Variant                  # 房間 view 的 npcs[].atk：{ mode, category, align, sect, menu_label, warn } 或 null
func menu_fields(s: Session, npc_id: String) -> Dictionary              # npc_menu.attack：{ ok, reason, label, warn } 或 {}
func npc_down(npc_id: String) -> bool                                   # 正在消失（KILL 後、重生前）
func on_battle_finished(entry: Dictionary, out: Dictionary) -> void     # BattleSystem._finish 結尾呼叫
func tick(now_s: float) -> void                                         # 每分鐘：到時重生、送 na_npc_back 給房內玩家
```

**`attack` 驗證順序**（第一個失敗就回原因碼）：
1. 規則 `npc_attack` 為 false → `npc_attack_off`。
2. NPC 不在這間（含消失中）→ 既有的 NPC 不在原因碼（`GameHost.npc_here` 回的那個）。
3. 沒有 `attack`、或 `via` 不允許這個 mode → `npc_not_attackable`。
4. 房間 `safe: true` → `npc_safe_room`。
5. 坐牢中 → 既有 `jailed`。
6. 這個 NPC 已在一場攻擊戰中 → `npc_busy`（回應附 `battle_id`，客戶端可提示加入）。
7. `attack.requires` 不成立 → 對應的 `req_*` 原因碼。
8. 成功：鎖定 NPC（`_busy[npc_id] = battle_id`）；先處理「動手就算」的門派後果（§5.6 的 ATTACK 類）；開戰：`host.battles.start_ex(s, ids, "NPC_ATTACK", { "npc": npc_id, "npc_unit": true, "no_flee": false })`，`ids` = [`attack.monster`] ＋ group；第一個單位的 spec 帶 `"ref": npc_id`、`"monster_row": attack.monster`、`"npc": npc_id`（獎勵用 `monster_row`；圖用 `ref`）；送 `na_attack_start`（self／room）。

**戰鬥結束 `on_battle_finished`**：解鎖；若 NPC 單位（spec.npc）死亡且玩家方勝：
- `KILL`：`world.npc_down[npc_id] = { "until_s": now + respawn 時辰 × 600 × npc_respawn_pct/100, "by": char_id }`（世界秒；1 時辰 = 遊戲日 ÷ 12 = 600 世界秒；整合紀錄 I3）；房內玩家 `view_dirty`；送 `na_npc_killed`（self／other／room）。
- `CHALLENGE`：送 `na_npc_routed`（「{npc}敗走，退回了{room}。」）；NPC 不消失。
- 善惡、殺氣由既有戰鬥獎勵依 `monster_row` 的 `morality_on_kill`、`killing_intent_on_kill` 給最後一擊者（§5.4 表的數值寫在 `m_npc_*` 列；group 用的既有門派守衛列照它們的值）。
- 門派後果中「殺了才算」的部分（§5.6 KILL 類）。
- 守衛反應（§5.5）。
- 玩家輸或逃：NPC 不消失，什麼都不結算（「動手就算」的已經算過）。

**消失與重生**：`world.npc_down` 惰性建立；`RegionSystem` 房間 view 不列消失中的 NPC；`GameHost.npc_here` 對消失中的 NPC 回「不在」；`tick` 到時刪除並對該房間的人送 `na_npc_back`（「{npc}又出現在這裡。」）。主機重開時照存檔的 `until_s` 繼續（世界凍結時不前進，與世界時鐘一致）。

### 5.4 類別數值（`m_npc_*` 列與預設重生；全部【設計提案】，量級比照既有 `monsters.json`）

| category | 陣營 | 善惡／每殺 | 殺氣／每殺 | 預設重生 | 戰鬥單位強度（`combat_xp_ref`） | 掉落 | 出處 |
|---|---|---|---|---|---|---|---|
| CIVILIAN 城市居民 | GOOD | −10 | +10 | 3 時辰 | 200（新手可勝） | 無 | 善惡方向【已證實 官方】；量【設計提案】 |
| CHILD 小孩 | GOOD | −20 | +20 | 3 時辰 | 50 | 無 | 同上 |
| ANIMAL 小動物 | GOOD | −3 | +2 | 1 時辰 | 60 | 肉或皮（既有物品，機率 0.5） | 同上；「黃兔、羊」2002 |
| WORKER 採礦師 | GOOD | −10 | +10 | 3 時辰 | 300 | 無 | 2002「採礦師」 |
| GUARD 守衛 | NEUTRAL | −5 | +10 | 1 時辰 | 既有 `m_city_guard` | 無 | 「城中的守衛」 |
| WUSHI 武館武師 | GOOD | −10 | +10 | （不消失） | 50000（「超強」）；`no_rewards: false`、學點低 | 無 | news_4-2 |
| VILLAIN 惡人 | EVIL | +10 | +5 | 6 時辰 | 3000 | 少量銀兩 | 官方「惡人、強盜」 |
| SECT_GATE、SECT_DISCIPLE | 依門派 | 依既有門派守衛列 | 同 | （不消失） | 既有 `m_<sect>_guard`；少林 `m_npc_sl_wuseng` 150000 | 既有 | 各門派頁 |
| SECT_MASTER 丁春秋、血刀老祖 | EVIL | +10 | +20 | （不消失） | 1000000（不可能單挑贏） | 無 | 2001/8/7 |
| 孫婆婆 `m_npc_sunpopo` | GOOD | −10 | +10 | （不消失） | 60000 | 無 | 2002「實戰 6 萬」 |

新怪物列（WP-NPCPK，`data/monsters.json`，只追加）：`m_npc_civilian`、`m_npc_child`、`m_npc_animal`、`m_npc_worker`、`m_npc_wushi`、`m_npc_villain`、`m_npc_sl_wuseng`、`m_npc_sunpopo`、`m_npc_dingchunqiu`、`m_npc_xd_laozu`；形狀照既有列，`era: "1.0A"`、`src: "proposal"`。

### 5.5 守城官兵（`server/pk_system.gd`，WP-NPCPK）

新公開函式 `func guard_strike(s: Session, n: int, reason_key: String) -> bool`：`guards_enabled` 開、玩家活著且不在戰鬥中時，送 `reason_key` 事件（`na_guard_alarm`：「城中守衛聞聲趕來：「大膽狂徒，竟敢當街行兇！」」）並以既有 `"GUARD"` 戰鬥開打 `n` 名 `m_city_guard`。觸發：主單位類別是 CIVILIAN／CHILD／ANIMAL／WORKER（n=1）或 GUARD（n=2）的攻擊戰以玩家勝利結束（KILL、CHALLENGE 都算），且房間所在地區 `type == "CITY"` 並有官兵（既有 `_has_guard`）。既有「善惡負／PK 高進出城被追殺」照舊。

### 5.6 門派後果（`server/sect_system.gd`，WP-NPCPK）

新門規事件（`DataSchema.SECT_RULE_EVENTS` 加 `ATTACK_SECT_NPC`、`KILL_GOOD_NPC`、`ATTACK_MASTER`）。

| 何時 | 誰 | 後果 | 出處 |
|---|---|---|---|
| 動手時（ATTACK 類） | 本派弟子攻擊本派任何可打的 NPC（`attack.sect == ch.sect`；SECT_MASTER 見下一列） | 觸發 `ATTACK_SECT_NPC` 事件 → 各派 `<p>_r_attack_npc` 門規 → 既有 `breach()`（JAIL／EXPEL／BAN 依世界模式） | 武當 index_jy2-22【已證實】；峨嵋 mengpai/3【已證實】；其他派【設計提案】比照同門相殘 |
| 動手時 | 本派弟子攻擊 SECT_MASTER（丁春秋／血刀老祖，`event: ATTACK_MASTER`） | `SectSystem.force_betray(s, sect_id, "ATTACK_MASTER")`：照既有叛派（武功減半、`sect_traitor`、`sect_enemies`），送 `na_master_betray` | 官方 2001/8/7【已證實】 |
| 動手時 | 外人攻擊 SECT_GATE、選「滅派」、或攻擊 SECT_MASTER | `SectSystem.make_enemy(s, sect_id, cause)`：加入 `ch.sect_enemies`（已是公敵不重複）、送 `na_sect_enemy`；之後既有 `hostile_entry`、執法者捉拿、`ENEMY` 監獄照常 | mengpai/2、5、6、7【已證實】；峨嵋、靈鷲、少林【設計提案】 |
| 動手時 | 外人攻擊 SECT_DISCIPLE（星宿門人、血刀弟子、武當弟子） | 不設公敵；武當弟子（外人）照 `n_wd_*` 的 `attack.event` 留空 → 只開戰（武當公敵只由滅派或擅闖產生） | mengpai/4「硬闖」 |
| 殺了才算（KILL 類） | 本派是 huashan、hengshan 的弟子殺了 GOOD 陣營 NPC 單位（KILL 或 CHALLENGE 的主單位） | 觸發 `KILL_GOOD_NPC` → `hs_r_kill_good_npc`、`hg_r_kill_good_npc` → 既有 `breach()` | mengpai/9、7【已證實】 |
| 殺了才算 | 本派是 shaolin、hengshan | `sects.sect_skill_penalties` 新觸發 `{ "trigger": "KILL_NPC_ALIGNMENT", "alignment": "GOOD", "levels": 1 }` → 佛法／慈悲降 1 級 | mengpai/1、7【已證實：會扣】；量【待考證】 |
| 殺了才算 | 本派是 emei | 既有 `sect_skill_gain KILL_ALIGNMENT EVIL` 對 NPC 戰鬥單位照常（殺惡人升斷惡） | mengpai/3 |

`data/sect_rules.json` 新列（WP-NPCPK）：11 派各一列 `<p>_r_attack_npc`（`tier BREACH`、`kind EVENT`、`event ATTACK_SECT_NPC`、模板 `rule_<p>_attack_npc`）；`hs_r_kill_good_npc`、`hg_r_kill_good_npc`（`event KILL_GOOD_NPC`）。前綴 `<p>` 照既有（`sl hs em gm hg lj qz wd xh xd gb`）。`data/sects.json`：shaolin、hengshan 的 `sect_skill_penalties` 各加上表那一列；shaolin 的 `hostile_entry` 加 `{ "if": [{ "type": "enemy_of", "sect": "shaolin" }], "rooms": "ALL", "monster": "m_npc_sl_wuseng", "count": [1, 2], "chance": 1.0, "no_flee": true, "capture": false }`（少林原本沒有公敵執法）。

`SectSystem` 新公開函式（WP-NPCPK）：

```gdscript
func on_npc_attack(s: Session, npc_id: String, attack: Dictionary) -> void      # 動手時：ATTACK 類後果
func on_npc_killed(s: Session, ch, npc_id: String, attack: Dictionary, alignment: String) -> void   # 殺了才算的後果
func make_enemy(s: Session, sect_id: String, cause: String) -> void
func force_betray(s: Session, sect_id: String, rule_id: String) -> void
```

### 5.7 戰鬥畫面的 NPC 單位

攻擊戰的主單位 spec：`ref = npc_id`（快照 `ref` 給圖，用 NPC 立繪）、`name = NPC 名`、`monster_row = attack.monster`（數值與獎勵）。`BattleRewards.compute` 已用 `spec.monster_row`（不改）。戰鬥種類 `"NPC_ATTACK"`：不拉隊友（不在 `PULL_KINDS`）、可用 `battle_join` 加入（既有規則）、不是 PvP。

### 5.8 介面（WP-NPCPK）

1. `scene_panel.gd`：NPC 按鈕 Ctrl+左鍵（`UiSocial.pk_modifier_down`）→ `signal npc_attack_requested(npc: Dictionary)`（npc ＝ view 的 npcs 項目）；`npcs[].atk` 為 null 時本機直接在訊息列顯示 `err_npc_not_attackable`，不送。可打的 NPC 名字滑鼠提示加「（Ctrl+點：動手）」。
2. 主畫面 `request_npc_attack(p: Dictionary)`（§11.2 掛點）：確認框（紅色確定鈕「動手」），內文由 `ui/game/social/npc_attack_ui.gd`（新，靜態）`confirm_text(npc_entry, sheet) -> String` 產生：善惡變化（「殺死善良的人，善惡會下降」）、城內會招來官兵、門派後果（「你是武當弟子，對同門動手會違反門規」「動手後你將成為古墓派公敵」「對丁春秋動手＝叛出星宿派」）、CHALLENGE 寫「此人不會被你殺死，但後果照算」。
3. `npc_dialog.gd`：`npc_menu.attack` 非空時多一個紅字選項（`label`，例「滅派」），灰掉時附原因；按下先跳同樣的確認框，確定送 `npc_attack { npc, mode: "MIEPAI" }`。
4. 測試：`tests/unit/test_ui_m3c_npc_attack.gd`（Ctrl+點送出、受保護不送、確認文字三種門派情境、滅派選項）。

### 5.9 資料一覽（WP-NPCPK 寫入）

- `data/npcs.json`：§5.2 的 `attack` 欄位；新列 `n_na_xx_jumin`、`n_na_dl_xiaohai`、`n_na_xx_huanggou`、`n_na_xw_yang`、`n_na_xe_kuangshi`、`n_na_xx_eba`。
- `data/monsters.json`：§5.4 的 10 列 `m_npc_*`。
- `data/maps/*.json`：只把 6 個新 NPC 加進房間 `npcs`。
- `data/sect_rules.json`、`data/sects.json`：§5.6。
- `data/text_templates.json`：`na_attack_start`、`na_npc_killed`、`na_npc_routed`、`na_npc_back`、`na_guard_alarm`、`na_sect_enemy`、`na_master_betray`、`na_miepai`、`rule_<p>_attack_npc` ×11、`rule_hs_kill_good_npc`、`rule_hg_kill_good_npc`、`talk_n_na_*` ×6、`err_npc_attack_off`、`err_npc_not_attackable`、`err_npc_safe_room`、`err_npc_busy`。
- lint（`tools/data_lint.gd`，WP-NPCPK）：`attack` 欄位型別與列舉；`monster`／`group[].monster` 存在；`via` 含 MENU 必有 `menu_label`；**`KILL` 的 NPC 不得**有 `QUEST TEACH JOIN SHOP INN RESPAWN TRAVEL BANK ESCORT ORG JAIL RANK GUIDE MEAL` 服務、不得被任何任務（`quests.json` 全文出現該 id）、`wanderers`、`ambient`、`reactions` 引用；SECT_* 類別必須有門派（`sect` 或 `npc_sect`）；`ATTACK_MASTER` 只能用在 `SECT_MASTER`。

---

## 6. E：裝備與打寶（WP-LOOT）

### 6.1 稀有度（`items.json` 新欄位 `rarity`，預設 `COMMON`）

| 值 | 名稱 | 顏色 | 用途 |
|---|---|---|---|
| `COMMON` | 凡品 | `#e8e0d0` | 一般商店貨、怪物素材 |
| `FINE` | 良品 | `#6fcf6f` | 較好的商店貨、精英常見掉落 |
| `RARE` | 精品 | `#5b9bf0` | 精英稀有、頭目常見 |
| `TREASURE` | 珍品 | `#b77ae8` | 頭目稀有；具名秘笈；**觸發【江湖傳聞】** |
| `DIVINE` | 神兵 | `#f0b43a` | 神兵利器；全服唯一 |

顏色常數放 `ui/game/econ/loot_ui.gd`（新，靜態：`rarity_color(r) -> Color`、`rarity_name(r) -> String`），所有介面共用。

### 6.2 物品資料（`data/items.json`，WP-LOOT 擁有）

**既有欄位不變**；新可選欄位：`rarity`、`official`（`{ "atk": int, "def": int, "weight": int }` 官方原值）、`requires`（條件組）、`bonus`（`{ "<attr id>": int }`，只限 `Character.ATTR_IDS`）、`manual`（§6.4）、`divine`（bool）、`unique_world`（bool）、`no_drop`（bool）、`keep_on_death`（bool）、`fx`（WP-FX 用：`"claw"` 表示爪類）。

**換算（O13）**：`atk` = 官方攻擊力；`def` = ⌈官方防禦力 ÷ 5⌉；`weight` = ⌈官方重量 ÷ 2⌉；武器 `def` = 0。

1. **修正既有 25 列**：武器 `def` → 0（那是誤讀的重量）；有官方對應的列補 `official` 並把 `atk`／`weight` 照換算（`w_mudao` 4／4、`w_chaidao` 5／6、`w_dandao` 10／6、`w_gangdao` 15／7、`w_tiejian` → 官方鐵劍 15／6 並改 `src: verified`；`a_cubudaopao` 20／8 → def 4、weight 4；`a_douli` 斗笠 2／42 → def 1、weight 21【斗笠重量照印、可能錯字：寫 todo】）；既有帽子類（`a_tupimao`、`a_douli`）改 `slot: "HEAD"`。
2. **新增官方武器**（`w_lt_*`，`src: verified`，`src_note` 寫 jyfree 頁）：刀 卜刀、苗刀、雁翎刀、天竺彎刀、青銅刀；劍 匕首、青銅短劍、玉劍、新月匕首（官方重 20；17173 寫 4，寫 todo）、秦劍、松紋劍、黑劍；鞭 鐵鍊、馬鞭、拂塵、珠索；杖（`STAFF`）鐵尺、哭喪棒；空手（`FIST`，`fx: "claw"` 只給鋼爪）鋼爪、手指虎、掌心虎。**槍**（長矛、槍）不做（本作沒有槍法武功，裝了只能普攻；寫 todo）。
3. **新增官方防具**（`a_lt_*`，`src: verified`）：衣 羊皮襖子、玄武長袍、射日短衣、便捷短衣、沙彌裝、牛皮背心、羽裳（`requires gender F`）；帽 帽子、紅鐵帽、羊皮帽、綠棉帽（後三 `gender M`）、木簪（`gender F`）；護腕 玉鐲、金絲鐲（`F`）、鐵項護手、異芒護手、霞光護腕、輕巧護手；戒 指環、結婚戒指；披風 粗布、精神、雷霆、雪雲、青銅、綠石、羊毛（定力加成放 `bonus.cal`）；鞋 皮靴、絕影靴、普通靴、速行靴、風速靴、加速靴；項鍊 金鍊子。性別條件寫法 `"requires": [{ "type": "gender", "value": "F" }]`。`bonus` 鍵對照：定力 `cal`、福緣 `luck`、臂力 `str`、機敏 `agi`、悟性 `wit`、膽識 `guts`、根骨 `con`；殺氣、聲望類加成只寫描述、不實作。
4. **傳家系列**（O20）：`w_lt_chuanjia_dao` 傳家寶刀（BLADE atk 4）、`a_lt_chuanjia_jia` 傳家寶甲（ARMOR def 4）、`a_lt_chuanjia_xie` 傳家寶鞋（BOOTS def 1）；名稱【已證實 2001-06-30】、數值【設計提案】、`price: 1`、`no_sell: true`；不放商店、不放掉落。
5. **價格**：有 2003-01-26 官方價的照抄（`src_note`「2003 降價後，只代表相對價位」）；其他【設計提案】依攻防插值；全部經 `econ` 平衡案例（§12.2）。
6. **商店**（`data/npcs.json` 只改 `shop.items`）：西夏 `n_xx_smith`、大理、京城兵器鋪加 COMMON／FINE 的新武器與防具（每家 ≤ 12 件新貨，依城市分配：西夏刀劍、大理劍鞭、京城刀杖與防具）；RARE 以上不上架。
7. **固定 id**（其他人引用的；其餘新列由 WP-LOOT 依 `w_lt_<拼音>`／`a_lt_<拼音>` 命名）：`a_lt_maozi` 帽子、`a_lt_zhihuan` 指環、`a_lt_yushang` 羽裳、`a_lt_jinlianzi` 金鍊子、`w_lt_heijian` 黑劍、`w_lt_gangzhua` 鋼爪（`fx: "claw"`）、`a_lt_hongshijie` 紅石戒（見下）。
8. **頭目專屬**：`a_lt_hongshijie` 紅石戒（RING、def ⌈15÷5⌉=3、`bonus.cal 5`、`TREASURE`；研究 鬼王→紅石戒【low：2019 來源】）、`a_lt_huangzhaojia` 黃罩甲（若既有 `a_jcn_huangzhaojia` 存在就用既有 id，不重建）等，`src_note` 寫 gaoshou/25、26。

### 6.3 裝備欄（`core/character/inventory.gd`、`derived_stats.gd`，WP-LOOT）

- `Inventory.SLOTS := ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"]`（`ARMOR`＝衣服）；`equipped` 預設 8 鍵空字串。
- `from_dict`：舊存檔只有 2 鍵 → 其他補空；新函式 `func fix_slots(tables: Dictionary) -> bool`：已裝備的物品若物品表的 `slot` 與所在鍵不同 → 搬到正確的鍵（目的鍵已有東西則卸下舊的那件，留在背包）；呼叫點與既有 `consolidate(tables)` 同處。
- `to_dict(legacy := true)` 的輸出**必須與現在逐位元組相同**（只有 `WEAPON`、`ARMOR`，護照舊簽章）；`legacy == false` 輸出 8 鍵。
- `equip`：檢查物品 `requires`（`Requirements.check` 既有條件；回 `req_<type>`，例 `req_gender`）；`divine` 照常可裝。
- `DerivedStats.compute`：`armor_power` = 7 個防具欄的 `def` 加總；`attrs` 加上所有已裝備物品的 `bonus`（`effective_attrs` 處理，WP-LOOT）。
- 角色表（`to_sheet`）：`equipped` 8 鍵；每個背包物品項目加 `rarity`、`slot`、`req_ok`（bool）、`req_text`（不合時的條件文字）、`bonus`、`official`（有才給）。
- 死亡懲罰：`keep_on_death` 的物品不掉（`core/character/death_penalty.gd`）；`no_drop` 的物品 `drop_item` 回 `divine_locked`；錢莊 `bank_put` 由 `bankable` 既有規則擋（神兵列不給 `bankable`）。

### 6.4 秘笈（`manual_read`；O17）

物品欄位：

```json
"manual": { "skill": "basic_medic", "cap": 60, "literacy_min": 20, "prof": 6, "jing": 15, "shen": 15, "requires": [] }
```

固定 id（`tab: "OTHER"`、`usable: false`、`stack: 1`、`era: "1.0A"`、`src: "proposal"`、`src_note`「名稱見 17173 武功密笈（無日期）；秘笈系統 2002-08-21 起，本作依擁有者要求提前【設計提案・非原作】」）：

| id | 名稱 | 技能 | cap | literacy_min | 稀有度 | 額外 |
|---|---|---|---|---|---|---|
| `bk_jian_tupu` | 劍法圖譜 | `basic_sword` | 30 | 10 | FINE | 名稱【設計提案】 |
| `bk_dao_tupu` | 刀法圖譜 | `basic_blade` | 30 | 10 | FINE | 同上 |
| `bk_quan_jing` | 拳經 | `basic_fist` | 30 | 10 | FINE | 同上 |
| `bk_huqingniu` | 胡青牛醫書 | `basic_medic` | 60 | 20 | RARE | 名稱【17173】 |
| `bk_wangnangu` | 王難姑毒經 | `basic_poison` | 60 | 20 | RARE | 名稱【17173】 |
| `bk_wumu` | 武穆遺書 | `basic_formation` | 60 | 30 | TREASURE | 名稱【17173】 |
| `bk_huatuo` | 華陀內昭圖 | `basic_medic` | 80 | 40 | TREASURE | 名稱【17173】 |
| `bk_jinshe` | 金蛇密笈 | `basic_sword` | 80 | 40 | TREASURE | `manual.requires: [{ "type": "attr_min", "attr": "wit", "value": 25 }]`（「資質不佳者無以習得」；門檻數字【設計提案】） |

`LootSystem.read_manual(s, uid, times)`（`times` 1–10）驗證順序：規則 `manuals` 關 → `manuals_off`；找不到物品 → `no_such_item`；沒有 `manual` → `not_manual`；`basic_literacy < literacy_min` → `manual_illiterate`；`manual.requires` 不成立 → `req_*`；目標等級上限 `cap_eff = min(manual.cap, basic_literacy 等級, host.skill_cap(ch, skill))`，現在等級 ≥ `cap_eff` → `manual_cap`；精或神不夠 → 既有 `not_enough_jing`／`not_enough_shen`。每讀一次扣 `jing`、`shen`，`ch.skills.add_prof(skill, prof, tables, cap_eff)`；送 `lt_manual_read`（self：讀了幾次、升級提示）；秘笈**不消耗**。純邏輯放 `core/character/learning.gd` 新靜態函式 `read_manual(ch, item_row, times, tables, cap_extra) -> Dictionary`（WP-LOOT）。介面：背包選秘笈時「研讀」鈕（次數 1／5／10）＋說明「讀書識字 X 級：最多讀到 Y 級」。

### 6.5 神兵（O15、O16）

| id | 名稱 | 類型 | 戰鬥 atk | 官方 | 其他 |
|---|---|---|---|---|---|
| `w_sb_yitian` | 倚天劍 | SWORD | 80 | 200、殺氣+80、重 45（17173） | weight 23 |
| `w_sb_xuantie` | 玄鐵重劍 | SWORD | 86 | 215、殺氣+50、重 60（17173） | weight 30 |
| `w_sb_tulong` | 屠龍刀 | BLADE | 84 | 官方價 421053；數值【待考證】 | weight 30 |

全部 `rarity: DIVINE`、`divine: true`、`unique_world: true`、`no_sell: true`、`no_drop: true`、`keep_on_death: true`、`era: "1.0A"`、`src: "later"`、`src_note`「2002-04 武林大會（gmdk 期）獎品；本作依擁有者要求以極稀有掉落提前【設計提案・非原作】」。（殺氣加成只寫在描述，不實作。）

- **世界登記**：`world.divine = { item_id: char_id }`（惰性建立）。掉落、轉移、管理員給都更新；擲掉落時若登記的持有者角色不存在或身上沒有該物品 → 釋放登記（惰性校正）。
- **掉落**（規則 `divine_source == "BOSS_DROP"`）：只在 §6.6 標了 `divine: true` 群組的掉落表（3 個頭目）擲，機率 0.002；該神兵已有人持有 → 這一擲作廢（不補擲別的）。
- **PvP 轉移**：`LootSystem.on_pvp_kill(killer_char_id, victim_char_id, summary)`（`PkSystem.on_pvp_end` 對每個被玩家殺死的玩家呼叫；叫戰、強制、捉拿都算——xinshou/11「不管是以何種方式」）：受害者身上（含已裝備）所有 `divine` 物品移給殺手（無視負重上限；已裝備的先卸下）、更新登記、送 `lt_divine_transfer`（self／target）並發【江湖傳聞】`lt_rmr_divine_transfer`。殺手離線或不存在（死於同歸於盡）→ 物品留在受害者身上。

### 6.6 掉落表（新表 `data/loot_tables.json`，WP-LOOT 擁有；DataLoader 由 WP-NPCPK Day-0 加入 `FILES` 與 `OPTIONAL_FILES`）

```json
{ "table": "loot_tables", "version": 1, "rows": [
  { "id": "lt_m_guiwang", "era": "1.0A", "src": "proposal", "src_note": "…",
    "guaranteed": [ { "item": "c_qiyao", "min": 2, "max": 3 } ],
    "groups": [
      { "chance": 0.30, "pick": [ { "item": "a_lt_jinlianzi", "w": 60 }, { "item": "w_lt_heijian", "w": 40 } ] },
      { "chance": 0.05, "pick": [ { "item": "a_lt_hongshijie", "w": 70 }, { "item": "bk_huatuo", "w": 30 } ] },
      { "chance": 0.002, "divine": true, "pick": [ { "item": "w_sb_xuantie", "w": 1 } ] }
    ] }
] }
```

- 怪物列新可選欄位 `loot_table: "<id>"`（WP-LOOT 在 `monsters.json` 只改這個欄位）。既有 `drops` 照舊先擲（行為不變），再擲 `loot_table`：`guaranteed` 全給；每個 `groups[i]` 擲一次 `chance`，中了依權重 `w` 挑一件。`divine: true` 的群組只在規則 `BOSS_DROP` 時擲（§6.5）；含秘笈的挑選在規則 `manuals` 關時把秘笈權重當 0。
- `BattleRewards.compute`（`core/battle/battle_rewards.gd`，WP-LOOT）：新增可選參數 `ctx: Dictionary = {}`（`{ "rules": …, "blocked": [item_id 已有持有者的神兵], "force": [item_id] }`）；`items` 每項多帶 `"rarity"`；`force` 清單中的物品若出現在此怪的任何群組 → 必中該群組並選該物品（一次性，由 LootSystem 管理）。沒有 `loot_table` 的怪物結果與現在**完全相同**（既有測試、金檔不變）。
- 精英、頭目的掉落表（WP-LOOT 決定細節，量級【設計提案】）：

| 怪物等級 | 群組 | 機率 |
|---|---|---|
| `ELITE`（36 列，挑有研究依據的優先：馬賊王、機關人、鬼賊、老鬼、忍者、女強盜、小殺手、攔路霸、蒙面殺手、野人、冤魂小憐、善勇和尚等對應列） | FINE 裝備 | 0.10 |
| | RARE（含研究 gaoshou/25 指名的掉落：鬼頭刀、鋸齒刀、玉石短劍、星月披風、關刀、回部古劍等對應新列） | 0.03 |
| | TREASURE | 0.005 |
| `BOSS`（`m_guiwang`）與 WP-LOOT 指定的 2 個最強怪（依 `combat_xp_ref`，1.0A） | FINE | 0.30 |
| | TREASURE | 0.05 |
| | DIVINE（每個頭目一把，§6.5） | 0.002 |

- 掉率倍數只有伺服器選項 `loot_drop_pct`（int，預設 100，範圍 10–300）：乘所有 `groups[].chance`（神兵群組除外），不影響 `guaranteed` 與既有 `drops`；不做成規則（避免和經濟平衡分岔）。

### 6.7 稀有掉落傳聞與結果畫面

- `LootSystem.on_settle(s, ch, items: Array, monster_ids: Array, room_id: String)`（`BattleSystem._settle_player` 在發獎勵物品後呼叫，WP-NPCPK Day-0 接線）：`rarity` ≥ `TREASURE` 且規則 `loot_broadcast` 開 → `host.m2_call(host.get("rumor"), "post", ["DEED", "lt_rmr_rare_drop", { "name", "item", "monster", "room" }])`（「【江湖傳聞】聽說{name}在{room}擊敗{monster}，得到了{item}！」）＋ self 事件 `lt_rare_drop`。`DIVINE` 用 `lt_rmr_divine_drop`。
- 戰鬥結算的 `close.rewards.items[]` 多 `"rarity"`（WP-NPCPK Day-0 在 `_settle_player` 加這一欄）。
- `ui/game/battle/battle_screen.gd`（WP-LOOT）：勝利結果框的物品列依稀有度上色，`RARE` 以上名字前加「【精品】」等字樣並有 0.6 秒的光暈；`TREASURE` 以上結果框標題下加一行金字「得到寶物！」。
- 訊息列：`item_gain` 既有事件不變；`lt_rare_drop` 走系統頻道。

### 6.8 背包與裝備視窗（`ui/game/panels/inventory_panel.gd`，WP-LOOT）

- 人形 8 格（`BODY_SLOTS` 既有位置）全部可用；空格灰底寫部位名。
- 物品格名稱依稀有度上色；詳情：名稱（色）、部位、武器類型、攻擊或防禦、重量、屬性加成、條件（不合紅字＋「（無法裝備）」）、官方數值一行（「官方：防禦 +20／重量 8」）、秘笈說明（§6.4）、神兵「全服唯一・被玩家擊殺時歸殺手所有」。
- 「研讀」鈕（秘笈）、裝備不合條件時「裝備」鈕灰掉附原因。
- 測試：`tests/unit/test_ui_m3c_loot.gd`（8 格、上色、條件灰鈕、研讀送出形狀、戰鬥結果上色）。

### 6.9 主機系統：`server/loot_system.gd`（`class_name LootSystem`，`GameHost.loot`）＋ `server/intents/intents_loot.gd`

```gdscript
func reward_ctx(entry: Dictionary) -> Dictionary              # 給 BattleRewards.compute 的 ctx（WP-NPCPK Day-0 在 _finish 呼叫並傳入）；用掉的強制掉落在這裡清掉
func on_settle(s: Session, ch, items: Array, monster_ids: Array, room_id: String) -> void
func on_pvp_kill(killer_char_id: String, victim_char_id: String, summary: Dictionary) -> void
func read_manual(s: Session, uid: String, times: int) -> Dictionary
func debug_force(s: Session, item_id: String) -> void         # debug_set loot_force
func grant_divine(s: Session, item_id: String) -> Dictionary  # 管理員／除錯
```

---

## 7. F：武器出招特效（WP-FX）

### 7.1 選特效（`ui/game/battle/weapon_fx.gd`，`class_name WeaponFx`；純函式＋繪圖）

```gdscript
const SKILL_CATS := { "STAB": "stab", "HIDDEN": "hidden", "INNER": "inner", "POISON": "poison", "MEDIC": "medic", "FORMATION": "formation" }
const WEAPON_KINDS := { "SWORD": "sword", "BLADE": "blade", "STAFF": "staff", "WHIP": "whip", "FIST": "fist", "SPEAR": "staff" }
static func kind_for(attacker: Dictionary, event: Dictionary, humanoid: bool) -> String   # "" = 不畫武器特效（用既有火花）；humanoid 由畫面傳入（UnitSprite.is_tall()）
```

規則（依序）：
1. 事件 `p.cat` 在 `SKILL_CATS` → 該鍵。舊主機沒有 `cat` 時：`battle_hidden_hit`／`battle_hidden_miss` → `hidden`；毒類命中 → `poison`；醫療 → `medic`；結陣 → `formation`。
2. 攻擊者不是人形（`kind != "PLAYER"` 且 `humanoid == false`）→ `""`。
3. 攻擊者 `wfx` 非空（`"claw"`）→ `claw`。
4. 攻擊者 `wtype` 在 `WEAPON_KINDS` → 對應鍵；空字串或不明 → `fist`。

### 7.2 主機的純表現欄位（WP-FX 擁有 `core/battle/battle.gd`、`battle_rules.gd`、`battle_cmds.gd` 的這些行）

- `_unit_snapshot`：**每個單位**加 `"wtype"`（玩家＝目前武器的 `weapon_type`，怪物＝怪物列 `weapon_type`）與 `"wfx"`（玩家＝目前武器物品列的 `fx`，怪物＝`""`）。
- 命中／未命中事件 payload（`battle_rules.gd` 一般招式、`battle_cmds.gd` 暗器／毒／醫／點穴）加 `"cat"`：用武功時＝`martial_arts.category`，普攻＝`""`。
- `BattleSystem.redact_unit` 的白名單加 `"wtype"`、`"wfx"`（WP-NPCPK Day-0 照抄）。
- 重產 `tests/fixtures/battle_golden_01.json`（`tools/regen_battle_golden.gd`），交付說明列出差異（只能是多了 `wtype`／`wfx`／`cat`）。

### 7.3 畫法（`battle_iso_view.gd`、`battle_fx.gd`、`unit_sprite.gd`）

- **起點**：攻擊者精靈的「前手」＝ `anchor + Vector2(facing × 0.28 × figure_w, −0.55 × figure_h)`（`facing` = ±1，面向目標）。**方向**：指向守方身體中心；貼圖以左緣中點對齊起點、依角度旋轉；指向左半邊時垂直翻轉（讓弧線上下不顛倒）。**長度**：`min(兩人距離 × 0.9, 1.6 × tile_w)`，高度依比例。**時間**：`IMPACT_AT − 0.06` 出現，淡入 0.06 秒、停 0.12、淡出 0.10；未命中也畫（較淡）。
- `medic`：畫在**目標**身上往上飄；`formation`：畫在施術者腳下的地面（等角壓扁）；`hidden`：從前手飛向目標。
- **有圖**：`ArtRegistry.weapon_fx_texture(kind)`。**沒圖的程式備援**（要「看起來像樣」）：sword＝細長銀白新月弧（polyline 漸細）；blade＝寬厚鋼藍弧帶；staff＝大半圓掃動＋三條風線；whip＝S 形曲線＋尾端爆星；fist＝金橙色掌勁圓＋2 圈擴散環；claw＝三道平行紅褐抓痕；stab＝細亮直線＋星形閃光；hidden＝3 枚帶尾跡的小鏢；inner＝淡藍白螺旋；poison＝綠色毒霧團＋黑點；medic＝綠光上升＋葉形光點；formation＝金色八卦八角形地紋。全部用 `_draw` 的線、多邊形、加法混色，不另開節點。
- **名牌武器小圖示**：人形單位名牌左側 18×18：`ArtRegistry.weapon_icon(kind)`；沒圖畫圓底單字（劍、刀、棍、鞭、爪、拳）；`kind` 用 §7.1 第 3–4 步（不看事件）。怪物非人形不畫。
- 設定：沿用既有「戰鬥特效」相關設定；無新選項。

### 7.4 測試

`tests/unit/test_m3c_weapon_fx.gd`：`kind_for` 每種組合（各武器類型、爪、六種武功類別、舊主機沒有 `cat`、獸類回 ""）；建一個 `BattleIsoView`＋假 `BattleViewModel`（一名拿刀的玩家打一名狼、一名拿劍的玩家被打），送命中事件 → 特效層有一筆 `kind == "blade"`、起點在攻擊者前手、角度朝目標、向左時翻轉；名牌圖示 kind 正確。

---

## 8. 協定增量（`core/protocol.gd` 與 `ui/game/ui_keys.gd`，WP-NPCPK Day-0 照抄；`VERSION` 維持 5）

```gdscript
# ---- M3c intents（M3C_PLAN §8；N1：純新增，RPC 簽名不變 → VERSION 維持 5） ----
const I_SET_LOOK := "set_look"           # intents_char.gd（WP-LOOKS）
const I_NPC_ATTACK := "npc_attack"       # intents_npcpk.gd（WP-NPCPK）
const I_MANUAL_READ := "manual_read"     # intents_loot.gd（WP-LOOT）
const LOOK_MAX := 8
const NPC_ATTACK_MODES := ["ATTACK", "MIEPAI"]
const SLOTS := ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"]   # 取代原本兩格（I_UNEQUIP 的列舉跟著擴）
```

| 位置 | 增量 |
|---|---|
| `INTENT_SCHEMA[I_CHAR_CREATE]` | 加 `"look": [TYPE_INT, false]` |
| `INTENT_SCHEMA` | `I_SET_LOOK: { "look": [TYPE_INT, true] }`；`I_NPC_ATTACK: { "npc": [TYPE_STRING, true], "mode": [TYPE_STRING, false] }`；`I_MANUAL_READ: { "item_uid": [TYPE_STRING, true], "times": [TYPE_INT, false] }` |
| `INT_RANGES` | `I_CHAR_CREATE: { … "look": [0, LOOK_MAX] }`；`I_SET_LOOK: { "look": [0, LOOK_MAX] }`；`I_MANUAL_READ: { "times": [1, 10] }` |
| `ENUMS` | `I_NPC_ATTACK: { "mode": NPC_ATTACK_MODES }` |

**事件**（模板 id＝事件 key；`ui` 標記的走 `"ui": true`）：`look_changed`、`na_attack_start`、`na_npc_killed`、`na_npc_routed`、`na_npc_back`、`na_guard_alarm`、`na_sect_enemy`、`na_master_betray`、`na_miepai`、`lt_rare_drop`、`lt_divine_transfer`、`lt_manual_read`；傳聞模板 `lt_rmr_rare_drop`、`lt_rmr_divine_drop`、`lt_rmr_divine_transfer`。

**原因碼**：`bad_look`、`npc_attack_off`、`npc_not_attackable`、`npc_safe_room`、`npc_busy`、`manuals_off`、`not_manual`、`manual_illiterate`、`manual_cap`、`divine_locked`（`req_gender` 等既有 `req_*` 照舊）。每個新原因碼都要有 `err_<reason>` 模板（擁有該原因碼的 WP 寫）。

**快照、選單、角色表新欄位**：
- 戰鬥單位快照：`wtype`、`wfx`；命中事件 `cat`（§7.2）。
- 房間 view：`npcs[].atk`（§5.3 `view_entry`，null＝不能動手）。
- `npc_menu`：`attack: { ok, reason, label, warn }`（沒有＝空字典）。
- 角色表：`look`、`appearance`；`equipped` 8 鍵；背包物品項目 `rarity`、`slot`、`req_ok`、`req_text`、`bonus`、`official`；`summary.look`。
- 戰鬥結算 `close.rewards.items[].rarity`。
- `world_info`：`rules.npc_attack`、`rules.divine_source`、`rules.manuals`、`rules.loot_broadcast`（若 `world_info` 已帶 `rules` 就沿用；否則客戶端讀不到時當預設值）。

`UiKeys`：照抄上面所有常數（字面值相同），`I_*` 加入既有的 intent 清單常數，`look_changed` 以外的新事件都不是 ui 事件。

`debug_set`（`server/intents/intents_debug.gd`，WP-NPCPK Day-0；只在 `--debug-intents`）新 key：`appearance`（int）、`give_item`（`"<item_id>:<n>"`）、`loot_force`（item id；`LootSystem.debug_force`）、`rng_seed`（int；`host.rng.seed = value`）、`battle_monster`（monster id；在目前房間開一場 `"FIGHT"` 戰）、`encounter_next`（bool；下一次可遇敵的移動必定遇敵）、`npc_respawn_now`（npc id 或 `"*"`）、`divine_grant`（item id；`LootSystem.grant_divine`）。

---

## 9. 資料、存檔、規則與選項增量（彙總）

### 9.1 存檔（全部增量；舊存檔可讀）

| 位置 | 欄位 | 預設 | WP |
|---|---|---|---|
| 角色 | `appearance: int` | 0 | LOOKS |
| 角色 `inventory.equipped` | `HEAD NECK WRIST CLOAK RING BOOTS` | `""` | LOOT |
| 角色 `ext.loot` | `{ "force": [item_id] }`（除錯用，可省） | 無 | LOOT |
| 角色 `ext.npcpk` | `{ "miepai": { sect_id: 次數 } }`（孫婆婆 6→4） | 無 | NPCPK |
| `world.json` | `npc_down: { npc_id: { until_s, by } }` | 無 | NPCPK |
| `world.json` | `divine: { item_id: char_id }` | 無 | LOOT |

### 9.2 規則（`data/rule_profiles.json` 與 `DataSchema.RULE_DEFAULTS`／`RULE_ENUMS`，WP-NPCPK Day-0）

| 規則 | 型別／列舉 | 預設 | classic_strict | classic_standard | later_official | friends_casual |
|---|---|---|---|---|---|---|
| `npc_attack` | bool | true | true | true | true | true |
| `divine_source` | `NONE`／`BOSS_DROP` | `BOSS_DROP` | `NONE` | `BOSS_DROP` | `NONE` | `BOSS_DROP` |
| `manuals` | bool | true | false | true | true | true |
| `loot_broadcast` | bool | true | false | true | false | true |

### 9.3 伺服器選項（`data/server_options.default.json`，WP-NPCPK Day-0；`INT_FIELDS.server_options` 加 int 欄位）

`npc_respawn_pct`（int，100，範圍 10–1000）、`loot_drop_pct`（int，100，範圍 10–300）。伺服器設定面板（WP-NAV 不碰；面板在 `ui/game/social/server_options_dialog.gd`，WP-NPCPK 擁有）加這兩列。

### 9.4 Schema（`core/data/data_schema.gd`，WP-NPCPK Day-0；`check_art` 與 `ART_*` 除外）

- `DataLoader.FILES` 加 `"loot_tables"`；`OPTIONAL_FILES` 加 `"loot_tables"`。
- `INT_FIELDS`：`loot_tables`（`guaranteed[].min`、`guaranteed[].max`、`groups[].pick[].w`）；`items`（`official.atk`、`official.def`、`official.weight`、`manual.cap`、`manual.literacy_min`、`manual.prof`、`manual.jing`、`manual.shen`、`bonus.*`）；`npcs`（`attack.respawn`、`attack.group[].count[]`、`attack.group_repeat[].count[]`）。
- `REFS`：`monsters.loot_table` → `loot_tables`；`loot_tables.guaranteed[].item`、`groups[].pick[].item` → `items`；`npcs.attack.monster`、`attack.group[].monster`、`attack.group_repeat[].monster` → `monsters`；`items.manual.skill` → `martial_arts` 或 `basic_skills`（WP-LOOT 在 lint 區塊檢查二擇一）。
- 新常數：`ITEM_SLOTS := Protocol.SLOTS`、`ITEM_RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]`、`NPC_ATTACK_MODES_DATA := ["KILL", "CHALLENGE"]`、`NPC_ATTACK_CATEGORIES := ["CIVILIAN", "CHILD", "ANIMAL", "WORKER", "GUARD", "WUSHI", "VILLAIN", "SECT_GATE", "SECT_DISCIPLE", "SECT_MASTER"]`、`NPC_ATTACK_VIA := ["CTRL", "MENU", "BOTH"]`；`SECT_RULE_EVENTS` 加 `"ATTACK_SECT_NPC", "KILL_GOOD_NPC", "ATTACK_MASTER"`；`sect_skill_penalties` 觸發列舉（若有）加 `"KILL_NPC_ALIGNMENT"`。

---

## 10. 規則與數值表

| 項目 | 值 | 依據 |
|---|---|---|
| 造型數 | 每性別 0–8（0＝布衣） | ART_REQUEST §9 |
| 入派後外觀 | 門派服裝優先 | 既有行為；O2 |
| 趕路停走 | 氣 < 30%、飽食或飲水 < 20 | 【設計提案】O3 |
| 續走 | 只在遇敵勝利後、選項開（預設開） | 擁有者需求 |
| 全圖座標 | `x = (60/1600 + wp.x/1000×1480/1600)·W`、`y = (60/1200 + wp.y/1000×1080/1200)·H` | `tools/make_map_layout_guide.py` |
| 房間框 9 宮格邊距 | 寬 1/6、高 1/4 | 【設計提案】 |
| 殺善方 NPC 善惡 | 居民 −10、小孩 −20、小動物 −3、採礦 −10、武師 −10、守衛（中立）−5 | 方向【已證實 jyfree jy1_4_1】；量【設計提案】 |
| 殺惡方 NPC 善惡 | 惡人 +10、丁春秋／血刀老祖 +10 | 同上 |
| 殺 NPC 的 PK值 | 不加 | 【待考證】O6 |
| 城內殺人 → 官兵 | 1 名（殺守衛 2 名） | news_4-2 方向；人數【設計提案】 |
| NPC 重生 | 居民、小孩、採礦 3 時辰；動物、守衛 1 時辰；惡人 6 時辰；CHALLENGE 不消失 | 【待考證】；推論見研究 |
| 滅派 孫婆婆 | 孫婆婆＋5 古墓弟子（共 6），每次都一樣（第二輪審查）；滅派專用列 `m_npc_gm_dizi`，實戰 6 萬單人勝率 ≥ 50%（第一輪審查） | mengpai/5「與孫婆婆觸發戰鬥＝公敵」（2001）；2002 攻略「之後 4 個」不採 |
| 門口硬闖 | 全真 4 名、恆山／峨嵋／靈鷲／星宿／血刀 2 名，用有獎勵的 `m_npc_<p>_gate`（執法列 ×0.55–0.75）；全真 20 萬、血刀 16 萬、其他 18 萬單人 ≥ 50%，6 萬 ≤ 5% | gaoshou/31（全真 160、血刀 60 學點／場）；其他【設計提案】 |
| 武當滅派 | 知客＋2 名武當弟子（共 3）；滅派專用列 `m_npc_wd_hushan`，實戰 15 萬單人 ≥ 50%；設武當公敵 | mengpai/2；人數【設計提案】 |
| CHALLENGE 打退後再動手 | 同一批人等重生時間（`attack.respawn` 或 3 時辰 × `npc_respawn_pct`）→ `npc_routed` | 【設計提案】第一輪審查 |
| 新手與守城官兵 | 規則 `newbie_guard_spare`（預設開、`classic_strict` 關）：實戰 < `newbie_pk_protect_xp` 時善惡負不追殺、城內行兇不招官兵（PK值 > 3 照舊） | 【設計提案】第一、二輪審查；`classic_strict` 照 news_4-2 |
| 全真硬闖 | 4 名；設全真公敵 | mengpai/6；gaoshou/31（原作 17–18 名，縮成一場）【設計提案】 |
| 本派攻擊同門 NPC | `ATTACK_SECT_NPC` → 依 `sect_violation_mode`（JAIL 1 遊戲日） | index_jy2-22、2001-11-15 |
| 對丁春秋／血刀老祖下手（本派） | 叛派 | 官方 2001/8/7 |
| 佛法、慈悲 | 每殺一個善良 NPC −1 級 | 會扣【已證實】；量【待考證】比照吃肉 −1 級 |
| 裝備換算 | atk＝官方；def＝⌈官方÷5⌉；weight＝⌈官方÷2⌉ | O13 |
| 裝備欄 | 1 武器＋7 防具 | 研究 裝備欄 |
| 裝備條件 | 性別 | 官方 jy1_3_8 等 |
| 稀有度 | 凡品／良品／精品／珍品／神兵 | 【設計提案】 |
| 精英掉落 | 良品 10%、精品 3%、珍品 0.5% | 【設計提案】 |
| 頭目掉落 | 良品 30%、珍品 5%、神兵 0.2%；同一角色每 12 時辰（1 遊戲日）只擲一次群組（頭目鎖 `lockout_shichen`，第一輪審查） | 【設計提案・非原作】 |
| 神兵戰鬥攻擊 | 官方 × 0.4（倚天 80、玄鐵 86、屠龍 84） | O16 |
| 秘笈上限 | min(秘笈 cap, 讀書識字等級, 一般武學上限) | 【設計提案・非原作】O17 |
| 研讀消耗 | 每次精 10、神 10、學點 1，熟練 +10（第二輪審查：原 15／15／+6 比自修慢 0.4 倍） | 【設計提案】 |
| 珍品以上傳聞 | 開（`classic_strict` 關） | 【設計提案・非原作】 |
| 武器特效時序 | 出現於命中前 0.06 秒、全長 0.28 秒 | 【設計提案】 |

---

## 11. 工作包與檔案所有權

### 11.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-ART** | `data/art.json`；`tools/import_art.py`；`tools/art_register.py`；`tools/art_contact_sheet.py`（新）；`ui/common/art_registry.gd`；`core/data/data_schema.gd` 的 `check_art()`、`_art_cycle()`、`ART_*` 常數（§11.2）；`tests/unit/test_art_registry.gd`、新 `tests/unit/test_m3c_art_import.gd`（呼叫 python 用暫存目錄，或以 GDScript 檢查輸出）；`assets/art/**`（只經由 import 工具寫入、先備份） | §2 |
| **WP-LOOKS** | `core/character/looks.gd`（新）；`core/character/character_factory.gd`；`server/intents/intents_char.gd`；`core/character/character.gd` 的 §11.2 指定部分；`ui/game/char/**`（含新 `look_picker.gd`、`look_dialog.gd`）；`ui/game/panels/attributes_panel.gd`、`ui/game/panels/skills_panel.gd`；`ui/game/dialogs/learn_dialog.gd`、`ui/game/dialogs/story_dialog.gd`；`tests/unit/test_m3c_looks.gd`、`tests/unit/test_ui_m3c_looks.gd`、既有 `test_character_create.gd` | §3 |
| **WP-NAV** | `ui/game/map/**`；`ui/game/main/mini_map.gd`；`ui/common/ui_settings.gd`；`ui/game/panels/system_panel.gd`；`ui/game/main/main_screen.gd`（§11.2 的他人掛點除外）；`ui/game/main/status_bar.gd`；`tests/unit/test_m3c_route.gd`、`test_m3c_autowalk.gd`、`test_ui_m3c_nav.gd`、既有 `test_ui_map_layout.gd`、`test_ui_map_panel.gd` | §4 |
| **WP-NPCPK**（也是 core 擁有者） | `core/protocol.gd`；`ui/game/ui_keys.gd`；`core/data/data_schema.gd`（`check_art`／`ART_*` 除外）；`core/data/data_loader.gd`；`core/rules/**`；`server/game_host.gd`、`server/battle_system.gd`、`server/pk_system.gd`、`server/sect_system.gd`、`server/npc_system.gd`、`server/region_system.gd`；`server/npc_attack_system.gd`（新）、`server/intents/intents_npcpk.gd`（新）、`server/intents/intents_debug.gd`、`server/intents/intents_pk.gd`；`data/npcs.json`（`shop.items` 除外）、`data/monsters.json`（`loot_table` 欄除外）、`data/maps/*.json`、`data/sect_rules.json`、`data/sects.json`、`data/rule_profiles.json`、`data/server_options.default.json`；`ui/game/main/scene_panel.gd`；`ui/game/dialogs/npc_dialog.gd`；`ui/game/social/npc_attack_ui.gd`（新）、`ui/game/social/server_options_dialog.gd`；`tools/data_lint.gd`（WP-LOOT 區塊除外）；`tests/unit/test_m3c_npc_attack.gd`、`test_m3c_npc_sect.gd`、`test_m3c_npc_respawn.gd`、`test_ui_m3c_npc_attack.gd`、`test_protocol*.gd`、`test_data_loader.gd`、`test_sect*.gd` | §5、§8、§9 Day-0 |
| **WP-LOOT** | `data/items.json`；`data/loot_tables.json`（新）；`data/npcs.json` 的 `shop.items`；`data/monsters.json` 的 `loot_table` 欄；`core/character/**`（`looks.gd`、`character_factory.gd` 與 character.gd 的 LOOKS 部分除外：含 `inventory.gd`、`derived_stats.gd`、`learning.gd`、`death_penalty.gd`、`requirements.gd`）；`core/battle/battle_rewards.gd`；`server/loot_system.gd`（新）、`server/intents/intents_loot.gd`（新）、`server/intents/intents_item.gd`；`ui/game/panels/inventory_panel.gd`；`ui/game/battle/battle_screen.gd`；`ui/game/econ/loot_ui.gd`（新）；`tools/balance_sim.gd`（WP-NPCPK 區塊除外）；`tools/data_lint.gd` 的 LOOT 區塊；`tests/unit/test_m3c_loot*.gd`、`test_m3c_manual.gd`、`test_m3c_divine.gd`、`test_m3c_slots.gd`、`test_ui_m3c_loot.gd`、既有 `test_character_inventory.gd`、`test_character_derived.gd`、`test_battle_rewards.gd`、`test_character_death.gd` | §6 |
| **WP-FX** | `ui/game/battle/battle_fx.gd`、`unit_sprite.gd`、`battle_iso_view.gd`、`battle_view_model.gd`、`weapon_fx.gd`（新）；`core/battle/battle.gd`、`core/battle/battle_rules.gd`、`core/battle/battle_cmds.gd`（只限 §7.2 欄位）；`tests/fixtures/battle_golden_01.json`；`tools/regen_battle_golden.gd`；`tests/unit/test_m3c_weapon_fx.gd`、既有 `test_battle_replay.gd`（金檔） | §7 |
| **整合者**（協調者） | `tests/bots/**`（新 `tests/bots/m3c_bot.gd`）、`tests/ui/ui_playthrough.gd`、`tests/ui/ui_driver.gd`、`tools/m3c_acceptance.gd`（新）、其他 `tools/*acceptance*`、`tests/unit/test_data_content.gd`、`README.md`、`docs/**`（本文件整合紀錄、GDD／ART_REQUEST 偏差同步） | §12 |

### 11.2 共用熱檔的切分（只有這裡列的跨 WP 修改是准許的）

| 檔案 | 擁有者 | 其他 WP 准許的修改（逐字照做，不得多動） |
|---|---|---|
| `core/character/character.gd` | WP-LOOT | **WP-LOOKS**：(1) `var appearance: int = 0` 一行（放在 `ext` 宣告下面）；(2) `from_dict` 內讀 `appearance` 兩行；(3) `to_dict` 內 `"appearance": appearance` 一行；(4) 整個 `battle_look()` 函式；(5) `to_summary()` 加 `"look"`；(6) `to_sheet()` 回傳字典加 `"look"`、`"appearance"` 兩個鍵。每處行尾註解 `# M3c WP-LOOKS`。 |
| `core/data/data_schema.gd` | WP-NPCPK | **WP-ART**：`ART_SECTIONS`、`ART_POSES` 與新 `ART_*` 常數、`check_art()`、`_art_cycle()`、新的 art 輔助函式（名稱以 `_art_` 開頭）。 |
| `server/battle_system.gd` | WP-NPCPK | 無；WP-NPCPK Day-0 照抄 §11.3 的 WP-LOOT／WP-FX 接線。 |
| `ui/game/main/main_screen.gd` | WP-NAV | **WP-NPCPK**：`_build()` 內一行 `scene_panel.npc_attack_requested.connect(request_npc_attack)`；檔尾區塊 `# ==== M3c WP-NPCPK ====` 內新增 `request_npc_attack(p: Dictionary) -> void`。**WP-LOOKS**：`_build()` 內一行 `(panels["attributes"] as AttributesPanel).look_change_requested.connect(open_look_dialog)`；檔尾區塊 `# ==== M3c WP-LOOKS ====` 內新增 `var look_dialog` 與 `open_look_dialog() -> void`，`_dialogs()` 回傳清單加 `look_dialog`（一處）。WP-NAV 自己的掛點：`_shortcut_input` 的 Esc 分支、`close_battle()`、`_on_battle_finished()`、`_build()` 的地圖接線。 |
| `tools/data_lint.gd` | WP-NPCPK | **WP-LOOT**：檔尾區塊 `# ==== M3c WP-LOOT ====` 內 `_check_m3c_loot(tables) -> PackedStringArray`，以及主流程呼叫它的一行。 |
| `tools/balance_sim.gd` | WP-LOOT | **WP-NPCPK**：檔尾區塊 `# ==== M3c WP-NPCPK ====` 內的案例函式，以及案例清單登記的一行。 |
| `data/text_templates.json` | （無單一擁有者） | **只能追加**（N3）：WP-LOOKS `look_*`、`err_bad_look`；WP-NPCPK `na_*`、`rule_*_attack_npc`、`rule_h*_kill_good_npc`、`talk_n_na_*`、`err_npc_*`；WP-LOOT `lt_*`、`err_manual*`、`err_not_manual`、`err_manuals_off`、`err_divine_locked`（`err_req_gender` 等若已存在不重建）。不得修改他人或既有列。 |
| `data/npcs.json` | WP-NPCPK | **WP-LOOT**：只改既有 NPC 的 `shop.items` 陣列（追加物品 id）。 |
| `data/monsters.json` | WP-NPCPK | **WP-LOOT**：只在既有怪物列加 `loot_table` 欄位。 |

### 11.3 Day-0（各 WP 開工的第一件事）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-NPCPK | (1) `core/protocol.gd`、`ui/game/ui_keys.gd`：§8 全部；(2) `data_schema.gd`／`data_loader.gd`：§9.4（`loot_tables` 空表可載入）；(3) `rule_profiles.json`、`server_options.default.json`、`RULE_DEFAULTS`／`RULE_ENUMS`：§9.2–9.3；(4) `GameHost`：`const M3C_SYSTEMS := { "npcpk": "res://server/npc_attack_system.gd", "loot": "res://server/loot_system.gd" }`、`const M3C_INTENTS := ["res://server/intents/intents_npcpk.gd", "res://server/intents/intents_loot.gd"]`（容錯載入，比照 M3B）；`_minute_jobs` 呼叫 `m2_call(npcpk, "tick", [now_s()])`；`npc_here` 先問 `m2_call(npcpk, "npc_down", [npc_id], false)`；`NpcSystem.menu` 合併 `m2_call(npcpk, "menu_fields", [s, npc_id], {})` 到 `attack`；(5) `BattleSystem`：`_finish` 擲獎勵改 `BattleRewards.compute(b, host.tables, host.rng, host.m2_call(host.get("loot"), "reward_ctx", [entry], {}))`（一場戰鬥一個 ctx：規則、已有持有者的神兵、參戰角色的強制掉落）；`_settle_player` 物品迴圈的 `close.rewards.items` 每項加 `"rarity": str(host.tables.get("items", {}).get(item_id, {}).get("rarity", "COMMON"))`，迴圈後呼叫 `host.m2_call(host.get("loot"), "on_settle", [s, ch, close["rewards"]["items"], kills, str(entry.get("room", ""))])`；`_finish` 結尾呼叫 `host.m2_call(host.get("npcpk"), "on_battle_finished", [entry, out])`；`redact_unit` 白名單加 `"wtype"`、`"wfx"`；(6) `PkSystem.on_pvp_end`：對每個死於玩家的單位呼叫 `host.m2_call(host.get("loot"), "on_pvp_kill", [killer_char, victim_char, summary])`；(7) `intents_debug.gd`：§8 的 debug key（`loot_force`、`divine_grant` 經 `m2_call` 呼叫 LootSystem，不存在時回 `bad_key`）；(8) `RegionSystem._npc_entry` 加 `"atk": m2_call(npcpk, "view_entry", [s, npc_id], null)`（需要時把 `s` 傳進去）並略過 `npc_down` | 其他 WP 依常數、載入點、接線開工 |
| WP-ART | `art_registry.gd` §2.4 API（先回 null 的空殼）＋ `art.json` §2.3 四個新區塊（全 `placeholder: true`） | WP-NAV、WP-FX 直接呼叫 |
| WP-LOOKS | `core/character/looks.gd` 全部 | WP-LOOT 的 character.gd、WP-FX 的測試會用到 `Looks.art_ref` |
| WP-LOOT | `Inventory.SLOTS` 8 鍵＋`to_dict(legacy)` 不變的測試；`LootSystem` 公開函式空殼 | WP-NPCPK 接線、WP-LOOKS 的護照測試 |
| WP-FX | `WeaponFx.kind_for` 與快照 `wtype`／`wfx` | 測試基礎 |

Day-0 還沒落地時：先寫純邏輯與不依賴新常數的測試；字串用與本文件**完全相同**的字面值，交付前改回常數。

### 11.4 凍結檔（M3c 任何 WP 都不得修改）

`project.godot`、`export_presets.cfg`、`tools/export_release.ps1`、`autoload/**`（`world_server.gd`、`client_state.gd` 若 Day-0 證明非改不可，由 WP-NPCPK 改並列在交付說明）、`core/util/*`、`core/quest/**`、`core/econ/**`、`core/battle/battle_formulas.gd`、`core/battle/battle_ai.gd`、`core/battle/battle_status.gd`、`core/battle/encounter.gd`、`tests/run_tests.gd`、`tests/test_case.gd`、`tools/net_smoke.gd`、`tools/steam_api_probe.gd`、`tools/check_vendor.ps1`、`tools/iso_gallery.gd`、`tools/godot_k.ps1`、`tools/make_map_layout_guide.py`、`addons/**`、`data_root.txt`、`data/quests.json`、`data/martial_arts.json`、`data/masters.json`、`data/regions.json`、`data/eras.json`、`data/patches/**`、`data/life_skills.json`、`data/escort_routes.json`、`data/sect_ranks.json`、`data/rumors.json`、`data/wanderers.json`、`data/ambient.json`、`data/reactions.json`、`server/` 中 §11.1 沒列的檔（`quest_system.gd`、`rumor_system.gd`、`wander_system.gd`、`ambient_system.gd`、`corpse_system.gd`、`mail_system.gd`、`party_system.gd`、`passport.gd`、`character_store.gd`、`world_clock.gd`、`world_index.gd`、`bank_system.gd`、`escort_system.gd`、`life_system.gd`、`org_system.gd`、`social_system.gd`、`scout_system.gd`、`admin_system.gd`、`condition_system.gd`）、`ui/game/econ/{bank,escort,craft}_window.gd`、`ui/game/social/` 中 §11.1 沒列的檔、`docs/**`（只由協調者改）。

---

## 12. 測試計畫

### 12.1 各 WP 的單元與整合測試（全部在 `tests/run_tests.gd` 裡跑，`--filter=m3c` 可單跑）

| WP | 測試 | 涵蓋 |
|---|---|---|
| WP-ART | `test_art_registry.gd`、`test_m3c_art_import.gd` | 第四批 5 個抽查與 16 個造型解析到自己的檔；新 API 沒圖回 null、注入假圖回圖；import 每類尺寸與目錄；覆寫備份位元組相同；`--no-json-update` 不寫 art.json；`check_art` 新區塊錯誤訊息 |
| WP-LOOKS | `test_m3c_looks.gd`、`test_ui_m3c_looks.gd`、`test_passport.gd`、`test_character_create.gd` | §3.4 第 5 點；護照舊簽章仍驗得過 |
| WP-NAV | `test_m3c_route.gd`、`test_m3c_autowalk.gd`、`test_ui_m3c_nav.gd` | §4.7 |
| WP-NPCPK | `test_m3c_npc_attack.gd` | 驗證順序全部原因碼；`npc_busy` 與 battle_id；KILL 後消失、view 不列、`npc_here` 不在；重生（世界時鐘快轉）；CHALLENGE 不消失；善惡殺氣只算一次；兩名玩家先後攻擊同一 NPC |
| | `test_m3c_npc_sect.gd` | 本派攻擊同門 → breach（JAIL／EXPEL 兩種模式）；外人滅派 → 公敵、`hostile_entry` 觸發；孫婆婆 6→4；丁春秋本派 → 叛派、外人 → 公敵；華山殺善良 → breach；少林、恆山降級；峨嵋斷惡 |
| | `test_m3c_npc_respawn.gd` | 存檔重開後 `npc_down` 照舊、到時重生、`npc_respawn_pct` |
| | `test_m3c_guard.gd`（可併） | 城內殺居民 → 1 名官兵；殺守衛 → 2 名；城外不觸發；`guards_enabled` 關不觸發 |
| | `test_ui_m3c_npc_attack.gd`、`test_protocol*.gd` | §5.8；新 intent 驗證（`look` 範圍、`mode` 列舉、`times` 範圍、`unequip` 新欄位） |
| WP-LOOT | `test_m3c_slots.gd` | 8 欄裝備、舊存檔 2 鍵相容、`fix_slots` 搬帽子、`legacy` 輸出不變、`armor_power` 加總、`bonus`、性別條件 `req_gender` |
| | `test_m3c_loot.gd` | 掉落表：必掉、群組、權重、`loot_drop_pct`、規則 `manuals` 關時不掉秘笈、沒 `loot_table` 的怪物結果與舊版相同（固定種子對照）、`force`、`rarity` 帶到結算、傳聞（規則開關） |
| | `test_m3c_manual.gd` | 全部原因碼；上限 = min(cap, 讀書識字, 一般上限)；不消耗；扣精神 |
| | `test_m3c_divine.gd` | 全服唯一（有人持有不掉）、惰性釋放、PvP 轉移（三種 PvP）、不能賣丟存、死亡不掉、`divine_source NONE` 不掉 |
| | `test_ui_m3c_loot.gd` | §6.8 |
| WP-FX | `test_m3c_weapon_fx.gd`、`test_battle_replay.gd`（新金檔） | §7.4 |

### 12.2 平衡（`tools/balance_sim.gd`；WP-LOOT 擁有，WP-NPCPK 在自己的區塊加 NPC 案例）

- **WP-LOOT**：`loot_econ_elite`（實戰 2 萬的角色連打精英 1 小時，掉落賣店的銀兩 ≤ 現行同場景收益的 1.25 倍）；`loot_econ_boss`（鬼王 100 場，銀兩期望 ≤ 1.25 倍；珍品掉落次數 2–9 次）；`armor_full_kit`（最便宜一整套 7 件官方防具 vs 現行布衣，對鬼王勝率提高 ≤ 15 個百分點）；`divine_duel`（同實戰、其中一人拿倚天劍的 PvP 勝率 ≤ 75%）；`manual_speed`（讀書識字 40 讀 `bk_huatuo` 從 0 到 40 級所需精神與學點，與自修相比不得快於 2 倍）；`loot_rate_hour`（第一輪審查：一人全力刷時頭目珍品 ≤ 0.25 件／時、全部珍品 ≤ 0.5 件／時、神兵最快 ≥ 300 小時）。
- **WP-NPCPK**：`npc_civilian`（新角色打城市居民勝率 ≥ 90%）；`npc_wushi`（實戰 0 勝率 ≤ 5%、實戰 5 萬 ≥ 50%）；`wd_disciple_150k`（實戰 15 萬單人打 1 名武當弟子 ≥ 50%，2002 攻略「15 萬刷武當」的實際對象）；`miepai_wudang`（實戰 15 萬單人打知客＋2 名滅派武當弟子 ≥ 50%）、`miepai_gumu`（實戰 6 萬單人打孫婆婆＋5 名古墓弟子 ≥ 50%）、`miepai_gumu_repeat`（＋3 ≥ 50%）、`miepai_gumu_newbie`（實戰 0 ≤ 5%）——第一輪審查 R1-A4 改用滅派專用列並判定（取代 I4 的「只列印」）；`npc_master`（實戰 100 萬單人打丁春秋 ≤ 10%）。
- 既有案例全部照舊通過。

### 12.3 驗收：`tools/m3c_acceptance.gd` + `tests/bots/m3c_bot.gd`（整合者）

架構照 `tools/m3b_acceptance.gd`：worker 子行程開真的主機（`--debug-intents`），玩家是假的遠端連線，一切動作經 `handle_intent`；每個劇本用**全新世界**（測試根目錄下 `m3c_acceptance/<run>/`）。`debug_set` 只用來設屬性、實戰、銀兩、技能、時辰快轉、給物品、強制掉落、開指定怪戰鬥；**路一律用走的**（`teleport` 只准把 bot 送回起點）。

| 劇本（`--only=`） | 步驟與斷言 |
|---|---|
| `looks` | 創角男、`look: 5` → `sheet.look == "look_m05"`、`summary.look` 同；`debug_set battle_monster m_rabbit` → 戰鬥快照自己的單位 `look == "look_m05"`、`wtype` 存在；`set_look 2` → `look_m02`；`set_look 9` → `bad_value:look`；`debug_set` 拜入條件後走到少林拜師 → `look == "shaolin_m"`、`appearance == 2`；存檔、關主機、重開、重新選角 → `appearance == 2`；另一角色創女 `look: 7` → `look_f07` |
| `nav_walk` | 西夏出生；bot 先**手動**走 西夏 → 華山山門（記錄走過的房間＝已探索）→ `teleport` 回起點；用 `RoutePlanner.find_path(graph, cur, hs_gate, known)` 得跨區路徑（斷言路徑跨 ≥ 2 個地區、只含已探索房間）；`AutoWalkCore` 驅動逐步 `move`；途中 `debug_set encounter_next true` → 遇敵戰鬥 → bot 打贏（`debug_set` 強屬性）→ `on_battle_end("VICTORY", true)` → 自動續走 → 抵達 `hs_gate`；另一段：續走關閉時打贏後停在原地、`STOP` 原因「戰鬥結束」；`debug_set` 把氣設到 25% → `STOP` 原因「氣血不足三成」 |
| `minimap_edge` | （介面層，`tests/ui/ui_playthrough.gd` 內做，整合者）小地圖點「往西夏郊外」→ 區域標題變成鄰區（瀏覽中）、看得到已探索房間 → 點其中一間 → 開始跨區趕路；按返回 → 回到目前區域。截圖 `K:\Project\JY-Mini-OL-Work\shots\m3c_minimap_edge_*.png` |
| `npc_good` | 大理出生（`debug_set` 強屬性）；兩名玩家 A、B 同在 `dl_square`；A `npc_attack n_na_dl_xiaohai` → 戰鬥中 B `npc_attack n_na_dl_xiaohai` → `npc_busy`；A 勝 → 善惡 −20、殺氣 +20、`na_npc_killed`；隨即 `na_guard_alarm` 與 `GUARD` 戰鬥開始（A 逃走或打完都可）；`look` → 房間 `npcs` 沒有小孩；`debug_set world_s_add` 3 時辰 → 房內收到 `na_npc_back`、`npcs` 又有小孩；A `npc_attack n_dl_cunmin`（CHALLENGE）勝 → 善惡 −10、`na_npc_routed`、村民仍在、引用他的任務照樣能接；`npc_attack n_dl_wushi`（大理武館）→ 開戰、輸了 NPC 仍在、武館照樣能 `learn_list`；Ctrl 攻擊同房的 `n_lj_baiyong`（任務 NPC，沒有 attack）→ `npc_not_attackable` |
| `npc_sect` | (a) 武當弟子（`debug_set` 條件後走去拜師）在 `wd_square` 一帶 `npc_attack n_wd_beizhong` → `sect_breach`、坐牢（`jail_in`、人在武當思過處）；(b) 無門派角色走到 `wd_gate`，`talk n_wd_zhike` → `npc_menu.attack.label == "滅派"` → `npc_attack { mode: MIEPAI }` → 戰鬥 3 名護山、`sheet.enemy_of` 含 `wudang`；之後走進 `wd_square` 觸發既有敵對入山；(c) 少林弟子 `npc_attack n_na_dl_xiaohai` 殺死 → 佛法降 1 級；(d) 星宿弟子 `npc_attack n_xh_dingchunqiu` → 叛派（`sect` 變空、`traitor_of` 含 `xingxiu`） |
| `loot_rare` | 兩名玩家 A、C 在線；A `debug_set loot_force a_lt_hongshijie`、強屬性；A `debug_set battle_monster m_guiwang` 打贏 → 結算 `rewards.items` 有 `a_lt_hongshijie` 且 `rarity == "TREASURE"`；A 收到 `lt_rare_drop`；C 收到【江湖傳聞】`lt_rmr_rare_drop`；`classic_strict` 世界重跑一次 → 沒有傳聞 |
| `manual` | `debug_set give_item bk_huqingniu:1`；讀書識字 0 → `manual_read` → `manual_illiterate`；`debug_set skill:basic_literacy 25` → 讀到 `basic_medic` 25 停、再讀 → `manual_cap`；秘笈仍在背包 |
| `equip8` | 給 `a_lt_maozi`（帽子）、`a_lt_zhihuan`（指環）、`a_lt_yushang`（羽裳）；男角裝帽子、戒指成功、`sheet.equipped.HEAD/RING` 有值、`armor_power` 增加；裝羽裳 → `req_gender`；`unequip HEAD` 成功；存讀往返 |
| `divine_pvp` | A `debug_set divine_grant w_sb_yitian` 並裝備；A、B 走到可 PK 的野外；B `force_pk` A，A 只「防」到死 → 倚天劍在 B 背包（A 沒有）、`world.divine.w_sb_yitian == B`、雙方收到 `lt_divine_transfer`、C 收到傳聞；A `sell`／`drop_item` 倚天前置斷言（給 A 時）回 `divine_locked`／不可賣 |
| `fx_snapshot` | 玩家拿刀打狼：戰鬥快照玩家 `wtype == "BLADE"`、狼 `wtype` 存在；命中事件有 `cat`（普攻 ""；用刀法時 `BLADE`）（畫面選特效由 WP-FX 單元測試涵蓋） |

成功印 `M3C_ACCEPT_OK`、結束碼 0；失敗印 `M3C_ACCEPT_FAIL <劇本> <原因>` 並傾印 log 尾端，結束碼 1；log 與世界在 `<測試根目錄>/m3c_acceptance/`；不論成敗所有子程序 `OS.kill()`，結束後 `tasklist` 不得有殘留 Godot。

### 12.4 介面驗收（`tests/ui/ui_playthrough.gd`，整合者加步驟；截圖 `K:\Project\JY-Mini-OL-Work\shots\`）

創角造型選擇器（男、女各一）；屬性視窗更換造型；地圖快捷目的地與進度列；小地圖「往XXX」切區與返回；Ctrl+點 NPC 確認框（三種文字）；武當知客「滅派」選項；背包 8 格與稀有度上色、詳情條件紅字；戰鬥結果珍品上色；武器特效（刀、劍、拳各一張，用程式備援）。

### 12.5 回歸（全部要綠，整合者驗收時逐一跑）

`tests/run_tests.gd`（0 failed）、`tools/data_lint.gd`（0 errors，各 era 閉包）、`tools/balance_sim.gd`、`tests/ui/ui_playthrough.gd`（headless）、M1 驗收 bot（全新世界、測試根目錄）、`tools/m2_acceptance.gd`、`tools/m3a_acceptance.gd`、`tools/m3b_acceptance.gd`、`tools/story_acceptance.gd --all`、`tools/m3c_acceptance.gd`、`tools/net_smoke.gd`、`tests/bots/close_mid_battle_bot.gd`（`--close-mode=wm` 與 `quit`，log 無 SCRIPT ERROR）。

---

## 13. 交付與整合

1. 各 WP 交付：改了哪些檔（必須都在 §11.1 自己的欄或 §11.2 准許的地方）、新增的 `class_name`（整合者先 `--import`）、`# M3C_PLAN 缺漏` 清單、自己的單元測試結果、`todo_verify`（【待考證】項目）、殘留 Godot 程序檢查（`tasklist`）。
2. WP-ART 另交：聯絡表路徑、快照備份路徑與檔數、比例微調清單。
3. WP-FX 另交：金檔差異摘要。
4. WP-LOOT 另交：新物品列數、商店上架表、各掉落表摘要、`balance_sim` 新案例數字。
5. WP-NPCPK 另交：可打 NPC 最終清單（含因 §5.2 條件被拿掉的）、新門規列。
6. 整合者：跑 §12.5 全部；同步 GDD（§1.4 F1–F4）、ART_REQUEST（F6：第四批、§9、§10、§11 狀態）、M3B_PLAN §1.2（F5）、README（造型、跨區趕路、攻擊 NPC、裝備 8 欄與打寶、秘笈、神兵、武器特效、`m3c_acceptance`、M3c 仍延後的清單）；在本文件 §15 寫整合紀錄。
7. **不 commit**；不碰擁有者存檔；不寫 C:；不刪檔（N6）。

---

## 14. 開放問題（擁有者決定；預設值已寫在 §1.3）

| # | 問題 | 預設 |
|---|---|---|
| Q1 | 新手裝換成 2001-06-30 官方清單（9 工具＋傳家三件＋稻米種子x10、活力頌x5、清水x5、熟牛肉x5、地圖；0 錢、0 實戰；實戰 100 以下不扣飲水）？ | M3c 不換；只建傳家三件資料列。建議做成規則 `starter_kit`（`classic_strict` 用 2001 清單），需同步 M1 驗收 bot |
| Q2 | 神兵在 2001 經典世界要不要能掉？ | `BOSS_DROP`（擁有者要求「極稀有」）；`classic_strict`／`later_official` 為 `NONE` |
| Q3 | 殺 NPC 是否加 PK值（兩種 17173 說法都只講玩家） | 不加 |
| Q4 | 孫婆婆滅派要不要設古墓公敵（2001 規則 vs 2002 重複刷） | 設（2001 規則）；第二輪審查：一致採 2001，拿掉 2002 的 6→4（`group_repeat`） |
| Q5 | NPC 重生時間、佛法／慈悲扣幾級 | §10 表 |
| Q6 | 馬王洞／馬賊王的時代（17173 2001-07-12 大陸服證據） | 不動 M3b 的 1.0B 決定；記錄 |
| Q7 | 槍類武器（本作沒有槍法） | 不做 |

---

## 15. 整合紀錄（整合者填寫）

（2026-10-20 整合者）

**整合時的修改**（都不改各 WP 的設計，只接縫與同步）：

| # | 檔案 | 修改 | 理由 |
|---|---|---|---|
| I1 | `server/passport.gd`（凍結檔，整合者例外） | 驗章多試一種「M3c 以前」格式：護照角色沒有 `appearance` 時，正規化去掉 `appearance`、裝備只留 WEAPON／ARMOR；與 lots、M3b 兩種舊格式任意組合 | WP-LOOT 回報：8 格 `equipped` 與 `appearance` 改了簽章格式，0.5.0.0（擁有者正式版）簽的護照會全部驗不過。新測試 `test_passport::test_pre_m3c_passport_verifies`（含竄改偵測） |
| I2 | （文件） | `set_look` 旗標是 `IDLE`（不是 `NEEDS_CHAR | IDLE`），戰鬥中回 `in_battle`（不是 `busy`） | WP-LOOKS 偏差 1、2：坐牢閘只看 `NEEDS_CHAR`，要讓坐牢中能換造型；`in_battle` 是既有 IDLE 旗標的原因碼。採用並改 §1.1 B4、§3.3 |
| I3 | （文件） | NPC 重生：1 時辰 = 600 世界秒（遊戲日 7200 ÷ 12） | WP-NPCPK 偏差；§5.3 原寫 7200 是筆誤（§5.1 也說 1 時辰 = 遊戲 2 小時）。採用並改 §5.3 |
| I4 | （文件） | §12.2 滅派兩個案例改成只列印，換成 `wd_disciple_150k` ≥ 50% | WP-NPCPK：滅派綁既有執法者列（`m_wd_guard`、`m_gm_guard`），15 萬單人打 3 名護山 0%、6 萬打孫婆婆＋5 0%。擁有者決定（預設）：**不改執法者列**（會動到 M3a 敵對入山與坐牢平衡），滅派是要組隊或很高實戰的事；2002「15 萬刷武當」的實際對象是單一武當弟子（實測 89.6%） |
| I5 | `server/admin_system.gd`、`autoload/world_server.gd`（`CLI_OPTS`） | `npc_respawn_pct`、`loot_drop_pct` 加進伺服器設定面板可改的清單（百分比選項）與 `--opts` | WP-NPCPK 偏差：面板列只能唯讀，因為主機端清單不在它的檔案內 |
| I6 | `ui/game/dialogs/npc_dialog.gd` | 沒有 NPC 立繪時的剪影改用自己的 `sheet.look`（`LookPicker.sheet_look_texture`） | WP-LOOKS 缺漏 6（§3.4 第 4 點） |
| I7 | `tests/unit/test_data_content.gd` | 計數更新（NPC 254、怪物 109、物品 237、西夏兵器鋪 27）；木刀 `def` 0（F1）；`bk_wumu`、`lt_elite_1b` 是 1.0B；模板參數加 `look_name note item monster room`；M3a lint 測試的壞事件改成 `ATTACK_NOPE`（`ATTACK_SECT_NPC` 已合法） | 各 WP 的預期變更 |
| I8 | `tests/unit/test_character_model.gd`、`tests/unit/test_ui_m3c_looks.gd` | summary 加 `look`；創角框改用「選擇器往上找」而不是子節點索引（全套測試時會 SCRIPT ERROR） | 測試脆弱 |
| I9 | `assets/art_in_backup_section11/.gdignore`（新） | 加空的 `.gdignore` | WP-ART 回報：擁有者的舊圖備份資料夾在專案裡被 Godot 匯入 |
| I10 | `tests/ui/ui_driver.gd` | `click(c, ctrl)`／`push_mouse_click(..., ctrl)`：按著 Ctrl 點 | 介面驗收 Ctrl+點 NPC |

**驗收工具**：`tools/m3c_acceptance.gd` + `tests/bots/m3c_bot.gd`（§12.3 全部劇本；`loot_rare` 另開 `loot_rare_strict` 世界）。與表格的小差異：`npc_sect (a)` 的武當弟子 `n_wd_beizhong` 在 `wd_gate`（不是 `wd_square`）；`(c)` 少林弟子殺的是西夏街上的黃狗（GOOD、KILL；小孩在大理）；`nav_walk` 把氣設成 25% 是直接改角色（`debug_set` 沒有氣的鍵，同 M3b bot 的 refill 捷徑）；`enemy_of` 是門派名（「武當」），斷言改用名字＋`sect_enemies` 的 id。
介面驗收 `tests/ui/ui_playthrough.gd` 加：創角造型選擇器（步驟 3）與第 21 步（§12.4 全部；截圖 `K:\Project\JY-Mini-OL-Work\shots\m3c\integrate\`）。

**仍延後**：§1.2 全部（懸賞、合體技、輕／閃、門派比武、劫鏢……）。
**仍【待考證】**：NPC 重生時間、佛法／慈悲每殺扣幾級、各類 NPC 的善惡殺氣量、2001 掉率、斗笠重量 42、新月匕首重量 20 vs 4、苗刀 +5／1235 兩、屠龍刀官方數值、羽裳男性購買說法。
**已知小問題（不擋）**：裝備性別不合時沿用既有 `err_req_gender` 文字「對方不收你這樣的弟子」（計畫禁止改既有列，建議下一包加 `err_req_gender_equip`）；地圖美術、`map_*` 圖還沒到，地圖照舊程式繪圖。截圖觀察（給 WP-LOOT／WP-FX 下一輪）：結果框窄時「【珍品】」會在括號中間換行（`116_m3c_loot_result`）；刀的正式特效圖在最後一擊時偶爾在角色背後多一段白弧（`103_m3c_weapon_fx_blade`），方向本身正確。

**回歸結果（§12.5，2026-10-20 最後一輪；log 在 `K:\Project\JY-Mini-OL-Work\logs\m3c_int\gates*\`）**：

| 關卡 | 結果 |
|---|---|
| `tests/run_tests.gd` | 1504 tests, 0 failed |
| `tools/data_lint.gd` | 70 files, 2811 rows, 44 maps, 15 eras, 8 warnings, 0 errors |
| `tools/balance_sim.gd --runs=500` | BALANCE OK (127 cases, 0 failed) |
| `tests/ui/ui_playthrough.gd`（headless） | UI_PLAY_OK（含第 21 步），engine_errors=0 |
| 同上（有視窗，`--ui-shots=K:\Project\JY-Mini-OL-Work\shots\m3c\integrate`） | UI_PLAY_OK，118 張截圖（`m3c_*` 19 張，已逐張檢視） |
| M1 驗收 bot（測試根目錄的新世界） | M1_ACCEPT_OK |
| `tools/m2_acceptance.gd` | M2_ACCEPT_OK |
| `tools/m3a_acceptance.gd` | M3A_ACCEPT_OK（9 個劇本，750 秒） |
| `tools/m3b_acceptance.gd` | M3B_ACCEPT_OK（10 個劇本） |
| `tools/story_acceptance.gd --all` | STORY_ACCEPT_OK（98 jobs） |
| `tools/m3c_acceptance.gd` | M3C_ACCEPT_OK（9 劇本＋classic_strict 重跑） |
| `tools/net_smoke.gd` | 兩個 bot BOT_OK |
| `close_mid_battle_bot`（wm、quit） | 結束碼 0、沒有 SCRIPT ERROR（結束時只有 bot 自己還在 await 的協程造成的 leak 警告，不是遊戲程式） |

介面驗收另修一個既有的不穩：出口鈕在按下與放開之間被場景卷軸重建（「…freed」，WP-LOOT／WP-NAV 都碰過的第 17 步失敗）→ `_walk` 改成已移動就算成功、否則重新找同一個出口再按一次。

### 15.1 第一輪審查修正（2026-10-20，R1）

三份審查（設計／平衡、主機正確性、介面）的修正；每項都有回歸測試。擁有者決定照「最忠實／最不意外」的預設選，標【設計提案】。

| # | 問題 | 修正 | 測試 |
|---|---|---|---|
| R1-A1 | 新手殺一隻黃狗就善惡 < 0，之後每次進出城被官兵（勝率 0%）打死 | `MoralityPk.guard_count(pk, morality, newbie)`：實戰 < `newbie_pk_protect_xp` 時善惡負不追殺，PK值 > 3 照舊；確認框與 `atk.warn` 加「善惡變負後進出有官兵的城都會被攻擊」（主機給 `morality_guard`，新手不警告） | `test_pk_system::test_guards_spare_negative_morality_newbie`、`test_ui_m3c_npc_attack` |
| R1-A2 | 神兵、珍品可無限刷（鬼王 FIGHT、銅甲遇敵、李莫愁任務） | 頭目鎖：`loot_tables.lockout_shichen`（3 個頭目 12 時辰）；`BattleRewards.compute` 對鎖定中的最後一擊者只給必掉（強制掉落照用），擲過的記 `ctx.lockout_rolled`，`LootSystem.on_settle` 寫 `ext.loot.lock`；lint：有神兵群組的表必須有鎖；`balance_sim loot_rate_hour`（頭目珍品 ≤ 0.25／時、全部 ≤ 0.5／時、神兵最快 ≥ 300 小時） | `test_m3c_loot` 2 項、`test_m3c_loot_world::test_boss_lockout_per_character` |
| R1-A3 | 秘笈不扣學點 | 研讀每次扣 `Learning.LP_PER_TIME`（不夠 → `not_enough_lp`，在精神之後）；`manual_speed` 加學點比較；秘笈說明寫學點 | `test_m3c_manual::test_read_costs_learn_points`、`m3c_acceptance manual` |
| R1-A4 | 滅派用執法列，6 萬／15 萬單人 0% | 新列 `m_npc_gm_dizi`、`m_npc_wd_hushan`（只由 `n_gm_sunpopo`、`n_wd_zhike` 的 attack 引用；`m_gm_guard`、`m_wd_guard` 不動）；`m_npc_sunpopo` 數值調低；`miepai_gumu`、`miepai_gumu_repeat`、`miepai_wudang` 改判定 ≥ 50%，`miepai_gumu_newbie` ≤ 5%；art.json 兩個 alias（取代 I4 的「只列印」） | `balance_sim m3c_npcpk` |
| R1-A5 | 後期版物品在 `classic_strict` 照掉；結婚戒指 era | 新規則 `later_loot`（`classic_strict` false）：`roll_table` 把 `src: later` 權重當 0（強制掉落也不行）；神兵與 2004 戒指照 §6.5 綁定保留 `era 1.0A`＋`src later`；`a_lt_jiehunjiezhi` 改 1.0B（只在 1.0B 精英表；DIAO/2-1 京城婚姻，確切【待考證】） | `test_m3c_loot::test_later_loot_off_skips_later_items`、`test_m3c_loot_world::test_no_broadcast_in_classic_strict`、`m3c_acceptance loot_rare_strict` |
| R1-A6 | 頭目「良品」群組多是凡品；李莫愁珍品群組有精品 | 金鍊子、雪雲披風、羽裳、風速靴改 `FINE`（§6.6 範例本來就把金鍊子放良品群組）；李莫愁珍品群組的王難姑毒經（精品）換成華陀內昭圖（珍品）。精英的「良品」群組照舊混有凡品裝備（§6.6 精英列視為「凡品／良品裝備」） | `balance_sim loot_*` |
| R1-B1 | 隊友 `battle_join` 繞過 requires 與門派後果 | `BattleSystem._join_check` 對 `NPC_ATTACK` 呼叫 `NpcAttackSystem.join_reason`（規則、坐牢、剛打退、requires）；`join()` 成功後 `on_join` → `SectSystem.on_npc_attack`（違規、叛派、公敵） | `test_m3c_npc_sect::test_party_join_checks_requires_and_applies_effects` |
| R1-B2 | CHALLENGE NPC 可無冷卻刷 | 打贏後參戰的每個人記 `ext.npcpk.routed[npc] = now + 重生時間`；`check` 回 `npc_routed`（新原因碼與 `err_npc_routed`） | `test_m3c_npc_attack::test_challenge_routed_cooldown` |
| R1-B3 | 線上殺手的善惡、佛法等沒存檔 | `on_battle_finished` 結尾一律 `save_char` | `test_m3c_npc_attack::test_npc_kill_effects_saved_for_online_killer` |
| R1-B4 | 0.5.0.0 護照可加未簽的新裝備欄 | `Passport._is_pre_m3c`：`equipped` 有 WEAPON／ARMOR 以外的鍵就不是舊格式 | `test_passport::test_pre_m3c_passport_verifies`（加兩項） |
| R1-B5 | 刪角＋護照還原可複製神兵 | `LootSystem.on_char_deleted`（釋放登記）、`on_char_restored`（別人名下的拿掉、沒人登記的歸還原者），由 `char_delete`、`passport_restore` 呼叫 | `test_passport::test_restore_deleted_divine_*` |
| R1-B6a | 開戰失敗時已記滅派次數與房間字 | 先 `start_ex`，成功才 bump 與送 `na_attack_start`／`na_miepai`（實際的 `start_ex` 不會回 ≤ 0，屬防禦性） | 既有 `test_sunpopo_group_six_then_four` |
| R1-B6b | 最後一擊者逃走／倒下時訊息說善惡變了、實際沒變 | `BattleRewards` 沒給到時由 `_morality(..., rewarded=false)` 照怪物列補（每殺一個結算一次） | `test_m3c_npc_attack::test_killer_gone_still_gets_morality` |
| R1-B6c | `safe` 房間旗標是否存在 | 已確認：8 間房（茶棚、監獄、雁門關等）有 `"safe": true`，`npc_safe_room` 會觸發（既有測試）；不改 | — |
| R1-C1 | 更換造型沒有回饋 | 主畫面處理 `look_changed`（ui 事件）：訊息列印模板文字、重新打開屬性窗 | `test_ui_m3c_review1`、介面驗收第 21 步 |
| R1-C2 | 小地圖「⟲」看不懂、瀏覽中看不出來、頁尾被切 | 「返」、標題前「瀏覽 」、小地圖頁尾用短句 | 同上、`test_ui_m3c_nav` |
| R1-C3 | 「往XXX」字被切、被房間框蓋住 | `RegionMapView.clamp_label` 把字框夾在畫面內；字在房間框之後才畫 | `test_ui_m3c_review1` |
| R1-C4 | 地圖上沒畫路線 | `AutoWalkCore.remaining_rooms`；區域圖／小地圖畫剩下的路（藍色虛線、「目的地」框、出區的「往XXX」改路線色），江湖全圖連經過的地區、目的地藍圈 | `test_ui_m3c_review1` |
| R1-C5 | 確認框文字矛盾、沒說人數、標題有英文 | CHALLENGE 改「對善良的人動手…／打贏了對方只會敗走」；「你要一個人面對：孫婆婆、古墓弟子 ×5（共 6 人）」（主機 `atk.foes`，第二次 4 人）；滅派寫「跟武當派動手」；標題「動手」；兩處確認都是「動手／再想想」 | `test_ui_m3c_npc_attack`、介面驗收 |
| R1-C6 | 「安全」誤導 | 場景卷軸：房間資料 `safe` 才寫「安全」，否則「無遇敵」；區域圖提示同 | `test_ui_m3c_review1` |
| R1-C7 | 武器特效太短、被氣條蓋住、結果框比最後一擊早出現 | 最短 0.8 格（`WeaponFx.MIN_LEN`，上限仍 1.6 格）；特效畫在腰間氣條之後；主畫面晚一拍才 `show_result`（主機先送 battle_close、同一輪才送最後一擊的事件），結束時排隊中的武器特效拉到現在依序播（`BattleFx.compress_weapon_fx`），`BattleScreen.show_result` 等它播完（最多 0.6 秒）再顯示；等待期間指令列已關 | `test_ui_m3c_review1`、`test_m3c_weapon_fx` |
| R1-C8 | 背包格名被切、詳情重複、部位名不一致 | 三字以內整個寫、太寬自動縮字；詳情名稱不加【珍品】、有部位的不在標題寫重量；`LootUi.SLOT_NAMES` 照人形（頭盔、頸、靴子） | `test_ui_m3c_review1` |
| R1-C9 | 全圖「你在這裡」像在隔壁 | 不壓線的位置裡優先挑離自己記號最近的；仍離別的地點較近或離得遠時畫引線接到自己的朱紅圈 | `test_ui_m3c_review1` |
| R1-C10 | 條件文字可能露出型別碼 | `LootUi.req_text_of` 用 `Requirements.describe`（不明的寫「另有條件」） | `test_ui_m3c_review1` |

擁有者決定（R1，預設值）：(1) 新手保護擋善惡負追殺、不擋 PK值 > 3 與城內行兇的即時官兵；(2) 頭目鎖 1 遊戲日、只鎖群組不鎖必掉、每個角色各自鎖；(3) 研讀每次 1 學點（＝自修）；(4) 滅派用專用弱列、孫婆婆調弱，執法列不動；(5) 後期版物品用規則 `later_loot` 擋（不改 era，避免破壞 §6.5 綁定與 1.0A 掉落表）；結婚戒指 1.0B；(6) CHALLENGE 打退冷卻＝重生時間、每個角色各自計；(7) 頭目良品群組的四件改 FINE。
存檔增量：角色 `ext.npcpk.routed`、`ext.loot.lock`（皆惰性、舊存檔可讀）。規則增量：`later_loot`。原因碼增量：`npc_routed`。
介面驗收另修兩個不穩（R1）：第 21 步江湖全圖趕路一出城就遇敵時先打完再續走；「小地圖往XXX」開始前先停下上一步遇敵後自動續走的趕路。
R1 回歸（log `K:\Project\JY-Mini-OL-Work\logs\m3c_r1fix\g1`、`g10`）：run_tests 1528／0 failed；data_lint 0 errors；balance_sim 128 cases 0 failed；ui_playthrough headless UI_PLAY_OK（有視窗 118 張，`shots\m3c
1fix\`）；M1、M2、M3a、M3b、story --all、M3c（10 劇本）、net_smoke、close_mid_battle（wm、quit）全綠。

### 15.2 第二輪審查修正（2026-10-20，R2）

兩份審查（設計／平衡、介面）。每項都查證過；錯的跳過並寫理由；有改的都有回歸測試（`test_m3c_review2`、`test_ui_m3c_review2`，加上既有測試的更新）。

| # | 問題 | 處理 | 測試 |
|---|---|---|---|
| R2-D1 | 滅派古墓的「再次 4 人」在正常遊玩走不到（動手＝公敵，回墓口就被執法弟子截殺） | 一致採 2001 規則（mengpai/5【已證實】）：孫婆婆的 `group_repeat` 拿掉，每次都是孫婆婆＋5；引擎仍支援 `group_repeat`（沒有資料使用）；`balance_sim miepai_gumu_repeat` 拿掉 | `test_m3c_npc_attack::test_sunpopo_group_six_then_four`（改寫：兩次都 6、引擎用暫改資料列測 6→4）、`test_m3c_review2::test_sunpopo_always_six` |
| R2-D2 | 新手例外沒有規則開關、`classic_strict` 也生效；【設計提案】的即時官兵反而沒擋新手 | 新規則 `newbie_guard_spare`（預設 true、`classic_strict` false）：`PkSystem.guard_spares(ch)` 同時管「善惡負進出城」與 `guard_strike`；新手在城內行兇 → `na_guard_spare`（官兵喝斥、不開打）；房間 view／選單多 `atk.guard_spare`，確認框與主機警告不寫官兵 | `test_m3c_review2` 三項（預設放過、strict 照打、老手照打）；`m3c_acceptance npc_good` 的 A 改成實戰 5000 |
| R2-D3 | 全真、恆山、峨嵋、靈鷲、星宿、血刀的門口戰沒有獎勵（用的是 `no_rewards` 的執法列） | 新列 `m_npc_<qz|hg|em|lj|xh|xd>_gate`（數值＝執法列 ×0.55–0.75，實戰 100、氣藥 0.3；學點：全真 40×4＝160、血刀 30×2＝60【已證實 gaoshou/31 每場】，其他 30【設計提案】）；6 名門口 NPC 改用它們；執法列不動。`balance_sim gate_*`：全真 20 萬 74.8%、血刀 16 萬 79.8%、其他 18 萬 92.8–99.6%，6 萬 0% | `test_m3c_review2::test_gate_fights_give_rewards_enforcers_do_not`、`test_qz_gate_fight_pays_learn_points` |
| R2-D4a | 黃狗只引 2003 FAQ 卻是 1.0A | 找到 2001-10（神鵰大俠 1.0B）17173 丐幫心得「小黃狗…大理、西夏最兇」→ `n_na_xx_huanggou` era **1.0B**（`classic_strict` 只開 1.0A，沒有這條狗；跨 era 的 NPC 照慣例不寫進 1.0A 房間清單） | `test_m3c_review2::test_dog_is_1_0b_…`、`test_data_content` |
| R2-D4b | 黃狗、羊掉豬肉 | 黃狗用自己的 `m_npc_huanggou`（1.0B）掉新物品 `r_gourou` 黃狗肉（2003 FAQ 名稱）；羊（`m_npc_animal`）掉既有的 `r_shoupi` 獸皮（§5.4「肉或皮」） | 同上 |
| R2-D4c | `w_lt_zijinbaguadao` 名稱已證實卻標 `later`，`classic_strict` 擋掉 | src 改 `verified`（2001-05 官方刀類名單；攻擊仍【設計提案】） | `test_m3c_review2::test_zijin_blade_not_blocked_by_later_loot_off` |
| R2-D5 | 頭目鎖讀戰鬥開始時的快照：同場兩隻同表的怪各擲一次；`loot_econ_boss` 沒說是上限 | `BattleRewards.is_locked` 也看本場的 `ctx.lockout_rolled`；`loot_econ_boss` 印「每場都擲＝上限；頭目鎖 12 時辰實際更少」 | `test_m3c_loot::test_two_lockout_monsters_in_one_battle_roll_once` |
| R2-D6a | 秘笈比自修慢 0.40 倍 | 每次熟練 +10、精 10、神 10（`Learning.MANUAL_DEFAULT_*` 與 8 本秘笈）：精神效率＝自修（1.00 倍）、學點 2.00 倍；`manual_speed` 加下限 0.9 倍 | `test_m3c_manual`（數字更新）、`balance_sim manual_speed` |
| R2-D6b | 神兵只比珍品珠索高 5 | **跳過**：珠索是鞭（不同武功線），劍、刀的對照是 1.0A 黑劍 40／後期精品 62，神兵 80–86 是兩倍；O16 的 ×0.4 是為了 `divine_duel`（現在 73.4%，上限 75%），再提高就破擁有者定的門檻 | — |
| R2-D6c | 街頭惡霸 0 與 2000 實戰都 0% | 查證：新手區之外另有會重生的加善惡怪（小嘍囉、山賊、1.0B 不良少年），但都打不過或不在 1.0A 新手區 → 惡霸強度 ×0.5（參考 1500）：實戰 2000 98%、0 實戰 0%（`npc_villain_2k`、`npc_villain_newbie`） | `balance_sim` |
| R2-D7 | 丁春秋、血刀老祖的 `attack.src` 寫 verified，但外人＝公敵是提案 | 兩個 attack 區塊 src 改 `proposal`，`src_note` 寫清楚哪一半已證實 | `test_m3c_review2::test_master_attack_src_is_proposal` |
| R2-U1 | 人形與否只看圖的長寬比（野兔有拳頭圖示、勞德諾沒有） | `data/art.json` 單位條目新欄位 `body`（`human`／`beast`；17 張獸圖、2 張寬的人圖；`DataSchema.ART_BODIES` 檢查、`art_register.py` 保留）；`ArtRegistry.unit_body`；`UnitSprite.is_humanoid()` 管圖示與特效，`body: human` 的寬圖照人的身高畫 | `test_ui_m3c_review2::test_body_flag_…`、`test_rabbit_has_no_weapon_icon_humans_do` |
| R2-U2 | 小地圖「往西夏東郊」蓋住胡楊林 | `RegionMapView.place_exit_label`：尖端外、左右、上下、斜角依序試，選不壓房間框與其他「往XXX」的 | `test_ui_m3c_review2::test_edge_label_does_not_cover_a_room` |
| R2-U3 | 瀏覽時小地圖標題被切 | 瀏覽中地圖鈕只寫「地圖」、標題不寫探索數、`OVERRUN_TRIM_ELLIPSIS` | `test_ui_m3c_review2::test_minimap_browse_title_fits`、`test_ui_m3c_nav` |
| R2-U4 | 全圖：「目的地」壓地名、路線壓印記、「你在這裡」引線劃過「西夏」 | 路線先畫、兩端退到圈外（`walk_route_segments`）；「目的地」選不壓地名／記號／路線的位置（`dest_label_rect`）；「你在這裡」計分加「引線劃過地名」，真的只能劃過時字的部分留白（`leader_pieces`） | `test_ui_m3c_review2::test_world_route_overlays_stay_off_labels` |
| R2-U5 | 戰報露出 `battle_proc_POISON_FANG {…}` | 加模板（1.0B）；`data_lint` 新檢查：每個門派技能效果都要有 `battle_proc_<EFFECT>` 模板 | `test_m3c_review2::test_every_sect_effect_has_a_proc_template`、`test_ui_m3c_review2::test_poison_fang_line_renders` |
| R2-U6 | 特效讀起來差（拳的「小金盤加逃字」、火花在自己腿上） | 查證：「金盤加逃」是躺在逃跑格上的「逃」章，不是拳的特效。真正的問題：落點用站著的身高（倒地的目標落在半空）→ 改用 `body_top()`；目標在正下方時起點挪到身體外側（`STEEP_*`） | `test_ui_m3c_review2::test_lying_target_…`、`test_straight_below_…`、`test_m3c_weapon_fx` |
| R2-U7 | 18 px 刀、劍圖示分不出、超出圓底 | 名牌大小畫單字（劍、刀…）；圖示圖只在 ≥ 28 px 時用（`ICON_ART_MIN`） | `test_ui_m3c_review2::test_icon_at_name_plate_size_is_a_glyph` |
| R2-U8 | 稀有度色對比低、戰報沒上色、兩行重複、詳情「官方：」像開發註記 | 羊皮紙另一組深色（對比 ≥ 4.5）、不加粗；戰報「得到：」依稀有度上色（`loot_log_bb`）；背包格字一律一般字色；珍品以上只送 `lt_rare_drop`（`LootSystem.announces`，不再多一行 `item_gain`）；詳情拿掉「官方：」行 | `test_ui_m3c_review2` 三項、`test_m3c_review2::test_rare_drop_not_announced_twice`、`test_ui_m3c_loot` |
| R2-U9 | 截圖缺：快捷趕路被遇敵搶走、沒有停走原因 | 介面驗收：Esc 停（`m3c_walk_stop_esc`）、強制遇敵＋拉長續走延遲拍「遇敵交戰中，趕路暫停。」（`m3c_walk_encounter_pause`）、`debug_set vital:qi／vital:food`（新 debug 鍵）拍氣血不足、肚子餓；快捷從荒草坡出發，遇敵先打完、等續走才拍 | 介面驗收、`test_m3c_review2::test_debug_vital_key` |
| R2-U10 | 確認框「算。」單獨一行、滅派沒提醒、造型提示與屬性窗矛盾 | CHALLENGE 句改短；有一群對手時加「對方人多勢眾，量力而為。」；造型提示改「拜入門派期間一律穿門派服裝；離開門派後換回這裡選的造型。」（屬性窗提示同步） | `test_ui_m3c_review2::test_confirm_text_…`、`test_look_hint_…` |

擁有者決定（R2，預設值）：(1) 孫婆婆一致採 2001（公敵、每次 6 人），不做 2002 的重複刷；(2) 新手保護做成規則 `newbie_guard_spare`，預設開（含即時官兵，取代 R1 決定 (1) 的「不擋即時官兵」）、`classic_strict` 關；(3) 門口硬闖用有獎勵的專用列，學點依 gaoshou/31（全真 160、血刀 60），其他門派比照 60【設計提案】，強度校準在研究的實戰區間中段；(4) 黃狗 1.0B（`classic_strict` 沒有），黃狗肉新物品；(5) 秘笈每次 +10／精 10／神 10；(6) 街頭惡霸強度減半；(7) 神兵 ×0.4 不動（O16）；(8) 武當大廳 4 名武當弟子（`n_wd_*`）任何人都能打、外人沒有門派後果，各自 3 時辰冷卻，實戰 15 萬約 89.6% 勝，每 30 分鐘真實時間約 4 ×（150 實戰／60 學點），只受每次 −10 善惡限制——照 §5.2／§5.6（2002「武當大廳隨機弟子」刷法）保留；(9) 丁春秋、血刀老祖的外人公敵維持【設計提案】。
存檔增量：無。規則增量：`newbie_guard_spare`。事件增量：`na_guard_spare`。資料增量：怪物 7 列（`m_npc_huanggou`、6 個 `m_npc_<p>_gate`）、物品 `r_gourou`、模板 2 列、`art.json` 的 `body` 欄與 7 個 alias。debug 增量：`vital:<id>`。
R2 回歸（log `K:\Project\JY-Mini-OL-Work\logs\m3c_r2fix\g1\`）：run_tests 1555／0 failed；data_lint 70 files、2824 rows、0 errors；balance_sim BALANCE OK（128 cases、runs=500；`gate_*`、`npc_villain_*`、`manual_speed` 1.00 倍）；ui_playthrough headless UI_PLAY_OK（engine_errors=0）；M1_ACCEPT_OK（測試根目錄新世界）；M2_ACCEPT_OK；M3A_ACCEPT_OK（9 劇本）；M3B_ACCEPT_OK（10）；M3C_ACCEPT_OK（10）；STORY_ACCEPT_OK（98 jobs）；net_smoke PASS；close_mid_battle wm、quit 結束碼 0。
有視窗的介面驗收：`shots\m3c\r2fix\` 一輪 UI_PLAY_OK（137 張，含新的 `m3c_walk_*` 4 張）；之後補拍三輪分別在第 9、14、18 步（戰鬥結果、飛鴿傳書點擊、故事對話；都不是 M3c 的步驟）因視窗計時失敗——同時有別的專案的 Godot 測試在跑，headless 版每次都過。

### 15.3 第三輪審查修正（2026-10-20，R3）

兩份審查（設計／平衡、介面），都標「小問題、不擋發行」。每項都查證過；有改的都有回歸測試（`test_m3c_review3`、`test_ui_m3c_review3`）。

| # | 問題 | 處理 | 測試 |
|---|---|---|---|
| R3-D1 | `w_lt_zijinbaguadao` 數值是編的卻標 `verified`（為了過 `later_loot`） | src 改 `proposal`（與傳家寶刀／寶甲／寶鞋同一規則：真名、編的數值）；`later_loot` 只擋 `later`，所以 `classic_strict` 仍會掉、但標的是【設計提案】 | `test_m3c_review3::test_zijin_blade_is_proposal_and_still_drops_in_strict`、`test_m3c_review2` 改期望值 |
| R3-D2 | 黃罩甲仍是 M3b 舊級距 def 16（比所有 M3c 防具都高） | def ⌈35 ÷ 5⌉ = 7（O13，同射日短衣 35→7）、`official { def 35, weight 0 }`；src_note 開頭寫現值；`balance_sim mw_mawang_huangjia` 備援值 7（55%，40–90% 內） | `test_huangjia_on_m3c_armor_scale` |
| R3-D3 | 頭目鎖跟著最後一擊者：4 人輪流 → 玄鐵約 250 小時、全服第一把神兵約 83 小時 | **神兵全服鎖**：有 `lockout_shichen` 的表，神兵群組全服每 12 時辰只擲一次（`world.divine_lock`、`ctx.divine_locked`／`divine_rolled`、`BattleRewards.DIVINE_LOCK_SCOPE`）；一般群組照舊每角色各鎖（輪流搶最後一擊時每人每鎖定期仍只一擲，每人每小時的量＝單人模型）。`loot_rate_hour` 改 4 人 × 3 頭目模型：每把最快 1000 小時、全服第一把 333 小時（≥ 300） | `test_roll_table_divine_group_world_lock`、`test_boss_kill_locks_the_divine_roll_for_everyone` |
| R3-D4 | 神兵可以寄放在新手分身上（叫戰故意輸；新手不能被強制 PK、官兵放過） | `PkSystem.newbie_protected`：**身上有神兵就沒有新手保護**（強制 PK、`guard_spares`、快照 `newbie` 標記、門派捉拿都用它；`LootSystem.holds_divine`） | `test_divine_holder_loses_newbie_protection` |
| R3-D5 | 羊、採礦師唯一出處 2002-06-17 卻是 1.0A（黃狗 2001-10 已改 1.0B） | 兩者 era 1.0B（本作最晚的時代；【待考證】2001 有沒有）；從 1.0A 房間清單移除、改用 npc 的 `room` 欄位（M3b L7） | `test_sheep_and_miner_are_1_0b_like_the_dog`、`test_data_content` 改數量 |
| R3-D6 | 機關人 gaoshou/25「--（無）」卻掛 `lt_elite_martial`（含珍品） | 拿掉 loot_table；只留 M3b 以前的凡品「機關零件」 | `test_jiguanren_drops_no_treasure` |
| R3-D7 | 白猿「扣善惡度」（鐵心 FAQ）沒做 | **記錄、暫不做**：FAQ 說的是大理後沙漠山洞的白猿（本作沒有），本作的白猿是龍門任務必殺；善惡 0 的武當弟子殺了會被官兵追殺、量無出處 → §1.2【待考證】；「黃兔」本作沒有這種怪 | `test_baiyuan_morality_is_documented_as_unverified` |
| R3-U1 | 刀特效身後的白色箭頭 | 查證：不是特效，是「輪到我」的白色雙線菱形畫在 VM 的格子——出招前衝／走路動畫還沒播完時人物不在那格，菱形被身體擋住只露出左右兩角。改成只在人物靜止時畫、畫在人物現在的格子（`BattleIsoView.my_turn_ring_visible／center`） | `test_my_turn_ring_only_at_rest_and_under_the_figure`；`iso_gallery` 新 7 張方向圖 |
| R3-U2 | 劍特效截圖默默不見；方向只拍得到往下 | 截圖改在 `_process` 輪詢到特效正在畫時拍（一刀打死時戰鬥先結束也拍得到）；沒拍到記 `ui.warn`。`tools/iso_gallery.gd` 加 7 個方向（左、左下、右下、右上、左上、正下、右；刀劍拳棍）——主機開場站位固定，真實介面驗收拍不到 | 介面驗收 `m3c_weapon_fx_sword` 有圖 |
| R3-U3 | 結果框「×1」單獨一行 | `BattleScreen.loot_line_bb(items, font, size, width)` 自己排行：一件「名 ×n」放不下就整件換行 | `test_loot_line_wraps_whole_items`、`test_battle_screen_result_uses_packed_loot_line` |
| R3-U4 | 出招時特效蓋住氣值數字 | 氣值小條畫回特效上面；出招者的小條底板淡到 35%（特效起點仍透得出來） | `test_hp_pill_plate_fades_while_striking` |
| R3-U5 | 城裡時「高昌 你在這裡▶ 西夏」 | `WorldMapView.here_style_penalty`：▶／◀ 指著自己的地名 +3、箭頭前方 28px 是別的地點 +3、貼著別的地名／記號 +2、左右兩側 +0.5、離自己的記號每超過 40px +1（不壓線仍優先） | `test_here_label_not_pointing_at_own_name_in_cities` |
| R3-U6 | 小地圖邊緣切到的房間露出半個房名 | `RegionMapView.is_clipped`：小地圖（follow_current）沒有整個在畫面內的房間只畫淡框、不寫房名／圖示 | `test_minimap_clipped_rooms_are_detected` |
| R3-U7 | 打完仗還寫「遇敵交戰中」 | 打贏、要續走時頁尾寫「戰鬥結束，稍後繼續趕路。」（`AutoWalker.RESUME_WAIT_TEXT`） | `test_resume_wait_text_after_a_won_fight`；介面驗收檢查 |

擁有者決定（R3，預設值）：(1) 神兵用全服鎖（每個頭目每遊戲日全服一擲），不是隊伍鎖——隊伍鎖擋不住四人各自單刷；一般掉落仍是每角色各鎖；(2) 持有神兵＝失去新手保護（三個選項裡唯一同時擋住「寄放」與「新手隊友搶最後一擊」的）；(3) 白猿扣善惡延後（§1.2）；(4) 紫金八卦刀仍在 `classic_strict` 掉落（數值標【設計提案】，與其他提案精英掉落一致）。
存檔增量：世界 `divine_lock`（舊存檔沒有＝沒鎖）。協定、規則、選項增量：無。
R3 回歸（log `K:\Project\JY-Mini-OL-Work\logs\m3c_r3fix\`）：run_tests 1570／0 failed（`run_tests4.log`）；data_lint 0 errors（8 個既有 warnings）；balance_sim BALANCE OK（128 cases、runs=500；`loot_rate_hour` 每把神兵最快 1000 小時、全服第一把 333 小時；`mw_mawang_huangjia` 55%）；M1 bot（新世界 `w_m3c_r3_m1`）、M2、M3a、M3b、story --all、M3C_ACCEPT_OK（10 劇本）、net_smoke、close_mid_battle（wm、quit）全綠；介面驗收 headless UI_PLAY_OK、有視窗 UI_PLAY_OK（129 張，`shots\m3c\review3fix\uiplay3\`；`m3c_weapon_fx_sword` 有圖）；`tools/iso_gallery.gd` 18 張（`shots\m3c\review3fix\gallery\`，7 張武器特效方向）。
