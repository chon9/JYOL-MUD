# M2 實作計畫：Steam 合作連線與 PK（M2_PLAN）

> 版本：2026-10-18（整合完成，見第 8 章）。協調者撰寫；實作中只由協調者（整合者）修改本文件。
> 上游：GDD §6、§10、§12、§13.1 M2 列；TECH_ARCH §6–§11、§15.4；M1_PLAN（既有協定，本文件只寫**增量**）；WORLD_2001；AUTHENTIC_UI_SPEC；docs/research/verified_research.md。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

M2 由 5 個工作包（WP）**同時**實作，實作者之間不溝通。規則完全沿用 M1_PLAN 0.1：

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent、事件 key、原因碼、伺服器選項 key、存檔欄位、資料列 id** 都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定。
3. 本文件 > M1_PLAN > GDD > TECH_ARCH。偏差列在 2.3。
4. 發現缺漏：照「最不意外」實作，程式裡寫 `# M2_PLAN 缺漏：……`，交付說明列出；**不要**改別人的檔案。

### 0.2 標記

沿用 GDD 第 0 章：【已證實】【後期版】【待考證】【設計提案】。本文件新增的數值一律是【設計提案】，資料列 `src` 填 `"proposal"`。

### 0.3 全域規則

M1_PLAN 0.3 的 G1–G10 全部繼續有效（主機權威、離線同一路徑、`core/**` 純邏輯、文字放資料、JSON 數字轉 int、不 commit、測完關掉 godot 並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認、新增 `class_name` 後先 `--import`、不新增 Autoload、不改 `project.godot`）。M2 另加：

| # | 規則 |
|---|---|
| H1 | **不新增任何 `@rpc` 方法**（`WorldServer`、`ClientState` 都一樣）。Godot 的 RPC 編號依方法表產生，加方法會讓舊版客戶端連 `c2s_hello` 都解錯，握手就無法乾淨地回 `protocol_mismatch`。主機 → 客戶端的新資料一律走既有的 `s2c_events`（`"ui": true` 事件）、`s2c_sheet`、`s2c_region_view`、`s2c_battle_open/close`。 |
| H2 | `Protocol.VERSION` 由 2 升為 **3**（intent 集合與 `chat` 語意改變）。Steam 大廳的 `proto` 欄位自動跟著變。 |
| H3 | 新的主機系統一律 `extends RefCounted`，建構子 `_init(p_host: GameHost)`，有 `var host` 欄位，`GameHost.dispose()` 會把它設成 null。 |
| H4 | **容錯接線**：`GameHost` 以路徑 `load()` 建立 M2 新系統與新 intent 檔（見 4.6.1），檔案不存在或載入失敗時該系統為 `null`，所有呼叫點先判斷 `!= null`。這讓各 WP 在別人的檔案還沒寫好時，自己的測試仍能載入。 |
| H5 | 時效（邀請、叫戰）用**真實秒數**：世界時間的到期點 = `now_s() + ttl_real_s × time_scale`（`GameHost.world_span(real_s)`，WP-HOST 提供）。`--time-scale=50` 時 60 秒的邀請不會在 1.2 秒內過期。 |
| H6 | 玩家輸入的文字（聊天、信件、名字）在主機端先清理：去掉控制字元、`[`→`［`、`]`→`］`（與 `WorldServer._clean_name` 相同），避免 BBCode 注入。WP-HOST 提供 `GameHost.clean_text(text, max_len) -> String`。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=party]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500 [--case=party4_vs_bandit_chief]
"$G" --headless --path . --script res://tools/net_smoke.gd -- --no-steam
"$G" --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam [--timeout=1500]
```

---

## 1. 現況盤點（M1 結束時已有什麼）

| 項目 | 已有（可重用，不要重寫） | M2 要補 |
|---|---|---|
| 主機權威骨架 | `WorldServer.c2s_intent` 單一入口、token bucket 20/s、`Protocol.validate_args`、`c2s_hello` 握手（protocol／版本／content_hash／identity／banned／滿員）、5 秒 hello 逾時、事件批次 `s2c_events`、本地短路 | 重連時取代舊 session、管理員判定、`--stop-file`、`--opts`、伺服器選項面板、文字清理 |
| 傳輸 | Offline／ENet／Steam 三種；`NetworkManager.kick()`（`s2c_kicked` + 0.5 秒後斷線）；Steam 大廳建立／加入／邀請覆蓋介面／`+connect_lobby` 冷啟動／搜尋 | `reconnect()`、記住上次連線目標、遊戲中接受邀請的流程、斷線畫面的「重新連線」 |
| 房間內其他玩家 | `view.players[]`（peer、name、char_id）、`room_enter/leave`、`char_entered/left` | 善惡顏色、新手、隊伍、戰鬥中 |
| 戰鬥 | `Battle` 支援多個玩家單位、side 0/1、等待模式 10.7（人數縮短逾時、每輪預算、afk 3 秒）、斷線改自動防、`BattleRewards` 已用 `1/√n` 分享 | 開戰拉入同房隊友、中途加入（`Battle.add_unit` 目前只在 SETUP 可用）、PvP（side 1 是玩家時結果要依 side 判定）、重連接回戰鬥 |
| 屍體 | `CorpseSystem`：建立、本人拾回、1800 秒到期；`world.json.corpses`；view.corpses | 授權撿取、公開期、他人撿取、單件撿取、公開通知 |
| 聊天 | M0 `_intent_chat`：千里傳音廣播，不耗水；UI 頻道鈕與 13 頻道開關（只有千里傳音可發話） | 7 個發話頻道 + 天外飛仙、耗水、謠言匿名、密語 |
| PK 欄位 | `Character.morality / killing_intent / pk`（存檔有）；`server_options.pk_mode = "CLASSIC"`、`newbie_pk_protect_xp = 500`；`regions.pk_allowed`；守衛 NPC（`kind: GUARD`，西夏東門、大理北門、京城南門） | 叫戰、強制 PK、PK值遞減、殺氣、善惡變化、守衛攻擊 |
| 飛鴿 | `world.json.mail = []`；HUD「鴿」圓章（「尚未開放」） | 整個信件系統 |
| 存檔 | 原子寫入 + bak1–5、60 秒自動存檔、離線／關服存檔、world_time_s、corpses、角色 online_s | 存檔新欄位、重開後完整恢復的驗證、護照 |
| 護照 | `SaveManager.passport_path()`；`world.json.world_secret` | 簽章、送出、還原、（P2）外來角色 |
| 選項 | `data/server_options.default.json`（已有 pk_mode、wait_mode、stagecoach_enabled、allow_foreign_characters…） | 新 key、面板、執行中修改 |

---

## 2. M2 範圍、偏差與驗收

### 2.1 範圍清單（逐項打勾；括號是負責 WP）

- [x] **主機權威強化**（HOST）：重連取代舊 session；管理員判定；文字清理（H6）；`passport` 等大參數的大小上限；`--stop-file`、`--opts`；關服前廣播 `host_closing`。
- [x] **組隊**（PARTY）：邀請／接受／拒絕／離開／踢人／移交領隊；上限 5；邀請 60 秒過期；系統開關「接受組隊邀請」（PK 擁有角色欄位，見 4.6.5）；離線或換角即離隊；主機重開時隊伍全部解散。
- [x] **多人同場戰鬥與中途加入**（PARTY）：遇敵、NPC 定點戰開戰時，同房、閒置的隊友自動入場（守衛戰不拉，2026-10-18 第二輪審查）；之後走進同房的隊友可「加入戰鬥」（`battle_join`）；一場最多 8 名玩家；實戰／學點依 GDD 2.4 的 `1/√n` 分享給勝利時還站著的參戰者（中途加入者同樣算）；掉落與銀兩歸最後一擊者；等待模式 10.7 在 8 人時仍成立（`test_battle_pacing.gd` 量測）；斷線者重連後接回原戰鬥。
- [x] **聊天頻道**（SOCIAL）：千里傳音、傳音入密、輕聲細語、門派、組織（M2 一律回 `no_guild`）、隊伍、江湖謠言（匿名）、天外飛仙（只限管理員）；耗水規則見 5.4；未選角的 session 只能用千里傳音且不耗水（保持 M0 行為，`net_smoke` 綠燈）。
- [x] **叫戰**（PK）：同房 = 視線範圍；對方同意才開打；可關「接受叫戰」；不加 PK值。
- [x] **強制 PK**（PK）：UI 以「連結鍵」+ 點玩家名發動（預設 Ctrl，系統窗「特殊開關」可改成 Alt／Shift，存在 `settings.json` 的 `ui.pk_key`）；只在 `pk_allowed` 地區；新手保護；擊殺 +1 PK值；PK值依角色上線時間每 30 分鐘 −1（惰性計算）。
- [x] **殺氣、善惡**（PK）：殺玩家 +100 殺氣；強制擊殺非惡人 −10 善惡（原 −50，2026-10-18 第二輪審查）、擊殺惡人 +10；名字顏色（惡藍、中立黃、善白）。
- [x] **守衛**（PK）：PK值 > 3 或善惡 < 0 的角色進出城（跨越 CITY 地區邊界）時，守城官兵開戰。
- [x] **PK 模式**（PK）：`pk_mode` = `CLASSIC`（預設）／`CHALLENGE_ONLY`／`OFF`。
- [x] **屍體與授權撿取**（PK）：保護期本人與授權者可撿，之後公開；授權最多 4 人；可單件撿；公開時通知擁有者；`corpse_window` CLASSIC_30／LATER_10。
- [x] **飛鴿傳書**（SOCIAL）：寄給任何角色名（離線也收得到），存在主機 `world.json`；上線時提醒；收件匣上限；HUD 鴿章閃爍。
- [x] **角色護照**（HOST）：主機在自動存檔、離開世界、玩家要求時送出 `passport` 事件；客戶端存到 `user://passports/`；同一世界的災難復原（驗章）；簽章誠實說明。外來角色匯入是 **P2**（可延後，見 2.2）。
- [x] **主機離線＝世界凍結**（HOST 主導、各 WP 配合）：關服時戰鬥 ABORTED、待決邀請／叫戰丟棄、隊伍解散；角色、屍體（含授權名單與剩餘時間）、信件（含已讀）、任務、世界時鐘、PK值、禁止名單完整恢復。
- [x] **伺服器選項面板最小版**（HOST 邏輯、UI 畫面）：只限管理員；可改 死亡規則（`rule_profile` 預設組合）、`pk_mode`、`wait_mode`、`stagecoach_enabled`；執行中修改只影響之後的事件。另有管理員踢人／禁止。
- [x] **Steam 大廳流程**（HOST 邏輯、UI 畫面）：邀請、遊戲中接受邀請（先離開目前連線）、冷啟動、斷線後「重新連線」、踢人與禁止、主機關閉時客戶端顯示「主機已離線，江湖凍結」。
- [x] **UI**（UI）：隊伍面板、邀請／叫戰提示框、玩家名右鍵選單、Ctrl+點強制 PK 確認、頻道選擇（含密語對象）、飛鴿視窗、屍體撿取視窗、伺服器選項面板、管理員名單、大廳／重連畫面、PvP 戰鬥畫面（我方在 side 1 時左右鏡像）。

### 2.2 M2 不做（明確延後）

| 項目 | 延到 | 理由 |
|---|---|---|
| 副主機 `BACKUP_HOST`（TECH_ARCH 8.5） | M4 | 擁有者已定「主機離線時世界凍結」；副主機會造成存檔分岔 |
| 外來角色匯入 `passport_import`（`allow_foreign_characters`） | **P2**：M2 有時間才做，否則 M3 | 需要數值截斷與主機確認流程；預設關閉，不影響驗收 |
| 懸賞與賞金獵人牌照（GDD 13.3 列 M2） | M3 | 需要捕快 NPC 與衙門，M3 與京城一起做 |
| 陣形（GDD 13.3 列 M2） | M3 | M3 才有「陣」指令與陣法資料 |
| 神兵利器 PvP 轉移給擊殺者【已證實】 | M3 | 目前沒有任何物品標成神兵；M3 加 `items.divine` 欄位時一起做 |
| 好友名單、好友交談 | M3 | GDD 13.1 M2 列沒有；密語已可用角色名 |
| 組織（幫會）與組織頻道內容 | M3 | 組織頻道保留，一律回 `no_guild` |
| 殺氣消除 NPC（大理，每 10 點 100 兩） | M3 | 2001 年是否存在【待考證】 |
| `SceneMultiplayer.auth_callback` 握手改寫 | M4 | H1：M2 不動 RPC 表 |
| 觀戰 | M3 | TECH_ARCH 10.6 已列 M3 |
| 門規：受戒／開除（依 PK值、殺氣、善惡、殘殺同門；`sects.json` 的 `expel_rules`）【已證實 少林】 | M3（2026-10-18 第二輪審查後記錄） | GDD 13.1 把門規列在 M3；M2 讓 PK值與殺氣變成真的數值，但沒有讀 `expel_rules` 的程式，`sect_rules.json` 也沒有列。**M2 期間少林弟子強制 PK 同門、殺氣破 2000 都不會被受戒或開除**；M3 與京城衙門、坐牢一起做 |
| Alt+Space 切換聊天紀錄的顯示模式（GDD 10.1【已證實】） | M3（2026-10-18 第二輪審查後記錄） | 原作只說「切換顯示模式」，沒寫有哪幾種模式；照字面猜等於發明。另外 Windows 視窗模式下 Alt+Space 會打開系統的視窗選單，要先確認攔得下來。目前可用系統窗「螢幕對話開關／頻道開關」 |
| 「屍體漂浮」開關（GDD 6.4【已證實】存在） | M3（2026-10-18 審查後記錄） | 只確認有這個開關，**它做什麼**原作資料沒寫（研究 verified_research.md 283 行）；照字面猜行為等於發明規則。查到說明再做。「授權撿取」M2 已做 |
| 撤銷屍體授權 | M3（2026-10-18） | 原作只說「授權撿取」；M2 的屍體視窗已列出已允許的人與名額（`authorized_names`／`auth_max`），撤銷要新 intent，等有需要再加 |

### 2.3 與 GDD／TECH_ARCH 的偏差（M2 決議）

| # | 原文 | M2 決議 | 理由 |
|---|---|---|---|
| D1 | GDD 13.1 驗收「4 人組隊打**馬王**」 | 改打新增的**山賊頭目**（狼嚎丘，隊伍級精英【設計提案】）；鬼王留在手動清單 | 馬王洞（華山）還沒做成地區（M3 內容）；4 個新角色不可能練到鬼王洞的 1 萬實戰 |
| D2 | TECH_ARCH 6.5 新 RPC `s2c_passport` | 改成 `ui` 事件 `passport` | H1 |
| D3 | TECH_ARCH 8.4「hello 帶上護照還原」 | 改成握手後、選角前的 intent `passport_restore` | 握手只做身分與版本檢查，比較單純 |
| D4 | TECH_ARCH 10.3「斷線者 30 秒後移除」 | 沿用 M1：斷線單位自動防到戰鬥結束；同一角色重連後**接回**原戰鬥（4.6.2 `reattach`） | 拔線逃不掉死亡；隊友不會少一個人 |
| D5 | GDD 10.5／系統開關「顯示名稱」 | 純客戶端設定（`UiSettings`），主機不管 | 只影響自己的畫面 |
| D6 | `corpse_window` 兩種值 | 數字相同：保護 600 秒、1800 秒消失。差別只在文件來源；LATER_10 的消失時間原作沒寫，取 1800【設計提案】 | 誠實記錄：目前兩個值行為一致。伺服器設定面板在規則組合下面顯示說明，「後期官方」寫明「原作沒寫何時消失，暫用 30 分鐘（目前和懷舊的屍體時間相同）」（2026-10-18 第二輪審查） |
| D7 | 叫戰是否受 `pk_allowed` 限制（原作不明） | 叫戰與強制 PK 都只能在 `pk_allowed == true` 的地區 | 任務要求；城裡有守衛，規則好懂 |
| D8 | 隊伍內 PvP | 禁止（`target_in_party`）；想切磋先離隊。叫戰之後才組隊的，接受時也回 `target_in_party`（2026-10-18 第二輪審查） | 避免中途加入時不知道站哪一邊 |
| D9 | GDD 10.2「參戰的隊員都能分享經驗【已證實】」 | 只分給**勝利時還站著**的參戰者（含中途加入）；戰死、逃走的不分 | 【設計提案】，沿用 M1 行為（5.1）。原作只說「參戰的隊員」，沒說死掉、逃走的算不算；GDD 10.2 已加註這個偏差（2026-10-18 第二輪審查） |

### 2.4 最終驗收（M2 完成的定義）

1. `tests/run_tests.gd`：0 failed，總數 ≥ 486 + 各 WP 新增。
2. `tools/data_lint.gd`、`tools/net_smoke.gd`：通過（net_smoke 不改，見 3.2）。
3. `tests/ui/ui_playthrough.gd` headless：`UI_PLAY_OK`。
4. M1 驗收 bot：三種死亡規則各跑一次（新世界名）＋網路版一次，都 `M1_ACCEPT_OK`。
5. `tools/balance_sim.gd --case=party4_vs_bandit_chief` 與 `--case=solo_vs_bandit_chief` 達到 4.9 的目標。
6. **`tools/m2_acceptance.gd`：1 個 ENet 專用主機 + 4 個 bot**，印 `M2_ACCEPT_OK`、結束碼 0。內容（細節見 6.3）：
   - 組成 4 人隊伍（含一次拒絕再邀請），隊伍頻道、密語、謠言；
   - 走到狼嚎丘，3 人開戰時被拉入，第 4 人中途 `battle_join`，打贏山賊頭目，勝利時還站著的人都有實戰（整合修訂：戰死者依 5.1 不分，4 人都有實戰不一定成立）；
   - 在 `pk_allowed` 的東門外官道：叫戰被拒、關閉接受叫戰、強制 PK 殺死另一人（PK值 = 1）；
   - 擊殺者撿屍被擋（`corpse_protected`），死者授權隊長，隊長在保護期內撿走 1 件；
   - 寄信給**離線**角色、寄信給在線角色；
   - 主機以 `--stop-file` 正常關閉、重開：隊伍已解散、PK值、屍體（同 id、同件數）、信件（含已讀狀態）、世界時間都恢復；離線收件人重新上線收到 `mail_waiting`。
7. 擁有者跑 6.5 的 Steam 兩帳號手動清單。

---

## 3. 工作包與檔案所有權

### 3.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-PARTY** | `server/party_system.gd`（新）、`server/battle_system.gd`、`server/intents/intents_party.gd`（新）、`server/intents/intents_battle.gd`；`core/battle/**`；`data/monsters.json`、`data/npcs.json`、`data/maps/*.json`；`tools/balance_sim.gd`；`tests/unit/test_battle*.gd`（既有＋新）、`tests/unit/test_party*.gd`（新）、`tests/unit/test_world_battle.gd`、`tests/unit/test_world_party.gd`（新）；`tests/fixtures/battle_*.json` | 4.6.2–4.6.3；組隊、拉入、中途加入、PvP 戰鬥核心、重連接回、獎勵分享、8 人節奏；**Day-0 資料列**（4.9） |
| **WP-PK** | `server/pk_system.gd`（新）、`server/corpse_system.gd`、`server/intents/intents_pk.gd`（新）；`core/rules/morality_pk.gd`（新，`class_name MoralityPk`）；`core/character/**`；`tests/unit/test_character*.gd`、`tests/unit/test_pk*.gd`（新）、`tests/unit/test_world_pk.gd`（新）、`tests/unit/test_world_corpse.gd`（新）、`tests/unit/test_world_death.gd` | 4.6.4–4.6.5；叫戰、強制 PK、PK值、殺氣、善惡、守衛、屍體授權與公開；角色新欄位 |
| **WP-SOCIAL** | `server/social_system.gd`（新）、`server/mail_system.gd`（新）、`server/intents/intents_social.gd`（新）；`tests/unit/test_social*.gd`（新）、`tests/unit/test_world_chat.gd`（新）、`tests/unit/test_world_mail.gd`（新） | 4.6.6–4.6.7；頻道、耗水、謠言、密語、飛鴿 |
| **WP-HOST** | `autoload/world_server.gd`、`autoload/network_manager.gd`、`autoload/steam_manager.gd`、`autoload/save_manager.gd`、`autoload/client_state.gd`；`server/game_host.gd`、`server/session.gd`、`server/character_store.gd`、`server/region_system.gd`、`server/admin_system.gd`（新）、`server/passport.gd`（新）、`server/intents/intents_char.gd`、`server/intents/intents_host.gd`（新）；`core/protocol.gd`；`core/data/**`；`tools/data_lint.gd`、`tools/validate_data.gd`；`data/text_templates.json`、`data/server_options.default.json`、`data/rule_profiles.json`；`tests/unit/test_world_server.gd`、`test_world_fixture.gd`、`test_world_chars.gd`、`test_world_move.gd`、`test_world_clock.gd`、`test_save_manager.gd`、`test_protocol_m1.gd`、`test_protocol_m2.gd`（新）、`test_world_persist.gd`（新）、`test_passport.gd`（新）、`test_world_admin.gd`（新）、`test_data_loader.gd`、`test_data_content.gd` | 4.1–4.5、4.6.1、4.6.8–4.6.10、4.7、4.8；**Day-0 協定與文字補丁**（3.3）；測試基底的多玩家輔助（4.6.10） |
| **WP-UI** | `ui/**`（全部）、`autoload/scene_router.gd`；`tests/unit/test_ui*.gd` | 4.10 的全部畫面；TextRenderer 頻道顏色與新 key；PvP 鏡像 |
| **整合者**（協調者本人，非並行 WP） | `tests/ui/ui_playthrough.gd`、`tests/ui/ui_driver.gd`、`tests/bots/**`（含新 `tests/bots/m2_party_bot.gd`）、`tools/m2_acceptance.gd`（新）、`README.md`、`docs/**` | 第 6 章的 bot 與驗收；修 M1 bot／ui_playthrough 因 M2 行為改變而壞的地方 |

未列出的既有檔案（`server/npc_system.gd`、`quest_system.gd`、`life_system.gd`、`world_index.gd`、`world_clock.gd`、`server/intents/intents_move.gd`／`intents_npc.gd`／`intents_self.gd`／`intents_item.gd`／`intents_quest.gd`，以及其餘 `tests/unit/test_world_*.gd`）歸 **WP-HOST**，但 M2 原則上不需要改它們。

**`data/text_templates.json` 的擁有權決定**：只有 WP-HOST 能改。所有 M2 新 key 的完整文字都寫在本文件 4.4 與 4.3，WP-HOST 在 Day-0 一次加齊（含 `talk_n_bandit_chief`）。其他 WP 不碰這個檔案；文字想潤飾，寫在交付說明裡，由整合者處理。這樣同一個 JSON 檔不會有多人同時編輯。

### 3.2 凍結檔（M2 任何 WP 都不得修改）

`project.godot`、`autoload/game_data.gd`、`autoload/bgm_player.gd`、`core/util/*`、`tests/run_tests.gd`、`tests/test_case.gd`、`tests/unit/test_core_util.gd`、`tests/bots/chat_bot.gd`、`tools/net_smoke.gd`、`tools/steam_api_probe.gd`、`tools/check_vendor.ps1`、`tools/iso_gallery.gd`、`tools/import_art.py`、`addons/**`、`assets/**`、`data/art.json`、`data/eras.json`、`data/patches/**`、其餘未列 `data/*.json`、`docs/**`。

> `test_core_util.gd` 測 `Protocol.validate_args` 與 `TextRenderer`：WP-HOST、WP-UI 必須保持它綠燈。`net_smoke` 的 bot 沒有角色、只發千里傳音：SOCIAL 必須保留「無角色 → 千里傳音、不耗水」的路徑。

### 3.3 Day-0（各 WP 開工的第一件事，先於其他程式）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-HOST | (1) `core/protocol.gd`：照 4.1 加齊所有常數、`INTENT_SCHEMA`、`INT_RANGES`、`ENUMS`、`CHAT_CHANNELS`、`VERSION = 3`；(2) `data/text_templates.json`：加齊 4.3、4.4 的全部列；(3) `data/server_options.default.json`：加齊 4.7 的 key；(4) `tools/data_lint.gd`：`REQUIRED_TEMPLATE_KEYS`／`UI_ONLY_KEYS`／`TEMPLATE_VARIANTS` 加上新 key；(5) `GameHost` 容錯接線骨架（4.6.1）；(6) `test_world_fixture.gd` 多玩家輔助（4.6.10）與 `ClientState.capture_remote`（4.6.9） | 其他 WP 引用 `Protocol.I_*` 常數、需要模板通過 lint、需要多玩家整合測試基底 |
| WP-PARTY | `data/monsters.json` 加 `m_bandit_chief`、`m_city_guard`；`data/npcs.json` 加 `n_bandit_chief`（4.9 的列，原樣貼上） | WP-PK 的守衛戰與整合測試需要 `m_city_guard` |

其他 WP 開工時若 Day-0 還沒落地：先寫純邏輯（`core/rules/morality_pk.gd`、系統類別本身）與不依賴新常數的單元測試；程式裡可以暫用與 4.1 **完全相同**的字串字面值，交付前改回 `Protocol.*` 常數。

### 3.4 依賴

```
WP-HOST Day-0 ──┬──▶ WP-PARTY ─┐
WP-PARTY Day-0 ─┼──▶ WP-PK ────┼──▶ 整合者：m2_party_bot + m2_acceptance + 修 M1 bot／ui_playthrough
                ├──▶ WP-SOCIAL ┤
                └──▶ WP-UI ────┘（只依賴 4.1–4.5 的字串與形狀、4.6.9 的 ClientState API）
```

- WP-PARTY ↔ WP-PK 的介面只有 4.6.2 的 `BattleSystem.start_pvp()`、`host.pk.on_pvp_end(summary)` 與 4.6.4 的 `PkSystem.on_move()`；雙方都照簽名寫，對方沒好時以 `null` 判斷跳過（H4）。
- WP-UI 不引用 `server/**`、`core/battle/**`、`core/character/**`、`core/rules/**`；字串放在 `ui/game/ui_keys.gd`，值必須與 4.1 相同。

---

## 4. 介面契約

### 4.1 `core/protocol.gd`（WP-HOST，Day-0）

```gdscript
const VERSION := 3          # H2

# ---- M2 intents ----
const I_PARTY_INVITE := "party_invite"
const I_PARTY_REPLY := "party_reply"
const I_PARTY_LEAVE := "party_leave"
const I_PARTY_KICK := "party_kick"
const I_PARTY_LEAD := "party_lead"
const I_BATTLE_JOIN := "battle_join"
const I_CHALLENGE := "challenge"
const I_CHALLENGE_REPLY := "challenge_reply"
const I_FORCE_PK := "force_pk"
const I_SET_PREF := "set_pref"
const I_CORPSE_AUTHORIZE := "corpse_authorize"
const I_MAIL_SEND := "mail_send"
const I_MAIL_LIST := "mail_list"
const I_MAIL_READ := "mail_read"
const I_MAIL_DELETE := "mail_delete"
const I_SERVER_OPTS_GET := "server_opts_get"
const I_SERVER_OPTS_SET := "server_opts_set"
const I_ADMIN_KICK := "admin_kick"
const I_PASSPORT_REQUEST := "passport_request"
const I_PASSPORT_RESTORE := "passport_restore"
const I_PASSPORT_IMPORT := "passport_import"      # P2：處理器可以只回 foreign_disabled

# ---- channels ----
const CH_CHAT_WHISPER := "CHAT_WHISPER"
const CH_CHAT_SAY := "CHAT_SAY"
const CH_CHAT_SECT := "CHAT_SECT"
const CH_CHAT_GUILD := "CHAT_GUILD"
const CH_CHAT_PARTY := "CHAT_PARTY"
const CH_CHAT_RUMOR := "CHAT_RUMOR"
const CH_GM := "GM"
const CH_MAIL := "MAIL"
const CHAT_CHANNELS := [CH_CHAT_WORLD, CH_CHAT_WHISPER, CH_CHAT_SAY, CH_CHAT_SECT, CH_CHAT_GUILD,
	CH_CHAT_PARTY, CH_CHAT_RUMOR, CH_GM]

const MAIL_MAX_LEN := 200
const PASSPORT_MAX_BYTES := 65536          # passport 參數 var_to_bytes 後的上限
const PREF_KEYS := ["accept_challenge", "accept_party"]
const PK_MODES := ["CLASSIC", "CHALLENGE_ONLY", "OFF"]
```

`INTENT_SCHEMA` 新增／修改（B = `TYPE_BOOL`）：

| kind | args（`[type, required]`） |
|---|---|
| `chat`（改） | text:S 必、ch:S 選、**to:S 選** |
| `loot_corpse`（改） | corpse_id:S 必、**item_uid:S 選** |
| `party_invite` | target:S 必（char_id） |
| `party_reply` | from:S 必（邀請者 char_id）、accept:B 必 |
| `party_leave` | — |
| `party_kick` | target:S 必 |
| `party_lead` | target:S 必 |
| `battle_join` | battle_id:I 必 |
| `challenge` | target:S 必 |
| `challenge_reply` | from:S 必、accept:B 必 |
| `force_pk` | target:S 必 |
| `set_pref` | key:S 必、value:B 必 |
| `corpse_authorize` | corpse_id:S 必、name:S 必（角色名） |
| `mail_send` | to:S 必（角色名）、text:S 必 |
| `mail_list` | — |
| `mail_read` | id:S 必 |
| `mail_delete` | id:S 必 |
| `server_opts_get` | — |
| `server_opts_set` | key:S 必、value:S 必 |
| `admin_kick` | peer:I 必、ban:B 選 |
| `passport_request` | char_id:S 必 |
| `passport_restore` | passport:D 必 |
| `passport_import` | passport:D 必 |

`validate_args` 擴充（保持既有順序：未知 → 多餘參數 → 型別 → 必填 → 特例 → 長度 → 範圍 → 列舉）：

- `chat`：既有規則；`ch` ∉ `CHAT_CHANNELS` → `bad_channel`；`ch == CHAT_WHISPER` 而沒有 `to` → `missing_arg:to`；有 `to` 但 `ch != CHAT_WHISPER` → `unexpected_arg`；`to` 長度 ≤ 64。
- `mail_send`：`text` 去空白後為空 → `empty_text`；長度 > `MAIL_MAX_LEN` → `text_too_long`；`to` ≤ 64（`bad_value:to`）。`text` 不套 64 字上限。
- `passport_restore`／`passport_import`：`var_to_bytes(passport).size() > PASSPORT_MAX_BYTES` → `bad_value:passport`。
- `ENUMS`：`set_pref.key ∈ PREF_KEYS`。
- `INT_RANGES`：`battle_join.battle_id` 1–2147483647；`admin_kick.peer` 1–2147483647。

事件 key 常數 `E_<大寫>`：4.4 表中每一個 key 都要有（例 `E_PARTY_JOINED := "party_joined"`、`E_CHAT_WHISPER := "chat_whisper"`）。

### 4.2 Intent 完整清單（M2 新增與修改）

「旗標」：C = `GameHost.NEEDS_CHAR`、I = `GameHost.IDLE`（M1 的 `no_character`／`in_battle` 先檢查）。「驗證」欄依序檢查，第一個失敗就回該原因碼。目標以 **char_id** 指定的 intent，「在場」= 有在線 session 選著該角色且 `room_id()` 相同。

| kind | 擁有 | 旗標 | 驗證（依序）與效果 | 事件／推送 |
|---|---|---|---|---|
| `party_invite` | PARTY | C+I | `bad_target`（自己）→ `target_not_here` → `target_busy`（對方在戰鬥）→ `target_in_party`（對方已有隊伍）→ `not_leader`（我在隊伍但不是領隊）→ `party_full`（我的隊伍人數 ≥ `party_max`）→ `invite_pending`（對方已有任何人的待決邀請）→ `invite_refused`（對方 `prefs.accept_party == false`，不送提示）→ `invite_cooldown`（對方剛拒絕或讓我的邀請到期，5.2）→ 建立待決邀請（TTL `pending_ttl_real_s`） | 我：`party_invite_sent`；對方：`party_invited`；雙方 sheet |
| `party_reply` | PARTY | C+I | `no_invite`（沒有這個人給我的待決邀請）→ accept=false：刪除，邀請者收 `party_declined`，回 ok → accept=true：`target_offline`（邀請者已離線）→ `already_in_party`（我已在隊伍）→ `no_invite`（邀請者已加入別人的隊伍、不是領隊）→ `party_full` → 加入（邀請者沒隊伍就建隊，邀請者為領隊） | 全隊：`party_joined`；全隊 sheet |
| `party_leave` | PARTY | C | `not_in_party` → 離隊（戰鬥中也可，戰鬥不受影響）；領隊離開 → 最早加入的成員接任；剩 1 人 → 解散 | 我與留下的人：`party_left`；接任時全隊 `party_leader`；解散時剩下那人 `party_disbanded` |
| `party_kick` | PARTY | C | `not_in_party` → `not_leader` → `bad_target`（自己）→ `target_not_in_party` → 移出（之後同 leave 的解散規則） | 全隊＋被踢者：`party_kicked` |
| `party_lead` | PARTY | C | `not_in_party` → `not_leader` → `bad_target` → `target_not_in_party` → 移交 | 全隊：`party_leader` |
| `battle_join` | PARTY | C+I | `battle_not_found`（不存在，或戰場房間 ≠ 我所在房間）→ `battle_over` → `join_not_allowed`（戰鬥中沒有任何**仍在場**的同隊隊友）→ `battle_full`（玩家數 ≥ `battle_max_humans` 或隊友那一方沒有空格）→ `Battle.join_unit()` 加到隊友那一方 | 新加入者：`s2c_battle_open`；全場：`battle_join` + `battle_unit_join`（ui） |
| `challenge` | PK | C+I | `pk_disabled`（`pk_mode == OFF`）→ `bad_target` → `target_not_here` → `pk_not_allowed_here`（我所在地區 `pk_allowed != true`）→ `target_busy` → `target_in_party`（同隊）→ `challenge_pending`（我對他已有待決叫戰）→ `challenge_refused`（對方 `prefs.accept_challenge == false`，不送提示）→ `challenge_cooldown`（對方剛拒絕或讓我的叫戰到期，5.2）→ 建立待決叫戰 | 我：`challenge_sent`；對方：`challenge_request`；對方 sheet |
| `challenge_reply` | PK | C+I | `no_challenge` → accept=false：刪除，叫戰者收 `challenge_declined` → accept=true：重驗 `pk_disabled` → `target_not_here`（叫戰者不在同房或離線）→ `pk_not_allowed_here` → `target_busy` → `target_in_party`（叫戰後兩人才組隊）→ `BattleSystem.start_pvp(叫戰者, 我, "CHALLENGE")` | 同房：`challenge_start`；雙方 `s2c_battle_open` |
| `force_pk` | PK | C+I | `pk_disabled` → `pk_challenge_only`（`CHALLENGE_ONLY`）→ `bad_target` → `target_not_here` → `pk_not_allowed_here` → `target_busy` → `target_in_party` → `target_newbie_protected`（對方 `combat_xp < newbie_pk_protect_xp`）→ `start_pvp(我, 對方, "FORCED")` | 同房：`force_pk_start`；雙方 `s2c_battle_open` |
| `set_pref` | PK | C | （key 已由 Protocol 列舉）寫入 `ch.prefs[key] = value` | `pref_changed`；sheet |
| `corpse_authorize` | PK | C | `corpse_not_found`（世界裡沒有這具屍體，不限房間）→ `not_corpse_owner` → `no_such_player`（`world.char_names` 查無此名）→ `bad_target`（自己）→ `corpse_auth_full`（已授權 ≥ `corpse_auth_max`，重複授權同一人不算）→ 加入 `authorized` | 我：`corpse_authorized`；對方在線：`corpse_auth_granted`；該房間 view dirty |
| `loot_corpse`（改） | PK | C+I | `corpse_not_found`（不在此房間）→ `corpse_protected`（保護期內，我不是擁有者也沒被授權）→ `no_item`（給了 item_uid 但屍體上沒有）→ 移入背包（全部或單件；放不下的留著）→ 一件都放不下 → `inventory_full`／`overweight` | 擁有者自己撿：`corpse_looted`；別人撿：撿的人 `corpse_looted_other`，擁有者在線 `corpse_looted_by`；房間 view；存 world＋角色 |
| `chat`（改） | SOCIAL | — | 見 4.6.6 | 依頻道 |
| `mail_send` | SOCIAL | C | `no_such_recipient` → `bad_target`（寄給自己）→ `mail_too_fast`（距本 session 上次寄信 < `mail_min_interval_real_s`）→ `mailbox_full`（收件人信件 ≥ `mail_inbox_max`，且先刪掉最舊的已讀信後仍滿）→ 存入 `world.mail` | 我：`mail_sent`；收件人在線：`mail_arrived` + sheet |
| `mail_list` | SOCIAL | C | — | 我：`mail_list`（ui） |
| `mail_read` | SOCIAL | C | `mail_not_found`（不存在或不是寄給我）→ 標已讀 | `mail_list`（ui）＋ sheet |
| `mail_delete` | SOCIAL | C | `mail_not_found` → 刪除 | `mail_list`（ui）＋ sheet |
| `server_opts_get` | HOST | — | `not_admin` | `server_options`（ui） |
| `server_opts_set` | HOST | — | `not_admin` → `bad_option`（key 不在 4.7 的可編輯清單）→ `bad_value:value`（解析失敗或不在列舉）→ 套用、存 `options.json` 與 `world.json` | 全員：`server_option_changed`、`world_info_changed`（ui）；我：`server_options`（ui） |
| `admin_kick` | HOST | — | `not_admin` → `bad_target`（自己或沒有此 peer）→ ban=true 時 `known_identities[identity].banned = true` → `NetworkManager.kick(peer, "admin")` | 其他人：`player_kicked` |
| `passport_request` | HOST | — | `no_such_char`（不是我的角色）→ 若是目前選中的角色先存檔 → 送護照 | 我：`passport`（ui） |
| `passport_restore` | HOST | — | `char_active`（要還原的角色正選著）→ `passport_bad_format` → `passport_wrong_world` → `passport_wrong_identity`（`char.identity != s.identity`）→ `passport_bad_sig` → `passport_not_needed`（主機上的檔案存在、讀得了、且 `online_s` ≥ 護照的；角色已刪除時，`deleted/` 封存檔的 `online_s` > 護照的）→ `too_many_chars`（刪除後還原、已有 3 個角色）→ `passport_name_taken`（名字屬於另一個仍存在的角色）→ 寫入角色檔、補 `char_names` | 我：`passport_restored`、`s2c_char_list` |
| `passport_import` | HOST | — | P2；未實作時一律 `foreign_disabled` | — |

`battle_cmd` 不變（PvP 也用同一個），`fight`／`move` 的外部行為不變（內部多了拉入隊友與守衛判定）。

### 4.3 新原因碼與錯誤文字（`err_<reason>`，`self` 變體）

WP-HOST 照下表加進 `text_templates.json`（`era: "1.0A"`, `src: "proposal"`），並加入 `REQUIRED_TEMPLATE_KEYS`。

| reason | 文字 |
|---|---|
| `bad_target` | 【系統】對象不對。 |
| `target_not_here` | 【系統】對方不在這裡。 |
| `target_busy` | 【系統】對方正在戰鬥中。 |
| `target_offline` | 【系統】對方已經離開江湖了。 |
| `target_in_party` | 【系統】對方已經有隊伍了。 |
| `target_not_in_party` | 【系統】對方不是你的隊友。 |
| `already_in_party` | 【系統】你已經在隊伍裡了。 |
| `not_in_party` | 【系統】你沒有隊伍。 |
| `not_leader` | 【系統】只有領隊才能這麼做。 |
| `party_full` | 【系統】隊伍已經滿了。 |
| `invite_pending` | 【系統】對方還在考慮別人的邀請。 |
| `invite_refused` | 【系統】對方不接受組隊邀請。 |
| `no_invite` | 【系統】邀請已經失效了。 |
| `join_not_allowed` | 【系統】這場戰鬥裡沒有你的隊友，插不上手。 |
| `battle_full` | 【系統】戰場上已經擠不下了。 |
| `pk_disabled` | 【系統】這個江湖禁止私鬥。 |
| `pk_challenge_only` | 【系統】這個江湖只能叫戰，不能強行出手。 |
| `pk_not_allowed_here` | 【系統】這裡不能動手。 |
| `target_newbie_protected` | 【系統】對方初入江湖，不能對他下手。 |
| `challenge_pending` | 【系統】你已經向對方叫戰了，等他回應吧。 |
| `challenge_cooldown` | 【系統】對方剛回絕過你，過一會兒再叫戰吧。 |
| `invite_cooldown` | 【系統】對方剛回絕過你，過一會兒再邀吧。 |
| `challenge_refused` | 【系統】對方不接受叫戰。 |
| `no_challenge` | 【系統】叫戰已經失效了。 |
| `corpse_protected` | 【系統】屍體還在保護時間內，只有本人和他允許的人能翻動。 |
| `not_corpse_owner` | 【系統】那不是你的屍體。 |
| `corpse_auth_full` | 【系統】允許翻動屍體的人已經太多了。 |
| `no_such_player` | 【系統】江湖上沒有這個人。 |
| `thirsty` | 【系統】你口乾舌燥，說不出話來。 |
| `no_sect` | 【系統】你沒有門派。 |
| `no_guild` | 【系統】你沒有加入組織。 |
| `no_party_chat` | 【系統】你沒有隊伍，隊伍頻道沒人聽。 |
| `not_admin` | 【系統】只有主機能這麼做。 |
| `chat_too_fast` | 【系統】說話慢一點。 |
| `no_such_recipient` | 【系統】查無此人，信鴿飛不出去。 |
| `mailbox_full` | 【系統】對方的信已經堆滿了。 |
| `mail_not_found` | 【系統】找不到這封信。 |
| `mail_too_fast` | 【系統】信鴿還沒飛回來，稍等一下。 |
| `bad_option` | 【系統】這個設定不能改。 |
| `passport_bad_format` | 【系統】護照格式不對。 |
| `passport_wrong_world` | 【系統】這份護照不是這個世界的。 |
| `passport_wrong_identity` | 【系統】這份護照不是你的角色。 |
| `passport_bad_sig` | 【系統】護照驗證失敗（可能被改過）。 |
| `passport_not_needed` | 【系統】主機上的角色比護照新，不需要還原。 |
| `passport_name_taken` | 【系統】這個名字已經被別的角色用了，護照不能還原。 |
| `foreign_disabled` | 【系統】這個世界不接受外來角色。 |

> 隊伍頻道沒有隊伍時的原因碼是 `no_party_chat`（不是 `not_in_party`），讓提示文字不同。既有 `corpse_not_yours` 不再產生，但模板保留。

### 4.4 新事件（M2）

格式沿用 M1_PLAN 3.8：`{ seq, t, ch, key, p [, bid] [, ui] }`。變體選擇沿用 M0／M1：`p.from_peer`／`p.peer`／`p.atk_peer` 等於自己 → `self`；`p.def_peer` 等於自己 → `target`；否則 `other`。`GameHost.tell(s, …)` 會自動補 `p.peer = s.peer_id`，所以「只送本人」的事件只需要 `self`。名稱欄位是查好的中文字串，數值是 int。`ttl` 是真實秒數。

#### 4.4.1 組隊與中途加入（WP-PARTY 產生）

| key | ch | 收件 | payload | 變體 | 文字 |
|---|---|---|---|---|---|
| `party_invite_sent` | SYSTEM | 邀請者 | name | self | 你邀請{name}加入隊伍。 |
| `party_invited` | SYSTEM | 被邀者 | name, from_char, ttl | self | {name}邀請你加入隊伍（{ttl} 秒內回覆）。 |
| `party_declined` | SYSTEM | 邀請者 | name | self | {name}婉拒了你的組隊邀請。 |
| `party_invite_expired` | SYSTEM | 邀請者 | name | self | {name}沒有回應你的組隊邀請。 |
| `party_joined` | SYSTEM | 全隊 | name, peer, leader_name | self, other | 你加入了{leader_name}的隊伍。／{name}加入了隊伍。 |
| `party_left` | SYSTEM | 離隊者＋留下的人 | name, peer | self, other | 你離開了隊伍。／{name}離開了隊伍。 |
| `party_kicked` | SYSTEM | 全隊＋被踢者 | name, peer, leader_name | self, other | 你被{leader_name}請出了隊伍。／{name}被請出了隊伍。 |
| `party_leader` | SYSTEM | 全隊 | name, peer | self, other | 你成了隊伍的領隊。／{name}成了隊伍的領隊。 |
| `party_disbanded` | SYSTEM | 剩下的人 | — | self | 隊伍解散了。 |
| `battle_join` | BATTLE | 全場玩家 | uid, name, peer | self, other | 你加入了戰局！／{name}加入了戰局！ |
| `battle_unit_join` | BATTLE | 全場玩家（ui） | unit（`Battle._unit_snapshot` 形狀，含 `pos`、`side`） | — | UI-only |

#### 4.4.2 PK、守衛、屍體（WP-PK 產生）

| key | ch | 收件 | payload | 變體 | 文字 |
|---|---|---|---|---|---|
| `challenge_sent` | SYSTEM | 叫戰者 | name | self | 你向{name}叫戰，等他回應。 |
| `challenge_request` | SYSTEM | 對方 | name, from_char, ttl | self | {name}向你叫戰！（{ttl} 秒內回覆） |
| `challenge_declined` | SYSTEM | 叫戰者 | name | self | {name}拒絕了你的叫戰。 |
| `challenge_expired` | SYSTEM | 叫戰者 | name | self | {name}沒有回應你的叫戰。 |
| `challenge_start` | SCENE | 同房 | atk_name, def_name, atk_peer, def_peer | self, target, other | 你和{def_name}擺開架式，比劃起來！／{atk_name}和你擺開架式，比劃起來！／{atk_name}和{def_name}擺開架式，比劃起來！ |
| `force_pk_start` | SCENE | 同房 | atk_name, def_name, atk_peer, def_peer | self, target, other | 你突然向{def_name}下了殺手！／{atk_name}突然向你下了殺手！／{atk_name}突然向{def_name}下了殺手！ |
| `pk_kill` | SYSTEM | 強制 PK：所有在線玩家；叫戰：只有擊殺者與死者（5.2【設計提案】） | atk_name, def_name, atk_peer, def_peer, room_name | self, target, other | 你殺死了{def_name}！／你死在{atk_name}手下！／【江湖傳聞】{def_name}在{room_name}死在{atk_name}手下。 |
| `pk_value_up` | SYSTEM | 擊殺者 | pk | self | 你的 PK 值變成 {pk}。 |
| `pk_wanted` | SYSTEM | 擊殺者（PK值剛超過 3） | pk | self | 你的 PK 值已經超過 3，進出城會被守城官兵追殺！ |
| `morality_change` | SYSTEM | 本人 | delta, value | self | 你的善惡度變化 {delta}，現在是 {value}。 |
| `killing_intent_change` | SYSTEM | 本人 | delta, value | self | 你的殺氣增加了 {delta}，現在是 {value}。 |
| `guard_attack` | BATTLE | 本人 | n | self | 守城官兵大喝一聲：「站住！」{n} 名官兵朝你撲了過來！ |
| `pref_changed` | SYSTEM | 本人 | label, state | self | {label}：{state}。（label：接受叫戰／接受組隊邀請；state：開／關） |
| `corpse_authorized` | SYSTEM | 擁有者 | name, room_name | self | 你允許{name}翻動你在{room_name}的屍體。 |
| `corpse_auth_granted` | SYSTEM | 被授權者 | owner_name, room_name | self | {owner_name}允許你翻動他在{room_name}的屍體。 |
| `corpse_looted_other` | SYSTEM | 撿的人 | owner_name, n_items | self | 你從{owner_name}的屍體上拿走了 {n_items} 件物品。 |
| `corpse_looted_by` | SYSTEM | 擁有者 | name, n_items | self | {name}從你的屍體上拿走了 {n_items} 件物品。 |
| `corpse_public` | SYSTEM | 擁有者（在線時） | room_name | self | 你在{room_name}的屍體已過保護時間，現在誰都能翻動了。 |

#### 4.4.3 聊天與飛鴿（WP-SOCIAL 產生）

| key | ch | 收件 | payload | 變體 | 文字 |
|---|---|---|---|---|---|
| `chat`（既有，千里傳音） | CHAT_WORLD | 所有 session | from, from_peer, text | self, other | 既有：【千里傳音】你：{text}／【千里傳音】{from}：{text} |
| `chat_say` | CHAT_SAY | 同房 | from, from_peer, text | self, other | 【輕聲細語】你：{text}／【輕聲細語】{from}：{text} |
| `chat_sect` | CHAT_SECT | 同門在線角色 | from, from_peer, text | self, other | 【門派】你：{text}／【門派】{from}：{text} |
| `chat_party` | CHAT_PARTY | 全隊在線 | from, from_peer, text | self, other | 【隊伍】你：{text}／【隊伍】{from}：{text} |
| `chat_whisper` | CHAT_WHISPER | 發話者、對象 | from, from_peer, to_name, text | self, other | 【傳音入密】你對{to_name}說：{text}／【傳音入密】{from}對你說：{text} |
| `chat_rumor` | CHAT_RUMOR | 所有 session | from（發話者那份＝本人名；其他人那份＝空字串）、from_peer（發話者那份＝本人 peer；其他人＝0）、text | self, other | 【江湖謠言】你放出風聲：{text}／【江湖謠言】(謠言)：{text} |
| `chat_gm` | GM | 所有 session | from, from_peer, text | self, other | 【天外飛仙】{text}（兩個變體同文字） |
| `mail_sent` | MAIL | 寄件者 | to_name | self | 信鴿振翅飛走了，信會送到{to_name}手上。 |
| `mail_arrived` | MAIL | 收件人（在線） | from_name, id | self | 一隻信鴿落在你肩頭，帶來{from_name}的信。 |
| `mail_waiting` | MAIL | 收件人（選角進入時，有未讀才送） | n | self | 你有 {n} 封飛鴿傳書還沒看。 |
| `mail_list` | MAIL | 本人（ui） | mails: `[ { id, from_name, text, sent_clock, read } ]`（新到舊） | — | UI-only |

#### 4.4.4 主機（WP-HOST 產生）

| key | ch | 收件 | payload | 變體 | 文字 |
|---|---|---|---|---|---|
| `server_options` | SYSTEM | 管理員（ui） | 見 4.7.2 | — | UI-only |
| `world_info_changed` | SYSTEM | 所有 session（ui） | world_info（`WorldServer.world_info()` 形狀） | — | UI-only；`ClientState` 更新 `world_info` 並重新 `GameData.activate()`（非主機） |
| `server_option_changed` | SYSTEM | 所有 session | label, value | self, other | 【系統】主機把「{label}」改為「{value}」。（兩個變體同文字） |
| `player_kicked` | SYSTEM | 其他 session | name | other | 【系統】{name}被主機請出了江湖。 |
| `host_closing` | SYSTEM | 所有 session | — | self, other | 【系統】主機即將關閉，江湖暫時凍結。（兩個變體同文字） |
| `passport` | SYSTEM | 本人（ui） | world_id, char_id, name, char（角色存檔字典）, sig, saved_s | — | UI-only；`ClientState` 存檔（4.6.9） |
| `passport_restored` | SYSTEM | 本人 | name | self | 已用角色護照還原「{name}」。 |

`UI_ONLY_KEYS` 加上：`battle_unit_join`、`mail_list`、`server_options`、`world_info_changed`、`passport`（不得有模板）。另 `talk_n_bandit_chief`（self）：`{npc_name}把大刀往地上一插：「狼嚎丘是老子的地盤！想過去？叫你的兄弟們一起上吧！」`。

### 4.5 快照新增欄位

#### 4.5.1 角色表 `s2c_sheet`（向下相容；只增不改）

| 欄位 | 來源 | 形狀 |
|---|---|---|
| `pk` | `Character.to_sheet`（PK） | int：**目前值**（已扣除遞減，`pk_value()`） |
| `align` | `Character.to_sheet`（PK） | `"GOOD"`／`"NEUTRAL"`／`"EVIL"`（5.2 的門檻） |
| `prefs` | `Character.to_sheet`（PK） | `{ "accept_challenge": bool, "accept_party": bool }` |
| `party` | `GameHost.push_sheet` ← `host.party.sheet_for(s)`（PARTY） | `{}`，或 `{ "id": "pt_…", "leader": char_id, "members": [ { "char_id", "name", "peer", "online": true, "room_name", "in_battle": bool, "leader": bool } ] }`（依加入順序） |
| `pending` | `push_sheet` ← `party.pending_for(s)`、`pk.pending_for(s)` | `{ "party_invite": {} 或 { "from_char", "name", "left_s" }, "challenges": [ { "from_char", "name", "left_s" } ] }`（left_s 為真實秒數） |
| `mail_unread` | `push_sheet` ← `mail.unread_count(ch)`（SOCIAL） | int |
| `my_corpses` | `push_sheet` ← `corpses.mine(ch)`（PK） | `[ { "id", "room_name", "public": bool, "left_s": int, "n_items": int } ]` |
| `is_admin` | `push_sheet`（HOST） | bool |

系統為 null（H4）時，對應欄位給空值（`{}`、`[]`、0）。

#### 4.5.2 房間視圖 `s2c_region_view`

| 欄位 | 來源 | 形狀 |
|---|---|---|
| `pk_allowed` | RegionSystem（HOST） | bool（地區 `pk_allowed`） |
| `players[]` 新增 | RegionSystem 合併 `pk.player_tags(o)`、`party.player_tags(o)` | `align`、`newbie`（`combat_xp < newbie_pk_protect_xp`）、`party_id`（""＝無）、`in_battle`、`battle_id` |
| `battles` | `host.battles.room_battles(room_id, s)`（PARTY） | `[ { "bid", "kind", "names": [[side0 名字…], [side1 名字…]], "joinable": bool } ]` |
| `corpses[]` 新增 | `corpses.in_room(room, viewer)`（PK） | `can_loot`、`public`、`left_s`（真實秒數）、`authorized_me`；`items`：可撿時才有，`[ { "uid", "id", "name", "n" } ]`；`authorized_names`（已允許的角色名）與 `auth_max`：只給擁有者（2026-10-18 審查） |

#### 4.5.3 戰鬥

- `s2c_battle_open` 新增：`kind`（`ENCOUNTER`／`FIGHT`／`GUARD`／`CHALLENGE`／`FORCED`）、`my_side`（0／1）。PvP 時對方玩家單位比照「敵方」只帶最少欄位＋`look`。UI 在 `my_side == 1` 時把 x 座標鏡像（`x' = 11 - x`），讓自己永遠在左邊；送出的 `target` 必須轉回主機座標。
- `s2c_battle_close` 新增：`kind`。`result` 一律是**相對於本人那一方**（我方勝 = `VICTORY`）。PvP 沒有實戰與學點（`rewards` 全 0）。

### 4.6 類別與函式（主機端）

#### 4.6.1 `server/game_host.gd`（WP-HOST）

```gdscript
const M2_SYSTEMS := { "party": "res://server/party_system.gd", "pk": "res://server/pk_system.gd",
	"social": "res://server/social_system.gd", "mail": "res://server/mail_system.gd" }
const M2_INTENTS := ["res://server/intents/intents_party.gd", "res://server/intents/intents_pk.gd",
	"res://server/intents/intents_social.gd", "res://server/intents/intents_host.gd"]
var party = null       # PartySystem 或 null（H4）
var pk = null          # PkSystem
var social = null      # SocialSystem
var mail = null        # MailSystem
var admin: AdminSystem

func world_span(real_s: float) -> float        # real_s × time_scale（H5）
func clean_text(text: String, max_len: int) -> String   # H6
func is_admin(s: Session) -> bool              # = s.is_admin
func session_for_char_name(name: String) -> Session      # 在線且選著此名角色（大小寫不敏感），否則 null
func char_ref_by_name(name: String) -> Dictionary        # world.char_names 查詢：{ identity, char_id } 或 {}
func pvp_char_name(char_id: String) -> String            # 在線找不到時查 char_names 反查；都沒有回 ""
```

接線（全部 `if x != null`）：

| 時機 | 呼叫 |
|---|---|
| `_init` | 依 `M2_SYSTEMS` 載入；依 `M2_INTENTS` 呼叫各檔的 `static func register(host: GameHost)`；`admin = AdminSystem.new(self)` |
| `tick(dt)` | `party.tick(now_s())`、`pk.tick(now_s())`（處理待決邀請／叫戰到期） |
| `_minute_jobs` | `corpses.expire(now)`（既有；PK 在其中加公開通知） |
| `push_sheet` | 4.5.1 的欄位 |
| `enter_character` 之後 | `mail.on_enter(s)` |
| `leave_character`（換角、斷線、關服）之前 | `party.on_leave(s)`、`pk.on_leave(s)` |
| `on_session_removed` | 既有 `battles.detach_for(s)` 之後照上一列 |
| `char_delete` 成功後 | `mail.on_char_deleted(char_id)`；`corpses` 不動（屍體照常到期） |
| `dispose` | 新系統的 `host = null` |

`RegionSystem.move()`（WP-HOST）：`_walk` → `quests.on_reach` → `party.on_moved(s)` → **`if pk != null and pk.on_move(s, from_room, to_room): return ok()`**（守衛已開戰就不擲遇敵）→ `roll_encounter(s)`。`view()` 合併 4.5.2 的欄位。

`intents_char.gd` 的 `char_select`（WP-HOST）：載入前先 `var bid := host.battles.battle_of_char(char_id)`；`bid != 0` → `host.battles.reattach(s, char_id)`（不從磁碟讀檔，沿用戰鬥中的同一個 Character 物件），成功回 ok；否則照 M1 流程。

#### 4.6.2 `server/battle_system.gd`（WP-PARTY）

```gdscript
const PULL_KINDS := ["ENCOUNTER", "FIGHT"]   # GUARD 不拉隊友（2026-10-18 第二輪審查）
func start(s: Session, monster_ids: Array, kind: String) -> int
	# 簽名不變。kind ∈ PULL_KINDS 時，host.party.members_in_room(s) 中閒置（battle_id == 0）且有角色的隊友一起入場（side 0），
	# 各自收 s2c_battle_open；總玩家數不超過 battle_max_humans
func start_pvp(atk: Session, def: Session, kind: String) -> int   # kind ∈ ["CHALLENGE", "FORCED"]；atk side 0、def side 1；只有兩人
func join(s: Session, bid: int) -> Dictionary                      # battle_join 的處理（4.2 的驗證順序）
func room_battles(room_id: String, viewer: Session) -> Array       # 4.5.2
func battle_of_char(char_id: String) -> int                        # 進行中且包含此角色（含已斷線者）的 bid，否則 0
func reattach(s: Session, char_id: String) -> bool                 # 換 peer、取消 detached/afk、s.character = 戰鬥中的物件、送 s2c_battle_open
func humans(bid: int) -> int
```

- `entry` 加 `kind`、`char_ids: { peer: char_id }`。
- 結算：每位玩家的結果依**自己那一方**（4.5.3）；PvP 不給 `BattleRewards`；死亡照 `handle_death()`（PvP 也一樣：屍體、降級、重生，依 rule_profile）。
- PvP 結束（所有玩家結算完）後呼叫 `host.pk.on_pvp_end(summary)`：
  `summary = { "bid", "kind", "room", "units": [ { "char_id", "name", "peer"（離線為 0）, "side", "died", "fled", "killed_by_char"（"" 或擊殺者 char_id） } ] }`。
- 中途加入者算參戰者：勝利時仍站著就分享獎勵（`BattleRewards` 已依 `1/√存活玩家數`）。

#### 4.6.3 `core/battle/**`（WP-PARTY）

```gdscript
# battle.gd
func join_unit(spec: Dictionary) -> int
	# 只在 RUNNING／AWAIT_COMMAND／RESOLVING 可用；放在 spec.side 那一方「最外側欄」（side 0：x=0，side 1：x=11）依 Y_ORDER 找空格，
	# 滿了往內一欄；沒有空格回 0。gauge 0、CHARGING；產生 battle_join（模板）與 battle_unit_join（ui）事件與 battle_gauges
func humans() -> int
func winner_side() -> int     # 0 / 1；未分勝負或全逃 -1
# outcome() 新增 "winner_side"；snapshot() 新增 "kind"（由 opts.kind 傳入）
```

- `_check_end` 不變（side 0 全倒 = DEFEAT）；「相對結果」由 BattleSystem 依 `winner_side` 換算。
- PvP 的擊殺：`killed_by` 照記；`BattleRewards.compute` 對沒有怪物的戰鬥回空字典。
- 等待模式 10.7：中途加入者進入 READY 時照同一套逾時；`test_battle_pacing.gd` 用 8 個玩家單位（其中 2 個一直不下令）量「每輪平均等待秒數」，斷言一輪 ≤ `wait_mode_round_budget_s + wait_mode_timeout_min_s`。

#### 4.6.4 `server/pk_system.gd`（WP-PK，`class_name PkSystem`）

```gdscript
const GUARD_MONSTER := "m_city_guard"
func challenge(s: Session, target_char: String) -> Dictionary
func challenge_reply(s: Session, from_char: String, accept: bool) -> Dictionary
func force_pk(s: Session, target_char: String) -> Dictionary
func set_pref(s: Session, key: String, value: bool) -> Dictionary
func on_move(s: Session, from_room: String, to_room: String) -> bool
	# guards_enabled 且「from、to 其中恰好一個屬於 type == CITY 的地區」且該城地區有 kind == GUARD 的 NPC，
	# 且 MoralityPk.guard_count(ch.pk_value(), ch.morality) > 0 → guard_attack 事件 → host.battles.start(s, [GUARD_MONSTER × n], "GUARD") → true
func on_pvp_end(summary: Dictionary) -> void     # 5.2 的 PK值／殺氣／善惡；pk_kill 廣播
func player_tags(o: Session) -> Dictionary       # { align, newbie }
func pending_for(s: Session) -> Array            # 4.5.1 pending.challenges
func tick(now: float) -> void                    # 叫戰到期 → challenge_expired
func on_leave(s: Session) -> void                # 刪除他發出與收到的叫戰
```

`core/rules/morality_pk.gd`（`class_name MoralityPk`，純邏輯，只吃參數）：

```gdscript
const PK_DECAY_ONLINE_S := 1800.0
const GUARD_PK_THRESHOLD := 3
const ALIGN_GOOD_MIN := 101          # > 100
const ALIGN_EVIL_MAX := -101         # < -100
static func align_of(morality: int) -> String
static func pk_value(pk_base: int, pk_stamp_s: float, online_s: float) -> int
	# max(0, pk_base - floor((online_s - pk_stamp_s) / 1800))
static func guard_count(pk: int, morality: int) -> int     # pk > 3 → 2；否則 morality < 0 → 1；否則 0
static func kill_deltas(kind: String, victim_morality: int) -> Dictionary
	# { "pk": FORCED ? 1 : 0, "killing_intent": 100,
	#   "morality": FORCED ? (victim_morality < -100 ? +10 : -10) : 0 }   # 原 −50（2026-10-18 第二輪審查）
static func can_be_forced(target_combat_xp: int, protect_xp: int) -> bool
```

`server/corpse_system.gd`（WP-PK）：

```gdscript
func create(ch, room_id: String, items: Array) -> String     # 簽名不變；新增欄位 authorized: [], public_notified: false
func in_room(room_id: String, viewer) -> Array               # 4.5.2
func mine(ch) -> Array                                       # 4.5.1 my_corpses
func authorize(s: Session, corpse_id: String, name: String) -> Dictionary
func loot(s: Session, corpse_id: String, item_uid: String = "") -> Dictionary
func private_s(c: Dictionary) -> float                       # 依 c.window：CLASSIC_30／LATER_10 都是 600
func expire_s(c: Dictionary) -> float                        # 都是 1800（D6）
func is_public(c: Dictionary, now: float) -> bool
func expire(now: float) -> void                              # 既有 + 過保護期時送一次 corpse_public（public_notified = true）
```

#### 4.6.5 `core/character/**`（WP-PK）

`Character` 新增（`to_dict`／`from_dict` 往返；舊檔缺欄位補預設）：

| 欄位 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `pk` | int | 0 | 意義改為「基準值」，搭配 `pk_stamp_s` |
| `pk_stamp_s` | float | 0.0 | 上次正規化時的 `online_s` |
| `prefs` | Dictionary | `{ "accept_challenge": true, "accept_party": true }` | 系統開關【已證實：開關存在】 |
| `origin_world` | String | `""` | 外來角色（P2） |

方法：`pk_value() -> int`、`add_pk(n: int) -> int`（先把基準正規化成目前值、`pk_stamp_s = online_s`，再加 n）、`align() -> String`、`add_morality(d) -> int`（夾在 ±1000）、`add_killing_intent(d) -> int`。`to_sheet` 補 4.5.1 的 `pk`／`align`／`prefs`。`Requirements` 的 `req_pk_max` 改用 `pk_value()`。

#### 4.6.6 `server/social_system.gd`（WP-SOCIAL，`class_name SocialSystem`）

`intents_social.gd` 以旗標 0 註冊 `chat`（覆蓋 M0 的 `_intent_chat`）。`chat(s, args)` 的順序：

1. `text = host.clean_text(text, CHAT_MAX_LEN)`；`ch` 預設 `CHAT_WORLD`。
2. 沒有角色：`ch != CHAT_WORLD` → `no_character`；`chat_too_fast`（同第 4 步）；否則照 M0 廣播 `chat`（不耗水）→ ok。（2026-10-18 審查：原本不檢查頻率，沒選角的連線能以每秒 20 則洗全服）
3. `ch == GM`：`not_admin`（不耗水）。
4. `chat_too_fast`：距**同一身分**上次發話 < `chat_min_interval_ms`（真實時間）。記在 `SocialSystem` 的字典裡，不記在 Session 上（重連會換新 Session）。
5. 頻道資格：`CHAT_SECT` 沒門派 → `no_sect`；`CHAT_GUILD` → `no_guild`（M2 一律）；`CHAT_PARTY` 沒隊伍 → `no_party_chat`；`CHAT_WHISPER`：`to` 找不到在線角色 → `no_such_player`、是自己 → `bad_target`。
6. 耗水：頻道在 `WATER_CHANNELS = [CHAT_WORLD, CHAT_SAY, CHAT_SECT, CHAT_GUILD, CHAT_PARTY, CHAT_RUMOR]` 且 `vitals.water < chat_water_cost` → `thirsty`；否則扣除、sheet dirty。
7. 依 4.4.3 送出；成功回 ok。

#### 4.6.7 `server/mail_system.gd`（WP-SOCIAL，`class_name MailSystem`）

```gdscript
func send(s: Session, to_name: String, text: String) -> Dictionary
func list(s: Session) -> Dictionary            # 送 mail_list（ui）
func read(s: Session, id: String) -> Dictionary
func delete(s: Session, id: String) -> Dictionary
func unread_count(ch) -> int
func on_enter(s: Session) -> void              # 有未讀 → mail_waiting
func on_char_deleted(char_id: String) -> void  # 刪除寄給他的信
```

存在 `world.mail`（見 4.8）；id 用 `host.new_id("ml_")`；寄送、讀信（未讀→已讀）、刪信後都 `host.ws.save_now()`（信件與已讀狀態不可因當機遺失或回復）。
`mail_too_fast` 依**寄件人身分**計時（記在 `MailSystem`，重連不歸零）；同一寄件人在同一收件匣最多 `MAX_UNREAD_PER_SENDER`（10）封未讀，超過回 `mailbox_full`【設計提案】（一個人不能把別人的收件匣塞滿）。

#### 4.6.8 `server/admin_system.gd`、`server/passport.gd`、`server/session.gd`（WP-HOST）

- `Session` 新增 `var is_admin := false`。`_add_session`／`register_local_player` 設定：本地玩家（非 `--dedicated` 的主機 peer 1，含離線模式）為 true；`identity ∈ options.admin_identities` 為 true。
- `AdminSystem`：`opts_get(s)`、`opts_set(s, key, value)`、`kick(s, peer, ban)`。
- `Passport`（`class_name Passport`，靜態）：
  - `canonical(char_dict) -> String` = `JSON.stringify(Character.from_dict(char_dict).to_dict(), "", true)`（排序鍵；先往返一次，消除 JSON 載入後 int 變 float 的差異）。
  - `sign(world_secret, world_id, char_dict) -> String` = `(world_secret + world_id + canonical(char_dict)).sha256_text()`。
  - `verify(world_secret, world_id, passport) -> bool`。
  - 護照字典：`{ "v": 1, "world_id", "char_id", "identity", "name", "char": <角色存檔字典>, "sig", "saved_s" }`。
- 送出時機：每次自動存檔時對每個在線且有角色的 session；`leave_character`（換角，連線還在時）；`passport_request`。
- **誠實說明**（UI 與 README 都要照寫）：簽章只證明「沒有主機檔案存取權的人改過護照會被發現」（可察覺竄改）；它**不防**主機玩家本人、拿到主機存檔的人、改程式的人；對別的世界完全無法驗證。護照是災難復原工具，不是防作弊。

#### 4.6.9 `autoload/client_state.gd`、`network_manager.gd`、`save_manager.gd`、`world_server.gd`（WP-HOST）

```gdscript
# client_state.gd
var capture_remote: Callable = Callable()
	# 測試用：有效時，送往「非本地」peer 的 deliver_*（welcome、roster、events、result、sheet、char_list、view、battle_open/close、kick）
	# 改成 capture_remote.call(peer_id, what: String, payload) 而不發 RPC（what = "events"、"result"、"sheet"…）
var mail_list: Array = []          # 最近一次 mail_list 事件
var server_options: Dictionary = {}# 最近一次 server_options 事件
signal mail_list_changed(list: Array)
signal server_options_changed(opts: Dictionary)
signal world_info_changed(info: Dictionary)
# _apply_events 依 key 處理 ui 事件（照常也 push 進 event_log）：
#   passport → SaveManager.save_passport(p.world_id, p.char_id, p)
#   world_info_changed → world_info = p.world_info；非主機時 GameData.activate(...)；發 world_info_changed（不重發 welcomed）
#   mail_list → mail_list = p.mails；發 mail_list_changed
#   server_options → server_options = p；發 server_options_changed

# network_manager.gd
var last_target: Dictionary = {}   # { "mode": "ENET", "address", "port" } 或 { "mode": "STEAM", "lobby_id": int }
func reconnect() -> Error           # 依 last_target 重新加入；沒有目標回 ERR_UNCONFIGURED
# 遊戲中收到 Steam join_requested：先 leave(true, true) 再加入新大廳（既有 keep_lobby 參數）
# --stop-file=<絕對路徑>：主機每 1 秒檢查；檔案出現 → 刪檔 → broadcast host_closing → flush → leave() → get_tree().quit(0)

# save_manager.gd
func save_passport(world_id: String, char_id: String, passport: Dictionary) -> Error   # 原子寫入 passport_path
func load_passport(world_id: String, char_id: String) -> Dictionary                    # { ok, data }
func list_passports(world_id: String) -> Array                                          # 該世界的 char_id 清單

# world_server.gd
# validate_hello：同一 identity 已有 session → 不再回 already_connected，而是先移除舊 session（照 on_peer_disconnected 流程：
#   存檔、斷線戰鬥照常、離隊）並 force_disconnect 舊 peer，再接受新的（重連取代）。banned、滿員照舊。
# 停止前：broadcast host_closing、flush（stop() 開頭）。
# --opts=key=value[,key=value…]：新建或既有世界都套用並存進 options.json；只接受 4.7.1 標「CLI」的 key，型別依預設值，錯誤時 last_error 並拒絕開世界。
```

#### 4.6.10 `tests/unit/test_world_fixture.gd` 多玩家輔助（WP-HOST，Day-0）

```gdscript
func add_player(char_name: String, city := "xixia") -> int
	# 建立假的遠端 session（peer 100 起遞增，identity local_<32 hex>），經 capture_remote 收件，建角並進入世界；回傳 peer
func send_as(peer: int, kind: String, args: Dictionary = {}) -> Dictionary
func reason_as(peer: int, kind: String, args: Dictionary = {}) -> String
func evs_for(peer: int, key: String) -> Array
func sheet_for(peer: int) -> Dictionary
func view_for(peer: int) -> Dictionary
func battle_open_for(peer: int) -> Dictionary
func session_of(peer: int) -> Session
func goto_as(peer: int, room: String) -> void
func drop_player(peer: int) -> void            # 模擬斷線（WorldServer.on_peer_disconnected）
func restart_world() -> void                   # stop() 後以同一 world_id start()，舊 peer 全部消失
```

`after_each` 清掉 `capture_remote`。

### 4.7 伺服器選項（`data/server_options.default.json`，WP-HOST）

#### 4.7.1 新增 key

| key | 型別 | 預設 | CLI（`--opts`） | 說明／來源 |
|---|---|---|---|---|
| `guards_enabled` | bool | true | ✓ | 【已證實】守衛存在 |
| `chat_water_cost` | int | 1 | ✓ | GDD 10.1【提案】 |
| `chat_min_interval_ms` | int | 500 | ✓ | 【設計提案】 |
| `party_max` | int | 5 | ✓ | GDD 10.2【待考證→提案】 |
| `battle_max_humans` | int | 8 | ✓ | 【設計提案】= 大廳上限 |
| `pending_ttl_real_s` | int | 60 | ✓ | 邀請／叫戰【設計提案】 |
| `pending_retry_cooldown_real_s` | int | 10 | ✓ | 被拒／到期後同一對人的重邀／再叫戰冷卻；0＝關【設計提案】（第三輪審查） |
| `encounters_enabled` | bool | true | ✓ | false＝不擲踩地雷【設計提案・測試／管理用】；`m2_acceptance` 用來排除路上的隨機死亡（第三輪審查） |
| `mail_inbox_max` | int | 50 | ✓ | 【設計提案】 |
| `mail_min_interval_real_s` | int | 10 | ✓ | 【設計提案】 |
| `corpse_auth_max` | int | 4 | ✓ | 【設計提案】 |
| `admin_identities` | Array[String] | [] | — | 專用主機的管理員 |

既有可用 `--opts` 的：`pk_mode`、`newbie_pk_protect_xp`、`wait_mode`、`wait_mode_timeout_s`、`allow_foreign_characters`。

#### 4.7.2 面板可編輯（`server_opts_set`）與 `server_options` 事件

```gdscript
{ "editable": [
    { "key": "rule_preset", "label": "死亡規則", "value": "classic_standard",
      "choices": [ { "value": "classic_standard", "label": "懷舊標準（預設）" }, …（rule_profiles 每一列） ] },
    { "key": "pk_mode", "label": "PK 模式", "value": "CLASSIC",
      "choices": [ {"value":"CLASSIC","label":"懷舊（叫戰＋強制 PK）"}, {"value":"CHALLENGE_ONLY","label":"只能叫戰"}, {"value":"OFF","label":"禁止 PK"} ] },
    { "key": "wait_mode", "label": "戰鬥等待模式", "value": "true", "choices": [ {"value":"true","label":"開"}, {"value":"false","label":"關"} ] },
    { "key": "stagecoach_enabled", "label": "驛站馬車（非原作）", "value": "false", "choices": [ … ] } ],
  "info": { "world_name", "host_offline_policy": "FROZEN", "players": [ { "peer", "name", "identity_short", "is_admin" } ] } }
```

- `rule_preset`：寫 `world.rule_profile.preset`（保留 `overrides`）與 `options.rule_profile`，重新 `GameData.activate()`；只影響之後的事件（TECH_ARCH 5.6）。
- `wait_mode`：只影響之後開的戰鬥。
- 套用後存 `options.json` 與 `world.json`，廣播 `server_option_changed`、`world_info_changed`。
- `world_info()` 新增 `pk_mode`、`wait_mode`。

### 4.8 存檔新增

| 檔案 | 欄位 | 形狀 | 擁有 |
|---|---|---|---|
| 角色檔 | `pk_stamp_s`、`prefs`、`origin_world` | 4.6.5 | PK |
| `world.json` | `corpses[].authorized` | `[char_id]` | PK |
| `world.json` | `corpses[].public_notified` | bool | PK |
| `world.json` | `mail` | `[ { "id": "ml_…", "to_char", "to_name", "from_char", "from_name", "text", "sent_s": float, "read": bool } ]` | SOCIAL |
| `world.json` | `known_identities[*].banned` | bool（既有欄位，開始使用） | HOST |
| `options.json` | 4.7.1 的 key | — | HOST |
| 客戶端 | `user://passports/<world_id>/<char_id>.json` | 4.6.8 護照字典 | HOST |

- `schema_version` 不升：全部是新增欄位，`SaveManager._coerce_world` 與各 `from_dict` 補預設值。
- **不存**：隊伍、待決邀請、待決叫戰、聊天頻率紀錄、戰鬥（關服時 ABORTED，與 M1 相同）。
- 世界凍結的保證來自既有設計：`world_time_s` 只在主機運作時累加；屍體用 `created_s`（世界時間）；PK值用角色 `online_s`；飢渴與腐壞只在 tick 時算。

### 4.9 資料列（WP-PARTY，Day-0，原樣貼上；數值之後只能由 WP-PARTY 依 balance_sim 調整）

`data/monsters.json`：

```json
{ "id": "m_bandit_chief", "name": "山賊頭目", "short": "頭目", "kind": "ELITE", "alignment": "EVIL",
  "desc": "狼嚎丘山賊的頭子，一把厚背大刀使得虎虎生風，單打獨鬥很難討到便宜。（隊伍級精英：設計提案）",
  "stats": { "qi": 1500, "neili": 100, "jing": 300, "str": 24, "guts": 24, "wit": 15, "luck": 15, "cal": 20, "agi": 18, "con": 24 },
  "skills": { "basic_dodge": 30, "basic_parry": 30, "basic_inner": 20 },
  "arts": [ { "art": "mon_blade", "level": 35 } ], "weapon_type": "BLADE", "weapon_power": 15, "armor_power": 20,
  "combat_xp_ref": 8000, "combat_xp": 120, "learn_points": 60,
  "drops": [ { "item": "c_qiyao", "chance": 1.0, "min": 1, "max": 2 }, { "item": "w_dandao", "chance": 0.3, "min": 1, "max": 1 } ],
  "money": { "min": 150, "max": 300 }, "morality_on_kill": 5, "killing_intent_on_kill": 5,
  "ai": "melee_basic", "no_rewards": false, "era": "1.0A", "src": "proposal" }
```

```json
{ "id": "m_city_guard", "name": "守城官兵", "short": "官兵", "kind": "ELITE", "alignment": "NEUTRAL",
  "desc": "守城的官兵，盔甲鮮明，專門緝拿惡徒。（守衛存在：已證實；數值：設計提案）",
  "stats": { "qi": 3000, "neili": 300, "jing": 600, "str": 30, "guts": 30, "wit": 20, "luck": 20, "cal": 30, "agi": 28, "con": 30 },
  "skills": { "basic_dodge": 80, "basic_parry": 80, "basic_inner": 60 },
  "arts": [ { "art": "mon_blade", "level": 80 } ], "weapon_type": "BLADE", "weapon_power": 40, "armor_power": 60,
  "combat_xp_ref": 60000, "combat_xp": 0, "learn_points": 0, "drops": [], "money": {},
  "morality_on_kill": 0, "killing_intent_on_kill": 0, "ai": "melee_basic", "no_rewards": true, "era": "1.0A", "src": "proposal" }
```

`data/npcs.json`：

```json
{ "id": "n_bandit_chief", "name": "山賊頭目", "kind": "EVIL_NPC", "region": "xixia_wild", "room": "xw_hill",
  "alignment": "EVIL", "talk": "talk_n_bandit_chief", "services": ["FIGHT"], "night_closed": false,
  "fight": { "monster": "m_bandit_chief", "requires": [] },
  "desc": "盤據狼嚎丘的山賊頭子，身邊總圍著幾個嘍囉。（設計提案）", "era": "1.0A", "src": "proposal" }
```

平衡目標（`tools/balance_sim.gd` 新 case，參考角色＝M1 的參考新手）：`party4_vs_bandit_chief` 勝率 ≥ 80%、每場死亡人數中位數 ≤ 1；`solo_vs_bandit_chief` 勝率 ≤ 20%；`newbie_vs_city_guard` 勝率 ≤ 2%。

### 4.10 UI（WP-UI）

只透過 `NetworkManager.send_intent()` 與 `ClientState`／`GameData` 互動（G1）。畫面與行為：

| 畫面 | 內容 |
|---|---|
| 場景卷軸的玩家名 | 名字顏色依 `align`（惡藍 `#4060FF`、中立黃 `#F0D060`、善白；【已證實：顏色】）；左鍵 → 選單：組隊邀請、叫戰、密語、寄信、（隊長）踢出／移交領隊；**Ctrl + 左鍵** → 確認框「確定要對 X 強行出手？」→ `force_pk`（`newbie` 或 `pk_allowed == false` 時直接顯示原因，不送） |
| 邀請／叫戰提示 | `sheet.pending` 有東西就顯示（接受／拒絕＋倒數）；重連後依 sheet 重建 |
| 隊伍面板 | 依 `sheet.party`：成員、領隊標記、在線、所在地、戰鬥中；離隊、踢人、移交。放在指令窗（Ctrl+4）新增「隊伍」分頁，或燈籠旁的小框（WP-UI 擇一，寫進交付說明） |
| 加入戰鬥 | `view.battles` 中 `joinable` 的戰鬥在場景卷軸顯示「加入戰鬥」按鈕 → `battle_join` |
| 戰鬥畫面 | `my_side == 1` 時鏡像（4.5.3）；處理 `battle_unit_join`（新單位出現）；PvP 對手用玩家美術（`look`） |
| 聊天 | 頻道選擇鈕列出 千里傳音／傳音入密／輕聲細語／門派交談／組織交談／隊伍交談／江湖謠言（管理員多「天外飛仙」）；預設發話頻道 **輕聲細語**【原作證實 AUTHENTIC_UI_SPEC 9.2】，記住上次選擇；傳音入密要輸入對象名字；`CHANNEL_OF` 對應 4.1 的 ch；顏色照 AUTHENTIC_UI_SPEC 9.3。聊天輸入框節點名固定為 `ChatInput`（給 ui_playthrough 找） |
| 飛鴿傳書 | HUD「鴿」圓章：`mail_unread > 0` 時閃爍；點開 → 視窗（收件匣 `mail_list`、讀、刪、寫信：收件人名＋內文 200 字） |
| 屍體 | 場景卷軸的屍體 → 撿取視窗：物品清單（`items`）、「全部拿走」、單件拿走、保護期倒數；自己的屍體另有「允許某人翻動」（輸入名字）；屬性窗或系統訊息顯示 `my_corpses` |
| 系統窗（Ctrl+5）「特殊開關」 | 接受叫戰、接受組隊邀請（`set_pref`）、顯示名稱（本機設定）；管理員多一顆「伺服器設定」 |
| 伺服器設定面板 | `server_options` 的 editable 清單（下拉）＋玩家名單（踢出、踢出並禁止，需確認） |
| 角色護照 | 角色選擇畫面：「護照」按鈕列出本機護照（`SaveManager.list_passports`）→ 「用護照還原」→ `passport_restore`；說明文字照 4.6.8 的誠實說明 |
| 連線 | 斷線畫面（`SceneRouter.show_disconnected`）：主機關閉時顯示「主機已離線，江湖凍結」；有 `last_target` 時顯示「重新連線」（呼叫 `NetworkManager.reconnect()`，最多自動重試 3 次、間隔 5 秒）；被踢顯示原因 |
| 標題／大廳 | 開 Steam 房、邀請好友、加入好友、搜尋大廳（既有 net_debug 的功能搬到正式標題畫面或保留除錯畫面入口；版本不符的大廳灰掉） |

---

## 5. 規則與數值（附來源）

### 5.1 組隊與多人戰鬥

| 規則 | 值 | 來源 |
|---|---|---|
| 隊伍上限 | 5 | 上限【待考證】→ GDD 10.2【設計提案】 |
| 經驗分享 | 勝利時每位還站著的參戰隊員（D9）各得 `round(基礎 × 比例 × 1/√n)`（n＝存活參戰玩家數，含中途加入） | 分享【已證實 17173 xinshou/14】；公式 GDD 2.4【設計提案】（M1 已實作） |
| 學點分享 | 同上（學點的比例夾在 0.2–3.0） | 同上 |
| 死亡／逃走的參戰者 | 不分 | 【設計提案】（M1 行為） |
| 掉落、銀兩、怪物的善惡與殺氣 | 給最後一擊者 | GDD 5.8【設計提案】 |
| 中途加入 | 隊友可加入同房的進行中戰鬥，從邊緣空格出場 | 【已證實 17173】；出場位置 GDD 5.8 |
| 開戰拉入同房隊友 | 遇敵、定點戰時自動入場；**守衛戰不拉**，隊友要幫忙就 `battle_join` | 【設計提案】。守衛是衝著某人的 PK值／善惡來的，不該把無辜的隊友拖去打 qi 3000 的官兵、替別人吃死亡懲罰（2026-10-18 第二輪審查） |
| 一場戰鬥玩家上限 | 8 | 【設計提案】 |
| 等待模式 | 逾時 `max(8, 20 − 2×(人數−1))`；每輪預算 45 秒；連兩次逾時 afk 3 秒 | TECH_ARCH 10.7【設計提案】（M1 已實作） |
| 斷線 | 單位自動防到結束；同角色重連後接回 | D4【設計提案】 |
| 離線／換角 | 立即離隊 | 【設計提案】 |
| 邀請／叫戰 | 60 真實秒過期 | 【設計提案】 |
| 系統開關 | 接受叫戰、接受組隊邀請、顯示名稱 | 【已證實 17173 yinan/33】 |

### 5.2 PK、善惡、殺氣、守衛

| 規則 | 值 | 來源 |
|---|---|---|
| 叫戰條件 | 同房（＝視線範圍）、對方同意、可關閉接受 | 【已證實 17173 xinshou/10、yinan/33】；「同房＝視線」【設計提案】 |
| 強制 PK 操作 | 連結鍵 + 點擊；預設 Ctrl，系統窗「特殊開關」可改 Alt／Shift（`ui.pk_key`） | 「連結鍵」【已證實 2001】；Ctrl【newton】；可改鍵是研究的建議 |
| 擊殺廣播 `pk_kill`「【江湖傳聞】X在某地死在Y手下」 | 強制 PK 的擊殺：所有在線玩家；叫戰的擊殺：只有擊殺者與死者 | 【設計提案】：原作資料沒有這種廣播（研究只把強制 PK 列為懸賞的前提）。叫戰是雙方同意的比武，不廣播（2026-10-18 審查） |
| 確認框的說明 | PK值 +1、殺氣 +100；依對方 `align`：惡人 →「善惡反而變好（+10）」，其餘 →「善惡變差（−10）」；寫明兩個守衛條件（善惡變負、PK值超過 3）；依自己的角色表算出殺後會挨官兵時直說 | 跟著本表的數值（2026-10-18 第二輪審查） |
| 允許地區 | `regions.pk_allowed == true`（城、華山、少林為 false） | D7【設計提案】 |
| PK 模式 | CLASSIC／CHALLENGE_ONLY／OFF，預設 CLASSIC | GDD 6.2【設計提案】 |
| PK值 | 強制擊殺玩家 +1；叫戰擊殺不加 | 【已證實 17173 xinshou/10】 |
| 誰算強制擊殺 | 只有出手者（side 0；PvP 不能中途加入，side 0 一定是出手者）。被出手的一方（side 1）反殺出手者＝自衛，照叫戰擊殺算：PK值不加、善惡不變、殺氣 +100、`pk_kill` 只給兩個當事人 | 原作的 PK值 +1 綁在「必須按連結鍵方可強迫開啟戰鬥」的惡意 PK【已證實 17173 xinshou/10】；反殺照叫戰算【設計提案】（2026-10-18 第三輪審查） |
| 叫戰／組隊重邀冷卻 | 被拒絕或到期後，同一人向同一人再叫戰／再邀要等 `pending_retry_cooldown_real_s`（10 真實秒）；`challenge_cooldown`／`invite_cooldown` | 【設計提案】（2026-10-18 第三輪審查：拒絕後能立刻連發洗提示） |
| PK值遞減 | 每 1800 秒**角色上線時間** −1（惰性計算） | 每真實 30 分鐘【已證實 newton】；只算上線時間【設計提案】（世界凍結） |
| 守衛 | 進出城時：PK值 > 3 → 2 名官兵；否則善惡 < 0 → 1 名；`guards_enabled` | 進出城被追殺、PK > 3【已證實 newton／官方】；善惡負被攻擊【已證實 官方】；人數【設計提案】 |
| 守城官兵強度 | qi 3000、刀法 80（新手幾乎必敗，可逃） | 「城衛很強」【已證實 研究補充】；數值【設計提案】 |
| 新手保護 | 實戰 < `newbie_pk_protect_xp`（500）不能被強制 PK | GDD 6.2【設計提案】 |
| 殺氣 | 殺死玩家 +100（叫戰、強制都算）；殺怪依 `killing_intent_on_kill` | GDD 6.3【設計提案】 |
| 善惡 | 強制擊殺非惡人 −10；強制擊殺惡人（< −100）+10；叫戰 0；範圍 ±1000 | 範圍【已證實】；數值【設計提案】。原本 −50：配上【已證實】的「善惡為負進出城就有官兵」，一次 PK 就讓善惡 0 的人進出城挨打，【已證實】的「PK值 > 3 才追殺」寬限形同虛設。−10 讓平時行善（善惡 ≥ 10）的人保有三次的寬限；善惡 0 的人第一次 PK 仍會挨打（照【已證實】的規則），確認框會先說（2026-10-18 第二輪審查） |
| 名字顏色 | 善惡 > 100 白、< −100 藍、其餘黃 | 顏色【已證實 鐵心網 FAQ】；門檻 GDD 6.1【設計提案】 |
| PvP 獎勵 | 無實戰、無學點 | 【設計提案】（防止互刷） |
| PvP 死亡 | 照 rule_profile 的死亡規則（降級、屍體、重生） | GDD 6.4、TECH_ARCH 15.3 |
| 神兵利器轉移給擊殺者 | M3 | 【已證實】，延後（2.2） |

### 5.3 屍體

| 規則 | CLASSIC_30 | LATER_10 | 來源 |
|---|---|---|---|
| 保護期（本人＋授權者） | 600 秒 | 600 秒 | 【已證實 17173 yinan/29】／【後期版 官方死亡頁】 |
| 公開期 | 600–1800 秒 | 600–1800 秒 | 2001【已證實】；後期消失時間沒寫 → 1800【設計提案】（D6） |
| 授權人數上限 | 4 | 4 | 授權【已證實】；人數【設計提案】 |
| 計時 | 世界時間（主機離線時凍結） | 同左 | TECH_ARCH 9 |
| 撿取 | 全部或單件；放不下的留在屍體上 | 同左 | 【設計提案】 |

### 5.4 聊天與飛鴿

| 規則 | 值 | 來源 |
|---|---|---|
| 頻道與對象 | 8 頻道（4.4.3） | 【已證實 17173 yinan/15】 |
| 耗水頻道 | 千里傳音、輕聲細語、門派、組織、隊伍：是；傳音入密：否；江湖謠言：是；天外飛仙：否 | 前五項與密語【後期版：懷舊版 jyhj】；謠言【提案】；GM 不扣 |
| 每則耗水 | 1 | GDD 10.1【提案】 |
| 飲水 0 不能說話 | `thirsty`：所有頻道（含不耗水的傳音入密）；天外飛仙例外；`chat_water_cost == 0` 時整條規則關閉 | 【已證實 官方屬性頁：不限頻道】；GM 例外與 0 耗水關閉【設計提案】（2026-10-18 第三輪審查：原本只擋耗水頻道，是把已證實的規則縮小了） |
| 謠言匿名 | 他人看到「(謠言)」 | 【已證實 17173 yinan/15】 |
| 未選角 | 只能千里傳音，不耗水；頻率照樣檢查；名字一律加「（未入世）」、事件帶 `unbound: true`（不能冒充角色） | 【設計提案】（M0 相容；頻率 2026-10-18 審查加上；標記第三輪審查加上） |
| 發話頻率 | 每 500 ms 一則，依身分計（重連不歸零） | 【設計提案】 |
| 頻道選單 | 只列 8 個發話頻道；耗水的標「（耗水）」；天外飛仙在「頻道開關」裡不能關 | 不能關【已證實 17173 yinan/15】；耗水標記照懷舊版攻略的列法 |
| 飛鴿：離線也收得到、圖示閃爍 | 存在主機，上線時 `mail_waiting` | 【已證實 官方】；存主機 GDD 10.4 |
| 信件長度／收件匣／寄信間隔／費用 | 200 字／50 封（滿時先刪最舊已讀）／10 真實秒（依身分計）／免費 | 【設計提案】 |
| 同一寄件人的未讀上限 | 每個收件匣 10 封 | 【設計提案】（2026-10-18 審查） |

---

## 6. 測試計畫

### 6.1 各 WP 的單元與整合測試（全部在 `tests/run_tests.gd` 裡跑）

| WP | 檔案 | 至少要有的案例 |
|---|---|---|
| PARTY | `test_party_system.gd` | 邀請／接受／拒絕／過期（`world_span`）／滿員／非領隊邀請／踢人／移交／領隊離開接任／剩 1 人解散／離線即離隊 |
| PARTY | `test_battle_join.gd` | `join_unit` 在 RUNNING 與 AWAIT 都能加、放在邊緣空格、沒有空格回 0、事件含 `battle_join` 與 `battle_unit_join`；`winner_side`；PvP 兩個玩家單位的結果 |
| PARTY | `test_battle_pacing.gd` | 8 玩家單位（2 個不下令）跑到結束：每輪等待 ≤ 53 秒、afk 標記、最壞一輪的秒數印出來 |
| PARTY | `test_world_party.gd` | 遇敵拉入同房閒置隊友（不同房、戰鬥中的不拉）；`battle_join` 驗證順序全部原因碼；勝利時 3 人都有實戰且每人 = 單人 × 1/√3（同實戰時）；中途加入者也有；斷線後重連 `char_select` 接回同一場；`room_battles` |
| PK | `test_morality_pk.gd` | `pk_value` 遞減邊界（1799／1800／3600 秒）、`guard_count`、`kill_deltas`、`align_of` 邊界 ±100／±101 |
| PK | `test_character_m2.gd` | 新欄位往返、舊檔缺欄位補預設、`add_pk` 正規化、`req_pk_max` 用目前值 |
| PK | `test_world_pk.gd` | `challenge` 與 `force_pk` 全部原因碼（依序）；`pk_mode` 三種；叫戰接受開戰（雙方 `my_side`）、拒絕、過期、關閉接受；強制擊殺 → PK值 1、殺氣 +100、善惡 −10、`pk_kill` 全員收到；叫戰擊殺 PK值 0；守衛：pk=4 出城 → GUARD 戰 2 名、morality=−1 → 1 名、`guards_enabled=false` 不觸發、城內移動不觸發 |
| PK | `test_world_corpse.gd` | 保護期他人 `corpse_protected`、授權後可撿、公開期誰都能撿、單件撿、`corpse_public` 只送一次、`corpse_auth_full`、重開世界後 `authorized` 與剩餘時間不變 |
| SOCIAL | `test_world_chat.gd` | 每個頻道的收件人集合；耗水與不耗水；`thirsty`；`no_sect`／`no_guild`／`no_party_chat`／`no_such_player`／`not_admin`／`chat_too_fast`；謠言他人那份 `from == ""`、`from_peer == 0`；無角色只能千里傳音且不扣水；BBCode 被清理 |
| SOCIAL | `test_world_mail.gd` | 寄給離線角色 → 重開世界 → 對方上線收到 `mail_waiting`；在線即時 `mail_arrived`；讀／刪／`mail_not_found`；收件匣滿時刪最舊已讀；全未讀 → `mailbox_full`；`mail_too_fast`；刪角色清信 |
| HOST | `test_protocol_m2.gd` | 4.1 每個新 intent 的型別、必填、列舉、範圍；chat `to` 規則；mail 長度；passport 大小；`VERSION == 3` |
| HOST | `test_world_persist.gd` | `restart_world()` 後：世界時間 ≥ 停止前、屍體、信件、PK基準與 stamp、任務、角色位置、禁止名單都在；隊伍消失；關服時進行中的戰鬥 ABORTED、不扣死亡 |
| HOST | `test_passport.gd` | 簽章往返（含 JSON 存讀一次）、改一個數字 → `passport_bad_sig`、`passport_wrong_world`／`wrong_identity`／`not_needed`、刪掉角色檔後還原成功 |
| HOST | `test_world_admin.gd` | 非管理員 `not_admin`；`server_opts_set` 每個 key、`bad_option`、`bad_value:value`；改 rule_preset 後 `GameData.rules` 變更且 `world_info_changed` 廣播；`admin_kick` + ban → 再 hello 被拒 `banned`；重連取代舊 session |
| UI | `test_ui_m2.gd` | 鏡像座標換算往返；頻道選擇與 `ChatInput`；鴿章閃爍條件；pending 提示由 sheet 重建；伺服器面板依 `server_options` 產生控制項；屍體視窗按鈕狀態 |

### 6.2 多客戶端 bot：`tests/bots/m2_party_bot.gd`（整合者）

- 啟動參數：`--bot=res://tests/bots/m2_party_bot.gd --m2-role=<leader|member|pker|victim> --m2-run=<4 hex> --m2-sync=<絕對路徑> [--m2-phase=return]`。
- 只透過 `NetworkManager.send_intent()`、`ClientState` 與 `NetworkManager.reconnect()` 互動；一次只送一個 intent。
- 角色名：`隊長<run>`、`隊員<run>`、`狂徒<run>`、`路人<run>`（≤ 8 字）。
- **同步**：用檔案柵欄。每個 bot 在 `<sync>/<role>.<step>` 寫檔表示完成該步，`wait_for(roles, step, timeout)` 等別人；不靠聊天同步（聊天本身是受測物）。
- 戰鬥 AI：輪到時，相鄰有敵人就 `ATTACK`，否則 `MOVE` 到移動範圍內離最近敵人最近的空格，都不行就 `DEFEND`；氣 < 30% 且有金創藥就 `REST`／用藥（可沿用 m1_playthrough_bot 的輔助函式）。路人在強制 PK 戰只按 `DEFEND`。
- 失敗印 `M2_BOT_FAIL role=<r> step=<n> <原因>`、結束碼 2；成功印 `M2_BOT_OK role=<r>`、結束碼 0。

步驟（每步的斷言都要寫進失敗訊息）：

| 步 | 誰 | 動作與斷言 |
|---|---|---|
| 1 | 全部 | 連線、建角（西夏）、寫 `ready`；等 4 人 |
| 2 | 隊長 | 依 `view.players` 邀請 隊員、狂徒、路人；路人第一次拒絕（隊長收 `party_declined`），隊長再邀，路人接受；全員 `sheet.party.members.size() == 4`、領隊是隊長 |
| 3 | 全部 | 隊長 `CHAT_PARTY`，其餘 3 人收到 `chat_party`；隊長 sheet 的 water 至少少 1；隊員密語路人，只有路人收到 `chat_whisper`（其他人過 2 秒沒有）；狂徒 `CHAT_RUMOR`，其他人收到的 `from == ""` |
| 4 | 隊長、隊員、狂徒 | 沿 `xx_square →E xx_gate_e →E xw_road →E xw_grass →E xw_hill` 走，每房等齊再走；途中遇敵就打（同房者應被拉入）。路人停在 `xw_grass` |
| 5 | 隊長 | `talk` + `fight n_bandit_chief`；隊員、狂徒 3 秒內收到 `battle_opened`（沒有自己送 intent）；寫 `boss.started` |
| 6 | 路人 | 讀到 `boss.started` 後走到 `xw_hill`，`view.battles` 有 joinable → `battle_join` → 收到 `battle_opened` 與 `battle_join`。全員打到結束：`VICTORY`；存活者 `rewards.combat_xp > 0`。輸了可重試一次（休息後再打），再輸就失敗 `boss_lost` |
| 7 | 狂徒 | `party_leave`（其他人收 `party_left`）；全員走到 `xw_road`（`pk_allowed`） |
| 8 | 狂徒→隊長 | `challenge` → 隊長 `challenge_reply false` → 狂徒收 `challenge_declined`；隊長 `set_pref accept_challenge false`；狂徒再 `challenge` → `challenge_refused` |
| 9 | 狂徒→路人 | `force_pk`；雙方 `battle_opened.kind == "FORCED"`、路人 `my_side == 1`；打到路人死亡：路人 `battle_closed.you_died`；狂徒收 `pk_kill`、`sheet.pk == 1`；隊長的 `view.corpses` 有路人的屍體 |
| 10 | 狂徒 | `loot_corpse` → `corpse_protected` |
| 11 | 路人 | 從 `sheet.my_corpses` 取 id → `corpse_authorize name=隊長…`；隊長收 `corpse_auth_granted` → `loot_corpse` 帶第一個 `item_uid` → `corpse_looted_other`；路人收 `corpse_looted_by`；屍體仍在、件數 −1；記下 corpse_id 與件數 |
| 12 | 隊員 | 寫 `leaving`，`NetworkManager.leave()` 後結束（`M2_BOT_OK role=member`） |
| 13 | 隊長 | 等隊員程序結束（讀 `member.left`，由 orchestrator 寫）→ `mail_send to=隊員…`（離線收件）→ `mail_sent`；路人寄信給隊長 → 隊長收 `mail_arrived`、`sheet.mail_unread == 1` → `mail_list` → `mail_read` |
| 14 | 隊長、狂徒、路人 | 記下 `sheet.clock.day`、狂徒 pk、屍體資訊；寫 `restart.ready`；等 `host.restarted` |
| 15 | 同上 | 收到斷線後每 2 秒 `reconnect()`，90 秒內必須重新 `welcomed`；`char_select` 原角色；斷言：`sheet.party` 為空、狂徒 `pk == 1`、隊長在 `xw_road` 看到同 id 屍體且件數相同、`clock.day` ≥ 之前、隊長 `mail_list` 中那封信 `read == true`；寫 `final` |
| 16 | 隊員（`--m2-phase=return`，由 orchestrator 重新啟動） | 選角後收到 `mail_waiting n=1`；`mail_list` 有隊長的信；`mail_read`；寫 `final` |

### 6.3 驗收指揮：`tools/m2_acceptance.gd`（整合者；照 `tools/net_smoke.gd` 的寫法）

- `extends SceneTree`；參數 `--timeout=1500`（預設）、`--keep-logs`、`--time-scale=10`。
- 產生 `run`（4 hex）、世界 `m2acc_<run>`、目錄 `user://m2_acceptance/<run>/`（`sync/`、`*.log`）。
- 啟動主機：`--no-steam --dedicated --enet-host --port=<25000–29999 隨機> --world=m2acc_<run> --rule-preset=classic_strict --opts=newbie_pk_protect_xp=0 --time-scale=10 --stop-file=<sync>/host.stop --quit-after=<timeout+60>`；等 log 出現 `ENet 主機`。
  - `classic_strict`：新角色死亡也會留屍體（STANDARD 對實戰 ≤ 500 免罰，不會有屍體）；`newbie_pk_protect_xp=0`：新角色可被強制 PK。
- 啟動 4 個 bot（`--no-steam --enet-join=127.0.0.1:<port> --profile=m2_<role>_<run> --name=<role> --bot=… --m2-role=… --m2-run=… --m2-sync=<絕對路徑> --quit-after=<timeout+30>`）。
- 監看：隊員程序結束 → 寫 `member.left`。三個 `restart.ready` 到齊 → 寫 `host.stop` → 等主機程序結束（≤ 30 秒，`OS.is_process_running`）→ 複製 `user://worlds/m2acc_<run>/world.json` 備查並斷言其中有該屍體 id 與兩封信 → 以相同參數重開主機（`--rule-preset` 對既有世界無效，無妨）→ 等 `ENet 主機` → 寫 `host.restarted` → 以 `--m2-phase=return` 重新啟動隊員。
- 全部 bot `final` 且結束碼 0 → 寫 `host.stop` 等主機結束 → 斷言主機 log 沒有 `SCRIPT ERROR` → 印 `M2_ACCEPT_OK`、結束碼 0。
- 任何失敗、逾時、看門狗：印 `M2_ACCEPT_FAIL <原因>`、傾印各 log 尾端 40 行、結束碼 1／2。
- **一律** `OS.kill()` 所有子程序（`_finalize` 也要做）；結束後 `tasklist` 不得有殘留。

### 6.4 回歸

- M1 驗收 bot 可能受影響的地方（整合者處理）：聊天耗水（bot 沒聊天則無影響）；守衛（bot 的善惡若變負，出入城會被打）；`chat` 預設頻道。
- `ui_playthrough.gd`：聊天框改用節點名 `ChatInput` 找；預設發話頻道變成輕聲細語。
- `net_smoke`：不改；必須綠燈（無角色千里傳音路徑）。

### 6.5 Steam 兩帳號手動清單（擁有者；M2 結束前跑一次，結果記進 README）

- [ ] TECH_ARCH 15.4 的全部項目（含渲染器矩陣中至少 Compatibility 與 Vulkan）。
- [ ] 主機建 FRIENDS_ONLY 大廳 → 覆蓋介面邀請 → 對方**遊戲已開**時接受 → 進入角色選擇。
- [ ] 對方**遊戲沒開**時接受邀請（冷啟動）：記錄啟動的是本作還是 Spacewar。
- [ ] 對方已在別的世界（例如單機）時接受邀請：自動離開原世界（有存檔）並加入。
- [ ] 好友清單「加入遊戲」。
- [ ] 兩人組隊、隊伍頻道、密語、寄信（對方離線一次）。
- [ ] 兩人一起打山賊頭目：一人開戰時另一人被拉入；第二次讓一人晚到再「加入戰鬥」。
- [ ] 東門外官道叫戰（拒絕一次、接受一次）；強制 PK（Ctrl+點名字）；屍體授權與撿取。
- [ ] 客戶端拔網路線或結束程序（戰鬥中）→ 主機上單位自動防 → 客戶端重開後「重新連線」→ 接回戰鬥。
- [ ] 主機開伺服器設定面板，改 PK 模式為「禁止 PK」→ 客戶端強制 PK 得到 `pk_disabled`；改回。
- [ ] 主機踢人（不禁止）→ 對方看到原因並回標題 → 可再加入；踢出並禁止 → 再加入被拒。
- [ ] 主機關遊戲 → 客戶端顯示「主機已離線，江湖凍結」→ 主機重開同一世界 → 客戶端「重新連線」→ 角色、屍體、信件都在。
- [ ] 4 人以上時量一次戰鬥中每輪等待秒數（`battle_await` 倒數），記錄 Steam 端延遲感受。
- [ ] 角色護照：客戶端 `user://passports/` 有檔；主機刪掉該角色檔後，客戶端「用護照還原」成功；手改護照一個數字 → 驗章失敗。
- [ ] （手動、選做）練到實戰 1 萬的隊伍打鬼王（血刀洞迷宮 `gw_throne`）。

---

## 7. 交付與整合

1. 每個 WP 交付時附：改了哪些檔、新增的 `class_name`、所有 `# M2_PLAN 缺漏` 註解、自己跑過的測試指令與結果、確認沒有殘留 godot 程序。
2. 整合者合併順序：WP-HOST → WP-PARTY → WP-PK → WP-SOCIAL → WP-UI；每合一個跑 `--import`、`run_tests`、`data_lint`。
3. 全部合完：`balance_sim` 兩個新 case → `net_smoke` → M1 bot（三規則＋網路）→ `ui_playthrough` → `m2_acceptance` → 更新 README（M2 怎麼玩、新參數 `--opts`、`--stop-file`、驗收指令、Steam 清單結果）。
4. 不 git commit。

---

## 8. 整合紀錄（整合者，2026-10-18）

### 8.1 結果

| 檢查 | 結果 |
|---|---|
| `tests/run_tests.gd` | 663 tests, 0 failed |
| `tools/data_lint.gd` | 0 errors, 0 warnings |
| `tools/net_smoke.gd` | PASS（未修改） |
| `tools/balance_sim.gd --runs=500` | 18 cases ok（`party4_vs_bandit_chief` 100%、死亡中位數 1；`solo_vs_bandit_chief` 0%；`newbie_vs_city_guard` 0%） |
| M1 驗收 bot（三種死亡規則、新世界＋ENet 網路版） | 四次都 `M1_ACCEPT_OK` |
| `tests/ui/ui_playthrough.gd` headless | `UI_PLAY_OK`（新增第 14 步 M2 介面）；有視窗 1920×1032 截圖 `UI_PLAY_OK shots=41` |
| `tools/m2_acceptance.gd` | `M2_ACCEPT_OK`（連續 3 次，30–110 秒） |
| Steam 兩帳號手動清單 6.5 | 擁有者未跑（README 有表格） |

### 8.2 整合時的決定與偏差

| # | 項目 | 決定 |
|---|---|---|
| I1 | `data/art.json`（3.2 凍結） | 整合者加了 `m_bandit_chief`、`m_city_guard` → `alias: m_bandit`，`n_bandit_chief` → `alias: m_bandit_chief`（WP-PARTY 的 Day-0 資料列沒有美術項，data_lint 與 `test_art_registry` 會紅）。正式美術到了再換 |
| I2 | 4.9 山賊頭目數值 | 採用 WP-PARTY 依 balance_sim 調整後的列（qi 800、str 6、刀法 5、weapon 0…）；原貼的列 4 個新手勝率 0%。守城官兵未改 |
| I3 | 2.4 第 6 項「4 人都有實戰」 | 改為「勝利時還站著的人都有實戰」（5.1：戰死者不分）。驗收 bot 斷言每個存活者 `rewards.combat_xp > 0`，並由隊長印出每人分到的實戰 |
| I4 | 6.2 第 4 步 | 路人也跟著走到 `xw_grass`（四人每房柵欄），三人再上 `xw_hill`。bot 加兩條求生規則：到達或等柵欄時，同房隊友的戰鬥 `joinable` 就 `battle_join`；單人遇到野狼（`newbie_vs_wolf` 0%）就往逃跑格逃。頭目戰輸了或路人沒趕上加入，最多重來 3 次 |
| I5 | 6.2 第 7 步 | `classic_strict` 下路人若先前戰死就身無長物，強制 PK 後不會有屍體（或只有一件、單件撿後屍體消失）：路人背包少於 2 格時先到西夏客棧買饅頭與清水 |
| I6 | 6.2 第 9 步 | 另加斷言：狂徒殺氣 +100、善惡 `FORCED_KILL_MORALITY`（−10）、收到 `killing_intent_change`／`morality_change`；第 15 步重開後所有人的善惡與殺氣不變 |
| I7 | 6.2 柵欄 | 「等別人觸發的事件」一律從**寫柵欄檔當下**的事件序號開始找（別人過柵欄前我一定已經寫了檔），避免對方的事件比我離開柵欄還早到而漏看 |
| I8 | `ui_playthrough` | 聊天框改用節點名 `ChatInput` 找（6.4）；新增第 14 步（頻道鈕、輕聲細語、隊伍頻道 `no_party_chat`、傳音入密對象欄、隊伍框在沒有隊伍時隱藏、飛鴿視窗、特殊開關 `set_pref`、伺服器設定面板）。單機只有一人，組隊後的隊伍框由 m2_acceptance（主機端）與 `test_ui_m2.gd` 驗；`ui_driver.gd` 新增 `type_text_edit`、`choose_menu`、`menu_items` |
| I9 | 各 WP 的 `# M2_PLAN 缺漏` | 全部接受（見各 WP 交付說明）：PvP 不能中途加入（`join_not_allowed`）、`reattach` 不重複呼叫 `enter_character`、`left_s` 是「目前這一段」的剩餘真實秒數、主機本機玩家不能被同 identity 重連取代、護照簽章前把整數化的 float 轉回 int、`intents_item.gd` 的舊 `loot_corpse` 由 `intents_pk.gd` 覆蓋（死碼，留著無害） |

### 8.3 審查修正（2026-10-18）

三份審查（規則、主機、介面）的修正，全部附回歸測試：

| 來源 | 問題 | 修正 |
|---|---|---|
| 規則 1 | 天外飛仙能在「頻道開關」關掉（原作不能關） | `MessageLog.LOCKED_ON`：開關灰掉、`set_channel_enabled` 忽略、舊設定檔的「關」載入時改回開 |
| 規則 2 | 「屍體漂浮」沒做也沒記延後 | 2.2 加延後列（行為原作沒寫，不發明） |
| 規則 3 | 強制 PK 鍵寫死 Ctrl | 系統窗「特殊開關」可選 Ctrl／Alt／Shift（`ui.pk_key`），選單、提示框跟著顯示 |
| 規則 4 | 確認框說殺誰都「善惡變差」 | 依對方 `align`：惡人 → 善惡變好 |
| 規則 5 | `pk_kill` 全服廣播是發明的規則、5.2 沒列 | 5.2 加【設計提案】列；叫戰擊殺只告訴兩個當事人 |
| 規則 6 | GDD 里程碑表還把陣形、懸賞列在 M2，驗收寫「打馬王」 | GDD 13.1／13.3 改成延後後的範圍 |
| 主機 1 | 斷線留在隊友戰鬥裡的角色可以被刪除／護照還原，戰鬥結束時被存檔寫回、名字可被重取 | `char_delete`、`passport_restore` 在 `battles.battle_of_char(id) != 0` 時回 `char_active` |
| 主機 2 | 沒選角的連線發千里傳音不檢查頻率 | 4.6.6 第 2 步也檢查 `chat_too_fast` |
| 主機 3 | 聊天、寄信的頻率記在 Session 上，重連就歸零；一個人能塞滿別人的收件匣 | 依身分記錄；同一寄件人未讀上限 10 |
| 主機 4 | 讀信、刪信沒有立刻存檔 | 和寄信一樣 `save_now()` |
| 介面 1 | 飛鴿／屍體視窗蓋住叫戰提示的文字，只露出「接受」 | 提示框畫在視窗之上，對話框層往下讓出提示列（`MainScreen.prompt_band_bottom`） |
| 介面 2 | 隊伍框「領」「踢」「離隊」一按就送 | 都先經確認框；「領」「踢」中間留空 |
| 介面 3 | 打 NPC 的戰鬥標成【切磋】 | `FIGHT` 改「打鬥」 |
| 介面 4 | 飛鴿分頁深底墨字、內文是預設灰色 TextEdit | 卷軸主題補上 TabBar 分頁、TextEdit、LineEdit 焦點樣式 |
| 介面 5 | 頻道選單看不出耗水、13 項要捲動 | 只列 8 個發話頻道，耗水的標「（耗水）」；謠言耗水本來就是【提案】（5.4） |
| 介面 6 | 伺服器面板只列設定檔名稱 | 角色名為主，設定檔名稱與身分縮寫放括號 |
| 介面 7 | 屍體視窗保護期說兩次、空白大塊、看不到已授權的人 | 不能撿時藏起物品區；物品區高度跟件數；擁有者看到「已允許（n／4）」 |
| 介面 8 | 提示的倒數「（60」「秒）」斷行 | 倒數是獨立不換行的標籤 |
| 介面 9 | 未讀「●」畫成彩色 emoji | 改「［新］」 |
| 介面 10 | `not_connected` 顯示原始代碼 | 加 `err_not_connected` |
| 介面 11 | 頻道截圖沒拍到選單 | 第 14 步截圖時打開選單 |

### 8.4 第二輪審查修正（2026-10-18）

| 來源 | 問題 | 修正 |
|---|---|---|
| 規則 1／介面 3 | 一次強制 PK（善惡 −50）就讓善惡 0 的人進出城挨官兵，「PK值 > 3」寬限沒意義；確認框只說 PK 值超過 3 | `FORCED_KILL_MORALITY` −50 → −10【設計提案】（5.2）；確認框寫出殺氣 +100、兩個守衛條件，依自己的角色表算出殺後會不會挨打 |
| 規則 2 | 經驗只分給站著的人，GDD 卻寫原作規則 | 記為偏差 D9，GDD 10.2 加註 |
| 規則 3 | 守衛戰把無辜隊友拉進去 | `PULL_KINDS` 拿掉 `GUARD`；隊友可 `battle_join` 自願加入 |
| 規則 4 | 門規（受戒／開除）是死資料、沒記延後 | 2.2 加 M3 列；GDD 6.3 加註 |
| 規則 5 | Alt+Space 沒做也沒記延後 | 2.2 加 M3 列（模式原作沒寫，不發明） |
| 規則 6 | `later_official` 改了看不出差別 | 伺服器設定面板顯示每個規則組合的說明，寫明屍體消失時間是暫定、和懷舊相同（D6） |
| 規則 7 | 西夏守衛「手持長槍」、官兵卻用刀 | 描述改「腰懸鋼刀」 |
| 主機 1 | 刪角後用舊護照還原能洗掉 PK、複製屍體物品；還原不管角色上限 | 刪除後還原時比對 `deleted/` 封存檔的 `online_s`（`SaveManager.deleted_character_online_s`）；用最新護照仍可還原；檢查 `too_many_chars` |
| 主機 2 | 還原能造出同名的第二個角色 | 名字屬於另一個仍存在的角色 → `passport_name_taken`，不寫檔 |
| 主機 3 | 叫戰後組隊，接受時隊友互打 | `challenge_reply` 接受時重驗 `target_in_party` |
| 主機 4 | 翻屍體、死亡時兩個檔案的寫入順序會在當機時複製物品 | 翻屍體 `save_now(true)`：先 world.json 再角色檔；死亡時先明寫死者的角色檔（斷線者不在 `sessions()`）再寫 world.json。兩者當機時最多消失、不會複製 |
| 主機 5 | 驗收在 10 倍速下屍體只剩不到一成壽命餘裕 | `m2_acceptance` 預設 `--time-scale=5` |
| 主機 6 | 邀請者已加入別人的隊伍（不是領隊），對方接受照樣入隊 | 回 `no_invite`，邀請作廢 |
| 介面 1 | 特殊開關頁撐高系統窗、蓋住精氣條和熱鍵列 | 系統窗右欄放進 `ScrollContainer` |
| 介面 2 | 回覆提示後立刻移除，下面的叫戰補到游標底下，連點就誤接 | 回覆的列留在原位、停用、顯示「已回覆」，等主機的 sheet 不再列才移除；有列移除後 300 ms 內的點擊不算 |
| 介面 4 | 叫戰提示看不出輸了會死 | 提示加「（生死自負）」，接受鈕的提示寫明死亡懲罰與對方殺氣 +100 |
| 介面 5 | 「X的屍體（2 件）　自己的」 | 自己的寫「我的屍體（2 件）」 |
| 介面 6 | 隊伍列名字長時「戰鬥中」被截掉 | 「戰鬥中」是獨立、不截斷的標籤 |
| 介面 7 | 一個開關的結果報三次 | `pref_changed` 只進聊天紀錄（不進右下系統框、不進面板回饋列） |
| 介面 8 | 頻道選單看不出目前頻道；打字後看不出耗水 | 選單改單選鈕、目前頻道打勾；耗水頻道的頻道鈕字染水藍、提示寫明 |
| 介面 9 | 空收件匣一大片空白加兩顆灰按鈕 | 空的時候藏起回信／刪除，讀信欄放寫信說明與「寫信」鈕 |

### 8.5 第三輪審查修正（2026-10-18）

| 來源 | 問題 | 修正 |
|---|---|---|
| 規則 1 | 被強制 PK 的人反殺出手者，被當成兇手：PK值 +1、殺氣、善惡 −10、全服「江湖傳聞」，善惡 < 10 的進出城挨官兵 | `PkSystem.effective_kill_kind`：強制 PK 只有 side 0（出手者）算 `FORCED`；side 1 反殺照叫戰擊殺算（5.2 新列，【設計提案】）；`test_force_pk_victim_counter_kill_is_self_defence` |
| 規則 2 | 已證實的「飲水 0 不能說話」被縮成「只擋耗水頻道」，密語照講 | 飲水 0 時所有頻道都擋（天外飛仙例外；`chat_water_cost == 0` 時整條關閉）；GDD 10.1、5.4 改寫 |
| 規則 3 | GDD 6.4、TECH_ARCH 10.3／15.3 還寫「斷線留 30 秒」 | 改成 D4 的實際行為（自動防到戰鬥結束、重連接回） |
| 主機 1 | `m2_acceptance` 兩次都在 `boss1.ready` 逾時：嚴格死亡規則下狂徒單獨走路遇狼死兩次、越死越弱；柵欄 300 秒 ＝ 戰鬥逾時 | 新選項 `encounters_enabled`（4.7.1，測試／管理用）；驗收主機帶 `--opts=…,encounters_enabled=false`；bot 柵欄逾時 600 秒（＞ 調息 150 秒＋戰鬥 300 秒） |
| 主機 2 | 主機送 `world_id=".."` 的護照能讓客戶端覆寫 `settings.json` | `SaveManager._safe_name` 開頭的點一律換成 `_`；`ClientState` 只存目前世界的護照 |
| 主機 3 | PvP 的 `battle_rest` 把敵方內力（`neili`、`neili_gain`）送給對方 | `BattleSystem._forward` 在 PvP 時逐一收件人剔除敵方玩家單位的私密欄位（`redact_event_for`） |
| 主機 4 | 最後一個真人斷線、當場戰死後，「離開了」送到重生點而不是戰場 | `on_session_removed` 先記住房間，`leave_world(s, room)` 從戰場房間通知 |
| 主機 5 | 驛站馬車沒跑移動鉤子：隊伍面板不更新、通緝犯搭車過城門沒官兵 | `travel` 呼叫 `party.on_moved`、`pk.on_move`；`on_move` 把「兩個不同的城之間」也算進出城 |
| 主機 6 | 未選角的千里傳音能用和角色相同的名字冒充 | 名字加「（未入世）」、事件帶 `unbound: true` |
| 主機 7 | 叫戰／組隊被拒後能立刻連發洗提示 | `pending_retry_cooldown_real_s`（10 真實秒，【設計提案】）；`challenge_cooldown`／`invite_cooldown` |
| 主機 8 | ENet 的封鎖是假的（身分是客戶端自己的 `local_<uuid>`） | `server_options.info.ban_enforced`（只有 Steam 主機為 true）；面板在 false 時不給「踢出並禁止」並說明原因 |
| 介面 1 | 提示框主文在固定寬度裡斷成「…加／入隊伍」 | 主文獨佔一行、不換行（太窄時省略號＋滑鼠提示）；倒數與接受／拒絕在第二行 |
| 介面 2 | 強制 PK 確認框沒有鍵盤預設、「出手」看起來不危險 | 打開時焦點在「取消」；強行出手的「出手」字染紅（`open_confirm(..., danger)`） |
| 介面 3 | 屍體授權列「允許 [名字] [翻動我的屍體]」像另一個動作；擁有者看到「本人和他」 | 「讓這人翻動：[名字] [允許]」；自己的屍體寫「只有你和你允許的人」 |
| 介面 4 | 單獨一顆「拾回」看不出拾什麼 | 「全部拾回」，和「我的屍體（n 件）」放在同一組 |
| 介面 5 | 頻道選單未選的圓點看不見 | 主題給 PopupMenu 金色的 `radio_unchecked`／`radio_checked` 圖示 |
| 介面 6 | 空收件匣兩邊都說「沒有信」 | 空的時候藏起左邊的信件清單欄 |

## 9. M3 小範圍：查看偵察（2026-10-19，擁有者核准；【設計提案・非原作】）

玩法與數值見 GDD 5.10。這裡只記協定與實作形狀（純新增，**RPC 簽名不變 → `Protocol.VERSION` 維持 3**）。

**Intent**

| kind | 參數 | 驗證順序／原因碼 |
|---|---|---|
| `look`（改） | `scout: bool`（可選，新） | 不變。`scout == true` 且房間能偵察（`scout_enabled`、遇敵率 > 0、遇敵表非空）且不在戰鬥中 → 偵察；冷卻中印 `scout_busy`，照樣回成功 |
| `scout_accept`（新） | `offer_id: String` | `no_character` → `in_battle`（IDLE）→ `scout_gone`（沒有提示、id 對不上、換了房間或角色、選項已關）→ `scout_expired` → `scout_dead`（氣 ≤ 0）→ `battles.start(s, 怪物, "ENCOUNTER")` |
| `scout_decline`（新） | `offer_id: String` | 一律成功；id 對得上才清掉提示並印 `scout_declined` |

客戶端只在 `world_info.scout_enabled == true` 時帶 `scout`（舊主機的 `look` 不認得這個參數，會回 `unexpected_arg`）；主畫面自動補畫面的 `look` 不帶。

**事件**

| key | 種類 | payload |
|---|---|---|
| `scout_offer` | ui | `{ offer_id, room, room_name, monsters: [ { id, name, n } ], text: "你發現附近有：野兔 ×2", ttl_s }` |
| `scout_closed` | ui | `{ offer_id, why }`，why ∈ moved／battle／expired／replaced／logout／disabled |
| `scout_found`、`scout_none`、`scout_busy {n}`、`scout_expired`、`scout_declined`、`scout_engage` | 模板 | 見 `data/text_templates.json` |
| `err_scout_gone`、`err_scout_expired`、`err_scout_dead` | 原因碼模板 | |

**主機**：`server/scout_system.gd`（`GameHost.scout`）、`server/intents/intents_scout.gd`。提示存在 `Session.scout_offer`（`{ id, char_id, room, monsters, expires_s }`，不存檔），
`RegionSystem` 走路／瞬移、`BattleSystem._register_player`（開戰、中途加入、重連）、`GameHost.leave_character`（離線、換角）即時收回，`ScoutSystem.tick` 收回過期與選項關閉的提示。
冷卻：`Session.scout_ready_s`（世界時間）與 `scout_ready_ms`（主機真實時鐘）取先到者——視窗模式掉幀時世界時間會落後真實時間，
客戶端照真實時間倒數到 0 就按，主機不能還回「再等 1 秒」。角色表 `cooldowns.scout`（真實秒數）只在能偵察的房間非 0。

**選項**：`scout_enabled`（`server_options.default.json`，預設 true；`AdminSystem.EDITABLE_KEYS`「查看偵察（非原作）」；`--opts=scout_enabled=false`；`world_info.scout_enabled`）。

**介面**：`ui/game/social/scout_dialog.gd`（`ScoutDialog`，玉石框；迎戰 Enter、離開 Esc／⊠，離開送 `scout_decline`；`scout_closed` 或換房間時直接收起），
`CooldownTracker.key_for("look") == "scout"`，熱鍵列／指令窗顯示「查看（5 秒）」。

**測試**：`tests/unit/test_world_scout.gd`（提示生命週期、冷卻與時間倍率、迎戰／離開／過期／換房／開戰／換角失效、隊友拉入、選項關閉、伺服器設定切換）、
`tests/unit/test_ui_scout.gd`（視窗文字、迎戰／離開送出的 intent、Enter、scout_closed／換房關閉、熱鍵列與指令窗倒數）、
`tests/ui/ui_playthrough.gd` 第 15 步（安全的房間按查看只印描述；大理郊外點「查看」→ 視窗 →「離開」；冷卻完按 F3 → 「迎戰」→ 戰鬥畫面打完）。
