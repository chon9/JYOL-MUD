# BGM_PLAN：背景音樂配置與播放規則

> 版本 1（2026-10-18）。適用範圍：`assets/bgm/` 的 4 首曲子。對應 GDD §0.1 第 5 項（是否公開發行）、§11（UI）、TECH_ARCH（客戶端表現層）。
> 標記：**【原作證實】** 表示有來源直接佐證；**【推測】** 表示沒有找到來源，後面附推測理由。**目前沒有任何一首曲子的原作使用場景能被證實**，所以下面的場景配置全部標【推測】，請把它當成本作的設計選擇，而不是「照原作重現」。

---

## 0. 授權與發行限制（必讀）

- 這 4 個檔案由擁有者提供，內容是智冠（Soft-World）的官方原聲帶錄音，**幾乎可以確定仍受著作權保護**。
  - 檔案沒有 ID3 標籤，編碼器是 FFmpeg `Lavf60.16.100`，`major_brand=isom`，看起來是從串流或 m4a 轉出來的，不是官方下載檔。
- **只限 GDD §0.1 第 5 項的「目前預設」**：好友間私下測試。
- **任何公開發行（Steam 上架、公開下載、公開實況附遊戲檔）之前，必須把這 4 首換成自製或可授權的曲子**。替換只要改 §4 的 `BGM_TRACKS` 表，不動播放邏輯。
- 不要把這 4 個 mp3 推到公開的 git 遠端；`assets/LICENSES` 要註明「擁有者私人提供，不可散布」。
- 在 GDD §0.1 第 5 項定案前，`tools/` 的匯出腳本（如果之後有）應預設排除 `assets/bgm/`。

---

## 1. 曲目身分【原作證實】

這 4 首都出自 2018-12-04 智冠在數位平台發行的 EP《智冠超炫電玩配樂(11): 2001《金庸群俠傳 Online》遊戲原聲帶》。演出者標「群星」，℗ 2018 Soft-World Kaohsiung Music Production Center，共 5 首，約 12 分鐘。
**它們不是 1996 年單機版的配樂**：單機版是另一張專輯（vol.13，27 首，第 1 首〈深林情綿〉）；Online 2（2004）也是另一張（vol.12）。

| 專輯曲序 | 曲名（專輯寫法） | 英文名（Asia Records） | 本專案檔案 | 實測長度 | 響度 (LUFS) | 開頭／結尾靜音 |
|---|---|---|---|---|---|---|
| 1 | 江湖路－田野風光 | Wandering Around The Countryside | `江湖路 田野風光.mp3` | 167.7 s | −12.9 | 0.60 s／163.58 s 起 4.1 s |
| 2 | 群俠聚金庸－天涯循歸途 | Find The Way To Victory | `群俠聚金庸 天涯循歸途.mp3` | 200.3 s | −10.7 | 0.55 s／196.23 s 起 4.1 s |
| 3 | 天涯任我行－刀劍同行 | My Own Way | `天涯任我行 刀劍同行.mp3` | 155.6 s | −11.4 | 0.57 s／150.76 s 起 4.8 s |
| 4 | 風起雲湧震九州 | The Rising Force | **缺**（擁有者沒有提供） | 1:47（只有一份來源列出，未能複核） | — | — |
| 5 | 石破天驚撼武林 | The Powerful Shock | `石破天驚撼武林.mp3` | 124.6 s | −12.2 | 0.46 s／122.40 s 起 2.2 s |

- 長度、響度和靜音位置是 2026-10-18 用 ffprobe／ffmpeg（`ebur128`、`silencedetect -45 dB`）實測的。
- 作曲：Spotify 把〈天涯循歸途〉標為蔡志展（標示是「詞曲」）；其他 3 首查不到個別作曲者【待考證】。
- 來源：
  - https://music-tw.line.me/album/1570960
  - https://music.apple.com/cn/album/…/1447843017
  - https://www.kkbox.com/tw/en/album/L_oHqj4-YWLlTrr3Pq
  - https://www.asia-records.com.tw/product_info.php?info=p568_…
  - https://open.spotify.com/track/1tEhtk8vYzvVRdOgWqgCLq

---

## 2. 原作的播放方式：查不到

下面這些都**沒有找到任何來源**：

- 哪一首在哪個場景播放（登入、城市、野外、戰鬥、魔王）。
- 戰鬥音樂是否會打斷地圖音樂。
- 有沒有勝利或戰敗的短樂句。

搜尋範圍包括繁中、簡中、英文、巴哈姆特、bilibili、貼吧，以及 2018 TCO 音樂會組曲影片（YouTube `5vMB2WvlQzU`，說明欄讀不到）。

確認方法：看官方 bilibili 的 BGM 合集（`BV1bw411C72K`）或 2001–2004 年的實機錄影，或問玩過的人。確認後把 §3 對應列的標記改成【原作證實】並附連結。

已知的旁證只有兩條：

- 原作設定裡有「音樂開關」「音效開關」兩個獨立選項（系統選單截圖 qqnjy_5／yxzls 系列）【原作證實】。這兩項直接對應到 §5 的設定。
- Online 版原聲帶只有 5 首，所以原作不太可能每座城各有主題曲【推測：發行的原聲帶不一定收錄所有遊戲內曲目】。

---

## 3. 場景配置

### 3.1 配置原則【推測】

沒有原作資料，所以只能從曲名的字面意思和實測的響度起伏來推。

- **安全區**（城市、門派，`pk_allowed=false`）共用一首，**危險區**（野外、PK 區）用一首，**戰鬥**另外兩首。這是 5 首曲子的專輯最自然的分法。
- 〈石破天驚撼武林〉的 LRA 只有 2.2 LU，全曲都很滿；它也是 4 首裡最短的。這只算弱證據，但可以拿來當「魔王戰」的理由之一。
- 響度範圍 LRA 本身不能證明曲風。請擁有者試聽後再調整。

### 3.2 配置表

`context` 是程式用的鍵，見 §4。

| 場景 | context | 曲目 | 標記 | 理由 |
|---|---|---|---|---|
| 標題畫面 | `title` | 群俠聚金庸－天涯循歸途 | 【推測】 | 曲名含「群俠…金庸」，是專輯的名稱主題曲；也是唯一有作曲署名的曲子。主題曲放登入畫面是業界慣例 |
| 角色選擇、創角 | `title`（同上，不重播） | 群俠聚金庸－天涯循歸途 | 【推測】 | 與標題連續播放，不切換。原作的出生地選擇畫面（qqnjy_1）有沒有專屬音樂查不到 |
| 西夏（CITY） | `town` | 群俠聚金庸－天涯循歸途 | 【推測】 | 副標「天涯循歸途」＝浪跡天涯後回家，符合城市作為補給和休息據點的意義 |
| 大理（CITY） | `town` | 同上 | 【推測】 | 同上。不做各城專屬曲：只有 5 首，原作很可能共用 |
| 京城（CITY） | `town` | 同上 | 【推測】 | 同上 |
| 少林寺（SECT） | `sect` | 群俠聚金庸－天涯循歸途 | 【推測】 | 門派是 `pk_allowed=false` 的安全區，比照城市。另外開一個 `sect` 鍵，以後有更適合的曲子（例如補到第 4 首）可以只改這一格 |
| 華山（SECT） | `sect` | 同上 | 【推測】 | 同上 |
| 野外（WILD：西夏郊外、大理郊外、京城南郊） | `wild` | 江湖路－田野風光 | 【推測】 | 曲名「田野風光」，英文名 *Wandering Around The Countryside*，最直接對應野外 |
| 血刀洞迷宮／鬼王洞（DUNGEON） | `dungeon` | 風起雲湧震九州 | 【推測】 | 擁有者 2026-10-18 補到第 4 首，依原規劃改用（英文名 *The Rising Force*）。實測 107.0 s、I −11.6 LUFS、頭 0.54 s／尾 4.8 s 靜音 → gain −4.4 dB、start 0.55、loop_end 102.1 |
| 一般戰鬥 | `battle` | 天涯任我行－刀劍同行 | 【推測】 | 副標「刀劍同行」 |
| 魔王戰（任何一個敵方單位的 `ref` 查到 `monsters.json` 的 `kind == "BOSS"`，例如 `m_guiwang`） | `boss` | 石破天驚撼武林 | 【推測】 | 曲名「石破天驚、撼動武林」，全曲響度最平均也最滿 |
| 勝利 | `victory` | **不播任何音樂**，直接回到 §4.3 的恢復流程 | 【推測：原作未見勝利畫面】 | 戰鬥 UI 研究找不到勝利或結算畫面，原聲帶也沒有短樂句。有需要可以只放一個音效（見 AUTHENTIC_UI_SPEC §13），不做音樂 |
| 戰敗、死亡 | `defeat` | 不另配曲；淡出到 0.4 倍音量 1.5 秒，然後照常恢復地區音樂 | 【推測】 | 同上 |
| 大地圖面板（M）、其他面板 | — | 不換曲 | 【推測】 | 面板只是疊在畫面上的視窗 |

### 3.3 資料驅動與覆寫

- 預設依 `data/regions.json` 的 `type` 決定：`CITY→town`、`SECT→sect`、`WILD→wild`、`DUNGEON→dungeon`。
- 個別地區可以在 `regions.json` 加一個可省略的欄位 `"bgm": "<context>"` 覆寫，例如以後某城改用別首曲子。舊資料沒有這個欄位，照 `type` 走即可。
- `ref` 查不到怪物、或查到的 `kind` 不是 `BOSS` → 用 `battle`。
- PvP 切磋（`fight` 對玩家）一律用 `battle`。

---

## 4. 播放器規格（實作用）

### 4.1 結構

- 新增 autoload `BgmPlayer`（`autoload/bgm_player.gd`），掛在 `project.godot` 的 `[autoload]` 最後面，放在 `SceneRouter` 之後。
- 這是**純客戶端表現層**：不送 intent、不進存檔、不影響規則。專用主機（`DEDICATED`，`--headless`）不建立播放器，可用 `DisplayServer.get_name() == "headless"` 判斷，直接 return。
- 建一條音訊匯流排 `Music`（送到 `Master`）。之後的音效走 `SFX` 匯流排（見 AUTHENTIC_UI_SPEC §13）。可以寫在 `default_bus_layout.tres`，或在 `_ready()` 用 `AudioServer.add_bus()` 建立。
- 內部用兩個 `AudioStreamPlayer`（A/B）輪流做交叉淡化，再加一份「暫停中的地區曲」紀錄（曲目鍵＋播放位置）。

```gdscript
const BGM_TRACKS := {
	# key: { path, gain_db, start, loop_end }  start/loop_end 單位秒，來自 §1 的靜音實測
	"tianya_guitu": { "path": "res://assets/bgm/群俠聚金庸 天涯循歸途.mp3", "gain_db": -5.3, "start": 0.55, "loop_end": 196.2 },
	"tianye":       { "path": "res://assets/bgm/江湖路 田野風光.mp3",     "gain_db": -3.1, "start": 0.60, "loop_end": 163.5 },
	"daojian":      { "path": "res://assets/bgm/天涯任我行 刀劍同行.mp3", "gain_db": -4.6, "start": 0.57, "loop_end": 150.7 },
	"shipo":        { "path": "res://assets/bgm/石破天驚撼武林.mp3",       "gain_db": -3.8, "start": 0.46, "loop_end": 122.3 },
	"fengqi":       { "path": "res://assets/bgm/風起雲湧震九州.mp3",       "gain_db": -4.4, "start": 0.55, "loop_end": 102.1 },
}
const CONTEXT_TRACK := {
	"title": "tianya_guitu", "town": "tianya_guitu", "sect": "tianya_guitu",
	"wild": "tianye", "dungeon": "daojian", "battle": "daojian", "boss": "shipo",
}
```

- `gain_db` 把每首曲子拉到大約 **−16 LUFS**，讓切換時不會忽大忽小。算法是 −16 減去 §1 的實測 I 值。
- 公開 API 只有：`play_context(ctx: String)`、`enter_battle(is_boss: bool)`、`leave_battle()`、`set_music_volume(linear: float)`、`set_music_enabled(on: bool)`。

### 4.2 循環

- **不要**用匯入設定的 `loop=true`：每首結尾有 2–5 秒靜音和可能的淡出，直接循環會有一段空白。
- 做法：播到 `loop_end` 時，用另一個播放器從 `start` 重播同一首，兩者交叉淡化 **2.0 秒**。從 `_process` 檢查 `get_playback_position()`，或用一個 `Timer`。
- `.import` 維持 `loop=false`（目前就是）。
- `loop_end` 取靜音開始點往前 0.1 s；結尾的淡出長度沒量過，擁有者試聽後覺得太突兀，可以把 `loop_end` 再往前提。

### 4.3 切換規則

| 事件 | 觸發點（現有檔案） | 行為 |
|---|---|---|
| 進標題 | `ui/game/title/title_screen.gd` `_ready()` | `play_context("title")`；淡入 1.5 s |
| 角色選擇、創角 | `ui/game/char/char_select.gd`、`char_create.gd` | `play_context("title")`。**同曲不重播**：目前已在播同一首就什麼都不做 |
| 進入世界、換地區 | `ui/game/main/main_screen.gd` `apply_view(v)`：讀 `v.region` → `GameData` 的 regions 表 → `type`／`bgm` | `play_context(ctx)`。只有曲目真的改變才切換：交叉淡化 **2.5 s**（舊曲淡出、新曲同時淡入）。同一地區內換房間不做任何事 |
| 開戰 | `main_screen.gd` `open_battle(state)` | 先記住目前地區曲的鍵和 `get_playback_position()`，再 `enter_battle(is_boss)`，其中 `is_boss` 由 `state.units[*].ref` 查 monsters 判斷。地區曲淡出 **0.6 s**（要快，開戰要有衝擊感），戰鬥曲從 `start` 淡入 0.3 s。**例外**：戰鬥曲和地區曲是同一首（鬼王洞裡打一般怪，都是 `daojian`）→ 不中斷、不重播 |
| 戰鬥結束 | `main_screen.gd` `_on_battle_finished()`（按「返回」之後，不是 `close_battle` 收到結果的時候） | `leave_battle()`：戰鬥曲淡出 1.2 s；地區曲**從記住的位置**淡入 2.0 s。記住的位置已超過 `loop_end` 就從 `start` 開始 |
| 戰鬥中換地區（例如逃跑後被傳送） | `apply_view` 在戰鬥期間收到 | 只更新「要恢復的地區曲」，不打斷戰鬥曲；恢復時播新地區的曲子，從 `start` 開始 |
| 戰敗、死亡 | `close_battle(result)` 看結果 | 戰鬥曲壓到 0.4 倍音量 1.5 s；按返回後照上一列恢復（回到記錄點那一區的曲子） |
| 回標題、離開世界 | `system_panel.gd` 的 `navigate` | `play_context("title")`，交叉淡化 2.5 s；清除記住的位置 |
| 視窗失焦 | `NOTIFICATION_APPLICATION_FOCUS_OUT` | 不暫停（原作行為查不到；好友連線時常切視窗）。可加一個「失焦時靜音」選項，預設關 |

- 「恢復到原位置」是本作的設計選擇【推測】。原作是重播還是續播查不到。
- 快速連續觸發（例如 2 秒內進出兩個地區）→ 以最後一個目標為準，正在淡出的播放器直接停掉。
- 播放器在 `SceneRouter` 換畫面時不會被釋放（因為是 autoload），所以畫面切換本身不會讓音樂斷掉。

### 4.4 音量預設與設定

| 設定 | 預設 | 範圍 | 存放 |
|---|---|---|---|
| 音樂開關（原作選項名「音樂開關」【原作證實】） | 開 | 開／關 | `SaveManager.settings_path()`（`user://…/settings.json`）的 `audio.music_on` |
| 音樂音量 | 0.6（約 −4.4 dB） | 0.0–1.0，每格 0.05 | `audio.music_volume` |
| 音效開關（原作「音效開關」【原作證實】） | 開 | 開／關 | `audio.sfx_on` |
| 音效音量 | 0.8 | 0.0–1.0 | `audio.sfx_volume` |
| 失焦時靜音 | 關 | 開／關 | `audio.mute_unfocused` |

- 音量套在 `Music` 匯流排上：`AudioServer.set_bus_volume_db(bus, linear_to_db(v))`；`v == 0` 時直接 `set_bus_mute(true)`。
- 開關關閉時：匯流排靜音，**播放器仍然照規則切換曲目和位置**，重新打開時直接接上當下該播的曲子，不必重新判斷場景。
- UI 位置：`ui/game/panels/system_panel.gd`，照原作系統選單的文字按鈕排列（見 AUTHENTIC_UI_SPEC §8.6）：「音樂開關」「音效開關」各一個開／關按鈕，旁邊各一條 `HSlider`。標題畫面也要能調整（系統面板要進了世界才看得到），在 `title_screen.gd` 角落放一個小的「音樂」開關即可。
- 指令列參數（方便測試）：`-- --no-music` 強制關閉音樂，不寫入設定。

### 4.5 測試

- `tests/` 裡加一個無頭測試，只驗證**狀態機**：用假的 `play_context`／`enter_battle`／`leave_battle` 序列，檢查最後的目標曲目鍵和記住的位置。不要在 CI 實際播放音訊，無頭模式下也不建立播放器。
- 手動測試清單：
  - 標題 → 創角 → 進西夏：同一首，不中斷。
  - 西夏 → 西夏郊外：交叉淡化到〈田野風光〉。
  - 野外遇敵 → 戰鬥 → 返回：〈田野風光〉從原位置接續。
  - 鬼王洞一般怪：不中斷。
  - 鬼王：換成〈石破天驚〉。
  - 音量 0：完全無聲。
  - 開關切換：可正確恢復。
- 依使用者規則：測試跑完要把 Godot 程序關掉。

---

## 5. 待辦與待決

| # | 項目 | 誰決定 |
|---|---|---|
| 1 | 擁有者試聽後確認 §3.2 的配置，尤其是「城市與標題共用一首」以及「鬼王洞用刀劍同行」 | 擁有者 |
| 2 | ~~能否取得第 4 首〈風起雲湧震九州〉~~ 已取得（2026-10-18），`dungeon` 已改用 `fengqi` | 完成 |
| 3 | 找到原作使用場景的證據後，把 §3.2 對應列改成【原作證實】 | 研究 |
| 4 | 公開發行前替換全部曲目（GDD §0.1 第 5 項） | 擁有者 |
| 5 | 實作 `autoload/bgm_player.gd`、`Music`／`SFX` 匯流排、系統面板的設定 | 開發 |
