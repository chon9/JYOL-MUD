# M3d 實作計畫：懸賞與律法、戰鬥增補與合體技、門派武功鏈、門派比武與劫鏢、跑腿與城鎮學點、黑龍潭（M3D_PLAN）

> 版本：2026-10-21（開工版）。協調者撰寫；實作中只由協調者（整合者）修改本文件。
> 上游：M3C_PLAN §1.2 與 M3C2_PLAN §1.2 的「M3d」延後清單；擁有者在 0.6.1.0 回報後的指示（陸大有切磋獎勵 BUG 排進 M3d）；M3C2_PLAN（`chore` 欄位、規則與選項格式、`balance_sim`／`data_lint` 區塊切分）；M3C_PLAN（攻擊 NPC、神兵、`m2_call` 鉤子）；M3A_PLAN（門規、坐牢、戰鬥指令 `later_battle_cmds`）；M2_PLAN（PK、叫戰、強制 PK、守城官兵）；STORY_PLAN §4（任務引擎 v2）、§5.2（遊蕩惡人與追擊戰）。
> 研究：`docs/research/verified_research.md` 的「M3d 研究」章（以下簡稱「研究」；分節：懸賞、戰鬥、武功鏈、事件、跑腿）。研究與本文件不一致時，以本文件的「擁有者決定」（§1.3）為準，並在 `src_note` 寫明。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

M3d 由 5 個工作包（WP-LAW、WP-COMBAT、WP-ARTS、WP-EVENTS、WP-ERRANDS）**同時**在同一個工作目錄實作，最後由整合者驗收。實作者之間不溝通。規則沿用 M3C2_PLAN §0.1：

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent 參數、事件 key、原因碼、伺服器選項 key、規則 key、存檔欄位、資料列 id 與前綴、檔名、房間 id**都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定（例如對白文字、怪物招式組合、函式內部結構）。
3. 優先順序：本文件 > M3C2_PLAN > M3C_PLAN > M3B_PLAN > STORY_PLAN > M3A_PLAN > WORLD_2001 > M2_PLAN > M1_PLAN > GDD > TECH_ARCH。偏差列在 §1.4。
4. 發現缺漏：照「最不意外」實作，程式裡寫 `# M3D_PLAN 缺漏：……`，交付說明列出；**不要**改別人的檔案（共用熱檔照 §9.2 的切分）。
5. 依賴別的 WP 的東西（類別、函式、資料 id）一律照本文件的簽名寫，並且**容忍對方還沒完成**：用 `host.m2_call(host.get("<系統>"), "<方法>", [...], <預設>)`、`ResourceLoader.exists()`、`tables` 查不到 id 時略過。這樣 5 個 WP 可以各自通過自己的測試。

### 0.2 標記

沿用 GDD 第 0 章：【已證實】【後期版】【待考證】【設計提案】【設計提案・非原作】。新資料列一律有 `era`、`src`（`verified`／`later`／`proposal`／`unverified`）、必要時 `src_note`。本文件新增的數值一律【設計提案】，有研究依據的在 `src_note` 註明（例：`"src_note": "研究 懸賞：天師 100 兩消 10 殺氣【已證實 7-11 news_2-5】；位置（西夏東門外官道）【設計提案】"`）。2002 以後才有的系統（門派比武、武林大會、血池、空明拳等）照專案慣例 `src: "later"`，`era` 用它最早能放進的版本（1.0A／1.0B），`src_note` 寫真正的年份。

### 0.3 全域規則

M1_PLAN G1–G10、M2_PLAN H1–H6、M3A_PLAN K1–K6、STORY_PLAN §0.3、M3B_PLAN L1–L8、M3C_PLAN N1–N9、M3C2_PLAN Q1–Q9 全部繼續有效（主機權威、離線同一路徑、`core/**` 純邏輯、JSON 數字轉 int、**不 commit、不 push**、測完關掉 godot 並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認、新增 `class_name` 後先 `--import`、不新增 Autoload、不新增 `@rpc` 方法）。M3d 另加：

| # | 規則 |
|---|---|
| T1 | `Protocol.VERSION` **維持 5**：M3d 只新增 intent、可選參數、事件、原因碼、快照欄位、`BATTLE_CMDS` 列舉值、`NPC_SERVICES` 列舉值；RPC 簽名不變。新舊混用由 `content_hash`（資料指紋）與版本比對擋下。若任何 WP 發現**非改 RPC 簽名不可**，停下來寫 `# M3D_PLAN 缺漏`，交整合者決定（只有整合者可以升 VERSION）。 |
| T2 | **一個檔案只有一個擁有者**（§9.1）。共用熱檔照 §9.2 切到「函式／欄位／具名區塊」層級；不在表上的修改一律禁止。具名區塊的標記一律是 `# ==== M3d WP-<名> ====`（檔尾）或行尾註解 `# M3d WP-<名>`（單行鉤子）。 |
| T3 | **共用 JSON 的寫法**（同 M3c2 Q3）：只用 Edit 工具做局部取代（每次 Edit 前重新 Read），**不得整檔重寫、不得重新排版、不得用 `json.dump` 重寫 `data/*.json`**。新列一律插在檔尾 `\n  ]\n}` 之前；改既有列只改 §9.2 准許的列與欄位。五個 WP 同時往同一個 JSON 檔尾插列：插入前重新 Read，插入失敗就重讀再插。 |
| T4 | **測試資料隔離**：測試、bot、驗收只寫測試根目錄（`DataRoot.test_root()` = `K:\Project\JY-Mini-OL-Work\testdata\`）或 `--data-root=<K: 上的絕對路徑>`。**絕對不碰**：`K:\Project\JY-Mini-OL-Release\userdata\`（擁有者真實存檔）、`K:\Project\JY-Mini-OL-Work\userdata\`、`K:\Project\JY-Mini-OL-Work\share\`、`appdata_old*`。**不寫 C:**。截圖 `K:\Project\JY-Mini-OL-Work\shots\`、log `K:\Project\JY-Mini-OL-Work\logs\`、暫存 `K:\Project\JY-Mini-OL-Work\tmp\`。 |
| T5 | **不刪任何東西**（`K:\Project\JY-Mini-OL-Work\tmp` 以外）：要淘汰的檔案搬到 `K:\Project\JY-Mini-OL-Work\tmp\m3d_moved\<WP>\`。資料列不刪：要停用就改 `era`／`requires` 並在 `src_note` 寫原因。 |
| T6 | 新 id 前綴（綁定）：WP-LAW `law`、WP-COMBAT `cb`、WP-ARTS `ar`、WP-EVENTS `ev`、WP-ERRANDS `er`。資料列：`n_<前綴>_*`（NPC）、`m_<前綴>_*`（怪物）、`i_<前綴>_*`（任務道具與特殊道具）、`q_<前綴>_*`（任務）、`ms_<前綴>_*`（師父列）、`w_<前綴>_*`（遊蕩列，如有）。文字模板：`<前綴>_*`、`talk_n_<前綴>_*`、`err_<原因碼>`（原因碼本身照 §7 的前綴）、`rmr_<前綴>_*`（傳聞）。房間 id 照 §9.5。 |
| T7 | **凍結檔**（§9.4）：任何 WP 都不得修改。戰鬥平衡的新規則只能寫在 `battle_rules.gd`／`battle.gd`／`battle_cmds.gd`／`battle_unit.gd` 與新檔 `core/battle/battle_combo.gd`。若戰鬥金檔因新指令改變（不應該：新指令只有被選用才生效），由 WP-COMBAT 用 `tools/regen_battle_golden.gd` 重產並在交付說明列出差異。 |
| T8 | **時代**：1.0A-only 世界（`--eras=1.0A`）與 `classic_strict` 必須完整可玩。1.0B 的東西（合體技、半仙、劫鏢、柯鎮惡→郭靖、武林帖、黑龍潭迷宮、血魔刀法、四象掌）一律 `era: "1.0B"`；1.0A-only 世界看不到它們，也不會因缺它們出錯（`data_lint` 的 1.0A 視圖要 0 錯誤）。 |
| T9 | **多人安全**：所有新的錢、名聲、學點來源都必須在 `balance_sim` 有一個「刷不出來」的案例（§10.2）；朋友互殺、互劫、互相出懸賞不能產生淨收入（§2.4、§5.2.4）。新手保護（實戰 < `newbie_pk_protect_xp`）照舊：不能被強制 PK、不被懸賞、不被賞金獵人追殺、不能被劫。 |
| T10 | **不碰擁有者世界資料夾的格式**：所有存檔改動都是增量（新鍵、舊檔可讀）；新的角色資料放在既有的 `ext` 與 `counters` 字典（§8.1），**不加**新的頂層鍵（護照簽章的正規化格式不變）。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=m3d]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500 [--case=law_hunter_tiers]
"$G" --headless --path . --script res://tests/ui/ui_playthrough.gd -- --no-steam            # 另跑一次有視窗（不加 --headless）
"$G" --headless --path . -- --no-steam --offline --world=w_m3d_m1 --profile=m1bot --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
"$G" --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3a_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3b_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3c_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3c2_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3d_acceptance.gd -- --no-steam [--only=bounty] [--timeout=2400]
"$G" --headless --path . --script res://tools/story_acceptance.gd -- --no-steam --all
"$G" --headless --path . --script res://tools/net_smoke.gd -- --no-steam
"$G" --headless --path . -- --no-steam --offline --world=close_x --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=wm --time-scale=50 --quit-after=300
"$G" --headless --path . -- --no-steam --offline --world=close_y --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=quit --time-scale=50 --quit-after=300
```

計時測試（`test_rate_limit`、`test_view_blade_hit_on_wolf`）在負載下會偶發失敗：先單獨重跑，單獨也失敗才算失敗。WASD 走路與自動走路修正（`test_ui_wasd_move`、`test_autowalk_view_first`）必須保持綠燈。

### 0.5 開工前量到的現況（協調者 2026-10-21，`balance_sim --runs=500`；log `K:\Project\JY-Mini-OL-Work\logs\m3d_plan_balance.log`）

（以下是讀程式碼量到的現況；`balance_sim` 的數字在 §0.6。）

| 項目 | 現況 | 出處 |
|---|---|---|
| PK值 | 角色 `pk`（基準）＋`pk_stamp_s`，`MoralityPk.pk_value` 惰性遞減：**每 1800 秒上線時間 −1**（標【已證實 newton】，研究更正為【後期版】）；強制 PK 擊殺時 +1；死於守城官兵**不會**降 PK值 | `core/rules/morality_pk.gd:6,47`、`character.gd:411` |
| 守城官兵 | 進出 CITY 時 `guard_count(pk, morality, newbie)`：PK > 3 → 2 名、善惡 < 0 → 1 名（新手例外受規則 `newbie_guard_spare`） | `server/pk_system.gd:170` |
| 懸賞 | 沒有系統。只有 `n_jc_bukuai`、`n_dl_bukuai` 對話提到懸賞；沒有佈告欄、沒有執照、沒有天師、沒有半仙 | `data/npcs.json` |
| 戰鬥指令 | `BATTLE_CMDS` = MOVE ATTACK ART DEFEND REST EQUIP FLEE＋M3a 七個；**沒有 閃、輕**。指令圓盤第一列已有「輕」字（不能用樣式「尚未開放」），**沒有「閃」** | `core/protocol.gd:417`、`ui/game/battle/command_bar.gd:2` |
| 逃跑 | 只能站在逃跑格（`not_on_escape`）；`opts.no_flee`（追擊戰、試煉）→ `no_flee` | `battle_rules.gd:126` |
| 換裝 | 沒有冷卻（地圖上 `equip`／`unequip`、戰鬥 EQUIP 都沒有） | `server/intents/intents_item.gd:50` |
| 合體技 | `gm_suxin` 列已有 `combo: true`、`party_size: 2`、旗標 `gm_suxin_unlocked` 鎖住；`ms_gm_xiaolongnu_suxin` cap 100、只要古墓。沒有默契系統 | `data/martial_arts.json`、`data/masters.json` |
| 夜晚 | `WorldClock` 有晝夜（戌～寅），畫面只在時鐘字樣加「（夜）」；沒有照明道具 | `server/world_clock.gd:7` |
| 武功鏈 | `qz_chongyang`（旗標 `qz_chongyang_jian`）、`qz_kongming`（旗標 `qz_kongming`）**沒有任何師父或任務能學**；`lj_bahuang` 由童姥直接教到 80（只看旗標 `lj_bahuang_learned`，沒有任務設這個旗標）；滅絕只教 1 級＋`self_study_cap` 90／80 已做；**沒有**四象掌、血魔刀法、血魔老祖；恐嚇只是一件雜務 `q_ch_xd_kongxia` | `martial_arts.json`、`masters.json`、`quests.json` |
| 全真／古墓 | 沒有「殺古墓弟子額外殺氣」，沒有殺古墓計數；`qz_r_pk` 等門規已有 | `data/sect_rules.json` |
| 比武 | 沒有遊戲內 PvP 比賽；PvP 種類只有 CHALLENGE／FORCED／SEIZE；沒有觀戰 | `server/battle_system.gd:12` |
| 鏢局 | 一般保鏢 6 條（`q_ec_biao_*`，酬勞 150 兩級，`escort_start` 跟隨 NPC）；托鏢不會被劫（M3b O16）；沒有劫鏢 | `data/quests.json`、`server/escort_system.gd` |
| 跑腿 | 有 `n_xx_zhugeyi`（豬哥義）、`m_xx_zhugeyi`（採花事件用）；沒有柯鎮惡、郭靖、三八紅；武林帖只有劉正風任務的 `i_hn_wulintie` | `npcs.json`、`items.json` |
| 城鎮學點任務 | `q_sm_esi_nongfu`（餓肚子的農夫，一次性、unverified）、`q_jc_xiaobao`（李大嬸，獎勵【設計提案】）、`q_ym_douji`（鬥酒，每日一次）已存在；沒有酒鬼、小虎／阿虎、送便當（可重複版） | `quests.json` |
| `chore` 欄位 | 只對 `group == "sect_chores"` 生效、必須有 `chore.sect`、學點受規則 `chore_xuedian` 與新手期控制、`decay_pct` 只縮放學點 | `server/quest_system.gd:1443`（M3c2 WP-PACE 區塊） |
| 黑龍潭 | 只有一間 `xe_heilong`（1.0A，西夏東郊）；沒有迷宮、瑛姑、九尾靈狐 | `data/maps/xixia_east.json` |
| 白猿 | `m_wd_baiyuan`（武當龍門七獸，善惡 0，M3c 決定不扣）、`m_em_mz_ape`；沙漠山洞房間已存在（`dlw_desertcave`、`de_cave`）但沒有白猿 | `monsters.json`、`maps/dali_wild.json`、`maps/desert_edge.json` |
| 陸大有 BUG | `n_ludayou` FIGHT `m_hs_trainee`；`SectSystem.spar_decide` 只看規則、每日上限、新手期，**不看是不是華山弟子** → 沒門派的人也拿得到切磋實戰與學點 | `server/sect_system.gd:1573` |
| 交易之道 | `basic_trade` 存在但沒有效果；`SELL_RATE` 0.3（`npc_system.gd:6`、`econ_calc.gd:13`） | — |
| 協定 | `Protocol.VERSION` 5；`GAME_VERSION` "0.1.0"（握手相容字串）；`project.godot` `config/version` 0.6.1.0 | `core/protocol.gd:10` |

`balance_sim --runs=500` 基準：見 §0.6。

### 0.6 `balance_sim` 基準（協調者 2026-10-21）

`balance_sim --runs=500`：**143 個案例全部 ok、0 FAIL**（M3d 審查更正：原寫 164；log 是 `BALANCE OK (143 cases …)`，整合後的 155 ＝ 143 ＋ 12 個 M3d 案例）（約 75 分鐘；log `K:\Project\JY-Mini-OL-Work\logs\m3d_plan_balance.log`；跑完已確認沒有殘留的 godot）。M3d 會用到的基準：

| 案例 | 基準值 | M3d 的用途 |
|---|---|---|
| `loot_econ_elite` | 實戰 2 萬打山賊頭目：每小時 42.5 場，銀兩 11,042 → 12,387 兩（含掉落） | 劫鏢收入帶（§5.2.4）、交易之道增幅上限（§6.6） |
| `loot_econ_boss` | 比例 1.200 | 交易之道（F） |
| `econ_hourly` | 同階段戰鬥收入：P1 159 兩／小時、P2 1,065、2 萬 12,387；所有鏈都在 0.5–0.9 倍帶內 | 交易之道（F）不得讓任何鏈超出帶 |
| `econ_loop` | 0 條（最低買價 95%） | F 之後仍必須 0 條 |
| `econ_chain`／`econ_no_loss` | 超出 0.3–1.5 倍的配方 0 條／成品不高於材料 0 條 | 照舊 |
| `chore_bot_cap` | 一個遊戲日雜務理論最大學點：少林 595（上限 600），其他派 36–494 | TOWN 任務另計（`er_town_lp_cap` ≤ 600） |
| `pace_<派>` | 中位數：少林 3.17、華山 3.31、武當 3.16、峨嵋 3.28、恆山 3.31、全真 3.24、古墓 3.49、靈鷲 3.36、星宿 3.34、血刀 3.55、丐幫 3.69 小時 | M3d 不得讓任何一派掉出 M3c2 的帶（TOWN 學點只給一點；E6 修 BUG 不影響本派弟子） |
| `xd_weihe_uplift` | 新／舊比 0.71–0.74 | R13：不動 |
| `p1_sect_xuedao` | 8.1 行動、剩氣 72.6% | 不動 |
| `ref_p0_vs_hs_trainee` | P0 打陸大有的華山弟子勝率 56% | E6 修 BUG 後切磋本身不變 |

---

## 1. 範圍

### 1.1 M3d 要做（逐項打勾；括號是負責 WP；每項附驗收準則）

**A. 懸賞與律法（WP-LAW）**
- [ ] A1 **佈告欄與懸賞名單**：西夏、大理（1.0A）、京城（1.0B）廣場各一個佈告欄（NPC `n_law_board_<城>`，服務 `BOARD`），選單「觀看懸賞名單」→ 名單視窗（名字、門派、PK值、善惡、懸賞金額、上榜時間）。名單**每遊戲時辰統計一次**（§2.2）。**驗收**：`test_m3d_bounty.gd`（誰上榜、門檻、新手不上榜、統計時間）；`test_ui_m3d_board.gd`。
- [ ] A2 **賞金獵人執照**：每城兩位官爺（`n_law_guanye_<城>_a` 發執照、`n_law_guanye_<城>_b` 耳聾，永遠聽錯，留著這個笑話），服務 `LICENSE`。只有 PK值 0、不在名單上的人能領；之後 PK值 > 0 自動失效（§2.3）。**驗收**：`test_m3d_license.gd`。
- [ ] A3 **合法緝拿**：持照的人對**名單上**的人強制 PK＝合法：不加 PK值、不扣善惡、殺氣只加 `LAWFUL_KILLING_INTENT`、不廣播 `pk_kill`（改發傳聞）；沒執照照舊是惡意 PK（研究：開服前規格）。擊殺後懸賞記到獵人名下，回官爺那裡「領賞」（`bounty_claim`）。**驗收**：`test_m3d_bounty.gd`（合法／非法兩路、領賞、重複領）。
- [ ] A4 **懸賞金與賞金池**：懸賞金＝罰金（依 PK值／善惡，§2.4）＋玩家加碼的賞金池（`bounty_add`，只能加給已在名單上的人）；罰金**從被懸賞者自己的錢扣**（身上 → 錢莊，扣不到就沒有）；**系統不憑空生錢**。**驗收**：`balance_sim law_bounty_zero_sum`：兩個朋友互殺、互加碼 1000 次，兩人合計銀兩不增加。
- [ ] A5 **NPC 賞金獵人追捕**：名單上的人在野外（WILD 地區）每進一間房擲一次，被三種強度的賞金獵人之一追上（依自己的實戰分級，§2.5），先警告、倒數後開「追擊戰」（不能逃，`烙跑鞋` 例外）。被獵人或守城官兵殺死 PK值 −1【已證實：守衛／特定 NPC】。**驗收**：`test_m3d_hunters.gd`；`balance_sim law_hunter_tiers`。
- [ ] A6 **天師消殺氣**（1.0A）：西夏東門外、大理北門外各一位（`n_law_tianshi_xx`、`n_law_tianshi_dl`），服務 `CLEANSE`：每 10 點殺氣 100 兩【已證實】。**驗收**：`test_m3d_cleanse.gd`。
- [ ] A7 **京城半仙消 PK值**（1.0B）：`n_law_banxian_jc`，服務 `CLEANSE`：每點 `BANXIAN_PRICE_PER_PK` 兩、每遊戲日最多 1 點【設計提案】。**驗收**：`test_m3d_cleanse.gd`。
- [ ] A8 **PK值 遞減規則**：新規則 `pk_decay`（`classic_strict` 關＝2001 沒有被動遞減；其他組合保留 30 分鐘遞減）。**驗收**：`test_m3d_pk_decay.gd`。
- [ ] A9 守城官兵殺死玩家 PK值 −1（同 A5）；劫鏢標記期間守城官兵照 PK > 3 的人數追殺（§5.2.5；讀 WP-EVENTS 的 `JiebiaoRules.rob_marked`）。

**B. 戰鬥增補（WP-COMBAT）**
- [ ] B1 **「閃」（2001）**：戰鬥指令 `DODGE`；到自己下次行動前，被打中的機率降低（§3.1）；規則 `dodge_cmd`。圓盤加「閃」。**驗收**：`test_m3d_dodge.gd`；`balance_sim combat_dodge`。
- [ ] B2 **「輕」（2002，跟著 `later_battle_cmds`）**：戰鬥指令 `QING`，`mode` = `JUMP`（越過敵人、移動範圍 +1、耗內力）或 `ESCAPE`（原地逃離、有機率、耗內力）（§3.2）。圓盤的「輕」改成可用。**驗收**：`test_m3d_qing.gd`；`balance_sim combat_qing_escape`。
- [ ] B3 **合體技系統（1.0B）**：【建立默契】／【取消默契】／【培養感情】、默契值、配合度、每兩遊戲日雙方同時在線時扣配合度（§3.3）；戰鬥中兩人在 3 秒（戰鬥時間）內都出同一組合體武功 → 依默契擲骰 → 合體一擊。**驗收**：`test_m3d_combo.gd`；`balance_sim combo_suxin`。
- [ ] B4 **玉女素心劍法**：官方條件（男學過全真劍法、女學過玉女劍法、組隊、默契與心性達一定程度才能修練；小龍女教）；`gm_suxin` 解鎖（拿掉 `gm_suxin_unlocked`）。**驗收**：`test_m3d_combo.gd`（男全真＋女古墓學得到；同性、沒組隊、默契不夠學不到）。
- [ ] B5 **無敵烙跑鞋**（1.0B）：鞋欄；戰鬥中任何格子都能 100% 逃，連追擊戰、被 PK 都可以；**任務戰（QUEST）、試煉（TRIAL）、劫鏢方（ROB 的 side 0）不行**（§3.4）。**驗收**：`test_m3d_flee_shoes.gd`。
- [ ] B6 **夜明珠**（1.0B）：背包有夜明珠時，夜裡畫面不變暗、小地圖不起霧（§3.5）。**驗收**：`test_ui_m3d_night.gd`。
- [ ] B7 **裝備兩秒間隔**（2001-10-09）：**全域**：地圖上 `equip`／`unequip` 與戰鬥 EQUIP 都要距上一次換裝 ≥ 2 秒（選項 `equip_cooldown_ms`，預設 2000；戰鬥用戰鬥時間）。**驗收**：`test_m3d_equip_cd.gd`。
- [ ] B8（選做）沖靈劍法、反兩儀刀法做成合體技資料列（`src: "proposal"`，§3.3.6）。

**C. 門派武功鏈（WP-ARTS）**
- [ ] C1 **全真 重陽劍法鏈**（1.0B／【後期版 2002 條件】）：山居隱士 → 自修 → 狀元紅與推薦信 → 漱流隱士 → 雲遊道士（拂塵）（§4.1）。**驗收**：`test_m3d_chongyang.gd`＋任務 `test_plan`。
- [ ] C2 **全真 空明拳**（1.0B，【後期版】）：王志謹給 1 級、自修到 40、王志謹教到 70（§4.2）。**驗收**：`test_m3d_kongming.gd`。
- [ ] C3 **靈鷲 八荒六合唯我獨尊功鏈**（1.0B，【後期版】）：服侍童姥 → 無涯子 → 虛竹 → 童姥給 1 級 → 自修 40 → 蘭劍教到 70（§4.3）。**驗收**：`test_m3d_bahuang.gd`。
- [ ] C4 **星宿 煉毒**（1.0A）：小木鼎（出塵子「邪惡的練毒」）＋指令「煉毒」→ 基本毒術熟練度，依「特定狀況」加倍（§4.4）。**驗收**：`test_m3d_liandu.gd`。
- [ ] C5 **峨嵋 滅絕只教 1 級、其餘自修**：確認並用測試鎖住（已做）；1.0B 峨嵋信差的鐵指環路線（選做，§4.5）。**驗收**：`test_m3d_emei_selfstudy.gd`。
- [ ] C6 **峨嵋 四象掌**（1.0B）：羅煞劍任務（雁門關守衛、蠻兵、拒收 50000 兩、推薦信、終南山破廟郭襄）（§4.6）。**驗收**：`test_m3d_sixiang.gd`＋任務 `test_plan`。
- [ ] C7 **血刀 恐嚇指令與血池**：對 NPC 下「恐嚇」練威嚇（1.0A）；血池比武初／中／高（【後期版 2003】）（§4.7）。**驗收**：`test_m3d_intimidate.gd`、`test_m3d_xuechi.gd`。
- [ ] C8 **血魔刀法**（1.0B）：新武功＋血魔老祖＋五個線人＋在血刀門口悟刀訣（§4.8）。**驗收**：`test_m3d_xuemo.gd`＋任務 `test_plan`。
- [ ] C9 **全真殺古墓弟子**：殺氣加倍（1.0A）；殺古墓弟子計數 > 10 → 門規坐牢（`qz_r_kill_gumu`，1.0B）（§4.9）。**驗收**：`test_m3d_qz_gumu.gd`。

**D. 事件（WP-EVENTS）**
- [ ] D1 **劫鏢（1.0B，2001-11-15）**：危險鏢（護送鏢、送貨鏢）、押金＝鏢價、成功領回兩倍、失敗沒收；路上「特殊地雷」；押鏢中頭上標「押鏢」；不接鏢冷卻 30/60/120 分（§5.2）。**驗收**：`test_m3d_jiebiao.gd`。
- [ ] D2 **劫鏢方**：`rob_escort` 開 PvP 種類 `ROB`；劫鏢標記 1 小時（守城官兵追殺）；成功分鏢價 80%；劫鏢方不能逃（§5.2.4）。**驗收**：`test_m3d_rob.gd`；`balance_sim ev_jb_zero_sum`（押鏢與劫鏢是朋友時，合計銀兩只減不增）。
- [ ] D3 **比武系統（【後期版 2002・設計提案】）**：武林大會（全服）與門派比武（各派），依遊戲日曆排程或主機開辦；報名、單淘汰對戰表、**切磋模式**的 1v1（種類 `DUEL`，沒有死亡懲罰）、10 分鐘判定、名次與稱號、觀戰者與全服收到江湖傳聞（§5.3）。**驗收**：`test_m3d_tourney_bracket.gd`、`test_m3d_duel.gd`、`test_m3d_tourney_schedule.gd`、`test_ui_m3d_tourney.gd`。
- [ ] D4 防刷：獎勵只給報名 ≥ 4 人的場次，且同一種比賽每 30 遊戲日只發一次獎勵（主機在冷卻內開的是不發獎的表演賽）（§5.3.6）。

**E. 跑腿與區域（WP-ERRANDS）**
- [ ] E1 **`chore` 欄位通用化**：`chore.kind` = `SECT`（現行，預設）或 `TOWN`（任何人、學點不受新手期與 `chore_xuedian` 限制、仍有每日遞減）；`chore.decay_all` 讓遞減也套用到銀兩、名聲、歷練、實戰（§6.1）。**驗收**：`test_m3d_chore_town.gd`；M3c2 的 `test_m3c2_chores.gd` 照過。
- [ ] E2 **丐幫跑腿**：柯鎮惡 → 郭靖（1.0B，名聲與歷練 ≥ 500【待考證】，名聲 +5 歷練 +20，每日遞減）；豬哥義 → 三八紅（1.0A，200 兩＋寬衣 → 名聲 +8，每日遞減）；武林帖（1.0B，買帖挑戰、每 3 遊戲日一次）；英雄帖不做（2004）（§6.2）。**驗收**：`test_m3d_errands.gd`＋任務 `test_plan`。
- [ ] E3 **城鎮學點任務**：送便當（西夏、大理各一，午時，學點 50 遞減）、大理酒鬼燒刀子酒（學點 5、拒絕被偷 40 兩）、阿虎與青青（學點 50＋300 兩，一次）、李大嬸（官方獎勵）、鬥酒（學點 40）（§6.3）。**驗收**：`test_m3d_chore_town.gd`＋任務 `test_plan`；`balance_sim er_town_lp_cap`。
- [ ] E4 **黑龍潭（1.0B 小區域）**：五行八卦陣迷宮、瑛姑小屋、九尾靈狐（抓到有「意外收獲」）、南坡羊群（扣善惡）、白猿（§6.4）。**驗收**：`test_m3d_heilongtan.gd`＋`story_acceptance` 的任務 `test_plan`。
- [ ] E5 **白猿扣善惡**：沙漠山洞（`dlw_desertcave`）與黑龍潭南坡的白猿 `m_er_baiyuan` 善惡 −5／隻【設計提案；扣善惡【已證實】、量【待考證】】；武當七獸 `m_wd_baiyuan` 照 M3c 不扣。
- [ ] E6 **BUG：陸大有切磋獎勵**：切磋弟子的實戰與學點只給**該派弟子**（`spar_decide` 多一個 `why: "not_disciple"`）；華山入門考驗（`q_hs_kaoyan`）照樣能完成（任務進度不受影響）（§6.5）。**驗收**：`test_m3d_spar_bug.gd`。
- [ ] F（選做，便宜才做）**交易之道影響收購價**：賣價 × (1 + 交易之道/300)（§6.6）；**只有** `balance_sim` 的 `econ_loop` 0 條、`loot_econ_*` 與 `econ_hourly` 都在帶內才能開。**驗收**：`test_m3d_trade.gd`；`balance_sim er_trade_band`。

### 1.2 M3d 不做

- **M5 以後**：木人巷、婚姻（合體技的夫妻加成照研究存在，但沒有婚姻 → 不做）、明教／桃花島、傭兵（日期與賣家有衝突，見研究）、總壇裝備、神兵的正式來源（武林大會**不發神兵**，§5.3.5）、門寶項鍊、替身娃娃（本作沒有死亡保護道具系統）、天下第一幫（2020 年代的實作）。
- **後期版（不做）**：周伯通左右互搏與單人素心劍（2002-04 以後）、血魔 50→70 紗紗鏈（只在現代私服）、掌經道長 65→80（懷舊 2024）、偷空明拳、英雄帖（2004 奇緣 NPC）、武師阿虎（晚期官方）、萬年寺靜象（不在本作地圖）、PK 分級懲罰表（開服前規格，沒證據上線）、玩家自己對任何人出懸賞（研究解讀更正：只有衙門懸賞惡人；本作只准**加碼**給已上榜的人，§2.4）。
- **觀戰（看別人的戰鬥畫面）**：2001-08-30 有，但要新的戰鬥快照轉送路徑；本包的觀戰只到「擂臺房間收到每一招的文字與結果、全服收到傳聞」（§5.3.4）。真正的觀戰畫面 M5 再做。
- 十大排名（惡人、善人、首富……）：佈告欄本包只有「觀看懸賞名單」；選單上其他排名顯示「尚未開放」【待做】。

### 1.3 擁有者決定（擁有者已預先授權本里程碑；以下是選定的預設值，建造者照做）

| # | 決定 | 理由（研究） | 本文落點 |
|---|---|---|---|
| R1 | **上名單**：PK值 ≥ 4（和守城官兵追殺同一個門檻），或 PK值 ≥ 1 且善惡 ≤ −101（惡）；新手不上；名單每遊戲時辰統計一次（不是即時） | 研究：「PK值高」被追殺、「只有惡性不良的人才能被懸賞」、「最慢一天、可能 30 秒統計一次」；門檻數字【設計提案】 | §2.2 |
| R2 | **懸賞金從被懸賞者自己的錢扣**（罰金 1000 兩 × PK值、惡人 +500、上限 2 萬），加上玩家加碼的賞金池；系統不出錢 → 朋友互殺不會生錢 | 研究：金額與誰出錢都沒有記載；擁有者要求「不能刷」 | §2.4 |
| R3 | 執照：PK值 0 才能領、100 兩、PK值 > 0 自動失效；持照緝拿不加 PK值、不扣善惡、殺氣 +20 | 研究：「執照限定只有無pk值的玩家」、「除非領有執照，否則判定為惡意PK」（開服前規格）；費用與殺氣【設計提案】 | §2.3 |
| R4 | 被持照玩家緝殺也 PK值 −1；同一獵人對同一目標每遊戲日只領一次；同隊或同組織的人互殺不給懸賞 | 研究：「被獎金獵人殺死來減低」（量是推論）；防刷【設計提案】 | §2.4 |
| R5 | NPC 賞金獵人由 WP-LAW 自己的系統在野外觸發（不是固定區域遊蕩），三種強度依目標實戰分級 | 研究：「到哪裡都會被許多的賞金獵人追殺」、強度「遙不可及」；名字與數值【設計提案】 | §2.5 |
| R6 | **PK值 遞減**：`classic_strict` 關（2001 沒有被動遞減），其他組合保留 30 分鐘（【後期版】，給朋友同樂） | 研究：30 分鐘只見於後期摘要 | §2.6 |
| R7 | 天師：西夏東門外、大理北門外；所有門派都能用（研究只說其他派「必須」去，沒說少林等派不能用）；半仙：京城，每點 10,000 兩、每遊戲日 1 點 | 研究：100 兩／10 點【已證實】；半仙價錢沒有記載 | §2.7 |
| R8 | 「閃」做成 2001 的指令（規則 `dodge_cmd`：`later_official` 關，其他開），「輕」跟著 `later_battle_cmds`（2002） | 研究：閃 2002-01-25 拿掉、輕同日加入；擁有者兩個都要 | §3.1、§3.2 |
| R9 | 裝備兩秒是**全域**冷卻（地圖上也算），不是只有戰鬥中 | 研究：n323 原文沒有限定戰鬥 | §3.6 |
| R10 | 玉女素心劍法：**修練**照官方（組隊、默契、心性）；**使用**只要同一場戰鬥、同一邊、3 秒內（【設計提案：放寬，官方沒說使用要不要組隊】）；合體一擊的加成【設計提案】 | 研究：官方只寫修練要組隊 | §3.3 |
| R11 | 烙跑鞋與夜明珠：京城「西域貨郎」賣（烙跑鞋 50,000 兩、夜明珠 20,000 兩）＋九尾靈狐的意外收獲有小機率給夜明珠【設計提案】 | 研究：來源與價錢沒有記載；2001 擂台賽獎品有夜明珠 | §3.4、§3.5、§6.4 |
| R12 | 武功鏈用**最早**有步驟的版本（2002）；2002 的「實戰 500 萬」這類數字照本作的實戰尺度改寫成 10 萬（武功 100 級的實戰門檻）【設計提案】；位置不在本作地圖的（百花谷、南帝隱所、大理鎮、萬年寺）放到最近的現有房間並在 `src_note` 註明 | 研究；本作武功上限公式 5+⌊√(實戰/10)⌋ | §4 |
| R13 | 血刀威嚇的戰鬥效果**維持 M3c2 的「重擊」**（擁有者 0.6.1.0 已批准削弱過的版本），不改成「削弱敵人攻擊」；`src_note` 註明兩種說法 | 研究：官方 1.0 頁寫削弱敵攻、2012 官方表與 2002 玩家寫重擊 | §4.7 |
| R14 | 門派比武與武林大會是 2002 的系統 → 做成【後期版・設計提案】的主機活動，**不發神兵**（神兵仍是 M5 的正式來源），名聲照 2002 官方數字、稱號照晚期官方表 | 研究：2002-04（武林大會）、2002-09（門派比武） | §5.3 |
| R15 | 劫鏢照設計文（押金全額、成功 2 倍、劫鏢 80%、1 小時標記、劫鏢方不能逃）；**劫鏢也算強制 PK**（PK值 +1）【設計提案：設計文沒寫懲罰，但動手的方式就是強制 PK】；門檻用 ≥ 100,000（「以下」的解讀【待考證】） | 研究 | §5.2 |
| R16 | 柯鎮惡 → 郭靖：門檻名聲與歷練 ≥ 500【待考證】；原作可以「5 小時歷練破萬」，本作用每日遞減擋掉無限刷 | 研究；擁有者「不能無限刷」 | §6.2.1 |
| R17 | 城鎮學點任務的學點是原作獎勵（不是新手加速）→ `chore.kind: "TOWN"`：不受新手期與 `chore_xuedian` 限制，但每日遞減 | 研究：酒鬼「無限次」、便當「一次50點後來就越來越少」 | §6.1 |
| R18 | 英雄帖、武師阿虎不做（2004／晚期）；「阿虎」做成 2001 的阿虎與青青（＝晚期的小虎） | 研究 | §6.3 |
| R19 | 黑龍潭迷宮、九尾靈狐抓法、瑛姑的委託全部【設計提案】（只有預告） | 研究：DIAO/2-3 只有預告 | §6.4 |
| R20 | 交易之道（選做）：賣價 × (1 + 等級/300)，100 級時 ×1.333（對應 2001 的 0.75→1.0）；只有 `balance_sim` 證明在帶內才開 | 研究：只影響賣價；公式沒有記載 | §6.6 |

### 1.4 與 GDD／既有文件的偏差（M3d 決議；整合者同步）

| # | 偏差 | 理由 |
|---|---|---|
| U1 | M2 `MoralityPk` 的「PK值 每 30 分鐘 −1【已證實 newton】」→ 標【後期版】，並由規則 `pk_decay` 控制 | R6、研究 |
| U2 | M3c 「白猿扣善惡延後」→ 沙漠山洞與黑龍潭的 `m_er_baiyuan` 扣善惡；`m_wd_baiyuan` 照舊 | E5 |
| U3 | M3C_PLAN §1.2「武林大會＝M5（神兵的正式來源）」→ 武林大會本包做，但不發神兵 | R14 |
| U4 | verified_research 第 1000 行「休回氣與內力」→ 1.0A 快報只補氣【待考證】（本包不改「休」的程式，只改文件） | 研究 |
| U5 | verified_research 第 1214 行「血魔老祖沒有出處」→ 官方血刀頁有「血魔老祖─血魔刀法」 | 研究 |
| U6 | M3c2 `chore` 欄位只給門派雜務 → 加 `kind: "TOWN"`、`decay_all` | E1 |

---

## 2. A：懸賞與律法（WP-LAW）

### 2.1 檔案與類別

- `core/rules/bounty_rules.gd`（`class_name BountyRules`，純靜態，`balance_sim` 與單元測試直接用）。
- `server/law_system.gd`（`class_name LawSystem`，`GameHost.law`；用 `_init(p_host)`，不加型別，讓測試能傳假主機）。
- `server/intents/intents_law.gd`（不設 class_name；GameHost 依 `M3D_INTENTS` 以路徑 load）。
- `ui/game/law/bounty_dialog.gd`（佈告欄名單＋領賞＋加碼）、`ui/game/law/cleanse_dialog.gd`（天師、半仙）。

```gdscript
class_name BountyRules
const LIST_PK_MIN := 4                 # PK值 ≥ 4（＝ guard 門檻 > 3）
const LIST_EVIL_PK_MIN := 1            # 或 PK值 ≥ 1 且善惡 ≤ LIST_EVIL_MORALITY
const LIST_EVIL_MORALITY := -101
const FINE_PER_PK := 1000
const FINE_EVIL_BONUS := 500
const FINE_CAP := 20000
const POOL_ADD_MIN := 100
const POOL_CAP := 100000               # 每個目標的加碼上限
const LICENSE_FEE := 100
const LAWFUL_KILLING_INTENT := 20
const TIANSHI_PRICE_PER_10 := 100      # 【已證實】
const BANXIAN_PRICE_PER_PK := 10000
const BANXIAN_PER_DAY := 1
const HUNTER_CHANCE_PCT := 8           # 名單上的人每進一間野外房間的機率
const HUNTER_COOLDOWN_SHICHEN := 1     # 遇過一次（不論逃掉或開打）之後的冷卻
const HUNTER_TIER_XP := [20000, 100000]  # < 2 萬 → 1；< 10 萬 → 2；其他 → 3
static func listed(pk: int, morality: int, combat_xp: int, protect_xp: int) -> bool
static func fine(pk: int, morality: int) -> int
static func collect(fine: int, money: int, bank: int) -> Dictionary   # { from_money, from_bank, total }
static func license_reason(pk: int, is_listed: bool, money: int) -> String   # "" | "license_pk" | "license_listed" | "not_enough_money"
static func lawful(has_license: bool, hunter_pk: int, target_listed: bool) -> bool
static func hunter_tier(combat_xp: int) -> int        # 1..3
static func tianshi(killing_intent: int, times: int, money: int) -> Dictionary   # { times, cost, drop }（times 截到付得起與殺氣夠扣的次數）
static func banxian(pk: int, money: int, used_today: int) -> Dictionary          # { ok, reason, cost }
```

### 2.2 名單（R1）

- `LawSystem.refresh_board()`：每遊戲時辰（`day_s / 12` 世界秒）一次，主機啟動時一次。掃**所有角色**（線上用 session，離線用 `CharacterStore` 讀摘要；離線角色也會在名單上），`BountyRules.listed(pk_value, morality, combat_xp, newbie_pk_protect_xp)` 成立 → 寫入 `world.bounty.board`（§8.1）。
- **緝拿與 NPC 獵人都看 `board`**（不是即時 PK值）；剛被 PK 的人要等下一次統計才上榜（照研究「不是即時」）。被緝殺、被獵人殺、找半仙降到門檻以下的人，下一次統計才下榜。
- 選項 `bounty_enabled`（預設 true）關 → 不統計、佈告欄只顯示「衙門暫停懸賞」、獵人不出現、執照照發但沒有用處。

### 2.3 執照與合法緝拿（R3）

- `bounty_license { npc }`：NPC 必須有服務 `LICENSE`；耳聾官爺（列欄位 `"deaf": true`）一律回 `license_deaf`（模板輪流講三句聽錯的話，例：「啥？你要領『賞錢』？那得先去殺人哪！」【設計提案】），**不收錢**。
- 領到 → `ext.law.license = true`、`license_s`；扣 `LICENSE_FEE`。
- 失效：每次用到執照（`force_pk`、`bounty_claim`）時檢查 PK值 > 0 → 清掉、送 `law_license_void`。
- **合法緝拿**（`server/pk_system.gd` 的 WP-LAW 區塊）：`force_pk` 照舊的檢查（PK 開關、地點、新手保護、同隊、忙碌）都要過；開戰前 `law.lawful_hunt(s, target_char) -> bool`；成立 → `start_pvp(..., "FORCED", { "lawful": true })`。`on_pvp_end` 看到 `opts.lawful`：擊殺者 PK值 +0、善惡 0、殺氣 +`LAWFUL_KILLING_INTENT`、不廣播 `pk_kill`、改發傳聞 `rmr_law_caught`（`{hunter}在{room}緝拿了懸賞犯{target}`）；被殺者照一般死亡、PK值 −1、懸賞進入領賞（§2.4）。
- 被殺者反殺獵人：照現行「被強制 PK 的人反殺是自衛」（M2 第三輪審查）。

### 2.4 懸賞金、加碼、領賞（R2、R4）

- 罰金：`fine(pk, morality) = min(FINE_CAP, FINE_PER_PK × pk + (FINE_EVIL_BONUS if morality ≤ LIST_EVIL_MORALITY else 0))`。
- 加碼：`bounty_add { npc, target_name, money }`（在官爺 `LICENSE` 或佈告欄 `BOARD` NPC 處）：目標必須在 `board` 上；`money ≥ POOL_ADD_MIN`；`pool + money ≤ POOL_CAP`；錢從加碼者身上扣、存進 `world.bounty.pools[target].added`，記 `contributors[char_id] += money`。目標下榜時加碼**留著**（下次上榜照舊）；加碼者不能取回。
- 緝殺成立（合法緝拿擊殺、目標在 `board` 上）：
  1. 防刷檢查：獵人與目標同隊（`party.player_tags`）或同組織（`org`）→ 不給、送 `law_no_bounty_friend`；`paid_log["<獵人>|<目標>"] == 今天` → 不給、送 `law_no_bounty_daily`。
  2. `collect(fine, 目標身上銀兩, 目標錢莊)`：從目標扣（離線角色照樣扣，存檔）。
  3. 賞金 = `collected.total + pools[target].added`（加碼池清零）。
  4. 寫入 `world.bounty.claims[獵人] += [{ target_name, amount, s }]`；送 `law_bounty_earned`（本人：「此人懸賞 {amount} 兩，回衙門找官爺領賞」）。
- `bounty_claim { npc }`：在發照官爺處把 `claims` 全部領走（`money_cap` 照舊；超過的留著）。
- **為什麼刷不出錢**：罰金是目標自己的錢、加碼是加碼者自己的錢；系統只搬錢，不生錢（`balance_sim law_bounty_zero_sum` 驗證）。

### 2.5 NPC 賞金獵人（R5）

- 鉤子：`LawSystem.on_enter_room(s, from, to)`（`GameHost.m3d_enter_room` 分派，§9.2）。條件：`bounty_enabled` 與 `bounty_hunters` 都開、角色在 `board` 上、房間的地區 `type == "WILD"`、不是安全房間、不在戰鬥中、不在牢裡、`ext.law.hunt_cd_s` 已過 → 擲 `HUNTER_CHANCE_PCT`。
- 成立：送 `law_hunter_warn`（本人，倒數 `villain_warn_s` 真實秒；**只是警告，沒有回覆按鈕**——不能用 `villain_prompt`／`villain_reply`，那條路徑屬於凍結的 `wander_system.gd`；介面由 `main_screen.gd` 的 `_m3d_law_event` 顯示倒數橫幅）→ 倒數內離開房間 = 逃掉；倒數結束 → `host.battles.start_ex(s, [m_law_hunter_<tier>], "CHASE", { "no_flee": true, "pull_party": true, "pull_min_xp": newbie_pk_protect_xp, "law_hunter": true })`。不論結果都設 `hunt_cd_s = now + HUNTER_COOLDOWN_SHICHEN × 時辰長`。
- 怪物列（`data/monsters.json`，WP-LAW，數值【設計提案】，`balance_sim law_hunter_tiers` 校準）：

| id | 名稱 | 階 | 目標實戰 | 氣（初值） | 閃躲／招架 | 招式 | 校準目標（目標方勝率） |
|---|---|---|---|---|---|---|---|
| `m_law_hunter_1` | 賞金獵人 | 1 | < 2 萬 | 1800 | 60 | 刀法 | 參考角色 P1（實戰 2 萬）40–70% |
| `m_law_hunter_2` | 捕頭 | 2 | < 10 萬 | 3500 | 90 | 刀法＋鐵尺 | P2 30–60% |
| `m_law_hunter_3` | 神捕 | 3 | ≥ 10 萬 | 8000 | 140 | 鏈子槍 | 實戰 20 萬的參考角色 25–55% |

  三列都 `no_rewards: true`（打贏獵人沒有實戰學點，避免把被懸賞變成練功）。
- 結算：`LawSystem.on_battle_settled(s, ch, summary)`：`summary.kind == "CHASE"` 且 `opts.law_hunter`，玩家死亡 → PK值 −1（`ch.add_pk(-1)`，最低 0）＋傳聞 `rmr_law_hunted`；玩家贏 → 送 `law_hunter_beaten`。
- **守城官兵**：`PkSystem` 的守衛戰（kind `GUARD`）玩家死亡 → PK值 −1【已證實 xinshou/21】（同一個結算函式，WP-LAW 區塊）。
- 烙跑鞋（WP-COMBAT）可以逃追擊戰（§3.4）；新手（實戰 < `newbie_pk_protect_xp`）不會上榜，所以不會被追。

### 2.6 PK值 遞減（R6）

- `MoralityPk.pk_value(pk_base, pk_stamp_s, online_s, decay := true)`：`decay == false` → 回 `pk_base`。
- `Character.pk_value()` 與 `add_pk(n)`（WP-LAW 區塊）讀主機規則：`Character` 不能引用主機 → 新增 `Character.pk_decay_on: bool = true`（**不存檔**的執行期欄位），由 `GameHost` 在角色載入與規則變更時設定（WP-LAW 的 `game_host.gd` 區塊）。`balance_sim` 與測試直接設。
- `add_pk(n)` 允許負數（緝殺、獵人、守衛、半仙），結果最低 0。

### 2.7 天師與半仙（R7）

- `cleanse { npc, what: "KILLING"|"PK", times: int }`：
  - `KILLING`：NPC 必須是 `n_law_tianshi_*`（服務 `CLEANSE`、列欄位 `"cleanse": "KILLING"`）；`times` 1–100；`BountyRules.tianshi` 截到付得起與殺氣夠扣的次數；每次 −10 殺氣、−100 兩；結果送 `law_cleansed_killing`。殺氣 0 → `cleanse_nothing`。
  - `PK`：NPC 必須是 `n_law_banxian_jc`（`"cleanse": "PK"`，1.0B）；每遊戲日 `BANXIAN_PER_DAY` 點（`counters.banxian_day`）；每點 `BANXIAN_PRICE_PER_PK`；`times` 忽略（一次一點）。PK值 0 → `cleanse_nothing`；今天已用 → `cleanse_daily`。
- 介面：`cleanse_dialog.gd`：天師顯示目前殺氣、可以消幾次、要多少錢（數量選擇用既有 `numbered_dialog.gd`）；半仙顯示 PK值 與價錢、確認框。

### 2.8 NPC 與位置（WP-LAW；全部用既有房間）

| id | 名稱 | 房間 | era | 服務 | 備註 |
|---|---|---|---|---|---|
| `n_law_board_xx` | 佈告欄 | `xx_square` | 1.0A | BOARD | 物件 NPC（`kind: "FUNC"`，畫面用佈告欄圖） |
| `n_law_board_dl` | 佈告欄 | `dl_square` | 1.0A | BOARD | |
| `n_law_board_jc` | 佈告欄 | `jc_square` | 1.0B | BOARD | |
| `n_law_guanye_xx_a`／`_b` | 官爺 | `xx_square` | 1.0A | LICENSE | `_b` 是耳聾（`"deaf": true`） |
| `n_law_guanye_dl_a`／`_b` | 官爺 | `dl_square` | 1.0A | LICENSE | 同上 |
| `n_law_guanye_jc_a`／`_b` | 官爺 | `jc_square` | 1.0B | LICENSE | 同上 |
| `n_law_tianshi_xx` | 天師 | `xw_road`（西夏東門外官道） | 1.0A | CLEANSE | `"cleanse": "KILLING"` |
| `n_law_tianshi_dl` | 天師 | 大理北門外的第一間野外房間（WP-LAW 查 `dl_gate_n` 的出口） | 1.0A | CLEANSE | 同上 |
| `n_law_banxian_jc` | 京城半仙 | `jc_square` | 1.0B | CLEANSE | `"cleanse": "PK"` |

---

## 3. B：戰鬥增補（WP-COMBAT）

### 3.1 閃（`DODGE`，R8）

- `Protocol.BATTLE_CMDS` 加 `"DODGE"`、`"QING"`（WP-LAW Day-0 寫進 `protocol.gd`；`battle_rules.CMDS` 由 WP-COMBAT 同步）。
- 可用條件：`b.opts.dodge_cmd == true`（`BattleSystem.battle_opts` 由規則 `dodge_cmd` 帶入，§9.2）。關閉 → `cmd_disabled`。
- 效果：`u.dodging = true`（到自己下次行動前；`execute` 開頭跟 `defending` 一起清掉）；`resolve_strike` 擲命中前：守方 `dodging` → `hit_p = max(0, hit_p − DODGE_HIT_DROP(def))`，`DODGE_HIT_DROP = min(0.30, 0.15 + basic_dodge/1000)`【設計提案；快報只說「可減低中招機率」】；`dodging` 的人**不反擊**；行動後時間棒歸 0（跟防一樣，只花一回合）。
- 事件 `battle_dodge`（`who`）；被閃掉的攻擊照舊 `battle_miss`，另帶 `dodged: true`（純表現）。
- 圓盤：第一列在「防」後面加「閃」（`UiKeys.CMD_DISC_ROWS`），快捷鍵 Shift+4；`dodge_cmd` 關時用「不能用」樣式，提示「原作 2002 年拿掉了（伺服器規則關閉）」。

### 3.2 輕（`QING`，R8）

- 可用條件：`b.opts.later_battle_cmds == true`（同「內」「穴」）；`battle_cmd` 新參數 `mode`：`"JUMP"`／`"ESCAPE"`（`Protocol.QING_MODES`）。
- `JUMP`：目標格在 `move_range(u) + 1` 的曼哈頓距離內、是空格；**路徑可以越過有人的格子**（`BattleGrid.jump_targets(u)`）；耗內力 `10 + 2 × move_range(u)`；之後時間棒 = `MOVE_GAUGE`（跟移動一樣）。不夠內力 → `not_enough_neili`。
- `ESCAPE`：任何格子；耗內力 30；成功率 `clamp(20 + lightness × 0.4 + basic_body × 0.2, 20, 80)%`；成功 → 跟 FLEE 一樣離場；失敗 → 事件 `battle_qing_fail`、時間棒歸 0。不能用的戰鬥：`opts.no_flee`（任務戰、試煉、追擊戰）與烙跑鞋例外清單相同（§3.4：任務戰、試煉不行；**追擊戰可以**，研究「功能和使用與烙跑鞋一樣」）；`DUEL` 逃＝棄權（§5.3）；`ROB` 的 side 0 不行。
- 事件：`battle_qing_jump`（from、to）、`battle_qing_escape`、`battle_qing_fail`。
- 數字全部【設計提案】（研究：內力與機率沒公布）。

### 3.3 合體技（1.0B，R10）

#### 3.3.1 資料

- 武功列新欄位 `combo`（取代原本的 `combo: true`）：

```jsonc
"combo": { "group": "suxin",                          // 合體組：同組的兩招在 3 秒內出現才觸發
           "pair": [ { "gender": "M", "art": "qz_jianfa", "min": 60, "sect_skill_min": 30 },
                     { "gender": "F", "art": "gm_yunu_jian", "min": 60, "sect_skill_min": 30 } ],
           "moqi_min": 10,                              // 修練門檻（默契值；審查第三輪 20 → 10，見 §13.6）
           "src_note": "官方 jy1-2-6-2：男全真劍法、女玉女劍法、組隊、默契值與心性修為達一定程度；數字【設計提案】" }
```

  `sect_skill_min` 是該玩家**本派門技**（全真養生、古墓清心＝研究的「心性」推論）。
- `gm_suxin` 列（WP-COMBAT 擁有）：`sect_id` 改 `""`（兩派都能學）、`requires` 拿掉 `sect gumu` 與 `gm_suxin_unlocked`（改由師父列與 `combo.pair` 把關）、`era: "1.0B"`、`src_note` 更新。
- `ms_gm_xiaolongnu_suxin`：`requires` 改成 `[{ "type": "combo_ready", "art": "gm_suxin" }]`（新 requirement，§9.2 `requirements.gd` 的 WP-COMBAT 區塊）：學的人有合體夥伴；夥伴在同一間房、同一隊；兩人分別符合 `pair` 的兩邊（性別、武功等級、門技）；默契 ≥ `moqi_min`。原因碼 `combo_need_partner`／`combo_need_party`／`combo_pair_mismatch`／`combo_moqi_low`。`cap` 維持 100。

#### 3.3.2 默契關係（`server/combo_system.gd`，`class_name ComboSystem`，`GameHost.combo`）

- `combo_bond { target_char }`：era 1.0B；同房、雙方都沒有夥伴、不是自己 → 對方收到 `cb_bond_request`（`pending_prompts` 既有 UI）→ `combo_reply { from_char, accept }` → 成立：`world.combo_pairs["<小id>|<大id>"] = { a, b, moqi: 0, peihe: 0, since_day, drain_day }`、兩個角色 `ext.combo.partner = 對方 id`。
- `combo_cancel {}`：任一方；刪掉關係（兩邊的 `ext.combo` 清掉）。
- `combo_nurture {}`：配合度 = 100 → 默契 +5（上限 100）、配合度歸 0；否則 `combo_peihe_low`。
- 消耗：`ComboSystem.tick`：每對關係，距 `drain_day` ≥ 2 遊戲日、而且**兩人同時在線**時：配合度 −20；不夠扣 → 配合度 0、默契 −5（最低 0）；`drain_day = 今天`。
- 角色刪除 → 關係刪除（`on_char_deleted`）。

#### 3.3.3 戰鬥中（`core/battle/battle_combo.gd`，`class_name ComboRules`，純邏輯；由 `battle_rules.execute` 的 ART 分支呼叫）

- 單位規格（`Character.to_combatant` 的 WP-COMBAT 區塊）加 `combo: { partner_char, moqi }`；`BattleUnit` 加 `combo_mark: { group, t, dmg }`。
- 出合體武功（武功列有 `combo`）：照一般招式結算；之後 `ComboRules.after_art(b, u, art_row, dmg_dealt, rng) -> Array[事件]`：
  1. 記 `u.combo_mark = { group, t: b.time_s(), dmg }`（`Battle.time_s()` 新增：`ticks × TICK`）。
  2. 找同一邊、角色 id 等於 `u.spec.combo.partner_char` 的單位 P（用規格裡既有的角色 id 欄位；若既有的 `id` 不是角色 id，WP-COMBAT 在 `to_combatant` 區塊加 `char_id`）；P 的 `combo_mark.group == group` 且 `u.t − P.t ≤ COMBO_WINDOW_S (3.0)` → 擲 `p = clamp(0.20 + moqi × 0.006, 0.20, 0.80)`。
  3. 成功：對 u 的目標（若已倒下改打最近的敵人）追加一擊 `round((u.dmg + P.dmg) × COMBO_BONUS (0.5))`，不反擊、不爆擊；事件 `battle_combo { a, b, art_name, dmg }`；清掉兩人的 `combo_mark`；結算後 `ComboSystem` 給這對 `peihe += 10`（上限 100；由 `battle_summary` 帶出 `combo_hits`）。
  4. 失敗：只清掉 P 的 mark（u 的保留，給 P 下一次機會）。
- 數字全部【設計提案】（`COMBO_WINDOW_S` 3 秒【已證實】）；`balance_sim combo_suxin`：兩人（P2 等級、默契 50）一起打精英怪，有合體比沒合體的總傷害多 10–25%。

#### 3.3.4 介面

- 燈籠選單「武學」分頁加【建立默契】【取消默契】【培養感情】（WP-COMBAT：`ui/game/main/lantern_menu.gd` 的 M3d 區塊＋新 `ui/game/social/combo_dialog.gd`：顯示夥伴、默契、配合度、下次扣點日）。
- 戰鬥畫面：`battle_combo` 用金色大字「合體技・玉女素心劍法！」＋兩人之間的光帶（`battle_fx.gd`；沒有美術就用程式畫的光帶）。

#### 3.3.5 era

合體系統全部 1.0B：1.0A-only 世界的燈籠選單不顯示三個按鈕，intent 回 `era_locked`。

#### 3.3.6 （選做 B8）沖靈劍法、反兩儀刀法

做的話：`hs_chongling`（劍，`group: "chongling"`，pair：男女各華山劍法 ≥ 60）、`hs_fanliangyi`（刀，`group: "fanliangyi"`，pair：任何性別各「華山刀法」≥ 60；若本作沒有華山刀法就**不做**這列），師父岳不群（`ms_cb_yuebuqun_*`），`src: "proposal"`、`era: "1.0B"`。

### 3.4 無敵烙跑鞋（R11）

- `i_cb_laopaoxie`：`slot: "BOOTS"`、`def: 5`、`weight: 1`、`price: 50000`、`effects: [{ "type": "FLEE_ANYWHERE" }]`、`era: "1.0B"`、`src: "verified"`（效果）、`src_note` 寫價錢與來源【設計提案】。
- `Character.to_combatant` 規格加 `flee_anywhere: bool`（穿著有 `FLEE_ANYWHERE` 的裝備）。
- `battle_rules.validate_cmd` 的 FLEE：`spec.flee_anywhere` 且 `b.opts.kind` 不在 `FLEE_SHOE_BLOCKED := ["QUEST", "TRIAL"]`、而且不是 `ROB` 的 side 0 → 略過 `no_flee` 與 `not_on_escape`。（`DUEL` 可以逃＝棄權。）
- 賣家：`n_cb_jc_huolang`（西域貨郎，`jc_square`，1.0B，SHOP：`i_cb_laopaoxie`、`i_cb_yemingzhu`）。

### 3.5 夜明珠（R11）

- `i_cb_yemingzhu`：`slot: ""`、`tab: "OTHER"`、`weight: 0`、`price: 20000`、`effects: [{ "type": "LIGHT" }]`、`keep_on_use: true`、`usable: false`、`era: "1.0B"`。
- 客戶端（`ui/game/main/main_screen.gd` 的 WP-COMBAT 區塊）：時鐘 `night == true` 且背包沒有 `LIGHT` 道具 → 地圖區（區域圖、小地圖、場景圖）蓋一層深藍半透明（alpha 0.35）、小地圖只顯示目前房間與相鄰房間；有夜明珠 → 不蓋。設定 `ui.night_dim`（預設開；系統視窗可關，`settings.json`，純客戶端）。【設計提案：原作有夜晚變暗，這裡的變暗程度與小地圖霧是本作的】
- 沒有伺服器端效果（不改遇敵、不改戰鬥）。

### 3.6 裝備兩秒（R9）

- 選項 `equip_cooldown_ms`（int，預設 2000，0–5000；0 = 關）。
- 地圖上：`IntentsItem.equip`／`unequip`：`now_ms − s.last_equip_ms < cd` → `equip_cooldown`（`Session` 新欄位 `last_equip_ms`，不存檔）。
- 戰鬥中：`BattleUnit.last_equip_t`（戰鬥時間秒，初值 −999）；EQUIP 驗證 `b.time_s() − last_equip_t < cd/1000` → `equip_cooldown`；開戰前 2 秒內在地圖上換過裝**不**影響戰鬥（戰鬥時間獨立）。
- 介面：被擋時顯示「換裝要間隔兩秒」；背包的裝備按鈕在冷卻中灰 2 秒。

---

## 4. C：門派武功鏈（WP-ARTS）

共通：鏈都做成任務 v2（`q_ar_*`）＋師父列（`ms_ar_*`）＋武功列；任務 `test_plan` 必須能被 `story_acceptance --all` 跑完。新 NPC 與位置照 §9.5 的房間表。數字依 R12。

### 4.1 全真 重陽劍法（C1；`era: "1.0B"`、`src: "later"`）

| 步驟 | 內容 |
|---|---|
| 條件 | 全真弟子；全真心法 70、基本劍法 60、基本內功 60、養生 80【2002-05-07】 |
| 1 | `n_ar_qz_shanju`（山居隱士，2002 稱「老頭」；`zn_river`【設計提案：百花谷不在地圖】）交談接任務 → 旗標 `qz_chongyang_jian` → 師父列 `ms_ar_qz_shanju` 教 1–20 |
| 2 | 自修 20 → 30（武功列 `self_study_until: 30`） |
| 3 | 等級 ≥ 30 回山居隱士 → 要 3 瓶狀元紅（`i_ar_zhuangyuanhong`，大理、西夏店小二賣 60 兩，§9.6）→ 交了給推薦信 `i_ar_qz_tuijianxin` |
| 4 | `n_ar_qz_shuliu`（漱流隱士；`dlw_river`「兩面靠水」）收推薦信 → `ms_ar_qz_shuliu` 教 30–40 |
| 5 | `n_ar_qz_yunyou`（雲遊道士；`em_road1` 崆峒橋，2002「娥眉和空洞這裡有一個小水潭」）要一把拂塵（`w_lt_fuchen`，既有）→ `ms_ar_qz_yunyou` 教 40–60 |
| 6 | 60 以上自修（`self_study_cap: 100`【設計提案；2002 作者自修到 76】） |

武功列 `qz_chongyang`：`era` 改 `1.0B`、`requires` 保留旗標與門檻、`self_study_until 30`、`self_study_cap 100`。

### 4.2 全真 空明拳（C2；`era: "1.0B"`、`src: "later"`）

- `n_ar_qz_wangzhijin`（王志謹，`qz_square` 全真布告欄旁）：條件 昊天掌 70、基本拳腳 80、全真心法 80、養生 90、福緣 32、善惡 ≥ 1000【2002-05-07】→ 任務 `q_ar_qz_kongming` 給旗標 `qz_kongming`＋`learn { qz_kongming: 1 }`。
- 自修 1–40（`self_study_until: 40`）；`ms_ar_qz_wangzhijin` 教 41–70；之上不能升（讀寶典是後期）。

### 4.3 靈鷲 八荒（C3；`era: "1.0B"`、`src: "later"`）

- 任務 `q_ar_lj_bahuang`：天山童姥對話選「服侍童姥」（條件 逍遙心法 80、定性 50【2002-08-18】）→ `n_ar_lj_wuyazi`（無涯子；`ts_hut`【設計提案：百花村不在地圖】）→ 西夏虛竹（既有 `n_xx_xuzhu`）→ 回童姥 → 旗標 `lj_bahuang_learned`＋`learn { lj_bahuang: 1 }`。
- 自修 1–40（`self_study_until: 40`）；`ms_ar_lj_lanjian_bahuang`（蘭劍，既有 `n_lj_lanjian`）教 41–70。
- 既有 `ms_lj_tonglao_bahuang`：`cap` 80 → 1、`src_note` 註明「1 級由任務給；之後蘭劍」（不刪列，T5）。武功列 `lj_bahuang`：`era` → `1.0B`、`self_study_until 40`。

### 4.4 星宿 煉毒（C4；1.0A）

- 任務 `q_ar_xh_muding`「邪惡的練毒」（標題【已證實】，步驟【設計提案】）：出塵子（`n_xh_chuchenzi`）要 3 種毒物各 1（既有 `i_sm_du_*` 或 `r_lf_*` 任三種）→ 給小木鼎 `i_ar_xh_muding`（`unique_per_char`、`no_sell`、`keep_on_death`）。
- 指令 `liandu {}`（`server/intents/intents_arts.gd`）：星宿弟子、身上有小木鼎、精 ≥ 15 → 扣精 15、基本毒術熟練度 `20 × 倍率`；倍率＝「特定狀況」相乘【設計提案】：夜裡 ×1.5、在 `xingxiu`／`xingxiu_road` 地區 ×1.5、身上中毒 ×2；不需要其他道具。原因碼 `liandu_no_tool`／`liandu_not_xh`／`not_enough_jing`。
- 介面：星宿弟子身上有小木鼎時，背包裡小木鼎的「使用」＝送 `liandu`（WP-ARTS 在 `IntentsItem.use_item` 的 WP-ARTS 單行鉤子之後處理；或道具 `usable: true` ＋ `effects: [{ "type": "LIANDU" }]` 由 `ArtsSystem.on_use_item` 處理，二選一，交付說明寫明）。

### 4.5 峨嵋 滅絕只教 1 級（C5）

- 已做：`ms_em_miejue_*` cap 1、武功列 `self_study_cap`（滅劍 90、九陽 80、佛光 80）。WP-ARTS 只加測試鎖住：滅絕教到 1 後再學回 `cap_reached`、自修 1→上限可以、規則 `self_study_cap: "NONE"`。
- （選做）1.0B 峨嵋信差 `n_ar_em_xinchai`（`em_square`）：第九話「新版鐵指環」，交談給鐵指環路線的旗標 `em_foguang_ok`（條件照既有 `q_em_*`，WP-ARTS 讀現有任務決定）。

### 4.6 峨嵋 四象掌（C6；`era: "1.0B"`）

- 新武功 `em_sixiang`（四象掌）：`category: "FIST"`、`base_skill: "basic_fist"`、`difficulty: 1.2`【設計提案；後期係數 2.21】、`tier: "QUEST"`、招式射程「半米字」用既有最接近的範圍型（WP-ARTS 選、`src_note` 註明）、`self_study_until: 10`、`self_study_cap: 70`【設計提案：35–70 原本是萬年寺靜象，不在本作】；`requires`：峨嵋、旗標 `em_sixiang_ok`、佛光普照掌 50、斷惡 60、福緣 20。
- 任務 `q_ar_em_luosha`「羅煞劍任務」（官方 index_jy19-1）：
  1. 雁門關守衛 `n_ar_ym_shouwei`（`ym_gate`）：條件 隊伍 ≥ 3 人（`party_size_min 3`）、隊長實戰 ≥ 100,000、最大內力 ≥ 300【R12：2002「實戰 500 萬」改寫】；選「幫忙」→ 戰鬥 `m_ar_manbing` 三波各 2 隻（每隻氣 2500【設計提案】，`party_only`）。
  2. 守衛要給 50,000 兩：**收**→ 任務結束（outcome `money`，+50,000 兩）；**拒收** → 推薦信 `i_ar_ym_tuijianxin`。
  3. `n_ar_guoxiang`（郭襄；新房間 `zn_pomiao` 終南山破廟）：峨嵋弟子且符合四象掌條件 → 旗標 `em_sixiang_ok`＋`learn { em_sixiang: 1 }`，之後 `ms_ar_guoxiang_sixiang` 教 2–10；不合格或非峨嵋 → 非峨嵋選「拼酒」（根骨 ≥ 20 → 羅煞劍 `i_ar_luoshajian`；否則黃藥丸 `i_ar_huangyaowan` ×10）；不合格的峨嵋弟子 → 羅煞劍。
- 羅煞劍：`weapon_type: "SWORD"`、`atk` 照同價位武器【設計提案】、`unique_per_char`。黃藥丸：回氣 200 的藥【設計提案】。

### 4.7 血刀 恐嚇與血池（C7；R13）

- 指令 `intimidate { npc }`（1.0A）：血刀弟子；NPC 在同一間房、`kind` 屬於 `STORY`／`FUNC`／`SHOP`／`QUEST`，**不是**守衛、師父、本派 NPC、佈告欄、任務進行中的對象；每個 NPC 每遊戲日一次（`counters.intimidate = { day, npcs: [id] }`）；扣精 20、神 20、善惡 −10；威嚇熟練度 +20（**沒有 < 50 的限制**，跟雜務不同；但威嚇熟練每遊戲日最多 +200）【研究：恐嚇指令練威嚇、降善惡、耗精神；數字【設計提案】】。NPC 回一句害怕的話（模板 `ar_intimidate_<n>` 輪流）。原因碼 `intimidate_not_xd`／`intimidate_bad_target`／`intimidate_daily`／`not_enough_jing`／`not_enough_shen`。
- 介面：血刀弟子在 NPC 選單多一個「恐嚇」（`npc_dialog.gd` 的 WP-ARTS 區塊）。
- 血池比武（`src: "later"`，2003；`era: "1.0A"`）：`n_ar_xd_xuechi`（血池師兄，`xd_pool`，服務 FIGHT 三選一：初／中／高 → `m_ar_xd_xuechi_1..3`，氣 800／2000／5000【設計提案】、`no_rewards: true`）；贏了 `ArtsSystem.on_battle_settled` 給威嚇熟練度 +30／+60／+100（同樣算進每日 +200 上限），每階每遊戲日 3 次。輸了沒有死亡懲罰（kind `FIGHT` 但 `opts.spar: true`，照 M3a 切磋）。
- 威嚇的戰鬥效果：**不動**（M3c2 HEAVY）。`sects.json` 血刀列 `src_note` 由 WP-ARTS 加一句兩種說法並存的註記。

### 4.8 血刀 血魔刀法（C8；`era: "1.0B"`）

- 新武功 `xd_xuemo`（血魔刀法）：`category: "BLADE"`、`base_skill: "basic_blade"`、`difficulty: 1.8`【設計提案；後期係數 2.23】、`tier: "QUEST"`、招式帶流血（既有狀態 `bleed`，用既有招式狀態欄位）、最高一招範圍大（接近全屏的既有範圍型，「練到 70 據說是全屏」）、`self_study_until: 10`【2002-08 最早版本】、`requires`：血刀、旗標 `xd_xuemo_ok`、威嚇 90、基本內功 100、基本刀法 100、血海魔功 30、善惡 ≤ −900。
- 任務 `q_ar_xd_xuemo`（2002-08-19 版；實戰門檻 R12 改成 ≥ 100,000）：
  1. 條件同上＋`quest_done q_xd_xuehai`（門規事件的替代）；血刀老祖（`n_xd_laozu`）交談接任務。
  2. 五個線人（全部 `appear.requires` 只在本階段出現）：`n_ar_xd_inf_heilong`（血刀弟子，`xe_heilong`）、`n_ar_xd_baoxiang`（寶象，`ym_outside` 雁門關外山丘；跟血刀門內的 `n_xd_spar` 同名不同 NPC，`src_note` 註明）、`n_ar_xd_inf_dali`（搶姑娘的血刀弟子，`dl_square`）、`n_ar_dingbusan`＋`n_ar_dingbusi`（`zn_road1` 終南山左上）、`n_ar_laokelian`（老可憐，`jc_biaoju` 旁，1.0B）；每個 TALK。
  3. 回老祖 → 給刀訣 `i_ar_xd_daojue`。
  4. 帶著刀訣在 `xd_gate`（血刀門口）**累計停留 2 個時辰**（世界時間；`ArtsSystem` 記 `counters.xuemo_walk_s`，離開就暫停）【「兩三個時辰」取 2】→ 送 `ar_xuemo_enlightened`、旗標 `xd_xuemo_ok`、`learn { xd_xuemo: 1 }`、收回刀訣。
  5. 自修到 10；`n_ar_xd_xuemo_laozu`（血魔老祖，`xd_pool`）`ms_ar_xd_xuemo` 教 11–70。
- 紗紗鏈：不做（§1.2）。

### 4.9 全真殺古墓弟子（C9）

- 殺氣加倍（1.0A，【已證實 2001 mengpai/6；量【設計提案】】）：全真弟子殺死古墓**玩家**（PvP 擊殺，任何種類）或古墓 NPC 弟子（`m_*` 列 `sect: "gumu"` 或 NPC 攻擊 `npc_sect == "gumu"`）時，該次殺氣 ×2。位置：`SectSystem.on_pvp_kill`、`_kill_gain`、`on_npc_killed` 的 WP-ARTS 區塊。
- 計數 `counters.qz_gumu_kills`（同上三種擊殺，全真弟子才計；永久，不遞減【待考證】）。
- 門規 `qz_r_kill_gumu`（`data/sect_rules.json`）：`{ "id": "qz_r_kill_gumu", "sect": "quanzhen", "tier": "BREACH", "kind": "STATE", "ok_if": [{ "type": "counter_max", "key": "qz_gumu_kills", "value": 10 }], "text": "rule_qz_kill_gumu", "era": "1.0B", "src": "verified", "src_note": "官方 index_jy2-22 晚期清單：殺死古墓弟子超過10人；2001-08-07 news 141 沒有這條 → 加入日期【待考證】，放 1.0B" }`。`counter_max` 是新 requirement（`requirements.gd` 的 WP-ARTS 區塊）。違規照 `sect_violation_mode`（坐牢／逐出），坐牢後計數**不歸零**（再殺一個再坐）【設計提案】。

---

## 5. D：事件（WP-EVENTS）

### 5.1 檔案與類別

- `core/rules/jiebiao_rules.gd`（`class_name JiebiaoRules`，純靜態）、`server/jiebiao_system.gd`（`class_name JiebiaoSystem`，`GameHost.jiebiao`）。
- `core/rules/tourney_rules.gd`（`class_name TourneyRules`，純靜態：對戰表、判定、稱號表）、`server/tourney_system.gd`（`class_name TourneySystem`，`GameHost.tourney`）。
- `server/intents/intents_events.gd`、`ui/game/events/tourney_dialog.gd`、`ui/game/events/jiebiao_confirm.gd`。

### 5.2 劫鏢（D1、D2；1.0B；R15）

#### 5.2.1 危險鏢

- NPC：`n_ev_jb_xx`、`n_ev_jb_dl`、`n_ev_jb_jc`（鏢局二掌櫃；`xx_biaoju`、`dl_biaoju`、`jc_biaoju`；1.0B；服務 QUEST）。
- 任務：12 條 `q_ev_jb_<起>_<迄>_<hu|huo>`（`xx`、`dl`、`jc` 兩兩互通 × 護送／送貨），`group: "jiebiao"`、`era: "1.0B"`、`repeat { max: 0, cooldown_days: 0 }`、`abandon: true`、`party_credit: false`。價格（設計文【已證實 40 個數字】，本作只有這三城）：

| 路線 | 護送鏢 | 送貨鏢 |
|---|---|---|
| 西夏↔大理 | 2400 | 3200 |
| 京城↔西夏 | 6000 | 8000 |
| 京城↔大理 | 6000 | 8000 |

- 接鏢條件（`requires`）：實戰 ≥ 100,000、名聲 ≥ 100、歷練 ≥ 100（R15）、`sect_not gaibang`（丐幫不能運鏢【已證實】）、沒有進行中的危險鏢、選項 `jiebiao_enabled`。接的時候扣押金＝鏢價（`JiebiaoSystem.on_accept`；不夠 → `jb_no_deposit`，任務不成立）。
- 進行中：`ext.jiebiao.active = { quest, value, kind, from, to, since_s }`；`escort_start` 跟隨 NPC：護送鏢 `n_ev_jb_client`（客商）、送貨鏢 `n_ev_jb_cart`（鏢車）；房間視圖與其他玩家看到「押鏢」標籤（金色，`player_tags`）。
- 成功（ESCORT 送達）：還押金＋鏢價（合計 2 × 鏢價）、名聲 +3（同一般鏢）；設不接鏢冷卻：`ext.jiebiao.cd[起點 NPC] = now + 隨機(1800, 3600, 7200) 世界秒`；冷卻中那位 NPC 說【目前沒有鏢可供承接】（`jb_cooldown`）；不擋一般保鏢。
- 失敗（任何一項 → 任務 `fail`、押金沒收、清 `active`）：在任何戰鬥中逃走（`FLED`）、死亡、劫鏢成功、登出／斷線（`on_logout`；主機關閉時進行中的不算失敗，存檔照留，登入時繼續）、放棄任務。
- 特殊地雷：`JiebiaoSystem.on_enter_room`：持有 `active` 的人進 WILD 房間，15% 機率（每 3 間最多一次）遇上劫匪 `m_ev_jb_bandit` ×2–4（氣 1200，【設計提案】）；種類 `ENCOUNTER`、`pull_party: true`；逃走＝失敗。

#### 5.2.2 劫鏢方

- `rob_escort { target_char }`：條件：選項 `jiebiao_enabled`；劫鏢者實戰 ≥ 100,000；目標有 `active`、在同一間房、閒置；房間允許 PK（`pk_allowed_at`）；不同隊；PK 模式允許強制 PK。違反 → `rob_*` 原因碼（§7）。
- 開戰：`battles.start_pvp(劫鏢者, 目標, "ROB", { pull_party: true })`；`BattleSystem` 的 WP-EVENTS 區塊在 side 1 加一個鏢單位（`m_ev_jb_cart`：氣 4000、防高、AI 不動；或 `m_ev_jb_client`：氣 1500、AI 隨機打／防／走）。
- 劫鏢標記：**開戰當下**給每個 side 0 玩家 `ext.jiebiao.rob_until_s = now + 3600`（世界秒），成不成功都給；登出不清。
- 規則：side 0 不能逃（`validate FLEE`／`QING ESCAPE` 回 `no_flee`；烙跑鞋也不行）；戰鬥結束條件照一般 PvP。
- 成功＝鏢單位死亡、或押鏢玩家死亡／逃走：押鏢方失敗（§5.2.1）；**結束時還活著、且是 side 0 的玩家**平分 `floor(鏢價 × 0.8)`（`JiebiaoRules.rob_share`）。失敗（劫鏢方全滅）：鏢繼續走。
- PK：`ROB` 照強制 PK（PK值 +1、殺氣、善惡、`pk_kill`）——`PkSystem.on_pvp_end` 把 `ROB` 當 `FORCED`（WP-LAW Day-0 寫好分派，§9.2）。

#### 5.2.3 守城官兵

`JiebiaoRules.rob_marked(ch_ext: Dictionary, now_s: float) -> bool`；WP-LAW 在守衛人數計算時：`rob_marked` → 至少 `MoralityPk.GUARDS_PK`（2 名）。

#### 5.2.4 防刷（`balance_sim ev_jb_zero_sum`）

押鏢的 A 與劫鏢的 B 是朋友：A 付押金 V、B 拿 0.8V → 兩人合計 −0.2V；A 自己送到：+V（正常收入，冷卻擋連刷）。`balance_sim ev_jb_income`：實戰 10 萬的角色只跑危險鏢（含特殊地雷時間）每小時收入 ∈ 同階段戰鬥收入的 0.6–1.5 倍。

### 5.3 比武（D3、D4；【後期版 2002・設計提案】；R14）

#### 5.3.1 種類與地點

- `WULIN`（武林大會）：所有人。`SECT:<sect_id>`（門派比武）：該派弟子（`sects_enabled` 有的派）。
- 地點：新房間 `xx_biwu`（西夏比武場擂臺）與 `xx_biwu_rest`（比武場休息區），1.0A（2001 已有比武場）；`safe: true`（禁止叫戰與強制 PK；比武由系統開打）。
- 報名 NPC：`n_ev_tourney_clerk`（武林大會報名員，`xx_biwu_rest`，服務 `TOURNEY`）；門派比武在同一位報名（本包不做各派的報名 NPC；`src_note` 列出 2002 各派報名 NPC 名字）。

#### 5.3.2 排程

- 日曆（`WorldClock` 的 day、month）：`WULIN` 每月第 15 遊戲日午時開打，第 8 日起可報名；`SECT:*` 每月第 1 遊戲日，從上個月第 24 日起可報名，各派依 §5.3.7 的時辰依序開打（同一時間只進行一場比賽）。
- 主機開辦：`tourney_host { kind, signup_s }`（`HOST` 旗標，只有主機或 `admin_identities`）→ 立刻開報名 `signup_s` 真實秒（預設 300，30–1800）後開打。
- 選項 `tourney_enabled`（預設 true）；關 → 日曆不排、`tourney_host` 回 `tourney_disabled`。

#### 5.3.3 對戰表

- `TourneyRules.bracket(entrants: Array, champion_id: String, seed: int) -> Array`：單淘汰；人數補到 2 的次方，空位＝輪空（自動晉級）；上屆冠軍放在另一半區的種子位；其餘亂數（`seed` 固定可重現）。至少 2 人才開打（不足 → 取消，送 `tourney_cancelled`）。
- 點名：每場開始前送 `ev_tourney_call`（本人與房間）；選手必須在 `xx_biwu` 或 `xx_biwu_rest`、閒置、不在牢裡；每 30 真實秒點一次，**3 次不到判負**。兩人都不到 → 都判負（下一輪對手輪空）。
- 比賽：`battles.start_pvp(a, b, "DUEL", { duel_limit_s: 600 })`；DUEL 規格：開戰前 `BattleSystem` 的 WP-EVENTS 區塊把雙方規格的 `sect_skill` 清空（不觸發門技）、`battle_items` 拿掉召喚類（`effects` 有 `SUMMON` 的道具）。

#### 5.3.4 DUEL（切磋模式）

- 沒有死亡懲罰：結算時 DUEL 一律跳過 `handle_death`、不掉物品、不扣技能；戰後雙方 精氣神內力 補滿、狀態清掉。
- 時間：`Battle` 的 WP-EVENTS 區塊：`opts.duel_limit_s` 到了 → `TourneyRules.judge(a_stats, b_stats)`：總傷害（`BattleUnit.dmg_dealt`）多者勝 → 命中次數（`hits_landed`）多者勝 → 目前氣／最大氣 高者勝 → 都一樣：先報名者勝。`dmg_dealt`、`hits_landed` 由 WP-COMBAT 的 `resolve_strike` 累計（§9.2）。
- 逃走、斷線（`detached`）＝棄權。
- 觀戰：擂臺與休息區的人收到每一擊的房間文字（既有 `battle_*` 事件轉成房間訊息，`ev_duel_line` 模板）、每場結果 `ev_duel_result`；決賽與冠軍發全服傳聞 `rmr_ev_tourney_champion`（`{name}在武林大會奪魁，成為武林盟主！`）。

#### 5.3.5 名次與獎勵（2002 官方數字【後期版】；不發神兵，R14）

- `WULIN`：名次 1–8（勝部／敗部照研究：冠軍、亞軍、兩個四強、四個八強）。名聲 +3000、2000、1200、1200、300、300、300、300【設計提案：單淘汰沒有 3／4 名、5–8 名分級 → 合併的名次取較低的那格：四強 1200、八強 300（M3d 審查：原寫四強 1500、八強 1000，比 2002 官方 1500／1200、1000／800／500／300 往上取）】；冠軍稱號「武林盟主」＋`i_ev_mengzhu_ling`（盟主令牌：`keep_on_death`、`no_drop`、`no_sell`；持有者 `player_tags` 發光「盟主」）——下一屆 `WULIN` 開打時收回。
- `SECT:<sect>`：冠軍稱號（研究晚期表）：恆山派掌門師姐、全真派天樞真人、星宿派大師兄、峨嵋派峨嵋第一、靈鷲宮掌門師姐、丐幫幫主、少林派掌門師兄、血刀門少祖、華山派武聖、武當派代理掌門、古墓派傳人（`TourneyRules.SECT_TITLES`）；全真 2–7 名 天璇、天璣、天權、玉衡、開陽、搖光真人（單淘汰不足 7 名就到實際名次為止）；冠軍名聲 +1000、歷練 +800；有效到下一屆該派比武。
- 稱號存 `ext.tourney.titles = [{ kind, title, until_s }]`；頭上顯示在門派名之後（`player_tags`）。叛派 → 門派稱號收回。

#### 5.3.6 防刷（D4）

- 報名人數 < 4 → 照打，但不發名聲與稱號（「表演賽」）。
- 同一種 `kind` 的獎勵每 30 遊戲日最多發一次（`world.tourney.last_reward_day[kind]`）；冷卻內主機開辦的也是表演賽。
- 同一身分（`identity`）只能有一個角色報名同一場。

#### 5.3.7 門派比武時辰

古墓 午、靈鷲 未、血刀 申、丐幫 酉、星宿 戌、少林 巳、武當 午、峨嵋 未、華山 申、恆山 酉、全真 戌（前 5 派在第 1 日、後 6 派在第 2 日；研究：2002 晚期官方時程週六／週日）。報名人數 < 2 的派直接取消。

---

## 6. E：跑腿與區域（WP-ERRANDS）

### 6.1 `chore` 欄位通用化（E1；`server/quest_system.gd` 由 WP-ERRANDS 接手 M3c2 WP-PACE 區塊）

新欄位（全部可選、向後相容）：

| 欄位 | 型別 | 預設 | 意義 |
|---|---|---|---|
| `kind` | String | `"SECT"` | `"SECT"`：現行（`sect` 必填、學點受 `chore_xuedian` 與新手期限制）；`"TOWN"`：任何人、`sect` 可省略、學點**不受**新手期與 `chore_xuedian` 限制 |
| `decay_all` | bool | false | true → `decay_pct` 也縮放 `money`、`fame`、`lilian`、`combat_xp`、`learn_points`（各自 floor） |
| `cost`、`prof_below`、`lp`、`decay_pct` | — | 照 M3c2 | 不變 |

- `TOWN` 不再要求 `group == "sect_chores"`；`chore` 存在就套用。計數照用 `counters.chore_day`。
- `data_lint`（WP-ERRANDS 區塊）：`kind` 合法；`SECT` 要有 `sect` 且與 `requires` 一致（現行規則）；`TOWN` 的任務必須 `repeat.max == 0`（可重複）且 `decay_pct` 最後一個值 ≤ 30。
- `balance_sim er_town_lp_cap`：一個角色一個遊戲日把**所有** TOWN 任務做到遞減到底，學點合計 ≤ 600、名聲 ≤ 60、歷練 ≤ 200。

### 6.2 丐幫跑腿（E2）

#### 6.2.1 柯鎮惡 → 郭靖（1.0B；R16）

- `n_er_kezhene`（柯鎮惡，江南七怪之首；新房間 `mw_snow`「馬王洞西雪地」）、`n_er_guojing`（郭靖；新房間 `zn_bridge`「終南山北橋」）。
- `q_er_kezhene`：`requires` 名聲 ≥ 500、歷練 ≥ 500（`src_note`：2001-12-03【待考證：可能是二袋門檻】）；柯鎮惡給信 `i_er_ke_xin` → 交給郭靖 → 名聲 +5、歷練 +20【已證實】。`repeat { max: 0, cooldown_days: 0 }`；`chore { kind: "TOWN", lp: 0, decay_pct: [100, 100, 80, 60, 40, 20, 0], decay_all: true }`。不限門派（研究：說法不是丐幫專屬）。

#### 6.2.2 豬哥義 → 三八紅（1.0A）

- `n_er_sanbahong`（三八紅；新房間 `dl_fangzhi`「大理紡織店」）；豬哥義用既有 `n_xx_zhugeyi`（`quests` 欄位由 WP-ERRANDS 加 `q_er_zhugeyi`）。
- `q_er_zhugeyi`：豬哥義給包袱 `i_er_zgy_baofu` → 交三八紅（對話要客氣：選「客氣」那句 → 200 兩＋寬衣 `i_er_kuanyi`；選粗話 → 她不收，可以重講）→ 寬衣帶回豬哥義 → 名聲 +8（`src_note`：2001-11-06「8-10 點名聲」，哪一步給【待考證】）。`repeat { max: 0, cooldown_days: 0.5 }`；`chore { kind: "TOWN", lp: 0, decay_pct: [100, 60, 30, 0], decay_all: true }`。

#### 6.2.3 武林帖（1.0B）

- `n_er_tiefan`（武林帖販子，`jc_square`，SHOP：`i_er_wulintie` 1000 兩）【設計提案：賣家與價錢沒有記載】；道具名「武林帖」若 `data_lint` 要求名稱唯一就叫「武林挑戰帖」。
- 使用（`ErrandsSystem.on_use_item`，由 `IntentsItem.use_item` 的 WP-ERRANDS 單行鉤子呼叫）：在 WILD 或 CITY 房間、閒置；`counters.wulintie_day` 距今 < 3 遊戲日 → `wlt_cooldown`（帖子不扣）；否則扣帖子、依實戰開打 `m_er_wulin_1..4`（< 2 萬／< 10 萬／< 50 萬／其他；FIGHT、可逃）；贏 → 名聲 +60、歷練 +200【設計提案；研究：8 張＋其他來源 → 名聲 3000、歷練 10000】、設 `wulintie_day`；輸或逃 → 帖子已用、不設冷卻。

#### 6.2.4 英雄帖：不做（R18）。

### 6.3 城鎮學點任務（E3；R17）

| id | 任務 | 地點／NPC | era | 獎勵 | 重複 | 出處 |
|---|---|---|---|---|---|---|
| `q_er_biandang_xx` | 送便當（西夏） | 婦人 `n_er_xx_funv`（`xx_minfang`）→ 農夫 `n_er_xx_nongfu`（西夏城門外的田：WP-ERRANDS 在 `xx_gate_e` 往東第一間有 `FIELD` 的房間放） | 1.0A | 學點 50 | `hour_in ["午"]`；`chore { TOWN, lp: 50, decay_pct: [100, 60, 30, 10, 0] }` | 鐵心 2001-09-04「一次50點後來就越來越少，只限午時」【已證實】；曲線【設計提案】 |
| `q_er_biandang_dl` | 送便當（大理） | 大理婦人（既有 `n_dl_furen`）→ 既有樵夫 `n_sm_qiaofu_dl` | 1.0A | 同上 | 同上 | 第五話「大理和西夏的農地旁，各有一位」 |
| `q_er_zuigui` | 醉鬼的燒刀子酒（M3d 審查：跟 NPC「醉鬼」同名；2001-08-18 原文「一个醉鬼」） | 醉鬼 `n_er_dl_zuigui`（`dl_bank`）；燒刀子酒 `i_er_shaodaozi` 大理店小二賣 20 兩（§9.6） | 1.0A | 學點 5；拒絕 → 被偷 40 兩（身上不夠就偷光） | `cooldown_days 0.25`；`chore { TOWN, lp: 5, decay_pct: [100, 100, 60, 30, 0] }` | 2001-08-18「無限次」＋官方晚期「學點 5、偷 40 兩、一段時間可再接」 |
| `q_er_ahu` | 阿虎的煩惱 | 阿虎 `n_er_dl_ahu`（`dl_square`）→ 青青 `n_er_dl_qingqing`（大理北方河邊：`rr_bridge` 以南第一間河邊房，WP-ERRANDS 選）→ 阿虎 | 1.0A | 學點 50＋300 兩 | 一次 | 2001-08-26【已證實】 |
| `q_jc_xiaobao`（改） | 李大嬸找小保 | 既有 | 1.0B | 實戰 < 700：200 兩＋學點 10；否則 100 兩＋學點 5 | 一次（不改） | 官方晚期頁【後期版數字】；改 outcomes，`src_note` 更新 |
| `q_ym_douji`（改） | 蕭峰鬥酒 | 既有 | 1.0A | 贏：學點 40、基本內功熟練 +10、歷練 +3 | 每日一次（不改）＋`chore { TOWN, lp: 40, decay_pct: [100, 0] }` | 2001 other.htm【已證實】 |

`q_sm_esi_nongfu`（一次性、unverified）**不改**。

### 6.4 黑龍潭（E4；1.0B；R19）

- 新地圖 `data/maps/heilongtan.json`（region `heilongtan`，`type: "DUNGEON"`，`era: "1.0B"`，`src: "proposal"`）：從 `xe_heilong` 往南（出口帶 `"era": "1.0B"`）進入；8 間：`hl_mud1`…`hl_mud5`（五行八卦陣：五間互相錯接，走錯會繞回 `hl_mud1`，正確順序寫在瑛姑的任務提示裡）、`hl_hut`（瑛姑小屋）、`hl_fox`（靈狐出沒處）、`hl_slope`（南坡：白猿與羊群）。`encounter` 只在 `hl_slope`（`m_er_yang` ×4–7【已證實 4-7 隻】、`m_er_baiyuan` 偶爾）。
- NPC：`n_er_yinggu`（瑛姑，`hl_hut`）、`n_er_cien`（慈恩，`hl_mud3`，只有對話【設計提案】）。
- `q_er_jiuwei`「九尾靈狐」：瑛姑要靈狐血（治病，照預告）→ `hl_fox` 的 FIGHT `m_er_jiuwei`（氣 900、閃躲 150、AI 逃跑型【設計提案】；`no_flee: false`）→ 贏得 `i_er_hulixue` → 交瑛姑 → 「意外收獲」：學點 100、名聲 20，另擲：5% 夜明珠 `i_cb_yemingzhu`（WP-COMBAT 的道具 id；查不到就略過）、20% 九花玉露丸（既有就用，沒有就略過）。`repeat { max: 0, cooldown_days: 3 }`。
- `m_er_yang`：善惡 −20／隻（研究「一次減100左右」÷ 4–7 隻）；`m_er_baiyuan`：善惡 −5／隻（R：扣善惡【已證實】、量【待考證】）；兩者實戰學點很低（新手不會來這裡練）。

### 6.5 BUG：陸大有切磋獎勵（E6）

- `SectSystem.spar_decide(ch, count, mid := "")`（WP-ERRANDS 區塊；新的可選參數）：`mid` 對應的門派（`Learning.spar_sect(mid)`：`m_<派前綴>_dizi` → 前綴對應的派、`m_hs_trainee` → `huashan`；`SPAR_EXTRA` 的對照表由 WP-ERRANDS 在 `learning.gd` **以外**的地方建，因為 `learning.gd` 凍結 → 放在 `server/sect_system.gd` 的 WP-ERRANDS 區塊 `spar_sect(mid)`）≠ `ch.sect` → `{ xp: false, lp: false, why: "not_disciple" }`，**不計**每日場數。
- `_spar_rows`／`spar_adjust`／`_spar_settle` 把 `mid` 傳進去；`why == "not_disciple"` 送 `er_spar_not_disciple`（「你不是本派弟子，切磋只是點到為止。」）。
- 任務 `q_hs_kaoyan`（FIGHT 目標）照舊完成。

### 6.6 （選做 F）交易之道（R20）

- `EconCalc.sell_price(item_row, trade_level := 0, on := false)`：`on` → `floor(price × SELL_RATE × (1 + trade_level / 300.0))`；`NpcSystem` 賣出時傳角色的 `basic_trade` 與規則 `trade_sell_bonus`（WP-ERRANDS 在 `npc_system.gd` 的具名區塊，§9.2）。
- 規則 `trade_sell_bonus`：`RULE_DEFAULTS` false；四個內建組合 true（1.0A 已有效果）——**只有在** `balance_sim` 的 `er_trade_band`（`econ_loop` 0 條、`loot_econ_elite`／`loot_econ_boss` 收入增幅 ≤ 33% 而且仍在帶內、`econ_hourly` 全在帶內）通過時，WP-ERRANDS 才把四組改成 true；否則留 false 並在交付說明寫數字。
- 訓練：照現行生活技能熟練（買賣清水不會賺錢：0.3 × 1.333 × 2 = 0.8 < 2）。

---

## 7. 協定增量（`core/protocol.gd` 由 WP-LAW Day-0 一次寫完；`ui/game/ui_keys.gd` 由 WP-COMBAT Day-0 一次寫完；`VERSION` 維持 5）

```gdscript
# ---- M3d（M3D_PLAN §7；T1：純新增，RPC 簽名不變 → VERSION 維持 5） ----
# WP-LAW
const I_BOUNTY_BOARD := "bounty_board"        # { npc }
const I_BOUNTY_LICENSE := "bounty_license"    # { npc }
const I_BOUNTY_ADD := "bounty_add"            # { npc, target_name, money:int }
const I_BOUNTY_CLAIM := "bounty_claim"        # { npc }
const I_CLEANSE := "cleanse"                  # { npc, what:"KILLING"|"PK", times:int? }
# WP-COMBAT
const I_COMBO_BOND := "combo_bond"            # { target_char }
const I_COMBO_REPLY := "combo_reply"          # { from_char, accept:bool }
const I_COMBO_CANCEL := "combo_cancel"        # {}
const I_COMBO_NURTURE := "combo_nurture"      # {}
# battle_cmd：BATTLE_CMDS 加 "DODGE"、"QING"；參數表加 "mode" 已存在 → 列舉 QING_MODES
const QING_MODES := ["JUMP", "ESCAPE"]
# WP-ARTS
const I_INTIMIDATE := "intimidate"            # { npc }
const I_LIANDU := "liandu"                    # {}
# WP-EVENTS
const I_ROB_ESCORT := "rob_escort"            # { target_char }
const I_TOURNEY_INFO := "tourney_info"        # {}
const I_TOURNEY_SIGNUP := "tourney_signup"    # { npc, kind }
const I_TOURNEY_WITHDRAW := "tourney_withdraw"  # {}
const I_TOURNEY_HOST := "tourney_host"        # { kind, signup_s:int? }（HOST）
# NPC_SERVICES 加 "BOARD"、"LICENSE"、"CLEANSE"、"TOURNEY"（DataSchema、data_lint、UiKeys.SERVICE_LABELS 同步：佈告欄、執照、消災、比武報名）
```

`battle_cmd` 參數驗證（`Protocol.ENUM_ARGS`）：`cmd` 列舉加兩個值；`mode` 依 `cmd` 對照：`INNER` → `INNER_MODES`、`QING` → `QING_MODES`（WP-LAW Day-0 把現行的單一 `"mode": INNER_MODES` 改成依 cmd 的檢查，回傳 `bad_value:mode`）。

事件（`E_*`，`ui: true` 的列在 `M3D_UI_EVENTS`）：

| key | 送給 | 內容 | WP |
|---|---|---|---|
| `bounty_board` (ui) | 本人 | `{ rows: [{ name, sect_name, pk, morality, amount, listed_s }], refreshed_s, claims_total, licensed }` | LAW |
| `law_license_ok` / `law_license_void` | 本人 | `{}` | LAW |
| `law_bounty_earned` | 本人 | `{ target_name, amount }` | LAW |
| `law_bounty_paid` | 本人 | `{ amount }` | LAW |
| `law_hunter_warn` (ui) | 本人 | 同 `villain_warn` 格式 `{ wid: "law_hunter", npc_name, warn_s }` | LAW |
| `law_cleansed` | 本人 | `{ what, times, cost, killing_intent, pk }` | LAW |
| `cb_bond_request` (ui) | 對方 | `{ from_char, from_name }` | COMBAT |
| `cb_bond_changed` (ui) | 雙方 | `{ partner_name, moqi, peihe, drain_day }`（解除時 partner_name ""） | COMBAT |
| `battle_dodge`、`battle_qing_jump`、`battle_qing_escape`、`battle_qing_fail`、`battle_combo` | 戰鬥 | 見 §3 | COMBAT |
| `ar_intimidated`、`ar_liandu`、`ar_xuemo_enlightened` | 本人 | `{ npc_name, gain }`／`{ gain, mult }`／`{}` | ARTS |
| `ev_jb_started`、`ev_jb_done`、`ev_jb_failed` | 本人 | `{ value, why }` | EVENTS |
| `ev_jb_robbed` | 雙方 | `{ robbers:[name], share }` | EVENTS |
| `tourney_state` (ui) | 報名者與房間 | `{ kind, phase: "SIGNUP"|"RUNNING"|"DONE", entrants, bracket, next_match }` | EVENTS |
| `ev_tourney_call` | 選手、房間 | `{ name, n }` | EVENTS |
| `ev_duel_result` | 房間 | `{ a, b, winner, how: "KO"|"JUDGE"|"FORFEIT" }` | EVENTS |
| `er_spar_not_disciple` | 本人 | `{}` | ERRANDS |

原因碼（模板 `err_<code>`，各 WP 自己的模板前綴）：
- LAW：`bounty_off`、`not_board_npc`、`license_pk`、`license_listed`、`license_deaf`、`license_none`、`bounty_not_listed`、`bounty_pool_min`、`bounty_pool_cap`、`bounty_no_claims`、`cleanse_nothing`、`cleanse_daily`、`not_cleanse_npc`。
- COMBAT：`dodge_off`、`qing_off`、`equip_cooldown`、`combo_need_partner`、`combo_need_party`、`combo_pair_mismatch`、`combo_moqi_low`、`combo_has_partner`、`combo_peihe_low`、`combo_no_request`。
- ARTS：`intimidate_not_xd`、`intimidate_bad_target`、`intimidate_daily`、`liandu_no_tool`、`liandu_not_xh`。
- EVENTS：`jb_no_deposit`、`jb_cooldown`、`jb_active`、`rob_no_escort`、`rob_xp`、`rob_same_party`、`tourney_disabled`、`tourney_closed`、`tourney_signed`、`tourney_not_eligible`、`tourney_running`。
- ERRANDS：`wlt_cooldown`、`wlt_place`。
- 既有沿用：`era_locked`、`not_enough_money`、`not_enough_jing`、`not_enough_shen`、`not_enough_neili`、`no_flee`、`pk_not_allowed_here`、`target_newbie_protected`、`target_busy`、`in_battle`。

快照增量（客戶端缺鍵當 false／空）：角色表 `law: { licensed, listed, claims }`、`combo: { partner_name, moqi, peihe }`、`titles: [String]`；戰鬥快照 `cmd_avail.DODGE`、`cmd_avail.QING`、單位 `dodging`、`duel_left_s`；房間玩家標籤 `tags` 加 `"押鏢"`、`"劫鏢"`、`"懸賞"`、`"盟主"`、門派稱號字串。

---

## 8. 資料、存檔、規則與選項增量（彙總）

### 8.1 存檔（全部增量；舊存檔可讀；T10）

| 位置 | 欄位 | 預設 | WP |
|---|---|---|---|
| 角色 `ext.law` | `{ license: bool, license_s: float, hunt_cd_s: float }` | 無 | LAW |
| 角色 `counters` | `banxian_day: int`、`intimidate: { day, npcs: [] }`、`intimidate_gain: { day, n }`、`qz_gumu_kills: int`、`xuemo_walk_s: float`、`wulintie_day: int`、`xuechi: { day, n: {tier: int} }` | 無 | LAW／ARTS／ERRANDS |
| 角色 `ext.combo` | `{ partner: char_id }` | 無 | COMBAT |
| 角色 `ext.jiebiao` | `{ active: {quest, value, kind, from, to, since_s}, cd: { npc_id: until_s }, rob_until_s }` | 無 | EVENTS |
| 角色 `ext.tourney` | `{ titles: [{ kind, title, until_s }] }` | 無 | EVENTS |
| `world.json` | `bounty: { board: [...], board_s, pools: { char_id: { added, contributors } }, claims: { char_id: [...] }, paid_log: { "a|b": day } }` | 無 | LAW |
| `world.json` | `combo_pairs: { "a|b": { a, b, moqi, peihe, since_day, drain_day } }` | 無 | COMBAT |
| `world.json` | `tourney: { current: {...}, history: [最近 10 場], champions: { kind: char_id }, last_reward_day: { kind: day } }` | 無 | EVENTS |
| 執行期（不存檔） | `Character.pk_decay_on`、`Session.last_equip_ms` | — | LAW／COMBAT |

### 8.2 規則（`data/rule_profiles.json` 與 `DataSchema.RULE_DEFAULTS`／`RULE_ENUMS`；WP-LAW Day-0）

| 規則 | 型別 | RULE_DEFAULTS | classic_strict | classic_standard | later_official | friends_casual |
|---|---|---|---|---|---|---|
| `pk_decay` | bool | true | false | true | true | true |
| `dodge_cmd` | bool | true | true | true | false | true |
| `trade_sell_bonus` | bool | false | 依 F（§6.6） | 依 F | 依 F | 依 F |
| `later_events`（審查第三輪，§13.7） | bool | true | false | true | true | true |

（RULE_DEFAULTS 的 `pk_decay`、`dodge_cmd` 用「開」＝舊自訂組合的行為不變；`trade_sell_bonus` 用「關」＝沒驗證過不會突然改經濟。）

### 8.3 伺服器選項（`data/server_options.default.json`；WP-LAW Day-0；`INT_FIELDS.server_options` 同步；伺服器設定面板加列＝WP-LAW 擁有 `server_options_dialog.gd` 的 M3d 區塊）

| key | 型別 | 預設 | 範圍 | WP |
|---|---|---|---|---|
| `bounty_enabled` | bool | true | — | LAW |
| `bounty_hunters` | bool | true | — | LAW |
| `equip_cooldown_ms` | int | 2000 | 0–5000 | COMBAT |
| `jiebiao_enabled` | bool | true | — | EVENTS |
| `tourney_enabled` | bool | true | — | EVENTS |

### 8.4 Schema（`core/data/data_schema.gd`；WP-LAW Day-0 一次寫完，之後只有 WP-LAW 改）

- `NPC_SERVICES` 加 `BOARD`、`LICENSE`、`CLEANSE`、`TOURNEY`。
- NPC 可選欄位：`deaf: bool`、`cleanse: "KILLING"|"PK"`（lint 檢查 `CLEANSE` 服務必須有 `cleanse`）。
- 武功列可選欄位：`combo: Dictionary`（取代 bool；lint 檢查 `group`、`pair[2]`、`pair[].art` 存在）。
- 道具 `effects[].type` 加 `FLEE_ANYWHERE`、`LIGHT`、`LIANDU`（若 WP-ARTS 選用）、`SUMMON`（只用來標召喚類，給 DUEL 過濾；既有召喚道具由 WP-EVENTS 加這個效果）。
- 任務 `chore.kind`（列舉 `SECT`／`TOWN`）、`chore.decay_all`。
- requirement 型別加：`combo_ready { art }`（COMBAT）、`counter_max { key, value }`（ARTS）、`bounty_listed`、`has_license`（LAW）、`jb_active`（EVENTS）。
- `INT_FIELDS`：`server_options.equip_cooldown_ms`；`monsters` 無新增；`quests.chore.*` 照舊。
- `REFS`：`npcs.shop.items[]` 照舊；`quests.*` 的新 id 照舊。

### 8.5 新資料 id 總表（各 WP 照建；名稱可微調、id 不可改）

- LAW：§2.8 的 NPC；`m_law_hunter_1..3`；模板 `law_*`、`talk_n_law_*`、`rmr_law_caught`、`rmr_law_hunted`。
- COMBAT：`i_cb_laopaoxie`、`i_cb_yemingzhu`、`n_cb_jc_huolang`；武功列 `gm_suxin`（改）、（選做）`hs_chongling`、`hs_fanliangyi`；師父列 `ms_gm_xiaolongnu_suxin`（改）、（選做）`ms_cb_*`。
- ARTS：`q_ar_qz_chongyang`、`q_ar_qz_kongming`、`q_ar_lj_bahuang`、`q_ar_xh_muding`、`q_ar_em_luosha`、`q_ar_xd_xuemo`；`ms_ar_qz_shanju`、`ms_ar_qz_shuliu`、`ms_ar_qz_yunyou`、`ms_ar_qz_wangzhijin`、`ms_ar_lj_lanjian_bahuang`、`ms_ar_guoxiang_sixiang`、`ms_ar_xd_xuemo`；`n_ar_qz_shanju`、`n_ar_qz_shuliu`、`n_ar_qz_yunyou`、`n_ar_qz_wangzhijin`、`n_ar_lj_wuyazi`、`n_ar_ym_shouwei`、`n_ar_guoxiang`、`n_ar_xd_xuechi`、`n_ar_xd_inf_heilong`、`n_ar_xd_baoxiang`、`n_ar_xd_inf_dali`、`n_ar_dingbusan`、`n_ar_dingbusi`、`n_ar_laokelian`、`n_ar_xd_xuemo_laozu`、（選做）`n_ar_em_xinchai`；`m_ar_manbing`、`m_ar_xd_xuechi_1..3`；`i_ar_zhuangyuanhong`、`i_ar_qz_tuijianxin`、`i_ar_xh_muding`、`i_ar_ym_tuijianxin`、`i_ar_luoshajian`、`i_ar_huangyaowan`、`i_ar_xd_daojue`；武功列 `em_sixiang`、`xd_xuemo`（新）、`qz_chongyang`、`qz_kongming`、`lj_bahuang`（改）；門規 `qz_r_kill_gumu`。
- EVENTS：`n_ev_jb_xx`、`n_ev_jb_dl`、`n_ev_jb_jc`、`n_ev_jb_client`、`n_ev_jb_cart`、`n_ev_tourney_clerk`；`m_ev_jb_bandit`、`m_ev_jb_cart`、`m_ev_jb_client`；`q_ev_jb_*`（12 條）；`i_ev_mengzhu_ling`；傳聞 `rmr_ev_*`。
- ERRANDS：`n_er_kezhene`、`n_er_guojing`、`n_er_sanbahong`、`n_er_tiefan`、`n_er_xx_funv`、`n_er_xx_nongfu`、`n_er_dl_zuigui`、`n_er_dl_ahu`、`n_er_dl_qingqing`、`n_er_yinggu`、`n_er_cien`；`m_er_wulin_1..4`、`m_er_jiuwei`、`m_er_yang`、`m_er_baiyuan`；`q_er_kezhene`、`q_er_zhugeyi`、`q_er_biandang_xx`、`q_er_biandang_dl`、`q_er_zuigui`、`q_er_ahu`、`q_er_jiuwei`；`i_er_ke_xin`、`i_er_zgy_baofu`、`i_er_kuanyi`、`i_er_wulintie`、`i_er_shaodaozi`、`i_er_biandang`、`i_er_shuixian`、`i_er_hulixue`；地圖 `heilongtan.json`、region `heilongtan`。

---

## 9. 工作包與檔案所有權

### 9.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-LAW**（也是 Day-0 共用骨架的擁有者） | `core/protocol.gd`；`core/data/data_schema.gd`；`data/rule_profiles.json`；`data/server_options.default.json`；`server/game_host.gd`（`# ==== M3d WP-LAW ====` 區塊：系統欄位、載入、`M3D_INTENTS`、分派函式，§9.2）；`server/region_system.gd`（只有 §9.2 列的單行鉤子）；`server/pk_system.gd`；`core/rules/morality_pk.gd`；`core/character/character.gd` 的 `pk_value()`、`add_pk()`、`pk_decay_on`；新 `core/rules/bounty_rules.gd`、`server/law_system.gd`、`server/intents/intents_law.gd`、`ui/game/law/bounty_dialog.gd`、`ui/game/law/cleanse_dialog.gd`；`ui/game/dialogs/npc_dialog.gd`（§9.2 的其他 WP 區塊除外）；`ui/game/social/server_options_dialog.gd` 的 M3d 區塊；`tools/balance_sim.gd`（Day-0 迴圈與 WP-LAW 區塊）；`tools/data_lint.gd`（Day-0 呼叫行、`NPC_SERVICES`、WP-LAW 區塊）；`data/*.json` 的 `law` 前綴列；新測試 `test_m3d_bounty.gd`、`test_m3d_license.gd`、`test_m3d_hunters.gd`、`test_m3d_pk_decay.gd`、`test_m3d_cleanse.gd`、`test_ui_m3d_board.gd` | §2、§7、§8 |
| **WP-COMBAT** | `core/battle/battle_rules.gd`、`battle.gd`（WP-EVENTS 區塊除外）、`battle_unit.gd`、`battle_cmds.gd`、`battle_grid.gd`、`battle_ai.gd`（如需要）；新 `core/battle/battle_combo.gd`；`core/character/character.gd` 的 `to_combatant()`；`server/combo_system.gd`（新）、`server/intents/intents_combo.gd`（新）、`server/intents/intents_item.gd`（WP-ERRANDS／WP-ARTS 單行鉤子由 WP-COMBAT Day-0 寫好）、`server/intents/intents_battle.gd`；`server/session.gd`（`last_equip_ms`）；`ui/game/ui_keys.gd`（Day-0 寫好所有 M3d 介面常數）；`ui/game/battle/**`（`battle_screen.gd` 的 WP-EVENTS 區塊除外）；`ui/game/main/main_screen.gd`（Day-0 寫好各 WP 的事件分派區塊）；`ui/game/main/lantern_menu.gd`；新 `ui/game/social/combo_dialog.gd`；`ui/game/panels/inventory_panel.gd`（換裝冷卻）；`data/*.json` 的 `cb` 前綴列＋`gm_suxin`、`ms_gm_xiaolongnu_suxin` 兩列；`tools/regen_battle_golden.gd` 的產出（`tests/fixtures/**` 戰鬥金檔，若改變）；新測試 `test_m3d_dodge.gd`、`test_m3d_qing.gd`、`test_m3d_combo.gd`、`test_m3d_flee_shoes.gd`、`test_m3d_equip_cd.gd`、`test_ui_m3d_battle_cmds.gd`、`test_ui_m3d_night.gd` | §3 |
| **WP-ARTS** | `core/character/requirements.gd`（Day-0 寫好各 WP 的分派區塊）；`server/sect_system.gd`（WP-ERRANDS 的切磋區塊除外）；`data/sect_rules.json`；`data/sects.json`（血刀列 `src_note`）；新 `core/rules/arts_rules.gd`、`server/arts_system.gd`、`server/intents/intents_arts.gd`；`data/*.json` 的 `ar` 前綴列＋`qz_chongyang`、`qz_kongming`、`lj_bahuang`、`ms_lj_tonglao_bahuang` 四列；新測試 `test_m3d_chongyang.gd`、`test_m3d_kongming.gd`、`test_m3d_bahuang.gd`、`test_m3d_liandu.gd`、`test_m3d_emei_selfstudy.gd`、`test_m3d_sixiang.gd`、`test_m3d_intimidate.gd`、`test_m3d_xuechi.gd`、`test_m3d_xuemo.gd`、`test_m3d_qz_gumu.gd` | §4 |
| **WP-EVENTS** | `server/battle_system.gd`（Day-0 寫好各 WP 的結算鉤子行）；新 `core/rules/jiebiao_rules.gd`、`core/rules/tourney_rules.gd`、`server/jiebiao_system.gd`、`server/tourney_system.gd`、`server/intents/intents_events.gd`、`ui/game/events/tourney_dialog.gd`、`ui/game/events/jiebiao_confirm.gd`；`core/battle/battle.gd` 的 WP-EVENTS 區塊；`ui/game/battle/battle_screen.gd` 的 WP-EVENTS 區塊；`server/quest_system.gd` 的 WP-EVENTS 區塊；`data/*.json` 的 `ev` 前綴列＋既有召喚類道具的 `effects` 加 `SUMMON`（只加這一項）；新測試 `test_m3d_jiebiao.gd`、`test_m3d_rob.gd`、`test_m3d_tourney_bracket.gd`、`test_m3d_duel.gd`、`test_m3d_tourney_schedule.gd`、`test_ui_m3d_tourney.gd` | §5 |
| **WP-ERRANDS** | `server/quest_system.gd`（WP-EVENTS 區塊除外；接手 M3c2 WP-PACE 區塊）；`data/maps/**`、`data/regions.json`（Day-0 先建 §9.5 的所有房間）；`server/sect_system.gd` 的切磋區塊（`spar_*` 函式）；新 `server/errands_system.gd`（`GameHost.errands`）；`data/npcs.json` 既有 NPC 的 `shop.items` 與 `quests` 陣列（照 §9.6）；`data/*.json` 的 `er` 前綴列＋`q_jc_xiaobao`、`q_ym_douji` 兩列；（選做 F）`server/npc_system.gd` 的具名區塊、`core/econ/econ_calc.gd`；新測試 `test_m3d_chore_town.gd`、`test_m3d_errands.gd`、`test_m3d_heilongtan.gd`、`test_m3d_spar_bug.gd`、（選做）`test_m3d_trade.gd` | §6 |
| **整合者** | `tests/bots/**`；`tests/ui/ui_playthrough.gd`；`tools/*acceptance*`（新 `tools/m3d_acceptance.gd`）；`tests/run_tests.gd`；`README.md`；`docs/CHANGELOG.md`（0.6.2.0 一節）；`docs/ART_REQUEST.md` §12；`docs/GDD.md`、`docs/攻略.md` 等文件同步；`project.godot`（只改 `config/version` → 0.6.2.0）與 `export_presets.cfg`（只改 `file_version`、`product_version`）；本文件 §0.6、§13 | §10、§11 |

### 9.2 共用熱檔的切分（只有這裡列的跨 WP 修改是准許的）

| 檔案 | 擁有者 | 其他 WP 准許的修改（逐字照做，不得多動） |
|---|---|---|
| `server/game_host.gd` | WP-LAW（M3d 區塊） | Day-0 寫好：欄位 `var law; var combo; var arts; var jiebiao; var tourney; var errands`；`const M3D_SYSTEMS := { "law": "res://server/law_system.gd", "combo": "res://server/combo_system.gd", "arts": "res://server/arts_system.gd", "jiebiao": "res://server/jiebiao_system.gd", "tourney": "res://server/tourney_system.gd", "errands": "res://server/errands_system.gd" }`（`ResourceLoader.exists` 才載入）；`const M3D_INTENTS := ["res://server/intents/intents_law.gd", "res://server/intents/intents_combo.gd", "res://server/intents/intents_arts.gd", "res://server/intents/intents_events.gd"]`（存在才註冊）；分派函式 `m3d_enter_room(s, from, to)`、`m3d_battle_settled(s, ch, summary)`、`m3d_pvp_end(summary)`、`m3d_tick(dt)`、`m3d_login(s)`、`m3d_logout(s)`、`m3d_player_tags(viewer, o) -> Dictionary`（合併各系統回傳的 `tags`）、`m3d_char_deleted(char_id)`——每個都用 `m2_call` 依序呼叫六個系統同名方法。**其他 WP 不改這個檔。** |
| `server/region_system.gd` | （無 M3d 擁有者） | WP-LAW：在 `host.sects.on_enter_room(s, to_room)` 下一行加 `host.m3d_enter_room(s, from_room, to_room)   # M3d WP-LAW`；在組房間玩家標籤處合併 `host.m3d_player_tags(viewer, o)`（一行）。 |
| `server/battle_system.gd` | WP-EVENTS | Day-0 寫好：`_settle_player` 結尾加 `host.m3d_battle_settled(s, ch, summary)   # M3d`（一行）；`battle_opts` 加 `"dodge_cmd": bool(host.rules.get("dodge_cmd", true)),   # M3d WP-COMBAT`（一行）；`PVP_KINDS` 加 `"ROB", "DUEL"`。WP-COMBAT 不再改；WP-LAW 的獵人戰用 `start_ex` 既有 API。 |
| `server/pk_system.gd` | WP-LAW | Day-0 寫好：`on_pvp_end` 開頭 `host.m3d_pvp_end(summary)`；接著 `kind == "DUEL"` 直接 return（**在 `_loot_pvp_kills` 之前**：比武不轉移神兵、不加 PK值、殺氣、不廣播）；`kind == "ROB"` 依 `FORCED` 處理（一行 `var as_kind := "FORCED" if kind == "ROB" else kind`）。WP-EVENTS 不改。 |
| `server/sect_system.gd` 的 `req_ctx(s)` | WP-ARTS | Day-0：回傳前合併 `host.m2_call(host.get("law"), "req_ctx", [s], {})` 與 `host.m2_call(host.get("combo"), "req_ctx", [s], {})`（各一行）。LAW 的 ctx 鍵 `bounty_listed: bool`；COMBAT 的 ctx 鍵 `combo: { partner_here: bool, same_party: bool, partner_gender, partner_skills: {art: lv}, partner_sect_skill: int, moqi: int }`。`requirements.gd` 的 `bounty_listed`、`combo_ready` 只讀 ctx（core 不能碰主機）；ctx 沒有這些鍵 → 不成立。 |
| `server/quest_system.gd` | WP-ERRANDS | **WP-EVENTS**：檔尾 `# ==== M3d WP-EVENTS ====` 區塊的函式 `jb_on_accept(s, qid) -> String`（回原因碼或 ""）、`jb_on_fail(s, qid, why)`；WP-ERRANDS Day-0 在 `accept` 流程（requires 通過後、扣物品前）呼叫 `jb_on_accept`，在任務 `fail` 時呼叫 `jb_on_fail`（各一行，行尾 `# M3d WP-EVENTS hook`）。 |
| `server/sect_system.gd` | WP-ARTS | **WP-ERRANDS**：只改 M3c2 WP-PACE 區塊的 `spar_decide`、`_spar_rows`、`spar_adjust`、`_spar_settle`、`_spar_tell` 與新增 `spar_sect(mid)`（放在同一區塊）。 |
| `core/character/requirements.gd` | WP-ARTS | Day-0：`check` 的 `match` 預設分支依序呼叫 `_m3d_law(c, ch, tables, options, rules, ctx)`、`_m3d_combat(...)`、`_m3d_arts(...)`、`_m3d_events(...)`（各回 `"?"` 表示不認得）；四個函式放在檔尾四個具名區塊，WP-LAW／COMBAT／EVENTS 只改自己的那一個函式（`bounty_listed`、`has_license`／`combo_ready`／`jb_active`；WP-ARTS 自己的 `counter_max`）。 |
| `core/character/character.gd` | 分函式 | WP-LAW：`pk_value()`、`add_pk()`、新欄位 `pk_decay_on`；WP-COMBAT：`to_combatant()`。其他 WP 不動（用 `ext`、`counters`）。 |
| `core/battle/battle.gd` | WP-COMBAT | **WP-EVENTS**：檔尾 `# ==== M3d WP-EVENTS ====` 的 `_duel_check() -> bool`（時間到 → 判定、結束戰鬥），以及 WP-COMBAT Day-0 在 `_check_end` 開頭預留的呼叫行 `if opts.has("duel_limit_s") and _duel_check(): return true   # M3d WP-EVENTS`。WP-COMBAT Day-0 也先加 `func time_s() -> float`。 |
| `core/battle/battle_unit.gd` | WP-COMBAT | Day-0 加 `var dmg_dealt := 0`、`var hits_landed := 0`（`resolve_strike` 命中時累計，含反擊與合體一擊）供 WP-EVENTS 判定。 |
| `ui/game/battle/battle_screen.gd` | WP-COMBAT | **WP-EVENTS**：檔尾區塊 `_m3d_events_duel_hud(snapshot)`（擂臺倒數）＋ WP-COMBAT Day-0 在快照更新處預留的呼叫行。 |
| `ui/game/main/main_screen.gd` | WP-COMBAT | Day-0 加事件分派：`_on_event` 對 M3d 事件 key 呼叫 `_m3d_law_event(key, p)`、`_m3d_combat_event`、`_m3d_arts_event`、`_m3d_events_event`、`_m3d_errands_event`（各在檔尾自己的具名區塊，回 bool＝已處理）；各 WP 只改自己的函式（可以 `preload` 自己的對話框）。 |
| `ui/game/dialogs/npc_dialog.gd` | WP-LAW | **WP-EVENTS**：服務 `TOURNEY` 的按鈕處理函式 `_m3d_events_service(svc, npc) -> bool`；**WP-ARTS**：血刀弟子的「恐嚇」選單項 `_m3d_arts_menu(npc) -> Array`；WP-LAW Day-0 預留兩個呼叫行。 |
| `server/intents/intents_item.gd` | WP-COMBAT | Day-0 在 `use_item` 開頭加：`var h = host.m2_call(host.get("errands"), "on_use_item", [s, str(a.get("uid", ""))], {})`、`if h is Dictionary and not h.is_empty(): return h`，以及同樣一行給 `arts`（煉毒）。 |
| `tools/balance_sim.gd` | WP-LAW（Day-0 迴圈） | 每個 WP 在檔尾自己的 `# ==== M3d WP-<名> ====` 區塊寫 `<名>_m3d_cases() -> Array` 與案例函式（名稱以 `law_`、`combat_`/`combo_`、`arts_`、`ev_`、`er_` 開頭）；WP-LAW Day-0 先在 `_initialize()` 加五個 `for c in <名>_m3d_cases(): …` 迴圈與五個回 `[]` 的空函式。 |
| `tools/data_lint.gd` | WP-LAW（Day-0） | 每個 WP 檔尾 `_check_m3d_<名>(tables) -> PackedStringArray`；WP-LAW Day-0 先寫五個空函式與主流程的呼叫行；`NPC_SERVICES` 常數由 WP-LAW 改。 |
| `data/npcs.json` | 依列 | 新列依前綴；既有 NPC 的 `shop.items` 與 `quests` 陣列只有 WP-ERRANDS 改（照 §9.6 的請求表）。 |
| `data/martial_arts.json`、`data/masters.json`、`data/items.json`、`data/monsters.json`、`data/quests.json` | 依列 | 新列依前綴；§9.1 點名的既有列由該 WP 改；WP-EVENTS 只對既有召喚類道具加 `SUMMON` 效果。 |
| `data/text_templates.json` | （無單一擁有者） | **只能追加**（T3），各 WP 用自己的前綴（T6）＋自己原因碼的 `err_*`。不得改他人或既有列。 |
| `ui/game/social/server_options_dialog.gd` | WP-CARRY 的 M3c2 檔 → M3d 由 WP-LAW 加區塊 | WP-LAW：檔尾 `# ==== M3d WP-LAW ====` 一個函式（五個選項列）＋ `_build()` 內一行呼叫。 |

### 9.3 Day-0（各 WP 開工的第一件事；做完就各自往下做，不等別人）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-LAW | `protocol.gd` §7 全部常數與參數表（含 `battle_cmd` 的 `mode` 依 cmd 檢查）；`data_schema.gd` §8.4 全部；`rule_profiles.json` 三條規則、`server_options.default.json` 五個選項；`game_host.gd` 的 M3d 區塊（§9.2）；`region_system.gd` 兩行；`pk_system.gd` 的分派三行；`balance_sim.gd` 與 `data_lint.gd` 的空區塊與呼叫 | 其他 WP 的 intent、事件、原因碼、規則鍵、服務、requirement 型別要先存在，`data_lint` 與註冊才不會報錯 |
| WP-COMBAT | `ui_keys.gd` 的 M3d 常數（服務標籤、圓盤列、指令提示）；`battle.gd` 的 `time_s()` 與 WP-EVENTS 預留呼叫行；`battle_unit.gd` 的 `dmg_dealt`、`hits_landed`；`battle_screen.gd` 與 `main_screen.gd` 的分派預留行與空函式；`intents_item.gd` 的兩行鉤子 | WP-EVENTS、各 WP 的介面要往裡面填 |
| WP-ARTS | `requirements.gd` 的四個分派函式與呼叫；`sect_system.gd` 的 `req_ctx` 兩行合併 | LAW、COMBAT、EVENTS 的 requirement 型別與 ctx |
| WP-EVENTS | `battle_system.gd` 的三處（結算鉤子、`dodge_cmd` 一行、`PVP_KINDS`）；`core/rules/jiebiao_rules.gd` 的 `rob_marked` 簽名（先回 false） | 各 WP 結算鉤子；WP-LAW 守衛判斷 |
| WP-ERRANDS | §9.5 全部新房間（只有房間與出口，NPC 欄位空；`src: "proposal"`）；`quest_system.gd` 的 WP-EVENTS 兩行呼叫與空區塊；先跑 `balance_sim --case=econ_chain` 與 `--case=loot_econ_elite` 存基準 log 到 `K:\Project\JY-Mini-OL-Work\logs\m3d_er_before.log` | 其他 WP 的 NPC 要放在這些房間；F 要前後對照 |

### 9.4 凍結檔（M3d 任何 WP 都不得修改）

`core/battle/battle_formulas.gd`、`core/battle/battle_status.gd`、`core/battle/battle_rewards.gd`、`core/battle/battle_aoe.gd`、`core/battle/encounter.gd`、`core/character/derived_stats.gd`、`core/character/skill_book.gd`、`core/character/learning.gd`、`core/character/foreign_import.gd`、`server/passport.gd`、`server/npc_system.gd`（選做 F 的具名區塊除外）、`server/wander_system.gd`、`server/escort_system.gd`、`server/loot_system.gd`、`autoload/**`、`ui/game/char/**`、`ui/game/title/**`、`data/reactions.json`、`data/loot_tables.json`、`data/escort_routes.json`、`data/life_skills.json`、`data/rumors.json`（傳聞用模板 `rmr_*` 追加到 `text_templates.json`；若傳聞系統只讀 `rumors.json`，寫 `# M3D_PLAN 缺漏` 交整合者）。

### 9.5 新房間（WP-ERRANDS Day-0 建；`src: "proposal"`，`src_note` 寫研究的原位置）

| 房間 id | 名稱 | 檔案 | 接到 | era | 用途（WP） |
|---|---|---|---|---|---|
| `xx_biwu` | 西夏比武場 | `xixia.json` | `xx_street`（方向由 WP-ERRANDS 選空的） | 1.0A | 擂臺（EVENTS）；`safe: true` |
| `xx_biwu_rest` | 比武場休息區 | `xixia.json` | `xx_biwu` | 1.0A | 報名、點名（EVENTS）；`safe: true` |
| `zn_pomiao` | 終南山破廟 | `zhongnan_foot.json` | `zn_road2` | 1.0B | 郭襄（ARTS） |
| `zn_bridge` | 終南山北橋 | `zhongnan_foot.json` | `zn_river` | 1.0B | 郭靖（ERRANDS） |
| `mw_snow` | 馬王洞西雪地 | `mawang.json` | `mw_mouth` | 1.0B | 柯鎮惡（ERRANDS） |
| `dl_fangzhi` | 大理紡織店 | `dali.json` | `dl_square` | 1.0A | 三八紅（ERRANDS） |
| `hl_mud1`…`hl_mud5`、`hl_hut`、`hl_fox`、`hl_slope` | 黑龍潭（迷宮、瑛姑小屋、靈狐、南坡） | 新 `heilongtan.json` | `xe_heilong` | 1.0B | ERRANDS |

1.0B 房間從 1.0A 房間接出去的出口一律帶 `"era": "1.0B"`（同 `ym_gate` 的寫法）。

### 9.6 既有 NPC 的商店與任務陣列（只有 WP-ERRANDS 改；其他 WP 在 Day-0 前就照這張表，不另外提）

| NPC | 欄位 | 追加 | 請求 WP |
|---|---|---|---|
| `n_xx_innkeeper`、`n_dl_innkeeper` | `shop.items` | `i_ar_zhuangyuanhong`（60 兩） | ARTS |
| `n_dl_innkeeper` | `shop.items` | `i_er_shaodaozi`（20 兩） | ERRANDS |
| `n_xx_zhugeyi` | `quests` | `q_er_zhugeyi` | ERRANDS |
| `n_xh_chuchenzi` | `quests` | `q_ar_xh_muding` | ARTS |
| `n_xd_laozu` | `quests` | `q_ar_xd_xuemo` | ARTS |
| `n_lj_tonglao` | `quests` | `q_ar_lj_bahuang` | ARTS |
| `n_dl_furen` | `quests` | `q_er_biandang_dl` | ERRANDS |

（武器店有沒有賣 `w_lt_fuchen`：WP-ARTS 開工時查；沒有就由 WP-ERRANDS 加到大理或西夏的兵器鋪 `shop.items`，WP-ARTS 在交付說明註記。）

---

## 10. 測試計畫

### 10.1 各 WP 的單元與整合測試（全部在 `tests/run_tests.gd` 裡跑，`--filter=m3d` 可單跑）

- **WP-LAW**：`test_m3d_bounty.gd`（上榜：PK 4、PK 1＋惡、新手不上、統計時點；合法緝拿：PK值不加、善惡不變、殺氣 +20、傳聞；非法：照惡意 PK；懸賞金從目標身上與錢莊扣、不夠就少；加碼、上限；同隊／同組織不給；同日重複不給；領賞）；`test_m3d_license.gd`（PK>0 不能領、上榜不能領、錢不夠、耳聾官爺、PK>0 自動失效）；`test_m3d_hunters.gd`（只在 WILD、冷卻、三階分級、死了 PK −1、選項關、新手不追）；`test_m3d_pk_decay.gd`（規則開關兩種、負數下限 0、守衛殺 PK −1）；`test_m3d_cleanse.gd`（天師次數截斷、錢、殺氣不足；半仙每日一點、era 1.0B）；`test_ui_m3d_board.gd`（名單視窗、領賞按鈕）。
- **WP-COMBAT**：`test_m3d_dodge.gd`（命中率下降量、不反擊、下次行動清除、規則關）；`test_m3d_qing.gd`（JUMP 越過敵人、範圍 +1、內力；ESCAPE 機率邊界、no_flee 種類、追擊戰可以、ROB side 0 不行、規則關）；`test_m3d_combo.gd`（建立、同意、拒絕、取消、培養感情、兩日扣點只在兩人同時在線、學素心劍的條件逐條、戰鬥中 3 秒窗內觸發與窗外不觸發、成功率邊界、配合度增加）；`test_m3d_flee_shoes.gd`（任何格可逃、追擊戰可、QUEST/TRIAL 不可、ROB side 0 不可）；`test_m3d_equip_cd.gd`（地圖 2 秒、戰鬥 2 秒、選項 0 關）；`test_ui_m3d_battle_cmds.gd`（閃、輕的圓盤狀態與提示）；`test_ui_m3d_night.gd`（夜晚變暗、有夜明珠不變暗、設定關）。
- **WP-ARTS**：每條鏈一個測試（`chongyang`、`kongming`、`bahuang`、`sixiang`、`xuemo`：條件不足被拒、逐步完成、師父 cap、自修上限、1.0A 視圖不可接）；`test_m3d_liandu.gd`（倍率三種、精不足、沒鼎、非星宿）；`test_m3d_emei_selfstudy.gd`；`test_m3d_intimidate.gd`（對象限制、每日一次、每日上限 200、善惡、精神）；`test_m3d_xuechi.gd`（三階、每日 3 次、無死亡懲罰）；`test_m3d_qz_gumu.gd`（殺氣 ×2、計數、門規 11 人觸發、坐牢後計數不歸零）。
- **WP-EVENTS**：`test_m3d_jiebiao.gd`（條件、押金、成功 2 倍、冷卻、失敗五種、特殊地雷、標籤、丐幫不行）；`test_m3d_rob.gd`（劫鏢條件、標記開戰即給、side 0 不能逃、80% 平分、劫鏢算強制 PK、守城官兵追殺）；`test_m3d_tourney_bracket.gd`（2–17 人的對戰表、輪空、冠軍種子、可重現）；`test_m3d_duel.gd`（無死亡懲罰、戰後補滿、門技不觸發、召喚道具拿掉、時間到判定三層、逃＝棄權）；`test_m3d_tourney_schedule.gd`（日曆、主機開辦、表演賽條件、30 日獎勵冷卻、稱號到期與收回）；`test_ui_m3d_tourney.gd`。
- **WP-ERRANDS**：`test_m3d_chore_town.gd`（`TOWN` 不受新手期、`decay_all`、M3c2 `SECT` 行為不變）；`test_m3d_errands.gd`（柯鎮惡門檻與遞減、三八紅客氣／粗話、武林帖冷卻與分級）；`test_m3d_heilongtan.gd`（迷宮走法、靈狐戰、意外收獲擲骰可重現、羊與白猿扣善惡）；`test_m3d_spar_bug.gd`（無門派 0、他派 0、本派有、`q_hs_kaoyan` 照樣完成、不計每日場數）；（選做）`test_m3d_trade.gd`。

### 10.2 平衡（`tools/balance_sim.gd`）

既有案例全過（§0.6），加：
- WP-LAW：`law_hunter_tiers`（§2.5 的勝率帶）、`law_bounty_zero_sum`（朋友互殺互加碼 1000 次，兩人合計銀兩不增）。
- WP-COMBAT：`combat_dodge`（閃的人被命中率下降 15–30 個百分點）、`combat_qing_escape`（逃離率帶 20–80%）、`combo_suxin`（合體 +10–25% 總傷害）。
- WP-ARTS：`arts_chongyang_power`（同等級重陽劍法對全真劍法的出力 1.1–1.5 倍）、`arts_xuemo_power`（血魔刀法 70 對血刀刀法 70 的期望傷害 0.9–1.3 倍，研究：剛開時較弱）、`arts_sixiang_power`。
- WP-EVENTS：`ev_jb_zero_sum`、`ev_jb_income`（§5.2.4）、`ev_duel_judge`（判定公平：同屬性兩人 500 場勝率 45–55%）。
- WP-ERRANDS：`er_town_lp_cap`（§6.1）、（選做）`er_trade_band`。

### 10.3 驗收：`tools/m3d_acceptance.gd`（整合者；`--only=<劇本>`；全部用測試根目錄下的新世界；兩個角色的劇本用兩個本機 session，同 `m2_acceptance` 的做法）

| 劇本 | 內容 | 通過條件 |
|---|---|---|
| `bounty` | A（實戰 3 萬）強制 PK 殺四個人（用除錯工具造對手）→ 撥到下個時辰 → 西夏佈告欄名單有 A、金額 4000；B（PK 0）找耳聾官爺 → `license_deaf`；找另一位領照 → 強制 PK A 並殺死 → B 的 PK值 0、善惡不變、A 的 PK值 3、A 的錢少了 4000（或身上＋錢莊的全部）→ B 回官爺領賞 +4000；B 再殺 A 同一天 → 沒有懸賞 | 數值相符 |
| `bounty_friends` | B 與 A 同隊 → 緝殺 → `law_no_bounty_friend`；C 加碼 5000 給 A → D 緝殺 → D 得 A 的罰金＋5000 | 相符 |
| `hunters` | A 在名單上走野外 20 間房（固定種子）→ 至少一次 `law_hunter_warn` → 不走、開打、輸 → PK值 −1；穿烙跑鞋再遇一次 → 逃走成功 | 相符 |
| `cleanse` | 殺氣 95 的角色找西夏天師消 10 次 → 只消 9 次、扣 900 兩；1.0B 世界 PK 2 找半仙 → PK 1、扣 10000；同日再找 → `cleanse_daily` | 相符 |
| `pk_decay` | `classic_strict` 世界 PK 2 的角色上線 2 小時 → 仍 2；`classic_standard` → 0 | 相符 |
| `dodge_qing` | 新角色對木樁怪：閃 → 下一擊命中率統計（用 BattleRules 直接跑 2000 次）下降 ∈ [0.15, 0.30]；`later_battle_cmds` 開時 QING JUMP 越過敵人、ESCAPE 統計率相符 | 相符 |
| `combo` | 1.0B 世界男全真（全真劍法 60、養生 30）＋女古墓（玉女劍法 60、清心 30）：建立默契 → 默契 0 學素心劍被拒（`combo_moqi_low`）→ 除錯設默契 20 → 組隊同房找小龍女 → 學到 → 一起打怪，兩人在 3 秒內各出一招 → 至少一次 `battle_combo`（固定種子）→ 配合度增加 | 相符 |
| `equip_cd` | 連按兩次換武器間隔 1 秒 → 第二次 `equip_cooldown`；2.1 秒 → 成功 | 相符 |
| `night` | 撥到戌時：截圖地圖區變暗；給夜明珠 → 不變暗（截圖存 `shots\m3d_night_*.png`） | 相符 |
| `arts_chains` | 用 `story_acceptance` 的方式跑 `q_ar_*` 六條的 `test_plan`（含 1.0A 視圖下 1.0B 鏈不出現） | 全部完成 |
| `intimidate` | 血刀弟子恐嚇 3 個不同 NPC → 威嚇熟練 +60、善惡 −30；同一個 NPC 再一次 → `intimidate_daily` | 相符 |
| `qz_gumu` | 全真弟子殺 11 個古墓 NPC 弟子（除錯開戰）→ 第 11 個後門規觸發（`classic_standard` → 坐牢） | 相符 |
| `jiebiao` | 實戰 10 萬角色在西夏接送貨鏢（扣 3200）→ 走到大理 → +6400；再接 → 冷卻中 `jb_cooldown`；改大理二掌櫃接護送鏢 → 遇特殊地雷時逃 → 失敗、押金沒了 | 相符 |
| `rob` | A 押鏢、B 劫鏢：B 標記立即存在；B 逃 → `no_flee`；B 殺掉鏢車 → B 得 2560、A 失敗、B 的 PK值 +1；B 進西夏 → 官兵 2 名 | 相符 |
| `tourney` | 主機開辦 WULIN（報名 60 秒）→ 5 個角色報名 → 對戰表（輪空 3）→ 一位不在場被點名 3 次判負 → 其餘打完 → 冠軍有「武林盟主」、盟主令牌、名聲 +3000；全服傳聞；所有人沒有死亡懲罰；馬上再開一次 → 表演賽、沒獎勵 | 相符 |
| `sect_tourney` | 4 位少林弟子門派比武 → 冠軍「少林派掌門師兄」、名聲 +1000、歷練 +800 | 相符 |
| `errands` | 名聲歷練 500 的角色跑柯鎮惡→郭靖 7 次（同一天）→ 名聲合計 +5+5+4+3+2+1+0；豬哥義→三八紅（先粗話被拒、再客氣）→ +200 兩、+8 名聲；武林帖：用一張 → 開打、贏 → 再用 → `wlt_cooldown`、帖子還在 | 相符 |
| `town_lp` | 午時送便當 3 次 → 學點 50、30、15；酒鬼拒絕 → −40 兩；阿虎 → +50 學點 +300 兩；李大嬸（實戰 500）→ +200 兩 +10 學點 | 相符 |
| `heilongtan` | 1.0B 世界：從 `xe_heilong` 進迷宮、照提示走到瑛姑 → 接九尾靈狐 → 打贏 → 交 → 學點 +100；南坡打一群羊 → 善惡下降；1.0A 世界 `xe_heilong` 沒有往南的出口 | 相符 |
| `spar_bug` | 沒門派的角色打贏陸大有 → 實戰學點 0、`q_hs_kaoyan` 完成；入華山後再打 → 有獎勵 | 相符 |

### 10.4 介面驗收（`tests/ui/ui_playthrough.gd`，整合者加步驟；截圖 `K:\Project\JY-Mini-OL-Work\shots\`）

佈告欄名單視窗與領賞；官爺（耳聾）對話；天師數量選擇；戰鬥圓盤的「閃」「輕」與提示；默契視窗；夜晚變暗；比武報名視窗與擂臺倒數；押鏢標籤；新 NPC 的對話與任務清單。headless 與有視窗各一次，0 警告。

### 10.5 回歸（全部要綠，整合者驗收時逐一跑）

`tests/run_tests.gd`（0 failed）、`tools/data_lint.gd`（0 錯誤，含 1.0A-only 視圖）、`tools/balance_sim.gd --runs=500`、`tests/ui/ui_playthrough.gd`（headless＋有視窗）、M1 驗收 bot（測試根目錄的新世界）、`tools/m2_acceptance.gd`、`tools/m3a_acceptance.gd`、`tools/m3b_acceptance.gd`、`tools/m3c_acceptance.gd`、`tools/m3c2_acceptance.gd`、`tools/m3d_acceptance.gd`、`tools/story_acceptance.gd --all`、`tools/net_smoke.gd`、`close_mid_battle_bot`（`--close-mode=wm` 與 `quit`）。WASD 與自動走路測試（`test_ui_wasd_move`、`test_autowalk_view_first`）必須在。每次跑完 `tasklist /FI "IMAGENAME eq Godot*"` 確認沒有殘留。

---

## 11. 交付與整合

1. 每個 WP 交付說明：改了哪些檔（對照 §9.1）、新 id 清單、校準後的數字（§10.2 各案例的結果）、因本包而改的既有測試（逐一列出原因）、`# M3D_PLAN 缺漏` 清單、戰鬥金檔差異（若有）、**沒有美術的新 NPC／怪物／道具清單**（給 ART_REQUEST §12）。
2. 整合者：合併 → `--import` → §10.5 全部 → 填 §0.6 與 §13 → README（懸賞與執照、天師與半仙、閃與輕、合體技、烙跑鞋與夜明珠、換裝間隔、新武功鏈、劫鏢、比武、跑腿、黑龍潭、PK值 規則）→ `docs/攻略.md` 同步 → `docs/CHANGELOG.md` 0.6.2.0 → `docs/ART_REQUEST.md` §12（M3d，下面的清單，照 §0 的風格說明寫 ChatGPT 提示）→ `project.godot` 與 `export_presets.cfg` 版本 0.6.2.0 → `export_release.ps1` 匯出（**不碰** `JY-Mini-OL-Release\userdata\`，匯出前後雜湊比對照舊）。
3. 版本：0.6.2.0；連線協定 5；資料指紋會改變 → 朋友要一起更新。
4. **ART_REQUEST §12（M3d）預定清單**（新 NPC 先用既有的程序化／後備圖）：
   - NPC 立繪：官爺（兩位，一胖一瘦、其中一位掏耳朵）、天師、京城半仙、西域貨郎、山居隱士、漱流隱士、雲遊道士、王志謹、無涯子、郭襄、雁門關守衛、血池師兄、寶象、丁不三、丁不四、老可憐、血魔老祖、鏢局二掌櫃、比武報名員、柯鎮惡（盲眼、鐵杖）、郭靖、三八紅、武林帖販子、送便當的婦人、田邊農夫、醉鬼、阿虎、青青、瑛姑、慈恩。
   - 怪物：賞金獵人、捕頭、神捕、蠻兵、血池弟子（三階可共用一張換色）、劫鏢山賊、鏢車、客商、武林人士（四階共用）、九尾靈狐、羊、白猿（沙漠）。
   - 物件與道具圖示：佈告欄（地圖物件）、無敵烙跑鞋、夜明珠、盟主令牌、小木鼎、刀訣、羅煞劍。
   - 戰鬥背景：黑龍潭泥沼、比武場擂臺。

---

## 12. 開放問題（不擋開工；預設值已選）

| # | 問題 | 預設 |
|---|---|---|
| Q1 | 上名單的門檻（PK值／善惡）與金額 | R1、R2【設計提案】 |
| Q2 | 賞金獵人是 NPC、玩家還是都有 | 都有（玩家持照、NPC 追捕）【設計提案】 |
| Q3 | 持照緝殺是否降目標 PK值 | −1（推論）【設計提案】 |
| Q4 | 半仙價錢；1.0A 大理／西夏有沒有減 PK 的半仙 | 只做京城 1.0B；每點 1 萬、每日 1 點 |
| Q5 | 閃與輕的數字 | §3.1、§3.2【設計提案】 |
| Q6 | 合體技的加成公式、成功率、配合度增減、門檻 | §3.3【設計提案】 |
| Q7 | 烙跑鞋與夜明珠的來源與價錢 | R11 |
| Q8 | 劫鏢門檻是 ≥ 還是 >；劫鏢有沒有 PK值 | ≥；有（R15） |
| Q9 | 柯鎮惡的 500 門檻是否其實是二袋門檻 | 照 2001-12-03 用 500【待考證】 |
| Q10 | 煉毒的「特定狀況」 | 夜、星宿地區、中毒（§4.4）【設計提案】 |
| Q11 | 威嚇戰鬥效果（削弱敵攻 vs 重擊） | 維持重擊（R13） |
| Q12 | 全真殺古墓計數算不算玩家、會不會消 | 算、不消【待考證】 |
| Q13 | 1.0 的「休」只補氣還是也補內力 | 不改程式（現行補氣與內力）；文件標【待考證】 |
| Q14 | 九尾靈狐的抓法與獎勵 | §6.4【設計提案】 |
| Q15 | 交易之道的公式 | ×(1 + 等級/300)，只有平衡通過才開（R20） |

## 13. 整合紀錄（整合者填）

（整合者 2026-10-21；版本 0.7.0.0 開發中，`Protocol.VERSION` 維持 5，資料指紋改變。）

**13.1 整合者的修改（跨 WP 的接縫）**

| # | 修改 | 檔案 |
|---|---|---|
| I1 | `data_lint`：效果 `LIANDU` 算「可使用」（小木鼎要有「使用」鈕）；門派 NPC 前綴另外接受 `n_ar_<派前綴>_`（WP-ARTS 武功鏈 NPC） | `tools/data_lint.gd` |
| I2 | `test_data_content`：1.0B 白名單加 WP-LAW 京城列、WP-COMBAT `cb`、WP-ARTS 1.0B 鏈、WP-EVENTS `ev_jb`；1.0A 列數 items +8、monsters +7、quests +6、npcs +18（逐列對過） | `tests/unit/test_data_content.gd` |
| I3 | 8 位 `n_ar_*` 故事 NPC 的夜間對白；`ar_xuechi_won` 的 `{left}` 改 `{count}`（佔位字白名單），事件同時帶 `left` 與 `count` | `data/text_templates.json`、`server/arts_system.gd` |
| I4 | 角色刪除呼叫 `host.m3d_char_deleted(char_id)`（WP-LAW 缺漏 1） | `server/intents/intents_char.gd` |
| I5 | 五個 M3d 伺服器選項加進 `AdminSystem.EDITABLE_KEYS`（選項、目前值、套用；換裝間隔 0／1000／2000／3000／5000）——面板不再是灰的（WP-LAW 缺漏 2）；`test_world_admin` 計數 13 → 18、加一個 M3d 選項測試 | `server/admin_system.gd`、`tests/unit/test_world_admin.gd` |
| I6 | 系統窗「特殊開關」加「夜晚變暗」（`ui.night_dim`，預設開；WP-COMBAT 缺漏 3） | `ui/game/panels/system_panel.gd`、`ui/common/ui_settings.gd` |
| I7 | 玩家選單「劫鏢」（對方 `tags` 有「押鏢」、不同隊）→ `m3d_events_open_rob`；房間玩家列在名字後畫 `tags`（〔押鏢〕〔懸賞〕…） | `ui/game/social/ui_social.gd`、`ui/game/main/main_screen.gd`、`ui/game/main/scene_panel.gd` |
| I8 | `Requirements.describe("jb_active", value:false)` →「沒有進行中的危險鏢」 | `core/character/requirements.gd` |
| I9 | `m3c_acceptance --only=equip8`：劇本內暫時把 `equip_cooldown_ms` 設 0（它驗八格，不驗冷卻；冷卻由 `m3d_acceptance equip_cd` 驗） | `tools/m3c_acceptance.gd` |
| I10 | 懸賞名單每時辰統計時，**名單沒變就不重送房間視圖**：原本每個時辰把所有人的 `view_dirty` 設起來，介面驗收在恆山點「定閒師太」時按鈕正好被重建、點擊落空（第 16 步，兩次都重現） | `server/law_system.gd` |
| I11 | 介面驗收：換裝兩秒間隔（R9 全域）→ 連續換裝前等滿 2 秒；新增第 23 步（M3d 畫面，§10.4） | `tests/ui/ui_playthrough.gd` |
| I12 | `tools/m3d_acceptance.gd`（協調器，同 m3c2 的 worker 作法）＋`tools/m3d_accept_scenarios.gd`（20 個劇本；沿用整合測試的世界夾具，兩個以上角色用遠端 session）；`arts_chains` 另呼叫 `story_acceptance --chain=` | 新檔 |

**13.2 採納的偏差（建造者寫 `# M3D_PLAN 缺漏` 的，整合者照實作改本文件的理解）**

- WP-LAW：賞金獵人數值校準成氣 940／2400／2900、技能 40／76／94（計畫的數值勝率 0%）；第 3 階的鏈子槍當鞭；耳聾官爺對每一種請求都聽錯；天師只消完整的 10 點；合法緝拿以戰鬥 id 記在 LawSystem（PvP 結算沒有 opts）。
- WP-COMBAT：合體加成 **0.4**（計畫 0.5 量到 +25.1% 超出帶）；`combo_ready` 由 ComboSystem 每秒更新一份角色上下文（師父判定不帶 ctx）；合體次數在結算時讀戰鬥單位的 `combo_with`，只算角色 id 較小的一方；原因碼用 `dodge_off`／`qing_off`（§7），不是 §3.1 的 `cmd_disabled`；`gm_suxin` 的 tier 改 SPECIAL（QUEST 要 quest_flag）；兩件新道具 rarity FINE；沒有 `equip_cd_ms` 的舊戰鬥規格不限制（金檔不變）。B8（沖靈劍法／反兩儀刀法）沒做：資料沒有華山刀法。
- WP-ARTS：重陽劍法、四象掌的 `self_study_until` 設 0（不然 `Learning.check_master` 擋住低級的師父），重陽劍法改用 `requires` 的 `any_of` 分段；血池三階是三個 NPC；`battle_system` 沒有 `opts.spar` → 血池輸了照常死亡懲罰，以弱攻擊的陪練怪緩和（測試鎖住每下 < 10% 氣）；小木鼎任務改收蛇膽 ×2、蠍尾 ×1；羅煞劍：最大內力 300 → 基本內功 60、「三人以上」→ 三人隊伍或實戰 30 萬、喝酒 根骨 ≥ 20、`cap_reached` 實際是 `cap_master`；老可憐放在京城鏢局。C5 的峨嵋信差（選做）沒做。
- WP-EVENTS：沒有任何道具有召喚效果（`SUMMON` 過濾留著）；鏢車用機敏 1、力 1 近似「不動」；劫鏢的 PK值 +1 在戰鬥結束時給每個劫鏢者（殺了押鏢者的人已由 PkSystem 加過就不重複）；部分模板佔位字改名（`{label}` 等），payload 照計畫的欄位一起送；DUEL 不經 PkSystem（不轉神兵、不加 PK）；斷線＝立即棄權。
- WP-ERRANDS：`zn_pomiao`、`zn_bridge` 在 1.0A 世界是空房間（地圖只能整張切 era）；`dl_fangzhi` 用 進／出；武林帖帶一個不會執行的 restore 1 效果（lint 只准可使用的道具有效果）；九尾靈狐用一般 AI（逃跑 AI 打贏也抓不到）；羊群固定 4 隻 × −25；九花玉露丸不存在 → 那 20% 加成略過。

**13.3 擁有者決定（建造者選的預設值，整合者照收；全部【設計提案】）**

- LAW：作廢的執照留著待領賞金，重新領照後可以領；不能替自己加碼（`self_target`）；剛上榜通知 `law_listed`；被賞金獵人或官兵殺死 PK −1，被拉進戰鬥的隊友也算。
- COMBAT：閃 Shift+4、輕 Shift+5；合體加成 0.4；烙跑鞋 50,000、夜明珠 20,000 由京城西域貨郎賣；夜晚小地圖的霧是目前房間＋相鄰房間的方框。
- ARTS：煉毒 精 15、熟練 20 ×（夜 1.5、星宿 1.5、中毒 2）；恐嚇 精 20、神 20、善惡 −10、威嚇 +20，與血池共用每日 200 上限；血池每勝 +30／+60／+100、每階每日 3 次；殺古墓額外殺氣＝原本的量（最少 5）；血魔刀訣的兩個時辰離開房間就暫停；狀元紅 1.0A。
- EVENTS：劫鏢山賊氣 1200（其餘數值調低：原數值實戰 10 萬打 3–4 個全輸）；比武報名員、比武場、盟主令牌 1.0A 標【後期版】；門派稱號顯示時檢查（叛派自動失效）；比武視窗只列武林大會、本派、自己報名的與進行中的；血刀門的叫「血刀門比武」；地雷劫匪不掉錢。
- ERRANDS：便當 100／60／30／10／0、酒鬼 100／100／60／30／0（冷卻 ¼ 遊戲日）、鬥酒 [100, 0]、豬哥義冷卻 ½ 遊戲日；便當只能午時接；武林帖 1000 兩、四階對手約 1.2 萬／6 萬／20 萬／60 萬實戰、本身不給實戰學點、不拉隊友；黑龍潭的解法寫在石碑、慈恩講方位、夜明珠在接任務時擲；西夏農夫在 `hf_paddy`、青青在 `dlw_river`、比武場在西大街東北。
- 整合者：M3d 選項全部開放在伺服器設定面板（含換裝間隔的五個值）；懸賞名單沒變就不重送視圖（I10）。

**13.4 驗收結果（整合者，2026-10-21；log 在 `K:\Project\JY-Mini-OL-Work\logs\m3d_int\`）**

見交付說明與 README「M3d」。`tools/run_tests.gd` 1929 tests 0 failed；`data_lint` 0 錯誤（15 個 era 視圖）；`m3d_acceptance` 20／20；M1 bot、m2、m3a、m3b、m3c、m3c2 驗收、`story_acceptance --all`（128 jobs）、`net_smoke`、`close_mid_battle_bot`（wm／quit）全綠；
介面驗收 headless＋有視窗（`--ui-shots=K:\Project\JY-Mini-OL-Work\shots\m3d\integrate`，第 23 步 13 張 M3d 截圖已看過）；`balance_sim --runs=500`：**155 個案例全部 ok、0 FAIL**（`BALANCE OK`；log `balance.log`）。M3d 案例：`law_hunter_tiers` 勝率 56.0／41.6／45.4%、`law_bounty_zero_sum` 淨 −100（執照費）、
`combat_dodge` −15.4／−19.6／−19.4 個百分點、`combat_qing_escape` 20／20／34／42.8／81%、`combo_suxin` +20.8%、`arts_chongyang_power` 1.23、`arts_xuemo_power` 1.02、`arts_sixiang_power` 0.95、
`ev_jb_zero_sum` −978,358、`ev_jb_income` 1.38、`ev_duel_judge` 47.2%、`er_town_lp_cap` 學點 254／600；M3c2 的 `pace_<派>` 中位數不變（少林 3.17 … 丐幫 3.69）。
**F（交易之道）沒做**：規則 `trade_sell_bonus` 維持關（R20：沒有 `balance_sim` 證明）。

**13.5 審查第一輪修正（2026-10-21；log 在 `K:\Project\JY-Mini-OL-Work\logs\m3d_fix1\`）**

- 素心劍：學習不看默契（`moqi_min` 0；默契只能靠合體一擊累積，原本這條鏈開不了頭）；合體武功要夥伴同場才能出（`combo_partner_absent`，官方「兩人同使」），AI 也不選；成功率 0.20 ＋ 默契 × 0.0035、上限 0.55；驗收拿掉除錯寫默契。
- 懸賞：只有真的發了賞金才 PK −1（朋友、同日不減）；PK 降到不夠格立刻下榜（緝拿、半仙、守衛、獵人）；合法緝拿與 NPC 獵人看當下 PK（`listed_live`）；獵人戰只有被追的人 −1；`paid_log` 換時辰只留今天、刪角色清 `claims`／`paid_log`。
- 劫鏢：同房隊友只拉實戰 ≥ 10 萬（也就過了新手保護）、沒有執照的（`start_pvp` 的 `pull_min_xp`、`pull_skip_chars`）。
- 比武：獎勵另加現實 30 日冷卻（`tourney_reward_cooldown_real_days`）；武林大會名聲 3000／2000／1200／1200／300×4；當機後 `match.bid` 要對得上 `opts.tourney`；合體請求還沒過期不能再送（`combo_request_pending`）。
- 煉毒每遊戲日熟練上限 200（`liandu_daily`）；空明拳招式威力 38／52／66 → 34／46／58；`qz_r_kill_gumu` src later；§0.6 案例數更正為 143。
- 介面：懸賞名單、消災視窗進主畫面視窗清單（Esc 關）；獵人橫幅放在視窗底下、甩掉／開打就收、只有一條倒數；「默契」燈籠 60 px；比武報名列出表頭那一場並寫原因（「限○○弟子」「報名已截止」）、日曆改「第 N 日（還有 N 日）」、對戰表高度跟行數；空名單收起捲動框；消災按鈕寫灰掉原因；八卦泥陣出口一律寫「八卦泥陣」（`hide_exit_names`）；合體金字放在所有單位頭上（放不下放腳下）；「閃避」青色大字＋腳下青色菱形；「醉鬼的燒刀子酒」；默契視窗「（戰鬥中）」；執照說明改寫。
- 新平衡案例：`combo_suxin` 默契 50 +16.0%、100 +20.6%；`arts_kongming_power` 1.42；`ev_tourney_farm` 每人每現實日 70 名聲（舊規則 150／900；正常跑腿 80／480）；`pace_town_<派>`（每遊戲日白拿 TOWN 學點上限 254，1.0B，每派 20 輪）中位數 3.13–3.75 小時，全在 M3c2 帶內（少林雜務佔比不把城鎮學點算進分母）。
- 結果：`balance_sim --runs=500` 168 個案例（全跑 167 ok；唯一的 `pace_town_shaolin` 是佔比分母，修正後單跑 ok）；`m3d_acceptance` 20／20；`data_lint` 0 錯誤；m3c2、m3c、m3b、m3a、m2、story --all、net_smoke、M1 bot、介面驗收 headless＋視窗、close_mid_battle wm／quit 全過。
  `run_tests` 1940 個中 6 個世界地圖測試失敗，原因是驗收進行中別的流程在 16:42 加入的 `assets/art/map/`（`map_world_base.png` 等）與 `data/art.json`，不是這一輪的修改。

**13.6 審查第三輪修正（2026-10-21；log 在 `K:\Project\JY-Mini-OL-Work\logs\m3d_fix3\`）**

- 素心劍（忠於原作）：`combo.moqi_min` 0 → **10**；`src_note` 改引官方原文（「待到默契值與心性修為都達到一定程度後方可修練」），拿掉錯引的「研究：學習沒有默契條件」。
  官方只寫合體一擊加配合度 → 兩人同一邊一起打贏一場（不是 DUEL／ROB、有打倒對手）配合度 +10、每對每遊戲日最多 60（`ComboSystem.JOINT_PEIHE`／`JOINT_PEIHE_DAY_CAP`）【設計提案・非原作】；
  `battle_summary` 帶 `allies`（同邊其他玩家）與 `foes_killed`（戰鬥結束時已從 `active` 移除，tick 不一定記到）。驗收 `combo`：默契 0 被拒 → 一起打贏 28 場、4 遊戲日 → 默契 10 → 兩人學到。
- 素心劍（平衡）：`ComboRules.usable`／合體一擊改用 `partner_for_art`——夥伴也要會這門武功、兩人性別配得上 `combo.pair`（官方 jy1-2-6-1「雙方都學合體武功」）；招式威力 50／70 → **42／56**（耗內 20／28）。
  新案例 `arts_suxin_power`（對全真劍法 1.32）、`arts_suxin_power_gm`（對玉女劍法 1.30），帶 1.1–1.5；`combo_suxin` 默契 50 +16.9%、100 +21.4%。
- 比武報名條件（`TourneyRules.entry_reason`）：武林大會 實戰 ≥ 10,000、PK值 0【設計提案：2002「報名員武功測驗」】；門派比武 實戰 ≥ 1000，恆山 4000＋善惡 200＋門技 10＋PK值 0、全真 4000＋善惡 200＋門技 30（2002 的 20 萬照 R12 ÷50）、少林 PK值 0【後期版】；丐幫「二袋以上」沒有對應規則【待考證】。
  開打時與每場點名時重查（叛派、有了 PK值 → 當作棄權，`ev_tourney_disqualified`）；原因碼 `tourney_need_xp`／`tourney_has_pk`／`tourney_need_morality`／`tourney_need_sect_skill`；`tourney_state.entry` 給介面灰鈕與「需…」。
  `tourney_withdraw` 改 `CI`（比武中要棄權就逃）。檔頭名聲註解更正為 3000／2000／1200×2／300×4。
- 賞金獵人：`BountyRules.apply_hunter_xp`——依被追的人的實戰決定數值（三列 `combat_xp_ref` 之間照 √實戰 內插；低於 2 萬、高於 20 萬照武學上限比例外推，往下再 ^1.15）；`LawSystem.start_hunt` 帶 `hunter_xp`，`BattleSystem.start_ex` 套用。
  `law_hunter_tiers` 補底端、中段與 50 萬、100 萬：目標方勝率 500 實戰 69.6%、5000 30.6%、19,999 56.0%、20,001 56.0%、5 萬 37.4%、10 萬 33.2%、20 萬 45.4%、50 萬 23.0%、100 萬 26.6%（帶 20–70%；頂端照原帶）。
- 換裝兩秒只在 1.0B 世界（n323 在 1.0B 之後）：`IntentsItem.equip_cooldown_ms` 1.0A-only 回 0，戰鬥規格同值；`world_info.equip_cooldown_ms` 帶實際值（介面冷卻跟著）。
- T9：新案例 `er_repeat_cap`——TOWN 做到底＋九尾靈狐＋武林帖平均每遊戲日 學點 287.3（≤ 600）、名聲 58.7（≤ 80）、歷練 149.7（≤ 400）、九尾夜明珠賣店期望 100 兩（≤ 500）【設計提案】。
- 劫鏢：押著危險鏢不能 `rob_escort`（`jb_active`）；`on_rob_end` 讓劫鏢戰裡死亡／逃走的其他玩家自己的危險鏢失敗。
- 武林帖：開戰帶 `party_only`（不拉隊友、不准中途加入）。
- 效能：`PkSystem._law_guard_count` 直接呼叫 `JiebiaoRules.rob_marked`；`ComboSystem.on_enter_room` 只更新走動的人與他的夥伴；`LawSystem` 離線角色檔分批讀（每次 8 個，tick 接著讀，讀完重算名單）。
- 介面：八卦泥陣（`hide_exit_names`）的小地圖不畫相鄰沒去過的「？」（`MapData.fog`）；夜晚小地圖亮區包含目前與相鄰房間的「往XXX」出區字（字框快取在 `RegionMapView`，霧層在主畫面藏起來時不重畫）；NPC 氣泡依序試右、左、下、上，避開其他按鈕；
  懸賞名單自己那一列「加碼」灰掉（`self`）、捲動框高度跟列數、表頭固定在框外（固定欄寬）；官爺「領取執照」依 PK值／上榜／錢不夠灰掉並寫原因；比武倒數寫「現實時間」、沒有比武不印報名名單、條件不合灰鈕；
  默契視窗不再列出正在邀請你的人、接受／拒絕旁倒數；「輕功脫身（內力不足，需 30）」；天師的「最多可以化解 N 次」另起一行。
- 擁有者決定（新增，全部【設計提案】）：
  - 懸賞的「朋友」判定實際只有**同組織**會觸發（同隊互相強制 PK 在 `PkSystem.force_pk` 就以 `target_in_party` 擋下）；不同隊、不同組織的朋友，每位持照獵人每遊戲日仍可讓目標 PK值 −1、罰金回到朋友手上。不另記「熟人」：死於 NPC 獵人或官兵本來就 −1（已證實），影響有限。
  - 加碼的賞金池**不退回**：目標下榜（半仙、獵人、官兵、PK 不夠格）或刪角色時，池子留在 `world.bounty.pools` 等下次上榜；刪角色時池子作廢。系統不生錢也不退錢。
  - 武林大會的報名門檻（實戰 1 萬、PK值 0）、恆山／全真的實戰換算 4000、合體夥伴一起打贏的配合度、獵人縮放的公式與 ^1.15、`er_repeat_cap` 的上限。
- 結果：`run_tests` 0 failed；`data_lint` 0 錯誤；`balance_sim --runs=500`：全跑在 `pace_xingxiu` 之後行程無訊息結束（log 停在第 160 行、前面全部 ok），其餘 34 個案例以 `--case` 各自重跑（`logs\m3d_fix3\bal\`），全部 ok；
  `m3d_acceptance` 20／20；m3c2、m3c、m3b、m3a、m2、story --all、net_smoke、M1 bot（新世界）、close_mid_battle wm／quit、介面驗收 headless＋視窗全過
  （有視窗的介面驗收前 4 次在第 9／15 步因計時失敗——「你遲遲沒有出手」、按鈕還灰著、查看還沒冷卻，和第二輪審查看到的一樣；夜晚霧層改成快取出區字框、戰鬥中不重畫之後第 6 次通過，log `ui_windowed_run*.log` 保留）。

**13.7 審查第四輪修正（2026-10-22；log 在 `K:\Project\JY-Mini-OL-Work\logs\m3d_fix4\`，截圖 `shots\m3d\fix4\`）**

- 忠於原作：新規則 `later_events`（`RULE_DEFAULTS` true；`classic_strict` false，其餘三組 true）。關掉時 `TourneySystem.enabled()` 為 false（日曆不開、`tourney_host`／`tourney_signup` 回 `tourney_disabled`）；
  血池三位 NPC 的 `fight.requires` 多一條 `{ type: rule, key: later_events }`（`req_rule`，`desc` 寫原因；`Requirements.describe` 的 `rule` 會用 `desc`），`ArtsSystem.on_battle_settled` 也不給威嚇熟練。
  驗收新劇本 `strict_events`（21 個劇本）。
- 比武：名聲與稱號照**名次**查（`TourneyRules.rank_slots`；名聲用同名次那組最低的那格），決賽兩人都沒到時不會有人拿冠軍的 3000／天樞真人；正式比賽不論有沒有冠軍都開始遊戲日與現實日冷卻；
  表演賽不收回上一屆的稱號與令牌、不改 `champions`（種子）；開打時就被取消資格的人不算報名人數。
- 合法緝拿：賞金 0 兩（目標身上與錢莊都沒錢、也沒有加碼）時 PK值 **不減**（照註解與 §13.6 的原意）。`LawSystem._load_any`、`PkSystem._char_any` 讀檔的角色照規則設 `pk_decay_on`。
- 劫鏢：同房隊友自己押著危險鏢 → 不拉（`pull_skip_chars`）。
- 武林帖：戰鬥 ABORTED（主機關閉、逾時）→ 退帖（`er_wlt_refund`），不設冷卻。
- 文件：`ms_gm_xiaolongnu_suxin` 的 `src_note` 與 §3.3.1 的 `moqi_min` 改成 10；README 獵人勝率改成 56.0／33.2／45.4%（整張表 23.0–69.6%）。
- 介面：比武報名視窗高度不超過對話框層（對戰表縮短捲動，`fit_bracket_h`）、報名倒數每秒往下數、主機列改「主機開辦新的一場，報名時間」；官爺頁與名單的「領賞（0 兩）」、自己那列的加碼（按鈕寫「自己」）都把原因寫在畫面上；
  NPC 氣泡避開已畫好的氣泡與人物列的文字標籤（「某某（你）」），多兩個候選位置；戰鬥小選單開在按下的指令鈕旁、蓋到戰鬥訊息扣分；「輕」兩種都寫耗多少內力（飛身越敵 10＋2×移動範圍）；
  介面驗收在三八紅粗話、客氣之後各多拍一張，並確認回話在對話框裡（`m3d_errand_rude_reply`、`m3d_errand_polite_reply`）。
- 沒改：換裝冷卻地圖→戰鬥不共用——§3.6 明定「開戰前 2 秒內在地圖上換過裝不影響戰鬥（戰鬥時間獨立）」，維持（擁有者決定）。
- 結果：`run_tests` 1976 個 0 失敗；`data_lint` 0 錯誤；`balance_sim --runs=500` 全部 ok（主程序跑到 163 個時被 90 分鐘逾時砍掉，其餘 9 個 pace_town／雜務與 27 個 econ2／M3d 案例以 `--case` 重跑，`logs\m3d_fix4\bal\`）；
  `m3d_acceptance` 21／21；m3c2、m3c、m3b、m3a、m2、story --all、net_smoke、M1 bot（新世界）、close_mid_battle wm／quit、介面驗收 headless＋視窗全過。
