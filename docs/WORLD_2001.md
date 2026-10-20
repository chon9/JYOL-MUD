# 2001 開服世界契約（WORLD_2001）

> 狀態：**契約（binding）**。擁有者已拍板，build agent 照本文施工；有衝突時以本文為準。
> 取代：`docs/WORLD_ROUTES.md` 的**地理部分**（京城樞紐、北路、南路、`xe_*`/`hf_*` 接京城的走法）。
> WORLD_ROUTES 裡的研究依據、房間文字、遇敵平衡原則、送信改版、馬車開關與審查紀錄照樣沿用，本文有引用的地方直接寫明。
> 範圍：1.0A 的世界（`enabled_eras: ["1.0A"]`）。京城留著資料，改成 1.0B 才出現（§6）。
> **M3b 更新（2026-10-20）**：新世界預設改開 `["1.0A","1.0B"]`（M3B_PLAN O1／E1），京城 1.0B 可出生（O3／E2）；本文件 §6.1「維持 `["1.0A"]`」與 §6.3「不能出生」作廢，其餘地理仍有效。
> 標記：【已證實】有原始資料；【後期版】資料來自 2001 年以後的版本；【設計提案】本作自訂；【設計提案・非原作】原作沒有的便利功能；【待考證】查不到資料。
> 文字一律用繁體中文；id 用英文。

---

## 0. 擁有者決定（不可更動）

| # | 決定 | 本文怎麼落實 |
|---|---|---|
| D1 | 世界照**原作 2001 地理**：一整片連續的野外，城市之間**走路**，路上踩地雷遇敵。1.0 只有**西夏**（西北）、**大理**（西南）兩座城。 | §1 地圖、§2 地區、§3 房間。城際只有一條路：**西路** 西夏 ↔ 大理。 |
| D2 | 京城是 1.0B（神鵰大俠）才有的內容：資料保留，但用 era 擋住，預設世界**沒有京城**。 | §6 |
| D3 | 山門照原作座標擺（17173 gaoshou/17，見 §1.1）。 | §1、§2 的 `world_pos` |
| D4 | 鬼王在**血刀洞迷宮**裡（8626,2228，西夏東北），不在大理附近。 | `guiwang` 地區搬到西夏東郊，入口 `xe_xuedao` |
| D5 | 驛站的工作**只有送信**：拿信自己走到目的地驛站。馬車留在程式裡，由伺服器選項 `stagecoach_enabled` 控制，**預設 false**，標【設計提案・非原作】。 | §5、§8 |
| D6 | 介面照 `docs/AUTHENTIC_UI_SPEC.md`。 | §9.2 WP-UI 清單 |
| D7 | 保留擁有者畫的戰鬥背景與人物圖，不准把戰鬥改成黑底。 | 新地區一律用 `data/art.json` 的 `alias` 指到現有的畫（§9.1） |

---

## 1. 世界地圖

### 1.1 座標換算

原作座標（17173 gaoshou/17，x 往東、y 往南）一律**除以 24 四捨五入**，換成大地圖 0–1000 的 `world_pos`。這樣最東邊的少林 23214 → 967，最南邊的大理 18617 → 776，兩軸用同一個比例，不會變形。

| 地點 | 原作座標 | `world_pos` | 1.0A 有沒有做 |
|---|---|---|---|
| 西夏 | 7296, 2966 | [304, 124] | 有（CITY） |
| 大理 | 5903, 18617 | [246, 776] | 有（CITY） |
| 血刀洞迷宮（鬼王）| 8626, 2228 | [359, 93] | 有（DUNGEON，id 沿用 `guiwang`） |
| 沙漠山洞 | 3864, 8280 | [161, 345] | 有（`desert_edge` 地區就擺在這裡；洞本身封著） |
| 恆山 | 15243, 6043 | [635, 252] | 山門封閉（岔路 `hf_fork`） |
| 華山 | 17404, 7820 | [725, 326] | 有（SECT） |
| 少林 | 23214, 7004 | [967, 292] | 有（SECT） |
| 武當 | 20094, 9406 | [837, 392] | 山門封閉（岔路 `sy_wdfork`） |
| 終南山 | 17407, 10987 | [725, 458] | 封閉（文字提到；大理那頭的岔路 `dlw_fork`） |
| 峨嵋 | 13902, 13772 | [579, 574] | 封閉（岔路 `dlw_fork`） |
| 衡山 | 22640, 16268 | [943, 678] | M1 不碰 |
| 星宿海 | 3408, 4608 | [142, 192] | 封閉（沙丘 `ws_dunes` 的文字提到） |
| 血刀門 | 477, 12471 | [20, 520] | 封閉（`de_cave` 的文字提到）。注意它和血刀洞迷宮是兩個地方 |
| 雁門關 | 20078, 2310（gaoshou/23 靈芝商人） | [837, 96] | 封閉（岔路 `hf_fork`） |

其他參考點（gaoshou/23）：陳家洛在西夏城外 (6397,3527)；范遙在「西夏上方山坡」(7423,1323)；桃花島銅屍、鐵屍在「西夏上方雪地」(13516,2926)；令狐沖在「華山與武當之間的水池」(17461,8715)；程靈素在「少林山腳」(24486,10206)。這些拿來寫房間文字，M1 不放這些 NPC。

> 審查備註（第 3 輪）：這幾個參考點只借來寫房間文字，房間位置**沒有**照座標擺，屬【推測／借用】：程靈素的「少林山腳」(24486,10206 → [1020,425]) 在少林山門東南，但 `sy_foot`（少室山腳）在山門西邊的嵩山古道上；陳家洛 (6397,3527 → [267,147]) 在西夏西南城外，但 `n_chenjialuo` 站在東門外官道 `xw_road`；銅屍鐵屍的雪地 (13516,2926 → [563,122]) 在很東邊，但借用它的 `xn_snow` 在 [318,62]。M1 不放這些 NPC，所以先當文件註記；之後要放 NPC 時再依座標加房間。

### 1.2 總覽（地區層級，北在上）

```
 x→   0          200          400          600          800         1000
 y↓ ┌───────────────────────────────────────────────────────────────────┐
  50│               西夏北郊 xixia_north                       ┌1.0B──────┐ │
    │                  ┆      ◆血刀洞迷宮 guiwang（鬼王）      │■京城     │ │
 100│               ●西夏 ─ 西夏郊外 ─ 西夏東郊 xixia_east     │ jingcheng│ │
    │   ✕星宿海       ┆                     ╲               │京城南郊  │ │
 200│               西夏南坡 xixia_south     恆山山麓 hengshan_foot ┄✕恆山 ┄✕雁門關
    │                  ┆                        ╲            └─┆────┆──┘ │
 300│               大漠邊緣 desert_edge        華陰道 ─ ▲華山 ─ 嵩山古道 ─ ▲少林
    │              （沙漠山洞，封）              huayin_road     songshan_road │
 400│                  ┆                         ✕終南        ✕武當          │
    │                  ┆                                                    │
 500│ ✕血刀門        河川古道 river_road                                     │
    │                  ┆                     ✕峨嵋                          │
 600│                  ┆                                                    │
    │                  ┆                                                    │
 700│               大理郊外 dali_wild ┄┄（崆峒道口：往崆峒、峨嵋、終南，封）   ✕衡山│
    │               ●大理                                                  │
 800└───────────────────────────────────────────────────────────────────┘
   ● 城（CITY）  ▲ 門派（SECT）  ◆ 洞窟（DUNGEON）  ✕ 1.0A 不開放  ┄ 封閉岔路
```

### 1.3 房間層級路線圖

**西夏一帶**（城、郊外、北郊、東郊、血刀洞迷宮）

```
                     xn_snow ──E── xe_xuedao ══IN══ gw_entrance ─N─ gw_hall ─N─ gw_maze ─N─ gw_throne（鬼王）
                       │S             │S
                     xn_slope         │
                       │S             │
  xx_inn_2f          xw_wood       xe_mine ──E── xe_heilong ──E── xe_river ──SE──▶ 東路（恆山山麓 hf_paddy）
     │U/D              │S          ╱W
  xx_inn             ╱          xe_road
     │S             ╱       NE ╱
xx_street ─W─ xx_square ─E─ xx_gate_e ─E─ xw_road ─E─ xw_grass ─E─ xw_hill（狼嚎丘，死路）
 │ │ │            │S                                  │S
 藥鋪 兵器鋪 武館   xx_station                          xw_creek
                                                     │S
                                                     ▼ 西路（西夏南坡 ws_slope）
```

（`xw_wood` 在 `xw_grass` 北邊，上圖為了排版畫在左上；方向以 §3 的出口表為準。）

**東路**：西夏東門 → 華山山門 12 步、華山山門 → 少林山門 8 步

```
xw_road ─NE─ xe_road ─E─ xe_mine ─E─ xe_heilong ─E─ xe_river ─SE─ hf_paddy ─E─ hf_teahouse ─E─ hf_shore ─E─ hf_fork ┄北┄ ✕恆山、雁門關
                                                                       （茶棚，安全）                          │SE
                                                                                                         hy_road
                                     1.0B：jcw_huashan ┄SW┄┐                                               │E
                                                     hs_gate（華山）                                          │
                                                        │N/S                                               │
                                     hy_pond ─W──── hy_foot ◀────────────────────────────────────────────────┘
                                        │E
                                     sy_road ─E─ sy_wdfork ─E─ sy_teahouse ─E─ sy_pines ─E─ sy_foot ─E─ sl_gate（少林）
                                                 ┆南：✕武當   （茶棚，安全）      ┆N（1.0B：jcw_songshan）
```

**西路**：西夏東門 → 大理北門 16 步（開服時唯一的城際路線）

```
xw_grass ─S─ xw_creek ─S─ ws_slope ─SW─ ws_ford ─S─ ws_dunes ─S─ de_edge ─S─ de_cave ─SE─ de_oasis ─SE─ rr_upper
                                                   ┆西：✕星宿海            ┆西：✕血刀門  （綠洲，安全）      │S
                                                                                                     rr_road
                                                                                                       │SE
 dlw_forest ─W── dlw_river ─NW──────────────────────────────── rr_bridge ─N─ rr_bend ◀──────────────────┘
（蒼山林道）       │S
 dlw_lake ─W── dlw_road ─E─ dlw_paddy ─E─ dlw_eastwood ─E─ dlw_fork ┄✕崆峒、峨嵋、終南
（洱海岸）          │S         （陶耘）
                dl_gate_n ─S─ dl_square（大理城）
```

### 1.4 步數與遇敵預算

一次 `move` 算一步。下表的數字是用本文 §3 的出口與遇敵表實際算出來的（路徑上不含起點與終點房間；遇敵期望值 = Σ 房間 `rate` × 該怪權重比例）。「難纏」指 `m_wolf`、`m_boar`、`m_bandit`：balance_sim 的 P0（新角色）打野狼、山豬的勝率都不到一成（`tools/balance_sim.gd` 的 `newbie_vs_wolf`、`newbie_vs_boar`），只能逃。

> 審查修正（第 2 輪）：原本的預算是 0.35，而且把大野兔當成好打的怪；實際上 P0 打大野兔只有 78% 勝、打完剩兩成氣，它又是送信路上最常見的怪，加上逃跑不一定成功，整合 log 裡新角色常死在西夏南坡／大漠邊緣。現在：大野兔下修（氣 150→110、臂力 13→12，P0 勝率 99.8%、打完剩約四成氣）；溪口、沙丘、河灣、華山水池拿掉野狼改放野兔，其他路段的野狼、山豬比重降低；難纏怪預算降到 **0.15**；balance_sim 加了「P0 走完全程」的案例（`p0_walk_*`，見下方規則 7）。

| 路段 | 步數 | 遇敵期望（場） | 難纏 | 其中山豬 | 其中山賊 |
|---|---|---|---|---|---|
| 西夏東門 → 大理北門（西路） | 16 | 1.68 | 0.18 | 0.06 | 0.024 |
| 　西夏東門 → 綠洲 `de_oasis` | 9 | 1.06 | 0.10 | 0.02 | 0.012 |
| 　綠洲 → 大理北門 | 7 | 0.62 | 0.08 | 0.03 | 0.012 |
| 西夏東門 → 華山山門 | 12 | 1.09 | 0.24 | 0.03 | 0.010 |
| 　西夏東門 → 茶棚 `hf_teahouse` | 7 | 0.67 | 0.12 | 0.01 | 0 |
| 　茶棚 → 華山山門 | 5 | 0.42 | 0.12 | 0.02 | 0.010 |
| 華山山門 → 少林山門 | 8 | 0.62 | 0.16 | 0.05 | 0.012 |
| 　華山山門 → 茶棚 `sy_teahouse` | 5 | 0.42 | 0.10 | 0.03 | 0.012 |
| 　茶棚 → 少林山門 | 3 | 0.20 | 0.06 | 0.02 | 0 |
| 西夏東門 → 少林山門 | 18 | 1.61 | 0.40 | 0.08 | 0.022 |
| 大理北門 → 華山山門（大理出生入派） | 26 | 2.62 | 0.41 | 0.09 | 0.034 |
| 大理北門 → 少林山門 | 32 | 3.14 | 0.57 | 0.14 | 0.046 |
| 西夏驛站 → 大理驛站（送信） | 20 | 1.68 | 0.18 | 0.06 | 0.024 |
| 西夏廣場 → 鬼王殿 `gw_throne` | 9 | — | — | — | — |

**新手安全規則**（綁定，WP-WORLD 要寫成測試，§9.1）：

1. **休息點**：城門房間、門派山門房間、茶棚／綠洲房間（不遇敵、有 INN）。路線上離休息點只差一步的房間（例如 `xw_road` 緊鄰西夏東門）也算休息點。
2. 兩個相鄰休息點之間：難纏怪期望 ≤ 0.15 場、山豬 ≤ 0.10 場、山賊 ≤ 0.015 場（`tools/data_lint.gd` 的 `NEWBIE_HARD_MAX`）。上表每一段都符合（最高 0.12 / 0.05 / 0.012）。
3. 緊鄰 CITY 城門或 SECT 山門的房間只能有 `m_rabbit`、`m_bigrabbit`（`xw_road`、`dlw_road`、`hy_foot`、`sy_foot`）。
4. 離任何 CITY／SECT 房間 2 步以內不放 `m_bandit`。
5. 必經路線上的怪，`combat_xp_ref` 最高只到山賊（3000），而且只能是小比重（權重 ≤ 10）。
6. 遇敵率每格 ≤ 0.15（data_lint 檢查每一間 WILD 房間，不只最短路線；例外：舊有的 `xw_grass` 0.25、`xw_wood` 0.20、`xw_hill` 0.30、`dlw_forest` 0.25，都不是必經的長程路段，或本來就是練功點）。
7. `tools/balance_sim.gd` 的走路案例 `p0_walk_*`：P0 沿西夏驛站 ⇄ 大理驛站、西夏廣場 → 少林山門、大理廣場 → 華山山門的最短路線一間一間走，照遇敵表擲骰；野兔、大野兔就打，難纏怪一開打就往逃跑格跑（逃跑成不成功也一起模擬），兩場之間不回氣，走到休息點才回滿。存活率要 ≥ 90%（目前 96–99%）。

**大理出生的新角色怎麼入派**：M1 的門派只有少林、華山，都在東邊。大理出生的人要走 **大理 → 西路 → 西夏郊外 → 東路**，到華山 26 步、到少林 32 步，總共遇敵約 2.6–3.1 場。路上有綠洲、西夏（只差一步就能進城住客棧、在東門找查小鏞設記錄點）、恆山茶棚三個休息點，每段都在上面的預算內。任務文字和大理守衛、驛站管事的對話會直接指路（§4、§7）。這段路很長是刻意的：原作的世界本來就大。

---

## 2. 地區表（`data/regions.json`）

共同欄位：`map` = `res://data/maps/<id>.json`；`night_closed: []`；`birth_room: ""`、`birth_allowed: false`（西夏、大理除外）。`city` 欄目前程式沒有讀，填最近的 1.0A 城市。

| id | name | type | era | city | world_pos | suggested_xp | pk_allowed | src | 狀態 |
|---|---|---|---|---|---|---|---|---|---|
| `xixia` | 西夏 | CITY | 1.0A | xixia | [304, 124] | [0, 0] | false | verified | 改 world_pos（原 [4,10]） |
| `xixia_wild` | 西夏郊外 | WILD | 1.0A | xixia | [340, 140] | [0, 2000] | true | verified | 改 world_pos |
| `xixia_north` | 西夏北郊 | WILD | 1.0A | xixia | [318, 62] | [500, 3000] | true | proposal | **新** |
| `xixia_east` | 西夏東郊 | WILD | 1.0A | xixia | [420, 118] | [0, 1500] | true | proposal | **新** |
| `guiwang` | 血刀洞迷宮 | DUNGEON | 1.0A | xixia | [359, 93] | [10000, 20000] | true | verified | 改名（原「鬼王洞」）、改 city、改 world_pos；id 不變 |
| `hengshan_foot` | 恆山山麓 | WILD | 1.0A | xixia | [610, 275] | [0, 1500] | true | proposal | **新** |
| `huayin_road` | 華陰道 | WILD | 1.0A | xixia | [705, 350] | [0, 1500] | true | proposal | **新** |
| `huashan` | 華山 | SECT | 1.0A | xixia | [725, 326] | [0, 0] | false | verified | 改 city（原 jingcheng）、改 world_pos |
| `songshan_road` | 嵩山古道 | WILD | 1.0A | xixia | [850, 330] | [0, 1500] | true | proposal | **新** |
| `shaolin` | 少林寺 | SECT | 1.0A | xixia | [967, 292] | [0, 0] | false | verified | 改 city、改 world_pos |
| `xixia_south` | 西夏南坡 | WILD | 1.0A | xixia | [262, 214] | [0, 1500] | true | proposal | **新** |
| `desert_edge` | 大漠邊緣 | WILD | 1.0A | xixia | [161, 345] | [0, 2000] | true | proposal | **新**（沙漠山洞座標） |
| `river_road` | 河川古道 | WILD | 1.0A | dali | [196, 560] | [0, 2000] | true | proposal | **新** |
| `dali_wild` | 大理郊外 | WILD | 1.0A | dali | [240, 700] | [0, 2000] | true | verified | 改 world_pos（原 [0,42]） |
| `dali` | 大理 | CITY | 1.0A | dali | [246, 776] | [0, 0] | false | verified | 改 world_pos |
| `jingcheng` | 京城 | CITY | **1.0B** | jingcheng | [850, 196] | [0, 0] | false | proposal | **era 改 1.0B**、改 world_pos |
| `jingcheng_wild` | 京城南郊 | WILD | **1.0B** | jingcheng | [850, 250] | [0, 2000] | true | proposal | **era 改 1.0B**、改 world_pos |

- 1.0A 共 15 個地區；開 1.0B 後 17 個。`world_pos` 全部不重複，都在 0–1000 之內（`check_world_pos` 照舊檢查）。
- 有原作座標的直接換算（§1.1）；`xixia_*`、`hengshan_foot`、`huayin_road`、`songshan_road`、`river_road`、`dali_wild`、京城兩區是沿路內插的【設計提案】。京城不在 2001 座標表裡，放在恆山、華山、少林之間的北邊，是依後期「京城 → 少林、武當、華山、恆山」的鄰近關係推的【後期版】。
- `suggested_xp` 會顯示在大地圖上（`map_data.gd`）。必經路線的區域下限一律是 0，不要嚇跑必須走這條路的新手。
- 每個地區檔的 `escape_tiles_hint: 2`、`src` 與上表相同。

---

## 3. 房間（`data/maps/*.json`）

格式照 M1_PLAN 3.11.8。`features` 只用 `FIELD`／`WOOD`／`WATER`／`STOVE`。遇敵寫成「rate：怪物 權重」，`count` 沒寫就是 [1,1]。「—」表示不遇敵或沒有 NPC。「不變」表示 desc 沿用現有文字。
出口一律雙向（`IN`↔`OUT`、`NE`↔`SW`…）。標 **(1.0B)** 的出口帶 `"era": "1.0B"`，預設世界看不到（§6.2）。

### 3.1 西夏城 `xixia.json`（9 間，地區 desc 不變）

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `xx_square` | 西夏廣場 | 不變 | E xx_gate_e、N xx_inn、S xx_station、W xx_street | — | — | n_wujieshan |
| `xx_gate_e` | 西夏東門 | 厚重的城門下站著守衛，城門邊的老先生正提筆記帳。出了城門往東是郊外：往東北的官道去恆山、華山、少林，順著南邊的小溪往南可以走到大理。 | W xx_square、E xw_road | — | — | n_xx_cha、n_xx_guard |
| `xx_inn` | 西夏客棧 | 不變 | S xx_square、U xx_inn_2f | STOVE | — | n_xx_innkeeper、n_xx_cook |
| `xx_inn_2f` | 客棧二樓 | 不變 | D xx_inn | — | — | n_zhangwuji |
| `xx_station` | 西夏驛站 | 驛站裡堆著一捆捆待送的信件，管事拿著名冊點收。牆上貼著告示：「代送書信，酬銀從優。」 | N xx_square | — | — | n_xx_station |
| `xx_street` | 西大街 | 不變 | E xx_square、N xx_pharmacy、S xx_smithy、W xx_wuguan | — | — | n_yeerniang、n_nanhai |
| `xx_pharmacy` | 回春藥鋪 | 不變 | S xx_street | — | — | n_xx_pharmacist |
| `xx_smithy` | 兵器鋪 | 不變 | N xx_street | — | — | n_xx_smith |
| `xx_wuguan` | 西夏武館 | 不變 | E xx_street | — | — | n_xx_wushi |

### 3.2 西夏郊外 `xixia_wild.json`（5 間，地區 desc 不變）

> **限制**：從 `xx_gate_e` 一直往東走（`xw_road` → `xw_grass` → `xw_hill`，死路）這條 E 鏈**不准改**。`tests/ui/ui_playthrough.gd` 第 8 步就是一直按「東」找怪打，東路改從 `xw_road` 的 **NE** 出去，西路改從 `xw_creek` 的 **S** 出去。

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `xw_road` | 東門外官道 | 出了西夏東門，一條黃土官道筆直向東，東北方另岔出一條往礦區、恆山去的官道。路旁草叢不時有野兔竄過，一位書生打扮的公子在路邊眺望遠方。 | W xx_gate_e、E xw_grass、**NE xe_road** | — | 0.15：m_rabbit 100 | n_chenjialuo |
| `xw_grass` | 荒草坡 | 不變 | W xw_road、N xw_wood、S xw_creek、E xw_hill | — | 0.25：m_rabbit 70 [1,2]、m_bigrabbit 30 | — |
| `xw_wood` | 胡楊林 | 一片耐旱的胡楊林，枝幹虯結，地上散著枯枝，一位樵夫正揮刀砍柴。林子北邊有條小徑爬上山坡。 | S xw_grass、**N xn_slope** | WOOD | 0.20：m_rabbit 100 | n_xw_woodcutter |
| `xw_creek` | 小溪邊 | 雪山融水匯成的小溪清澈見底，一位漁夫戴著斗笠坐在石頭上垂釣。溪水往南流去，順著溪岸走，可以一路走到大漠邊緣，再往南就是往大理的路。 | N xw_grass、**S ws_slope** | WATER | 0.12：m_rabbit 100 | n_xw_fisher |
| `xw_hill` | 狼嚎丘 | 不變 | W xw_grass | — | 0.30：m_wolf 90 [1,2]、m_bigrabbit 10 | — |

### 3.3 西夏北郊 `xixia_north.json`（新，2 間）

地區 desc：「西夏城北的山坡一路爬上雪線，風大天寒，少有人跡。」

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `xn_slope` | 城北山坡 | 山坡上碎石遍地，從這裡可以俯瞰整座西夏城。據說常有個神情冷漠的中年人獨自坐在坡上。 | S xw_wood、N xn_snow | — | 0.15：m_bigrabbit 50、m_wolf 50 | — |
| `xn_snow` | 雪地 | 終年不化的積雪蓋住山脊，雪地上偶爾有兩行沉重的腳印，不知是人是屍。往東的山脊下就是礦山。 | S xn_slope、E xe_xuedao | — | 0.15：m_wolf 80、m_bigrabbit 20（第 3 輪審查：原 0.18 違反 §1.4 規則 6） | — |

（范遙、銅屍鐵屍只寫進文字，M1 不放 NPC。）

### 3.4 西夏東郊 `xixia_east.json`（新，5 間）

地區 desc：「西夏城東北一帶山丘起伏，礦坑和深潭散落在往恆山的官道兩旁。」
地名依據：血刀洞迷宮在西夏東北、下方是礦區、礦工叫阿火、黑龍潭「從潭往右走到河邊」【2002 山洞清單（後期版，非 2001）】。

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `xe_road` | 東北官道 | 官道離開荒原折向東北，路邊一塊里程碑刻著「東至恆山、華山」，碑腳長滿了駱駝刺。 | SW xw_road、E xe_mine | — | 0.10：m_rabbit 70、m_bigrabbit 30 | — |
| `xe_mine` | 礦區 | 山坡上挖了好幾個礦坑，礦工推著獨輪車進進出出。北邊陡壁上有個黑黝黝的洞口。 | W xe_road、N xe_xuedao、E xe_heilong | — | 0.10：m_bigrabbit 80、m_wolf 20 | n_xe_miner |
| `xe_xuedao` | 血刀洞口 | 陡壁上裂開一道洞口，陰風從裡頭直往外灌。礦工都說洞裡是座迷宮，深處住著鬼王，沒有萬點實戰的本事千萬別進去。 | S xe_mine、W xn_snow、IN gw_entrance | — | 0.12：m_wolf 70、m_bigrabbit 30 | — |
| `xe_heilong` | 黑龍潭 | 一泓深黑的潭水，傳說潭底住著黑龍。潭水往東流出，順著走可以到河邊。 | W xe_mine、E xe_river | WATER | 0.10：m_bigrabbit 70、m_wolf 30 | — |
| `xe_river` | 潭東河岸 | 潭水匯成小河向東南流去，岸邊蘆葦叢生，常有野狼下來喝水。 | W xe_heilong、SE hf_paddy | WATER | 0.12：m_bigrabbit 50、m_wolf 50 | — |

### 3.5 血刀洞迷宮 `guiwang.json`（地區 id 不變，4 間）

地區 desc：「西夏東北礦山腹中的血刀洞迷宮，陰氣森森，小鬼成群，鬼王盤據在最深處。」
戰鬥背景照舊用擁有者畫的 `bg_guiwang`（`art.json` 的 key 就是地區 id，不必改）。

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `gw_entrance` | 洞口甬道 | 不變 | **OUT xe_xuedao**（原 dlw_cave）、N gw_hall | — | 0.30：m_ghost 100 | — |
| `gw_hall` | 陰風廳 | 洞中一座天然石廳，陰風呼嘯，地上散落著白骨，成群的小鬼在此遊蕩。北邊分出好幾條岔道。 | S gw_entrance、**N gw_maze**（原 gw_throne） | — | 0.35：m_ghost 100 [1,2] | — |
| `gw_maze` | 迷宮回廊 | **新**。岔道交錯，石壁上刻滿亂七八糟的記號，走過的路轉眼就認不出來。最裡頭隱約有火光。 | S gw_hall、N gw_throne | — | 0.35：m_ghost 100 [1,2] | — |
| `gw_throne` | 鬼王殿 | 不變 | **S gw_maze**（原 gw_hall） | — | — | n_guiwang |

### 3.6 東路：恆山山麓 `hengshan_foot.json`（新，4 間）

地區 desc：「恆山腳下水田連片，官道沿著河往東南通到華山。」地名依據「恆山外的稻田和岸邊」【2002 清單】；茶棚【設計提案】。

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `hf_paddy` | 恆山外稻田 | 山腳下開出一片稻田，田埂縱橫，水車吱呀作響。 | NW xe_river、E hf_teahouse | FIELD | 0.10：m_rabbit 50、m_bigrabbit 40、m_boar 10 | — |
| `hf_teahouse` | 路邊茶棚 | 官道旁搭著一座茅草茶棚，幾張木桌坐滿歇腳的旅人。老闆說往東南再走半天就到華山腳下。 | W hf_paddy、E hf_shore | — | —（安全） | n_hf_teaman |
| `hf_shore` | 恆山岸邊 | 河水在這裡轉了個彎，沙洲上繫著一條小船。對岸的雲霧裡露出恆山峰頂。 | W hf_teahouse、E hf_fork | WATER | 0.12：m_bigrabbit 50、m_rabbit 20、m_wolf 20、m_boar 10 | — |
| `hf_fork` | 恆山岔路 | 官道在這裡分岔。往北的山路通往恆山派和雁門關，路口有官兵設卡，不許通行。往東南是去華山的華陰道。 | W hf_shore、SE hy_road | — | 0.10：m_bigrabbit 50、m_wolf 40、m_bandit 10 | — |

### 3.7 東路：華陰道 `huayin_road.json`（新，3 間）

地區 desc：「華山南麓的華陰道，往北上華山，往西北通恆山，往東過水池可到嵩山。」

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `hy_road` | 華陰道 | 黃土路兩旁是半人高的蒿草，遠遠望去，西嶽華山像一柄倒插的長劍。 | NW hf_fork、E hy_foot | — | 0.10：m_bigrabbit 50、m_rabbit 20、m_wolf 20、m_boar 10 | — |
| `hy_foot` | 華山腳下 | 華山腳下的小鎮口，往北一條石階直上華山山門。往東是一片水池，往西北回恆山。 | W hy_road、N hs_gate、E hy_pond、**NE jcw_huashan (1.0B)** | — | 0.10：m_rabbit 60、m_bigrabbit 40 | — |
| `hy_pond` | 華山水池 | 華山與武當之間的一汪水池，池邊垂柳依依，常有人在池邊練劍。 | W hy_foot、E sy_road | WATER | 0.10：m_bigrabbit 60、m_rabbit 40 | — |

### 3.8 華山 `huashan.json`（只改山門）

| id | name | desc | exits | 其他 |
|---|---|---|---|---|
| `hs_gate` | 華山山門 | 峭壁間鑿出的石階通往山門，門前立著「華山派」石碑。碑旁的老先生正在簿子上記事。往南下山就是華山腳下。 | **S hy_foot**（原 W jcw_huashan）、N hs_square | npcs 不變（n_hs_cha） |
| `hs_square`、`hs_hall` | — | 不變 | 不變 | 不變 |

### 3.9 東路：嵩山古道 `songshan_road.json`（新，5 間）

地區 desc：「從華山往東到少林的古道，翻過幾道山嶺，越走松柏越多。」茶棚【設計提案】。

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `sy_road` | 東行古道 | 古道往東穿過丘陵，路邊的石碑寫著「東去嵩山少林」。 | W hy_pond、E sy_wdfork | — | 0.10：m_bigrabbit 50、m_rabbit 20、m_wolf 20、m_boar 10 | — |
| `sy_wdfork` | 武當岔路 | 往南的岔路通往武當山，被山崩阻斷，幾塊巨石擋在路中央。這一帶林深，偶爾有山賊出沒。 | W sy_road、E sy_teahouse | — | 0.12：m_wolf 35、m_bigrabbit 40、m_bandit 10、m_boar 15 | — |
| `sy_teahouse` | 嵩陽茶棚 | 古道邊的竹棚下支著一口大茶壺，過往的香客在這裡喝碗涼茶、換換腳力。 | W sy_wdfork、E sy_pines | — | —（安全） | n_sy_teaman |
| `sy_pines` | 嵩山松林 | 松林遮天蔽日，地上鋪滿松針，風一吹滿林都是松濤聲。 | W sy_teahouse、E sy_foot、**N jcw_songshan (1.0B)** | WOOD | 0.10：m_bigrabbit 40、m_wolf 40、m_boar 20 | — |
| `sy_foot` | 少室山腳 | 少室山腳下，石板路兩旁是給香客歇腳的石凳，往東再走幾步就是少林山門。山腳的茅屋裡住著一位採藥的姑娘。 | W sy_pines、E sl_gate | — | 0.10：m_rabbit 70、m_bigrabbit 30 | — |

### 3.10 少林 `shaolin.json`（只改山門）

| id | name | desc | exits | 其他 |
|---|---|---|---|---|
| `sl_gate` | 少林山門 | 山門上懸著「少林寺」三字匾額，古樸莊嚴。知客僧在門前迎送香客，一旁的老先生正在簿子上記事。往西是下山的嵩山古道。 | **W sy_foot**（原 E jcw_songshan）、N sl_court | npcs 不變 |
| 其餘 6 間 | — | 不變 | 不變 | 不變 |

### 3.11 西路：西夏南坡 `xixia_south.json`（新，3 間）

地區 desc：「西夏城南的緩坡順著雪水小溪往南延伸，越往南越乾。」

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `ws_slope` | 南坡 | 小溪沿著緩坡往南流，坡上的草越來越稀，偶爾能看到野兔在石縫間打洞。 | N xw_creek、SW ws_ford | — | 0.10：m_rabbit 60、m_bigrabbit 40 | — |
| `ws_ford` | 溪口淺灘 | 溪水在這裡攤成一片淺灘，踩著石頭就能過去。對岸往南是一片黃沙。 | NE ws_slope、S ws_dunes | WATER | 0.10：m_bigrabbit 50、m_rabbit 50 | — |
| `ws_dunes` | 沙丘邊緣 | 連綿的沙丘從西邊漫過來。往西去星宿海的小路被流沙埋了，只剩往南的路還看得出痕跡。 | N ws_ford、S de_edge | — | 0.10：m_bigrabbit 50、m_rabbit 50 | — |

### 3.12 西路：大漠邊緣 `desert_edge.json`（新，3 間）

地區 desc：「西夏與大理之間的大漠東緣，黃沙連著戈壁，只有一處綠洲可以歇腳。」依據：「大理後面的沙漠」、沙漠山洞 (3864,8280)【已證實】。綠洲【設計提案】。

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `de_edge` | 大漠邊緣 | 放眼望去盡是黃沙，駱駝商隊踩出的路沿著沙漠東緣往南延伸。 | N ws_dunes、S de_cave | — | 0.12：m_bigrabbit 50、m_rabbit 30、m_wolf 20 | — |
| `de_cave` | 沙漠山洞外 | 風蝕的石山下有個山洞，洞口被沙堵了一半，暫時進不去。往西是更深的大漠，聽說一直走能到血刀門，但沒人敢去。 | N de_edge、SE de_oasis | — | 0.12：m_wolf 30、m_boar 20、m_bandit 10、m_bigrabbit 40 | — |
| `de_oasis` | 綠洲 | 沙漠裡的一片綠洲，幾株胡楊圍著一口泉眼，一戶人家搭了帳篷賣茶水、供人歇宿。 | NW de_cave、SE rr_upper | WATER | —（安全） | n_de_host |

### 3.13 西路：河川古道 `river_road.json`（新，4 間）

地區 desc：「大理城北的河川往西北一直延伸到大漠，古道就沿著河岸走。」依據：「出大理城後往左上方依著河川方向行走」、「大理出城往上走、過橋的地方有河川」【已證實】。

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `rr_upper` | 河川上游 | 河水從大漠邊的泉眼匯出，水勢還小，岸邊盡是山豬拱過的爛泥。 | NW de_oasis、S rr_road | — | 0.12：m_bigrabbit 50、m_wolf 20、m_boar 20、m_bandit 10 | — |
| `rr_road` | 河川古道 | 古道貼著河岸蜿蜒，一邊是水，一邊是長滿灌木的山坡。 | N rr_upper、SE rr_bend | — | 0.10：m_bigrabbit 60、m_rabbit 20、m_wolf 10、m_boar 10 | — |
| `rr_bend` | 河灣 | 河在這裡繞了個大彎，水流緩慢，是釣魚的好地方。 | NW rr_road、S rr_bridge | WATER | 0.10：m_bigrabbit 60、m_rabbit 40 | — |
| `rr_bridge` | 過河石橋 | 一座古老的石拱橋橫跨河面。過了橋往東南走，就是大理城北的河畔。 | N rr_bend、SE dlw_river | — | 0.10：m_bigrabbit 60、m_rabbit 40 | — |

### 3.14 大理郊外 `dali_wild.json`（7 間，地區 desc 不變）

| id | name | desc | exits | features | encounter | npcs |
|---|---|---|---|---|---|---|
| `dlw_road` | 北門外大道 | 出了北門，一條大道穿過田野。東邊是陶耘的稻田，西邊是洱海，往北到河邊，過了石橋就是往西夏的河川古道。 | S dl_gate_n、**N dlw_river**（原 dlw_forest）、E dlw_paddy、W dlw_lake | — | 0.10：m_rabbit 100 | — |
| `dlw_river` | 城北河畔 | **新**。大理城北的一條河，河邊石階上有人洗衣。往西北過石橋、順著河往上游走，就是往西夏的古道；往東是蒼山林道。 | NW rr_bridge、S dlw_road、E dlw_forest | WATER | 0.10：m_rabbit 70、m_bigrabbit 30 | — |
| `dlw_paddy` | 陶耘稻田 | 一片綠油油的水田，稻穗低垂。田埂上一位老農捲著褲管，正彎腰插秧。東邊有一片樹林。 | W dlw_road、**E dlw_eastwood** | FIELD | 0.08：m_rabbit 100 | n_taoyun |
| `dlw_lake` | 洱海岸 | 不變 | E dlw_road | WATER | 0.10：m_rabbit 100 | — |
| `dlw_forest` | 蒼山林道 | 林木蔽日，山道崎嶇。樹叢裡偶爾閃過人影，聽說有山賊在這一帶出沒。林道到這裡已是蒼山腳下，再往裡就沒有路了。 | **W dlw_river**（原 S dlw_road、N dlw_cave） | — | 0.25：m_boar 60、m_bandit 25、m_wolf 15（不變） | — |
| `dlw_eastwood` | 東邊樹林 | **新**。大理城東邊的一片樹林，林間小徑鋪滿落葉。樵夫說穿過樹林往東北，從前是往崆峒、峨嵋的路。 | W dlw_paddy、E dlw_fork | WOOD | 0.10：m_rabbit 60、m_bigrabbit 30、m_wolf 10 | — |
| `dlw_fork` | 崆峒道口 | **新**。幾條山路在這裡交會：往北通崆峒，往東北通峨嵋和終南山。前些日子山崩，路全被落石堵死了。 | W dlw_eastwood | — | 0.12：m_wolf 50、m_boar 40、m_bigrabbit 10 | — |

- `dlw_cave`（鬼王洞口）**刪除**，存檔處理見 §8。
- 【推測】大理郊外的東西方位跟真實地理相反：`dlw_lake`（洱海岸）在 `dlw_road` 西邊、`dlw_forest`（蒼山林道）在 `dlw_river` 東邊，現實裡蒼山在大理西、洱海在東。原作客戶端的擺法沒有資料可查，沿用 1.0 版資料的方位，有證據再改。
- 依據：「大理右邊的樹林，在大理和崆峒派之間」【已證實】。`dlw_fork` 是留給 M3 的封閉岔路：M3 開峨嵋／終南時從這裡加出口，GDD 7.2 的 `kongtong_road` 地區到時候再從這間接出去。

### 3.15 大理城 `dali.json`（7 間，只改驛站）

| id | 改動 |
|---|---|
| `dl_station` | desc 改成：「驛站裡拴著幾匹滇馬，是官府傳遞公文用的。管事正在清點要送往各地的信件。」 |
| `dl_square`、`dl_gate_n`、`dl_inn`、`dl_yamen`、`dl_wuguan`、`dl_shop` | 不變（`dl_gate_n` 的 desc 本來就寫「大道通往蒼山與洱海」，不用改） |

### 3.16 出口對照（每條邊只列一次，左邊的方向反過來就是右邊的方向）

新增或改過的邊：

| 房間 A | A→B | B→A | 房間 B |
|---|---|---|---|
| xw_road | NE | SW | xe_road |
| xw_wood | N | S | xn_slope |
| xn_slope | N | S | xn_snow |
| xn_snow | E | W | xe_xuedao |
| xe_road | E | W | xe_mine |
| xe_mine | N | S | xe_xuedao |
| xe_mine | E | W | xe_heilong |
| xe_xuedao | IN | OUT | gw_entrance |
| xe_heilong | E | W | xe_river |
| gw_hall | N | S | gw_maze |
| gw_maze | N | S | gw_throne |
| xe_river | SE | NW | hf_paddy |
| hf_paddy | E | W | hf_teahouse |
| hf_teahouse | E | W | hf_shore |
| hf_shore | E | W | hf_fork |
| hf_fork | SE | NW | hy_road |
| hy_road | E | W | hy_foot |
| hy_foot | N | S | hs_gate |
| hy_foot | E | W | hy_pond |
| hy_pond | E | W | sy_road |
| sy_road | E | W | sy_wdfork |
| sy_wdfork | E | W | sy_teahouse |
| sy_teahouse | E | W | sy_pines |
| sy_pines | E | W | sy_foot |
| sy_foot | E | W | sl_gate |
| xw_creek | S | N | ws_slope |
| ws_slope | SW | NE | ws_ford |
| ws_ford | S | N | ws_dunes |
| ws_dunes | S | N | de_edge |
| de_edge | S | N | de_cave |
| de_cave | SE | NW | de_oasis |
| de_oasis | SE | NW | rr_upper |
| rr_upper | S | N | rr_road |
| rr_road | SE | NW | rr_bend |
| rr_bend | S | N | rr_bridge |
| rr_bridge | SE | NW | dlw_river |
| dlw_river | S | N | dlw_road |
| dlw_river | E | W | dlw_forest |
| dlw_paddy | E | W | dlw_eastwood |
| dlw_eastwood | E | W | dlw_fork |
| hy_foot (1.0B) | NE | SW | jcw_huashan |
| sy_pines (1.0B) | N | S | jcw_songshan |

拿掉的邊：`dlw_road N↔S dlw_forest`、`dlw_forest N↔S dlw_cave`、`dlw_cave IN↔OUT gw_entrance`、`gw_hall N↔S gw_throne`、`hs_gate W↔E jcw_huashan`、`sl_gate E↔W jcw_songshan`。

已用腳本照上表建圖核對過：1.0A 71 間、1.0B 78 間；每個出口都有反向出口；從 `xx_square` 走路到得了每一間；唯一刻意的死路是 `xw_hill`、`dlw_forest`、`dlw_fork`、`dlw_lake`、`gw_throne` 和城內房間。

### 3.17 房間 id 異動總表

| 類別 | id |
|---|---|
| 沿用、內容不變 | 西夏城 9 間（`xx_station` 只改 desc）、大理城 7 間（`dl_station` 只改 desc）、`xw_grass`、`xw_hill`、`dlw_lake`、`hs_square`、`hs_hall`、少林 6 間 |
| 沿用、改出口或 desc | `xx_gate_e`、`xw_road`、`xw_wood`、`xw_creek`、`dlw_road`、`dlw_paddy`、`dlw_forest`、`gw_entrance`、`gw_hall`、`gw_throne`、`hs_gate`、`sl_gate` |
| 新增（33 間；46 − 1 刪除 − 7 京城 + 33 = 71） | `xn_slope`、`xn_snow`；`xe_road`、`xe_mine`、`xe_xuedao`、`xe_heilong`、`xe_river`；`gw_maze`；`hf_paddy`、`hf_teahouse`、`hf_shore`、`hf_fork`；`hy_road`、`hy_foot`、`hy_pond`；`sy_road`、`sy_wdfork`、`sy_teahouse`、`sy_pines`、`sy_foot`；`ws_slope`、`ws_ford`、`ws_dunes`；`de_edge`、`de_cave`、`de_oasis`；`rr_upper`、`rr_road`、`rr_bend`、`rr_bridge`；`dlw_river`、`dlw_eastwood`、`dlw_fork` |
| 改名 | 無 |
| 刪除 | `dlw_cave` |
| 改成 1.0B（預設世界不存在） | `jc_station`、`jc_street`、`jc_inn`、`jc_gate_s`、`jcw_crossroad`、`jcw_songshan`、`jcw_huashan` |

新增房間的前綴：`xn_`（西夏北郊）、`xe_`（西夏東郊）、`hf_`（恆山山麓）、`hy_`（華陰道）、`sy_`（嵩山古道）、`ws_`（西夏南坡）、`de_`（大漠邊緣）、`rr_`（河川古道）。`hs_`、`sl_`、`em_` 留給門派內部房間，所以山麓路段不用這些前綴。

---

## 4. NPC（`data/npcs.json`）

### 4.1 新增

| id | name | kind | region / room | services | 其他 | src |
|---|---|---|---|---|---|---|
| `n_xe_miner` | 礦工阿火 | STORY | xixia_east / xe_mine | — | alignment NEUTRAL；talk `talk_n_xe_miner` | verified（人名，2002 清單）／proposal（台詞） |
| `n_hf_teaman` | 茶棚老闆 | FUNC | hengshan_foot / hf_teahouse | INN、SHOP | `inn_price` 15；shop：c_mantou、c_water、c_qiyao | proposal |
| `n_sy_teaman` | 茶棚老闆 | FUNC | songshan_road / sy_teahouse | INN、SHOP | 同上 | proposal |
| `n_de_host` | 綠洲店家 | FUNC | desert_edge / de_oasis | INN、SHOP | 同上 | proposal |

全部 `night_closed: false`、`era: "1.0A"`。茶棚與綠洲不放 `STOVE`、不放 `RESPAWN`（記錄點照原作規則只在城門和山門）。

### 4.2 修改

| id | 改動 |
|---|---|
| `n_xx_station` | `travel` 改成 `[ { "to_room": "dl_station", "price": 150 } ]`（拿掉京城；只有馬車選項打開時有用，【設計提案・非原作】）。`services` 保留 `TRAVEL`、`QUEST`，`quests: ["q_letter"]` 不變 |
| `n_dl_station` | `travel` 改成 `[ { "to_room": "xx_station", "price": 150 } ]`；`quests: ["q_letter_dl"]` 不變 |
| `n_jc_station`、`n_jc_innkeeper`、`n_jc_cha`、`n_jc_guard` | `era` 改 `"1.0B"`。`n_jc_station.travel` 改成 xx_station 120、dl_station 150 |
| `n_guiwang` | `region` 仍是 `guiwang`、`room` 仍是 `gw_throne`，不用改 |

---

## 5. 任務（`data/quests.json`）與驛站送信

### 5.1 規則（沿用 WORLD_ROUTES §3.1）

- 向驛站管事接信，背包多一件 `i_letter`（quest_item，不能賣）。自己走到目的地驛站交給管事，拿銀兩和名聲。**不收押金**、**沒有時限**。
- 死在路上：`STRICT_2001` 下信跟著背包掉進屍體，可以回去撿或放棄重接；`STANDARD`、`CASUAL` 信不會掉。不用改程式。
- 預設只有 西夏 ↔ 大理 兩封信。1.0B 不另外加京城的信（要加的話之後另開文件）。

### 5.2 任務列

| id | giver | 目標 | 獎勵 | 改動 |
|---|---|---|---|---|
| `q_letter` | n_xx_station | DELIVER i_letter → **n_dl_station**（不變） | money **100**（原 30）、fame **2**（原 1） | 文字、獎勵 |
| `q_letter_dl` | n_dl_station | DELIVER i_letter → **n_xx_station**（不變） | money **100**、fame **2** | 文字、獎勵 |
| `q_rabbit` | n_wujieshan | 不變 | 不變 | 文字 |
| `q_rice` | n_taoyun | 不變 | 不變 | 文字 |
| `q_bandit` | n_dl_bukuai | 不變（KILL m_bandit ×3，再 TALK） | 不變 | 文字 |
| `q_hs_kaoyan` | n_yuebuqun | 不變 | 不變 | 文字 |

送信的數值是【設計提案】：驛站到驛站 20 步、約 1.7 場遇敵，單程 100 兩、來回 200 兩，比 WORLD_ROUTES 北路的 80 兩（15 步）每步略低，符合原作「送信錢比較少」。目標 NPC 沒變，所以進行中的信不必轉換存檔。

鬼王：目前沒有鬼王任務，`n_guiwang` 只有 `FIGHT` 服務。本次不加新任務；跟鬼王有關的改動是地點（§3.4、§3.5）和下面 §7 的對話、`m_guiwang` 的 desc。

### 5.3 任務文字（直接指路）

- **q_letter**：「西夏驛站管事託你把一封信送到大理驛站。驛站的馬只送官文，信得你親自走過去。出西夏東門到荒草坡，往南到小溪邊，順著溪水往南經過西夏南坡、大漠邊緣，在綠洲歇歇腳，再沿河川古道往東南，過石橋到大理城北的河畔，往南進北門。驛站在五華樓前廣場的西邊。大漠一帶有野狼、山豬，新手別硬拼，一開打就往白框「逃」字的逃跑格跑，記得帶金創藥。」
  - 步驟：「把信函交給大理驛站管事」
- **q_letter_dl**：「大理驛站管事託你把一封信送到西夏驛站。出大理北門往北到河畔，過石橋往西北，沿河川古道走到大漠裡的綠洲，再往北穿過沙丘、西夏南坡，順著小溪走到荒草坡，往西就是西夏東門。驛站在廣場南邊。大漠一帶有野狼、山豬，新手別硬拼，一開打就往白框「逃」字的逃跑格跑。」
  - 步驟：「把信函交給西夏驛站管事」
- **q_rabbit**：「武介山想要一張大兔皮。出西夏東門往東到郊外的荒草坡打大野兔，把大兔皮帶回來給他。荒草坡東邊的狼嚎丘野狼成群；東北的官道和南邊的小溪是往外地的遠路，新手先別走遠。」
- **q_rice**：「陶耘的稻田缺人手。先跟陶耘學種田，在田裡耕作，收成 5 份米交給他。稻田在大理北門外大道的東邊。」
- **q_bandit**：「蒼山林道一帶山賊橫行。出大理北門往北走到城北河畔，往東就是蒼山林道。剿滅 3 名山賊，再回衙門向捕快覆命。大漠的沙漠山洞、河川古道上游、恆山岔路和嵩山古道的武當岔路偶爾也有山賊，一樣算數。」
- **q_hs_kaoyan**：「岳不群要先看看你的根基：到玉女峰練武場找陸大有切磋，勝過華山弟子後再來見他。」

---

## 6. 京城改成 1.0B

### 6.1 怎麼擋

| 檔案 | 改動 |
|---|---|
| `data/eras.json` | **不改**。`1.0B`（神鵰大俠，`requires: ["1.0A"]`、`base: false`）本來就有 |
| `data/server_options.default.json` | ~~`enabled_eras` 維持 `["1.0A"]`~~ M3b 起改 `["1.0A","1.0B"]`（M3B_PLAN E1） |
| `data/regions.json` | `jingcheng`、`jingcheng_wild` 的 `era` 改 `"1.0B"` |
| `data/maps/jingcheng.json`、`data/maps/jingcheng_wild.json` | 檔頭 `era` 改 `"1.0B"` |
| `data/npcs.json` | `n_jc_station`、`n_jc_innkeeper`、`n_jc_cha`、`n_jc_guard` 的 `era` 改 `"1.0B"` |
| `data/text_templates.json` | `talk_n_jc_station`、`talk_n_jc_innkeeper`、`talk_n_jc_cha`、`talk_n_jc_guard` 的 `era` 改 `"1.0B"` |
| 1.0A 房間的出口 | `hy_foot` 的 `NE→jcw_huashan`、`sy_pines` 的 `N→jcw_songshan` 加 `"era": "1.0B"`（§6.2） |
| `data/patches/1.0B.json`（新） | 見下 |

`DataLoader.activate()` 本來就會依 `era` 篩掉 regions／maps／npcs／templates 的列，所以只差**出口層級**的 era（§6.2）。

`data/patches/1.0B.json`：

```json
{ "era": "1.0B", "rows": [
  { "id": "p1b_xx_station_travel", "target_table": "npcs", "target_id": "n_xx_station", "op": "merge",
    "set": { "travel": [ { "to_room": "dl_station", "price": 150 }, { "to_room": "jc_station", "price": 120 } ] },
    "src": "proposal" },
  { "id": "p1b_dl_station_travel", "target_table": "npcs", "target_id": "n_dl_station", "op": "merge",
    "set": { "travel": [ { "to_room": "xx_station", "price": 150 }, { "to_room": "jc_station", "price": 150 } ] },
    "src": "proposal" }
] }
```

（`merge` 會整個換掉陣列，所以要把原本的路線一起寫進去。如果 `PatchApplier` 或 lint 要求 patch 列的其他欄位，照 TECH_ARCH 5.5.3 補齊。）

### 6.2 出口層級的 era（core 小改）

- 出口物件可以多帶 `"era": "<era id>"`（也支援 `"era_until"`，規則和資料列一樣）。
- `DataLoader.activate()` 複製 maps 之後，對每間房的 `exits` 用 `row_active(exit, on)` 篩掉沒生效的出口；沒有 `era` 欄的出口一律保留。
- 主機和客戶端都用同一個 `activate()`（客戶端用 welcome 給的 `enabled_eras`），所以兩邊看到的出口一樣，不必改協定。
- lint：出口的 `era` 必須是存在的 era id；而且雙向檢查是在每個 era 閉包的 activate 視圖上做，所以帶 era 的出口兩邊都要帶同一個 era（或另一邊整個地圖就是那個 era）。

### 6.3 開了 1.0B 之後，京城接在哪裡

京城在恆山、華山、少林之間的北邊（[850,196]），南郊用兩條下山路接到東路，形成一個三角：

```
                 jc_station ─E─ jc_street ─N─ jc_inn
                                  │S
                               jc_gate_s
                                  │S
          jcw_huashan ─W──── jcw_crossroad ────E─ jcw_songshan
              │SW                                      │S
   hy_foot（華山腳下）                            sy_pines（嵩山松林）
```

| 房間 | 1.0B 的出口 | desc 改成 |
|---|---|---|
| `jc_gate_s` | 不變（N jc_street、S jcw_crossroad） | 「高大的南門城樓下，守衛盤查著進出的行人。出了南門，往西南下山是華山，往東南是嵩山少林。」 |
| `jcw_crossroad` | N jc_gate_s、W jcw_huashan、E jcw_songshan | 「幾條古道在此交會。往西下山到華山腳下，往東接嵩山古道去少林；路牌上往武當、恆山、雁門關的方向都寫著『道路不通』。」 |
| `jcw_huashan` | E jcw_crossroad、**SW hy_foot**（原 E hs_gate） | 「山勢漸陡，古道兩旁松柏參天。往西南下山就是華山腳下。」 |
| `jcw_songshan` | W jcw_crossroad、**S sy_pines**（原 W sl_gate） | 「石板古道蜿蜒入山，遠處隱約傳來寺院的鐘聲。往南下山接上嵩山松林，再往東就是少林山門。」 |

步數（1.0B）：京城南門 → 華山山門 4 步、→ 少林山門 5 步。遇敵表沿用現有的 `jcw_*`。
`talk_n_jc_guard` 改成：「{npc_name}喝道：『南門外往華山、少林的路都通。往武當、恆山、雁門關的路還封著，別白跑一趟。』」
~~京城在 1.0B 仍然**不能出生**（`birth_allowed: false` 不變）。~~ M3b 起 1.0B 京城可出生（`birth_allowed: true`、`birth_room: "jc_square"`；研究 2001-11-06「選京城為出生地」，M3B_PLAN O3／E2）。

### 6.4 怎麼開

- 新建世界時用新的啟動參數 `--eras=1.0A,1.0B`（只影響**新建**的世界，比照 `--rule-preset`；要先過 `DataLoader.validate_enabled_eras`）。
- 既有世界：手動改 `world.json` 的 `enabled_eras`。關掉 1.0B 時站在京城的角色會被 §8 的規則搬走。

---

## 7. 文字模板（`data/text_templates.json`）

| key | 新文字 |
|---|---|
| `talk_n_xx_station` | {npc_name}翻著名冊：「往大理的信最多。路遠，得先往南過大漠，再順著河川下去。肯跑一趟，酬勞少不了。」 |
| `talk_n_dl_station` | {npc_name}一邊點信一邊說：「這兒有封信要送去西夏。出北門到河邊過橋，順著河往西北走，過了大漠就到。你肯不肯跑一趟？」 |
| `talk_n_xx_guard` | {npc_name}打量了你一眼：「出了東門就是郊外，野兔野狼多得很，新來的別往狼嚎丘跑。往大理，順著南邊的小溪走；往恆山、華山、少林，走東北的官道。」 |
| `talk_n_dl_guard` | {npc_name}和氣地說：「北門外河邊往東的蒼山林道有山賊。要去西夏，過橋順著河往西北走；東邊往崆峒、峨嵋的路還封著。」 |
| `talk_n_dl_wushi` | {npc_name}抱拳道：「本館傳授基本功夫，每次請教收五兩。想去西夏東北邊的血刀洞會鬼王，先把根基打好。」 |
| `talk_n_xe_miner`（新） | {npc_name}抹了把汗：「這礦坑上頭就是血刀洞，裡頭是迷宮，深處住著鬼王。前幾天又有個愣頭青進去，就沒再出來過。」 |
| `talk_n_hf_teaman`（新） | {npc_name}提著茶壺：「客官歇歇腳吧！往東南是華山，再往東走嵩山古道就到少林。往北的恆山、雁門關官兵封著。住一宿十五兩。」 |
| `talk_n_sy_teaman`（新） | {npc_name}擦著桌子：「往西回華山，往東再走幾里就是少林山門。南邊往武當的路塌了，別白跑。」 |
| `talk_n_de_host`（新） | {npc_name}遞來一碗水：「大漠裡就這一口泉。往北過沙丘是西夏，往東南順著河下去是大理。歇一宿十五兩。」 |
| `talk_n_jc_*` | 文字不變（`talk_n_jc_guard` 改 §6.3），`era` 改 1.0B |
| `err_stagecoach_disabled`（新） | 驛站的馬只送官文，不載客。要去哪裡，得自己走路。 |
| `relocated`（新事件） | 你原本所在的地方已經不在這個江湖裡了。回過神來，你人在{room_name}。 |
| `respawn_reset`（新事件） | 你的記錄點已經不在這個江湖裡了，改回{room_name}。 |
| `travel`、`err_no_route` | 不變（馬車選項打開時還會用到） |

其他資料文字：

- `data/items.json` `i_letter.desc`：「封了火漆的信函，要親手送到收信的驛站。」
- `data/monsters.json` `m_guiwang.desc`：「盤據血刀洞迷宮深處的鬼王，一身陰氣，掌風過處燭火盡滅。（設計提案）」。`m_ghost` 的名稱「鬼王洞小鬼」保留（2002 指南的練功點就叫鬼王洞），desc 不變。

---

## 8. 舊存檔怎麼處理

### 8.1 角色位置（`server/game_host.gd` `enter_character()`）

角色進入世界時，如果 `location.room` 在目前生效的房間索引裡找不到，依序：

1. 查 `ROOM_FALLBACK`（`game_host.gd` 新常數）：`{ "dlw_cave": "dlw_forest" }`。目標房間存在就搬過去。
2. 否則搬到記錄點 `respawn_room(ch)`（記錄點也失效時，它本來就會退回出生城）。
3. 搬完以後補正 `location.region`，並送 `relocated` 事件（`CH_SYSTEM`，payload `{ "room_name": ... }`）。

### 8.2 記錄點

如果 `ch.respawn.room` 不在生效的房間裡（例如在京城南門找查小鏞設過記錄點，現在京城被 era 擋掉），進入世界時把 `ch.respawn` 清成 `{}`，並送 `respawn_reset`（payload `{ "room_name": <出生城 birth_room 的名稱> }`）。死亡重生本來就會退回出生城，這一步只是讓角色表顯示正確，也讓玩家知道。

### 8.3 會被搬走的情形

| 舊位置 | 預設世界（1.0A） | 開了 1.0B |
|---|---|---|
| `dlw_cave` | 搬到 `dlw_forest` | 同左 |
| `jc_*`、`jcw_*` | 搬到記錄點（例如少林、華山山門），沒有就回出生城 | 不動 |
| `gw_*`（洞裡） | 不動。洞現在在西夏東北，出洞（OUT）會到 `xe_xuedao` | 不動 |
| 其他沿用的房間 | 不動 | 不動 |

- 進行中的任務：`q_letter` 仍然送到大理、`q_letter_dl` 仍然送到西夏，id 和目標都沒變，不必轉換。沒有任務的目標 NPC 被 era 擋掉。
- 屍體（`world.json` 的 `corpses`）：房間在 `ROOM_FALLBACK` 裡的，開世界時搬到目標房間；在 era 擋掉的房間裡的，照常 30 分鐘後消失（只有在世界升級的那一刻剛好有屍體才會遇到，接受）。
- 舊世界的 `server_options` 沒有 `stagecoach_enabled`，一律讀成 `false`：更新後舊世界也變成只能走路（在更新說明裡寫一句）。

---

## 9. 各工作包的改動清單

### 9.1 WP-WORLD（`data/**`、`server/**`、`core/**`、`tools/data_lint.gd`、`tests/unit/test_world*.gd`、`tests/unit/test_data*.gd`、`tests/bots/m1_playthrough_bot.gd`、GDD §7、M1_PLAN 的世界章節）

**資料**

| 檔案 | 改動 |
|---|---|
| `data/regions.json` | §2：新增 8 列；改 `xixia`、`xixia_wild`、`guiwang`、`huashan`、`shaolin`、`dali_wild`、`dali` 的 `world_pos`／`city`／`name`；京城兩列 `era` 改 1.0B |
| `data/maps/xixia_north.json`、`xixia_east.json`、`hengshan_foot.json`、`huayin_road.json`、`songshan_road.json`、`xixia_south.json`、`desert_edge.json`、`river_road.json` | 新檔（§3.3、3.4、3.6、3.7、3.9、3.11、3.12、3.13） |
| `data/maps/xixia.json` | `xx_gate_e`、`xx_station` 的 desc |
| `data/maps/xixia_wild.json` | `xw_road`、`xw_wood`、`xw_creek` 的出口與 desc |
| `data/maps/guiwang.json` | 地區 desc；新增 `gw_maze`；`gw_entrance`、`gw_hall`、`gw_throne` 的出口 |
| `data/maps/huashan.json`、`shaolin.json` | `hs_gate`、`sl_gate` 的出口與 desc |
| `data/maps/dali_wild.json` | 刪 `dlw_cave`；新增 `dlw_river`、`dlw_eastwood`、`dlw_fork`；改 `dlw_road`、`dlw_paddy`、`dlw_forest` |
| `data/maps/dali.json` | `dl_station` desc |
| `data/maps/jingcheng.json`、`jingcheng_wild.json` | 檔頭 `era: "1.0B"`；§6.3 的出口與 desc |
| `data/patches/1.0B.json` | 新檔（§6.1） |
| `data/npcs.json` | §4 |
| `data/quests.json` | §5.2、§5.3 |
| `data/text_templates.json` | §7 |
| `data/items.json`、`data/monsters.json` | §7 的 desc |
| `data/server_options.default.json` | 加 `"stagecoach_enabled": false` |
| `data/art.json` | `backgrounds` 加 alias（**不換任何圖、不加黑底**）：`xixia_north`、`xixia_east`、`xixia_south`、`desert_edge` → `xixia_wild`；`river_road` → `dali_wild`；`hengshan_foot`、`huayin_road`、`songshan_road` → `jingcheng_wild`（綠色山丘那張畫；檔名照舊，`bg_default` 照舊） |

**程式**

| 檔案 | 改動 |
|---|---|
| `core/data/data_loader.gd` | `activate()` 依 `row_active` 篩出口（§6.2） |
| `core/data/data_schema.gd` | 如果 `server_options` 有型別轉換清單，加 `stagecoach_enabled`（bool） |
| `core/protocol.gd` | 加 `E_RELOCATED := "relocated"`、`E_RESPAWN_RESET := "respawn_reset"`（純新增） |
| `server/game_host.gd` | `ROOM_FALLBACK`；`enter_character()` 改成 §8.1、§8.2；開世界時搬屍體（§8.3） |
| `server/npc_system.gd` | `travel()` 開頭：`stagecoach_enabled` 不是 true 就 `fail("stagecoach_disabled")`；`menu()`：選項關閉時 `services` 拿掉 `TRAVEL`、`routes: []`；打開時只列 `has_room(to_room)` 的路線 |
| `autoload/world_server.gd`（不在上面的目錄裡，**需整合者同意**；沒人擁有這個檔） | (1) `--stagecoach=on|off`：開世界時（新建或既有）把值寫進該世界的 options 並存檔；沒給就沿用存檔值，預設 false。(2) `--eras=1.0A,1.0B`：只影響新建世界。(3) `world_info()` 加 `"stagecoach_enabled": bool` |

**lint（`tools/data_lint.gd`）**

1. `room_graph()` 預設**只算步行出口**；`reachable_rooms`、`find_path`、`_c_reachability` 都改成純步行。驛站路線只檢查 `to_room` 存在。
2. 每座 `birth_allowed` 的城，彼此要走得到；每個 SECT 地區至少有一間房從每座出生城走得到。
3. 每個 DELIVER 任務的目標 NPC 房間，從給任務的 NPC 房間走得到。
4. 出口 `era`：必須是存在的 era id（§6.2）。
5. `_check_server_options`：`stagecoach_enabled` 有寫就必須是 bool。
6. 錯誤 key `err_stagecoach_disabled`、事件 key `relocated`、`respawn_reset` 加進 `REQUIRED_TEMPLATE_KEYS`。
7. （warning）§1.4 的新手安全規則 2–5：沿著每座出生城到每個門派山門的最短步行路線檢查，超標印 warning；測試裡用 assert（下面）。

**測試**

| 檔案 | 改動 |
|---|---|
| `tests/unit/test_data_content.gd` | room count 46 → **71**；regions 9 → **15**；可達性改純步行；`test_path_from_xx_square_to_gw_throne_uses_station` 改成 `..._walks_via_xuedao`：路徑經過 `xe_xuedao`、不經過任何驛站、長度 9；`test_walk_route_jingcheng_to_shaolin_and_huashan` 改成東路（`xx_gate_e`→`hs_gate` 12 步、`hs_gate`→`sl_gate` 8 步、`xx_gate_e`→`dl_gate_n` 16 步，用 `find_path` 長度斷言）；`test_rooms_match_plan_regions` 換成 §3 的房間表；`test_room_features_and_locks` 加新的 FIELD／WOOD／WATER，三個休息房間沒有 `encounter`；`test_encounter_tables_match_plan` 加 §1.4 規則 2–5（休息點間的期望值用 §1.4 的公式算）；`test_newbie_path_has_no_wolves_and_quest_monster_lives_there` 保留不改；`test_all_m1_npcs_exist_with_services` 拿掉 `n_jc_*`、加 4 個新 NPC；`test_jingcheng_hub_only_has_hub_npcs` 改成「1.0A 視圖沒有任何 `jc_*`／`jcw_*` 房間與 `n_jc_*` NPC；1.0B 視圖有，而且 `jc_gate_s` 到 `hs_gate` 4 步、到 `sl_gate` 5 步」；`test_npc_service_details` 的 travel 改新價（1.0A 與 1.0B 各一）；`test_quests_table` 改信件獎勵；`test_lint_detects_unreachable_room` 改成拿掉 `xw_road` 的 NE 出口時，lint 要報 `xe_*`、`gw_*`、`hs_*`、`sl_*` 不可達；新增「出口帶 era 的房間在 1.0A 視圖沒有那個出口」 |
| `tests/unit/test_world_move.gd` | `test_travel_by_station`：先設 `host.options.stagecoach_enabled = true`，目的地改 `dl_station`、價格 150；新增 `test_travel_disabled_by_default`（`stagecoach_disabled`，位置和銀兩不變）；`test_jingcheng_hub_npcs_only` 刪掉或改成 1.0B fixture；第 126 行的 travel 改用 fixture 的 `goto(room)`；新增 `test_walk_xixia_to_dali`（關遇敵或用守護者之煙，一步步 move 到 `dl_gate_n`）；新增搬家測試：位置 `dlw_cave` → `dlw_forest`、位置 `jc_street` → 記錄點、記錄點 `jc_gate_s` → 清空並收到 `respawn_reset` |
| `tests/unit/test_world_quest.gd` | 第 66、82 行的 `travel` 改成 `goto(room)`；信件獎勵 100／+2；加測送信要走到目的地房間才能交 |
| `tests/unit/test_world_chars.gd` | 第 55 行 `birth_city: "jingcheng"` 照樣要回 `bad_value:birth_city`（1.0A 沒有這個地區），斷言不用改，確認一下 |
| `tests/unit/test_world_death.gd` | `goto("gw_throne")` 不用改 |
| `tests/bots/m1_playthrough_bot.gd` | 見 §9.3 |

**文件**：GDD §7.1（重寫「1.0-A 的地理斷層」：照原作地理，城際只有西路；京城 1.0B；馬車選項【設計提案・非原作】；加 §1.1 的座標表）、§7.2（換成 §2 的地區；`guiwang` 改名血刀洞迷宮、鄰近西夏；`jingcheng` 改 1.0B；`kongtong_road` 註明從 `dlw_fork` 接出、M3）、§7.3（m_ghost 地區不變、m_bandit 出沒地點）。M1_PLAN：3.11.7、3.11.8（出口可帶 `era`）、3.11.15（lint 新檢查）、3.6／3.7（travel 的 `stagecoach_disabled`）、3.8.1（`relocated`、`respawn_reset`）、5.1（房間表）、5.2（新 NPC、驛站路線價格）、5.7（任務）、6.1（測試表）、6.4（bot 劇本）。

### 9.2 WP-UI（`ui/**`、`autoload/bgm_player.gd`、`autoload/scene_router.gd`、`tests/unit/test_ui*.gd`）

| 檔案 | 改動 |
|---|---|
| `ui/game/map/map_data.gd` | `world_model(tables, show_travel := false)`：`show_travel` 為 false 時 `travel` 回空陣列。新的步行連線會自動算出來（1.0A 共 15 對：xixia–xixia_wild、xixia_wild–xixia_north、xixia_wild–xixia_east、xixia_wild–xixia_south、xixia_north–xixia_east、xixia_east–guiwang、xixia_east–hengshan_foot、hengshan_foot–huayin_road、huayin_road–huashan、huayin_road–songshan_road、songshan_road–shaolin、xixia_south–desert_edge、desert_edge–river_road、river_road–dali_wild、dali_wild–dali） |
| `ui/game/map/map_panel.gd` | 呼叫 `world_model` 時傳 `ClientState.world_info.get("stagecoach_enabled", false)` |
| `ui/game/map/world_map_view.gd` | 座標改成 0–1000 的真實比例後，西夏一帶 5 個區域擠在約 60×80 的範圍裡，現在 112×46 的方框一定會疊在一起。改成：城市用朱紅印章方塊、門派用山形記號、郊外和洞窟用小點，名字標在旁邊並且避開彼此；畫布照真實比例，放不下時可以捲動或縮放。底和線照 AUTHENTIC_UI_SPEC §8.10（羊皮紙底、`#5A4630` 2px 墨線）。圖例改成「虛線＝驛站馬車（伺服器選項，非原作）」。可以順便把 §1.1 封閉的門派（✕）畫成灰字，資料直接寫在 UI 裡就好（不是遊戲資料） |
| `ui/game/char/char_create.gd` | 出生地羊皮紙地圖（§8.11）用 `world_pos`：西夏在上、大理在下，比例照真的 |
| `ui/game/battle/battle_iso_view.gd` | 不用改。`region_palette` 只在找不到圖時用；新地區靠 `art.json` 的 alias 拿到擁有者的畫 |
| 文字顯示 | 確認 `relocated`、`respawn_reset` 兩個事件有照模板顯示在系統訊息（如果 `text_renderer` 是依 key 查模板就不用改） |
| `autoload/bgm_player.gd`、`autoload/scene_router.gd` | 不用改。新地區都是 `WILD`、`guiwang` 仍是 `DUNGEON`；BGM 依地區類型切換，茶棚房間跟著所在地區播野外曲 |
| `tests/unit/test_ui_map_layout.gd` | 第 183–192 行改成：預設 `travel` 為空、`walk` 包含上面 15 對；位置斷言改成 西夏在大理北邊、少林在華山東邊、華山在恆山山麓東南、大漠在西夏西南；新增「1280×720 下任兩個區域的標籤矩形不重疊」（1.0A 與 1.0B 各測一次） |
| `tests/unit/test_ui_map_panel.gd` | 第 234–236 行：`setup(..., "xixia")`；`show_travel = true` 時才檢查有路線 |
| `tests/unit/test_ui_host_flows.gd` | 第 96 行的 travel 前先把 `host.options.stagecoach_enabled` 設成 true |
| `tests/unit/test_ui_scenes.gd` | 第 131 行的假 menu 可以不改；新增：`stagecoach_enabled` 為 false 時 `npc_dialog` 不出現「驛站」按鈕 |

### 9.3 驗收 bot（`tests/bots/m1_playthrough_bot.gd`，WP-WORLD）

`_graph()` 拿掉驛站邊（或只在 `stagecoach_enabled` 時加）；刪掉 `HUB_NPCS` 和第 11 步的京城固定路線。新劇本（步驟號碼重排，M1_PLAN 6.4 一起改）：

| 步驟 | 內容 | 檢查 |
|---|---|---|
| 1–9 | 不變（第 4 步京城出生照樣被拒） | 不變 |
| 10 | 西夏驛站接 `q_letter`；送 `travel n_xx_station dl_station` 預期 `stagecoach_disabled`；`_goto("dl_station")`；交信 | 位置 `dl_station`、路上經過 `de_oasis`、`quest_complete`／`reward` 事件的 money = 100（不要比身上餘額，打怪會掉錢、住綠洲要花錢）、名聲 +2。`classic_strict` 下死在路上丟了信：放棄任務、回西夏重接 |
| 11 | 種田＋`q_rice`（原 19） | 原檢查 |
| 12 | 廚師（原 20） | 原檢查 |
| 13 | 大理驛站接 `q_letter_dl`，走回西夏驛站交信 | 同第 10 步 |
| 14 | `_goto("sl_gate")` | 路上經過 `hf_teahouse`、`hy_foot`、`sy_teahouse`；不經過任何 `jc_*` |
| 15–20 | 原 12–17（入少林、學武、齋堂等） | 原檢查 |
| 21 | `_goto("gw_entrance")` | 經過 `xe_xuedao`；`location.region == "guiwang"` |
| 22–24 | 不變 | 不變 |

走路約多出 80 步、4–6 場仗。README 和檔頭指令的 `--quit-after` 從 900 調成 **1800**（網路版主機 1860、客戶端 1850）。`_nearest_inn()` 如果是照 `INN` 服務找，三個休息房間會自動算進去；住宿 15 兩要留在 `INN_RESERVE` 裡。

### 9.4 整合者（只有整合者能改的檔案）

| 檔案 | 改動 |
|---|---|
| `tests/ui/ui_playthrough.gd` | 送信那段照舊測馬車介面：執行指令加 `--stagecoach=on`（因為這個參數對既有世界也有效，`ui_play` 世界不用每次重建）。第 8 步「一直往東找怪」不用改：E 鏈 `xw_road`→`xw_grass`→`xw_hill` 維持原樣（§3.2）。檔頭第 13 行的說明加一句「馬車是伺服器選項，驗收時打開」 |
| `README.md` | 「怎麼玩 M1」第 3 點改寫路線（西夏 → 東北官道 → 恆山茶棚 → 華山／少林；西夏 → 南邊小溪 → 大漠綠洲 → 河川古道 → 大理；鬼王在西夏東北的血刀洞迷宮）；bot 指令的 `--quit-after`；UI driver 指令加 `--stagecoach=on`；啟動參數表加 `--stagecoach`、`--eras` |
| `docs/WORLD_ROUTES.md` | 檔頭加一行：「地理已由 `docs/WORLD_2001.md` 取代」 |
| GDD §0.1、§1、§8.2、§13 | 拿掉「經驛站到京城」「京城驛站樞紐」的說法；§8.2 信件列；§13 驗收句改成「走路到少林並完成一次西夏 ↔ 大理送信」 |

---

## 10. 客戶端看得到的協定改動

全部是**新增**，舊客戶端不會壞；`Protocol.VERSION` 不用升（資料改了，`content_hash` 本來就會不同，大廳照 hash 擋不同版本）。

| 項目 | 內容 |
|---|---|
| `world_info.stagecoach_enabled` | 新欄位（bool）。客戶端讀不到就當 false |
| 原因碼 `stagecoach_disabled` | `travel` intent 的新失敗原因；模板 `err_stagecoach_disabled` |
| 事件 `relocated` | `CH_SYSTEM`，payload `{ room_name }` |
| 事件 `respawn_reset` | `CH_SYSTEM`，payload `{ room_name }` |
| `npc_menu` | 形狀不變；馬車關閉時 `services` 沒有 `TRAVEL`、`routes` 是空陣列 |
| 房間視圖的 `exits` | 形狀不變；帶 era 的出口在主機和客戶端的 `activate()` 都被篩掉 |

沒有新增或改名的 intent。

---

## 11. 依據與待考證

- 【已證實】開服只有西夏（西北）、大理（西南）；京城是神鵰大俠加的第三座城（17173 yinan/35、DIAO/2-1）。山門座標：17173 gaoshou/17。NPC 座標：gaoshou/23。野外踩地雷遇敵：xinshou/13。
- 【後期版】血刀洞迷宮（8626,2228）、礦區、阿火、黑龍潭、恆山外稻田與岸邊、鬼王在血刀洞迷宮裡：2002 山洞清單。已收進 `docs/research/verified_research.md`（世界章節，標【later-version】）。
- 【已證實】西路的地形依據：「大理後面的沙漠」、沙漠山洞 (3864,8280)、「出大理城後往左上方依著河川方向行走」、「大理出城往上走、過橋的地方有河川」。
- 【設計提案】茶棚與綠洲、所有 desc、遇敵表、送信獎勵、各地區的內插座標。
- 【設計提案・非原作】驛站馬車（`stagecoach_enabled`，預設關）。
- 【待考證】原作的西夏有沒有南門；本作讓西路從郊外的小溪往南出去，不另開城門。2001 年西夏到大理實際要走多久，查不到資料。
