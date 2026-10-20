# M1 實作計畫：單機核心循環（M1_PLAN）

> 版本：v1.0（2026-10-17）
> 依據：`docs/GDD.md` v0.2（§13.1 M1 列）、`docs/TECH_ARCH.md`、`docs/research/verified_research.md`
> 擁有者已確認的預設：ATB 格子戰鬥**預設開啟等待模式**；主機離線時世界凍結；死亡規則預設 `classic_standard`（懷舊標準）；世界照原作 2001 地理：城市之間走路、京城是 1.0B 內容（預設世界沒有京城）、驛站只辦送信，馬車是預設關閉的伺服器選項（`docs/WORLD_2001.md`，取代原本的「京城驛站樞紐」）；只在好友間測試。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

M1 由 5 個工作包（WP）**同時**實作，實作者之間不溝通。本文件就是唯一的協調依據：

1. 本文件的**名稱、檔案路徑、類別名、函式簽名、字典欄位、intent 名稱、事件 key、資料表欄位、錯誤原因碼**都具有約束力。實作者不得自行改名，也不得把欄位改成別的型別。
2. 本文件沒有規定的**內部細節**（私有函式、內部資料結構、演算法寫法）由各 WP 自行決定。
3. 本文件與 GDD／TECH_ARCH 衝突時，**以本文件為準**（偏差都列在 1.3）。本文件沒寫的，回頭看 GDD → TECH_ARCH。
4. 發現本文件有錯或缺漏時：照「最不意外」的方式實作，在程式裡寫 `# M1_PLAN 缺漏：……` 註解，並在交付說明中列出。**不要**修改別的 WP 擁有的檔案。

### 0.2 標記

沿用 GDD 第 0 章：【已證實】【後期版】【待考證】【設計提案】。本文件新增的數值一律是【設計提案】，寫進資料表時 `src` 填 `"proposal"`；有來源的填 `"verified"`／`"later"`；來源互相矛盾的填 `"unverified"`。

### 0.3 全域規則（所有 WP）

| # | 規則 |
|---|---|
| G1 | **主機權威**：所有遊戲邏輯（擲骰、戰鬥、學武、經濟、任務、存檔）只在主機執行。UI 只透過 `NetworkManager.send_intent()` 送 intent，只讀 `ClientState` 與 `GameData`。 |
| G2 | **離線同一條路徑**：離線模式（`OfflineMultiplayerPeer`，peer 1）走的程式碼與連線完全相同（TECH_ARCH 6.4 本地短路）。不得寫「離線時直接改角色」的捷徑。 |
| G3 | `core/**` 是純邏輯：`extends RefCounted`，**不得**引用任何 Autoload（`GameData`、`WorldServer`…）、不得碰場景樹。資料表以參數 `tables: Dictionary`（= `GameData.tables` 的形狀：`table_name -> { id -> row }`，另含 `"maps": { region_id -> map }`）傳入；規則以 `rules: Dictionary`（= `GameData.rules`，已展開的 rule_profile）傳入；亂數以 `rng: RandomNumberGenerator` 傳入。 |
| G4 | 玩家看得到的文字一律**繁體中文**，而且放在資料（`name`、`desc`、`text_templates.json`）裡；程式識別字、id、欄位名一律英文 snake_case。主機**不送組好的句子**，只送結構化事件（TECH_ARCH 11.1）。 |
| G5 | JSON 數字載入後是 float。整數欄位由 `DataSchema.INT_FIELDS`（資料）或各模型的 `from_dict()`（存檔）轉回 int。所有存檔模型必須能 `from_dict(to_dict(x))` 完整往返。 |
| G6 | **不要 git commit**。 |
| G7 | 測試結束一定要關掉自己啟動的每個 godot 程序，並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認沒有殘留；有殘留就 `taskkill /F /PID <pid>`。 |
| G8 | 新增或改名 `class_name` 之後，先跑一次 `godot --headless --path . --import` 更新全域類別快取，再跑測試。 |
| G9 | 不得新增 Autoload、不得修改 `project.godot`（凍結檔，見 2.2）。 |
| G10 | 每個 WP 的單元測試只能依賴：自己的程式碼、凍結檔、測試內自建的字典 fixture。跨 WP 的整合測試只有 WP-WORLD 的 `test_world_*.gd` 與 bot（合併後才會全綠）。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=character]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500
"$G" --headless --path . -- --no-steam --offline --world=m1_accept --profile=m1bot \
     --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
```

---

## 1. M1 範圍與驗收

### 1.1 範圍清單（逐項打勾）

| # | 項目 | 來源 | 擁有 WP | 驗收條件 |
|---|---|---|---|---|
| S1 | 創角：選性別、擲骰 7 項屬性（可無限重擲，單項上限 25）、分配 5 點自由點數（可超過 25）、生日月份、出生城（西夏／大理；京城不可） | GDD 2.1 | CHAR（規則）、WORLD（intent）、UI | 擲出值都在 [13,25]；5 點分配總和必須剛好 5；京城出生被拒（`bad_value:birth_city`） |
| S2 | 初始物品：精藥水 ×5、銀兩 100、布衣（已裝備）、木刀（已裝備）；學點 100 | GDD 2.1、2.4 | CHAR | 新角色的角色表符合 |
| S3 | 7 項屬性、衍生數值（精氣神內上限、負重）、進度數值（實戰、學點、歷練、名聲、善惡、殺氣、PK值、金錢） | GDD 2.2–2.4 | CHAR | 公式見 4.2，單元測試逐項比對 |
| S4 | 17 項基本武學資料；M1 可學的基本武學（見 5.6）；特殊武功最多 16 套 | GDD 4.1 | DATA、CHAR | 第 17 套被拒 `cap_arts16` |
| S5 | 學武：消點（向師父學）、自修、武館；熟練度曲線；悟性效率表；實戰上限；學點上限 | GDD 4.2–4.3 | CHAR、WORLD | 4.3 的公式與表逐項有測試 |
| S6 | 屬性成長：讀書識字每 10 級悟性 +1（最多 +10）；`attr_from_basic_skills`（預設關）；生日成長 | GDD 2.2 | CHAR | 單元測試 |
| S7 | 飽食、飲水下降；飽食 0 時回復 ×0.25；自然回復；打坐（修煉內力）；施展內功；客棧休息；服藥過量 | GDD 2.3、2.5 | CHAR、WORLD | 單元測試；客棧休息全回復並扣 20 兩 |
| S8 | 世界：西夏城＋郊外、大理城＋郊外、西路（南坡、大漠、河川）、東路（東郊、恆山山麓、華陰道、嵩山古道）、少林、華山、血刀洞迷宮（房間圖，見 5.1、WORLD_2001） | GDD 7.1–7.2 | DATA、WORLD | 從 `xx_square` **走路**可到達所有房間（BFS，不含驛站路線） |
| S9 | 驛站送信（自己走到目的地驛站）；馬車旅行只在伺服器選項 `stagecoach_enabled` 時【設計提案・非原作】 | GDD 7.1 | WORLD | 預設 `travel` 回 `stagecoach_disabled`；打開後西夏 → 大理成功、扣錢、位置改變 |
| S10 | 世界時鐘、時辰、晝夜；夜間打烊（只有武館、鏢局、驛站、客棧營業） | GDD 7.1 | WORLD | 夜間向商店買東西被拒 `closed_night` |
| S11 | 查小鏞設定記錄點；死亡後回記錄點，沒有就回出生地 | GDD 6.4、7.1 | WORLD | 單元＋整合測試 |
| S12 | NPC：對話、商店買賣（收購價 30%）、師父教學、客棧、驛站、拜入門派（性別與 `join_requires`）、少林齋食、定點戰鬥 | GDD 3、7、9.4 | WORLD | 每種服務一個整合測試 |
| S13 | 門派：少林、華山（拜入、門派技能 佛法／儒風 的學習與戰鬥觸發） | GDD 3.2–3.4 | DATA、CHAR、BATTLE、WORLD | 女性拜少林被拒 `req_gender`；佛法觸發可在固定種子重現 |
| S14 | 踩地雷遇敵（野外房間每步依遇敵率擲骰）；守護者之煙 | GDD 5.1 | BATTLE（擲骰）、WORLD | 固定種子下遇敵可重現 |
| S15 | ATB 格子戰鬥 12×8；指令 移、攻、武（招式＋成數 1–10）、防、休、裝、逃；黃色逃跑格；等待模式（預設開）與純半即時；怪物 AI | GDD 5.2–5.6、TECH_ARCH 10 | BATTLE、UI | 決定性回放測試；等待模式逾時自動「防」 |
| S16 | 傷害、命中、爆擊、浮動、內功加成、反擊、成數、兵器類別修正 | GDD 5.5–5.6 | BATTLE | 公式單元測試；平衡模擬達標（6.3） |
| S17 | 戰鬥獎勵：實戰、學點（GDD 2.4 公式）、掉落、銀兩、善惡、殺氣 | GDD 2.4、5.8 | BATTLE（計算）、CHAR（套用） | 單元測試 |
| S18 | 死亡：`death_rule` 三值 STRICT_2001／STANDARD／CASUAL，四個預設組合；屍體與 `corpse_window`（本人拾回） | GDD 6.4 | CHAR（懲罰）、WORLD（屍體、重生） | 6.2 的死亡測試矩陣全過 |
| S19 | 任務：KILL、DELIVER、TALK、REACH；大兔皮、種稻、驛站送信、剿滅山賊、岳不群的考驗 | GDD 8 | DATA、WORLD | 每個任務一個整合測試 |
| S20 | 物品：四分頁背包、負重、持有上限 300 件、裝備（武器、防具）、使用、丟棄、腐壞 | GDD 9.1–9.3 | CHAR、WORLD | 單元測試 |
| S21 | 生活技能 4 種：種田、樵夫、釣魚、廚師（學習、工具、動作、產出、熟練度） | GDD 9.5 | DATA、CHAR、WORLD | 每種技能一個整合測試 |
| S22 | 存檔：每個 identity 最多 3 個角色，原子寫入；自動存檔、登出、關服時存檔 | GDD 12.5、TECH_ARCH 8 | WORLD | 關服重開後角色完整 |
| S23 | UI：標題、角色選擇、創角、主畫面（場景描述、出口、人物、動作、訊息紀錄、狀態列）、戰鬥畫面（格子、時間棒、指令列、招式／成數選擇、戰報）、屬性／武功／背包裝備／任務面板、NPC 對話／商店／學武／驛站對話框 | GDD 11、TECH_ARCH 12 | UI | 6.5 的 UI 檢查清單 |
| S24 | 驗收 bot：從創角一路玩到鬼王洞 | GDD 13.1 | WORLD | 6.4 全部步驟通過，輸出 `M1_ACCEPT_OK` |

### 1.2 M1 不做（明確延後）

PK（叫戰、強制 PK、PK值變動）、組隊與經驗分享、多人同場戰鬥與中途加入、聊天頻道（只保留 M0 的千里傳音，**M1 不扣飲水**）、屍體授權撿取與他人撿屍、門規／坐牢／叛派／開除、指令 特 毒 醫 暗 陣 內 穴 輕、戰鬥中用物品、錢莊、鏢局、讀書（秘笈）、其他 9 派、少林木人巷與十八銅人陣、京城完整城市機能、惡方 NPC 主動攻擊（葉二娘、南海鱷神在 M1 只能對話）、小地圖圖塊、F1–F8 指令列與 Alt 物品列、殺氣消除 NPC、名字顏色以外的善惡效果、伺服器選項面板。

### 1.3 與 GDD／TECH_ARCH 的偏差（M1 決議）

| # | 偏差 | 理由 |
|---|---|---|
| D1 | 區格內容改為**房間圖**（`maps/<region>.json` 的 `rooms[]`，見 3.11.8），不使用 TECH_ARCH 5.3 的 `tiles`／`exits.at` 圖塊格式；小地圖延到 M4 | 任務要求 MUD 式文字場景；房間圖比圖塊好驗證與測試 |
| D2 | UI 場景放在 `ui/game/**`，不是 TECH_ARCH 12 的 `ui/char`、`ui/main`… | 工作包分工 |
| D3 | 角色模型放在 `core/character/**`，不是 TECH_ARCH 4.1 的 `core/model`、`core/rules`；戰鬥公式放在 `core/battle/battle_formulas.gd` | 工作包分工，避免一個檔案兩個擁有者 |
| D4 | `masters.json` 的欄位 `art_id` 改名為 `skill_id`，可以指向基本武學、特殊武功、門派技能、生活技能 | 師父也教基本武學與門派技能（研究：梁發教基本武學） |
| D5 | 熟練度曲線解讀為**累計**：到達等級 L 所需累計熟練度 = L³ × 係數 | 研究顯示學點上限 65,200 與「每次消點約 10–20 熟練度」，只有累計解讀能讓 100 級落在這個量級 |
| D6 | 鬼王洞小鬼的氣由 GDD 7.3 的 1,200 下修為 450；野兔等怪物的防具強度偏高 | 依 GDD 5.6 公式與校準目標（新手打野兔 8–15 點）反推（4.6） |
| D7 | `battle_cmd` 不帶 `unit_id`；主機以 peer 找到該玩家唯一的戰鬥單位 | M1 一個 peer 只有一個單位 |
| D8 | 新增 intent `fight`（定點 NPC 戰鬥）與 `meal`（少林齋食）；新增資料表 `life_skills.json` | GDD 5.1「定點 NPC」、3.4 少林生活、9.5 生活技能 |
| D9 | `s2c_battle_tick`（1 Hz 校正）延到 M2；M1 只用 `battle_gauges` 事件錨點 | 單機與區網測試不需要 |
| D10 | 新增啟動參數 `--time-scale=<0.1–100>`（只影響主機世界時鐘與戰鬥 tick），供 bot 與手動測試加速 | 驗收 bot 需要在合理時間內練功 |

### 1.4 最終驗收（M1 完成的定義）

- A1：`run_tests.gd` 全綠（含 M0 既有的 45 個測試）。
- A2：`data_lint.gd` 0 錯誤。
- A3：`balance_sim.gd` 全部案例落在 6.3 的區間內。
- A4：驗收 bot（6.4）以預設規則（`classic_standard`）跑完並輸出 `M1_ACCEPT_OK`，結束碼 0。
- A5：死亡規則矩陣（6.2 的 `test_world_death.gd`）對 STRICT_2001／STANDARD／CASUAL 全部正確。
- A6：`net_smoke.gd` 仍然通過（M0 迴歸）。
- A7：手動遊玩：以離線模式從標題畫面創角，走到少林拜師、打一場戰鬥，全程無腳本錯誤（6.5 清單）。
- A8：結束後 `tasklist` 沒有殘留的 godot 程序。

---

## 2. 工作包與檔案所有權

### 2.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-DATA** | `data/*.json`、`data/maps/*.json`、`data/patches/*`；`core/data/data_schema.gd`、`core/data/data_loader.gd`、`core/data/patch_applier.gd`；`tools/data_lint.gd`、`tools/validate_data.gd`；`tests/fixtures/data_min/**`；`tests/unit/test_data_loader.gd`、`tests/unit/test_data_content.gd`（新） | 第 5 章全部內容；3.11 的 schema；lint 新檢查（3.11.15）；`text_templates.json` 涵蓋 3.8／3.7 的每個 key |
| **WP-CHAR** | `core/character/**`（新目錄）；`tests/unit/test_character*.gd`（新） | 3.2 的全部類別；4.1–4.5、4.10–4.13 的公式 |
| **WP-BATTLE** | `core/battle/**`；`tests/unit/test_battle*.gd`（新）；`tests/fixtures/battle_*.json`（新）；`tools/balance_sim.gd`（新） | 3.4 的全部類別；4.6–4.9、4.14 的公式；決定性回放；平衡模擬 |
| **WP-WORLD** | `server/**`（含既有 `server/session.gd` 與新目錄 `server/intents/`）；`autoload/world_server.gd`、`autoload/client_state.gd`、`autoload/save_manager.gd`；`core/protocol.gd`；`tests/unit/test_world*.gd`（含既有 `test_world_server.gd`）、`tests/unit/test_save_manager.gd`、`tests/unit/test_protocol_m1.gd`（新）；`tests/bots/m1_playthrough_bot.gd`（新）；`README.md` | 3.5–3.10；所有 intent 處理器；遊戲主機系統；存檔；驗收 bot |
| **WP-UI** | `ui/game/**`（新目錄）；`ui/boot/**`；`ui/common/**`；`ui/theme/**`；`ui/debug/**`；`autoload/scene_router.gd`；`tests/unit/test_ui*.gd`（新） | 3.12 的全部畫面；TextRenderer 擴充；開機與路由 |

### 2.2 凍結檔（M1 任何 WP 都不得修改）

`project.godot`、`autoload/game_data.gd`、`autoload/network_manager.gd`、`autoload/steam_manager.gd`、`core/util/*`、`tests/run_tests.gd`、`tests/test_case.gd`、`tests/unit/test_core_util.gd`、`tests/bots/chat_bot.gd`、`tools/net_smoke.gd`、`tools/steam_api_probe.gd`、`tools/check_vendor.ps1`、`addons/**`、`assets/**`、`docs/**`（本文件只由協調者修改）。

> `test_core_util.gd` 測試了 `Protocol.validate_args` 與 `TextRenderer`；WP-WORLD 與 WP-UI 修改這兩個類別時必須保持它綠燈。

### 2.3 依賴與合併

```
WP-DATA ─┐
WP-CHAR ─┼──▶ WP-WORLD ──▶ 驗收 bot
WP-BATTLE┘        │
                  ▼
                WP-UI（只依賴 3.5.4 的 ClientState API 與 3.7／3.8 的字串）
```

- WP-CHAR、WP-BATTLE、WP-DATA 彼此**互不依賴**：
  - BATTLE 只吃「戰鬥者規格字典」（3.3），不引用 `Character`。
  - CHAR 不引用 `Battle`；戰鬥結果以字典（3.4.6）交給 CHAR。
  - 兩者的測試都用測試內自建的 `tables` 字典，不讀 `res://data`。
- WP-UI 不引用 `server/**`、`core/battle/**`、`core/character/**` 的類別（可以讀 `GameData.tables`）。UI 需要的 intent／事件字串自行定義在 `ui/game/ui_keys.gd`（`class_name UiKeys`），值必須與 3.6、3.8 完全相同。
- 所有 WP 在同一個工作目錄並行。別人的檔案寫到一半時，你的測試可能暫時無法載入；這時用 `--filter=` 只跑自己的測試。
- 合併後的整合由 WP-WORLD 主導（`test_world_*.gd`、bot）。平衡數值的最後調整由 WP-DATA 依 `balance_sim` 的輸出修改 `monsters.json`；**公式常數不准改**（它們來自 GDD）。

---

## 3. 介面契約

### 3.1 共用慣例

| 項目 | 規定 |
|---|---|
| 結果字典 | 會失敗的操作一律回傳 `{ "ok": bool, "reason": String, ... }`；成功時 `reason == ""`。`reason` 只能用 3.7 的原因碼。 |
| 屬性 id | `str` 臂力、`guts` 膽識、`wit` 悟性、`luck` 福緣、`cal` 定力、`agi` 機敏、`con` 根骨。順序固定為 `ATTR_IDS := ["str","guts","wit","luck","cal","agi","con"]`。 |
| 生命數值 id | `jing` 精、`qi` 氣、`shen` 神、`neili` 內力、`food` 飽食、`water` 飲水（皆 int）。 |
| 技能種類 | `BASIC`（basic_skills 表）、`ART`（martial_arts 表）、`SECT`（sects 表的 `sect_skill`）、`LIFE`（life_skills 表）。 |
| 武功類別 | `FIST BLADE SWORD STAFF WHIP SPEAR INNER LIGHTNESS HIDDEN POISON MEDIC FORMATION ACUPOINT`（GDD 4.4）。戰鬥「武」只用前 6 類。 |
| 兵器類別 → 對應基本武學 | FIST→`basic_fist`、BLADE→`basic_blade`、SWORD→`basic_sword`、STAFF→`basic_staff`、WHIP→`basic_whip`、SPEAR→`basic_spear`。沒裝武器 = FIST。 |
| 方向 | `N S E W NE NW SE SW U D IN OUT`；反向：N↔S、E↔W、NE↔SW、NW↔SE、U↔D、IN↔OUT；中文標籤：北 南 東 西 東北 西北 東南 西南 上 下 進 出。 |
| 時間 | 世界時間 `world_time_s`（float，只在主機運作時累加，乘上 `time_scale`）。所有「遊戲時間」計時都用世界時間。 |
| 實例 id | 角色 `ch_<8 hex>`、物品實例 `it_<8 hex>`、屍體 `cp_<8 hex>`，由主機 RNG 產生；保證在該世界內唯一。 |
| 金錢上限 | 6,000,000 兩；超過的部分捨棄（並回 `money_cap` 給買賣類操作）。 |

### 3.2 WP-CHAR：`core/character/`

所有檔案 `extends RefCounted`。靜態工具類別只有 `static func`。

#### 3.2.1 `character.gd` — `class_name Character`

```gdscript
const SCHEMA_VERSION := 1
const ATTR_IDS := ["str","guts","wit","luck","cal","agi","con"]
const MONEY_CAP := 6000000
const MAX_CHARS_PER_IDENTITY := 3

var id: String              # "ch_1a2b3c4d"
var identity: String        # "local_<32hex>" / "steam_<id>"
var name: String
var gender: String          # "M" / "F"
var birth_month: int        # 1–12
var birth_city: String      # region id："xixia" / "dali"
var created_s: float        # 世界時間
var online_s: float         # 累計上線（世界時間）
var attrs: Dictionary       # 基礎屬性（擲骰 + 分配 + 成長），不含裝備加成
var vitals: Dictionary      # { jing, qi, shen, neili, food, water }
var combat_xp: int          # 實戰經驗
var learn_points: int       # 學點
var lili: int               # 江湖歷練
var fame: int               # 名聲
var morality: int           # 善惡 −1000..1000
var killing_intent: int     # 殺氣 ≥ 0
var pk: int                 # PK值（M1 恆為 0）
var money: int
var sect: String            # "" / "shaolin" / "huashan"
var sect_enemies: Array     # 成為公敵的門派 id（M1 不會增加）
var skills: SkillBook
var inventory: Inventory
var location: Dictionary    # { "region": String, "room": String }
var respawn: Dictionary     # { "region": String, "room": String }；空字串 = 未設定
var quests: Dictionary      # { "active": { quest_id: { "step": int, "counts": {key: int} } }, "done": { quest_id: int(完成次數) } }
var flags: Dictionary       # 任務旗標等：{ flag: true }
var buffs: Dictionary       # { "smoke_until_s": float }
var qi_bonus: int           # 修煉累積的氣上限加成
var cultivations: int       # 已用的修煉次數
var counters: Dictionary    # 內部計時與累計器（見 3.2.7）；欄位由 WP-CHAR 自訂，但必須可序列化
var dead_count: int
var dormant: Dictionary     # TECH_ARCH 5.5.4；M1 永遠是空字典，但要往返保存

static func from_dict(d: Dictionary) -> Character   # 轉型 int；缺欄位補預設值
func to_dict() -> Dictionary                        # 3.10.1 的格式
func effective_attrs(tables: Dictionary, options: Dictionary) -> Dictionary
    # 基礎 + 裝備 effects.attr + 讀書識字每 10 級悟性 +1 + (options.attr_from_basic_skills 時的基本武學成長)
func derived(tables: Dictionary, options: Dictionary) -> Dictionary   # = DerivedStats.compute(self, tables, options)
func to_sheet(tables: Dictionary, options: Dictionary, rules: Dictionary) -> Dictionary   # 3.9.1
func to_summary(tables: Dictionary) -> Dictionary   # 3.9.5 的一列
func to_combatant(tables: Dictionary, options: Dictionary, side: int, peer_id: int) -> Dictionary   # 3.3
func clamp_vitals(tables: Dictionary, options: Dictionary) -> void   # 把 vitals 夾在 [0, max]（food/water 夾在 [0,100]）
func add_money(n: int) -> int          # 回傳實際增加量（受上限影響）；n 可為負，不會低於 0
func add_learn_points(n: int, rules: Dictionary) -> int   # 回傳實際增加量；rules.xuedian_cap > 0 時夾住
func apply_battle_outcome(unit: Dictionary, tables: Dictionary, options: Dictionary) -> void
    # unit = 3.4.6 的 units[uid]：寫回 qi/neili/jing/shen；依 weapon_uid 更新裝備
func apply_rewards(r: Dictionary, rules: Dictionary) -> Dictionary
    # r = 3.4.7 的單人獎勵（或任務獎勵 3.11.11 rewards）；回傳實際入帳 { combat_xp, learn_points, money, fame, morality, killing_intent }
    # 物品不在這裡處理（由 WORLD 呼叫 inventory.add 並產生事件）
```

#### 3.2.2 `skill_book.gd` — `class_name SkillBook`

```gdscript
var entries: Dictionary   # skill_id -> { "level": int, "prof": int }  （prof 為累計熟練度）

static func from_dict(d: Dictionary) -> SkillBook
func to_dict() -> Dictionary
static func kind_of(skill_id: String, tables: Dictionary) -> String   # "BASIC"/"ART"/"SECT"/"LIFE"/""
static func skill_name(skill_id: String, tables: Dictionary) -> String
func level(skill_id: String) -> int        # 沒學過 = 0
func prof(skill_id: String) -> int
func has(skill_id: String) -> bool         # level ≥ 1
func add_prof(skill_id: String, amount: int, tables: Dictionary, cap_level: int) -> Dictionary
    # 加熟練度並依曲線（4.3）重算等級；等級不會超過 cap_level（超過的熟練度保留但等級停在 cap）
    # 回傳 { "before": int, "after": int, "prof": int }
func set_level(skill_id: String, lv: int, tables: Dictionary) -> void   # prof 設為該等級的門檻值
func special_arts(tables: Dictionary) -> Array    # level≥1、kind ART、非 monster_only 的 id 清單
func highest_special_art(tables: Dictionary) -> String   # 等級最高者；同級比 prof，再同比 id 字典序；沒有回 ""
func best_level_in_category(category: String, tables: Dictionary) -> int   # 例：LIGHTNESS、INNER
static func prof_for_level(skill_id: String, lv: int, tables: Dictionary) -> int   # 4.3 曲線
static func level_for_prof(skill_id: String, p: int, tables: Dictionary) -> int
```

#### 3.2.3 `inventory.gd` — `class_name Inventory`

```gdscript
const MAX_PIECES := 300
const SLOTS := ["WEAPON", "ARMOR"]
var items: Array          # [{ "uid": "it_..", "id": "c_jingyao", "n": 5, "born_s": float, "lots": [{ "born_s": float, "n": int }] }]
                          # 2026-10 改版：lots 由舊到新、總數＝n；born_s＝最舊一批（舊存檔沒有 lots → 整疊當一批）
var equipped: Dictionary  # { "WEAPON": uid 或 "", "ARMOR": uid 或 "" }

static func from_dict(d: Dictionary) -> Inventory
func to_dict() -> Dictionary
func pieces() -> int                                 # Σ n
func weight(tables: Dictionary) -> int               # Σ n × items.weight
func count(item_id: String) -> int
func find(uid: String) -> Dictionary                 # 找不到回 {}
func add(item_id: String, n: int, tables: Dictionary, now_s: float, carry_max: int, make_uid: Callable) -> Dictionary
    # 可疊加（stack>1）的物品一律併入既有堆疊（同 id、未裝備、未滿；會腐壞的也一樣），每次放入記成一批 lot；make_uid.call() 產生新 uid
    # （舊版只在 60 秒內取得的才合併 → 每場戰鬥的兔皮各佔一格，擁有者回報後改掉）
func add_lots(item_id, lots: Array, tables, carry_max, make_uid) -> Dictionary   # 整疊連同每批時間放回（屍體撿回）
func consolidate(tables: Dictionary) -> bool        # 舊存檔被拆開的同物品堆疊併回去（角色進入世界時）
func spoil_left_s(it, now_s, day_s, tables) -> float   # 最早一批還剩幾秒會壞；不會腐壞 −1（sheet 的 spoil_left_days）
    # 失敗：inventory_full（超過 300 件）、overweight（重量超過 carry_max）
    # 回傳 { ok, reason, uid }
func remove(uid: String, n: int) -> Dictionary       # 已裝備的物品先卸下；從最舊的批扣；{ ok, reason("no_item"), removed: n }
func remove_item_id(item_id: String, n: int) -> Dictionary   # 跨堆疊依批的時間由舊到新扣
func equip(uid: String, tables: Dictionary) -> Dictionary    # { ok, reason("no_item"/"not_equippable"), slot, prev_uid }
func unequip(slot: String) -> Dictionary                     # { ok, reason("no_item"), uid }
func equipped_row(slot: String, tables: Dictionary) -> Dictionary   # items 表的列；沒有回 {}
func weapon_options(tables: Dictionary) -> Array    # 背包內所有 slot == "WEAPON" 的實例：[{ uid, item_id, weapon_type, atk, name }]
func spoil(now_s: float, day_s: float, tables: Dictionary) -> Array
    # spoil_days > 0 的堆疊只移除 now_s − lot.born_s ≥ spoil_days × day_s 的批；回傳 [{ id, n }]（每疊一筆）
func take_all() -> Array            # 清空背包與裝備，回傳全部實例（STRICT 死亡用）
func take_equipped() -> Array       # 移除已裝備的實例並回傳（STANDARD 死亡用）
```

#### 3.2.4 `character_factory.gd` — `class_name CharacterFactory`

```gdscript
const ROLL_CAP := 25
const FREE_POINTS := 5
static func roll(rng: RandomNumberGenerator) -> Dictionary   # 每項 = 9 + 4d4 → [13, 25]（4.1）
static func validate_alloc(alloc: Dictionary) -> String      # 鍵只能是 ATTR_IDS、值 int ≥ 0、總和 == 5；錯誤回 "bad_alloc"
static func validate_name(name: String) -> String            # 1–8 字，不含空白、[]、{}、<>、控制字元；錯誤回 "bad_name"
static func create(p: Dictionary, roll: Dictionary, tables: Dictionary, options: Dictionary,
        rng: RandomNumberGenerator, now_s: float) -> Character
    # p = { id, identity, name, gender, birth_month, birth_city, alloc }
    # 位置 = regions[birth_city].birth_room；respawn 留空；初始物品見 4.1
```

#### 3.2.5 `derived_stats.gd` — `class_name DerivedStats`

```gdscript
static func compute(ch: Character, tables: Dictionary, options: Dictionary) -> Dictionary
    # { jing_max, qi_max, shen_max, neili_max, carry_max, carry, weapon_power, weapon_type,
    #   armor_power, effective_inner, art_level_cap, attrs (有效屬性) }
static func art_level_cap(combat_xp: int) -> int     # 4.4
static func effective_inner(book: SkillBook, tables: Dictionary) -> int   # 4.2
```

#### 3.2.6 `learning.gd` — `class_name Learning`

```gdscript
static func wit_cost(wit: int) -> Dictionary   # { "jing": int, "prof": int }（4.5）
static func check_master(ch: Character, npc_id: String, skill_id: String, tables: Dictionary,
        options: Dictionary, rules: Dictionary) -> String   # 3.7 原因碼或 ""
static func learn(ch: Character, npc_id: String, skill_id: String, times: int, tables: Dictionary,
        options: Dictionary, rules: Dictionary) -> Dictionary
static func self_study(ch: Character, skill_id: String, times: int, tables: Dictionary,
        options: Dictionary, rules: Dictionary) -> Dictionary
    # 兩者回傳：{ ok, reason, times_done, prof_gain, lp_cost, jing_cost, neili_cost, shen_cost,
    #             money_cost, level_before, level_after, stopped_reason }
    # times_done ≥ 1 才算 ok；中途資源不足就停，stopped_reason 記錄原因
static func learn_life(ch: Character, npc_id: String, skill_id: String, tables: Dictionary) -> Dictionary
    # 生活技能 0 → 1 級；扣 masters.price；回傳 { ok, reason, money_cost, tool_item }（tool_item 由 WORLD 放進背包）
static func practice_life(ch: Character, skill_id: String, success: bool, tables: Dictionary) -> Dictionary
    # { before, after, prof }（4.12）
static func teach_entries(ch: Character, npc_id: String, tables: Dictionary, options: Dictionary,
        rules: Dictionary) -> Array    # 3.8 teach_list.entries
```

#### 3.2.7 `survival.gd` — `class_name Survival`

```gdscript
static func tick(ch: Character, dt_s: float, in_battle: bool, tables: Dictionary, options: Dictionary) -> Array
    # 飽食飲水下降（戰鬥中也降）、自然回復（戰鬥中不回）；dt_s 為世界時間
    # 回傳通知 key 陣列：可能含 "hungry" "thirsty" "starving" "parched"（只在跨越門檻時各回傳一次）
static func meditate(ch: Character, tables: Dictionary, options: Dictionary, now_s: float) -> Dictionary
    # { ok, reason("no_inner"/"busy"/"nothing_to_do"/"not_enough_jing"), kind: "neili"|"cultivate", gain, neili, qi_gain }
static func exert(ch: Character, stat: String, tables: Dictionary, options: Dictionary) -> Dictionary
    # { ok, reason("not_enough_neili"/"bad_value:stat"), stat, gain }
static func rest_full(ch: Character, tables: Dictionary, options: Dictionary) -> void   # 精氣神內全滿
static func use_item(ch: Character, uid: String, tables: Dictionary, options: Dictionary, now_s: float) -> Dictionary
    # 消耗 1 個；效果見 3.11.10 items.effects
    # { ok, reason("no_item"/"not_usable"), item_id, effects_applied: [{stat, gain}], overdose: bool }
static func eat_meal(ch: Character, food: int, water: int) -> void
static func birthday_check(ch: Character, game_year: int, game_month: int, rng: RandomNumberGenerator) -> String
    # 當 game_month == birth_month 且今年尚未過生日：隨機一項屬性 +1，回傳屬性 id；否則 ""
```

`counters` 內 WP-CHAR 自訂的鍵至少包含（要能存檔）：飽食／飲水／回復的時間餘數、`last_meditate_s`、`med_uses`（最近 60 秒服藥時間戳陣列）、`last_birthday_year`、`last_meal_key`。

#### 3.2.8 `requirements.gd` — `class_name Requirements`

```gdscript
static func check(conds: Array, ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary) -> String
    # 依序判定，第一個不符合的回 "req_<type>"；全部符合回 ""
static func describe(cond: Dictionary, tables: Dictionary) -> String   # 中文說明，例：「佛法 10 級以上」
```

M1 必須實作的 type：`morality_min`、`morality_max`、`sect`、`no_sect`、`not_enemy_of`、`gender`、`attr_min`、`skill_min`、`combat_xp_min`、`pk_max`、`quest_flag`、`quest_done`（新增）、`killing_intent_max`、`era_enabled`、`sect_enabled`、`rule`。`unmarried` 一律視為符合（M5 才有婚姻）。各 type 的欄位見 3.11.1。

#### 3.2.9 `death_penalty.gd` — `class_name DeathPenalty`

```gdscript
const NEWBIE_XP := 500
static func apply(ch: Character, rules: Dictionary, tables: Dictionary) -> Dictionary
    # 依 rules.death_rule（4.13）修改角色；不處理重生位置與屍體物件（WORLD 負責）
    # 回傳 { rule: String, safe_newbie: bool,
    #        skill_losses: [{ skill, name, from, to }],
    #        dropped: [物品實例...],        # 要放進屍體的實例（可能為空）
    #        money_lost: int }
static func respawn_vitals(ch: Character, tables: Dictionary, options: Dictionary) -> void
    # 精、氣、神 = 上限的 50%（無條件捨去，至少 1）；內力 = 0
```

### 3.3 戰鬥者規格（CHAR 產生 → BATTLE 使用）

`Character.to_combatant()` 與 `Encounter.monster_spec()` 都輸出同一種字典。BATTLE 只讀這份字典（加上 `tables`），不讀 `Character`。

```gdscript
{
  "kind": "PLAYER",                 # "PLAYER" / "MONSTER"
  "ref": "ch_1a2b3c4d",             # 角色 id 或怪物 id
  "name": "測試俠客",
  "side": 0,                        # 0 = 玩家方，1 = 敵方
  "peer": 1,                        # 玩家的 peer id；怪物為 0
  "ai": "",                         # 玩家 ""；怪物 "melee_basic" / "coward"
  "attrs": { "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20 },   # 有效屬性
  "qi": 180, "qi_max": 180, "neili": 0, "neili_max": 0,
  "jing": 92, "jing_max": 92, "shen": 88, "shen_max": 88,
  "skills": { "basic_fist": 10, "sl_changquan": 10, "foxa": 10 },   # skill_id -> level（只列 ≥1 的）
  "arts": ["sl_changquan"],        # 戰鬥中可用「武」的武功（類別 FIST..SPEAR、level ≥1）
  "weapon": { "uid": "it_0001", "item_id": "w_mudao", "weapon_type": "BLADE", "atk": 4, "name": "木刀" },
                                    # 空手：{ "uid": "", "item_id": "", "weapon_type": "FIST", "atk": 0, "name": "" }
  "weapon_options": [ { "uid": "it_0001", "item_id": "w_mudao", "weapon_type": "BLADE", "atk": 4, "name": "木刀" } ],
  "armor_power": 2,
  "effective_inner": 0,             # 4.2
  "lightness": 0,                   # 最高 LIGHTNESS 武功等級
  "sect_skill": { "id": "foxa", "effect": "DEFENSE", "level": 10 },   # 沒有門派技能：{}
  "killing_intent": 0,
  "carry_ratio": 0.12,              # 負重 / 負重上限
  "monster_row": "",                # 怪物 id（獎勵計算用）；玩家 ""
  "combat_xp": 250                  # 【整合補】玩家實戰（4.8 獎勵比例用）；怪物 0
}
```

### 3.4 WP-BATTLE：`core/battle/`

#### 3.4.1 `battle.gd` — `class_name Battle`

```gdscript
enum State { SETUP, RUNNING, AWAIT_COMMAND, RESOLVING, ENDED }
enum Result { NONE, VICTORY, DEFEAT, ALL_FLED, ABORTED }
const GAUGE_FULL := 100.0
const TICK := 0.1
const W := 12
const H := 8
const MAX_TICKS := 18000            # 30 分鐘遊戲時間仍未分勝負 → ABORTED

var id: int
var state: State
var result: Result
var tick_no: int
var units: Array                    # Array[BattleUnit]
var grid: BattleGrid
var rng: RandomNumberGenerator

func _init(p_id: int, p_seed: int, p_opts: Dictionary) -> void
    # p_opts：wait_mode(bool)、wait_mode_timeout_s、wait_mode_timeout_min_s、wait_mode_round_budget_s（server_options 的值）、
    #         escape_tiles(int，預設 2)
func add_unit(spec: Dictionary) -> int          # 回傳 uid（從 1 開始遞增）；只能在 start() 前呼叫
func start(tables: Dictionary) -> Array         # 佈陣、放逃跑格、算速度 → 回傳事件（含第一個 battle_gauges）
func step(dt: float, tables: Dictionary) -> Array   # 主機每 0.1 秒（乘 time_scale 後的世界時間）呼叫一次
func submit(peer: int, cmd: Dictionary, tables: Dictionary) -> String
    # 以 peer 找單位；回傳 "" 或 3.7 的戰鬥原因碼；合法就排入，於下一次 step 結算
func uid_for_peer(peer: int) -> int             # 沒有回 0
func snapshot(tables: Dictionary) -> Dictionary # 3.9.3
func is_over() -> bool                          # state == ENDED
func outcome() -> Dictionary                    # 3.4.6；只在 is_over() 後呼叫
func abort() -> Array                           # 主機關服時：result = ABORTED，回傳 battle_end 事件
```

- 狀態機照 TECH_ARCH 10.2；等待模式節奏照 TECH_ARCH 10.7 的 6 條規則全部實作（`afk` 在 M1 也要做，因為是純邏輯）。
- 同一 tick 多個單位滿條：依溢出量 → 機敏 → uid 排序（TECH_ARCH 13.4）。
- 每場戰鬥只用自己的 `rng`。**同一個種子 + 同樣的單位規格 + 同樣的指令序列（含送達的 tick）必須產生完全相同的事件陣列**。
- 產生的每個事件都是 `{ "ch": "BATTLE", "key": String, "p": Dictionary, "bid": int }`；UI-only 事件另加 `"ui": true`（3.8）。WORLD 轉送時加上 `seq` 與 `t`。

#### 3.4.2 其他類別

| 檔案 | class_name | 公開介面 |
|---|---|---|
| `battle_unit.gd` | `BattleUnit` | `var uid, spec(Dictionary), side, peer, pos: Vector2i, qi, neili, jing, shen, gauge, rate, state(String: CHARGING/READY/ACTING/DEAD/FLED), defending(bool), statuses(Dictionary id->remaining_actions), queued_cmd(Dictionary), kills(Array), last_hitter(int), afk(bool), timeouts(int)`；`func is_active() -> bool`（非 DEAD/FLED）、`func is_ai() -> bool`、`func can_charge() -> bool` |
| `battle_grid.gd` | `BattleGrid` | `func place_units(units, rng)`、`func place_escape_tiles(n, units, rng)`、`func is_free(p: Vector2i) -> bool`、`func reachable(from: Vector2i, steps: int) -> Array[Vector2i]`（BFS，4 方向，不能穿越單位）、`func is_escape(p) -> bool`、`var escape: Array[Vector2i]` |
| `battle_formulas.gd` | `BattleFormulas` | `static func atb_gain(u: BattleUnit, tables) -> float`、`static func move_range(u) -> int`、`static func attack_power(u, art_row, move_row, tenths, tables) -> float`、`static func defense_power(u, attacker_category, tables) -> float`、`static func hit_chance(att, def, art_level) -> float`、`static func crit_chance(u) -> float`、`static func crit_mult(u) -> float`、`static func float_range(u) -> Vector2`、`static func power_factor(tenths, base_skill_level) -> float`、`static func inner_cost(move_row, tenths) -> int`、`static func proc_chance(level) -> float`、`static func counter_chance(u) -> float`（全部照第 4 章） |
| `battle_rules.gd` | `BattleRules` | `static func validate_cmd(b: Battle, u: BattleUnit, cmd: Dictionary, tables) -> String`、`static func execute(b, u, cmd, tables, rng) -> Array`（回傳事件）、`static func await_timeout(b, pending: Array, opts) -> float`（10.7） |
| `battle_ai.gd` | `BattleAI` | `static func choose(b: Battle, u: BattleUnit, tables, rng) -> Dictionary`（回傳一個 cmd 字典，4.9） |
| `battle_rewards.gd` | `BattleRewards` | `static func compute(b: Battle, tables: Dictionary, rng: RandomNumberGenerator) -> Dictionary`（3.4.7） |
| `encounter.gd` | `Encounter` | `static func roll(room: Dictionary, rng: RandomNumberGenerator, rate_mult: float = 1.0) -> Array`（回傳怪物 id 陣列，空 = 沒遇敵；4.14）、`static func monster_spec(monster_id: String, tables: Dictionary) -> Dictionary`（3.3） |

#### 3.4.3 戰鬥指令（`battle_cmd` 的 `cmd` 字典，M1 子集）

| cmd | 欄位 | 驗證（依序；失敗回原因碼） | 效果 |
|---|---|---|---|
| `MOVE` | `target: [x,y]` | 單位 READY（`not_ready`）；格子在 `reachable(pos, move_range)` 內（`out_of_range`／`occupied`） | 移動；行動後時間棒設為 50（半個行動） |
| `ATTACK` | `target: [x,y]` | 目標格有敵方存活單位（`no_target`）；曼哈頓距離 ≤ 1（`out_of_range`） | 以手上兵器普通攻擊（招式威力 0、武功等級 = 對應基本武學、出力 1.0） |
| `ART` | `art, move, power_tenths(1–10), target: [x,y]` | 會此武功且在 `arts` 內（`art_unknown`）；招式屬於此武功且 `unlock_level ≤ 等級`（`move_locked`）；兵器類武功需要同類兵器（`need_weapon`）；`aoe == "SINGLE"`（`aoe_not_supported`）；目標與距離同 ATTACK，距離上限 = 招式 `range`；內力 ≥ 內力消耗（`not_enough_neili`）；精 ≥ `cost_jing`（`not_enough_jing`） | 出招（4.7） |
| `DEFEND` | — | READY | 直到自己下次行動前，防禦力 × (1.5 + 有效內功/400) |
| `REST` | — | 沒有內傷（`status_blocked`） | 回復 氣 5%、內力 10%（上限內） |
| `EQUIP` | `item_uid` | `""`（空手）或 `weapon_options` 內的 uid（`no_item`） | 換武器；消耗行動 |
| `FLEE` | — | 單位站在逃跑格上（`not_on_escape`） | 單位狀態 FLED，離開戰場 |

共通錯誤：`not_ready`（單位不是 READY 或不在等待清單）、`bad_cmd`（不認得的 cmd 或缺欄位）、`battle_over`。

#### 3.4.4 佈陣

- 玩家方在 x = 1，敵方在 x = 10；同一方依序放在 y = 3, 4, 2, 5, 1, 6（遇到占用往下一個）。
- 逃跑格數量 = `opts.escape_tiles`（取地圖的 `escape_tiles_hint`，預設 2）；從所有「空格、且與每個玩家方起始格的曼哈頓距離 ≥ 3」的格子中用 `rng` 均勻抽取。

#### 3.4.5 等待模式摘要

- 開啟（預設）：任一**玩家**單位 READY → 整場進入 AWAIT_COMMAND，時間棒全部暫停，送 `battle_await`（UI-only）與 `battle_gauges`；所有在等的玩家都下令或逾時（逾時 → `battle_timeout` 事件 + 自動 DEFEND）後才結算。
- 關閉：READY 的玩家停在滿條，其他單位照常累積；玩家隨時下令，下一個 step 結算。
- AI 單位 READY 時立刻由 `BattleAI.choose` 決定指令。

#### 3.4.6 `Battle.outcome()` 形狀

```gdscript
{
  "bid": 3,
  "result": "VICTORY",               # "VICTORY" / "DEFEAT" / "ALL_FLED" / "ABORTED"
  "ticks": 412,
  "units": {
    1: { "uid": 1, "kind": "PLAYER", "ref": "ch_1a2b3c4d", "side": 0, "peer": 1,
         "alive": true, "died": false, "fled": false,
         "qi": 150, "neili": 0, "jing": 92, "shen": 88,
         "weapon_uid": "it_0001",      # 戰鬥結束時拿在手上的武器（"" = 空手）
         "kills": ["m_rabbit"] },      # 由此單位造成最後一擊的怪物 id
    2: { "uid": 2, "kind": "MONSTER", "ref": "m_rabbit", "side": 1, "peer": 0,
         "alive": false, "died": true, "fled": false, "qi": 1, "neili": 0, "jing": 0, "shen": 0,
         "weapon_uid": "", "kills": [], "killed_by": 1 }
  }
}
```

- 死亡判定：氣降到 **1**（或以下，夾在 1）即死亡（GDD 2.3【已證實】）。`died == true` 的玩家單位 `qi == 1`。
- VICTORY：敵方全部 DEAD 或 FLED，且玩家方至少一人存活未逃。DEFEAT：玩家方沒有存活且未逃的單位，且至少一名玩家死亡。ALL_FLED：玩家方全部逃走（或部分逃走、其餘死亡時依「是否有人死亡」判 DEFEAT）。

#### 3.4.7 `BattleRewards.compute()` 形狀

```gdscript
{   # key = 玩家單位 uid；只有「存活且未逃走」的玩家單位有實戰、學點
  1: { "combat_xp": 5, "learn_points": 2, "money": 1,
       "items": [ { "id": "r_rabbitskin", "n": 1 } ],
       "morality": 0, "killing_intent": 0,
       "kills": ["m_rabbit"] }          # 此玩家最後一擊的怪物（任務 KILL 計數用）
}
```

計算規則見 4.8。DEFEAT／ALL_FLED／ABORTED 時回傳空字典。死亡或逃走的玩家單位不出現在結果中；WORLD 只用本結果的 `kills` 推進 KILL 任務，所以死亡者的擊殺不算任務進度【設計提案】。

### 3.5 WP-WORLD：主機端

#### 3.5.1 `autoload/world_server.gd` 的修改（保持 M0 行為與測試）

```gdscript
var game: GameHost = null          # start() 成功後建立；stop() 時 game.shutdown() 後設為 null
var time_scale := 1.0              # 由 CLI --time-scale 讀入，夾在 [0.1, 100]
func register_intent(kind: String, handler: Callable) -> void   # handler(s: Session, args: Dictionary) -> Dictionary{ok, reason}
func queue_event(peer_id: int, ch: String, key: String, p: Dictionary, ui := false) -> void
func broadcast_event(ch: String, key: String, p: Dictionary, ui := false) -> void
func queue_room_event(room_id: String, ch: String, key: String, p: Dictionary, except_peer := 0) -> void
```

- `_process(delta)`：`scaled = delta * time_scale`；`world_time_s += scaled`；累加器每滿 0.1 秒呼叫一次 `game.tick(0.1)`（一幀最多 50 次，避免卡死）；其餘照 M0。
- `_add_session` 的 welcome `your_characters` 改為 `game.char_store.summaries(identity)`。
- `on_peer_disconnected`：在移除 session 前呼叫 `game.on_session_removed(s)`（戰鬥不中止：`BattleSystem.detach_for` 把他的單位改為自動「防」，戰鬥中已沒有在線玩家就當場快轉到分出勝負並結算，死亡照罰；然後存角色、離開房間。ABORTED 只留給主機關閉與 MAX_TICKS）。
- `_handlers` 仍保留 `ping`、`chat`；其餘 intent 由 `GameHost` 在建立時呼叫 `register_intent()` 註冊。
- `ui == true` 的事件在事件字典頂層加 `"ui": true`。

#### 3.5.2 `server/` 檔案清單

| 檔案 | class_name | 職責 |
|---|---|---|
| `server/session.gd`（修改） | `Session` | 新增 `var character: Character`（null = 未選角）、`var pending_roll: Dictionary`、`var battle_id := 0`、`var sheet_dirty := false`、`var view_dirty := false` |
| `server/game_host.gd` | `GameHost` | 持有下列所有系統；`func _init(ws: Node)`；`func tick(dt: float)`；`func on_session_removed(s)`；`func shutdown()`；共用檢查 `require_char(s) -> String`、`require_idle(s) -> String`（不在戰鬥中）、`npc_here(s, npc_id) -> String`；`func push_sheet(s)`、`func push_view(s)` |
| `server/world_index.gd` | `WorldIndex` | 由 `GameData.tables.maps` 建 `room_id -> room`、`room_id -> region_id`、`npc_id -> room_id` 索引 |
| `server/world_clock.gd` | `WorldClock` | 靜態：`clock(world_s, day_s) -> { shichen_idx, shichen_name, ke, night, day, month, year, text }`（4.15） |
| `server/character_store.gd` | `CharacterStore` | 角色檔的載入、存檔、列表、刪除；名稱唯一索引（world.json `char_names`） |
| `server/region_system.gd` | `RegionSystem` | 房間占用、`move`、房間視圖（3.9.2）、進出房間事件、踩地雷 |
| `server/npc_system.gd` | `NpcSystem` | 對話選單、商店、教學、客棧、記錄點、驛站、拜入、齋食、定點戰鬥的入口 |
| `server/battle_system.gd` | `BattleSystem` | 開戰、每 tick 推進、轉送戰鬥事件、結算（獎勵、死亡、屍體、重生） |
| `server/quest_system.gd` | `QuestSystem` | 接受、進度（KILL、REACH 自動推進）、交付、放棄、獎勵 |
| `server/life_system.gd` | `LifeSystem` | 生活技能動作 `work` |
| `server/corpse_system.gd` | `CorpseSystem` | 建立屍體、拾回、到期清除（world.json `corpses`） |
| `server/intents/intents_char.gd` | `IntentsChar` | `char_list` `char_roll` `char_create` `char_select` `char_delete` |
| `server/intents/intents_move.gd` | `IntentsMove` | `look` `move` `travel` |
| `server/intents/intents_npc.gd` | `IntentsNpc` | `talk` `shop_list` `buy` `sell` `learn_list` `learn` `join_sect` `inn_rest` `set_respawn` `meal` `fight` |
| `server/intents/intents_self.gd` | `IntentsSelf` | `self_study` `meditate` `exert` `work` |
| `server/intents/intents_item.gd` | `IntentsItem` | `use_item` `equip` `unequip` `drop_item` `loot_corpse` |
| `server/intents/intents_quest.gd` | `IntentsQuest` | `quest_accept` `quest_turn_in` `quest_abandon` |
| `server/intents/intents_battle.gd` | `IntentsBattle` | `battle_cmd` |

每個 `intents_*.gd` 提供 `static func register(host: GameHost) -> void`。

#### 3.5.3 處理器的固定步驟（每個 intent）

1. （M0 既有）session、序號、速率、`Protocol.validate_args`。
2. `require_char`（除了 `ping` `chat` `char_*`）→ `no_character`。
3. 除 `battle_cmd` `look` `ping` `chat` `char_list` 外，戰鬥中一律 `in_battle`。
4. NPC 類：`npc_here` → `not_here`；服務不在該 NPC 的 `services` → `no_service`；夜間且 `night_closed` → `closed_night`。
5. 呼叫 `core/character` 或 `core/battle` 驗證並套用。
6. 產生事件；標記 `sheet_dirty`／`view_dirty`；角色檔標 dirty。
7. 回 `{ok, reason}`。成功或失敗都會回 `intent_result`（M0 已處理）。
   **冷卻中的 `busy`（附加，2026-10）**：主機回 `{ ok: false, reason: "busy", cooldown: "meditate"|"life", left_s: int }`（`left_s` = 剩餘真實秒數，無條件進位、至少 1），
   回結果之前先送一次最新角色表（含 `cooldowns`）。`s2c_intent_result(seq, ok, reason, extra = {})` 多一個**可省略**的第 4 個參數，
   `busy` 時 `extra = { "left_s": n }`，其他結果不送；客戶端在發 `intent_result` 訊號前把它存進 `ClientState.last_result_extra`，
   UI 用它填 `err_busy` 的 `{n}`（「你正忙著，還要 N 秒。」）。訊號 `intent_result(seq, ok, reason)` 不變。
   **相容性**：Godot RPC 的參數數目必須一致，舊版客戶端（3 個參數的 `s2c_intent_result`）收到 4 個參數的呼叫會失敗、那個結果直接遺失，
   所以這次把 `Protocol.VERSION` 從 1 升到 2：新舊版在握手（`c2s_hello.protocol`，不同就 `rejected`）與大廳篩選（`proto`）就互相擋掉，不會連上後才掉結果。
   主機與客戶端必須同一版一起發佈。（「1 秒」的退路只在新客戶端的 `extra` 沒有 `left_s` 時用。）
   **客戶端倒數**：`ClientState._apply_sheet` 收到角色表時蓋上本機收件時刻 `sheet._rx_ms`（`Time.get_ticks_msec()`，只在客戶端，不回送），
   `CooldownTracker` 以「收件時刻 + `cooldowns` 剩餘秒數（四捨五入到毫秒）」當到期時刻：同一份角色表重套不會重設倒數，兩次動作剩餘秒數相同也會各自開始倒數；比上一份舊的角色表不採用。

`sheet_dirty` 的 session 每 tick 檢查，最多每 0.25 秒送一次 `s2c_sheet`；`view_dirty` 送 `s2c_region_view`。**每個成功的 intent 處理完、以及戰鬥結束後，必須讓下一個 flush 前送出最新角色表**（離線測試會檢查）。

#### 3.5.4 `autoload/client_state.gd`（UI 契約）

新增（WP-WORLD 實作，WP-UI 使用）：

```gdscript
signal char_list_changed(list: Array)        # 3.9.5
signal region_changed(view: Dictionary)      # 3.9.2
signal battle_opened(state: Dictionary)      # 3.9.3
signal battle_closed(result: Dictionary)     # 3.9.4
# 既有：events_received(batch)、intent_result(seq, ok, reason)、welcomed(info)、rejected、kicked、roster_changed、sheet_changed(sheet)

var char_list: Array = []
var region_view: Dictionary = {}
var battle_state: Dictionary = {}           # battle_opened 時的快照；battle_closed 後清空
var last_battle_result: Dictionary = {}
var last_result_extra: Dictionary = {}      # 最近一個 intent_result 的附加欄位（busy → { left_s }）；3.5.3 第 7 點

@rpc("authority", "call_remote", "reliable") func s2c_char_list(list: Array)
@rpc("authority", "call_remote", "reliable") func s2c_region_view(view: Dictionary)
@rpc("authority", "call_remote", "reliable") func s2c_battle_open(state: Dictionary)
@rpc("authority", "call_remote", "reliable") func s2c_battle_close(result: Dictionary)
func deliver_sheet(peer_id: int, sheet: Dictionary)          # 本地短路或 s2c_sheet
func deliver_char_list(peer_id: int, list: Array)
func deliver_region_view(peer_id: int, view: Dictionary)
func deliver_battle_open(peer_id: int, state: Dictionary)
func deliver_battle_close(peer_id: int, result: Dictionary)
```

- `welcome.your_characters` 收到時也要更新 `char_list` 並發 `char_list_changed`。
- `reset()` 清空上述新欄位。
- 戰鬥事件仍走 `s2c_events`（`ch == "BATTLE"`）；ClientState **不**解讀戰鬥事件，UI 自己維護戰鬥畫面模型。

#### 3.5.5 `core/protocol.gd`

- `INTENT_SCHEMA` 加入 3.6 的全部 intent；常數名稱為 `I_<大寫 kind>`（例：`I_CHAR_CREATE := "char_create"`、`I_BATTLE_CMD := "battle_cmd"`）。
- 事件 key 常數 `E_<大寫 key>`（只需定義 3.8 表中的固定 key；動態 key 如招式 flavor、`talk_*`、`err_*` 不需常數）。
- 頻道常數新增 `CH_SCENE`（已有）、`CH_BATTLE`（已有）。
- `validate_args` 擴充：支援 `TYPE_ARRAY`、`TYPE_DICTIONARY`；所有 String 參數長度 ≤ 64（`bad_value:<arg>`）；3.6「範圍」欄的檢查失敗回 `bad_value:<arg>`。
- 保持 `test_core_util.gd` 綠燈。

#### 3.5.6 `autoload/save_manager.gd` 新增

```gdscript
const CHARACTER_SCHEMA_VERSION := 1
func characters_dir(world_id: String, identity: String) -> String
func save_character(world_id: String, identity: String, data: Dictionary) -> Error   # 原子寫入 character_path(...)
func load_character(world_id: String, identity: String, char_id: String) -> Dictionary # { ok, data, source }（備份退回）
func list_character_ids(world_id: String, identity: String) -> Array                 # 依檔名，不含 deleted/
func delete_character(world_id: String, identity: String, char_id: String) -> Error
    # 不真的刪：把本體與 .bak* 移到 characters/<identity>/deleted/<char_id>_<unix>.json
```

### 3.6 Intent 完整清單

型別：S = String、I = int、A = Array、D = Dictionary。`?` = 選填（預設值在括號內）。「需要角色」= 沒選角時回 `no_character`；「閒置」= 戰鬥中回 `in_battle`。

| kind | args | 需要角色／閒置 | 範圍驗證（Protocol） | 遊戲驗證（依序）與效果 | 產生的事件／推送 |
|---|---|---|---|---|---|
| `ping` | nonce:I? | — | — | M0 | `pong` |
| `chat` | text:S, ch:S? | — | M0 | M0（M1 不扣飲水） | `chat` |
| `char_list` | — | 否 | — | — | `s2c_char_list` |
| `char_roll` | — | 否／閒置 | — | 擲骰存進 `session.pending_roll` | `char_rolled` |
| `char_create` | name:S, gender:S, birth_month:I, birth_city:S, alloc:D | 否 | gender ∈ {M,F}；birth_month 1–12（`Protocol` 是 core，不能讀 `GameData`，所以 birth_city 在處理器檢查） | birth_city 不是 `regions` 中 `birth_allowed == true` 的城市 → `bad_value:birth_city`（最先檢查）；`no_roll`；`bad_name`；`name_taken`；`too_many_chars`（已有 3 個）；`bad_alloc`；建立 → 存檔 → 自動選角進入世界；清除 pending_roll | `char_created`、`char_entered`、sheet、view、char_list |
| `char_select` | char_id:S | 否／閒置 | — | `no_such_char`；已有角色時先存檔並離開房間 | `char_entered`、sheet、view |
| `char_delete` | char_id:S, confirm_name:S | 否 | — | `no_such_char`；`confirm_mismatch`（名字不同）；`char_active`（是目前選中的角色） | `char_deleted`、char_list |
| `look` | — | 是 | — | — | sheet、view |
| `move` | dir:S | 是／閒置 | dir ∈ 方向集合 | `no_exit`；`room_locked`（目的房間的 `requires` 不符）；`overweight`（負重超過上限）；移動 → 進入野外房間時踩地雷（4.14） | `room_leave`、`room_enter`、view、（遇敵時 `encounter` + `s2c_battle_open`）；REACH 任務推進 |
| `travel` | npc:S, dest:S | 是／閒置 | — | 伺服器選項 `stagecoach_enabled` 不是 true → `stagecoach_disabled`（預設，WORLD_2001 D5：驛站馬車【設計提案・非原作】）；NPC 檢查（服務 TRAVEL）；`no_route`（dest 不在 `travel` 清單或房間不在生效視圖）；`not_enough_money`；扣錢、移到 dest 房間 | `travel`、view、sheet |
| `talk` | npc:S | 是／閒置 | — | `not_here` | `<npc.talk>`、`npc_menu`（UI-only） |
| `shop_list` | npc:S | 是／閒置 | — | NPC 檢查（SHOP、夜間） | `shop_list`（UI-only） |
| `buy` | npc:S, item:S, n:I?(1) | 是／閒置 | n 1–99 | NPC 檢查；`no_item`（不在商品清單）；`not_enough_money`；`inventory_full`／`overweight` | `buy`、sheet |
| `sell` | npc:S, item_uid:S, n:I?(1) | 是／閒置 | n 1–99 | NPC 檢查（SHOP）；`no_item`；`not_sellable`（`no_sell` 或任務物品）；數量不足 `no_item`；已裝備的先卸下 | `sell`、sheet |
| `learn_list` | npc:S | 是／閒置 | — | NPC 檢查（TEACH） | `teach_list`（UI-only） |
| `learn` | npc:S, skill:S, times:I?(1) | 是／閒置 | times 1–10 | NPC 檢查（TEACH）；LIFE → `Learning.learn_life`（`already_known`）；其他 → `Learning.learn`（原因碼見 4.5） | `learn` 或 `life_learn`、`skill_up`（升級時）、`item_gain`（工具）、sheet |
| `self_study` | skill:S, times:I?(1) | 是／閒置 | times 1–10 | `Learning.self_study` | `self_study`、`skill_up`、sheet |
| `join_sect` | npc:S | 是／閒置 | — | NPC 檢查（JOIN）；`already_in_sect`；性別不在 `sects.gender` → `req_gender`；`join_requires` → `req_*` | `sect_join`（廣播）、sheet |
| `inn_rest` | npc:S | 是／閒置 | — | NPC 檢查（INN）；`not_enough_money` | `inn_rest`、sheet |
| `set_respawn` | npc:S | 是／閒置 | — | NPC 檢查（RESPAWN）；記錄點 = NPC 所在房間 | `respawn_set`、sheet |
| `meal` | npc:S | 是／閒置 | — | NPC 檢查（MEAL）；目前時辰不在 `meal.hours` → `not_meal_time`；同一時辰已吃過 → `already_ate` | `meal`、sheet |
| `fight` | npc:S | 是／閒置 | — | NPC 檢查（FIGHT）；`fight.requires` → `req_*`；開戰（敵方 = `fight.monster`） | `s2c_battle_open` |
| `use_item` | item_uid:S | 是／閒置 | — | `Survival.use_item`；`c_smoke` 設定 `buffs.smoke_until_s` | `item_use`、（`overdose`）、（`meat_vow_broken`：少林弟子吃葷，見 4.11）、sheet |
| `equip` | item_uid:S | 是／閒置 | — | `Inventory.equip` | `equip`、sheet |
| `unequip` | slot:S | 是／閒置 | slot ∈ {WEAPON, ARMOR} | `Inventory.unequip` | `unequip`、sheet |
| `drop_item` | item_uid:S, n:I?(1) | 是／閒置 | n 1–999 | `no_item`；任務物品 `not_droppable`；物品直接消失（M1 沒有地上物品） | `item_drop`、sheet |
| `meditate` | — | 是／閒置 | — | `Survival.meditate` | `meditate` 或 `cultivate`、sheet |
| `exert` | stat:S | 是／閒置 | stat ∈ {jing, qi, shen} | `Survival.exert` | `exert`、sheet |
| `work` | skill:S, recipe:S?("") | 是／閒置 | skill ∈ 4 個 life id | 房間 `features` 沒有該技能的 feature → `no_feature`；`not_known`；需要工具時背包沒有 → `no_tool`；冷卻中 → `busy`；精不足 → `not_enough_jing`；廚師：`no_recipe`／`recipe_level`／`no_ingredients`；成功或失敗都給熟練度 | `work_ok_<skill>` 或 `work_fail_<skill>`、`skill_up`、`item_gain`、sheet |
| `quest_accept` | npc:S, quest:S | 是／閒置 | — | `not_here`；`quest_unknown`（不是此 NPC 的任務）；`quest_active`；`quest_done`（不可重複且已完成）；`quests.requires` → `req_*`；`quest_full`（進行中 ≥ 20）；接受時給予 `give_items` | `quest_accept`、`item_gain`、sheet |
| `quest_turn_in` | npc:S, quest:S | 是／閒置 | — | `quest_not_active`；目前步驟不是對此 NPC 的 TALK／DELIVER，或 DELIVER 物品不足 → `quest_incomplete`；完成該步驟；最後一步完成時發獎勵 | `quest_progress` 或 `quest_complete` + `reward` + `item_gain`、`npc_menu`（refresh）、sheet |
| `quest_abandon` | quest:S | 是／閒置 | — | `quest_not_active`；收回 `give_items` 中仍在身上的物品 | `quest_abandon`、sheet |
| `loot_corpse` | corpse_id:S | 是／閒置 | — | `corpse_not_found`（不存在或不在此房間）；`corpse_not_yours`（M1 只有本人可撿）；物品逐件放回背包，放不下的留在屍體上；屍體空了就移除 | `corpse_looted`、sheet、view |
| `battle_cmd` | battle_id:I, cmd:S, target:A?, art:S?, move:S?, power_tenths:I?, item_uid:S? | 是 | cmd ∈ {MOVE, ATTACK, ART, DEFEND, REST, EQUIP, FLEE}；target 為兩個 int 且 0≤x<12、0≤y<8；power_tenths 1–10 | `battle_not_found`（battle_id 不是此 session 的戰鬥）；`Battle.submit` 的原因碼 | 戰鬥事件（下一個 tick） |

### 3.7 原因碼完整清單（`intent_result.reason`）

UI 顯示時查 `text_templates` 的 `err_<reason>`（`self` 變體）。`err_busy` 帶 `{n}`（還要幾秒，來自 `last_result_extra.left_s`）。帶冒號的原因（`bad_type:x`、`missing_arg:x`、`bad_value:x`）一律查 `err_bad_args`；`req_<type>` 查 `err_req_<type>`；`drop:` 開頭的不顯示。查不到時顯示「【系統】無法執行（{reason}）」。

| 分類 | 原因碼 |
|---|---|
| 協定（M0） | `unknown_intent` `unexpected_arg` `bad_type:<arg>` `missing_arg:<arg>` `empty_text` `text_too_long` `bad_channel` `bad_value:<arg>` |
| 角色 | `no_character` `no_roll` `bad_name` `name_taken` `too_many_chars` `bad_alloc` `no_such_char` `confirm_mismatch` `char_active` |
| 狀態 | `in_battle` `busy` `overweight` `inventory_full` `money_cap` |
| 移動 | `no_exit` `room_locked` `no_route` `stagecoach_disabled` |
| NPC | `not_here` `no_service` `closed_night` `not_enough_money` `not_meal_time` `already_ate` |
| 物品 | `no_item` `not_usable` `not_equippable` `not_sellable` `not_droppable` |
| 學武 | `not_taught` `cap_master` `cap_sect_skill` `cap_xp` `cap_arts16` `need_self_study` `not_known` `already_known` `not_enough_lp` `not_enough_jing` `not_enough_neili` `not_enough_shen` |
| 門派 | `already_in_sect` |
| 需求 | `req_morality_min` `req_morality_max` `req_sect` `req_no_sect` `req_not_enemy_of` `req_gender` `req_attr_min` `req_skill_min` `req_combat_xp_min` `req_pk_max` `req_quest_flag` `req_quest_done` `req_killing_intent_max` `req_era_enabled` `req_sect_enabled` `req_rule` |
| 回復 | `no_inner` `nothing_to_do` |
| 生活技能 | `no_feature` `no_tool` `no_recipe` `recipe_level` `no_ingredients` |
| 任務 | `quest_unknown` `quest_active` `quest_done` `quest_not_active` `quest_incomplete` `quest_full` |
| 屍體 | `corpse_not_found` `corpse_not_yours` |
| 戰鬥 | `battle_not_found` `battle_over` `not_ready` `bad_cmd` `out_of_range` `occupied` `no_target` `art_unknown` `move_locked` `need_weapon` `aoe_not_supported` `not_on_escape` `status_blocked` `battle_not_enough_jing`（`battle_cmd` 出招精不足；`core/battle` 仍回 `not_enough_jing`，`BattleSystem.submit` 改碼，提示「精不足，使不出這一招。」而不是叫人去客棧） |

### 3.8 事件完整清單

事件格式（TECH_ARCH 11.1）：`{ "seq": int, "t": float, "ch": String, "key": String, "p": Dictionary [, "bid": int] [, "ui": true] }`。

- **模板**：除了標「UI-only」的事件，每個 key 在 `text_templates.json` 都有同名的列；列中提供表內「變體」欄列出的 `self`／`target`／`other`。TextRenderer 選變體的規則（M0 既有）：`p.from_peer`／`p.peer`／`p.atk_peer` 等於自己 → `self`；`p.def_peer` 等於自己 → `target`；否則 `other`。怪物的 peer 一律 0。
- **UI-only**：事件頂層帶 `"ui": true`，沒有模板，TextRenderer 一律不顯示。
- 名稱類欄位都是已經查好的中文名稱字串（`name`、`npc_name`、`item_name`、`skill_name`、`room_name`…），數值類是 int。

#### 3.8.1 系統、場景、角色

| key | ch | 收件 | payload | 變體 | 範例文字（DATA 可潤飾，佔位符不可改） |
|---|---|---|---|---|---|
| `char_rolled` | SYSTEM | 本人 | str, guts, wit, luck, cal, agi, con, total | self | 擲骰結果：臂力 {str}、膽識 {guts}、悟性 {wit}、福緣 {luck}、定力 {cal}、機敏 {agi}、根骨 {con}（合計 {total}）。 |
| `char_created` | SYSTEM | 本人 | name, char_id | self | 你以「{name}」之名踏入江湖。 |
| `char_deleted` | SYSTEM | 本人 | name | self | 角色「{name}」已刪除。 |
| `char_entered` | SCENE | 本人＋同房 | name, peer, room_name | self, other | 你來到了{room_name}。／{name}出現在這裡。 |
| `char_left` | SCENE | 同房 | name, peer | other | {name}離開了江湖。 |
| `room_enter` | SCENE | 同房其他人 | name, peer, from_label | other | {name}從{from_label}邊走了過來。 |
| `room_leave` | SCENE | 同房其他人 | name, peer, dir_label | other | {name}往{dir_label}邊離開了。 |
| `travel` | SYSTEM | 本人 | from_name, to_name, cost | self | 你付了 {cost} 兩，搭上驛站的馬車，一路顛簸來到{to_name}。 |
| `relocated` | SYSTEM | 本人 | room_name | self | 你原本所在的地方已經不在這個江湖裡了。回過神來，你人在{room_name}。（選角進入世界時位置已不在生效的房間裡，WORLD_2001 §8.1） |
| `respawn_reset` | SYSTEM | 本人 | room_name | self | 你的記錄點已經不在這個江湖裡了，改回{room_name}。（記錄點房間被 era 擋掉或刪除，§8.2） |
| `night_falls` | SYSTEM | 全部在線 | clock | other | 【{clock}】天色漸暗，城中商家紛紛打烊。 |
| `day_breaks` | SYSTEM | 全部在線 | clock | other | 【{clock}】天亮了，街上又熱鬧起來。 |
| `hungry` | SYSTEM | 本人 | peer | self | 你的肚子咕嚕咕嚕叫了起來。 |
| `thirsty` | SYSTEM | 本人 | peer | self | 你覺得口乾舌燥。 |
| `starving` | SYSTEM | 本人 | peer | self | 你餓得頭昏眼花，精氣神回復得很慢。 |
| `parched` | SYSTEM | 本人 | peer | self | 你渴得說不出話來。 |
| `birthday` | SYSTEM | 本人 | attr_name | self | 今天是你的生日，你的{attr_name}提升了！ |

> 本人收件的事件 payload 一律帶 `peer`（= 收件者 peer），讓 TextRenderer 選到 `self`。

#### 3.8.2 NPC 與經濟

| key | ch | 收件 | payload | 變體 | 範例文字 |
|---|---|---|---|---|---|
| `<npcs.talk>`（例 `talk_n_wujieshan`） | SCENE | 本人 | npc_name, name, peer | self | 武介山愁眉苦臉地說：「最近西夏郊外的大野兔……」 |
| `npc_menu` | SYSTEM | 本人 | npc, npc_name, services:Array, closed:bool, quests:[{id, name, state}], routes:[{to_room, to_name, price}], inn_price, join_sect, sect_name, refresh:bool?（接／交任務成功後主機重送，true＝只更新已開著的同一位 NPC 對話框，不另開） | UI-only | — |
| `shop_list` | SYSTEM | 本人 | npc, npc_name, items:[{id, name, tab, price}], sellable:[{uid, id, name, n, price, equipped:bool}] | UI-only | — |
| `teach_list` | SYSTEM | 本人 | npc, npc_name, entries:[{skill, name, kind, cap, level, ok:bool, reason, price}] | UI-only | — |
| `buy` | SYSTEM | 本人 | peer, item_name, n, cost | self | 你花了 {cost} 兩買下{item_name} ×{n}。 |
| `sell` | SYSTEM | 本人 | peer, item_name, n, gain | self | 你把{item_name} ×{n}賣了 {gain} 兩。 |
| `learn` | SYSTEM | 本人 | peer, npc_name, skill_name, times, prof, lp, jing, level | self | 你向{npc_name}請教{skill_name}{times}次，花了 {lp} 點學點、{jing} 點精，熟練度 +{prof}。 |
| `skill_up` | SYSTEM | 本人 | peer, skill_name, level | self | 你的「{skill_name}」進步到第 {level} 級！ |
| `self_study` | SYSTEM | 本人 | peer, skill_name, times, prof, jing | self | 你閉目揣摩{skill_name}{times}次，熟練度 +{prof}。 |
| `life_learn` | SYSTEM | 本人 | peer, npc_name, skill_name, cost, tool_name | self | 你向{npc_name}學會了{skill_name}。（-{cost} 兩） |
| `sect_join` | SYSTEM | 全部在線 | name, peer, sect_name | self, other | 你拜入{sect_name}門下。／{name}拜入了{sect_name}。 |
| `inn_rest` | SYSTEM | 本人 | peer, cost | self | 你在客棧好好歇了一宿，精神飽滿。（-{cost} 兩） |
| `respawn_set` | SYSTEM | 本人 | peer, room_name | self | 查小鏞在簿子上記下：你的記錄點設在{room_name}。 |
| `meal` | SYSTEM | 本人 | peer, npc_name | self | 你在齋堂用了一頓齋飯。 |

#### 3.8.3 物品、回復、生活技能、任務

| key | ch | 收件 | payload | 變體 | 範例文字 |
|---|---|---|---|---|---|
| `item_use` | SYSTEM | 本人 | peer, item_name, effects:Array | self | 你服下{item_name}。 |
| `item_gain` | SYSTEM | 本人 | peer, item_name, n | self | 你得到{item_name} ×{n}。 |
| `item_lost` | SYSTEM | 本人 | peer, item_name, n | self | 你失去了{item_name} ×{n}。 |
| `item_drop` | SYSTEM | 本人 | peer, item_name, n | self | 你丟掉了{item_name} ×{n}。 |
| `item_spoiled` | SYSTEM | 本人 | peer, item_name, n | self | 你的{item_name}放太久，已經腐爛了。 |
| `money_gain` | SYSTEM | 本人 | peer, n | self | 你得到 {n} 兩銀子。 |
| `equip` | SYSTEM | 本人 | peer, item_name | self | 你裝備了{item_name}。 |
| `unequip` | SYSTEM | 本人 | peer, item_name | self | 你卸下了{item_name}。 |
| `overdose` | SYSTEM | 本人 | peer | self | 你服藥過量，氣血失調！ |
| `meat_vow_broken` | SYSTEM | 本人 | peer, skill_name, level | self | 你破了葷戒，{skill_name}降了一級，現為 {level} 級。 |
| `meditate` | SYSTEM | 本人 | peer, gain, neili | self | 你運氣修煉內力，內力 +{gain}（{neili}）。 |
| `cultivate` | SYSTEM | 本人 | peer, qi_gain, count | self | 你修煉內力有成，氣的上限 +{qi_gain}。（第 {count} 次） |
| `exert` | SYSTEM | 本人 | peer, stat_name, gain | self | 你施展內功，{stat_name}回復了 {gain}。 |
| `work_ok_life_farming` | SYSTEM | 本人 | peer, skill_name, item_name, n, prof | self | 你在田裡耕作了一陣，收成{item_name} ×{n}。（種田熟練度 +{prof}） |
| `work_ok_life_woodcut` | 同上 | | 同上 | self | 你掄起柴刀砍了一陣，得到{item_name} ×{n}。 |
| `work_ok_life_fishing` | 同上 | | 同上 | self | 你垂釣良久，釣起了{item_name} ×{n}。 |
| `work_ok_life_cooking` | 同上 | | 同上 | self | 你在灶前忙了一陣，做好了{item_name} ×{n}。 |
| `work_fail_life_farming` 等 4 個 | SYSTEM | 本人 | peer, skill_name, prof | self | 你忙了半天，什麼也沒收成。（{skill_name}熟練度 +{prof}） |
| `quest_accept` | SYSTEM | 本人 | peer, quest_name, text | self | 【任務】你接下了「{quest_name}」：{text} |
| `quest_progress` | SYSTEM | 本人 | peer, quest_name, have, need, target_name | self | 【任務】{quest_name}：{target_name} {have}/{need} |
| `quest_complete` | SYSTEM | 本人 | peer, quest_name | self | 【任務】你完成了「{quest_name}」！ |
| `quest_abandon` | SYSTEM | 本人 | peer, quest_name | self | 【任務】你放棄了「{quest_name}」。 |
| `reward` | SYSTEM | 本人 | peer, combat_xp, learn_points, money, fame, morality | self | 你獲得 實戰經驗 +{combat_xp}、學習點數 +{learn_points}、銀兩 +{money}。 |

#### 3.8.4 戰鬥（由 `Battle` 產生，ch = BATTLE，收件 = 該場戰鬥的所有玩家 peer）

共通 payload：`bid`；單位以 `uid` + `name` + `peer` 表示。攻擊類事件帶 `atk_uid, def_uid, atk, def, atk_peer, def_peer`。

| key | payload（除共通外） | 變體 | 範例文字 |
|---|---|---|---|
| `battle_gauges` | tick, units:[[uid, gauge, rate_per_tick, charging:bool]] | UI-only | — |
| `battle_await` | units:[uid], deadline_tick | UI-only | — |
| `battle_end` | result:String | UI-only | — |
| `battle_move` | uid, name, peer, from:[x,y], to:[x,y] | self, other | 你移動了位置。／{name}移動了位置。 |
| 招式命中：key = `moves.flavor`（例 `move_fist_basic`） | art, move, tenths, dmg, part, crit:bool, def_qi, atk_neili | self, target, other | 見 3.11.13 |
| 普通攻擊命中：`atk_fist` `atk_blade` `atk_sword` `atk_staff` `atk_whip` `atk_spear` | weapon（兵器名，空手為「拳腳」）, dmg, part, crit, def_qi | self, target, other | 你揮動{weapon}，打中{def}的{part}！（-{dmg}） |
| `battle_miss` | move（招式名或兵器名） | self, target, other | 你的「{move}」被{def}閃開了。／{atk}的「{move}」被你閃開了。／{atk}的「{move}」落空了。 |
| `battle_crit` | — | self, target, other | 好一招！ |
| `battle_counter` | （atk = 反擊者） | self, target, other | 你看穿來勢，順勢反擊！／{atk}看穿你的來勢，順勢反擊！ |
| `battle_defend` | uid, name, peer | self, other | 你擺開架式，嚴加防守。／{name}擺開架式，嚴加防守。 |
| `battle_rest` | uid, name, peer, qi_gain, neili_gain, qi, neili | self, other | 你調勻呼吸，回復了 {qi_gain} 點氣。 |
| `battle_equip` | uid, name, peer, item_name | self, other | 你換上了{item_name}。 |
| `battle_flee` | uid, name, peer | self, other | 你一個轉身，逃出了戰圈！／{name}逃走了！ |
| `battle_timeout` | uid, name, peer | self, other | 你遲遲沒有出手，只好先守住門戶。 |
| `battle_proc_DEFENSE` | uid, name, peer, skill_name | self, other | 你默念佛號，{skill_name}護體！ |
| `battle_proc_RECOVER` | uid, name, peer, skill_name, qi_gain, shen_gain | self, other | 你一派儒雅，{skill_name}運轉，回復了 {qi_gain} 點氣。 |
| `battle_status_on` | uid, name, peer, status, status_name | self, other | 你受了{status_name}！ |
| `battle_status_off` | uid, name, peer, status, status_name | self, other | 你的{status_name}好了。 |
| `battle_wound_tick` | uid, name, peer, dmg, qi | self, other | 你內傷發作，氣血翻湧。（-{dmg}） |
| `battle_kill` | uid, name, peer(0), by | other | {name}哀嚎一聲，倒地不起。 |
| `battle_death` | uid, name, peer | self, other | 你眼前一黑，倒了下去……／{name}倒在地上。 |

`part`（受擊部位）由 `Battle` 的 rng 從 `["胸口","左肩","右臂","小腹","後背","頭頂","左腿","右腿"]` 抽取【設計提案】。

#### 3.8.5 戰鬥前後（由 WORLD 產生）

| key | ch | payload | 變體 | 範例文字 |
|---|---|---|---|---|
| `encounter` | BATTLE | peer, clock, room_name, monsters（以「、」連接的名稱） | self | 【{clock}】你在{room_name}踩到了{monsters}！ |
| `fight_start` | BATTLE | peer, npc_name | self | {npc_name}擺開架式：「出招吧！」 |
| `battle_victory` | BATTLE | peer | self | 你打贏了這一仗。 |
| `battle_victory_fled` | BATTLE | peer | self | 對手逃出戰圈，這一仗沒有任何收穫。 |
| `battle_defeat` | BATTLE | peer | self | 你敗下陣來。 |
| `battle_fled` | BATTLE | peer | self | 你脫離了戰鬥。 |
| `battle_reward` | BATTLE | peer, combat_xp, learn_points, money | self | 你獲得 實戰經驗 +{combat_xp}，學習點數 +{learn_points}。 |
| `death_strict` | SYSTEM | peer, n_skills, n_items, room_name | self | 你死了。所有武功都退步了一級，身上的東西全留在{room_name}的屍體上。 |
| `death_standard` | SYSTEM | peer, skill_name, level, n_items, room_name | self | 你死了。{skill_name}退步到 {level} 級，身上的裝備留在{room_name}的屍體上。 |
| `death_standard_safe` | SYSTEM | peer | self | 你死了。所幸初入江湖，沒有任何損失。 |
| `death_casual` | SYSTEM | peer, money_lost | self | 你死了，掉了 {money_lost} 兩銀子。 |
| `respawn` | SYSTEM | peer, room_name | self | 你在{room_name}悠悠醒轉。 |
| `corpse_looted` | SYSTEM | peer, n_items | self | 你從自己的屍體上取回了 {n_items} 件物品。 |
| `corpse_expired` | SYSTEM | peer, room_name | self | 你留在{room_name}的屍體已經不見了。 |

### 3.9 推送給客戶端的快照

#### 3.9.1 角色表 `s2c_sheet(sheet)`（由 `Character.to_sheet()` 產生，WORLD 補上 `clock`、`in_battle`、`battle_id`）

```gdscript
{
  "char_id": "ch_1a2b3c4d", "name": "測試俠客", "gender": "M", "birth_month": 3, "birth_city": "xixia",
  "sect": "shaolin", "sect_name": "少林",
  "attrs": { "str": 22, ... },          # 有效屬性
  "attrs_base": { "str": 22, ... },
  "vitals": { "jing": 80, "jing_max": 92, "qi": 170, "qi_max": 180, "shen": 88, "shen_max": 88,
              "neili": 5, "neili_max": 10, "food": 96, "water": 94 },
  "carry": 14, "carry_max": 160,
  "combat_xp": 250, "learn_points": 40, "learn_points_cap": 65200, "lili": 0, "fame": 0,
  "morality": 0, "killing_intent": 0, "pk": 0, "money": 180,
  "art_level_cap": 10, "weapon_power": 4, "armor_power": 2,   # 武器強度／防具強度【已證實】
  "special_arts": 1, "special_arts_max": 16,
  "skills": [ { "id": "foxa", "name": "佛法", "kind": "SECT", "category": "", "level": 10, "prof": 1000, "next_prof": 1331 } ],
  "inventory": [ { "uid": "it_0001", "id": "w_mudao", "name": "木刀", "tab": "WEAPON", "n": 1, "weight": 2,
                   "equipped_slot": "WEAPON", "usable": false, "equippable": true } ],
  "equipped": { "WEAPON": "it_0001", "ARMOR": "it_0002" },
  "quests": [ { "id": "q_rabbit", "name": "狩獵事件：大兔皮", "giver_name": "武介山",
                "steps": [ { "text": "交給武介山 1 張大兔皮", "have": 0, "need": 1, "done": false } ] } ],
  "quests_done": ["q_rice"],
  "location": { "region": "xixia", "region_name": "西夏", "room": "xx_square", "room_name": "西夏廣場" },
  "respawn": { "room": "xx_gate_e", "room_name": "西夏東門" },
  "clock": { "text": "辰時三刻", "night": false, "day": 1 },
  "in_battle": false, "battle_id": 0,
  "cooldowns": { "meditate": 0.0, "life": 0.0 }   // 冷卻剩餘真實秒數（世界時間 ÷ time_scale，送出當下計算）；life = 生活技能共用冷卻（附加，2026-10）。
                                                   // UI 以收件時刻（sheet._rx_ms，客戶端蓋）自己倒數（CooldownTracker，不輪詢主機）：按鈕灰掉、鈕面「修煉（7 秒）」（方鈕畫兩行：修煉／（7 秒）），冷卻完回到「修煉」
}
```

#### 3.9.2 房間視圖 `s2c_region_view(view)`

```gdscript
{
  "region": "xixia_wild", "region_name": "西夏郊外", "room": "xw_grass", "room_name": "荒草坡",
  "desc": "……", "clock": "辰時三刻", "night": false,
  "exits": [ { "dir": "W", "label": "西", "to": "xw_road", "to_name": "東門外官道", "locked": false,
               "lock_reason": "" } ],   # 進不去時為 req_* 原因碼；UI 把按鈕設為灰色並顯示原因
  "npcs": [ { "id": "n_xw_fisher", "name": "漁夫", "kind": "FUNC", "services": ["TEACH"], "closed": false } ],
  "players": [ { "peer": 1, "name": "測試俠客", "char_id": "ch_1a2b3c4d" } ],
  "features": ["WATER"],
  "corpses": [ { "id": "cp_00aa11bb", "owner_name": "測試俠客", "mine": true, "n_items": 2 } ],
  "danger": true,      # 此房間遇敵率 > 0
  "danger_top": "野狼", # 遇敵表中最強（combat_xp_ref 最高）的怪物名稱；沒有遇敵為 ""
  "safe": false
}
```

#### 3.9.3 戰鬥開場 `s2c_battle_open(state)`（= `Battle.snapshot()`，WORLD 補上 `my_uid`）

```gdscript
{
  "bid": 3, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1,
  "escape": [[0, 6], [5, 0]],
  "units": [
    { "uid": 1, "name": "測試俠客", "side": 0, "kind": "PLAYER", "peer": 1, "pos": [1, 3],
      "qi": 180, "qi_max": 180, "neili": 0, "neili_max": 0, "jing": 92, "jing_max": 92,
      "gauge": 0.0, "rate": 7.0, "state": "CHARGING", "move_range": 2,
      "weapon": { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" },
      "weapon_options": [ { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" } ],
      "arts": [ { "id": "sl_changquan", "name": "少林長拳", "category": "FIST", "level": 10,
                  "moves": [ { "id": "sl_cq_1", "name": "黑虎掏心", "unlock_level": 1, "range": 1,
                               "cost_inner": 0, "cost_jing": 0, "usable": true } ] } ] }
  ]
}
```

敵方單位只帶 `uid name side kind peer pos qi qi_max gauge rate state`（其餘欄位可省略）。

**表現用追加欄位（戰鬥美術，向下相容；舊客戶端忽略即可，不影響規則）**：
- 玩家單位帶 `"look"`：`"<門派 id 或 player>_<m|f>"`（`Character.battle_look()`，例 `"shaolin_m"`、`"huashan_f"`、未入派 `"player_m"`）。
- 敵方單位帶 `"ref"`：怪物 id（例 `"m_wolf"`；NPC 定點戰鬥為該 NPC 的 `fight.monster`）。玩家單位不帶 `ref`（不外流角色 id）。
- 客戶端以 `ArtRegistry.ref_for_unit(u)` 取得選圖代號（沒有 `look` 的玩家 → `"player_m"`），再查 `data/art.json`（見 `ui/common/art_registry.gd`、`tools/import_art.py`、`docs/ART_REQUEST.md`）。

#### 3.9.4 戰鬥結束 `s2c_battle_close(result)`

```gdscript
{ "bid": 3, "result": "VICTORY",          # "VICTORY" / "DEFEAT" / "FLED" / "ABORTED"
  "you_died": false,
  "enemies_fled": false,                    # VICTORY 但沒有任何敵人被打死（對手全部逃走、沒有獎勵）→ UI 顯示「對手逃走了」
  "rewards": { "combat_xp": 5, "learn_points": 2, "money": 1, "items": [ { "id": "r_rabbitskin", "name": "兔皮", "n": 1 } ] },
  "death": {} }                            # 死亡時：{ "rule", "skill_losses":[...], "n_items", "money_lost", "respawn_room_name" }
```

#### 3.9.5 角色清單 `s2c_char_list(list)` 與 `welcome.your_characters`

```gdscript
[ { "char_id": "ch_1a2b3c4d", "name": "測試俠客", "gender": "M", "sect_name": "少林",
    "combat_xp": 250, "room_name": "少林山門" } ]
```

### 3.10 存檔格式

#### 3.10.1 角色檔 `user://worlds/<world_id>/characters/<identity>/<char_id>.json`

```json
{
  "schema_version": 1,
  "id": "ch_1a2b3c4d", "identity": "local_0123…", "name": "測試俠客", "gender": "M",
  "birth_month": 3, "birth_city": "xixia", "created_s": 12.5, "online_s": 3600.0,
  "attrs": { "str": 22, "guts": 19, "wit": 24, "luck": 18, "cal": 19, "agi": 20, "con": 20 },
  "vitals": { "jing": 80, "qi": 170, "shen": 88, "neili": 5, "food": 96, "water": 94 },
  "combat_xp": 250, "learn_points": 40, "lili": 0, "fame": 0, "morality": 0, "killing_intent": 0, "pk": 0,
  "money": 180, "sect": "shaolin", "sect_enemies": [],
  "skills": { "foxa": { "level": 10, "prof": 1000 }, "basic_inner": { "level": 2, "prof": 13 } },
  "inventory": {
    "items": [ { "uid": "it_0001", "id": "w_mudao", "n": 1, "born_s": 12.5 } ],
    "equipped": { "WEAPON": "it_0001", "ARMOR": "it_0002" } },
  "location": { "region": "shaolin", "room": "sl_gate" },
  "respawn": { "region": "shaolin", "room": "sl_gate" },
  "quests": { "active": {}, "done": { "q_rabbit": 1 } },
  "flags": {}, "buffs": { "smoke_until_s": 0.0 },
  "qi_bonus": 0, "cultivations": 0,
  "counters": { "last_meditate_s": 0.0, "med_uses": [], "last_birthday_year": 0, "last_meal_key": "" },
  "dead_count": 0, "dormant": {}
}
```

- `from_dict()` 負責把所有整數欄位轉回 int（含巢狀的 skills、vitals、items[].n、quests.counts）。
- 讀檔失敗時退回備份（M0 的 `read_json_with_fallback`）；`schema_version` 不是 1 視同損壞。

#### 3.10.2 `world.json` 新增欄位（WP-WORLD；`SaveManager.new_world` 補上預設值，舊檔載入時補齊）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `char_names` | `{ name_lower: { "identity": String, "char_id": String } }` | 名稱唯一索引 |
| `corpses` | `[ { "id", "owner_identity", "char_id", "owner_name", "room", "created_s", "window", "items": [物品實例] } ]` | 既有欄位，M1 開始使用 |
| `clock_last_night` | bool | 晝夜轉換偵測 |
| `id_counter` | int | 產生實例 id 的計數器（與 RNG 合用，保證唯一） |

### 3.11 資料表 schema（WP-DATA）

所有表都是 `{ "table": <名稱>, "version": 1, "rows": [...] }`；每列必有 `id`、`era`（M1 全部 `"1.0A"`）、`src`。下列「int」欄位必須加進 `DataSchema.INT_FIELDS`。

#### 3.11.1 條件格式（`requires`／`join_requires`／`hostile_if`）

| type | 欄位 | 意義 |
|---|---|---|
| `morality_min` / `morality_max` | value:int | 善惡 ≥ / ≤ value |
| `sect` | sect:String | 屬於該門派 |
| `no_sect` | — | 沒有門派 |
| `not_enemy_of` | sect | 不是該派公敵 |
| `gender` | value:"M"/"F" | 性別 |
| `attr_min` | attr, value:int | 有效屬性 ≥ value |
| `skill_min` | skill, value:int | 技能等級 ≥ value |
| `combat_xp_min` | value:int | 實戰 ≥ value |
| `pk_max` | value:int | PK值 ≤ value |
| `quest_flag` | flag:String | `character.flags[flag] == true` |
| `quest_done` | quest:String | 任務完成過（新增 type，DATA 加進 `REQUIRE_TYPES`） |
| `killing_intent_max` | value:int | 殺氣 ≤ value |
| `era_enabled` | era | 該 era 啟用 |
| `sect_enabled` | sect | 在 `server_options.sects_enabled` 內 |
| `rule` | key, value | `rules[key] == value` |
| `unmarried` | — | M1 恆真 |

#### 3.11.2 `attributes.json`

欄位：`id`、`name`、`roll_cap`(int)、`desc`、`era`、`src`。7 列，id 依 3.1。
例：`{ "id": "wit", "name": "悟性", "roll_cap": 25, "desc": "影響學武時精的消耗與每次增加的熟練度；影響讀書和自修。", "era": "1.0A", "src": "verified" }`

#### 3.11.3 `basic_skills.json`

欄位：`id`、`name`、`curve`（`CUBIC`／`QUARTIC`／`LITERACY`）、`difficulty`(float)、`max_level`(int，預設 250)、`attr_bonus_per10`（`{ attr: int }`，只在 `attr_from_basic_skills` 開啟時生效；讀書識字的悟性 +1 不受此開關影響，固定生效）、`era`、`src`。17 列見 5.6。
例：`{ "id": "basic_inner", "name": "基本內功", "curve": "QUARTIC", "difficulty": 0.8, "max_level": 250, "attr_bonus_per10": { "con": 1 }, "era": "1.0A", "src": "verified" }`

#### 3.11.4 `sects.json`（既有欄位 + 修改）

`id name home_city gate_region gender[] join_requires[] sect_skill sect_skill_name sect_skill_effect sect_skill_cost[] sect_skill_cap(int) enforcer jail_region expel_rules[] era src`。
修改：`sect_skill_effect` 改為 `{ "effect": "DEFENSE" }`（GDD 3.3 的枚舉：DEFENSE RESIST EVADE RECOVER COUNTER REST PARALYZE CONFUSE DISTRACT HEAVY POISON_FANG）；新增 `sect_skill_cap`（100）；華山 `join_requires` 加 `{ "type": "quest_flag", "flag": "hs_trial_passed" }`。

#### 3.11.5 `martial_arts.json`

GDD 4.4 + TECH_ARCH 5.3，新增：`monster_only`(bool，預設 false)、`self_study_cap`(int，沒有師父教的武功自修上限，預設 0)。`moves[].aoe` M1 只能是 `SINGLE`。
例：見 5.5 的少林長拳。

#### 3.11.6 `masters.json`

欄位：`id`、`npc_id`、`skill_id`（D4）、`cap`(int)、`requires[]`、`price`(int，每次消點另收的銀兩；生活技能為一次性學費)、`tool`（生活技能：學會時給的工具 item id，可空）、`era`、`src`。
例：`{ "id": "ms_huizhen_changquan", "npc_id": "n_sl_huizhen", "skill_id": "sl_changquan", "cap": 100, "price": 0, "tool": "", "requires": [ { "type": "sect", "sect": "shaolin" }, { "type": "skill_min", "skill": "foxa", "value": 10 } ], "era": "1.0A", "src": "verified" }`

#### 3.11.7 `regions.json`

欄位：`id`、`name`、`type`（CITY／WILD／SECT／DUNGEON）、`city`、`map`（`res://data/maps/<id>.json`）、`suggested_xp`[int,int]、`pk_allowed`、`birth_allowed`(bool)、`birth_room`（出生與預設重生房間，非出生城為 ""）、`night_closed`（保留，M1 為 []）、`era`、`src`。

#### 3.11.8 `maps/<region_id>.json`（房間圖，D1）

```json
{
  "region_id": "xixia_wild", "era": "1.0A", "src": "proposal",
  "desc": "西夏城外一片荒原，風沙捲著枯草，遠處偶有狼嚎。",
  "escape_tiles_hint": 2,
  "rooms": [
    { "id": "xw_grass", "name": "荒草坡", "desc": "……",
      "exits": [ { "dir": "W", "to": "xw_road" }, { "dir": "N", "to": "xw_wood" } ],
      "npcs": [],
      "features": [],
      "requires": [],
      "encounter": { "rate": 0.25, "table": [ { "monster": "m_rabbit", "w": 70, "count": [1, 2] } ] } }
  ]
}
```

- 房間 id 全域唯一（以區格縮寫開頭），出口 `to` 直接寫房間 id（可跨區格）。
- 出口必須雙向（反向方向，3.1），除非出口帶 `"oneway": true`。
- 出口可帶 `"era"`／`"era_until"`（WORLD_2001 §6.2）：`DataLoader.activate()` 依世界的 enabled_eras 篩掉沒生效的出口（主機與客戶端同一個函式）。帶 era 的出口，反向出口也要帶同一個 era（或另一邊整張地圖就是那個 era）；雙向檢查在每個 era 閉包的生效視圖上做。
- `features` ⊂ {`FIELD`, `WOOD`, `WATER`, `STOVE`}。
- `encounter` 可省略（= 不遇敵）；`requires` 是進入此房間的條件（不符回 `room_locked`）。
- `npcs` 與 `npcs.json` 的 `room` 欄位必須一致（lint 檢查）。
- int 欄位：`escape_tiles_hint`、`rooms[].encounter.table[].w`、`rooms[].encounter.table[].count[]`。

#### 3.11.9 `npcs.json`

欄位：`id`、`name`、`kind`（FUNC／MASTER／SHOP／QUEST／STORY／GUARD／EVIL_NPC）、`region`、`room`、`alignment`（GOOD／NEUTRAL／EVIL）、`talk`（text_templates key）、`services[]`（⊂ `SHOP TEACH INN RESPAWN TRAVEL JOIN QUEST MEAL FIGHT`）、`night_closed`(bool)、`shop`（`{ "items": [item id] }` 或 null）、`inn_price`(int)、`travel`（`[ { "to_room", "price" } ]`）、`join_sect`、`quests[]`、`meal`（`{ "food": int, "water": int, "hours": ["卯","午","酉"] }`）、`fight`（`{ "monster": id, "requires": [] }`）、`desc`、`era`、`src`。沒有用到的欄位可省略。
例：`{ "id": "n_xx_station", "name": "驛站管事", "kind": "FUNC", "region": "xixia", "room": "xx_station", "alignment": "NEUTRAL", "talk": "talk_n_xx_station", "services": ["TRAVEL", "QUEST"], "night_closed": false, "travel": [ { "to_room": "dl_station", "price": 150 } ], "quests": ["q_letter"], "era": "1.0A", "src": "verified" }`（`travel` 只在伺服器選項 `stagecoach_enabled` 為 true 時有用；關閉時 `npc_menu.services` 沒有 TRAVEL、`routes` 為空）

#### 3.11.10 `items.json`

欄位：`id`、`name`、`tab`（WEAPON／ARMOR／OTHER／MATERIAL）、`slot`（WEAPON／ARMOR／""）、`weapon_type`（武器才有）、`atk`(int)、`def`(int；武器的 def 是 GDD 9.2「數值2」，語意【待考證】，M1 不使用；防具的 def = 防具強度)、`weight`(int)、`price`(int)、`stack`(int)、`spoil_days`(int，0 = 不腐壞)、`effects[]`、`usable`(bool)、`usable_in_battle`(bool，M1 不用)、`no_sell`(bool)、`quest_item`(bool)、`desc`、`era`、`src`。
`effects` 的 type：`restore`（stat ∈ jing/qi/shen/neili/food/water，value:int）、`attr`（stat ∈ 屬性 id，value:int，裝備時生效）、`smoke`（value:int 秒數）。
例：`{ "id": "a_cubudaopao", "name": "粗布道袍", "tab": "ARMOR", "slot": "ARMOR", "atk": 0, "def": 4, "weight": 3, "price": 120, "stack": 1, "spoil_days": 0, "effects": [ { "type": "attr", "stat": "wit", "value": 2 } ], "era": "1.0A", "src": "verified" }`

#### 3.11.11 `quests.json`

欄位：`id`、`name`、`giver`(npc id)、`text`（接任務時的說明）、`repeatable`(bool)、`requires[]`、`give_items`（`[ { "id", "n" } ]`，接任務時給）、`steps[]`、`rewards`、`era`、`src`。
`steps[]`：`{ "type": "KILL"|"DELIVER"|"TALK"|"REACH", "target": String, "item": String, "count": int, "text": String }`
- KILL：target = 怪物 id，count = 數量（戰鬥勝利時由最後一擊者計數）。
- DELIVER：target = npc id，item、count；`quest_turn_in` 時扣物品。
- TALK：target = npc id；`quest_turn_in` 完成。
- REACH：target = 房間 id；進入房間時完成。
`rewards`：`{ "money": int, "combat_xp": int, "learn_points": int, "fame": int, "morality": int, "items": [ { "id", "n" } ], "flags": [String], "skill_prof": { skill_id: int } }`（缺省 = 0／空）。

#### 3.11.12 `life_skills.json`（新表；`DataLoader.FILES` 加 `"life_skills"`）

欄位：`id`、`name`、`feature`、`tool`（item id 或 ""）、`verb`、`jing_cost`(int)、`cooldown_s`(int，世界時間)、`yield`（`[ { "item", "chance": float, "n": [int,int] } ]`）、`recipes`（只有廚師：`[ { "id", "name", "inputs": [ { "item", "n" } ], "output": { "item", "n" }, "min_level": int } ]`）、`cap`(int)、`era`、`src`。

#### 3.11.13 `text_templates.json`

欄位：`id`、`self`、`target`、`other`（依 3.8 的「變體」欄提供）、`era`、`src`。佔位符 `{name}` 對應 payload 欄位。
必須涵蓋：3.8 全部非 UI-only 的 key；每個招式 `flavor`；6 個 `atk_*`；每個 `npcs.talk`；每個 `err_<reason>`（3.7 去掉帶冒號者與 `drop:`，另加 `err_bad_args`）。
招式模板佔位符：`{atk} {def} {art} {move} {tenths} {dmg} {part}`；M0 既有的 `move_fist_basic`、`move_sword_basic` 保留。

#### 3.11.14 `monsters.json`、`status_effects.json`

`monsters`：`id`、`name`、`short`（戰鬥格子上的兩字簡稱，選填；同名多隻時主機加 甲／乙…）、`kind`（MONSTER／ELITE／BOSS／EVIL_NPC）、`alignment`、`desc`、`stats`（`{ qi, neili, jing, str, guts, wit, luck, cal, agi, con }`，皆 int）、`skills`（`{ skill_id: level }`，至少含 `basic_dodge`、`basic_parry`、`basic_inner`）、`arts`（`[ { "art", "level" } ]`，第一個是主要招式）、`weapon_type`、`weapon_power`、`armor_power`、`combat_xp_ref`、`combat_xp`、`learn_points`、`drops[]`（`{ item, chance, min, max }`）、`money`（`{ min, max }`）、`morality_on_kill`、`killing_intent_on_kill`、`ai`（`melee_basic`／`coward`）、`no_rewards`(bool)、`era`、`src`。
`status_effects`：`id`、`name`、`kind`、`duration_actions`(int)、`blocks`（指令陣列）、`qi_pct_per_action`(float)、`era`、`src`。M1 只有 `inner_wound`（內傷：持續 5 次行動、禁止 REST、每次行動扣 2% 氣上限）。

#### 3.11.15 `tools/data_lint.gd` 新增檢查

1. 每個 `maps/*.json` 符合 3.11.8；房間 id 全域唯一；出口目標存在；雙向性；`features` 合法。
2. 只算**步行出口**（驛站馬車不算，WORLD_2001 §9.1）：從 `xx_square` 走得到每一個房間；出生城彼此走得到；每個 SECT／DUNGEON 地區至少一間房從每座出生城走得到；每個 DELIVER 任務的目標 NPC 從給任務的 NPC 走得到。出口的 `era` 必須是存在的 era id；`server_options.stagecoach_enabled` 有寫就必須是 bool。另外沿出生城 → 門派山門、出生城之間的最短步行路線檢查 WORLD_2001 §1.4 的新手安全規則（lint 印 warning，`test_data_content.gd` 用 assert）。
3. `npcs.room` 存在且該房間的 `npcs` 含此 NPC（雙向一致）。
4. 服務一致：SHOP 有 `shop.items` 且都存在；TRAVEL 的 `to_room` 存在；JOIN 的 `join_sect` 存在；FIGHT 的怪物存在；TEACH 至少有一列 `masters`；QUEST 的任務存在且 `giver` 是此 NPC；MEAL 有 `meal`。
5. `masters.skill_id` 可解析到 basic_skills／martial_arts／sect_skill／life_skills 其中之一；`tool` 存在。
6. `quests.steps` 的 target／item 存在；`rewards.items`、`give_items` 存在。
7. `life_skills` 的 tool、yield、recipes 物品存在；feature 合法。
8. 怪物的 `arts` 存在；`monster_only` 的武功只出現在怪物身上，不出現在 masters。
9. 遇敵表的怪物存在；權重 > 0；count 合法。
10. `regions.birth_room` 存在；`birth_allowed == true` 的只能是 CITY。
11. `text_templates` 涵蓋 3.11.13 的全部 key（清單寫成 lint 內的常數 `REQUIRED_TEMPLATE_KEYS`，內容抄自本文件 3.7、3.8）。
12. `items.effects` 的 type／stat 合法；`slot == "WEAPON"` 的物品有 `weapon_type`。

`DataSchema.REFS` 也要更新（masters 改用自訂檢查；npcs 加 `room` 由 lint 檢查）。fixtures（`tests/fixtures/data_min`）要跟著更新，`test_data_loader.gd` 全部維持綠燈。

### 3.12 WP-UI：畫面清單與行為

畫面可以像 `net_debug.gd` 一樣在程式裡組，`.tscn` 只放根節點與腳本。

| 檔案 | 內容與行為 |
|---|---|
| `ui/game/ui_keys.gd`（`class_name UiKeys`） | intent kind、事件 key、方向標籤、服務名稱的中文對照（例 SHOP→「交易」、TEACH→「請教」、INN→「住宿」、RESPAWN→「記錄」、TRAVEL→「驛站」、JOIN→「拜師」、QUEST→「任務」、MEAL→「用齋」、FIGHT→「切磋」） |
| `ui/game/title/title_screen.tscn/.gd` | 「單機遊玩」（世界名稱輸入，預設 `default`）→ `NetworkManager.start_offline()`；「區網開房」「區網加入」（位址輸入）；「Steam 開房」（Steam 不可用時灰色）；「連線除錯」→ net_debug。連線開始且 `ClientState.welcomed` 後 → 角色選擇 |
| `ui/game/char/char_select.tscn/.gd` | 讀 `ClientState.char_list`；進場送 `char_list`；選角 → `char_select`；刪除需輸入角色名確認 → `char_delete`；「建立新角色」（已有 3 個時灰色）→ 創角。收到 `sheet_changed` 且 `sheet.char_id != ""` → 主畫面 |
| `ui/game/char/char_create.tscn/.gd` | 名稱、性別、生日月份、出生城（從 `GameData.tables.regions` 篩 `birth_allowed`）；「擲骰」→ `char_roll`，從 `char_rolled` 事件顯示 7 項；5 點分配（+／− 按鈕，剩餘點數顯示，總和必須 5 才能送出）；「建立」→ `char_create` |
| `ui/game/main/main_screen.tscn/.gd` | GDD 11.2 版面：上方面板按鈕列（屬性 Ctrl+1、武功 Ctrl+2、背包 Ctrl+3、任務 Ctrl+4、系統 Ctrl+5；Esc 關閉面板）；右側場景面板；下方訊息紀錄；最下方狀態列；左側動作區。`battle_opened` 時疊上戰鬥畫面，`battle_closed` 顯示結果後移除 |
| `ui/game/main/scene_panel.gd` | 房名、時辰、描述、出口按鈕（`move`）、NPC 清單（點擊 → `talk`）、在場玩家、屍體（自己的 → `loot_corpse`）、生活技能按鈕（依 `features` 與已學技能：耕作／砍柴／垂釣／烹煮 → `work`；烹煮彈出食譜選擇） |
| `ui/game/main/message_log.gd` | `RichTextLabel` 顯示 `TextRenderer.render()`；分頁：全部／戰鬥／系統（篩 `ch`）；最多 500 行；底部千里傳音輸入（`chat`）；`intent_result` 失敗時顯示 `err_*` |
| `ui/game/main/status_bar.gd` | 精（黃）、氣（紅）、神（藍）、內（紫）四色條；七屬性縮寫；飽食、飲水；銀兩；實戰、學點 |
| `ui/game/main/action_bar.gd` | 修煉內力（`meditate`）、施展內功（`exert`，選精／氣／神）、查看（`look`） |
| `ui/game/panels/attributes_panel.gd` | 屬性（有效／基礎）、衍生數值、進度數值、門派、記錄點 |
| `ui/game/panels/skills_panel.gd` | 分組：基本武學、特殊武功（n/16）、門派技能、生活技能；等級、熟練度進度條（prof / next_prof）；自修按鈕（`self_study`，次數 1／5／10）；顯示 `art_level_cap` |
| `ui/game/panels/inventory_panel.gd` | 四分頁（武器、防具、其他、原料）；負重 carry/carry_max；每項：使用（`use_item`）、裝備／卸下（`equip`／`unequip`）、丟棄（`drop_item`，確認） |
| `ui/game/panels/quest_panel.gd` | 進行中任務與步驟進度；放棄（`quest_abandon`，確認）；已完成清單 |
| `ui/game/dialogs/npc_dialog.gd` | 收到 `npc_menu` 開啟：對話文字（最近一則 talk 事件）、服務按鈕：交易 → `shop_list`；請教 → `learn_list`；住宿 → `inn_rest`（顯示價格）；記錄 → `set_respawn`；驛站 → 路線清單 → `travel`；拜師 → 確認 → `join_sect`；任務 → 列出 quests（AVAILABLE → `quest_accept`；READY → `quest_turn_in`；ACTIVE 只顯示狀態、沒有交付鈕）；收到 refresh 的 `npc_menu` 就地更新；用齋 → `meal`；切磋 → `fight`；`closed == true` 時服務灰色並顯示「打烊了」 |
| `ui/game/dialogs/shop_dialog.gd` | 收到 `shop_list` 開啟：買（數量 1–99）→ `buy`；賣（背包可賣項目；`equipped` 的標「已裝備」、要再按一次確認）→ `sell`；成功後重新送 `shop_list` |
| `ui/game/dialogs/learn_dialog.gd` | 收到 `teach_list` 開啟：每列技能名、目前等級／師父上限、`ok == false` 時顯示 `reason` 的中文並灰色；「請教 ×1／×5／×10」→ `learn`；成功後重新送 `learn_list` |
| `ui/game/battle/battle_screen.tscn/.gd` | 12×8 格子（黃色＝逃跑格）、時間棒、指令列、戰報；用 `BattleViewModel` |
| `ui/game/battle/battle_view_model.gd`（`class_name BattleViewModel`） | 以 `battle_state` 初始化，套用戰鬥事件：`battle_move`（pos）、命中類（def 的 qi = `def_qi`）、`battle_rest`、`battle_equip`、`battle_flee`、`battle_kill`／`battle_death`、`battle_gauges`（錨點）、`battle_await`（我是否該下令、倒數）；`func gauge_at(uid, now_tick: float) -> float` 在錨點間外插（TECH_ARCH 10.6） |
| `ui/game/battle/command_bar.gd` | 移、攻、武、防、休、裝、逃（另顯示灰色的 特 毒 醫 暗 陣 內 穴，M1 不可用）；只有我的 uid 在 `battle_await.units` 內（或非等待模式下我的單位滿條）時可按；移 → 高亮 `move_range` 內可達格 → 點格；攻 → 點相鄰敵人；武 → 招式選擇器；裝 → 武器清單；逃 → 只有站在逃跑格上可按 |
| `ui/game/battle/art_picker.gd` | 選武功 → 招式（未解鎖灰色）→ 成數滑桿 1–10（預設 10；顯示內力消耗 = `ceil(cost_inner × 成數 / 5)`）→ 點目標 |
| `ui/common/text_renderer.gd`（修改） | 事件有 `"ui": true` 時回傳空字串（`render` 與 `render_plain`）；模板缺變體時也回空字串，但 key 完全不存在時維持 M0 行為（顯示 key + JSON，方便除錯）；新增 `static func render_reason(reason: String, templates: Dictionary) -> String`（3.7 的查表規則） |
| `ui/boot/boot.gd`（修改） | 有 `--bot` 或 `--debug-net` → 照 M0 進 `net_debug`；有連線參數（`--offline` 等）且成功 → `char_select`；沒有參數 → `title`；Steam 不可用時 M0 會自動開離線，改成進 `title` 並顯示原因（**不要**自動開離線） |
| `autoload/scene_router.gd`（修改） | `SCENES` 新增 `title`、`char_select`、`char_create`、`main`；`show_disconnected` 改回 `title` |
| `ui/debug/net_debug.gd`（修改） | 加「進入江湖」按鈕（在世界中時可按）→ `char_select` |

UI 規則：

- 不改任何遊戲狀態；按鈕送出 intent 後鎖住，直到收到同 seq 的 `intent_result`（逾時 5 秒自動解鎖）。
- 數值只從 `ClientState.sheet`、`region_view`、`battle_state` 與事件讀；中文名稱可從 `GameData.tables` 查。
- 字型與主題用 `SceneRouter.theme`（`UiTheme.build()`）；精氣神內顏色寫在 `ui_theme.gd` 的常數。

---

## 4. 公式與常數

除非標【已證實】，以下皆為【設計提案】。「有效屬性」= `Character.effective_attrs()`。所有除法結果在最後才取整（`floori` 除非另註明）。

### 4.1 創角

| 項目 | 規則 | 標記 |
|---|---|---|
| 擲骰 | 每項 = 9 + 4 顆 d4 → [13, 25]，平均 19 | 上限 25【已證實：悟性】；分布【設計提案】 |
| 自由點數 | 5 點，可讓單項超過 25 | 【已證實】 |
| 初始 | 學點 100【已證實】；銀兩 100；精藥水 ×5【已證實 ZOL】；布衣（裝備）、木刀（裝備）；飽食 100、飲水 100；精氣神全滿、內力 0；善惡 0 | |
| 出生位置 | `regions[birth_city].birth_room`；記錄點空白（死亡時回出生房間） | 【已證實】 |

### 4.2 衍生數值

| 數值 | 公式 | 標記 |
|---|---|---|
| 負重上限 | 根骨×3 + 臂力×5 | 【已證實】 |
| 內力上限 | 基本內功等級 × 5 | 【已證實】 |
| 氣上限 | 60 + 根骨×6 + qi_bonus（修煉，每次 +8） | 係數【設計提案】；修煉【後期版：至尊版】 |
| 精上限 | 50 + 悟性×2 + ⌊基本內功/10⌋×8 | |
| 神上限 | 50 + 定力×2 + ⌊讀書識字/10⌋×8 | |
| 讀書成長 | 有效悟性 += min(10, ⌊讀書識字/10⌋)（上限讀 `basic_skills.attr_bonus_cap.wit`） | 【已證實】 |
| 基本武學成長（`attr_from_basic_skills`，預設關） | 有效屬性 += Σ min(`attr_bonus_cap`, ⌊等級/10⌋ × `attr_bonus_per10`)；上限 基內→根骨 14、搏擊→臂力 15、閃躲→機敏 14 | 【後期版】；上限【已證實】 |
| 有效內功 | 基本內功 + ⌊最高 INNER 武功等級 / 2⌋ | |
| 輕功值 | 最高 LIGHTNESS 武功等級 | |
| 武器強度／防具強度 | 裝備的 `atk`／`def` | 【已證實】 |

### 4.3 熟練度曲線（累計熟練度，D5）

| curve | 到達等級 L 所需累計熟練度 | 用於 |
|---|---|---|
| `CUBIC` | ⌈L³ × difficulty⌉ | 一般基本武學、特殊武功（`martial_arts.difficulty`）、門派技能（difficulty 1.0） |
| `QUARTIC` | ⌈L⁴ × 0.8⌉ | 基本內功【已證實：粉絲估算】 |
| `LITERACY` | Σ_{n=0}^{L−1} (n+3)² × 10 | 讀書識字【已證實：粉絲估算，本作解讀為逐級成本】 |
| `LIFE` | L² × 2 | 生活技能 |

難度係數：血刀 1.6、天山折梅手 1.25、神門十三劍 0.97、玉女劍法 0.96、華山劍法 0.8、其他 0.9【已證實：粉絲估算】。

### 4.4 等級上限

| 項目 | 規則 | 標記 |
|---|---|---|
| 實戰上限 | 基本武學、特殊武功、門派技能的等級上限 = 5 + ⌊√(實戰/10)⌋（實戰 0 → 5） | 「沒有實戰最多 5 級」【已證實】；根號式【設計提案】 |
| 師父上限 | `masters.cap` | |
| 門派技能上限 | `sects.sect_skill_cap`（100） | |
| 門派技能限制本門武功（原因碼 `cap_sect_skill`） | `sects.sect_skill_limits_arts = true` 的門派（M1：少林）：本門特殊武功（ART 且 `sect_id` == 角色門派）的等級上限 = 門派技能等級 + `sect_art_cap_bonus`（10）；消點、自修都受限，門派技能本身與基本武學不受限 | 佛法限制本門武功【已證實】；公式【設計提案】 |
| 特殊武功數 | 最多 16 套（level ≥1 的 ART） | 【已證實：懷舊版】 |
| 學點上限 | `rules.xuedian_cap`（0 = 不設） | 【後期版：至尊版】 |
| 自修上限 | `self_study_cap == NONE`：不超過「教此技能的師父最高 cap」，沒有師父則 `martial_arts.self_study_cap`；`HJ_1_5X`：再夾在 min(250, ⌊1.5 × 師父最高 cap⌋)，取兩者較小 | 【後期版】解讀 |

### 4.5 學武

**悟性效率表**（GDD 4.3【已證實】，分段線性，結果四捨五入）：

| 悟性 w | 每次消耗精 | 每次熟練度 |
|---|---|---|
| w ≤ 21 | clamp(10 + (21−w)×5/9, 1, 15) | max(5, 11 − (21−w)×4/9) |
| 21 < w ≤ 30 | 10 − (w−21)×5/9 | 11 + (w−21)×4/9 |
| 30 < w ≤ 40 | 5 − (w−30)×0.3 | 15 + (w−30)×0.5 |
| w > 40 | max(1, 2 − (w−40)×0.1) | 20 + (w−40)×0.5 |

驗算：w=21 → 10／11；w=30 → 5／15；w=40 → 2／20。

**消點（`learn`）每次**：學點 1；精（表）；門派技能另扣 `sect_skill_cost` 含 `neili` 時內力 1、含 `shen` 時神 2；`masters.price` 兩。熟練度 +（表）。

**驗證順序**（第一個失敗即回）：`not_taught`（沒有此 npc+skill 的 masters 列）→ `masters.requires`（`req_*`）→ 武功本身的 `requires`（`req_*`）→ 新武功且已有 16 套 → `cap_arts16` → `self_study_until > 0` 且目前等級 < 該值 → `need_self_study` → 等級 ≥ 師父上限 → `cap_master` → 等級 ≥ 門派技能限制（4.4）→ `cap_sect_skill` → 等級 ≥ 實戰上限 → `cap_xp` → 資源：`not_enough_lp`／`not_enough_jing`／`not_enough_neili`／`not_enough_shen`／`not_enough_money`。`times` 多次時，每次重新檢查上限與資源，不足就停（至少成功 1 次才算 ok）。

**自修（`self_study`）每次**：學點 1；精（表）；熟練度 +⌊有效悟性/4⌋【已證實】。必須已會（level ≥1）或該武功 `self_study_until > 0`；否則 `not_known`。上限見 4.4。

### 4.6 ATB 與移動

| 項目 | 公式 | 標記 |
|---|---|---|
| 每 tick（0.1 秒）時間棒增加 | 4 + 機敏×0.15 + 基本身法×0.03 + 輕功值×0.02 | 【設計提案，GDD 5.3】 |
| 修正 | 負重比 > 0.8 時 ×0.7 | |
| 滿值 | 100 | |
| 移動格數 | 2 + ⌊輕功值/25⌋（曼哈頓距離、4 方向、不能穿越單位） | |
| MOVE 後時間棒 | 設為 50 | |

### 4.7 傷害（GDD 5.5–5.6）

```
出力係數   = 0.55 + 0.05 × 成數；若 對應基本武學 ≥ 120 → 固定 1.05；ATTACK 固定 1.0；AI 一律 10 成
內力消耗   = ceil(招式內力 × 成數 / 5)
兵器類別修正（攻）：刀 +10%、劍 0、拳掌 −10%、其他 0
對手拆招修正（守方的拆招卸力項）：刀 −10%、拳掌 +10%、其他 0

攻擊力 = 兵器強度(只有武功類別 == 手上兵器類別時才算；FIST 招式為 0；ATTACK 用手上兵器)
       + 臂力×1.5 + 招式威力 × (1 + 武功等級/60) + 對應基本武學/4
攻擊力 ×= 出力係數 × (1 + 兵器類別修正) × (1 + 殺氣/10000)

防禦力 = 防具強度 + 根骨×1.2 + 拆招卸力/3 × (1 + 對手拆招修正)
防禦力 ×= (1 − 膽識×0.004) × (1 − 殺氣/20000) × (防禦中 ? 1.5 + 有效內功/400 : 1)

命中率 = clamp(80 + (攻方武功等級 − 守方閃躲縱躍)×0.3 + (攻方機敏 − 守方機敏)×0.8, 10, 95) %
       （ATTACK 的武功等級 = 對應基本武學）
爆擊率 = 2 + 膽識×0.3 %；爆擊倍率 = 1.5 + 根骨×0.01
浮動   = rng 均勻 [1 − (0.3 − 定力×0.006), 1.1]（下界夾在 ≤ 1.0）
內功加成 = rng 均勻 [0, 有效內功/10]
傷害   = max(1, round((攻擊力 − 防禦力×0.6) × 浮動 + 內功加成))；爆擊時 × 爆擊倍率 再 round
反擊率 = 定力 ≥ 25 時 定力×0.4 %；反擊 = 對攻擊者做一次 ATTACK，傷害 ×0.6；反擊不會再引發反擊
```

**結算順序**（一次 ATTACK／ART）：扣內力與精 → 命中判定（失敗 `battle_miss`，結束）→ 爆擊判定（`battle_crit`）→ 算傷害 → 守方門派技能 DEFENSE 觸發（傷害 × (0.7 − 等級×0.002)，`battle_proc_DEFENSE`）→ 扣氣（氣 ≤ 1 → 夾在 1、死亡）→ 命中事件 → 招式附帶狀態（`status_chance`）→ 守方存活時反擊判定 → 攻方行動結束時 RECOVER 觸發（回復 氣、神 各 上限×(3% + 等級×0.05%)）。行動開始時若有內傷：扣 2% 氣上限（`battle_wound_tick`），可致死。

**門派技能觸發率**：level ≥ 1 時 min(25%, 5% + 等級×0.2%)【設計提案，GDD 3.3】。

**REST**：氣 += round(氣上限×5%)、內力 += round(內力上限×10%)。

### 4.8 戰鬥獎勵（GDD 2.4）

```
比例     = (怪物.combat_xp_ref + 1000) / (玩家實戰 + 1000)
學點     = max(1, round(怪物.learn_points × clamp(比例, 0.2, 3.0) × 分享係數))   # learn_points 為 0 的怪物給 0
實戰     = max(1, round(怪物.combat_xp   × clamp(比例, 0.1, 2.0) × 分享係數))   # combat_xp 為 0 的怪物給 0
分享係數 = 1 / √(戰鬥結束時存活且未逃走的玩家人數)
```

- 每隻**死亡**的敵方怪物（`no_rewards == false`）都分別計算，對每位存活未逃的玩家加總。逃走的怪物不給。
- 掉落與銀兩：每隻死亡怪物逐列擲 `drops`（chance → n = randi_range(min, max)）與 `money`，全部給最後一擊者；最後一擊者若已死亡，改給 uid 最小的存活玩家；沒有存活玩家則丟棄。
- `morality_on_kill`、`killing_intent_on_kill` 只給最後一擊者。善惡夾在 [−1000, 1000]。

### 4.9 怪物 AI

| ai | 行為 |
|---|---|
| `melee_basic` | 有相鄰敵人 → 用 `arts[0]` 最高可用招式 ART（10 成）攻擊氣最少的相鄰敵人（同氣比 uid）；否則 MOVE 到離最近敵人最近的可達格（同距離選 x 再 y 較小）；無法移動 → DEFEND |
| `coward` | 氣 < 10% 時：站在逃跑格上 → 先喘一口氣（DEFEND，浪費一次行動），下一次行動才 FLEE；不在逃跑格 → MOVE 往最近的逃跑格；其餘同 `melee_basic`【設計提案；原為 30%，野兔幾乎都在被打死前逃走，見 6.3 kill 檢查】 |

`balance_sim` 的玩家方使用 `melee_basic`，但用 3.3 `arts` 中威力最高的已解鎖招式、10 成。

### 4.10 飽食、飲水、自然回復

| 項目 | 規則 | 標記 |
|---|---|---|
| 下降 | 每 300 秒世界時間各 −1（= 每時辰 −2）；只在角色在線時 | 數值【設計提案，GDD 2.3】 |
| 門檻通知 | 降到 20 → `hungry`／`thirsty`；降到 0 → `starving`／`parched` | |
| 飽食 0 | 自然回復 ×0.25 | 【已證實：官方】 |
| 飲水 0 | M2 聊天限制；M1 無效果 | 【已證實】 |
| 自然回復（非戰鬥） | 每 10 秒：精、氣、神各 +ceil(上限×2%)；內力 +ceil(上限×1%) | |

### 4.11 修煉內力、施展內功、休息、藥物

| 項目 | 規則 |
|---|---|
| 修煉內力 `meditate` | 需基本內功 ≥1（`no_inner`）；冷卻 10 秒（`busy`）；扣精 2；內力未滿 → 內力 += max(1, 基本內功 + ⌊內力上限×0.2⌋)；內力已滿且 `cultivations < 基本內功×5` → 修煉：內力歸 0、`qi_bonus += 8`、`cultivations += 1`；都不行 → `nothing_to_do` |
| 施展內功 `exert` | 內力 ≥ 20（`not_enough_neili`）；扣 20；指定的精／氣／神回復上限的 15%【已證實 ZOL】 |
| 客棧休息 | 付 `inn_price`（20）；精氣神內全滿【設計提案】 |
| 少林齋食 | 卯、午、酉時，每時辰一次，飽食 +40、飲水 +40，免費【已證實：時辰與免費】 |
| 少林葷戒 | 少林弟子（`sects.forbid_meat`）使用 `items.meat = true` 的物品（M1：烤魚、豬肉）→ 佛法降一級（熟練度設為新等級門檻，同死亡降級），送 `meat_vow_broken`；佛法 0 級時不再降【已證實：吃葷降一級；哪些算葷為設計提案】 |
| 服藥過量 | 使用 `restore` 類物品（食物除外：只含 food/water 的不算）時，若最近 60 秒內已用過 5 次 → 本次仍生效，但隨後精氣神都變成 1，送 `overdose`【已證實：現象；門檻為提案】 |
| 守護者之煙 | 使用後 300 秒內遇敵率 ×0.1【已證實：功能與 5000 兩】 |

### 4.12 生活技能

| 項目 | 規則 |
|---|---|
| 學習 | 向教學 NPC `learn`：0 → 1 級，付 `masters.price`（50 兩），得到工具（`masters.tool`，背包已有就不給） |
| 動作 | `work`：房間有對應 feature；需要工具（`life_skills.tool` 在背包）；扣精 `jing_cost`（5）；冷卻 `cooldown_s`（5 秒） |
| 成功率 | min(0.95, 0.5 + 等級×0.005)；成功：依 `yield` 擲產出（廚師：扣食材，產出 `output`），熟練度 +5；失敗：熟練度 +2 |
| 曲線與上限 | `LIFE`（L²×2），上限 100【後期版：至尊版數字】；生活技能**不受**實戰上限限制 |
| 廚師 | 需 `recipe`；`min_level` 不足 → `recipe_level`；食材不足 → `no_ingredients` |

### 4.13 死亡（GDD 6.4）

| death_rule | 武功 | 物品 | 金錢 | 屍體 |
|---|---|---|---|---|
| `STRICT_2001` | **全部**基本武學、特殊武功、門派技能各降 1 級（0 級不變；熟練度設為新等級的門檻值）；生活技能不變 | 背包與裝備**全部**移到屍體 | 不掉 | 有物品就建立 |
| `STANDARD` | 實戰 ≤ 500：不受影響（`death_standard_safe`）。否則只有 `highest_special_art` 降 1 級；沒有特殊武功就不降 | 實戰 ≤ 500：不掉；否則**已裝備**的物品移到屍體 | 不掉 | 有物品就建立 |
| `CASUAL` | 不降級 | 不掉 | 掉 ⌊金錢 × 10%⌋（消失） | 不建立 |

共通：`dead_count += 1`；重生到記錄點（沒有就出生房間）；`respawn_vitals`（精氣神 50%、內力 0）；送 `death_*`、`respawn`、角色表、房間視圖。

**屍體時限**（`rules.corpse_window`，世界時間）：
- 存檔：建立屍體後、成功拾回後都立即 `WorldServer.save_now()`（角色檔與 world.json 一起落地，當機時物品不會消失或重複）。
- `CLASSIC_30`：0–600 秒只有本人可撿；600–1800 秒公開（M2 才有他人撿屍，M1 本人仍可撿）；1800 秒消失。
- `LATER_10`：0–600 秒只有本人；之後公開；1800 秒消失（原作未寫消失時間【設計提案】）。
- 到期時清除並對在線的擁有者送 `corpse_expired`。

### 4.14 遇敵

- 只在進入房間時判定（`move` 成功後）；`rate = room.encounter.rate × (煙 ? 0.1 : 1)`。
- `Encounter.roll`：`rng.randf() < rate` → 依權重抽一列 → 數量 `randi_range(count[0], count[1])`，總數夾在 4 以內；回傳怪物 id 陣列。
- 遇敵時：送 `encounter`，然後開戰（BattleSystem）。

### 4.15 世界時鐘

| 項目 | 規則 |
|---|---|
| 1 遊戲日 | `game_day_real_s`（7200 秒世界時間）【設計提案】 |
| 1 時辰 | 日長 / 12（600 秒）；1 刻 = 時辰 / 8 |
| 起始 | `clock_s = world_time_s + 4 × 時辰長`（新世界從辰時開始） |
| 時辰名 | index 0..11 = 子 丑 寅 卯 辰 巳 午 未 申 酉 戌 亥 |
| 顯示 | 「辰時三刻」：刻 = ⌊時辰內比例×8⌋ → 初 一 二 三 四 五 六 七 |
| 夜間 | 戌、亥、子、丑、寅（index 10, 11, 0, 1, 2）；`night_closed == true` 的 NPC 打烊 |
| 日曆 | day = ⌊clock_s / 日長⌋ + 1；month = (⌊(day−1)/30⌋ % 12) + 1；year = ⌊(day−1)/360⌋ + 1（生日用） |
| 腐壞 | `spoil_days × 日長` 世界時間；每 60 秒世界時間檢查一次在線角色 |

### 4.16 經濟

| 項目 | 數值 |
|---|---|
| NPC 收購價 | ⌊price × 0.3⌋，至少 1【設計提案，GDD 9.4】 |
| 客棧 | 20 兩 |
| 驛站馬車（`stagecoach_enabled`，預設關） | 西夏↔大理 150；1.0B：西夏↔京城 120、大理↔京城 150 |
| 武館 | 每次消點另收 5 兩【設計提案；GDD「500 兩」待考證】 |
| 生活技能學費 | 50 兩 |
| 金錢上限 | 6,000,000【已證實】 |
| 背包上限 | 300 件【設計提案】 |

---

## 5. M1 內容清單（WP-DATA）

### 5.1 區格與房間

**照原作 2001 地理（擁有者決定）**：完整的地區表、房間表、出口與遇敵表以 `docs/WORLD_2001.md` §2、§3 為準（預設世界 15 個地區、71 間房；開 1.0B 後 17 個地區、78 間房）。摘要：

| region | 名稱 | type | era | 房間 |
|---|---|---|---|---|
| `xixia` | 西夏 | CITY（出生，`xx_square`） | 1.0A | `xx_square` `xx_gate_e` `xx_inn` `xx_inn_2f`（STOVE 在客棧）`xx_station` `xx_street` `xx_pharmacy` `xx_smithy` `xx_wuguan` |
| `xixia_wild` | 西夏郊外 | WILD | 1.0A | `xw_road`（NE→東路）`xw_grass` `xw_wood`（WOOD；N→北郊）`xw_creek`（WATER；S→西路）`xw_hill`（狼嚎丘，死路）。`xx_gate_e`→`xw_road`→`xw_grass`→`xw_hill` 這條 E 鏈不准改（UI driver 第 8 步） |
| `xixia_north` | 西夏北郊 | WILD | 1.0A | `xn_slope` `xn_snow`（E→血刀洞口） |
| `xixia_east` | 西夏東郊 | WILD | 1.0A | `xe_road` `xe_mine`（礦工阿火）`xe_xuedao`（血刀洞口，IN→`gw_entrance`）`xe_heilong`（WATER）`xe_river`（WATER） |
| `guiwang` | 血刀洞迷宮 | DUNGEON | 1.0A | `gw_entrance`（OUT→`xe_xuedao`）`gw_hall` `gw_maze` `gw_throne`（鬼王）。`suggested_xp` [10000, 20000] |
| `hengshan_foot` | 恆山山麓 | WILD | 1.0A | `hf_paddy`（FIELD）`hf_teahouse`（茶棚，安全，INN／SHOP）`hf_shore`（WATER）`hf_fork`（往恆山、雁門關，封） |
| `huayin_road` | 華陰道 | WILD | 1.0A | `hy_road` `hy_foot`（N→`hs_gate`；1.0B：NE→`jcw_huashan`）`hy_pond`（WATER） |
| `huashan` | 華山 | SECT | 1.0A | `hs_gate`（S→`hy_foot`）`hs_square` `hs_hall`（requires sect huashan） |
| `songshan_road` | 嵩山古道 | WILD | 1.0A | `sy_road` `sy_wdfork`（往武當，封）`sy_teahouse`（茶棚，安全）`sy_pines`（WOOD；1.0B：N→`jcw_songshan`）`sy_foot` |
| `shaolin` | 少林寺 | SECT | 1.0A | `sl_gate`（W→`sy_foot`）`sl_court` `sl_wuchang` `sl_hall` `sl_zhaitang`（STOVE）`sl_caiyuan`（FIELD）`sl_zhulin`（WOOD） |
| `xixia_south` | 西夏南坡 | WILD | 1.0A | `ws_slope` `ws_ford`（WATER）`ws_dunes` |
| `desert_edge` | 大漠邊緣 | WILD | 1.0A | `de_edge` `de_cave` `de_oasis`（綠洲，安全，WATER，INN／SHOP） |
| `river_road` | 河川古道 | WILD | 1.0A | `rr_upper` `rr_road` `rr_bend`（WATER）`rr_bridge` |
| `dali_wild` | 大理郊外 | WILD | 1.0A | `dlw_road` `dlw_river`（WATER）`dlw_paddy`（FIELD）`dlw_lake`（WATER）`dlw_forest`（山賊）`dlw_eastwood`（WOOD）`dlw_fork`（往崆峒、峨嵋、終南，封）。`dlw_cave` 已刪除（舊存檔搬到 `dlw_forest`） |
| `dali` | 大理 | CITY（出生，`dl_square`） | 1.0A | `dl_square` `dl_station` `dl_gate_n` `dl_inn`（STOVE）`dl_yamen` `dl_wuguan` `dl_shop` |
| `jingcheng` | 京城 | CITY（不能出生） | **1.0B** | `jc_station` `jc_street` `jc_inn` `jc_gate_s` |
| `jingcheng_wild` | 京城南郊 | WILD | **1.0B** | `jcw_crossroad` `jcw_huashan`（SW→`hy_foot`）`jcw_songshan`（S→`sy_pines`） |

步數：西夏東門 → 華山山門 12、華山 → 少林 8、西夏東門 → 大理北門 16、西夏廣場 → 鬼王殿 9。新手安全規則見 WORLD_2001 §1.4。

### 5.2 NPC

| id | 名稱 | 房間 | 服務 | 細節 | src |
|---|---|---|---|---|---|
| `n_xx_cha` | 查小鏞 | xx_gate_e | RESPAWN | | later（懷舊版 jyhj） |
| `n_xx_guard` | 西夏守衛 | xx_gate_e | — | GUARD，對話 | verified |
| `n_wujieshan` | 武介山 | xx_square | QUEST | q_rabbit | verified |
| `n_xx_innkeeper` | 店小二 | xx_inn | INN、SHOP | inn_price 20；商品 c_mantou、c_water | proposal |
| `n_xx_cook` | 客棧廚子 | xx_inn | TEACH | life_cooking | proposal |
| `n_zhangwuji` | 張無忌 | xx_inn_2f | — | STORY，對話 | verified |
| `n_xx_station` | 驛站管事 | xx_station | TRAVEL、QUEST | 路線 dl_station 150（只在 `stagecoach_enabled` 時，【設計提案・非原作】；1.0B patch 加 jc_station 120）；q_letter | verified（驛站存在） |
| `n_xx_pharmacist` | 藥鋪掌櫃 | xx_pharmacy | SHOP | night_closed；c_jingyao、c_qiyao | proposal |
| `n_xx_smith` | 兵器鋪老闆 | xx_smithy | SHOP | night_closed；w_mudao、w_chaidao、w_dandao、w_gangdao、w_mujian、w_qingfeng、w_zhubang、a_bupao、a_pijia、a_cubudaopao | proposal |
| `n_xx_wushi` | 武館教頭 | xx_wuguan | TEACH | 基本武學（5.6 的武館欄），cap 30，price 5 | 武館【已證實】；cap、價格 proposal |
| `n_yeerniang` | 葉二娘 | xx_street | — | EVIL_NPC，M1 只對話 | verified |
| `n_nanhai` | 南海鱷神 | xx_street | — | EVIL_NPC，M1 只對話 | verified |
| `n_chenjialuo` | 陳家洛 | xw_road | — | STORY | verified |
| `n_xw_fisher` | 漁夫 | xw_creek | TEACH | life_fishing，給 t_yugan | verified（向漁夫學）|
| `n_xw_woodcutter` | 樵夫 | xw_wood | TEACH | life_woodcut，給 w_chaidao | verified |
| `n_xe_miner` | 礦工阿火 | xe_mine | — | STORY，對話（血刀洞迷宮與鬼王） | verified（人名）／proposal（台詞） |
| `n_hf_teaman` | 茶棚老闆 | hf_teahouse | INN、SHOP | inn_price 15；c_mantou、c_water、c_qiyao；沒有 STOVE、沒有 RESPAWN | proposal |
| `n_sy_teaman` | 茶棚老闆 | sy_teahouse | INN、SHOP | 同上 | proposal |
| `n_de_host` | 綠洲店家 | de_oasis | INN、SHOP | 同上 | proposal |
| `n_jc_station` | 京城驛站管事 | jc_station | TRAVEL | **1.0B**；xx_station 120、dl_station 150 | proposal |
| `n_jc_innkeeper` | 京城店小二 | jc_inn | INN、SHOP | **1.0B**；20；c_mantou、c_water | proposal |
| `n_jc_cha` | 查小鏞 | jc_gate_s | RESPAWN | **1.0B** | later |
| `n_jc_guard` | 京城守衛 | jc_gate_s | — | **1.0B**；GUARD | proposal |
| `n_sl_cha` | 查小鏞 | sl_gate | RESPAWN | | later |
| `n_sl_zhike` | 知客僧 | sl_gate | JOIN、TEACH | join_sect shaolin；教 foxa（cap 50，requires sect shaolin） | proposal（少林入門 NPC 未考證） |
| `n_sl_huizhen` | 慧真 | sl_wuchang | TEACH | 5.5 少林；另教 basic_inner、basic_fist、basic_parry、basic_dodge、basic_body（cap 140，requires sect shaolin，src proposal） | verified（武功清單）|
| `n_sl_huixu` | 慧虛 | sl_wuchang | TEACH | sl_cibeidao | verified |
| `n_sl_huikong` | 慧空 | sl_wuchang | TEACH | sl_luohanjian | verified |
| `n_sl_zhaiseng` | 齋堂僧 | sl_zhaitang | MEAL | food 40、water 40、hours 卯午酉 | 齋食【已證實】；NPC 名 proposal |
| `n_hs_cha` | 查小鏞 | hs_gate | RESPAWN | | later |
| `n_yuebuqun` | 岳不群 | hs_square | JOIN、QUEST、TEACH | join_sect huashan；q_hs_kaoyan；教 hs_xinfa、hs_jianfa（cap 100）、rufeng（cap 50），皆 requires sect huashan | 考驗【已證實】；教授項目 proposal |
| `n_ludayou` | 陸大有 | hs_square | FIGHT | fight.monster = m_hs_trainee | proposal |
| `n_liangfa` | 梁發 | hs_hall | TEACH | basic_inner 140、basic_fist 150、basic_parry 140、basic_dodge 140、basic_sword 150、basic_body 140（requires sect huashan） | later（至尊版上限） |
| `n_dl_station` | 大理驛站管事 | dl_station | TRAVEL、QUEST | xx_station 150（同 n_xx_station 的馬車條件；1.0B patch 加 jc_station 150）；q_letter_dl | proposal |
| `n_dl_cha` | 查小鏞 | dl_gate_n | RESPAWN | | later |
| `n_dl_guard` | 大理守衛 | dl_gate_n | — | GUARD | proposal |
| `n_dl_innkeeper` | 大理店小二 | dl_inn | INN、SHOP | 20；c_mantou、c_water | proposal |
| `n_dl_cook` | 客棧廚子 | dl_inn | TEACH | life_cooking | proposal |
| `n_dl_bukuai` | 捕快 | dl_yamen | QUEST | q_bandit | verified（捕快存在） |
| `n_weixiaobao` | 韋小寶 | dl_yamen | — | STORY | verified |
| `n_shuanger` | 雙兒 | dl_yamen | — | STORY | verified |
| `n_dl_wushi` | 武館教頭 | dl_wuguan | TEACH | 同 n_xx_wushi | proposal |
| `n_dl_grocer` | 雜貨鋪老闆 | dl_shop | SHOP | night_closed；c_mantou、c_water、c_jingyao、c_qiyao、t_chutou、t_yugan、c_smoke | proposal |
| `n_taoyun` | 陶耘 | dlw_paddy | QUEST、TEACH | q_rice；life_farming，給 t_chutou | verified |
| `n_guiwang` | 鬼王 | gw_throne | FIGHT | fight.monster = m_guiwang | proposal |

每個 NPC 的 `talk` 模板 key = `talk_<npc id>`，DATA 為每位寫一句符合原著或功能的台詞（繁中）。

### 5.3 怪物（起始數值；最後依 balance_sim 調整）

| id | 名稱 | 氣 | 臂 | 根 | 機 | 定 | 膽 | 閃/拆/內 | 招式（等級） | 兵/防 | ref | 實戰 | 學點 | 掉落 | 銀兩 | ai | 地點 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `m_rabbit` 野兔 | | 60 | 8 | 10 | 15 | 5 | 5 | 5/0/0 | mon_bite(1) | 0/26 | 50 | 5 | 2 | r_rabbitskin 0.5 | 0–2 | coward | 西夏郊外、西路、東路、大理郊外 |
| `m_bigrabbit` 大野兔 | | 150 | 10 | 12 | 16 | 8 | 6 | 8/0/0 | mon_bite(5) | 0/31 | 200 | 10 | 4 | r_bigrabbitskin 0.5、r_rabbitskin 0.5 | 0–3 | melee_basic | 西夏郊外 |
| `m_wolf` 野狼 | | 250 | 10 | 15 | 22 | 12 | 12 | 15/5/0 | mon_claw(10) | 0/28 | 500 | 15 | 6 | r_wolfskin 0.5 | 0–5 | melee_basic | 西夏郊外、北郊、東郊、西路、東路、大理郊外 |
| `m_boar` 山豬 | | 250 | 13 | 20 | 14 | 15 | 20 | 10/10/0 | mon_ram(15) | 0/30 | 900 | 20 | 12 | r_pork 0.6 | 0–5 | melee_basic | 大理蒼山林道、鬼王洞口（P1→P2 的主要練功對象） |
| `m_bandit` 山賊 | | 600 | 20 | 20 | 20 | 18 | 22 | 25/25/10 | mon_blade(25) | 10/30 | 3000 | 40 | 15 | w_dandao 0.1、c_qiyao 0.2 | 20–60 | melee_basic | 大理郊外；EVIL，善惡 +3、殺氣 +5 |
| `m_hs_trainee` 華山弟子 | | 220 | 14 | 16 | 18 | 16 | 15 | 8/8/5 | hs_jianfa(8) | 4/6 | 300 | 0 | 0 | — | — | melee_basic | 陸大有切磋；`no_rewards: true`；weapon_type SWORD |
| `m_ghost` 鬼王洞小鬼 | | 450 | 14 | 22 | 24 | 20 | 25 | 35/30/20 | mon_ghost(30) | 0/40 | 10000 | 60 | 30 | c_qiyao 0.15 | 10–40 | melee_basic | 鬼王洞（D6） |
| `m_guiwang` 鬼王 | | 2000 | 24 | 30 | 26 | 28 | 30 | 50/50/50 | mon_guiwang(50) | 0/60 | 20000 | 300 | 120 | c_qiyao 1.0 (2–3)、a_cubudaopao 0.3 | 200–400 | melee_basic | 鬼王殿 BOSS |

所有怪物 `src: "proposal"`，除了：野兔、大野兔（大兔皮任務）、野狼、山豬、山賊、小鬼的**存在**為 `verified`／GDD 7.3（數值仍為提案，`src` 填 `proposal`，在 `desc` 旁加註也可）。
怪物的 `skills` 未列出對應基本武學時，BATTLE 以招式等級當作對應基本武學等級。

### 5.4 物品

| id | 名稱 | tab | slot / 類別 | atk / def | 重 | 價 | stack | 腐壞日 | 效果 | src |
|---|---|---|---|---|---|---|---|---|---|---|
| `w_mudao` | 木刀 | WEAPON | WEAPON / BLADE | 4 / 4 | 2 | 20 | 1 | 0 | | verified |
| `w_chaidao` | 柴刀 | WEAPON | WEAPON / BLADE | 5 / 6 | 3 | 50 | 1 | 0 | 樵夫工具 | verified |
| `w_dandao` | 單刀 | WEAPON | WEAPON / BLADE | 10 / 6 | 3 | 150 | 1 | 0 | | verified |
| `w_gangdao` | 鋼刀 | WEAPON | WEAPON / BLADE | 15 / 7 | 4 | 400 | 1 | 0 | | verified |
| `w_mujian` | 木劍 | WEAPON | WEAPON / SWORD | 4 / 4 | 2 | 20 | 1 | 0 | | proposal |
| `w_qingfeng` | 青鋒劍 | WEAPON | WEAPON / SWORD | 15 / 7 | 3 | 400 | 1 | 0 | | proposal |
| `w_zhubang` | 竹棒 | WEAPON | WEAPON / STAFF | 6 / 5 | 2 | 30 | 1 | 0 | | proposal |
| `a_bupao` | 布衣 | ARMOR | ARMOR | 0 / 2 | 2 | 10 | 1 | 0 | | proposal |
| `a_cubudaopao` | 粗布道袍 | ARMOR | ARMOR | 0 / 4 | 3 | 120 | 1 | 0 | attr wit +2 | verified（悟性+2） |
| `a_pijia` | 皮甲 | ARMOR | ARMOR | 0 / 8 | 5 | 300 | 1 | 0 | | proposal |
| `c_jingyao` | 精藥水 | OTHER | — | | 1 | 30 | 99 | 0 | restore jing 50 | verified |
| `c_qiyao` | 金創藥 | OTHER | — | | 1 | 50 | 99 | 0 | restore qi 100 | proposal |
| `c_mantou` | 饅頭 | OTHER | — | | 1 | 5 | 20 | 3 | restore food 20 | proposal |
| `c_water` | 清水 | OTHER | — | | 1 | 3 | 20 | 0 | restore water 30 | proposal |
| `c_baifan` | 白飯 | OTHER | — | | 1 | 8 | 20 | 3 | restore food 25 | proposal |
| `c_kaoyu` | 烤魚 | OTHER | — | | 1 | 15 | 20 | 3 | food 35、water 5 | proposal |
| `c_smoke` | 守護者之煙 | OTHER | — | | 1 | 5000 | 10 | 0 | smoke 300 | verified |
| `r_rabbitskin` | 兔皮 | MATERIAL | — | | 1 | 10 | 50 | 30 | | proposal |
| `r_bigrabbitskin` | 大兔皮 | MATERIAL | — | | 1 | 30 | 50 | 30 | 任務物品（`no_sell`） | verified |
| `r_wolfskin` | 狼皮 | MATERIAL | — | | 2 | 40 | 50 | 30 | | proposal |
| `r_pork` | 豬肉 | MATERIAL | — | | 2 | 20 | 50 | 3 | | proposal |
| `r_rice` | 米 | MATERIAL | — | | 1 | 6 | 99 | 30 | | proposal（GDD 9.5） |
| `r_wood` | 木材 | MATERIAL | — | | 2 | 5 | 99 | 0 | | proposal |
| `r_fish` | 魚 | MATERIAL | — | | 1 | 10 | 99 | 3 | | proposal |
| `t_chutou` | 鋤頭 | OTHER | — | | 3 | 40 | 1 | 0 | 種田工具 | proposal |
| `t_yugan` | 魚竿 | OTHER | — | | 2 | 40 | 1 | 0 | 釣魚工具 | proposal |
| `i_letter` | 驛站信函 | OTHER | — | | 0 | 0 | 1 | 0 | `quest_item`、`no_sell` | proposal |

### 5.5 武功與招式

| id | 名稱 | 門派 | 類別 | 基本武學 | 係數 | 招式（id 名稱 解鎖 威力 射程 內力；flavor） | src |
|---|---|---|---|---|---|---|---|
| `sl_changquan` | 少林長拳 | shaolin | FIST | basic_fist | 0.9 | sl_cq_1 黑虎掏心 1/20/1/0；sl_cq_2 雙龍搶珠 30/32/1/5；sl_cq_3 猛虎下山 60/44/1/10（`move_fist_basic`） | 武功 verified；招式 proposal |
| `sl_luohanquan` | 羅漢拳 | shaolin | FIST | basic_fist | 0.9 | sl_lhq_1 羅漢拜佛 1/21/1/0；sl_lhq_2 伏虎式 40/36/1/6（`move_fist_basic`） | 同上 |
| `sl_xinfa` | 少林心法 | shaolin | INNER | basic_inner | 0.9 | — | 同上 |
| `sl_shenfa` | 少林身法 | shaolin | LIGHTNESS | basic_body | 0.9 | — | 同上 |
| `sl_cibeidao` | 慈悲刀法 | shaolin | BLADE | basic_blade | 0.9 | sl_cbd_1 慈航普渡 1/22/1/0；sl_cbd_2 回頭是岸 35/34/1/6（`move_blade_basic`） | 同上 |
| `sl_luohanjian` | 羅漢劍法 | shaolin | SWORD | basic_sword | 0.9 | sl_lhj_1 金剛護法 1/22/1/0；sl_lhj_2 降魔一劍 35/34/1/6（`move_sword_basic`） | 同上 |
| `hs_xinfa` | 華山心法 | huashan | INNER | basic_inner | 0.9 | — | verified（武功存在） |
| `hs_jianfa` | 華山劍法 | huashan | SWORD | basic_sword | 0.8 | hs_jf_1 有鳳來儀 1/24/1/0；hs_jf_2 蒼松迎客 30/34/1/5；hs_jf_3 白虹貫日 60/46/1/10（`move_sword_basic`） | 係數 verified |
| `hs_pishiquan` | 劈石破玉拳 | huashan | FIST | basic_fist | 0.9 | 既有列保留；`requires` 加 `{quest_flag: "q_taogu_done"}`，M1 取不到（M3 桃谷六仙任務） | |
| `mon_bite` | 撕咬 | "" | FIST | basic_fist | 0.9 | mon_bite_1 撲咬 1/8/1/0（`move_bite`） | proposal，`monster_only` |
| `mon_claw` | 利爪 | "" | FIST | basic_fist | 0.9 | mon_claw_1 利爪撕扯 1/12/1/0（`move_claw`） | 同上 |
| `mon_ram` | 衝撞 | "" | FIST | basic_fist | 0.9 | mon_ram_1 猛衝 1/16/1/0（`move_ram`） | 同上 |
| `mon_blade` | 山賊刀法 | "" | BLADE | basic_blade | 0.9 | mon_blade_1 亂刀砍 1/20/1/0（`move_blade_basic`） | 同上 |
| `mon_ghost` | 陰風爪 | "" | FIST | basic_fist | 0.9 | mon_ghost_1 陰風爪 1/20/1/0（`move_ghost`） | 同上 |
| `mon_guiwang` | 鬼王掌 | "" | FIST | basic_fist | 0.9 | mon_guiwang_1 鬼王掌 1/30/1/0；mon_guiwang_2 攝魂 40/45/2/0（`move_ghost`） | 同上 |

所有門派武功的 `requires`：`[{ "type": "sect", "sect": <門派> }]`。少林初階師父的 masters 列另加 `{ "type": "skill_min", "skill": "foxa", "value": 10 }`【已證實：佛法 10】。所有招式 `aoe: "SINGLE"`、`status: ""`（劈石破玉除外）。

新增的 flavor 模板：`move_blade_basic`、`move_bite`、`move_claw`、`move_ram`、`move_ghost`。

### 5.6 基本武學、門派技能、生活技能

| id | 名稱 | curve | 係數 | 武館教（cap 30） | 每 10 級屬性 |
|---|---|---|---|---|---|
| `basic_blade` | 基本刀法 | CUBIC | 0.9 | ✓ | |
| `basic_sword` | 基本劍法 | CUBIC | 0.9 | ✓ | |
| `basic_whip` | 基本鞭法 | CUBIC | 0.9 | | |
| `basic_staff` | 基本棍法 | CUBIC | 0.9 | ✓ | |
| `basic_spear` | 基本槍法 | CUBIC | 0.9 | | |
| `basic_inner` | 基本內功 | QUARTIC | 0.8 | ✓ | con +1 |
| `basic_stab` | 基本刺術 | CUBIC | 0.9 | | |
| `basic_parry` | 拆招卸力 | CUBIC | 0.9 | ✓ | |
| `basic_fist` | 搏擊格鬥 | CUBIC | 0.9 | ✓ | str +1 |
| `basic_dodge` | 閃躲縱躍 | CUBIC | 0.9 | ✓ | agi +1 |
| `basic_body` | 基本身法 | CUBIC | 0.9 | ✓ | |
| `basic_formation` | 基本陣法 | CUBIC | 0.9 | | |
| `basic_poison` | 基本毒術 | CUBIC | 0.9 | | |
| `basic_medic` | 基本醫術 | CUBIC | 0.9 | | |
| `basic_hidden` | 基本暗器 | CUBIC | 0.9 | | |
| `basic_literacy` | 讀書識字 | LITERACY | — | ✓ | （悟性 +1 固定生效，4.2） |
| `basic_trade` | 交易之道 | CUBIC | 0.9 | | |

門派技能：`foxa` 佛法（少林，DEFENSE，消耗 精+內力）、`rufeng` 儒風（華山，RECOVER，消耗 精+內力）【已證實】；曲線 CUBIC 1.0、上限 100【設計提案】。

生活技能（`life_skills.json`）：

| id | 名稱 | feature | 工具 | 產出（成功時） | 教學 NPC |
|---|---|---|---|---|---|
| `life_farming` | 種田 | FIELD | t_chutou | r_rice ×1（chance 1.0） | 陶耘 |
| `life_woodcut` | 樵夫 | WOOD | w_chaidao | r_wood ×1–2 | 樵夫 |
| `life_fishing` | 釣魚 | WATER | t_yugan | r_fish ×1 | 漁夫 |
| `life_cooking` | 廚師 | STOVE | — | 食譜：`rc_baifan` 白飯（r_rice×1 → c_baifan×1，min 1）、`rc_kaoyu` 烤魚（r_fish×1 + r_wood×1 → c_kaoyu×1，min 5） | 西夏、大理客棧廚子 |

全部 `jing_cost` 5、`cooldown_s` 5、`cap` 100。少林菜園、竹林也可以耕作、砍柴（同樣需要學會與工具）。

### 5.7 任務

| id | 名稱 | 給予 | 步驟 | 獎勵 | repeatable | src |
|---|---|---|---|---|---|---|
| `q_rabbit` | 狩獵事件：大兔皮 | n_wujieshan | DELIVER n_wujieshan r_bigrabbitskin ×1 | 銀兩 100、學點 25【已證實 jyhj】 | 否 | verified（2001-08-17） |
| `q_rice` | 種稻 | n_taoyun | DELIVER n_taoyun r_rice ×5 | 銀兩 100、實戰 10、`skill_prof { life_farming: 10 }`【已證實 jyhj】 | 否 | verified |
| `q_letter` | 驛站送信 | n_xx_station | give_items i_letter ×1；DELIVER n_dl_station i_letter ×1（自己走西路 20 步送到） | 銀兩 100、名聲 2【已證實：送信加名聲】 | 是 | verified（功能）；數值 proposal（WORLD_2001 §5） |
| `q_letter_dl` | 驛站送信（大理） | n_dl_station | give_items i_letter ×1；DELIVER n_xx_station i_letter ×1 | 同上 | 是 | 同上 |
| `q_bandit` | 剿滅山賊 | n_dl_bukuai | KILL m_bandit ×3；TALK n_dl_bukuai | 銀兩 200、學點 30、善惡 +10 | 否 | proposal |
| `q_hs_kaoyan` | 岳不群的考驗 | n_yuebuqun | requires：no_sect、skill_min basic_inner 5、skill_min basic_literacy 5；KILL m_hs_trainee ×1；TALK n_yuebuqun | flags `hs_trial_passed` | 否 | 考驗【已證實】；內容 proposal |

驛站兩個送信任務的接取 NPC 不同；同一時間只能有一個進行中（各自 `quest_active` 檢查即可）。信要自己走到目的地驛站交（馬車預設關閉）；`STRICT_2001` 下死在路上，信跟著背包進屍體，可以回去撿或放棄重接。任務文字直接指路（WORLD_2001 §5.3）。

---

## 6. 測試計畫

### 6.1 各 WP 單元測試（`tests/unit/`，檔名前綴即擁有者）

| WP | 檔案 | 必測項目 |
|---|---|---|
| DATA | `test_data_loader.gd`（既有，維持綠燈）、`test_data_content.gd` | 真實資料載入 0 錯誤；`activate(["1.0A"])` 0 錯誤；純步行 BFS 可達性（71 間房；出生城彼此、每個門派與血刀洞迷宮都走得到）；`xx_square`→`gw_throne` 9 步經血刀洞口；東路、西路步數；1.0B 視圖有京城、1.0A 沒有；帶 era 的出口被篩掉；WORLD_2001 §1.4 新手安全規則；每個事件 key／err key 有模板；每個 NPC 房間一致；M1 所有 id（5.x 表）存在 |
| CHAR | `test_character_model.gd` | to_dict／from_dict 往返（含 float→int）；預設值補齊 |
| CHAR | `test_character_create.gd` | 擲骰 1000 次都在 [13,25]；`validate_alloc`（總和 4、6、負數、未知鍵）；`validate_name`；初始物品、裝備、學點、位置 |
| CHAR | `test_character_derived.gd` | 4.2 每條公式；裝備悟性 +2；讀書 10 級悟性 +1；`attr_from_basic_skills` 開關 |
| CHAR | `test_character_learning.gd` | 4.3 四種曲線（等級門檻值逐一比對 L=1,2,5,10）；悟性表（21/30/40 與內插）；4.5 驗證順序每個原因碼各一例；實戰上限；`times` 中途資源不足；學點上限；自修；16 套上限；生活技能學習與練習 |
| CHAR | `test_character_survival.gd` | 飽食飲水下降與門檻通知；飽食 0 回復 ×0.25；打坐（內力、修煉、冷卻、無內功）；運功；過量服藥；生日 |
| CHAR | `test_character_inventory.gd` | 疊加、300 件、超重、裝備換裝、卸下、腐壞、`take_all`、`take_equipped` |
| CHAR | `test_character_requirements.gd` | 3.11.1 每個 type 的通過與失敗 |
| CHAR | `test_character_death.gd` | 6.2 矩陣的 CHAR 部分 |
| BATTLE | `test_battle_formulas.gd` | 4.6–4.7 每條公式的數值例（含出力 120 精熟補正、兵器修正、防禦姿態） |
| BATTLE | `test_battle_flow.gd` | 狀態機；等待模式暫停與逾時自動防；10.7 逾時縮短、每輪預算、afk；非等待模式；同 tick 排序；勝負判定；MAX_TICKS → ABORTED |
| BATTLE | `test_battle_commands.gd` | 3.4.3 每個 cmd 的合法與每個原因碼 |
| BATTLE | `test_battle_replay.gd` | `tests/fixtures/battle_golden_01.json`：種子 + 規格 + 指令序列 → 事件序列（以 JSON 字串比對）完全相同；同輸入跑兩次結果相同 |
| BATTLE | `test_battle_rewards.gd` | 4.8 公式；分享係數；掉落歸屬；逃走怪物不給；DEFEAT 空結果 |
| BATTLE | `test_battle_encounter.gd` | 固定種子重現；權重；煙 ×0.1；數量上限 4；`monster_spec` 形狀 |
| WORLD | `test_world_server.gd`（既有，維持綠燈） | |
| WORLD | `test_protocol_m1.gd` | 3.6 每個 intent 的型別與範圍驗證 |
| WORLD | `test_world_chars.gd` | 擲骰→創角→自動選角；名稱重複；第 4 個角色被拒；刪除；`stop()`→`start()` 後角色完整；`welcome.your_characters` |
| WORLD | `test_world_move.gd` | 移動、`no_exit`、`room_locked`（非華山弟子進正氣堂）、驛站馬車預設關閉（`stagecoach_disabled`）、打開時扣錢、西夏走到大理、舊存檔搬家（`relocated`、`respawn_reset`）、夜間打烊（把世界時間撥到戌時）、REACH 任務 |
| WORLD | `test_world_npc.gd` | 商店買賣（收購 30%）、教學（含佛法 10 門檻）、拜入（女性拜少林 `req_gender`；華山缺考驗 `req_quest_flag`）、客棧、記錄點、齋食時辰 |
| WORLD | `test_world_quest.gd` | 5.7 每個任務完整流程；放棄收回任務物品 |
| WORLD | `test_world_battle.gd` | 遇敵 → 開戰 → 送 `s2c_battle_open` → 以 `battle_cmd` 打贏 → 獎勵入帳、KILL 任務計數、角色表更新；逃跑無獎勵 |
| WORLD | `test_world_death.gd` | 6.2 矩陣（整合） |
| WORLD | `test_world_life.gd` | 4 種生活技能：學習（拿到工具）、`no_feature`、`no_tool`、冷卻、產出、廚師食譜 |
| UI | `test_ui_text_renderer.gd` | UI-only 事件不顯示；self／target／other 選擇；`render_reason` 查表規則 |
| UI | `test_ui_scenes.gd` | 每個 `ui/game/**/*.tscn` 都能 instantiate、加進樹、餵假資料（假 sheet、view、battle_state、事件）後一幀內無錯誤，再釋放 |

### 6.2 死亡規則測試矩陣

固定一個角色：實戰 2000、特殊武功 少林長拳 20、羅漢拳 15、基本內功 10、佛法 12、生活技能 種田 5；背包 精藥水 ×3、大兔皮 ×1；裝備 木刀、布衣；銀兩 1000。另一個新手角色：實戰 300，其餘同上。

| 預設組合 | 角色 | 預期 |
|---|---|---|
| `classic_strict` | 老手 | 長拳 19、羅漢拳 14、基本內功 9、佛法 11、種田 5（不變）；背包＋裝備全部進屍體；銀兩 1000；屍體在死亡房間；`death_strict` |
| `classic_strict` | 新手 | 同上規則（2001 規則沒有新手保護） |
| `classic_standard` | 老手 | 只有長拳 → 19；其他不變；木刀、布衣進屍體，背包留身上；銀兩 1000；`corpse_window` = CLASSIC_30 |
| `classic_standard` | 新手 | 完全不變；不建立屍體；`death_standard_safe` |
| `later_official` | 老手 | 同 classic_standard 老手；`corpse_window` = LATER_10 |
| `friends_casual` | 老手 | 武功不變；物品不變；銀兩 900；沒有屍體；`death_casual` |
| 全部 | 全部 | 重生到記錄點（有設）或出生房間（沒設）；精氣神 50%、內力 0；`dead_count` +1；本人可 `loot_corpse` 拿回（放不下的留著）；1800 秒後屍體消失並送 `corpse_expired` |

`test_world_death.gd` 用 `GameData.activate(["1.0A"], {"preset": <組合>})` 切換規則，再讓角色與 `m_guiwang`（`fight`）開戰並以 DEFEND 撐到死亡（或直接把角色氣設為 2 再開戰）。

### 6.3 平衡模擬（`tools/balance_sim.gd`）

參考角色（全部空手時用 FIST；有武器照列）：

| 代號 | 有效屬性 | 技能 | 裝備 | 實戰 | 氣上限 |
|---|---|---|---|---|---|
| P0 | 臂 20、膽 19、悟 21、福 19、定 19、機 20、根 20 | 無 | 木刀、布衣 | 0 | 180 |
| P1 | 同 P0 | 佛法 10、少林長拳 10、搏擊格鬥 10、基本內功 5、拆招卸力 5、閃躲縱躍 5 | 布衣（空手出拳） | 500 | 180 + 10 次修煉 = 260 |
| P2 | 同 P0 | 佛法 30、少林長拳 35、搏擊格鬥 35、基本內功 30、拆招卸力 30、閃躲縱躍 30、少林身法 20、基本身法 20 | 粗布道袍（空手） | 10000 | 180 + 60 次修煉 = 660 |
| P3 | 同 P0 | 各項 40（長拳、搏擊、內功、拆招、閃躲、身法），佛法 40 | 皮甲（空手） | 15000 | 180 + 100 次修煉 = 980 |

| 案例 | 通過條件（`--runs=500`） |
|---|---|
「勝」＝`VICTORY`（含敵人全部逃走，那種勝利沒有任何獎勵）；「擊殺」＝怪物真的被打死（才有實戰、學點、掉落）。新手案例一律看擊殺率。

| 案例 | 通過條件（`--runs=500`） |
|---|---|
| `newbie_vs_rabbit`（P0 vs m_rabbit） | P0 每次命中的平均傷害 ∈ [8, 16]【GDD 5.6 校準目標 8–15，放寬 1】；勝率 ≥ 95%；擊殺率 ≥ 80% |
| `newbie_str14_vs_rabbit`（P0、臂力 14） | 擊殺率 ≥ 60%（低臂力擲骰也要能練） |
| `newbie_vs_bigrabbit`（P0 vs m_bigrabbit） | 擊殺率 ∈ [50%, 95%] |
| `newbie_vs_wolf`、`newbie_vs_boar`（P0） | 勝率 ≤ 10%：野狼、山豬不得放在出生點與新手生活點（砍柴、釣魚、種田）附近，必經路上權重 ≤ 10 |
| `p1_vs_wolf` | 勝率 ≥ 80% |
| `p1_vs_boar` | 擊殺率 ∈ [55%, 80%]（P1→P2 的主要練功對象） |
| `p1_vs_bandit` | 勝率 ≤ 40%（山賊對 P1 仍危險） |
| `p2_vs_ghost` | 勝率 ≥ 70%；勝場平均剩餘氣 ≥ 25% |
| `newbie_vs_ghost`（P0） | 勝率 ≤ 5% |
| `p3_vs_guiwang` | 勝率 ∈ [40%, 90%] |

輸出每案例一行（勝率、擊殺率、平均回合、平均傷害、平均剩餘氣），任一案例不通過 → 結束碼 1。整合階段由 WP-DATA 調 `monsters.json` 直到全過。

**P1 → P2 估算**（4.8 的獎勵比例，只打山豬）：實戰 500 → 10,000 約需 1,560 隻山豬、得約 5,700 學點；P2 的技能組合（悟性 21、每次 11 熟練度）約需 17,000 學點，差距約 3 倍。這個缺口（加可重複的學點任務、或調整學點來源）留給 M1 平衡收尾時由擁有者決定，目標時數待定。

### 6.4 驗收 playthrough（`tests/bots/m1_playthrough_bot.gd`）

執行：

```bash
"$G" --headless --path . -- --no-steam --offline --world=m1_accept --profile=m1bot \
     --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
```

世界照原作 2001 地理（WORLD_2001 §9.3）：城市之間全部走路，`_graph()` 只在 `world_info.stagecoach_enabled` 時才加驛站邊；`_nearest_inn()` 找最近有 INN 服務的房間（客棧、茶棚、綠洲）。

規則：bot 是 `extends Node`（同 `chat_bot.gd` 的掛法），只透過 `NetworkManager.send_intent()` 與 `ClientState` 的訊號／欄位互動；**一次只送一個 intent，等到同 seq 的 `intent_result` 再送下一個**（避免觸發 20/秒 速率限制）；每一步有斷言，失敗時印出 `M1_ACCEPT_FAIL step=<n> <原因>` 並以結束碼 2 結束；成功印 `M1_ACCEPT_OK` 並以 0 結束；逾時由 `--quit-after` 以 1 結束。戰鬥中的決策：收到 `battle_await` 且含自己 → 有相鄰敵人就攻擊（會少林長拳後改用 ART 黑虎掏心 10 成）；否則 MOVE 到最接近敵人的可達格；自己氣 < 25% 且站在逃跑格上 → FLEE。

| 步驟 | 動作 | 斷言 |
|---|---|---|
| 1 | 等 `ClientState.in_world`；`char_list`；刪除此 identity 既有的全部角色 | 清單為空 |
| 2 | `char_roll` | `char_rolled` 七項都在 [13,25] |
| 3 | `char_create`（名「驗收俠客」、M、3 月、xixia、alloc {wit:5}） | sheet：位置 `xx_square`；學點 100；銀兩 100；c_jingyao ×5；木刀、布衣已裝備；`welcome`／`char_list` 有 1 個角色 |
| 4 | `char_create` 以京城出生（另一個名字） | 失敗 `bad_value:birth_city` |
| 5 | `talk n_wujieshan` → `quest_accept q_rabbit` | sheet.quests 含 q_rabbit |
| 6 | `move E` → `talk n_xx_cha` → `set_respawn n_xx_cha` | respawn = xx_gate_e |
| 7 | 練功迴圈：在 `xw_road`↔`xw_grass`↔`xw_hill` 之間來回移動踩地雷並戰鬥；氣 < 50% 時回 `xx_inn` 用 `inn_rest`（錢不夠就用打坐／自然回復等待）；直到 實戰 ≥ 250 **且** 背包有 r_bigrabbitskin | 至少 1 場 VICTORY；`battle_reward` 實戰 > 0；曾出現 m_rabbit 與 m_bigrabbit 的擊殺 |
| 8 | 回 `xx_square`：`quest_turn_in n_wujieshan q_rabbit` | 銀兩 +100、學點 +25、`q_rabbit` 在 quests_done |
| 9 | `xw_creek`：`learn n_xw_fisher life_fishing` → `work life_fishing` ×3（等冷卻） | 拿到 t_yugan；種田以外的生活技能熟練度 > 0 |
| 10 | `xx_station`：`quest_accept q_letter`；`travel n_xx_station dl_station` 預期 `stagecoach_disabled`；走到 `dl_station`；`quest_turn_in n_dl_station q_letter`（`STRICT_2001` 下死在路上丟了信：`quest_abandon`、回西夏重接） | 位置 dl_station；路上經過 `de_oasis`；`reward` 事件 money = 100、fame = 2；名聲 +2 |
| 11 | `dlw_paddy`：`learn n_taoyun life_farming`；`quest_accept q_rice`；`work life_farming` 直到 r_rice ≥ 6；`quest_turn_in n_taoyun q_rice` | q_rice 完成；種田熟練度增加 |
| 12 | `dl_inn`：`learn n_dl_cook life_cooking`；`work life_cooking rc_baifan`；`use_item` 白飯 | 飽食增加（或已滿時不減） |
| 13 | `dl_station`：`quest_accept q_letter_dl`，走回 `xx_station` 交信 | 同第 10 步 |
| 14 | 走到 `sl_gate`（東路） | 路上經過 `hf_teahouse`、`hy_foot`、`sy_teahouse`；不經過任何 `jc_*`／`jcw_*` |
| 15 | `set_respawn n_sl_cha`；`join_sect n_sl_zhike` | sect = shaolin；`sect_join` 事件 |
| 16 | `learn n_sl_huizhen sl_changquan` | 失敗 `req_skill_min`（佛法未達 10） |
| 17 | `learn n_sl_huizhen basic_inner` ×（times 5）直到等級 ≥ 2 | 基本內功 ≥ 2；內力上限 ≥ 10 |
| 18 | 反覆 `learn n_sl_zhike foxa`（times 10）；精不足時用 c_jingyao 或等待回復；內力不足時 `meditate`；直到佛法 10 | 佛法 = 10；學點有減少 |
| 19 | `learn n_sl_huizhen sl_changquan` 直到等級 ≥ 1 | 會少林長拳；sheet.special_arts = 1 |
| 20 | `sl_zhaitang`：若目前是卯、午、酉時則 `meal`，否則斷言 `meal` 回 `not_meal_time` | 符合時辰規則 |
| 21 | 從少林走回西夏東北，經血刀洞口 `xe_xuedao` 進 `gw_entrance`（途中遇敵照常戰鬥；若死亡則從記錄點重走） | 經過 `xe_xuedao`；位置 region = guiwang |
| 22 | 在 `gw_entrance` 至少打一場（移動 `N`／`S` 來回直到遇敵）；至少一場戰鬥中用過 ART（黑虎掏心） | 戰鬥結束；若死亡：依世界的 death_rule（STANDARD：實戰 > 500 時長拳降 1 級、≤ 500 時無損失；STRICT_2001：降 1 級；CASUAL：不降）、重生於 sl_gate |
| 23 | 【整合補】死亡規則：在 `gw_entrance` 遇敵後只送 DEFEND 撐到死亡（最多 6 場）；可用 `--bot-expect-rule` 斷言世界規則；三種預設各跑一次（`--rule-preset=classic_standard／classic_strict／friends_casual`，各用新世界） | 重生於 sl_gate、內力 0；STRICT_2001：每門非生活技能 −1、背包清空、`death_strict`；STANDARD 老手：恰好降 1 級、裝備離身、`death_standard`；STANDARD 新手：無損失、`death_standard_safe`；CASUAL：武功物品不變、銀兩 −10%、`death_casual` |
| 24 | `char_select` 自己（重新進入）；斷言角色檔存在於 `user://worlds/m1_accept/characters/<identity>/` | 檔案可讀、`schema_version == 1`（ENet 客戶端只檢查重選成功） |
| 25 | 印 `M1_ACCEPT_OK`，`SceneRouter.quit(0)` | 結束碼 0 |

> 執行後用 `tasklist /FI "IMAGENAME eq Godot*"` 確認沒有殘留程序（G7）。

### 6.5 UI 手動檢查清單（A7）

- [ ] 無參數啟動 → 標題畫面；Steam 沒開時 Steam 按鈕灰色並顯示原因。
- [ ] 單機遊玩 → 角色選擇（空）→ 創角：擲骰、分配 5 點、生日、出生城 → 進入主畫面。
- [ ] 主畫面顯示房名、時辰、描述、出口、NPC；點出口能移動；訊息紀錄有進出房間文字。
- [ ] 對武介山對話 → NPC 對話框 → 接任務；任務面板出現。
- [ ] 郊外遇敵 → 戰鬥畫面：12×8 格、黃色逃跑格、時間棒會動、等待模式下輪到我時指令列亮起；移／攻／武（成數滑桿）／防／休／裝／逃都能用；戰報有文字。
- [ ] 戰鬥結束顯示獎勵並回到主畫面；狀態列數值更新。
- [ ] 屬性、武功、背包（四分頁、負重、裝備）、任務面板都正確；Ctrl+1–5、Esc 可用。
- [ ] 商店買賣、客棧休息、查小鏞記錄、驛站送信（走路把信送到大理；馬車只在伺服器選項打開時）、少林拜師、學武對話框（灰色項目顯示原因）。
- [ ] 失敗的操作在訊息紀錄顯示中文原因。
- [ ] 關閉遊戲（主機存檔）後重開 → 角色仍在、位置與物品正確。

---

## 7. 風險與待決

| # | 項目 | 處理 |
|---|---|---|
| R1 | 熟練度累計解讀（D5）若與原作體感不符 | 曲線只在 `basic_skills.curve`／`difficulty` 與 `SkillBook` 的四個函式中；M4 平衡時再調 |
| R2 | GDD 5.6 公式的線性成長使高階怪物需要偏高的防具強度（D6） | 數值全在 `monsters.json`；balance_sim 為準 |
| R3 | 少林入門 NPC、佛法教授者、基本武學師父的原作名單未考證 | 以 `知客僧`、`慧真` 代替，`src: proposal`；查到後只改資料 |
| R4 | 驗收 bot 依賴隨機遇敵，耗時不固定 | `--time-scale=50`、`--quit-after=1800`；bot 內每個迴圈有次數上限並在逾時前報告卡在哪一步 |
| R5 | 新增 class_name 需要重新匯入才會被 `--script` 模式辨識 | G8；`run_tests.gd` 前一律先 `--import` |
| R6 | 等待模式在連線下的 8 人節奏 | 純邏輯已在 M1 實作與單元測試；實際 8 bot 測量在 M2 |
