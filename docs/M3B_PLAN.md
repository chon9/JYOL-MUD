# M3b 實作計畫：丐幫與京城（神鵰大俠 1.0B）、絕情谷、高昌雁門關、錢莊鏢局組織、生活技能、未做的 2001 事件（M3B_PLAN）

> 版本：2026-10-20（開工版）。協調者撰寫；實作中只由協調者（整合者）修改本文件。
> 上游：GDD §3、§7、§9、§10、§13 M3 列；WORLD_2001（地理，仍然有效，本文件只寫增量）；M1_PLAN、M2_PLAN、M3A_PLAN（門派框架，**新增門派＝資料＋碎片**）、STORY_PLAN（任務／對話引擎，§4 的列格式綁定）。
> 研究：`docs/research/verified_research.md` 的「M3b 研究」章（以下簡稱「研究」；分節：丐幫、京城與範圍、明教高昌雁門關、經濟組織生活技能、未做的 2001 事件）。研究與本文件不一致時，以本文件的「擁有者決定」（§1.3）為準，並在 `src_note` 寫明。

---

## 0. 文件地位與通則

### 0.1 本文件是契約

M3b 由 4 個機制工作包（WP-SECT、WP-ECON、WP-ORG、WP-UI）與 6 個內容工作包（WP-C-<key>）**同時**實作，之後由 WP-MERGE 單獨合併資料，最後由整合者驗收。實作者之間不溝通。規則沿用 M3A_PLAN 0.1：

1. 本文件中的**檔案路徑、類別名、函式簽名、字典欄位、intent、事件 key、原因碼、伺服器選項 key、規則 key、存檔欄位、資料列 id、房間 id、出口方向、碎片檔格式**都有約束力，不得改名或改型別。
2. 沒寫的內部細節由各 WP 自行決定。
3. 優先順序：本文件 > STORY_PLAN > M3A_PLAN > WORLD_2001 > M2_PLAN > M1_PLAN > GDD > TECH_ARCH。偏差列在 §1.4。
4. 發現缺漏：照「最不意外」實作，程式裡寫 `# M3B_PLAN 缺漏：……`，交付說明列出；**不要**改別人的檔案。

### 0.2 標記

沿用 GDD 第 0 章與 M3A_PLAN 0.2：【已證實】【後期版】【待考證】【設計提案】【設計提案・非原作】。`era` = 這個東西在哪個版本**已經存在**；`src` = 這一列細節的出處（`verified`／`later`／`proposal`）。本文件新增的數值一律【設計提案】（`src: "proposal"`），有研究依據的寫【已證實】並在 `src_note` 註明出處（例：`"src_note": "研究 丐幫：2001-12-01 n424_340813 瘋魔 太祖50 心法30 乞討30 二袋"`）。
**1.0B 的判定**（研究「經濟組織生活技能」第 1 條）：官方「第二片資料片」頁列出的丐幫、京城、絕情谷、工匠、門派監獄（含捉拿公敵）、合體技、玉女素心劍一律 `era: "1.0B"`，不能當 1.0A。錢莊、鏢局、組織、其他 10 種生活技能是 `1.0A`（細節多半 `src: "later"`）。

### 0.3 全域規則

M1_PLAN G1–G10、M2_PLAN H1–H6、M3A_PLAN K1–K6、STORY_PLAN §0.3 全部繼續有效（主機權威、離線同一路徑、`core/**` 純邏輯、文字放資料、JSON 數字轉 int、**不 commit**、測完關掉 godot 並用 `tasklist /FI "IMAGENAME eq Godot*"` 確認、新增 `class_name` 後先 `--import`、不新增 Autoload、不改 `project.godot`、不新增 `@rpc` 方法、新系統容錯接線）。M3b 另加：

| # | 規則 |
|---|---|
| L1 | `Protocol.VERSION` **維持 5**：M3b 只新增 intent、事件、選單與角色表欄位，RPC 簽名不變（比照查看偵察「純新增不升版」）。舊客戶端看不到新功能但不會壞；內容不同由 `content_hash` 擋。 |
| L2 | **一個檔案只有一個擁有者**（§9.1）。內容只寫在 `docs/m3b_staging/<key>.json`；**只有 WP-MERGE 能改 `data/*.json`、`data/maps/*.json`、`data/patches/*.json`、`data/art.json`**（例外：`data/rule_profiles.json`、`data/server_options.default.json` 歸 WP-SECT）。機制 WP 需要的資料列（模板、NPC、物品、任務）寫成 `_sect.json`、`_econ.json`、`_org.json` 碎片。 |
| L3 | 新主機系統（`BankSystem`、`EscortSystem`、`OrgSystem`）照 M3A K3：`extends RefCounted`、`_init(p_host: GameHost)`、`GameHost` 以路徑 `load()` 建立（WP-SECT Day-0 寫好載入行），失敗時為 `null`，所有呼叫點先判斷 `!= null`（或用 `host.m2_call`）。 |
| L4 | **測試資料隔離**：所有測試、bot、驗收只能寫測試根目錄（`DataRoot.test_root()`，開發時 `K:\Project\JY-Mini-OL-Work\testdata\`）或 `--data-root=<K: 上的絕對路徑>`；**絕對不碰擁有者存檔**（`JY-Mini-OL-Work\userdata\`、`JY-Mini-OL-Release\userdata\`、`appdata_old*`）。不得寫 C:（不用系統暫存、不用 `%APPDATA%`、不用 `user://` 當測試根）。截圖放 `K:\Project\JY-Mini-OL-Work\shots\`、log 放 `...\logs\`、暫存放 `...\tmp\`。 |
| L5 | 新 id 一律用碎片前綴（§3.6 表），不得撞到既有 id。 |
| L6 | 新地區遵守 WORLD_2001 §1.4 與 M3A_PLAN §2.3 的**新手安全規則**；1.0B 世界的出生城多了京城，`check_newbie_routes` 從三座出生城檢查（§3.4）。 |
| L7 | **1.0A-only 世界必須完整可玩**：所有 `era: "1.0B"` 的列、出口、patch 都要在只開 1.0A 時被濾掉而不留斷頭（lint 對每個 era 閉包各跑一次）。 |
| L8 | `tools/export_release.ps1` 是 PowerShell 5.1、UTF-8 **帶 BOM**：M3b 任何 WP 都不改它；萬一要改，保留 BOM。 |

### 0.4 Godot 指令

```bash
G="K:/Godot/Godot_v4.6.3-stable_win64_console.exe"
"$G" --headless --path . --import
"$G" --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=m3b]
"$G" --headless --path . --script res://tools/data_lint.gd -- --no-steam
"$G" --headless --path . --script res://tools/balance_sim.gd -- --no-steam --runs=500
"$G" --headless --path . --script res://tests/ui/ui_playthrough.gd -- --no-steam
"$G" --headless --path . -- --no-steam --offline --world=w_m3b_m1_10a --eras=1.0A --profile=m1bot --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
"$G" --headless --path . -- --no-steam --offline --world=w_m3b_m1_10b --profile=m1bot --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
"$G" --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/m3a_acceptance.gd -- --no-steam
"$G" --headless --path . --script res://tools/story_acceptance.gd -- --no-steam --all
"$G" --headless --path . --script res://tools/m3b_acceptance.gd -- --no-steam [--only=gaibang] [--timeout=2400]
"$G" --headless --path . --script res://tools/net_smoke.gd -- --no-steam
"$G" --headless --path . -- --no-steam --offline --world=close_x --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=wm --time-scale=50 --quit-after=300
"$G" --headless --path . -- --no-steam --offline --world=close_y --profile=closebot --bot=res://tests/bots/close_mid_battle_bot.gd --close-mode=quit --time-scale=50 --quit-after=300
```

（bot 指令沒帶 `--data-root` 時自動用測試根目錄，README「測試」節。）

---

## 1. 範圍

### 1.1 M3b 要做（逐項打勾；括號是負責 WP）

1. **1.0B 的 era 決定與遷移**（§2）：新世界預設開 1.0B；既有世界保留存檔；主機可在伺服器設定開 1.0B；1.0A-only 世界照常（WP-SECT；文件整合者）。
2. **丐幫**（第 11 派；era 1.0B）：山門走得到、拜師、2001 的一二階武功與門檻、門派技能**乞討**（向 NPC 乞討來練、限制武功）、**袋位**（一袋、二袋，月聚會升袋）、小黃狗追咬、不能運鏢、京城買不到兵器防具、門規（同門相殘、善惡 < 0 停止傳功）、毒牙觸發（`POISON_FANG`）（WP-SECT 機制；WP-C-gaibang 內容）。
3. **完整京城**（era 1.0B）：街坊、錢莊、中華鏢局、衙門、**京城監獄**、兵器鋪、打鐵舖、布莊、藥鋪、紫禁城外、**天地會**（棺材鋪暗門與香堂、入會任務、會眾商店）、北門；1.0B 京城可出生；南郊接回原有接點（WP-C-jingcheng）。
4. **監獄一般化**：`jail_scope: "CAPITAL"` 的京城監獄收押違反門規與被抓的公敵；**捉拿公敵**指令（1.0B，2001-10-05）（WP-SECT）。
5. **絕情谷**（era 1.0B）：谷口、情花林（情花毒）、石屋（丹房、書房、劍房）、斷腸崖、地牢與鱷魚池；救柳姑娘任務（WP-C-jueqinggu）。
6. **明教、高昌、雁門關、馬王洞**：1.0A 的明教 NPC（范遙；張無忌已在）與「入口任務是騙局」的處理（不能拜、不做入口任務）；高昌（室外、計老人居、迷宮 6 層、機關人）；雁門關補完（關外苗人鳳、阿朱、刻字石碑、拓印與鬥酒任務）；馬王洞（WP-C-mingjiao_gaochang_yanmen；審查改 **1.0B**：所有來源都在 1.0B 期間或以後，見 §13.6）。
7. **錢莊**（存錢與倉庫，三城通用）、**鏢局**（托鏢寄物、拿取貨品、保鏢護送工作）（WP-ECON 機制；`_econ.json` 店面與保鏢任務）。
8. **組織**（創立連署、加入、退出、開除、位階、封號、移交、解散、組織頻道）；總壇、攻城、競標、傭兵留 M5（WP-ORG）。
9. **生活技能擴充**：挖礦、打鐵、鑄劍、工匠（1.0B）、織布、裁縫、獵人，材料 → 成品的鏈接進經濟（店家收購、任務用料）；種田加麻、棉；樵夫加燒炭（WP-ECON 引擎；WP-C-lifeskills_content 內容）。
10. **未做的 2001 事件**：運鐵、七毒、出外抓毒物、冷凝劍、辛勤的程薇、獨居老人等（§8.3 清單），用故事引擎資料（WP-C-story_missing）。
11. **美術需求** `docs/ART_REQUEST.md` §8「第五批」（WP-MERGE）。

### 1.2 M3b 不做（M3c、M5 或更後）

- **M5（神鵰期社交）**：婚姻、傭兵、總壇、競標、攻城、工匠的刨刀半套（總壇萬用工匠機）、組織同盟／宣戰（與總壇一起做）、合體技的婚姻加成。
- **M3c 整合註（2026-10-20，M3C_PLAN §1.4 F5）**：下列的 `ATTACK_SECT_NPC`（含武當滅派、孫婆婆、恆山知客、對丁春秋／血刀老祖下手）與神兵 PvP 轉移已在 M3c 完成；其餘照 M3C_PLAN §1.2 仍延後。
- **M3c（M3 剩餘；本文件不實作，資料可先放並鎖住）**：懸賞與賞金獵人牌照（捕快、衙門懸賞榜）；神兵 PvP 轉移；合體技與玉女素心劍法（資料列保持 `requires` 鎖住）；輕功指令「輕」與 2001「閃」按鈕；`ATTACK_SECT_NPC`（PK 丁春秋、攻擊血刀老祖、武當滅派、攻擊孫婆婆、攻擊恆山知客弟子；`sect_rules.event` 仍保留）；NPC 執法者野外追捕；剩下的門派武功鏈（全真重陽劍法、靈鷲八荒、星宿煉毒、血刀恐嚇與血池、滅絕 cap-1 自修）；峨嵋四象掌、全真空明拳；門派比武與武林大會；黑龍潭的 1.0B 內容（九尾靈狐、瑛姑；研究無法重抓）；劫鏢（2001-11-15，機制【待考證】）；**血魔刀法**（M3A_PLAN D7 延後「屬 1.0B（要京城）」；官方第七話 2001-11-22 的標題之一，內容【待考證】；目前沒有任何資料列，M3c 建立）；**審查 4 補列（研究【已證實】有記載、M3b 沒做，延後 M3c；不是「待考證」）**：京城半仙（消 PK值，2001-11-02，1.0B；研究「PK reducers (半仙/天師) are 1.0B」——怎麼消、要多少錢沒有記載，PK值遞減機制也要先擴充）；新物品無敵烙跑鞋（任何非任務戰鬥 100% 逃跑，含 PK）與夜明珠（永久夜間照明）（官方 1.0B 頁 index_jy1-2-6-x；要戰鬥逃跑與夜間照明兩個新機制）；丐幫可做的跑腿：柯鎮惡 → 郭靖（+5 名聲 +20 歷練，2001-11-03；2001-11-12 有人接不到；資料裡沒有柯鎮惡與郭靖，2001-09-04「郭靖目前沒有開放」，兩人的位置【待考證】）、三八紅（大理織布坊）→ 西夏豬哥義（+8–10 名聲；當時拒絕了丐幫玩家，給誰做、送什麼【待考證】）、武林帖約每 3 天一次（2001-12-03；給的人與內容沒有記載）、2001-10-29 提到的「英雄帖 1 萬」（只有一句）。西夏老人送藥（每天一次 +1/+1）已併進 `q_sm_dujulaoren`（審查 4）。
- **更後**：丐幫三袋以上的任務、降龍十八掌／降龍十八缺三／打狗棒／逍遙遊／陰山掌／迴風拂柳拳（2002 以後）；明教拜入（M6，懷舊版）；畢業（M9）；十大技能等佈告欄排行；生活技能合計上限 400 與日月星冰（至尊版）；錢莊容量 10000（M10）。
- 不改任何既有戰鬥公式（例外：§5.1.7 的毒牙觸發與 D12 觸發消耗統一，金檔重產）。

### 1.3 擁有者決定（擁有者已預先授權本里程碑；以下是選定的預設值，建造者照做）

| # | 決定 | 理由（研究） | 本文落點 |
|---|---|---|---|
| O1 | **新世界預設 `enabled_eras: ["1.0A","1.0B"]`**；`--rule-preset=classic_strict`（2001-08 規則）的新世界預設只開 `["1.0A"]`；`--eras=` 永遠優先。既有世界保留存檔裡的 era。 | 神鵰大俠 2001-09-28 上線，仍是 2001 的經典版；`classic_strict` 模擬 2001-08 | §2 |
| O2 | 既有世界由主機在「伺服器設定」打開 1.0B：**只能開、不能關**，**下次開服生效**（存 `pending_eras`），不在執行中重建索引 | 執行中重建房間索引會打斷戰鬥與護送；關掉 1.0B 要搬人，只能離線改 `world.json`（WORLD_2001 §8 的搬移規則照舊） | §2.3 |
| O3 | **1.0B 京城可出生**（`birth_allowed: true`、`birth_room: "jc_square"`） | 研究 丐幫：2001-11-06「選京城為出生地」；官方後期出生地分組 | §3.1、§2.4 |
| O4 | **丐幫山門在京城北郊的山路中段**（`gaibang` [884,122]），京城廣場走 5 步；山門**沒有查小鏞**、沒有商人 | 「山路中間」「跑上10分鐘」「離馬王洞不遠」「沒有查小鏞」（2001-10-09/10-24/11-12）；DIAO「總舵在京城」是預告 | §3 |
| O5 | 丐幫男女皆收；入派只要 無門派＋非丐幫公敵／叛徒（框架共通的叛派規則）；**不設善惡入派門檻**（M3b 審查 3：研究找不到「非惡」的出處，「善惡 ≥ 0」入派原列【後期版】是錯標，實為【設計提案／待考證】，已從 `join_requires` 拿掉）；停止傳功 善惡 < 0【後期版官方】；門規只有同門相殘；**沒有執法者** → 違規一律 `BAN` | index_jy2-6-4、jy2-4-2「執行違反門規處罰的師父：無」 | §4.1 |
| O6 | 丐幫武功只做 2001 有記載的：一階 丐幫心法、太祖長拳、太祖棍法、六合刀法、銅鎚手、滿天花雨（基本暗器，【待考證】單一含糊來源）；二階（**要二袋**）纏絲擒拿手、瘋魔杖法、擒龍功、混天功、蓮花掌。二階門檻用 2001-12 的形式（前置武功 50、心法 30、乞討 30、二袋），只有瘋魔的數字【已證實】，其他【設計提案】比照；二階上限 60（瘋魔【已證實】，其他比照）。降龍、打狗、逍遙遊不做 | 研究 丐幫：2001-10-09 列表、2001-12-01 | §4.1、§10 |
| O7 | **乞討**：陳長老消點只教到 10 級（夠學銅鎚手）；之後只能對 NPC「乞討」練（耗精、神）；乞討成功有小額施捨【設計提案】 | 2001 練法是乞討；給 10 級是為了一階武功可學（比照 M3a 俞岱巖教俠義到 20） | §5.1.2 |
| O8 | **袋位只做一袋、二袋**（2001 已證實）；三袋～七袋是 `era: "xkd"` 的資料列（不會出現在 1.0B 世界）。升袋在「聚會」生效：伺服器選項 `gb_assembly` 預設 **`DAILY`**（每個遊戲日辰時聚會【設計提案・偏離原作月初】），可改 `MONTHLY`（每遊戲月 1 日，忠實） | 原作「等一號」；但主機離線時世界凍結，月初可能要等 30 次開服 | §5.1.1 |
| O9 | 小黃狗：丐幫弟子在西夏、大理街上 15%、京城 5% 機率被追咬（審查 4：預設不免追——「乞討 ≥ 30 免」只見於後期，2001 門檻【待考證】，見 R4-3）；打贏一隻得 5 學點【已證實】 | 2001-10-24「一次有5點」；狗弱 | §5.1.3 |
| O10 | 「京城買不到兵器防具」照做：京城兵器鋪拒絕賣給丐幫弟子（`shop.refuse_if`）【已證實 2001-10-09；可能是 bug】；「大理西夏以外不能買賣」不做 | 研究 丐幫 restrictions | §4.8 |
| O11 | **明教不能拜、不做入口任務**；只放 1.0A 明教 NPC：范遙（西夏城北山坡，交談只回一句冷話）、張無忌（已在） | 2001-08-14 入口法是騙局（08-17 證實）；決戰光明頂官方也說不開放拜師 | §8.3 |
| O12 | **監獄位置**（2026-10-20 審查修正）：選項 `jail_location` 預設 `AUTO` = 京城監獄房間生效時**被抓的公敵**關京城監獄（不論該派有沒有執法者），**違反門規仍關各派思過處**（1.0A【已證實】；`breach_jail_resolved`）。`CAPITAL`：違規也關京城監獄（要有執法者才坐牢，否則 BAN）。`SECT`：全部思過處。京城監獄出獄送到京城衙門。京城監獄的位置與是否取代思過處【待考證】 | 官方門派監獄頁（位置未寫【待考證】）；GDD 6.5「1.0-B 改用京城監獄」 | §5.1.4 |
| O13 | **捉拿公敵**（1.0B）：只有本派弟子能抓本派公敵、可組隊、在可 PK 的房間或本派地盤、目標不能是 500 實戰以下新手；抓的人不加 PK 值、殺氣、善惡；目標可逃 | 官方門派監獄頁；「可逃」與地點【設計提案】 | §5.1.5 |
| O14 | 組織：創立要 幫主名聲 ≥ 150、連署 `guild_signers` 人（預設 3，原作 30）每人名聲 ≥ 20、**一萬兩**手續費【設計提案】；在三城衙門的「書吏」登記；連署人自動成為成員【設計提案】；成員上限 50【設計提案】；位階 5 級名稱由幫主自訂 | 官方組織頁（30 人、20、150） | §5.3 |
| O15 | 錢莊三城**共用一個帳戶**（`ch.bank`）【待考證：原作是否分城】；容量 `bank_capacity`（1000 件）；存款上限 600 萬【後期版推得】；不收保管費；存在錢莊的食物不腐壞【設計提案】；任務物品、裝備中的物品不能存 | 研究 錢莊 | §5.2.1 |
| O16 | 托鏢：寄給任何角色名、選目的城、運費 20 兩 + 每重 2 兩、送達時間依城際表（西夏↔大理 4 時辰…）【設計提案】；30 遊戲日沒人領就退回寄件城；不會被劫【待考證】 | 官方鏢局三功能；細節無資料 | §5.2.2 |
| O17 | 保鏢＝可重複的護送任務（故事引擎 `ESCORT` 目標）：護送鏢車到別城鏢局，給銀兩與名聲；丐幫不能接 | 「保鏢與驛站送信皆能提升名聲值」；2001「丐幫不能運鏢」 | §5.2.3 |
| O18 | 生活技能保留既有 4 種的名稱與 id（種田、樵夫、釣魚、廚師；官方名 農夫、伐木、捕魚 寫在 desc）；新 7 種用 挖礦（官方「採礦」寫在 desc）、打鐵、鑄劍、工匠、織布、裁縫、獵人；上限各 100【後期版】；不做合計上限 | 研究 生活技能清單 | §4.5 |
| O19 | 工匠（1.0B）只做鋸子那一半（隨地用，做木製兵器、斗笠、木簪）；刨刀與總壇設施 M5 | 官方 1.0B 工匠頁 | §4.5 |
| O20 | D12（M3a 延後）：毒牙與所有門派技能觸發的精／內力（神）消耗**統一**，含 M1 的 DEFENSE、RECOVER；`tools/regen_battle_golden.gd` 重產金檔並在交付說明列出差異 | M3a D12 延到 M3b | §5.1.7 |
| O21 | 咸楓子（出外抓毒物）與楚禮子（七毒）**共用一組大地圖毒物點**（推翻本檔舊註記） | 研究：5 點中 4 點吻合 | §8.3 |
| O22 | 黑龍潭 1.0B、劫鏢、攻城大師等只有預告的 1.0B 事件：不做（M3c）；1.0B 事件只做研究有名字且能用京城既有 NPC 收尾的 3 條（李大嬸找小保、靈犬小黃、愛好礦石的張員外），全部【設計提案】 | 研究：第七～九話只有預告 | §8.3 |

### 1.4 與 GDD／既有文件的偏差（M3b 決議；整合者同步 GDD 與相關文件）

| # | 偏差 | 理由 |
|---|---|---|
| E1 | `data/server_options.default.json` 的 `enabled_eras` 改 `["1.0A","1.0B"]`；WORLD_2001 §6.1「維持 `["1.0A"]`」作廢；README「預設世界沒有京城」改寫 | O1 |
| E2 | 京城 1.0B 可出生（WORLD_2001 §6.3「仍然不能出生」作廢） | O3 |
| E3 | GDD §1.2 註 1、§13 M3 列「明教 NPC、地區與入口任務」改成「明教 NPC 與事件（不能拜、沒有入口任務）」；研究舊條「明教 entry content existed by 2001-08-14」作廢 | O11 |
| E4 | GDD §7.2 `mawang` 從「華山」改到「雁門關附近」；`m_mawang` 氣改 2000【待考證：17173 gaoshou/25 只列「馬賊王」2000 HP】 | 研究 馬王洞（2002-01 山洞介紹＋2001-11-12「離馬王洞不遠」兩個來源指向同一帶）；查證者對單一來源的保留寫進 `todo_verify` |
| E5 | GDD §7.2 `gaochang` 機關人 20 萬氣作廢，改 3000 為基準（gaoshou/25） | 研究 高昌 |
| E6 | GDD §3 丐幫袋位表標【後期版】的 1300 改 1200（2002）並註明 1.0B 只有一、二袋 | 研究 丐幫 袋位 |
| E7 | M3A_PLAN §1.2 婚姻「M3b 或更後」→ M5；ART_REQUEST 明教、桃花島服裝 → M6／M7 | GDD 里程碑表 |
| E8 | 雁門關首次出現日期以 2001-07-18 為準（tishi.htm），不是 07-11 | 研究 雁門關 |
| E9 | 研究 1072 行（藍鳳凰預告只有 17173）、975 行（毒物點不能合併）更正；「可憐的韓后」→「可憐的韓玲」；第五話 2001-08-16 | 研究 未做的 2001 事件 |
| E10 | ART_REQUEST.md:384 的尋找楊康、陳大寶「還沒做好」改成已完成 | 研究 |
| E11 | 生活技能「工匠＝1.0B」從「研究結論，未再複查」升為【已證實】（官方第二片資料片工匠頁）；GDD 開放問題 17 關閉 | 研究 |
| E12 | GDD §8 拓印、蕭峰鬥酒「找不到 2001 出處」改【已證實】（other.htm）；開放問題 10 關閉 | 研究 雁門關 |
| E13 | GDD 6.5「1.0-B 改用京城監獄」改成「`jail_location: AUTO`：1.0B 有京城監獄時被抓的公敵關京城，違規仍關各派思過處（審查修正）」 | O12 |

---

## 2. Era 決定與遷移（WP-SECT 程式；整合者文件）

### 2.1 預設

- `data/server_options.default.json`：`"enabled_eras": ["1.0A", "1.0B"]`。
- `data/rule_profiles.json`：每列可有選填 `default_eras`（Array）。`classic_strict` 加 `"default_eras": ["1.0A"]`，其他三列不加。
- 新建世界的 era 決定順序（`autoload/world_server.gd` 新世界分支）：`--eras=` → 規則預設列的 `default_eras`（`--rule-preset` 或預設 preset）→ `server_options.default.enabled_eras`。結果經 `DataLoader.validate_enabled_eras` 檢查後寫進 `options.enabled_eras` 與 `world.enabled_eras`。
- 既有世界：`world.json` 的 `enabled_eras` 永遠是權威；`options.json` 補預設值時**不得**覆寫 `enabled_eras`（現有「只補缺的」行為已滿足，加單元測試鎖住）。

### 2.2 1.0A-only 世界的保證（L7）

- `era: "1.0B"` 的：地區 `jingcheng`、`jingcheng_wild`、`jingcheng_north`、`gaibang`、`jueqinggu`、`jueqinggu_dilao`；所有這些地區的房間、NPC、怪物、任務、模板；丐幫的 `sects` 列、`sect_ranks`、武功、師父；`life_carpentry`（工匠）與其配方、工具、成品列；京城相關保鏢路線與 `escort_routes`；1.0B 事件任務；1.0A 房間通往 1.0B 房間的出口（`exits[].era: "1.0B"`，WORLD_2001 §6.2 機制）。
- `capture` 公敵、`seize_enemy`、京城監獄、丐幫小黃、毒牙：程式以「資料存在與否」或 `era_enabled` 條件判斷，1.0A 世界自動關閉（`seize_enemy` 回 `era_locked`）。
- 1.0A 世界照常有：錢莊、鏢局（西夏↔大理）、組織、6 種新生活技能（工匠除外）、高昌、雁門關補完、1.0A 事件。馬王洞（含馬賊王、黃罩甲、`q_ym_mawang`）審查改 **1.0B**，1.0A 世界沒有（雁門關口沒有往西的出口）。
- 1.0A 世界 `char_create` 的出生城清單仍只有西夏、大理（由 regions 的 `birth_allowed` 與 era 自動決定）。

### 2.3 既有世界打開 1.0B（WP-SECT `admin_system.gd`；WP-UI 面板）

- `AdminSystem.EDITABLE_KEYS` 加 `"enable_era_1_0b"`（標籤「開放神鵰大俠（1.0B）內容」）。選項：`"on"`（只在目前 `world.enabled_eras` 沒有 1.0B 時出現）。值為 `on` 時：把 `"1.0B"` 寫進 `options.pending_eras`（`world.enabled_eras` 加 1.0B 後的完整清單）、存 `options.json`、廣播 `server_option_changed`（文字「下次開服生效」）。已開 1.0B 的世界，這一列顯示「已開放」且不能改。
- `WorldServer` 開服時：`options.pending_eras` 非空且通過 `validate_enabled_eras` → 寫入 `world.enabled_eras`、清掉 `pending_eras`、存檔，再 `GameData.activate`。
- 不提供關閉；README 寫明「要關 1.0B：關服後編輯 `world.json` 的 `enabled_eras`；站在京城的角色會依 WORLD_2001 §8 搬到記錄點或出生城」。

### 2.4 遷移安全

- 京城接在既有接點（`hy_foot` NE ↔ `jcw_huashan`、`sy_pines` N ↔ `jcw_songshan`，WORLD_2001 §6.3），開 1.0B 不需要改任何角色檔。
- 角色檔新欄位（§4.12）由 `Character.from_dict` 補預設（`DATA_VERSION` 2 → 3，檔案 `SCHEMA_VERSION` 維持 1，M3a 的理由不變）。
- `world.json` 新 key（§4.13）由各系統惰性建立（比照 `MailSystem`）；`SaveManager`（凍結）不需要改：它不會刪掉不認得的 key（`guilds` 本來就在 `new_world` 裡）。
- 舊世界的 `options.json` 沒有新選項 key → 補預設值（既有機制）。

---

## 3. 世界接點（2001 地圖）

### 3.1 地區

原作座標 ÷ 24（WORLD_2001 §1.1）。新地區一律 `night_closed: []`、`map: "res://data/maps/<id>.json"`；`birth_allowed` 除京城外都是 false。

| 地區 id | 名稱 | type | era | world_pos | 依據 | 擁有碎片 | suggested_xp |
|---|---|---|---|---|---|---|---|
| `jingcheng`（改） | 京城 | CITY | 1.0B | [850, 196]（不變） | WORLD_2001 §6【後期版鄰近】 | jingcheng | [0, 0]；**`birth_allowed: true`、`birth_room: "jc_square"`**（O3） |
| `jingcheng_wild`（改） | 京城南郊 | WILD | 1.0B | [850, 250]（不變） | 同上 | jingcheng | [0, 2000] |
| `jingcheng_north` | 京城北郊 | WILD | 1.0B | [862, 150] | 【設計提案】（丐幫山路，O4） | gaibang | [0, 20000] |
| `gaibang` | 丐幫總舵 | SECT | 1.0B | [884, 122] | 【設計提案】（O4；後期座標 28588,2196 → [1191,92] 超出 2001 地圖，只取「京城東北、近雁門關」的方向） | gaibang | [0, 0] |
| `jueqinggu` | 絕情谷 | WILD | 1.0B | [905, 232] | 【設計提案】（GDD「鄰近京城」；位置【待考證】） | jueqinggu | [0, 80000] |
| `jueqinggu_dilao` | 絕情谷地牢 | DUNGEON | 1.0B | [910, 240] | 【設計提案】（DIAO/2-2 鱷魚池地底迷宮） | jueqinggu | [60000, 150000] |
| `mawang` | 馬王洞 | DUNGEON | 1.0B（審查改） | [820, 96] | 2002-01-26 山洞介紹「雁門關附近、靈芝商人左方靠山」＋2001-11-12「離馬王洞不遠」；【待考證】（E4）；所有來源都在 1.0B 期間或以後 → 1.0B | mingjiao_gaochang_yanmen | [10000, 30000]（審查 4：馬賊王照 gaoshou/25「弱」降級距） |
| `gaochang_road` | 高昌古道 | WILD | 1.0A | [130, 70] | 內插【設計提案】 | mingjiao_gaochang_yanmen | [0, 10000] |
| `gaochang` | 高昌 | WILD | 1.0A | [16, 84] | 香香公主 391,2005（gaoshou/23）【已證實】 | mingjiao_gaochang_yanmen | [0, 30000] |
| `gaochang_maze` | 高昌迷宮 | DUNGEON | 1.0A | [12, 80] | jy1_2 場景表 高昌迷宮 1–6【已證實】 | mingjiao_gaochang_yanmen | [30000, 200000] |

（`yanmen`、`xixia`、`dali`、`xixia_north`、`desert_edge`、`tianshan_road` 等既有地區只用 `extra_rooms`／`exit_patches` 加房間與出口，§3.3。）

### 3.2 接點圖（房間層級；全部雙向出口）

```
京城（jingcheng，1.0B）：
  南半：jc_station ─E─ jc_street ─N─ jc_inn；jc_street ─S─ jc_gate_s ─S─ jcw_crossroad（南郊）；jc_street ─E─ jc_square
  廣場：jc_square ─E─ jc_biaoju｜─S─ jc_bank｜─SW─ jc_pharmacy｜─NW─ jc_buzhuang｜─NE─ jc_yamen ─N─ jc_jail_gate ─N─ jc_jail
  北半：jc_square ─N─ jc_street_n ─W─ jc_smithy｜─E─ jc_tiepu｜─NW─ jc_zijin｜─NE─ jc_coffin ─N─ jc_tdh_hall｜─N─ jc_gate_n

京城北郊（jingcheng_north，1.0B）與丐幫（gaibang，1.0B）：
  jc_gate_n ─N─ jcn_road1 ─N─ jcn_road2 ─E─ gb_gate ─N─ gb_pomiao ─N─ gb_houdian；gb_pomiao ─E─ gb_yuan
  jcn_road2 ─W─ jcn_kongdi（死路練功點）；jcn_road2 ─N─ jcn_road3 ─N─ jcn_road4 ─W─ ym_road（雁門古道；出口帶 era 1.0B）

絕情谷（1.0B）：jcw_crossroad ─SE─ jq_road1 ─E─ jq_gukou ─E─ jq_qinghua ─E─ jq_shiwu
  jq_shiwu ─N─ jq_danfang｜─NE─ jq_shufang｜─SE─ jq_jianfang｜─E─ jq_duanchang
  jq_shufang ─N─ jq_dilao1（jueqinggu_dilao）─N─ jq_dilao2 ─N─ jq_eyuchi ─E─ jq_dilao3（裘千尺）

雁門關（yanmen，1.0A）補完：ym_bridge ─E─ ym_outside（苗人鳳）；ym_inner ─W─ ym_stele（刻字石碑）；ym_gate ─W─ mw_mouth（馬王洞；這條出口審查改 1.0B）
馬王洞（mawang，1.0B，審查改）：mw_mouth ─N─ mw_cave1 ─N─ mw_cave2 ─N─ mw_deep
高昌（1.0A）：ts_road1 ─SW─ gc_road1 ─W─ gc_road2（駝隊歇腳處，INN）─W─ gc_road3 ─W─ gc_outside
              gc_outside ─SW─ gc_jihut_out ─S─ gc_jihut ；gc_outside ─N─ gc_maze1 ─N─ gc_maze2 … ─N─ gc_maze6
城內新建築（1.0A）：xx_square ─SW─ xx_bank；xx_square ─NE─ xx_biaoju；xx_street ─SE─ xx_tiepu；xx_street ─SW─ xx_buzhuang
                    dl_square ─NW─ dl_bank；dl_square ─NE─ dl_biaoju；dl_shop ─E─ dl_tiepu；de_edge ─W─ de_mine
```

**下表是唯一權威**（方向、兩端房間 id 都綁定；反向出口照寫）：

| # | 房間 A（地區，擁有者） | 方向 | 房間 B（地區，擁有者） | 反向 | era |
|---|---|---|---|---|---|
| 1 | `jc_street`（jingcheng） | E | `jc_square` | W | 1.0B |
| 2 | `jc_square` | N | `jc_street_n` | S | 1.0B |
| 3 | `jc_square` | E | `jc_biaoju` | W | 1.0B |
| 4 | `jc_square` | S | `jc_bank` | N | 1.0B |
| 5 | `jc_square` | NE | `jc_yamen` | SW | 1.0B |
| 6 | `jc_square` | NW | `jc_buzhuang` | SE | 1.0B |
| 7 | `jc_square` | SW | `jc_pharmacy` | NE | 1.0B |
| 8 | `jc_yamen` | N | `jc_jail_gate` | S | 1.0B |
| 9 | `jc_jail_gate` | N | `jc_jail` | S | 1.0B |
| 10 | `jc_street_n` | W | `jc_smithy` | E | 1.0B |
| 11 | `jc_street_n` | E | `jc_tiepu` | W | 1.0B |
| 12 | `jc_street_n` | NW | `jc_zijin` | SE | 1.0B |
| 13 | `jc_street_n` | NE | `jc_coffin` | SW | 1.0B |
| 14 | `jc_coffin` | N | `jc_tdh_hall` | S | 1.0B |
| 15 | `jc_street_n` | N | `jc_gate_n` | S | 1.0B |
| 16 | `jc_gate_n`（jingcheng） | N | `jcn_road1`（jingcheng_north，gaibang） | S | 1.0B |
| 17 | `jcn_road1` | N | `jcn_road2` | S | 1.0B |
| 18 | `jcn_road2` | E | `gb_gate`（gaibang） | W | 1.0B |
| 19 | `jcn_road2` | W | `jcn_kongdi` | E | 1.0B |
| 20 | `jcn_road2` | N | `jcn_road3` | S | 1.0B |
| 21 | `jcn_road3` | N | `jcn_road4` | S | 1.0B |
| 22 | `jcn_road4`（gaibang） | W | `ym_road`（yanmen，既有；**出口帶 `"era": "1.0B"`**，由 gaibang 的 `exit_patches` 加） | E | 1.0B |
| 23 | `gb_gate` | N | `gb_pomiao` | S | 1.0B |
| 24 | `gb_pomiao` | N | `gb_houdian` | S | 1.0B |
| 25 | `gb_pomiao` | E | `gb_yuan` | W | 1.0B |
| 26 | `jcw_crossroad`（jingcheng_wild，jingcheng） | SE | `jq_road1`（jueqinggu；出口由 jueqinggu 的 `exit_patches` 加） | NW | 1.0B |
| 27 | `jq_road1` | E | `jq_gukou` | W | 1.0B |
| 28 | `jq_gukou` | E | `jq_qinghua` | W | 1.0B |
| 29 | `jq_qinghua` | E | `jq_shiwu` | W | 1.0B |
| 30 | `jq_shiwu` | N | `jq_danfang` | S | 1.0B |
| 31 | `jq_shiwu` | NE | `jq_shufang` | SW | 1.0B |
| 32 | `jq_shiwu` | SE | `jq_jianfang` | NW | 1.0B |
| 33 | `jq_shiwu` | E | `jq_duanchang` | W | 1.0B |
| 34 | `jq_shufang` | N | `jq_dilao1`（jueqinggu_dilao） | S | 1.0B |
| 35 | `jq_dilao1` | N | `jq_dilao2` | S | 1.0B |
| 36 | `jq_dilao2` | N | `jq_eyuchi` | S | 1.0B |
| 37 | `jq_eyuchi` | E | `jq_dilao3` | W | 1.0B |
| 38 | `ym_bridge`（yanmen） | E | `ym_outside`（extra_rooms） | W | 1.0A |
| 39 | `ym_inner` | W | `ym_stele`（extra_rooms） | E | 1.0A |
| 40 | `ym_gate` | W | `mw_mouth`（mawang） | E | 1.0B（審查改；出口帶 `era: "1.0B"`，`ym_gate` 的 `desc_1_0b` 才提山洞） |
| 41 | `mw_mouth` | N | `mw_cave1` | S | 1.0B（審查改） |
| 42 | `mw_cave1` | N | `mw_cave2` | S | 1.0B（審查改） |
| 43 | `mw_cave2` | N | `mw_deep` | S | 1.0B（審查改） |
| 44 | `ts_road1`（tianshan_road） | SW | `gc_road1`（gaochang_road） | NE | 1.0A |
| 45 | `gc_road1` | W | `gc_road2` | E | 1.0A |
| 46 | `gc_road2` | W | `gc_road3` | E | 1.0A |
| 47 | `gc_road3` | W | `gc_outside`（gaochang） | E | 1.0A |
| 48 | `gc_outside` | SW | `gc_jihut_out` | NE | 1.0A |
| 49 | `gc_jihut_out` | S | `gc_jihut` | N | 1.0A |
| 50 | `gc_outside` | N | `gc_maze1`（gaochang_maze） | S | 1.0A |
| 51–55 | `gc_maze1`…`gc_maze5` | N | 下一層 `gc_maze2`…`gc_maze6` | S | 1.0A |
| 56 | `xx_square`（xixia，`_econ`） | SW | `xx_bank` | NE | 1.0A |
| 57 | `xx_square` | NE | `xx_biaoju` | SW | 1.0A |
| 58 | `xx_street`（xixia，lifeskills_content） | SE | `xx_tiepu` | NW | 1.0A |
| 59 | `xx_street` | SW | `xx_buzhuang` | NE | 1.0A |
| 60 | `dl_square`（dali，`_econ`） | NW | `dl_bank` | SE | 1.0A |
| 61 | `dl_square` | NE | `dl_biaoju` | SW | 1.0A |
| 62 | `dl_shop`（dali，lifeskills_content） | E | `dl_tiepu` | W | 1.0A |
| 63 | `de_edge`（desert_edge，lifeskills_content） | W | `de_mine` | E | 1.0A |

- 既有 4 間京城房（`jc_station`、`jc_street`、`jc_inn`、`jc_gate_s`）id 與出口保留；jingcheng 碎片的 `maps.jingcheng` 是完整替換，必須包含它們。
- jingcheng 碎片也提供完整的 `maps.jingcheng_wild`（保留 3 間房的 id 與出口、可改 desc 與遇敵表）；#26 的出口由 jueqinggu 的 `exit_patches` 在地圖合併**之後**加。
- 1.0A 房間加的出口（#22 `ym_road`→E、#38–40、#44、#56–63）由表中「擁有者」碎片的 `exit_patches` 加；只有本表列出的既有房間能被 patch。

### 3.3 既有房間的 patch（WP-MERGE 照碎片套）

| 房間 | 碎片 | 改動 |
|---|---|---|
| `ym_road` | gaibang | 加 E → `jcn_road4`（`era: "1.0B"`）；desc 句末加「往東的山徑翻過去可到京城北郊。」（用 `desc_1_0b` 欄，見 §4.4） |
| `ym_gate` | mingjiao_gaochang_yanmen | 加 W → `mw_mouth`；desc 加「關口西邊靠山處有個黑黝黝的山洞。」 |
| `ym_bridge`、`ym_inner` | mingjiao_gaochang_yanmen | 加 #38、#39 |
| `ts_road1` | mingjiao_gaochang_yanmen | 加 SW → `gc_road1`；desc 加「西南方有條駝隊踩出的古道，通往高昌。」 |
| `jcw_crossroad` | jueqinggu | 加 SE → `jq_road1`；desc 改「幾條古道在此交會。往西下山到華山腳下，往東接嵩山古道去少林；東南有條小路鑽進山谷，谷口隱約可見花樹。」 |
| `xx_square`、`dl_square` | `_econ` | 加 #56、#57、#60、#61；desc 加一句提到錢莊、鏢局 |
| `xx_street`、`dl_shop`、`de_edge` | lifeskills_content | 加 #58、#59、#62、#63；desc 加一句 |
| `xe_mine` | lifeskills_content | `add_features: ["MINE"]`（礦區＝礦場） |
| `xw_grass`、`ts_xuegu`、`dlw_forest` | lifeskills_content | `add_features: ["HUNT"]`＋`hunt_table`（§4.4） |
| `xx_smithy` | lifeskills_content | 不加 feature（兵器鋪只賣；打鐵在 `xx_tiepu`） |
| `hy_foot`、`sy_pines` | （不動） | 1.0B 出口已在（WORLD_2001 §6.2） |

### 3.4 步數與新手安全

| 路線（最短步行） | 步數 | 說明 |
|---|---|---|
| 京城南門 → 京城廣場 | 2 | `jc_street`、`jc_square` |
| 京城廣場 → 丐幫破廟門口 `gb_gate` | 5 | `jc_street_n`、`jc_gate_n`、`jcn_road1`、`jcn_road2`、`gb_gate`（原作「跑上 10 分鐘」【設計提案縮短】） |
| 京城北門 → 雁門古道 `ym_road` | 5 | 1.0B 新捷徑 |
| 西夏東門 → 京城南門（1.0B） | 約 14 | 東路到華山腳下 → `jcw_huashan` → `jcw_crossroad` → 南門 |
| 京城南門 → 絕情谷谷口 `jq_gukou` | 3 | |
| 雁門關口 → 馬王洞最深處 | 4 | |
| 西夏廣場 → 高昌室外 `gc_outside` | 約 12 | 西夏北郊 → 天山道 `ts_road1` → 高昌古道（`gc_road2` 歇腳） |
| 西夏廣場 → 錢莊／鏢局 | 1 | 大理同 |

必須遵守（`tools/data_lint.gd` `check_newbie_routes`，**出生城改成「生效的 `birth_allowed` 地區」**，1.0B 閉包包含京城）：
1. M3A_PLAN §2.3 第 1–7 條全部照舊，自動涵蓋新山門 `gb_gate`。
2. `jcn_road1`、`jcn_road2`（緊鄰山門）只能有 `m_rabbit`、`m_bigrabbit` 與 `m_jc_qigaitou`、`m_jc_buliang`（新手怪，`combat_xp_ref` ≤ 500，lint 白名單）；`jcn_road3` 只能有新手怪與 `m_wolf`。
3. 原作山路上的埋伏（護國法師、煞風寨寨主）只放 `jcn_road4`（離山門 3 步，**不在**京城→山門的必經路上），遇敵率 ≤ 0.20；**偏離原作**（原作山門就在埋伏的山路中間）標【設計提案・偏離】寫在 `src_note`。
4. `jcn_kongdi`（丐幫左方空地，原作 20–29 級練功點：馬王、道人頭子、隱面人）是死路，遇敵率 ≤ 0.30（比照 `wd_woods`）。
5. 絕情谷：`jq_road1`、`jq_gukou` 只能有新手怪與 `m_wolf`；`jq_qinghua` 以後才放強怪；地牢 DUNGEON 不受新手規則限制。
6. 高昌古道：`gc_road1` 只能有 `m_rabbit`、`m_bigrabbit`、`m_wolf`；`gc_road2` 是休息點（`INN` NPC，`inn_price` 15，不遇敵）。
7. 京城北門、南門外各 1 步內不放 `m_bandit` 等級以上的怪。

### 3.5 原作座標與參考（寫 `src_note` 用）

| 地點 | 原作座標 | world_pos | 依據 |
|---|---|---|---|
| 范遙（西夏上方山坡） | 7423,1323 | [309,55] → 放在既有 `xn_slope` | gaoshou/23 |
| 香香公主、霍青桐（高昌迷宮外左方） | 391,2005 | [16,84] | gaoshou/23（「香相公主」原文錯字） |
| 計老人、李文秀（高昌左下方小屋） | — | `gc_jihut` | gaoshou/23 |
| 靈芝商人（雁門關口） | 20078,2310 | [837,96] | gaoshou/23 |
| 強盜（關口右下橋邊） | 20196,3760 | [842,157] | gaoshou/23（既有 `ym_bridge`；座標偏南，沿用既有擺法） |
| 苗人鳳（雁門關外右下） | — | `ym_outside` | gaoshou/23 |
| 阿朱、胡斐（雁門關內） | — | `ym_inner` | gaoshou/23、other.htm |
| 阿火的礦（星宿海左下） | 3615,8285 | [151,345] → `de_mine` | 17173 other.htm（未重抓） |
| 丐幫附近（後期） | 28588,2196 | [1191,92]（不用） | 2002-11-16 |

### 3.6 id 前綴（L5）

| 碎片 | 房間 | NPC | 怪物 | 物品 | 任務 | 模板 | 其他 |
|---|---|---|---|---|---|---|---|
| gaibang | `gb_`、`jcn_` | `n_gb_` | `m_gb_`、`m_jcn_` | `*_gb_` | `q_gb_` | `talk_n_gb_*`、`rule_gb_*`、`gb_*` | 武功 `gb_*`、師父 `ms_gb_*`、袋位 `gb_dai*` |
| jingcheng | `jc_` | `n_jc_`、`n_tdh_` | `m_jc_` | `*_jc_`、`*_tdh_` | `q_jc_`、`q_tdh_` | `talk_n_jc_*`、`talk_n_tdh_*` | |
| jueqinggu | `jq_` | `n_jq_` | `m_jq_` | `*_jq_` | `q_jq_` | | 狀態 `qinghua` |
| mingjiao_gaochang_yanmen | `ym_`（新房）、`mw_`、`gc_` | `n_mj_`、`n_ym_`、`n_gc_` | `m_mw_`、`m_gc_` | `*_gc_`、`*_mw_` | `q_ym_`、`q_gc_`、`q_mj_` | | |
| lifeskills_content | `xx_tiepu`、`xx_buzhuang`、`dl_tiepu`、`de_mine` | `n_ls_`（＋既有 NPC 的 `npc_links`） | `m_hunt_` | `r_`、`t_`、`w_`、`a_`（新 id 前加 `ls` 不必，但不得撞既有） | `q_ls_` | `talk_n_ls_*` | 配方 `rc_*` |
| story_missing | — | `n_sm_`（只有沒有其他擁有者時） | `m_sm_` | `i_sm_`、`r_sm_` | `q_sm_` | `talk_n_sm_*`、`rmr_q_sm_*` | |
| `_sect` | — | — | — | — | — | `e_*`、`err_*` | |
| `_econ` | `xx_bank`、`xx_biaoju`、`dl_bank`、`dl_biaoju` | `n_ec_` | `m_ec_` | `i_ec_` | `q_ec_` | `e_*`、`err_*`、`talk_n_ec_*` | 路線 `er_*` |
| `_org` | — | `n_og_` | — | — | — | `e_org_*`、`err_org_*`、`talk_n_og_*` | |

---

## 4. 資料模型（增量）

### 4.1 `sects.json`：丐幫列與新欄位

形狀照 M3A_PLAN §3.1，新增選填欄位（其他 10 派不必補，預設值如右）：

| 欄位 | 預設 | 說明 |
|---|---|---|
| `ranks` | `""` | 本派位階表 id（= `sect_ranks.sect`）；空 = 沒有位階 |
| `practice` | `null` | 門派技能的「行動練習」（§5.1.2）：`{ "verb": "乞討", "target": "NPC", "cost": { "jing": 20, "shen": 20 }, "prof": [3, 6], "per_npc_cd_s": 600, "alms": [...], "npc_kinds": ["SHOP","FUNC","QUEST","STORY"] }` |
| `harass` | `[]` | 城內追咬（§5.1.3）：`[{ "regions": {"xixia": 0.15, "dali": 0.15, "jingcheng": 0.05}, "monster": "m_gb_xiaohuang", "count": [1, 1], "unless": [ { "type": "skill_min", "skill": "qitao", "value": 30 } ] }]` |
| `no_escort` | false | true：不能接保鏢工作（O17；由保鏢任務的 `requires` 實作，這欄只給 lint 對照與介面說明） |
| `respawn_at_gate` | true | false：山門沒有查小鏞（lint 不要求 `n_<p>_cha`；丐幫 false，O4） |

丐幫列（WP-C-gaibang 碎片，固定值不得改）：

```json
{ "id": "gaibang", "name": "丐幫", "home_city": "jingcheng", "gate_region": "gaibang", "prefix": "gb",
  "gate_room": "gb_gate", "head_npc": "n_gb_chen", "gender": ["M", "F"],
  "join_requires": [ { "type": "no_sect" }, { "type": "morality_min", "value": 0 }, { "type": "not_enemy_of", "sect": "gaibang" } ],
  "teach_requires": [ { "type": "morality_min", "value": 0 } ],
  "sect_skill": "qitao", "sect_skill_name": "乞討", "sect_skill_effect": { "effect": "POISON_FANG" },
  "sect_skill_cost": ["jing", "shen"], "sect_skill_train_cost": ["jing"], "sect_skill_cap": 100,
  "sect_skill_limits_arts": false, "sect_art_cap_bonus": 0,
  "sect_skill_gain": [], "sect_skill_penalties": [], "personal_master": false,
  "enforcer": false, "enforcers": [], "jail_room": "", "hostile_entry": [], "visitors": "OPEN", "meal_npc": "",
  "ranks": "gaibang", "no_escort": true, "respawn_at_gate": false,
  "practice": { "verb": "乞討", "target": "NPC", "cost": { "jing": 20, "shen": 20 }, "prof": [3, 6], "per_npc_cd_s": 600,
                "alms": [ { "money": [1, 8], "chance": 0.35 }, { "item": "c_mantou", "n": 1, "chance": 0.10 } ],
                "npc_kinds": ["SHOP", "FUNC", "QUEST", "STORY"] },
  "harass": [ { "regions": { "xixia": 0.15, "dali": 0.15, "jingcheng": 0.05 }, "monster": "m_gb_xiaohuang", "count": [1, 1],
                "unless": [ { "type": "skill_min", "skill": "qitao", "value": 30 } ] } ],
  "src_note": "研究 丐幫：1.0B 2001-09-28；男女皆收、善惡<0停止傳功、執法者無（官方後期 jy2-6-4、jy2-4-2）；乞討＝毒牙（jy1-4-11）；不能運鏢（2001 多篇）；小黃（2001-10-24）；乞討30免追是後期",
  "era": "1.0B", "src": "later" }
```

`c_mantou`（饅頭）、`c_baifan`（白飯）、`c_jieduyao`（解毒藥）是既有物品。黃甲 `a_huangjia` 目前不存在，由 mingjiao_gaochang_yanmen 碎片建立；解毒草沒有既有 id，由 story_missing 建 `r_sm_jieducao`。

### 4.2 `data/sect_ranks.json`（新表；WP-MERGE 合併）

```json
{ "table": "sect_ranks", "version": 1, "rows": [
  { "id": "gb_dai0", "sect": "gaibang", "rank": 0, "name": "無袋弟子", "requires": [], "promote": "JOIN", "cost": {},
    "era": "1.0B", "src": "proposal" },
  { "id": "gb_dai1", "sect": "gaibang", "rank": 1, "name": "一袋弟子",
    "requires": [ { "type": "fame_min", "value": 250 }, { "type": "lilian_min", "value": 250 } ],
    "promote": "QUEST", "quest": "q_gb_dai1", "assembly": true, "cost": {},
    "era": "1.0B", "src": "verified", "src_note": "研究 丐幫：2001-11-03 n247_163262 名聲歷練250、陳長老、聚會" },
  { "id": "gb_dai2", "sect": "gaibang", "rank": 2, "name": "二袋弟子",
    "requires": [ { "type": "fame_min", "value": 500 }, { "type": "lilian_min", "value": 500 }, { "type": "sect_rank_min", "sect": "gaibang", "value": 1 } ],
    "promote": "QUEST", "quest": "q_gb_dai2", "assembly": true, "cost": { "fame": 250, "lilian": 250 },
    "era": "1.0B", "src": "verified", "src_note": "研究 丐幫：2001-11-23、11-25、12-03（升二袋扣 250）" },
  { "id": "gb_dai3", "sect": "gaibang", "rank": 3, "name": "三袋弟子",
    "requires": [ { "type": "fame_min", "value": 1200 }, { "type": "lilian_min", "value": 1200 }, { "type": "sect_rank_min", "sect": "gaibang", "value": 2 } ],
    "promote": "QUEST", "quest": "q_gb_dai3", "assembly": true, "cost": {}, "era": "xkd", "src": "later",
    "src_note": "2002-07、2002-11 攻略；任務本身不在 M3b（列只給後期 era）" },
  { "id": "gb_dai4", "…": "四～七袋 1700/2500/3500/10000，promote AUTO，era xkd，src later（免費版數字）" }
] }
```

| 欄位 | 說明 |
|---|---|
| `rank` | 0 起算；每派連續不缺號（lint） |
| `promote` | `JOIN`（拜入即得）／`QUEST`（`quest` 任務的結局給 `sect_rank` 獎勵，§4.9）／`AUTO`（`requires` 成立時在下次聚會自動升） |
| `assembly` | true：任務完成後先記「待升」，下次聚會才生效（§5.1.1）；false：立即 |
| `cost` | 升袋時扣（`fame`、`lilian`、`money`） |
| `requires` | 接升袋任務（`QUEST`）或自動升（`AUTO`）的門檻；聚會當下**再檢查一次**，不成立就繼續等 |

只有 era 生效的列會載入；一派生效列中最大的 `rank` = 目前世界的最高袋位（1.0B 世界 = 2）。

### 4.3 新條件型別（`core/data/data_schema.gd`、`core/character/requirements.gd`，WP-SECT Day-0）

| type | 欄位 | 成立條件 | 原因碼 |
|---|---|---|---|
| `sect_not` | `sect` | `ch.sect != sect`（不在該派；保鏢「丐幫不能運鏢」） | `req_sect_not` |
| `sect_rank_min` | `sect`, `value` | `ch.sect == sect` 且 `ch.sect_rank >= value` | `req_sect_rank_min` |
| `org_member` | `org`（選填；空 = 任何組織） | 在組織裡（`ch.guild != ""`，有 `org` 時比對 id） | `req_org_member` |
| `no_org` | — | 不在任何組織 | `req_no_org` |
| `life_min` | `skill`, `value` | 同 `skill_min`，但只接受 `life_skills` id（lint 用；介面顯示「生活技能」字樣） | `req_life_min` |

`REQUIRE_FIELDS_BY_TYPE` 同步。`org_member`／`no_org` 的純角色判定讀 `ch.guild`（快取值，OrgSystem 維護）。

### 4.4 地圖與房間（增量）

房間新增選填欄位：

| 欄位 | 說明 |
|---|---|
| `jail: true` + `jail_scope` | `jail_scope: "SECT"`（預設，M3a 思過處）／`"CAPITAL"`（京城監獄，§5.1.4）。全資料最多一間 `CAPITAL`（lint） |
| `jail_release_to` | `CAPITAL` 牢房必填：出獄送去的房間（`jc_yamen`） |
| `features` 新值 | `MINE`（礦場）、`FORGE`（打鐵爐）、`CAST`（鑄劍爐）、`LOOM`（紡紗機與織布機）、`TANNERY`（烘皮爐）、`KILN`（燒炭爐）、`HUNT`（打獵專區）。既有 `FIELD WOOD WATER STOVE` 不變 |
| `hunt_table` | 有 `HUNT` 的房間必填：`[{ "monster": "m_rabbit", "w": 60 }, …]`（只能放野獸：`monsters[].hunt: true`） |
| `desc_1_0b` | 選填：1.0B 生效時取代 `desc`（`DataLoader.activate` 在 1.0B 閉包裡換掉；給 1.0A 房間提到 1.0B 出口用）。lint：有 `desc_1_0b` 的房間必須有帶 `era: "1.0B"` 的出口 |
| `requires` | 既有；天地會香堂用 `any_of`（§8.3 jingcheng） |

`exit_patches` 擴充（碎片用）：`{ "room": "xe_mine", "add_exits": [...], "add_features": ["MINE"], "hunt_table": [...], "desc": "…", "desc_1_0b": "…" }`。`add_features`、`hunt_table`、`desc_1_0b` 只能用在 §3.3 表列出的房間。

### 4.5 `life_skills.json` 第 2 版（WP-ECON 引擎；列由 WP-C-lifeskills_content 寫）

既有欄位保留。新增：

| 欄位 | 預設 | 說明 |
|---|---|---|
| `mode` | `"GATHER"` | `GATHER`（`yield`）／`CRAFT`（只有配方）／`HUNT`（戰鬥打獵，§5.2.4） |
| `tools` | `[]` | 除了 `tool` 之外還必須帶在身上的工具 id（全部要有） |
| `yield[].min_level` | 1 | 低於這個等級不會擲這一項 |
| `recipes[].feature` | 技能的 `feature` | 這個配方要在哪種設施做；`""` = 隨地（裁縫、工匠） |
| `recipes[].tools` | `[]` | 這個配方額外要的工具 |
| `recipes[].jing_cost` | 技能的 `jing_cost` | |
| `recipes[].prof` | 1 | 成功時熟練加多少（`Learning.practice_life` 的倍數） |
| `hunt` | null | `mode: HUNT` 必填：`{ "drops": [ { "item": "r_shoupi", "chance": 0.6, "n": [1,1], "min_level": 1, "monsters": ["m_wolf"] } ] }`（打贏後**額外**掉落；一般掉落照怪物表） |
| `teachers` | `[]` | 顯示用：教這項的 NPC id（實際教學仍是 `masters` 列） |
| `src_note` | | |

`work { skill, recipe }`：`recipe == ""` → 採集（`mode` 必須是 `GATHER` 或 `HUNT`）；否則照配方做。同一技能可以同時有 `yield` 與 `recipes`（樵夫採木材＋燒炭、種田收稻＋種麻棉）。

7 個新技能（id 綁定；欄位值由 lifeskills_content 依研究填）：

| id | 名稱 | era | mode | feature | 工具 | 產物鏈（摘要） | 依據 |
|---|---|---|---|---|---|---|---|
| `life_mining` | 挖礦（官方「採礦」） | 1.0A | GATHER（＋淘洗配方） | MINE | `t_shizigao` 十字鎬；淘洗配方另要 `t_caishaqi` 採沙器 | 鐵礦石（1 級）、綠石礦（20 級）、紫石礦（40 級） | 官方生活技能頁【後期版】；2001 大理礦石大王 |
| `life_smithing` | 打鐵 | 1.0A | CRAFT | FORGE | `t_tiechui` 打鐵鎚 | 3 同級礦 → 鐵塊（三級）【已證實「3 個同等級礦」】；鐵塊＋木炭 → 十字鎬、打鐵鎚、鋤頭、柴刀 | 同上 |
| `life_swordsmith` | 鑄劍 | 1.0A | CRAFT | CAST | `t_tiechui` | 鐵塊＋木炭（＋焦炭）→ 鐵劍、單刀、鋼刀、青鋒劍、**冷凝劍（30 級）** | 官方頁；冷凝劍事件（2001-08-08；鑄劍 30 後期） |
| `life_carpentry` | 工匠 | **1.0B** | CRAFT | `""` | `t_juzi` 鋸子 | 木材 → 木刀、木劍、木杖、玄木杖、木爪、斗笠、木簪 | 官方 1.0B 工匠頁【已證實】 |
| `life_weaving` | 織布 | 1.0A | CRAFT | LOOM（皮革配方 TANNERY） | — | 麻／棉花 → 線軸 → 麻布／棉布；獸皮 → 皮革 | 官方頁 |
| `life_tailoring` | 裁縫 | 1.0A | CRAFT | `""` | `t_zhenxian` 針線包 | 布匹 → 布袍、粗布道袍；皮革 → 皮甲；大兔皮 → 兔皮帽【設計提案】 | 官方頁；2001 李裁縫 |
| `life_hunting` | 獵人 | 1.0A | HUNT | HUNT | —（用自己的武功） | 打贏野獸 → 肉、獸皮 | 官方頁 |

既有列的替換（lifeskills_content 給整列，WP-MERGE 以碎片為準並報告）：`life_farming` 加配方 種麻（`r_zhongzi_ma` → `r_ma` ×2，10 級）、種棉（`r_zhongzi_mian` → `r_mianhua` ×2，20 級），`feature: FIELD`；`life_woodcut` 加配方 燒炭（木材 ×3 → 木炭 ×1，20 級，`feature: KILN`）。其餘欄位不變。

### 4.6 物品（增量；`items.json` 形狀不變）

- 新 `tab` 值：無（工具用 `OTHER`、材料用 `MATERIAL`）。
- 新欄位（選填）：`tool: true`（工具，介面分類用）；`bankable: false`（不能存錢莊；預設 true；`quest_item: true` 一律不能存）；`grade: 1|2|3`（礦石、鐵塊的等級，打鐵配方檢查用）。
- 綁定 id（lifeskills_content 建立，其他碎片可引用）：

| id | 名稱 | 類 | 備註 |
|---|---|---|---|
| `t_shizigao` | 十字鎬 | 工具 | 打鐵可做；西夏、大理打鐵舖賣 |
| `t_caishaqi` | 採沙器 | 工具 | |
| `t_tiechui` | 打鐵鎚 | 工具 | |
| `t_juzi` | 鋸子 | 工具 | era 1.0B |
| `t_zhenxian` | 針線包 | 工具 | |
| `r_kuang_tie` | 鐵礦石 | 材料 grade 1 | |
| `r_kuang_lv`（既有） | 綠石礦 | 材料 grade 2 | 碎片只能補 `grade`（`item_patches`） |
| `r_kuang_zi`（既有） | 紫石礦 | 材料 grade 3 | 同上 |
| `r_tiekuai_1`／`_2`／`_3` | 鐵塊／綠紋鐵塊／紫紋鐵塊 | 材料 | 名稱【設計提案】 |
| `r_mutan` | 木炭 | 材料 | 樵夫燒炭 |
| `r_jiaotan` | 焦炭 | 材料 | 打鐵舖賣；拓印任務用（other.htm「兩個焦炭」） |
| `r_zhongzi_ma`、`r_zhongzi_mian` | 麻種子、棉花種子 | 材料 | 菜販賣 |
| `r_ma`、`r_mianhua` | 麻、棉花 | 材料 | 辛勤的程薇（20 麻、10 棉） |
| `r_xianzhou` | 線軸 | 材料 | |
| `r_mabu` | 麻布 | 材料 | **可賣**；拓印任務用（「兩個麻布」）；與任務物 `r_lf_mabu` 不同 |
| `r_mianbu` | 棉布 | 材料 | |
| `r_shoupi`、`r_pige` | 獸皮、皮革 | 材料 | |
| `w_tiejian` | 鐵劍 | 兵器 SWORD | 鑄劍 |
| `w_lengning` | 冷凝劍 | 兵器 SWORD | 鑄劍 30 級；冷凝劍事件 |
| `w_muzhang`、`w_xuanmuzhang`、`w_muzhua` | 木杖、玄木杖、木爪 | 兵器 STAFF／STAFF／FIST | era 1.0B（工匠） |
| `a_douli` | 斗笠 | 防具 | era 1.0B（工匠） |

### 4.7 `data/escort_routes.json`（新表；WP-ECON 定形，`_econ.json` 寫列）

```json
{ "table": "escort_routes", "version": 1, "rows": [
  { "id": "er_xx_dl", "from_city": "xixia", "to_city": "dali", "consign_delay_shichen": 4, "job_quest": "q_ec_biao_xx_dl",
    "era": "1.0A", "src": "proposal" },
  { "id": "er_dl_xx", "from_city": "dali", "to_city": "xixia", "consign_delay_shichen": 4, "job_quest": "q_ec_biao_dl_xx", "era": "1.0A", "src": "proposal" },
  { "id": "er_xx_jc", "from_city": "xixia", "to_city": "jingcheng", "consign_delay_shichen": 3, "job_quest": "q_ec_biao_xx_jc", "era": "1.0B", "src": "proposal" },
  { "id": "er_jc_xx", "…": "" }, { "id": "er_dl_jc", "consign_delay_shichen": 5, "…": "" }, { "id": "er_jc_dl", "…": "" }
] }
```

每個 `(from_city, to_city)` 只能一列；`job_quest` 必須存在且 era 相同；鏢局 NPC 的 `escort.city` 必須是這些城之一。

### 4.8 NPC（增量）

新服務（`NPC_SERVICES`、`UiKeys.SERVICES`）：

| 服務 | 標籤 | 欄位 | 擁有機制 |
|---|---|---|---|
| `BANK` | 錢莊 | — | WP-ECON |
| `ESCORT` | 鏢局 | `escort: { "city": "xixia" }` | WP-ECON（托鏢、取貨；保鏢工作用 `QUEST`） |
| `ORG` | 組織 | — | WP-ORG |
| `RANK` | 袋位 | —（看本派 `ranks`） | WP-SECT |

其他新欄位：`shop.refuse_if: [條件…]`（任一組成立就拒賣，回 `shop_refused`，模板 `shop.refuse_text`）；`no_beg: true`（不能對他乞討；師父、守衛、惡人預設不能，`kind` 不在 `practice.npc_kinds` 也不能）。

京城兵器鋪 `n_jc_smith`：`"shop": { "items": [...], "refuse_if": [ [ { "type": "sect", "sect": "gaibang" } ] ], "refuse_text": "jc_smith_refuse_gb" }`（`refuse_if` 是「條件組」陣列，組內全成立才算）。

### 4.9 任務（`quests.json` 第 2 版，STORY_PLAN §4.2；增量）

- 獎勵新 key（`outcomes.<x>.rewards`、動作 `reward`）：`sect_rank: { "sect": "gaibang", "rank": 1 }` → `SectSystem.queue_rank(s, sect, rank)`（`assembly: true` 時記待升；否則立即升）。只有 `sect_ranks` 中 `quest` 指向本任務的列可用（lint）。
- 保鏢工作是一般任務列（`_econ.json`）：

```json
{ "id": "q_ec_biao_xx_dl", "name": "保鏢：西夏往大理", "chapter": "鏢局・保鏢", "group": "_econ",
  "giver": "n_ec_xx_biaotou", "era": "1.0A", "src": "proposal",
  "src_note": "官方鏢局頁：保鏢提升名聲（研究 經濟）；路線、酬勞【設計提案】",
  "requires": [ { "type": "sect_not", "sect": "gaibang" } ],
  "repeat": { "max": 0, "cooldown_days": 1 }, "abandon": true, "party_credit": true,
  "start": "s_go",
  "stages": [ { "id": "s_go", "title": "押鏢到大理", "log": "護著鏢車出西夏東門……走到大理鏢局交鏢。",
      "on_enter": [ { "do": "escort_start", "npc": "n_ec_biaoche" } ],
      "objectives": [ { "id": "o_go", "type": "ESCORT", "npc": "n_ec_biaoche", "to_room": "dl_biaoju", "text": "把鏢車護送到大理鏢局" } ],
      "on_complete": [ { "do": "escort_end", "npc": "n_ec_biaoche" } ],
      "next": "END" } ],
  "outcomes": { "default": { "label": "鏢已送達", "rewards": { "money": 150, "fame": 3 } } } }
```

- `n_ec_biaoche`（鏢車，`kind: "STORY"`、`services: []`、不放在任何房間，`room: ""`，只供護送）——STORY_PLAN 的護送 NPC 規則照舊。

### 4.10 狀態（`status_effects.json`；碎片可給新列）

jueqinggu 碎片新增 `qinghua` 情花毒：`kind DEBUFF`、`glyph "情"`、`persists: true`、`persist_tick_real_s: 600`、`persist_ticks_per_level: 12`（約 12 時辰，研究「十二個時辰之內」）、`persist_qi_pct: 0.03`、`cure_by: ["ANTIDOTE"]`、`resist_by: []`、`era "1.0B"`、`src "verified"`（情花毒存在）＋數值 proposal。解藥 `c_jq_juequingdan` 絕情丹（`effects: [{ "type": "cure", "status": "qinghua", "max_level": 99 }]`，一人一顆：`unique_per_char: true`【已證實「一人一顆」】，新欄位 lint 只檢查型別）。施加方式：房間 `jq_qinghua` 的 `on_enter_status: { "status": "qinghua", "level": 1, "chance": 0.5, "unless": [ { "type": "has_item", "item": "c_jq_juequingdan" } ] }`（**新房間欄位**，WP-SECT 在 `RegionSystem` 進房流程呼叫 `ConditionSystem.add`）。

### 4.11 規則與伺服器選項（WP-SECT）

`data/rule_profiles.json`：`classic_strict` 加 `"default_eras": ["1.0A"]`（§2.1）。沒有新規則 key。

`data/server_options.default.json`（INT 的加進 `DataSchema.INT_FIELDS.server_options`）：

| key | 預設 | 說明 | 擁有 |
|---|---|---|---|
| `enabled_eras` | `["1.0A","1.0B"]` | O1 | WP-SECT |
| `pending_eras` | `[]` | O2；開服時套用 | WP-SECT |
| `jail_location` | `"AUTO"` | `AUTO`／`SECT`／`CAPITAL`（O12） | WP-SECT |
| `gb_assembly` | `"DAILY"` | `DAILY`／`MONTHLY`（O8） | WP-SECT |
| `seize_enabled` | true | 捉拿公敵（1.0B 時才有效） | WP-SECT |
| `bank_capacity` | 1000（既有） | 錢莊件數上限 | WP-ECON |
| `bank_money_cap` | 6000000 | 錢莊存款上限 | WP-ECON |
| `consign_fee_base` | 20 | 托鏢基本運費（兩） | WP-ECON |
| `consign_fee_per_weight` | 2 | 每重量單位運費 | WP-ECON |
| `consign_hold_days` | 30 | 沒人領幾遊戲日後退回 | WP-ECON |
| `guild_signers` | 3（既有） | 連署人數（原作 30） | WP-ORG |
| `org_found_fame` | 150 | 幫主名聲門檻【已證實】 | WP-ORG |
| `org_signer_fame` | 20 | 連署人名聲門檻【已證實】 | WP-ORG |
| `org_found_fee` | 10000 | 創立手續費【設計提案】 | WP-ORG |
| `org_member_max` | 50 | 【設計提案】 | WP-ORG |
| `org_petition_days` | 3 | 連署期限（遊戲日）【設計提案】 | WP-ORG |

`AdminSystem.EDITABLE_KEYS` 加：`enable_era_1_0b`（§2.3）、`jail_location`（「監獄位置」）、`gb_assembly`（「丐幫聚會」：每日／每月初）、`seize_enabled`（「捉拿公敵」）。

### 4.12 角色（`core/character/**`，WP-SECT Day-0 全部加好）

`Character.DATA_VERSION` 2 → 3；檔案 `SCHEMA_VERSION` 維持 1。`from_dict` 補預設：

| 欄位 | 預設 | 擁有邏輯 | 說明 |
|---|---|---|---|
| `sect_rank: int` | 0 | WP-SECT | 本派位階；拜入時設成 `promote: JOIN` 的列（0）；離派／叛派歸 0 |
| `sect_rank_pending: Dictionary` | `{}` | WP-SECT | `{ "sect", "rank", "since_world_s" }`：等聚會 |
| `bank: Dictionary` | `{ "money": 0, "items": [] }` | WP-ECON | `items` 用與 `inventory.items` 相同的列形狀（lot、uid） |
| `guild: String` | `""` | WP-ORG | 組織 id 快取（權威在 `world.guilds`；登入時 OrgSystem 校正） |

`to_dict`／`from_dict`／護照（Passport 只帶 `to_dict`；**審查更正**：M3b 以前簽的護照沒有這四個鍵，`Passport.verify` 另用不加這四鍵的舊格式驗，`test_pre_m3b_passport_verifies`）。`Character.add_money` 上限不變（600 萬）。新純函式（WP-SECT 寫骨架，各 WP 填）：`bank_pieces() -> int`、`bank_find(uid) -> Dictionary`。

### 4.13 `world.json`（各系統惰性建立）

| key | 形狀 | 擁有 |
|---|---|---|
| `guilds`（既有空陣列） | `[{ "id": "g1", "name", "status": "PETITION"/"ACTIVE", "leader": char_id, "created_s", "petition_until_s", "signers": [char_id], "members": { char_id: { "rank": 0..4, "title": "", "joined_s" } }, "rank_names": ["幫主","副幫主","長老","堂主","幫眾"], "invites": { char_id: until_world_s } }]` | WP-ORG |
| `consignments` | `[{ "id", "from_char", "from_name", "to_char", "to_name", "from_city", "to_city", "items": [lot…], "money", "sent_s", "arrive_s", "status": "TRANSIT"/"READY"/"RETURNED"/"TAKEN" }]` | WP-ECON |
| `gb_assembly_last_day` | int | WP-SECT（上一次聚會的遊戲日；避免同一天聚兩次） |

---

## 5. 引擎

### 5.1 WP-SECT（門派框架、監獄、捉拿、era；同時是 core 擁有者）

#### 5.1.1 位階與聚會（`SectSystem`）

```
func rank_rows(sect_id: String) -> Array                      # 生效的 sect_ranks 列，依 rank 排序
func rank_name(sect_id: String, rank: int) -> String
func queue_rank(s: Session, sect_id: String, rank: int) -> void   # 任務獎勵呼叫；assembly → pending，否則 _promote
func assembly_tick(now_world_s: float) -> void                # 每個時辰檢查（GameHost._minute_jobs 或 on_clock）
func _promote(ch, sect_id: String, rank: int) -> bool          # 再檢查 requires、扣 cost、sect_rank = rank、事件
func rank_menu(s: Session) -> Dictionary                       # RANK 服務的選單資料
```

- 聚會時刻：`DAILY` = 每個遊戲日進入**辰時**的那一刻；`MONTHLY` = 遊戲日 `day % 30 == 1` 的辰時（`WorldClock.clock().day`）。同一遊戲日只聚一次（`gb_assembly_last_day`）。
- 聚會時：所有**在線**且 `sect_rank_pending.sect` 生效的角色 → `_promote`；不在線的人下次登入時若錯過了至少一次聚會（`since_world_s` 之後有聚會）→ 登入時補升。`requires` 不成立 → 保留 pending，事件 `rank_wait { reason }`。`cost` 不夠扣 → 保留 pending。
- `AUTO` 列：聚會時對在線本派角色檢查 `requires`，成立就升一級（每次聚會最多一級）。
- 事件：`sect_assembly`（給在線本派弟子：「丐幫在總舵聚會…」）、`sect_rank_up { sect_name, rank_name }`（自己＋同派廣播 `other`）。
- 拜入：`sect_rank = 0`；叛派、開除：`sect_rank = 0`、清 pending。
- 角色表 `sect_info.rank`：`{ "level", "name", "pending": { "rank", "name" }|null, "next": { "name", "requires_text": [..] }|null }`。

#### 5.1.2 乞討（門派技能行動練習）

intent `beg { npc }`：驗證順序 `no_character` → `in_battle` → `jailed` → 本派沒有 `practice` → `no_practice` → NPC 不在這間房 `npc_not_here` → NPC 不可乞討（`no_beg`、`kind` 不在清單）→ `cant_beg` → 這個 NPC 對你還在冷卻 `beg_cooldown`（`per_npc_cd_s`，世界秒，存在 `ch.counters["beg_cd"][npc]`）→ 精或神不夠 `not_enough_jing`／`not_enough_shen`。
成功：扣 `cost`；`Learning.practice` 給門派技能熟練 `randi_range(prof)`（會升級就 `skill_up`）；依 `alms` 擲施捨（銀兩或物品）；事件 `beg { npc_name, gain_prof, money, item_name }`（自己）＋`beg` 的 `other` 變體給同房間。乞討不受 `teach_requires`（善惡）限制。`npc_menu` 對可乞討的 NPC 加 `beg: { "ok": bool, "reason": "" }`（只有本派有 `practice` 的人看得到）。

#### 5.1.3 小黃追咬（`harass`）

`on_enter_room`：選項 `sect_hostile_entry` 不影響；角色不在戰鬥中、房間屬於 `regions` 的地區、房間不是 `safe` 也不是有 `INN`／`BANK`／`SHOP` NPC 的室內（只在街道類房間：沒有 `npcs` 帶這些服務），`unless` 都不成立，擲中機率 → `battles.start_ex(s, [monster × count], "HARASS", { "no_flee": false, "pull_party": false })`；同一角色 60 秒內最多一次。小黃 `m_gb_xiaohuang`：氣 60–80、`learn_points: 5`【已證實「一次有5點」】、`combat_xp` 5、不掉東西、`morality_on_kill: 0`。

#### 5.1.4 京城監獄（監獄一般化）

- `jail_room_for(sect_id: String, reason: String) -> String`：
  - 解析 `jail_location`：`AUTO` → 有生效的 `jail_scope: "CAPITAL"` 房間就 `CAPITAL`，否則 `SECT`。
  - **審查修正**：`AUTO` 的 `CAPITAL` 只用在 `reason == "ENEMY"`；`BREACH` 用 `breach_jail_resolved()`（只有選項明寫 `CAPITAL` 才是 `CAPITAL`，`AUTO` 一律 `SECT`）。`world_info.jail_breach_resolved` 給客戶端與 bot。
  - `CAPITAL`：`reason == "ENEMY"` → 京城牢房（不看本派有沒有執法者）；`reason == "BREACH"` → 本派 `can_jail_in`（有執法者）才回京城牢房，否則 `""`（→ BAN）。
  - `SECT`：M3a 行為（本派 `jail_room`）。
- `_jail_char` 改用 `jail_room_for`；`ch.jail` 多記 `"scope": "SECT"/"CAPITAL"`。
- `release`：`scope == "CAPITAL"` → 送到牢房的 `jail_release_to`（`jc_yamen`）；否則照舊送山門。公敵改過自新、叛徒記號不消（M3a）照舊。
- `capture_on_death`：M3a 的 `can_jail_in(x)` 檢查改成 `jail_room_for(x, "ENEMY") != ""`。
- 贖人：京城監獄看守人 `n_jc_jailer`（`JAIL` 服務）＝ M3a `jail_ransom`（`prisoners_in(room)` 不變）。
- 獄中限制、上線秒計時、出獄 tick 全部沿用 M3a §6.6。

#### 5.1.5 捉拿公敵（1.0B）

intent `seize_enemy { name }`：`no_character` → `in_battle` → `jailed` → 1.0B 沒開或 `seize_enabled == false` → `era_locked`／`seize_disabled` → 自己沒有門派 `no_sect` → 目標不在同房間 `not_here` → 目標不是本派公敵（`enemy_of` 不含本派）`not_enemy` → 目標實戰 < `newbie_pk_protect_xp` → `target_newbie_protected` → 房間不能 PK 且不屬於本派地區 `no_pk_here` → 目標在戰鬥中 `target_busy`。
成功：`PkSystem` 開 `kind: "SEIZE"` 的 PvP（拉本隊同房閒置隊友；目標不拉隊友【設計提案】；目標可逃）。結算：抓的人**不**加 PK 值、殺氣、善惡；目標死亡 → 死亡懲罰照世界規則 ＋ `capture_on_death`（`killed_by.sect` = 抓的人的門派）→ 關進牢房（`ENEMY`，`jail_enemy_days`）。事件 `seize_start`（雙方）、`seize_done { name, sect_name }`（全服 SYSTEM）。
`player_tags` 加 `seizable: bool`（對方是我派公敵）；玩家選單多「捉拿」。

#### 5.1.6 京城兵器鋪拒賣（`shop.refuse_if`）

`NpcSystem` 的 `shop_list`／`buy`：`refuse_if` 任一組全部成立 → `buy` 回 `shop_refused`，`shop_list` 照樣列出但帶 `refused: true` 與文字。

#### 5.1.7 毒牙與觸發消耗統一（`core/battle/**`）

- `POISON_FANG`：門派技能觸發（`later_battle_cmds` 開時；M3A_PLAN §5.6 的機率公式）→ 對目標施加 `poison`，等級 = `1 + floor(乞討/25)`，消耗精、神（`sect_skill_cost`）。
- D12（O20）：DEFENSE、RECOVER 觸發也照 `sect_skill_cost` 扣精／內力（數值同 M3a 新 8 種）。`tools/regen_battle_golden.gd` 重產 `tests/fixtures/battle_golden_01.json`，交付說明列出哪幾回合變了；`balance_sim` 全部案例仍要過。

#### 5.1.8 戰鬥結算掛鉤（`server/battle_system.gd`）

`_settle_*` 結束後依 `kind` 呼叫：`HUNT` → `host.life.on_hunt_settled(s, ch, summary)`；`HARASS` → 無（一般獎勵）；`SEIZE` → `host.pk.on_pvp_end(summary)`（同 FORCED 路徑但不加懲罰）。新 kind 的逃跑、獎勵照 `opts`。

#### 5.1.9 出生與 era

- `intents_char.gd` `char_create`：出生城清單 = 生效 `regions` 中 `birth_allowed: true` 的 `CITY`（1.0B 多京城）。
- `world_server.gd`：§2.1、§2.3 的 `default_eras`、`pending_eras`。
- `region_system.gd`：`on_enter_status`（§4.10）、`desc_1_0b`（由 `DataLoader.activate` 處理，WP-SECT 擁有 `core/data/**`）。

### 5.2 WP-ECON（錢莊、鏢局、生活技能）

#### 5.2.1 錢莊（`server/bank_system.gd`，`class_name BankSystem`，`GameHost.bank`）

```
func open(s: Session, npc_id: String) -> Dictionary            # 送 bank_view
func put(s: Session, npc_id: String, uid: String, n: int) -> Dictionary
func take(s: Session, npc_id: String, uid: String, n: int) -> Dictionary
func money(s: Session, npc_id: String, amount: int) -> Dictionary   # >0 存、<0 領
func view(ch) -> Dictionary   # { money, items:[{uid,item_id,name,n,weight}], used, capacity, money_cap }
```

驗證順序（每個 intent）：`no_character` → `in_battle` → `jailed` → NPC 不在／沒有 `BANK` → `not_at_bank`；`put`：找不到 `no_such_item` → 裝備中 `equipped_item` → `quest_item`／`bankable: false` → `not_bankable` → 件數超過 `bank_capacity` → `bank_full`；`take`：找不到 `no_such_item` → 拿了會超重或超過 300 件 → `too_heavy`／`too_many`；`money`：存 > 身上 `not_enough_money`、存後 > `bank_money_cap` → `bank_money_cap`；領 > 存款 `not_enough_bank_money`、領後身上 > 600 萬 → `money_cap`。
堆疊物品可部分存取（`n`）；lot 資料（腐壞戳記）存進錢莊時**凍結**：取出時把 `spoil` 起點平移存放時間（O15「不腐壞」）。成功送 `bank_view`（ui）與 `bank_put`／`bank_take`／`bank_money` 系統訊息；`sheet_dirty`。存檔隨角色檔（重開不丟）。

#### 5.2.2 托鏢與取貨（`server/escort_system.gd`，`class_name EscortSystem`，`GameHost.escort`）

```
func send(s: Session, npc_id: String, to_name: String, to_city: String, items: Array, money: int) -> Dictionary
func list(s: Session, npc_id: String) -> Dictionary    # 在這個城的鏢局等你領的、你寄出還在路上的
func take(s: Session, npc_id: String, cid: String) -> Dictionary
func tick(now_world_s: float) -> void                  # TRANSIT → READY（到站，通知在線收件人）；READY 過期 → RETURNED（回寄件城）
```

- `send`：NPC 有 `ESCORT` 且 `escort.city` = 寄件城；`to_city` 有 `escort_routes` 列（`from_city` = 寄件城）→ 否則 `no_route`；收件角色名存在（`char_names`）→ 否則 `no_such_char`；不能寄給自己 `self_target`；物品可寄（同錢莊規則，`not_bankable`）；運費 = `consign_fee_base + consign_fee_per_weight × 總重`，錢不夠 `not_enough_money`；`items` 最多 10 個 uid、`money` ≤ 身上錢。成功：從身上移除、寫 `world.consignments`、`arrive_s = now + consign_delay_shichen × 時辰長`；事件 `consign_sent`。
- 到站：在線收件人收到 `consign_arrived { from_name, city_name }`；離線的人登入時收到（`mail_waiting` 同一個時點）。
- `take`：`READY`（或 `RETURNED` 且你是寄件人）、你在 `to_city`（退回時是 `from_city`）的鏢局 → 放進身上（超重 `too_heavy`，不拿任何東西）→ `TAKEN` 並移除該列。
- 不會被劫（O16）。

#### 5.2.3 保鏢工作

用故事引擎（§4.9 列）；WP-ECON 只負責 `_econ.json` 的 6 條任務、`n_ec_biaoche`、鏢頭 NPC（`n_ec_xx_biaotou`、`n_ec_dl_biaotou`、`n_ec_jc_biaotou`，`services: ["ESCORT","QUEST"]`）、錢莊 NPC（`n_ec_xx_banker`、`n_ec_dl_banker`、`n_ec_jc_banker`，`services: ["BANK"]`；京城三位 `era: "1.0B"`、`room` 在 jingcheng 碎片的房間）。酬勞：西夏↔大理 150 兩＋名聲 3；西夏／大理↔京城 200 兩＋名聲 4【設計提案】；冷卻 1 遊戲日；組隊可同時完成（`party_credit`）。

#### 5.2.4 生活技能引擎（`server/life_system.gd`）

- `work(s, skill_id, recipe_id)` 照 §4.5：驗證順序 `no_feature`（配方 feature 覆寫）→ `not_known` → `no_tool`（`tool` 與 `tools`、配方 `tools`）→ `busy` → `not_enough_jing` → `no_recipe`／`recipe_level`／`no_ingredients`；打鐵配方的「3 個同等級礦」直接寫成 `inputs` 的同一 id ×3（每級一條配方），不需要特殊規則。
- `HUNT`：`recipe == ""`、房間有 `HUNT` 與 `hunt_table` → 擲一隻 → `battles.start_ex(s, [m], "HUNT", { "pull_party": false })`；扣精、設冷卻在開戰時。`on_hunt_settled`：本人勝利 → `Learning.practice_life(success=true)`＋`hunt.drops`（`monsters` 有寫時只對那些怪）；逃跑或失敗 → `practice_life(false)`。
- 產出放不下：維持 M1 缺漏處理（作廢），但改成**先檢查**：會超重或滿件時回 `too_heavy`，不扣精、不扣材料。
- 學習：`masters` 列（`skill_id` = 生活技能 id）照舊；新 7 種的教學 NPC 由 lifeskills_content 放（§8.3）。

### 5.3 WP-ORG（組織；`server/org_system.gd`，`class_name OrgSystem`，`GameHost.orgs`）

```
func found(s: Session, npc_id: String, name: String) -> Dictionary
func sign(s: Session, npc_id: String, org_id: String) -> Dictionary
func invite(s: Session, target_name: String) -> Dictionary
func reply(s: Session, org_id: String, accept: bool) -> Dictionary
func leave(s: Session) -> Dictionary
func kick(s: Session, target_name: String) -> Dictionary
func set_rank(s: Session, target_name: String, rank: int) -> Dictionary
func set_rank_names(s: Session, names: Array) -> Dictionary
func set_title(s: Session, target_name: String, title: String) -> Dictionary
func transfer(s: Session, target_name: String) -> Dictionary
func disband(s: Session, confirm: bool) -> Dictionary
func info(s: Session) -> Dictionary                 # 送 org_info
func members_online(org_id: String) -> Array        # SocialSystem 的 CHAT_GUILD 用
func on_login(s: Session) -> void                   # 校正 ch.guild、送待處理邀請
func tick(now_world_s: float) -> void               # 連署過期
```

規則：
- **創立**（`found`，在 `ORG` NPC 前）：不在組織 `already_in_org` → 名聲 ≥ `org_found_fame` `req_fame_min` → 錢 ≥ `org_found_fee` `not_enough_money` → 名字 2–8 個字、只能中日韓文字與數字、不得重複（含連署中的）`bad_org_name`／`org_name_taken` → 你沒有別的連署中組織 `already_petitioning`。扣手續費（連署失敗不退【設計提案】）、建 `PETITION`（`petition_until_s = now + org_petition_days × day_s`）；事件 `org_petition { name }`（全服 SYSTEM：「某某發起創立組織『X』，名聲 20 以上的人可到各城衙門連署」）。
- **連署**（`sign`，在任一 `ORG` NPC 前）：組織是 `PETITION` → 自己不是發起人 → 不在組織 → 名聲 ≥ `org_signer_fame` → 沒簽過。簽滿 `guild_signers` 人 → `ACTIVE`：發起人位階 0（幫主），連署人位階 4（幫眾）並成為成員（O14）；事件 `org_founded`（全服）。過期 → 刪除，事件 `org_petition_expired`（發起人）。
- **邀請**：位階 ≤ 1 的人可邀請；目標在線、不在組織、人數 < `org_member_max`；邀請 60 遊戲秒（`pending_ttl_real_s` 換算）內有效；目標送 `org_reply`。開除：位階數字大於自己的人才能踢；幫主不能被踢。退出：幫主要先移交或解散（`leader_must_transfer`）。
- **位階**：5 級（0 幫主 … 4 幫眾），名稱由幫主設（每個 1–4 字）；`set_rank` 只有幫主；不能設 0（移交才行）。封號 `set_title`：幫主與副幫主可封，0–6 字。
- **解散**：幫主、`confirm: true`（客戶端兩段確認）；所有成員 `guild = ""`；事件 `org_disbanded`。
- **組織頻道**：`SocialSystem` 的 `CHAT_GUILD`：不在組織 → `no_guild`（既有原因碼）；否則送給 `members_online`；耗水照既有頻道設定（懷舊指南：耗水）。
- **天地會**不是組織：會籍是旗標 `tdh_member`（入會任務給）；`org_info` 多一欄 `societies: ["天地會"]`（`OrgSystem.SOCIETY_FLAGS := { "tdh_member": "天地會" }`），角色表同。
- 角色表 `org: { "id", "name", "rank", "rank_name", "title", "leader_name", "members_online" }|null`；玩家選單（點名字）多「邀請入組織」（自己有權限且對方不在組織）。

### 5.4 故事引擎缺口（WP-SECT 擁有 `server/quest_system.gd` 的這兩點）

- 獎勵 `sect_rank`（§4.9）。
- 物品 `unique_per_char`（絕情丹）：`give`／獎勵給這種物品時，身上已有就不給（任務不失敗）。
- 其他需求都用現有引擎：護送（保鏢）、`room_actions`（乞討不用、拓印、鬥酒、毒物點）、`WAIT hours`、`BUY`、`STATE`、`npc_links`。

---

## 6. 協定增量（`core/protocol.gd`，WP-SECT Day-0；`VERSION` 維持 5）

**Intent**（全部加進 `INTENT_SCHEMA`；處理器所在檔案在右欄）

| kind | 參數 | 檔案（WP） |
|---|---|---|
| `beg` | `npc: String` | `intents_sect.gd`（SECT） |
| `seize_enemy` | `name: String` | `intents_pk.gd`（SECT） |
| `bank_open` | `npc: String` | `intents_econ.gd`（ECON） |
| `bank_put` | `npc: String`, `uid: String`, `n: int` | 同上 |
| `bank_take` | `npc: String`, `uid: String`, `n: int` | 同上 |
| `bank_money` | `npc: String`, `amount: int` | 同上 |
| `consign_send` | `npc: String`, `to: String`, `city: String`, `items: Array`（`[{uid, n}]`）, `money: int` | 同上 |
| `consign_list` | `npc: String` | 同上 |
| `consign_take` | `npc: String`, `id: String` | 同上 |
| `org_found` | `npc: String`, `name: String` | `intents_org.gd`（ORG） |
| `org_sign` | `npc: String`, `org: String` | 同上 |
| `org_invite` | `name: String` | 同上 |
| `org_reply` | `org: String`, `accept: bool` | 同上 |
| `org_leave` | — | 同上 |
| `org_kick` | `name: String` | 同上 |
| `org_set_rank` | `name: String`, `rank: int` | 同上 |
| `org_rank_names` | `names: Array` | 同上 |
| `org_title` | `name: String`, `title: String` | 同上 |
| `org_lead` | `name: String` | 同上 |
| `org_disband` | `confirm: bool` | 同上 |
| `org_info` | — | 同上 |

`work` 不變（`skill`、`recipe`）。`debug_set` 新 key：`sect_rank`（int，自己本派）、`guild`（不支援，回 `bad_key`）、`assembly_now`（觸發一次聚會）、`bank_clear`（清自己的錢莊，測試用）。

**事件**（模板由 `_sect.json`／`_econ.json`／`_org.json` 提供；`ui` 標記的走 `"ui": true`）：
`beg`、`sect_assembly`、`sect_rank_up`、`rank_wait`、`seize_start`、`seize_done`、`shop_refused`、`bank_view`(ui)、`bank_put`、`bank_take`、`bank_money`、`consign_sent`、`consign_list`(ui)、`consign_arrived`、`consign_taken`、`consign_returned`、`org_info`(ui)、`org_petition`、`org_signed`、`org_founded`、`org_petition_expired`、`org_invite`(ui，pending prompt)、`org_joined`、`org_left`、`org_kicked`、`org_rank_changed`、`org_title_changed`、`org_leader_changed`、`org_disbanded`、`hunt_start`。

**原因碼**：`no_practice`、`cant_beg`、`beg_cooldown`、`not_enough_shen`、`era_locked`、`seize_disabled`、`not_enemy`、`target_newbie_protected`（既有）、`no_pk_here`、`target_busy`、`shop_refused`、`not_at_bank`、`not_bankable`、`bank_full`、`equipped_item`、`no_such_item`、`too_heavy`、`too_many`、`bank_money_cap`、`not_enough_bank_money`、`money_cap`、`no_route`、`no_such_char`、`self_target`、`already_in_org`、`bad_org_name`、`org_name_taken`、`already_petitioning`、`not_petition`、`already_signed`、`org_full`、`no_permission`、`leader_must_transfer`、`no_invite`、`req_sect_not`、`req_sect_rank_min`、`req_org_member`、`req_no_org`、`req_life_min`。

**npc_menu 新欄位**：`bank: bool`、`escort: { "city", "city_name", "ready": int, "routes": [ { "city", "city_name", "delay_text" } ] }|null`、`org: { "petitions": [ { "id", "name", "leader_name", "signed", "need" } ], "can_found": bool, "fee": int }|null`、`rank: { …§5.1.1 rank_menu… }|null`、`beg: { "ok", "reason" }|null`、`shop.refused: bool`（`shop_list` 內）。

**角色表新欄位**：`sect_info.rank`（§5.1.1）、`org`（§5.3）、`societies: [String]`、`jail.scope`。**world_info 新欄位**：`jail_location_resolved: "SECT"|"CAPITAL"`、`gb_assembly`、`seize_enabled`、`pending_eras`。**player_tags**：`seizable: bool`、`org_name: String`。

`NPC_SERVICES`、`UiKeys.SERVICES` 加 `BANK`、`ESCORT`、`ORG`、`RANK`；`SERVICE_LABELS`：錢莊、鏢局、組織、袋位。`FEATURES` 加 `MINE FORGE CAST LOOM TANNERY KILN HUNT`。

---

## 7. 介面（WP-UI；`ui/**`、`autoload/scene_router.gd`）

照 `docs/AUTHENTIC_UI_SPEC.md` 的玉石框、燈籠、卷軸風格；新視窗都能用 Esc 關、數字鍵選。

1. **錢莊窗**（`ui/game/econ/bank_window.gd`）：左身上、右錢莊兩欄清單（名稱、數量、重量），中間「存入／取出」與數量輸入；上方存款與身上銀兩、「存錢／領錢」；底部「已用 n／1000 件」。開窗＝ npc_menu「錢莊」→ `bank_open`。
2. **鏢局窗**（`ui/game/econ/escort_window.gd`）：分頁「托鏢」（收件人名、目的城下拉＋送達時間、選物品與銀兩、即時運費）、「取貨」（`consign_list`，到站的可領）、「保鏢」＝既有任務選單（服務「任務」）。
3. **製作窗**（`ui/game/econ/craft_window.gd`）：從場景卷軸的生活技能按鈕或指令窗「生活」開；依房間設施列出可用技能與配方（材料夠的亮、不夠的灰並寫缺什麼、等級不夠寫「需 N 級」、缺工具寫工具名）；採集與打獵直接按鈕。結果訊息走系統框。
4. **組織面板**（`ui/game/social/org_panel.gd`）：燈籠「指令 → 組織」；顯示組織名、你的位階與封號、成員表（在線標記、位階、封號）；有權限的按鈕：邀請、開除、設位階、封號、改位階名稱、移交、解散（兩段確認，第二段輸入組織名）、退出；沒組織時顯示「到各城衙門找書吏創立或連署」與天地會會籍（如果有）。衙門書吏選單：創立（輸入名字、顯示費用與名聲條件）、連署清單。組織邀請用既有 pending prompt。
5. **袋位顯示**：屬性燈籠的門派欄加「袋位：一袋弟子」，待升時加「（待聚會）」；陳長老選單「袋位」頁列出每一袋的條件與任務。
6. **乞討**：npc_menu 多「乞討」選項（灰掉時附原因：冷卻剩幾分、精神不足）；指令窗「行動」裡也有，對目前選取的 NPC。
7. **監獄畫面**：沿用 M3a 坐牢提示條，`scope == "CAPITAL"` 時寫「京城監獄」；看守人選單沿用。
8. **捉拿公敵**：玩家選單「捉拿」（`seizable`），確認窗「確定要捉拿本派公敵 X？」；指令窗「雜項 → 捉拿公敵」列出同房可抓的人。
9. **伺服器設定面板**：新 4 列（§4.11）；`enable_era_1_0b` 已開放時顯示「已開放」灰掉，`pending_eras` 非空時顯示「下次開服生效」。
10. **創角**：出生城依 `world_info` 生效地區（1.0B 多京城），說明文字「京城（神鵰大俠）」。
11. **地圖**：新地區照 `world_pos` 出現在大地圖；1.0A 世界不顯示 1.0B 地區（既有 era 機制）。
12. 測試：`tests/unit/test_ui_m3b_econ.gd`、`test_ui_m3b_org.gd`、`test_ui_m3b_sect.gd`（建窗、餵假資料、按鈕送出的 intent 形狀正確）。

---

## 8. 碎片格式（`docs/m3b_staging/<key>.json`）

### 8.1 結構（每個建造者**只寫自己的一個檔案**）

M3A_PLAN §4.1 與 STORY_PLAN §7.1 的聯集：

```json
{
  "fragment": "gaibang", "version": 1, "author": "WP-C-gaibang",
  "sects": [ "…§4.1…" ], "sect_rules": [ "…" ], "sect_ranks": [ "…§4.2…" ],
  "regions": [ "…§3.1 形狀…" ],
  "maps": { "gaibang": { "region_id": "gaibang", "era": "1.0B", "src": "proposal", "desc": "…", "escape_tiles_hint": 2, "rooms": [ "…" ] } },
  "extra_rooms": { "yanmen": [ "…只限 §3.2 表…" ] },
  "exit_patches": [ { "room": "ym_road", "add_exits": [ { "dir": "E", "to": "jcn_road4", "era": "1.0B" } ], "desc_1_0b": "…" } ],
  "npcs": [ "…" ], "masters": [ "…" ], "martial_arts": [ "…" ], "monsters": [ "…" ], "items": [ "…" ],
  "item_patches": [ { "id": "r_kuang_lv", "set": { "grade": 2 } } ],
  "shop_patches": [ { "npc": "n_xx_smith", "add_items": [ "t_shizigao" ] } ],
  "npc_links": [ { "npc": "n_xx_zhangtie", "add_quests": [ "q_sm_yuntie" ] } ],
  "life_skills": [ "…§4.5，只有 lifeskills_content…" ],
  "escort_routes": [ "…§4.7，只有 _econ…" ],
  "status_effects": [ "…§4.10，只有 jueqinggu…" ],
  "quests": [ "…STORY_PLAN §4.2 第 2 版…" ],
  "text_templates": [ "…" ], "rumors": [ "…" ], "ambient": [ "…" ],
  "patches_1_0b": [ "…data/patches/1.0B.json 的列（只限既有 NPC 的 travel 等；見下）…" ],
  "art_requests": { "units": [ { "id": "gaibang_m", "alias": "shaolin_m", "prompt": "…" } ], "backgrounds": [ { "id": "gaibang", "alias": "shaolin", "prompt": "…" } ] },
  "test_plan": [ "…STORY_PLAN §7.1 的 bot 動作語彙…" ],
  "todo_verify": [ "…【待考證】…" ], "owner_decisions": [ "O4", "O6", "…" ], "notes": ""
}
```

- 每列形狀**完全照** `data/<table>.json` 現有列＋本文件新欄位；每列都要 `era`、`src`，有研究依據加 `src_note`。
- `maps` 只能是本碎片擁有的地區（§3.1 表），或 jingcheng 對 `jingcheng`、`jingcheng_wild` 的完整替換。`extra_rooms`、`exit_patches`、`item_patches`、`shop_patches` 只能動 §3.2／§3.3 列出、或本節明列的對象。
- `npc_links` 只能追加 `quests`。**NPC 的 `room` 可以指向別的碎片的房間**（例：`_econ` 的錢莊 NPC 放在 jingcheng 的 `jc_bank`）；WP-MERGE 依 `npcs[].room` 自動把 NPC id 加進該房間的 `npcs`（碎片不寫別人房間的 `npcs` 陣列）。
- 跨碎片引用只能用 §8.3 表列出的固定 id。
- `patches_1_0b`：只給 jingcheng（`n_xx_station`、`n_dl_station` 的 `travel` 已在 1.0B patch，不動）；其他碎片不得寫。
- `test_plan`：每條新任務每個結局至少一條（STORY_PLAN §7.1 語彙；`walk@room` 會用區域圖找路）；整合者的 story bot 直接跑。
- 合法 JSON、繁體中文、不得有簡體字；房間 desc 1–2 句；對白每段 3–8 節點、照原著口吻。

### 8.2 每個碎片的必備內容（共同）

1. §3 指定的房間 id、出口、地區列；遇敵表遵守 §3.4。
2. 每個 NPC 有 `talk_<npc>` 模板；新地區每間房有 desc；每個新怪有 desc 與 `src`（數值【設計提案】照 `monsters.json` 級距，balance_sim 驗證）。
3. `art_requests`：每個新地區一張背景、每個有立繪價值的 NPC、每種新怪；`alias` 指到 `data/art.json` 現有條目。
4. `todo_verify` 列出所有【待考證】；`owner_decisions` 列出採用的 §1.3 編號。

### 8.3 各碎片內容要點與固定 id

**WP-C-gaibang**（`docs/m3b_staging/gaibang.json`；研究「丐幫」）

| 類 | 固定 id 與內容 |
|---|---|
| 門派 | `gaibang`（§4.1 原樣）；`sect_rules`：`gb_r_kill_same`（EVENT `KILL_SAME_SECT`，模板 `rule_gb_kill_same`，src later 官方）。沒有 STATE 規則（善惡 < 0 是停止傳功，已在 `teach_requires`） |
| 位階 | `sect_ranks` `gb_dai0`–`gb_dai7`（§4.2；三袋以上 era `xkd`） |
| 地區 | `jingcheng_north`（`jcn_road1`–`jcn_road4`、`jcn_kongdi`）、`gaibang`（`gb_gate` 破廟門口、`gb_pomiao` 破廟正殿、`gb_houdian` 後殿、`gb_yuan` 破廟後院）；`exit_patches` 只有 `ym_road`（#22） |
| NPC | `n_gb_chen` 陳長老（`gb_pomiao`；`JOIN`、`BETRAY`、`RANK`、`QUEST`、`TEACH`（只教 `qitao` 到 10，O7））；`n_gb_chuangong` 傳功長老（`gb_houdian`；`TEACH` 全部丐幫武功與基本武學：基本拳腳、基本棍法、基本刀法、基本暗器、基本內功、基本招架、閃躲縱躍，上限 140【後期版】）；`n_gb_zhanggun` 掌棍長老（`gb_yuan`；`QUEST`；src_note 寫「2001-11-23 掌棍長老，後期掌棒龍頭」）；`n_gb_zhifa` 執法長老（`gb_yuan`；只對話；預告「四大長老」）；`n_gb_spar` 丐幫弟子（`gb_houdian`；`FIGHT` → `m_gb_dizi`，限本派）；`n_gb_jiang` 姜乞丐（`jc_square`，「錢莊前」2002-07；二袋任務）；`n_gb_youqiming` 游啟（`xx_pharmacy`「藥店門口」）；`n_gb_pan` 潘乞兒（`dl_wuguan`「武館門口」；名字只知「潘**」【待考證】）；`n_gb_shenyi` 神醫（`dl_shop`；大理沒有藥店房，放雜貨鋪【設計提案】）；`n_gb_jc_informant` 轉角的漢子（`jc_smithy`「兵器店轉角」）；`n_gb_dl_qigai` 丐幫弟子（`dl_square`「大理菜商上方」，送信任務收信人） |
| 武功 | 一階（`requires` 只有 `sect` 與下列門檻；招式名【設計提案】，射程照研究）：`gb_xinfa` 丐幫心法（INNER）、`gb_taizu_quan` 太祖長拳（FIST，CROSS，係數 0.99）、`gb_taizu_gun` 太祖棍法（STAFF，CROSS，0.75）、`gb_liuhe_dao` 六合刀法（BLADE，CROSS，0.95）、`gb_tongchui` 銅鎚手（FIST，**CROSS_L**，0.90；`skill_min gb_xinfa 10`、`skill_min qitao 10`）、`gb_mantian` 滿天花雨（HIDDEN；todo_verify：基本武功只有含糊單一來源）。二階（`tier: "ADVANCED"`，全部加 `sect_rank_min gaibang 2`，上限 60）：`gb_fengmo` 瘋魔杖法（STAFF，1.337；太祖棍法 50、心法 30、乞討 30【已證實 2001-12-01】）、`gb_chansi` 纏絲擒拿手（FIST，1.3；太祖長拳 50、心法 30、乞討 30）、`gb_qinlong` 擒龍功（FIST，1.25；銅鎚手 50、心法 30、乞討 30）、`gb_huntian` 混天功（INNER【待考證：類別】；擒龍功 30、心法 30、乞討 30）、`gb_lianhua` 蓮花掌（FIST，1.424；纏絲 30、心法 30、乞討 30）。後四套門檻【設計提案】比照瘋魔 |
| 師父 | `ms_gb_*`：陳長老教 `qitao`（cap 10）；傳功長老教上表全部（一階 cap 100【設計提案】、二階 cap 60） |
| 怪 | `m_gb_dizi`（切磋）、`m_gb_xiaohuang` 小黃（§5.1.3）、`m_gb_xiejiao` 邪教門徒（氣 300【已證實】）、`m_gb_manbing` 蠻兵（原作 100000 HP；依本作級距換算，balance_sim 案例「3 人、各實戰 2 萬勝、兩人打不過」【設計提案】；審查 3 從「各 6 萬」改，見 13.7）、北郊：`m_jcn_mazeitou` 馬賊頭子、`m_jcn_mazeiwang` 馬賊王（氣 2000、建議實戰 18 級量、掉 `a_jcn_huangzhaojia` 黃罩甲 +35【已證實 gaoshou/25】）、`m_jcn_edaotou` 惡道人頭子、`m_jcn_daoren` 道人頭子、`m_jcn_yinmian` 隱面人、`m_jcn_huguo` 護國法師、`m_jcn_shafeng` 煞風寨寨主（後兩者只在 `jcn_road4`） |
| 任務 | `q_gb_dai1` 一袋（陳長老；名聲／歷練 ≥ 250；情報三城：游啟 → 潘乞兒 → 神醫 → 京城轉角漢子；三次橋上埋伏：房間動作在 `ym_bridge`、`rr_bridge`（大理北的石橋）、`jcn_road3`，各限一個時辰【設計提案：時辰】，每次 `fight` 7 個邪教門徒 `no_flee: true`；逃跑 → `WAIT days=1` 再來；KILL `m_gb_xiejiao` 共 20【已證實 ≥ 20】→ 陳長老 → `sect_rank {gaibang,1}`）；`q_gb_dai2` 二袋（姜乞丐；500/500、一袋 → 蠻族情報 → 掌棍長老 → 三封信 DELIVER 給 游啟、潘乞兒、轉角漢子 → 三場蠻兵（各在 `jcn_road4`、`dlw_forest`、`xw_hill` 房間動作）→ 陳長老 → `sect_rank {gaibang,2}`；升袋時扣 250/250 由 `sect_ranks.cost` 處理）；`q_gb_xin` 丐幫送信（游啟 → `n_gb_dl_qigai`，名聲 +1 歷練 +1，可重複、冷卻 0.5 遊戲日【設計提案】；`requires sect gaibang`） |
| 模板 | 每個 NPC 的 `talk_*`（陳長老、執法長老用預告文字：淨衣污衣、污衣戒律、四大長老、「不敬尊長、毆傷長老是丐帮大忌」）、`rule_gb_kill_same`、`beg`（self/other，含施捨與沒討到兩種）、`harass_gb`（小黃撲上來）、`sect_assembly`、`sect_rank_up` |
| 美術 | `gaibang_m`、`gaibang_f`（補丁百衲衣、草鞋、竹棒）、背景 `gaibang`（破廟）、`jingcheng_north`（山路）、立繪 陳長老、傳功長老、掌棍長老、姜乞丐、怪 小黃、邪教門徒、蠻兵、護國法師、煞風寨寨主 |
| test_plan | `q_gb_dai1`、`q_gb_dai2`、`q_gb_xin` 各一條（bot 用 `debug_set` 名聲、歷練、`sect_rank`） |

**WP-C-jingcheng**（`jingcheng.json`；研究「京城與範圍」「經濟」「未做的事件」）

| 類 | 固定 id 與內容 |
|---|---|
| 地區與地圖 | `jingcheng` 改 `birth_allowed: true`、`birth_room: "jc_square"`；`maps.jingcheng` 完整：既有 4 間＋`jc_square` 京城廣場、`jc_bank` 京城錢莊、`jc_biaoju` 中華鏢局【已證實名】、`jc_yamen` 京城衙門、`jc_jail_gate` 監獄門口、`jc_jail` 京城監獄（`jail: true`、`jail_scope: "CAPITAL"`、`jail_release_to: "jc_yamen"`、`requires` 只許坐牢中的人進、`safe: true`）、`jc_buzhuang` 京城布莊（`LOOM`、`TANNERY`）、`jc_pharmacy` 京城藥鋪、`jc_street_n` 北大街、`jc_smithy` 京城兵器鋪、`jc_tiepu` 京城打鐵舖（`FORGE`、`CAST`、`KILN`）、`jc_zijin` 紫禁城外（DIAO《紫禁城》；只有外景與守門侍衛）、`jc_coffin` 棺材鋪、`jc_tdh_hall` 天地會香堂（`requires`: `any_of [[quest_flag tdh_member], [quest_stage q_tdh_ruhui s_hall]]`）、`jc_gate_n` 京城北門；`maps.jingcheng_wild` 完整（3 間保留，遇敵表加 `m_jc_qigaitou`、`m_jc_buliang`【已證實 2001-10-13 京城門口 0–10 級】） |
| NPC | `n_jc_cha_n` 查小鏞（北門，`RESPAWN`）、`n_jc_guard_n` 守衛；`n_jc_jailer` 監獄看守人（`jc_jail_gate`，`JAIL`）；`n_jc_bukuai` 捕快（`jc_yamen`，對話：懸賞 M3c）；`n_jc_smith` 兵器防具鋪老闆（§4.8 `refuse_if`）；`n_jc_pharmacist` 藥鋪（`SHOP`）；`n_jc_zijin_guard` 侍衛；`n_tdh_zhanggui` 棺材鋪掌櫃（天地會聯絡人）；`n_tdh_chenjinnan` 陳近南（`jc_tdh_hall`）；`n_tdh_shop` 天地會管事（`jc_tdh_hall`，`SHOP`，`shop.refuse_if: [[ {not_flag tdh_member} ]]`）。既有 `talk_n_jc_guard` 改「南門外往華山、少林的路都通；東南小路進得去山谷，北門出去是往丐幫和雁門關的山路。」 |
| 任務 | `q_tdh_ruhui` 天地會入會（【設計提案】依 DIAO「嚴密審核、交辦事宜、確定忠誠度」：棺材鋪掌櫃對暗號（選項原樣：「地振高岡，一派溪山千古秀」「門朝大海，三河合水萬年流」——《鹿鼎記》天地會切口）→ 交辦：送密函到大理衙門的王捕頭並把回條帶回（DELIVER）→ 忠誠考驗：衙門捕快以銀兩利誘（選「收下」→ 任務失敗、30 遊戲日內不能再接；選「拒絕」→ 繼續）→ 香堂見陳近南 → `flags: ["tdh_member"]`、名聲 +20；`requires`：善惡 ≥ 0、實戰 ≥ 5000【設計提案】；一次）。1.0B 事件三條：`q_jc_xiaobao` 李大嬸找小保（第七話；小保迷路在京城 → 找到後帶回 ESCORT）、`q_jc_lingquan` 靈犬小黃（第七話標題【已證實】；「京城的狗討食」這個題材是【設計提案】，研究沒有預告原文（審查 4）：買肉包餵三隻小黃；丐幫弟子做有額外對白）、`q_jc_zhangyuanwai` 愛好礦石的張員外（第九話，大理；收購紫石礦 → 銀兩，接上生活技能經濟；`npc_links` 給大理既有房間的新 NPC `n_jc_zhangyuanwai`（room `dl_square`））——都是【設計提案】，`src: "proposal"`、`src_note` 引預告原文 |
| 商店 | 天地會商店【設計提案】：解毒靈藥、金創藥、蒙汗藥（暗器彈藥 `hidden`）、夜行衣（防具）；京城藥鋪：一般藥品；兵器鋪：比照西夏 |
| 美術 | 背景 `jingcheng`（街坊）、`jingcheng_wild`、`jc_jail`（牢房）、`jc_tdh_hall`；立繪 陳近南、監獄看守人、棺材鋪掌櫃 |

**WP-C-jueqinggu**（`jueqinggu.json`；研究「未做的事件」絕情谷、「經濟」1.0B 項目）

| 類 | 固定 id 與內容 |
|---|---|
| 地區 | `jueqinggu`（`jq_road1` 谷外山道、`jq_gukou` 谷口、`jq_qinghua` 情花林（`on_enter_status` 情花毒）、`jq_shiwu` 石屋大廳、`jq_danfang` 丹房、`jq_shufang` 書房、`jq_jianfang` 劍房、`jq_duanchang` 斷腸崖）、`jueqinggu_dilao`（`jq_dilao1`–`jq_dilao3`、`jq_eyuchi` 鱷魚池）；`exit_patches` 只有 `jcw_crossroad`（#26） |
| NPC | `n_jq_gongsunzhi` 公孫止（`jq_shiwu`）、`n_jq_lve` 公孫綠萼（`jq_danfang`）、`n_jq_fanyiweng` 樊一翁（`jq_gukou`）、`n_jq_qiuqianchi` 裘千尺（`jq_dilao3`）、`n_jq_liumei` 柳姑娘（`jq_shufang`，被軟禁）【已證實名：預告「柳妹」】 |
| 物品／狀態 | `c_jq_juequingdan` 絕情丹（§4.10）、`qinghua` 狀態；`w_jq_junzijian` 君子劍、`w_jq_shunvjian` 淑女劍（劍房陳設；**不可取得**，`no_sell`、只出現在房間描述與對白，【設計提案】避免 1.0B 早期出神兵） |
| 怪 | `m_jq_lvyi` 綠衣弟子（谷中）、`m_jq_eyu` 鱷魚（鱷魚池）、`m_jq_dilao_*` 地牢怪（研究「隱藏地牢有怪」）；樊一翁 `m_jq_fanyiweng`（谷口戰） |
| 任務 | `q_jq_liumei` 救柳姑娘（【設計提案】依預告：谷口樊一翁攔路 `fight`（WIN_OR_FLEE）→ 情花林（中毒是正常的）→ 石屋見公孫止（拒婚對話）→ 綠萼指點：丹房取絕情丹 → 書房找到柳姑娘 → 暗道下地牢 → 鱷魚池 `fight` → 裘千尺（交代往事，給「谷底秘道」）→ 護送柳姑娘出谷（ESCORT 到 `jq_road1`）→ 名聲 +40、歷練 +60；一次）；`q_jq_duanchang` 斷腸崖（房間動作「望崖」，只給對白與一句傳聞，奇遇 M3c） |
| 美術 | 背景 `jueqinggu`（情花林）、`jueqinggu_dilao`；立繪 公孫止、公孫綠萼、裘千尺；怪 鱷魚、樊一翁 |

**WP-C-mingjiao_gaochang_yanmen**（`mingjiao_gaochang_yanmen.json`；研究「明教高昌雁門關」）

| 類 | 固定 id 與內容 |
|---|---|
| 明教 | `n_mj_fanyao` 明教右使范遙（`xn_slope`，7423,1323【已證實】；`talk` 只回冷話，`src_note` 記 2001-08-14 入口法騙局與 08-17 澄清；**沒有 JOIN、沒有任務**）；`talk_n_zhangwuji` 可補一句（若既有模板已存在則不動）。`q_mj_*` 不建立 |
| 雁門關 | `extra_rooms.yanmen`：`ym_outside` 雁門關外（`n_ym_miaorenfeng` 苗人鳳）、`ym_stele` 刻字石碑（`n_ym_keshi` 拓碑人，2001「刻字石塊前的NPC」；後期名石有田寫 src_note）；`n_ym_azhu` 阿朱（`ym_inner`）。任務 `q_ym_tuoyin` 拓印（白勇 `n_lj_baiyong`（既有，`npc_links`）→ BUY/COLLECT `r_mabu` ×2、`r_jiaotan` ×2 → 拓碑人 → 拓印 → 白勇；獎勵【後期版】歷練 +5、銀兩 50【設計提案】；可重複、冷卻 1 遊戲日；2001 無時辰，後期卯時寫 src_note）；`q_ym_xiaofeng` 找蕭峰（阿朱 → 西夏客棧蕭峰 `n_xx_qiaofeng`（既有）→ 回阿朱；只有預告，獎勵【設計提案】歷練 +10）；`q_ym_douji` 蕭峰鬥酒（`n_xx_qiaofeng`；未時；房間動作「斟酒」：結果依臂力＋根骨擲【設計提案】代替滑鼠滿杯小遊戲；勝：內力熟練 +10、學點 40、歷練 +5【已證實 other.htm】；「酒醉上限」本作沒有，略；每遊戲日一次） |
| 馬王洞 | `mawang` 地區（`mw_mouth`、`mw_cave1`、`mw_cave2`、`mw_deep`）；`m_mw_mawang` 馬王（氣 2000【待考證】，掉 `a_huangjia` 黃甲（GDD 既有提案 id；若不存在就建立）機率 0.15）；洞內共 7 隻：`mw_deep` 固定 3 隻（房間動作戰）、其餘遇敵；`todo_verify` 寫明馬王＝馬賊王？、地點只有 2002-01 與 2001-11-12 兩來源 |
| 高昌 | `gaochang_road`（`gc_road1`、`gc_road2` 駝隊歇腳處（`n_gc_tuodui` INN 15 兩）、`gc_road3`）、`gaochang`（`gc_outside`：`n_gc_xiangxiang` 香香公主、`n_gc_huoqingtong` 霍青桐；`gc_jihut_out`、`gc_jihut`：`n_gc_jilaoren` 計老人、`n_gc_liwenxiu` 李文秀（只對話：《白馬嘯西風》；內容【待考證】））、`gaochang_maze`（`gc_maze1`–`gc_maze6`，DUNGEON，`m_gc_jiguanren` 機關人 氣 3000【已證實 gaoshou/25】、攻擊高（「防禦還打 200+」用高攻擊數值表達，不改公式）；4–6 層另有 `m_gc_jiguanren2`） |
| 美術 | 背景 `mawang`、`gaochang_road`、`gaochang`、`gaochang_maze`、`yanmen` 補充；立繪 范遙、苗人鳳、阿朱、香香公主、霍青桐、計老人、李文秀；怪 馬王、機關人 |

**WP-C-lifeskills_content**（`lifeskills_content.json`；研究「經濟組織生活技能」）

| 類 | 固定 id 與內容 |
|---|---|
| 技能列 | §4.5 的 7 個新列＋`life_farming`、`life_woodcut` 替換列；每個配方 `src_note` 寫官方頁的工具與材料鏈（`src: "later"`，存在是 1.0A：十大技能 2001-08-09、2001 李裁縫／礦石大王，工匠 1.0B） |
| 房間 | `xx_tiepu` 西夏打鐵舖（`FORGE`、`CAST`、`KILN`）、`xx_buzhuang` 西夏布莊（`LOOM`、`TANNERY`）、`dl_tiepu` 大理打鐵舖（`FORGE`、`CAST`）、`de_mine` 大漠礦場（`MINE`；阿火的礦）；`exit_patches`：§3.3 表的 `xx_street`、`dl_shop`、`de_edge`、`xe_mine`、`xw_grass`、`ts_xuegu`、`dlw_forest` |
| 教學 NPC（`masters` 列＋NPC） | 挖礦：`n_xe_miner`（既有，`npc_links` 不夠 → 用新 NPC `n_ls_kuanggong` 礦工頭，`xe_mine`）；打鐵：`n_xx_zhangtie` 冶鐵商人張鐵（`xx_tiepu`，研究運鐵「張鐵（西夏城內，武器店邊上）」；`TEACH`、`SHOP` 賣十字鎬、打鐵鎚、焦炭）；鑄劍：`n_ls_dl_zhujian` 鑄劍師（`dl_tiepu`）；工匠：`n_ls_jc_mujiang` 木匠（`jc_street_n`，era 1.0B）；織布：`n_ls_xx_fangzhi` 紡織女（`xx_buzhuang`；懷舊指南「紡織女」）；裁縫：`n_dl_licaifeng` 李裁縫（既有，`masters` 列指向他即可）；獵人：`n_lj_hunter`（既有獵戶，`masters` 列）。教到 30 級【設計提案】，之後自己練 |
| 物品 | §4.6 全部（`grade` 用 `item_patches` 補既有礦石）；工具售價 30–120 兩、材料收購價 = 成品鏈逐級加值（礦 30 → 鐵塊 120 → 鐵劍 300…）【設計提案】，由 `balance_sim` 的經濟案例檢查（§11.2） |
| 商店 | `shop_patches`：西夏、大理菜販（既有 `n_xx_caishang` 等）加種子；兩城兵器鋪加 十字鎬、針線包 |
| 獵場 | `hunt_table`：`xw_grass`（野兔、大野兔）、`ts_xuegu`（雪狐、野狼）、`dlw_forest`（山豬、野狼）；`m_hunt_*` 新野獸可選 |
| 經濟出口 | `n_jc_zhangyuanwai`（jingcheng 碎片）收紫石礦；各城兵器鋪照價收購成品 |

**WP-C-story_missing**（`story_missing.json`；研究「未做的 2001 事件」；STORY_PLAN §4 引擎）

| 優先 | 任務 id | 標題 | 要點 |
|---|---|---|---|
| P1 | `q_sm_yuntie` | 運鐵 | 少林限定【設計提案】；道相 `n_sm_daoxiang`（`sl_court`「十八銅人陣外左邊」）→ 精鐵採購信 → 張鐵（`n_xx_zhangtie`，`npc_links`）→ 精鐵（任務物 `i_sm_jingtie`）→ 道相 → 綠石礦 ×2 ＋ `learn {life_swordsmith: 1}` ＋ `skill_prof {life_swordsmith: 100}`【攻略 2001-07-23，未重抓】；一次；「紅晶鐵」後期不做 |
| P1 | `q_sm_qidu` | 幫楚禮子尋找七毒 | 星宿；楚禮子 `n_sm_chulizi`（位置不明 → `xh_hall` 左偏殿 `xh_left`【設計提案】）；辰時～未時【後期】；7 種毒物各 1：房間動作打毒物，點位用**共用毒物點**（O21）：赤蝎、蝎子、蜈蚣、蟾蜍、青蛇、彩蛛、黑蛛 → 對應既有房間（依 2001 座標換算挑最近的既有房間，`src_note` 寫座標）；獎勵 解毒草 ×2【後期】（`r_sm_jieducao`，若既有解毒草 id 存在用既有） |
| P1 | `q_sm_zhuadu` | 出外抓毒物 | 咸楓子 `n_sm_xianfengzi`（`xh_right`）；卯時～未時【後期】；同一組毒物點；每交一種給基本毒術熟練 +3/+5/+7、全交 +40【後期】；可重複、冷卻 1 遊戲日 |
| P1 | `q_sm_lengning` | 冷凝劍事件 | 劍痴（既有 `n_em_jianchi`，`npc_links`）；`requires` `life_min life_swordsmith 30`【後期】；COLLECT `w_lengning` → 選「給她看」：交出得 3800 兩＋學點 70；選「不給」：學點 50【後期原文】 |
| P1 | `q_sm_chengwei` | 辛勤的程薇 | 恆山（`n_hg_chengwei` 既有，`npc_links`）；`requires` `skill_max life_farming 19`、`skill_max basic_medic 29`【後期】；交 20 麻 → 基本醫術熟練 +50、殺氣 −100 → 申或巳時 棉花事件給 `i_sm_nongwu` 農務委託書 → 交 10 棉花 → 毒龍涎（若無既有物品則建 `r_sm_dulongxian`）、學點 +10、殺氣 −100 |
| P1 | `q_sm_dujulaoren` | 獨居老人 | 王老先生 `n_sm_wanglao`（`xx_bank` 錢莊旁，研究「by the 西夏 bank」）→ 到藥鋪 BUY 傷藥膏 → 交給他 → 15 兩＋名聲 2＋歷練 2【未重抓，2001-08-24】；一次 |
| P1 | `q_sm_esi_nongfu` | 餓肚子的農夫 | 大理 `dlw_paddy`、西夏 `hf_paddy` 旁各一位樵夫 `n_sm_qiaofu_dl`、`n_sm_qiaofu_xx`；`requires combat_xp_max 999`【未重抓】；各送一份食物（白飯或饅頭）→ 學點 15、實戰 50 |
| P1 | `q_sm_ahuo` | 著急的阿火 | 阿火 `n_sm_ahuo`（`de_mine`）→ 礦石送到大理礦業大王 `n_sm_kuangye`（`dl_square`）→ 名聲＋歷練各 3【未重抓】；可重複、冷卻 1 遊戲日 |
| P2 | `q_sm_abao` | 路痴的礦工 | 只有預告 → 整條【設計提案】：阿寶得離開礦場辦事卻不認路，護送他到西夏城門再回來（ESCORT）→ 綠石礦 ×1；一次 |
| P2 | `q_sm_ahong` | 離鄉的阿鴻 | 信送大理 張箐（天龍寺不存在 → `dlw_lake` 洱海岸，比照李莫愁的擺法）→ 1000 兩【未重抓】；可重複 |
| P2 | `q_sm_rixing` | 日行一善 | 大理城外受傷的樵夫，送藥；2001「沒好處」→ 只有善惡 +5【設計提案】 |
| P2 | `q_sm_shepi` | 為蛇皮困擾的武介山 | 武介山（既有 `n_wujieshan`）→ 西夏城外青蛇皮 ×3（`m_lf_qingshe` 掉落或房間動作）→ 銀兩 |
| P2 | `q_sm_litong` | 離派修練的李同 | 李同 → 信給華山陸大有（若無 NPC 建 `n_sm_ludayou` 於 `hs_*` 既有房間）→ 盤纏 |
| P3（可不做） | `q_sm_xiaozhen`、`q_sm_fengjizi`、`q_sm_xunsixian`、`q_sm_zhongnan`、`q_sm_xiongrou` | 孝順的小珍、逢紀子、荀思現、終南山在哪裡?、愛吃熊肉的老祖 | 只有預告；做就全【設計提案】 |

- 毒物點：`q_sm_qidu`、`q_sm_zhuadu` 用同一組房間動作 id（`a_poison_<種類>`），**兩個任務各自**在同房放動作（STORY_PLAN 房間動作是任務階段專屬）；`src_note` 註明 O21。
- 不做：全真教討賊書、峨嵋回部短劍、物色美女（惡行，留 M3c）、劍隱事件（劍宗內容）、所有 1.0B 第七～九話（除了 jingcheng 碎片那 3 條）。

**`_sect.json`（WP-SECT）**：`beg`、`harass`、`sect_assembly`、`sect_rank_up`、`rank_wait`、`seize_*`、`shop_refused`、`era` 面板文字、京城監獄 `jail_in`／`jail_out` 的 CAPITAL 變體模板；`err_*` 原因碼文字。

**`_econ.json`（WP-ECON）**：§3.2 #56、#57、#60、#61 的房間（`xx_bank` 西夏錢莊、`xx_biaoju` 西夏鏢局、`dl_bank` 大理錢莊、`dl_biaoju` 大理鏢局）；錢莊／鏢頭 NPC（§5.2.3）；`n_ec_biaoche`；`escort_routes` 6 列；保鏢任務 6 條（`q_ec_biao_xx_dl`、`q_ec_biao_dl_xx`、`q_ec_biao_xx_jc`、`q_ec_biao_jc_xx`、`q_ec_biao_dl_jc`、`q_ec_biao_jc_dl`；京城相關 era 1.0B）；事件與錯誤模板。

**`_org.json`（WP-ORG）**：書吏 `n_og_xx_shuli`（`xx_yamen`）、`n_og_dl_shuli`（`dl_yamen`）、`n_og_jc_shuli`（`jc_yamen`，era 1.0B），`services: ["ORG"]`；組織事件與錯誤模板。

---

## 9. 工作包與檔案所有權

### 9.1 所有權表（一個檔案只有一個擁有者）

| WP | 擁有的檔案（新增或修改） | 主要交付 |
|---|---|---|
| **WP-SECT**（也是 core 擁有者） | `core/protocol.gd`；`core/data/**`；`core/character/**`；`core/rules/**`；`core/battle/**`；`server/game_host.gd`、`server/session.gd`、`server/sect_system.gd`、`server/condition_system.gd`、`server/npc_system.gd`、`server/region_system.gd`、`server/pk_system.gd`、`server/battle_system.gd`、`server/quest_system.gd`、`server/admin_system.gd`、`server/scout_system.gd`；`server/intents/intents_sect.gd`、`intents_pk.gd`、`intents_npc.gd`、`intents_move.gd`、`intents_char.gd`、`intents_host.gd`、`intents_debug.gd`、`intents_self.gd`、`intents_item.gd`、`intents_quest.gd`、`intents_story.gd`；`autoload/world_server.gd`、`autoload/client_state.gd`；`data/rule_profiles.json`、`data/server_options.default.json`；`tools/regen_battle_golden.gd`、`tests/fixtures/battle_*.json`；`tests/unit/test_character*.gd`、`test_world_*.gd`、`test_protocol*.gd`、`test_data_loader.gd`、`test_sect*.gd`、`test_requirements*.gd`、`test_battle*.gd`、新 `test_m3b_sect_ranks.gd`、`test_m3b_beg.gd`、`test_m3b_capital_jail.gd`、`test_m3b_seize.gd`、`test_m3b_era.gd`、`test_m3b_requirements.gd`、`test_m3b_poison_fang.gd`；`docs/m3b_staging/_sect.json` | §2、§4.1–4.4、4.10–4.13 的程式部分、§5.1、§5.4、§6 Day-0 |
| **WP-ECON** | `server/bank_system.gd`（新）、`server/escort_system.gd`（新）、`server/life_system.gd`、`server/intents/intents_econ.gd`（新）、`core/econ/**`（新，純邏輯：`bank_store.gd`、`consign_calc.gd`、`recipe_check.gd`）；`tests/unit/test_m3b_bank.gd`、`test_m3b_consign.gd`、`test_m3b_life.gd`、`test_m3b_hunt.gd`、既有 `test_life*.gd`；`docs/m3b_staging/_econ.json` | §4.5（引擎）、§4.7、§5.2 |
| **WP-ORG** | `server/org_system.gd`（新）、`server/intents/intents_org.gd`（新）、`server/social_system.gd`；`tests/unit/test_m3b_org.gd`、`test_m3b_org_chat.gd`、既有 `test_social*.gd`；`docs/m3b_staging/_org.json` | §5.3 |
| **WP-UI** | `ui/**`、`autoload/scene_router.gd`；`tests/unit/test_ui*.gd`（含新 `test_ui_m3b_*.gd`） | §7 |
| **WP-C-gaibang** | `docs/m3b_staging/gaibang.json`（只有這個檔） | §8.3 |
| **WP-C-jingcheng** | `docs/m3b_staging/jingcheng.json` | §8.3（含監獄、天地會） |
| **WP-C-jueqinggu** | `docs/m3b_staging/jueqinggu.json` | §8.3 |
| **WP-C-mingjiao_gaochang_yanmen** | `docs/m3b_staging/mingjiao_gaochang_yanmen.json` | §8.3 |
| **WP-C-lifeskills_content** | `docs/m3b_staging/lifeskills_content.json` | §8.3 |
| **WP-C-story_missing** | `docs/m3b_staging/story_missing.json` | §8.3 |
| **WP-MERGE**（建造之後單獨執行） | `data/*.json`（除了 `rule_profiles`、`server_options.default`）、新表 `data/sect_ranks.json`、`data/escort_routes.json`；`data/maps/*.json`；`data/patches/*.json`；`data/art.json`；`data/eras.json`（只准把 1.0B 列的 `src` 改 `"verified"`）；`tools/data_lint.gd`、`tools/validate_data.gd`；`tests/unit/test_data_content.gd`；`docs/ART_REQUEST.md`（只追加 §8「第五批」） | §9.4、§9.5 |
| **整合者**（協調者） | `tests/bots/**`（新 `tests/bots/m3b_bot.gd`；改 `m1_playthrough_bot.gd` 的京城出生步）、`tests/ui/**`、`tools/m3b_acceptance.gd`（新）、`tools/m3a_acceptance.gd`、`tools/story_acceptance.gd`、`tools/m2_acceptance.gd`、`tools/balance_sim.gd`（新案例）、`README.md`、`docs/**`（GDD、WORLD_2001、M3A_PLAN、STORY_PLAN、ART_REQUEST 的偏差同步；本文件整合紀錄） | §11 |

### 9.2 凍結檔（M3b 任何 WP 都不得修改）

`project.godot`、`export_presets.cfg`、`tools/export_release.ps1`、`autoload/game_data.gd`、`autoload/bgm_player.gd`、`autoload/network_manager.gd`、`autoload/steam_manager.gd`、`autoload/save_manager.gd`、`autoload/file_log.gd`、`core/util/*`、`tests/run_tests.gd`、`tests/test_case.gd`、`tests/unit/test_core_util.gd`、`tests/bots/chat_bot.gd`、`tools/net_smoke.gd`、`tools/steam_api_probe.gd`、`tools/check_vendor.ps1`、`tools/iso_gallery.gd`、`tools/import_art.py`、`tools/godot_k.ps1`、`addons/**`、`assets/**`、`data_root.txt`、`docs/**`（各 WP 只能寫自己的碎片；本文件只由協調者改）、`server/ambient_system.gd`、`server/rumor_system.gd`、`server/wander_system.gd`、`server/mail_system.gd`、`server/party_system.gd`、`server/corpse_system.gd`、`server/passport.gd`、`server/character_store.gd`、`server/world_clock.gd`、`server/world_index.gd`、`core/quest/**`（引擎增量只在 `server/quest_system.gd`）。

### 9.3 Day-0（各 WP 開工的第一件事）

| WP | Day-0 內容 | 為什麼 |
|---|---|---|
| WP-SECT | (1) `core/protocol.gd`：§6 全部 intent 常數、`INTENT_SCHEMA`、事件、原因碼、`CH_CHAT_GUILD` 不變；(2) `core/data/data_schema.gd`：§4.3 條件、§4.4 房間欄位與 `FEATURES`、`NPC_SERVICES`、`sect_ranks`／`escort_routes` 表的必填欄位與 `INT_FIELDS`、`REFS`（`sect_ranks.sect`→sects、`sect_ranks.quest`→quests、`escort_routes.job_quest`→quests、`npcs.escort.city`→regions）、§4.11 的 `INT_FIELDS.server_options`；(3) `Character` §4.12 欄位與 `from_dict` 預設、`bank_pieces`／`bank_find` 骨架；(4) `GameHost`：以路徑載入 `res://server/bank_system.gd`→`bank`、`res://server/escort_system.gd`→`escort`、`res://server/org_system.gd`→`orgs`，與 `M3B_INTENTS := ["res://server/intents/intents_econ.gd", "res://server/intents/intents_org.gd"]`；`_minute_jobs` 呼叫 `m2_call(escort, "tick")`、`m2_call(orgs, "tick")`；登入流程呼叫 `m2_call(orgs, "on_login")`、`m2_call(escort, "on_login")`；`NpcSystem.menu` 合併 `m2_call(bank/escort/orgs, "menu_fields", [s, npc_id])`；(5) `battle_system.gd` 的 `HUNT` 結算掛鉤（§5.1.8）；(6) `data/server_options.default.json` §4.11 全部 key | 其他 WP 依常數、角色欄位與載入點開工 |
| WP-ECON | `core/econ/bank_store.gd` 的純函式簽名（`put(bank, inv, uid, n, tables, cap) -> Dictionary` 等）先交出 | WP-UI 的錢莊窗用 `bank_view` 形狀 |
| WP-ORG | `org_info` 事件 payload 形狀先寫成 `_org.json` 註解與單元測試 | WP-UI 的組織面板 |

Day-0 還沒落地時：先寫純邏輯與不依賴新常數的測試；字串用與本文件**完全相同**的字面值，交付前改回常數。

### 9.4 合併程序（WP-MERGE）

1. 讀 `docs/m3b_staging/*.json`（6 個內容碎片＋`_sect`、`_econ`、`_org`）。逐檔 JSON 解析；id 重複（跨碎片或與現有資料）→ 停下並在報告列出，**以先到者（字母序）為準**，後者改名加 `_2` 並記錄。
2. 依序合併：`sects`、`sect_rules`、`sect_ranks`（新表）、`regions`（`jingcheng`、`jingcheng_wild` 以碎片為準）、`maps`（寫成 `data/maps/<region>.json`；jingcheng 的兩張完整替換）、`extra_rooms`、`exit_patches`（含 `add_features`、`hunt_table`、`desc_1_0b`）、`npcs`（再依 `room` 把 id 加進房間 `npcs`）、`masters`、`martial_arts`、`monsters`、`items`、`item_patches`、`shop_patches`、`npc_links`、`life_skills`（同 id 以碎片為準並報告）、`escort_routes`（新表）、`status_effects`、`quests`（`test_plan` 原樣存進任務列，STORY_PLAN 慣例）、`text_templates`、`rumors`、`ambient`、`patches_1_0b`（併入 `data/patches/1.0B.json`）、`art_requests` → `data/art.json`（`alias` 照填、`required: false`、`placeholder: false`）。
3. 跨碎片固定 id（§8.3）全部存在；缺的列成錯誤，不自己補內容。
4. `tools/data_lint.gd` 新檢查（§9.5）跑到 0 錯誤（每個 era 閉包：`["1.0A"]`、`["1.0A","1.0B"]`、全部）；跑全部單元測試；更新 `test_data_content.gd` 的計數與抽查（丐幫、京城監獄、7 個生活技能、6 條保鏢、新任務）。
5. `docs/ART_REQUEST.md` 追加 **§8「第五批（2026-10-20 新增，M3b：丐幫、京城、絕情谷、高昌、雁門關、馬王洞）」**，格式照第三、四批：8.1 丐幫服裝（2 張，最優先）；8.2 新地區戰鬥背景（京城、京城南郊、京城北郊、丐幫破廟、京城監獄、天地會香堂、絕情谷、絕情谷地牢、馬王洞、高昌古道、高昌、高昌迷宮）；8.3 NPC 立繪（陳長老、傳功長老、掌棍長老、姜乞丐、陳近南、公孫止、公孫綠萼、裘千尺、柳姑娘、范遙、苗人鳳、阿朱、香香公主、霍青桐、計老人、李文秀、張鐵、錢莊老闆、鏢頭、監獄看守人）；8.4 選做：新怪物（小黃、邪教門徒、蠻兵、馬賊王、護國法師、煞風寨寨主、隱面人、鱷魚、樊一翁、馬王、機關人）；8.5 之後才需要的（生活技能工具與材料圖示、鏢車）。每張附檔名、名稱、英文 prompt（第 0 節風格說明照舊）。

### 9.5 Lint 新檢查（`tools/data_lint.gd`）

1. §4.3 新條件的欄位；`sect_rank_min.sect` 存在且有 `ranks`。
2. `sects`：`ranks` 指向存在的 `sect_ranks.sect`；`practice`、`harass` 欄位型別、`harass.monster` 存在、`regions` 鍵是 CITY 地區；`respawn_at_gate: false` 時不要求查小鏞。
3. `sect_ranks`：每派 `rank` 從 0 連續；`promote` 合法；`QUEST` 有 `quest` 且任務的某個結局有對應 `sect_rank` 獎勵；`cost` 鍵只限 `fame`、`lilian`、`money`。
4. 房間：`jail_scope` 合法、`CAPITAL` 最多一間且有 `jail_release_to`（存在、同 era）；`features` 新值；`HUNT` 必有 `hunt_table`、怪物 `hunt: true`；`desc_1_0b` 必有 1.0B 出口；`on_enter_status` 的狀態存在。
5. `life_skills`：`mode` 合法；`GATHER` 有 `yield` 或 `HUNT` 有 `hunt`；配方 `feature` 合法；所有 `tool`／`tools`／`inputs`／`output` 物品存在且**同一 era 閉包可取得**（1.0A 技能不能用 1.0B 物品）；每個配方的輸入至少有一個取得來源（商店、採集、其他配方、怪物掉落）——材料鏈不斷頭。
6. `escort_routes`：城存在、`job_quest` 存在、一對城一列；每個 `ESCORT` NPC 的 `escort.city` 有路線。
7. NPC：`BANK`、`ESCORT`、`ORG`、`RANK` 服務的必要欄位；`shop.refuse_if` 是條件組陣列。
8. 新手路線（§3.4）：出生城取「生效的 `birth_allowed` 地區」；`jcn_road1`、`jcn_road2`、`jq_road1`、`jq_gukou`、`gc_road1` 的白名單。
9. era 一致性：1.0A 房間的出口指向 1.0B 房間時出口必須帶 `era: "1.0B"`；1.0B 的 NPC 不能放在只有 1.0A 存在的檢查漏洞（NPC era ≥ 房間 era）；`exits[].era` 雙向一致。
10. 任務：`sect_rank` 獎勵、`unique_per_char` 物品型別；STORY_PLAN §8.5 的既有檢查自動涵蓋新任務。
11. 簡體字檢查涵蓋所有新文字。

---

## 10. 規則與數值表

| 項目 | 值 | 依據 |
|---|---|---|
| 1.0B 上線 | 2001-09-28（台灣／年表）；大陸約 2001-10-05 | 研究 丐幫【已證實】 |
| 新世界 era | `["1.0A","1.0B"]`；`classic_strict` → `["1.0A"]` | O1【設計提案】 |
| 京城出生 | 1.0B 可 | 2001-11-06【已證實】 |
| 京城廣場 → 丐幫山門 | 5 步 | 原作「跑上 10 分鐘」；步數【設計提案】 |
| 丐幫入派 | 無門派、非公敵；男女皆收（不設善惡門檻，見 O5） | 男女皆收：官方後期【後期版】；不設善惡門檻：研究找不到出處（M3b 審查 3） |
| 丐幫停止傳功 | 善惡 < 0 | jy2-4-2【後期版官方】 |
| 丐幫違規 | 同門相殘 → BAN（沒有執法者） | jy2-4-2【後期版官方】 |
| 乞討消點 | 陳長老教到 10 | O7【設計提案】 |
| 乞討行動 | 精 20、神 20；熟練 +3～6；同一 NPC 冷卻 600 世界秒；施捨 35% 1–8 兩、10% 饅頭 | 「精神全滿討五次」【已證實】；數值【設計提案】 |
| 銅鎚手 | 心法 10、乞討 10 | 2001-10-09【已證實】 |
| 瘋魔杖法 | 太祖棍 50、心法 30、乞討 30、二袋；上限 60 | 2001-12-01【已證實】 |
| 纏絲、擒龍、混天、蓮花 | 前置 50（混天、蓮花前置 30）、心法 30、乞討 30、二袋；上限 60 | 比照瘋魔【設計提案】；10-09 列表 |
| 一階武功上限 | 100 | 【設計提案】 |
| 一袋 | 名聲、歷練 ≥ 250；三城情報、三次橋上埋伏、殺邪教門徒 ≥ 20；聚會生效 | 2001-11-03、12-03【已證實】 |
| 二袋 | 名聲、歷練 ≥ 500、一袋；姜乞丐 → 掌棍長老 → 三封信 → 三場蠻兵；升時扣 250/250 | 2001-11-23、11-25、12-03【已證實】 |
| 三袋～七袋 | 1200／1700／2500／3500／10000（era xkd） | 2002 攻略、免費版【後期版】 |
| 聚會 | `DAILY`（辰時）預設；`MONTHLY`（每月 1 日）可選 | 原作每月 1 日【已證實】；預設【設計提案・偏離】 |
| 小黃 | 西夏、大理 15%、京城 5%（街道房）；乞討 ≥ 30 免；打贏 5 學點 | 2001-10-24【已證實】；機率【設計提案】；30【後期版】 |
| 毒牙 | 中毒等級 1 + 乞討/25；耗精、神；`later_battle_cmds` 才觸發 | 官方 jy1-4-11；2002-01-25 才觸發【已證實】；等級公式【設計提案】 |
| 邪教門徒 | 氣 300 | 2001-11-03【已證實】 |
| 蠻兵 | 原作 100000 HP → 依本作級距（3 人隊可勝） | 2001-11-23【已證實】；換算【設計提案】 |
| 京城監獄刑期 | 違規 1 遊戲日、公敵 3 遊戲日（3 金庸日 = 6 真實小時） | 官方門派監獄頁【已證實】 |
| 保釋 | 100000 兩 | 官方【已證實】 |
| 出獄地點 | 京城衙門 | 【設計提案】 |
| 捉拿公敵 | 只抓本派公敵、可組隊、抓的人無懲罰 | 官方【已證實】；其餘【設計提案】 |
| 錢莊 | 1000 件；存款 600 萬；三城共用；不收費 | 1000【已證實】；600 萬【後期版推得】；共用【待考證】 |
| 托鏢運費 | 20 兩 + 2 兩／重量 | 【設計提案】 |
| 托鏢時間 | 西夏↔大理 4 時辰、西夏↔京城 3、大理↔京城 5 | 【設計提案】 |
| 托鏢保管 | 30 遊戲日後退回 | 【設計提案】 |
| 保鏢酬勞 | 西夏↔大理 150 兩＋名聲 3；京城線 200 兩＋名聲 4；冷卻 1 遊戲日 | 「保鏢提升名聲」【已證實】；數值【設計提案】 |
| 丐幫保鏢 | 不能接 | 2001 多篇【已證實】 |
| 組織創立 | 幫主名聲 150、連署人名聲 20、連署人數 3（原作 30） | 官方【已證實】；人數【設計提案】 |
| 組織手續費 | 10000 兩 | 【設計提案】 |
| 組織上限 | 50 人；位階 5 級；連署期 3 遊戲日 | 【設計提案】 |
| 生活技能上限 | 每項 100 | 至尊版【後期版】 |
| 打鐵 | 3 個同級礦 → 1 鐵塊 | 官方【後期版】 |
| 冷凝劍 | 鑄劍 30 | 後期攻略【後期版】 |
| 漁網 | 51 級（本包不做漁網，記錄） | 官方 |
| 生活技能教學上限 | NPC 教到 30，之後自練 | 【設計提案】 |
| 情花毒 | 約 12 時辰；絕情丹解；一人一顆 | DIAO/2-2、官方 1.0B 頁【已證實】；數值【設計提案】 |
| 機關人 | 氣 3000 | gaoshou/25【已證實】 |
| 馬王 | 氣 2000、掉黃甲 15% | gaoshou/25 馬賊王【待考證】；機率【設計提案】 |
| 鬥酒 | 未時；內力熟練 +10、學點 40、歷練 +5 | other.htm【已證實】；歷練數【設計提案】 |

---

## 11. 測試計畫

### 11.1 各 WP 的單元與整合測試（全部在 `tests/run_tests.gd` 裡跑，`--filter=m3b` 可單跑）

| WP | 測試 | 涵蓋 |
|---|---|---|
| WP-SECT | `test_m3b_era.gd` | 新世界預設 1.0A+1.0B；`classic_strict` 只 1.0A；`--eras` 優先；既有世界不被改；`pending_eras` 下次開服套用；1.0A 世界沒有京城、丐幫、工匠，出生城只有兩座 |
| | `test_m3b_requirements.gd` | `sect_not`、`sect_rank_min`、`org_member`、`no_org`、`life_min` |
| | `test_m3b_sect_ranks.gd` | 拜入 rank 0；任務獎勵 → pending；DAILY 辰時聚會升級並扣 cost；requires 不成立保留；MONTHLY 只在 1 日；離線錯過聚會登入補升；叛派歸 0；二階武功在二袋前回 `req_sect_rank_min` |
| | `test_m3b_beg.gd` | 驗證順序全部原因碼；熟練增加；同 NPC 冷卻；施捨；乞討不受善惡停止傳功影響 |
| | `test_m3b_harass.gd`（可併 beg） | 街道房機率觸發、乞討 30 免、室內不觸發、60 秒節流、打贏 5 學點 |
| | `test_m3b_capital_jail.gd` | `AUTO` 解析；違規在有執法者時進 `jc_jail`、無執法者 BAN；公敵被抓一律 `jc_jail`；出獄到 `jc_yamen`；贖人；1.0A 世界退回各派思過處 |
| | `test_m3b_seize.gd` | 全部原因碼；SEIZE 戰鬥抓的人無 PK 懲罰；目標死亡 → 關押；目標逃跑不關 |
| | `test_m3b_poison_fang.gd`＋既有 `test_battle*` | 毒牙觸發與消耗；D12 統一後 DEFENSE/RECOVER 扣精；金檔重產 |
| | `test_m3b_shop_refuse.gd` | 丐幫在京城兵器鋪 `shop_refused`；他派可買；西夏可買 |
| WP-ECON | `test_m3b_bank.gd` | 存取物品（部分堆疊）、存領錢、容量、存款上限、任務物品與裝備拒存、角色檔 to_dict/from_dict 往返、三城共用、腐壞凍結 |
| | `test_m3b_consign.gd` | 運費計算、送達時間、到站通知（在線／登入）、取貨、超重不拿、過期退回、沒有路線、寄給自己、不存在的人 |
| | `test_m3b_life.gd` | 7 個新技能：工具檢查、設施檢查（配方 feature 覆寫）、等級門檻、產出放不下先拒絕、材料鏈 挖礦 → 打鐵 → 鑄劍 → 鐵劍；樵夫燒炭；種麻棉；1.0A 世界沒有工匠 |
| | `test_m3b_hunt.gd` | `HUNT` 開戰、勝利額外掉落、逃跑只加失敗熟練 |
| WP-ORG | `test_m3b_org.gd` | 創立各原因碼；連署滿 → ACTIVE、連署人成員；過期刪除；邀請／回覆、上限、開除權限、位階、封號、移交、幫主不能直接退出、解散；存檔往返（`world.guilds`） |
| | `test_m3b_org_chat.gd` | `CHAT_GUILD` 只送組織在線成員、非成員 `no_guild`、耗水 |
| WP-UI | `test_ui_m3b_econ.gd`、`test_ui_m3b_org.gd`、`test_ui_m3b_sect.gd` | 視窗建立、假資料顯示、送出 intent 形狀 |
| WP-MERGE | `test_data_content.gd` | 計數；丐幫 11 套武功、`gb_dai0..2` 在 1.0B 生效；京城監獄唯一；7 技能；6 保鏢；固定 id 存在 |

### 11.2 平衡（`tools/balance_sim.gd`，整合者加案例）

- `walk_jc_gb`：新角色（實戰 0）京城廣場 → `gb_gate` 存活率 ≥ 90%（§3.4）；`walk_jc_jq`：京城南門 → 谷口；`walk_xx_gc`：西夏 → 高昌室外。
- `gb_xiejiao7`：實戰 3000 的丐幫角色（一階武功 30）打 7 個邪教門徒勝率 ≥ 70%；`gb_manbing_party3`：3 人各實戰 2 萬勝率 ≥ 70%（審查 3 從 6 萬改）、`gb_manbing_duo` 兩人各 2 萬 ≤ 10%、單人實戰 1 萬勝率 ≤ 10%；`gb_xiaohuang`：新丐幫弟子勝率 ≥ 95%。
- `gc_robot`、`mw_mawang`：建議實戰的單人勝率 40–80%。
- `econ_chain`：每條生活技能鏈的「每點精換到的銀兩」不超過打怪的 1.5 倍、也不低於 0.3 倍（以 balance_sim 既有打怪收益為基準）【設計提案】。
- 既有案例全部照舊通過（D12 改了消耗，數值若超出門檻，WP-SECT 調觸發機率，不調門檻）。

### 11.3 驗收：`tools/m3b_acceptance.gd` + `tests/bots/m3b_bot.gd`（整合者）

架構照 `tools/story_acceptance.gd`：worker 子行程在自己的行程裡開真的主機（`WorldServer`＋`GameHost`、全部系統、`--debug-intents`），玩家是假的遠端連線，一切動作經 `handle_intent`；需要「重開主機」的劇本照故事驗收的 存檔 → 關主機 → 同世界重開 → 重新選角。每個劇本用**全新世界**（測試根目錄下 `m3b_acceptance/<run>/`），角色出生城依劇本。`debug_set` 只用來設屬性、實戰、銀兩、名聲、歷練、技能等級、時辰快轉；**路一律用走的**（`teleport` 只准把 bot 送回起點）。

| 劇本（`--only=`） | 世界 | 步驟與斷言 |
|---|---|---|
| `jingcheng_walk` | 預設（1.0A+1.0B） | 西夏出生 → 走東路 → 華山腳下 → `jcw_huashan` → 南郊 → 京城南門 → 廣場（斷言 region `jingcheng`、步數 ≤ 20）；另一角色**京城出生**成功、在 `jc_square` |
| `gaibang` | 預設 | 京城出生 → 走 5 步到 `gb_gate` → 陳長老 `sect_join` 丐幫 → 學乞討到 1 → `beg` 3 次（熟練增加、冷卻原因碼）→ 傳功長老學 丐幫心法、太祖長拳（斷言 `sect_info` 丐幫）→ 對二階武功 `learn` 回 `req_sect_rank_min` → `debug_set` 名聲、歷練 250、技能加強 → 跑 `q_gb_dai1`（走路到西夏、大理、京城三處、三次埋伏、殺滿 20）→ 陳長老 → `sect_info.rank.pending` = 一袋 → `debug_set world_s_add` 到下一個辰時 → `sect_rank_up`、`sect_info.rank.level == 1`、名稱「一袋弟子」 |
| `capital_jail` | 預設 | 兩名少林角色 A、B（`debug_set` 拜入條件後走到少林拜師）→ 兩人走到京城南郊 `jcw_crossroad`（可 PK）→ A 對 B `force_pk`、B 只「防」到死 → A 收到 `sect_breach`（JAIL）＋`jail_in`、人在 `jc_jail`、`world_info.jail_location_resolved == "CAPITAL"` → A 世界頻道回 `jailed`、輕聲細語可以 → B 重生後走到 `jc_jail_gate` `jail_ransom` A（`debug_set money`）→ A `jail_out`、人在 `jc_yamen`；另一段：A' 叛出少林（公敵）→ 少林弟子 B `seize_enemy` A' → A' 死 → A' 在 `jc_jail`、`reason ENEMY` |
| `escort` | 預設；**兩名玩家** | A、B（非丐幫）組隊 → 西夏鏢局接 `q_ec_biao_xx_dl`（兩人都接）→ 帶鏢車走到大理鏢局 → 兩人都完成、各得 150 兩＋名聲 3；另一名丐幫角色接同任務回 `req_sect_not`；托鏢：A 在大理鏢局寄 1 件物品給 B 到西夏 → `debug_set world_s_add` 4 時辰 → B 收到 `consign_arrived` → B 走回西夏鏢局 `consign_take` |
| `bank` | 預設 | 西夏錢莊存 500 兩與 3 件物品 → 存檔、關主機、重開、重新選角 → 錢莊仍有 → 走到大理錢莊取出（三城共用） |
| `org` | 預設；`guild_signers=1`；**兩名玩家**＋一名旁觀者 | A（`debug_set` 名聲 150、銀兩 1 萬）在西夏衙門書吏 `org_found`「江湖小築」→ B（名聲 20）`org_sign` → `org_founded`、A 幫主、B 幫眾 → B 說 `CHAT_GUILD` → A 收到、旁觀者 C 沒收到、C 說組織頻道回 `no_guild` → B `org_leave` → A `org_invite` B → B `org_reply` 接受 → 存檔重開 → 組織與成員都在 |
| `craft` | 預設 | `debug_set` 挖礦、打鐵、鑄劍各 1 級＋銀兩 → 西夏打鐵舖買十字鎬、打鐵鎚、焦炭 → 走到 `xe_mine` 挖鐵礦石到 3 個（`work`）→ 回 `xx_tiepu` 打鐵得鐵塊 → 鑄劍得鐵劍（斷言背包）；1.0B：京城木匠學工匠 → 樵夫在 `sy_pines` 砍木材 → 工匠做木劍 |
| `jueqinggu` | 預設 | 京城南門 → 3 步到 `jq_gukou`（樊一翁）→ `jq_qinghua`（可能中情花毒，`conditions` 有 `qinghua` 或沒有都可）→ `jq_shiwu` 與公孫止交談（`talk`）→ 丹房取絕情丹（`q_jq_liumei` 的第一個階段）→ 用絕情丹解毒 |
| `story` | 預設 | `q_sm_dujulaoren`（獨居老人）完整走完並斷言獎勵；`q_sm_yuntie` 走到張鐵那一步 |
| `era_1_0a` | `--eras=1.0A` 世界 | 京城、丐幫、工匠不存在（`look` 找不到房間、`work life_carpentry` 回 `not_known`、創角出生城只有兩座、`seize_enemy` 回 `era_locked`）；錢莊、組織、挖礦照常 |

另外兩個獨立閘門（整合者在驗收說明裡一起跑）：**M1 bot 在 1.0A-only 世界**（§0.4 第一條 M1 指令，`--eras=1.0A`，必須 `M1_ACCEPT_OK`）與 **M1 bot 在預設世界**（第 4 步「京城出生被拒」改成：`world_info.enabled_eras` 有 1.0B 時改斷言京城出生**成功**後刪掉該角色再照原劇本）。

成功印 `M3B_ACCEPT_OK`、結束碼 0；失敗印 `M3B_ACCEPT_FAIL <劇本> <原因>` 並傾印 log 尾端，結束碼 1；log 與世界在 `<測試根目錄>/m3b_acceptance/`；不論成敗所有子程序 `OS.kill()`，結束後 `tasklist` 不得有殘留 Godot。

### 11.4 回歸（全部要綠，整合者驗收時逐一跑）

`tests/run_tests.gd`（0 failed）、`tools/data_lint.gd`（0 errors，三個 era 閉包）、`tools/balance_sim.gd`、`tests/ui/ui_playthrough.gd`（headless；新增錢莊窗、組織面板、製作窗的截圖步，截圖寫 `K:\Project\JY-Mini-OL-Work\shots\`）、M1 驗收 bot（1.0A-only 與預設各一次，全新世界、測試根目錄）、`tools/m2_acceptance.gd`、`tools/m3a_acceptance.gd`、`tools/story_acceptance.gd --all`（含所有新任務的 `test_plan`）、`tools/m3b_acceptance.gd`、`tools/net_smoke.gd`、`tests/bots/close_mid_battle_bot.gd`（`--close-mode=wm` 與 `quit`，log 無 SCRIPT ERROR）。

---

## 12. 交付與整合

1. 各 WP 交付：改了哪些檔（必須都在 §9.1 自己的欄）、新增的 `class_name`（整合者先 `--import`）、`# M3B_PLAN 缺漏` 清單、自己的單元測試結果、殘留 Godot 程序檢查（`tasklist`）。
2. 內容 WP 交付：碎片檔 JSON 合法、`todo_verify`、`owner_decisions`、`test_plan`。
3. WP-MERGE 交付：合併報告（覆寫、改名、缺 id）、lint 0 錯誤、`ART_REQUEST.md` §8。
4. 整合者：跑 §11.4 全部；同步 GDD（§1.4 E1–E13）、WORLD_2001（§6.1、§6.3）、M3A_PLAN（§1.2 婚姻）、STORY_PLAN（§1.2 延後清單）、ART_REQUEST（:384、§6.5）、README（1.0B 預設、京城、丐幫、錢莊、鏢局、組織、生活技能、`m3b_acceptance`）；在本文件 §13 寫整合紀錄。
5. **不 commit**；不碰擁有者存檔；不寫 C:。

---

## 13. 整合紀錄（整合者填寫）

**2026-10-20 整合（WP-SECT、WP-ECON、WP-ORG、WP-UI、6 個內容碎片經 WP-MERGE 合併之後）。** 不 commit；不碰擁有者存檔；所有暫存、log、截圖在 `K:\Project\JY-Mini-OL-Work\`。

### 13.1 跨包不一致的修正

| 項目 | 原因 | 修正 |
|---|---|---|
| `test_battle_status` 狀態列數 | 合併加了情花毒 | 11 → 12 |
| `test_m3b_capital_jail`、`test_m3b_seize` | 合併後有真的 `jc_jail`（CAPITAL），AUTO 選它而不是測試的 `tcap_jail` | `test_sect_m3b_fixture.gd` 的 `before_each` 把資料裡真的 CAPITAL 牢房降成一般房間（只改記憶體，after_each 重建） |
| `test_world_chars::test_create_validation_order` | 京城 1.0B 可出生（O3） | 不合法出生城改用少林 |
| `test_world_npc::test_talk_sends_line_and_menu` | 武介山多了 `q_sm_shepi`（npc_links） | 任務數 2，抽查 `q_rabbit` |
| `test_ui_map_layout` | 西夏多 4 間（錢莊、鏢局、打鐵舖、布莊） | 13 → 17 間、霧的清單加 `xx_bank`、`xx_biaoju` |
| `test_ui_map_panel` 760×440 | 8 個新地區（高昌在最西邊）把全圖壓扁：驛站線穿過別的地區框、靈鷲的「你在這裡」壓在線上 | `world_map_view.gd`：驛站線找不到路時逐步縮小留白（6→3→1 px，`MapLayout.route_around`／`grid_route` 加 `clear` 參數）；「你在這裡」找不到空位時在記號周圍 150 px 內每 8 px 再找一圈 |
| `test_art_registry::test_pose_never_borrowed_from_fallback` | 另一個工作階段 01:39 匯入全真出招圖 | 那個工作階段 01:56 已自行改測試（改用張三丰），整合者未動 |
| 故事驗收 4 條（`use@`、`expect_no_act@`、`expect_locked@`、`setup.sect_rank`） | §5.4／碎片 `test_plan` 用到的語彙 bot 還沒有 | `tests/bots/story_bot.gd` 加 `use@<item>`、`expect_no_act@<qid>:<act>`、`expect_locked@<npc>:<node>:<choice>`、`debug_give:<item>:<n>`、`setup.sect_rank`、`setup.attrs_exact`，expect 加 `sect_rank_pending`、`conditions_absent`、`money_delta`、`learn_points_delta`、`skill_prof_delta` |
| `q_ym_douji` 醉倒路徑 | bot 角色加強到屬性 150，根骨 12 的設定蓋不下去 | 該路徑 `setup.attrs_exact: true` |
| `q_ym_tuoyin` 第二路徑 | 只有一張麻布時階段停在 `s_buy`（COLLECT），拓碑人的對話根本不會開，`expect_locked` 走不到 | 改成 `expect_stage:s_buy` → `debug_give:r_mabu:1` → `expect_stage:s_stele` → 拓印 |
| `q_ym_tuoyin`、`q_ym_mawang` 的 `money_delta` | 路上打怪掉錢，角色銀兩增減不等於獎勵 | 改用 `money`（任務獎勵事件加總） |
| M1 bot 第 4 步 | 預設世界有 1.0B | §11.3：有 1.0B 時京城出生成功 → 選回原角色 → 刪掉京城角色 |
| M1 bot 第 14 步 | 1.0B 世界往少林的最短路改走京城南郊（華山古道 → 南郊岔路 → 嵩山古道 → 嵩山松林），不經嵩陽茶棚 | 1.0B 世界接受南郊岔路或嵩陽茶棚，仍不准進京城城內；1.0A 世界照舊必須經嵩陽茶棚 |
| M3a 驗收（武當公敵、少林坐牢）與 UI 驗收的 M3a 坐牢段 | 新世界預設 1.0B → `jail_location: AUTO` 解析成 CAPITAL：關京城監獄、事件可能是 `jail_in_capital`、出獄到京城衙門 | `m3a_sect_bot.gd`、`ui_playthrough.gd` 依 `world_info.jail_location_resolved` 判斷牢房與出獄地點；京城監獄裡沒有看守人可談（在監獄門口），UI 驗收那段改成直接坐滿刑期 |
| 組織面板連署中的標題 | 連署中寫「成員 0／50」看不出進度（截圖審查） | `OrgUi.org_header`：「名字　連署中（n／need 人簽名）」；成員區寫還要幾人連署與已簽名名單 |

### 13.2 平衡（`tools/balance_sim.gd` 新案例，§11.2）

| 案例 | 結果（runs=500） |
|---|---|
| `walk_jc_gb`／`walk_jc_jq`／`walk_xx_gc` | 存活 100%／100%／98.2%（5／3／11 步） |
| `gb_xiejiao7`（實戰 3000、一階 30 打 7 個邪教門徒） | 86.0% |
| `gb_manbing_party3`（三人各 6 萬）／`gb_manbing_solo`（單人 1 萬） | 94.4%／0% |
| `gb_xiaohuang` | 100% |
| `gc_robot`（實戰 3 萬）／`mw_mawang`（實戰 2 萬） | 55.2%／75.6% |
| `econ_chain` | 只印報告（見 13.5 I2） |

合併時的怪物數值是把原作 HP 直接搬進本作，參考角色全部 0% 勝率（P3、武學 60、氣 1780 也打不贏馬王、機關人）。整合者照本作級距調：武學、招式等級、兵器與護甲強度乘 f、臂力根骨乘 (0.5+f/2)：
邪教門徒 f=0.45、蠻兵 0.6、馬王 0.35、機關人 0.25；原值寫在各列 `src_note`（【設計提案】）。
**審查更正（2026-10-20）**：「氣不變（原作數值）」只對邪教門徒（300）、馬王（2000）、機關人（3000）成立；**蠻兵的氣 6000 不是原作數值**（原作 100000 HP），是依本作級距換算的【設計提案】。馬王與機關人的 ×0.35／×0.25 已由 §13.6 的審查修正取代。

### 13.3 驗收

`tools/m3b_acceptance.gd`＋`tests/bots/m3b_bot.gd`（§11.3 的 10 個劇本全部 PASS）。與 §11.3 的差異：

- `craft`：配方鑄鐵劍要木炭（`r_mutan`）不是焦炭，西夏打鐵舖買木炭。
- `gaibang`：乞討對象用京城廣場王大娘、大街李大嬸、藥鋪郎中；姜乞丐是丐幫自己人（`no_beg`）→ 另斷言 `cant_beg`。
- `capital_jail`、`escort`、`org`：多人長途步行時關掉遇敵（`encounters_enabled`）；捉拿段關掉敵對入山（`sect_hostile_entry`），讓叛僧走得出少林山門。都是主機在伺服器設定能改的選項。
- `escort` 丐幫旁證角色的門派直接寫（同故事 bot 的 `setup.sect`）。
- 時辰快轉後托鏢到站、聚會用 `debug_set world_s_add`／`hour`（會跑 `_minute_jobs` 與 `check_clock`）。

UI 驗收（`tests/ui/ui_playthrough.gd` 第 20 步）：叛出少林 → 丐幫拜師 → 袋位頁 → 屬性窗袋位 → 乞討 → 錢莊窗存錢存物 → 鏢局窗三頁 → 製作窗 → 書吏創立組織 → 組織面板；截圖 `K:\Project\JY-Mini-OL-Work\shots\m3b\integrate\71–83_m3b_*.png`。

### 13.4 文件同步

GDD（E3、E4、E5、E6、E11、E12、E13；開放問題 10、17 關閉）、WORLD_2001（E1、E2：§6.1、§6.3）、M3A_PLAN（E7 婚姻 → M5）、STORY_PLAN（§1.2 延後清單中 M3b 已做的六條）、ART_REQUEST（E10：7.4；6.5 明教、桃花島 → M6／M7）、README（M3b 一節、M3b 驗收、era 預設、UI 驗收、目錄）。
E8、E9 是研究文件的日期與名稱更正，研究文件沒有對應的錯誤句子可改（WP-MERGE 已照新說法寫 `src_note`），不另改。

### 13.5 整合者的擁有者決定（預設，已採用；可推翻）

- **I1** 平衡：邪教門徒、蠻兵的武學與攻防照本作級距縮小；邪教門徒的氣保留原作 300，蠻兵的氣 6000 是原作 100000 HP 的換算【設計提案】（不是原作數值；審查更正）。馬王、機關人的縮小已由 §13.6 取代。
- **I2** `econ_chain` 只印報告、不判定：基準（打獵收益）與材料是自己採還是買差很多；目前打獵基準 1.37 兩／精，四種採集 0.15–0.63 倍、22 條配方在 0.3–1.5 倍之外（多數是低於 0.3，賣成品不如賣材料），等擁有者看數字再定價或定門檻。
- **I3** 1.0B 世界往少林的建議路線可以走京城南郊（不進京城城內）；M1 bot 照此接受兩條路。
- **I4** M3a 驗收、UI 驗收在預設（1.0B）世界驗京城監獄；1.0A 世界仍驗各派思過處（同一份程式依 `jail_location_resolved` 判斷）。
- **I5** 組織面板連署中顯示連署進度而不是成員數（UI 文字調整）。

---

### 13.6 審查修正（2026-10-20，三份審查：資料出處、平衡、程式與介面）

**資料出處**

| 項目 | 修正 |
|---|---|
| 京城監獄標成【已證實】 | `jingcheng.json` 地圖 `src_note` 拿掉監獄（只留 DIAO/2-1 證實的京城、鏢局、紫禁城、天地會）；`jc_jail` 加 `src: proposal`、位置【待考證】。**O12 改**：`AUTO` 只把被捉拿的公敵關京城監獄，違反門規仍關各派思過處（`SectSystem.breach_jail_resolved`、`world_info.jail_breach_resolved`）；`CAPITAL` 才連違規也送京城。GDD 6.5、README、M3a／UI／M3b 驗收、`test_m3b_capital_jail` 跟著改 |
| 機關人拿掉了「每下 200+」 | 還原高攻（臂力 60、拳 110），改成慢、不招架、沒護甲（敏捷 4、招架閃躲 5、護甲 5）→ 隊伍內容；`gc_robot_hit` 平均每下 ≥ 200、`gc_robot_party3`（三人各 3 萬）≥ 85%、`gc_robot` 單人 3 萬 ≤ 20%；迷宮 3 層機關人、6 層銅甲一次一隻 |
| 蠻兵氣 6000 寫成原作數值 | `src_note`、13.2、I1 改成「原作 100000 HP 的換算【設計提案】」 |
| 馬王＝馬賊王建了兩次 | 合併：`m_jcn_mazeiwang` 刪掉，`m_mw_mawang` 名稱「馬賊王」、簡稱「馬王」，馬王洞與丐幫空地共用；`a_jcn_huangzhaojia` 刪掉，`a_huangjia` 改名黃罩甲、防 35（舊 id 保留）；歧義只記在 `m_mw_mawang` 一處 |
| 馬王洞 era 沒有依據 | 改 1.0B（地圖、地區、馬賊、馬賊王、`q_ym_mawang`、環境句、傳聞；`ym_gate` 西出口帶 era、1.0A 描述不提山洞；胡斐的任務由 `patches/1.0B.json` 掛上） |
| 未重抓的結局標 verified | `q_sm_dujulaoren`、`q_sm_esi_nongfu`、`q_sm_ahuo`、`q_sm_ahong`、`q_sm_yuntie` 整列與結局改 `unverified`（`QuestDef.SRC_TAGS` 加 `unverified`）；只有標題的 `q_jq_liumei`、`q_jq_duanchang`、`q_tdh_ruhui`、`q_ym_xiaofeng`、`q_sm_rixing`、`q_sm_shepi`、`q_sm_litong` 整列 `proposal`；`q_ym_tuoyin` 結局 `field_src.money = proposal`；`gb_sect_assembly` 改 proposal（辰時每日是 O8）；埋伏每處 7 個標【設計提案】 |
| `q_gb_dai1` 不能逃 | 照研究與本文件：埋伏可以逃，逃走或戰敗後那一處要等 1 遊戲日（新的 fight 欄位 `retry_days`；`QuestSystem` 記在 vars，`test_m3b_retry_days`） |
| 北門查小鏞 | `n_jc_cha_n` 改 era `xkd`（後期擺法），1.0B 北門不放 |
| E9 沒改 | 研究 975、1072 行改正、待修正清單標已修；STORY_PLAN 115 行加註研究已更正；延後清單加愛吃熊肉的老祖、劍隱事件 |
| GDD | 馬王列（氣 2000、實戰 30000、1.0B、劍坤任務標【後期版】不接）、機關人列（氣 3000、實戰 60000、隊伍內容）、黃罩甲、丐幫入派條件標【後期版／待考證】、`q_mawang` 標後期 |
| 兩個阿火 | `n_xe_miner` 顯示名改「老礦工」（2002 清單的人名留在 `src_note`） |

**平衡**（`tools/balance_sim.gd`）：先拿 1.0A 既有怪校準參考角色 `_p_at`（50% 勝率點 ≈ 0.7R–2.5R，`cal_1_0a_*` 鎖住），再照同一級距調 1.0B 新怪：馬賊 ×0.9、道人頭子 ×0.8、隱面人 ×0.65、惡道人頭子 ×0.9、高昌惡賊 ×0.7（原值在 `src_note`）；馬賊王改成「武學 38、慢、氣 2000」（boss ≥ 嘍囉，`mw_boss_ge_minion`）。新案例：`spot_jcn_kongdi`、`spot_jq_qinghua`、`spot_jq_dilao`、`spot_jq_eyuchi`、`spot_gc_maze2/3/5`、`spot_mw_cave1_solo`、`spot_mw_cave2_party2`、`q_ym_mawang_party3`／`solo`（洞底改 2 隻、門檻實戰 2 萬、對白說要組隊）。護國法師、煞風寨寨主是 2001-10-24「26、29 級都打不過」的站點挑戰，不調。
保鏢酬勞照步數約 7.5 兩／步（西夏↔京城 145、西夏↔大理 150、大理↔京城 200），趟子手台詞不再說京城線較遠。`q_gb_xin` 不動（見擁有者決定）。京城加武館（`jc_wuguan`、`n_jc_wushi`、`ms_jcwg_*`）與驛站送信（`q_letter_jc_xx`、`q_letter_jc_dl`）【設計提案】。
生活技能：~~粗工具改用鐵礦石打、布衣用兩把麻縫~~（審查 3 改回官方鏈，見 13.7），米 10、木材 7、白飯 ~~10~~ 14、烤魚 20 → `econ_no_loss`（審查 3 起：成品收購價 **>** 材料）通過，採集約打獵的 0.44–0.63 倍。
組織：連署過期、作廢（發起人加入別的組織）、撤回 → 全額退手續費（`world.org_refunds` 給離線的發起人）。
文字：京城南門描述、華山腳下／嵩山松林的 `desc_1_0b`、西夏東門描述、執法長老的污衣派戒律改成傳統、張員外傳聞。

**程式與介面**

| 項目 | 修正 |
|---|---|
| 舊護照驗不過 | `Passport.verify` 另用「不加 bank、guild、sect_rank、sect_rank_pending」的舊格式驗（`test_pre_m3b_passport_verifies`）；§4.12 的「不受影響」更正 |
| 保鏢戰死後卡關 | 鏢車走散後回給任務的鏢頭再談一次 → 重新交給你（不另收費；選單顯示 READY；`quest_escort_resumed`） |
| 搭車完成保鏢 | 護送中 `travel` 回 `escorting` |
| 刪角色留在組織 | `OrgSystem.on_char_deleted`：移出成員、連署、邀請；幫主 → 位階最高（同階最早加入）的成員，沒人就解散 |
| 連署發起人不能撤回 | `OrgUi.normalize_info` 保留 `my`、`rank_in` 用 `my.rank`；連署中只顯示「撤回連署」 |
| 書吏頁不更新 | `found`／`sign` 後重送 `npc_menu`（refresh），組織面板一併重要 `org_info`；UI 驗收檢查清單 |
| 托鏢頁 | 勾選框深色字；運費與「托鏢」鈕移到捲動區外 |
| 小項 | 永遠不會施捨的 NPC 不列「乞討」；`EscortSystem.take` 呼叫 `quests.on_items` |

### 13.7 審查修正 3（2026-10-20，三份審查：資料出處、平衡、程式與介面）

**資料出處**

| 項目 | 修正 |
|---|---|
| 1.0A 世界出現 1.0B 內容 | `talk_n_ec_xx_banker`（京城分號）、`talk_n_ec_xx_biaotou`（丐幫不能運鏢）的 1.0A 文字拿掉那一句；`patches/1.0B.json` 的 `p1b_xx_banker_talk`、`p1b_xx_biaotou_talk` 在 1.0B 補回 |
| 四個任務列標 verified | `q_sm_lengning`、`q_sm_chengwei`、`q_sm_qidu`、`q_sm_zhuadu` 整列改 `later`（只有標題與預告已證實）；七毒的辰～未時寫進 `q_sm_qidu` 的 `src_note`（由楚禮子 `appear.hours` 執行） |
| 范遙不說話標【已證實】 | `talk_n_mj_fanyao` 改 `unverified`；`n_mj_fanyao` 的 `src_note` 把「連話都不跟她說」標【待考證】（08-14、08-17 本文抓不到），「不能加入明教」的獨立出處是 juezhan/4 |
| 丐幫入派善惡 ≥ 0 | 研究找不到出處 → 從 `join_requires` 拿掉（只留無門派＋非本派公敵／叛徒）；`teach_requires` 善惡 ≥ 0 照舊（jy2-4-2）；O5、§10、GDD 門派表同步 |
| GDD 與研究矛盾 | 合體技從「來源資料片未定」移出（官方第二片資料片 1-2-6-1 → M3c）；降龍十八缺三改「2002-07 俠客島已有，M11 推測不成立」 |
| 血魔刀法沒人追 | §1.2 M3c 清單加上（M3A_PLAN D7 延後、第七話 2001-11-22 標題） |
| 製作鏈跳過鐵塊、布匹 | 改回官方鏈：柴刀／鋤頭／十字鎬／採沙器用鐵塊、布衣用一塊麻布；改價錢而不是改結構：線軸 7、麻布 17、布衣 20、鐵礦石 14、鐵塊 44、鋤頭 60、白飯 14；紡麻線 1 麻 → 1 線軸、淘洗 3 礦砂 → 1 鐵礦石（都【設計提案】）。`econ_no_loss` 改成嚴格大於（白飯、淘洗、粗布道袍以前剛好打平） |
| 黃罩甲 era 1.0A | 改 1.0B（唯一來源馬賊王是 1.0B；M3b 新 id，沒有舊存檔帶著它） |

**平衡**（`tools/balance_sim.gd`）

| 項目 | 修正 |
|---|---|
| 二袋要三人各 6 萬，二袋只開上限 60 的武功 | 蠻兵氣 6000 → 2500、武學／招式／兵器／護甲 ×0.85、臂力根骨 ×0.9、級距 60000：三人各 2 萬 100%、兩人各 2 萬 0%、單人 1 萬 0%（`gb_manbing_party3`／`gb_manbing_duo`／`gb_manbing_solo`）；任務文字「邀齊三人（每人實戰兩萬上下）」 |
| `q_jq_liumei` 鱷魚 | 地牢文字改「三人結伴、每人實戰六萬」、公孫止留客時警告、傳聞加一句危險；`q_jq_eyu_party3`（三人各 6 萬 ≥ 80%）、`q_jq_eyu_duo`（兩人各 6 萬 ≤ 40%）鎖住文字 |
| 絕情丹一次性陷阱 | 新物品欄位 `keep_on_use`（`Survival.use_item`、戰鬥 `_x_item` 都不扣）：絕情丹解毒不消耗——「一人一顆」照原作，但不會因為解過一次毒就永遠解不了；驗收 `jueqinggu` 檢查解毒後丹藥還在 |
| 情花林、丐幫空地沒警告 | 谷口描述、樊一翁對白、山路岔口與空地描述加上實戰門檻警告 |
| 深層迷宮打不了又沒收穫 | 銅甲機關人只在第 6 層、一次一隻（照 §8.3）；武學／招式／護甲 ×0.83 → 三人各 6 萬 ≥ 60%（`gc_tongjia_party3`）、兩人 ≤ 10%；4、5 層只有機關人；機關零件 80 → 300（機關人不掉錢）；`spot_gc_maze4/5/6` |
| `q_ym_mawang` 人數 | 文字改「湊齊三人、各 2 萬；兩人得各 3 萬」；`q_ym_mawang_duo`（兩人各 2 萬 ≤ 10%） |
| 黃罩甲刷裝 | 防 35 → 16（皮甲兩倍）、價 3000 → 1500、掉率 0.15 → 0.08；`mw_mawang_huangjia`（3 萬穿著打馬賊王仍 40–85%） |
| 文字 | 趟子手「一步七八兩」；埋伏與傳聞「橋下」→「橋邊／橋頭」；嵩山古道「經少室山腳到少林山門」；陳長老說二袋去找姜乞丐；`q_gb_dai1` 西夏段提京城驛站車資 120 兩；絕情谷驗收訊息不再印空括號 |

**程式與介面**

| 項目 | 修正 |
|---|---|
| 鏢車丟了介面領不回 | `turn_in` 遇到可重新領的護送 → `_escort_restart`；選單項加 `resume: true`，鏢局保鏢頁顯示「重領鏢車」、NPC 任務頁顯示「重新領回」（送 `quest_talk`）；`test_m3b_review3_world` |
| 存檔順序 | `EscortSystem.take` 改 `save_now(true)`（先 world 後角色，同翻屍體）；`OrgSystem._pay_refund` 入帳後馬上 `save_now(true)`；測試讀磁碟檔驗證 |
| 坐牢、引路不丟鏢車 | `QuestSystem.drop_escorts`（倒下也走這裡）；押進監獄、出獄、逐出師門與犯戒瞬移到山門時叫它；引路護送中回 `escorting`（文字改成不能搭車也不能引路） |
| 介面沒拍到的畫面 | UI 驗收加：錢莊取出、有貨的取貨單（debug `consign_demo`）、組織邀請提示（debug `org_invite_demo`／`org_demo_clear`）、成立後的組織面板（debug `org_activate`，選自己、檢查每個動作鈕都在對話框內）。幫主的動作列拆成三行（對象名字一行、開除／位階一行、封號／移交一行） |
| 連署期限 | 書吏頁的連署列與組織面板顯示「還剩 …」（主機在書吏選單也給 `left_s`）；自己發起的連署標「（你發起的）」 |
| 組織冒用門派名 | `OrgSystem.reserved_name`：全部 era 的門派名（「X」「X派」）與天地會不能當組織名（`org_name_taken`）【設計提案】 |
| 刪除寄件人的貨 | 刪除時把寄件人的在途／待領貨標 `from_deleted`（收件人照領）；退回時 `tick` 直接清掉 |

### 13.8 審查修正 4（2026-10-20，三份審查：資料出處、平衡與文字、程式與介面）

**資料出處**

| 項目 | 修正 |
|---|---|
| 1.0A 世界漏 1.0B 地名 | `xx_bank` 描述只提大理（1.0B 的京城分號由掌櫃對白 `p1b_xx_banker_talk` 說；`desc_1_0b` 只給有 1.0B 出口的房間，lint §4.4）；`q_sm_lengning` 鑄劍步驟拿掉「開放神鵰大俠時京城…」；`test_m3b_review4_data` 掃整個 1.0A 視圖（京城、神鵰大俠、丐幫、絕情谷、馬王洞） |
| 著急的阿火的獎勵 | 照研究 1188 行（2001-10／11 丐幫跑腿文）「只 +3 名聲」：拿掉歷練 +3，結局 src `verified` |
| 西夏老人送藥 | 研究 1188 行「西夏老人送藥（每天一次 +1/+1）」與「獨居老人」（王老先生、西夏錢莊旁、買藥送藥）判定是同一件事【設計提案：合併】→ `q_sm_dujulaoren` 改每天一次、名聲 +1、歷練 +1；15 兩留著標【待考證】（`field_src.money: unverified`） |
| 丐幫跑腿、半仙、新物品沒做也沒列 | §1.2 M3c 清單與 STORY_PLAN §1.2 補列：京城半仙、無敵烙跑鞋、夜明珠、柯鎮惡 → 郭靖、三八紅 → 豬哥義、武林帖、「英雄帖 1 萬」 |
| 馬賊王比來源強 | gaoshou/25「弱、18 級」→ 級距 30000 → 11000（低於惡道人頭子、道人頭子、隱面人；與熊霸天同檔），武學 28、刀 14、甲 28、氣 2000 不變；嘍囉馬賊 10000 → 7000；馬王洞建議實戰 [10000, 30000]；`q_ym_mawang` 門檻 2 萬 → 1.5 萬、文字「每人 1.5 萬；兩人得各 2 萬」 |
| M3B_PLAN 正文還寫馬王洞 1.0A | §1.1、§2.2、§3.1 地區表、§3.2 接點圖與出口表全部改 1.0B（審查改） |
| 鬼王與馬王洞同一份清單、era 不同 | 鬼王留 1.0A，理由寫進 `regions.guiwang.src_note` 與 GDD 地區表：馬王洞另有 2001-10-13、2001-11-12、鐵心網 FAQ 三個 1.0B 期間的來源；鬼王沒有任何 2001 日期的證據，而且是 M1 核心循環的終點（WORLD_2001 D4 擁有者決定） |
| 靈犬小黃引用不存在的預告 | `src_note` 改：研究只確認標題，「京城的狗討食」題材【設計提案】；§8.3 同步 |
| 小黃「乞討 30 免追」是後期 | 預設拿掉（`harass[0].unless = []`，附 `unless_src_note`）：2001-11-06 玩家還在開玩笑說狗哪天會不追；要後期規則就放回 `skill_min qitao 30` |
| 四～七袋用 2006 數字標 xkd later | 列 src 改 `proposal`，`src_note`：四～七袋存在、直接升是 2002-07【已證實】；門檻數字借用免費版（約 2006）【後期版數字・設計提案】 |
| 游啟明 | 2001-11-03 一袋情報只寫「游啟」；「游啟明」只見於 2001-08 假消息 → NPC 名、任務、對白、物品全部改「游啟」（id `n_gb_youqiming` 沿用），同一人與否【待考證】 |
| GDD §1.2 註 1 | 改寫成「2001 明教只有 NPC，2001-08-14 入口法 08-17 證實是騙局」，不再先引用騙局文當證據；研究 710 行標 Superseded |

**平衡與文字**

| 項目 | 修正 |
|---|---|
| 京城驛站管事說沒有信 | `talk_n_jc_station`（基本列與 1.0B patch）：車資＋「這兒也有信要往西夏、大理送」。實際在 1.0B 生效的是 patch，基本列是舊文字，兩邊一起改 |
| 嵩山古道方向 | `jcw_songshan`：「往南下山接上嵩山松林，再從松林往東經少室山腳就到少林山門」；`sl_gate`：「往西下山是少室山腳」 |
| 京城→大理的信走不通的路 | `q_letter_jc_dl` 文字改照 `q_ec_biao_jc_dl` 的路線（嵩山古道、松林、武當岔路、終南、峨嵋、崆峒）；測試用 BFS 驗證最短路經嵩山、不經華山腳下 |
| 南門守衛 | 基本列與 patch：「去武當走嵩山那頭最近；恆山得先下到華山腳下再往西北。雁門關、丐幫走北門」 |
| 馬王文字 | `q_ym_mawang` 結局 src_note 掉率 0.08；首殺傳聞「雁門關西邊的馬王洞」 |
| 京城北郊建議實戰 | [0, 20000] → [0, 40000]（空地要兩三萬，北路有護國法師、煞風寨寨主） |
| 救柳姑娘獎勵偏低 | 歷練 60 → 100（比照 `q_xd_xuehai`、`q_yangkang`）【設計提案】 |
| 「兩人得各 X 萬才有勝算」沒測 | 新 `q_ym_mawang_duo2`（兩人各 2 萬 ≥ 40%）；`q_ym_mawang_duo` 改兩人各 1.5 萬 ≤ 10%；新 `mw_mawang_tier`（2.5 萬單挑：馬賊王勝率 ≥ 道人頭子 ≥ 隱面人） |
| 製作不賺錢、丐幫袋位慢、保鏢組隊全額 | 不改，列擁有者決定（§13.8 下方） |

**程式與介面**

| 項目 | 修正 |
|---|---|
| 連署人加入別的組織後仍算數 | `OrgSystem._add_member` 把新成員從別的連署名單（signers、signer_names）拿掉；`valid_signer_count`（不是發起人、還沒入會）給 `sign`、`tick`、書吏選單與面板用；舊存檔殘留也不算 |
| 創立扣手續費沒存檔 | `found` 扣費、建連署後 `ws.save_now()`（角色檔先、world.json 後）。審查建議 `save_now(true)`，但 world 先寫時當機會變成「錢沒扣、連署在」→ 過期再退一次＝複製；角色先寫最壞是損失（同 `EscortSystem.send`） |
| 錢莊取空後數字鍵沒編號 | `BankWindow._render`：目前那一欄空了、另一欄有東西就換過去 |
| 邀請沒警告會作廢自己的連署 | 主機的 `org_invite` 事件帶 `petition_name`；提示框多一行紅字「接受後你發起的連署「X」將作廢（退還手續費）」 |
| 組織面板選到自己仍能動位階下拉 | 沒選人、選到幫主或自己時 `RankPick` 也停用 |
| `EscortSystem.send` 沒有金額上限 | `money > BankStore.CARRY_MONEY_CAP` → `bad_amount`（網路路徑原本就由 `INT_RANGES` 擋） |

**擁有者決定（審查 4，預設已採用，可推翻）**

- R4-1 西夏老人送藥併進「獨居老人」（每天一次 +1/+1，15 兩【待考證】）。若要分成兩件事，另建一條每日送藥任務即可。
- R4-2 馬賊王級距 11000、`q_ym_mawang` 門檻 1.5 萬（照 gaoshou/25「弱」）。
- R4-3 小黃預設不免追（2001 沒有門檻）；後期「乞討 30 免追」留在 `unless_src_note`，要用就放回。
- R4-4 四～七袋門檻沿用免費版數字（標【後期版數字・設計提案】），xkd 世界才有。
- R4-5 柯鎮惡 → 郭靖、三八紅、武林帖、京城半仙、無敵烙跑鞋、夜明珠延後 M3c（缺位置或機制）。丐幫袋位因此比 2001 慢：可重複的歷練約每遊戲日 20 點（加上送藥 +1），一袋約 9 遊戲日。
- R4-6 製作不當賺錢的手段（只有煉紫紋鐵塊、冷凝劍、張員外划算）：不改，`econ_no_loss` 照舊嚴格；要調就調每個配方的精耗或成品收購率。
- R4-7 保鏢 `party_credit` 照舊每人全額：每個人自己的冷卻 1 遊戲日，組隊的每人收入＝各自單跑一車，不是倍增。
- R4-8 救柳姑娘歷練 100（原 60）。
- R4-9 鬼王留 1.0A（理由見上）。

## 14. 開放問題（擁有者決定；預設值已寫在 §1.3）

1. 丐幫山門是京城的一部分還是另一張地圖（預設：京城北郊山路上的獨立地區，O4）。
2. 2001 二階門檻（10-09 的 30/20/30 與 12-01 的 50/30/30/二袋）是改版還是誤讀（預設 12-01，O6）。
3. 一袋是否也等月初聚會（預設：一、二袋都等聚會；聚會預設每日，O8）。
4. 乞討的收穫與 1.0B 小黃門檻（預設：小額施捨；不免追，O7、O9、R4-3）。
5. 京城監獄在哪裡、是否取代思過處（預設 `AUTO`，O12）。
6. 錢莊是否三城分開（預設共用，O15）。
7. 托鏢費用、時間、劫鏢（預設表 §10；不劫，O16）。
8. 馬王＝馬賊王？馬王洞在雁門關還是別處（預設雁門關附近，E4）。
9. 計老人居、高昌迷宮各層內容（預設只放 NPC 對話與機關人）。
10. 10 種非工匠生活技能哪些開服就有（預設全部 1.0A，`src: "later"`）。
11. 楚禮子的位置（預設星宿大殿左偏殿）。
12. 天地會入會的實際步驟（預設 §8.3 的【設計提案】三段）。
