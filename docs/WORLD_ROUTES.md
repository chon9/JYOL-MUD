# 城際路線與驛站送信改版（WORLD_ROUTES）

> **已被 `docs/WORLD_2001.md` 取代（地理部分）**：擁有者決定世界照原作 2001 開服地理（一整片連續野外、城與城之間步行、1.0 只有西夏與大理、京城是 1.0B 內容、驛站只管送信、馬車是預設關的伺服器選項）。
> 本文以京城為樞紐的路網不再採用；研究資料、房間文字、遇敵平衡規則、送信改版、變更清單與審查紀錄仍供參考。
>
> 狀態：提案，待擁有者確認。依據：`docs/research/verified_research.md`，以及本輪的地理調查（17173 座標表 gaoshou/17、新手指南 xinshou/13·19·20、懷舊版新手日記 jy2_3_2·jy2_3_9、2002 年山洞清單）。
> 標記：【已證實】有原始資料；【設計提案】本作自訂；【設計提案・非原作】原作沒有的便利功能；【待考證】查不到資料。
> 範圍：只改 M1 已有的地區。新增 5 個野外地區、19 個野外房間、1 個城門房間。

---

## 1. 決定摘要

| # | 決定 | 依據 |
|---|---|---|
| 1 | 預設玩法**拿掉驛站馬車**。城市之間只能走路，經過野外會踩地雷遇敵。 | 【已證實】野外踩地雷遇敵（17173 xinshou/13：「特定場景為踩地雷式進入戰鬥畫面」）；2001 年新手指南 xinshou/19：「出野地後按下 ctrl+M 就可看地圖」「先問一些人要進入的門派在那，再慢慢前進」（原文講的是走去門派，不是城際，但足以說明靠走路移動）。送信日記「途中遇到許許多多的盜賊……邊打邊跑」出自懷舊版日記【後期版】。「2001 年沒有馬車或傳送」是**查不到反證**，不是有資料明說沒有，標【推定】。 |
| 2 | 馬車程式**保留但預設關閉**：新增 `server_options.stagecoach_enabled`，預設 `false`。打開時就是現在的付費瞬間移動。 | 【設計提案・非原作】給人少、時間少的好友房用。「馬車是 2018 年至尊服才有」這句 `verified_research.md` 沒有收錄，本次複查也找不到來源，改標【待考證】。 |
| 3 | 驛站的工作**只有驛站送信**：接一封信，自己走到目的地驛站交給管事，拿到銀兩和名聲。 | 【已證實】官方屬性頁「保鏢與驛站送信皆能提升名聲值」。「接信、自己走過去、交給驛站長、領錢」的流程出自懷舊版（2008）日記【後期版・推定沿用】。 |
| 4 | 送信**沒有時限**，**不收押金**。 | 不收押金【後期版】（懷舊版：鏢局要押金，送信不用；2001 版沒有直接資料）。時限【待考證】：查不到資料，所以先不設。 |
| 5 | 死亡或下線後回到記錄點，本作照樣保留，不另外加傳送或回城道具。 | 【已證實】17173 yinan/11：「設定記錄點以後，每次你死亡重生或離開遊戲重新進入時都會出現在記錄點所在地。」原稿說這是「唯一」捷徑：資料沒有這樣寫，只是沒找到別的回城方式，改標【推定】。 |
| 6 | 新蓋兩條官道：**北路** 西夏 ↔ 京城、**南路** 京城 ↔ 大理。城門到城門 11–13 步，實際遊玩約 3–4 分鐘（包含 1–2 場遇敵）。西夏 ↔ 大理之間的**西路**（大漠、河川）放到 M3，見 §2.5。 | 世界方位：西夏在西北 (7296,2966)、大理在西南 (5903,18617)【已證實，17173 gaoshou/17】。京城**不在** 2001 座標表裡：京城是 2001-09-28「神鵰大俠」資料片才加的第三座城【已證實】，放在東北、靠近少林是【後期版】推定。所以這兩條路都是**本作設計**，不是 2001 開服就有的路；開服時唯一的城際步行路線其實是西夏 ↔ 大理（西路）。 |
| 7 | 少林、華山仍然從京城南郊走過去，鬼王洞仍然在大理郊外蒼山林道北邊。 | 沿用 M1 |

**不採用的做法**：信件在身上時不准搭車。打開馬車選項本來就代表這一桌人選擇方便，不必再加限制。

---

## 2. 世界路線圖

### 2.1 總覽

```
                    恆山（M3，岔路封閉）
                          ┆
xx_gate_e ─ xw_road ─NE─ [西夏東郊 xixia_east] ─E─ [恆山山麓 hengshan_foot] ─E─ jc_gate_w ─SE─ jc_street
   西夏                 （礦區、血刀洞外、黑龍潭）    （茶棚、稻田、岸邊）              京城      │
                                                                                     jc_gate_s
                                                                                         │
                                                         jcw_songshan ─W─ jcw_crossroad ─E─ jcw_huashan
                                                           （少林）          │S            （華山）
                                                                   [終南古道 zhongnan_road]
                                                                   （河邊、終南山腳、茶棚）
                                                                             │W
                                                                   [峨嵋山麓 emei_foot]
                                                                   （劍穴、峨嵋山腳、西林）
                                                                             │SW
                                                                   [大理–崆峒道 kongtong_road]
                                                                   （崆峒道口、大理東林）
                                                                             │W
 鬼王洞 ─ dlw_cave ─ dlw_forest ─ dlw_road ─E─ dlw_paddy ──────────────────────┘
                                   │S
                                dl_gate_n  大理
```

**步數**（一次 `move` 算一步）：

| 路段 | 步數 | 路線 |
|---|---|---|
| 西夏東門 → 京城西門 | 11 | xw_road、xe_road、xe_mine、xe_heilong、xe_river、hf_teahouse、hf_paddy、hf_shore、hf_fork、hf_jxroad、jc_gate_w |
| 京城南門 → 大理北門 | 13 | jcw_crossroad、zn_road、zn_river、zn_foot、zn_teahouse、ef_jianxue、ef_foot、ef_forest、kt_road、kt_wood、dlw_paddy、dlw_road、dl_gate_n |
| 西夏驛站 → 京城驛站 | 15 | 前面 2 步出城 + 11 + 後面 2 步（jc_street、jc_station） |
| 京城驛站 → 大理驛站 | 17 | 前面 2 步 + 13 + 後面 2 步（dl_square、dl_station） |
| 西夏驛站 → 大理驛站 | 30 | 經京城。M3 開西路以後約 16 步 |

**時間估算**（北路）：沿路遇敵率加總約 1.3（含 `xw_road` 0.15），代表平均遇 1–2 場。每步點擊約 2 秒，同一區內可以用小地圖自動趕路（`auto_walker`）；每場戰鬥 45–90 秒。加起來約 2.5–3.5 分鐘。南路的遇敵率加總約 1.6，約 3–4.5 分鐘。都在目標 3–6 分鐘以內。

**難度安排**（審查後修訂，見 §6）：
- 靠近城市的房間只有野兔、大野兔，往中段逐漸出現野狼、山豬。
- **北路**是新手（0–500 實戰）為了拜少林／華山第一次出遠門的路（驗收 bot 第 10 步）。茶棚以西最強只有野狼（combat_xp_ref 500）。山豬（900）只出現在茶棚以東兩格，而且比重低，平均每趟遇到山豬約 0.12 場（原稿約 0.34 場）。
- **南路**不能假設只有練過的角色在走。M1 只有少林、華山兩派，都在京城南郊，所以**大理出生的新角色要入門派，一定得走南路**。因此山賊不做成主力，只在峨嵋一段（`ef_jianxue`–`kt_road`）佔 10–15%，平均每趟遇到山賊約 0.1 場。靠兩端城市的房間（`zn_road`、`kt_wood`）完全沒有山賊。
- 每條路的中段放一座**茶棚**（住宿、乾糧、清水、金創藥，房間不遇敵），讓人歇腳補血。

### 2.2 新地區（regions.json）

所有新地區的共同欄位：`type: "WILD"`、`pk_allowed: true`、`birth_allowed: false`、`birth_room: ""`、`night_closed: []`、`era: "1.0A"`。`map` 指向 `res://data/maps/<id>.json`。

| id | name | city | suggested_xp | world_pos | src | 地名依據 |
|---|---|---|---|---|---|---|
| `xixia_east` | 西夏東郊 | xixia | [0, 2000] | [42, 7] | proposal | 【已證實（2002 山洞清單，非 2001）】血刀洞迷宮 (8626,2228) 在西夏東北，下方有礦區，礦工叫阿火；黑龍潭「從潭往右走到河邊」。注意 17173 gaoshou/17 的「血刀門」在 (477,12471) 西南，和這個「血刀洞迷宮」是兩個地方。這些地名尚未收進 `verified_research.md`。地區名稱是【設計提案】 |
| `hengshan_foot` | 恆山山麓 | jingcheng | [200, 3000] | [56, 4] | proposal | 【已證實】恆山 (15243,6043) 在北部中段；「恆山外的稻田和岸邊」（尚未收進 `verified_research.md`）。茶棚是【設計提案】（「原作的少林山腳、衡山都有小茶店」查無出處，【待考證】） |
| `zhongnan_road` | 終南古道 | jingcheng | [200, 4000] | [66, 44] | proposal | 【已證實】終南山 (17407,10987) 在中央偏南；「終南山左上方的河邊」 |
| `emei_foot` | 峨嵋山麓 | dali | [500, 5000] | [46, 50] | proposal | 【已證實】峨嵋 (13902,13772)；劍穴山洞在「峨嵋東南、終南西南」；「峨嵋出口左邊的樹林」；樹林迷宮 (11000,14000) |
| `kongtong_road` | 大理–崆峒道 | dali | [200, 4000] | [30, 52] | verified（地名） | 【已證實】「大理右邊的樹林，在大理和崆峒派之間」。GDD 7.2 已經有 `kongtong_road`，這裡直接沿用 |

建議同時把 `dali_wild.world_pos` 從 [0, 42] 改成 [16, 44]。這樣大理東邊來的步行線（kongtong_road → dali_wild）不會繞過大理城畫到最左邊。這項可做可不做，改的話要一起檢查 `test_ui_map_layout`。

大地圖座標的規則：`world_pos` 不能重複，數值在 0–1000 以內（`check_world_pos` 會檢查）。上面各點都沒有和現有區域重疊。北路畫在西夏郊外 [28,10] 和京城 [70,8] 之間。南路從京城南郊 [70,21] 往下，從少林 [57,33] 和華山 [83,33] 中間穿過，再往西南到大理一帶。

### 2.3 北路：西夏 ↔ 京城

`desc` 都是 MUD 風格的一兩句話。房間 id 前綴：`xe_`、`hf_`、`zn_`、`ef_`、`kt_`。峨嵋山麓用 `ef_`（emei foot），不用 `em_`，因為 `em_` 要留給 M3 的峨嵋派房間（比照 `sl_`、`hs_`）。`features` 只用 `FIELD`、`WOOD`、`WATER`。`encounter.count` 沒寫的話是 [1,1]。

**`data/maps/xixia_east.json`**（region `xixia_east`，`escape_tiles_hint: 2`，desc：「西夏城東北一帶山丘起伏，礦坑與深潭散落在官道兩旁。」）

| id | name | desc | exits | features | encounter（rate：monster w） | npcs |
|---|---|---|---|---|---|---|
| `xe_road` | 東北官道 | 官道離開荒原，折向東北。路邊一塊里程碑刻著「東至京城」，碑腳長滿了駱駝刺。 | SW→xw_road、E→xe_mine | — | 0.12：m_rabbit 70、m_bigrabbit 30 | — |
| `xe_mine` | 礦區山坡 | 山坡上挖了好幾個礦坑，礦工推著獨輪車進進出出。北邊陡壁上隱約有個洞口。 | W→xe_road、N→xe_xuedao、E→xe_heilong | — | 0.15：m_bigrabbit 80、m_wolf 20 | `n_xe_miner` 礦工阿火 |
| `xe_xuedao` | 血刀洞外 | 陡壁上裂開一道洞口，聽說裡頭是座迷宮，有馬王出沒。洞口新近被落石堵死，一時進不去。 | S→xe_mine | — | 0.20：m_wolf 100 | — |
| `xe_heilong` | 黑龍潭 | 一泓深黑的潭水，傳說潭底住著黑龍。潭水往東流出，順著走可以到河邊。 | W→xe_mine、E→xe_river | WATER | 0.15：m_bigrabbit 60、m_wolf 40 | — |
| `xe_river` | 潭東河岸 | 潭水匯成小河向東流去，岸邊蘆葦叢生，常有野狼下來喝水。 | W→xe_heilong、E→hf_teahouse | WATER | 0.18：m_wolf 60、m_bigrabbit 40 | — |

`xe_xuedao` 是封住的支線（M3 開放血刀洞迷宮），所以沒有 `IN` 出口。

**`data/maps/hengshan_foot.json`**（region `hengshan_foot`，desc：「恆山腳下水田連片，官道沿河向東直通京城西門。」）

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `hf_teahouse` | 路邊茶棚 | 官道旁搭著一座茅草茶棚，幾張木桌坐滿歇腳的旅人。老闆說往東再走半天就到京城。 | W→xe_river、E→hf_paddy | — | 無（安全） | `n_hf_teaman` 茶棚老闆 |
| `hf_paddy` | 恆山外稻田 | 山腳下開出一片稻田，田埂縱橫，水車吱呀作響。 | W→hf_teahouse、E→hf_shore | FIELD | 0.15：m_rabbit 50、m_bigrabbit 30、m_boar 20 | — |
| `hf_shore` | 恆山岸邊 | 河水在這裡轉了個彎，沙洲上繫著一條小船。對岸的雲霧裡露出恆山峰頂。 | W→hf_paddy、E→hf_fork | WATER | 0.18：m_wolf 50、m_boar 50 | — |
| `hf_fork` | 恆山岔路 | 官道在這裡分岔。往北的山路通往恆山和雁門關，路口有官兵設卡，不許通行。往東是京城西郊。 | W→hf_shore、E→hf_jxroad | — | 0.15：m_wolf 60、m_bigrabbit 40 | — |
| `hf_jxroad` | 京西官道 | 官道越走越寬，車馬行人多了起來，遠遠已經望得見京城的城樓。 | W→hf_fork、E→jc_gate_w | — | 0.10：m_rabbit 80、m_wolf 20 | — |

**`jingcheng.json` 新增房間**

| id | name | desc | exits | npcs |
|---|---|---|---|---|
| `jc_gate_w` | 京城西門 | 西門城樓下車馬往來。出了西門，官道經恆山腳下一路往西，可以通到西夏。 | W→hf_jxroad、SE→jc_street | 無。M1 不放 NPC，因為 `test_jingcheng_hub_only_has_hub_npcs` 規定京城只能有樞紐 NPC；M3 開完整京城時再加查小鏞和守衛 |

`jc_street` 加出口 NW→jc_gate_w。desc 改成「……西邊是驛站，西北是西門，北邊是客棧，南邊通往南門。」

### 2.4 南路：京城 ↔ 大理

**`data/maps/zhongnan_road.json`**（desc：「京城南郊往西南的古道，沿著終南山麓的河谷蜿蜒。」）

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `zn_road` | 南下官道 | 出了南郊岔路往南，官道沿著山谷蜿蜒而下，路旁立著「西南往大理」的石樁。 | N→jcw_crossroad、S→zn_river | — | 0.12：m_rabbit 60、m_wolf 40 | — |
| `zn_river` | 終南河邊 | 一條清澈的河從終南山流下來，河邊的卵石被沖得又圓又亮。 | N→zn_road、SW→zn_foot | WATER | 0.15：m_wolf 50、m_boar 50 | — |
| `zn_foot` | 終南山腳 | 終南山層巒疊翠。往東的山路通往全真教和古墓，巡山弟子守在路口，不讓外人上山。 | NE→zn_river、W→zn_teahouse | — | 0.18：m_boar 60、m_wolf 40 | — |
| `zn_teahouse` | 古道茶棚 | 古道邊的竹棚下支著一口大茶壺，過往的客商在這裡喝碗涼茶、換換腳力。 | E→zn_foot、W→ef_jianxue | — | 無（安全） | `n_zn_teaman` 茶棚老闆 |

**`data/maps/emei_foot.json`**（desc：「峨嵋山麓林深路險，常有山賊埋伏劫道。」）

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `ef_jianxue` | 劍穴山洞外 | 山壁上有個形如劍痕的洞穴，洞裡寒氣逼人。洞口木牌寫著：「洞內塌方，暫禁出入。」 | E→zn_teahouse、W→ef_foot | — | 0.20：m_boar 45、m_wolf 45、m_bandit 10 | — |
| `ef_foot` | 峨嵋山腳 | 峨嵋金頂高聳雲端，上山的石階有峨嵋弟子把守，說本派暫不見客。 | E→ef_jianxue、W→ef_forest | — | 0.20：m_boar 45、m_wolf 40、m_bandit 15 | — |
| `ef_forest` | 峨嵋西林 | 林木茂密，日光幾乎透不進來。聽說北邊的樹林是座迷宮，進去的人常常走不出來。 | E→ef_foot、SW→kt_road | WOOD | 0.20：m_wolf 45、m_boar 40、m_bandit 15 | — |

**`data/maps/kongtong_road.json`**（desc：「大理東北的山道，往北岔向崆峒，往西南下山就是大理地界。」）

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `kt_road` | 崆峒道口 | 幾條山路在這裡交會，往北的岔路通往崆峒山，被落石堵住了。往西南下山，就是大理地界。 | NE→ef_forest、W→kt_wood | — | 0.18：m_boar 50、m_wolf 40、m_bandit 10 | — |
| `kt_wood` | 大理東林 | 大理城東邊的一片樹林，林間小徑鋪滿落葉，穿出樹林就能看到陶耘家的稻田。 | E→kt_road、W→dlw_paddy | WOOD | 0.12：m_rabbit 60、m_bigrabbit 40 | — |

`dali_wild.json` 的 `dlw_paddy` 加出口 E→kt_wood。desc 加上「東邊的樹林小徑通往京城方向的官道。」

`jingcheng_wild.json` 的 `jcw_crossroad` 加出口 S→zn_road。desc 改成「……往西是嵩山古道，往東是華山古道，往南的官道通往大理；路牌上往武當的那條路被山崩阻斷，尚未通行。」恆山、雁門關的路改從北路的 `hf_fork` 出去，所以這裡的路牌不再提它們。

南路中段（`ef_jianxue` 到 `kt_road`）是全路最危險的一段，山賊在這四格佔 10–15%，平均每趟約遇 0.1 場（原稿四成，約 0.35 場，對大理出生的新手太險，見 §6）。`q_bandit` 的 KILL 步驟只看怪物 id，所以南路的山賊也算數；蒼山林道仍然是大理附近主要的山賊點，這樣不衝突，任務文字不用改。

### 2.5 西路：西夏 ↔ 大理（M3，現在只寫大綱）

現有資料可以支持的地名：
- 「大理後面的沙漠」與沙漠山洞 (3864,8280)【已證實】，位置在西夏和大理之間的西側。
- 小虎任務寫：「出大理城後往左上方依著河川方向行走」【已證實】。
- 「大理出城往上走、過橋的地方，有河川」【已證實】。

預定路線：`xw_creek` S → 西夏南坡 → 大漠邊緣 → 沙漠山洞外 → 綠洲 → 河川古道 → 過河石橋 → `dlw_lake` NW，約 9 個房間。

M3 再做的原因：
1. M1 兩座出生城已經可以經京城互通。
2. 這條路應該和 M3 的血刀門、星宿、豬哥義送東西等 2001 年事件一起設計。

做好以後，再加西夏 ↔ 大理的長程信件。

### 2.6 新 NPC（npcs.json）

| id | name | kind | room | services | 其他 | src |
|---|---|---|---|---|---|---|
| `n_xe_miner` | 礦工阿火 | STORY | xe_mine | — | talk：「這礦坑上頭就是血刀洞，前陣子塌了，裡頭的東西出不來，我們也進不去。」 | verified（人名）／proposal（台詞） |
| `n_hf_teaman` | 茶棚老闆 | FUNC | hf_teahouse | INN、SHOP | `inn_price` 15；shop：c_mantou、c_water、c_qiyao | proposal |
| `n_zn_teaman` | 茶棚老闆 | FUNC | zn_teahouse | INN、SHOP | 同上 | proposal |

茶棚不放 `STOVE`，客棧才有灶。三位新 NPC 都要有 `talk_<id>` 模板，`night_closed: false`。

---

## 3. 驛站送信改版

### 3.1 規則

- 向城裡驛站的管事接一封信，背包會多一件 `i_letter`（quest_item，不能賣）。
- 自己走到目的地驛站，把信交給管事（DELIVER），領銀兩和名聲。**不必付押金**【後期版】，**沒有時限**【待考證】。
- 每個信件任務同時只能接一次（`quest_accept` 只擋**同一個**任務重複接，`quest_system.gd` 第 77 行）。所以原稿「同一時間只能有一封信」不對：在京城可以同時接 `q_letter_jc_xx` 和 `q_letter_jc_dl`，西夏來的人身上也可能還有一封 `q_letter`。四個任務共用 `i_letter`，DELIVER 只看數量，所以信可以互換，但不會多領獎勵，M1 接受這個行為。如果之後要「一次一封」，就在 `accept` 裡加「已經有進行中的 DELIVER i_letter 任務就擋」，並新增錯誤 `err_letter_in_hand`。
- 死在路上的情形：
  - `STRICT_2001`：背包整個掉進屍體，信也在裡面。回屍體撿得回來；或是放棄任務（`quest_abandon`）再接一封。
  - `STANDARD`、`CASUAL`：信不會掉。
  - 這些都是現有的死亡規則，不必改程式。
- 原作的收信人也可能是門派山腳下的「臨時驛站長」【後期版：懷舊版日記，尚未收進 `verified_research.md`】。M3 開放門派時可以加：例如峨嵋山腳的臨時驛站長，信從大理送過去。M1 不做。

### 3.2 信件路線與獎勵（quests.json）

| id | name | giver | DELIVER 給 | 步數 | money | fame | 備註 |
|---|---|---|---|---|---|---|---|
| `q_letter` | 驛站送信 | n_xx_station | **n_jc_station**（原本是 n_dl_station） | 15 | 80 | 2 | 改目的地 |
| `q_letter_dl` | 驛站送信（大理） | n_dl_station | **n_jc_station**（原本是 n_xx_station） | 17 | 100 | 2 | 改目的地 |
| `q_letter_jc_xx` | 驛站送信（京城往西夏） | n_jc_station | n_xx_station | 15 | 80 | 2 | 新增 |
| `q_letter_jc_dl` | 驛站送信（京城往大理） | n_jc_station | n_dl_station | 17 | 100 | 2 | 新增 |

所有信件任務都是 `repeatable: true`，`give_items: [i_letter ×1]`，`era: "1.0A"`，`src: "verified"`（功能有證據，數值是提案）。

**數值說明**：全部是【設計提案】。原作送信「錢比較少」；懷舊版一封長途信 450 兩，但那是後期物價。現有資料是 30 兩、名聲 +1。以 M1 的物價來看，客棧一晚 20 兩、大兔皮任務 100 兩（只能做一次）。原稿給 120–150 兩，但信件可以重複接，在西夏和京城之間來回跑（xx→jc 接著 jc→xx），每 7–8 分鐘就有 240 兩，再加上路上打怪掉的錢，會變成 M1 最好的賺錢方法，也不符合原作「送信錢比較少」。所以審查後改成北路 80 兩、南路 100 兩（南路比較長，也比較危險），來回一趟約 160 兩。名聲方面，可重複的「婦人」送信任務每次 +5，送信沒有官方數值，取 +2。原作送信也會加「歷練」（婦人任務 +6），但 `rewards` 目前沒有 `lili` 欄位。要加的話，得在 quest_system、data_lint 和 M1_PLAN 3.11 一起加欄位，建議 M3 再做。

### 3.3 任務文字（直接指路，不再提搭車）

- **q_letter**：「西夏驛站管事託你把一封信送到京城驛站。驛站不備車馬，信要親自送到。出西夏東門，在官道往東北走，經過礦區、黑龍潭和恆山腳下的茶棚，一路往東就到京城西門。驛站在大街西側。」
  - 步驟：「把信函交給京城驛站管事」
- **q_letter_dl**：「大理驛站管事託你把一封信送到京城驛站。出大理北門往東，穿過陶耘稻田和大理東林，經崆峒道口、峨嵋山腳、終南古道一路往東北，走到京城南郊岔路再往北進城。峨嵋山腳一帶偶有山賊，帶夠金創藥；路上兩座茶棚可以歇腳。」
  - 步驟：「把信函交給京城驛站管事」
- **q_letter_jc_xx**：「京城驛站管事託你把一封信送到西夏驛站。出京城西門往西，沿恆山腳下的官道經過茶棚和黑龍潭，往西南走就到西夏東門。驛站在廣場南邊。」
  - 步驟：「把信函交給西夏驛站管事」
- **q_letter_jc_dl**：「京城驛站管事託你把一封信送到大理驛站。出京城南門到南郊岔路，往南走官道，經終南山腳、峨嵋山腳和崆峒道口，再往西穿過大理東林，就到大理北門外。峨嵋山腳一帶偶有山賊。驛站在五華樓前廣場的西邊。」
  - 步驟：「把信函交給大理驛站管事」

### 3.4 驛站房間與台詞（去掉「搭車」）

| key | 新文字 |
|---|---|
| `xx_station.desc` | 驛站裡堆著一捆捆待送的信件，管事拿著名冊點收。牆上貼著告示：「代送書信，酬銀從優。」 |
| `jc_station.desc` | 京城驛站人來人往，各地送來的信函堆滿了櫃台。管事忙著登記收發。 |
| `dl_station.desc` | 驛站裡拴著幾匹滇馬，是官府傳遞公文用的。管事正在清點要送往各地的信件。 |
| `talk_n_xx_station` | {npc_name}翻著名冊：「驛站的馬只送官文，不載客。客官要是肯走一趟京城幫忙捎封信，酬勞少不了。」 |
| `talk_n_jc_station` | {npc_name}打著官腔：「往西夏、往大理的信都有，各位自己走過去，路上小心山賊。」 |
| `talk_n_dl_station` | {npc_name}一邊點信一邊說：「這兒有封信要送去京城。路遠，中段又有山賊，你肯不肯跑一趟？」 |
| `talk_n_jc_guard` | {npc_name}喝道：「南門外往嵩山、華山、大理的路都通。往恆山、雁門關的話，從西門出去，到岔路口官兵就不放行了。」 |
| `talk_n_dl_guard` | {npc_name}和氣地說：「北門外往蒼山的林道有山賊，再往北的鬼王洞更去不得。要上京城，從稻田往東走。」 |
| 新錯誤 `err_stagecoach_disabled`（伺服器回 `fail("stagecoach_disabled")`，`text_renderer.gd` 會自動加上 `err_` 前綴） | 驛站的馬只送官文，不載客。要去哪裡，得自己走路。 |

事件模板 `travel`（`Protocol.E_TRAVEL`，「你付了 {cost} 兩，搭上驛站的馬車……」）保留，打開馬車選項時還會用到。

---

## 4. 要改的程式、資料、測試和文件

### 4.1 伺服器選項與馬車開關

| 檔案 | 改動 |
|---|---|
| `data/server_options.default.json` | 加 `"stagecoach_enabled": false` |
| `core/data/data_schema.gd` | 如果 `server_options` 有型別強制轉換清單，就加上這個布林欄位 |
| `autoload/world_server.gd` | 比照 `--rule-preset` 加 CLI `--stagecoach`：只在**新建**世界時把 `options.stagecoach_enabled` 設成 true。舊存檔沒有這個 key，一律讀成 false（用 `options.get(..., false)`） |
| `server/npc_system.gd` `travel()` | 開頭加上：`if not bool(host.options.get("stagecoach_enabled", false)): return GameHost.fail("stagecoach_disabled")` |
| `server/npc_system.gd` `menu()` | 選項關閉時 `routes: []`，`services` 去掉 `"TRAVEL"`。這樣 NPC 對話框就不會出現「驛站」按鈕，`npc_dialog.gd` 本身不用改 |
| `server/game_host.gd` 的 `npc_check` | 不用改，`travel()` 自己先擋掉 |
| `data/text_templates.json` | 加錯誤 key `err_stagecoach_disabled`；更新 §3.4 列出的台詞；新增 3 位 NPC 的 talk |
| `tools/data_lint.gd` | 把 `err_stagecoach_disabled` 加進 `REQUIRED_TEMPLATE_KEYS`（第 245 行起，`err_no_route` 在第 274 行，加在它旁邊） |

### 4.2 資料

| 檔案 | 改動 |
|---|---|
| `data/regions.json` | 新增 5 列（§2.2）；`dali_wild.world_pos` 可選擇改成 [16,44] |
| `data/maps/xixia_east.json`、`hengshan_foot.json`、`zhongnan_road.json`、`emei_foot.json`、`kongtong_road.json` | 新檔（§2.3、§2.4） |
| `data/maps/xixia_wild.json` | `xw_road` 加 NE→xe_road；desc 加「東北方有條官道通往京城」 |
| `data/maps/xixia.json` | 改 `xx_station.desc` |
| `data/maps/jingcheng.json` | 新增 `jc_gate_w`；`jc_street` 加 NW→jc_gate_w 並改 desc；改 `jc_station.desc`；`jc_gate_s.desc` 加上「往南可下大理」；**地區 desc**（「眼下只有驛站、客棧與南門一帶有人往來」）加上西門 |
| `data/maps/jingcheng_wild.json` | `jcw_crossroad` 加 S→zn_road，改 desc |
| `data/maps/dali_wild.json` | `dlw_paddy` 加 E→kt_wood，改 desc |
| `data/maps/dali.json` | 改 `dl_station.desc` |
| `data/npcs.json` | 三個驛站管事的 `services` 保留 `"TRAVEL"`，`travel` 路線也保留（只在選項開啟時有效），價格改成西夏↔京城 100、京城↔大理 100、西夏↔大理 150【設計提案・非原作】。`n_jc_station` 加 `"QUEST"` 和 `quests: ["q_letter_jc_xx", "q_letter_jc_dl"]`。新增 `n_xe_miner`、`n_hf_teaman`、`n_zn_teaman`（`region` 欄分別填 `xixia_east`、`hengshan_foot`、`zhongnan_road`） |
| `data/quests.json` | `q_letter`、`q_letter_dl` 改目的地和文字；新增 `q_letter_jc_xx`、`q_letter_jc_dl`（§3.2、§3.3） |
| `data/items.json` | `i_letter.desc` 改成「封了火漆的信函，要親手送到收信的驛站。」 |

**舊存檔**：如果角色身上正有一封 `q_letter`（原本送大理）或 `q_letter_dl`（原本送西夏），改版後收信地點都會變成京城。任務 id 沒變，信也還在，所以不需要轉換資料，在更新說明裡提一句就好。已經存在的世界存檔裡沒有 `stagecoach_enabled`，讀成 false，所以舊世界更新後也會變成只能走路。

### 4.3 data_lint（`tools/data_lint.gd`）

1. `room_graph(view, include_travel := false)`：預設**只算步行出口**。`reachable_rooms`、`find_path`、`_c_reachability` 都改用純步行圖，也就是「從 `xx_square` 走路到得了每一個房間」。驛站路線只拿來檢查 `to_room` 是否存在（第 573–582 行已經有這項檢查）。
2. 新檢查：每一座 `type == "CITY"` 的城，彼此之間都要走得到（從各自的 `birth_room` 或第一個房間開始 BFS）。
3. 新檢查（warning）：兩城城門之間的最短步數超過 16 時提醒。
4. 新檢查：每個 DELIVER 任務的目標 NPC 所在房間，從任務給予者的房間走路要到得了。
5. `_check_server_options`：檢查 `stagecoach_enabled` 有的話必須是布林值。
6. `check_world_pos`：沿用，新座標不重複。

### 4.4 江湖全圖與 BGM

| 檔案 | 改動 |
|---|---|
| `ui/game/map/map_data.gd` `world_model(tables, show_travel := false)` | 選項關閉時不輸出 `travel` 虛線，只畫步行實線。新的步行連線會自動出現：xixia_wild–xixia_east、xixia_east–hengshan_foot、hengshan_foot–jingcheng、jingcheng_wild–zhongnan_road、zhongnan_road–emei_foot、emei_foot–kongtong_road、kongtong_road–dali_wild |
| 呼叫端（目前只有 `map_panel.gd` 第 141 行呼叫 `world_model`；`world_map_view.gd` 只負責畫） | `show_travel` 從伺服器傳給客戶端的選項讀取。客戶端目前**拿不到** server options，建議在進世界的 view/welcome 加一個 `stagecoach` 欄位。如果不想動協定，就固定傳 `false` |
| `world_map_view.gd` 第 3 行註解和圖例 | 改成「虛線＝驛站馬車（伺服器選項）」 |
| BGM | 不用改。新地區的 `type` 都是 `WILD`，依 BGM_PLAN §4 的規則會自動播 `wild`（田野風光）。茶棚房間也是一樣，因為曲目是照地區切換，不是照房間 |

### 4.5 驗收 bot（`tests/bots/m1_playthrough_bot.gd`）

這個 bot 已經有 Dijkstra 尋路（`_graph`、`_path`、`_goto`）。`_goto` 一路上會打遇到的怪，氣低於一半時回客棧或原地調息，戰鬥中氣低會逃跑，死掉重生後也會重新規劃路線。所以改動很少：

| 位置 | 改動 |
|---|---|
| `_graph()` | 拿掉驛站邊。如果想保留，就只在 `GameData.default_server_options().get("stagecoach_enabled")` 為 true 時加。路線只會走步行出口 |
| `_s10` | 改名 "walk to jingcheng (letter)"。先到 `xx_station` 執行 `quest_accept n_xx_station q_letter`，再 `_goto("jc_station")`，然後 `quest_turn_in n_jc_station q_letter`。檢查：所在房間是 `jc_station`；交付回報的 `reward.money` 是 80（不要比對身上銀兩：路上打怪會掉錢，`_goto` 也可能在茶棚花 15 兩住宿，所以餘額可多可少）；名聲 +2；`HUB_NPCS` 檢查維持不變 |
| `_s11` | 不用改。從 `jc_station` 走 E、S、S、W、W 到少林的固定路線還在 |
| `_s18` | 改名 "walk to dali (letter)"。到 `jc_station` 接 `q_letter_jc_dl`，`_goto("dl_station")`，交信，檢查所在房間是 `dl_station`、`reward.money` 是 100、名聲 +2 |
| `_nearest_inn()` | 確認會把 `n_hf_teaman`、`n_zn_teaman`（有 INN 服務）當成客棧；如果它是用 services 找的，就不用改。要注意 bot 的 `INN_RESERVE`：bot 剛出遠門時錢不多，住茶棚要留得出 15 兩 |
| 檔頭的執行指令 | 走路會增加約 30 步和幾場戰鬥。在 `--time-scale=50` 下大約多 1–2 分鐘，建議 `--quit-after` 從 900 調到 1200 |
| 新增一個負向檢查 | 在 `_s10` 接信後送 `travel n_xx_station jc_station`，預期失敗 `stagecoach_disabled` |

### 4.6 介面驗收（`tests/ui/ui_playthrough.gd`）

介面測試用的角色只打過一場兔子，走 11 步的北路很容易被野狼、山豬打死，讓測試時好時壞。建議：

- **方案 A（推薦）**：讓 UI 測試的世界用 `--stagecoach` 新建（`--world=ui_play` 每次都新建）。`_letter_quest` 照舊測馬車 UI：接信、進行中沒有交付鈕、`_ride` 到「京」（目的地從大理改成京城）、大地圖頁尾重設、在「京城驛站管事」交付、交付後清單即時更新，最後 `_ride` 回西夏。
  - 要改：`_ride(dlg, "京城")` 兩處，`_talk("京城驛站管事")`，檔頭第 13 行的流程說明，以及執行指令加 `--stagecoach`。
  - 再加一段步行檢查：從西夏東門走 NE 到 `xe_road`，確認換了區域以後大地圖頁尾會重設，然後走回來。這段只有野兔、大野兔，安全。
- **方案 B**：UI 測試完全不坐車。接信以後走到 `xe_road` 再回來，然後放棄任務。缺點是「交付後清單即時更新」這項 UI 回歸檢查就沒有地方測了，所以不推薦。

另外加一個單元測試，確認**預設選項下**驛站管事的對話框沒有「驛站」按鈕（見 4.7 的 `test_ui_scenes`）。

### 4.7 單元測試

| 檔案 | 改動 |
|---|---|
| `tests/unit/test_data_content.gd` | `room count` 46 改成 **66**（+19 野外、+1 `jc_gate_w`）；`test_every_room_reachable_from_xx_square` 改成純步行；`test_path_from_xx_square_to_gw_throne_uses_station` 改名 `..._walks_via_jingcheng`，斷言路徑經過 `jc_gate_w` 和 `jcw_crossroad`，**不經過**任何驛站；`test_rooms_match_plan_regions` 加 5 個新地區和 `jc_gate_w`；`test_room_features_and_locks` 加新的 FIELD／WOOD／WATER 房間，並確認兩座茶棚沒有遇敵；`test_encounter_tables_match_plan` 加「北路沒有 m_bandit」「北路茶棚以西沒有 m_boar」「`zn_road`、`zn_foot`、`kt_wood` 沒有 m_bandit」「每格 m_bandit 權重 ≤ 15」；第 409–413 行的信件斷言改成新目的地（兩封都送 `n_jc_station`）、`fame` 1 改 2；`test_all_m1_npcs_exist_with_services` 把 `n_jc_station` 改成 `["TRAVEL","QUEST"]` 並加新 NPC；第 206–208 行改成新價格；`test_quests_table` 加兩封新信；`test_regions_table` 9 改成 **14**；`test_lint_detects_unreachable_room` 改成拿掉 `dlw_paddy` 往東的出口時，lint 要報出 `dl_*` 和 `gw_*` 不可達；新增「城門到城門步數介於 8 和 14 之間」 |
| `tests/unit/test_world_move.gd` | `test_travel_by_station`：先把 fixture 的 `host.options.stagecoach_enabled` 設成 true 再跑原本的斷言，金額改新價；新增 `test_travel_disabled_by_default`，預期 `stagecoach_disabled`、位置和銀兩都不變；新增 `test_walk_xixia_to_jingcheng`：用 fixture 一步步 `move`，關掉遇敵或給角色守護者之煙，走到 `jc_gate_w`。第 126 行有用到 travel，一樣先開選項，或改成 fixture 的 `goto(room)` |
| `tests/unit/test_world_quest.gd` | 第 66、82 行的 `travel` 改成 fixture 的 `goto(room)`（`test_world_fixture.gd:139`，內部呼叫 `regions.teleport`；fixture 沒有叫 `teleport` 的方法），目的地依新路線改：`q_letter` 送到 `jc_station`；`q_letter_dl` 送到 `jc_station`；第 72 行的任務狀態斷言改成在 `n_jc_station` 看到 `q_letter` READY、`q_letter_jc_xx`／`q_letter_jc_dl` AVAILABLE；第 75、77 行的交付對象和名聲 +1 改成 `n_jc_station`、+2；加測兩封京城的信；加測在京城同時接兩封信、各自交付（見 §3.1） |
| `tests/unit/test_ui_map_layout.gd` 第 184–186 行 | 預設選項下 `travel` 為空；`walk` 包含 §4.4 列出的 7 對連線 |
| `tests/unit/test_ui_map_panel.gd` 第 236 行 | 「travel routes exist」改成在 `show_travel = true` 時才檢查 |
| `tests/unit/test_ui_host_flows.gd` 第 96 行 | 開選項，或改成直接呼叫 `regions.teleport` |
| `tests/unit/test_ui_scenes.gd` | `SERVICE_LABELS["TRAVEL"]` 仍然是「驛站」；新增：`menu()` 在選項關閉時 `services` 不含 TRAVEL |
| `tests/unit/test_protocol_m1.gd` | 不用改，`travel` intent 還在 |

### 4.8 文件

| 文件 | 改動 |
|---|---|
| `docs/GDD.md` §0.1 第 2 項 | 京城「只作為驛站樞紐」改成「京城提前開放；西夏、大理、京城之間用野外官道相連，原作就是走路」 |
| `docs/GDD.md` §1（第 148、164 行）、§2（第 250 行） | 拿掉「經驛站到京城」「驛站樞紐」的說法 |
| `docs/GDD.md` §7.1 | 重寫「1.0-A 的地理斷層」那一段：本作做法改成北路、南路兩條步行官道（本文 §2），西路排在 M3；馬車改成 `stagecoach_enabled`【設計提案・非原作】，預設關閉；加上大地圖座標表（本文開頭引用的 17173 座標） |
| `docs/GDD.md` §7.2 | 加 5 個新地區列，`kongtong_road` 改成實作中；備註「鬼王」：2002 年的資料寫鬼王在血刀洞迷宮裡（靠近西夏），和本作把鬼王洞放在大理不同，記為【待考證／設計提案】 |
| `docs/GDD.md` §8.2 | `q_letter` 那一列改成新路線，加上兩封京城信 |
| `docs/GDD.md` §13 M1 | 驗收句「經驛站到京城」改成「走官道到京城並完成一次驛站送信」 |
| `docs/M1_PLAN.md` | 第 5 行的擁有者預設；S8 的 BFS 改成純步行；**S9 改成「城際步行官道（北路、南路）＋馬車選項（預設關閉）」**；S19 的送信改成步行；3.x 的 travel intent 列（第 644 行）加 `stagecoach_disabled`；第 710 行的事件模板註明只在選項開啟時出現；第 1031 行的 NPC 範例；第 1067 行的 BFS 說明；第 1325 行的價格表；5.1 世界表加新地區和房間（第 1339–1345 行附近）；第 1361、1370、1384 行的 NPC 列；第 1512–1517 行的任務列；6.x 測試表（第 1527、1545 行）；6.4 bot 劇本第 10、18 步（第 1624、1632 行）；第 1652 行的手動檢查清單「驛站旅行」改成「步行送信到京城」 |
| `docs/TECH_ARCH.md` | 如果有提到 travel 的段落，加註它受選項控制 |
| `docs/BGM_PLAN.md` 第 85 行 | WILD 範例加上新地區名稱（可選） |
| `docs/research/verified_research.md` | 把本輪地理調查（17173 gaoshou/17 座標表、2002 山洞清單裡的血刀洞迷宮／黑龍潭／阿火／劍穴、懷舊版送信日記）補進去，各自標年代。現在本文標【已證實】的地名有一半只出現在這份提案裡，研究檔裡查不到 |

### 4.9 建議的施工順序

1. 資料：地圖、地區、NPC、任務、模板。改完跑 `data_lint`，這時 lint 還算驛站邊，應該會過。
2. lint 改成純步行（4.3），並更新 `test_data_content`。
3. 伺服器選項、`travel()` 和 `menu()` 的開關，加上 `test_world_move`、`test_world_quest`。
4. 江湖全圖的 `show_travel` 和地圖相關測試。
5. 驗收 bot 和 UI 測試（4.5、4.6）。
6. GDD 和 M1_PLAN 的文件更新。

---

## 5. 附註：沒有解決的地理不一致（不在這次範圍）

- 原作座標裡華山 (17404) 在少林 (23214) 的**西邊**，本作的京城南郊是少林在西、華山在東。暫時不改，M3 開完整京城時再一起重排。
- 鬼王的位置見 §4.8 的 GDD §7.2 那一列。
- 2001 年的座標表裡沒有京城。京城放在東北、靠近少林和武當，是依據後期的「京城外」分區推出來的【後期版】。

---

## 6. Review notes（審查紀錄，2026-10-18）

審查時讀了本文、`verified_research.md`、`data/maps/*.json`、`regions.json`、`npcs.json`、`quests.json`、`monsters.json`、`text_templates.json`，以及本文引用的程式和測試。也重新抓了 17173 gaoshou/17、xinshou/13、xinshou/19、yinan/11 四頁。jyhj（懷舊版）的頁面連不上，沒有重新核對。上面各節已經照下列結論直接改過。

### 6.1 考據（原稿把推測寫成原作的地方）

1. **京城不是 2001 開服就有。** `verified_research.md` 寫京城是 2001-09-28「神鵰大俠」才加的第三座城。北路和南路都是本作的路，開服時真正的城際步行路線是西夏 ↔ 大理（西路）。§1 第 6 項已改。西路仍然排在 M3，但它其實是**最接近原作**的一條，建議擁有者考慮提前。
2. **「2001 年沒有馬車」是推定。** 只能說查不到反證。「馬車是 2018 至尊服才有」研究檔裡沒有，也查不到出處，改標【待考證】。
3. **「死亡／下線回記錄點是唯一捷徑」**：yinan/11 只證實會回記錄點，沒有說是「唯一」，改標【推定】。
4. **送信流程、不收押金、臨時驛站長**都出自懷舊版（2008）日記，改標【後期版】，不再寫【已證實】。
5. **ctrl+M 引文**：xinshou/19 原文是在講走去門派（「先問一些人要進入的門派在那，再慢慢前進」）。原稿用「……」把兩句接起來，讀起來像在講城際移動。已補上原文。
6. **地名來源**：血刀洞迷宮、黑龍潭、礦工阿火、劍穴、恆山外稻田等，研究檔裡都沒有，只出現在本文。17173 gaoshou/17 的「血刀門」在 (477,12471) 西南，跟西夏東北的「血刀洞迷宮」(8626,2228) 是兩個地方，原稿沒有區分。已加註，並把「補進研究檔」列進 §4.8。「少林山腳、衡山有小茶店」查無出處，改標【待考證】。
7. **核對過的座標**（gaoshou/17）：西夏 (7296,2966)、大理 (5903,18617)、恆山 (15243,6043)、華山 (17404,7820)、少林 (23214,7004)、終南山 (17407,10987)、峨嵋山 (13902,13772)。北路沿恆山往東、南路從終南經峨嵋往西南到大理，方位上說得通。

### 6.2 可玩性

1. **大理出生的新手一定要走南路（嚴重）。** M1 只有少林、華山兩派，都在京城南郊，所以大理出生的角色要入門派，只能走南路。原稿假設「南路給練過的角色走」，在峨嵋一段放了山賊（combat_xp_ref 3000、氣 600、用刀），佔三到四成，平均每趟約遇 0.35 場。0–500 實戰的新手遇上幾乎必死，`STRICT_2001` 下還會掉光背包。修正：山賊只放在 `ef_jianxue`–`kt_road`，權重 10–15%，平均每趟約 0.1 場；`zn_foot` 和 `kt_wood` 拿掉山賊。`suggested_xp` 一起調低。
2. **北路山豬太多。** 原稿茶棚以西的 `xe_river` 就有山豬（900）50%，一趟平均遇到 0.34 場山豬，而走這條路的新手只有 0–500 實戰。修正：茶棚以西最強只到野狼（500）；山豬只在 `hf_paddy`（20%）、`hf_shore`（50%），平均每趟約 0.12 場。`xe_river` 的 desc 改成野狼。`xe_xuedao` 這條死路原本會一次出兩隻狼，改成一隻。
3. **`suggested_xp` 會顯示在大地圖上**（`map_data.gd` 第 159 行）。原稿北路寫 [200,3000]／[500,5000]，會叫新手別去他們必須走的路。已全部調低。
4. **步數**：重新算過。北路城門到城門 11 步、南路 13 步，驛站到驛站分別是 15、17 步，西夏到大理經京城 30 步。都正確。
5. **出口互通**：每個新出口都有反向出口（`xw_road` NE↔`xe_road` SW、`zn_river` SW↔`zn_foot` NE、`ef_forest` SW↔`kt_road` NE、`jc_street` NW↔`jc_gate_w` SE，其餘是 E/W）。死路只有刻意設計的 `xe_xuedao`。
6. **id 衝突**：新房間、地區、NPC、任務的 id 都沒有和現有資料重複。不過 `em_` 前綴之後會撞上 M3 的峨嵋派房間（照 `sl_`／`hs_` 的命名慣例），所以峨嵋山麓的三個房間改名為 `ef_jianxue`、`ef_foot`、`ef_forest`。
7. **送信獎勵**：原稿 120–150 兩、可以重複接、不收押金，西夏和京城之間來回送信會變成 M1 最好的賺錢方法。現有值是 30 兩、名聲 +1。改成 80／100 兩。名聲 +2 不變。
8. **「同一時間只有一封信」不成立**：`quest_active` 只擋同一個任務重複接，在京城可以同時接兩封信。行為無害，已在 §3.1 說明，並寫了要限制時怎麼加。

### 6.3 改動清單的缺漏（已補進 §4）

- 錯誤 key 應該是 `err_stagecoach_disabled`（`text_renderer.gd` 第 70 行會加上 `err_` 前綴），lint 清單在 `data_lint.gd` 第 245 行起。
- 事件模板的 key 是 `travel`，不是 `E_TRAVEL`（`E_TRAVEL` 是 Protocol 常數）。
- 測試 fixture 沒有 `teleport(room)`，要用 `goto(room)`（`test_world_fixture.gd:139`）。
- `world_model` 只有 `map_panel.gd` 一個呼叫端。
- 漏列的項目：`test_data_content.gd` 第 409–413 行的信件斷言；`test_world_quest.gd` 第 72–77 行的狀態和名聲斷言；`jingcheng.json` 的地區 desc；新 NPC 的 `region` 欄；`q_letter_dl` 的舊存檔說明；舊世界讀不到選項時會變成只能走路；bot 不能用餘額驗收送信獎勵（茶棚住宿和打怪掉錢都會讓餘額變動），要看 `reward.money`。
- `verified_research.md` 要補上本輪的地理資料。

### 6.4 還要擁有者決定的事

- 西路（西夏 ↔ 大理，原作開服就有的路線）要不要從 M3 提前到 M1 末。
- 新手在南路仍然有約一成機率遇到山賊。要不要再加保護，例如 `newbie_pk_protect_xp` 那樣，500 實戰以下不會遇到 EVIL_NPC？目前不加，因為原作的送信日記就寫「途中遇到許許多多的盜賊」。
- 送信獎勵 80／100 兩、名聲 +2 仍然是提案數值。
