# M3c2 實作計畫：學點節奏與門派雜務、血刀威嚇削弱、製作經濟、帶走角色、標題版本列（M3C2_PLAN）

> 版本：2026-10-20（開工版）。協調者撰寫；實作中只由協調者（整合者）修改本文件。
> 上游：擁有者 2026-10-20 的四項決定（M3c 完成回報的「下一步」：門派雜務給學點、入門約 3 小時到第二階段；血刀威嚇小幅削弱；生活技能可以賺錢但不能無限循環；帶走角色＋標題畫面版本與資料指紋）；M2_PLAN §2.2（P2 `passport_import`）、§4.6.8；M1_PLAN §6.3（參考角色 P0–P3、P1→P2 學點缺口）；M3A_PLAN（門派、切磋、師父）；M3B_PLAN §5.2（生活技能 v2）；M3C_PLAN（規則格式、神兵全服登記、`balance_sim` 區塊切分）；STORY_PLAN §4（任務引擎 v2：`stages`、`room_actions`、`repeat`、`hours`）。
> 研究：`docs/research/verified_research.md` 的「M3c2 研究」章（以下簡稱「研究」；分節：門派雜務與學點來源、生活技能與製作經濟）。研究與本文件不一致時，以本文件的「擁有者決定」（§1.3）為準，並在 `src_note` 寫明。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

M3c2 由 3 個工作包（WP-PACE、WP-ECON、WP-CARRY）**同時**在同一個工作目錄實作，最後由整合者驗收。實作者之間不溝通。規則沿用 M3C_PLAN §0.1：

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent 參數、事件 key、原因碼、伺服器選項 key、規則 key、存檔欄位、資料列 id 與前綴、檔名**都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定。
3. 優先順序：本文件 > M3C_PLAN > M3B_PLAN > STORY_PLAN > M3A_PLAN > WORLD_2001 > M2_PLAN > M1_PLAN > GDD > TECH_ARCH。偏差列在 §1.4。
4. 發現缺漏：照「最不意外」實作，程式裡寫 `# M3C2_PLAN 缺漏：……`，交付說明列出；**不要**改別人的檔案（共用熱檔照 §9.2 的切分）。

### 0.2 標記

沿用 GDD 第 0 章：【已證實】【後期版】【待考證】【設計提案】【設計提案・非原作】。新資料列一律有 `era`、`src`（`verified`／`later`／`proposal`）、必要時 `src_note`。本文件新增的數值一律【設計提案】，有研究依據的在 `src_note` 註明（例：`"src_note": "研究 雜務：mengpai/1 挑水 卯時、精 15、基本輕功 <50；學點【設計提案】"`）。

### 0.3 全域規則

M1_PLAN G1–G10、M2_PLAN H1–H6、M3A_PLAN K1–K6、STORY_PLAN §0.3、M3B_PLAN L1–L8、M3C_PLAN N1–N9 全部繼續有效（主機權威、離線同一路徑、`core/**` 純邏輯、JSON 數字轉 int、**不 commit**、測完關掉 godot 並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認、新增 `class_name` 後先 `--import`、不新增 Autoload、不新增 `@rpc` 方法）。M3c2 另加：

| # | 規則 |
|---|---|
| Q1 | `Protocol.VERSION` **維持 5**：M3c2 只新增可選參數（`char_select.identity`、`passport_import.new_name`）、事件、原因碼、快照欄位；RPC 簽名不變（`s2c_rejected(reason: String)` 照舊，只是 reason 字串多帶 `|` 分隔的主機資訊，§6.3）。新舊混用由 `content_hash` 擋。 |
| Q2 | **一個檔案只有一個擁有者**（§9.1）。共用熱檔照 §9.2 切到「函式／欄位／附加區塊」層級；不在表上的修改一律禁止。 |
| Q3 | **共用 JSON 的寫法**（同 M3c N3）：只用 Edit 工具做局部取代（每次 Edit 前重新 Read），**不得整檔重寫、不得重新排版、不得用 `json.dump` 重寫 `data/*.json`**。新列一律插在檔尾 `\n  ]\n}` 之前；改既有列只改 §9.2 准許的欄位。 |
| Q4 | **測試資料隔離**：測試、bot、驗收只寫測試根目錄（`DataRoot.test_root()` = `K:\Project\JY-Mini-OL-Work\testdata\`）或 `--data-root=<K: 上的絕對路徑>`。**絕對不碰**：`K:\Project\JY-Mini-OL-Release\userdata\`（擁有者真實存檔）、`K:\Project\JY-Mini-OL-Work\userdata\`、`K:\Project\JY-Mini-OL-Work\share\`、`appdata_old*`。不寫 C:。截圖 `...\Work\shots\`、log `...\Work\logs\`、暫存 `...\Work\tmp\`。匯入／匯出的測試檔一律放在測試根目錄的 `exports/`、`passports/` 或 `...\Work\tmp\m3c2\`。 |
| Q5 | **不刪任何東西**（`K:\Project\JY-Mini-OL-Work\tmp` 以外）：要淘汰的檔案搬到 `K:\Project\JY-Mini-OL-Work\tmp\m3c2_moved\<WP>\`。 |
| Q6 | 新 id 前綴：WP-PACE `q_ch_<派前綴>_*`（雜務任務）、`n_ch_<派前綴>_*`（新雜務 NPC）、`i_ch_*`（雜務道具）、模板 `ch_*`、`talk_n_ch_*`、`err_chore_*`；WP-ECON 新物品 `r_*`／`c_*`（既有慣例，加 `src: "proposal"`）、新配方 `rc_*`、模板 `econ2_*`；WP-CARRY 模板 `fi_*`、`err_foreign_*`、`title_build_*`、`err_alt_identity*`。 |
| Q7 | **不改既有戰鬥公式**：`core/battle/battle_formulas.gd` 凍結（`proc_chance` 不動）。威嚇削弱只在 `core/battle/battle_status.gd` 的 HEAVY 專屬常數與 `try_proc` 的 HEAVY 分支（§3）。若戰鬥金檔因 HEAVY 改變而不同，由 WP-PACE 用 `tools/regen_battle_golden.gd` 重產並在交付說明列出差異（只能是帶威嚇的單位）。 |
| Q8 | 1.0A-only 世界（`--eras=1.0A`）與 `classic_strict` 必須完整可玩：1.0B 門派（丐幫）的雜務 `era: "1.0B"`；`classic_strict` 關掉所有【設計提案】的加速（`novice_learn_pct`、`chore_xuedian`、`spar_rewards`，§8.2），得到「忠實」的雜務（只有熟練度與精神消耗）。 |
| Q9 | **不碰擁有者的世界資料夾格式**：所有存檔改動都是增量（新鍵、舊檔可讀）；角色檔不加新的頂層鍵（外來資料放在既有的 `origin_world` 與 `ext.foreign`，§5.6），所以護照簽章的正規化格式不變（`Passport.canonical` 不用再加 pre_m3c2 分支）。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=m3c2]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500 [--case=pace_shaolin]
"$G" --headless --path . --script res://tests/ui/ui_playthrough.gd -- --no-steam            # 另跑一次有視窗（不加 --headless）
"$G" --headless --path . -- --no-steam --offline --world=w_m3c2_m1 --profile=m1bot --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
"$G" --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3a_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3b_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3c_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3c2_acceptance.gd -- --no-steam [--only=chores] [--timeout=2400]
"$G" --headless --path . --script res://tools/story_acceptance.gd -- --no-steam --all
"$G" --headless --path . --script res://tools/net_smoke.gd -- --no-steam
"$G" --headless --path . -- --no-steam --offline --world=close_x --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=wm --time-scale=50 --quit-after=300
"$G" --headless --path . -- --no-steam --offline --world=close_y --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=quit --time-scale=50 --quit-after=300
```

計時測試（`test_rate_limit`、`test_view_blade_hit_on_wolf`）在負載下會偶發失敗：先單獨重跑，單獨也失敗才算失敗。

### 0.5 開工前量到的現況（協調者 2026-10-20，`balance_sim --runs=500`：128 案例全過；log `K:\Project\JY-Mini-OL-Work\logs\m3c2_plan_balance.log`）

| 項目 | 現況 | 出處 |
|---|---|---|
| 學點來源 | 只有戰鬥（`BattleRewards.lp_for`：怪物 `learn_points` × clamp((ref+1000)/(實戰+1000), 0.2, 3.0)）與任務獎勵；沒有雜務系統。可重複的門派任務只有 `q_em_jiancheng`（斷惡熟練 50）、`q_hg_zaowanke`（慈悲 15）、`q_wd_jiaofei`、`q_wd_jiashu`（俠義）、`q_xh_maipi`（學點 5）、`q_xh_liandu`（學點 10） | `core/battle/battle_rewards.gd:91`、`data/quests.json` |
| 雜務可用的引擎 | 任務 v2：`stages`、`room_actions`（`room`、`label`、`hours`、`requires`、`do`、`repeat`）、`repeat {max, cooldown_days}`、`requires hour_in`、獎勵 `skill_prof`／`learn_points`／`learn`／`learn_add` | `core/quest/quest_def.gd`、`server/quest_system.gd` |
| 學藝成本 | 每「次」1 學點；悟性 21 每次 精 10、熟練 11；悟性 30 精 5、熟練 15（`Learning.wit_cost`）；武功門檻 L³×difficulty（累計）；門派技能 L³；生活技能 L²×2 | `core/character/learning.gd`、`skill_book.gd:135` |
| 實戰上限 | 武功等級 ≤ 5 + ⌊√(實戰/10)⌋ → 35 級要實戰 9000 | `derived_stats.gd:47` |
| P1→P2 缺口 | M1_PLAN §6.3 已記：P2 技能組約 17,000 學點、只打山豬 1,560 隻才 5,700 學點，「目標時數待定」 | M1_PLAN:1633 |
| 精 | 每 10 秒回 2%（`Survival.REGEN_PCT`）；P0 精上限 92 → 約 660 精／小時；精藥水 30 兩回 50 | `survival.gd:7`、`items.json c_jingyao` |
| 切磋 | 十派 `m_<派>_dizi` 都是 `no_rewards: true`、實戰 0、學點 0 | `data/monsters.json` |
| 威嚇 | 血刀 `weihe` = HEAVY：`proc_chance(lv) = min(0.25, 0.05 + 0.002·lv)`，觸發時傷害 ×1.5（`HEAVY_MULT`），扣精、內力各 3 → 期望增傷 = p × 0.5：lv10 +3.5%、lv50 +7.5%、lv100 +12.5% | `battle_status.gd:15,150`、`battle_formulas.gd:130`、`battle_rules.gd:342` |
| 血刀現況 | `p1_sect_xuedao` 8.1 行動（參考少林長拳 13.3，下限 0.55× = 7.3）、剩氣 72.7%（其他派約 50–60%）——最快的一派，主要是血刀刀法本身；威嚇在 lv10 只貢獻約 +3.5% | balance log |
| 製作經濟 | `SELL_RATE = 0.3`（`npc_system.gd:6`）、商店買價 = 價格 × `price_pct`（聲望折扣最低 95%）；`success_chance = min(0.95, 0.5 + 0.005·L)`；失敗只扣精。`econ_chain`：打獵基準 1.37 兩／精；採集 0.44–0.63 倍；28 條配方超出 0.3–1.5 倍（多數 0.07–0.22）；`econ_no_loss` 0 條 | `server/life_system.gd`、balance log |
| 循環 | 目前沒有「全部材料商店買得到、成品收購價高於材料買價」的配方（商店有賣的原料：r_jiaotan、r_mabu、r_mutan、r_zhongzi_ma、r_zhongzi_mian；工具 t_*） | 協調者計算 |
| 戰鬥收入 | 實戰 2 萬打山賊頭目：每小時約 42.5 場、銀兩（含掉落賣店）11,080→12,426／小時（`loot_econ_elite`；時間模型：每場 行動數 × 2 秒 + 60 秒） | balance log |
| 護照 | `passport_import` 只回 `foreign_disabled`；`allow_foreign_characters` 選項已存在（預設 false）；`Character.origin_world` 已存在、已存檔 | `server/intents/intents_host.gd:96`、`character.gd:42` |
| 身分 | Steam 主機只收 `steam_<SteamID64>`、ENet／離線只收 `local_<32 hex>`；角色在 `worlds/<世界>/characters/<身分>/` | `world_server.gd:525`、README |
| 版本 | `project.godot` `config/version="0.1.0"`；`export_presets.cfg` 0.6.0.0；`Protocol.GAME_VERSION = "0.1.0"`（握手比對用的相容字串）；拒絕原因 `protocol_mismatch`／`version_mismatch`／`content_mismatch` 只送代碼 | `world_server.gd:501` |

---

## 1. 範圍

### 1.1 M3c2 要做（逐項打勾；括號是負責 WP；每項附驗收準則）

**A. 學點節奏與門派雜務（WP-PACE）**
- [ ] A1 **雜務系統**：每派 3–6 件雜務，做成任務 v2 列（`group: "sect_chores"`，id `q_ch_<派>_*`）＋新欄位 `chore`（§2.3）；忠實的獎勵（生活／基本技能熟練度，只在 < 50 時給）＋代價（精／神）＋時辰窗照研究；學點是【設計提案】且受規則 `chore_xuedian` 控制。**驗收**：`test_m3c2_chores.gd`：接、做、交、冷卻、時辰窗、代價不足 `chore_tired`、同一遊戲日第 n 次的學點遞減、`classic_strict` 學點為 0 但熟練度照給、熟練度 ≥ 50 不再加。
- [ ] A2 **防刷**：每件雜務有 `repeat.cooldown_days`、同一遊戲日遞減 `decay_pct`、而且**只在角色「最高的門派武功」< `novice_learn_below`（預設 40）時給學點**（過了新手期只剩熟練度）。**驗收**：單元測試；`balance_sim chore_bot_cap`：只做雜務的機器人一個遊戲日最多拿 `CHORE_DAY_CAP_LP`（§2.5）學點、過了 40 級拿 0。
- [ ] A3 **切磋給獎勵**：十派切磋弟子（`m_<派>_dizi`，含 `m_hs_trainee`）打贏給少量實戰與學點（研究：古墓、全真切磋「增加實戰經驗與潛能點數」；其他派比照【設計提案】）；每遊戲日只有前 `spar_daily_cap` 場有獎勵；學點同樣只在 < 40 時給。規則 `spar_rewards`。**驗收**：`test_m3c2_spar.gd`。
- [ ] A4 **新手學藝加速**（主要的壓縮槓桿）：規則 `novice_learn_pct`（向師父學藝每次的熟練度 × pct/100）與 `novice_jing_pct`（每次的精 × pct/100，最少 1），只在該技能等級 < `novice_learn_below` 時生效（§2.4）。`classic_strict` 為 100／100（忠實）。**驗收**：`test_m3c2_novice_learn.gd`。
- [ ] A5 **節奏量測與校準**：`balance_sim` 新案例 `pace_<派>`（§2.6 的「實際遊玩」模型，用真的 `Character`、`Learning`、`simulate_multi`），從剛拜師到「第二階段 P2 門檻」（§2.2）的時數：**少林中位數 2.5–3.5 小時**（目標約 3）；其他派中位數 2.0–4.5 小時（血刀 2.0–5.0：血刀刀法 difficulty 1.6）。雜務佔學點收入 ≥ 30%（少林案例）。**驗收**：`balance_sim` 全綠；`docs/M3C2_PLAN.md` 的數字由整合者依 WP-PACE 交付說明更新（§2.7 表）。
- [ ] A6 不破壞既有學點來源：怪物 `learn_points`、任務獎勵、`xuedian_cap` 照舊；M1 驗收 bot、`story_acceptance`、`m3a_acceptance` 全綠。

**B. 血刀威嚇小幅削弱（WP-PACE）**
- [ ] B1 HEAVY 的期望增傷降約 28%（擁有者「一點點，不要太多」：目標 −20%～−30%）：`HEAVY_MULT` 1.5 → 1.4、HEAVY 專屬觸發機率 × 0.9（§3）。威嚇仍是重擊（血刀的特色不變）。**驗收**：`test_m3c2_weihe.gd`（解析值）；`balance_sim xd_weihe_uplift`：新／舊期望增傷比 ∈ [0.70, 0.80]（lv 10、50、100 三點）；`p1_sect_xuedao` 等既有門派案例照過。
- [ ] B2 資料與文件：`sects.json` 血刀列 `src_note` 加註削弱；README／GDD 的威嚇描述由整合者同步。

**C. 製作經濟（WP-ECON）**
- [ ] C1 **盤點每條鏈**（採集、種田→廚師、釣魚→廚師、樵夫→燒炭／木工、挖礦→打鐵→鑄劍、種麻→織布→裁縫、打獵→皮革→裁縫）：材料成本（商店價或採集時間）對成品收購價，寫進 `balance_sim econ_hourly` 的報表。
- [ ] C2 **每條鏈每小時可賺錢**，落在「同階段戰鬥收入」的 0.5–0.9 倍（略低於戰鬥；§4.2），隨技能等級上升（10 ≤ 30 ≤ 50 不遞減）。**驗收**：`balance_sim econ_hourly` 全部在帶內。
- [ ] C3 **沒有無限循環**：凡是「全部材料商店買得到」的配方（含多步驟的鏈），成品收購價 **<** 材料在最低可能折扣下的買價。**驗收**：`balance_sim econ_loop` 0 條；`data_lint` 的 WP-ECON 區塊同樣檢查（新增配方或改價時立刻報錯）。
- [ ] C4 `econ_no_loss`（成品收購價 > 材料收購價）照舊必須 0 條。
- [ ] C5 不破壞打寶平衡：`loot_econ_elite`、`loot_econ_boss`、`armor_full_kit`、`loot_rate_hour` 照過；商店販售的裝備改價幅度 ≤ ±40%。

**D. 帶走角色（WP-CARRY）**
- [ ] D1 **匯出角色**：角色選擇畫面每個角色列有「匯出」→ 把最新護照包成匯出檔寫到 `<資料根目錄>/exports/`（§5.2），顯示路徑。**驗收**：`test_m3c2_export.gd`。
- [ ] D2 **匯入角色**（實作 M2 P2 `passport_import`）：角色選擇畫面「匯入角色」→ 檔案選擇（預設在 `<資料根目錄>/passports/`，另有「匯出資料夾」「瀏覽…」）→ 預覽（名字、性別、門派、實戰、主要技能等級、銀兩、物品數、會被拿掉的東西）→ 確認 → `passport_import`。**驗收**：`test_m3c2_foreign.gd` 全部原因碼與清單；`test_ui_m3c2_import.gd`。
- [ ] D3 **數值驗證與截斷**（§5.4）：未知物品／技能拿掉並列清單；等級、屬性、銀兩、學點、善惡等截到資料與規則的範圍；世界綁定的狀態重設；角色標「外來」。
- [ ] D4 **神兵**：本世界登記沒人持有 → 帶入並登記給匯入的角色；已有人持有 → 拿掉、列在清單（§5.5）。
- [ ] D5 **不重複**：以「來源世界 id＋來源角色 id」登記在本世界 `world.json.foreign_imports`；再匯入同一個角色：護照時間比登記的新才取代原本那個本地角色，否則 `foreign_not_newer`（§5.6）。
- [ ] D6 **選項**：單機（OFFLINE）一律允許；開房（ENet／Steam）看 `allow_foreign_characters`（預設關），主機可在標題畫面開房前勾「允許外來角色」或在伺服器設定面板切換。**驗收**：單元測試兩種模式。
- [ ] D7 **單機讀 Steam 身分的角色**（§5.7）：OFFLINE 時角色清單另列這個世界裡「目前登入的 Steam 帳號」的 `steam_<id>` 角色；Steam 沒開時列出世界裡所有 `steam_*` 資料夾的角色並要求確認。選了就用那個身分玩（存檔回到原資料夾），朋友拿到世界資料夾後可以直接按「單機遊玩」。**驗收**：`test_m3c2_offline_steam.gd`。
- [ ] D8 README、`docs/` 寫新的「把世界給朋友／帶走角色」說明（**不碰** `K:\Project\JY-Mini-OL-Work\share\`）。整合者寫 README，WP-CARRY 在交付說明提供文字草稿。

**E. 標題畫面版本列與拒絕訊息（WP-CARRY）**
- [ ] E1 標題畫面右下角一行小字（淡色）：`v0.6.1.0　協定 5　資料 9d24a2e10ccc`（全形空白分隔；版本取 `ProjectSettings application/config/version`；協定 `Protocol.VERSION`；資料指紋 = `GameData.content_hash` 去掉 `sha256:` 後前 12 字）。**驗收**：`test_ui_m3c2_title.gd`。
- [ ] E2 `project.godot` `application/config/version` 改成 `0.6.1.0`，與 `export_presets.cfg` 的 `application/file_version`、`application/product_version` 一致（WP-CARRY 兩個檔都只改這幾行）。**驗收**：單元測試讀兩個檔比對。
- [ ] E3 主機因協定／版本／資料不同拒絕加入時，客戶端訊息寫出**雙方**的版本、協定、資料指紋（§6.3）。**驗收**：`test_m3c2_reject_msg.gd`；`net_smoke` 照過。

### 1.2 M3c2 不做（延後到 M3d 或更後）

- **M3d**：懸賞名單與賞金獵人；輕功「輕」與 2001「閃」；合體技與玉女素心劍法；門派比武（大會）；劫鏢；NPC 執法者野外追捕；剩下的門派武功鏈；黑龍潭 1.0B；京城半仙與天師；丐幫跑腿（柯鎮惡、三八紅、武林帖、英雄帖）；裝備 2 秒間隔。
- **交易之道（`basic_trade`）影響收購價**（研究：2001 的收購比例約 0.75→1.0）：會動到全遊戲經濟與打寶平衡（`LOOT_SELL_RATE` 等），列為 M3d 候選，本包 `SELL_RATE` 維持 0.3。
- 恐嚇**指令**（對任何 NPC 下指令）、血池比武：本包只把恐嚇做成血刀的一件雜務（§2.3）。
- 送便當、酒鬼燒刀子酒、小虎、李大嬸等城鎮學點任務（研究有記載）：M3d 候選（可以直接用本包的 `chore` 欄位做遞減）。
- 少林木人巷（三門 50＋卸裝）、俗家弟子與結婚限制：M3d 以後。
- 外來角色的跨世界簽章驗證（護照的誠實說明照舊：別的世界無法驗證，所以只做截斷）。

### 1.3 擁有者決定（擁有者已預先授權本里程碑；以下是選定的預設值，建造者照做）

| # | 決定 | 理由（研究） | 本文落點 |
|---|---|---|---|
| R1 | 「第二階段」＝M1_PLAN §6.3 的 **P2 參考角色**換成各派武功（§2.2 門檻表）；不是少林木人巷（三門 50）——木人巷 M3d 以後再做 | 擁有者說的「P2 stage」；木人巷要的量是 P2 的數倍 | §2.2 |
| R2 | 3 小時是【設計提案】的壓縮：原作推算要幾十小時（研究「少林第二階段要多久」）。壓縮主要靠**新手學藝加速**（規則 `novice_learn_pct`／`novice_jing_pct`），雜務與切磋是學點與實戰的來源；`classic_strict` 全關＝忠實 | 研究：雜務沒有學點；精是第二道限制；光靠雜務給學點要每小時幾千點，等於鼓勵掛機 | §2.4 |
| R3 | 雜務的**忠實部分**照研究（熟練度到 50、精／神代價、時辰窗、化緣一天一次）；**學點**是【設計提案】；少林「掃地」、武當「劈柴／挑水」是擁有者點名但研究沒有記載的雜務 → 【設計提案】照做 | 研究 少林雜務、各派修練 | §2.3 |
| R4 | 雜務與切磋的學點**只給新手**（最高門派武功 < 40）＋每件冷卻＋同一遊戲日遞減；過了新手期只剩熟練度 → 掛機刷雜務沒有長期價值 | 擁有者「不能無限刷」 | §2.5 |
| R5 | 古墓、全真切磋「增加實戰經驗與潛能點數」→ 十派切磋都給實戰與學點【設計提案：擴大到其他派、潛能＝學點【待考證】】；每遊戲日前 30 場有獎勵 | 研究 mengpai/5、6 | §2.3.3 |
| R6 | 威嚇削弱 = 觸發時傷害 ×1.4（原 1.5）＋觸發機率 ×0.9 → 期望增傷約 −28%（每個等級都一樣）；不改成「削弱敵人攻擊」（那是 17173 介紹文的說法，官方門派技能表是重擊） | 研究：威嚇沒有數字；官方表＝重擊 | §3 |
| R7 | 製作收入定在**同階段戰鬥收入的 0.5–0.9 倍**（擁有者：略低於戰鬥）；**不照搬** 2001 裁縫的暴利（研究：2001 十大首富是裁縫） | 擁有者決定優先 | §4.2 |
| R8 | `SELL_RATE` 維持 0.3、**不加**每日賣出上限或價格下跌（2001 沒有任何記載）；防循環靠「商店買得到的材料做出的成品收購價一定低於材料買價」 | 研究 資源限制 | §4.3 |
| R9 | 外來角色：單機一律允許；開房預設關、主機可開（`allow_foreign_characters`）；匯入**是複製**（原世界的角色照舊在） | 擁有者需求；護照誠實說明 | §5.3 |
| R10 | 外來神兵：本世界登記空著才帶入（登記給匯入的角色），否則拿掉並列在清單；**不**變成普通複製品（沒有對應的普通物品列） | 神兵全服唯一（M3c O15） | §5.5 |
| R11 | 錢莊存款、組織、進行中的任務、任務冷卻、監獄／禁學、屍體、記錄點留在原世界；完成過的任務與旗標、門派、袋位、善惡、殺氣、PK值、名聲照帶（截斷到合法範圍） | 世界綁定的東西不能跨世界 | §5.4 |
| R12 | 重複匯入：同一個來源角色只對應本世界一個本地角色；護照比登記的新才取代，否則拒絕（避免把賣掉的東西「再匯一次」） | 擁有者「重新匯入不能複製」 | §5.6 |
| R13 | 單機讀 Steam 身分：只在 OFFLINE；選了 Steam 角色就把這個連線的身分換成那個 `steam_<id>`，存檔寫回原資料夾（之後朋友再用 Steam 開房，角色接得上） | 擁有者需求 | §5.7 |
| R14 | `Protocol.GAME_VERSION` 維持握手相容字串 `"0.1.0"`（連線條件照 CHANGELOG：協定與資料指紋都相同）；標題顯示的版本是 `config/version`（純資訊） | 不改既有連線規則 | §6 |
| R15 | 白猿扣善惡：照 M3c 第三輪延後（等沙漠山洞） | M3c 審查 | — |

### 1.4 與 GDD／既有文件的偏差（M3c2 決議；整合者同步）

| # | 偏差 | 理由 |
|---|---|---|
| S1 | GDD 學點來源「戰鬥與任務」→ 加「門派雜務（新手）」與「切磋（新手）」【設計提案】 | R2–R5 |
| S2 | M1_PLAN §6.3 P1→P2「目標時數待定」→ 約 3 小時（少林；規則 `classic_standard`） | 擁有者 |
| S3 | M2_PLAN `passport_import`「P2、未實作回 foreign_disabled」→ 實作；`allow_foreign_characters` 的意義改為「開房時」，單機一律允許 | R9 |
| S4 | M3a 血刀威嚇 ×1.5 → ×1.4、機率 ×0.9 | R6 |
| S5 | README「給朋友（可攜版）」→ 加「把世界給朋友」「帶走角色」兩節 | D7、D8 |

---

## 2. A：學點節奏與門派雜務（WP-PACE）

### 2.1 目標與槓桿

從剛拜師（P0 屬性、悟性 21、起始學點 100、實戰 0）到 §2.2 的 P2 門檻：`classic_standard` 下少林中位數約 3 小時。四個槓桿，WP-PACE 依序調（每個都有允許範圍，超出範圍要寫進交付說明並說明原因）：

| 槓桿 | 落點 | 初始值 | 允許範圍 |
|---|---|---|---|
| `novice_learn_pct` | 規則（§8.2） | 1000（每次熟練 ×10） | 100–3000 |
| `novice_jing_pct` | 規則 | 30（每次精 ×0.3，最少 1） | 10–100 |
| 雜務學點 `chore.lp` | `data/quests.json` | §2.3 表 | 每件 10–100 |
| 切磋獎勵 | `data/monsters.json` `m_*_dizi` 的 `combat_xp`、`combat_xp_ref`、`learn_points`；選項 `spar_daily_cap` | §2.3.3 | 實戰每場 20–300、學點每場 2–30 |

不准動的：`BattleRewards` 公式、`DerivedStats.art_level_cap`、`Learning.wit_cost`、`SkillBook.prof_for_level`、野外怪物的 `learn_points`／`combat_xp`（既有平衡案例依賴它們）、`xuedian_cap`。

### 2.2 P2 門檻（綁定；`balance_sim` 與驗收都用這張表）

角色有下列全部技能等級、且實戰 ≥ 9000（35 級的實戰上限）就算到達「第二階段」：

| 技能 | 等級 | 對應 M1 P2 |
|---|---|---|
| 本派門派技能（`sects.sect_skill`） | 30 | 佛法 30 |
| 本派入門兵器／拳腳武功（下表） | 35 | 少林長拳 35 |
| 該武功的 `base_skill`（基本拳腳／刀／劍…） | 35 | 搏擊格鬥 35 |
| 本派心法（下表） | 30 | （新增：M3a 學藝順序 門派技能 → 心法 → 武功） |
| `basic_inner` | 30 | 基本內功 30 |
| `basic_parry`、`basic_dodge` | 各 30 | 拆招卸力、閃躲縱躍 30 |

| 門派 | 入門武功 | 心法 |
|---|---|---|
| shaolin | `sl_changquan` | `sl_xinfa` |
| huashan | `hs_jianfa` | `hs_xinfa` |
| wudang | `wd_changquan` | `wd_xinfa` |
| emei | `em_piaoxue` | `em_xinfa` |
| hengshan | `hg_jianfa` | `hg_xinfa` |
| quanzhen | `qz_jianfa` | `qz_xinfa` |
| gumu | `gm_yunu_jian` | `gm_xinfa` |
| lingjiu | `lj_zhemei` | `lj_xiaoyao` |
| xingxiu | `xh_chousui` | `xh_xinfa` |
| xuedao | `xd_daofa` | `xd_xinfa` |
| gaibang（1.0B） | 第一位師父教的最低 cap 的 ART（WP-PACE 查 `masters.json` 後寫死在 `PACE_GATE`） | `gb_xinfa` |

（`balance_sim` 常數 `PACE_GATE` 照抄這兩張表。）另外印出「門檻角色 vs `m_ghost`」的勝率與剩氣（只報告；原 `p2_vs_ghost` 標準是勝率 ≥ 70%、剩氣 ≥ 25%），讓擁有者看到門檻角色真的打得動第二階段練功點。

少林門檻的熟練度總量（協調者算）：佛法 27,000＋長拳 38,588＋搏擊 38,588＋心法 24,300＋內功／拆招／閃躲 各 24,300 ≈ **201,000**；悟性 21 每次 11 → 約 18,300 次（＝學點），精 183,000。`novice_learn_pct` 1000／`novice_jing_pct` 30 時 → 約 1,830 學點、約 5,500 精（3 小時自然回精約 2,000，其餘靠休息／精藥水／雜務間的等待）。

### 2.3 雜務（任務 v2 ＋ `chore` 欄位）

#### 2.3.1 資料形狀（`data/quests.json`，WP-PACE 追加）

```jsonc
{ "id": "q_ch_sl_tiaoshui", "name": "挑水", "chapter": "少林派", "group": "sect_chores",
  "giver": "n_ch_sl_kanshui", "era": "1.0A", "src": "verified", "dialogue_src": "proposal",
  "requires": [{"type": "sect", "sect": "shaolin"}, {"type": "hour_in", "hours": ["卯"]}],
  "repeat": { "max": 0, "cooldown_days": 0.1 },
  "stages": [ /* TALK 看水僧（給 i_ch_tong）→ room_actions 在 sl_zhulin「挑水」（hours ["卯"]）→ DELIVER i_ch_tong 給看水僧 */ ],
  "outcomes": { "done": { "label": "", "rewards": { "skill_prof": { "basic_body": 30 } } } },
  "chore": { "sect": "shaolin", "lp": 50, "decay_pct": [100, 60, 30, 0],
             "cost": { "jing": 15 }, "prof_below": 50,
             "src_note": "研究 雜務：mengpai/1 挑水 卯時、精 15、基本輕功 <50；學點【設計提案】" } }
```

`chore` 欄位（綁定）：

| 欄位 | 型別 | 意義 |
|---|---|---|
| `sect` | String | 只有這派的弟子能接（另外 `requires` 也要寫 `sect`，lint 檢查兩者一致） |
| `lp` | int | 完成時的基本學點【設計提案】 |
| `decay_pct` | Array[int] | 同一個**遊戲日**（`floor(now_s / day_s)`）內第 1、2、3…次完成的學點百分比；超過長度用最後一個值 |
| `cost` | Dictionary | `jing`／`shen`／`qi` → int：**交差時**扣；不夠 → 不能交差，原因碼 `chore_tired`（任務留著） |
| `prof_below` | int | `outcomes.*.rewards.skill_prof` 的每項只在該技能等級 < 這個值時給（忠實：「<50 時額外加」） |
| `src_note` | String | 出處 |

主機規則（`server/quest_system.gd` 的 WP-PACE 區塊，§9.2）：
1. 完成 `group == "sect_chores"` 的任務：先檢查 `cost`（不夠 → `chore_tired`），扣掉；
2. 學點 = `floor(lp × decay_pct[n] / 100)`，n = 這個角色本遊戲日已完成這件雜務的次數；**再乘 0**，如果規則 `chore_xuedian` 為 false，或角色最高的本派 ART 等級 ≥ `novice_learn_below`；
3. `skill_prof` 每項依 `prof_below` 過濾；其他獎勵照任務引擎；
4. 計數存在角色 `counters.chore_day = { "day": int, "n": { quest_id: int } }`（換日就重設）；
5. 事件：既有 `reward` 照送；學點被遞減成 0 時另送 `ch_no_lp`（系統訊息「今天這件事已經做了好幾回，師兄說你該去練功了。」或「你的武功已有根基，雜務只是磨練心性。」——依原因二選一，模板 `ch_no_lp_daily`／`ch_no_lp_novice`）。

需要的新 `requires` 型別（`core/character/requirements.gd`，WP-PACE）：`money_max {value}`（化緣：身上銀兩 ≤ value）、`has_item {item, n}`（若已存在則沿用）。原因碼依既有慣例 `req_money_max`、`req_has_item`。

#### 2.3.2 雜務表（WP-PACE 照建；NPC 已存在的用既有 id，新 NPC 用 `n_ch_*`，放在表上的房間；學點欄是初始值）

時辰窗的「早上」一律卯辰巳、「三餐」卯午酉（研究：原文是早中晚，對應時辰是推論【待考證】）。冷卻 `cooldown_days` 0.1（≈12 分鐘真實時間，遊戲日 2 小時）除非另註。

| id | 名稱 | 給的人（房間） | 時辰 | 代價 | 忠實獎勵（<50） | 學點 | 出處 |
|---|---|---|---|---|---|---|---|
| `q_ch_sl_tiaoshui` | 挑水 | 新 `n_ch_sl_kanshui` 看水僧（`sl_court`）；挑水在 `sl_zhulin` | 卯 | 精 15 | `basic_body` +30 | 50 | mengpai/1【已證實】 |
| `q_ch_sl_kanchai` | 砍柴 | 新 `n_ch_sl_chaigong` 柴工頭陀（`sl_caiyuan`）；要帶柴刀 `w_chaidao` | 卯辰巳 | 精 15 | `life_woodcut` +30（沒學過樵夫則不給） | 50 | mengpai/1【已證實】 |
| `q_ch_sl_zhufan` | 煮飯 | `n_sl_zhaiseng`（`sl_zhaitang`） | 卯午酉 | 精 10 | `life_cooking` +30 | 40 | mengpai/1【已證實；時辰推論】 |
| `q_ch_sl_dujing` | 讀經 | 新 `n_ch_sl_jingseng` 知經僧（`sl_hall`）；給 `i_ch_jingshu`（不能丟、不能給人） | 全天 | 神 20 | `basic_literacy` +30 | 40 | mengpai/1【已證實】 |
| `q_ch_sl_huayuan` | 化緣 | `n_sl_zhike`（`sl_gate`）；`requires money_max 0` | 全天，`cooldown_days` 1.0 | — | — | 30 | mengpai/1 只寫限制、沒寫獎勵 → 學點【設計提案】 |
| `q_ch_sl_saodi` | 掃地 | `n_ch_sl_kanshui` | 全天 | 精 5 | — | 20 | 擁有者點名【設計提案】 |
| `q_ch_wd_nongwu` | 農務 | `n_wd_nongfu`（`wd_daotian`） | 卯辰巳 | 精 10 | `life_farming` +30 | 40 | mengpai/2【已證實】 |
| `q_ch_wd_taqiang` | 踏牆 | `n_wd_yulianzhou`（`wd_tanqiang`） | 全天 | 精 15 | `basic_body` +30 | 50 | mengpai/2【已證實】 |
| `q_ch_wd_shufa` | 寫書法 | `n_wd_zhangsongxi`（`wd_shufang`） | 全天 | 神 20 | `basic_literacy` +30 | 40 | mengpai/2【已證實】 |
| `q_ch_wd_pichai` | 劈柴 | 新 `n_ch_wd_chaifu` 火工道人（`wd_houshan`） | 卯辰巳 | 精 15 | `life_woodcut` +30 | 40 | 擁有者點名【設計提案】 |
| `q_ch_wd_tiaoshui` | 挑水 | `n_ch_wd_chaifu` | 卯 | 精 15 | `basic_dodge` +30 | 40 | 擁有者點名【設計提案】 |
| `q_ch_em_taqiang` | 踏牆 | `n_em_beimianyi`（`em_square`） | 全天 | 精 15 | `basic_body` +30 | 50 | mengpai/3（貝綿丁）【已證實；本作 NPC 名貝綿儀】 |
| `q_ch_em_yili` | 易理 | `n_em_jingzhao`（`em_jingzhao`） | 全天 | 神 20 | `basic_literacy` +30 | 40 | mengpai/3【已證實】 |
| `q_ch_em_chanding` | 禪定 | `n_em_jingxuan`（`em_dadian`） | 全天 | 精 10、神 10 | `basic_inner` +30 | 50 | mengpai/3【已證實】 |
| `q_ch_em_chanxiu` | 禪修 | `n_em_lianxiang`（`em_chanfang`） | 酉【待考證：固定時刻】 | 神 10 | 殺氣 −50（`killing_intent` 獎勵） | 30 | mengpai/3【已證實】 |
| `q_ch_em_caiyuan` | 菜園 | `n_em_nongfu`（`em_caiyuan`） | 卯辰巳 | 精 10 | `life_farming` +30 | 40 | 【設計提案】 |
| `q_ch_hs_tiaoshui` | 何寶生的挑水工作 | 新 `n_ch_hs_hebaosheng`（`hs_square`） | 卯【設計提案：比照少林】 | 精 15 | `basic_body` +30 | 50 | gonglue/9 標題【已證實】 |
| `q_ch_hs_kanchai` | 辛苦的勞斯克 | 新 `n_ch_hs_laosike` 儲柴生（`hs_hall`） | 卯辰巳 | 精 15 | `life_woodcut` +30 | 50 | gonglue/9【已證實】 |
| `q_ch_hs_zhibu` | 煩人的藍依涵 | `n_hs_lanyihan`（`hs_square`） | 全天 | 精 10 | `life_weaving` +30 | 40 | gonglue/9【已證實】 |
| `q_ch_hs_tiaoqi` | 基本修習 | 新 `n_ch_hs_yejing` 葉靜（`hs_hall`） | 全天 | 精 10 | `basic_inner` +30 | 40 | gonglue/9（調氣）【已證實】 |
| `q_ch_hs_xishu` | 教書生 | 新 `n_ch_hs_zhuge` 諸葛仕（`hs_square`） | 辰【待考證：固定時辰】 | 神 20 | `basic_literacy` +30 | 40 | gonglue/9【已證實】；華山門書不做 |
| `q_ch_qz_dujing` | 誦經 | `n_qz_xiazhicheng`（`qz_reading`） | 全天 | 神 20 | `basic_literacy` +30 | 40 | 【設計提案】 |
| `q_ch_qz_jiaoyuan` | 澆園 | `n_qz_zhangyuan`（`qz_garden`） | 卯辰巳 | 精 10 | `life_farming` +30 | 40 | 【設計提案】 |
| `q_ch_qz_kanchai` | 砍柴 | 新 `n_ch_qz_chaifu` 火工道人（`qz_houshan`） | 卯辰巳 | 精 15 | `life_woodcut` +30 | 40 | 【設計提案】 |
| `q_ch_gm_yangfeng` | 養蜂 | 新 `n_ch_gm_fengnu` 養蜂婢（`gm_huayuan`） | 全天 | 精 10 | `basic_body` +30 | 40 | 【設計提案】（玉蜂） |
| `q_ch_gm_hanyu` | 寒玉床練功 | `n_gm_hanyu`（`gm_hanyu`） | 全天 | 精 10、神 10 | `basic_inner` +30 | 50 | 【設計提案】 |
| `q_ch_gm_songfan` | 送飯 | `n_gm_songfan`（`gm_food`） | 卯午酉 | 精 10 | `life_cooking` +30 | 40 | mengpai/5 三餐【設計提案：雜務】 |
| `q_ch_hg_chaihuo` | 儲柴生 何月 | `n_hg_heyue`（`hg_woodshed`） | 卯辰巳 | 精 15 | `life_woodcut` +30 | 50 | gonglue/7【已證實】 |
| `q_ch_hg_nongwu` | 憂煩的程薇 | `n_hg_chengwei`（`hg_field`） | 卯辰巳 | 精 10 | `life_farming` +30 | 40 | gonglue/7【已證實】 |
| `q_ch_hg_shiyao` | 識藥 | `n_hg_yizhen`（`hg_first`） | 辰巳申 | 神 15 | `basic_medic` +30 | 50 | mengpai/7（3 個時辰）【已證實】；時辰沿用儀真教醫的時辰 |
| `q_ch_hg_tiaoqi` | 定靜 調氣 | `n_hg_dingjing`（`hg_houshan`） | 全天 | 精 10 | `basic_inner` +30 | 40 | gonglue/7【已證實】 |
| `q_hg_zaowanke`（既有） | 恆山早晚課 | 既有 | 卯酉 | 神 10 | 既有慈悲 15（不受 `prof_below`：門派技能） | 30 | 只加 `chore` 欄位與 `group` 不變；`prof_below` 寫 250 |
| `q_ch_lj_fangzhi` | 好心的程清霜 | `n_lj_chengqingshuang`（`lj_west`） | 全天 | 精 10 | `life_weaving` +30 | 40 | gonglue/10【已證實】 |
| `q_ch_lj_tanlu` | 探路學輕功 | `n_lj_jujian`（`lj_west`） | 全天 | 精 15 | `basic_body` +30 | 50 | gonglue/10【已證實】 |
| `q_ch_lj_dingzuo` | 定坐修內力 | `n_lj_lanjian`（`lj_east`） | 全天 | 精 10 | `basic_inner` +30 | 50 | gonglue/10【已證實】 |
| `q_xh_maipi`（既有） | 馬屁研習 | 既有 | 全天 | 神 10 | 既有 | 30（原 `rewards.learn_points` 5 → 0，改由 `chore.lp`） | 加 `chore` 欄位 |
| `q_xh_liandu`（既有） | 邪惡的練毒 | 既有 | 全天 | 精 10 | 既有 | 40（原 10 → 0） | 加 `chore` 欄位 |
| `q_ch_xh_shoulie` | 狩獵 | `n_xh_shudouzi`（`xh_mid1`）：KILL 2 隻星宿路上的既有怪（WP-PACE 選 P0 打得過的） | 全天 | 精 10 | `basic_hidden` +20 | 40 | gonglue/8【已證實；步驟設計提案】 |
| `q_ch_xh_anqi` | 毒門暗器 | `n_xh_canjizi`（`xh_mid1`） | 全天 | 精 10 | `basic_hidden` +30 | 40 | gonglue/8【已證實】 |
| `q_ch_xd_pizhi` | 劈紙削腐 | `n_xd_shengdi`（`xd_yard`） | 全天 | 精 15 | `xd_daofa` +30（< 50） | 40 | mengpai/4【已證實】 |
| `q_ch_xd_dizong` | 堤縱 | `n_xd_kuji`（`xd_yard`） | 全天 | 精 15 | 雪遁步行（WP-PACE 查 id）+30 | 40 | mengpai/4【已證實】 |
| `q_ch_xd_kongxia` | 恐嚇 | `n_xd_herder`（`xd_tent`）：TALK 牧人選「恐嚇」 | 全天 | 精 20、神 20 | `weihe` +20；善惡 −10 | 30 | mengpai/4 恐嚇（指令改成雜務【設計提案】） |
| `q_ch_xd_jiu` | 嗜酒的淨歧 | `n_xd_jingqi`（`xd_mishi`）：DELIVER 1 壺酒（既有商店酒類物品） | 全天 | — | — | 40 | gonglue/4 標題【已證實；步驟設計提案】 |
| `q_ch_gb_qitao` | 乞討 | `n_gb_jiang`（`jc_square`） | 全天 | 精 10 | `qitao` +20 | 40 | 【設計提案】 `era 1.0B` |
| `q_ch_gb_jianchai` | 撿柴 | `n_gb_zhanggun`（`gb_yuan`） | 全天 | 精 10 | `life_woodcut` +30 | 40 | 【設計提案】 `era 1.0B` |

每派至少 3 件；每派有一件「全天」可做（不讓時辰窗把新手卡住）。NPC 對話、任務文字一律【設計提案】（原作沒有逐字對白）。新 NPC：`kind` `FUNC`、`alignment` 依門派、`services ["QUEST"]`、`attack` **不寫**（不能被打）、`era` 同門派。

#### 2.3.3 切磋獎勵（`m_<派>_dizi`、`m_hs_trainee`；`server/sect_system.gd` 的 WP-PACE 區塊）

- 資料（只改這幾個欄位）：`no_rewards: false`、`combat_xp`（初始 120）、`combat_xp_ref`（初始 10000）、`learn_points`（初始 8）、`money` 維持空、`drops` 維持空。
- 主機：切磋打贏後，若規則 `spar_rewards` 為 false → 不給；否則看 `counters.spar_day = { "day", "n" }`：`n < options.spar_daily_cap`（預設 30）才給 BattleRewards 的實戰與學點，`n += 1`；學點另外受「最高本派 ART < `novice_learn_below`」限制（實戰不受）。超過上限送 `ch_spar_capped`（「今天切磋夠多了，師兄弟們都累了。」）。
- 切磋輸了不扣、不給（既有）。

### 2.4 新手學藝加速（`core/character/learning.gd` 的 WP-PACE 區塊）

```gdscript
## M3C2_PLAN §2.4：向師父學藝（Learning.learn）時，該技能目前等級 < rules.novice_learn_below 才生效
static func novice_mults(ch: Character, skill_id: String, rules: Dictionary) -> Dictionary   # { "prof": float, "jing": float }
```

- `prof` = `novice_learn_pct / 100.0`、`jing` = `novice_jing_pct / 100.0`；等級 ≥ `novice_learn_below` 或規則缺 → `{1.0, 1.0}`。
- `Learning.learn` 每次：熟練 `roundi(wc.prof × prof)`、精 `maxi(1, roundi(wc.jing × jing))`；學點仍是每次 1、師父學費照舊；上限檢查不變（`cap_master`、`cap_sect_skill`、`cap_xp`）。
- **只**影響 `Learning.learn`（向師父學）；自修 `self_study`、秘笈 `manual_read`、生活技能、任務 `skill_prof` 不受影響。
- `res` 多回 `novice: bool`（學藝視窗可顯示「新手加速」字樣；UI 由 WP-PACE 在 `ui/game/dialogs/learn_dialog.gd` 加一個小標籤）。
- 既有單元測試若斷言精確熟練度／精：測試用的 rules 改成明確傳 `classic_strict` 或把期望值改成新值（WP-PACE 擁有那些測試檔的這次修改，§9.1）。

### 2.5 防刷常數（綁定）

- `CHORE_DAY_CAP_LP`：一派**所有**雜務在一個遊戲日理論最大學點 = Σ 每件 `lp × Σdecay_pct/100 × 時辰窗內可完成次數`，`balance_sim chore_bot_cap` 計算並檢查 ≤ 600。
- 過了新手期（最高本派 ART ≥ 40）雜務與切磋學點為 0 → `chore_bot_cap` 另檢查「40 級角色只做雜務一個遊戲日 = 0 學點」。

### 2.6 節奏模擬（`tools/balance_sim.gd` 的 WP-PACE 區塊；案例 `pace_<sect_id>`、`chore_bot_cap`、`xd_weihe_uplift`）

模型（綁定；WP-PACE 照做，不准為了過關而簡化成理想化的流程）：

1. **角色**：用真的 `CharacterFactory` 建 P0 屬性（悟性 21）、選定性別（門派限制）、加入門派（`sect` 設好、起始學點 100、實戰 0）；學藝用真的 `Learning.learn`（真的 `masters.json` 師父、cap、規則 `classic_standard`）；生命值／精回復用 `Survival` 常數；起點在山門，起始時辰均勻隨機（每輪一個 seed）。
2. **時間成本**（世界秒 = 真實秒，time_scale 1）：走一間房 `STEP_S = 4`；對話一步 `TALK_S = 6`；房間動作 `ACT_S = 8`；學藝每次 `LEARN_S = 1`（10 次一批）；戰鬥 = `simulate_multi` 的 ticks × `Battle.TICK` ＋ 結果畫面 2.5 ＋ 偵察冷卻 6；出門練功的來回步數用 `DataLint.room_index` BFS 算（山門 → 最近的練功房）。
3. **策略**（每一步依序檢查，第一個成立就做）：(a) 有可做的雜務（門派對、時辰窗內、不在冷卻、代價付得起、今天學點還沒遞減到 0）→ 做（含走路）；(b) 學點 ≥ 10 且精夠 → 學門檻表裡**完成度最低**、且沒被 cap 擋住的技能 10 次；被 `cap_xp` 擋住就跳過；(c) 切磋今天還有獎勵 → 切磋一場（`simulate_multi` 對 `m_<派>_dizi`）；(d) 出門練功一趟：挑門派附近遇敵表裡「目前角色勝率 ≥ 0.8」中實戰最高的怪，打 8 場（勝率用 50 場預跑快取），氣 < 30% 就回；(e) 精 < 學一批所需 → 原地等回精（或回客棧休息，如果該派地區有 `INN` 且來回比等待快）。
4. **輸出**：每派跑 `min(runs, 100)` 輪 → 中位數、P10、P90 小時；學點來源比例（雜務／切磋／野外／任務）；實戰來源比例；門檻角色 vs `m_ghost` 勝率與剩氣（報告）。
5. **通過條件**：§1.1 A5；`chore_bot_cap` §2.5；`xd_weihe_uplift` §3.3。

### 2.7 校準結果（整合者依 WP-PACE 交付說明填）

| 項目 | 值 |
|---|---|
| `novice_learn_pct`／`novice_jing_pct` | 3000／10（兩個都在允許範圍的邊上：`basic_inner` 是四次方曲線，P2 門檻實際要約 825,000 熟練度，不是 §0.5 估的 201,000） |
| 少林中位數（P10–P90） | **3.17 小時**（3.04–3.35；審查修正後 §14：到第二階段含打得過小鬼；技能數字到門檻 2.96） |
| 其他派中位數範圍 | 3.16（武當）– 3.69（丐幫）小時；華山 3.31、峨嵋 3.28、恆山 3.31、全真 3.24、古墓 3.49、靈鷲 3.36、星宿 3.34、血刀 3.55 |
| 學點來源比例（少林） | 雜務 35%、切磋 62%、野外 3%；其他派雜務 19–33%（§14 O1） |
| 切磋弟子 | `combat_xp` 100（審查：原 200）、`combat_xp_ref` 10000、`learn_points` 25（一場最多 30）；少林 `m_sl_dizi` 學點 20、較弱 |
| 少林雜務學點 | 挑水 70、砍柴 50、煮飯 50、讀經 50、化緣 50、幫農 40、學佛 40、掃地 20（審查 §14） |
| `chore_bot_cap` | 一天理論最大：少林 595、恆山 494、峨嵋 458、華山 414、星宿／血刀 397、武當 363、靈鷲 350、古墓 331、全真／丐幫 312（上限 600） |
| `xd_weihe_uplift` | 新／舊期望增傷 0.74（lv10）、0.71（lv50）、0.72（lv100）；lv100 觸發 22.5% |

---

## 3. B：血刀威嚇削弱（WP-PACE）

### 3.1 規則（`core/battle/battle_status.gd`）

```gdscript
const HEAVY_MULT := 1.4             # M3C2 R6：1.5 → 1.4
const HEAVY_CHANCE_MULT := 0.9      # M3C2 R6：HEAVY 的觸發機率 = proc_chance(lv) × 0.9
```

`try_proc`：效果是 `HEAVY` 時，判定改成 `b.rng.randf() >= BattleFormulas.proc_chance(lv) * HEAVY_CHANCE_MULT`（**一樣只擲一次亂數**，其他效果的亂數序列完全不變）。`BattleFormulas.proc_chance` 不動（凍結）。

### 3.2 數字

| 威嚇等級 | 舊 p | 舊期望增傷 p×0.5 | 新 p | 新期望增傷 p×0.4 | 比 |
|---|---|---|---|---|---|
| 10 | 0.070 | +3.50% | 0.063 | +2.52% | 0.72 |
| 50 | 0.150 | +7.50% | 0.135 | +5.40% | 0.72 |
| 100 | 0.250 | +12.50% | 0.225 | +9.00% | 0.72 |

觸發消耗（精、內力各 3）不變。

### 3.3 驗證

- `tests/unit/test_m3c2_weihe.gd`：常數、一次亂數、期望值（解析）、固定種子下觸發次數比。
- `balance_sim xd_weihe_uplift`：P1 血刀（`sect_spec("P1","xuedao","xd_daofa",20)`，威嚇設 10／50／100）對野狼 5000 次出手，量「有威嚇／威嚇效果移除」的平均每擊傷害比，換算新／舊增傷比 ∈ [0.70, 0.80]；`p1_sect_xuedao`、`p1_sect_xuedao_vs_group`、`p0_vs_xuedao_dizi`、`gate_xd_*` 照過。
- 若戰鬥金檔（`tests/fixtures/**` 的 battle golden）有血刀單位而改變 → WP-PACE 用 `tools/regen_battle_golden.gd` 重產並在交付說明列出。

---

## 4. C：製作經濟（WP-ECON）

### 4.1 盤點（`balance_sim econ_hourly` 的報表；每條鏈一行）

鏈（綁定清單；新增配方可以加鏈）：

| 鏈 id | 內容 |
|---|---|
| `g_farm`／`g_wood`／`g_fish`／`g_mine` | 純採集：產物直接賣 |
| `farm_cook` | 種田（稻）→ 廚師（白飯等） |
| `fish_cook` | 釣魚＋樵夫 → 烤魚等 |
| `wood_char` | 樵夫 → 燒炭 |
| `wood_carp` | 樵夫 → 工匠（1.0B） |
| `mine_smith` | 挖礦 → 打鐵（鐵塊、工具） |
| `mine_sword` | 挖礦 → 打鐵 → 鑄劍（＋燒炭） |
| `ma_tailor` | 種麻 → 織布（線軸、麻布）→ 裁縫 |
| `hunt_tailor` | 打獵 → 皮革 → 裁縫 |

每條鏈在技能等級 10、30、50 各算一次（鏈內各技能同等級），兩種材料來源：`self`（自己採集，採集時間算進去）、`shop`（商店買得到的材料用買價算成本，買不到的還是自己採）。

每小時收入模型（綁定）：
- 一次動作的時間 = max(`cooldown_s`, 精成本 / 回精速度)；回精速度 = 參考角色精上限 × `Survival.REGEN_PCT` / `REGEN_INTERVAL_S`（參考角色：等級 10→P1、30→P2、50→P3 的精上限，§2.2 的公式同 `player_spec`）；另算「買精藥水」版本（30 兩回 50 精，成本扣掉），取兩者較高的收入。
- 成功率 = `LifeSystem.success_chance(L)`（或配方的新欄位 §4.4）；失敗只扣精（既有規則）。
- 產物賣價 = `NpcSystem.sell_price`（價格 × 0.3）。每小時另加 5% 時間給走路與賣東西。

### 4.2 收入目標（綁定）

同階段戰鬥收入（`combat_h(stage)`）＝ `balance_sim` 用既有時間模型（每場 行動數 × 2 秒 ＋ 60 秒）算「參考角色打該階段練功怪的銀兩＋掉落賣店」：

| 技能等級 | 對應階段 | 參考角色 | 練功怪 |
|---|---|---|---|
| 10 | P1 | `player_spec("P1")` | `m_boar` |
| 30 | P2 | `player_spec("P2")` | `m_ghost` |
| 50 | 2 萬 | `_p_party(20000, 1)` | `m_bandit_chief`（＝`loot_econ_elite`） |

通過條件（`econ_hourly`，每條鏈取 `self` 與 `shop` 中較高者）：
- 等級 30、50：`chain_h / combat_h ∈ [0.5, 0.9]`；
- 等級 10：`chain_h > 0` 且 `chain_h / combat_h ∈ [0.3, 0.9]`（練功期可以只小賺）；
- 每條鏈 10 ≤ 30 ≤ 50（不遞減）；
- `hunt_tailor` 只檢查 > 0 與不遞減（打獵本身就是戰鬥）。

協調者先估：P1 打山豬每場只掉 0–5 兩＋豬肉，`combat_h(P1)` 只有幾百兩；2 萬約 1.1 萬兩（`loot_econ_elite`）。所以等級 10 的鏈每小時幾百兩、50 級幾千兩就在帶內——**不要**為了接近 2001 裁縫的暴利去拉高（R7）。

### 4.3 防循環（綁定；`balance_sim econ_loop` ＋ `data_lint` WP-ECON 區塊）

- **最低買價** = 物品價格 × `MIN_BUY_PCT / 100`，`MIN_BUY_PCT` = 100 ＋ `data/reactions.json` 裡所有 `services` 含 `SHOP` 的列 `(price_pct − 100)` 中**負值的總和**（現在 = 95）；沒有負值時 100。
- 對每個配方：若**每一項**材料都有商店賣（`npcs.shop.items`），要求 `Σ 產物 sell_price × n < Σ 材料 最低買價 × n`（嚴格小於）。
- 多步驟：把「商店買得到」的閉包算出來（某物品若是配方產物、且配方材料全部在閉包內，該物品以「材料最低買價總和 / 產量」視為可買），對閉包內的物品重複上面的檢查。
- 工具（`t_*`）不算消耗材料。
- `econ_no_loss`（既有）照舊。

### 4.4 允許的槓桿（WP-ECON）

1. `data/items.json`：生活技能原料、中間品、食物（`r_*`、`c_*` 中出現在 `life_skills.json` 的 yield／recipes 的列）的 `price`；配方產出的裝備（`w_*`、`a_*`、`t_*`）`price` 只能改 ±40% 以內，而且 `loot_econ_*`、`armor_full_kit` 照過；新增原料或食物列（研究的等級段：麥、松木、綠晶鐵、棉線軸…，`era`、`src: "proposal"`、名稱有出處的寫 `src_note`）。
2. `data/life_skills.json`：`yield[].n`、`yield[].min_level`、`yield[].chance`、`recipes[].inputs[].n`、`output.n`、`jing_cost`、`cooldown_s`、`min_level`；新配方 `rc_*`；新的可選欄位（綁定名稱）：
   - `success_base`（float，預設 0.5）、`success_per_level`（float，預設 0.005）——配方或技能列；`LifeSystem.success_chance(level, row, recipe)` 改成讀它們（上限 0.95 不變）；
   - `yield[].n_per_levels`（int，預設 0＝不變）：每多 N 級，採集數量上下限各 +1（隨等級提升收入）。
3. `data/npcs.json` 只改既有 NPC 的 `shop.items`（加或移除原料）——**移除**要確認沒有任務或 bot 依賴（`grep` 任務 `BUY`／驗收 bot）。
4. **不准**：改 `SELL_RATE`、`NpcSystem.sell_price`、`price_pct`、`reactions.json`、怪物掉落與 `money`、打寶表。

### 4.5 報表格式（`econ_hourly` 每條鏈一行）

```
econ_hourly  ok    ma_tailor   L10 self 312/h (0.62×P1)  L30 self 1840/h (0.71×P2)  L50 shop 6900/h (0.62×20k)
econ_loop    ok    商店材料循環 0 條（最低買價 95%）
```

---

## 5. D：帶走角色（WP-CARRY）

### 5.1 檔案格式

**護照**（既有，`Passport.make`）不變。**匯出檔**（新；`<資料根目錄>/exports/<角色名>_<世界id>_<YYYYMMDD-HHMM>.jychar.json`）：

```json
{ "kind": "jy_char_export", "v": 1, "exported_at": "2026-10-20T21:30:00",
  "game_version": "0.6.1.0", "protocol": 5, "content_fp": "9d24a2e10ccc",
  "world_name": "jy2001", "passport": { …護照字典… } }
```

匯入接受兩種：匯出檔（取 `passport`）或裸護照（`passports/<world>/<char>.json`）。檔案大小 > 256 KB 或 JSON 壞掉 → 客戶端直接說「檔案無法讀取」，不送出；`var_to_bytes(passport) > Protocol.PASSPORT_MAX_BYTES` → 主機 `bad_value:passport`（既有）。

### 5.2 匯出（客戶端）

- 角色選擇畫面每列「匯出」→ 有本機護照（`SaveManager.load_passport(world_id, char_id)` 成功、且 `online_s` 與清單一致）就直接寫；否則送 `passport_request`，收到 `passport` 事件後寫。
- `SaveManager.export_character(passport: Dictionary, meta: Dictionary) -> String`（回傳寫好的絕對路徑；失敗回 "" 並設 `last_error`）；`SaveManager.exports_dir() -> String`（`<資料根目錄>/exports/`，不存在就建）。
- 成功後訊息（第三輪審查改成三行）：「已匯出到：」／<路徑>／「把這個檔案給朋友，他在自己的世界按「匯入角色」。」；失敗寫中文原因（紅字）＋「開啟資料夾」鈕（`OS.shell_open`）。

### 5.3 誰可以匯入

`GameHost.foreign_allowed() -> bool` = `NetworkManager.mode == OFFLINE` **或** `options.allow_foreign_characters == true`。不允許 → `foreign_disabled`（既有）。

標題畫面「區網開房」「Steam 開房」旁加核取「允許外來角色」（預設不勾；存到該世界 `options.json` 的 `allow_foreign_characters`）；伺服器設定面板加同一個開關（既有 key 已在可改清單 `world_server.gd:331`）。

### 5.4 截斷與驗證（`core/character/foreign_import.gd`，`class_name ForeignImport`，純邏輯；客戶端預覽與主機共用）

```gdscript
## 回傳 { "ok": bool, "reason": String, "char": Dictionary（已截斷、可直接 Character.from_dict）,
##        "dropped": Array[String]（給人看的清單，例 "未知物品 x_abc ×2"、"錢莊存款（留在原世界）"）,
##        "summary": { name, gender, sect, sect_name, combat_xp, money, items_n, top_skills: [[name, level]] } }
static func sanitize(passport: Dictionary, tables: Dictionary, rules: Dictionary, options: Dictionary) -> Dictionary
```

順序與規則（綁定）：
1. `Passport.check_format`（簽章**不**驗：別的世界無法驗證）；不合 → `foreign_bad_data`。
2. `Character.from_dict` 往返一次；失敗 → `foreign_bad_data`。
3. **身分與 id**：`identity`、`id` 由主機在寫入時換（§5.6）；`origin_world` = 護照的 `world_id`；`ext.foreign = { "world_id", "world_name", "char_id", "saved_s", "imported_s", "dropped" }`。
4. **屬性**：每項截到 [13, 30]（創角 13–25 ＋自由點 5）；總和 ≤ 7×25＋5。
5. **技能**：資料裡沒有的 id 拿掉；每項等級 ≤ `SkillBook.max_level_of`；非生活技能 ≤ `DerivedStats.art_level_cap(截斷後的實戰)`；特殊武功數 ≤ `Character.SPECIAL_ARTS_MAX`（多的從最低等級開始拿掉）；所屬門派不在本世界啟用的門派／era 裡 → 該派武功保留，`sect` 清空並列「門派 X 本世界沒有開放」。
6. **數值**：實戰 [0, 10,000,000]；學點 ≤ `rules.xuedian_cap`（>0 時）；銀兩 ≤ `options.bank_money_cap`（6,000,000）；善惡 [−1000, 1000]；殺氣、PK值、名聲、歷練 ≥ 0 且 ≤ 資料或規則的上限（沒有上限的取 1,000,000）；精氣神內力 ≤ 衍生上限；飽食飲水 ≤ 上限。
7. **物品**：未知 id、`quest_item: true`、`no_transfer`（若有）拿掉；堆疊截到 `stack`；裝備欄裡的東西不符合裝備條件 → 卸到背包；負重超過 `carry_max` → 從最重的開始拿掉並列出。
8. **神兵**：交給主機（§5.5）；`sanitize` 只把它們標出來（`summary.divine: [item_id]`），預覽寫「神兵視主機登記而定」。
9. **世界綁定的狀態重設**（R11）：錢莊存款與物品、組織、袋位待升、進行中的任務、任務冷卻、`counters` 中的冷卻與打獵、監獄／禁學／犯戒狀態、屍體參照、記錄點與位置（→ 本世界出生城的記錄點；出生城不在本世界 era → 西夏）、隊伍與郵件。保留：完成過的任務與旗標、門派與公敵／叛徒記號（門派存在時）、外觀、`online_s`。

預覽（客戶端）用 `GameData.tables`、`GameData.rules`、目前世界的選項（`ClientState` 已有）跑同一個 `sanitize`。

### 5.5 神兵（`server/loot_system.gd` 的 WP-CARRY 區塊）

```gdscript
## 外來角色帶進來的神兵：世界登記（world.json divine）沒人持有 → 登記給 ch、保留；有人持有 → 從 ch 拿掉、回傳名稱清單
func on_foreign_import(ch) -> Array
```

取代（§5.6）時先把舊的本地角色從登記中撤銷，再對新資料呼叫。

### 5.6 `passport_import` 主機流程（`server/intents/intents_host.gd`，取代現在只回 `foreign_disabled` 的版本）

參數：`passport: Dictionary`（必）、`new_name: String`（可選，Q1）。

順序（第一個不成立就回原因碼）：
1. `foreign_allowed()` → 否則 `foreign_disabled`；
2. `Passport.check_format` → `foreign_bad_data`；
3. 護照 `world_id` == 本世界 → `foreign_same_world`（客戶端提示改用「用護照還原」）；
4. `ForeignImport.sanitize` → `foreign_bad_data`；
5. 登記鍵 `key = "<origin world_id>/<origin char_id>"`；`reg = ws.world.foreign_imports.get(key)`：
   - 有登記且 `passport.saved_s <= reg.saved_s` → `foreign_not_newer`；
   - 有登記、本地角色還在，但屬於別的身分 → `foreign_owned`；
   - 有登記、本地角色還在、屬於自己 → **取代**（本地 id 不變）；該角色在線或在戰鬥中 → `char_active`；
   - 沒登記（或登記的本地角色已刪除）→ 新角色：本身分角色數已滿 → `too_many_chars`；
6. 名字：用 `new_name`（若有，驗證同 `char_create`，不合 → `bad_value:new_name`）否則護照名字；被**別的**存在角色佔用 → `passport_name_taken`（客戶端彈出改名欄）；
7. 寫入：`identity = s.identity`；新角色的 `id` 用 `CharacterStore` 產新 id；`LootSystem.on_foreign_import`；`save_char`；`register_name`；`ws.world.foreign_imports[key] = { "char_id", "identity", "saved_s", "imported_s": now_s }`；`ws.save_now()`；
8. 送 `foreign_imported { name, replaced: bool, dropped: [String] }`、`s2c_char_list`；回 `ok({ "char_id" })`。

角色清單的摘要（`Character.to_summary` 由 WP-CARRY 加鍵，§9.2）：`foreign: bool`（`origin_world != ""`）、`origin_world_name`。角色選擇與屬性視窗名字後加「（外來）」。

### 5.7 單機讀 Steam 身分的角色（R13）

- 只在 `NetworkManager.mode == OFFLINE` 且 session `is_local`。
- **可選身分** `GameHost.alt_identities(s) -> Array[Dictionary]`：
  - 列出本世界 `characters/` 底下所有身分資料夾（`SaveManager.list_identities(world_id) -> PackedStringArray`，新）；
  - Steam 正在執行且登入（`SteamManager` 有 SteamID）→ 只提供 `steam_<目前 SteamID>`（有那個資料夾才列），`needs_confirm: false`；
  - Steam 沒開 → 提供所有 `steam_*`，`needs_confirm: true`；
  - 一律另外提供本機身分（`local_*`，目前連線原本的身分），讓玩家換回來。
- `push_char_list`：本身分的角色照舊；再附上每個可選身分的角色，摘要多 `identity`、`alt: true`、`needs_confirm`。
- `char_select { char_id, identity? }`：`identity` 有值且 ≠ `s.identity` → 必須在 `alt_identities(s)` 裡，否則 `alt_identity_denied`；通過就把 `s.identity` 換成它（並記到 `ws.world.known_identities`），再走原本的選角流程。
- 客戶端：清單分組「本機角色」「Steam 角色（steam_7656…1234）」；`needs_confirm` 的先跳確認：「這個角色屬於另一個 Steam 帳號（steam_…）。用單機玩會直接改動這份存檔，之後用 Steam 開房也是這份。確定？」。
- README 新節「把世界給朋友」（整合者寫）：關掉遊戲 → 把 `userdata\worlds\<世界>\` 整個資料夾複製給朋友 → 朋友放進自己的 `userdata\worlds\` → 標題畫面「單機遊玩」選那個世界（`--world=<世界>` 或世界清單）→ 角色選擇裡會看到 Steam 角色。

### 5.8 介面（`ui/game/char/**`，WP-CARRY）

- `char_select.gd`：按鈕列加「匯入角色」；每列加「匯出」；外來角色名字後「（外來）」；分組與確認（§5.7）。
- 新 `ui/game/char/import_dialog.gd`（`class_name ImportDialog`）：檔案選擇（`FileDialog`，`ACCESS_FILESYSTEM`，篩選 `*.json`，起始資料夾 `<資料根目錄>/passports/`；「護照資料夾」「匯出資料夾」「瀏覽…」三個快捷）→ 預覽（§5.4 summary＋dropped 清單，可捲動）→「確定匯入」；收到 `passport_name_taken` 時顯示改名欄再送一次（帶 `new_name`）；`foreign_same_world` 時提示改用「護照 → 用護照還原」。
- 不允許時「匯入角色」灰掉、滑鼠提示「主機沒有開放外來角色」。

---

## 6. E：標題版本列與拒絕訊息（WP-CARRY）

### 6.1 `core/util/build_info.gd`（`class_name BuildInfo`，新，純靜態）

```gdscript
static func version() -> String          # ProjectSettings "application/config/version"，空時 "0.0.0"
static func protocol() -> int            # Protocol.VERSION
static func fingerprint12(content_hash: String) -> String   # 去掉 "sha256:" 取前 12
static func line(content_hash: String) -> String            # "v0.6.1.0　協定 5　資料 9d24a2e10ccc"（全形空白）
```

`tools/print_build_info.gd` 不改（`export_release.ps1` 照舊）。

### 6.2 標題畫面

`ui/game/title/title_screen.gd`：右下角 `Label`，字級比狀態列小一號、顏色用主題的淡色（muted），內容 `BuildInfo.line(GameData.content_hash)`；滑鼠提示「跟朋友連線前互相對照：協定與資料指紋都一樣才能連線。」。Steam 大廳清單的不相容列（`compatible() == false`）後面加「（主機 v… 協定 … 資料 …）」——大廳 metadata 已有的值才顯示，沒有的不顯示。

### 6.3 拒絕訊息（`autoload/world_server.gd` 拒絕區塊、`ui/game/social/ui_social.gd`）

- 主機：`validate_hello` 回 `protocol_mismatch`／`version_mismatch`／`content_mismatch` 時，送出的 reason 改成 `"<code>|<主機版本>|<主機協定>|<主機指紋12>"`（例 `content_mismatch|0.6.1.0|5|9d24a2e10ccc`）；其他原因照舊只有代碼。
- 客戶端：`reason` 用 `split("|")` 取第一段查原有文字，再加一行：「主機：v0.6.1.0　協定 5　資料 9d24a2e10ccc／你：v0.6.0.0　協定 5　資料 1a2b3c4d5e6f」（自己的值用 `BuildInfo`）。沒有 `|` 的舊主機 → 只顯示原文字＋自己的值。
- 舊客戶端（0.6.0.0）收到帶 `|` 的字串時查不到文字 → 會直接顯示整串（可接受；資料指紋本來就不同）。

---

## 7. 協定增量（`core/protocol.gd` 與 `ui/game/ui_keys.gd`，WP-CARRY；`VERSION` 維持 5）

```gdscript
# ---- M3c2（M3C2_PLAN §7；Q1：純新增，RPC 簽名不變 → VERSION 維持 5） ----
# I_CHAR_SELECT 參數表加 "identity": [TYPE_STRING, false]
# I_PASSPORT_IMPORT 參數表加 "new_name": [TYPE_STRING, false]
const E_FOREIGN_IMPORTED := "foreign_imported"        # ui：{ name, replaced, dropped:[String] }
const E_CH_NO_LP := "ch_no_lp"                        # 系統：{ quest_name, why: "daily"|"novice"|"rule" }
const E_CH_SPAR_CAPPED := "ch_spar_capped"            # 系統：{}
```

新原因碼（模板 `err_<code>`，§0.3 Q6 的前綴）：`foreign_same_world`、`foreign_not_newer`、`foreign_owned`、`foreign_bad_data`、`alt_identity_denied`、`chore_tired`；`req_money_max`、`req_has_item`（若不存在）。既有沿用：`foreign_disabled`、`passport_name_taken`、`too_many_chars`、`char_active`、`bad_value:new_name`。

`char_list` 摘要新增鍵：`identity`、`alt`、`needs_confirm`、`foreign`、`origin_world_name`（客戶端缺鍵時當 false／空）。

---

## 8. 資料、存檔、規則與選項增量（彙總）

### 8.1 存檔（全部增量；舊存檔可讀；Q9）

| 位置 | 欄位 | 預設 | WP |
|---|---|---|---|
| 角色 `counters` | `chore_day: { day: int, n: { quest_id: int } }` | 無 | PACE |
| 角色 `counters` | `spar_day: { day: int, n: int }` | 無 | PACE |
| 角色 `origin_world`（既有） | 來源世界 id | `""` | CARRY |
| 角色 `ext.foreign` | `{ world_id, world_name, char_id, saved_s, imported_s, dropped: [String] }` | 無 | CARRY |
| `world.json` | `foreign_imports: { "<world>/<char>": { char_id, identity, saved_s, imported_s } }` | 無 | CARRY |
| 本機 | `<資料根目錄>/exports/*.jychar.json` | — | CARRY |

### 8.2 規則（`data/rule_profiles.json` 與 `DataSchema.RULE_DEFAULTS`／`RULE_ENUMS`，WP-PACE Day-0）

| 規則 | 型別 | 預設（RULE_DEFAULTS） | classic_strict | classic_standard | later_official | friends_casual |
|---|---|---|---|---|---|---|
| `novice_learn_pct` | int | 100 | 100 | 校準值（初始 1000） | 同 standard | 同 standard |
| `novice_jing_pct` | int | 100 | 100 | 校準值（初始 30） | 同 standard | 同 standard |
| `novice_learn_below` | int | 40 | 40 | 40 | 40 | 40 |
| `chore_xuedian` | bool | false | false | true | true | true |
| `spar_rewards` | bool | false | false | true | true | true |

（RULE_DEFAULTS 用「關」：沒寫的舊自訂組合不會突然變快；四個內建組合明確寫值。）

### 8.3 伺服器選項（`data/server_options.default.json`）

- `spar_daily_cap`（int，30，範圍 0–200；WP-PACE 追加；`INT_FIELDS.server_options` 加；伺服器設定面板加一列——面板檔 WP-CARRY 擁有，WP-PACE 只在 §9.2 准許的區塊加這一列）。
- `allow_foreign_characters`（既有，false）：意義改為「開房時」（§5.3）；不改預設。

### 8.4 Schema（`core/data/data_schema.gd`，WP-PACE 擁有；WP-ECON 只在 §9.2 准許處加）

- `INT_FIELDS.quests` 加 `chore.lp`、`chore.decay_pct[]`、`chore.cost.*`、`chore.prof_below`（WP-PACE）。
- `INT_FIELDS.rule_profiles` 加 `rules.novice_learn_pct`、`rules.novice_jing_pct`、`rules.novice_learn_below`（WP-PACE）。
- `INT_FIELDS.server_options` 加 `spar_daily_cap`（WP-PACE）。
- `INT_FIELDS.life_skills` 加 `yield[].n_per_levels`（WP-ECON，§9.2）。
- `REFS`：`quests.chore.sect` → `sects`（WP-PACE）。

---

## 9. 工作包與檔案所有權

### 9.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-PACE** | `data/quests.json`（追加 `q_ch_*` 列；既有 `q_hg_zaowanke`、`q_xh_maipi`、`q_xh_liandu` 只加 `chore` 欄位與把 `learn_points` 改 0）；`data/npcs.json`（追加 `n_ch_*` 列；`shop.items` 除外）；`data/monsters.json`（只改 `m_*_dizi`、`m_hs_trainee` 的 `no_rewards`、`combat_xp`、`combat_xp_ref`、`learn_points`）；`data/rule_profiles.json`；`data/server_options.default.json`；`data/sects.json`（血刀列 `src_note`）；`core/data/data_schema.gd`（§9.2 的 WP-ECON 區塊除外）；`core/data/data_loader.gd`（若需要）；`core/character/learning.gd`；`core/character/requirements.gd`；`core/battle/battle_status.gd`；`server/quest_system.gd`；`server/sect_system.gd`；`ui/game/dialogs/learn_dialog.gd`；`tools/balance_sim.gd`（§9.2 的 WP-ECON 區塊除外）；`tools/data_lint.gd`（§9.2 的 WP-ECON 區塊除外）；`tools/regen_battle_golden.gd` 的產出（`tests/fixtures/**` 戰鬥金檔，若改變）；新 `tests/unit/test_m3c2_chores.gd`、`test_m3c2_spar.gd`、`test_m3c2_novice_learn.gd`、`test_m3c2_weihe.gd`；**因 A4／B1 而失敗的既有單元測試**（逐一列在交付說明，只改期望值或改傳 `classic_strict`） | §2、§3 |
| **WP-ECON** | `data/life_skills.json`；`data/items.json`（§4.4 准許的列與新列；WP-PACE 只追加 `i_ch_*`，§9.2）；`data/npcs.json` 的 `shop.items` 陣列；`server/life_system.gd`；`core/econ/**`（含 `recipe_check.gd`）；`tools/balance_sim.gd` 的 `# ==== M3c2 WP-ECON ====` 區塊與既有 `case_econ_chain`；`tools/data_lint.gd` 的 `# ==== M3c2 WP-ECON ====` 區塊；新 `tests/unit/test_m3c2_econ.gd`；因改價／配方而失敗的既有生活技能、商店測試（列在交付說明） | §4 |
| **WP-CARRY** | `core/protocol.gd`；`ui/game/ui_keys.gd`；`core/character/foreign_import.gd`（新）；`core/util/build_info.gd`（新）；`core/character/character.gd` 的 `to_summary()`（加 `foreign`、`origin_world_name`）；`server/passport.gd`；`server/intents/intents_host.gd`；`server/intents/intents_char.gd`；`server/character_store.gd`；`server/game_host.gd`；`server/loot_system.gd` 的 `# ==== M3c2 WP-CARRY ====` 區塊；`autoload/save_manager.gd`；`autoload/world_server.gd`；`autoload/client_state.gd`；`ui/game/char/**`（含新 `import_dialog.gd`）；`ui/game/title/**`；`ui/game/social/ui_social.gd`；`ui/game/social/server_options_dialog.gd`；`ui/game/panels/attributes_panel.gd`（名字後「（外來）」一處）；`project.godot`（只改 `config/version`）；`export_presets.cfg`（只改 `file_version`、`product_version`）；新 `tests/unit/test_m3c2_foreign.gd`、`test_m3c2_export.gd`、`test_m3c2_offline_steam.gd`、`test_m3c2_reject_msg.gd`、`test_m3c2_build_info.gd`、`test_ui_m3c2_title.gd`、`test_ui_m3c2_import.gd`；既有護照測試（若需要） | §5、§6、§7 |
| **整合者** | `tests/bots/**`；`tests/ui/ui_playthrough.gd`；`tools/*acceptance*`（新 `tools/m3c2_acceptance.gd`）；`tests/run_tests.gd`；`README.md`；`docs/CHANGELOG.md`（0.6.1.0 一節）；`docs/GDD.md` 等文件同步；本文件 §2.7 | §10 |

### 9.2 共用熱檔的切分（只有這裡列的跨 WP 修改是准許的）

| 檔案 | 擁有者 | 其他 WP 准許的修改（逐字照做，不得多動） |
|---|---|---|
| `tools/balance_sim.gd` | WP-PACE | **WP-ECON**：檔尾區塊 `# ==== M3c2 WP-ECON ====` 內的常數與案例函式（`case_econ_hourly`、`case_econ_loop` 等，名稱以 `econ` 開頭）、`econ2_cases() -> Array`；`_initialize()` 內 WP-PACE 預留的一行 `for c in econ2_cases(): …`（WP-PACE Day-0 先寫好這個迴圈，WP-ECON 只填函式）；既有 `case_econ_chain` 函式本體。WP-PACE 的案例放在 `# ==== M3c2 WP-PACE ====` 區塊、`pace_cases() -> Array`。 |
| `tools/data_lint.gd` | WP-PACE | **WP-ECON**：檔尾 `# ==== M3c2 WP-ECON ====` 內 `_check_m3c2_econ(tables) -> PackedStringArray`，以及 WP-PACE Day-0 預留的主流程呼叫行。 |
| `core/data/data_schema.gd` | WP-PACE | **WP-ECON**：`INT_FIELDS["life_skills"]` 陣列加 `"yield[].n_per_levels"` 一項。 |
| `data/items.json` | WP-ECON | **WP-PACE**：只追加 `i_ch_*` 列（雜務道具：`quest_item: true`、`no_sell: true`、`price: 0`）。 |
| `data/npcs.json` | WP-PACE | **WP-ECON**：只改既有 NPC 的 `shop.items` 陣列。 |
| `data/text_templates.json` | （無單一擁有者） | **只能追加**（Q3）：WP-PACE `ch_*`、`talk_n_ch_*`、`err_chore_*`、`err_req_money_max`、`err_req_has_item`；WP-ECON `econ2_*`、`work_ok_*`／`work_fail_*`（新配方需要時）；WP-CARRY `fi_*`、`err_foreign_*`、`err_alt_identity_denied`、`title_build_*`。不得修改他人或既有列。 |
| `ui/game/social/server_options_dialog.gd` | WP-CARRY | **WP-PACE**：加 `spar_daily_cap` 一列（檔尾區塊 `# ==== M3c2 WP-PACE ====` 的一個函式，與 `_build()` 內呼叫它的一行，行尾註解 `# M3c2 WP-PACE`）。 |
| `core/character/character.gd` | WP-CARRY（只有 `to_summary`） | 其他 WP 不動；WP-PACE 的計數放 `counters`（既有字典）。 |

### 9.3 Day-0（各 WP 開工的第一件事）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-PACE | `balance_sim.gd` 加兩個空區塊與 `_initialize()` 的 `pace_cases()`、`econ2_cases()` 迴圈（`econ2_cases` 先回 `[]`）；`data_lint.gd` 預留呼叫行與空 `_check_m3c2_econ`；`data_schema.gd` 的規則鍵、`RULE_DEFAULTS`、`INT_FIELDS`；`rule_profiles.json` 四組規則；`server_options.default.json` 加 `spar_daily_cap` | WP-ECON 要往裡面填；規則鍵要先存在，`data_lint` 才不會報錯 |
| WP-CARRY | `core/protocol.gd` 的 §7 常數與參數表；`ui_keys.gd`；`core/util/build_info.gd` 空殼（簽名照 §6.1） | 其他 WP 的事件 key（`E_CH_NO_LP`、`E_CH_SPAR_CAPPED`）由 WP-PACE 以字串常數 `Protocol.E_CH_NO_LP` 參照 |
| WP-ECON | 先跑 `balance_sim --case=econ_chain` 存一份基準 log 到 `K:\Project\JY-Mini-OL-Work\logs\m3c2_econ_before.log` | 交付說明要附前後對照 |

### 9.4 凍結檔（M3c2 任何 WP 都不得修改）

`core/battle/battle_formulas.gd`、`core/battle/battle_rewards.gd`、`core/character/derived_stats.gd`、`core/character/skill_book.gd`、`server/npc_system.gd`、`data/reactions.json`、`data/loot_tables.json`、`data/martial_arts.json`、`data/masters.json`、`data/maps/**`（雜務只用既有房間；如果真的需要新房間，寫 `# M3C2_PLAN 缺漏` 並在交付說明提出，由整合者決定）。

---

## 10. 測試計畫

### 10.1 各 WP 的單元與整合測試（全部在 `tests/run_tests.gd` 裡跑，`--filter=m3c2` 可單跑）

- **WP-PACE**：`test_m3c2_chores.gd`（每派至少一件：接／做／交、時辰窗外不能接、冷卻、`chore_tired`、遞減 100/60/30/0、換日重設、40 級後學點 0、`classic_strict` 學點 0 但熟練照給、`prof_below`）；`test_m3c2_spar.gd`（打贏給、`spar_daily_cap`、規則關、輸了不給）；`test_m3c2_novice_learn.gd`（倍率、精最少 1、門檻 40、只影響 `learn`、`classic_strict` 不變）；`test_m3c2_weihe.gd`（§3.3）。
- **WP-ECON**：`test_m3c2_econ.gd`（`success_base`／`success_per_level`、`n_per_levels`、新配方可做、循環檢查函式對構造的循環資料報錯）。
- **WP-CARRY**：`test_m3c2_foreign.gd`（所有原因碼；截斷每一類；未知物品／技能清單；神兵登記空／被佔；重複匯入舊／新；取代保持本地 id；同世界拒絕；單機允許、開房依選項）；`test_m3c2_export.gd`（檔名、內容、目錄只在資料根目錄下、裸護照與匯出檔都能讀）；`test_m3c2_offline_steam.gd`（Steam 有／沒有 → 清單與 `needs_confirm`；換身分後存檔寫回 `steam_*` 資料夾；非 OFFLINE 回 `alt_identity_denied`）；`test_m3c2_reject_msg.gd`（三種原因的字串格式、客戶端解析、舊格式相容）；`test_m3c2_build_info.gd`（`line()` 格式、`project.godot` 與 `export_presets.cfg` 版本一致）；`test_ui_m3c2_title.gd`、`test_ui_m3c2_import.gd`。

### 10.2 平衡（`tools/balance_sim.gd`）

既有 128 個案例全過，加：`pace_<sect>`（11 派；丐幫用 1.0A＋1.0B 視圖）、`chore_bot_cap`、`xd_weihe_uplift`（WP-PACE）；`econ_hourly`、`econ_loop`（WP-ECON）；`econ_chain`／`econ_no_loss` 照舊。

### 10.3 驗收：`tools/m3c2_acceptance.gd`（整合者；`--only=<劇本>`；全部用測試根目錄下的新世界）

| 劇本 | 內容 | 通過條件 |
|---|---|---|
| `chores` | 新角色（男）走到少林拜師 → 把時鐘撥到卯時 → 接「挑水」、在竹林挑水、交差 → 再接一次（冷卻中被拒）→ 等冷卻過、第 2 次 → 檢查學點遞減；精不夠時交差回 `chore_tired`；`classic_strict` 世界同流程學點 0、熟練度有加 | 學點 +50、+30；熟練度 `basic_body` 增加；原因碼正確 |
| `chores_all` | 11 派各做一件「全天」雜務（1.0A＋1.0B 世界；用除錯傳送到山門、`debug_set` 加入門派） | 每件都完成、有獎勵事件 |
| `novice` | 少林新弟子向師父學佛法 10 次：熟練度 = 11 × 倍率、精 = max(1, 10 × 精倍率)；把佛法設到 40 再學：回到原值 | 數值相符 |
| `spar` | 切磋 31 場（`spar_daily_cap` 設 30）：前 30 場有實戰與學點、第 31 場 `ch_spar_capped` | 相符 |
| `weihe` | 血刀弟子（威嚇 100）對木樁怪打 2000 次的統計（用 `BattleStatus` 直接跑，不經網路）：觸發率 ∈ [0.20, 0.25]、觸發倍率 1.4 | 相符 |
| `econ` | 新角色學裁縫與織布、種麻：做一條完整鏈並賣掉 → 銀兩增加；另外用商店買得到的材料做 `econ_loop` 檢查過的每一個配方 → 賣掉後銀兩一定比買材料前少 | 相符 |
| `carry_export_import` | 世界 A 建角色、給物品（含一件未知物品 id 寫進存檔、一把神兵）、匯出 → 世界 B（單機）匯入：外來標記、未知物品被拿掉並在清單、數值截斷（把實戰改成 99,999,999 的那份 → 10,000,000）、神兵登記到新角色；再匯入同一份 → `foreign_not_newer`；在 A 玩一下再匯出新的 → 匯入取代、本地 id 不變、角色數不變；第三個世界已有人持有那把神兵 → 匯入後神兵不在、清單有寫 | 全部相符 |
| `carry_hosted` | ENet 開房（`allow_foreign_characters` 關）→ 客戶端匯入回 `foreign_disabled`；主機打開 → 成功 | 相符 |
| `offline_steam` | 在測試世界手動放一個 `characters/steam_76561190000000001/` 角色檔 → 單機開（`--no-steam`）→ 角色清單有它、`needs_confirm: true` → `char_select { identity }` → 進入世界、移動、存檔 → 檔案寫回那個資料夾、`local_*` 資料夾沒有多出角色 | 相符 |
| `title_line` | 開標題畫面：版本列文字 = `BuildInfo.line(GameData.content_hash)`、以 `v0.6.1.0` 開頭 | 相符 |
| `reject_msg` | 用測試鉤子讓客戶端送錯的 `content_hash` 握手 → 客戶端訊息含主機與自己的指紋 | 相符 |

### 10.4 介面驗收（`tests/ui/ui_playthrough.gd`，整合者加步驟；截圖 `K:\Project\JY-Mini-OL-Work\shots\`）

標題畫面版本列；角色選擇（匯入鈕、匯出鈕、外來標記、Steam 角色分組與確認框）；匯入預覽視窗；學藝視窗「新手加速」字樣；雜務任務在任務清單與對話。headless 與有視窗各一次，0 警告。

### 10.5 回歸（全部要綠，整合者驗收時逐一跑）

`tests/run_tests.gd`（0 failed）、`tools/data_lint.gd`（0 錯誤）、`tools/balance_sim.gd --runs=500`、`tests/ui/ui_playthrough.gd`（headless＋有視窗）、M1 驗收 bot（測試根目錄的新世界）、`tools/m2_acceptance.gd`、`tools/m3a_acceptance.gd`、`tools/m3b_acceptance.gd`、`tools/m3c_acceptance.gd`、`tools/m3c2_acceptance.gd`、`tools/story_acceptance.gd --all`、`tools/net_smoke.gd`、`close_mid_battle_bot`（`--close-mode=wm` 與 `quit`）。每次跑完 `tasklist /FI "IMAGENAME eq Godot*"` 確認沒有殘留。

---

## 11. 交付與整合

1. 每個 WP 交付說明：改了哪些檔（對照 §9.1）、新 id 清單、校準後的數字（WP-PACE：§2.7 四項；WP-ECON：`econ_hourly` 前後對照表）、因本包而改的既有測試（逐一列出原因）、`# M3C2_PLAN 缺漏` 清單、戰鬥金檔差異（若有）。
2. 整合者：合併 → `--import` → §10.5 全部 → 填 §2.7 → README（雜務、新手加速、切磋獎勵、威嚇、製作賺錢、匯入／匯出角色、把世界給朋友、單機讀 Steam 角色、標題版本列）→ `docs/CHANGELOG.md` 0.6.1.0 → `export_release.ps1` 匯出（**不碰** `JY-Mini-OL-Release\userdata\`，匯出前後雜湊比對照舊）→ dist zip 到 `K:\Project\JY-Mini-OL-Dist\`。
3. 版本：0.6.1.0；連線協定 5；資料指紋會改變（雜務、價格、規則都進 `content_hash`）→ 朋友要一起更新。

---

## 12. 開放問題（不擋開工；預設值已選）

| # | 問題 | 預設 |
|---|---|---|
| Q1 | 潛能點數是否等於學點（古墓、全真切磋） | 當作學點【待考證】，十派切磋都給 |
| Q2 | 雜務的時辰窗（原文「早上／早中晚」）對應的時辰 | 卯辰巳／卯午酉【待考證】 |
| Q3 | 交易之道影響收購價（2001 約 0.75→1.0） | 不做，M3d 候選 |
| Q4 | 城鎮學點任務（送便當、酒鬼、小虎、李大嬸、阿虎、鬥酒） | M3d 候選，可用 `chore` 欄位做遞減 |
| Q5 | 木人巷（三門 50＋卸裝）當「少林第二階段」的正式門檻 | M3d 以後；本包用 P2 參考角色 |
| Q6 | 外來角色在多人世界是否要給其他玩家看到「外來」標記 | 只在自己的角色選擇與屬性視窗顯示 |

## 13. 整合紀錄（2026-10-20，整合者）

**結果**：`run_tests` 1660 個 0 失敗；`data_lint` 0 錯誤；`balance_sim --runs=500` 143 案例 0 失敗；`m3c2_acceptance` 12 劇本全過；
M1 驗收 bot、`m2`／`m3a`／`m3b`／`m3c` 驗收、`story_acceptance --all`、`net_smoke`、`close_mid_battle_bot`（wm、quit）全過；
介面驗收 headless 與有視窗（截圖 `K:\Project\JY-Mini-OL-Work\shots\m3c2\integrate\`，第 22 步 `m3c2_*`）都 `UI_PLAY_OK`、0 警告。
資料指紋 `96cdbf897d9b`（0.6.0.0 是 `9d24a2e10ccc`）。

**整合時的修改與偏差**（照契約，較好的偏差寫在這裡）：

| # | 修改 | 理由 |
|---|---|---|
| I1 | 新增少林切磋弟子：NPC `n_sl_spar`（`sl_wuchang`，FIGHT，限少林）＋怪物 `m_sl_dizi`（少林長拳 3、氣 180、`learn_points` 20）＋ `talk_n_sl_spar`、美術 alias【設計提案】 | §2.3.3 要「十派切磋」，但少林原本沒有切磋弟子 → `pace_shaolin` 100 輪全部超過 12 小時。少林入門武功要先有佛法 10，新手打不贏一般強度的弟子，所以這位比較弱、學點較少（20） |
| I2 | 雜務 NPC `n_ch_*` 寫進 `data/maps/**` 的房間清單（§9.4 凍結檔的整合例外），`data_lint` 拿掉 WP-PACE 的 `n_ch_*` 豁免 | 和其他 NPC 一樣由地圖列出；`test_every_npc_room_is_consistent` 照舊嚴格 |
| I3 | `BattleSystem` 在發放獎勵前呼叫 `SectSystem.spar_adjust`（傳這場打倒的全部怪物與 1/√人數分成） | WP-PACE 缺漏 3：結果框顯示的就是真的發出去的量，不再事後收回 |
| I4 | `spar_daily_cap` 加進 `AdminSystem.EDITABLE_KEYS`（0／5／10／20／30／50／100／200 場） | WP-PACE 缺漏 4：面板那一列可以改 |
| I5 | 雜務與切磋的「遊戲日」改用 `WorldClock` 的 day（子時換日）；`balance_sim` 的 `_pace_day` 同步 | 原本用 `now_s / day_s`，換日點落在辰時（新世界從辰時開始），和時辰窗、畫面上的「第 N 日」對不上；驗收抓到 |
| I6 | **`Character.to_combatant` 帶上 `combat_xp`** | 既有 bug（M1 起）：主機上每場戰鬥都當成玩家實戰 0，實戰 ×2、學點 ×3 永遠吃到上限；GDD 公式與 `balance_sim` 都是依實戰遞減。修好後老手打低階怪拿得比以前少。`test_m3c_review2` 全真硬闖的斷言改成「一場 4 人 30–160」（研究更正：160 是一整趟 17–18 人的總數） |
| I7 | `test_data_content` 的計數與期望（NPC 262、怪物 118、1.0A 任務 110、丐幫雜務 1.0B、知客僧與齋堂僧多 QUEST、切磋弟子 `no_rewards` false）；`test_world_admin` 面板 13 個可改選項；`test_m3c2_spar` 加 `m_sl_dizi` | 本包資料的直接結果 |
| I8 | 角色選擇的狀態列：匯入成功改用金色（原本和錯誤一樣是紅字） | 截圖檢查 |
| I9 | 驗收 `chores`：學點期望值照資料（挑水 80、掃地 30／18），同日第 2 次用「掃地」量（挑水只在卯時、冷卻 1.2 時辰，同一天做不了第 2 次）；`chores_all`／`spar` 用 `SectSystem.on_join` 直接入派；`novice` 用知客僧教佛法（0 級與 40 級）；`econ` 的技能等級用 `debug_set`、自己收成的麻（§4.3：買種子的鏈本來就該虧，WP-ECON 已說明）；`offline_steam` 把 bot 的 session 標成本機（單機的玩家是本機 session） | 測試捷徑，受測物不變 |

**擁有者決定（整合者的預設）**：少林切磋弟子較弱、學點 20（I1）；少林雜務學點保留 WP-PACE 的高值（§2.7）；修正戰鬥獎勵的實戰比例（I6，會讓老手練功變慢，但符合 GDD 與平衡模擬）；雜務／切磋子時換日（I5）。

**下一步（M3d）**：懸賞與賞金獵人、輕功「輕」與「閃」、合體技、門派比武、劫鏢（範圍見 §1.2 第一點）。

## 14. 審查修正紀錄（2026-10-20，三份審查：節奏與經濟、帶走角色、介面）

**結果**：`run_tests` 0 失敗；`data_lint` 0 錯誤；`balance_sim --runs=500` 143 案例 0 失敗；`m3c2_acceptance` 12 劇本全過；其餘閘門見交付說明。
§2.7 的數字已改成這一輪的量測。

### 14.1 節奏（A5 的量法改了）

| # | 審查 | 修正 |
|---|---|---|
| P1 | 「第二階段」角色打不過鬼（勝 0%） | `pace_<派>` 的門檻加上 P2 參考角色其餘部分：本派輕功、基本輕功各 20、修練到氣上限 660（`Survival.meditate`，每次精 2、10 秒），最後要通過門檻角色 vs `m_ghost` 勝率 ≥ 70%、剩氣 ≥ 25%（不過就再加碼修練與武功，最多 6 次，仍不過判 FAIL）。防具照創角布衣（比 P2 的粗布道袍嚴）。報表另列「技能數字到門檻」的時數 |
| P2 | 35–55% 時間站著等 | 空檔依序：雜務 → 學藝 → 切磋 → 打坐修練 → 出門練功 → 才等；報表多「實際操作」（扣掉純等待）。學費付不起時改挑掉錢的怪練功（丐幫新手身無分文、武館教頭收錢） |
| P3 | 學點主要來自切磋、新角色一場切磋 75 學點 | 切磋一場最多 `Learning.SPAR_LP_MAX` 30 學點（`SectSystem.spar_adjust` 與模擬一致）；切磋實戰 200 → 100（一天切磋不再單獨就超過 9000 實戰）；十派雜務學點上調（每派一天理論最大 312–595，仍 ≤ 600）。雜務佔學點 19–35%：**擁有者決定 O1** |
| P4 | 防刷只看本派武功 < 40 | 新規則 `novice_xp_below`（30000）：實戰到了就不算新手（雜務、切磋學點與新手學藝加速都停；老手換門派不會重新算）；`novice_lp_cap`（4000）：雜務＋切磋學點一輩子上限（`counters.novice_lp`）。`Learning.novice_mults` 另看實戰 |
| P5 | 全真 3.71 小時 | 全真 3.24；所有門派 3.16–3.69（表 §2.7）。帶寬照 §1.1 A5：少林 2.5–3.5、血刀 2.0–5.0、其他 2.0–4.5：**擁有者決定 O2** |
| P6 | 少林幫農、學佛沒做；煮飯的人不對；+30 熟練沒標 | 新 `q_ch_sl_bangnong`（務農僧 `n_ch_sl_wunong`，菜園，精 10，農夫）、`q_ch_sl_xuefo`（知經僧，大雄寶殿，神 15，佛法；證道院／達摩洞本作沒有【設計提案】）；煮飯改由火工頭陀 `n_ch_sl_huogong`（齋堂；gonglue 寫普剛），齋堂僧只剩齋飯。少林雜務學點重排（挑水 70、其餘 20–50，一天理論最大 595）。所有 `q_ch_*` 的 `src_note`／`chore.src_note` 加「熟練 +N 的數字【待考證】」 |

### 14.2 經濟

| # | 審查 | 修正 |
|---|---|---|
| E1 | 10 級打獵每小時 3.87 倍 | 打獵一場的時間改用戰鬥基準同一個模型（行動數 × 2 ＋ 60 秒，原本固定 30 秒）；打獵精 10 → 13；野味、獸皮、豬肉 15 級、兔皮 11 級才剝得下來。10 級 0.86 倍；`hunt_tailor` 另加「不超過 0.9 倍」檢查 |
| E2 | 製作不如賣原料、22 條配方超出 0.3–1.5 | `econ_hourly` 新檢查：製作鏈在 30、50 級的最佳產物必須是製作技能的成品；`econ_chain` 超出 0.3–1.5 倍改為不通過（0 條）。槓桿：低階配方精降低（3–8）、高階成品精提高並調價（菜飯 22／133、烤鰻魚 22／128、焦炭 20／120、紫紋鐵塊 33、冷凝劍 140／1730、棉襖 58／431、皮甲 28、兔皮帽 14／80、鋼刀／青鋒劍 14／480…）、粗布道袍改麻布 ×1＋線軸 ×1、精 17；種子不收購（`no_sell`）、麻種子 30、棉種子 60；工匠新配方 `rc_zhangmuxiang` 樟木箱（45 級、樟木 ×4、精 30、`r_zhangmuxiang` 195，1.0B）；織布冷卻 4 秒、裁縫 5 秒。裝備改價都在 ±40% 內，`loot_econ_*`、`armor_full_kit` 照過 |

### 14.3 帶走角色

| # | 審查 | 修正 |
|---|---|---|
| C1 | 刪角後同一份檔案能再匯入 | 登記一直留著：`saved_s ≤ 登記` 一律 `foreign_not_newer`（本地角色在不在都一樣）；`passport_restore` 遇到已被較新匯入取代的外來角色回 `foreign_superseded`（新原因碼） |
| C2 | A → B → A 回流 | `foreign_same_world` 另看角色的 `origin_world`、`ext.foreign.world_id`、`ext.foreign.via`（新：來源鏈），以及「用本世界密鑰驗得過的護照（world_id 被改過）」與「角色 id 是本世界現有的角色」 |
| C3 | 取代時洗掉本世界的錢莊、組織、坐牢、冷卻 | `ForeignImport.keep_local_world_bound`：錢莊、組織、袋位待升、進行中的任務與冷卻、counters、坐牢、門派犯戒／禁學、buffs、其他系統的 ext、位置沿用本地角色 |
| C4 | 整個世界給朋友＝給密鑰 | README「把世界給朋友」加警告：**擁有者決定 O5** |
| C5 | 怪型別讓引擎報錯 | `CharData.to_str`：`Character.from_dict`、`Inventory.from_dict` 的字串欄位只收字串（審查的 probe 不再出現 SCRIPT ERROR） |
| C6 | 同 uid 兩件 | `sanitize` 只留第一件並列清單；主機寫入前每件物品換新編號（裝備欄跟著換） |
| C7 | 用戶端 256 KB／主機 64 KB 不一致 | `ForeignImport.parse_text` 先算 `var_to_bytes(passport)`，超過 `Protocol.PASSPORT_MAX_BYTES` 回 `passport_too_large`；匯入視窗遇到 `bad_value:passport` 也寫「檔案無法讀取」 |
| C8 | 外來角色還能動到經濟（第一份 #7） | 開房且沒開放時，已匯入的外來角色 `char_select`／`passport_restore` 回 `foreign_char_blocked`（新原因碼）；外來角色最多 10 萬兩（`ForeignImport.FOREIGN_MONEY_CAP`）、2 件珍品（`FOREIGN_TREASURE_MAX`）。神兵照 R10：**擁有者決定 O4** |

### 14.4 介面

角色清單放進可捲動容器（最高 330）、列文字固定寬度截斷＋滑鼠提示；匯入預覽：同世界只顯示提示與摘要、讀不了寫原因（太大／不是 JSON／不是角色檔／角色資料太大）、檔案清單高度對齊整列、預覽底部留白；開匯入視窗或出現新狀態訊息時收起舊的匯出列；Windows 路徑用反斜線；Steam 確認框用縮寫；一般進度訊息淡色；學藝視窗「新手期」一行（金色、不帶內部標記）；製作窗賣價小字；雜務第一階段標題「到某處做某事」（不再「撿柴：撿柴」）；`ui_playthrough` 第 22 步加 Steam 分組與確認框、壞檔、同世界檔、改名列的截圖，打寶路徑每個失敗都留原因。

### 14.5 擁有者決定（這一輪的預設）

| # | 決定 | 理由 |
|---|---|---|
| O1 | 雜務不是最大的學點來源（19–35%），切磋 54–70% | 一天 600 學點的雜務上限（§2.5 防掛機）與「約 3 小時」不能同時讓雜務佔一半；切磋本身也是門派內的修練（研究：古墓、全真切磋增加潛能）。要雜務為主就得放寬 600 上限或接受更慢的節奏 |
| O2 | 節奏帶寬照 §1.1：少林 2.5–3.5、血刀 2.0–5.0、其他 2.0–4.5；量到 3.16–3.69 | 丐幫（1.0B，3.69）、血刀（3.55）、古墓（3.49）略超 3.5：師父收學費、晚上休息、練功點遠；全真已回到 3.24 |
| O3 | 新手期：實戰 30000、雜務＋切磋學點一輩子 4000 | 足夠走完第二階段（門檻約 1–1.5 萬實戰、雜務＋切磋約 2500 學點）；之後就只是一般玩法 |
| O4 | 外來神兵仍照 R10（本世界沒人持有就帶入） | 匯入無法驗證；若要更嚴可改成神兵一律不帶 |
| O5 | 「把世界給朋友」只加警告，不換密鑰 | 給了資料夾就等於給了主機密鑰；自動換密鑰會讓原世界的護照全部失效 |
| O6 | 外來角色上限 10 萬兩、珍品 2 件 | 匯入是複製；數字【設計提案】 |
| O7 | 打獵 10 級收入壓到 0.86 倍（精 13、額外剝皮割肉 11／15 級） | R7：生產收入低於同階段戰鬥 |

## 15. 第二輪審查修正紀錄（2026-10-21：節奏與經濟、帶走角色、介面）

**結果**：`run_tests` 1691 個 0 失敗；`data_lint` 0 錯誤；`balance_sim --runs=500` 143 案例 0 失敗；`m3c2_acceptance` 12 劇本全過；M1 驗收 bot、`m2`／`m3a`／`m3b`／`m3c` 驗收、`story_acceptance --all`、`net_smoke`、`close_mid_battle_bot`（wm、quit）全過；介面驗收 headless 1 次、有視窗 3 次連續 `UI_PLAY_OK`、0 警告（截圖 `K:ProjectJY-Mini-OL-Workshotsm3c2_rev3win1–3`；log `K:ProjectJY-Mini-OL-Workogsm3c2_rev3`）。

### 15.1 節奏與經濟

| # | 審查 | 修正 |
|---|---|---|
| A1 | 外來角色用高價輕巧的消耗品（守護者之煙、大還丹、千年人參）繞過 10 萬兩上限，而且改個 `char_id` 就能一直匯 | `ForeignImport._clamp_value`：**銀兩＋身上物品收購總值**（`EconCalc.sell_price`；神兵另算）≤ `FOREIGN_MONEY_CAP`，先拿掉背包單價最高的、再卸最貴的裝備，剩下的額度才是銀兩；主機另限每個身分最多 3 個不同來源角色（`foreign_quota`，見 C4） |
| A2 | 10 級製作鏈會賠錢（麻→線軸 −887/h）、燒炭 10 級沒配方，閘門沒檢查 | `econ_hourly` 新檢查：每條製作鏈 10 級的最佳成品每小時 > 0；例外 `ECON2_L10_CRAFT_EXEMPT` 只列研究的等級擋住的兩條（燒炭 20 級＝研究炭爐 30 已壓縮、麻要種田 21 級），報表寫「練功期」：**擁有者決定 O8**。`mine_sword` 10 級做單刀 112/h（> 0）不算問題 |
| A3 | 節奏模型 80–99% 的實戰、54–70% 的學點來自切磋；`chore_bot_cap` 只算雜務 | `chore_bot_cap` 多一行 REPORT：每派「雜務＋切磋（30 場 × 一場最多 30）」一個遊戲日的理論最大學點與一輩子上限 4000；「約 3 小時」是照雜務＋切磋的新手路線量的：**擁有者決定 O9** |
| A4 | 新世界匯入會把 `counters.novice_lp` 歸零 | `sanitize` 保留 `novice_lp`；取代時取本地與檔案較大的（同 C3） |
| A5 | 峨嵋禪修 殺氣 −50 沒標 | 結果的 `src_note` 加「殺氣 −50 的數字【設計提案】」 |

### 15.2 帶走角色

| # | 審查 | 修正 |
|---|---|---|
| C1 | 取代匯入讓 `online_s` 倒退 → 取代前存的本世界護照被當成較新而可還原（複製） | `keep_local_world_bound`：`online_s = max(檔案, 本地) + 1` |
| C2 | `qi_bonus`、`cultivations` 只截到 1,000,000 | `_clamp_cultivation`：修練次數 ≤ 基本內功 × `CULTIVATE_PER_INNER`、氣加成 ≤ 次數 × `CULTIVATE_QI` |
| C3 | 同 A4 | 同 A4 |
| C4 | 偽造檔案可以帶進任何沒人持有的神兵（繞過全服 12 時辰鎖），也能一直改來源鍵重匯 | 外來神兵**預設一律拿掉**（新伺服器選項 `allow_foreign_divine`，預設 false，只能改 `options.json`；true 才照 R10 登記）；每個身分在本世界最多 `FOREIGN_SOURCES_PER_IDENTITY`＝3 個不同來源角色（登記永久，刪角也算；已登記來源的更新不算）→ 新原因碼 `foreign_quota`：**擁有者決定 O4（改）、O11** |
| C5 | Steam 大廳只比協定，同協定不同資料的大廳看起來相容 | 主機的大廳資料多 `ver`、`fp`（`BuildInfo.fingerprint12(content_hash)`）；`TitleLobby.compatible` 協定相同且（有 fp 時）指紋相同才可加入；舊主機沒有 fp → 只看協定 |
| C6 | `Protocol.GAME_VERSION` 還是 "0.1.0" | **保留**（R14）：它是握手相容字串，不是標題顯示的版本；在 `core/protocol.gd` 註明用途。指向 `BuildInfo.version()` 會讓資料相同的小版本互相連不上 |

### 15.3 介面

| # | 審查 | 修正 |
|---|---|---|
| U1 | 有視窗的介面驗收第 21 步不穩（續走等待中又遇敵；戰鬥中點「停」） | `ui_playthrough` 的 `_resume_world_walk`：遇敵就打、回地圖、等續走，最多 6 輪；小地圖「停」之前先把戰鬥打完 |
| U2 | 外來角色列的房名被截掉 | 角色列兩行：名字（外來）性別／門派 實戰 所在 |
| U3 | Steam 列的「進入江湖」位置不同 | 每列右邊固定寬的按鈕欄（`RowActions`，靠左） |
| U4 | 「開啟資料夾」被撐高 | `SIZE_SHRINK_CENTER` |
| U5 | 角色選擇框隨內容上下跳 | 框上緣固定（`FRAME_TOP` 48），只左右置中 |
| U6 | 匯入視窗、Steam 確認框後面沒遮罩 | `ModalDim` 半透明遮罩（擋滑鼠），任何彈出視窗開著就顯示 |
| U7 | 「賣店約」、價格欄不齊 | 「收購價約 N 兩（材料約 M 兩）」；配方按鈕撐滿、右邊「缺什麼」「收購價」兩欄固定寬；製作窗 640 → 820 寬 |
| U8 | 匯入視窗資料夾用正斜線 | `ImportDialog.display_path`（角色選擇的匯出訊息共用） |
| U9 | 預覽寫「物品 0 件」、拿掉的清單被切掉 | 錢莊只寫非 0 的部分；預覽 200 → 250 高，內容比可視區高時下面寫「清單較長，往下捲動可以看全部。」 |
| U10 | 分組標題的全形空白與內部前綴 | 「本機角色（目前）」「Steam 角色（7656…1234）」；確認框用同一個縮寫 |

### 15.4 擁有者決定（這一輪的預設）

| # | 決定 | 理由 |
|---|---|---|
| O4（改） | 外來神兵預設一律拿掉；主機打開 `allow_foreign_divine` 才照 R10 | 匯入檔無法驗證；神兵全服唯一、掉落有全服鎖，偽造的檔案不應該能拿到 |
| O8 | 10 級時燒炭、種麻→裁縫兩條鏈只有採集收入（製作是練功期） | 研究：炭爐 30 級（本作 20）、麻要種田 21；把它們提前會偏離研究，買種子照 R8 一定虧 |
| O9 | 新手「約 3 小時」以雜務＋切磋為主要路線；只打野外會比較慢 | 一天雜務 ≤ 約 600、切磋 ≤ 900，合計受一輩子 4000 學點限制；要更依賴野外就得放寬雜務或拉長節奏 |
| O10 | 外來角色實戰上限仍是 10,000,000、完成的任務與旗標照帶 | 誠實的老角色要能帶走；偽造的強角色只影響接受外來角色的世界（開房預設關），重複匯入已被錢、珍品、神兵、來源數上限擋住 |
| O11 | 每個身分在一個世界最多 3 個不同來源的外來角色（刪了也算）【設計提案】 | 和每身分 3 個角色一致；擋「改來源編號無限匯入」 |

## 16. 第三輪審查修正紀錄（2026-10-21：帶走角色的複製漏洞、節奏標示、介面）

**結果**：`run_tests` 1699 個 0 失敗（之後介面測試再跑一次 11 個 0 失敗）；`data_lint` 0 錯誤；`balance_sim --runs=500` 143 案例 0 失敗；`m3c2_acceptance` 12 劇本全過；M1 驗收 bot（全新世界）、`m2`／`m3a`／`m3b`／`m3c` 驗收、`story_acceptance --all`、`net_smoke`、`close_mid_battle_bot`（wm、quit）全過；介面驗收 headless 與有視窗都 `UI_PLAY_OK`、0 警告（截圖 `K:\Project\JY-Mini-OL-Work\shots\m3c23fix2`；log `K:\Project\JY-Mini-OL-Work\logs\m3c2_r3fix`）。

### 16.1 帶走角色

| # | 審查 | 修正 |
|---|---|---|
| D1 | 檔案沒有簽章、`saved_s` 可以改大：取代時錢莊留本地、銀兩與物品卻從檔案重新給 → 「匯入 → 存錢莊／給別人 → 改 `saved_s` 再匯」無限複製；刪掉本地角色再匯也一樣 | 取代時 `ForeignImport.keep_local_goods`：**銀兩與身上物品（含裝備）沿用本地角色**，只更新成長；清單多一行「銀兩與身上物品沿用本世界的…」。已登記的來源但沒有本地角色可沿用（刪了、或本地檔讀不到）→ `ForeignImport.strip_goods`：銀兩 0、身上空，清單寫「第一次匯入時已經帶進過」：**擁有者決定 O12** |
| D2 | NaN 的 `saved_s`：`saved_s <= NaN` 永遠 false（無限重匯），存進 world.json 變 null，下次讀檔 `float(null)` 中斷 | `Passport.check_format` 拒絕非有限的 `saved_s`；`sanitize` 把角色字典裡所有 NaN／INF 換成 0（`ForeignImport.finite_floats`，含 `online_s`）；`SaveManager._coerce_world` 的 `saved_s`／`imported_s`／`world_time_s`／`sent_s`／`created_s` 與 `deleted_character_online_s` 改用 `CharData.to_float`（舊檔的 null 讀成 0） |
| D3 | 取代時 `loot.on_char_deleted` 把本地角色在本世界合法拿到的神兵登記撤掉、背包換成檔案的 → 神兵無聲消失 | 同 D1：取代沿用本地背包，不再撤銷神兵登記、不對本地背包做外來神兵處理（只有本地檔讀不到時才撤銷） |
| D4 | 本地角色刪掉後，別的身分可以用較新的檔案接手登記，原身分的來源名額空出一格 | 登記永遠屬於第一次匯入的身分：`e.identity != s.identity` 一律 `foreign_owned`（不論本地角色在不在）：**擁有者決定 O13** |
| D5 | 規則 `xuedian_cap` 0（`classic_strict`、`friends_casual`）時匯入不截學點 | `ForeignImport.FOREIGN_LP_CAP_FALLBACK`＝65200（同 `RULE_DEFAULTS`）【設計提案】 |
| D6 | ENet 的身分是用戶端自報的，每身分 3 個來源的名額可以換身分繞過 | 不改機制（同 NAT 的朋友會被 IP 名額誤擋）；README 註明 LAN 開房時只對信得過的朋友打開「允許外來角色」：**擁有者決定 O16** |

### 16.2 節奏與經濟、資料標示

| # | 審查 | 修正 |
|---|---|---|
| E1 | 「約 3 小時」是機器人（不離開門派、不看選單）的最佳情況 | `pace_<派>` 另列「含真人操作」（每場戰鬥＋25 秒、每件雜務＋25 秒、每次學藝＋0.5 秒；只報告不當條件）；README 表格多一欄、GDD／CHANGELOG 註明 3 小時是最佳情況：**擁有者決定 O15** |
| E2 | 打獵→皮革→裁縫 30／50 級只有 0.36／0.03 倍 | 照研究「獵人 71 還沒有看到賺錢的曙光」保留；README 註明：**擁有者決定 O14** |
| E3 | `later_official` 帶著【設計提案】的加速 | 照 §8.2 的表（同 standard）保留，加 `src_note` 說明「後期官方」只指死亡、屍體、叛派、不掉神兵，加速是【設計提案】：**擁有者決定 O17** |
| E4 | 11 個切磋弟子 `src: proposal` 沒有 `src_note` | 每列加 `src_note`：研究只證實古墓、全真（武當抱太極 17173 2001-07-08）、其他派【設計提案】；「潛能」是不是學點【待考證】 |
| E5 | `q_ch_xd_jiu`、`q_ch_hs_tiaoshui`、`q_ch_hs_kanchai`、`q_ch_hg_chaihuo` 只有標題已證實卻標 `verified` | 整列改 `proposal`，`src_note` 寫「【已證實】（只有標題…）」 |

### 16.3 介面

| # | 審查 | 修正 |
|---|---|---|
| V1 | 匯出失敗顯示 `passport_bad_format`、`commit tmp failed (…)`，一般字色 | `CharSelect.export_error_text`：中文原因、`ErrorLabel` |
| V2 | 預覽「門派 xiaoyao 本世界沒有開放」露出內部 id | 改「原門派本世界沒有開放（武功保留，門派身分清除）」 |
| V3 | 製作窗被配方長字撐到約 970 寬，蓋住小地圖左緣 | 製作窗固定 900（`CraftWindow.WIDTH`），兩欄 110／210，配方按鈕 `clip_text`＋「…」、完整內容在滑鼠提示；截圖量到右緣約 915（小地圖 950） |
| V4 | 「打打鐵鎚」 | `rc_tiechui` 改名「鍛打鐵鎚」（攻略同步） |
| V5 | 匯出訊息在檔名中間換行、按鈕列下空約 40 px | 訊息三行：「已匯出到：」／路徑／說明；空的狀態列隱藏（不佔位）。路徑本身比欄寬長時仍會在路徑裡換行 |
| V6 | 匯入視窗隨狀態改大小、出現改名欄時整個往上跳；第 4 個檔案只能靠細捲軸 | 匯入視窗上緣固定在 `FRAME_TOP`（不再置中）；改名欄放進按鈕列右邊（出現時高度不變、按鈕不動）；預覽 250 → 230 讓整個視窗放得進 720；檔案清單下寫「共 N 個檔案（，清單往下捲動可以看全部）」；讀不了的檔案多一行「請選別的檔案…」。壞檔時預覽區仍留白（保持視窗大小不變） |

### 16.4 擁有者決定（這一輪的預設）

| # | 決定 | 理由 |
|---|---|---|
| O12 | 再次匯入同一個來源只更新成長；銀兩與身上物品沿用本地角色；刪後再匯不帶錢與物品（每個來源的錢與物品只帶一次） | 護照無法驗證，`saved_s` 可改；只有這樣才不能靠重匯複製錢與寶物 |
| O13 | 來源登記永遠屬於第一次匯入的身分 | 刪角後別的身分接手會空出原身分的名額 |
| O14 | 打獵鏈 30、50 級幾乎不賺，保留 | 研究「獵人 71 還沒有看到賺錢的曙光」；其他鏈照「可以賺錢」 |
| O15 | 「約 3 小時」是機器人的最佳情況；含真人操作另列、只報告 | 真人多約 1.0–1.2 小時（含真人操作中位數 4.23–4.86）（看選單、讀字、學藝點擊）；要真人 3 小時得再加快新手學藝，偏離更多 |
| O16 | ENet 不加 IP 名額 | 朋友常在同一個 NAT 後面；LAN 身分本來就不可信，README 註明只對信得過的朋友打開外來角色 |
| O17 | `later_official` 照 §8.2 保留新手加速、雜務學點、切磋獎勵，用 `src_note` 標明 | 要忠實節奏用 `classic_strict`；改掉會讓「後期官方」比預設慢很多 |
| — | 匯入學點上限 65200（規則不限時）【設計提案】 | 同 `RULE_DEFAULTS.xuedian_cap` |
