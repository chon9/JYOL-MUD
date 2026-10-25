# 江湖試煉（肉鴿模式）實作計畫（ROGUE_PLAN）

> 版本：2026-10-22（開工版）。協調者撰寫；實作中只由協調者（整合者）修改本文件。
> 上游：擁有者 2026-10-22 的請求（每回合選一張：兵器、武功、屬性點或隊友 → 打一場能力相當的對手 → 打到死 → 獎勵永久的初始屬性點；屬性點永久，武功、兵器、裝備、隊友每局歸零）。
> 慣例：沿用 M3D_PLAN §0 的寫法與 G／H／K／L／N／Q／T 全域規則。本模式整個是【設計提案・非原作】：原作沒有肉鴿模式，資料列一律 `src: "proposal"`。
> 基準版本：0.7.0.2（`Protocol.VERSION` 5）。目標版本：0.7.1.0。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

江湖試煉由 3 個工作包（WP-RUN、WP-ALLY、WP-UI）**同時**在同一個工作目錄實作，最後由整合者驗收。實作者之間不溝通。

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent 參數、事件 key、原因碼、資料列 id 與前綴、檔名、房間 id、opts 鍵**都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定（版面細節、函式內部結構、卡面文字的措辭）。
3. 優先順序：本文件 > M3D_PLAN > M3C2_PLAN > 更早的計畫 > GDD > TECH_ARCH。
4. 發現缺漏：照「最不意外」實作，程式裡寫 `# ROGUE_PLAN 缺漏：……`，交付說明列出；**不要**改別人的檔案（共用熱檔照 §8.2 切分）。
5. 依賴別的 WP 的東西一律照本文件的簽名寫，並且**容忍對方還沒完成**：主機端用 `host.m2_call(host.get("rogue"), "<方法>", [...], <預設>)`；core 端用 `ResourceLoader.exists("res://core/rogue/<檔>.gd")` 後 `load()`；查不到資料列就略過。三個 WP 必須能各自通過自己的測試。

### 0.2 標記

GDD 第 0 章的標記照用。本模式所有新資料列：`"era": "rogue"`、`"src": "proposal"`；`src_note` 寫「江湖試煉【設計提案・非原作】」，借用原作人物時加上人物出處（例：「令狐沖（笑傲江湖）；數值與招式組合【設計提案】」）。

### 0.3 全域規則（本計畫另加 U1–U12；舊規則全部繼續有效）

| # | 規則 |
|---|---|
| U1 | **只做本文件的範圍**（§1.1）。不順手改 MUD 的平衡、文字或介面。 |
| U2 | **擁有者說了「別再開視窗測試」**：Godot 一律 `--headless`；**絕不**開有視窗的 Godot，也**絕不**執行匯出的 exe。介面驗收只跑 headless 的 `ui_playthrough`。 |
| U3 | **只能結束自己開的行程**：用 PID，而且先確認那個 PID 的命令列含有你自己的參數（例如 `--script res://tools/rogue_acceptance.gd`）。**不准**用名字結束行程（`taskkill /IM`、`Stop-Process -Name`），擁有者可能正在玩 `JY-Mini OL.exe`。 |
| U4 | **不寫 C:**。log → `K:\Project\JY-Mini-OL-Work\logs\`，暫存 → `K:\Project\JY-Mini-OL-Work\tmp\`。**絕不碰** `K:\Project\JY-Mini-OL-Release\userdata\`、`K:\Project\JY-Mini-OL-Work\userdata\`、`K:\Project\JY-Mini-OL-Work\share\`。測試、bot、驗收只用 `K:\Project\JY-Mini-OL-Work\testdata\`（`DataRoot.test_root()`）。 |
| U5 | **不刪任何東西**（`K:\Project\JY-Mini-OL-Work\tmp` 以外）。**不 git commit、不 push**。 |
| U6 | 玩家看得到的文字只用**繁體中文**、遊戲內名稱，**不用表情符號**。不在玩家文字裡留開發標記（`0.7.0.1` 的 data_lint 檢查會擋）。 |
| U7 | `Protocol.VERSION` **維持 5**：只新增 intent、可選參數、事件、原因碼、戰鬥 kind、快照欄位；RPC 簽名不變。資料指紋（`content_hash`）會變 → 朋友要一起更新（照舊）。 |
| U8 | **一個檔案只有一個擁有者**（§8.1）；共用熱檔照 §8.2 切到具名區塊。區塊標記：檔尾 `# ==== ROGUE WP-<名> ====`，單行鉤子行尾 `# ROGUE WP-<名>`。 |
| U9 | **共用 JSON**（同 M3d T3）：只用 Edit 工具局部取代、每次 Edit 前重新 Read，不整檔重寫、不重新排版、不用 `json.dump`。新列插在檔尾 `\n  ]\n}` 之前。 |
| U10 | **MUD 完全不受影響**：試煉的資料列全部 `era: "rogue"`，MUD 世界永遠不會啟用這個 era（§2.2）；試煉世界不寫任何世界檔、角色檔、護照；永久點數只存在 `<資料根目錄>/rogue/profile.json`，**只**影響試煉開局的屬性分配，**絕不**影響 MUD 角色或世界。 |
| U11 | **決定性**：同一個 run 種子＋同一串選擇＝同樣的抽卡與同樣的對手組合（戰鬥本身另有種子，見 §3.7.5）。所有亂數走具名的 `RandomNumberGenerator`，不用全域 `randi()`。 |
| U12 | **凍結檔**（§8.4）任何 WP 都不得修改；戰鬥公式只能**讀**。 |

### 0.4 Godot 指令（一律 headless）

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
export APPDATA="K:/Project/JY-Mini-OL-Work/godot_home"
"$G" --headless --path . --import                                   # 新增 class_name 之後先跑
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=rogue]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=200 --case=rogue_first_runs
"$G" --headless --path . --script res://tools/rogue_acceptance.gd -- --no-steam [--only=start_run,lose_run]
"$G" --headless --path . --script res://tests/ui/ui_playthrough.gd -- --no-steam               # 只跑 headless（U2）
# 回歸照 M3D_PLAN §0.4 的其餘指令（M1 bot、m2/m3a/m3b/m3c/m3c2/m3d 驗收、story_acceptance --all、net_smoke）
```

`balance_sim` 全部案例太慢時用 `--case=` 分批跑。計時測試（`test_rate_limit`、`test_view_blade_hit_on_wolf`）偶發失敗：先單獨重跑。

### 0.5 開工前讀程式碼量到的現況（協調者 2026-10-22）

| 項目 | 現況 | 出處 |
|---|---|---|
| 離線主機 | `NetworkManager.start_offline(world)` → `WorldServer.start(world)`（讀／建 `worlds/<id>/world.json`、`options.json`）→ `GameHost.new(ws)` 建全部子系統、註冊 intent → `ClientState.begin_local_session()` → welcome | `autoload/network_manager.gd:114`、`autoload/world_server.gd:76` |
| 存檔時機 | `WorldServer._process` 每 `autosave_interval_s` 呼叫 `save_now()`（`game.save_all()` 存在線角色＋`world.json`）與 `game.on_autosave()`（寫護照）；`stop()` 也存 | `world_server.gd:240,278,400` |
| era 篩選 | 每一列有 `era`；`GameData.activate(enabled_eras)` 只留 `on.has(row.era)` 的列；地圖檔也一樣 | `core/data/data_loader.gd:145,213` |
| 新資料表 | `DataLoader.FILES`／`OPTIONAL_FILES` 列名的檔才會載入 | `data_loader.gd:5,15` |
| 創角 | `CharacterFactory.roll`：每項 9＋4d4（13–25）；`FREE_POINTS` 5；起始物品 精藥×5、布衣、木刀 | `core/character/character_factory.gd` |
| 衍生數值 | 氣上限 60＋根骨×6；內力上限＝基本內功×5；身法＝LIGHTNESS 最高等級 | `core/character/derived_stats.gd`（凍結） |
| 戰鬥單位 | `BattleUnit.kind()` 讀 `spec.kind`（預設 MONSTER）；`is_ai()`＝`peer == 0` 或有 `spec.ai`；`side` 0／1 | `core/battle/battle_unit.gd` |
| 怪物 AI | `BattleAI._enemies` 已經用 `e.side != u.side` → **本來就分邊**；非玩家只用 `arts[0]`；`coward` 會逃 | `core/battle/battle_ai.gd` |
| 勝負判定 | `_check_end`：side 0 還有任何活人（含 AI）就繼續；side 0 全倒且有人死 → DEFEAT | `core/battle/battle.gd:503` |
| 開戰 API | `BattleSystem.start_ex(s, monster_ids, kind, opts)`：side 0 只放玩家（可拉隊友），side 1 用 `Encounter.monster_specs(ids)`；`opts.no_flee`；戰鬥種子 `host.rng.randi()` | `server/battle_system.gd:67` |
| 結算 | `_finish`：非 PvP 勝利算獎勵；`_settle_player`：`apply_battle_outcome`、獎勵、任務、`handle_death`（死亡懲罰）、`deliver_battle_close`、`save_char` | `battle_system.gd:538,663` |
| NPC 當戰鬥單位 | `_npc_unit_spec`：`ref`＝NPC id（立繪）、`monster_row`＝數值列、`name`＝NPC 名 → 戰鬥畫面用 NPC 立繪 | `battle_system.gd:120` |
| 戰鬥畫面分邊 | `BattleViewModel.is_enemy(uid)`＝`side != my_side`；名字顏色 `NAME_ALLY`／`NAME_ENEMY`；精靈朝向依 `side == my_side` | `ui/game/battle/battle_view_model.gd:186`、`battle_screen.gd:316`、`battle_iso_view.gd:279` |
| 戰鬥畫面宿主 | `main_screen.open_battle(state)` 在 `battle_opened` 時實例化 `battle_screen.tscn`、`setup(state)`；`battle_closed` → `show_result`；`finished` 訊號收起 | `ui/game/main/main_screen.gd:879` |
| 名人資料 | 有 NPC 列＋立繪：令狐沖 `n_hs_linghuchong`、喬峰 `n_xx_qiaofeng`、虛竹 `n_xx_xuzhu`、張無忌 `n_zhangwuji`、周芷若 `n_em_zhouzhiruo`、小龍女 `n_gm_xiaolongnu`、張三丰 `n_wd_zhangsanfeng`、岳不群 `n_yuebuqun`、滅絕師太 `n_em_miejue`、丘處機 `n_qz_qiuchuji`、天山童姥 `n_lj_tonglao`、丁春秋 `n_xh_dingchunqiu`、血刀老祖 `n_xd_laozu`、胡斐 `n_ym_hufei`、李莫愁 `n_dl_limochou`、葉二娘 `n_yeerniang`、南海鱷神 `n_nanhai`；郭靖 `n_er_guojing`（1.0B，**沒有立繪**）。有戰鬥數值列：`m_npc_dingchunqiu`、`m_npc_xd_laozu`、`m_dl_limochou`、`m_yeerniang`、`m_nanhai`、`m_em_hufei`、`m_em_zhouzhiruo`、`m_wd_zhangsongxi`、`m_wd_yulianzhou`、`m_qz_yangkang`、`m_gm_hongningbo` | `data/npcs.json`、`data/monsters.json`、`data/art.json` |
| 物品稀有度 | `items.rarity` ∈ COMMON FINE RARE TREASURE DIVINE（缺省 COMMON）；顏色與裝飾名在 `LootUi` | `core/data/data_schema.gd:281` |
| 隊友系統 | 只有玩家隊伍（PartySystem）；**沒有** AI 隊友。本計畫的「隊友」＝戰鬥中由 AI 控制、站在玩家這一邊的單位（WP-ALLY） | — |

---

## 1. 範圍

### 1.1 要做（括號是負責 WP）

- [ ] R1 試煉世界：記憶體內的臨時世界（不寫任何檔），只開 era `rogue`＋1.0A＋1.0B；單機（RUN）。§2
- [ ] R2 標題畫面「江湖試煉」按鈕，在「單機遊玩」旁邊（UI）。§5.1
- [ ] R3 試煉者檔案 `<資料根目錄>/rogue/profile.json`：永久點數、戰績、名人錄（RUN 寫、UI 讀）。§3.9
- [ ] R4 開局：擲屬性＋5 點自由點＋永久點數，玩家自己分配；布衣、木刀、沒有武功（RUN、UI）。§3.3
- [ ] R5 每回合 3 張卡，從 武功／兵器／屬性／隊友 四種裡加權抽，有稀有度；選一張（RUN、UI）。§3.4、§3.5
- [ ] R6 戰力分數與對手生成：依回合曲線與我方戰力出一組對手，每 5 回合一位名人首領（RUN）。§3.6、§3.7
- [ ] R7 回合之間部分回復（RUN）。§3.8
- [ ] R8 AI 隊友：從 NPC／怪物列生成、站在玩家這邊自動打、最多 2 位、死了這一局就沒了（ALLY）。§4
- [ ] R9 戰鬥畫面支援隊友單位（名牌、氣條、朝向、指令目標、結果框）（ALLY）。§4.6
- [ ] R10 死亡（或放棄）→ 結算畫面：撐過幾回合、擊敗幾名對手、最好的一張卡、得到幾點永久點數（RUN、UI）。§3.9、§5.5
- [ ] R11 局內 HUD：回合、隊友、兵器與裝備、武功（UI）。§5.4
- [ ] R12 `balance_sim` 新案例與數字（RUN、ALLY）。§9.2
- [ ] R13 `tools/rogue_acceptance.gd` 的劇本（整合者）。§9.3

### 1.2 不做

- 多人合作試煉（擁有者決定 b：先做單機；但資料結構與 intent 都照「一局可以有多位成員」設計，§2.5）。
- 局中存檔與續玩（關掉遊戲＝這一局以「放棄」結算，§3.9.4）。
- 商店、金錢、消耗品、學點、師父、地圖移動、任務、遇敵表。
- 新美術（缺圖的名人用別名或程序化後備，列進交付說明）。

### 1.3 擁有者決定（擁有者已預先授權；以下是選定的預設值，建造者照做）

| # | 決定 | 內容 |
|---|---|---|
| O1 | 永久點數歸屬（擁有者 a） | 屬於「試煉者」檔案，**只**在試煉開局時加到可分配點數；永不影響 MUD 角色或世界。 |
| O2 | 先單機（擁有者 b） | v1 只接受本機 peer（遠端 → `rogue_solo_only`）；`RogueRun.members` 是陣列，以後合作再開。 |
| O3 | 人物來源（擁有者 c） | 隊友與對手用資料裡已有的金庸人物（NPC 立繪＋既有或新增的數值列）、門派弟子、怪物；每 5 回合一位名人首領。 |
| O4 | 試煉世界 | 記憶體內的臨時世界，用既有的 `WorldServer`＋`GameHost`（戰鬥畫面、intent、主機權威全部沿用）；**不寫** `worlds/`、`passports/`。 |
| O5 | 永久資料的隔離方式 | 新 era `rogue`（`requires: ["1.0B"]`、`mode_only: true`）：所有試煉資料列只在試煉世界生效；MUD 世界拒絕啟用它。 |
| O6 | 玩家倒下＝這一局結束 | 試煉戰鬥裡只要我方**所有玩家單位**都倒下就判負（隊友還活著也一樣）。理由：擁有者說「一直到死」；隊友不能代打。 |
| O7 | 不能逃 | 試煉戰鬥 `no_flee`。放棄只能在兩場之間按「放棄試煉」。 |
| O8 | 沒有經驗、金錢、掉落、死亡懲罰 | 試煉戰鬥不發 `BattleRewards`、不呼叫 `handle_death`。 |
| O9 | 卡片種類 | 「兵器」卡也包含護具（擁有者說的「裝備」）；「武功」卡也包含基本武學（基本內功、閃躲縱躍等）。 |
| O10 | 屬性卡 | 給 N 點，由玩家自己分配到七項屬性。 |
| O11 | 每局屬性上限 | 單項屬性在試煉中最多 45（擲骰＋自由點＋永久點數＋屬性卡）。 |
| O12 | 永久點數上限 | 終身 60 點；每局所得有遞減（§3.9.2）。 |
| O13 | 回復規則 | 每贏一場回復最大值的 35%（氣、精、神）與 50%（內力）；打贏首領全滿；飽食、飲水每回合補滿。 |
| O14 | 首領獎勵 | 打贏首領後多一次選卡，而且那一次三張都至少「稀」。 |
| O15 | 版本 | 0.7.1.0；`Protocol.VERSION` 5。 |

### 1.4 與 GDD／既有文件的偏差（整合者同步）

- GDD 新增一節「江湖試煉【設計提案・非原作】」（整合者依本文件 §2–§5 摘要）。
- TECH_ARCH 新增「臨時世界（ephemeral world）」與「模式專用 era」兩段（整合者）。
- `docs/攻略.md` 新增一章（整合者）。

---

## 2. 架構

### 2.1 流程

```
標題「江湖試煉」→ SceneRouter.goto("rogue")（RogueScreen 的 LOBBY：讀 profile.json 顯示戰績）
  →「開始試煉」→ NetworkManager.start_rogue(seed) → WorldServer.start_rogue(seed)
       （記憶體世界 _rogue、enabled_eras = 1.0A,1.0B,rogue、ephemeral = true）→ GameHost（含 host.rogue）
  → welcome → RogueScreen 送 rogue_open → rogue_state(phase=ALLOC, roll, alloc_points)
  → rogue_start{alloc,name,gender,look} → 建角色、進 rg_hall → rogue_state(phase=PICK, cards×3)
  → rogue_pick{idx[,alloc]} → rogue_state(phase=READY) →（可在 HUD 換裝：既有 equip／unequip）
  → rogue_fight → BattleSystem.start_ex(kind=ROGUE, foe_specs, ally_specs) → battle_opened（RogueScreen 疊戰鬥畫面）
  → 勝：rogue_round_won、回復 → rogue_state(phase=PICK, round+1)（打贏首領：先多一次 PICK）
  → 敗／放棄：rogue_over(summary) → 寫 profile.json → rogue_state(phase=OVER)
  →「再戰一場」= rogue_open（同一個試煉世界重開一局）；「返回標題」= NetworkManager.leave() → title
```

### 2.2 試煉世界（WP-RUN）

- `WorldServer.start_rogue(seed: int = 0) -> Error`（新函式；`world_server.gd` 的 `# ==== ROGUE WP-RUN ====` 區塊）：
  - `options = GameData.default_server_options()`，再覆寫 `ROGUE_OPTIONS := { "encounters_enabled": false, "guards_enabled": false, "pk_mode": "OFF", "wait_mode": true, "autosave_interval_s": 999999, "scout_enabled": false, "rumors_enabled": false, "wanderers_enabled": false, "enabled_eras": ["1.0A", "1.0B", "rogue"] }`（鍵不存在於預設選項的略過）。
  - `world = SaveManager.new_world("_rogue", "江湖試煉", GameData.content_hash, options)`（純函式，不寫檔）；`world["mode"] = "ROGUE"`；`world["rogue_seed"] = seed`。
  - `var ephemeral := true`（新欄位，預設 false）；`GameData.activate(world.enabled_eras, world.rule_profile)`；其餘同 `start()` 的尾段（rng、sessions、`_create_game()`、`started.emit`），**不呼叫** `save_now()`、`SaveManager.save_options()`。
  - `save_now()` 開頭：`if ephemeral: return OK   # ROGUE WP-RUN`；`_process` 的自動存檔區段在 `ephemeral` 時略過（含 `game.on_autosave()`）；`stop()` 結束時把 `ephemeral` 設回 false。
  - `world_info()` 加 `"mode": str(world.get("mode", "MUD"))`（一行）。
  - `decide_new_world_eras()`／`apply_pending_eras()`：結果含任何 `mode_only: true` 的 era → 錯誤 `"era 'rogue' 只能用於江湖試煉"`（MUD 世界拒絕，含 `--eras=` 與 `pending_eras`）。
- `NetworkManager.start_rogue(seed: int = 0) -> Error`：同 `start_offline`，改呼叫 `WorldServer.start_rogue(seed)`；狀態列文字「江湖試煉」。
- `GameHost`（`# ==== ROGUE WP-RUN ====` 區塊＋單行鉤子）：
  - `const ROGUE_SYSTEMS := { "rogue": "res://server/rogue_system.gd" }`、`const ROGUE_INTENTS := ["res://server/intents/intents_rogue.gd"]`、`var rogue = null`；在 `_load_m3d()` 之後載入（`_load_systems`／`_register_intent_files`，檔案不存在就略過）。**MUD 世界也載入**；`RogueSystem.enabled()` 為 false 時所有 rogue intent 回 `rogue_off`。
  - `_run_intent` 在 jail_gate 之後加一行：`if rogue != null: var rg: String = rogue.gate(s, kind); if rg != "": return fail(rg)   # ROGUE WP-RUN`（寫成兩行亦可）。
  - `save_char(ch)` 開頭：`if ws.get("ephemeral") == true: return OK   # ROGUE WP-RUN`；`send_passport` 與 `on_autosave` 開頭同樣 return。
  - `leave_character`、`shutdown` 開頭各一行：`m2_call(rogue, "on_leave", [s])`（`shutdown` 對每個 session 呼叫）— 局中離開＝以 ABANDON 結算並寫 profile（§3.9.4）。
- 房間：新地圖 `data/maps/rogue_trial.json`（`era: "rogue"`）：地區 `rg_trial`「試煉場」、唯一房間 `rg_hall`「江湖試煉場」，沒有出口、沒有 NPC、沒有遇敵、`safe: true`；`data/regions.json` 加列 `rg_trial`（`type: "CITY"`、`birth_allowed: false`、`pk_allowed: false`、`world_pos` 隨意不重疊、`era: "rogue"`）。
- `data/eras.json` 加列 `{ "id": "rogue", "name": "江湖試煉", "order": 900, "date": "", "requires": ["1.0B"], "base": false, "mode_only": true, "src": "proposal" }`；`DataSchema`／`data_lint` 接受 `mode_only` 欄位。

### 2.3 程式分層

| 層 | 檔案 | 類別 | WP |
|---|---|---|---|
| core（純邏輯，可在 balance_sim／測試直接用） | `core/rogue/rogue_rules.gd` | `RogueRules` | RUN |
| | `core/rogue/rogue_power.gd` | `RoguePower` | RUN |
| | `core/rogue/rogue_draw.gd` | `RogueDraw` | RUN |
| | `core/rogue/rogue_foes.gd` | `RogueFoes` | RUN |
| | `core/rogue/rogue_run.gd` | `RogueRun` | RUN |
| | `core/rogue/rogue_profile.gd` | `RogueProfile` | RUN |
| | `core/rogue/rogue_ally.gd` | `RogueAlly` | ALLY |
| server | `server/rogue_system.gd` | `RogueSystem`（`host.rogue`） | RUN |
| | `server/intents/intents_rogue.gd` | `IntentsRogue` | RUN |
| ui | `ui/game/rogue/rogue_screen.tscn`＋`.gd` | `RogueScreen` | UI |
| | `ui/game/rogue/rogue_card.gd` | `RogueCard` | UI |
| | `ui/game/rogue/rogue_hud.gd` | `RogueHud` | UI |
| | `ui/game/rogue/rogue_alloc_panel.gd`、`rogue_summary_panel.gd`、`rogue_lobby_panel.gd` | 同名 PascalCase | UI |

core 不碰 Autoload（`GameData` 只在 server 讀，傳 `tables` 進 core）。

### 2.4 試煉中允許的 intent（`RogueSystem.gate`）

試煉世界（`enabled()`）只放行：`ping`、`chat`、`battle_cmd`、`equip`、`unequip`、`char_list`、`passport_request`（回空，不寫檔）、以及全部 `rogue_*`；其他 → `rogue_off`。MUD 世界：`gate` 一律回 `""`（不影響任何既有 intent）。

### 2.5 為了以後的合作模式

- `RogueRun.members: Array[String]`（角色 id）；v1 只有一位。所有「我方戰力」都是 `members` 的玩家單位＋隊友的總和。
- `rogue_state` 帶 `run_id`；以後隊伍成員共用同一個 run。
- 試煉者檔案存在各自的機器上；合作時客人把 `points_total` 帶在 `rogue_open` 的 `profile_claim`（**v1 不實作**，保留參數名）。

---

## 3. WP-RUN：局的狀態機、抽卡、對手、獎勵、檔案、主機接線、平衡

### 3.1 檔案與類別（簽名綁定）

```gdscript
class_name RogueRules extends RefCounted
const RULES_ID := "rg_rules"                       # data/rogue_rules.json 的唯一列
const PHASES := ["ALLOC", "PICK", "READY", "BATTLE", "OVER"]
const KINDS := ["ART", "WEAPON", "ATTR", "ALLY"]
const RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]   # 凡 良 稀 珍 神
const RARITY_NAMES := { "COMMON": "凡", "FINE": "良", "RARE": "稀", "TREASURE": "珍", "DIVINE": "神" }
const CAUSES := ["DEATH", "ABANDON", "TIMEOUT", "LEAVE"]
static func rules(tables: Dictionary) -> Dictionary            # rogue_rules 列；缺 → DEFAULTS
static func award(wins: int, bosses: int, total: int, new_best: bool, r: Dictionary) -> int   # §3.9.2
static func restore(ch: Character, tables: Dictionary, options: Dictionary, boss: bool, r: Dictionary) -> Dictionary  # §3.8 → { qi, jing, shen, neili }（實際加了多少）
static func is_boss_round(round: int, r: Dictionary) -> bool  # round % boss_every == 0

class_name RoguePower extends RefCounted
static func unit_power(spec: Dictionary, tables: Dictionary) -> float          # §3.6
static func side_power(specs: Array, tables: Dictionary) -> float               # Σ unit_power
static func scale_spec(spec: Dictionary, s: float) -> Dictionary                # §3.7.3（回新字典）
static func scale_to(spec: Dictionary, target: float, tables: Dictionary, s_min := 0.5, s_max := 2.5) -> Dictionary  # { spec, s, power, ok }

class_name RogueDraw extends RefCounted
static func draw(run: RogueRun, ch: Character, tables: Dictionary, rng: RandomNumberGenerator, min_rarity := "") -> Array  # 3 張卡快照 §3.4.4

class_name RogueFoes extends RefCounted
static func target(run: RogueRun, my_power: float, r: Dictionary) -> float      # §3.7.1
static func generate(run: RogueRun, target: float, tables: Dictionary, rng: RandomNumberGenerator) -> Dictionary
	# { specs: Array（side 1 的完整戰鬥者規格）, power: float, boss_id: String（rogue_foes 列 id 或 ""）, boss_name: String }

class_name RogueRun extends RefCounted
var run_id := ""; var seed := 0; var phase := "ALLOC"; var round := 1; var wins := 0
var foes_beaten := 0; var bosses_beaten := 0; var members: Array = []
var cards: Array = []            # 目前可選的 3 張（快照）
var extra_picks := 0             # 首領獎勵還剩幾次 PICK（§3.8）
var allies: Array = []           # [{ slot, card_id, monster, npc, name, share, qi_pct, alive }]
var taken: Array = []            # 拿過的卡 [{ id, kind, rarity, title, round }]
var best_card: Dictionary = {}
var roll: Dictionary = {}        # 擲出的七項屬性
var cause := ""
func to_dict() -> Dictionary; static func from_dict(d: Dictionary) -> RogueRun
func rng_for(stream: String) -> RandomNumberGenerator   # 種子 = hash([seed, stream, round, wins, taken.size()])（U11）
func apply_card(ch: Character, card: Dictionary, alloc: Dictionary, tables: Dictionary, options: Dictionary, r: Dictionary) -> String   # "" 或原因碼；§3.5
func summary() -> Dictionary                             # §3.9.1

class_name RogueProfile extends RefCounted
const SCHEMA := 1
const FILE_REL := "rogue/profile.json"
static func default_profile() -> Dictionary
static func normalize(d: Variant) -> Dictionary          # 缺鍵補預設、型別轉 int、夾 0..cap
static func path(root_dir: String) -> String            # root_dir.path_join(FILE_REL)
static func read(root_dir: String) -> Dictionary         # 檔案不在／壞了 → default（壞檔另存 .corrupt 不覆蓋：交給 SaveManager 備份機制）
static func apply_run(p: Dictionary, summary: Dictionary, r: Dictionary) -> Dictionary   # 回新的 profile；summary.points_gained 在這裡算好填回
```

`server/rogue_system.gd`（`class_name RogueSystem`，建構 `_init(h: GameHost)`）：

```gdscript
func enabled() -> bool                                   # GameData.enabled_eras.has("rogue") and host.ws.get("ephemeral") == true
func gate(s: Session, kind: String) -> String            # §2.4
func open(s: Session, seed: int) -> Dictionary           # rogue_open
func start(s: Session, a: Dictionary) -> Dictionary      # rogue_start
func pick(s: Session, idx: int, alloc: Dictionary) -> Dictionary
func fight(s: Session) -> Dictionary
func abandon(s: Session, confirm: bool) -> Dictionary
func debug(s: Session, a: Dictionary) -> Dictionary      # 只在 host.debug_enabled（§3.11）
func run_of(s: Session) -> RogueRun                      # 沒有 → null
func state(s: Session) -> Dictionary                     # rogue_state 的 payload（§6.3）
func on_battle_finished(entry: Dictionary, out: Dictionary) -> void       # BattleSystem._finish，在逐一結算玩家之前
func settle_player(s: Session, ch, u: Dictionary, per: String, close: Dictionary) -> bool   # true＝已處理（不呼叫 handle_death）
func on_leave(s: Session) -> void
func profile_path() -> String                            # RogueProfile.path(SaveManager.root_dir)
```

### 3.2 狀態機

| phase | 進入 | 允許的 intent | 離開 |
|---|---|---|---|
| （無 run） | — | `rogue_open` | → ALLOC |
| ALLOC | `rogue_open`：建 `RogueRun`（`seed` 參數 > 0 用它，否則 `host.rng.randi() & 0x7FFFFFFF`）、擲屬性 | `rogue_start`、`rogue_open`（重擲＝新 run，**不**算一局） | `rogue_start` 成功 → PICK |
| PICK | 開局／打贏一場（或還有首領獎勵 PICK） | `rogue_pick`、`rogue_abandon`、`equip`、`unequip` | 選好 → `extra_picks > 0` ? PICK（重抽，至少「稀」） : READY |
| READY | 選完卡 | `rogue_fight`、`rogue_abandon`、`equip`、`unequip` | `rogue_fight` 成功 → BATTLE |
| BATTLE | `start_ex` 成功 | `battle_cmd` | 勝 → PICK（`round += 1`）；敗／中止 → OVER |
| OVER | 死亡、放棄、逾時、離線 | `rogue_open`（再戰一場） | `rogue_open` → ALLOC（舊角色離開房間、不存檔） |

狀態錯 → `rogue_phase`。每次 phase 改變送一次 `rogue_state`（ui）。

### 3.3 開局（`rogue_open`、`rogue_start`）

- `roll = CharacterFactory.roll(run.rng_for("roll"))`。
- 可分配點數 `alloc_points = CharacterFactory.FREE_POINTS + profile.points_total`。
- `rogue_start { alloc, name?, gender?, look? }`：`alloc` 的總和必須**等於** `alloc_points`、每項 ≥ 0、`roll[a] + alloc[a] ≤ attr_cap`（45）；否則 `rogue_bad_alloc`／`rogue_attr_cap`。`name` 缺省「試煉者」（`CharacterFactory.validate_name`，不合法 → `bad_name`）；`gender` 缺省 M；`look` 缺省 0。
- 建角色：`CharacterFactory.create({ id: host.new_id("rg"), identity: s.identity, name, gender, birth_month: 1, birth_city: "xixia", alloc, look }, roll_plus_alloc_shape, …)` 之後**改寫**：`attrs[a] = roll[a] + alloc[a]`；物品清空，只放 `a_bupao`（裝備）、`w_mudao`（裝備）；`money = 0`、`learn_points = 0`；`location = { region: "rg_trial", room: "rg_hall" }`；`ext["rogue"] = { "run_id": run.run_id }`；生命值全滿、內力 0。`host.enter_character(s, ch)`。
- 角色永遠不存檔（§2.2 的 `save_char` 守衛）；`host.ws.world.char_names` 不登記。

### 3.4 抽卡（`RogueDraw.draw`）

#### 3.4.1 種類權重（`rogue_rules.kind_weights`）

`{ "ART": 35, "WEAPON": 25, "ATTR": 25, "ALLY": 15 }`；`ALLY` 在 `round < ally_min_round`（2）或活著的隊友數 ≥ `ally_max`（2）時權重 0。三張至少兩種不同種類（第三張若與前兩張同種，重抽種類最多 5 次）。

#### 3.4.2 稀有度（`rogue_rules.rarity_bands`，依回合）

| 回合 | 凡 | 良 | 稀 | 珍 | 神 |
|---|---|---|---|---|---|
| 1–3 | 60 | 30 | 10 | 0 | 0 |
| 4–6 | 40 | 35 | 20 | 5 | 0 |
| 7–9 | 25 | 35 | 27 | 11 | 2 |
| 10–14 | 15 | 30 | 32 | 18 | 5 |
| 15+ | 10 | 25 | 33 | 23 | 9 |
| 首領獎勵（`min_rarity = "RARE"`） | 0 | 0 | 60 | 30 | 10 |

#### 3.4.3 候選（`data/rogue_cards.json`，§7.2）

先定種類與稀有度，再從該種類、該稀有度、`min_round ≤ round`、條件成立的卡列依 `weight` 抽。該稀有度沒有候選 → 往下一階找，再往上一階找。

- ART：已經會而且等級 ≥ `level` 的武功不出；已經會但等級較低 → 卡變成「精進」（§3.5）。**搭配偏好**：抽到 ART 時，50% 機率只在「與目前兵器同類別（或 FIST、INNER、LIGHTNESS、基本武學）」的卡裡抽，沒有就不限。
- WEAPON：物品列存在、`Inventory.requirement_reason(row, ch, …) == ""`、不是背包裡已有的同 id；**搭配偏好**：50% 機率只在「與已會的最高 ART 同類別」的兵器裡抽。
- ATTR：固定列（每稀有度一列）。
- ALLY：已經在隊（活著）或這局死過的同一位不出。
- 同一次三張不重複 `id`。

#### 3.4.4 卡片快照（綁定；`rogue_state.cards[]`）

```
{ "idx": int(0..2), "id": String, "kind": "ART"|"WEAPON"|"ATTR"|"ALLY", "rarity": String,
  "title": String,          # 例「華山劍法 四十級」「青鋒劍」「屬性 +4」「令狐沖」
  "sub": String,            # 例「劍法・需持劍」「兵器・劍・攻擊 15」「自由分配」「隊友・華山派」
  "lines": [String],        # 2–4 行說明（招式名與威力、與目前兵器是否相合、隊友的武功）
  "upgrade": bool,          # ART：已會、這張是精進
  "art": { "id", "level", "category" }?,  "item": { "id", "slot", "weapon_type", "atk", "def" }?,
  "points": int?,           "ally": { "name", "ref", "monster" }? }
```

文字由主機組（繁中、遊戲內名稱）；介面不自己拼規則文字（可以另外用 `SkillEffects` 顯示提示）。

### 3.5 卡片效果（`RogueRun.apply_card`）

| 種類 | 效果 | 原因碼 |
|---|---|---|
| ART（新） | `skills.set_level(art, level)`；`base_skill`（`martial_arts.base_skill`，空的話依類別 `BattleFormulas.basic_for_category`）設為 `max(現值, level)`；類別 INNER → 另設 `basic_inner = max(現值, level)`；LIGHTNESS → `basic_dodge = max(現值, level)` | — |
| ART（精進） | 等級 + `upgrade_by[rarity]`（凡 15、良 20、稀 25、珍 30、神 35），上限 `art_cap`（150）；基本武學同上規則跟上 | — |
| ART（基本武學列，`art` 是 `basic_*`） | 該基本武學 = `max(現值, level)` | — |
| WEAPON | 放進背包並裝備（`inventory.equip`）；換下的同欄位護具丟掉；背包內的兵器超過 `weapons_keep`（3）時丟掉攻擊最低、沒裝備的那把（戰鬥中可用 EQUIP 換的就是這些） | 裝備失敗 → `rogue_bad_card` |
| ATTR | `alloc` 必須給、總和 = `points`、每項 ≥ 0、`attrs[a] + alloc[a] ≤ 45` | `rogue_bad_alloc`、`rogue_attr_cap` |
| ALLY | `allies.append({ slot, card_id, monster, npc, name, share: ally_share[rarity], qi_pct: 1.0, alive: true })`；已有 2 位活著 → `rogue_ally_full` | `rogue_ally_full` |

之後：`taken.append(...)`、更新 `best_card`（稀有度高者；同階取較晚的）、送 `rogue_card_taken`（ALLY 另送 `rogue_ally_joined`）、`s.sheet_dirty = true`。內力上限因基本內功改變時，目前內力不變（下一次回復才會加）。

### 3.6 戰力分數（`RoguePower.unit_power`）

純函式，只讀 `BattleFormulas`（凍結）與 `BattleAI.usable_moves`：

```
u   = BattleUnit.new(1, spec)；u.neili = u.neili_max()（以滿內力估最佳招式）
ref = BattleUnit.new(2, REF_SPEC)   # REF_SPEC：七項屬性 18、qi/qi_max 300、skills { basic_dodge: 20, basic_parry: 20 }、armor_power 10、FIST 空手
best_atk、best_lv = max( 普通攻擊 attack_power(u,{},{},0)、每個 usable_moves 的 attack_power(u,row,move,10) )
dmg_out = max(1, best_atk − 0.6 × defense_power(ref, cat)) × hit_chance(u, ref, best_lv)
          × (1 + crit_chance(u) × (crit_mult(u) − 1)) + inner_bonus_max(u) / 2
off     = atb_gain(u) × dmg_out
dmg_in  = max(1, REF_ATK − 0.6 × defense_power(u, "FIST")) × hit_chance(ref, u, 30)     # REF_ATK = 60
life    = qi_max(u) / (dmg_in × atb_gain(ref))
P       = sqrt(off × life)
side_power = Σ P
```

常數 `REF_SPEC`、`REF_ATK` 寫在 `RoguePower`；校準交給 `balance_sim rogue_power_fair`（§9.2）。

### 3.7 對手生成（`RogueFoes`）

#### 3.7.1 目標戰力

```
base(r)   = P0 × growth^(r − 1)                       # P0 = 參考新角色（七項 17、木刀、布衣、無武功）的 unit_power × p0_mult(0.9)；growth 1.16
diff(r)   = min(diff_max, diff_start + diff_step × (r − 1))    # 0.80、+0.04、上限 1.20
blend     = 0.5                                       # 一半看回合曲線，一半看我方戰力 → 永久點數有感，又不會讓對手一面倒
target(r) = diff(r) × ((1 − blend) × base(r) + blend × my_power) × (boss_mult 1.15 if 首領回合 else 1)
my_power  = side_power(我方玩家單位 spec＋隊友 spec)（用開戰前那一刻的 to_combatant 與 RogueAlly.spec_for）
```

所有常數在 `data/rogue_rules.json`（§7.1），`balance_sim` 校準後只改資料。

#### 3.7.2 對手池（`data/rogue_foes.json`，§7.3）

- 每列：`monster`（數值列）、可選 `npc`（名字與立繪；`ref` 用它，同 `_npc_unit_spec`）、`tier`（1–6）、`min_round`、`max_round`（0＝不限）、`boss`（bool）、`minions`（首領的隨從列 id 陣列）、`weight`。
- 排除：`ai == "coward"` 的怪物、`m_ev_jb_cart` 之類非戰鬥列（池裡本來就不放）。
- 人數：回合 1–2 一名；3–4 一到二名；5 以上一到三名；首領回合＝首領＋0–2 名隨從（首領至少占目標的 60%）；上限 `Encounter.MAX_MONSTERS`（4）。
- 演算法（決定性，用 `run.rng_for("foes")`）：依回合篩候選 → 擲人數 n → 擲帶頭的那一位（首領回合從 `boss: true` 且 `min_round ≤ round` 的列，**同一局不重複**）→ 每位的目標 = 帶頭 `target × lead_share`（n=1：1.0；n=2：0.6／0.4；n=3：0.5／0.25／0.25）→ `RoguePower.scale_to` → 縮放係數不在 [0.5, 2.5] 的候選換人（最多 8 次，仍不行就 n−1）。
- 同名多隻沿用 `Encounter.monster_specs` 的甲乙丙命名。

#### 3.7.3 縮放（`RoguePower.scale_spec(spec, s)`）

`qi`、`qi_max`、`neili`、`neili_max` × s；`attrs` 的 str、con、agi + round(6 × (s − 1))，夾在 [5, 60]；`skills` 每項 × (0.6 + 0.4 s)，至少 1；`armor_power` × (0.7 + 0.3 s)；`weapon.atk` × (0.7 + 0.3 s)。`scale_to` 用 12 次二分搜尋讓 `unit_power` 落在目標 ±3%。結果 spec 加 `"rg_scale": s`。

#### 3.7.4 首領

每 `boss_every`（5）回合。開戰前送 `rogue_boss { name }`；`rogue_state.next_round_is_boss` 讓介面預告「下一場：名人登場」（不透露是誰）。首領被打倒：`bosses_beaten += 1`、`profile.famous_beaten[id] += 1`、`extra_picks = 1`。

#### 3.7.5 戰鬥種子

`opts.seed = hash([run.seed, "battle", round])`（BattleSystem 用它取代 `host.rng.randi()`）。同樣的指令序列＝同樣的戰鬥（玩家指令本身會不同，這只保證「可重現」）。

### 3.8 回合結算與回復

- 勝：`wins += 1`、`foes_beaten += side 1 死亡數`、`round += 1`；`RogueRules.restore`：氣、精、神各 + 最大值 × `restore_pct`（0.35），內力 + 最大值 × `restore_neili_pct`（0.5），都夾在最大值；首領回合 → 全滿；飽食、飲水補滿；中毒等戰後狀態清掉（`ch.conditions = {}`）。隊友 `qi_pct` 同規則（§4.5）。送 `rogue_round_won { round, qi, jing, neili }`。之後 `cards = RogueDraw.draw(...)`、phase PICK；首領剛打贏 → `extra_picks = 1`，第一次 PICK 用 `min_rarity = "RARE"`，選完再一般 PICK。
- 開局第一場前生命值全滿。

### 3.9 結束、永久點數、試煉者檔案

#### 3.9.1 結算（`RogueRun.summary()`；綁定）

`{ "run_id", "seed", "cause", "rounds": round, "wins", "foes_beaten", "bosses_beaten", "best_card": { id, title, rarity }, "allies_recruited": int, "points_gained": int, "points_total": int, "new_best": bool }`

`cause`：DEATH（戰鬥判負）、ABANDON（按放棄）、TIMEOUT（戰鬥 ABORTED）、LEAVE（離線、關遊戲、換到別的模式）。四種**都**照同一公式給點（不給「放棄」懲罰，也不給刷點空間：點數只看 `wins` 與 `bosses`）。

#### 3.9.2 點數公式（`RogueRules.award`；常數在 `rogue_rules`）

```
raw   = floor(1.5 × sqrt(wins)) + bosses + (1 if new_best and wins ≥ 3 else 0)
award = raw                                    若 total < 20
      = max(min(1, raw), round(raw × 30 / (30 + total)))     否則
award = min(award, cap(60) − total)
```

預估（`balance_sim rogue_profile_growth` 量實際值，填 §12）：首局 6 勝 1 首領 → 3＋1＋1＝5；前 5 局約 20 點；之後每局 2–3 點；約第 25–30 局到 60 點上限。

#### 3.9.3 檔案（`<資料根目錄>/rogue/profile.json`；綁定）

```
{ "schema": 1, "identity": String, "name": String,
  "points_total": int, "runs": int, "best_wins": int, "total_wins": int,
  "foes_beaten": int, "bosses_beaten": int,
  "famous_beaten": { rogue_foes 列 id: int }, "famous_allied": { rogue_cards 列 id: int },
  "history": [ { "t": int(unix), "seed": int, "wins": int, "bosses": int, "cause": String, "points": int,
                 "best_card": { "id", "title", "rarity" } } ],      # 最新在前，最多 20 筆
  "updated": int(unix) }
```

- 寫：`SaveManager.write_json_atomic(profile_path(), p)`（原子寫入＋備份輪替）；讀：`RogueProfile.read(SaveManager.root_dir)`。測試的 `SaveManager.root_dir` 是測試根目錄 → 不碰擁有者檔案。
- 結算時寫一次；`rogue_open` 時讀一次（點數不在局中改變）。
- 介面的 LOBBY 在沒有主機時用 `RogueProfile.read(SaveManager.root_dir)` **唯讀**顯示。

#### 3.9.4 離線與關遊戲

`on_leave(s)`：phase 是 PICK／READY／BATTLE → `cause = "LEAVE"`、寫 profile；戰鬥中先 `host.battles.detach_for(s)` 的既有流程會繼續 → 我方沒有玩家在場 → 判負，`settle_player` 看到 run 已 OVER 就只回 true。

### 3.10 主機接線（WP-RUN 擁有的 `battle_system.gd` 區塊）

- `const KIND_ROGUE := "ROGUE"`。
- `start_ex`：
  - `if opts.has("seed"): Battle 種子用 int(opts.seed)`（一行改寫 `Battle.new(...)` 的第二個參數）。
  - `kind == KIND_ROGUE` → `bo["no_flee"] = true`、`bo["end_on_players_down"] = true`、`bo["kind"] = "ROGUE"`。
  - 怪物迴圈之後：`for spec in opts.get("foe_specs", []): spec.side = 1; spec.peer = 0; b.add_unit(spec)   # ROGUE WP-RUN`。
  - 玩家加入之後、怪物之前：`_rogue_ally_units(entry, b, opts)   # ROGUE WP-ALLY`（函式在 WP-ALLY 區塊，Day-0 由 WP-RUN 寫空殼）。
- `_finish`：`if kind == KIND_ROGUE: host.m2_call(host.get("rogue"), "on_battle_finished", [entry, out])` 放在逐一結算之前；獎勵條件改成 `result == "VICTORY" and not pvp and kind != KIND_ROGUE`。
- `_settle_player`：`died` 時先 `if kind == ROGUE and bool(host.m2_call(host.get("rogue"), "settle_player", [s, ch, u, per, close], false)): 不呼叫 handle_death`；`close["rogue"]` 由 `settle_player` 填（§6.4）。其餘（`apply_battle_outcome`、`deliver_battle_close`、`save_char`）照舊（`save_char` 已被守衛）。
- `RogueSystem.fight(s)`：檢查 phase READY → 組 `foe_specs`（`RogueFoes.generate`）、`ally_specs`（`RogueAlly.spec_for`，§4.1）→ `host.battles.start_ex(s, [], "ROGUE", { "foe_specs": [...], "ally_specs": [...], "seed": ..., "no_flee": true, "pull_party": false, "party_only": true })` → bid 0 → `rogue_phase`；成功 phase BATTLE。

### 3.11 除錯 intent（只在 `--debug-intents`）

`rogue_debug { op, ids?, n? }`：`op` ∈ `cards`（下一次抽卡固定為 `ids` 的三張卡列）、`foes`（下一場固定為 `ids` 的對手列、不縮放）、`round`（`round = n`）、`points`（profile `points_total = n`，寫檔）。沒有開除錯 → intent 不註冊（同 `debug_set`）。

---

## 4. WP-ALLY：AI 隊友

### 4.1 隊友規格（`core/rogue/rogue_ally.gd`，綁定）

```gdscript
class_name RogueAlly extends RefCounted
const KIND := "ALLY"
const AI := "ally"
static func spec_for(ally: Dictionary, my_unit_power: float, tables: Dictionary) -> Dictionary
	# ally = RogueRun.allies 的一筆；回完整戰鬥者規格（side 0、peer 0）；資料缺 → {}
static func apply_outcome(ally: Dictionary, unit_out: Dictionary) -> Dictionary
	# 戰後：died → alive=false；否則 qi_pct = qi / qi_max；回新字典
```

`spec_for`：`Encounter.monster_spec(ally.monster)` → 有 `npc` 時 `ref = npc`、`name = npc 名`、`short`（同 `_npc_unit_spec`）；`kind = "ALLY"`、`ai = "ally"`、`side = 0`、`peer = 0`、`rg_ally = ally.slot`；`RoguePower.scale_to(spec, my_unit_power × ally.share)`（RoguePower 不存在 → 不縮放）；`qi = round(qi_max × qi_pct)`（至少 1）、`neili = neili_max`。隊友每場都依玩家當下戰力重新縮放（「跟著你成長」），所以晚期也不會變成拖油瓶；`share`：凡 0.35、良 0.45、稀 0.60、珍 0.75、神 0.90（`rogue_rules.ally_share`）。

### 4.2 進場

`BattleSystem._rogue_ally_units(entry, b, opts)`（WP-ALLY 區塊）：`for spec in opts.get("ally_specs", []): b.add_unit(spec)`；`BattleGrid.place_units` 依 side 放左側（既有）。最多 `ally_max`（2）。

### 4.3 AI（`core/battle/battle_ai.gd`）

- `choose`：`u.ai_kind() == "ally"` → `_ally_basic(b, u, tables, rng)`；其他路徑**位元不變**（戰鬥金檔不得改變）。
- `_ally_basic`：同 `_melee_basic`，差異：(1) 招式用 `arts` 全部（同玩家），不是只有 `arts[0]`；(2) 目標排序：氣最少 → 離最近的我方玩家單位最近 → uid；(3) 不逃、不用毒以外的特殊指令（沿用 `_poison_cmd`）；(4) 沒有可攻擊目標時往「離我方玩家最近的敵人」移動。
- `usable_moves`：條件 `not u.is_player() and u.ai_kind() != "ally"` 時才只取 `arts[0]`。
- 隊友打不到隊友：`_enemies` 已用 side；`BattleRules.validate_cmd` 的目標檢查不變。

### 4.4 勝負（`core/battle/battle.gd`）

`_check_end` 開頭（`_duel_check` 那行之後）加一行：`if bool(opts.get("end_on_players_down", false)) and _rg_players_down(): return true   # ROGUE WP-ALLY`。區塊函式 `_rg_players_down() -> bool`：side 0 有玩家單位、而且沒有任何 `is_player() and is_active()` → `_end(Result.DEFEAT)`、回 true。沒有 `end_on_players_down` 的戰鬥行為不變。

### 4.5 永久死亡與傷勢延續

`RogueSystem.on_battle_finished` 對 `entry.battle.units` 中 `spec.rg_ally != ""` 的單位呼叫 `RogueAlly.apply_outcome`（WP-RUN 呼叫、WP-ALLY 實作）：倒下 → `alive = false`、送 `rogue_ally_fallen { name }`、這一局不能再招同一位；活著 → 記 `qi_pct`；回合回復對 `qi_pct` 加 0.35（首領全滿）。判負時隊友狀態不重要（局已結束）。

### 4.6 戰鬥畫面支援（`ui/game/battle/**`）

- 名牌：`kind == "ALLY"` 用 `UiTheme.NAME_ALLY`＋前綴小牌「友」；時間棒列表、氣條照怪物方式顯示（快照本來就有 `qi`、`qi_max`）。
- 精靈：`UnitSprite.shape_for` 把 `ALLY` 當人形（同 `NPC`）；圖用 `ref`（NPC 立繪），沒有圖走既有後備；朝向依 side（既有）。
- 指令：ATTACK／ART 不能選隊友（`is_enemy` 已分邊）；MEDIC、INNER TRANSFER 可以選隊友（`ally_cells_within` 已含非玩家的同邊單位 → 確認可用；若主機端 `battle_cmds.gd`（凍結）擋掉，介面就不提供隊友目標，並寫 `# ROGUE_PLAN 缺漏` 交整合者）。
- 結果框：`result.kind == "ROGUE"` → 不顯示實戰／學點／金錢列，改顯示 `close.rogue`：「第 N 回合　勝」／「試煉結束」、倒下的隊友名單；按鈕文字「繼續」。
- 戰鬥事件文字：隊友行動走既有第三人稱模板；隊友倒下沿用 `battle_kill`。
- `art.json`：`n_er_guojing`（郭靖）沒有立繪 → 加別名列（例 `"alias": "n_xx_qiaofeng"` 或既有男性劍客），`placeholder: false`；`backgrounds` 加 `rg_trial`（別名到既有背景，例比武場或 `bg_default`）。

### 4.7 稽核清單（WP-ALLY 交付時逐項回報）

`grep -n "is_player()\|\"MONSTER\"\|kind()" core/battle server/battle_system.gd ui/game/battle` 的每一處：說明 ALLY 單位走哪條路、是否需要改。已知：`BattleRewards.compute` 第 18、28 行（試煉不算獎勵，不影響）、`battle_system.battle_summary` 的 `killed_by.kind`（隊友打死的敵人記 `"MONSTER"` → 改成 `k.kind()`，只影響 ROGUE）、`BattleRules.kill` 的 `killer.kills`（隊友的擊殺照記）、`BattleCombo`（只看玩家，不影響）、`BattleFormulas.base_level`（非玩家用武功等級代基本武學，隊友照此）。

---

## 5. WP-UI：介面

### 5.1 標題畫面

`title_screen.gd` 在「單機遊玩」同一列右邊加 `UiBuild.button(row, "江湖試煉", _on_rogue)`；`_on_rogue` → `SceneRouter.goto("rogue")`（`scene_router.gd` 的 `SCENES` 加 `"rogue": "res://ui/game/rogue/rogue_screen.tscn"`，一行）。標題的 `_on_welcomed` 不受影響（試煉的 welcome 在 rogue 畫面才發生）。

### 5.2 RogueScreen 的狀態

| 畫面狀態 | 什麼時候 | 內容 |
|---|---|---|
| LOBBY | 進入場景、沒有主機 | 試煉者檔案（唯讀）：永久點數 `n / 60`、局數、最佳勝場、累計擊敗、首領、名人錄（擊敗過／招募過的名人，未遇到的顯示「？？？」）、最近 5 局；按鈕「開始試煉」「返回標題」 |
| ALLOC | `rogue_state.phase == "ALLOC"` | 七項屬性：擲骰值＋分配（＋／－）、剩餘點數、單項上限 45 的提示；名字（預設「試煉者」）、性別、造型（沿用創角的造型選擇元件或簡化版）；「重擲」（再送 `rogue_open`）、「入陣」 |
| PICK | `phase == "PICK"` | 三張卡（§5.3）；首領獎勵時標題「名人敗退，再選一張」；HUD（§5.4） |
| READY | `phase == "READY"` | HUD＋「出戰」「放棄試煉」（確認框）；HUD 的兵器／護具可直接換裝 |
| BATTLE | `battle_opened` | 疊上 `battle_screen.tscn`（同 `main_screen.open_battle` 的作法：`setup(state)`、`battle_closed` → `show_result`、`finished` → 收起）；上方一條 HUD 細列：「第 N 回」、隊友名與氣 |
| OVER | `rogue_over` | 結算（§5.5） |

- 「開始試煉」：`NetworkManager.start_rogue(0)`；收到 welcome（`UiClient.connect_signal("welcomed", …)`）→ 送 `rogue_open {}`。失敗 → 訊息列顯示原因。
- 「返回標題」：有主機時 `NetworkManager.leave()` 再 `SceneRouter.goto("title")`。
- 斷線／主機關閉：同其他畫面（`SceneRouter.show_disconnected`）。
- 所有 intent 用 `IntentGate`（鎖按鈕、錯誤用 `UiClient.reason_inline` 顯示）。
- 鍵盤：PICK 時 1／2／3 選卡、Enter 確認；READY 時 Enter＝出戰；Esc＝取消選取。

### 5.3 三張卡（仿原作客戶端風格）

- 每張卡一個框：ART 用 `UiFrame.Kind.JADE`（武功窗的玉框）、WEAPON 用 `SCROLL`（交易窗卷軸）、ATTR 用 `AMBER`（屬性窗琥珀框）、ALLY 用 `INK`（金邊如意角）。約 260×340（1280×720 基準），三張水平置中、間距 24。
- 卡頭：`PLATE` 名牌寫 `title`；右上一顆稀有度印（凡／良／稀／珍／神，顏色用 `LootUi.rarity_color`）；種類字大印（「武」「兵」「屬」「友」，毛筆字型）。
- 卡身：`sub`、`lines`；ART 加「精進」小印（`upgrade`）；ALLY 顯示立繪縮圖（`ArtRegistry.unit_texture(ref, "NPC", "idle")`，沒有圖就程序化剪影）。
- 互動：滑過 → 框改金描邊；點一下 → 選取（下沉）；再點或按「選定」→ 送 `rogue_pick`。ATTR 卡選定後彈出分配小窗（七項＋／－，必須用完）再送。
- 文字一律來自 `rogue_state`；本地只做排版。

### 5.4 局內 HUD（`RogueHud`）

左側直欄（`JADE` 框）：回合「第 N 回」（`PLATE`）、勝場、擊敗數；下一場是首領時顯示「名人登場」紅字。隊友兩格（立繪縮圖、名字、氣條；倒下的灰掉寫「已殞」）。兵器與護具清單（目前裝備加框；未裝備的兵器有「裝備」按鈕 → `equip`）。武功清單（名字、等級、類別；與目前兵器不合的灰字）。屬性七項（`AMBER` 小框）。資料來源：`rogue_state`＋角色表（`UiClient.sheet()`：生命值、物品、技能）。

### 5.5 結算畫面

`AMBER` 框大窗「試煉結束」：死因（「力戰而亡」「放棄試煉」「久戰不決」「離開試煉」）、撐過 `rounds` 回（勝 `wins` 場）、擊敗對手 `foes_beaten` 名、首領 `bosses_beaten` 位、最好的一張卡（帶稀有度色）、招募隊友數、**永久點數 +`points_gained`（累計 `points_total` / 60）**、`new_best` 時「新紀錄」。按鈕「再戰一場」（`rogue_open`）、「返回標題」。

### 5.6 介面常數

`ui/game/ui_keys.gd` 的 ROGUE 區塊（Day-0）：`I_ROGUE_OPEN`…（與 Protocol 同值）、`ROGUE_KIND_GLYPH := { ART: "武", WEAPON: "兵", ATTR: "屬", ALLY: "友" }`、`ROGUE_CAUSE_TEXT`、`ROGUE_PHASE_*`。

---

## 6. 協定增量（`core/protocol.gd` 由 WP-RUN Day-0 一次寫完；`VERSION` 維持 5）

### 6.1 intent

```gdscript
# ---- 江湖試煉（ROGUE_PLAN §6；U7：純新增，RPC 簽名不變 → VERSION 維持 5） ----
const I_ROGUE_OPEN := "rogue_open"          # { seed:int? }
const I_ROGUE_START := "rogue_start"        # { alloc:Dictionary, name:String?, gender:String?, look:int? }
const I_ROGUE_PICK := "rogue_pick"          # { idx:int, alloc:Dictionary? }
const I_ROGUE_FIGHT := "rogue_fight"        # {}
const I_ROGUE_ABANDON := "rogue_abandon"    # { confirm:bool }
const I_ROGUE_DEBUG := "rogue_debug"        # { op:String, ids:Array?, n:int? }（只在 --debug-intents）
const ROGUE_DEBUG_OPS := ["cards", "foes", "round", "points"]
```

ARGS：`rogue_open { seed: [TYPE_INT, false] }`；`rogue_start { alloc: [TYPE_DICTIONARY, true], name: [TYPE_STRING, false], gender: [TYPE_STRING, false], look: [TYPE_INT, false] }`；`rogue_pick { idx: [TYPE_INT, true], alloc: [TYPE_DICTIONARY, false] }`；`rogue_fight {}`；`rogue_abandon { confirm: [TYPE_BOOL, true] }`；`rogue_debug { op: [TYPE_STRING, true], ids: [TYPE_ARRAY, false], n: [TYPE_INT, false] }`。
INT_RANGES：`rogue_open.seed [0, 2147483647]`、`rogue_start.look [0, LOOK_MAX]`、`rogue_pick.idx [0, 2]`、`rogue_debug.n [0, 999]`。ENUMS：`rogue_start.gender GENDERS`、`rogue_debug.op ROGUE_DEBUG_OPS`。
旗標：`rogue_open`、`rogue_start` 不要角色（`0`）；`rogue_pick`、`rogue_abandon` 要角色（`NEEDS_CHAR`）；`rogue_fight` 要 `NEEDS_CHAR | IDLE`。

### 6.2 事件（模板 id＝事件 key；`ui` 的列在 `ROGUE_UI_EVENTS`）

| key | ui | payload | 模板（WP-RUN 寫） |
|---|---|---|---|
| `rogue_state` | 是 | §6.3 | — |
| `rogue_over` | 是 | §3.9.1 的 summary | — |
| `rogue_round_won` | | `{ round, qi, jing, neili }` | 「第 {round} 回合得勝，稍事調息，氣血回復 {qi}。」 |
| `rogue_card_taken` | | `{ title, rarity_name }` | 「你取得了〔{rarity_name}〕{title}。」 |
| `rogue_boss` | | `{ name }` | 「{name}現身試煉場！」 |
| `rogue_ally_joined` | | `{ name }` | 「{name}願與你並肩作戰。」 |
| `rogue_ally_fallen` | | `{ name }` | 「{name}力戰倒下，退出了這次試煉。」 |
| `rogue_points` | | `{ gained, total }` | 「試煉者的根基更穩了：永久屬性點 +{gained}（共 {total}）。」 |

### 6.3 `rogue_state` payload（綁定；客戶端缺鍵當空）

```
{ "run_id", "seed", "phase", "round", "wins", "foes_beaten", "bosses_beaten",
  "next_round_is_boss": bool, "extra_picks": int, "min_rarity": String,
  "cards": [卡片快照 §3.4.4],
  "roll": { attr: int }, "alloc_points": int, "attr_cap": int,          # ALLOC 才有意義
  "attrs": { attr: int },
  "allies": [ { "slot", "name", "ref", "rarity", "qi_pct": float, "alive": bool } ],
  "arts": [ { "id", "name", "level", "category" } ],
  "gear": { 欄位: { "uid", "item_id", "name", "rarity" } }, "weapons": [ { "uid", "item_id", "name", "weapon_type", "atk", "equipped" } ],
  "best_card": { "id", "title", "rarity" },
  "profile": { "points_total", "cap", "runs", "best_wins" },
  "summary": { … } }                                                       # OVER 才有
```

### 6.4 其他

- 戰鬥 kind：`"ROGUE"`（`battle_opened.state.kind`、`battle_closed.result.kind`）。
- `battle_closed.result.rogue = { "round": int, "won": bool, "boss": bool, "allies_fallen": [String], "over": bool }`。
- 戰鬥單位快照：`kind == "ALLY"` 的單位（公開欄位同怪物）。
- `world_info.mode`：`"ROGUE"`／`"MUD"`。
- 原因碼（模板 `err_<code>`，WP-RUN 寫）：`rogue_off`「這裡不是江湖試煉。」、`rogue_phase`「現在不能這麼做。」、`rogue_bad_card`「沒有這張卡。」、`rogue_bad_alloc`「屬性點要剛好分完。」、`rogue_attr_cap`「單項屬性最多 45。」、`rogue_ally_full`「隊友已滿兩位。」、`rogue_solo_only`「江湖試煉目前只能單人進行。」、`rogue_confirm`「請再確認一次。」。`const ROGUE_REASONS := [...]`。

---

## 7. 資料檔（全部 `era: "rogue"`、`src: "proposal"`、id 前綴 `rg_`；WP-RUN 擁有，除非另註）

### 7.1 `data/rogue_rules.json`（新；`DataLoader.OPTIONAL_FILES` 加 `"rogue_rules"`）

```json
{ "table": "rogue_rules", "version": 1, "rows": [
  { "id": "rg_rules", "era": "rogue", "src": "proposal", "src_note": "江湖試煉【設計提案・非原作】",
    "attr_cap": 45, "art_cap": 150, "weapons_keep": 3, "ally_max": 2, "ally_min_round": 2, "boss_every": 5,
    "kind_weights": { "ART": 35, "WEAPON": 25, "ATTR": 25, "ALLY": 15 },
    "rarity_bands": [ { "from": 1, "w": [60,30,10,0,0] }, { "from": 4, "w": [40,35,20,5,0] }, { "from": 7, "w": [25,35,27,11,2] },
                      { "from": 10, "w": [15,30,32,18,5] }, { "from": 15, "w": [10,25,33,23,9] } ],
    "boss_reward_w": [0,0,60,30,10],
    "attr_points": { "COMMON": 3, "FINE": 4, "RARE": 6, "TREASURE": 8, "DIVINE": 10 },
    "art_level": { "COMMON": 25, "FINE": 40, "RARE": 60, "TREASURE": 80, "DIVINE": 100 },
    "upgrade_by": { "COMMON": 15, "FINE": 20, "RARE": 25, "TREASURE": 30, "DIVINE": 35 },
    "ally_share": { "COMMON": 0.35, "FINE": 0.45, "RARE": 0.60, "TREASURE": 0.75, "DIVINE": 0.90 },
    "p0_mult": 0.9, "growth": 1.16, "diff_start": 0.80, "diff_step": 0.04, "diff_max": 1.20, "blend": 0.5, "boss_mult": 1.15,
    "restore_pct": 0.35, "restore_neili_pct": 0.5,
    "points_cap": 60, "points_k": 1.5, "points_soft": 20, "points_half": 30 } ] }
```

### 7.2 `data/rogue_cards.json`（新；`OPTIONAL_FILES` 加 `"rogue_cards"`）

列形狀：`{ "id", "kind", "rarity", "weight", "min_round", "era": "rogue", "src": "proposal", "src_note" }`＋依種類：ART `"art"`（`martial_arts` id 或 `basic_*`）、`"level"`（缺 → `art_level[rarity]`）；WEAPON `"item"`；ATTR `"points"`（缺 → `attr_points[rarity]`）；ALLY `"monster"`、`"npc"`（可空）、`"name"`（缺 → NPC 名或怪物名）。id 規則：`rg_c_art_<art>`、`rg_c_wpn_<item>`、`rg_c_attr_<rarity 小寫>`、`rg_c_ally_<人物>`。

最少內容（WP-RUN 可以加，不得少）：

- ART（約 40 張）：凡＝各派入門武功（`hs_jianfa sl_changquan wd_changquan em_piaoxue gm_meinu qz_jianfa lj_zhemei xh_chousui xd_daofa hg_jianfa sl_cibeidao wd_xuanxu xh_tianshan`）與基本武學（`basic_inner basic_dodge basic_parry basic_body`）；良＝`gm_yunu_jian em_huifeng wd_raozhi qz_haotian lj_tianyu lj_ruyi hs_pishiquan wd_mianzhang` 與各派心法（INNER）、身法（LIGHTNESS）；稀＝`em_foguang hg_tianchang hg_wanhua qz_tonggui qz_sanhua lj_liuyang wd_rouyun xd_miexian xh_sanyin xh_huagong em_miejian em_juejian`、`hs_zixia`；珍＝`gm_tianluo_zhang gm_yinsuo sl_riyuebian wd_huzhao qz_chongyang qz_kongming`、`gm_yunu_xinjing wd_taiji_sg`；神＝`wd_taijiquan wd_taijijian wd_yitian`、`gm_jiuyin`、`lj_bahuang`。**不放**：FORMATION、POISON、MEDIC、HIDDEN 類、`gm_suxin`（合體）、`monster_only`。
- WEAPON（約 30 張）：用 `items.rarity` 當卡的稀有度（缺省：atk < 15 凡、否則良）；兵器全部七類都要有（刀劍杖鞭拳套至少各 2）；護具每欄位至少 1 張（布衣以外）；神＝`w_sb_yitian w_sb_xuantie w_sb_tulong`（`weight` 低）。
- ATTR：五張（每稀有度一張）。
- ALLY（至少 14 張）：凡＝門派弟子（`m_hs_trainee`、`m_em_dizi`、`m_wd_dizi`、`m_sl_dizi`）與 `m_gb_xiaohuang`「小黃」；良＝`m_npc_wushi`（武館教頭）、`m_npc_wd_hushan`（武當弟子）、`m_npc_sl_wuseng`（少林武僧）；（反派不當隊友：勞德諾、葉二娘、南海鱷神等只出現在對手池）稀＝胡斐（`m_em_hufei`＋`n_ym_hufei`）、周芷若（`m_em_zhouzhiruo`＋`n_em_zhouzhiruo`）、張松溪（`m_wd_zhangsongxi`）；珍＝令狐沖（`m_rg_linghuchong`＋`n_hs_linghuchong`）、虛竹（`m_rg_xuzhu`＋`n_xx_xuzhu`）、小龍女（`m_rg_xiaolongnu`＋`n_gm_xiaolongnu`）；神＝郭靖（`m_rg_guojing`＋`n_er_guojing`）、喬峰（`m_rg_qiaofeng`＋`n_xx_qiaofeng`）、張無忌（`m_rg_zhangwuji`＋`n_zhangwuji`）。

### 7.3 `data/rogue_foes.json`（新；`OPTIONAL_FILES` 加 `"rogue_foes"`）

列形狀：`{ "id": "rg_f_<名>", "monster", "npc"?, "tier": 1..6, "min_round", "max_round", "boss": bool, "minions": [rg_f_ id]?, "weight", "era": "rogue", "src": "proposal", "src_note" }`。

- 一般（至少 30 列）：野獸（`m_wolf m_boar m_wd_menghu m_wd_heixiong m_wd_liebao m_xh_toad m_em_mz_snake m_em_mz_ape`）、賊寇（`m_bandit m_bandit_chief m_ym_qiangdao m_cdb_xiongbatian m_cdb_duyanren m_amb_etou m_gc_ezei m_hn_mojiao m_dl_mingjiao`）、各派弟子與守山弟子（`m_*_dizi`、`m_npc_*_gate`、`m_qz_xunshan m_em_xunshan`）、精英（`m_npc_wushi m_dl_cuisou m_jcn_shafeng m_jq_fanyiweng m_gb_manbing m_xd_pantu`）。1.0B 怪也可以（試煉世界開 1.0B）。
- 首領（至少 12 列，`boss: true`，各帶 0–2 名隨從列）：令狐沖、岳不群、滅絕師太、丘處機、張三丰、天山童姥、小龍女、周芷若、喬峰、虛竹、張無忌、郭靖、丁春秋（`m_npc_dingchunqiu`，隨從星宿門人）、血刀老祖（`m_npc_xd_laozu`，隨從血刀弟子）、李莫愁（`m_dl_limochou`）、葉二娘、南海鱷神。名人的 `min_round`：5（較弱的：周芷若、岳不群、滅絕、丘處機、李莫愁、南海鱷神、葉二娘）、10（令狐沖、小龍女、虛竹、童姥、丁春秋、血刀老祖）、15（喬峰、郭靖、張無忌、張三丰）。

### 7.4 新的戰鬥數值列（`data/monsters.json`，前綴 `m_rg_`，`era: "rogue"`、`no_rewards: true`）

沒有數值列的名人：`m_rg_linghuchong`（SWORD；`hs_jianfa`、`hs_zixia`）、`m_rg_yuebuqun`（SWORD；`hs_jianfa`、`hs_zixia`）、`m_rg_miejue`（SWORD；`em_miejian`、`em_jiuyang`）、`m_rg_qiuchuji`（SWORD；`qz_tonggui`、`qz_xiantian`）、`m_rg_zhangsanfeng`（FIST；`wd_taijiquan`、`wd_taiji_sg`）、`m_rg_tonglao`（FIST；`lj_liuyang`、`lj_bahuang`）、`m_rg_xiaolongnu`（WHIP；`gm_yinsuo`、`gm_yunu_xinjing`）、`m_rg_qiaofeng`（FIST）、`m_rg_xuzhu`（FIST；`lj_liuyang`、`lj_zhemei`）、`m_rg_zhangwuji`（FIST；`wd_taijiquan`）、`m_rg_guojing`（FIST）。喬峰、郭靖可以用新的怪物專用武功（選做：`rg_mon_xianglong`「降龍十八掌」，`martial_arts.json`、`monster_only: true`、`era: "rogue"`、`category: "FIST"`；不做就用 `gb_lianhua`）。數值以「縮放前 ≈ 回合 10 的目標戰力」為準（縮放器負責實際強度）。`arts[0]` 必須是主要攻擊武功（隊友以外的非玩家只用它）。

### 7.5 其他資料

- `data/eras.json`：`rogue` 列（§2.2）。
- `data/maps/rogue_trial.json`、`data/regions.json` 的 `rg_trial` 列（§2.2）。
- `data/text_templates.json`：§6.2 的模板與 §6.4 的 `err_rogue_*`（WP-RUN）；WP-ALLY 若加隊友專用文字用 `rg_ally_*`；WP-UI 不寫模板（介面字串在程式裡）。
- `data/art.json`：郭靖別名、`rg_trial` 背景（WP-ALLY，§4.6）。
- `DataSchema`：`eras.mode_only`（bool）；`rogue_cards.kind` ∈ `RogueRules.KINDS`、`rarity` ∈ `ITEM_RARITIES`；`rogue_foes` 欄位型別（WP-RUN）。

---

## 8. 工作包與檔案所有權

### 8.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-RUN**（也是 Day-0 共用骨架的擁有者） | 新 `core/rogue/rogue_rules.gd`、`rogue_power.gd`、`rogue_draw.gd`、`rogue_foes.gd`、`rogue_run.gd`、`rogue_profile.gd`；新 `server/rogue_system.gd`、`server/intents/intents_rogue.gd`；`core/protocol.gd`（ROGUE 區塊）；`core/data/data_loader.gd`（`OPTIONAL_FILES` 一行）；`core/data/data_schema.gd`（ROGUE 區塊）；`autoload/world_server.gd`（ROGUE 區塊與 §2.2 的守衛行）；`autoload/network_manager.gd`（`start_rogue`）；`server/game_host.gd`（ROGUE 區塊與 §2.2 的鉤子行）；`server/battle_system.gd`（§3.10 的 ROGUE 行與 Day-0 空殼；WP-ALLY 區塊除外）；新 `data/rogue_rules.json`、`data/rogue_cards.json`、`data/rogue_foes.json`、`data/maps/rogue_trial.json`；`data/eras.json` 的 `rogue` 列；`data/regions.json` 的 `rg_trial` 列；`data/monsters.json` 的 `m_rg_*` 列；`data/martial_arts.json` 的 `rg_mon_*` 列（選做）；`data/text_templates.json` 的 `rogue_*`、`err_rogue_*`；`tools/balance_sim.gd`（Day-0 迴圈＋`# ==== ROGUE WP-RUN ====` 區塊）；`tools/data_lint.gd`（呼叫行＋`# ==== ROGUE WP-RUN ====` 區塊）；新測試 `tests/unit/test_rogue_rules.gd`、`test_rogue_power.gd`、`test_rogue_draw.gd`、`test_rogue_foes.gd`、`test_rogue_run.gd`、`test_rogue_profile.gd`、`tests/integration/test_rogue_system.gd`、`test_rogue_world_isolation.gd` | §2、§3、§6、§7 |
| **WP-ALLY** | 新 `core/rogue/rogue_ally.gd`；`core/battle/battle_ai.gd`；`core/battle/battle.gd`（`_check_end` 一行＋檔尾 `# ==== ROGUE WP-ALLY ====`）；`server/battle_system.gd` 的 `# ==== ROGUE WP-ALLY ====` 區塊（`_rogue_ally_units`）與 `battle_summary` 的 `killed_by.kind` 一處；`ui/game/battle/**`（`battle_screen.gd`、`battle_view_model.gd`、`unit_sprite.gd`、`battle_iso_view.gd` 視需要）；`data/art.json`（郭靖別名、`rg_trial` 背景）；`data/text_templates.json` 的 `rg_ally_*`（如有）；`tools/balance_sim.gd` 的 `# ==== ROGUE WP-ALLY ====` 區塊；新測試 `tests/unit/test_rogue_ally.gd`、`test_battle_ally_ai.gd`、`test_battle_players_down.gd`、`tests/unit/test_ui_rogue_battle.gd` | §4 |
| **WP-UI** | `ui/game/title/title_screen.gd`；`autoload/scene_router.gd`（`SCENES` 一行）；新 `ui/game/rogue/**`（`rogue_screen.tscn/.gd`、`rogue_card.gd`、`rogue_hud.gd`、`rogue_alloc_panel.gd`、`rogue_summary_panel.gd`、`rogue_lobby_panel.gd`）；`ui/game/ui_keys.gd`（ROGUE 區塊）；`ui/theme/ui_theme.gd`（如需新色，ROGUE 區塊）；新測試 `tests/unit/test_ui_rogue_title.gd`、`test_ui_rogue_cards.gd`、`test_ui_rogue_flow.gd` | §5 |
| **整合者** | `tools/rogue_acceptance.gd`（新）＋`tools/rogue_accept_scenarios.gd`（新）；`tests/ui/ui_playthrough.gd`（ROGUE 步驟）；`tests/run_tests.gd`（只有在需要新目錄時）；`README.md`；`docs/CHANGELOG.md`（0.7.1.0）；`docs/GDD.md`、`docs/TECH_ARCH.md`、`docs/攻略.md`、`docs/ART_REQUEST.md`；`project.godot`（只改 `config/version`）、`export_presets.cfg`（只改版本欄）；本文件 §12 | §9、§10 |

### 8.2 共用熱檔的切分（只有這裡列的跨 WP 修改是准許的）

| 檔案 | 擁有者 | 其他 WP 准許的修改 |
|---|---|---|
| `server/battle_system.gd` | WP-RUN（ROGUE 行） | **WP-ALLY**：檔尾 `# ==== ROGUE WP-ALLY ====` 的 `func _rogue_ally_units(entry: Dictionary, b: Battle, opts: Dictionary) -> void`（WP-RUN Day-0 寫空殼與 `start_ex` 的呼叫行）；`battle_summary` 的 `killed_by` 一行（`"kind": k.kind()` 取代 PLAYER/MONSTER 二分；行尾 `# ROGUE WP-ALLY`）。其他行不動。 |
| `core/battle/battle.gd` | WP-ALLY（ROGUE 部分） | 只有 WP-ALLY 改（§4.4）；WP-RUN、WP-UI 不改。 |
| `tools/balance_sim.gd` | WP-RUN（Day-0 迴圈） | WP-RUN Day-0 在 `_initialize()` 的 M3d 迴圈之後加 `for lst in [rogue_run_cases(), rogue_ally_cases()]: …`（同 M3d 寫法），並在檔尾放兩個區塊的空函式；**WP-ALLY** 只填 `# ==== ROGUE WP-ALLY ====` 的 `rogue_ally_cases()` 與案例函式（名稱 `rogue_ally_` 開頭）。 |
| `tools/data_lint.gd` | WP-RUN | 只有 WP-RUN 改（`_check_rogue(loader)`）。WP-ALLY 的 `art.json` 改動由既有 `DataSchema.check_art` 檢查。 |
| `data/text_templates.json` | 無單一擁有者 | 只能追加（U9）；WP-RUN 用 `rogue_*`、`err_rogue_*`；WP-ALLY 用 `rg_ally_*`。 |
| `data/monsters.json`、`data/martial_arts.json` | 依列 | 只有 WP-RUN 加 `m_rg_*`、`rg_mon_*` 列；不改既有列。 |
| `data/art.json` | 依列 | 只有 WP-ALLY 加列（`n_er_guojing` 別名、`backgrounds.rg_trial`）；不改既有列。 |
| `autoload/scene_router.gd` | WP-UI | 只有 `SCENES` 一行。 |
| `autoload/world_server.gd`、`autoload/network_manager.gd` | WP-RUN | 只有 §2.2 列的函式與守衛行。 |
| `server/game_host.gd` | WP-RUN | 只有 §2.2 列的區塊與鉤子行（共 7 處以內，行尾 `# ROGUE WP-RUN`）。 |
| `ui/game/battle/battle_screen.gd` | WP-ALLY | WP-UI 不改：試煉的 HUD 細列畫在 RogueScreen 上層，不畫在戰鬥畫面裡。 |

### 8.3 Day-0（各 WP 開工的第一件事；做完就各自往下做，不等別人）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-RUN | `protocol.gd` §6 全部常數與參數表；`data/eras.json` 的 `rogue` 列與 `DataSchema` 的 `mode_only`；三個新 JSON 的空殼（只有 `rg_rules` 列）與 `OPTIONAL_FILES`；`battle_system.gd` 的 `KIND_ROGUE`、`start_ex` 的 `foe_specs`／`seed`／`_rogue_ally_units` 呼叫行與 WP-ALLY 空殼；`balance_sim.gd` 的迴圈與兩個空函式；`data_lint.gd` 的呼叫行與空區塊；`--import` | 其他 WP 的 intent、事件、opts 鍵、kind 要先存在 |
| WP-ALLY | `core/rogue/rogue_ally.gd` 的簽名（先回未縮放的 spec）；`battle.gd` 的 `_rg_players_down` | WP-RUN 的 `fight` 與整合測試要能叫到 |
| WP-UI | `ui_keys.gd` 的 ROGUE 常數；`scene_router.gd` 的 `"rogue"` 場景；`rogue_screen.tscn` 的空殼（能載入） | 標題按鈕與整合者的 `ui_playthrough` 步驟 |

### 8.4 凍結檔（任何 WP 都不得修改）

`core/battle/battle_formulas.gd`、`battle_status.gd`、`battle_rewards.gd`、`battle_aoe.gd`、`battle_rules.gd`、`battle_cmds.gd`、`battle_combo.gd`、`battle_grid.gd`、`battle_unit.gd`、`encounter.gd`；`core/character/**`（`character_factory.gd`、`character.gd`、`derived_stats.gd` 等；試煉只**呼叫**它們）；`autoload/save_manager.gd`、`client_state.gd`、`game_data.gd`；`server/` 中本文件沒點名的全部系統；`ui/game/main/**`、`ui/game/char/**`；`data/` 中本文件沒點名的全部檔案；`tests/fixtures/**`（戰鬥金檔不得改變）。發現非改不可 → `# ROGUE_PLAN 缺漏`，交整合者。

---

## 9. 測試計畫

### 9.1 各 WP 的單元與整合測試（`tests/run_tests.gd --filter=rogue`）

- **WP-RUN**：`test_rogue_rules`（award 表：0 勝 0 點、1 勝 1 點、6 勝 1 首領 5 點、遞減、上限 60、`new_best` 加點只在 ≥ 3 勝；restore 35%／50%／首領全滿／夾上限）；`test_rogue_power`（單調：屬性、等級、兵器攻擊越高 P 越大；scale_to 收斂 ±3%；s 邊界）；`test_rogue_draw`（同種子同結果；至少兩種種類；ALLY 在第 1 回合與滿兩位時不出；首領獎勵全 ≥ 稀；不重複 id；已會等級較高的武功不出；兵器條件不合不出）；`test_rogue_foes`（人數依回合；總戰力在目標 ±10%；首領回合有首領且同局不重複；`min_round` 遵守；決定性）；`test_rogue_run`（狀態機每一條轉移與錯誤碼；四種卡的效果；ATTR 分配錯誤；兵器保留 3 把；best_card 規則）；`test_rogue_profile`（normalize、壞檔退回預設、apply_run 的歷史 20 筆、名人錄計數）；整合 `test_rogue_system`（真的 WorldServer.start_rogue＋GameHost：open → start → pick → fight → 勝 → 敗 → OVER、profile 寫到測試根目錄、gate 擋 MUD intent）；`test_rogue_world_isolation`（試煉世界不寫 `worlds/`、`passports/`；MUD 世界的視圖沒有任何 `era: rogue` 的列；`decide_new_world_eras("1.0A,rogue")` 回錯誤）。
- **WP-ALLY**：`test_rogue_ally`（spec 形狀：kind ALLY、side 0、ai ally、ref＝NPC id、縮放到份額、qi_pct；apply_outcome）；`test_battle_ally_ai`（隊友只打 side 1；會用全部武功；不逃；沒有 `ai: ally` 的戰鬥行為與金檔一致——跑既有 `test_battle_replay`）；`test_battle_players_down`（玩家倒下、隊友還在 → DEFEAT；沒有 opts 時照舊）；`test_ui_rogue_battle`（headless：隊友名牌「友」、顏色、ATTACK 目標不含隊友、MEDIC 可選隊友、ROGUE 結果框沒有獎勵列）。
- **WP-UI**：`test_ui_rogue_title`（按鈕存在、位置在「單機遊玩」旁、切到 rogue 場景）；`test_ui_rogue_cards`（三張卡依種類用對的框、稀有度印與顏色、精進印、鍵盤 1/2/3＋Enter、ATTR 分配窗必須用完）；`test_ui_rogue_flow`（用假的 `rogue_state` 事件序列走 LOBBY → ALLOC → PICK → READY → OVER，所有按鈕送出正確的 intent 與參數）。

### 9.2 平衡（`tools/balance_sim.gd`；用 core 類別直接跑，不開主機）

模擬器：`RogueRun`＋`Character`（`CharacterFactory`）＋`Battle`，雙方都由 `BattleAI` 控制（玩家方用 BattleAI 的玩家路徑：全部武功裡威力最高的已解鎖招式），隊友 `ai: ally`；非等待模式。挑卡策略：
- `greedy`：有與兵器相合的 ART 選它（精進優先）→ 否則與已會武功相合的 WEAPON → 隊友未滿選 ALLY → 否則 ATTR（點數平均分到 str、con、agi）。
- `random`：三張隨機選一張。
- 開局分配：自由點與永久點數平均分到 str、con、agi、guts。

| 案例 | 內容 | 通過條件（初值；校準後只改 `rogue_rules` 的數字，案例條件不改） |
|---|---|---|
| `rogue_power_fair` | 300 對戰力相差 ≤ 5% 的隨機單位（池中怪物縮放）1 對 1 | 勝率 ∈ [0.35, 0.65] |
| `rogue_power_match` | 2000 次對手生成 | 99% 的組合戰力在目標 ±10% |
| `rogue_first_runs` | 200 局、永久點數 0、`greedy` | 勝場中位數 ∈ [5, 8]；第 10 百分位 ≥ 2；第 90 百分位 ≤ 14 |
| `rogue_random_policy` | 200 局、點數 0、`random` | 勝場中位數 ∈ [3, 6]（亂選比較差，但不是必死） |
| `rogue_profile_growth` | 30 局連續累積點數（`greedy`），重複 20 次 | 前 5 局每局點數中位數 ∈ [3, 5]；第 21–30 局勝場中位數 − 第 1–10 局 ∈ [2, 8]；30 局後點數 ∈ [40, 60] 且從不超過 60 |
| `rogue_boss_round5` | 打到第 5 回合的局 | 首領戰勝率 ∈ [0.45, 0.75] |
| `rogue_determinism` | 同種子、同策略跑兩次 | 抽卡與對手組合完全相同 |
| `rogue_ally_value`（WP-ALLY） | `greedy` vs `greedy` 但不選 ALLY | 勝場中位數差 ∈ [+0.5, +3] |
| `rogue_ally_share`（WP-ALLY） | 隊友單挑同回合對手 | 稀以上隊友不會單挑贏過整組對手的機率 ≥ 0.7（隊友是幫手，不是主角） |

數字寫進交付說明與 §12：首局中位勝場、30 局的點數曲線（每 5 局一點）、第 10／20／30 局的中位勝場。

### 9.3 驗收：`tools/rogue_acceptance.gd`（整合者；headless；作法照 `tools/m3d_acceptance.gd`：協調器每個劇本開一個 worker 子行程，worker 用真的 `WorldServer.start_rogue`＋`GameHost`、`--debug-intents`、測試根目錄下的新資料夾；不論成敗只 `OS.kill()` 自己開的 PID）

| 劇本 | 內容 | 通過條件 |
|---|---|---|
| `start_run` | `rogue_open { seed: 12345 }` → ALLOC（roll 七項 13–25、`alloc_points` = 5＋profile）→ `rogue_start` 分配少 1 點 → `rogue_bad_alloc`；單項超 45 → `rogue_attr_cap`；正確 → PICK、三張卡、至少兩種種類；角色只有布衣與木刀、沒有武功 | 相符 |
| `pick_each_kind` | 每次用 `rogue_debug { op: "cards" }` 固定卡：ART（`hs_jianfa` 40）→ 技能 40、`basic_sword` ≥ 40；WEAPON（`w_qingfeng`）→ 已裝備；ATTR（4 點，alloc str 4）→ str +4；ATTR 不給 alloc → `rogue_bad_alloc`；ALLY（周芷若）→ `allies` 一位；第三位隊友 → `rogue_ally_full` | 相符 |
| `win_round` | 固定弱對手（`rogue_debug foes [rg_f_wolf]`）→ `rogue_fight` → `battle_opened.kind == "ROGUE"`、`no_flee` → 用 bot 策略下指令打到勝 → `rogue_round_won`、round 2、phase PICK、氣回復量 = 35% 規則；實戰、學點、金錢都沒變；沒有屍體 | 相符 |
| `ally_acts` | 帶一位隊友打一場：戰鬥事件裡隊友單位至少行動 2 次、目標全是 side 1；固定強對手讓隊友倒下但玩家贏 → `rogue_ally_fallen`、`allies[].alive == false`、下一次抽卡不出同一位 | 相符 |
| `lose_run` | 固定極強對手 → 玩家倒下（隊友還活著也一樣）→ `battle_closed.result.rogue.over == true`、`rogue_over` 的 summary 欄位齊全、`cause == "DEATH"` → profile.json 的 `points_total` 增加量 = `RogueRules.award(...)`、`runs` +1、`history[0]` 正確 → `rogue_fight` → `rogue_phase` | 相符 |
| `points_persist` | `lose_run` 之後 `WorldServer.stop()`、再 `start_rogue` → `rogue_open` 的 `alloc_points` = 5＋新的總點數；`rogue_debug points 59` → 再輸一局拿 ≥ 2 點 → 總數 60（上限） | 相符 |
| `boss_round` | `rogue_debug round 5` → `next_round_is_boss` → 打首領（固定 `rg_f_zhouzhiruo`）→ `rogue_boss` 事件 → 贏 → `extra_picks == 1`、這次三張都 ≥ 稀 → 選完再一次一般 PICK | 相符 |
| `abandon` | READY 時 `rogue_abandon { confirm: false }` → `rogue_confirm`；`true` → OVER、`cause == "ABANDON"`、點數照公式；局中 `on_leave`（移除 session）→ `cause == "LEAVE"`、profile 已寫 | 相符 |
| `determinism` | 同種子兩次各打三回合（固定挑卡序列）→ 每回合的卡 id 與對手組合完全相同 | 相符 |
| `mud_unaffected` | 先在測試根目錄建 MUD 世界 `w_rg_mud`、建一個角色、存檔 → 記下 `worlds/`、`passports/` 全部檔案的雜湊 → 跑完整一局試煉（含 `stop()`）→ 雜湊完全相同、沒有新檔（`rogue/profile.json` 除外）→ 重開 `w_rg_mud`：`GameData.enabled_eras` 沒有 `rogue`、`tables` 裡沒有任何 `rg_` 開頭的列、角色屬性不變 → `--eras=1.0A,rogue` 開新世界 → 失敗並回錯誤訊息；試煉世界中送 `move` → `rogue_off` | 相符 |

成功印 `ROGUE_ACCEPT_OK`（結束碼 0）；失敗印 `ROGUE_ACCEPT_FAIL <劇本> <原因>`（結束碼 1）。log 在 `<測試根目錄>/rogue_acceptance/<run>/`。

### 9.4 介面驗收（`tests/ui/ui_playthrough.gd`，整合者加步驟；**只跑 headless**；截圖 `K:\Project\JY-Mini-OL-Work\shots\rogue_*.png` 若 headless 能出圖）

標題 → 「江湖試煉」→ LOBBY 顯示點數 → 開始 → 分配 → 三張卡（截圖）→ 選一張 → 出戰 → 戰鬥畫面上有隊友（如有）→ 勝 → 再選 → 用除錯讓下一場必敗 → 結算畫面（截圖）→ 返回標題。0 警告。

### 9.5 回歸（全部要綠）

`tests/run_tests.gd`（0 failed）、`tools/data_lint.gd`（0 錯誤；`rogue` era 閉包也 0 錯誤）、`tools/balance_sim.gd`（既有案例全過，可分批）、`tests/ui/ui_playthrough.gd`（**headless only**）、M1 bot、`m2`／`m3a`／`m3b`／`m3c`／`m3c2`／`m3d` 驗收、`tools/story_acceptance.gd --all`、`tools/net_smoke.gd`、`tools/rogue_acceptance.gd`。戰鬥金檔（`test_battle_replay`）不得改變。每次跑完只確認、只結束自己開的 Godot PID（U3）。

---

## 10. 交付與整合

1. 每個 WP 交付說明：改了哪些檔（對照 §8.1）、新 id 清單、校準後的數字（§9.2 各案例）、因本包而改的既有測試（逐一列出原因；應該是 0）、`# ROGUE_PLAN 缺漏` 清單、沒有美術的新單位清單。
2. 整合者：合併 → `--import` → §9.5 全部 → 填 §12 → README（江湖試煉一節：怎麼開始、卡片、隊友、首領、永久點數、檔案位置）→ `docs/攻略.md` → `docs/CHANGELOG.md` 0.7.1.0 → GDD／TECH_ARCH 同步（§1.4）→ `project.godot` 與 `export_presets.cfg` 版本 0.7.1.0。**不匯出、不開 exe**（U2）；匯出與實機確認交給擁有者。
3. 版本：0.7.1.0；連線協定 5；資料指紋改變 → 朋友要一起更新。
4. ART_REQUEST 預定清單：郭靖立繪；試煉場戰鬥背景；卡片種類印（武、兵、屬、友）可先用字型。

---

## 11. 開放問題（不擋開工；預設值已選）

| # | 問題 | 預設 |
|---|---|---|
| Q1 | 玩家倒下但隊友還活著，要不要讓隊友代打 | 不要，直接判負（O6） |
| Q2 | 屬性點每局可重新分配還是永久綁定某項 | 每局開局自由分配（比較好試不同流派） |
| Q3 | 放棄要不要少給點數 | 不少給；點數只看勝場與首領（不會因此有刷點空間） |
| Q4 | 「兵器」卡是否包含護具 | 包含（O9） |
| Q5 | 隊友數值固定還是跟著玩家成長 | 每場依玩家戰力 × 份額重新縮放（§4.1） |
| Q6 | 首領是否會重複 | 同一局不重複；不同局可以 |
| Q7 | 試煉中能不能用藥 | 不能（沒有消耗品卡）；以後可加「丹藥」卡 |
| Q8 | 合作模式 | 以後；v1 拒絕遠端 peer（O2） |
| Q9 | 降龍十八掌等原作招式要不要做 | 選做（`rg_mon_*`，怪物專用、只在試煉 era） |

## 12. 整合紀錄（整合者填）

### 12.1 版本

- 擁有者這一輪的指示：CHANGELOG 寫「0.8.0.0（進行中，江湖試煉）」，取代 §1.3 O15 的 0.7.1.0。`project.godot`、`export_presets.cfg` 的版本**還沒改**（進行中；匯出時再改）。`Protocol.VERSION` 維持 5。

### 12.2 採用的偏差（取代上文的對應段落）

| # | 原文 | 改成 | 理由 |
|---|---|---|---|
| D1 | §3.6 戰力以固定 `REF_SPEC` 為參考 | 每場以玩家自己的戰鬥者規格為參考（`RoguePower.set_reference`，經 `RogueFoes.prepare_fight`）；沒設參考時照原公式 | 固定參考下「弱但很硬」的對手被低估（WP-RUN：狐狸 0.5 倍戰力卻贏 94%） |
| D2 | §7.3／§7.2 沒有 `override` | `rogue_foes` 列與 ALLY 卡可帶 `override`（換成試煉等級的數值，保留名字與立繪）；隊友經 `RogueFoes.ally_spec` 套用 | MUD 名人數值列遠超 0.5–2.5 的縮放範圍 |
| D3 | §3.7.1 `my_power` = 玩家＋隊友 | `my_power` = 玩家＋`ally_weight` × 隊友；**校準為 0**：對手只依玩家本人生成，隊友是用一張卡換來的純加成 | 隊友計入時選隊友反而變差（主機路徑：中位數 6 對 7） |
| D4 | §4.1 `ally_share` 凡 0.35／良 0.45／稀 0.60／珍 0.75／神 0.90 | 0.45／0.55／0.70／0.85／1.00 | 配合 D3；稀以上隊友單挑整組對手仍輸 92% |
| D5 | §9.2 `rogue_ally_value`：勝場**中位數**差 ∈ [+0.5, +3] | 改用 WP-RUN 的 `_rg_play`（與主機同一條路），看**平均**勝場差 ∈ [+0.3, +3]，中位數差只要 ≥ 0 | 勝場集中在 4–9 的整數，調過的所有變體中位數都是 7 對 7；平均差才量得出隊友的效果 |
| D6 | §3.8 只有回合回復 | 兩場之間等待不會自己回血（出戰前把超過結算值的部分拿掉） | O13 的回復只有這一個來源 |
| D7 | §2.2 GameHost 鉤子 ≤ 7 處 | 8 處（另一行 `_load_rogue()` 在 `_init`） | 載入點 |
| D8 | §4.6 結果框 | 同 WP-ALLY：〔友〕前綴、「第 N 回合　勝」／「試煉結束」、倒下的隊友名單、按鈕「繼續」 | — |
| D9 | §9.4 介面驗收 | 第 24 步走一局最短的流程（標題 → 大廳 → 分配 → 選卡 → 出戰 → 結果 →〔勝則放棄〕→ 結算 → 返回標題）；「用除錯讓下一場必敗」改成放棄（介面驗收不送除錯 intent）；`--ui-rogue-only` 只跑這一段 | 介面只透過按鈕操作 |
| D10 | §9.3 `lose_run`「隊友還活著也一樣」 | 劇本把隊友的氣調到很高；玩家 60 秒內沒倒就用捷徑打倒 | 張三丰會先打隊友，自然流程無法保證「玩家先倒」 |

### 12.3 數字（`balance_sim --runs=200`，greedy 挑卡；整合後的資料）

| 案例 | 結果 | 帶 |
|---|---|---|
| `rogue_power_fair` | 41.5% | 35–65% |
| `rogue_power_match` | 100%（最大誤差 8%） | ≥ 99% 在 ±10% |
| `rogue_first_runs` | 中位數 7、P10 4、P90 9 | 5–8、≥ 2、≤ 14 |
| `rogue_random_policy` | 中位數 6 | 3–6 |
| `rogue_profile_growth` | 前 5 局每局 5 點；第 21–30 局中位勝場 14 − 第 1–10 局 9 = +5；30 局後 60 | 3–5、+2–+8、40–60 |
| `rogue_boss_round5` | 66.1%（192／200 局打到第 5 回合） | 45–75% |
| `rogue_determinism` | 相同 | — |
| `rogue_ally_value` | 平均 6.60 對 6.07（+0.53）；中位數 7 對 7；平均招募 1.33 位 | D5 |
| `rogue_ally_share` | 輸 92%（最常贏：喬峰 23%） | ≥ 70% |

點數曲線（平均累計）：第 5 局 24.1、第 10 局 38.7、第 15 局 51.6、第 20 局起 60（上限）。比 §3.9.2 預估的第 25–30 局早到上限；仍在 `rogue_profile_growth` 的帶內，沒有改公式。

### 12.4 整合者新增

- `tools/rogue_acceptance.gd`＋`tools/rogue_accept_scenarios.gd`（§9.3 十個劇本，全過）。
- `tests/ui/ui_playthrough.gd` 第 24 步（§9.4、D9）。
- `tests/unit/test_ui_scenes.gd` 加 `rogue_screen.tscn`；`tests/unit/test_rogue_run.gd` 的隊友份額改讀 `rogue_rules`（D4）。
- README「江湖試煉（肉鴿模式）」與「江湖試煉驗收」；CHANGELOG 0.8.0.0（進行中）。
- 還沒做：GDD、TECH_ARCH、`docs/攻略.md`、ART_REQUEST 的同步（§1.4、§10.4）。

### 12.5 試煉審查修正（玩法審查＋介面審查；擁有者預先授權預設值）

採用的偏差（接在 D1–D10 後面，取代上文的對應段落）：

| # | 原文 | 改成 | 理由 |
|---|---|---|---|
| D11 | §3.4.2 ART「已會而且等級 ≥ `level` 的不出」 | 已會、還沒到 `art_cap` 的特殊武功都會以「精進」出現（目前等級 + `upgrade_by`）；基本武學照舊 | 每門武功只有一張卡，舊規則讓精進永遠不出現 |
| D12 | §3.5 兵器卡「選定後立刻換上」 | 兵器：目前兵器有相合的武功時，只在同類且攻擊不低於目前才換上，否則放進行囊（卡面寫明）；沒有相合武功時，相合的新兵器、或攻擊較高的才換。超過 3 把時丟攻擊最低、沒裝備、不是剛拿到的那把，卡面寫出丟哪一把。護具照舊 | 兵器卡換上後把相合的武功關掉（「永遠選兵器」平均只有 4.96 勝） |
| D13 | §3.7.2 首領同局不重複 | 另外：這局招募過的隊友不會被抽成首領；見過的首領不會再以隊友卡出現 | 同一人同時出現在敵我兩邊 |
| D14 | §3.7.1 曲線 `diff_start` 0.70、`boss_mult` 1.4 | `diff_start` 0.85、`boss_mult` 1.15（`growth` 1.20、`diff_step` 0.04 不變） | 一般回合 95% 勝＝走過場、首領是牆（第 10 回合首領 14%）；死在首領回合 114／200 |
| D15 | §3.7 對手的實際難度只看戰力分數 | `rogue_foes.power_adj`（數字，或 `{ "起始回合": 倍率 }`）：有效戰力 = 分數 × power_adj，縮放時縮到「份額 ÷ power_adj」。由 `rogue_boss_spread` 校準（李莫愁、小龍女、周芷若（第 10 回合）較易 → < 1；南海鱷神、丁春秋、血刀老祖、虛竹、童姥、丘處機（第 10 回合）較難 → > 1） | 同戰力的首領勝率從 43% 到 89%（第 5 回合）、0% 到 36%（第 10 回合） |
| D16 | §3.7.1 參考新角色固定 | 江湖名聲：永久點數 × `renown_share`（0.6）× 淡出（第 1 回合 1，每回合少 1/`renown_fade`（10），第 11 回合起 0）平均加到參考新角色的臂力、根骨、機敏 | 60 點時第 1–9 回合剩氣 74–92%＝走過場；點數的好處留到首領與後面的硬仗 |
| D17 | §3.9.2 `points_k` 1.5、`points_half` 30 | `points_k` 1.3、`points_half` 20 | 第 20 局就到 60 點上限（預估第 25–30 局）；前 5 局每局 5 點（帶的上緣） |
| D18 | O6 只寫「玩家倒下＝結束」 | 不改 O6；另外：試煉的對手（`opts.kind` ROGUE 的 side 1）在攻擊範圍內先打「氣剩下比例最高」的人（分散出手），結果框與結算畫面在「你倒下時隊友還站著」時說明「試煉以你本人為準」 | 144 次有隊友的死亡裡 139 次隊友還站著；輸的時候對手平均剩 52% 的氣 |
| D19 | §7.4 名人 | 郭靖（降龍十八掌＋九陰真經，不屬丐幫，卡面「隊友・襄陽」）、張無忌（乾坤大挪移＋九陽神功，卡面「隊友・明教」）、令狐沖（獨孤九劍＋華山劍法，沒有紫霞神功）、周芷若（新列 `m_rg_zhouzhiruo`：九陰白骨爪＋峨嵋九陽功；MUD 的 `m_em_zhouzhiruo` 不變）、李莫愁的隨從改成洪凌波（`rg_f_lmc_hongningbo`，weight 0，只當隨從）、胡斐的 override 改 `basic_blade`。新的怪物專用武功 `rg_mon_xianglong`、`rg_mon_qiankun`、`rg_mon_jiuyang`、`rg_mon_dugu`（`era: rogue`；威力照原本共用的武功） | 郭靖＝喬峰、張無忌＝張三丰、令狐沖＝岳不群的複製；李莫愁被逐出古墓 |
| D20 | §5.3、§5.4 介面 | HUD 的基本武學寫「基本武學」（主機送 `BASIC`）、補「筆法」；卡面屬性名稱同全遊戲（臂力、機敏）；武功卡寫出同步提升的基本武學與攻擊加成、輕功寫基本輕功與閃躲縱躍、基本武學卡寫數字；武功卡的滑鼠提示附 `SkillEffects` 完整說明；回合一律「第 N 回合」；`err_rogue_attr_cap` 讀主機附的上限；放棄確認窗 Enter＝再想想；數字鍵盤 1–3 選卡；分配窗 Enter＝確定、結算 Enter＝再戰一場 | 介面審查 1–6 |

新增的回歸測試：`tests/unit/test_rogue_review.gd`、`tests/unit/test_ui_rogue_layout.gd`（1280×720 版面）；平衡案例（`tools/balance_sim.gd`）`rogue_choice_matters`（看得懂數字的 smart 中位數 − 亂選 ≥ 3；greedy 平均 > 亂選）、`rogue_upgrade_offered`、`rogue_no_wall`、`rogue_boss_spread`（同一批角色在首領回合前存檔、輪流打每位首領）、`rogue_points_late`。

數字（`balance_sim --runs=500`）：

| 案例 | 結果 | 帶 |
|---|---|---|
| `rogue_power_fair` | 43.7% | 35–65% |
| `rogue_power_match` | 100%（最大誤差 8%） | ≥ 99% |
| `rogue_first_runs` | 中位數 6、P10 3、P90 11 | 5–8、≥ 2、≤ 14 |
| `rogue_random_policy` | 中位數 4 | 3–6 |
| `rogue_profile_growth` | 前 5 局每局 4 點；+7 勝；曲線 5 局 18.6、10 局 30.2、20 局 47.9、25 局 56.1、30 局 60 | 3–5、+2–+8、40–60 |
| `rogue_boss_round5` | 68.5% | 45–75% |
| `rogue_ally_value` | 平均 6.51 對 5.18（+1.33）；中位數 6 對 4 | D5 |
| `rogue_ally_share` | 輸 95% | ≥ 70% |
| `rogue_choice_matters` | smart 11 − 亂選 4 = +7；greedy 6.51 − 亂選 5.46 = +1.05 | ≥ 3、> 0 |
| `rogue_upgrade_offered` | 看過精進 45%、拿過 43%（點數 20） | ≥ 40%、≥ 30% |
| `rogue_no_wall` | 死在首領回合 43%；第 10 回合首領 58%；輸時對手剩氣 39% | ≤ 60%、≥ 35%、≤ 45% |
| `rogue_boss_spread` | 第 5 回合 62–69%；第 10 回合 62–76% | 差 ≤ 25、≤ 35 |
| `rogue_points_late` | 60 點第 1–4 回合剩氣 65%；60 點 − 0 點 = +8 勝 | ≤ 80%、≥ 4 |

審查第 2 點的補充：審查用的 greedy（先挑相合的武功）只比亂選多 1 勝左右，但會看數字挑卡的 smart 中位數 11 勝、亂選 4 勝，選卡本身差很多；greedy 低估了兵器攻擊與屬性卡。

### 12.6 第二輪審查修正（玩法、正確性、介面三份審查；擁有者預先授權預設值）

| # | 原文 | 改成 | 理由 |
|---|---|---|---|
| D21 | §3.4.4 卡片快照 | 主機替每張非隊友卡加 `power_pct`（`RogueDraw.annotate_power`：在角色與這一局的副本上套用這張卡，量「以自己為參考的戰力 ÷ 參考新角色的戰力」的變化，同 balance_sim 的 smart；屬性卡以平均加到臂力、根骨、機敏估算並附 `power_note`）；卡面在種類那一行靠右寫「戰力 ▲n%／▼n%／持平」，滑鼠提示說明。協定只加欄位，`VERSION` 維持 5 | 贏的選法（smart 中位數 11–13）在畫面上看不到，照卡面文字選的 greedy 只比亂選多 1 勝 |
| D22 | §3.4.3 候選依 weight 抽 | 已會的特殊武功（精進卡）在候選裡權重 ×3（`RogueDraw.UPGRADE_WEIGHT_MULT`） | `rogue_upgrade_offered` 換種子（7）只有 37% |
| D23 | D14 `boss_mult` 1.15 | 1.12 | 種子 7：死在首領回合 55%（≤ 60%）、新手中位數 5（帶的下緣）；對手改成會補刀（D24）後多留餘裕。1.10 時種子 1 的第 5 回合首領勝率 72%（貼上緣 75%），1.12 在 66–68% |
| D24 | D18 分散出手 | 例外：攻擊範圍內有氣 < 15% 的人時先補刀（比例最低的先；`BattleAI.RG_FINISH_PCT`） | 對手從不補刀、站在隊友旁邊就不會被打；倒下要有看得見的最後一擊 |
| D25 | §3.4 試煉不能逃 | `BattleRules.FLEE_SHOE_BLOCKED` 加 `ROGUE`：輕功脫身與無敵烙跑鞋在試煉中也不能用（指令可用清單與快照也不列） | 「輕功脫身」成功後玩家方全倒，被當成倒下、以 DEATH 結束這一局 |
| D26 | §3.9.3 profile 只在結算時寫 | 每打贏一場寫一次 `profile.in_progress`（run_id、seed、勝場、首領、擊敗數、最好的卡、名人錄）；下一次 `rogue_open`（大廳讀檔時只在記憶體裡）以 LEAVE 結算；`apply_run` 清掉它 | 當機、工作管理員結束、斷電時這一局的點數歸零、歷史也沒有紀錄 |
| D27 | §3.7 `rogue_fight` | 開戰失敗（`start_ex` 回 0）時還原 `bosses_seen`、`run.fight`（含 pin）與 `debug_foes` | 重試時同種子不再是同一場、沒有 pin 時不回復規則被繞過 |
| D28 | §7.4 名人 | 喬峰：降龍十八掌＋擒龍功＋混天功（郭靖：降龍十八掌＋九陰真經，以第二門武功區分）；丘處機：同歸劍法＋全真劍法（先天氣功是王重陽的）；張松溪卡面「隊友・武當」、胡斐「隊友・遼東」（`affil`） | 降龍十八掌是喬峰的招牌；張松溪是武當七俠 |
| D29 | §5 介面 | 大廳的名人錄／最近 5 局放進高度 220 的捲動區（大廳 694→533 px，錯誤列回到畫面內）；結算寫「倒在第 N 回合（勝 M 場）」「於第 N 回合放棄／離開」（`rounds` 是結束時所在的回合）；屬性分配窗與放棄確認後面墊擋滑鼠的暗幕，開著時不能換卡，確定時送給開窗的那一張；護具卡顯示「甲／護具」；拳掌武功卡寫「不挑兵器」「拿什麼兵器都能出招」，拳套卡寫出相合的拳掌武功；點數上限讀主機（summary.points_cap、rogue_rules.points_cap）；隊友卡寫「功力約為你的四成半」「功力與你相當」；武功說明拿掉只在江湖用得到的行（頻道、修煉、拜師、秘笈…）；卡名用阿拉伯數字（「華山劍法 25 級」）；大廳 Enter＝開始試煉、Esc＝返回標題 | 介面審查 1–6 |

新增的回歸測試：`tests/unit/test_rogue_review2.gd`（卡面戰力、護具顯示、拳掌文字、隊友功力說法、名人武功與門派、精進權重、補刀、in_progress 結算）；`tests/integration/test_rogue_system.gd` 加開戰失敗還原、戰鬥中斷線（`WorldServer.on_peer_disconnected`）只結算一次且為 LEAVE、當機後下一局結算；`tests/unit/test_ui_rogue_layout.gd` 加大廳／配點／結算的 1280×720 版面與浮層強制回應；`tests/unit/test_m3d_qing.gd` 的 `test_escape_blocked_kinds` 加 ROGUE 與烙跑鞋。

數字（`balance_sim --runs=200`，種子 1／7／13）：

| 案例 | 種子 1 | 種子 7 | 種子 13 | 帶 |
|---|---|---|---|---|
| `rogue_first_runs` 中位數 | 6 | 6 | 6 | 5–8 |
| `rogue_random_policy` 中位數 | 4 | 4 | 4 | 3–6 |
| `rogue_boss_round5` | 68.4% | 66.7% | 67.0% | 45–75% |
| `rogue_no_wall` 首領回合死亡／第 10 回合首領／輸時剩氣 | 41%／66%／37% | 51%／52%／36% | 42%／52%／36% | ≤ 60%、≥ 35%、≤ 45% |
| `rogue_boss_spread` 差（第 5／10 回合） | 17／20 | 10／31 | 15／19 | ≤ 25、≤ 35 |
| `rogue_upgrade_offered` 看過／拿過 | 70%／70% | 68%／68% | 61%／61% | ≥ 40%、≥ 30% |
| `rogue_choice_matters` smart − 亂選；greedy − 亂選 | +7；+0.76 | +7；+1.15 | +7；+0.82 | ≥ 3、> 0 |
| `rogue_ally_value` | +1.19 | +1.05 | +0.87 | +0.3–+3 |
| `rogue_ally_share` 輸 | 94.5% | 94.5% | 90.0% | ≥ 70% |
| `rogue_points_late` 剩氣／點數差 | 65%／+8 | 67%／+8 | 65%／+8 | ≤ 80%、≥ 4 |
| `rogue_power_fair` | 46.0% | 42.5% | 47.0% | 35–65% |
| `rogue_power_match` | 100% | 100% | 100% | ≥ 99% |
| `rogue_profile_growth` 晚 − 早 | +7 | +7 | +6 | +2–+8 |
