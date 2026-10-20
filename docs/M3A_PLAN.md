# M3a 實作計畫：其餘 8 個 1.0 門派、門規坐牢叛派、毒醫暗陣內穴（M3A_PLAN）

> 版本：2026-10-19（開工版）。協調者撰寫；實作中只由協調者（整合者）修改本文件。
> 上游：GDD §3、§4、§5、§6.5、§13 M3 列；WORLD_2001（地理，**仍然有效**，本文件只寫增量）；M1_PLAN、M2_PLAN（既有協定與資料形狀；本文件只寫**增量**）；`docs/research/verified_research.md` 的「M3a 門派研究」章（以下簡稱「研究」）。
> 已完成、要保留的 M3 小範圍：查看偵察（GDD §5.10、M2_PLAN §9）。新門派的野外房間都有遇敵表，**查看偵察照樣可用**，驗收要涵蓋（§10.3）。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

M3a 由 3 個機制工作包（WP-CMD、WP-RULES、WP-UI）與 8 個門派內容工作包（WP-SECT-<id>）**同時**實作，之後由 WP-MERGE 單獨合併資料，最後由整合者驗收。實作者之間不溝通。規則沿用 M1_PLAN 0.1、M2_PLAN 0.1：

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent、事件 key、原因碼、伺服器選項 key、規則 key、存檔欄位、資料列 id、房間 id、碎片檔格式**都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定。
3. 優先順序：本文件 > WORLD_2001 > M2_PLAN > M1_PLAN > GDD > TECH_ARCH。偏差列在 1.4。
4. 發現缺漏：照「最不意外」實作，程式裡寫 `# M3A_PLAN 缺漏：……`，交付說明列出；**不要**改別人的檔案。

### 0.2 標記

沿用 GDD 第 0 章：【已證實】【後期版】【待考證】【設計提案】【設計提案・非原作】。本文件新增的數值一律是【設計提案】（資料列 `src: "proposal"`），有研究依據的寫【已證實】並在 `src_note` 註明出處（例：`"src_note": "研究 武當：2001-07-08 入派條件"`）。
**era 與 src 的分工**（M3a 審查修正 R7）：`era` = 這個東西在哪個版本**已經存在**（決定世界裡有沒有它）；`src` = 這一列的**細節**（數字、名單、門檻）出處。base era（1.0A）的列標 `src: "later"` 表示「1.0A 就有，但細節借用後期版」，`src_note` 必須寫 1.0A 存在的依據與借了哪些後期數字（`data_lint` 檢查）。存在本身就是後期的東西（例：陣法 = 1.0B）要改 era，不能只標 src。2002-01-25 才有的**機制**（門派技能觸發、痲痺／混亂／封穴／內傷／分心）不靠 era 篩掉（資料列仍是 1.0A），由規則 `later_battle_cmds` 控制（D9），狀態列以 `since: "gmdk"` 標記。
**招式名稱**：研究查遍所有來源，**沒有任何一派有招式名單**（原作只用「射程形狀」區分武功）。所以每一招的名字都是【設計提案】，取自金庸原著並在 `moves[].src` 填 `"proposal"`；射程形狀（小十字、大十字、直線、半米字）有研究依據的照研究。

### 0.3 全域規則

M1_PLAN 0.3 的 G1–G10 與 M2_PLAN 0.3 的 H1–H6 全部繼續有效（主機權威、離線同一路徑、`core/**` 純邏輯、文字放資料、JSON 數字轉 int、**不 commit**、測完關掉 godot 並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認、新增 `class_name` 後先 `--import`、不新增 Autoload、不改 `project.godot`、不新增 `@rpc` 方法、新系統容錯接線）。M3a 另加：

| # | 規則 |
|---|---|
| K1 | `Protocol.VERSION` 由 3 升為 **4**（戰鬥指令集合、快照與角色表欄位改變）。Steam 大廳 `proto` 自動跟著變。 |
| K2 | **一個檔案只有一個擁有者**（§8.1）。門派內容只寫在 `docs/m3a_staging/<id>.json`（碎片），**只有 WP-MERGE 能改 `data/*.json`、`data/maps/*.json`、`data/art.json`**（例外：`data/status_effects.json` 歸 WP-CMD；`data/rule_profiles.json`、`data/server_options.default.json` 歸 WP-RULES）。機制 WP 需要的文字模板、物品列也寫成碎片（`_cmd.json`、`_rules.json`），由 WP-MERGE 合併。 |
| K3 | 新主機系統（`SectSystem`、`ConditionSystem`）照 H3/H4：`extends RefCounted`、`_init(p_host: GameHost)`、`GameHost` 以路徑 `load()` 建立，失敗時為 `null`，所有呼叫點先判斷 `!= null`。 |
| K4 | 期間（坐牢、禁止學武、中毒發作）一律以**角色累計上線秒數** `ch.online_s` 計（研究：「累計遊戲上線時間」）。1 遊戲日 = `server_options.game_day_real_s`（預設 7200 真實秒，研究：1 遊戲日 = 2 真實小時）。`--time-scale` 只縮放世界時鐘，**不縮放上線秒數**；驗收用 debug intent 快轉（§6.9）。 |
| K5 | 每個新門派的房間、NPC、怪物、物品、任務、模板 id 都用**門派前綴**（§3.2 表），不得撞到既有 id（`xx_` 是西夏、`hs_` 是華山，所以星宿用 `xh_`、恆山用 `hg_`）。 |
| K6 | 新地區必須遵守 WORLD_2001 §1.4 的**新手安全規則**（lint 會檢查從兩座出生城到每一座山門的路線，見 §2.3）。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=sect]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500 [--case=p1_sect_wudang]
"$G" --headless --path . --script res://tools/net_smoke.gd -- --no-steam
"$G" --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3a_acceptance.gd -- --no-steam [--sect=emei] [--timeout=2400]
"$G" --headless --path . -- --no-steam --offline --world=close_x --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=wm --time-scale=50 --quit-after=300   # 與 quit 各一次（它是 bot，不是 --script；整合紀錄 I9）
```

---

## 1. 範圍

### 1.1 M3a 要做（逐項打勾；括號是負責 WP）

1. **8 個門派完整可玩**：武當 `wudang`、峨嵋 `emei`、恆山 `hengshan`、全真 `quanzhen`、古墓 `gumu`、靈鷲宮 `lingjiu`、星宿 `xingxiu`、血刀門 `xuedao`。每派都有：
   - 山門地區接在 2001 世界原作座標上，**走路**到得了（§2）（WP-SECT 碎片 → WP-MERGE）。
   - 拜師（性別、善惡、PK、物品／任務條件；§3.2）（WP-SECT 資料，WP-RULES 程式）。
   - 師父與武功（研究名單；每套武功都有招式，§4.2）（WP-SECT）。
   - 門派技能與戰鬥觸發（§5.6）（WP-CMD）；門派技能的取得與衰減（§6.4）（WP-RULES）。
   - 門規：停止傳功、違反門規 → 坐牢／禁止學武、叛派、開除、公敵、敵對入山（§6）（WP-RULES）。
   - 研究有寫到的門派生活：齋飯時辰、切磋弟子、門派任務（入門任務、武當 俠義任務、峨嵋 斷惡）（WP-SECT）。
2. **戰鬥指令** 毒、醫、暗、陣、內、穴，以及「裝」底下的戰鬥用藥（`ITEM`）（WP-CMD 規則；WP-UI 按鈕與選目標）。
3. **狀態效果**：中毒（戰後持續發作）、內傷、封穴、痲痺、混亂、分心、流血、陣法加持（§5.7）（WP-CMD；戰後持續的部分 WP-RULES）。
4. **範圍招式**：小十字、大十字、直線、半米字、周身（§5.3）（WP-CMD）。
5. **少林十八銅人陣**（3 人、3 波、每波 6 人）與金剛伏魔圈、日月鞭法、少林思過處（WP-CMD 碎片 `shaolin.json`；開陣流程 WP-RULES）。
6. **通用門派框架**：新增門派只要資料（碎片）不用改程式。丐幫、明教、桃花島之後照同一格式加。
7. 1.0B（神鵰）以後才有的「京城監獄」不做；M3a 的牢房是各派思過處（GDD 6.5 已定）。

### 1.2 M3a 不做（M3b 或更後）

丐幫、京城（完整）、絕情谷、天地會、組織、生活技能擴充（工匠、打鐵、鑄劍、織布、裁縫、挖礦、獵人）、2001 年事件任務（除了 1.1 列的入門與俠義任務）、懸賞與賞金獵人、神兵 PvP 轉移、合體技（玉女素心劍法等；資料列先放，`requires` 鎖住）、輕功指令「輕」與 2001 的「閃」按鈕、婚姻（「未婚」條件一律視為成立；M3b 整合：婚姻改到 M5，M3B_PLAN E7）、各派武功任務長鏈（純陽無極功、梯雲縱、太極拳劍、峨嵋九陽／滅劍、重陽劍法…；武功列先放，用 `quest_flag` 鎖住）、峨嵋四象掌（17173 全武功表峨嵋區塊有、研究推測 1.0A 就有，但教者郭襄、羅煞劍隊伍門檻與上限 70 都是後期資料【待考證】→ M3a 不放資料列，M3b 查證後再加；M3a 審查 A9）、畢業與自創門派（M9）、門派比武與武林大會、NPC 執法者在野外追捕（M3a 違規即時押入思過處，§6.6）、玩家「捉拿公敵」指令、**對 NPC 出手**（星宿「PK 丁春秋」、血刀「攻擊血刀老祖」＝叛派【已證實 news 141、jy2-22「嚴禁弒師犯上」】；武當「滅派」、攻擊孫婆婆成古墓公敵）：M3a 沒有對 NPC 下 PK 指令的方法，`sect_rules.event` 的 `ATTACK_SECT_NPC` 保留給 M3b。

### 1.3 擁有者決定（不可更動）

| # | 決定 | 本文怎麼落實 |
|---|---|---|
| O1 | 原作忠實優先；自訂數字標【設計提案】；查不到的標【待考證】並給合理預設 | 全文；§9 數值表 |
| O2 | 走路的世界，沒有傳送（門派內部「引路」除外，§6.8） | §2 接點與步數 |
| O3 | 好友小服 | 規則預設組合可切換（§3.10） |
| O4 | 查看偵察【設計提案・非原作】已核准，要保持可用 | §10.3 驗收含偵察 |

### 1.4 與 GDD／既有資料的偏差（M3a 決議）

| # | 偏差 | 理由（研究） |
|---|---|---|
| D1 | 武當入派善惡改為 **≥ 50**（GDD 寫 −99），並要 **引薦書**（引薦人給） | 2001-07-08 入派條件原文；−99 是 2001-08 的叛派線 |
| D2 | 古墓 **只收女**（GDD 寫男女） | 2001 官方開發頁與 17173 2001-07-08；男女皆收是懷舊版 |
| D3 | 峨嵋的入門劍法是**迴風拂柳劍**；GDD 的「峨嵋劍法」「金頂佛光 em_jf_1」作廢 | 研究：峨嵋劍法不是峨嵋武功 |
| D4 | 古墓沒有「古墓輕功」；輕功是天羅地網勢身法、迎風拂柳步 | 2001 官方開發頁 |
| D5 | 靈鷲宮 1.0 只有天山童姥傳武功；GDD 的周婆婆、蘭劍八荒、李秋水白虹掌是後期名單，不做（蘭劍改教「定性」） | 官方門派頁、事件預告 |
| D6 | 星宿 1.0 核心 6 套武功；飛星術、化功大法【待考證】：飛星術做成資料但 `tier: QUEST` 用 `quest_flag xh_feixing_quest` 鎖住（不能向丁春秋消點；免費版自己的善惡 −1000 門檻也寫上），化功大法不做 | 2018 開服模板只列 6 套（審查 R7） |
| D7 | 血刀入派 **善惡 ≤ −100**；血魔刀法屬 1.0B（要京城），不做 | 2003 攻略「−99 以下」；血魔任務經過京城 |
| D8 | 叛派減半的範圍改為**本門武功**（`sect_id` = 該派的武功），不是 GDD 寫的「特殊武功全部」；`betrayal_halves_basics` 開啟時改為「全部武功與基本武學減半」 | 2001 各派頁「本門武功減半」、jb170 星宿叛派後抽髓掌 20→10；後期官方頁才是全部減半 |
| D9 | 內、穴兩個指令、**全部 10 種門派技能觸發**（含 M1 的 DEFENSE、RECOVER）與 `since: "gmdk"` 的狀態（痲痺、混亂、封穴、內傷、分心）屬於 2002-01-25（決戰光明頂）；M3a 照做，但全部由規則 key `later_battle_cmds` 控制（`classic_strict` 關；`classic_standard` 開）。2001 的狀態（中毒、流血、氣血失調、昏迷、走火入魔；news 316）不受影響 | news 399 第 6、13 條；研究 狀態 2001 清單；審查 R4 |
| D13 | 陣法（陣法武功、基本陣法、陣法狀態、教陣的師父列）era **1.0B**：2001-10-05 隨神鵰大俠開放。1.0A 的渡厄只對話，1.0B patch 加回 TEACH | news 322；審查 R8 |
| D10 | 門規分兩層：**停止傳功**（狀態）與**違反門規**（觸發）。違反門規的後果依規則 key `sect_violation_mode`：`JAIL`（2001-11-15 以後官方：坐牢 1 遊戲日）、`EXPEL`（2001-08 以前：誤觸即叛派）、`BAN`（禁止學武 1 遊戲日）。沒有執法者的門派一律 `BAN` | news 141/160/331/268；GDD 6.5「沒有執法者的門派改成禁止學武」 |
| D11 | `sects.json` 的 `jail_region` 改名 `jail_room`（房間 id）；`expel_rules` 改寫成 `sect_rules.json` 的列 | 少林原本的 `shaolin_jail` 地區不存在 |
| D12 | 門派技能觸發的精／內力（神）消耗只套用在 M3a 新的 8 種效果；既有的 DEFENSE、RECOVER 不改（避免改動 M1 的戰鬥回放金檔與平衡） | 研究有消耗類型、沒有數值；M3b 再統一 |

---

### 1.5 審查記下的原作差距（都已標【設計提案】／【待考證】，等擁有者決定）

| # | 差距 | 現況 |
|---|---|---|
| G1 | 古墓迷宮：2001-07-05 記載怪多、**不能逃跑**、洪凌波／李莫愁會加入；2002 指南每場 4 隻 | 保留不能逃跑（`encounter.no_flee`）；每場 1 隻、約三分之一氣、遇敵率 0.35 是整合時為單人調低的【設計提案・偏離原作】，**待擁有者決定**是否改回多隻；李莫愁不出現 |
| G2 | 恆山犯戒：進不了恆山、不能學、NPC 不理，直到悔過；向誰悔過不明 | `breach_outcome: LOCKOUT`：山門以外進不去、本派師父不教；跟山門的知客弟子交談且門規條件都符合＝悔過【設計提案】 |
| G3 | 全真看門老頭不讓邪惡的人上山，要隊友帶 | `qz_road` 要 善惡 ≥ −299、或全真弟子、或同隊同房 2 人以上【設計提案：−300 界線、「帶」的做法】 |
| G4 | 血刀 威嚇 原作靠恐嚇指令與血池比武練；峨嵋 斷惡 原作靠殺惡人 | M3a 先用師父消點（血刀老祖教威嚇、靜照教斷惡到 20）代替【設計提案】；恐嚇、血池、殺惡人加斷惡留給 M3b |
| G5 | 流血的原作觸發不明（有記載的流血武功 血魔刀法 是 1.0B） | 血刀刀法、萬花劍法第 3 招附帶流血只在 `later_battle_cmds` 開時施加，2001 規則不觸發 |
| G6 | 門派監獄、捉拿公敵 2001-10-05（1.0B）才有 | `classic_strict`（2001-08）`jail_enabled: false`；預設規則照 GDD 決定保留坐牢 |

## 2. 世界接點（2001 地圖）

### 2.1 座標與地區

原作座標 ÷ 24（WORLD_2001 §1.1）。新地區（全部 era `1.0A`；`night_closed: []`；`birth_allowed: false`；`map: "res://data/maps/<id>.json"`）：

| 地區 id | 名稱 | type | world_pos | 依據 | 擁有碎片 | suggested_xp |
|---|---|---|---|---|---|---|
| `wudang_foot` | 武當山下 | WILD | [845, 365] | 內插【設計提案】 | wudang | [0, 3000] |
| `wudang` | 武當派 | SECT | [837, 392] | 20094,9406【已證實】 | wudang | [0, 0] |
| `emei_road` | 峨嵋道 | WILD | [420, 640] | 內插【設計提案】 | emei | [0, 3000] |
| `emei` | 峨嵋派 | SECT | [579, 574] | 13902,13772【已證實】 | emei | [0, 0] |
| `hengshan` | 恆山派 | SECT | [635, 252] | 15243,6043【已證實】 | hengshan | [0, 0] |
| `zhongnan_foot` | 終南山下 | WILD | [700, 505] | 內插【設計提案】 | quanzhen | [0, 2000] |
| `quanzhen` | 全真教 | SECT | [735, 458] | 17630,11000（主讀數）【已證實】 | quanzhen | [0, 0] |
| `gumu` | 古墓派 | SECT | [750, 455] | 17990,10918【後期版】 | gumu | [0, 0] |
| `gumu_maze` | 活死人墓迷宮 | DUNGEON | [762, 468] | 【設計提案】 | gumu | [60000, 120000] |
| `tianshan_road` | 天山道 | WILD | [240, 48] | 【設計提案】（研究：靈鷲屬「邊疆」，近西夏） | lingjiu | [0, 3000] |
| `lingjiu` | 靈鷲宮 | SECT | [190, 30] | 【待考證】（1.0 無座標） | lingjiu | [0, 0] |
| `xingxiu_road` | 星宿海邊 | WILD | [200, 205] | 內插【設計提案】 | xingxiu | [0, 3000] |
| `xingxiu` | 星宿派 | SECT | [142, 192] | 3408,4608【已證實】 | xingxiu | [0, 0] |
| `xuedao_road` | 大漠雪山道 | WILD | [85, 440] | 內插【設計提案】 | xuedao | [0, 3000] |
| `xuedao` | 血刀門 | SECT | [20, 520] | 477,12471【已證實】 | xuedao | [0, 0] |

（可選）`emei_maze` 峨嵋迷宮 DUNGEON [565, 592]：研究找到 10 層線性迷宮圖；M3a 可做 3–5 間的縮短版【設計提案】，不做也不影響驗收。

### 2.2 接點（房間層級；全部雙向出口）

WP-MERGE 改既有房間（新增出口、改 desc，§4.1 `exit_patches`）；新房間由碎片提供。**跨碎片的出口兩邊都要寫**，id 與方向照下表，不得更改。

```
東路：sy_wdfork ─S─ wd_road1 ─S─ wd_road2 ─S─ wd_gate（武當）
                    │W                 │SW
                 wd_woods（武當山下樹林，山賊練功點，死路）
                                       zn_east ◀─┘
南路（新）：dlw_fork ─NE─ em_road1 ─E─ em_road2 ─E─ em_teahouse ─E─ em_road3 ─NE─ em_road4 ─E─ em_foot ─N─ em_gate（峨嵋）
                                                       │S                           │E
                                                    em_bandit（峨嵋山下，山賊，死路）     zn_road1 ─E─ zn_road2 ─NE─ zn_foot ─N─ qz_gate（全真）
                                                                                                    │E        │NE
                                                                                                 zn_backhill  zn_east ─NE─ wd_road2
                                                                                                    │E
                                                                                                 gm_entrance（古墓）
恆山：hf_fork ─N─ hg_shandao ─N─ hg_gate（恆山）
天山：xn_snow ─W─ ts_road1 ─W─ ts_hut（獵戶小屋，休息點）─NW─ ts_road2 ─N─ lj_gate（靈鷲宮）
星宿：ws_dunes ─W─ xh_road1 ─W─ xh_road2 ─W─ xh_gate（星宿海）
血刀：de_cave ─W─ xd_road1 ─W─ xd_road2 ─SW─ xd_tent（牧民帳篷，休息點）─SW─ xd_road3 ─SW─ xd_road4 ─W─ xd_gate（血刀門）
```

圖上不好畫的出口（以這裡為準）：`wd_woods` 接在 `wd_road1` 的 **W**；`em_bandit` 接在 `em_road3` 的 **S**；`zn_river` 接在 `zn_road2` 的 **N**；`zn_foot` 的出口是 SW `zn_road2`、N `qz_gate`、E `zn_backhill`、NE `zn_east`；`zn_east` 的出口是 SW `zn_foot`、NE `wd_road2`；`em_foot` 的出口是 W `em_road4`、N `em_gate`、E `zn_road1`。

| 接點 | 既有房間（WP-MERGE 改） | 新出口 | 新房間（碎片） | 反向出口 |
|---|---|---|---|---|
| 武當 | `sy_wdfork`（songshan_road） | S → `wd_road1` | `wd_road1`（wudang_foot） | N → `sy_wdfork` |
| 峨嵋 | `dlw_fork`（dali_wild） | NE → `em_road1` | `em_road1`（emei_road） | SW → `dlw_fork` |
| 恆山 | `hf_fork`（hengshan_foot） | N → `hg_shandao` | `hg_shandao`（**hengshan_foot**，用 `extra_rooms`） | S → `hf_fork` |
| 終南（峨嵋側） | `em_foot`（emei 碎片） | E → `zn_road1` | `zn_road1`（quanzhen 碎片） | W → `em_foot` |
| 終南（武當側） | `wd_road2`（wudang 碎片） | SW → `zn_east` | `zn_east`（quanzhen 碎片） | NE → `wd_road2` |
| 古墓 | `zn_backhill`（quanzhen 碎片） | E → `gm_entrance` | `gm_entrance`（gumu 碎片） | W → `zn_backhill` |
| 靈鷲 | `xn_snow`（xixia_north） | W → `ts_road1` | `ts_road1`（tianshan_road） | E → `xn_snow` |
| 星宿 | `ws_dunes`（xixia_south） | W → `xh_road1` | `xh_road1`（xingxiu_road） | E → `ws_dunes` |
| 血刀 | `de_cave`（desert_edge） | W → `xd_road1` | `xd_road1`（xuedao_road） | E → `de_cave` |

既有房間的新 desc（WP-MERGE 照貼）：
- `sy_wdfork`「往南的岔路通往武當山，山崩的巨石已經清開，石階上偶有道童往來。這一帶林深，偶爾有山賊出沒。」
- `dlw_fork`「幾條山路在這裡交會。往北通崆峒的路還被落石堵著；往東北的小路已經清開，可以走到峨嵋山和終南山。」
- `hf_fork`「官道在這裡分岔。往北的山路通往恆山派；更北的雁門關有官兵設卡，不許通行。往東南是去華山的華陰道。」
- `xn_snow`（保留原文，句末加）「往西的雪原上有一條踩出來的小徑，聽說通往天山。」
- `ws_dunes`「連綿的沙丘從西邊漫過來。往西有一條插著蛇骨標記的小路通往星宿海，往南的路通往大漠。」
- `de_cave`「風蝕的石山下有個山洞，洞口被沙堵了一半，暫時進不去。往西是更深的大漠，再過去是終年積雪的大雪山，血刀門就在雪山裡。」

### 2.3 步數與新手安全

| 路線（最短步行） | 步數 | 說明 |
|---|---|---|
| `sy_wdfork` → `wd_gate` | 3 | |
| `dlw_fork` → `em_gate` | 7 | 中途 `em_teahouse` 休息點 |
| `em_foot` → `qz_gate` | 4 | `zn_road1`、`zn_road2`、`zn_foot`、`qz_gate` |
| `zn_foot` → `gm_entrance` | 2 | |
| `zn_foot` → `wd_gate` | 3 | `zn_east`、`wd_road2`、`wd_gate` |
| `hf_fork` → `hg_gate` | 2 | |
| `xn_snow` → `lj_gate` | 4 | 中途 `ts_hut` 休息點 |
| `ws_dunes` → `xh_gate` | 3 | |
| `de_cave` → `xd_gate` | 6 | 中途 `xd_tent` 休息點 |
| 大理北門 → 少林山門（新南路） | 21 | 比西路＋東路（32）短；這是原作「大理→少林茶食路線經過武當、終南」的走法【已證實】 |
| 大理北門 → 峨嵋山門 | 11 | |
| 西夏廣場 → 靈鷲宮 | 約 10 | 西夏北郊 → 天山道 |

**必須遵守**（WORLD_2001 §1.4；`tools/data_lint.gd` 的 `check_newbie_routes` 會從兩座出生城檢查到每一座山門）：
1. 休息點：城門、山門房間、茶棚／綠洲／小屋／帳篷（不遇敵、有 `INN` 的 NPC）。離休息點一步的房間也算休息點。新休息點 `em_teahouse`、`ts_hut`、`xd_tent` 各要有一個 `INN` NPC（`inn_price` 10–20）。
2. 兩個相鄰休息點之間：難纏怪（野狼、山豬、山賊）期望 ≤ 0.15 場、山豬 ≤ 0.10、山賊 ≤ 0.015。
3. **緊鄰山門的房間只能有 `m_rabbit`、`m_bigrabbit`**（`wd_road2`、`em_foot`、`hg_shandao`、`zn_foot`、`zn_backhill`（緊鄰 `gm_entrance`）、`ts_road2`、`xh_road2`、`xd_road4`）。
4. 離任何 CITY／SECT 房間 2 步以內不放 `m_bandit`（`wd_woods`、`em_bandit` 刻意放在 3 步外的死路）。
5. 必經路線上的怪 `combat_xp_ref` ≤ 3000，權重 ≤ 10。
6. WILD 房間遇敵率 ≤ 0.15（例外只限死路練功點 `wd_woods`、`em_bandit`：≤ 0.30）。
7. 新路線的 `balance_sim` 走路案例（§10.2）存活率 ≥ 90%。

---

## 3. 資料模型（增量）

### 3.1 `sects.json`（WP-MERGE 合併；所有 10 派同一格式）

既有欄位保留（`id`、`name`、`home_city`、`gate_region`、`gender`、`join_requires`、`sect_skill`、`sect_skill_name`、`sect_skill_effect`、`sect_skill_cost`、`sect_skill_cap`、`sect_skill_limits_arts`、`sect_art_cap_bonus`、`forbid_meat`、`src_note`、`enforcer`、`era`、`src`）。**改名**：`jail_region` → `jail_room`。**刪除**：`expel_rules`（改寫成 `sect_rules`）。**新增**：

```json
{
  "id": "wudang", "name": "武當", "home_city": "dali", "gate_region": "wudang",
  "prefix": "wd",
  "gate_room": "wd_gate",
  "head_npc": "n_wd_zhangsanfeng",
  "gender": ["M"],
  "join_requires": [
    { "type": "morality_min", "value": 50 }, { "type": "no_sect" },
    { "type": "not_enemy_of", "sect": "wudang" }, { "type": "quest_flag", "flag": "wd_recommended" }
  ],
  "teach_requires": [ { "type": "morality_min", "value": 50 } ],
  "sect_skill": "xiayi", "sect_skill_name": "俠義",
  "sect_skill_effect": { "effect": "RESIST" },
  "sect_skill_cost": ["jing", "neili"],
  "sect_skill_cap": 100,
  "sect_skill_limits_arts": false,
  "sect_art_cap_bonus": 10,
  "sect_skill_gain": [],
  "sect_skill_penalties": [],
  "personal_master": false,
  "enforcer": true,
  "enforcers": ["n_wd_songyuanqiao", "n_wd_yudaiyan"],
  "jail_room": "wd_siguo",
  "hostile_entry": [
    { "if": [ { "type": "enemy_of", "sect": "wudang" } ], "rooms": "ALL",
      "monster": "m_wd_guard", "count": [1, 2], "chance": 1.0, "no_flee": true, "capture": true },
    { "if": [ { "type": "morality_max", "value": -101 } ], "rooms": "INNER",
      "monster": "m_wd_guard", "count": [1, 1], "chance": 1.0, "no_flee": false, "capture": false }
  ],
  "visitors": "OPEN",
  "meal_npc": "",
  "src_note": "研究 武當：入派 2001-07-08；俠義＝抗技（官方 2-25）；敵對入山（17173 mengpai/2）",
  "era": "1.0A", "src": "verified"
}
```

| 欄位 | 型別 | 說明 |
|---|---|---|
| `prefix` | String | id 前綴（K5），lint 檢查本派所有 id 以 `<prefix>_` 或 `n_<prefix>_`／`m_<prefix>_`／`ms_<prefix>_` 開頭 |
| `gate_room` | String | 山門房間 id（叛派重入、出獄、開除後送回的地點） |
| `head_npc` | String | 掌門／收徒 NPC；有 `BETRAY` 服務（§6.5） |
| `teach_requires` | Array[條件] | **停止傳功**：不成立時本派所有師父拒絕傳授（含門派技能）；錯誤 `sect_stop_teach` |
| `sect_skill_gain` | Array | 門派技能的額外取得，見 §6.4 |
| `sect_skill_penalties` | Array | 門派技能衰減，見 §6.4 |
| `personal_master` | bool | true（全真）：拜入時的 NPC 記為 `ch.sect_master`，師父列可用 `sect_master` 條件限定只教自己的徒弟 |
| `enforcer` | bool | 有沒有執法者（研究的官方門規頁）；false → 違反門規一律 `BAN` |
| `enforcers` | Array[npc id] | 執法者（顯示用；押送文字用第一位） |
| `jail_room` | String | 思過處房間；`enforcer: false` 時必須是 `""` |
| `hostile_entry` | Array | 敵對入山（§6.7）。`rooms`：`"GATE"`／`"INNER"`（山門以外的本派房間）／`"ALL"`；`if` 的條件**全部成立**才觸發；`capture`：在這場戰鬥中死亡會被押入本派思過處（§6.6） |
| `visitors` | enum | `"OPEN"`（非本派可進）／`"MEMBERS"`（`INNER` 房間只許本派與「現在就能拜入的人」，用房間 `requires` 的 `any_of` 實作，見 3.6）；純資訊欄，lint 檢查與房間 `requires` 一致 |
| `meal_npc` | String | 有齋飯時辰的門派填 NPC id（顯示用） |

`sect_skill_effect.effect` 的值：`DEFENSE`（少林）、`RECOVER`（華山）、`RESIST`（武當）、`EVADE`（峨嵋）、`COUNTER`（恆山）、`REST`（全真）、`PARALYZE`（古墓）、`CONFUSE`（靈鷲）、`DISTRACT`（星宿）、`HEAVY`（血刀）、`POISON_FANG`（丐幫，M3b）。

**既有兩派的遷移**（WP-MERGE）：少林 `prefix "sl"`、`gate_room "sl_gate"`、`head_npc "n_sl_zhike"`、`jail_room "sl_siguo"`、`enforcers ["n_sl_puzhi"]`、`teach_requires` 見 §6.2；華山 `prefix "hs"`、`gate_room "hs_gate"`、`head_npc "n_yuebuqun"`、`jail_room ""`、`enforcer false`。兩派都補 `hostile_entry: []`、`visitors "OPEN"`、`sect_skill_gain []`、`sect_skill_penalties []`、`personal_master false`。

### 3.2 各派固定 id（綁定；acceptance bot 與其他 WP 依此寫）

| 門派 | prefix | 性別 | 入派條件（`join_requires` 摘要） | 門派技能 id／名稱／效果／消耗 | `limits_arts` | 收徒 NPC（房間） | 入門師父 | 入門兩套（先學門派技能） | 驗收招式 | 驗收指令 | 切磋 NPC → 怪 | 思過處 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 武當 | wd | M | 善惡 ≥ 50、無門派、非公敵、`wd_recommended` | `xiayi` 俠義／RESIST／精＋內力 | false | `n_wd_zhangsanfeng`（`wd_neitang`） | `n_wd_yudaiyan` | `wd_changquan`、`wd_xinfa` | `wd_cq_1` | 內（HEAL） | `n_wd_spar` → `m_wd_dizi` | `wd_siguo` |
| 峨嵋 | em | F | 善惡 ≥ −299、無門派、非公敵 | `duane` 斷惡／EVADE／精＋神 | false | `n_em_miejue`（`em_miejue`） | `n_em_jingjia` | `em_piaoxue`、`em_xinfa` | `em_px_1` | 內（HEAL） | `n_em_spar` → `m_em_dizi` | `em_siguo` |
| 恆山 | hg | F | 善惡 ≥ 0、PK = 0、無門派、非公敵 | `cibei` 慈悲／COUNTER／精＋內力 | true | `n_hg_dingxian`（`hg_hall`） | `n_hg_yihe` | `hg_jianfa`、`hg_xinfa` | `hg_jf_1` | 醫 | `n_hg_spar` → `m_hg_dizi` | （無，enforcer false） |
| 全真 | qz | M | 善惡 ≥ 0、無門派、非全真／古墓公敵 | `yangsheng` 養生／REST／精＋神 | true | `n_qz_qiuchuji`（`qz_sanqing`；七子任一皆可收徒） | `n_qz_qiuchuji` | `qz_jianfa`、`qz_xinfa` | `qz_jf_1` | 內（HEAL） | `n_qz_spar` → `m_qz_dizi` | `qz_siguo` |
| 古墓 | gm | F | 善惡 −299…299、無門派、非公敵 | `qingxin` 清心／PARALYZE／精＋神 | true | `n_gm_zhangmen`（`gm_hall`） | `n_gm_zhangmen` | `gm_yunu_jian`、`gm_xinfa` | `gm_yn_1` | 內（HEAL） | `n_gm_spar` → `m_gm_dizi` | `gm_shishi` |
| 靈鷲 | lj | F | 善惡 −299…299、PK ≤ 3、無門派、非公敵 | `dingxing` 定性／CONFUSE／精＋神 | true | `n_lj_tonglao`（`lj_hall`） | `n_lj_tonglao` | `lj_zhemei`、`lj_xiaoyao` | `lj_zm_1` | 穴 | `n_lj_spar` → `m_lj_dizi` | （無） |
| 星宿 | xh | M, F | 善惡 ≤ −100、無門派、非公敵 | `chanmei` 諂媚／DISTRACT／精＋神 | true | `n_xh_dingchunqiu`（`xh_hall`） | `n_xh_dingchunqiu` | `xh_chousui`、`xh_xinfa`（另學 `xh_fangdu` 供毒） | `xh_cs_1` | 毒 | `n_xh_spar` → `m_xh_dizi` | （無） |
| 血刀 | xd | M | 善惡 ≤ −100、無門派、非公敵 | `weihe` 威嚇／HEAVY／精＋內力 | false | `n_xd_laozu`（`xd_hall`） | `n_xd_shengdi` | `xd_daofa`、`xd_xinfa` | `xd_df_1` | 內（HEAL） | `n_xd_spar` → `m_xd_dizi` | （無） |
| 少林（既有） | sl | M | 不變 | `foxa` | true | `n_sl_zhike` | `n_sl_huizhen` | — | — | 陣（十八銅人後） | — | `sl_siguo`（新） |
| 華山（既有） | hs | M, F | 不變 | `rufeng` | false | `n_yuebuqun` | — | — | — | — | — | （無） |

- 門派技能師父（`masters` 列，`skill_id` = 門派技能 id，`cap` 50，`price` 0，`requires: [{ "type": "sect", "sect": "<id>" }]`）：武當 `n_wd_songyuanqiao`（cap **20**；研究：2001 俠義只能靠任務，所以只給起步的 20 級【設計提案】）、峨嵋 `n_em_jingzhao`（cap 20，同理：斷惡靠殺惡人）、恆山 `n_hg_yusao`、全真 `n_qz_yinzhiping`、古墓 `n_gm_zhangmen`、靈鷲 `n_lj_lanjian`、星宿 `n_xh_shihouzi`、血刀 `n_xd_laozu`。
- 驗收的入門學習順序：**基本內功 → 打坐** → 門派技能 ≥ 1 → 心法 → 拳／劍／刀（`limits_arts: true` 的門派，武功上限 = 門派技能等級 + 10）。門派技能消點的額外消耗看 `sects.sect_skill_train_cost`（審查 R3；`sect_skill_cost` 是戰鬥觸發的消耗），新派都不再要內力，先學基本內功只是讓之後的心法、運功有內力可用。
- 入門兩套武功的 `requires` 只能有 `sect`（以及 `limits_arts` 機制本身），**不能**有屬性或其他武功門檻（新角色要學得到）。
- 驗收招式 `unlock_level` 必須是 1；`aoe` 是 `SINGLE` 或 `CROSS`；`range` ≥ 1。
- 切磋怪 `m_<p>_dizi`：比照 `m_hs_trainee`（氣 200–260、`no_rewards: true`、`morality_on_kill: 0`、`killing_intent_on_kill: 0`、會本派一套入門武功 8 級）；`n_<p>_spar` 是 `FUNC` NPC，`services: ["FIGHT"]`，`fight.requires: [{ "type": "sect", "sect": "<id>" }]`，放在本派練武場。
- 武當入門任務 `q_wd_yinjian`：給予者 `n_wd_yinjian`（引薦人，房間 `wd_road2`）；`requires` = 男、善惡 ≥ 50、無門派；接下時給 `i_wd_yinjianshu`（引薦書，`quest_item: true`）；步驟 `DELIVER i_wd_yinjianshu → n_wd_zhangsanfeng`；獎勵 `flags: ["wd_recommended"]`。
- 星宿毒指令：`xh_fangdu`（放毒法，category `POISON`，丁春秋教，`requires` 只有 `sect` 與 `skill_min basic_poison 1`）；丁春秋也教 `basic_poison`（cap 140）。
- 靈鷲點穴：`lj_zhemei`（天山折梅手，category `FIST`，`acupoint: true`，係數 1.25 沿用 GDD）。
- 恆山醫指令：`n_hg_yizhen`（儀真）教 `basic_medic`（cap 140）；`hg_yishu`（恆山醫術，category `MEDIC`）由儀和教【待考證：1.0A 教者不明】。

### 3.3 `sect_rules.json`（WP-MERGE 合併；一列一條門規）

```json
{ "id": "wd_r_morality", "sect": "wudang", "tier": "BREACH", "kind": "STATE", "modes": ["JAIL", "BAN"],
  "ok_if": [ { "type": "morality_min", "value": -299 } ],
  "text": "rule_wd_morality", "era": "1.0A", "src": "verified",
  "src_note": "官方門規頁 index_jy2-22（2001-11-15 起的坐牢名單）：善惡 < −299" }
{ "id": "wd_r_morality_npc_a", "sect": "wudang", "tier": "BREACH", "kind": "STATE", "modes": ["EXPEL"],
  "on_npc": ["n_wd_zhangsanfeng", "n_wd_yudaiyan", "…"], "ok_if": [ { "type": "morality_min", "value": -99 } ], … }
{ "id": "wd_r_kill_same", "sect": "wudang", "tier": "BREACH", "kind": "EVENT",
  "event": "KILL_SAME_SECT", "text": "rule_wd_kill_same", "era": "1.0A", "src": "verified" }
```

| 欄位 | 說明 |
|---|---|
| `tier` | `"BREACH"`（違反門規；後果依 §6.3）。停止傳功不寫在這裡，寫在 `sects.teach_requires`。 |
| `kind` | `"STATE"`：`ok_if` 任一條件不成立 → 違規（只在「成立 → 不成立」的轉換時觸發一次，§6.3）。`"EVENT"`：事件發生時觸發。 |
| `event` | `"KILL_SAME_SECT"`（強制 PK 殺死同門玩家，§6.3）、`"ENTER_REGION"`（`event_arg` = 地區 id；例：全真弟子進古墓）。其他值保留給 M3b（`ATTACK_SECT_NPC`、`MARRY`），lint 拒絕。 |
| `text` | 模板 key（`self` 變體說明違反了什麼），由該派碎片提供 |
| `modes` | （選填，審查 R1）這一列適用的 `sect_violation_mode`：`["JAIL", "BAN"]` = 2001-11-15 以後官方的坐牢名單（jy2-22），`["EXPEL"]` = 2001-08 的叛派名單（news 141）。沒寫 = 全部模式 |
| `on_npc` | （選填，STATE 才有）只在跟這些 NPC 交談時檢查（武當 2001-08：善惡 < −99／−199 時與特定師長交談即叛派）；走路、TICK 不檢查 |

`sects.expel_rules` 刪除；少林原本的 `{ "type": "killing_intent_over", "value": 2000 }` 改寫成 `sl_r_killing`（`ok_if: [{ "type": "killing_intent_max", "value": 2000 }]`）。

### 3.4 `martial_arts.json`（增量）

既有欄位不變。**新增**（全部選填，預設值如右）：

| 欄位 | 預設 | 說明 |
|---|---|---|
| `tier` | `"BASIC"` | `BASIC`／`ADVANCED`／`SPECIAL`／`QUEST`（顯示與 lint 用；`QUEST` 必須有 `quest_flag` 條件） |
| `acupoint` | false | 可用來點穴（穴指令，§5.5） |
| `formation` | null | 陣法：`{ "party_size": 3, "stations": [[0,0],[-1,1],[1,1]], "gender": "", "atk_bonus": 0.10, "def_bonus": 0.20, "per_avg_level": 0.002 }`；`category` 必須是 `FORMATION` |
| `inner` | null | 內功：`{ "heal_mult": 1.0, "expel_mult": 1.0 }`；`category` 必須是 `INNER` |
| `poison` | null | 毒術：`{ "status": "poison", "level_bonus": 0 }`；`category` 必須是 `POISON` |
| `medic` | null | 醫術：`{ "heal_mult": 1.0 }`；`category` 必須是 `MEDIC` |
| `hidden` | null | 暗器功夫：`{ "range_bonus": 1 }`；`category` 必須是 `HIDDEN` |
| `combo` | false | 合體技（M3a 不可用；資料列先放） |

`category` 合法值：`FIST BLADE SWORD STAFF WHIP SPEAR STAB INNER LIGHTNESS HIDDEN POISON MEDIC FORMATION`（`STAB` 新增：筆、刺類，基本武學 `basic_stab`；例：武當倚天屠龍筆法）。
`moves[].aoe` 合法值：`SINGLE CROSS CROSS_L LINE FAN AROUND`（§5.3）。`moves[]` 其餘欄位不變（`status`、`status_chance` 指向 `status_effects`）。
`POISON`／`MEDIC`／`HIDDEN` 武功也要有至少一招（`moves[0]` 決定射程、內力消耗、威力），招式 `flavor` 用 §5.9 的模板。

範例（研究：星宿每招都可能帶毒）：

```json
{ "id": "xh_chousui", "name": "抽髓掌", "sect_id": "xingxiu", "category": "FIST", "base_skill": "basic_fist",
  "difficulty": 0.87, "tier": "BASIC", "self_study_until": 0, "self_study_cap": 0, "party_size": 0, "monster_only": false,
  "requires": [ { "type": "sect", "sect": "xingxiu" } ],
  "desc": "以毒為本的掌法，掌風帶著腥甜的氣味。", "era": "1.0A", "src": "verified",
  "src_note": "研究 星宿：2018 開服模板 6 套之一；係數 0.87（巴哈 2004）",
  "moves": [
    { "id": "xh_cs_1", "name": "腐骨穿心", "unlock_level": 1, "power": 22, "range": 1, "aoe": "SINGLE",
      "cost_inner": 2, "cost_jing": 0, "status": "poison", "status_chance": 0.15, "flavor": "move_palm_poison", "src": "proposal" },
    { "id": "xh_cs_2", "name": "抽髓吸血", "unlock_level": 40, "power": 34, "range": 1, "aoe": "SINGLE",
      "cost_inner": 8, "cost_jing": 0, "status": "poison", "status_chance": 0.25, "flavor": "move_palm_poison", "src": "proposal" }
  ] }
```

**招式數值的上下限**（lint 檢查；比照少林／華山）：入門武功 3 招（解鎖 1／30／60），威力 18–48；進階 2–4 招，威力 30–70；`cost_inner` ≤ 威力 ÷ 2；`status_chance` ≤ 0.35；範圍招式（非 SINGLE）威力 × 0.75 再取整（多目標補償）。

### 3.5 `masters.json`（增量）

形狀不變；新增選填欄位 `hours: ["卯","酉"]`（只在這些時辰教；空陣列 = 全天）。新條件型別 `sect_master`（3.7）用在全真七子各自的列。武功能教到幾級仍放在 `cap`（例：研究「滅絕只教 1 級」→ `ms_em_miejue_jiuyang` 的 `cap: 1`，其餘自修）。

### 3.6 地圖與房間（增量）

`data/maps/<region>.json` 形狀不變（M1_PLAN 3.11.8）。房間新增選填欄位：

| 欄位 | 說明 |
|---|---|
| `jail: true` | 思過處。只有坐牢中的人與本派弟子能進（`requires` 自己寫 `sect`），坐牢中的人走不出去（§6.6） |
| `encounter_exempt: ["gumu"]` | 這些門派的弟子在此房間不踩地雷、不能偵察（古墓迷宮「專人帶路」【已證實】） |
| `meditate: { "mult": 1.5, "drain_pct": 0.05 }` | 修煉內力加成與每次扣精氣神百分比（古墓寒玉床【已證實：有加成、精氣神大降；數值設計提案】） |
| `exits[].era` | 既有（M1_PLAN 3.11.8） |

`requires` 的 `any_of` 條件（3.7）用來做「非本派只能到山門」：

```json
"requires": [ { "type": "any_of", "options": [
  [ { "type": "sect", "sect": "lingjiu" } ],
  [ { "type": "no_sect" }, { "type": "gender", "value": "F" }, { "type": "morality_min", "value": -299 },
    { "type": "morality_max", "value": 299 }, { "type": "pk_max", "value": 3 }, { "type": "not_enemy_of", "sect": "lingjiu" } ]
] } ]
```

`features` 合法值不變（`FIELD WOOD WATER STOVE`）。

### 3.7 條件型別（`core/data/data_schema.gd` 與 `core/character/requirements.gd`，WP-RULES）

新增：

| type | 欄位 | 成立條件 |
|---|---|---|
| `has_item` | `item`, `n`（選填，預設 1） | 身上有 ≥ n 個 |
| `any_of` | `options: [[條件…], [條件…]]` | 任一組全部成立（巢狀，最多 2 層；lint 檢查每個內層條件） |
| `enemy_of` | `sect` | `sect` 在 `ch.sect_enemies` 裡 |
| `pk_min` | `value` | PK值 ≥ value |
| `killing_intent_min` | `value` | 殺氣 ≥ value |
| `sect_master` | `npc` | `ch.sect_master == npc` |
| `party_size_min` | `value` | 同隊、同房間、不在戰鬥中的隊員（含自己）≥ value（只在主機端有 session 時判定；純角色判定時視為不成立） |
| `hour_in` | `hours: ["卯","午"]` | 現在的時辰在清單內（主機用 `host.clock()`；純角色判定時視為成立） |

`Requirements.check` 回傳的原因碼照舊：`"req_" + type`（例：`req_has_item`）。`any_of` 失敗回 `req_any_of`。

### 3.8 `status_effects.json`（WP-CMD 擁有；Day-0 照貼）

> 審查 R5 之後以 `data/status_effects.json` 為準（11 列：多了氣血失調 `qixue`、昏迷 `coma`、走火入魔 `zouhuo`；新欄位 `since`、`qi_max_pct_per_action`、`src_note`；痲痺、流血、內傷的數值與標記已改）。下面是 Day-0 原稿。

形狀（全部欄位都要寫；未用到的填預設）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id`, `name` | String | |
| `kind` | `DEBUFF`／`BUFF` | |
| `glyph` | String（1 字） | 單位頭上的小字圖示 |
| `color` | String | `#rrggbb`（原作狀態色【已證實 news 316】：中毒綠、氣血失調藍、昏迷灰、走火紫、流血紅） |
| `duration_actions` | int | 基本持續行動數（§5.7 定力縮短） |
| `stack` | `REFRESH`／`LEVEL_MAX` | 重複施加：重設次數／取較高等級並重設次數 |
| `blocks` | Array[cmd] | 這些指令不能用 |
| `skip_actions` | bool | 輪到時直接跳過（消耗一次） |
| `random_action` | bool | 輪到時自動亂打（混亂） |
| `atk_mult`, `def_mult`, `gauge_mult` | float | 預設 1.0 |
| `qi_pct_per_action` | float | 每次行動開始扣氣上限的比例（不致死於 1 以下以外：扣到 1 即死亡，沿用內傷寫法） |
| `qi_pct_per_level` | float | 有等級時每級再加 |
| `qi_pct_per_move` | float | 每次「移」扣 |
| `resist_by` | Array[effect] | 有這個門派技能效果的單位可觸發抵抗（`RESIST`） |
| `cure_by` | Array | `ANTIDOTE`（藥）、`MEDIC`（醫，僅 `later_battle_cmds`）、`INNER_EXPEL`、`INNER_UNSEAL`、`AUTO` |
| `persists` | bool | 戰鬥結束後帶回角色（§6.10） |
| `persist_tick_real_s` | int | 戰後發作間隔（上線秒） |
| `persist_ticks_per_level` | int | 戰後總發作次數 = 等級 × 此值 |
| `persist_qi_pct` | float | 每次戰後發作扣氣上限比例（扣到 1 為止，**不致死**） |
| `era`, `src`, `desc` | | |

Day-0 列（數值【設計提案】，原作有的行為【已證實】在 desc 註明）：

```json
{ "table": "status_effects", "version": 2, "rows": [
  { "id": "inner_wound", "name": "內傷", "kind": "DEBUFF", "glyph": "傷", "color": "#8a4b9c", "duration_actions": 5, "stack": "REFRESH",
    "blocks": ["REST"], "skip_actions": false, "random_action": false, "atk_mult": 1.0, "def_mult": 1.0, "gauge_mult": 1.0,
    "qi_pct_per_action": 0.02, "qi_pct_per_level": 0.0, "qi_pct_per_move": 0.0, "resist_by": [], "cure_by": ["AUTO"],
    "persists": false, "persist_tick_real_s": 0, "persist_ticks_per_level": 0, "persist_qi_pct": 0.0,
    "desc": "氣血翻湧，無法調息；每次行動損失 2% 氣上限。", "era": "1.0A", "src": "proposal" },
  { "id": "poison", "name": "中毒", "kind": "DEBUFF", "glyph": "毒", "color": "#3c9a3c", "duration_actions": 6, "stack": "LEVEL_MAX",
    "blocks": [], "skip_actions": false, "random_action": false, "atk_mult": 1.0, "def_mult": 1.0, "gauge_mult": 1.0,
    "qi_pct_per_action": 0.02, "qi_pct_per_level": 0.004, "qi_pct_per_move": 0.0, "resist_by": ["RESIST"],
    "cure_by": ["ANTIDOTE", "MEDIC", "INNER_EXPEL"],
    "persists": true, "persist_tick_real_s": 120, "persist_ticks_per_level": 2, "persist_qi_pct": 0.03,
    "desc": "每次行動都扣氣；離開戰鬥後每 2 分鐘發作一次（已證實 news 316），直到藥效時間結束。", "era": "1.0A", "src": "verified" },
  { "id": "acupoint", "name": "封穴", "kind": "DEBUFF", "glyph": "穴", "color": "#c8a020", "duration_actions": 3, "stack": "REFRESH",
    "blocks": ["MOVE", "FLEE"], "skip_actions": false, "random_action": false, "atk_mult": 1.0, "def_mult": 1.0, "gauge_mult": 0.6,
    "qi_pct_per_action": 0.0, "qi_pct_per_level": 0.0, "qi_pct_per_move": 0.0, "resist_by": [], "cure_by": ["INNER_UNSEAL", "AUTO"],
    "persists": false, "persist_tick_real_s": 0, "persist_ticks_per_level": 0, "persist_qi_pct": 0.0,
    "desc": "穴道受制，無法移動，時間棒變慢（後期版 2002-01-25）。", "era": "1.0A", "src": "later" },
  { "id": "paralysis", "name": "痲痺", "kind": "DEBUFF", "glyph": "痺", "color": "#5a5a5a", "duration_actions": 1, "stack": "REFRESH",
    "blocks": [], "skip_actions": true, "random_action": false, "atk_mult": 1.0, "def_mult": 1.0, "gauge_mult": 1.0,
    "qi_pct_per_action": 0.0, "qi_pct_per_level": 0.0, "qi_pct_per_move": 0.0, "resist_by": ["RESIST"], "cure_by": ["AUTO"],
    "persists": false, "persist_tick_real_s": 0, "persist_ticks_per_level": 0, "persist_qi_pct": 0.0,
    "desc": "四肢發麻，跳過下一次行動（古墓清心觸發）。", "era": "1.0A", "src": "proposal" },
  { "id": "confusion", "name": "混亂", "kind": "DEBUFF", "glyph": "亂", "color": "#d8c040", "duration_actions": 2, "stack": "REFRESH",
    "blocks": [], "skip_actions": false, "random_action": true, "atk_mult": 1.0, "def_mult": 1.0, "gauge_mult": 1.0,
    "qi_pct_per_action": 0.0, "qi_pct_per_level": 0.0, "qi_pct_per_move": 0.0, "resist_by": ["RESIST"], "cure_by": ["AUTO"],
    "persists": false, "persist_tick_real_s": 0, "persist_ticks_per_level": 0, "persist_qi_pct": 0.0,
    "desc": "神智錯亂，不分敵我亂打（靈鷲定性觸發）。", "era": "1.0A", "src": "proposal" },
  { "id": "distract", "name": "分心", "kind": "DEBUFF", "glyph": "分", "color": "#6aa0c8", "duration_actions": 3, "stack": "REFRESH",
    "blocks": [], "skip_actions": false, "random_action": false, "atk_mult": 0.8, "def_mult": 1.0, "gauge_mult": 1.0,
    "qi_pct_per_action": 0.0, "qi_pct_per_level": 0.0, "qi_pct_per_move": 0.0, "resist_by": [], "cure_by": ["AUTO"],
    "persists": false, "persist_tick_real_s": 0, "persist_ticks_per_level": 0, "persist_qi_pct": 0.0,
    "desc": "心神不寧，攻擊力下降兩成（星宿諂媚觸發）。", "era": "1.0A", "src": "proposal" },
  { "id": "bleed", "name": "流血", "kind": "DEBUFF", "glyph": "血", "color": "#c03030", "duration_actions": 4, "stack": "REFRESH",
    "blocks": [], "skip_actions": false, "random_action": false, "atk_mult": 1.0, "def_mult": 1.0, "gauge_mult": 1.0,
    "qi_pct_per_action": 0.0, "qi_pct_per_level": 0.0, "qi_pct_per_move": 0.03, "resist_by": [], "cure_by": ["ANTIDOTE", "AUTO"],
    "persists": false, "persist_tick_real_s": 0, "persist_ticks_per_level": 0, "persist_qi_pct": 0.0,
    "desc": "傷口流血，戰鬥中每走一步就損氣（已證實 2001-08-09；觸發來源待考證）。", "era": "1.0A", "src": "verified" },
  { "id": "formation", "name": "陣法", "kind": "BUFF", "glyph": "陣", "color": "#d0a050", "duration_actions": 6, "stack": "REFRESH",
    "blocks": [], "skip_actions": false, "random_action": false, "atk_mult": 1.0, "def_mult": 1.0, "gauge_mult": 1.0,
    "qi_pct_per_action": 0.0, "qi_pct_per_level": 0.0, "qi_pct_per_move": 0.0, "resist_by": [], "cure_by": [],
    "persists": false, "persist_tick_real_s": 0, "persist_ticks_per_level": 0, "persist_qi_pct": 0.0,
    "desc": "結陣加持：攻防依陣法平均等級提高；有人倒下或移動即破陣（加成值由陣法武功決定）。", "era": "1.0A", "src": "proposal" }
] }
```

### 3.9 `items.json`（增量；物品列由 `_cmd.json` 碎片提供，WP-MERGE 合併）

新 `effects[].type`：

| type | 欄位 | 說明 |
|---|---|---|
| `hidden` | `value`（敵人傷氣）, `poisonable`（bool） | 暗器彈藥；暗指令每丟一次消耗 1 個【待考證：原作沒寫，預設消耗】 |
| `cure` | `status`, `max_level` | 解除狀態（中毒等級 ≤ max_level 才能解） |

新物品（`_cmd.json`，WP-CMD 撰寫；`tab: "OTHER"`、`slot: ""`、`stack: 99`）：

| id | 名稱 | effects | 重量 | 價格 | usable／in_battle | 依據 |
|---|---|---|---|---|---|---|
| `h_dangong` | 彈弓 | hidden 2, poisonable | 1 | 30 | false／false | 官方暗器頁【已證實】；價格【設計提案】 |
| `h_jinqianbiao` | 金錢鏢 | hidden 8 | 1 | 60 | 同上 | 同上 |
| `h_feihuangshi` | 飛蝗石 | hidden 12 | 1 | 90 | 同上 | 同上 |
| `h_tieling` | 鐵菱 | hidden 20 | 2 | 150 | 同上 | 同上 |
| `h_yubiao` | 魚鏢 | hidden 20 | 2 | 150 | 同上 | 同上 |
| `h_tielianzi` | 鐵蓮子 | hidden 35 | 2 | 300 | 同上 | 同上 |
| `c_jieduyao` | 解毒藥 | cure poison ≤ 5 | 1 | 150 | true／true | 「一般的毒吃解毒藥」【已證實】 |
| `c_jiedulingyao` | 解毒靈藥 | cure poison ≤ 10 | 1 | 600 | true／true | 2001 任務獎勵物【已證實】；販售【設計提案】 |

WP-MERGE：西夏、大理兵器鋪（`n_xx_smith`、大理的兵器商）加賣 `h_jinqianbiao`、`h_feihuangshi`；兩城藥鋪加賣 `c_jieduyao`。星宿 `n_xh_*` 商人可賣 `h_tieling`（星宿碎片自行決定）。

物品新欄位（選填）：`sect_only: "<sect_id>"`（叛派時沒收，研究 news 317【已證實】）。

### 3.10 規則與伺服器選項（WP-RULES）

`data/rule_profiles.json` 每個預設組合加兩個 key；`DataSchema.RULE_DEFAULTS`／`RULE_ENUMS` 同步：

| key | 型別 | classic_strict | classic_standard | later_official | friends_casual | 預設 |
|---|---|---|---|---|---|---|
| `sect_violation_mode` | `JAIL`／`EXPEL`／`BAN` | `EXPEL` | `JAIL` | `JAIL` | `BAN` | `JAIL` |
| `later_battle_cmds` | bool | false | true | true | true | true |

`jail_enabled: false` 時 `JAIL` 視同 `BAN`。

`data/server_options.default.json` 新 key（INT 的加進 `DataSchema.INT_FIELDS.server_options`）：

| key | 預設 | 說明 |
|---|---|---|
| `jail_breach_days` | 1 | 違反門規坐牢遊戲日【已證實】 |
| `jail_enemy_days` | 3 | 公敵被抓坐牢遊戲日【已證實】 |
| `ban_days` | 1 | 禁止學武遊戲日（事件型違規、無執法者的門派）【設計提案】 |
| `jail_ransom` | 100000 | 贖人金額（兩）【已證實 10 萬】 |
| `sect_hostile_entry` | true | 敵對入山開關 |
| `poison_flare_enabled` | true | 戰後中毒發作開關 |

`AdminSystem.EDITABLE_KEYS` 加 `"sect_hostile_entry"`（標籤「門派敵對入山」）；`preset_desc` 的叛派文字改成實際規則說明（§6.5）。

### 3.11 角色（`core/character/**`，WP-RULES）

`Character.SCHEMA_VERSION` 1 → 2（`from_dict` 讀舊檔補預設）。新欄位：

| 欄位 | 預設 | 說明 |
|---|---|---|
| `sect_master: String` | `""` | 全真等 `personal_master` 門派的師父 NPC id |
| `sect_record: Dictionary` | `{ "joined_online_s": 0.0, "breached": {}, "ban_until_online_s": 0.0, "history": [] }` | `breached[rule_id] = true` 表示這條狀態規則目前處於違規（避免重複觸發）；`history` 最多 20 筆 `{ sect, what: JOIN/BETRAY/EXPEL/JAIL/RELEASE, online_s }` |
| `jail: Dictionary` | `{}` | 坐牢中：`{ "sect", "room", "until_online_s", "reason": "BREACH"/"ENEMY", "rule": "" }` |
| `conditions: Dictionary` | `{}` | 戰後持續狀態：`status_id -> { "level": int, "ticks_left": int, "next_online_s": float }` |

新方法（純邏輯，不碰 host）：`is_jailed() -> bool`、`jail_left_s() -> float`、`add_condition(id, level, ticks, next_online_s)`、`clear_condition(id)`、`condition_level(id) -> int`、`betray_penalty(tables, rules) -> Dictionary`（套用 §6.5 的減半，回傳 `{ arts: {id: [before, after]}, sect_skill: [before, 0], items_removed: [...] }`；`ch.sect` 清空、加入 `sect_enemies`）。

`to_combatant()` 新增欄位（WP-CMD 依此寫戰鬥；WP-RULES 負責填）：

```
"gender": "M"/"F",
"sect": "<sect_id 或 ''>",
"cmd_arts": { "POISON": [art_id…], "MEDIC": […], "HIDDEN": […], "FORMATION": […], "INNER": […], "ACUPOINT": […] },
   # INNER 依等級高到低；ACUPOINT = acupoint:true 的武功（任何類別）
"hidden_items": [ { "uid", "item_id", "name", "n", "dmg" } ],         # effects 有 hidden 的堆疊
"battle_items": [ { "uid", "item_id", "name", "n", "effects": [...] } ], # usable_in_battle 的物品
"statuses": { "poison": { "n": 6, "level": 2 } },                       # 由 conditions 轉入（戰後持續的狀態帶進戰鬥）
"party_id": "<隊伍 id 或 ''>"
```

`arts`（可出招的武功）的類別白名單 `CharData.BATTLE_CATEGORIES` 加 `STAB`。

---

## 4. 碎片格式（`docs/m3a_staging/<id>.json`）

### 4.1 結構（每個門派建造者**只寫自己的一個檔案**）

```json
{
  "fragment": "wudang",
  "version": 1,
  "author": "WP-SECT-wudang",
  "sect": { "...sects 一列，形狀見 3.1..." },
  "sect_rules": [ "...3.3..." ],
  "regions": [ { "id": "wudang", "name": "武當派", "type": "SECT", "city": "dali", "map": "res://data/maps/wudang.json",
                 "world_pos": [837, 392], "suggested_xp": [0, 0], "pk_allowed": false, "birth_allowed": false,
                 "birth_room": "", "night_closed": [], "era": "1.0A", "src": "verified" } ],
  "maps": {
    "wudang":      { "region_id": "wudang", "era": "1.0A", "src": "proposal", "desc": "…", "escape_tiles_hint": 2, "rooms": [ "..." ] },
    "wudang_foot": { "region_id": "wudang_foot", "era": "1.0A", "src": "proposal", "desc": "…", "escape_tiles_hint": 2, "rooms": [ "..." ] }
  },
  "extra_rooms": { "hengshan_foot": [ "…只有恆山用：hg_shandao…" ] },
  "exit_patches": [ { "room": "sy_wdfork", "add_exits": [ { "dir": "S", "to": "wd_road1" } ], "desc": "…§2.2 的新 desc…" } ],
  "npcs": [ "..." ], "masters": [ "..." ], "martial_arts": [ "..." ], "monsters": [ "..." ],
  "items": [ "..." ], "quests": [ "..." ], "text_templates": [ "..." ],
  "art_requests": {
    "units": [ { "id": "wudang_m", "alias": "shaolin_m", "prompt": "武當道袍男弟子，青灰道袍、髮髻、背劍……" },
               { "id": "n_wd_zhangsanfeng", "alias": "n_sl_huizhen", "prompt": "…" } ],
    "backgrounds": [ { "id": "wudang", "alias": "huashan", "prompt": "…" }, { "id": "wudang_foot", "alias": "songshan_road" } ]
  },
  "todo_verify": [ "柔雲劍法 大十字 13 格或 10 格【待考證】", "…" ],
  "notes": "…"
}
```

- 每個陣列的列形狀**完全照** `data/<table>.json` 現有列（以少林、華山為範本）加本文件的新欄位。每列都要有 `era`、`src`；有研究依據的加 `src_note`。
- `exit_patches` 只能「加出口、換 desc」，不能刪出口。只有接點表（2.2）列出的既有房間能被改。
- `extra_rooms`：加到**既有**地區地圖的房間（只有恆山的 `hg_shandao`）。
- `art_requests.units` 一定要有本派允許性別的 `<sect_id>_m`／`<sect_id>_f`（戰鬥外觀 `battle_look()`）、每個 NPC、每個新怪；`alias` 指到 `data/art.json` **現有**的條目（WP-MERGE 照填 `alias`，之後擁有者給真圖）。`backgrounds` 每個新地區一條。
- `text_templates`：每個 NPC 的 `talk_<npc_id>`（`self` 變體，句子裡用 `{npc_name}`）、每條門規的 `text`、本派新招式用到的新 `flavor`（若用既有的 `move_*` 可省略）、任務文字。形狀照既有模板列（`id`、`era`、`self`／`target`／`other`、`src`）。
- 文字：繁體中文；房間 desc 1–2 句；不得有簡體字（lint 有檢查）。
- 檔案必須是合法 JSON（`python -c "import json;json.load(open(p,encoding='utf-8'))"` 通過）。

### 4.2 每個門派碎片的必備內容（WP-SECT 檢查清單）

共同：
1. `sect` 列（3.1，3.2 的固定值不得改）、`sect_rules`（§6.2 表的列）。
2. 地區列與地圖（2.1、2.2；房間 id 照 2.2 的固定名，其餘自訂）。本派地圖至少：山門（`<p>_gate`，放查小鏞 `n_<p>_cha` 記錄點 `RESPAWN`）、收徒房、練武場（入門師父與切磋 NPC）、門派技能師父房、思過處（有執法者的派）、其他研究有的房間。山門以外的房間 `requires` 依 `visitors`。
3. NPC：所有師父（`kind: "MASTER"`，`services` 含 `TEACH`；收徒 NPC 加 `JOIN` 與 `BETRAY`；`join_sect` 欄）、查小鏞、切磋 NPC、思過處看守人 `n_<p>_jailer`（`services: ["JAIL"]`，只有有執法者的派）、齋飯 NPC（`MEAL`，研究有寫的派：全真 卯午酉 只限弟子、古墓 卯午酉 任何人）、研究有的雜務／劇情 NPC（只要對話即可）。
4. `masters`：研究名單（§4.3）；基本武學由本派某位師父教到 140（研究多為後期數字【後期版】），每派至少教 `basic_inner`、`basic_parry`、`basic_dodge`、`basic_body` 與本派兵器對應的基本武學。
5. `martial_arts`：§4.3 的核心武功全部要有，每套 2–4 招（3.4 的上下限）；任務武功用 `tier: "QUEST"` + `quest_flag` 條件鎖住（M3b 才開任務）。
6. `monsters`：切磋弟子 `m_<p>_dizi`、敵對入山守衛 `m_<p>_guard`（強；比照 `m_city_guard` 的級距，**新手打不贏**）、研究提到的野外怪（例：武當山下山賊用既有 `m_bandit` 即可）。`monsters[].sect: "<id>"`（新欄位，選填）讓「死在本派手下」能判定公敵被抓（§6.6）。
7. 野外地區每間房的遇敵表遵守 §2.3。
8. `todo_verify` 列出所有【待考證】。

### 4.3 各派內容要點（研究摘要；細節以研究章為準）

**武當**（研究「武當派」）
- 房間：`wd_road1`（古道南岔）、`wd_woods`（武當山下樹林，山賊練功點，3 步外死路）、`wd_road2`（武當山下，引薦人 `n_wd_yinjian`）、`wd_gate`（知客道長 `n_wd_zhike`、查小鏞）、`wd_square`（練武場：俞岱巖、切磋）、`wd_dadian`（大殿：宋遠橋）、`wd_tanqiang`（大殿後屋：俞蓮舟）、`wd_sanqing`（三清宮；東超在右側）、`wd_neitang`（內堂：張三丰，收徒）、`wd_daotian`（稻田，`FIELD`）、`wd_siguo`（思過處）。非本派可進 `wd_gate`、`wd_square`；`wd_neitang` 用 `any_of`（本派／有引薦書／`wd_recommended`）。
- 師父：俞岱巖教 8 套基本（武當心法 `wd_xinfa`、武當身法 `wd_shenfa`、武當長拳 `wd_changquan`、繞指柔劍 `wd_raozhi`、玄虛刀法 `wd_xuanxu`、太極神功 `wd_taiji_sg`（`skill_min wd_xinfa 50`）、綿掌 `wd_mianzhang`（長拳 30）、柔雲劍法 `wd_rouyun`（繞指 40））；宋遠橋教俠義（cap 20）；張松溪教 `basic_literacy`（cap 60）。
- 任務武功（`QUEST`，鎖住）：純陽無極功、梯雲縱、太極拳、太極劍法、倚天屠龍筆法（`STAB`）、真武七截陣（`FORMATION` 7 人）。屬性門檻照 2001-08-07 表【已證實】，俠義門檻【設計提案】。
- 形狀：長拳、繞指 `CROSS`；柔雲 `CROSS_L`【待考證 13/10 格】；玄虛、綿掌 `LINE`。
- 任務：`q_wd_yinjian`（3.2）；`q_wd_jiaofei` 剿滅盜匪（`n_wd_songyuanqiao`；`requires` 本派 + `skill_min wd_xuanxu 15`；步驟 KILL `m_bandit` ×3 → TALK 宋遠橋；獎勵 `skill_prof: { "xiayi": 50 }`；`repeatable: true`）；`q_wd_jiashu` 送家書（大理老人 `n_wd_dl_oldman`，WP-MERGE 放進 `dali` 的菜商與兵器商之間的房間；DELIVER 家書給東超 `n_wd_dongchao`；俠義熟練 25；repeatable）。
- 門規：§6.2。敵對入山：公敵（ALL，capture）、善惡 ≤ −101（INNER）。

**峨嵋**（研究「峨嵋派」）
- 房間：`em_road1`（崆峒橋）…`em_road4`、`em_teahouse`（INN）、`em_bandit`（峨嵋山下，山賊死路，研究：武當剿匪與峨嵋殲逞令的打賊點）、`em_foot`、`em_gate`（峨嵋弟子守門）、`em_square`（靜迦、切磋）、`em_jingzhao`（易理房：靜照，斷惡 cap 20、讀書）、`em_kitchen`、`em_zhou`（周芷若）、`em_miejue`（滅絕的家，收徒）、`em_siguo`。
- 武功：靜迦教 `em_xinfa`、`em_shenfa`、`em_piaoxue`（飄雪穿雲掌，`LINE`）、`em_jinding`（金頂綿掌，飄雪 20，`LINE`）、`em_huifeng`（迴風拂柳劍，`CROSS`）；滅絕教 `em_jiuyang`（九陽功，`QUEST`：斷惡 50 + `em_shougongsha` 旗標）、`em_miejian`（滅劍 `CROSS_L`，`QUEST`）、`em_juejian`、`em_foguang`（`QUEST`），滅絕的 `cap` 一律 1【已證實：只教 1 級】。
- 斷惡：`sect_skill_gain: [{ "on": "KILL_ALIGNMENT", "alignment": "EVIL", "prof": 10 }]`（研究：每殺一個邪惡的人斷惡增長；數值設計提案）。
- 敵對入山：公敵（ALL，capture）；善惡 ≤ −300（INNER，chance 0.5，不 capture；研究：邪惡練功點）。

**恆山**（研究「恆山派」）
- 房間：`hg_shandao`（恆山山道，`extra_rooms` 放進 `hengshan_foot`）、`hg_gate`（知客弟子 `n_hg_zhike`）、`hg_square`（儀和、切磋）、`hg_hall`（定閒師太，收徒【待考證：掌門是否定閒】、定逸師太教天長掌法）、`hg_first`（第一間屋：儀真，醫書與識藥）、`hg_houshan`（後山：定靜師太修定、儀文縱山）、`hg_kitchen`（于嫂：慈悲）、`hg_field`（程薇，`FIELD`）、`hg_woodshed`（何月，`WOOD`）。**不要**用無色庵、白雲庵、見性峰、懸空寺（研究：沒有遊戲證據）。
- 武功：儀和教 `hg_xinfa`、`hg_shenfa`、`hg_jianfa`（`CROSS`）、`hg_yishu`（`MEDIC`，`CROSS`【待考證】）；定逸教 `hg_tianchang`（天長掌法，慈悲 30【後期版】，`CROSS`）；定閒教 `hg_wanhua`（萬花劍法，慈悲 50【後期版】）；儀真教 `basic_medic`（`hours: ["辰","巳","申"]`【設計提案：研究只說三個時辰】）；定靜教 `basic_inner`。
- 敵對入山：善惡 < 0 或 PK ≥ 1 的非本派（INNER，chance 0.8【已證實「高機率」】，不 capture）、公敵（ALL）。`visitors: "OPEN"`。
- 沒有執法者：`enforcer false`、`jail_room ""`。

**全真**（研究「全真教」）
- 房間：`zn_road1`、`zn_road2`、`zn_foot`、`zn_river`（終南山左上方河邊，陳大寶站這裡，對話即可）、`zn_east`、`zn_backhill`（2.2）、`qz_gate`（知客道長）、`qz_road`、`qz_sanqing`（三清殿：七子、收徒）、`qz_square`（全真大廣場：祁志誠教基本武學、切磋 `n_qz_spar` = 趙志敬）、`qz_chongyang`（重陽宮：鹿清篤 `MEAL` 卯午酉 只限弟子、掌藥大師兄賣藥）、`qz_reading`（丘初級屋子：夏志誠教 `basic_literacy` cap 61【已證實】）、`qz_houshan`（後山：尹志平 養生）、`qz_cave`（閉關山洞：`meditate` 加成）、`qz_siguo`。
- `personal_master: true`；七子 NPC：`n_qz_majue`（馬鈺）、`n_qz_qiuchuji`、`n_qz_wangchuyi`、`n_qz_tanchuduan`、`n_qz_liuchuxuan`、`n_qz_haodatong`、`n_qz_sunbuer`，七位都有 `JOIN`（`join_sect: "quanzhen"`）；`head_npc` = `n_qz_qiuchuji`（`BETRAY` 只在丘處機）。
- 武功：七子各教 `qz_xinfa`、`qz_jinyan`（金雁功）、`qz_jianfa`（全真劍法，`CROSS`）、`qz_haotian`（昊天掌，`CROSS_L`）、`qz_tiangang`（天罡北斗陣 `FORMATION`，7 人、全男，`stations` 北斗七星形）；第七套照研究分派：馬鈺、劉處玄 `qz_xiantian`（先天氣功）；王處一、譚處端、孫不二 `qz_tonggui`（同歸劍法 `FAN`）；丘處機、郝大通 `qz_sanhua`（三花聚頂掌 `FAN`）。每列 `requires` 加 `{ "type": "sect_master", "npc": "<該師父>" }`；進階門檻照 2002 數字【已證實 1.0B 大陸】；cap 照 2002 各師父表（沒列的師父用 80【設計提案】）。
- 門規 `ENTER_REGION gumu`：進古墓 → 違反門規（研究：不得進入古墓）；另外 `sect_skill_penalties` 進古墓養生 −1 級。
- 不能飲酒【已證實 mengpai/6、index_jy2-25：飲酒 → 減低養生】：`sect_skill_penalties` 加 `{ "trigger": "DRINK", "levels": 1 }`（級數【設計提案】）；喝 `items.alcohol: true` 的物品（目前只有血刀門的青稞酒）→ 養生 −1 級、事件 `wine_vow_broken`（M3a 審查 A4）。
- 敵對入山：公敵（ALL，capture）；善惡 ≤ −500（INNER，研究 2001-08-08）。

**古墓**（研究「古墓派」）
- 房間：`gm_entrance`（活死人墓入口，孫婆婆 `n_gm_sunpopo`：`GUIDE` 送到 `gm_hall`，§6.8）、`gumu_maze` 地區 3–5 間迷宮（`encounter_exempt: ["gumu"]`；遇敵率 0.35【設計提案：研究「一路不斷高機率」】；怪：研究沒有名字，自訂【設計提案】，`combat_xp_ref` 6.5 萬–12 萬，每場 2–4 隻；其中一隻可以是 `m_gm_hongningbo` 洪凌波【已證實會參戰】）、`gm_hall`（掌門人，收徒、清心、入門武功）、`gm_xiaolongnu`（小龍女：進階與特殊）、`gm_hanyu`（寒玉床：`meditate`）、`gm_xiaomei`（小梅：清心練習，對話即可）、`gm_food`（送飯弟子 `MEAL` 卯午酉 任何人）、`gm_shishi`（石室，思過處）。迷宮兩端：`gm_entrance` ─IN─ 迷宮第一間 …迷宮最後一間 ─IN─ `gm_hall`（強闖路線）。`gm_hall` 以外的內室 `requires` 本派或可拜入者。
- 武功：掌門人教 `gm_xinfa`、`gm_yunu_jian`（玉女劍法，係數 0.96，`CROSS`）、`gm_meinu`（美女拳法，`LINE`）、`gm_tianluo_shen`（天羅地網勢身法）、**`qz_jianfa`**（全真劍法：直接引用全真碎片的武功 id，不另建）；小龍女教 `gm_yunu_xinjing`、`gm_tianluo_zhang`、`gm_yingfeng`（迎風拂柳步）、`gm_yinsuo`（銀索金鈴，`WHIP`）、`gm_suxin`（玉女素心劍法，`combo: true`、`QUEST` 鎖住）。`gm_jiuyin`（九陰真經）：沒有師父列【已證實無教者】，`QUEST` 鎖住。
- 門規：§6.2。敵對入山：公敵（ALL，capture）。強闖迷宮不算公敵【已證實】。
- 離山限制【已證實但執行方式不明】：不做（`notes` 記下，等擁有者決定）。

**靈鷲宮**（研究「靈鷲宮」）
- 房間：`ts_road1`、`ts_hut`（獵戶小屋 INN）、`ts_road2`、`lj_gate`（靈鷲宮外景；守門弟子 `n_lj_zhike`、查小鏞）、`lj_hall`（大殿：天山童姥，收徒並教全部武功）、`lj_east`（室內景2：蘭劍 定性、定坐）、`lj_west`（室內景3：菊劍 探路 `basic_body`、程清霜、符敏儀）、`lj_square`（練武：切磋）。山門以外 `requires` 用 3.6 的 `any_of`（`visitors: "MEMBERS"`）。不要用鸞天部、朱天部、鈞天部（2020 攻略）。
- 武功：童姥教 `lj_xiaoyao`（逍遙心法）、`lj_yueying`（月影舞步）、`lj_zhemei`（天山折梅手，`CROSS`，`acupoint: true`）、`lj_tianyu`（天羽奇劍，`CROSS_L`【待考證】）、`lj_ruyi`（如意刀法，`LINE`）、`lj_liuyang`（天山六陽掌，`LINE`，折梅 90【待考證】）、`basic_stab`（cap 140）；`lj_bahuang`（八荒六合唯我獨尊功）`QUEST` 鎖住。
- `sect_skill_penalties: [{ "trigger": "DAILY_IF", "if": [{ "type": "killing_intent_min", "value": 2001 }], "levels": 1 }]`（研究：殺氣過高定性減少；門檻與速度設計提案）。
- 沒有執法者。

**星宿**（研究「星宿派」）
- 房間：`xh_road1`、`xh_road2`、`xh_gate`（星宿海外景：水上木棧、蛇骨雕像）、`xh_hall`（大殿：丁春秋）、`xh_left`（左房：獅吼子 諂媚）、`xh_right`（右房：出塵子 練毒對話、切磋）、`xh_mid1`（中房一樓：燦極子、疏斗子）、`xh_mid2`（中房二樓）。
- 武功：丁春秋教 `xh_xinfa`、`xh_shenfa`、`xh_chousui`（`SINGLE`／帶毒）、`xh_sanyin`（三陰蜈蚣爪，`LINE`）、`xh_tianshan`（天山杖法，`STAFF`，`FAN`）、`xh_fangdu`（放毒法，`POISON`，cap 120）、`xh_feixing`（飛星術，`HIDDEN`【待考證】）與 `basic_poison`、`basic_hidden`、`basic_staff`、`basic_fist`（cap 140）。所有本派攻擊招式都帶 `status: "poison"`（`status_chance` 0.10–0.25）【已證實：每招都可能中毒】。
- 門規：善惡 > −100 停止傳功【已證實】；沒有執法者；`sect_skill_penalties` 同靈鷲（諂媚）。
- 敵對入山：公敵（ALL，不 capture）。

**血刀門**（研究「血刀門」）
- 房間：`xd_road1`、`xd_road2`、`xd_tent`（INN）、`xd_road3`（雪山）、`xd_road4`（雪谷）、`xd_gate`（門口兩名血刀弟子守衛 `n_xd_guard`）、`xd_hall`（本堂：血刀老祖，收徒、威嚇）、`xd_yard`（勝諦：入門 4 套、切磋）、`xd_pool`（血池：血海老祖）、`xd_mishi`（密室）。
- 武功：勝諦教 `xd_xinfa`、`xd_daofa`（血刀刀法 `BLADE`，係數 1.6【待考證】，`LINE`【設計提案】）、`xd_miexian`（滅仙掌，cap **80**【已證實 2001 上限低於 100，數值設計提案】）、`xd_xuedun`（雪遁步行）；`xd_xuehai`（血海魔功）`QUEST` 鎖住（威嚇 60 等 2002 數字）。
- 門規：善惡 ≥ −99 停止傳功【已證實】；沒有執法者。
- 敵對入山：善惡 > 0 的人進 `INNER` 被攻擊（chance 1.0，不 capture）【已證實】；公敵（ALL）。

**少林補充**（`docs/m3a_staging/shaolin.json`，WP-CMD 撰寫；`sect` 欄位留空，只補列）
- 房間：`sl_luohan`（羅漢堂：羅漢練武師 `n_sl_luohan`，`TRIAL`）、`sl_cangjing`（藏經閣，`requires: quest_flag sl_tongren_passed`；渡厄 `n_sl_due`）、`sl_siguo`（思過處：普知 `n_sl_puzhi` 看守 `JAIL`）。接到 `sl_court` 或 `sl_hall`（WP-MERGE 以 `exit_patches` 加出口）。
- 怪：`m_sl_tongren_1`／`_2`／`_3`（三波，一波比一波強，每波 6 隻【已證實】；數值【設計提案】，目標：§10.2 `party3_vs_tongren`）。
- 武功：`sl_riyuebian`（日月鞭法，`WHIP`，玄淨 `n_sl_xuanjing` 教，GDD 二階條件）、`sl_jgfmq`（金剛伏魔圈，`FORMATION` 3 人，`stations: [[0,0],[-1,1],[1,1]]`，`requires`：`quest_flag sl_tongren_passed`、`skill_min foxa 70`、`skill_min sl_riyuebian 50`、`skill_min basic_formation 1`）；渡厄教 `sl_jgfmq` 與 `basic_formation`。
- NPC `n_sl_luohan` 的 `trial` 欄位見 §6.9。

---

## 5. 戰鬥指令與狀態（WP-CMD）

### 5.1 指令集合

`Protocol.BATTLE_CMDS`（WP-RULES Day-0）與 `BattleRules.CMDS`（WP-CMD）：
`["MOVE","ATTACK","ART","DEFEND","REST","EQUIP","FLEE","POISON","MEDIC","HIDDEN","FORMATION","INNER","ACUPOINT","ITEM"]`

`battle_cmd` intent 新參數：`mode: String`（選填；INNER 用）。其餘沿用（`target`、`art`、`move`、`power_tenths`、`item_uid`）。`Protocol.ENUMS[I_BATTLE_CMD]` 加 `"mode": ["HEAL","EXPEL","UNSEAL","TRANSFER"]`。

| cmd | 參數 | 按鈕 | 開放條件（spec） | 1.0 依據 |
|---|---|---|---|---|
| `POISON` | `art`（POISON 武功）、`target`（敵格） | 毒 | `cmd_arts.POISON` 非空 | 【已證實】2001-08-09 |
| `MEDIC` | `target`（自己或隊友的格）、`art`（選填，MEDIC 武功） | 醫 | `skills.basic_medic ≥ 1` 或 `cmd_arts.MEDIC` 非空 | 【已證實】2001-07 |
| `HIDDEN` | `item_uid`（暗器堆疊）、`target`（敵格）、`art`（選填） | 暗 | `skills.basic_hidden ≥ 1` 且 `hidden_items` 非空 | 【已證實】需暗器功夫與暗器 |
| `FORMATION` | `art`（FORMATION 武功） | 陣 | `cmd_arts.FORMATION` 非空 | 【已證實】2001-10-05 |
| `INNER` | `mode`、`target`（TRANSFER 才要） | 內 | `cmd_arts.INNER` 非空，且 `rules.later_battle_cmds` | 【後期版】2002-01-25 |
| `ACUPOINT` | `target`（敵格）、`art`（選填） | 穴 | (`cmd_arts.ACUPOINT` 非空 或 `skills.basic_stab ≥ 10`)，且 `later_battle_cmds` | 【後期版】2002-01-25 |
| `ITEM` | `item_uid`、`target`（自己或隊友） | 裝（子選單「用藥」） | `battle_items` 非空 | 【已證實】2001-08-23 |

`later_battle_cmds == false` 時 INNER、ACUPOINT 回 `cmd_disabled`（主機把規則放在 `Battle.opts.later_battle_cmds`，由 `BattleSystem.battle_opts()` 帶入）。

### 5.2 驗證順序與原因碼（`BattleRules.validate_cmd`）

先跑既有共通檢查（`battle_over`、`not_ready`、`bad_cmd`），再跑狀態封鎖（`status_blocked`：`blocks` 含此 cmd），再依指令：

| cmd | 依序 |
|---|---|
| POISON | `cmd_disabled`（無）→ `no_poison_art`（art 不在 `cmd_arts.POISON` 或等級 0）→ `no_target`（目標格不是活著的敵人）→ `out_of_range`（曼哈頓 > `moves[0].range`）→ `not_enough_neili` |
| MEDIC | `no_medic` → `not_ally`（目標不是自己或同側活著的單位）→ `out_of_range`（> 1，或 MEDIC 武功的 `moves[0].range`）→ `not_enough_jing`／`not_enough_shen` |
| HIDDEN | `no_hidden` → `no_ammo`（`item_uid` 不在 `hidden_items` 或數量 0）→ `no_target` → `out_of_range`（> 暗器射程，5.4） |
| FORMATION | `no_formation_art` → `formation_party`（同側、同隊伍 `party_id`、會此陣法、活著的玩家 < `party_size`，或性別不符）→ `formation_stations`（站位格上沒有對應隊友）→ `not_enough_neili` |
| INNER | `cmd_disabled` → `no_inner_art` → 依 mode：HEAL 無額外；EXPEL `nothing_to_expel`（沒有中毒）；UNSEAL `not_sealed`（沒有封穴）；TRANSFER `not_ally`／`out_of_range`（> 1）→ `not_enough_neili` |
| ACUPOINT | `cmd_disabled` → `no_acupoint` → `no_target` → `out_of_range`（> 1，或點穴武功 `moves[0].range`）→ `not_enough_neili` |
| ITEM | `no_item`（不在 `battle_items`）→ `not_ally` → `out_of_range`（> 1） |
| ART（改） | 拿掉 `aoe_not_supported`；非 SINGLE 的招式：`target` 是範圍中心格，`out_of_range` 以中心格算，範圍內沒有任何敵人 → `no_target`；LINE／FAN 的中心格必須與自己同列、同行或同斜線 → 否則 `bad_direction` |

新原因碼（都要有 `err_<reason>` 模板，`self` 變體；由 `_cmd.json` 提供）：`cmd_disabled no_poison_art no_medic not_ally no_hidden no_ammo no_formation_art formation_party formation_stations no_inner_art nothing_to_expel not_sealed no_acupoint no_item not_enough_shen bad_direction`。

### 5.3 範圍形狀（招式 `aoe`）

座標系同戰場（12×8）。中心格 c 必須在招式 `range` 內（曼哈頓距離）。

| aoe | 名稱（研究用語） | 打到的格 |
|---|---|---|
| `SINGLE` | 單體 | c（必須是敵人） |
| `CROSS` | 小十字（5 格）【已證實】 | c 與上下左右各 1 |
| `CROSS_L` | 大十字（上下左右各 3，13 格）【已證實形狀；格數 13 vs 10【待考證】】 | c 與上下左右各 1–3 |
| `LINE` | 直線（一個方向）【已證實】 | 自己往 c 方向（8 方向之一）連續 `range` 格 |
| `FAN` | 半米字【設計提案的幾何】 | 自己往 c 方向的那條線，加上相鄰的兩條斜／直線，各 `range` 格 |
| `AROUND` | 周身 | 自己周圍 8 格 |

- 只打敵方單位（混亂中的出招者例外，§5.7）。每個被打到的目標各自跑一次 `resolve_strike`（各自命中、爆擊、傷害、招式附帶狀態）；**範圍招式不引發反擊**；內力只扣一次。
- 事件：每個目標一個原本的打擊事件，前面加一個 `battle_aoe { uid, name, peer, move, cells: [[x,y]…] }`（ui；給畫面標格子）。

### 5.4 公式（全部【設計提案】，除非另註）

定義：`B(skill)` = 單位的該項等級；`A` = 所用武功等級。

- **毒（POISON）**：`P = B(basic_poison) + A + art.poison.level_bonus`；`R = B(basic_inner) + 2 × 定力`（目標）。成功率 `p = clamp(0.40 + (P − R) × 0.005, 0.10, 0.90)`；施毒者不是武功所屬門派弟子（叛派者）時 `p × 0.5`【已證實「非星宿成功率低很多」，倍數設計提案】。成功：直接傷害 = `round(招式威力 × 0.5 × (1 + A/60))`（比特攻小【已證實】），再施加 `poison` 等級 `L = clamp(1 + floor(P / 25), 1, 10)`；失敗事件 `battle_poison_fail`。內力消耗 = `moves[0].cost_inner`。目標若有 `RESIST` 門派技能，先擲觸發（5.6）。
- **中毒每次行動扣氣** = `qi_max × (qi_pct_per_action + qi_pct_per_level × L)`（L=1 時 2.4%，L=10 時 6%）。
- **醫（MEDIC）**：回氣 `= round((20 + 2 × B(basic_medic) + 3 × A_medic) × heal_mult × (恆山弟子 1.3【已證實「醫療效果比其他門派強」，倍數設計提案】))`，不超過上限；消耗 精 10、神 5。`later_battle_cmds` 為 true 時，若 `B(basic_medic) + A_medic ≥ 10 × 中毒等級`，同時解毒【後期版：醫術治毒傷是 2002】。
- **暗（HIDDEN）**：射程 `3 + floor(B(basic_hidden) / 40) + art.hidden.range_bonus`（最多 6）。命中率用 `BattleFormulas.hit_chance(att, def, B(basic_hidden))`。傷害 `= max(1, round((暗器傷氣 × (1 + B(basic_hidden)/50) + 招式威力 × (1 + A/60) − 防禦力 × 0.3) × 浮動))`（有暗器武功才加招式威力）。每次消耗 1 個（命中與否都消耗）；戰後從背包扣除（5.8）。
- **陣（FORMATION）**：施陣者是隊長位（站位 `[0,0]`）；`stations` 是相對座標（己方在左側時 y 往下為正；在右側時左右鏡像）。所有站位格上要有同隊、會此陣法的活人玩家。成功：每位成員得到 `formation` 狀態（持續 6 次行動），攻 × `(1 + atk_bonus + per_avg_level × 平均陣法等級)`、防 × `(1 + def_bonus + per_avg_level × 平均陣法等級)`；平均陣法等級 = 成員的（陣法武功等級 + 基本陣法）/2 的平均【已證實：用平均等級】。任一成員倒下或使用「移」→ 全員 `formation` 解除（`battle_formation_off`）【已證實：一人倒下陣就破】。每位成員扣內力 `moves[0].cost_inner`（只有施陣者行動，其他人在下次行動時扣，不夠就退出陣法）。
- **內（INNER）**：用 `cmd_arts.INNER[0]`（等級最高的內功），`I = A + B(basic_inner)/2`。
  - HEAL：扣內力 `n = round(neili_max × 0.10)`，回氣 `round(n × (1 + I/100) × heal_mult × (全真 1.3【已證實「內力療傷較強」】))`。
  - EXPEL（逼毒）：扣內力 20；中毒等級 −`(1 + floor(I/25))`，到 0 解除。
  - UNSEAL（衝穴）：扣內力 15；成功率 `clamp(0.30 + I × 0.005 + (定力 − 20) × 0.01, 0.10, 0.95)`。
  - TRANSFER（傳力）：目標相鄰隊友；轉 `min(自己內力 × 0.5, 目標缺的內力)`。
- **穴（ACUPOINT）**：`Aac = B(basic_stab) + A_acupoint`；`D = B(basic_inner) + B(basic_dodge)/2`（目標）。成功率 `clamp(0.30 + (Aac − D) × 0.004, 0.05, 0.80)`；成功施加 `acupoint`；扣內力 15。點穴武功（`acupoint: true`）的一般招式命中時另有 `0.05 + A × 0.001` 的機率附帶 `acupoint`（研究：天山折梅手命中附帶封穴【後期版】）。
- **ITEM**：套用 spec `battle_items[].effects`：`restore`（`stat` 為 qi／neili／jing／shen 時直接加到單位，不超過上限；其他 stat 忽略）、`cure`（解除等級 ≤ `max_level` 的狀態）；戰後扣背包（5.8）。`core/battle` 不呼叫 `Character`／`Survival`。

### 5.5 戰鬥規格（spec）新欄位的使用

WP-CMD 只讀 3.11 列出的 spec 欄位；怪物 spec（`Encounter.monster_spec`）補上：`cmd_arts`（從怪物 `arts` 分類）、`hidden_items: []`、`battle_items: []`、`statuses: {}`、`gender: ""`、`sect: monster_row.sect`。怪物 AI（`battle_ai.gd`）：有 POISON 武功的怪 30% 機率用毒【設計提案】；其他新指令 AI 不用。

### 5.6 門派技能觸發（`resolve_strike`／行動流程）

觸發率沿用 `BattleFormulas.proc_chance(level)`（5% + 0.2%/級，最高 25%，GDD 3.3）。新 8 種效果每次觸發扣 `sect_skill_cost` 列的兩項各 3 點（精、內力或神；不夠就不觸發）（D12）。

| effect | 時機 | 效果（GDD 3.3，數值設計提案） | 事件 |
|---|---|---|---|
| RESIST | 自己要被施加 `resist_by` 含 RESIST 的狀態時 | 不中該狀態 | `battle_proc_RESIST` |
| EVADE | 被打、命中判定之前 | 這一下命中率 −15 個百分點 | `battle_proc_EVADE` |
| COUNTER | 被打中、沒死、與攻擊者相鄰 | 立刻反擊一次（傷害 × 0.6，不再連鎖）；與 M1 的定力反擊不疊加（先判門派觸發） | `battle_proc_COUNTER` |
| REST | 自己按「休」 | 氣、內力各再回 10% | `battle_proc_REST` |
| PARALYZE | 自己的攻擊／招式命中後 | 目標 `paralysis` | `battle_proc_PARALYZE` |
| CONFUSE | 同上 | 目標 `confusion` | `battle_proc_CONFUSE` |
| DISTRACT | 同上 | 目標 `distract` | `battle_proc_DISTRACT` |
| HEAVY | 自己的攻擊／招式算傷害時 | 傷害 × 1.5 | `battle_proc_HEAVY` |

事件 payload 照既有 `battle_proc_DEFENSE`：`{ uid, name, peer, skill_name }`（HEAVY、COUNTER 另帶 `def_uid`）。

### 5.7 狀態效果的執行

- 行動開始（`_status_tick`）：依每個狀態的 `qi_pct_*` 扣氣；`skip_actions` → 本次行動直接結束（事件 `battle_status_skip`）；`random_action` → 改成「對射程 1 內隨機一個活人（不分敵我）普通攻擊，沒有就防」（`battle_confused`）；次數 −1，到 0 解除（`battle_status_off`）。
- `qi_pct_per_move`：執行「移」時扣。
- `atk_mult`、`def_mult`、`gauge_mult`：分別乘進攻擊力、防禦力、時間棒增加量。
- 施加（`apply_status(b, u, id, tables, level := 1)`）：持續次數 = `max(1, duration_actions − floor(max(0, 定力 − 20) / 10))`【已證實「定力越高恢復越快」，公式設計提案】；`LEVEL_MAX` 取較高等級。
- 戰鬥開始時 spec 的 `statuses` 直接放入單位（帶等級）。
- 快照：每個單位（含敵方）加 `statuses: [ { "id", "name", "glyph", "color", "n", "level" } ]`。

### 5.8 戰鬥結束寫回（`BattleSystem._settle_player`，WP-CMD）

1. 消耗：`HIDDEN` 用掉的暗器、`ITEM` 用掉的藥，從背包扣（`ch.inventory.remove(uid, n)`），並送既有 `item_lost` 事件。
2. 持續狀態：單位結束時身上 `persists: true` 的狀態 → `ch.add_condition(id, level, level × persist_ticks_per_level, ch.online_s + persist_tick_real_s)`。
3. 呼叫 `host.sects.on_battle_settled(s, ch, summary)`（`null` 判斷）：`summary = { "kind", "result", "kills": [monster ids], "killed_by": { "kind": "MONSTER"/"PLAYER", "ref", "sect" }, "died": bool, "pvp_initiator": bool, "same_sect_kills": [char ids] }`。
4. 死亡流程 `handle_death` 先問 `host.sects.capture_on_death(s, ch, summary) -> Dictionary`；回傳 `{ "jail": true, ... }` 時照常套死亡懲罰，但**不**送回記錄點，改由 SectSystem 押入思過處。

### 5.9 波次（十八銅人）與新開戰 API

`BattleSystem.start_ex(s: Session, monster_ids: Array, kind: String, opts: Dictionary) -> int`：`opts` = `{ "waves": [[ids…], [ids…]], "no_flee": bool, "party_only": bool, "pull_party": bool }`。`start()` 改成呼叫 `start_ex(s, ids, kind, {})`。
`Battle` 的波次：第一波用 `monster_ids`；敵方全滅且還有下一波 → 從右側邊緣空格放入下一波（`battle_wave { n, total }` 事件），不結束戰鬥；最後一波清光才 VICTORY。`no_flee: true` 時 FLEE 回 `no_flee`（新原因碼，追擊戰不能逃【已證實】）。
新 kind：`"TRIAL"`（十八銅人）、`"SECT_GUARD"`（敵對入山）。`battle_opts(region, kind)` 對這兩種不受 `pk_allowed` 影響。

### 5.10 文字模板（`_cmd.json` 碎片；每個都要 `self`／`target`（有目標時）／`other`）

`battle_poison_ok {atk, def, dmg, level}`、`battle_poison_fail {atk, def}`、`battle_poison_tick {name, dmg, qi}`、`battle_medic {atk, def, heal, cured}`、`battle_hidden_hit {atk, def, item_name, dmg, part}`、`battle_hidden_miss {atk, def, item_name}`、`battle_formation_on {name, art_name, members}`、`battle_formation_off {art_name}`、`battle_inner_heal {name, heal, neili}`、`battle_inner_expel {name, level_left}`、`battle_inner_unseal_ok {name}`、`battle_inner_unseal_fail {name}`、`battle_inner_transfer {atk, def, n}`、`battle_acupoint_ok {atk, def}`、`battle_acupoint_fail {atk, def}`、`battle_status_skip {name, status_name}`、`battle_confused {name}`、`battle_item_use {atk, def, item_name}`、`battle_wave {n, total}`、`battle_proc_RESIST`…`battle_proc_HEAVY`（8 個，照 5.6）、`battle_aoe`（ui，可只有 `self`）、招式 flavor `move_palm_poison`、`move_sword_cross`、`move_blade_line`、`move_whip_fan`、`move_staff_fan`、`move_stab_basic`，以及 5.2 的 `err_*`。

---

## 6. 門派系統（WP-RULES）

### 6.1 類別與接線

- `server/sect_system.gd`：`class_name SectSystem`（`GameHost.sects`）。
- `server/condition_system.gd`：`class_name ConditionSystem`（`GameHost.conditions`）：戰後中毒發作、坐牢期滿、禁止學武期滿、每日門派技能衰減（以上線秒判定，每秒檢查一次在線角色）。
- `server/intents/intents_sect.gd`：`sect_betray`、`jail_ransom`、`sect_trial`、`npc_guide`。
- `server/intents/intents_debug.gd`：`debug_set`（只在啟動參數 `--debug-intents` 時註冊；§6.11）。

`SectSystem` 公開函式（其他 WP 依此呼叫）：

```
func can_teach(s: Session, npc_id: String) -> String            # "" 或原因碼 sect_stop_teach / sect_banned / jailed
func on_join(s: Session, sect_id: String, npc_id: String) -> void
func on_enter_room(s: Session, room_id: String) -> void         # RegionSystem 走路／瞬移後呼叫
func on_battle_settled(s: Session, ch, summary: Dictionary) -> void
func capture_on_death(s: Session, ch, summary: Dictionary) -> Dictionary
func on_pvp_kill(killer: Session, victim_char, initiator: bool) -> void   # PkSystem 呼叫
func check_state(s: Session, trigger: String) -> void           # 狀態規則檢查：trigger ∈ ENTER/BATTLE/LEARN/PK/TICK
func betray(s: Session, npc_id: String) -> Dictionary
func expel(s: Session, reason: String, rule_id: String) -> void
func jail(s: Session, sect_id: String, days: int, reason: String, rule_id: String) -> void
func release(s: Session, why: String) -> void                   # why ∈ served/ransom/admin
func ban(s: Session, sect_id: String, days: int, rule_id: String) -> void
func start_trial(s: Session, npc_id: String) -> Dictionary
func guide(s: Session, npc_id: String) -> Dictionary
func is_jailed(s: Session) -> bool
```

### 6.2 各派門規列（`sect_rules` 與 `teach_requires`；碎片照寫）

| 門派 | 停止傳功（`teach_requires`，任一不成立就不教） | 違反門規（`sect_rules`，BREACH） | 依據 |
|---|---|---|---|
| 少林 | 善惡 ≥ −99、PK值 ≤ 0、殺氣 ≤ 1000【設計提案「殺氣重」】 | STATE：善惡 ≥ −299、PK值 ≤ 2、殺氣 ≤ 2000；EVENT：KILL_SAME_SECT | 少林官方頁、news 141 |
| 華山 | 善惡 ≥ −299 | STATE：善惡 ≥ −299、PK值 ≤ 1；EVENT：KILL_SAME_SECT | news 141 |
| 武當 | 善惡 ≥ 50 | JAIL/BAN：善惡 ≥ −299；EXPEL：跟張三丰等 6 人交談時善惡 ≥ −99、跟宋遠橋等 7 人交談時 ≥ −199；EVENT：KILL_SAME_SECT | 2001-07-08、jy2-22、news 141 |
| 峨嵋 | 善惡 ≥ 0【待考證「善良」】、殺氣 ≤ 2000 | STATE：善惡 ≥ −299；EVENT：KILL_SAME_SECT | mengpai/3、news 141 |
| 恆山 | 善惡 ≥ 0、PK值 ≤ 0、殺氣 ≤ 3000 | STATE：善惡 ≥ 0、PK值 ≤ 1（EXPEL 另有殺氣 ≤ 3000）；EVENT：KILL_SAME_SECT | mengpai/7、jy2-22、news 141 |
| 全真 | 善惡 ≥ 0、PK值 ≤ 0、殺氣 ≤ 1000 | JAIL/BAN：善惡 ≥ −399；EXPEL：善惡 ≥ −299；兩者：PK值 ≤ 10；EVENT：KILL_SAME_SECT。進古墓只降養生 1 級（`sect_skill_penalties`），**不是**違反門規（審查 R2，mengpai/6） | mengpai/6、jy2-22、news 141 |
| 古墓 | 善惡 −299…299、PK值 ≤ 3、殺氣 ≤ 1000 | JAIL/BAN：PK值 ≤ 10、殺氣 ≤ 10000；EXPEL：善惡 ≥ −500、殺氣 ≤ 2000、PK值 ≤ 3 | 2001 官方頁、jy2-22、news 141；研究「三層」 |
| 靈鷲 | 善惡 −299…299 | EVENT：KILL_SAME_SECT | 官方門規頁 |
| 星宿 | 善惡 ≤ −100 | （無；PK 丁春秋 M3b） | 官方門規頁 |
| 血刀 | 善惡 ≤ −100 | （無；攻擊老祖 M3b） | 官方門規頁 |

### 6.3 違反門規的處理

1. **觸發**：
   - STATE 規則：`check_state` 在下列時機檢查本派所有 STATE 規則：走進任何房間、戰鬥結算、學武前、PK值改變後、每分鐘一次（`TICK`）。規則從「成立」變「不成立」時觸發一次並記 `sect_record.breached[rule_id] = true`；條件恢復成立時清掉。剛拜入時，已經不成立的規則直接記為 breached、不觸發（不會一入門就坐牢）。
   - EVENT `KILL_SAME_SECT`：強制 PK 的**發起者**殺死同門玩家（研究：殺死參戰的同門不算）；叫戰（雙方同意）不算。
   - EVENT `ENTER_REGION`：走進 `event_arg` 地區的房間時。
2. **後果**（`mode = rules.sect_violation_mode`；`jail_enabled == false` 時 JAIL → BAN；本派 `enforcer == false` 或 `jail_room == ""` 時 JAIL → BAN）：
   - `JAIL`：`jail(s, sect, server_options.jail_breach_days, "BREACH", rule)`，文字「{enforcer}將你押回思過處」。
   - `EXPEL`：`expel(s, "BREACH", rule)`（= 叛派懲罰，§6.5）。
   - `BAN`：`ban(s, sect, server_options.ban_days, rule)`：本派師父不教，直到 `ban_until_online_s`。
3. 事件 `sect_breach { sect_name, rule_text, outcome: "JAIL"/"EXPEL"/"BAN", days }`（SYSTEM，自己看）。

### 6.4 門派技能的取得與衰減

- 取得：師父消點（3.2 的師父列）、任務 `skill_prof`（既有）、`sect_skill_gain`：`{ "on": "KILL_ALIGNMENT", "alignment": "EVIL", "prof": 10 }` → 戰鬥勝利後，每殺一隻 `alignment` 相符的怪，門派技能熟練 +prof（呼叫既有加熟練的函式，會升級就送 `skill_up`）。
- 衰減 `sect_skill_penalties`：
  - `{ "trigger": "DAILY_IF", "if": [條件], "levels": 1 }`：每累計上線 1 遊戲日檢查一次，條件全部成立 → 門派技能 −levels（最低 0）；事件 `sect_skill_decay { skill_name, level }`。
  - `{ "trigger": "ENTER_REGION", "region": "gumu", "levels": 1 }`：走進該地區時 −levels（每遊戲日最多一次）。
- 少林吃肉降佛法（既有）不動。

### 6.5 叛派（`BETRAY`）與開除

- 對 `head_npc` 選「叛教」（npc_menu 有 `betray: true` 才顯示）→ 客戶端二次確認 → `sect_betray { npc, confirm: true }`。驗證：`no_character` → `in_battle` → `jailed` → 不是本派掌門 `no_service` → `confirm != true` → `need_confirm`。
- 懲罰（`Character.betray_penalty`）：
  - 預設：**本門武功**（`martial_arts.sect_id == 該派`）等級減半（`floor(level/2)`；變 0 就移除）；`sect_only` 物品沒收【已證實 news 317】；門派技能不動（2001 各派頁只說「本門武功減半」，jb170；審查 R10）。
  - `betrayal_halves_basics == true`：改成全部特殊武功與基本武學都減半，**門派技能歸零**（後期官方頁 jy2-22）。
  - `ch.sect = ""`、`ch.sect_master = ""`、`sect_enemies` 加入該派（公敵）、`sect_traitor` 加入該派（叛徒記號，存檔；永遠不能再拜入【已證實】，`not_enemy_of` 條件同時檢查兩者）、`sect_record.history` 記一筆。
- 開除 `expel(s, reason, rule)`：懲罰同叛派；事件 `sect_expel`；送到 `gate_room`（如果人在本派地圖）。
- 廣播：`sect_betray`／`sect_expel`（SYSTEM，全服；`{ name, sect_name }`）。

### 6.6 思過處（坐牢）

- `jail(...)`：`ch.jail = { sect, room: sect.jail_room, until_online_s: ch.online_s + days × game_day_real_s, reason, rule }`；角色若在戰鬥中，等戰鬥結束再執行；瞬移到 `jail_room`（`RegionSystem.teleport`）；事件 `jail_in { sect_name, days, reason_text }`（自己）＋ `jail_in` 的 `other` 變體給同房間。
- 坐牢中允許：`chat`（只限 `CHAT_WHISPER`、`CHAT_SAY`）【已證實 jy1-2-5-4：囚犯只留傳音入密、輕聲細語，不能用其他指令】。【設計提案】的偏離（M3a 審查 A8）：`look`、`talk`（只限同房間；向看守人問刑期）、`use_item`（只為吃喝；刑期最長 6 小時上線時間，不讓人餓死渴死）、`quest_abandon`、`mail_list`／`mail_read`（純查看）也放行。`self_study`、`meditate`、`exert`、`equip`／`unequip` **不**放行（坐牢不能練功）。其他 intent 一律回 `jailed`。`move` 走不出 `jail: true` 的房間。不會踩地雷、不能偵察、不能被叫戰或強制 PK（`pk_system` 判斷）。
- 出獄：`ConditionSystem` 每秒檢查 `online_s ≥ until_online_s` → `release(s, "served")`：清 `ch.jail`、瞬移到該派 `gate_room`、`reason == "ENEMY"` 時把該派從 `sect_enemies` 移除（改過自新【已證實 jy1-2-5-4】：不再被圍攻、不再被抓）；**叛徒記號 `sect_traitor` 不移除**，所以還是不能再拜入（研究「公敵 never rejoin」；審查 R11）；事件 `jail_out`。
- 贖人：任何人在看守人（`JAIL` 服務）面前 `jail_ransom { npc, name }`：`name` 是正在這間思過處坐牢、在線的角色名；付款人錢 ≥ `jail_ransom` → 扣錢、`release(target, "ransom")`；事件 `jail_ransom_paid`（付款人）、`jail_out`（被贖者）。原因碼：`no_prisoner`、`not_enough_money`。
- 看守人的 npc_menu 附 `jail: { "prisoners": [ { "name", "left_s" } ], "ransom": 100000 }`；自己坐牢時 `left_s` 也放在角色表（6.12）。
- **公敵被抓**（`capture_on_death`）：角色身上有 `enemy_of X`，在 `SECT_GUARD` 戰鬥中死亡、或被 `monsters[].sect == X` 的怪殺死、或被 X 派玩家殺死 → X 有 `jail_room` 且模式不是 BAN 時，`jail(s, X, jail_enemy_days, "ENEMY", "")`（死亡懲罰照常，但不回記錄點）。

### 6.7 敵對入山

`on_enter_room`：選項 `sect_hostile_entry` 開、角色不在戰鬥中、房間屬於某派地區、房間符合 `rooms`（`GATE` = `gate_room`；`INNER` = 本派地區除了 `gate_room` 的房間；`ALL`），依序檢查 `hostile_entry`，第一條 `if` 全部成立且擲中 `chance` → `battles.start_ex(s, [monster × count], "SECT_GUARD", { "no_flee": rule.no_flee, "pull_party": true })`；事件 `sect_hostile { sect_name }`。本派弟子不觸發。同一角色 30 秒內最多觸發一次。

### 6.8 引路（`GUIDE`）

NPC 欄位 `guide: { "to_room": "gm_hall", "requires": [條件] }`。`npc_guide { npc }`：`no_character` → `in_battle` → `jailed` → NPC 不在這裡／沒有 `GUIDE` → `requires` 不成立（回 `req_*`）→ 瞬移到 `to_room`（同一門派地區內，O2 允許）；事件 `npc_guide { npc_name, room_name }`。古墓孫婆婆：`requires: [ any_of [[sect gumu], [no_sect, gender F, morality −299…299, not_enemy_of gumu]] ]`。

### 6.9 試煉（`TRIAL`，十八銅人）

NPC 欄位：

```json
"trial": { "id": "sl_tongren", "waves": [["m_sl_tongren_1","m_sl_tongren_1","m_sl_tongren_1","m_sl_tongren_1","m_sl_tongren_1","m_sl_tongren_1"],
                                         ["m_sl_tongren_2","…×6"], ["m_sl_tongren_3","…×6"]],
           "party_min": 3, "party_max": 3,
           "requires": [ { "type": "sect", "sect": "shaolin" }, { "type": "combat_xp_min", "value": 60000 } ],
           "reward_flag": "sl_tongren_passed", "no_flee": true }
```

`sect_trial { npc }`：`no_character` → `in_battle` → `jailed` → NPC 檢查 → 自己 `requires` → 隊伍檢查（同隊、同房間、閒置的隊員數在 `party_min..party_max`，每位都符合 `requires`；不符回 `trial_party`）→ `battles.start_ex(s, waves[0], "TRIAL", { "waves": waves, "no_flee": true, "party_only": true, "pull_party": true })`。勝利（最後一波清光）→ 參戰者都得到 `reward_flag`；事件 `trial_passed { trial_name }`。實戰門檻 60,000【待考證：官方只說「足夠的實戰經驗」；本專案研究另有 50 萬】。

### 6.10 戰後持續狀態（ConditionSystem）

每個在線角色每秒：對 `conditions` 裡每個狀態，`online_s ≥ next_online_s` → 套用 `persist_qi_pct`（扣氣上限比例，最低剩 1，不致死）、`ticks_left −1`、`next_online_s += persist_tick_real_s`；`ticks_left == 0` → 移除並送 `condition_off`。事件 `poison_flare { dmg, qi }`。解藥 `use_item`（`cure` 效果）可在戰鬥外清除（WP-RULES 改 `inventory`／`intents_item` 的使用流程）。選項 `poison_flare_enabled == false` 時不發作、直接到期移除。

### 6.11 Debug intent（只給驗收用）

`debug_set { key: String, value: Variant }`：只在主機以 `--debug-intents` 啟動時註冊（`WorldServer` 讀參數→ `GameHost.debug_enabled`）。`key` ∈ `morality`、`killing_intent`、`pk`、`combat_xp`、`money`、`learn_points`、`attr:<id>`、`skill:<id>`（等級）、`flag:<name>`、`online_s_add`（秒，快轉坐牢／中毒）、`teleport`（房間 id，**只給 bot 回到起點**，正常遊戲不可用）。回 `ok`；事件 `debug_set`（SYSTEM）。`Protocol` 常數 `I_DEBUG_SET := "debug_set"`；不在 `--debug-intents` 時回 `unknown_intent`（與未註冊相同）。

### 6.12 協定增量（`core/protocol.gd`，WP-RULES Day-0）

**Intent**

| kind | 參數 | 回應／事件 |
|---|---|---|
| `battle_cmd`（改） | `mode: String`（選填） | 5.1 |
| `sect_betray` | `npc: String`, `confirm: bool` | 6.5 |
| `jail_ransom` | `npc: String`, `name: String` | 6.6 |
| `sect_trial` | `npc: String` | 6.9 |
| `npc_guide` | `npc: String` | 6.8 |
| `debug_set` | `key: String`, `value`（任意，型別不檢查） | 6.11 |

**事件**（模板由 `_rules.json` 提供；`ui` 標記的走 `"ui": true`）：`sect_breach`、`sect_expel`、`sect_betray`、`sect_stop_teach`（學武被拒時的說明）、`sect_skill_decay`、`sect_hostile`、`jail_in`、`jail_out`、`jail_ransom_paid`、`poison_flare`、`condition_off`、`npc_guide`、`trial_passed`、`debug_set`。原因碼：`sect_stop_teach`、`sect_banned`、`jailed`、`need_confirm`、`no_prisoner`、`trial_party`、`no_flee`、`req_has_item`、`req_any_of`、`req_enemy_of`、`req_pk_min`、`req_killing_intent_min`、`req_sect_master`、`req_party_size_min`、`req_hour_in`。

**npc_menu 新欄位**：`betray: bool`、`jail: {…}|null`、`trial: { "name", "party_min", "party_max", "ok": bool, "reason" }|null`、`guide: { "room_name", "ok": bool }|null`、`teach_blocked: ""|原因碼`。

**角色表（`s2c_sheet`）新欄位**：`sect_info: { "id", "name", "skill_id", "skill_name", "skill_level", "master": "", "stop_teach": ""|原因碼, "ban_left_s": 0, "warnings": [ "morality", "pk", "killing_intent" ] }`（`warnings` = 距離本派任一 BREACH 狀態規則門檻 10% 以內的屬性 → 屬性燈籠變色【已證實 news 318】）、`enemy_of: [sect names]`、`jail: { "sect_name", "room_name", "left_s" }|null`、`conditions: [ { "id", "name", "glyph", "color", "level", "left_s" } ]`。
**world_info 新欄位**：`later_battle_cmds: bool`。

`NPC_SERVICES`（lint 與 UI）加：`BETRAY`、`JAIL`、`TRIAL`、`GUIDE`。`UiKeys.SERVICE_LABELS`：叛教、思過處、試煉、引路。

---

## 7. 介面（WP-UI）

1. **指令圓盤**（`command_bar.gd`、`ui_keys.gd`）：毒、醫、暗、陣、內、穴按鈕啟用（依快照 `cmd_avail`，見下）；快捷鍵 8 毒、9 醫、0 暗，`Shift+1` 陣、`Shift+2` 內、`Shift+3` 穴（顯示在提示）；`later_battle_cmds == false` 時內、穴維持「不能用」樣式，提示「原作 2002 年才有（伺服器規則關閉）」。輕、特、絕、馴維持鎖住。
   - 快照（玩家自己的單位）新欄位（WP-CMD 輸出）：`cmd_avail: { "POISON": bool, "MEDIC": bool, "HIDDEN": bool, "FORMATION": bool, "INNER": ["HEAL","EXPEL","UNSEAL","TRANSFER"], "ACUPOINT": bool, "ITEM": bool }`、`cmd_arts`（同 spec，附名稱與 `moves[0]` 射程）、`hidden_items`、`battle_items`、`formation: { "art", "stations": [[x,y]…] }|null`。
2. **選目標**：毒、暗、穴 → 敵格（紅框，射程內）；醫、ITEM、傳力 → 自己或隊友格（綠框）；陣 → 顯示站位格（金框，缺人的格閃爍），按 Enter 送出；範圍招式 → 滑鼠移到中心格時預覽打擊格（半透明）。
3. **內**：小選單（運功療傷／逼毒／衝穴／傳力），不可用的灰掉並附原因。
4. **暗**：先選暗器（顯示數量、傷氣），再選目標。**裝**：子選單「換兵器／用藥」。
5. **狀態圖示**：戰鬥單位頭上用狀態 `glyph` 小圓章（`color`），滑鼠提示名稱與剩餘次數；主畫面底部 HUD「狀」圖示顯示戰後持續狀態（`conditions`）與剩餘時間。
6. **門派對話**：npc_menu 的「拜師」先顯示確認窗（門派名、性別與善惡條件、門規摘要＝`sect_rules` 文字）；「叛教」兩段確認（第二段要輸入「叛教」兩字），列出會減半的武功；「試煉」顯示隊伍條件；「引路」直接送。
7. **思過處**：坐牢時主畫面上方一條提示「思過處：剩 1 小時 32 分（上線時間）」；被鎖的指令按了顯示 `err_jailed`；看守人選單列出囚犯與「贖人（十萬兩）」按鈕。
8. **學藝視窗**：`teach_blocked` 不是空字串時整個視窗上方顯示原因（停止傳功、禁止學武），學習鈕灰掉。
9. **屬性燈籠**：`sect_info.warnings` 裡的屬性數字改成紅色並加提示「接近門規底線」。
10. 文字新 key 的 TextRenderer 顏色：門規類用系統色，戰鬥新事件沿用戰鬥頻道。

---

## 8. 工作包與檔案所有權

### 8.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-CMD** | `core/battle/**`；`server/battle_system.gd`；`server/intents/intents_battle.gd`；`data/status_effects.json`；`tools/balance_sim.gd`；`tests/unit/test_battle*.gd`（既有＋新：`test_battle_m3a_cmds.gd`、`test_battle_status.gd`、`test_battle_aoe.gd`、`test_battle_formation.gd`、`test_battle_waves.gd`、`test_battle_procs.gd`）；`tests/fixtures/battle_*.json`（可用 `tools/regen_battle_golden.gd` 重產，交付說明列出差異原因）；`docs/m3a_staging/_cmd.json`；`docs/m3a_staging/shaolin.json` | §5 全部；§4.3 少林補充；新物品與戰鬥模板；balance_sim 新案例（§10.2） |
| **WP-RULES** | `server/sect_system.gd`（新）、`server/condition_system.gd`（新）、`server/intents/intents_sect.gd`（新）、`server/intents/intents_debug.gd`（新）；`server/game_host.gd`、`server/session.gd`、`server/npc_system.gd`、`server/region_system.gd`、`server/pk_system.gd`、`server/social_system.gd`、`server/scout_system.gd`、`server/quest_system.gd`、`server/admin_system.gd`、`server/intents/intents_npc.gd`、`intents_move.gd`、`intents_self.gd`、`intents_item.gd`、`intents_char.gd`、`intents_host.gd`、`intents_pk.gd`、`intents_social.gd`、`intents_scout.gd`、`intents_quest.gd`；`autoload/world_server.gd`、`autoload/client_state.gd`；`core/protocol.gd`；`core/character/**`；`core/rules/**`；`core/data/**`；`data/rule_profiles.json`、`data/server_options.default.json`；`tests/unit/test_character*.gd`、`test_world_*.gd`（既有）、`test_protocol_*.gd`、`test_data_loader.gd`、新 `test_sect_system.gd`、`test_world_sect.gd`、`test_world_jail.gd`、`test_world_conditions.gd`、`test_requirements_m3a.gd`、`test_protocol_m3a.gd`；`docs/m3a_staging/_rules.json` | §3.3、3.7、3.10、3.11；§6 全部；協定 Day-0 |
| **WP-UI** | `ui/**`、`autoload/scene_router.gd`；`tests/unit/test_ui*.gd`（既有＋新 `test_ui_m3a_battle.gd`、`test_ui_m3a_sect.gd`） | §7 全部 |
| **WP-SECT-<id>** ×8 | `docs/m3a_staging/<id>.json`（wudang、emei、hengshan、quanzhen、gumu、lingjiu、xingxiu、xuedao），**只有這個檔** | §4 |
| **WP-MERGE**（建造之後單獨執行） | `data/*.json`（除了 `status_effects`、`rule_profiles`、`server_options.default`）、`data/maps/*.json`、`data/art.json`；`tools/data_lint.gd`、`tools/validate_data.gd`；`tests/unit/test_data_content.gd`；`docs/ART_REQUEST.md` §6「第三批」 | §8.4 合併程序 |
| **整合者**（協調者本人） | `tests/bots/**`（新 `tests/bots/m3a_sect_bot.gd`）、`tests/ui/ui_playthrough.gd`、`tests/ui/ui_driver.gd`、`tools/m3a_acceptance.gd`（新）、`README.md`、`docs/**`（GDD 同步、本文件的整合紀錄） | §10 驗收 |

### 8.2 凍結檔（M3a 任何 WP 都不得修改）

`project.godot`、`autoload/game_data.gd`、`autoload/bgm_player.gd`、`autoload/network_manager.gd`、`autoload/steam_manager.gd`、`autoload/save_manager.gd`、`core/util/*`、`tests/run_tests.gd`、`tests/test_case.gd`、`tests/unit/test_core_util.gd`、`tests/bots/chat_bot.gd`、`tools/net_smoke.gd`、`tools/steam_api_probe.gd`、`tools/check_vendor.ps1`、`tools/iso_gallery.gd`、`tools/import_art.py`、`addons/**`、`assets/**`、`data/eras.json`、`data/patches/**`、`docs/**`（只能寫自己的碎片；本文件只由協調者改）。

### 8.3 Day-0（各 WP 開工的第一件事）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-RULES | (1) `core/protocol.gd`：`VERSION = 4`、§5.1 的 `BATTLE_CMDS`、`mode` 參數、§6.12 的 intent／事件／原因碼常數與 `INTENT_SCHEMA`；(2) `core/data/data_schema.gd`：3.7 條件型別與欄位、`RULE_DEFAULTS`／`RULE_ENUMS`（3.10）、`INT_FIELDS`（`status_effects` 的 `duration_actions persist_tick_real_s persist_ticks_per_level`、`sects` 的 `hostile_entry[].count[]`、`masters`……）、`REFS`（`sects.head_npc`→npcs、`sect_rules.sect`→sects、`martial_arts.moves[].status`→status_effects）；(3) `Character` 新欄位與 `to_combatant` 新 spec 欄位（可先填空陣列）；(4) `GameHost` 容錯載入 `SectSystem`、`ConditionSystem` 與新 intent 檔 | WP-CMD 需要 spec 形狀與 cmd 常數；WP-UI 需要常數 |
| WP-CMD | (1) `data/status_effects.json` 照 3.8 貼上；(2) `BattleSystem.start_ex` 簽名（可先轉呼 `start`） | WP-RULES 的試煉、敵對入山要呼叫 |

其他 WP 開工時 Day-0 還沒落地：先寫純邏輯與不依賴新常數的測試；字串用與本文件**完全相同**的字面值，交付前改回常數。

### 8.4 合併程序（WP-MERGE）

1. 讀 `docs/m3a_staging/*.json`（8 派 + `shaolin.json` + `_cmd.json` + `_rules.json`）。逐檔 JSON 解析；任何 id 重複（跨碎片或與現有資料）→ 停下並在報告列出，**以先到者（字母序）為準**，後者改名加 `_2` 並記錄。
2. 依表合併：`sects`（取代同 id 列；遷移少林、華山，3.1）、`sect_rules`、`regions`、`npcs`、`masters`、`martial_arts`、`monsters`、`items`、`quests`、`text_templates`（同 id 以碎片為準，報告列出覆寫）；`maps` 寫成 `data/maps/<region>.json`；`extra_rooms` 附加到既有地圖；`exit_patches` 套到既有房間；2.2 表的既有房間與 desc；`art_requests` → `data/art.json` 的 `units`／`backgrounds`（`alias` 照填，`required: false`、`placeholder: false`）。
3. 補商店（3.9）與 `dali` 的武當老人（`n_wd_dl_oldman`）房間。
4. `tools/data_lint.gd` 新檢查（§8.5），跑到 0 錯誤；跑 `tools/balance_sim.gd` 走路案例；跑全部單元測試；更新 `test_data_content.gd` 的計數與新派抽查。
5. `docs/ART_REQUEST.md` §6「第三批」：每派男／女門派服（依允許性別）、主要師父立繪（收徒 NPC、入門師父）、每個新地區戰鬥背景；格式照前兩批。

### 8.5 Lint 新檢查（`tools/data_lint.gd`）

1. 3.7 新條件型別的欄位；`any_of` 內層每個條件。
2. `sects`：`prefix`、`gate_room` 存在且屬於 `gate_region`、`head_npc` 存在且有 `JOIN` 與 `BETRAY`、`jail_room` 存在且 `jail: true`（`enforcer: false` 時必須空）、`hostile_entry[].monster` 存在、`rooms` 合法、`sect_skill` 有師父教。
3. `sect_rules`：`tier`、`kind`、`event` 合法；`text` 模板存在。
4. `martial_arts`：新類別合法；`formation`／`inner`／`poison`／`medic`／`hidden` 與類別一致；`aoe` 合法；招式數值範圍（3.4）；`QUEST` 必須有 `quest_flag`；`unlock_level` ≤ 教這套武功的最高 `masters.cap`（只教 1 級的 QUEST 武功除外）。
5. `masters.skill_id` 存在；`hours` 是合法時辰。
6. 每派：收徒 NPC 從兩座出生城走得到（既有可達性檢查擴充到 `head_npc` 房間）；3.2 表的固定 id 全部存在。
7. NPC 服務：`BETRAY`、`JAIL`、`TRIAL`（`trial` 欄位、怪物存在）、`GUIDE`（`to_room` 存在、與 NPC 同地區）。
8. 新休息點有 `INN` NPC；§2.3 新手規則（既有檢查自動涵蓋新山門）。
9. `items.effects` 新型別（`hidden`、`cure`）；`sect_only` 指向存在的門派。
10. 房間 `jail`、`encounter_exempt`（門派存在）、`meditate` 欄位型別。
11. 簡體字檢查擴充到新文字（既有檢查若有，否則新增常見簡體字黑名單：门 派 师 剑 刀 气 内 毒 医 阵 宫 灵 鹫 峨 恒 全 古 墓 武 当 华 少 林 中 的 简体对应）。

---

## 9. 規則與數值表

| 項目 | 數值 | 依據 |
|---|---|---|
| 1 遊戲日 | 2 真實小時（`game_day_real_s` 7200，累計上線） | 【已證實】news 331 |
| 違反門規坐牢 | 1 遊戲日 | 【已證實】jy2-22（2001-11-15 起） |
| 公敵被抓坐牢 | 3 遊戲日 | 【已證實】jy1-2-5-4 |
| 贖人 | 100,000 兩 | 【已證實】jy1-2-5-4 |
| 坐牢可用頻道 | 傳音入密、輕聲細語 | 【已證實】 |
| 禁止學武（BAN） | 1 遊戲日 | 【設計提案】 |
| 叛派懲罰 | 本門武功減半、門派技能歸零、門派物品沒收、公敵永不得回 | 【已證實】2001 各派頁、news 317；後期全部減半為規則選項 |
| 違規後果三種模式 | EXPEL（2001-08 前）／JAIL（2001-11-15 後）／BAN | 【已證實】時間線；預設組合對應【設計提案】 |
| 門派技能觸發率 | 5% + 0.2%/級，最高 25% | 【設計提案】GDD 3.3 |
| 觸發消耗 | 兩項各 3 | 類型【已證實】；數值【設計提案】 |
| 中毒 | 每次行動扣氣（2% + 0.4%/級）；戰後每 120 秒發作扣 3%，共 等級×2 次，不致死 | 機制【已證實 news 316】；數值【設計提案】 |
| 毒成功率 | 0.40 + (P−R)×0.005（0.10–0.90）；非本派 ×0.5 | 【設計提案】；非本派較低【已證實】 |
| 毒直接傷害 | 招式威力 × 0.5 × (1 + 等級/60) | 「比特攻小」【已證實】 |
| 醫 | 20 + 2×基本醫術 + 3×醫術；恆山 ×1.3；精 10 神 5 | 【設計提案】；恆山醫療強【已證實早期文】 |
| 暗器傷氣 | 彈弓 2、金錢鏢 8、飛蝗石 12、鐵菱 20、魚鏢 20、鐵蓮子 35 | 【已證實】官方暗器頁 |
| 暗器射程 | 3 + 基本暗器/40 (+武功)，最多 6 | 【設計提案】 |
| 暗器消耗 | 每丟 1 個 | 【待考證】 |
| 陣法 | 站位固定、平均等級加成、一人倒下即破、只限隊伍 | 【已證實】jy2-99 舊陣法；數值【設計提案】 |
| 內 療傷 | 10% 內力換氣 ×(1+內功/100)；全真 ×1.3 | 【設計提案】；全真療傷強【已證實 2002】 |
| 內／穴 | 2002-01-25 才有；規則 `later_battle_cmds` | 【後期版】 |
| 點穴成功率 | 0.30 + (攻−守)×0.004（0.05–0.80） | 【設計提案】；基本刺術管點穴【已證實】 |
| 定力縮短狀態 | 每高於 20 的 10 點 −1 次 | 機制【已證實】；公式【設計提案】 |
| 十八銅人 | 3 人、3 波、每波 6 隻、通過開藏經閣與金剛伏魔圈 | 【已證實】少林官方頁 |
| 十八銅人實戰門檻 | 60,000 | 【待考證】（另一說 50 萬） |
| 武當入派 | 男、善惡 ≥ 50、引薦書 | 【已證實】2001-07-08 |
| 峨嵋入派 | 女、非邪惡（≥ −299） | 【已證實】；邪惡 = ≤ −300【待考證】 |
| 恆山入派 | 女、善惡 ≥ 0、PK 0 | 【已證實】 |
| 全真入派 | 男、善惡 ≥ 0 | 【已證實】（「不低於初始數值」） |
| 古墓入派 | 女、中立（−299…299） | 【已證實】中立；數字【後期版】 |
| 靈鷲入派 | 女、−299…299、PK ≤ 3 | 【已證實】官方頁 |
| 星宿入派 | 善惡 ≤ −100 | 【已證實】官方門規「> −100 不能學武」 |
| 血刀入派 | 男、善惡 ≤ −100 | 2003「−99 以下」【後期版】 |
| 敵對入山 | 武當：惡人入山即戰；峨嵋：邪惡隨機戰；恆山：負善惡或有 PK 高機率；全真：≤ −500；血刀：正善惡；各派公敵 | 【已證實】各派頁 |
| 斷惡取得 | 每殺一隻邪惡怪 +10 熟練 | 機制【已證實】；數值【設計提案】 |
| 定性／諂媚衰減 | 殺氣 > 2000 時每遊戲日 −1 級 | 機制【已證實】；數值【設計提案】 |
| 全真進古墓 | 違反門規 + 養生 −1 級 | 【已證實】門規；數值【設計提案】 |
| 滅絕只教 1 級 | 九陽、滅劍等 `cap: 1` | 【已證實】2001-08-13 |
| 血刀刀法係數 | 1.6 | 【待考證】（後期表 1.40） |
| 玉女劍法係數 | 0.96 | 早期粉絲表（後期 1.12） |
| 天山折梅手係數 | 1.25 | GDD（後期 1.508） |
| 滅仙掌上限 | 80 | 2001 低於 100【已證實】；80【設計提案】 |
| 古墓迷宮遇敵率 | 0.35（弟子與引路者免） | 「一路高機率」【已證實】；數值【設計提案】 |

---

## 10. 測試計畫

### 10.1 各 WP 的單元與整合測試（全部在 `tests/run_tests.gd` 裡跑）

| WP | 檔案 | 至少涵蓋 |
|---|---|---|
| WP-CMD | `test_battle_m3a_cmds.gd` | 每個新指令的驗證原因碼（5.2 每列至少一個）、成功路徑事件、內力／精／神扣除、暗器數量遞減、ITEM 解毒 |
| | `test_battle_status.gd` | 每個狀態的效果（扣氣、跳過、亂打、封鎖移動、攻擊倍率、時間棒倍率、流血移動扣氣）、定力縮短、LEVEL_MAX 疊加、RESIST 抵抗、戰鬥開始帶入狀態、快照 `statuses` |
| | `test_battle_aoe.gd` | 六種形狀的格子集合（含邊界與鏡像）、多目標各自結算、不反擊、`bad_direction`、`no_target` |
| | `test_battle_formation.gd` | 3 人陣成功、站位不足、性別限制、一人倒下破陣、移動破陣、加成數值 |
| | `test_battle_waves.gd` | 3 波接續、`battle_wave` 事件、最後一波才勝利、`no_flee` |
| | `test_battle_procs.gd` | 8 種門派觸發（固定亂數種子）與消耗、消耗不夠不觸發；DEFENSE／RECOVER 行為不變（M1 金檔照舊通過） |
| WP-RULES | `test_requirements_m3a.gd` | 3.7 每個新條件 |
| | `test_sect_system.gd` | 停止傳功、STATE 轉換只觸發一次、三種模式、無執法者轉 BAN、叛派減半（預設與 `betrayal_halves_basics`）、沒收門派物品、公敵不能再拜、全真 `sect_master` |
| | `test_world_sect.gd` | 8 派各一位合格角色拜師成功、不合格的原因碼（性別、善惡、引薦書、公敵）、內室 `any_of` 鎖、敵對入山開戰（含選項關閉）、引路、斷惡取得、衰減、進古墓違規 |
| | `test_world_jail.gd` | 押入、指令封鎖清單、頻道限制、不能出房、期滿出獄與公敵清除、贖人、公敵死亡被抓、坐牢中不踩地雷不偵察 |
| | `test_world_conditions.gd` | 戰後中毒發作與到期、解毒藥、選項關閉、不致死 |
| | `test_protocol_m3a.gd` | VERSION 4、新 intent schema 與 enum、`debug_set` 只在 `--debug-intents` 註冊 |
| | `test_character*.gd`（改） | SCHEMA 2 讀舊檔、`to_combatant` 新欄位、`betray_penalty` |
| WP-UI | `test_ui_m3a_battle.gd` | 按鈕啟用依 `cmd_avail`、`later_battle_cmds` 關閉時鎖住、選目標顏色、內選單、暗器選單、陣站位顯示、範圍預覽、狀態圖示 |
| | `test_ui_m3a_sect.gd` | 拜師確認、叛教兩段確認送出 intent、坐牢提示與倒數、贖人鈕、學藝視窗被拒原因、屬性燈籠變色、HUD 狀態 |
| WP-MERGE | `test_data_content.gd`（改） | 10 派列、3.2 固定 id、接點出口雙向、各派入門兩套武功與驗收招式存在且 `unlock_level == 1`、新物品與商店 |

### 10.2 平衡（`tools/balance_sim.gd`，WP-CMD）

新案例（`CASES`）：
- `p1_sect_<id>`（8 個）：P1 參考角色學本派入門武功 20 級、用驗收招式打 `m_wolf`，勝率 ≥ 0.70，且平均行動數 ≥ 少林長拳參考線 × 0.55（與少林長拳同級，防止某派過強）。（整合紀錄 I4：原寫 0.70–0.98，但參考線本身就是 100%）
- `p0_vs_<id>_dizi`（8 個）：P0 學入門武功 5 級打本派切磋怪，勝率 0.35–0.85（與範本華山弟子 ~54% 同級）。（整合紀錄 I4：原寫 ≥ 0.90）
- `newbie_vs_<id>_guard`（8 個）：P0 打本派守衛，勝率 ≤ 0.05（敵對入山真的危險）。
- `party3_vs_tongren`：3 名 P3 參考角色、3 波，勝率 0.40–0.85。
- `formation3_bonus`：3 人金剛伏魔圈 vs 同條件無陣，勝率至少高 15 個百分點。
- `poison_p1_vs_wolf`：P1 只用毒指令（放毒法 20 級、基本毒術 20、基本內功 20）＋防，平均戰鬥時間比普通攻擊長、但勝率 ≥ 0.5（毒不是無敵）。（整合紀錄 I4：P1 底子內力 25 只夠放 6 次毒）
- `gumu_maze_p3`：P3 在古墓迷宮連打 3 場的存活率 0.6–0.95（中段練功點）。

`ROUTE_CASES` 新增（P0、surv ≥ 0.90）：`p0_walk_dl_emei`（dl_square → em_gate）、`p0_walk_dl_quanzhen`（→ qz_gate）、`p0_walk_dl_gumu`（→ gm_entrance）、`p0_walk_dl_wudang`（→ wd_gate）、`p0_walk_xx_hengshan`（→ hg_gate）、`p0_walk_xx_lingjiu`（→ lj_gate）、`p0_walk_xx_xingxiu`（→ xh_gate）、`p0_walk_xx_xuedao`（→ xd_gate）、`p0_walk_dl_shaolin_south`（dl_square → sl_gate，最短路線會走新南路）。既有 4 個走路案例照舊要過（路徑可能因南路改變，數值仍要達標）。

### 10.3 驗收：`tools/m3a_acceptance.gd` + `tests/bots/m3a_sect_bot.gd`（整合者）

照 `tools/m2_acceptance.gd` 的寫法：指揮程式啟動一個主機（`--offline` 或區網、`--debug-intents`、全新世界 `--world=m3a_accept_<時間>`、`--time-scale=20`）與 bot 客戶端，bot 依劇本跑，最後輸出 `M3A_ACCEPT_OK` 與結束碼 0；任何一步失敗輸出 `M3A_ACCEPT_FAIL <步驟> <原因>` 結束碼 1。可用 `--sect=<id>` 只跑一派。

**每派劇本**（8 派各建一個新角色；性別依 3.2）：
1. 創角（出生城：恆山、靈鷲、星宿 → 西夏；武當、峨嵋、全真、古墓、血刀 → 大理），`debug_set` 把善惡設到該派入派範圍中間值（武當 100、峨嵋 0、恆山 0、全真 0、古墓 0、靈鷲 0、星宿 −200、血刀 −200）、`combat_xp` 2000、`money` 5000、`learn_points` 3000。**善惡為負的設定要等走出出生城之後才做**（M2 規則：善惡為負進出城會被官兵攻擊【已證實】；需要的兵器、藥先在城裡買好）。**不准用 `teleport`**：從出生城**走路**到山門（用 `data_lint.find_path` 算路，一間一間 `move`；遇到戰鬥就打或逃，死了算失敗）。
2. 途中在第一間有遇敵表的新地區房間按一次查看（`look { scout: true }`）：收到 `scout_offer` 後送 `scout_decline`（偵察保持可用）。
3. 武當先接 `q_wd_yinjian`、交引薦書；古墓先找孫婆婆 `npc_guide`；其餘直接走到收徒房。`join_sect` 成功（收到 `sect_join`）。
4. 學門派技能 → 心法 → 入門兵器武功，各至少 1 級（`learn`），需要兵器的去城裡買（木劍）並裝上。星宿另學 `basic_poison`、`xh_fangdu`；恆山另學 `basic_medic`；靈鷲確認 `lj_zhemei`。
5. 對切磋 NPC `fight`；在戰鬥中至少一次用驗收招式（`ART`，3.2 的 move id）並至少一次用驗收指令（3.2；內＝`INNER HEAL`、醫＝`MEDIC` 自己、毒＝`POISON` 對敵、穴＝`ACUPOINT` 對敵），收到對應事件（`move_*`、`battle_inner_heal`、`battle_medic`、`battle_poison_ok|fail`、`battle_acupoint_ok|fail`）。打完（勝或敗都可，不能卡死）。
6. 確認角色表 `sect_info.id` 正確、兩套武功等級 ≥ 1。

**門規劇本**（在全部 8 派之後）：
- 坐牢：用少林新角色（大理出生走到少林或西夏出生）拜師後 `debug_set killing_intent 2500` → 收到 `sect_breach`（JAIL）與 `jail_in`，人在 `sl_siguo`；`move` 回 `jailed`；`chat` 世界頻道被拒、密語可用；`debug_set online_s_add 7300` → 收到 `jail_out`，人在 `sl_gate`。
- 叛派：星宿角色找丁春秋 `sect_betray { confirm: false }` → `need_confirm`；`confirm: true` → `sect_betray`；本門武功等級減半、`chanmei` 為 0、`enemy_of` 含星宿；再 `join_sect` → `req_not_enemy_of`；走進 `xh_hall` → `sect_hostile` 開戰。
- 公敵被抓：武當角色叛派後走進 `wd_square` → `SECT_GUARD` 戰鬥（不能逃）→ 戰死 → `jail_in`（`wd_siguo`，3 天）。
- 陣：`tests/unit/test_battle_formation.gd` 涵蓋（驗收不另跑 3 人隊）。十八銅人：`test_world_sect.gd` 用 3 個測試角色跑 `sect_trial` 的開戰與勝利旗標（波次縮短的測試資料）。

### 10.4 回歸（全部要綠）

`tests/run_tests.gd`（目前 710 個，加上新測試後 0 失敗）、`tools/data_lint.gd` 0 錯誤、`tools/balance_sim.gd` 全部案例在區間內、`tests/ui/ui_playthrough.gd` 無頭（整合者加：戰鬥中按「內」療傷一次、恆山／星宿角色按醫／毒的畫面截圖）、M1 驗收 bot（全新世界）、`tools/m2_acceptance.gd`、`tools/net_smoke.gd`、`tests/bots/close_mid_battle_bot.gd`（`--close-mode=wm` 與 `quit`，不能有 SCRIPT ERROR）、`tools/m3a_acceptance.gd`。每次跑完 `tasklist /FI "IMAGENAME eq Godot*"` 確認沒有殘留。

---

## 11. 交付與整合

1. 各 WP 交付說明：改了哪些檔、與本文件的偏差（`M3A_PLAN 缺漏`）、自己的測試結果（`--filter`）、已知問題。
2. 門派建造者另列：所有【待考證】、取捨（例：哪些房間名稱是自訂）、要給擁有者的圖。
3. WP-MERGE 交付：合併報告（每個碎片的列數、改名、覆寫、lint 錯誤處理）、全部單元測試結果。
4. 整合者：修跨 WP 不一致（以本文件為準；若偏差更好，改本文件並記在第 12 章）、跑 §10 全部、README 加「M3a：怎麼拜入各派、新戰鬥指令、門規與思過處」一節。

## 12. 整合紀錄

整合者（2026-10-19）。以本文件為準修跨 WP 不一致；以下偏差比原文更好，已同步改寫上文。

| # | 問題 | 處理 |
|---|---|---|
| I1 | 世界全圖 `ui/game/map/world_map_view.gd` 寫死 8 個「未開」山門（只用名字比對），新地區名稱是「恆山派」「武當派」…，6 派開放後仍畫成未開；新 16 個地區讓西夏一帶太擠，3 個 UI 測試失敗 | `CLOSED_SITES` 加 `region`，該地區已在 regions 就不畫；剩衡山、雁門關兩個「未開」。整組推開後再清一次道路（只在不壓到別人時移動），血刀洞迷宮的記號不再貼著別的路。`test_ui_review_w2001` 改成 2 個未開＋各派地區名 |
| I2 | `--debug-intents` 沒有值時 `CliArgs` 給 bool，`args["debug-intents"] != "false"` 是 bool 與 String 比較 → SCRIPT ERROR、debug_set 永遠沒註冊 | `autoload/world_server.gd` 改成 `str(...) != "false"` |
| I3 | 門派技能消點耗內力（武當、恆山、血刀：精＋內力），新角色內力上限 0，**3.2 的入門順序「門派技能 → 心法 → 兵器」學不了第一步** | ~~不改規則（原作就要內力）~~ **審查 R3 更正**：官方表的「會耗精與內力」是戰鬥觸發的消耗，不是學習消耗，原作沒有這條。學習消耗改看 `sects.sect_skill_train_cost`（依各派的修練方式，數字【設計提案】）；驗收 bot 的順序（基本內功 → 打坐 → 門派技能 → 心法 → 兵器）照舊可用，但不再是必要 |
| I4 | balance_sim 18 個案例與參考線矛盾：`p1_sect_*` 上限 98% 但參考線少林長拳 20 級就是 100%；`p0_vs_*_dizi` 要 ≥ 90% 但範本華山弟子只有 54%；`poison_p1_vs_wolf` P1 內力 25 只夠放 6 次毒；古墓迷宮 `gumu_maze_p3` 存活 0%（怪物是實戰 6.5–10 萬級、2–4 隻一群） | 判準改寫在 10.2（速度下限取代勝率上限、切磋 0.35–0.85、毒案例基本內功 20）。資料【設計提案】重調：迷宮 蝙蝠／玉蜂／盜墓賊 一次 1 隻、氣 260／240／380、武功 30–32 級、`combat_xp_ref` 2–2.8 萬（洪凌波不動，5% 機率的危險）；`m_xd_dizi` 血刀刀法 6 級、氣 210，`m_wd_dizi` 氣 215。57 個案例全過 |
| I5 | 大理沒有兵器鋪，大理出生的全真、古墓（劍法）買不到木劍；3.2 要「去城裡買（木劍）」 | 大理雜貨鋪 `n_dl_grocer` 加賣 `w_mujian`【設計提案】（與 WP-MERGE 加的皮鞭同理） |
| I6 | 主機最多 8 個連線（凍結檔 `NetworkManager.ENET_MAX_CLIENTS`），驗收 9 個劇本不能同時上線 | `tools/m3a_acceptance.gd` 同時最多 7 個 bot，跑完一個補一個 |
| I7 | 驗收 bot 是 P0 新手，路上被野狼咬死就算失敗；切磋輸了也會死（FIGHT 照常死亡） | bot 出城前在武館學基本內功 4、兵器基本功 10（新手照樣做得到）；路上兔子就打、其他就逃；切磋達成招式與指令後就逃，氣 < 55% 也逃，逃不掉先運功療傷 |
| I8 | 驗收劇本細節 | 偵察：第一間新地區野外「離開」，之後第一次只發現兔子就「迎戰」（使用者要求的查看迎戰流程兩條路都測）；少林（jail）的東路沒有新地區，第一間野外就偵察。叛派後「走進 `xh_hall`」改成在星宿地區走一步（`rooms: ALL`，人本來就在 `xh_hall`）；公敵被抓同理在武當走一步 |
| I9 | 0.4 的 `close_mid_battle_bot` 指令寫成 `--script`，它其實是 `--bot`（M1 bot 的子類，要離線世界） | 0.4 改正 |
| I10 | `ui_playthrough` 要按 內／醫／毒，但無門派的介面角色學不到內功心法、醫術、毒術 | 主機加 `--debug-intents` 時，查看偵察前用 `debug_set` 給恆山心法、基本醫術、基本毒術＋放毒法（設定，不是受測物），之後從指令列真的按「內 → 運功療傷」「醫 → 點自己」「毒 → 點相鄰敵人」；每場戰鬥檢查六個新按鈕都在。沒帶參數時警告並略過 |
| I11 | 查看偵察：負載高時客戶端倒數比主機早幾個影格，按鈕亮了按下去卻是「再等 1 秒吧」（ui_playthrough 在 9 個 Godot 同時跑時偶發） | `ScoutSystem.GRACE_REAL_S` 0.3 真實秒：剩不到這麼多就當作冷卻完了（顯示用的倒數不變） |

### 12.1 審查修正（2026-10-19，第二輪）

| # | 審查意見 | 處理 |
|---|---|---|
| R1 | 坐牢門檻用了 2001-08 叛派名單（武當 −99、全真 −299、古墓 −500／2000／3） | `sect_rules.modes`：JAIL／BAN 用 jy2-22 坐牢名單（武當 −299、全真 −399、古墓 PK > 10、殺氣 > 10000），EXPEL 用 2001-08 名單；武當 2001-08 的 −99／−199 是「跟特定師長交談時」→ `on_npc` 交談觸發。恆山殺氣 3000 只在 EXPEL。屬性燈籠與拜師確認的門規文字也照模式篩 |
| R2 | 全真弟子進古墓被坐牢 | 刪 `qz_r_gumu`；只剩 `sect_skill_penalties` 降養生 1 級（mengpai/6） |
| R3 | 學門派技能扣的是觸發消耗 | 新欄位 `sect_skill_train_cost`／`sect_skill_train_note`；I3、GDD 3.1 改寫 |
| R4 | 2001 規則組仍跑 2002 的觸發與狀態 | `try_proc`、DEFENSE、RECOVER 與 `since: "gmdk"` 狀態的施加都看 `later_battle_cmds`（D9 擴充） |
| R5 | 狀態不照研究 | 補 2001 官方狀態 氣血失調（藍）、昏迷（灰）、走火入魔（紫）；內傷、痲痺換掉撞到的官方色；內傷改 `src: later`＋`since: gmdk`；痲痺改成「不能移動、時間棒變慢」；流血改成「氣上限一直往下掉、醫可止血」並標【設計提案】。戰鬥中第 3 次吃藥起氣血失調、失調中再吃藥昏迷（次數【設計提案】）；走火入魔的觸發不在戰鬥範圍【待考證】 |
| R6 | 後期數字標成已證實 1.0A | 15 套武功列改 `src: later`；萬花劍法的教者（定閒師太）改 `unverified` |
| R7 | 飛星術在 1.0A 可學；era／src 混用 | 飛星術 QUEST 鎖住（D6）；0.2 寫明 era／src 分工，`data_lint` 要求 1.0A＋later 的列都有 `src_note`（補了 45 列）。三陰蜈蚣爪屬 1.0 核心 6 套（研究），重陽劍法、空明拳本來就 quest 鎖住：不改 era |
| R8 | 陣法標 1.0A | D13：陣法武功、基本陣法、陣法狀態、教陣的師父列改 1.0B；balance_sim `formation3_bonus` 用 1.0A＋1.0B 視圖 |
| R9 | 缺研究項目 | 古墓入派加「未婚」「守宮砂未失」（新條件 `not_flag`）；武當執法者補齊 7 人；攻擊師父＝叛派寫進 1.2 不做清單（沒有對 NPC 出手的指令）。古墓硬闖：原本就能走 `gumu_maze` 迷宮硬闖（遇敵率 0.35、不算公敵），`visitors` 只是 lint 用 → 不改 |
| R10 | 叛派懲罰混了兩個時代 | 門派技能歸零跟 `betrayal_halves_basics` 綁在一起 |
| R11 | 公敵坐完牢可以再拜 | 新增存檔欄位 `sect_traitor`（叛徒記號）；坐牢期滿仍移除公敵（研究 jy1-2-5-4 改過自新），但 `not_enemy_of` 也看叛徒記號 |
| R12 | 戰後持續中毒每打一場就重設 | 進戰鬥不再清掉角色身上的持續狀態；戰鬥中只帶剩餘行動次數（`actions_left`），戰後保留原本的發作次數與時刻 |
| R13 | 十八銅人可以中途加人 | `TRIAL` 與 `party_only` 的戰鬥 `battle_join` 回 `join_not_allowed` |
| R14 | 介面 | 滿血「運功療傷」灰掉（氣血已滿）、滿血又沒中毒／流血的人不是醫的目標；醫／用藥選自己人時頭上綠箭頭＋腳下閃爍綠框畫在人物上面；相鄰時名字牌與腰部氣血字不蓋到別人身上；冷卻層在不能用時改暗色；場景的「搜尋野獸」改名「查看」；世界地圖門派地名帶「派」、地名不會比較靠近別人的記號；戰報「戰鬥結束」排在最後一擊之後、實戰獎勵不重複；拜師確認紅字列出看得出來的不符合條件；拜師後選單即時換成「叛教」。`ui_playthrough` 新增截圖：滿血內選單、狀態圓牌、恆山師父與不符合條件、星宿師父與拜師確認、叛教兩段、思過處提示列、看守人贖人列 |
| — | 血刀 威嚇 觸發率（速度 0.61，下限 0.55） | 擁有者再看；資料不動 |

驗收結果（整合者跑）：`tests/run_tests.gd` 884 個 0 失敗、`data_lint` 0 錯誤 0 警告、`balance_sim` 57 個全過、`ui_playthrough`（headless 與視窗截圖）`UI_PLAY_OK`、M1 bot 全新世界 `M1_ACCEPT_OK`、`m2_acceptance` `M2_ACCEPT_OK`、`net_smoke` PASS、`close_mid_battle_bot` wm／quit 沒有 SCRIPT ERROR、`m3a_acceptance` 9 個劇本 `M3A_ACCEPT_OK`。

## 13. 開放問題（擁有者決定；預設值已寫在本文件）

1. 靈鷲宮的位置（1.0 無座標）：預設西夏西北的天山道。
2. 古墓「沒有任務不得離開終南山」：預設不執行。
3. 十八銅人實戰門檻：預設 60,000（另一說 50 萬）。
4. 武當 俠義：2001 只能靠任務取得；預設宋遠橋可教到 20 級。
5. 內、穴、門派技能觸發與 2002 狀態（痲痺、混亂、封穴、內傷、分心）屬於 2002：預設開（`classic_strict` 全部關，D9）。
6. 招式名稱全部是設計提案（原作沒有招式名單）。
