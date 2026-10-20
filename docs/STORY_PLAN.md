# 故事包實作計畫：2001 事件劇情、活的江湖、門派故事任務（STORY_PLAN）

> 原作依據：`docs/research/verified_research.md`「故事包研究」章（以下簡稱「研究」）。世界接點以 `docs/WORLD_2001.md` 與 `docs/M3A_PLAN.md` 為底。
> 狀態：契約（2026-10-19，協調者撰寫；擁有者睡覺中、已預先授權，需要擁有者決定的事都先選了預設值，列在 §1.3 與 §11）。

## 0. 文件地位與通則

### 0.1 本文件是契約

故事包由 3 個機制工作包（WP-ENGINE、WP-AMBIENT、WP-UI）與 10 個內容工作包（WP-C-<key>）**同時**實作，之後由 WP-MERGE 單獨合併資料，最後由整合者驗收。實作者之間不溝通。規則沿用 M3A_PLAN 0.1：

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent、事件 key、原因碼、伺服器選項 key、存檔欄位、資料列 id、房間 id、旗標名、碎片檔格式**都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定。
3. 優先順序：本文件 > M3A_PLAN > WORLD_2001 > M2_PLAN > M1_PLAN > GDD > TECH_ARCH。偏差列在 §1.4。
4. 發現缺漏：照「最不意外」實作，程式或碎片裡寫 `# STORY_PLAN 缺漏：……`（碎片寫進 `notes`），交付說明列出；**不要**改別人的檔案。

### 0.2 標記

沿用 GDD 第 0 章與 M3A_PLAN 0.2：【已證實】【後期版】【待考證】【設計提案】【設計提案・非原作】。`era` = 東西在哪個版本存在；`src` = 細節出處（`verified` / `later` / `proposal`）；有研究依據就寫 `src_note`（例：`"研究 尋找虛竹：17173 2001-7-23 n996_912972"`）。
**對白**：研究確認**沒有任何一個事件留下原作逐字對白**。所有對白都是【設計提案】，依研究的官方簡介與攻略改寫；任務列 `dialogue_src: "proposal"`，每個對話樹第一句的 `src_note` 寫依據的簡介原文出處。原作攻略留下的**選項文字**（「幫他」「明白」「太陽月亮..」「剷平他」「有....」）要原樣出現在選項裡（截斷的部分由建造者補完，標【待考證】）。

### 0.3 全域規則

M1_PLAN G1–G10、M2_PLAN H1–H6、M3A_PLAN K1–K6 全部繼續有效（主機權威、離線同一路徑、`core/**` 純邏輯、文字放資料、JSON 數字轉 int、**不 commit**、測完關掉 godot 並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認、新增 `class_name` 後先 `--import`、不新增 Autoload、不改 `project.godot`、不新增 `@rpc` 方法、新系統容錯接線、一個檔案一個擁有者、新內容用前綴）。故事包另加：

| # | 規則 |
|---|---|
| S1 | `Protocol.VERSION` 由 4 升為 **5**（角色表 `quests` 列形狀、view 欄位改變）。 |
| S2 | 新主機系統（`RumorSystem`、`WanderSystem`、`AmbientSystem`）照 K3：`extends RefCounted`、`_init(p_host: GameHost)`、`GameHost` 以路徑 `load()` 建立（`STORY_SYSTEMS` 表），失敗時為 `null`，所有呼叫點用 `host.m2_call(...)` 或先判斷 `!= null`。`QuestSystem` 是既有必載系統，原地升級。 |
| S3 | **任務狀態一律是每個角色自己的**（`ch.quests`），沒有隊伍共用的任務狀態。世界共用的只有：江湖傳聞紀錄、遊蕩惡人的位置、「全服第一個完成」紀錄（`ws.world` 的三個鍵，§4.7）。 |
| S4 | 時間：任務等待與冷卻用**世界時間**（`host.now_s()`；主機離線時凍結，H 規則）；時辰判斷用 `host.clock()`。坐牢、中毒仍照 K4 用 `ch.online_s`。1 遊戲日 = `host.day_s()`。 |
| S5 | 內容只寫在 `docs/story_staging/<key>.json`（碎片），**只有 WP-MERGE 能改 `data/*.json`、`data/maps/*.json`、`data/art.json`**。新資料表 `data/rumors.json`、`data/wanderers.json`、`data/ambient.json`、`data/reactions.json` 也由 WP-MERGE 從碎片建立。 |
| S6 | **一切都要用走的**：每個任務的每一步都必須從兩座出生城走得到（lint 檢查，§8.5）；不得用傳送完成任務步驟（debug `teleport` 只給 bot 回起點）。新房間、新 NPC 只在研究指定的地方、且既有資料沒有可用的地方才加（§2）。 |
| S7 | 新手保護：遊蕩惡人、追擊 NPC 不得對 `combat_xp < server_options.newbie_pk_protect_xp`（預設 500，研究：2001-07-20 實戰 < 500 不被強制 PK）的玩家出手；安全房間（§5.2.3）裡不出手、不移入。 |
| S8 | 舊存檔、舊任務列都要能讀：`quests.json` 舊格式（`steps`）自動正規化成新格式；角色存檔的舊 `quests.active[qid] = {step, counts}`、`quests.done[qid] = int` 自動遷移（§4.12）。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=story]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500
"$G" --headless --path . --script res://tools/net_smoke.gd -- --no-steam
"$G" --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3a_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/story_acceptance.gd -- --no-steam [--chain=q_yuner] [--branch=abao] [--all] [--timeout=3600]
"$G" --headless --path . --script res://tests/ui/ui_playthrough.gd -- --no-steam
"$G" --headless --path . -- --no-steam --offline --world=close_x --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=wm --time-scale=50 --quit-after=300   # 與 --close-mode=quit 各一次
```

---

## 1. 範圍

### 1.1 要做（優先順序；括號是負責 WP）

**P0：2001 事件做成可玩的任務鏈**（有對話、選項、後果）

| 優先 | 任務 id | 名稱 | era | 碎片 | 研究小節 |
|---|---|---|---|---|---|
| P0 | `q_yuner` | 雲兒小姐的煩惱（二選一，兩種結局） | 1.0A（開服） | `ev_yuner` | 雲兒 |
| P0 | `q_xuzhu` | 尋找虛竹（護送、守衛戰可逃） | 1.0A | `ev_xuzhu` | 尋找虛竹 |
| P0 | `q_liu_jinpen` | 劉二爺金盆洗手（上）（時辰限定的莫大） | 1.0A | `ev_liuzhengfeng` | 劉二爺 |
| P0 | `q_liu_jinpen_2` | 劉二爺金盆洗手（下）（密語、魔教伏擊，可逃） | 1.0A（`src: later`） | `ev_liuzhengfeng` | 劉二爺 |
| P0 | `q_xingxia` | 行俠仗義（靈芝商人，可重複） | 1.0A | `ev_xingxia` | 行俠仗義 |
| P0 | `q_wentailai` | 解救文泰來（張豹灌酒、王捕頭情報） | 1.0A | `ev_wentailai` | 文泰來 |
| P0 | `q_lanfeng` | 藍鳳凰採收毒物（五毒各五、瑩月兒支線；恆山分支） | 1.0A | `ev_lanfenghuang` | 藍鳳凰 |
| P0 | `q_guhongzi` | 孤鴻子師伯的死因（峨嵋；家書→大理→明教分舵主） | 1.0A | `ev_guhongzi` | 孤鴻子 |
| P0 | `q_hs_jianqi` + `q_hs_spy` | 劍氣宗之別（只做選擇與旗標）＋ 華山內奸 → 紫霞神功 | 1.0A | `ev_laodenuo` | 華山內奸 |
| P0 | `q_yangkang` | 尋找楊康（全真；西夏皇宮密道） | 1.0A（`src: later`） | `ev_yangkang` | 尋找楊康 |
| P0 | `q_chendabao` | 幫助陳大寶（武當俠義，四戰；之後可重複） | 1.0A | `ev_chendabao` | 陳大寶 |
| P2 | `q_mailu_shangren`、`q_liangfa`、`q_qingwei`、`q_xd_caihua`、`q_qz_paotui`、`q_qz_jiangqingrui`、`q_qz_wangchuyi`、`q_qz_limochou` | 其他有 2001 攻略的事件（研究「Other 2001 events」；`q_qz_limochou` 天龍寺前的李莫愁是第三輪審查補上的，天龍寺 → 洱海岸） | 1.0A | `ev_misc_2001`（`q_qz_limochou` 放在 `sect_stories` 全真章） | Other |

**P1：活的江湖**（WP-AMBIENT 伺服器端、WP-UI 顯示）

1. 【江湖傳聞】廣播：事件預告（還沒人完成時偶爾放風聲）、事件結果、玩家事蹟（名聲里程碑、善惡轉惡、擊敗惡人、全服首位完成、強制 PK 擊殺）。【設計提案・非原作】，伺服器選項開關（§5.1）。
2. 遊蕩惡人：葉二娘、南海鱷神（既有 `EVIL_NPC`）白天照原作站在 `xx_street`（交談即開打；葉二娘只對善惡 > 0），夜裡依排程在西夏附近野外遊蕩並出手（非原作延伸，擁有者要求）；原作 2001-08-30 的「追擊 NPC」（野外惡人頭子）也做（§5.2）。
3. NPC 依時辰的閒聊／環境句（§5.3）。
4. NPC 對善惡／名聲的反應：招呼語（全部 NPC）、價格與拒絕服務（商店、客棧；【設計提案・非原作】，伺服器選項）、原作有的反應（葉二娘、守衛、邪派門下）保持（§5.4）。

**P1：門派故事任務解鎖特殊武功**（`sect_stories` 碎片；鎖住武功的旗標在 `data/martial_arts.json` 已存在，見 §3.5）

| 派 | 任務 id | 名稱 | 解鎖 |
|---|---|---|---|
| 武當 | `q_wd_yinliu` | 殷六俠的迷思 | 旗標 `wd_q_yinliu` + 梯雲縱 1 級 |
| 武當 | `q_wd_heiyu` | 真假黑玉斷續膏之謎 | `wd_q_heiyu`（純陽無極功） |
| 武當 | `q_wd_longmen` | 龍門遺案 | `wd_q_longmen`（真武七截陣；使用陣法仍是 1.0B） |
| 武當 | `q_wd_yitian` | 倚天屠龍筆法（要先完成黑玉） | `wd_q_yitian` |
| 武當 | `q_wd_taiji` | 太極拳與太極劍（俞蓮舟、張松溪考較） | `wd_q_taiji` |
| 峨嵋 | `q_em_shougongsha` | 冰清玉潔守宮砂 | `em_shougongsha`（九陽功） |
| 峨嵋 | `q_em_shandu` | 善妒之女（掌門指環） | `em_miejian_ok`（滅劍） |
| 峨嵋 | `q_em_baifang` | 峨嵋的修練（拜訪名人） | 學點、歷練 |
| 峨嵋 | `q_em_lianhuan` | 連環殺人案（別名替天行道；可重複） | 斷惡熟練 |
| 少林 | `q_sl_riyuebian` | 日月鞭法（玄淨送經） | `sl_riyuebian_ok`（新旗標，§3.5） |
| 星宿 | `q_xh_huagong` | 化功大法（韋小寶的拍馬屁神功） | `xh_huagong_ok`（新武功 `xh_huagong`） |
| 血刀 | `q_xd_xuehai` | 血海魔功的試鍊 | `xd_xuehai_lv1` |
| 靈鷲 | `q_lj_chengqingshuang` | 程清霜的煩惱（戌時） | 千年人參 |
| 古墓 | `q_gm_limochou` | 李莫愁任務（情侶的眼淚） | 毒術、暗器熟練 |
| 恆山 | `q_hg_lincai` | 恆山事件（琳彩學裁縫） | 裁縫熟練 |

### 1.2 不做（之後或永不）

- 1.0B 及之後的內容：京城任務、金輪法王、全真切磋、新版鐵指環（佛光普照掌，2001-12-06）、血魔老祖、陣法的**使用**（真武七截陣只解鎖不開陣）。可以寫成 `era: "1.0B"` 的列，但本包不驗收。
- 師命難違 → 九陰白骨爪（擁有者決定 D9，預設延後）、古墓男性入派路線（研究判定低可信，不做）、獨孤九劍（2001 進洞階段可能根本沒開）、劍宗內容（只做選擇與旗標）。
- 奇遇、奇緣 NPC、英雄帖（2004+ 的系統；2001-10-29 丐幫文另有一句「英雄帖 1 萬」，只有這一句，列在 M3B_PLAN §1.2 M3c）；死亡公告（2004）；夜間商店打烊新規則（1.0B+）。
- **M3b 審查 4 補列（研究【已證實】、1.0B、延後 M3c；詳見 M3B_PLAN §1.2）**：京城半仙消 PK值（2001-11-02）；無敵烙跑鞋、夜明珠（官方 1.0B 新物品）；丐幫跑腿 柯鎮惡 → 郭靖（+5／+20，2001-11-03）、三八紅 → 豬哥義（+8–10 名聲）、武林帖（約每 3 天，2001-12-03）。西夏老人送藥（每天 +1/+1）已併進 `q_sm_dujulaoren`。
- **研究有、但這次刻意不做的 2001 內容**（擁有者決定，第三輪審查列出；不是「待考證」）：
  - 全真教討賊書（2001-9-7 n881_797753：山賊撤出終南山，要先殺頭目）：攻略只有一句，沒有給任務的人、地點、人數、獎勵，「先殺頭目」的規則引擎也沒有 → 延後，等找到更完整的攻略。
  - 峨嵋回部短劍（2001-09-10【已證實】：迴風拂柳劍 45、+75 攻擊、每遊戲日一次）：誰給、怎麼拿沒有記載，而且每天一把 +75 的武器會影響平衡 → 延後（`q_em_shandu` 的結局 src_note 已改標「刻意延後」）。
  - 物色美女、劍宗／劍隱內容（見上）。
  - M3b 審查補列（研究「其他 1.0A 事件」，都只有標題與預告 → 延後）：愛吃熊肉的老祖（第二話，血刀 苦集）、劍隱事件（第四話，華山劍宗）。（好心有好報、狩獵事件、陶耘種稻已由 `q_wd_jiashu`、`q_rabbit`、`q_rice` 做了，不在延後清單。）
  - 第四輪審查補列（研究有記載、本包沒做；都是「只有預告，延後」，不是「待考證」）。**M3b 整合（2026-10-20）：下列六條已由 M3b 做成【設計提案】任務（`q_sm_abao`、`q_sm_yuntie`、`q_sm_zhuadu`、`q_sm_qidu`、`q_sm_chengwei`、`q_sm_lengning`；M3B_PLAN §8.3、O21：咸楓子與楚禮子共用一組毒物點），以下保留當時的延後理由作紀錄：**
    - 路痴的礦工（開服區塊；研究 verified_research「阿寶 is the same 礦工阿寶 of 路痴的礦工」）：只知道標題與阿寶是同一人，沒有步驟與獎勵 → 延後；`q_yuner` 與它無關（研究的擁有者預設）。
    - 運鐵（少林，2001-07-11 預告；研究「少林」目錄列）：只有標題 → 延後。
    - 出外抓毒物（星宿 咸楓子，2001-07-18 區塊；研究「2001-07-18 block blurb」）：只有標題 → 當時延後。（當時寫「研究註明不可與 2001 七毒合併」；**研究已更正**：5 點中 4 點吻合、可以共用，M3b 照 O21 合併。）
    - **七毒（楚禮子，2001-08-18 n862_778664）**：已證實的 2001 任務，七種毒物的出沒座標都有，但攻略沒寫楚禮子在哪、屬哪一派、怎麼接、交什麼、獎勵是什麼；本包只借它的座標給 `q_wd_heiyu` 的七蟲步驟（§7 `sect_stories`）。延後的理由：給予者、交付與獎勵全都要自己編，等於整條【設計提案】，而且七個出沒點在 1.0 地圖上的對應房間要另外判定 → 等找到更完整的攻略再做。
    - 辛勤的程薇（恆山，2001-07-26 預告；研究「恆山」列）：只有標題；`n_hg_chengwei` 已在菜田（17173 門派頁「收成不好」），沒有任務 → 延後。
    - 冷凝劍事件（峨嵋，2001-08-08／08-10 預告；研究「峨嵋 catalog」與「Dated sect quests」）：只有標題；`n_em_jianchi`（劍痴）已在峨嵋山腳，沒有任務 → 延後。
- 不改任何戰鬥公式；新怪物的數值照 `monsters.json` 既有級距。

### 1.3 擁有者決定（預設值已選定；建造者照做，不得自行改）

| # | 決定 | 預設 | 依據 |
|---|---|---|---|
| D1 | 事件日期 | 官方 TW 日期為準，17173 日期記在 `src_note` 當別名 | 研究前言 |
| D2 | 可重複性 | 除了明確寫「每次」「可反覆做」的（行俠仗義、陳大寶完成後），一律**每角色一次**。例外（第三輪審查改寫）：連環殺人案的重複狀態研究寫【待考證】，可重複是**擁有者預設的【設計提案】**（`repeat_src: "proposal"`）；藍鳳凰的可重複只見於台免（後期版），再做照台免給熟練 +50、要基本毒術 < 30（`repeat` 結局，src later），2001 的「升一級」只給第一次 | 研究各節 |
| D3 | 劉二爺（上）給予者 | `n_hn_liugongzi`「劉公子」（2001 攻略的名字，是衡山弟子）；莫大只在**申、酉**時出現 | 2001-08-29 vs 2004 申時 |
| D4 | 劉二爺（下） | 逃跑也算完成、獎勵照給；「太陽月亮」只暗示日月神教；交付句用「魔教的圈套」；不限門派 | 研究 |
| D5 | 雲兒選李台安 | 雲兒給 10 兩，沒有傷藥 | 研究 |
| D6 | 尋找虛竹 | 少林弟子限定；守衛戰逃跑或打贏都算；回信是任務物品；大還丹 1400 兩在西夏藥鋪賣 | 研究 |
| D7 | 藍鳳凰 | 一個任務 `q_lanfeng`；獎勵 基本毒術 +1 級 + 解毒藥 ×1；恆山派改給解毒藥 ×5；善惡 −100、福緣 22、1 遊戲日等待與冷卻都標 `later` | 研究 |
| D8 | 行俠仗義 | 3 靈芝草 + 名聲 5 + 歷練 5；可重複、冷卻 1 遊戲日；拿掉 GDD 的善惡 +20 | 研究 |
| D9 | 九陰白骨爪（師命難違） | 延後，不做 | 研究 |
| D10 | 華山內奸 | 門檻 華心50 讀書30 悟30 儒風30；勞德諾要打贏；物品「氣宗武譜」；保留「衡山左冷蟬」原文 | 研究 |
| D11 | 尋找楊康 | 丘處機給、全真弟子限定；獎勵 歷練 50 學點 10（`later`） | 研究 |
| D12 | 陳大寶 | 武當限定；每戰俠義熟練 +250；完成後可重複（冷卻 1 遊戲日）；可對陳大寶出手（善惡 −50/次） | 研究 + 【設計提案】 |
| D13 | 遊蕩惡人 | 白天照原作定點；**戌～寅時**在附近野外遊蕩（非原作）；追擊戰不能逃；新手、安全房間免疫；出手前 3 秒警告 | 研究 + 擁有者要求 |
| D14 | 系統【江湖傳聞】 | 【設計提案・非原作】，`rumors_enabled` 預設開 | 研究：原作沒有系統謠言 |
| D15 | 價格／拒絕反應 | 【設計提案・非原作】，`npc_reactions` 預設 `"FULL"`（溫和數值，§5.4）；查小鏞、守衛、師父、驛站不受影響 | 擁有者要求 |
| D16 | 新地區 | 開 **衡山**（劉二爺、龍門遺孤）、**雁門關**（靈芝商人、胡斐）兩個小地區；西夏城加民房、衙門、皇宮門口與密道；這些都是走得到的 | 研究 + S6 |
| D17 | 靜觀的稱呼 | 對白用「靜觀師姐」，NPC 名稱 `靜觀師太` 不改（改名留給擁有者） | 研究 |
| D18 | 歷練 | 新增角色欄位 `lilian`（江湖歷練）；原作每個事件獎勵都有它 | 研究 |
| D19 | 隊伍 | KILL／FIGHT 目標：同一場戰鬥裡、目前步驟相同的隊友各自得分；對話、物品交付、選擇都是個人的 | §4.11 |
| D20 | 陳家洛位置 | 維持 `xw_road`（既有），不照 gaoshou/23 的 [267,147] 搬家 | 既有資料 |

### 1.4 與 GDD／既有資料的偏差（整合者同步 GDD §8.2）

| 項目 | GDD／既有 | 本包 |
|---|---|---|
| `q_liu_jinpen` | 給予者【待考證】、【提案】300 兩 + 50 學點 | 劉公子、1000 兩、無學點 |
| `q_guhongzi` | 【提案】200 學點 | 學點 50、名聲 10、歷練 10（`later`） |
| `q_yuner` | 2001-07-18 | 開服（≤ 2001-07-17） |
| `q_xingxia` | 【提案】善惡 +20 | 靈芝草 ×3、名聲 5、歷練 5 |
| `q_hs_spy` | 給予者岳不群、【提案】儒風熟練 | 起點勞德諾（西夏客棧），獎勵紫霞神功解鎖 |
| `q_lanfeng2` | 獨立任務 | 併入 `q_lanfeng` 的獎勵分支 |
| 替天行道 | 研究舊註「fan-only」 | 2001-09 已有；做成 `q_em_lianhuan` |
| 化功大法 | 【待考證】 | 2001-08-25 已證實；新增 `xh_huagong` |
| 任務資料模型（GDD §8.3） | `steps[]` | `stages[]` + 對話樹（§4.2）；舊格式仍可讀 |

---

## 2. 世界接點（新房間與新地區；全部由 `_world` 碎片建立）

### 2.1 新地區

| 地區 id | 名稱 | type | `world_pos` | `pk_allowed` | 前綴 | 依據 |
|---|---|---|---|---|---|---|
| `hengshan_s_road` | 衡陽古道 | WILD | [900, 520] | true | `hn_` | 【設計提案】連接武當山下與衡山 |
| `hengshan_s` | 衡山 | WILD | [943, 678] | true | `hn_` | WORLD_2001 §1.1 衡山 22640,16268 |
| `yanmen` | 雁門關 | WILD | [837, 96] | true | `ym_` | 靈芝商人 20078,2310 |

> 注意：`hengshan`（`hg_`）是北嶽**恆山**派；南嶽**衡山**一律用 `hengshan_s`／`hn_`，文字裡寫「衡山」，不得混用。

### 2.2 新房間（id 綁定；desc 由 `_world` 碎片寫，1–2 句）

| 房間 id | 名稱 | 地區 | 出口（新增，雙向） | 遇敵 | 放誰 |
|---|---|---|---|---|---|
| `xx_minfang` | 民房 | xixia | `xx_gate_e` S ↔ N | 無 | 雲兒 |
| `xx_yamen` | 西夏衙門 | xixia | `xx_square` NW ↔ SE | 無 | 張豹、虛竹、公告欄（features） |
| `xx_palace` | 皇宮門口 | xixia | `xx_street` NW ↔ SE | 無 | 左守衛、右守衛、阿大 |
| `xx_palace_mishi` | 皇宮密道 | xixia | `xx_palace` N ↔ S；`requires: [{"type":"quest_active","quest":"q_yangkang"}]`（之後別的任務要用時改成 `any_of` 的 `options`） | 無 | 楊康（`appear` 限 q_yangkang 進行中） |
| `sl_leftroom` | 山門左廂房 | shaolin | `sl_court` NW ↔ SE | 無 | 道品 |
| `hs_siguoya` | 思過崖破劍洞 | huashan | `hs_hall` N ↔ S | 無 | 成不憂 |
| `dlw_desertcave` | 大理西沙漠洞窟 | dali_wild | `dlw_lake` W ↔ E | 0.10：m_wolf 60、m_bandit 40（洞內） | 詭異的人（明教分舵主） |
| `rr_eastbank` | 雪山東岸 | river_road | `rr_bend` E ↔ W | 0.08：m_rabbit 70、m_bigrabbit 30 | 藍鳳凰 |
| `hn_road1` | 衡陽古道 | hengshan_s_road | `wd_road1` SE ↔ NW | 0.10：m_bigrabbit 60、m_wolf 30、m_boar 10 | — |
| `hn_road2` | 湘江渡口 | hengshan_s_road | `hn_road1` S ↔ N | 0.10：同上 | — |
| `hn_foot` | 衡山下 | hengshan_s | `hn_road2` S ↔ N | 0.08：m_rabbit 60、m_bigrabbit 40 | 劉公子（池塘邊）、衡山弟子 |
| `hn_teahouse` | 衡山小茶店 | hengshan_s | `hn_foot` E ↔ W | 無（休息點，INN） | 茶店老闆（INN）、龍門遺孤、秘密客（`appear`） |
| `hn_shore` | 上山路口海邊 | hengshan_s | `hn_foot` NE ↔ SW | 0.08：m_rabbit 100 | 莫大（`appear` 申、酉） |
| `hn_bridge` | 小島石橋 | hengshan_s | `hn_foot` SE ↔ NW | 0.05：m_rabbit 100 | — |
| `hn_island` | 衡山下方小島 | hengshan_s | `hn_bridge` S ↔ N | 無 | 魯連榮 |
| `ym_road` | 雁門古道 | yanmen | `hf_fork` NE ↔ SW | 0.10：m_bigrabbit 60、m_wolf 35、m_bandit 5 | — |
| `ym_gate` | 雁門關口 | yanmen | `ym_road` N ↔ S | 0.05：m_rabbit 100 | 靈芝商人 |
| `ym_bridge` | 關外橋邊 | yanmen | `ym_gate` SE ↔ NW | 0.10：m_wolf 50、m_bandit 50 | 強盜（`fight`，只在 q_xingxia 目前步驟時可打） |
| `ym_inner` | 雁門關內 | yanmen | `ym_gate` N ↔ S | 無 | 胡斐 |

`exit_patches` 同時更新被接的既有房間 desc（提到新出口）：`xx_gate_e`、`xx_square`、`xx_street`、`sl_court`、`hs_hall`、`dlw_lake`、`rr_bend`、`wd_road1`、`hf_fork`（原 desc「往北通往恆山派和雁門關，官兵設卡」改成雁門關往東北已通）。`hf_teahouse` 的 talk 模板、`n_jc_guard` 的 talk 模板中「雁門關路封著」的字句也要改（`_world` 碎片寫 `text_templates` 覆寫）。

### 2.3 新手安全（K6 延伸；lint 檢查）

- 休息點：`hn_teahouse`（INN），既有 `hf_teahouse`、`em_teahouse`、`de_oasis`。
- `wd_road1 → hn_teahouse`：4 步，難纏怪期望 ≤ 0.15、山豬 ≤ 0.10、山賊 0（WORLD_2001 §1.4 規則 2）。
- `hf_teahouse → ym_gate`：4 步，同上；`ym_bridge`、`dlw_desertcave` 是任務戰鬥點，不在必經路線，不受規則 2 限制但要遵守規則 6（rate ≤ 0.15）。
- 緊鄰休息點的房間只放野兔、大野兔（`hn_foot`、`ym_gate` 符合）。
- `tools/balance_sim.gd` 走路案例新增 `p0_walk_hengshan_s`（大理廣場 → 衡山小茶店）、`p0_walk_yanmen`（西夏廣場 → 雁門關口），存活率 ≥ 90%（WP-MERGE 跑；balance_sim 歸 WP-MERGE 於本包）。

---

## 3. 固定 id（綁定）

### 3.1 任務

見 §1.1 兩張表。另：`q_chendabao` 是**一條**任務、四個戰鬥階段（不是四條）。P2 的 `ev_misc_2001` 任務 id 也以 §1.1 為準。

### 3.2 NPC（擁有者 = 建立這列的碎片；其他碎片只能用 `npc_links` 掛任務，§7.1）

| NPC id | 名稱 | 房間 | kind | 擁有碎片 | 用到的碎片 |
|---|---|---|---|---|---|
| `n_xx_yuner` | 雲兒 | `xx_minfang` | STORY | `ev_yuner` | `ev_guhongzi` |
| `n_xx_litaian` | 李台安 | `xx_pharmacy` | STORY | `ev_yuner` | — |
| `n_xx_abao` | 礦工阿寶 | `xn_slope` | STORY | `ev_yuner` | — |
| `n_xx_xuzhu` | 虛竹 | `xx_yamen` | STORY | `ev_xuzhu` | `sect_stories`（拜訪名人） |
| `n_xx_palace_guard_l` | 皇宮左守衛 | `xx_palace` | STORY | `ev_xuzhu` | — |
| `n_xx_palace_guard_r` | 皇宮右守衛 | `xx_palace` | STORY | `ev_xuzhu` | — |
| `n_xx_ada` | 阿大 | `xx_palace` | EVIL_NPC | `ev_xuzhu` | `sect_stories`（黑玉） |
| `n_sl_daopin` | 道品 | `sl_leftroom` | STORY | `ev_xuzhu` | — |
| `n_xx_zhangbao` | 張豹 | `xx_yamen` | STORY（`appear`：子時以外） | `ev_wentailai` | — |
| `n_dl_wangbutou` | 王捕頭 | `dl_yamen` | STORY | `ev_wentailai` | — |
| `n_chenjialuo` | 陳家洛 | `xw_road` | 既有 | 既有 | `ev_wentailai` |
| `n_hn_liugongzi` | 劉公子 | `hn_foot` | QUEST | `ev_liuzhengfeng` | — |
| `n_hn_dizi` | 衡山弟子 | `hn_foot` | STORY | `ev_liuzhengfeng` | — |
| `n_hn_teaman` | 茶店老闆 | `hn_teahouse` | FUNC（INN） | `_world` | — |
| `n_hn_moda` | 莫大先生 | `hn_shore` | STORY（`appear` 申、酉） | `ev_liuzhengfeng` | — |
| `n_hn_lulianrong` | 魯連榮 | `hn_island` | STORY | `ev_liuzhengfeng` | — |
| `n_hn_mimike` | 秘密客 | `hn_teahouse` | STORY（`appear` 見 §4.6） | `ev_liuzhengfeng` | — |
| `n_hn_longmen` | 龍門遺孤 | `hn_teahouse` | STORY | `sect_stories` | — |
| `n_em_jingguan` | 靜觀師太 | 既有 | 既有 | 既有 | `ev_guhongzi`、`sect_stories` |
| `n_dl_cunmin` | 大理村民 | `dl_square` | STORY | `ev_guhongzi` | — |
| `n_dlw_guiyi` | 詭異的人 | `dlw_desertcave` | STORY | `ev_guhongzi` | — |
| `n_lf_lanfenghuang` | 藍鳳凰 | `rr_eastbank` | QUEST | `ev_lanfenghuang` | — |
| `n_hs_lanyihan` | 藍依涵 | `hs_square` | STORY | `ev_lanfenghuang` | — |
| `n_em_yingyueer` | 瑩月兒 | 既有 `em_teahouse` | 既有（talk 模板由 `ev_lanfenghuang` 覆寫） | 既有 | `ev_lanfenghuang`、`ev_misc_2001`（梁發） |
| `n_ym_lingzhi` | 靈芝商人 | `ym_gate` | QUEST | `ev_xingxia` | — |
| `n_ym_qiangdao` | 強盜 | `ym_bridge` | EVIL_NPC | `ev_xingxia` | — |
| `n_ym_hufei` | 胡斐 | `ym_inner` | STORY | `sect_stories` | — |
| `n_xx_laodenuo` | 勞德諾 | `xx_inn` | STORY | `ev_laodenuo` | — |
| `n_hs_linghuchong` | 令狐沖 | `hy_pond` | STORY（`appear` 巳午未） | `ev_laodenuo` | — |
| `n_hs_chengbuyou` | 成不憂 | `hs_siguoya` | STORY | `ev_laodenuo` | — |
| `n_qz_yangkang` | 楊康 | `xx_palace_mishi` | STORY | `ev_yangkang` | — |
| `n_qz_chendabao` | 陳大寶 | 既有 `zn_river` | 既有 | 既有 | `ev_chendabao` |
| `n_xx_qiaofeng` | 喬峰 | `xx_inn` | STORY | `sect_stories` | — |
| `n_xx_azi` | 阿紫 | `xx_inn` | STORY | `sect_stories` | — |
| `n_dl_limochou` | 李莫愁 | `dlw_lake` | EVIL_NPC | `sect_stories` | `ev_misc_2001` |

既有 NPC 一律沿用（`n_weixiaobao`、`n_shuanger`、`n_zhangwuji`、`n_em_jixiaofu`、`n_em_dingminjun`、`n_em_miejue`、`n_em_jingzhao`、`n_wd_*`、`n_xh_dingchunqiu`、`n_xd_laozu`、`n_lj_chengqingshuang`、`n_qz_qiuchuji`、`n_yuebuqun`、`n_liangfa`、`n_yeerniang`、`n_nanhai`）。

### 3.3 物品（前綴依碎片；`items.json` 形狀）

| id | 名稱 | 碎片 | 備註 |
|---|---|---|---|
| `i_hn_wulintie` | 武林帖 | ev_liuzhengfeng | 任務物品 |
| `c_dahuandan` | 大還丹 | ev_xuzhu | 精氣神各回 300，`price` 1400，加到 `n_xx_pharmacist` 商店 |
| `i_xz_huixin` | 虛竹的回信 | ev_xuzhu | 任務物品 |
| `i_gh_jiashu` / `i_gh_yunerxin` | 靜觀的家書／雲兒的信 | ev_guhongzi | 任務物品 |
| `c_niuroubing` | 牛肉餅 | ev_guhongzi | 食物（既有 `c_mantou` 級距） |
| `r_lf_wugong` `r_lf_qingshe` `r_lf_xiezi` `r_lf_zhizhu` `r_lf_chanchu` | 蜈蚣／青蛇／蝎子／蜘蛛／蟾蜍 | ev_lanfenghuang | 任務素材，「其他」欄 |
| `r_lf_mabu` | 麻布 | ev_lanfenghuang | 任務物品 |
| `r_kuang_zi` / `r_kuang_lv` | 紫石礦／綠石礦 | ev_yuner | 素材 |
| `i_ym_baohe` | 寶盒 | ev_xingxia | 任務物品 |
| `c_lingzhicao` | 靈芝草 | ev_xingxia | 回氣藥【設計提案】（效果研究查無） |
| `c_baijiu` `c_yangrujiu` `c_zhuyeqing` | 白酒／羊乳酒／竹葉青 | ev_wentailai | 加到 `n_xx_innkeeper` 商店；「客棧的每種酒」= 這三種 |
| `i_wtl_gongwen` | 公文手抄本 | ev_wentailai | 任務物品（`later`） |
| `i_hs_mihan` `i_hs_zhuijiling` `i_hs_qizongwupu` | 華山密函／追擊令／氣宗武譜 | ev_laodenuo | 任務物品 |
| `i_qz_shouyu` `i_qz_guojing_bishou` | 丘處機手諭／郭靖匕首 | ev_yangkang | 任務物品 |
| `i_cdb_taofaling` `i_cdb_lingpai` | 討伐令／青雪寨令牌 | ev_chendabao | 任務物品 |

`sect_stories` 自行以派前綴命名物品（例：`i_wd_jixiaofu_xin`、`i_em_zhangmen_zhihuan`、`r_lj_qiannian_renshen`、`i_gm_qinglv_lei`）。

### 3.4 怪物（`monsters.json` 形狀；`sect` 欄不填）

| id | 名稱 | 碎片 | 級距（`combat_xp_ref`） |
|---|---|---|---|
| `m_xx_palace_guard` | 西夏皇宮守衛 | ev_xuzhu | 60000（打不贏，設計上逃） |
| `m_hn_mojiao` | 魔教教徒 | ev_liuzhengfeng | 8000（6 隻同場；可逃） |
| `m_dl_mingjiao` | 明教分舵主 | ev_guhongzi | 6000（研究：門檻實戰 1000） |
| `m_lf_wugong` / `m_lf_zhizhu` | 蜈蚣／毒蜘蛛 | ev_lanfenghuang | 400 / 600（既有 `m_xh_snake`、`m_xh_scorpion` 用於青蛇、蝎子） |
| `m_ym_qiangdao` | 強盜 | ev_xingxia | 3000 |
| `m_xx_laodenuo` | 勞德諾 | ev_laodenuo | 30000 |
| `m_qz_yangkang` | 楊康 | ev_yangkang | 40000 |
| `m_cdb_zeitou` `m_cdb_louluo` `m_cdb_xiongbatian` `m_cdb_duyanren` `m_cdb_chendabao` | 賊頭／小嘍囉／熊霸天／獨眼仁／陳大寶 | ev_chendabao | 2500 / 2000 / 8000 / 12000 / 300 |
| `m_nanhai` / `m_yeerniang` | 南海鱷神／葉二娘 | `_ambient` | 80000 / 70000（原作「超強」） |
| `m_amb_etou` | 惡人頭子 | `_ambient` | 15000（追擊 NPC） |

所有掉落任務物品的怪物 `drops` 必須 100%（`chance: 100`）且只在目標進行中掉（`drops[].requires: [{"type":"quest_stage", ...}]`，新欄位，§4.6）。

### 3.5 旗標與武功

- 既有（`martial_arts.json` 已用來鎖武功，名稱不得改）：`wd_q_yinliu`、`wd_q_heiyu`、`wd_q_longmen`、`wd_q_yitian`、`wd_q_taiji`、`em_shougongsha`、`em_miejian_ok`、`em_juejian_ok`、`em_foguang_ok`、`xd_xuehai_lv1`、`lj_bahuang_learned`。
- 新增：`hs_qizong`、`hs_jianzong`（劍氣宗選擇，互斥）、`hs_zixia_ok`、`xh_huagong_ok`、`sl_riyuebian_ok`。
- 新武功（`sect_stories` 寫 `xh_huagong`，`ev_laodenuo` 寫 `hs_zixia`）：`tier: "QUEST"`，`requires` 含上面的旗標；形狀照 `martial_arts.json` 既有 QUEST 列。`sl_riyuebian` 已存在（ADVANCED），`sect_stories` 用 `art_patches` 只追加 `{"type":"quest_flag","flag":"sl_riyuebian_ok"}` 條件。
- 旗標只由任務的 `flag` 動作設定（§4.4）；任務自己的中間狀態放在任務的 `vars`，**不得**用角色旗標。

---

## 4. 任務引擎（WP-ENGINE）

### 4.1 現況與缺口

`server/quest_system.gd`（253 行）＋ `data/quests.json`（15 列）現在只支援：線性 `steps[]`、步驟型別 TALK／DELIVER／KILL／REACH、`requires`、`give_items`、`repeatable`（無冷卻）、獎勵（銀兩、實戰、學點、名聲、善惡、物品、旗標、技能熟練）。故事包需要的缺口：

| 缺口 | 現況 | 本包 |
|---|---|---|
| 對話樹與選項 | 只有一句 `talk_<npc>` 模板 + 服務選單 | 每個任務有 `dialogues`，節點有說話者、文字、選項（可上鎖）、動作、跳轉（§4.5） |
| 分支旗標、結局 | 無 | 任務區域變數 `vars`、`outcomes`、`next` 條件跳轉、結局記錄（§4.2） |
| 每角色故事狀態 | `active {step, counts}`、`done {qid: int}` | `active {stage, objs, vars, since…, escort}`、`done {n, outcome, world_s}`、`cd`（§4.7） |
| 時間／世界狀態觸發 | `hour_in` 只用在接任務 | 目標與 NPC 的 `hours`、`WAIT`、`STATE`、NPC `appear`（§4.8） |
| 物品交付 | DELIVER（只能最後交） | DELIVER／COLLECT／動作 `give`／`take` 任一步驟 |
| 護送、戰鬥步驟 | 只有 KILL 計數 | `ESCORT`、`FIGHT`（勝／逃／任意，可不能逃、波次、單人），房間動作（§4.3） |
| 跨 NPC 步驟 | 只限 TALK／DELIVER 的目標 NPC | 任何階段的任何目標都能指定 NPC；NPC 選單自動出現「進行中的任務」項 |
| 獎勵型別 | 無歷練、無武功解鎖、無依結局給獎 | `lilian`、`killing_intent`、`learn`（直接學到某級）、`skill_prof`、`flags`、`rumor`；`outcomes` 各自的獎勵（§4.9） |
| 重複與冷卻 | `repeatable` 布林 | `repeat: { "max": n|0, "cooldown_days": f }`（§4.10） |
| 多人規則 | 只有最後一擊者計 KILL | 同場隊友依目標設定各自計分；個人狀態；主機權威（§4.11） |
| 存檔中途重載 | 狀態存了，但沒有護送、對話游標 | 護送、變數全進存檔；對話游標不存，下次交談從階段的 `resume` 節點開始（§4.7） |

### 4.2 `quests.json` 第 2 版列格式（綁定）

```json
{ "id": "q_yuner", "name": "雲兒小姐的煩惱", "chapter": "西夏・開服事件", "group": "ev_yuner",
  "giver": "n_xx_yuner", "era": "1.0A", "src": "verified", "dialogue_src": "proposal",
  "src_note": "研究 雲兒：17173 2001-7-17 n431_348015、2001-7-23 n274_190972",
  "text": "西夏城裡民房中的雲兒小姐，為了要嫁給藥局的李台安還是青梅竹馬的阿寶而煩惱。",
  "requires": [], "give_items": [],
  "repeat": { "max": 1, "cooldown_days": 0 },
  "abandon": true, "party_credit": true,
  "start": "s_ask",
  "offer": "d_offer",
  "stages": [
    { "id": "s_ask", "title": "雲兒的心事", "log": "雲兒要你先去看看李台安是個怎樣的人。",
      "objectives": [ { "id": "o_li", "type": "TALK", "npc": "n_xx_litaian", "dialogue": "d_li", "text": "到藥鋪找李台安" } ],
      "next": "s_abao" },
    { "id": "s_abao", "title": "城外的阿寶", "log": "再去西夏城外的礦場看看阿寶。",
      "objectives": [ { "id": "o_abao", "type": "TALK", "npc": "n_xx_abao", "dialogue": "d_abao_1", "text": "到城北山坡找礦工阿寶" } ],
      "next": "s_choose" },
    { "id": "s_choose", "title": "替雲兒拿主意", "log": "回民房，替雲兒做個決定。",
      "objectives": [ { "id": "o_choose", "type": "TALK", "npc": "n_xx_yuner", "dialogue": "d_choose", "text": "回去告訴雲兒你的看法" } ],
      "next": [ { "if": [ { "type": "quest_var", "quest": "q_yuner", "var": "pick", "value": "abao" } ], "goto": "s_thanks" },
                { "goto": "END:li" } ] },
    { "id": "s_thanks", "title": "阿寶的謝禮", "log": "雲兒選了阿寶。回去告訴他這個好消息。",
      "objectives": [ { "id": "o_thanks", "type": "TALK", "npc": "n_xx_abao", "dialogue": "d_abao_2", "text": "回城北找阿寶" } ],
      "next": "END:abao" }
  ],
  "dialogues": {
    "d_offer":  { "start": "n0", "nodes": {
        "n0": { "speaker": "npc", "text": "唉……一個是藥局的李台安，一個是從小一起長大的阿寶，我到底該嫁給誰才好？",
                "choices": [ { "id": "c_help", "label": "我替妳去看看他們兩個。", "do": [ { "do": "accept" } ], "goto": "END" },
                             { "id": "c_no", "label": "這種事我可幫不上忙。", "goto": "END" } ] } } },
    "d_choose": { "start": "n0", "resume": "n0", "nodes": {
        "n0": { "speaker": "npc", "text": "你都見過他們了？你說，我該選誰？",
                "choices": [
                  { "id": "c_abao", "label": "阿寶對妳一片真心。", "do": [ { "do": "var", "name": "pick", "value": "abao" }, { "do": "complete", "obj": "o_choose" } ], "goto": "n_abao" },
                  { "id": "c_li", "label": "李台安有份正當差事。", "do": [ { "do": "var", "name": "pick", "value": "li" }, { "do": "complete", "obj": "o_choose" } ], "goto": "n_li" } ] },
        "n_abao": { "speaker": "npc", "text": "嗯……我也是這麼想的。麻煩你去跟阿寶說一聲。", "goto": "END" },
        "n_li": { "speaker": "npc", "text": "那就這麼定了。這點小錢你收下吧。", "goto": "END" } } }
  },
  "outcomes": {
    "abao": { "label": "雲兒嫁給了阿寶", "rewards": { "items": [ { "id": "r_kuang_zi", "n": 3 }, { "id": "r_kuang_lv", "n": 3 } ] },
              "src_note": "2001-07-17、07-23 兩篇一致" },
    "li": { "label": "雲兒嫁給了李台安", "rewards": { "money": 10 }, "src": "later", "src_note": "2001-07-17「只有10元」；給錢的人【設計提案】" }
  },
  "rumors": { "first": "rmr_q_yuner_first" }
}
```

欄位規則：

1. `stages` 與舊的 `steps` 互斥；兩者都沒有 → lint 錯誤。`start` 是第一個階段 id。
2. `offer`（選填）：NPC 選單點「可接」的任務時，先開這段對話；對話裡的 `accept` 動作才真的接。沒有 `offer` → 點了直接接（舊行為）。
3. 階段：`objectives` 全部完成（或 `"any": true` 時任一完成）→ 執行 `on_complete` 動作 → 依 `next` 前進。`next` 是字串（階段 id 或 `END:<outcome>`）或 `[{ "if": [條件…], "goto": … }, …, { "goto": … }]`（依序取第一個成立的；最後一項必須無條件）。`END` 單獨寫等於 `END:default`。
4. 階段可有 `on_enter`（進入時動作）、`room_actions`（§4.3）、`hint_room`（任務窗與地圖標記用，選填）、`fail_if`（條件成立即失敗，例：護送目標走散）。
5. `outcomes`：每個 `END:<x>` 都要有對應的 `outcomes.<x>`（可只有 `label`）。`rewards` 形狀見 §4.9。
6. `rumors`：`{ "first": 模板 id, "each": 模板 id, "foreshadow": 模板 id }`（全選填，§5.1）。
7. 文字直接寫在任務列（繁體；可用 `{name}` 玩家名、`{npc_name}`）；系統訊息、傳聞、閒聊用 `text_templates`。
8. `chapter`：任務窗分章（例：「西夏・開服事件」「衡山・劉二爺金盆洗手」「峨嵋派」）。

### 4.3 目標型別（`objectives[].type`）

| type | 欄位 | 完成條件 |
|---|---|---|
| `TALK` | `npc`、`dialogue`（選填）、`hours`（選填） | 有 `dialogue`：對話中執行 `{"do":"complete","obj":…}`；沒有：點選單上這個任務項即完成 |
| `DELIVER` | `npc`、`item`、`count`、`consume`（預設 true）、`dialogue`（選填） | 對該 NPC 交付且背包數量夠；扣物品 |
| `COLLECT` | `item`、`count` | 背包數量 ≥ count（隨物品增減即時重算；不扣） |
| `KILL` | `monster`、`count`、`regions`（選填） | 擊殺計數（§4.11 隊伍規則） |
| `FIGHT` | `id` 對應的戰鬥由動作 `fight` 開打；`win`：`"WIN"`／`"WIN_OR_FLEE"`／`"ANY"` | 戰鬥結束時本人結果符合 `win` |
| `REACH` | `room` | 進入該房間（含搭車、被引路） |
| `BUY` | `item`、`count`、`npc`（選填） | 本階段開始後才買的數量（研究：張豹「之前買的不算」） |
| `WAIT` | `days`（遊戲日，可小數）或 `hours`（時辰陣列） | 階段開始後經過 `days`；或目前時辰在 `hours` 內 |
| `STATE` | `requires`（條件陣列） | 條件全部成立（每次角色表推送、每個時辰、每次技能升級時檢查） |
| `ESCORT` | `npc`、`to_room` | 帶著護送 NPC 進入 `to_room`；護送 NPC 由動作 `escort_start` 產生 |

**房間動作**（階段的 `room_actions`）：`[{ "id": "a_wugong", "room": "rr_upper", "label": "捕捉蜈蚣", "hours": [], "requires": [], "repeat": true, "do": [ { "do": "fight", "monsters": ["m_lf_wugong"], "obj": "" } ] }]`。玩家在該房間、階段進行中、條件成立時，場景卷軸多一個按鈕（view `story_actions`）；按下送 `story_act`。`repeat: false` 用過一次就消失（存在 `vars`）。

### 4.4 動作（`do` 陣列；對話選項、節點、`on_enter`、`on_complete`、房間動作共用）

| `do` | 欄位 | 效果 |
|---|---|---|
| `accept` | — | 接下本任務（只在 `offer` 對話有效） |
| `complete` | `obj` | 完成目前階段的某個目標 |
| `var` | `name`、`value`（字串／整數／布林） | 設任務區域變數 |
| `goto` | `stage` | 直接跳到某階段（略過 `next`） |
| `finish` | `outcome` | 立刻結束任務並給該結局獎勵 |
| `fail` | `reason`（模板 id） | 任務失敗：移除、收回 `give_items`、記 `done[qid].failed += 1`；可再接（受冷卻） |
| `give` / `take` | `item`、`n` | 給／收物品（`take` 數量不夠 → 這個選項整個不執行，回 `quest_incomplete`） |
| `reward` | 獎勵字典（§4.9） | 立即給獎（例：瑩月兒的名聲 5 歷練 15） |
| `flag` / `unflag` | `flag` | 設／清角色旗標（只限 §3.5 的旗標與 `<前綴>_` 開頭的新旗標） |
| `learn` | `skill`、`level` | 直接把武功學到該級（已高於則不變；受 `skill_cap`） |
| `fight` | `monsters`、`waves`（選填）、`no_flee`、`solo`、`obj`（對應的 FIGHT 目標 id，選填）、`npc`（顯示名來源） | 開戰（`BattleSystem.start_ex`，kind `"QUEST"`）；`solo: true` 不拉隊友 |
| `escort_start` / `escort_end` | `npc` | 護送 NPC 跟隨／離開 |
| `tell` | `key`（模板 id） | 對本人送一則系統訊息 |
| `rumor` | `key`、`scope`（`WORLD`／`REGION`） | 交給 RumorSystem（null 時略過） |
| `close` | — | 關閉對話 |

### 4.5 對話樹（`dialogues.<id>`）

- `start`（必填）、`resume`（選填；重開對話時從這裡開始，預設 = `start`）、`nodes`。
- 節點：`speaker`（`"npc"` = 正在交談的 NPC、`"player"`、或某個 NPC id）、`text`、`do`（進入節點時執行）、`choices` 或 `goto`（兩者擇一；都沒有 = 結束）。
- 選項：`id`、`label`、`requires`（不成立時顯示為灰色並附原因，或 `hide_if_locked: true` 時不顯示）、`do`、`goto`（節點 id 或 `END`）。
- 對話游標存在 `Session.dialogue = { npc, quest, dlg, node }`；移動、開戰、斷線、`dialogue_close` 時清除；`dialogue_choose` 必須帶與游標一致的 `npc`、`quest`、`node`，否則回 `dialogue_stale`。
- 不屬於任何任務的閒聊仍用 `talk_<npc>` 模板（§5.3 依時辰換句）。

### 4.6 新條件型別（`core/character/requirements.gd`、`core/data/data_schema.gd`）

| type | 欄位 | 成立 |
|---|---|---|
| `quest_active` | `quest` | 任務進行中 |
| `quest_stage` | `quest`、`stage`（字串或陣列） | 進行中且在該階段 |
| `quest_var` | `quest`、`var`、`value` | 任務區域變數等於 value |
| `quest_outcome` | `quest`、`outcome` | 完成過且最後結局是 outcome |
| `lilian_min` | `value` | 江湖歷練 ≥ value |
| `fame_min` | `value` | 名聲 ≥ value |
| `combat_xp_max` | `value` | 實戰 ≤ value |

既有 `has_item`（`item`、`n`）、`any_of`（`options`）、`hour_in`、`quest_flag`、`quest_done`、`skill_min`、`attr_min`、`sect`、`morality_min/max` 照用。

**NPC `appear`**（新欄位，`npcs.json`）：`{ "hours": ["申","酉"], "requires": [條件…] }`。不成立時該 NPC 對這位玩家**不出現在 view**、不能交談（`npc_here` 回 `not_here`）。用途：莫大（申酉）、令狐沖（巳午未）、張豹（子時以外）、秘密客（`[{"type":"quest_stage","quest":"q_liu_jinpen_2","stage":["s_mimike","s_fight"]}]`）、楊康（`quest_active q_yangkang`）。

**怪物 `drops[].requires`**（新欄位）：條件成立才掉；任務素材一律這樣寫。

### 4.7 每角色故事狀態與存檔（`core/character/character.gd`）

```text
ch.quests = {
  "active": { qid: { "v": 2, "stage": "s_abao", "objs": { "o_abao": 1 }, "vars": { "pick": "abao" },
                     "since_world_s": 1234.0, "stage_since_world_s": 2345.0, "escort": "" } },
  "done":   { qid: { "n": 1, "outcome": "abao", "world_s": 3456.0, "failed": 0 } },
  "cd":     { qid: 9999.0 }          # 世界時間到了才能再接
}
ch.lilian = 0                         # 江湖歷練（新，int，存檔鍵 "lilian"）
ch.ext = {}                           # 各系統私用的持久資料：{ "ambient": {...}, "wander": {...} }（鍵 = 系統名）
```

世界共用（`ws.world`，隨 world.json 存檔）：`"rumors"`（最近 50 則，RumorSystem 擁有）、`"wanderers"`（WanderSystem 擁有）、`"quest_firsts"`（`{ qid: 角色名 }`，QuestSystem 擁有）。

存檔中途重載：上面的狀態全進角色檔；對話游標與遊蕩惡人的警告倒數**不存**（重連後重新交談即可；倒數取消）。護送：`active.escort` 有值 → 重載後 NPC 仍跟著玩家。

### 4.8 觸發

- **時辰**：`GameHost._minute_jobs` 每換時辰呼叫 `quests.on_clock(s)`（WAIT、STATE、`appear` 變化 → `push_view`）。
- **移動**：`on_reach(s)`（既有）＋ 房間動作重算。
- **物品**：`host.item_gain_event` / `item_lost_event` 之後呼叫 `quests.on_items(s)`（COLLECT）。
- **商店**：`NpcSystem.buy` 成功後 `quests.on_buy(s, npc_id, item_id, n)`。
- **戰鬥**：`BattleSystem._settle_player` 在既有 `on_kills` 之後呼叫 `quests.on_battle_settled(s, summary)`；`summary` 增加 `quest_tag`（開戰動作帶的 `{quest, obj}`）與 `per`（VICTORY／FLED／DEFEAT）。
- **技能／屬性變化**：`push_sheet` 時呼叫 `quests.on_sheet(s)`（STATE；節流：同一角色每秒最多一次）。
- **登入**：`quests.on_login(s)`（舊狀態遷移、護送恢復、`appear` 重算）。

### 4.9 獎勵（`outcomes.<x>.rewards`、動作 `reward`）

既有欄位全保留（`money`、`combat_xp`、`learn_points`、`fame`、`morality`、`items`、`flags`、`skill_prof`），新增：`lilian`（int）、`killing_intent`（int）、`learn`（`{ skill_id: level }`）、`rumor`（模板 id）。`Character.apply_rewards` 回傳值加 `lilian`；`E_REWARD` 事件 payload 加 `lilian`。

**分支型獎勵**（藍鳳凰的恆山派、劉二爺）用 `next` 條件導到不同結局，不要在獎勵裡寫條件。

### 4.10 重複與冷卻

`repeat: { "max": 0 = 無限 | n, "cooldown_days": f }`。完成時 `cd[qid] = now_s + cooldown_days × day_s`；`max` 達到 → 選單狀態 `DONE`。舊欄位 `repeatable: true` 正規化成 `{max: 0, cooldown_days: 0}`、`false` → `{max: 1}`。選單狀態增加 `COOLDOWN`（附剩餘遊戲時間）。

### 4.11 多人規則

1. 主機權威；客戶端只送 intent。離線單機走同一路徑（G 規則）。
2. 每個角色各自接、各自的階段與變數。兩個人做同一條任務互不影響（同一個 NPC 對兩人顯示的選單、對話不同）。
3. `appear` 與護送是**每位玩家各自**判斷：A 在秘密客階段、B 不在 → 只有 A 看得到秘密客。
4. KILL 與 FIGHT：任務列 `party_credit: true`（預設）時，同場戰鬥 side 0 的每位玩家，只要自己目前階段有對應目標，都各自計分／完成（KILL 不再限最後一擊者；舊任務正規化時 `party_credit` 預設 true，這是行為變更，交付說明列出）。`fight` 動作 `solo: true` 時不拉隊友，中途加入的玩家不計。
5. 對話選擇、物品交付、`take`／`give`、房間動作的 `fight` 由按下的人觸發；拉進戰鬥的隊友只在自己的目標符合時得分。
6. 「全服第一個完成」：`ws.world.quest_firsts[qid]` 只記第一次，傳聞只發一次（§5.1）。

### 4.12 舊格式遷移（`core/quest/quest_def.gd`）

- 資料：`steps[i]` → 階段 `step_<i>`，一個目標 `o`，型別與欄位照搬（TALK `target` → `npc`；DELIVER `target`/`item`/`count`；KILL `target` → `monster`；REACH `target` → `room`）；`next` 依序，最後 `END`；`rewards` → `outcomes.default.rewards`；`repeatable` → `repeat`。正規化在 **載入時** 做（`GameData` 的生效表裡已是新格式），所以引擎只處理新格式。
- 存檔：`active[qid] = {step, counts}` → `{stage: "step_<step>", objs: {"o": counts[target]}}`；`done[qid] = n` → `{n, outcome: "default", world_s: 0}`。`Character.from_dict` 做。
- 驗收：既有 15 條任務、M1／M2／M3a 的 bot 全部照舊通過。

### 4.13 引擎 API（綁定）

純邏輯（新目錄 `core/quest/`，WP-ENGINE）：

```gdscript
class_name QuestDef      # core/quest/quest_def.gd
static func normalize(row: Dictionary) -> Dictionary          # 舊→新，並補預設值
static func validate(row: Dictionary, tables: Dictionary) -> PackedStringArray   # lint 共用
class_name QuestState    # core/quest/quest_state.gd
static func migrate(quests: Dictionary) -> Dictionary
static func objective_progress(def: Dictionary, st: Dictionary, ch, tables: Dictionary) -> Array   # [{id,text,have,need,done}]
class_name DialogueTree  # core/quest/dialogue_tree.gd
static func node_view(def: Dictionary, dlg_id: String, node_id: String, ch, tables, options, rules, ctx) -> Dictionary
static func choice(def: Dictionary, dlg_id: String, node_id: String, choice_id: String) -> Dictionary
```

主機（`server/quest_system.gd`，原地升級，保留既有函式名）：

```gdscript
func menu_entries(s: Session, npc_id: String) -> Array          # [{id,name,state,chapter}] state 加 COOLDOWN
func accept(s: Session, npc_id: String, qid: String) -> Dictionary
func talk_quest(s: Session, npc_id: String, qid: String) -> Dictionary     # 開 offer 或目前階段在此 NPC 的對話
func choose(s: Session, npc_id: String, qid: String, node_id: String, choice_id: String) -> Dictionary
func close_dialogue(s: Session) -> Dictionary
func turn_in(s: Session, npc_id: String, qid: String) -> Dictionary        # 舊 intent：等於完成此 NPC 的 TALK/DELIVER 目標
func abandon(s: Session, qid: String) -> Dictionary
func room_action(s: Session, act: String) -> Dictionary                     # act = "<qid>:<action id>"
func room_actions(ch, room_id: String) -> Array                             # [{act,label}]
func npc_visible(ch, npc_id: String) -> bool
func on_kills(s: Session, kills: Array) -> void
func on_reach(s: Session) -> void
func on_battle_settled(s: Session, summary: Dictionary) -> void
func on_items(s: Session) -> void
func on_buy(s: Session, npc_id: String, item_id: String, n: int) -> void
func on_clock(s: Session) -> void
func on_sheet(s: Session) -> void
func on_login(s: Session) -> void
func debug_stage(s: Session, qid: String, stage: String) -> Dictionary      # 只給 debug_set
```

`NpcSystem.talk`：先送 `talk_<npc>`（時辰變體，§5.3），再：若玩家有進行中任務的目前目標在此 NPC 且有 `dialogue` → 直接開該對話（不另開選單）；否則送 `npc_menu`（含任務項）。`npc_here` 尊重 `appear`。

### 4.14 協定增量（`core/protocol.gd`，`VERSION = 5`）

Intent（`INTENT_SCHEMA` 一併登錄）：

| 常數 | 字串 | 參數 | 旗標 |
|---|---|---|---|
| `I_QUEST_TALK` | `quest_talk` | `npc`、`quest` | NEEDS_CHAR、IDLE |
| `I_DIALOGUE_CHOOSE` | `dialogue_choose` | `npc`、`quest`、`node`、`choice` | NEEDS_CHAR、IDLE |
| `I_DIALOGUE_CLOSE` | `dialogue_close` | — | NEEDS_CHAR |
| `I_STORY_ACT` | `story_act` | `act` | NEEDS_CHAR、IDLE |
| `I_VILLAIN_REPLY` | `villain_reply` | `wid`、`choice`（`FIGHT`／`CALL`） | NEEDS_CHAR |
| `I_RUMOR_LIST` | `rumor_list` | — | NEEDS_CHAR |

事件：

| 常數 | key | 頻道 | payload |
|---|---|---|---|
| `E_DIALOGUE` | `dialogue` | SYSTEM（ui） | `npc, npc_name, quest, quest_name, dlg, node, speaker_name, text, choices:[{id,label,locked,why}], end` |
| `E_DIALOGUE_CLOSE` | `dialogue_close` | SYSTEM（ui） | `npc` |
| `E_QUEST_STAGE` | `quest_stage` | SYSTEM | `quest_name, stage_title, objectives:[text]` |
| `E_QUEST_FAIL` | `quest_fail` | SYSTEM | `quest_name, reason_text` |
| `E_QUEST_COMPLETE`（既有） | `quest_complete` | SYSTEM | 加 `outcome_label` |
| `E_RUMOR` | `jianghu_rumor` | **新頻道 `CH_JIANGHU := "JIANGHU"`** | `text_key, params, kind, world_s` |
| `E_RUMOR_LIST` | `rumor_list` | SYSTEM（ui） | `items:[{text_key,params,kind,world_s}]` |
| `E_VILLAIN_PROMPT` | `villain_prompt` | SYSTEM（ui） | `wid, npc_name, countdown_s, can_call` |
| `E_VILLAIN_CLEAR` | `villain_clear` | SYSTEM（ui） | `wid, why`（`ESCAPED`／`FOUGHT`／`GONE`） |

原因碼：`dialogue_none`、`dialogue_stale`、`choice_locked`、`quest_cooldown`、`quest_not_now`、`act_unknown`、`act_not_here`、`villain_none`、`npc_refuse`、`escort_lost`。每個都要有 `text_templates` 的 `fail_<code>` 模板（`_engine` 碎片）。

角色表（sheet）：`lilian`；`quests` 列改成 `{ id, name, chapter, stage, stage_title, log, objectives:[{text,have,need,done}], hint_room, escort }`；`quests_done` 改成 `[{ id, name, chapter, outcome_label, n }]`；`quest_cd`：`{ qid: 剩餘世界秒 }`。
view：`npcs` 依 `appear` 過濾；新 `story_actions:[{act,label}]`；`escort:[{npc,name}]`；`wanderers:[{wid,npc,name,hostile}]`（WanderSystem 經 `host.m2_call(host.wander,"view_for",[s],[])` 提供）。

### 4.15 Debug intent 增量（`server/intents/intents_debug.gd`）

新 key：`world_s_add`（秒，快轉世界時鐘，觸發 `_minute_jobs`）、`hour`（直接跳到某時辰起點）、`quest_stage`（值 `"<qid>:<stage>"`，沒接就先接）、`quest_reset`（值 qid：清 active/done/cd）、`lilian`、`fame`、`wander_place`（值 `"<wid>:<room>"`）、`rumor_flush`（清空傳聞節流）。只在 `--debug-intents` 時註冊（M3A_PLAN 6.11）。

---

## 5. 活的江湖（WP-AMBIENT，伺服器端）

### 5.1 江湖傳聞（`server/rumor_system.gd`，`class_name RumorSystem`）

```gdscript
func post(kind: String, text_key: String, params: Dictionary, scope := "WORLD", region := "") -> bool   # 節流後廣播
func recent(n: int) -> Array
func on_login(s: Session) -> void          # 補送最近 5 則
func tick(dt: float) -> void               # 預告、事蹟輪詢
```

- 全部【設計提案・非原作】（研究：原作的「江湖謠言」是匿名玩家頻道，沒有系統謠言）。伺服器選項 `rumors_enabled`（預設 true）、`rumor_min_gap_s`（同一 kind 兩則之間的最短真實秒數，預設 120）。
- 來源與 kind：
  1. `FORESHADOW`：`data/rumors.json` 的預告列，在條件成立、還沒人完成該任務時，每個遊戲日最多一次（例：「聽說衡山劉正風要金盆洗手了，莫大先生卻不知去向。」）。
  2. `QUEST`：任務 `rumors.first`（全服第一位完成，必發）／`rumors.each`（之後每次完成，受節流）。
  3. `DEED`：玩家事蹟——名聲跨過 100／500／1000／5000、善惡跨過 −100（轉惡）與 +1000、擊敗遊蕩惡人、加入門派、叛派（輪詢角色表差異，標記存在 `ch.ext.ambient.deeds`）。
  4. `PK`：既有強制 PK 擊殺廣播改由 `PkSystem` 呼叫 `post("PK", "e_pk_kill", …)`（RumorSystem 為 null 時照舊直接廣播；`pk_system.gd` 歸 WP-AMBIENT）。
  5. `VILLAIN`：遊蕩惡人出沒與被擊敗（§5.2）。
- `ws.world.rumors` 保留最近 50 則（存檔）。玩家匿名頻道「江湖謠言」（`CH_CHAT_RUMOR`）不變；新增伺服器選項 `rumor_chat_inner_min`（審查修正後預設 **80**，照研究「謠 needs 基本內功 80」；era 【待考證】；0 = 不限）。
- `data/rumors.json` 列：`{ "id", "kind": "FORESHADOW", "quest": qid, "text": 模板 id, "requires_world": { "not_first": qid } , "hours": [], "weight": 1, "era", "src" }`。

### 5.2 遊蕩惡人與追擊 NPC（`server/wander_system.gd`，`class_name WanderSystem`）

#### 5.2.1 資料 `data/wanderers.json`

```json
{ "id": "w_nanhai", "npc": "n_nanhai", "monster": "m_nanhai", "home_room": "xx_street",
  "schedule": [ { "hours": ["卯","辰","巳","午","未","申","酉"], "mode": "HOME" },
                { "hours": ["戌","亥","子","丑","寅"], "mode": "ROAM", "regions": ["xixia_wild","xixia_south","xixia_north"] } ],
  "move_every_ke": 4, "aggro": { "requires": [], "chance_pct": 60, "per_player_cooldown_days": 1 },
  "talk_fight": { "requires": [] },
  "no_flee": true, "respawn_days": 1,
  "rumors": { "roam": "rmr_w_nanhai_roam", "defeated": "rmr_w_nanhai_defeated" },
  "era": "1.0A", "src": "proposal", "src_note": "白天定點、交談即打：官方自救手札、gaoshou/23；夜遊與主動出手【設計提案・非原作】" }
```

預設三列（`_ambient` 碎片）：`w_nanhai`（如上；`talk_fight.requires` 空 = 招呼就打）、`w_yeerniang`（同房 `xx_street`；`talk_fight.requires: [{"type":"morality_min","value":1}]`；夜遊 `xixia_south`、`desert_edge`；`aggro.requires` 同樣只對善惡 > 0）、`w_etou_*`（追擊 NPC「惡人頭子」，`mode` 全天 `ROAM`，各 1 隻在 `xixia_east`、`dali_wild`、`songshan_road`；era 1.0A，`since: "2001-08-30"`，受規則 `chase_npcs` 控制，預設開）。

#### 5.2.2 行為

1. 每 `move_every_ke` 刻，ROAM 中的惡人移到允許地區內一個相鄰房間（不得進入安全房間、CITY、SECT、DUNGEON；沒有合法鄰房就留在原地）；HOME 時段開始時走回（直接出現在 `home_room`，文字「XX 回城去了」只對同房玩家）。
2. 玩家進入惡人所在房間，或惡人移入玩家所在房間，且全部成立：房間不是安全房間、玩家 `combat_xp ≥ newbie_pk_protect_xp`、玩家不在戰鬥／坐牢／對話中、`aggro.requires` 成立、該玩家冷卻已過、擲骰 `chance_pct` → 送 `E_VILLAIN_PROMPT`（`countdown_s` 預設 3 真實秒）。
3. 倒數期間玩家可以：`move` 離開（成功離開房間 → `villain_clear ESCAPED`，記冷卻）；`villain_reply FIGHT`（立刻開打）；`villain_reply CALL`（立刻以 `求救` 通知同地區的隊友與玩家「XX 在 YY 遭南海鱷神襲擊」，倒數照走）。倒數結束仍在房間 → 開戰：`start_ex(s, [monster], "CHASE", {"no_flee": true, "pull_party": true})`（研究：追擊戰不能逃）。
4. 白天 HOME：不主動出手；交談時若 `talk_fight.requires` 成立 → 開戰（kind `FIGHT`，可逃；研究：南海鱷神那場玩家逃了好幾次才逃掉）。
5. 惡人被擊敗（勝方 side 0）：消失 `respawn_days` 遊戲日，發 `VILLAIN` 傳聞「某某在某地擊退了南海鱷神」；給 `DEED`。
6. 狀態（位置、下次移動、重生時間、每位玩家冷卻）存 `ws.world.wanderers`；主機離線時凍結（S4）。

#### 5.2.3 安全房間（綁定定義）

區域 type 是 CITY 或 SECT 的房間；有 `INN` 服務 NPC 的房間；房間 `safe: true`（新欄位，選填）；`encounter` 為空且是 WILD 地區的第一間（緊鄰城門）房間（`xw_road`、`dlw_road`、`hy_foot`、`sy_foot` 等，WORLD_2001 規則 1）。

### 5.3 NPC 閒聊與環境句（`server/ambient_system.gd`，`class_name AmbientSystem`）

- 時段：`DAWN`（卯辰）、`DAY`（巳午未申）、`DUSK`（酉）、`NIGHT`（戌亥子丑寅）。
- 交談：`talk_<npc>@<period>` 模板存在就用它，否則用 `talk_<npc>`（`NpcSystem.talk` 呼叫 `host.m2_call(host.ambient, "talk_key", [s, npc_id], 預設key)`）。
- 招呼語：`AmbientSystem.greet_key(s, npc_id) -> String`，依 `data/reactions.json` 的 `greet` 規則（例：善惡 ≤ −500 的人找 GOOD 商人 → 「哼，你這種人也敢上門？」；名聲 ≥ 1000 → 「久仰大名」；新手 → 「小兄弟第一次來？」）。送在 talk 句之前（CH_SCENE）。
- 環境句：`data/ambient.json` 列 `{ id, room|region|npc, periods:[], requires:[], weight, text: 模板 id }`；玩家進房時 25% 機率送一則（同一玩家 90 真實秒冷卻），只送給本人（CH_SCENE）。原作沒有自動閒聊的記載 → 【設計提案・非原作】，選項 `ambient_lines`（預設 true）。內容方向照研究的原作風味：老農夫重複叮嚀、落第秀才要錢、客棧是打聽消息的地方、夜裡城裡暗下來、茶棚老闆報路況、惡人出沒的風聲。
- 每個有 talk 模板的 STORY／QUEST NPC，`_ambient` 碎片至少給 `@NIGHT` 一句（店家可省略）。

### 5.4 對善惡／名聲的反應（AmbientSystem）

`data/reactions.json` 列：

```json
{ "id": "rx_good_shop_evil", "npc_kinds": ["SHOP","FUNC"], "npc_alignment": ["GOOD","NEUTRAL"], "services": ["SHOP","INN"],
  "when": [ { "type": "morality_max", "value": -500 } ], "price_pct": 120, "greet": "greet_cold_evil",
  "era": "1.0A", "src": "proposal", "src_note": "研究：1.0 查無依善惡改價的記載【設計提案・非原作】" }
```

- 預設列（`_ambient` 碎片）：善惡 ≤ −500 → GOOD/NEUTRAL 商店、客棧 +20%；善惡 ≤ −1000 → 拒絕（`refuse: "rx_refuse_evil"`）；名聲 ≥ 1000 → −5%；邪派店家（`n_xh_canjizi`、`n_xd_jingqi`）對善惡 ≥ 500 → +20%、≥ 1000 拒絕。
- **永不受影響**：`RESPAWN`、`TRAVEL`、`QUEST`、`TEACH`、`JOIN`、`JAIL`、`GUIDE`、守衛、查小鏞（安全與門派規則歸 M3a）。
- API：`price_pct(s, npc_id, service) -> int`（100 = 原價）、`refuse_reason(s, npc_id, service) -> String`（"" = 不拒）。`NpcSystem.buy`／`inn_rest` 經 `host.m2_call` 呼叫；拒絕回原因碼 `npc_refuse` 並送 refuse 模板。選項 `npc_reactions`：`"OFF"`／`"FLAVOR"`（只有招呼語）／`"FULL"`（預設）。
- 原作有的反應保持且要測：葉二娘交談即戰（善惡 > 0，§5.2）、守城官兵（M2）、邪派門下追殺善惡 > 0 入山者（M3a 敵對入山）。

### 5.5 伺服器選項（`data/server_options.default.json`，WP-ENGINE 擁有檔案，數值照本表）

| key | 預設 | 說明 |
|---|---|---|
| `rumors_enabled` | true | §5.1 |
| `rumor_min_gap_s` | 120 | §5.1 |
| `rumor_chat_inner_min` | 80 | 江湖謠言頻道的基本內功門檻（審查修正：原 0） |
| `wanderers_enabled` | true | §5.2（白天定點的交談即戰不受此開關影響） |
| `villain_warn_s` | 3 | 出手前警告秒數（【設計提案】，擁有者可調長） |
| `chase_npcs` | true | 追擊 NPC（2001-08-30） |
| `ambient_lines` | true | §5.3 |
| `npc_reactions` | `"FULL"` | §5.4 |

伺服器設定面板（WP-UI）新增這 8 項。

---

## 6. 介面（WP-UI）

1. **對話視窗**（`ui/game/dialogs/story_dialog.gd`，新）：AUTHENTIC_UI_SPEC 的對話框風格（玉石框、上方 NPC 名、內文逐字顯示可點跳過）、選項按鈕（數字鍵 1–9；上鎖選項灰色＋滑鼠提示 `why`）、「結束」（Esc → `dialogue_close`）。收到 `E_DIALOGUE` 開啟或更新；`E_DIALOGUE_CLOSE`、移動、開戰時關閉。與既有 `npc_dialog.gd`（服務選單）並存：任務項點下送 `quest_talk`。
2. **任務窗升級**（`ui/game/panels/quest_panel.gd`）：左欄依 `chapter` 分組（可收合），右欄目前階段標題、`log`、目標清單（進度 `have/need`、完成打勾）、已走過的階段（從 `log` 歷史，灰字）、護送對象、提示地點（點了在地圖上標記 `hint_room`）；「已完成」分頁顯示結局名與次數；可重複任務顯示冷卻剩餘（遊戲時辰）。
3. **傳聞顯示**：`CH_JIANGHU` 走既有公告浮層（`message_log.add_announcement`，樣式「【江湖傳聞】」）；系統窗新增「江湖傳聞」頁（開啟時送 `rumor_list`）；頻道開關可關掉 JIANGHU。
4. **惡人警告**（`ui/game/social/villain_prompt.gd`，新）：非模態提示「南海鱷神朝你逼近！」＋倒數條＋「迎戰」「求救」；提示文字「快離開這裡」；`villain_clear` 收起。
5. **場景卷軸**：`story_actions` 按鈕（任務動作，紅字）；`wanderers` 在人物列以【惡】標記；護送 NPC 顯示「（隨行）」；`appear` 過濾後的 NPC 列表照 view。
6. **伺服器設定面板**：§5.5 八項。
7. **角色屬性窗**：顯示「江湖歷練」（`lilian`），位置在名聲旁邊。

---

## 7. 碎片格式（`docs/story_staging/<key>.json`）

### 7.1 結構（每個內容建造者**只寫自己的一個檔案**）

```json
{
  "fragment": "ev_yuner", "version": 1, "author": "WP-C-ev_yuner",
  "quests": [ "…§4.2 第 2 版列…" ],
  "npcs": [ "…只放本碎片擁有的 NPC（§3.2），形狀照 npcs.json，加 appear（選填）…" ],
  "npc_links": [ { "npc": "n_em_jingguan", "add_quests": ["q_guhongzi"] } ],
  "shop_patches": [ { "npc": "n_xx_pharmacist", "add_items": ["c_dahuandan"] } ],
  "art_patches": [ { "id": "sl_riyuebian", "add_requires": [ { "type": "quest_flag", "flag": "sl_riyuebian_ok" } ] } ],
  "items": [], "monsters": [], "martial_arts": [], "masters": [],
  "text_templates": [ "…talk_<npc>、talk_<npc>@NIGHT、rmr_*、本任務用到的 tell／fail 模板…" ],
  "rumors": [ "…data/rumors.json 列…" ],
  "ambient": [ "…data/ambient.json 列（選填）…" ],
  "art_requests": { "units": [ { "id": "n_xx_yuner", "alias": "n_em_yingyueer", "prompt": "…" } ], "backgrounds": [] },
  "test_plan": [ { "quest": "q_yuner", "outcome": "abao", "path": ["accept@n_xx_yuner", "talk@n_xx_litaian", "…"], "expect": { "items": { "r_kuang_zi": 3 } } } ],
  "todo_verify": [ "…【待考證】…" ],
  "owner_decisions": [ "…本碎片採用的 §1.3 決定編號，或新的預設…" ],
  "notes": ""
}
```

只有 `_world` 碎片可以有 `regions`、`maps`、`extra_rooms`、`exit_patches`（M3A_PLAN 4.1 形狀）。只有 `_ambient` 可以有 `wanderers`、`reactions`。`npc_links` 只能追加 `quests`；不得改別人的 NPC 其他欄位（`ev_lanfenghuang` 例外：覆寫 `talk_n_em_yingyueer` 模板，研究要求調和）。唯一的 `npc_patches` 例外是 `ev_chendabao` 給既有 `n_qz_chendabao` 加 `fight` 服務（§7.3）。

`test_plan`（必填）：每個結局至少一條路徑，用 bot 的動作語彙（`accept@npc`、`talk@npc`、`choose@npc:node:choice`、`act@<qid>:<action>`、`fight:WIN|FLEE`、`buy@npc:item:n`、`wait:hour=申`、`wait:days=1`、`walk@room`）。整合者的 story bot 直接讀它（§9.2）。

### 7.2 每個內容碎片的必備內容

1. 研究對應小節的每一步都成為階段或目標；研究的選項文字原樣出現；每個 `END:<x>` 都有結局。
2. 每個給予者與步驟 NPC 都放在 §3.2 指定的房間；跨碎片 NPC 用 `npc_links`。
3. 對話：每個任務至少 `offer` 一段、每個 TALK 目標一段；每段 3–8 個節點；說話口吻符合原著人物；繁體；不得有簡體字。
4. 時辰限制（莫大、令狐沖、張豹、程清霜）一定要在 `appear` 或目標 `hours`，並在 `log` 告訴玩家什麼時候去。
5. 每條任務的 `log` 文字要指路（照 WORLD_2001 §5.3 的寫法：從哪個城門出、經過哪些地方）。
6. `rumors`：P0 任務各給 1 則 `first`、1 則 `FORESHADOW`。
7. `todo_verify` 列出所有【待考證】；`owner_decisions` 列出採用的 §1.3 編號。

### 7.3 各碎片內容要點（細節以研究為準）

| 碎片 | 擁有的任務 | 要點 |
|---|---|---|
| `_world` | — | §2 全部；`n_hn_teaman`；`hf_fork`／`hf_teahouse`／`n_jc_guard` 文字更新；房間 `safe` 欄位 |
| `_engine`（WP-ENGINE） | — | `fail_<code>` 模板、`e_quest_stage`／`e_quest_fail`／`e_dialogue_*` 系統模板 |
| `_ambient`（WP-AMBIENT） | — | `wanderers`、`reactions`、`m_nanhai`、`m_yeerniang`、`m_amb_etou`、`n_amb_etou_*`、所有 `@NIGHT` 閒聊、環境句、`greet_*`、`rx_*`、`rmr_w_*`、DEED 傳聞模板 |
| `ev_yuner` | `q_yuner` | §4.2 範例為準；阿寶的謝禮 3 紫石礦 3 綠石礦；李台安 10 兩；`@NIGHT` 雲兒點燈發愁 |
| `ev_xuzhu` | `q_xuzhu` | 道品 → 虛竹（護送 `escort_start`）→ `xx_palace` 左守衛：選項 1 → 守衛回話 → 選項 2 → `fight` 守衛（`win: "WIN_OR_FLEE"`）→ 虛竹給回信（`escort_end`）→ 道品 → 大還丹 ×3；少林限定；選錯選項只是重來那段對話 |
| `ev_liuzhengfeng` | `q_liu_jinpen`、`q_liu_jinpen_2` | 上：劉公子給武林帖 → 申酉時到 `hn_shore` 見莫大（不在時 `log` 寫「黃昏時分再來」）→ 莫大叫你把帖子留在衡山 → 劉公子 → 1000 兩。下：魯連榮（`requires quest_done q_liu_jinpen`）→「幫他」→「明白」（其他選項結束對話、不接）→ `hn_teahouse` 房間動作「休息」→ 秘密客出現 → 密語（「太陽月亮……」、「剷平他」；答錯 → 秘密客不理你，可再試）→ `fight` 6 名魔教教徒（`WIN_OR_FLEE`，`no_flee: false`）→ 魯連榮（受傷、魔教的圈套）→ 名聲 40 歷練 40 |
| `ev_guhongzi` | `q_guhongzi` | 靜觀師姐 → 家書給雲兒 → 雲兒的信（+清水 3、牛肉餅 5，`later`）→ 靜觀說出孤鴻子之死（小說版，D17、研究）→ 大理問兩個人（村民＋捕快 或 韋小寶，`any`）→ `dlw_desertcave` 詭異的人 → `fight` 明教分舵主（WIN）→ 再交談「並不壞」→ 靜觀 → 滅絕 → 學點 50 名聲 10 歷練 10；門檻 峨嵋心法 5、實戰 1000、名聲 100（`later`） |
| `ev_lanfenghuang` | `q_lanfeng` | 藍鳳凰（福緣 22，`later`）→ 五種素材各 5（房間動作各打 5 次：`rr_upper` 蜈蚣、`dlw_river` 青蛇、`xh_marsh` 蝎子、`hf_fork` 蜘蛛；蟾蜍走瑩月兒支線：麻布 5 → 藍依涵 → 瑩月兒給蟾蜍 5 並 `reward` 名聲 5 歷練 15）→ `WAIT days=1`（`later`）→ 藍鳳凰：恆山派 → `END:hengshan`（解毒藥 ×5），其他 → `END:default`（`learn basic_poison` +1 級、解毒藥 ×1、善惡 −100 `later`）；重複：冷卻 1 遊戲日（`later`） |
| `ev_xingxia` | `q_xingxia` | 靈芝商人 → `ym_bridge` 強盜 `fight`（WIN）→ 寶盒 → 靈芝商人 → 靈芝草 3、名聲 5、歷練 5；`repeat {max:0, cooldown_days:1}` |
| `ev_wentailai` | `q_wentailai` | 買白酒＋羊乳酒（BUY）→ 張豹（給酒 `take`）→ 陳家洛 → 張豹「有酒就說」→ BUY 每種酒各 1（階段開始後才算）→ 張豹選項 2 → 王捕頭 → 張豹 BUY → 「王捕頭的情報」→ 王捕頭要三瓶竹葉青灌醉 → 公文手抄本 → 陳家洛 → 歷練 10（`later`） |
| `ev_laodenuo` | `q_hs_jianqi`、`q_hs_spy`、武功 `hs_zixia` | 劍氣宗之別：華山劍法 35、華山心法 30 → 成不憂「你可知劍宗？」→ 加入劍宗（`flag hs_jianzong`）或婉拒（`flag hs_qizong`）；互斥、一次。華山內奸：`requires` 華山派、`hs_qizong`、華心 50 讀書 30 悟 30 儒風 30 → 勞德諾 → 令狐沖（巳午未）→ 勞德諾「敷衍一下」（衡山左冷蟬）→ 令狐沖 → 華山密函 → 岳不群 → 追擊令 → 勞德諾 `fight`（WIN）→ 氣宗武譜 → 岳不群 → `flag hs_zixia_ok`、`learn hs_zixia 1` |
| `ev_yangkang` | `q_yangkang` | 丘處機（全真弟子）→ 丘處機手諭 → `xx_palace_mishi` 楊康 `fight`（WIN）→ 郭靖匕首 → 丘處機 → 歷練 50 學點 10（`later`）；`rumors.first` 提到江南七怪的賭約 |
| `ev_chendabao` | `q_chendabao` | 陳大寶（武當）→ 討伐令 → `ts_road1` 賊頭 → 令牌 → 陳大寶（俠義 +250）→ `dl_square` 小嘍囉 → `dlw_fork` 熊霸天 → `xd_road2` 獨眼仁（每戰回報 +250）→ `repeat {max:0, cooldown_days:1}`；可對陳大寶出手：`npc_links` 不夠用，所以本碎片用 `npc_patches`（唯一例外）只給 `n_qz_chendabao` 加 `fight: {"monster":"m_cdb_chendabao"}` 與 `FIGHT` 服務；新怪 `m_cdb_chendabao`（300，`morality_on_kill: -50`） |
| `ev_misc_2001` | §1.1 P2 七條 | 研究「Other 2001 events」；血刀採花是惡行分支（善惡 −100）；物色美女不做 |
| `sect_stories` | §1.1 門派表 | 研究「Sect story quests」；每派解鎖照既有旗標；武當黑玉的七蟲用 2001 七毒出沒點（研究），綠柳莊、馬王洞等後期地點換成 1.0 既有地點（標【設計提案】）；龍門遺孤在 `hn_teahouse`、白天限定；峨嵋拜訪名人略去段譽；李莫愁在 `dlw_lake`；化功大法照 2001-08-25 步驟（`STATE` 目標檢查拍馬屁神功等級 → 用門派技能 `chanmei` 熟練代替，標【設計提案】） |

---

## 8. 工作包與檔案所有權

### 8.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-ENGINE** | `server/quest_system.gd`；新 `core/quest/quest_def.gd`、`core/quest/quest_state.gd`、`core/quest/dialogue_tree.gd`；新 `server/intents/intents_story.gd`；`server/intents/intents_quest.gd`、`server/intents/intents_debug.gd`、`server/intents/intents_npc.gd`；`server/npc_system.gd`、`server/region_system.gd`、`server/battle_system.gd`（只加 §4.8 的呼叫與 `quest_tag`、kind `QUEST`／`CHASE`）、`server/game_host.gd`（`STORY_SYSTEMS` 載入、時辰與 tick 鉤子）、`server/session.gd`；`core/protocol.gd`；`core/character/**`；`core/data/**`；`autoload/world_server.gd`、`autoload/client_state.gd`；`data/server_options.default.json`；新 `tests/unit/test_quest_def.gd`、`test_quest_state.gd`、`test_dialogue_tree.gd`、`test_world_quest_v2.gd`、`test_world_quest_party.gd`、`test_world_quest_legacy.gd`、`test_protocol_story.gd`；既有 `tests/unit/test_character*.gd`、`test_world_*.gd`、`test_protocol_*.gd`、`test_data_loader.gd` 的必要更新；`docs/story_staging/_engine.json` | §4 全部；Day-0 |
| **WP-AMBIENT** | 新 `server/rumor_system.gd`、`server/wander_system.gd`、`server/ambient_system.gd`、`server/intents/intents_ambient.gd`；`server/pk_system.gd`（只改廣播改走 RumorSystem）；新 `tests/unit/test_rumor_system.gd`、`test_wander_system.gd`、`test_ambient_system.gd`；`docs/story_staging/_ambient.json` | §5 全部 |
| **WP-UI** | `ui/**`、`autoload/scene_router.gd`；新 `tests/unit/test_ui_story_dialog.gd`、`test_ui_quest_log.gd`、`test_ui_rumor.gd`、`test_ui_villain_prompt.gd`；既有 `tests/unit/test_ui*.gd` 的必要更新 | §6 全部 |
| **WP-C-<key>** ×10 | `docs/story_staging/<key>.json`，**只有這個檔**：`_world`、`ev_yuner`、`ev_xuzhu`、`ev_liuzhengfeng`、`ev_guhongzi`、`ev_lanfenghuang`、`ev_xingxia`、`ev_wentailai`、`ev_laodenuo`、`ev_yangkang`、`ev_chendabao`、`ev_misc_2001`、`sect_stories`（`_world` 與 `ev_misc_2001` 可由同一個建造者兼做；`ev_yangkang`、`ev_chendabao` 可兼做） | §7 |
| **WP-MERGE**（建造之後單獨執行） | `data/*.json`（除了 `server_options.default`）、`data/maps/*.json`、`data/art.json`、新 `data/rumors.json`、`data/wanderers.json`、`data/ambient.json`、`data/reactions.json`；`tools/data_lint.gd`、`tools/validate_data.gd`、`tools/balance_sim.gd`（只加 §2.3 走路案例與新怪 1v1 案例）；`tests/unit/test_data_content.gd`、新 `tests/unit/test_data_story.gd`；`docs/ART_REQUEST.md` §6「第四批」 | §8.4 |
| **整合者**（協調者本人） | `tests/bots/**`（新 `tests/bots/story_bot.gd`、`tests/bots/story_duo_bot.gd`）、`tests/ui/ui_playthrough.gd`、`tests/ui/ui_driver.gd`、`tools/*acceptance*`（新 `tools/story_acceptance.gd`）、`README.md`、`docs/**`（GDD §8 同步、本文件的整合紀錄） | §9 驗收 |

`core/data/data_loader.gd` 的 `FILES` 由 WP-ENGINE 加 `rumors`、`wanderers`、`ambient`、`reactions`（四個新表都要有 `era`）。`GameHost.STORY_SYSTEMS := { "rumor": "res://server/rumor_system.gd", "wander": "res://server/wander_system.gd", "ambient": "res://server/ambient_system.gd" }`、`STORY_INTENTS := ["res://server/intents/intents_story.gd", "res://server/intents/intents_ambient.gd"]` 由 WP-ENGINE 寫；WP-AMBIENT 的系統檔還沒交付時載入失敗 → `null`，引擎照常運作（S2）。

### 8.2 凍結檔（本包任何 WP 都不得修改）

M3A_PLAN 8.2 的全部，加上：`server/sect_system.gd`、`server/condition_system.gd`、`server/intents/intents_sect.gd`、`server/party_system.gd`、`server/social_system.gd`、`server/mail_system.gd`、`server/corpse_system.gd`、`server/scout_system.gd`、`server/admin_system.gd`、`core/battle/**`、`data/status_effects.json`、`data/rule_profiles.json`、`docs/m3a_staging/**`。需要這些檔案的行為改變 → 寫成 `# STORY_PLAN 缺漏` 交給整合者。

### 8.3 Day-0（各 WP 開工的第一件事）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-ENGINE | (1) `core/protocol.gd`：`VERSION = 5`、§4.14 全部常數與 `INTENT_SCHEMA`、`CH_JIANGHU`；(2) `core/data/data_schema.gd`：§4.6 條件、`quests` 第 2 版欄位的 `INT_FIELDS`／`REFS`（`stages[].objectives[].npc`→npcs、`.item`→items、`.monster`→monsters、`.room`→房間）、四個新表；(3) `Character.lilian`、`ch.ext`、`QuestState.migrate`；(4) `GameHost` 容錯載入 `STORY_SYSTEMS`／`STORY_INTENTS`，以及 §4.8 的 `host.m2_call(host.wander|ambient|rumor, …)` 呼叫點（方法不存在時略過） | WP-AMBIENT 與 WP-UI 需要常數與鉤子 |
| WP-AMBIENT | 先寫純邏輯（排程、安全房間判斷、節流）與測試；鉤子名照 §5 | — |

### 8.4 合併程序（WP-MERGE）

1. 讀 `docs/story_staging/*.json`；逐檔 JSON 解析；id 重複（跨碎片或與現有資料）→ 停下並列出，以字母序先到者為準，後者加 `_2` 並記錄。
2. 合併：`_world` 的地區、地圖、`extra_rooms`、`exit_patches`；各碎片 `npcs`、`items`、`monsters`、`martial_arts`、`masters`、`quests`、`text_templates`（同 id 以碎片為準，列出覆寫）、`rumors`、`ambient`；`_ambient` 的 `wanderers`、`reactions`；`npc_links` → `npcs[].quests`；`shop_patches` → `npcs[].shop.items`；`art_patches` → `martial_arts[].requires` 追加；`art_requests` → `data/art.json`（`alias` 照填）。
3. 舊列 `q_liu_jinpen`、`q_guhongzi`、`q_xuzhu`、`q_lanfeng`、`q_yuner`、`q_xingxia`、`q_wentailai`、`q_hs_spy`、`q_lanfeng2`、`q_yangkang` 若在 `data/quests.json` 不存在就新增（目前只在 GDD 表）；不得刪既有 15 條。
4. 跑 lint（§8.5）到 0 錯誤；`balance_sim` 新走路案例；全部單元測試；更新 `test_data_content.gd` 計數；新 `test_data_story.gd`（每條 P0 任務的階段圖可達、結局齊全、NPC 與房間存在）。
5. `docs/ART_REQUEST.md` §6「第四批」：新 NPC 立繪、`hengshan_s`、`hengshan_s_road`、`yanmen` 戰鬥背景、皇宮門口；格式照前幾批。

### 8.5 Lint 新檢查（`tools/data_lint.gd`）

1. 任務第 2 版：`start` 存在；每個 `next`／`goto` 指到存在的階段、節點或 `END[:x]`；每個 `END:x` 有 `outcomes.x`；條件陣列最後一項無條件；**每個階段都從 `start` 走得到、每條路都會結束**（無死循環：圖上每個節點都能到 END）。
2. 目標與動作欄位合法；引用的 NPC／物品／怪物／房間／武功存在；`fight` 動作的怪物存在。
3. 每個目標 NPC 有房間、從兩座出生城走得到（既有可達性檢查擴充，S6），而且不只靠 `xx_palace_mishi` 這類 `requires` 房間以外的路（`requires` 房間必須在需要它的任務裡可滿足）。
4. `appear.hours` 是合法時辰；有 `hours` 限制的目標 NPC，`log` 文字必須含時辰字。
5. 任務素材掉落：`drops[].requires` 存在、`chance` 100。
6. 旗標：`flag` 動作只能用 §3.5 的旗標或碎片前綴開頭的新旗標；`martial_arts` 的 `quest_flag` 都至少有一個任務會設。
7. `wanderers`：`home_room` 存在、`regions` 存在、不含 CITY／SECT；`monster` 存在。`reactions`：`services` 不含 §5.4 永不受影響的服務。
8. 新地區通過 WORLD_2001 §1.4 新手規則（§2.3）。
9. 簡體字黑名單擴充到任務對白與傳聞（M3A_PLAN 8.5 #11 的清單 + 鳳 风、龍 龙、寶 宝、劍 剑、雲 云、門 门、與 与、這 这、說 说、們 们、對 对、會 会、來 来、還 还、讓 让、謝 谢、聽 听）。
10. 每條 P0 任務的 `test_plan` 覆蓋每個 `outcomes` 鍵。

---

## 9. 測試計畫

### 9.1 各 WP 的單元與整合測試（全部在 `tests/run_tests.gd` 裡跑，`--filter=story` 可單跑）

| WP | 測試 | 內容 |
|---|---|---|
| ENGINE | `test_quest_def.gd` | 舊格式 15 條正規化結果；各種錯誤列被 `validate` 抓到 |
| ENGINE | `test_quest_state.gd` | 舊存檔遷移（`{step,counts}`、`done:int`）；目標進度計算 |
| ENGINE | `test_dialogue_tree.gd` | 節點檢視、上鎖選項與 `why`、`hide_if_locked`、`goto END`、`resume` |
| ENGINE | `test_world_quest_v2.gd` | 用小型測試任務（fixture，不依賴內容碎片）：接任務（`offer`→`accept`）、TALK/DELIVER/COLLECT/KILL/FIGHT（勝、逃、敗）/REACH/BUY（之前買的不算）/WAIT（快轉）/STATE/ESCORT；條件分支；結局獎勵（含 `lilian`、`learn`）；`fail`；冷卻與 `max`；`appear` 隨時辰變化與 `npc_here`；房間動作；**中途存檔→重新載入→繼續**（含護送） |
| ENGINE | `test_world_quest_party.gd` | 兩個 session 同隊：KILL／FIGHT 各自計分、`solo` 不計、中途加入規則；兩人同任務不同階段時 `appear` 各自不同；對話游標互不干擾 |
| ENGINE | `test_world_quest_legacy.gd` | 既有 15 條任務照舊可做（大兔皮、種稻、送信、剿滅山賊、岳不群考驗、M3a 各派任務） |
| ENGINE | `test_protocol_story.gd` | `VERSION == 5`；新 intent 的 schema；sheet／view 新欄位形狀 |
| AMBIENT | `test_rumor_system.gd` | 節流、`first` 只發一次、預告在完成後停止、`recent`、選項關閉時不發、存檔往返 |
| AMBIENT | `test_wander_system.gd` | 排程（HOME／ROAM 換時辰）、只走允許地區、不進安全房間、新手免疫、冷卻、警告倒數內離開即脫身、倒數結束開 `no_flee` 戰鬥、擊敗後重生、主機凍結時不動、葉二娘只對善惡 > 0 |
| AMBIENT | `test_ambient_system.gd` | 時辰變體 talk 句、招呼語、`price_pct`／`refuse_reason`、永不受影響的服務、`npc_reactions` 三種模式 |
| UI | `test_ui_story_dialog.gd`、`test_ui_quest_log.gd`、`test_ui_rumor.gd`、`test_ui_villain_prompt.gd` | 依 M3a UI 測試慣例：餵事件、檢查節點、按鈕送出正確 intent |
| MERGE | `test_data_story.gd` | §8.4 #4 |

### 9.2 故事驗收：`tools/story_acceptance.gd` + `tests/bots/story_bot.gd`（整合者）

- 主機以 `--debug-intents --time-scale=50` 在**全新世界**起動；每條鏈用**新角色**（debug 只用來滿足門派、屬性、技能門檻與快轉時辰；移動一律 `move` 一步一步走，用區域圖 BFS 找路）。
- 路徑來源：各碎片的 `test_plan`（合併後由 WP-MERGE 原樣存進 `data/quests.json` 列的 `test_plan` 欄位；引擎忽略此欄）。
- `--all`：每條任務的**每個結局**至少跑一次（`q_yuner` abao/li、`q_lanfeng` default/hengshan、`q_hs_jianqi` 劍宗/氣宗、`q_xuzhu` 逃/勝、`q_liu_jinpen_2` 逃/勝 …）；`--chain`／`--branch` 單跑。
- 每條鏈檢查：每個階段的 `E_QUEST_STAGE`、最終 `E_QUEST_COMPLETE` 的結局、角色表差異（銀兩、名聲、`lilian`、善惡、物品、旗標、技能等級）等於 `outcomes` 宣告；可重複任務第二次接被冷卻擋下、快轉後可接；一次性任務第二次是 `DONE`。
- **存檔重載**：每條鏈在中間某個階段（`test_plan` 的 `save_reload_at` 或預設第 2 階段）呼叫 `WorldServer.save_now()` → `stop()` → 同一世界 `start()` → 重新選角，繼續跑完；護送、變數、計數都要還在。
- **雙人**（`tests/bots/story_duo_bot.gd`，在同一行程開兩個 session，照 m2_acceptance 的作法）：A、B 同時做 `q_liu_jinpen_2`，A 先到秘密客階段時 B 看不到秘密客；A、B 組隊打魔教伏擊時兩人都完成 FIGHT 目標；A 選阿寶、B 選李台安，兩人結局各自正確；A 完成時全服傳聞只發一次「第一位」。
- **活的江湖**：快轉到戌時，`wander_place` 把南海鱷神放到 bot 的下一間野外房間，檢查警告→不動→`CHASE` 戰鬥且不能逃；另一次在警告內移動脫身；新手角色進同房不被出手；城裡交談即戰（白天）。傳聞：完成 `q_yuner` 收到 `jianghu_rumor`。
- 輸出：每條鏈 PASS/FAIL、耗時、未覆蓋的結局；任何 `SCRIPT ERROR` 即失敗。

### 9.3 回歸（全部要綠）

`tests/run_tests.gd`（0 failed）、`tools/data_lint.gd`、`tools/balance_sim.gd`、`tests/ui/ui_playthrough.gd`（headless）、M1 驗收 bot（全新世界）、`tools/m2_acceptance.gd`、`tools/m3a_acceptance.gd`、`tools/net_smoke.gd`、`tests/bots/close_mid_battle_bot.gd --close-mode=wm` 與 `quit`（沒有 SCRIPT ERROR）、新 `tools/story_acceptance.gd --all`。發行匯出 `tools/export_release.ps1`（PowerShell 5.1，UTF-8 BOM 要保留）→ `../JY-Mini-OL-Release`。每次測完確認沒有殘留 godot 行程；不得動到擁有者自己在 `%APPDATA%/Godot/app_userdata/JY-Mini OL` 的世界與設定檔。

---

## 10. 交付與整合

1. 各 WP 交付：變更檔案清單、新測試通過數、`# STORY_PLAN 缺漏` 清單、【待考證】清單。
2. 整合順序：WP-ENGINE Day-0 → WP-AMBIENT、WP-UI、內容碎片並行 → WP-MERGE → 整合者寫 bot 與驗收 → 回歸 → README（新增「江湖事件」一節：每條任務去哪裡接、時辰限制、伺服器選項）→ GDD §8 同步（§1.4 表）→ 發行匯出。
3. 整合紀錄寫在本文件 §12（整合者）。

## 11. 開放問題（擁有者決定；預設值已寫在 §1.3）

1. 遊蕩惡人夜遊（D13）是非原作延伸；不要的話把 `wanderers_enabled` 關掉，白天定點行為照舊。
2. 價格／拒絕反應（D15）是非原作；可改成 `"FLAVOR"`。
3. 系統【江湖傳聞】（D14）是非原作；可關。
4. 九陰白骨爪（師命難違）要不要做（D9）。
5. 劉二爺（下）的發布日期不明（最早 2004 年可證），目前當 1.0A 做（`src: later`）。
6. 劉二爺（上）的給予者：2001 攻略「劉公子」vs 2004 攻略「衡山弟子」（D3 選前者，兩個 NPC 都放）。
7. 靜觀的稱呼（師姐／師太，D17）。
8. 陳家洛要不要依座標搬到西夏西南城外（D20）。
9. 葉二娘 1.0B 時是否搬到大理裝備商旁（目前留在西夏）。
10. 行俠仗義的冷卻長度（1 遊戲日，【設計提案】）。
11. 全真教討賊書、峨嵋回部短劍要不要做（第三輪審查：預設延後，見 §1.2）。
11a. 第四輪審查的【設計提案・非原作】預設：大理出生的新手歡迎風聲優先講西夏的雲兒（`RumorSystem.WELCOME_PREFER`），離給予者 12 步內的事件權重 ×2；同一句環境句對同一個人 15 分鐘（真實）內不重複（`AmbientSystem.LINE_NO_REPEAT_REAL_S`；荒野只有一句的地區就安靜下來，不另寫新句）；`villain_warn_s` 預設照舊 3 秒；新手的支線選擇（武介山、驛站送信、剿滅山賊加選項）不做。
11b. 路痴的礦工、運鐵、出外抓毒物、七毒（楚禮子）、辛勤的程薇、冷凝劍事件要不要做（第四輪審查補列：預設延後，理由見 §1.2）。
12. 天龍寺前的李莫愁（`q_qz_limochou`）：天龍寺不存在，放在洱海岸；一次性、輸了可以重打（預設）。
13. 依性別稱呼的佔位字（`{honorific}` 兄台／姑娘、`{shaoxia}` 少俠／女俠、`{shidi}` 師弟／師妹、`{gege}` 大哥／姊姊；【設計提案】）。
14. 新手第一次走上西大街一定聽到惡人警告、新角色第一次登入送一則自己接得了的風聲、事件風聲依地區加權、站久了也會聽到閒話（都是【設計提案・非原作】，跟著 `ambient_lines`／`rumors_enabled` 開關）。
15. 具名人物的招式（鱷嘴剪、九陰白骨爪、八臂神劍、胡家刀法…）：取材原著，威力照原本共用的怪物招式（平衡不變）【設計提案】。

## 12. 整合紀錄

2026-10-19（整合者；擁有者睡覺中、已預先授權，需要決定的事都選了預設值並列在交付報告）：

1. **WP-MERGE 之後的接縫修正**
   - `server/quest_system.gd`：`FIGHT` 目標可以帶 `npc`＋`dialogue`（`q_xingxia` 的強盜、`q_hs_spy` 的勞德諾）。原本只有 TALK／DELIVER 會在 NPC 身上出現入口，這兩個碎片的寫法讓強盜「交談也沒有對話」、任務卡死。現在交談直接開那段對話，選項裡的 `fight` 開打；逃走後可再交談重打；打贏後不再有入口。新增 `tests/unit/test_world_story_integration.gd`。
   - `ui/game/panels/system_panel.gd`：去過「特殊開關」頁再換到「江湖傳聞」頁，下一次角色表推送時 `apply_sheet` 把已釋放的開關按鈕轉型成 `CheckButton` → SCRIPT ERROR。先檢查 `is_instance_valid` 再轉型。
   - `tests/bots/m1_playthrough_bot.gd`：`quests_done` 改成 `[{ id, name, chapter, outcome_label, n }]`（§4.14），第 8、11 步改用 `_quest_done(qid)`。
   - `tests/unit/test_world_battle.gd`、`test_world_move.gd`：舊任務狀態 `counts`／`done:int` 改讀新形狀（`objs.o`、`QuestState.done_count`）；這兩個測試原本「通過」但中途 SCRIPT ERROR，後半斷言沒跑到。
2. **故事驗收**（§9.2）：`tools/story_acceptance.gd`（協調器＋worker 子行程）、`tests/bots/story_bot.gd`（玩家驅動器）、`tests/bots/story_duo_bot.gd`（雙人＋活的江湖）。作法見 README「故事驗收」。
   與 §9.2 的差異：主機與玩家在同一個 worker 行程（同 §9.2「雙人在同一行程開兩個 session」的作法，所有動作照樣經 `WorldServer.handle_intent`），不開 ENet；時間用 `WorldServer.advance` 推進，`--time-scale` 不適用。
   bot 對 `test_plan` 的補位（碎片的路徑沒寫到，**不改資料**）：`accept@` 後的 offer 對話沒寫選項 → 在對話樹裡找通到 `accept` 的選項自動選（`q_yuner`）；合成的「（繼續）」自動按；
   任務條件沒寫在 `setup` → 前置任務照它的 `test_plan` 先走（`q_liu_jinpen_2` 的 `q_liu_jinpen`），旗標／武功／屬性門檻用 `debug_set`（`q_sl_riyuebian` 的 `sl_tongren_passed`，WP-MERGE 決定 4 加的條件）；
   `setup.after` 先跑再套本路徑的 `setup`（`q_hs_spy` 的 `after: q_hs_jianqi:qizong` 會把華山心法設回 30）；bot 角色實戰 400（武功上限 11 級；`q_xh_huagong` 韋小寶教的諂媚 10 級受實戰上限限制，0 實戰的角色永遠卡在 STATE）。
   結果：40 條路徑＋duo＋ambient 全部 PASS（約 10 秒）。
3. **介面**：`tests/ui/ui_playthrough.gd` 新增第 18 步（雲兒，選李台安那條 `test_plan`）：「詳談」開任務對話視窗、編號選項與「（繼續）」、任務窗章節／階段／目標、已完成分頁的結局名、系統窗「江湖傳聞」頁。
4. **文件**：README 新增「江湖事件」與「故事驗收」兩節、UI 驗收說明補故事包；GDD §8.2／§8.3 照 §1.4 同步。
5. ~~仍未交付~~（審查修正已補，見 6）：`ev_yangkang`、`ev_chendabao`、`ev_misc_2001`。戰鬥掉落不看 `drops[].requires`（`core/battle/battle_rewards.gd` 凍結），任務素材只透過房間動作的戰鬥取得時無影響。
6. **審查修正（2026-10-19，三份審查：原作忠實度、敘事、引擎／介面）**
   - 引擎：獎勵 `learn_add`（`{ skill: n }`，在目前等級上再升 n 級）與 `learn` 動作的 `add`；`var` 動作的 `random`（從清單隨機取一個值）；
     任務狀態 `given`（這次任務交給玩家、還沒收回的物品；放棄或失敗時全部收回，存檔往返）；新條件 `quest_not_done`、`quest_not_active`；
     `QuestSystem.can_accept`（公開）；`ws.world.quest_first_outcomes`（全服第一位的結局，傳聞的 `{outcome_label}`）。
   - 活的江湖：`data/ambient.json` 的**交談列**（有 `talk` 欄位：`npc`、`talk` 模板、`requires`、`periods`、`priority`；`AmbientSystem.talk_key` 先找它，再找時辰變體）；
     `AmbientSystem.talk_greet`（同一位 NPC 同一種態度只招呼一次，記在 `ch.ext.ambient.greeted`）；預告傳聞只放線上有人接得了的任務；
     新手遇上夜遊惡人不開打、改送威嚇（`wander_newbie[_<wid>]`，每惡人每遊戲日一次）；`GameHost.npc_here` 也問 `WanderSystem.npc_shown`。
   - 資料：補上 `q_yangkang`、`q_chendabao` 與 P2 七條（`q_mailu_shangren`、`q_liangfa`、`q_qingwei`、`q_xd_caihua`、`q_qz_paotui`、`q_qz_jiangqingrui`、`q_qz_wangchuyi`）；
     日月鞭法拿掉沒有來源的銅人陣門檻（藏經閣在取經階段特准進入）、佛經改回隨機；孤鴻子的打聽對象改成 2001 攻略的王大富人／李裁縫；
     殷六俠補上後期攻略的俠義 40 門檻；連環殺人案的淫賊移到新房間 `ym_qiaoxia`（關外橋下）；每個故事任務結局都標 `src`，混了後期或提案數值的用 `field_src` 逐欄標（lint 檢查）；
     去掉任務文字裡的驛站馬車；指路照真正的出口；有選擇的任務結局有差別；`rumor_chat_inner_min` 預設改成 80（照原作）。
   - 介面：任務窗沒選中的列設字色；任務對話視窗照 AUTHENTIC_UI_SPEC §8.7（680×416、立繪 180×240、名牌，NPC 自己說話時不重複顯示說話者）。
   - 驗收：`tests/unit/test_world_story_review.gd`；story bot 新步驟 `set_var:<qid>:<name>=<value>`；UI 驗收第 19 步拍 `villain_prompt`；
     `SceneRouter.about_to_quit` 讓 UI bot 在任何結束路徑都印最後一行（沒有結論就以 0 結束會改成失敗）；debug `option:<key>`（限幾個整數選項，測試用）。
7. **第三輪審查修正（2026-10-19，三份審查：原作忠實度、敘事、引擎／介面）**
   - 忠實度：藍鳳凰拆開年代（第一次 2001「升一級」；再做 = 台免的熟練 +50，`repeat` 結局；新條件 `skill_max`，基本毒術 < 30 才接得了，src later）；
     血海魔功 1.0A 列改用 2001-08-18 門檻，2002-08 的數字移到新檔 `data/patches/xkd.json`；新任務 `q_qz_limochou`（天龍寺前的李莫愁，+50 歷練與名聲）；
     全真教討賊書、回部短劍列入 §1.2（刻意延後）；連環殺人案的土匪大當家移到大理城西（`dlw_desertcave`），重複標 `repeat_src: proposal`，D2 改寫；
     GDD §8.2 藍鳳凰、孤鴻子列照資料；瑩月兒的描述與 src 照研究（藍鳳凰的幫手、藍依涵的朋友、梁發的意中人）；阿大改標 verified。
   - 引擎：放棄（或失敗）不能重領中途獎勵（`reward` 動作與 `learn` 的 `add`；`active[qid].paid`、`quests.paid[qid]`，完成時清掉；存檔往返）；
     `GameHost.tell` 與任務對話補依性別的稱呼佔位字；遊蕩惡人每人自己的警告句（`villain_warn_<wid>`，提示條另顯示一行）、
     對話中被略過的玩家在對話結束後再判定一次、每位玩家的冷卻到期就清掉；環境句列 `first_visit`、站著不動也會擲閒話；新角色第一次登入的歡迎風聲、預告依地區加權。
   - 敘事：具名人物各有招式（`mon_eyujian` 等 17 套僅限怪物的武功）；公開場合的 NPC 不分性別、初次見面不用角色名當稱呼；大理城的故事開頭（雲兒、文泰來的閒話）；
     阿寶夜裡的結局台詞；「地圖左上方」改成江湖地名（`zn_river` 改名「終南山西北河灘」）；指路方向與房間名修正；長途指路在任務窗分段；大理沒有肉攤。
   - 介面：任務對話視窗改成和 NPC 對話框同一種水墨底、沒有標題列；江湖傳聞頁與伺服器設定說明不再顯示【設計提案】字樣；伺服器設定選項區加高；李台安改用藥鋪的立繪（年紀不合，列入 ART_REQUEST）。
   - 驗收：`tests/unit/test_world_story_review3.gd`；`q_lanfeng` 新增 repeat 的 `test_plan`、`q_qz_limochou` 的 `test_plan`。
