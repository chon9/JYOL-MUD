# 《JY-Mini OL》技術架構文件 Technical Architecture

> 版本：v0.2（草案），對應 GDD v0.2（`docs/GDD.md`）
> v0.2 變更：Steam 初始化定案為單一路徑（2.1）；GodotSteam 以 vendored 方式固定版本（2.2）；渲染器改為 M0 四格矩陣實測（1.1）；新增 8 人等待模式節奏（10.7）、主機離線策略（8.6）；角色護照改寫為「僅在好友間可察覺竄改」（8.4）；新增資料表 era 分期與規則設定檔（5.5、5.6），取代舊的 `content_era` A/B/LATER 三段式。
> **範圍更新（擁有者決定，優先於本文與 GDD 舊敘述）**：本作不限於 1.0。原作同一產品線後續的**官方**資料片（神鵰大俠、決戰光明頂、勇闖俠客島、葵花寶典、喬峰傳奇、小寶闖情關、書劍江山、冷月飛狐、郭靖大俠、碧血沙場、懷舊版的明教／桃花島等門派）都可以收錄。仍然排除：無關的「2.0」遊戲、商城付費機制、現代私服的數值膨脹。基底是 1.0 經典核心循環，後期官方內容以後續里程碑加入；版本之間規則衝突處做成每個世界可切換的選項（5.5、5.6）。
> 引擎：Godot 4.6.3 stable（標準版，非 .NET）
> Steam：GodotSteam GDExtension 4.23（Steamworks SDK 1.65），開發期 AppID 480（Spacewar）
> 語言：本文以繁體中文撰寫，程式識別字一律使用英文
> 文件日期：2026-10-17

---

## 0. 閱讀說明

### 0.1 標記

本文沿用 GDD 的標記，另外新增一個技術標記：

| 標記 | 意義 |
|---|---|
| 【已證實】 | 已在 GodotSteam 官方文件、Godot 官方文件或 release 頁面核對過 |
| 【API待驗證】 | 名稱或簽名是根據文件或慣例推得，但本文撰寫時沒有逐字核對。第一次寫到時請在編輯器內用「說明文件搜尋」或 `ClassDB` 確認，錯了就改本文 |
| 【推論】 | 合理的工程判斷，不是文件明寫的事實 |
| 【設計提案】 | 本作自訂的架構決策 |

所有 【API待驗證】 項目都彙整在第 17 章，M0 階段要逐條勾銷。

### 0.2 與 GDD 的對齊狀態

GDD v0.2 已改用 `.json` 資料表與本文的七個 Autoload 名稱。下列項目也已在 GDD v0.2 同步；之後若兩份文件又出現差異，記在這張表，以本文為準：

| 項目 | 本文決定 | GDD 同步位置 |
|---|---|---|
| 版本標記 `era` | 每個資料片一個 era id（`"1.0A"`、`"1.0B"`、`"gmdk"`……），世界以 `enabled_eras` 清單決定啟用哪些（5.5） | 4.4、7.2／8.2／9.2 的 era 欄、13.4、附錄 A |
| 規則衝突 | 集中成 `rule_profile`（死亡規則、屍體時限、叛派是否減半基本武功、學點上限、坐牢、自修上限）（5.6） | 0.1 第 3 項、3.1、4.2、6.4、6.5、附錄 A |
| 後期分支門派拜入 | `sects_enabled`，與 `enabled_eras` 分開（5.5.1） | 1.2、13.2 |
| Steam 初始化 | `steamInitEx(APP_ID, false)`，自動初始化與 embed callbacks 皆關（2.1） | 12.2 |
| 開房、intent、同步 | `create_host(0)`、`c2s_intent`、`battle_gauges` + 1 Hz 校正（6.3、10.6、13.1） | 12.3、12.4 |
| 存檔與主機離線 | `characters/<identity>/<char_id>.json`（8.1）；`host_offline_policy`（8.6） | 12.5、12.6 |

---

## 1. 版本鎖定與工具鏈

| 項目 | 版本 | 備註 |
|---|---|---|
| Godot | **4.6.3 stable**，標準版 | 從 godotengine.org 下載獨立版編輯器。**不要用 Steam 上的 Godot**：它自帶的 `steam_api64.dll` 版本可能過舊，會讓 GodotSteam GDExtension 載入失敗（4.6.3 推出後已有案例；GodotSteam 4.20 以後會自動偵測）【已證實】 |
| GodotSteam | **GDExtension 4.23**（SDK 1.65） | 4.23.1 在 Godot 商店上被標為 unstable，暫不使用。商店標示的最低 Godot 版本是 4.4.1，所以 4.6.3 可用【已證實】。若 4.23 在 4.6.3 上出現問題，退回 **4.19.1**（官方標示對應 Godot 4.6.3 / SDK 1.64） |
| GodotSteam 下載來源 | Codeberg release，或 Godot 商店（store.godotengine.org） | GitHub repo 已於 2026-10-05 封存，GitHub 上的檔案「日後會移除」【已證實】。所以**下載一次後就把整個 addon 提交進版控**，之後不再依賴外部下載（2.2） |
| GodotSteam 授權 | 目前為 MIT | 2026 年 5 月曾宣布改用自訂授權，6 月「暫時取消」，作者表示到 Godot 5 前後可能再改【已證實】。**每次升級都要重看 LICENSE**，並把當時的 LICENSE 原文一起提交（2.2） |
| GodotSteam 更新方式 | **手動**，不用外掛內建的更新器 | 4.23.1 加入了「專案 → 工具」裡的外掛更新器【已證實】。它會改掉我們固定的版本，所以不用；升級一律照 2.2 的流程 |
| 多人連線 | GodotSteam 內建 `SteamMultiplayerPeer`（4.17 起） | **絕對不要**另外安裝 ExpressoBits 的 steam-multiplayer-peer，兩者的類別註冊會衝突【已證實】 |
| 單元測試 | 自帶執行器 `tests/run_tests.gd`（取代 GUT，見 15.2、17 #19） | 沒有外部相依；`--script` 模式下 Autoload 會初始化（17 #18） |
| 字型 | LXGW WenKai TC v1.522、Noto Sans TC / Noto Serif TC | 皆為 OFL-1.1，出貨前確認 OFL.txt |
| 版本控制 | Git（建議 `git init`，`.godot/` 加入 `.gitignore`） | 目前專案資料夾還不是 git repo |

### 1.1 渲染器與 Steam 覆蓋介面

本作以文字和 2D 為主，用不到 Forward+ 的功能，所以**暫定 Compatibility 渲染器**。但「哪個渲染器下 Steam 覆蓋介面最穩」沒有可靠資料，M0 必須實測後再定案：

- GodotSteam 文件指出 Steam 覆蓋介面「自從 Vulkan 之後就不太穩定」【已證實：文件說法】；覆蓋介面打不開，就等於不能用 Steam 邀請好友，所以這是 M0 的阻斷項目。
- Godot 4.6 起，Windows 上 Forward+／Mobile 新專案的預設 RenderingDevice 驅動可能已改為 **D3D12**（專案設定 `rendering/rendering_device/driver.windows`）【API待驗證：在 4.6.3 建立新專案後直接查看該設定值】。本作的專案是新建的，所以不能假設是 Vulkan。
- Compatibility 在 Windows 上走 OpenGL 3（`rendering/gl_compatibility/driver.windows`），驅動不支援時可能退回 ANGLE（底層是 D3D11）【API待驗證：設定名稱與退回條件】。覆蓋介面掛的是哪一層 API，結果可能不同。

**M0 實測矩陣**（每格都要測：Shift+Tab 開覆蓋介面、`activateGameOverlayInviteDialog` 邀請對話框、好友清單「加入遊戲」；一律從 Steam 用戶端啟動匯出版）：

| 渲染器 | 驅動 | 設定方式 |
|---|---|---|
| Compatibility | OpenGL 3 | 預設 |
| Compatibility | ANGLE | 命令列 `--rendering-driver opengl3_angle`【API待驗證】 |
| Forward+ | Vulkan | `--rendering-method forward_plus --rendering-driver vulkan` |
| Forward+ | D3D12 | `--rendering-method forward_plus --rendering-driver d3d12` |

選擇規則：三項都正常的組合裡，選 Compatibility 優先；全部都有問題時，改用「遊戲內好友清單 + `inviteUserToLobby`」繞過覆蓋介面【API待驗證：函式名稱】。結果記到第 17 章 #23。

---

## 2. GodotSteam 安裝步驟（Windows）

1. **安裝 Godot 4.6.3**：下載 `Godot_v4.6.3-stable_win64.exe`（標準版），放在固定資料夾，例如 `C:\Tools\Godot\`。
2. **建立專案**：路徑 `k:\Project\JY-Mini OL\game\`（建議把 Godot 專案放在 `game/` 子資料夾，`docs/` 與 `design_tables/` 留在外層）。渲染器暫選 Compatibility（M0 實測後定案，見 1.1）。
3. **下載 GodotSteam GDExtension 4.23**：從 Codeberg 的 GodotSteam release 頁或 Godot 商店下載 GDExtension 版本的壓縮檔（實際檔名未核對【API待驗證】）。
4. **解壓縮**：把壓縮檔裡的 `addons/godotsteam/` 整個資料夾放到 `res://addons/godotsteam/`。裡面應該有 `godotsteam.gdextension`、各平台的二進位檔，以及 `steam_api64.dll`（Windows）。接著照 2.2 記錄版本、雜湊與授權，**整個資料夾提交進 git**。
5. **重新啟動編輯器**。GDExtension 只在編輯器啟動時載入。
6. **確認載入成功**：開「說明 → 搜尋說明」，搜尋 `Steam` 與 `SteamMultiplayerPeer`，兩個類別都要找得到。或在任一腳本執行 `print(Engine.has_singleton("Steam"))`，應印出 `true`【API待驗證：GDExtension 單例是否透過 `Engine.has_singleton` 回報】。
7. **專案設定**：開啟「專案 → 專案設定」，打開「進階設定」，到 **Steam → Initialization**（GodotSteam 4.14 起才有）：
   - `app_id` 可以填 `480`（只當作紀錄；實際以 `SteamManager.APP_ID` 傳給 `steamInitEx` 為準）
   - **自動初始化（initialize on startup）必須關閉**
   - **embed callbacks 必須關閉**
   - 理由見 2.1。設定項的確切名稱【API待驗證】。
8. **建立 `steam_appid.txt`**（見第 3 章）。
9. **確認 Steam 用戶端已開啟並登入**，然後按 F5。`SteamManager` 會印出 `Steam OK: <你的名字> (<SteamID64>)`。
10. **匯出測試**（M0 就要做一次，不要拖到最後）：
    - 「專案 → 匯出」，新增 Windows Desktop 預設。
    - 「資源」分頁的「要匯出的非資源檔案篩選」加上 `*.json`，確保資料表一定被打包【推論：Godot 4 有 JSON 資源載入器，通常會自動包含，加上篩選只是保險】。
    - 匯出到 `build/win/`，確認 `steam_api64.dll` 已被複製到 exe 旁邊（GDExtension 的相依檔案設定應會自動處理【API待驗證】；沒有的話手動複製）。
    - 手動把 `steam_appid.txt` 複製到 exe 旁邊。

**不要做的事**：
- 不要裝 GodotSteamKit（它會自動加一個 `steamworks.gd` autoload，授權也比較嚴格），本作自己寫 `SteamManager`。
- **不要安裝 ExpressoBits 的 steam-multiplayer-peer**（Asset Library 上也叫 SteamMultiplayerPeer）。GodotSteam 4.17 起已內建同名類別，兩者同時存在會造成類別註冊衝突；ExpressoBits 版本也已暫停開發【已證實】。網路上很多舊教學是用 ExpressoBits 版本寫的，照抄前先確認。
- 不要使用 4.23.1 的外掛更新器（1 章）。

### 2.1 Steam 初始化：只用一條路徑（定案）

GodotSteam 有兩種初始化方式：專案設定的自動初始化（4.14 起），或程式手動呼叫 `steamInitEx()`。**兩種同時開會初始化兩次**；而且自動初始化搭配 embed callbacks 曾讓編輯器崩潰（4.14–4.16），直到 4.23 才宣告修好【已證實】。

**本作定案：在 `SteamManager`（autoload）的 `_ready()` 手動呼叫 `Steam.steamInitEx(APP_ID, false)`，專案設定的自動初始化與 embed callbacks 都關閉，`run_callbacks()` 在 `SteamManager._process()` 每幀手動呼叫。** 理由：

1. **要能失敗後退回單機**：手動呼叫才拿得到 `{status, verbal}`，決定要不要灰掉 Steam 按鈕（7.3）；`--no-steam` 參數也只能在手動路徑上實作（測試、bot、無介面主機都需要）。
2. **避開剛修好的崩潰組合**：4.23 才修好「自動初始化＋embed」，而 4.23 本身發布不到兩週。手動路徑不碰那段程式碼。
3. **時機可控**：初始化發生在 `GameData` 之後、`NetworkManager` 之前（4.2 的 autoload 順序），冷啟動邀請 `+connect_lobby` 也在同一個函式裡處理。
4. **callback 不會因暫停而停**：`SteamManager` 的 `process_mode = ALWAYS`，文件要求 callback 不能放在會被暫停的節點【已證實】。embed 模式的呼叫時機由外掛決定，我們看不到。

GDD 12.2 寫的 `steamInitEx(480, true)`（embed = true）已改成 `false`（GDD v0.2 已同步）。

### 2.2 GodotSteam 的版本固定（vendoring）

GitHub 已封存、檔案會被移除，授權也可能再變，所以 addon **整個提交進 repo**，不靠任何人「再去下載一次」：

1. `res://addons/godotsteam/` 整個資料夾（含 `.gdextension`、各平台二進位檔、`steam_api64.dll`）加入 git。`.gitignore` 不可排除 `*.dll`／`*.so`。二進位檔若太大可用 Git LFS，但要在 README 寫明。
2. 在同一資料夾新增 `res://addons/godotsteam/VENDOR.md`，內容固定為：
   - 版本：`GodotSteam GDExtension 4.23`（Steamworks SDK 1.65）
   - 來源網址：實際下載的 Codeberg release 或 Godot 商店頁面
   - 下載日期
   - 原始壓縮檔的 SHA-256，以及每個二進位檔的 SHA-256（PowerShell：`Get-FileHash -Algorithm SHA256 <檔案>`；Git Bash：`sha256sum <檔案>`）
   - 當時的授權：MIT，並把 LICENSE 原文存成 `res://addons/godotsteam/LICENSE.txt`
3. 原始壓縮檔另存一份在 repo 外的備份位置（例如 `k:\Project\JY-Mini OL\vendor_archive\`，不進 `res://`），以防日後兩個下載來源都消失。
4. 另寫一個小檢查腳本 `tools/check_vendor.ps1`（M0 時手動跑，之後每次升級跑）：比對二進位檔雜湊與 `VENDOR.md` 是否一致，防止有人誤用更新器覆蓋。
5. **升級流程**：開新分支 → 下載新版 → 重新計算雜湊 → **逐字重讀 LICENSE**，授權若不再是 MIT，先停下來由擁有者決定 → 跑第 17 章的 Steam 項目與 15.4 手動清單 → 合併。退路版本是 4.19.1（1 章）。

---

## 3. steam_appid.txt

- 內容只有一行：`480`（不要有 BOM，換不換行都可以）。
- 放置位置：
  - **編輯器執行時**：放在專案根目錄（與 `project.godot` 同層）。
  - **匯出後**：放在 exe 旁邊。
- 在匯出篩選裡**排除** `steam_appid.txt`，不要被包進 `.pck`（Steam API 只看工作目錄裡的實體檔案）。
- 它的作用：不從 Steam 用戶端啟動時，告訴 Steam API 這是哪個 AppID。GodotSteam 文件把它列為「不建議」的 AppID 指定方式之一，但本作同時在 `steamInitEx(480)` 裡傳 AppID，它只是保險【已證實：文件列出四種方式，環境變數與 steam_appid.txt 標為 not recommended】。
- **正式上架後**（取得正式 AppID）：發行版**不要**附 `steam_appid.txt`，並把 `APP_ID` 常數改掉。開發版可以繼續附。

---

## 4. 專案結構

### 4.1 `res://` 資料夾

```
res://
├─ project.godot
├─ steam_appid.txt                 # 不打包進 pck
├─ addons/
│  ├─ godotsteam/                  # GodotSteam GDExtension 4.23，整個提交進 git（2.2）
│  │  ├─ VENDOR.md                 # 版本、來源、SHA-256、授權紀錄
│  │  └─ LICENSE.txt               # 下載當時的授權原文
│  └─ （不使用 GUT：改用自帶的 tests/run_tests.gd，見 15.2）
├─ autoload/                       # 全部的 Autoload（見 4.2）
│  ├─ game_data.gd
│  ├─ steam_manager.gd
│  ├─ save_manager.gd
│  ├─ network_manager.gd
│  ├─ world_server.gd
│  ├─ client_state.gd
│  └─ scene_router.gd
├─ core/                           # 純邏輯（RefCounted，不碰場景樹、不碰 Autoload）→ 可單元測試
│  ├─ protocol.gd                  # class_name Protocol：協定版本、intent/event 名稱常數
│  ├─ data/                        # 資料表載入與驗證
│  │  ├─ data_loader.gd            # class_name DataLoader
│  │  └─ data_schema.gd            # 欄位型別表（哪些欄位要轉 int）
│  ├─ model/                       # 資料模型（to_dict / from_dict）
│  │  ├─ character.gd
│  │  ├─ inventory.gd
│  │  ├─ skill_book.gd             # 基本武學 + 特殊武功 + 門派技能
│  │  └─ world_state.gd
│  ├─ rules/                       # 遊戲規則（GDD 的公式都放這裡）
│  │  ├─ formulas.gd               # 衍生數值、學點、傷害、命中、ATB 速度
│  │  ├─ learning.gd               # 消點、自修、讀書、實戰上限
│  │  ├─ sect_rules.gd             # 入門、門規、叛派、開除
│  │  ├─ morality_pk.gd            # 善惡、殺氣、PK值
│  │  ├─ death_rules.gd            # 三種死亡規則（rule_profile.death_rule，5.6）
│  │  └─ requirements.gd           # 共用的 requires 條件判定
│  ├─ battle/
│  │  ├─ battle.gd                 # class_name Battle：戰鬥狀態機（第 10 章）
│  │  ├─ battle_unit.gd
│  │  ├─ battle_grid.gd            # 12×8 格、阻擋、逃跑格
│  │  ├─ battle_ai.gd              # 怪物 AI、斷線玩家代打
│  │  └─ status_effects.gd
│  └─ util/
│     ├─ seeded_rng.gd             # 可存檔的 RNG
│     └─ id.gd                     # 角色/物品實例 id 產生器
├─ server/                         # 只在主機上運作的系統（由 WorldServer 持有）
│  ├─ session.gd                   # 一位連線玩家：peer_id、identity、character、速率限制
│  ├─ region_system.gd             # 區格、移動、踩地雷、場景內人物
│  ├─ battle_system.gd             # 管理所有進行中的 Battle
│  ├─ chat_system.gd               # 8 個頻道、耗水
│  ├─ mail_system.gd               # 飛鴿傳書
│  ├─ corpse_system.gd             # 屍體時限依 rule_profile.corpse_window（5.6）
│  ├─ party_system.gd
│  ├─ guild_system.gd
│  ├─ quest_system.gd
│  ├─ economy_system.gd            # 商店、錢莊、交易視窗
│  ├─ jail_system.gd               # 坐牢（累計上線時間；rule_profile.jail_enabled）
│  ├─ timer_system.gd              # 世界時鐘、PK值遞減、腐壞（惰性計算）
│  └─ event_router.gd              # 事件依範圍送給哪些 peer（第 11 章）
├─ net/                            # M0 不建立：三種傳輸各只有幾行（換 multiplayer_peer），直接寫在 NetworkManager 內（13.2）
├─ data/                           # 內容資料表（JSON，第 5 章）
│  ├─ attributes.json
│  ├─ basic_skills.json
│  ├─ sects.json
│  ├─ sect_rules.json
│  ├─ martial_arts.json            # 含 moves
│  ├─ masters.json
│  ├─ regions.json
│  ├─ maps/                        # 每個區格一個檔：xixia.json、dali_wild.json ……
│  ├─ npcs.json
│  ├─ monsters.json
│  ├─ items.json
│  ├─ quests.json
│  ├─ status_effects.json
│  ├─ text_templates.json          # 戰報與系統訊息模板
│  ├─ eras.json                    # 版本／資料片清單（5.5）
│  ├─ rule_profiles.json           # 規則設定檔預設組合（5.6）
│  ├─ patches/                     # 後期 era 對既有資料列的修改（5.5.3）
│  └─ server_options.default.json
├─ ui/                             # 場景（第 12 章）
├─ assets/
│  ├─ fonts/
│  ├─ tiles/                       # Kenney 等 CC0
│  ├─ portraits/                   # nessava Ancient Chinese Character Pack 1
│  ├─ icons/                       # game-icons.net（CC BY 3.0）
│  └─ LICENSES/                    # 每個素材包的授權檔與來源網址
├─ tests/
│  ├─ run_tests.gd                 # 自帶的測試執行器（SceneTree 腳本，有失敗就結束碼 1）
│  ├─ test_case.gd                 # 斷言、暫存資料夾等共用工具；測試檔 extends 它
│  ├─ bots/                        # bot 客戶端腳本（15.3）
│  ├─ unit/
│  ├─ integration/
│  └─ fixtures/
└─ tools/
   ├─ data_lint.gd                 # 無介面資料檢查（第 15 章）
   ├─ balance_sim.gd               # 無介面平衡模擬
   ├─ net_smoke.gd                 # 無介面連線冒煙測試
   └─ check_vendor.ps1             # 比對 GodotSteam 二進位檔雜湊（2.2）
```

專案外層（不在 `res://` 內）：

```
k:\Project\JY-Mini OL\
├─ docs\            GDD.md、TECH_ARCH.md
├─ design_tables\   （選用）企劃用 TSV，轉成 game/data/*.json
├─ game\            Godot 專案（res://）
└─ build\           匯出結果（不進版控）
```

### 4.2 Autoload

依下列**順序**登錄（順序就是初始化順序，後面的可以依賴前面的）：

| # | 名稱 | 檔案 | 職責 | process_mode |
|---|---|---|---|---|
| 1 | `GameData` | `autoload/game_data.gd` | 啟動時載入 `res://data/` 全部 JSON，建立以 id 為鍵的唯讀登錄表；計算內容雜湊 `content_hash` | INHERIT |
| 2 | `SteamManager` | `autoload/steam_manager.gd` | Steam 初始化、`run_callbacks()`、大廳建立/加入/搜尋/邀請、冷啟動 `+connect_lobby` | **ALWAYS** |
| 3 | `SaveManager` | `autoload/save_manager.gd` | 資料根目錄（`core/util/data_root.gd`：`--data-root`＞`data_root.txt`＞`user://`）下的世界存檔、角色檔、角色護照、本機設定檔；原子寫入與備份輪替 | ALWAYS |
| 4 | `NetworkManager` | `autoload/network_manager.gd` | 選擇並建立傳輸層（Offline / ENet / Steam）、連線生命週期、握手、`send_intent()` | ALWAYS |
| 5 | `WorldServer` | `autoload/world_server.gd` | **權威遊戲邏輯**。只有 `multiplayer.is_server()` 時才啟動；接收 `c2s_*` RPC | ALWAYS |
| 6 | `ClientState` | `autoload/client_state.gd` | 客戶端的狀態鏡像（自己的角色表、目前場景、戰鬥畫面資料、訊息紀錄）；接收 `s2c_*` RPC 並發出 signal 給 UI | ALWAYS |
| 7 | `SceneRouter` | `autoload/scene_router.gd` | 切換主要畫面（標題 → 大廳 → 創角 → 主畫面 ↔ 戰鬥） | ALWAYS |

**為什麼 RPC 一定放在 Autoload**：Godot 的高階 RPC 是用「節點路徑 + 方法」對應的，所有 peer 上的節點路徑和 RPC 設定必須一致。Autoload 在每個 peer 上都固定是 `/root/WorldServer`、`/root/ClientState`，所以不會發生路徑對不上的問題。規則：

- **客戶端 → 主機** 的 RPC 只寫在 `WorldServer`，方法名以 `c2s_` 開頭，標註 `@rpc("any_peer", ...)`。
- **主機 → 客戶端** 的 RPC 只寫在 `ClientState`，方法名以 `s2c_` 開頭，標註 `@rpc("authority", ...)`（只有主機能呼叫）。
- UI 場景裡**不寫任何 RPC**。

`WorldServer` 的腳本在每個 peer 上都存在（RPC 設定要一致），但在客戶端上它的 `_process` 什麼都不做，`world` 也是 null。

### 4.3 分層原則

```
UI 場景  ──讀取/訂閱──▶  ClientState  ◀──s2c RPC──  WorldServer（主機）
   │                                                    ▲
   └──── NetworkManager.send_intent() ────c2s RPC───────┘
                                                        │
                                       server/*  ──呼叫──▶ core/rules、core/battle（純邏輯）
                                                        │
                                                   GameData（唯讀）、SaveManager
```

- `core/` 不能引用任何 Autoload，所有依賴（資料登錄表、RNG）由參數傳入。這樣單元測試和無介面工具（`--script` 模式）都能直接使用。
- `server/` 只在主機上存在，可以使用 `GameData`、`SaveManager`。
- UI 永遠不直接改遊戲狀態，只送 intent。**單機模式也一樣走 intent**，確保單機與連線是同一條程式路徑。

---

## 5. 資料格式（`res://data/*.json`）

### 5.1 決策

- **格式**：JSON，UTF-8（無 BOM）。
- **檔案外框**：每個檔案都是

  ```json
  { "table": "sects", "version": 1, "rows": [ { ... }, { ... } ] }
  ```

  `rows` 是陣列，每列一定有字串 `id`（英文 snake_case）。`GameData` 載入時建立 `Dictionary[id → row]`，重複 id 直接報錯。
- **顯示文字**：中文名稱、描述直接寫在資料裡（`name`、`desc`）。本作只做繁體中文，不做 `tr()` 翻譯表（YAGNI）。
- **版本標記**：每列**必須**有 `era`（例如 `"1.0A"`、`"1.0B"`、`"gmdk"`），值必須是 `eras.json` 裡的 id。世界存檔的 `enabled_eras` 決定哪些列在這個世界生效。完整規則見 5.5。
- **標記欄**：每列可有 `src` 欄位，記錄 GDD 標記（`"verified"`、`"later"`、`"unverified"`、`"proposal"`），方便 data_lint 列出所有待考證數值。

### 5.2 JSON 的型別陷阱（重要）

Godot 4 的 `JSON.parse_string()` 會把**所有數字解析成 float**。所以：

1. `core/data/data_schema.gd` 為每個表列出整數欄位，`DataLoader` 載入時逐一 `int()` 轉換。
2. **SteamID64 一律存成字串**。SteamID64 約 7.6×10¹⁶，超過 JSON/float 能精確表示的 2⁵³（約 9×10¹⁵），存成數字會被截斷。
3. 存檔（第 8 章）也遵守同樣規則：`from_dict()` 負責轉型。

### 5.3 結構範例

**sects.json**（GDD 3.2）

```json
{
  "table": "sects", "version": 1,
  "rows": [
    {
      "id": "shaolin",
      "name": "少林",
      "home_city": "jingcheng",
      "gate_region": "shaolin",
      "gender": ["M"],
      "join_requires": [
        { "type": "morality_min", "value": -99 },
        { "type": "no_sect" },
        { "type": "not_enemy_of", "sect": "shaolin" }
      ],
      "sect_skill": "foxa",
      "sect_skill_name": "佛法",
      "sect_skill_effect": { "trigger": "on_defend", "effect": "def_up", "value": 0.3 },
      "sect_skill_cost": ["jing", "neili"],
      "enforcer": true,
      "jail_region": "shaolin_jail",
      "expel_rules": [ { "type": "killing_intent_over", "value": 2000 } ],
      "era": "1.0A",
      "src": "verified"
    }
  ]
}
```

**martial_arts.json**（GDD 4.4；招式內嵌在武功裡，載入時另建 `moves` 索引）

```json
{
  "table": "martial_arts", "version": 1,
  "rows": [
    {
      "id": "sl_changquan",
      "name": "少林長拳",
      "sect_id": "shaolin",
      "category": "FIST",
      "base_skill": "basic_fist",
      "difficulty": 0.9,
      "self_study_until": 0,
      "party_size": 0,
      "requires": [ { "type": "sect", "sect": "shaolin" } ],
      "era": "1.0A",
      "src": "proposal",
      "moves": [
        {
          "id": "sl_cq_1", "name": "黑虎掏心", "unlock_level": 1,
          "power": 20, "range": 1, "aoe": "SINGLE",
          "cost_inner": 0, "cost_jing": 0,
          "status": "", "status_chance": 0.0,
          "flavor": "move_fist_basic"
        },
        {
          "id": "sl_cq_2", "name": "雙龍搶珠", "unlock_level": 30,
          "power": 32, "range": 1, "aoe": "SINGLE",
          "cost_inner": 5, "cost_jing": 0,
          "status": "", "status_chance": 0.0,
          "flavor": "move_fist_basic"
        }
      ]
    }
  ]
}
```

`flavor` 指向 `text_templates.json` 的模板 key，不直接存整句文字（見第 11 章）。

**masters.json**（師父能教到幾級；GDD 4.2）

```json
{
  "table": "masters", "version": 1,
  "rows": [
    { "id": "m_liangfa_fuhu", "npc_id": "n_liangfa", "art_id": "hs_fuhuquan", "cap": 30,
      "requires": [ { "type": "sect", "sect": "huashan" } ], "era": "1.0A", "src": "verified" }
  ]
}
```

**monsters.json**（GDD 7.3）

```json
{
  "table": "monsters", "version": 1,
  "rows": [
    {
      "id": "m_wolf",
      "name": "野狼",
      "kind": "MONSTER",
      "alignment": "NEUTRAL",
      "stats": { "qi": 250, "neili": 0, "str": 18, "con": 16, "agi": 22, "cal": 15, "guts": 20 },
      "arts": [ { "art": "mon_bite", "level": 10 } ],
      "weapon_power": 6, "armor_power": 2,
      "combat_xp_ref": 500, "learn_points": 6, "combat_xp": 12,
      "drops": [ { "item": "r_wolfskin", "chance": 0.5, "min": 1, "max": 1 } ],
      "money": { "min": 0, "max": 5 },
      "morality_on_kill": 0, "killing_intent_on_kill": 0,
      "ai": "melee_basic",
      "era": "1.0A", "src": "proposal"
    }
  ]
}
```

**items.json**（GDD 9.2、9.3）

```json
{
  "table": "items", "version": 1,
  "rows": [
    { "id": "w_dandao", "name": "單刀", "tab": "WEAPON", "slot": "WEAPON", "weapon_type": "BLADE",
      "atk": 10, "def": 6, "weight": 3, "price": 150, "sell_ratio": 0.3,
      "spoil_days": 0, "stack": 1, "effects": [], "shop_ok": true, "era": "1.0A", "src": "verified" },
    { "id": "c_jingyao", "name": "精藥水", "tab": "OTHER", "slot": "", "weight": 1, "price": 30,
      "spoil_days": 0, "stack": 99,
      "effects": [ { "type": "restore", "stat": "jing", "value": 50 } ],
      "usable_in_battle": true, "era": "1.0A", "src": "verified" },
    { "id": "c_mantou", "name": "饅頭", "tab": "OTHER", "weight": 1, "price": 5,
      "spoil_days": 3, "stack": 20,
      "effects": [ { "type": "restore", "stat": "food", "value": 20 } ], "era": "1.0A", "src": "proposal" }
  ]
}
```

**regions.json**（世界區格清單，GDD 7.2）＋ **maps/<region_id>.json**（區格內容）

```json
{
  "table": "regions", "version": 1,
  "rows": [
    { "id": "xixia_wild", "name": "西夏郊外", "type": "WILD", "city": "xixia",
      "map": "res://data/maps/xixia_wild.json", "suggested_xp": [0, 2000],
      "night_closed": [], "pk_allowed": true, "era": "1.0A", "src": "verified" }
  ]
}
```

```json
{
  "region_id": "xixia_wild",
  "desc": "西夏城外一片荒原，風沙捲著枯草，遠處偶有狼嚎。",
  "size": [24, 16],
  "tiles": [
    "########################",
    "#......~~~......T......#",
    "#..P...~~~.............#"
  ],
  "legend": { "#": "BLOCK", ".": "GROUND", "~": "WATER", "T": "TREE", "P": "FIELD" },
  "exits": [
    { "at": [0, 8], "to": "xixia", "to_at": [23, 8], "label": "東門" }
  ],
  "encounter": {
    "rate_per_step": 0.06,
    "table": [ { "monster": "m_rabbit", "w": 50, "count": [1, 2] },
               { "monster": "m_wolf", "w": 20, "count": [1, 1] } ]
  },
  "npcs": [ { "npc": "n_chenjialuo", "at": [5, 3] } ],
  "battle_bg": "res://assets/tiles/bg_grass.png",
  "escape_tiles_hint": 2
}
```

**npcs.json**（GDD 7.3；功能 NPC、師父、商人、任務、惡方 NPC）

```json
{
  "table": "npcs", "version": 1,
  "rows": [
    {
      "id": "n_taoyun",
      "name": "陶耘",
      "kind": "QUEST",
      "region": "dali_wild",
      "alignment": "GOOD",
      "talk": "npc_taoyun_hello",
      "services": [ "QUEST", "TEACH_LIFE" ],
      "quests": [ "q_rice" ],
      "teach_life": [ { "skill": "life_farming", "cap": 30, "price": 0 } ],
      "shop": null,
      "hostile_if": [],
      "combat": null,
      "schedule": { "night_absent": false },
      "era": "1.0A", "src": "verified"
    },
    {
      "id": "n_yeerniang",
      "name": "葉二娘",
      "kind": "EVIL_NPC",
      "region": "xixia",
      "alignment": "EVIL",
      "talk": "npc_yeerniang_hello",
      "services": [],
      "hostile_if": [ { "type": "morality_min", "value": 1 } ],
      "combat": { "monster_template": "boss_yeerniang" },
      "era": "1.0A", "src": "verified"
    }
  ]
}
```

**requires / hostile_if 條件**：所有條件共用同一套 `{ "type": ..., ... }` 格式，由 `core/rules/requirements.gd` 判定。M1 支援的 type：`morality_min`、`morality_max`、`sect`、`no_sect`、`not_enemy_of`、`gender`、`attr_min`、`skill_min`、`combat_xp_min`、`pk_max`、`unmarried`、`quest_flag`、`killing_intent_max`、`era_enabled`（5.5.2）、`sect_enabled`（依 `server_options.sects_enabled` 判定，5.5.1）、`rule`（依 rule_profile 開關判定，例如 `{ "type": "rule", "key": "jail_enabled", "value": true }`）。新增 type 時要同時更新 `data_lint`。

**server_options.default.json**（GDD 附錄 A；每個世界存檔會複製一份再讓主機修改）

```json
{
  "enabled_eras": ["1.0A"],
  "rule_profile": {
    "preset": "classic_standard",
    "overrides": {}
  },
  "pk_mode": "CLASSIC",
  "wait_mode": true,
  "wait_mode_timeout_s": 20,
  "wait_mode_timeout_min_s": 8,
  "wait_mode_round_budget_s": 45,
  "guild_signers": 3,
  "attr_from_basic_skills": false,
  "allow_foreign_characters": false,
  "newbie_pk_protect_xp": 500,
  "max_players": 8,
  "autosave_interval_s": 60,
  "game_day_real_s": 7200,
  "host_offline_policy": "FROZEN",
  "bank_capacity": 1000,
  "sects_enabled": []
}
```

- 舊欄位 `content_era` 改成 `enabled_eras`（5.5）；舊的 `death_rule`、`corpse_window`、`basic_halve_on_betray`、`learn_point_cap`、`jail_in_era_a` 都移進 `rule_profile`（5.6），名稱改為 5.6 表中的開關名。
- `bank_capacity`：錢莊倉庫件數，1.0 為 1000；`xbcq`（小寶闖情關，M10）生效時由 patch 改成 10000，也可以由主機提前調高（GDD 9.1）。
- `sects_enabled`：要開放**拜入**的後期分支門派 id 清單（例如 `"mingjiao"`、`"taohuadao"`），預設空清單。收費版始終只有 11 派，明教、桃花島等拜入只存在於懷舊版／免費版，所以拜入和 `enabled_eras` 分開控制（5.5.1）。門派列仍要先通過 era 篩選；era 生效但不在此清單的門派，只有 NPC 與地區，不能拜入。
- `wait_mode_timeout_min_s`、`wait_mode_round_budget_s` 見 10.7；`host_offline_policy` 見 8.6。

### 5.4 （選用）從試算表產生 JSON

若企劃習慣用試算表：在 `design_tables/` 放 `.tsv`（不要放進 `res://`，避免被匯入成翻譯），用 `tools/tsv2json`（Godot `--script` 或 Python 皆可）轉成 `res://data/*.json`。**JSON 才是唯一的真實來源**；巢狀欄位（`requires`、`moves`）在 TSV 裡用 JSON 字串表示。

### 5.5 版本／資料片分期（era gating）【設計提案】

範圍擴大到後期官方資料片之後，「A／B／LATER」三段式不夠用。改成：**每個資料片一個 era id，每個世界自己決定開哪些 era**。內容以「疊加」方式加入，1.0 核心不必改寫。

#### 5.5.1 `eras.json`

```json
{
  "table": "eras", "version": 1,
  "rows": [
    { "id": "1.0A", "name": "公測開服",   "order": 0,  "date": "2001-06-28", "requires": [],    "base": true,  "src": "verified" },
    { "id": "1.0B", "name": "神鵰大俠",   "order": 10, "date": "2001-09-28", "requires": ["1.0A"], "base": false, "src": "unverified" },
    { "id": "gmdk", "name": "決戰光明頂", "order": 20, "date": "2002-01-23", "requires": ["1.0B"], "base": false, "src": "verified" }
  ]
}
```

| 欄位 | 意義 |
|---|---|
| `id` | era id，資料列的 `era` 欄位引用它。一旦發布就不能改名（存檔會引用） |
| `order` | 排序與 patch 套用順序（5.5.3）。不是「開了後面就自動開前面」，相依關係由 `requires` 決定 |
| `requires` | 開這個 era 必須同時開的 era（例如光明頂的地圖接在京城上，所以需要 1.0B） |
| `base` | 只有 `1.0A` 為 true，任何世界都必須開 |
| `src` | 同 5.1 的標記欄；日期或順序沒查證的寫 `unverified` |

預定的 era id（id 先保留，內容在後續里程碑才做）：

日期全部出自 jy2001 年表【已證實】（與 GDD 1.2、13.2 相同）。`1.0B` 的 `src` 仍標 `unverified`，指的是「神鵰大俠是第一個資料片還是 1.0 零售客戶端名稱」的命名問題（GDD 0.1、附錄 B #15），不是日期。

| era id | 資料片 | 上線日期 | 里程碑 |
|---|---|---|---|
| `1.0A` | 公測開服（10 派） | 2001-06-28 | M1–M3 |
| `1.0B` | 神鵰大俠 | 2001-09-28 | M3 + M5 |
| `gmdk` | 決戰光明頂 | 2002-01-23 | M6 |
| `xkd` | 勇闖俠客島 | 2002-06-06 | M7 |
| `khbd` | 葵花寶典 | 2002-09-18 | M8 |
| `qfcq` | 喬峰傳奇（畢業、自創門派） | 2003-01-15 | M9 |
| `xbcq` | 小寶闖情關 | 2003-05-21 | M10 |
| `gjdx` | 郭靖大俠 | 2003-11-12 | M11 |
| `sjjs` | 書劍江山 | 2004-04-21 | M12 |
| `lyfh` | 冷月飛狐 | 2004-08-27 | M13 |
| `bxsc` | 碧血沙場 | 2005-02-23 | M14 |
| `wlhd` | 武林浩蕩 | 2005-02-23 | M14 |
| `lzlhc` | 浪子令狐沖 | 2006-01-18 | M15 |
| `rysj` | 日月神教 | 2006-10-04 | M16 |
| `wyjp` | 五嶽劍派 | 2007-07-18 | M17 |

**後期分支門派（懷舊版／免費版／至尊版）不另設 era**。收費版直到五嶽劍派仍為 11 派【已證實】，明教、桃花島拜入只存在於懷舊版（2008）／免費版【後期版：懷舊版】。做法：

- 門派列的 `era` 填它的地區所屬的資料片，`src: "later"`：明教 `era: "gmdk"`（M6）、桃花島 `era: "xkd"`（M7）。M18 的逍遙、大理段氏、五毒教、崑崙同樣標所屬地區的 era（未定前不建列）。
- 能不能**拜入**另由 `server_options.sects_enabled` 決定（5.3）。所以開 `gmdk` 只會出現光明頂地區與明教 NPC，不會自動多一個可拜入門派，與原作收費版一致。
- `requires` 條件新增 type `sect_enabled`（`{ "type": "sect_enabled", "sect": "mingjiao" }`），用在該門派的入門任務與師父列；`data_lint` 檢查 `sects_enabled` 裡的 id 都存在於 `sects.json`。

各 era 的 `order` 依上線日期遞增；`requires` 預設是「前一個資料片」，加入該 era 的內容時再依實際地圖相依關係調整，並在 `src` 標記。

#### 5.5.2 資料列的規則

- 所有內容表（sects、basic_skills、martial_arts、masters、regions、maps、npcs、monsters、items、quests、status_effects、text_templates）的每一列都**必須**有 `era`。maps 的檔案外框也有 `era`。
- 選用欄位 `era_until`：如果某個 era 開了之後這一列就應該消失（例如後期把某個 NPC 移走），寫上那個 era 的 id。
- **生效條件**：`row.era ∈ enabled_eras`，而且（沒有 `era_until`，或 `era_until ∉ enabled_eras`）。
- 列內的部分內容只在某些 era 才有（例如某任務多一個步驟），用 requires 條件 `{ "type": "era_enabled", "era": "gmdk" }` 表示（新增到 5.3 的 requires type 清單）。
- **交叉參照**：生效的列只能引用生效的列。`data_lint` 對「每個 era 加上它的 `requires` 閉包」這種組合各檢查一次，確保任何合法的 `enabled_eras` 都不會有懸空的參照。
- `enabled_eras` 本身的檢查：一定包含 `1.0A`；對 `requires` 封閉（開 `gmdk` 卻沒開 `1.0B` 就報錯）；所有 id 都要在 `eras.json` 裡。

#### 5.5.3 後期版本修改既有資料：`patches/`

有些資料片不是新增，而是修改 1.0 的東西（數值調整、NPC 換位置）。不要把舊列複製一份改，改用 patch：

```json
{
  "table": "patches", "version": 1, "era": "gmdk",
  "rows": [
    { "id": "p_gmdk_001", "target_table": "npcs", "target_id": "n_example",
      "op": "merge", "set": { "region": "jingcheng" }, "src": "later" }
  ]
}
```

- 檔案放在 `res://data/patches/<era>.json`；只有該 era 生效時才套用，依 `eras.order` 由小到大套用。
- `op` 只有 `merge`（淺層覆寫欄位）與 `remove`（等同 `era_until`）兩種。需要更複雜的改動，就新增一列並把舊列標 `era_until`。
- patch 盡量少用；它是讓同一份 1.0 資料可以疊上不同資料片的工具，不是一般的內容編輯方式。

#### 5.5.4 載入、連線與存檔

1. `DataLoader.load_all()` **載入全部 era 的資料**，`content_hash` 涵蓋全部資料檔（與哪些 era 啟用無關），所以握手只需比對一個雜湊。
2. `GameData.activate(enabled_eras, rule_profile)` 依 5.5.2 篩選並套用 patch，產生這個世界的**生效視圖** `GameData.tables`。其他程式只讀生效視圖。
3. 主機開世界時呼叫 `activate()`；客戶端在 `s2c_welcome` 收到 `world_info.enabled_eras` 與**已展開**的 `rule_profile`（5.6）後呼叫同一個函式，兩邊的視圖一定相同。
4. 世界存檔（8.2）記錄 `enabled_eras` 與 `rule_profile`。**era 原則上只加不減**。真的要關掉某個 era 時，角色身上屬於該 era 的武功與物品不刪除，而是移到 `dormant` 清單保存，畫面上不顯示；重新開啟時還原。
5. 角色護照帶到別的世界時（8.4），對方世界沒開的 era 的內容同樣放進 `dormant`。

### 5.6 規則設定檔（rule_profile）【設計提案】

同一條規則在不同版本寫法不同（GDD 0.1 第 3 項、6.4、6.5）。這些規則不寫死在程式裡，也不散在 `server_options` 各處，而是集中成一組 `rule_profile`，`core/rules/` 只讀這組值。

| 開關 | 型別／選項 | 預設 | 來源 |
|---|---|---|---|
| `death_rule` | `STRICT_2001`（全部武功降 1 級、全部物品留屍體）／`STANDARD`（只降最高特殊武功、實戰 ≤ 500 免罰、只掉裝備）／`CASUAL`（不降級、只掉 10% 金錢） | `STANDARD` | 2001 規則【已證實】；STANDARD 為後期規則【後期版】；CASUAL【設計提案】 |
| `corpse_window` | `CLASSIC_30`（10 分鐘本人與授權者 + 20 分鐘公開）／`LATER_10`（10 分鐘後開放給所有人） | `CLASSIC_30` | 17173 2001【已證實】／newton【後期版】 |
| `betrayal_halves_basics` | bool：叛派時基本武功是否也減半 | `false` | 後期官方門規頁為 true【後期版】 |
| `xuedian_cap` | int：學點上限，`0` 表示不設上限 | `65200` | 至尊版指南【後期版】；1.0 查無資料 |
| `jail_enabled` | bool：門規坐牢，作用於所有 era。`false` 時任何時期都沒有坐牢，原本要坐牢的違規一律改成「禁止學武」（`NO_LEARN`），刑期照算 | `true` | 規則【已證實】，但 1.0-A 是否已有【待考證】 |
| `self_study_cap` | `NONE`（自修只受師父上限限制）／`HJ_1_5X`（自修上限為等級 1.5 倍，練滿時 250） | `NONE` | 懷舊版數據【後期版：懷舊版】（GDD 4.2） |

`rule_profiles.json` 提供幾組預設組合，世界選項只存「預設組合 + 個別覆寫」：

```json
{
  "table": "rule_profiles", "version": 1,
  "rows": [
    { "id": "classic_strict",   "name": "懷舊嚴苛（2001）", "era": "1.0A",
      "rules": { "death_rule": "STRICT_2001", "corpse_window": "CLASSIC_30",
                 "betrayal_halves_basics": false, "xuedian_cap": 0, "jail_enabled": true,
                 "self_study_cap": "NONE" } },
    { "id": "classic_standard", "name": "懷舊標準（預設）", "era": "1.0A",
      "rules": { "death_rule": "STANDARD", "corpse_window": "CLASSIC_30",
                 "betrayal_halves_basics": false, "xuedian_cap": 65200, "jail_enabled": true,
                 "self_study_cap": "NONE" } },
    { "id": "later_official",   "name": "後期官方規則", "era": "1.0A",
      "rules": { "death_rule": "STANDARD", "corpse_window": "LATER_10",
                 "betrayal_halves_basics": true, "xuedian_cap": 65200, "jail_enabled": true,
                 "self_study_cap": "NONE" } },
    { "id": "friends_casual",   "name": "好友休閒", "era": "1.0A",
      "rules": { "death_rule": "CASUAL", "corpse_window": "CLASSIC_30",
                 "betrayal_halves_basics": false, "xuedian_cap": 0, "jail_enabled": false,
                 "self_study_cap": "NONE" } }
  ]
}
```

- 展開順序：預設組合的 `rules` → 世界的 `overrides`。展開後的完整字典才傳給 `core/rules/`（以參數傳入，`core/` 不讀 Autoload，符合 4.3）。
- 每個開關都要有預設值；`data_lint` 檢查每組預設組合都填齊了所有開關。
- **新增開關的規則**：之後的資料片若又帶來規則衝突（例如畢業制的條件），一律新增一個開關並給「1.0 行為」當預設值，不改既有開關的意義。舊世界載入時缺少的開關自動補預設值（`SaveMigrations`）。
- 世界開始後仍可修改 rule_profile，但修改只影響之後發生的事件，已經發生的死亡、叛派不回溯。

---

## 6. 網路模型：主機權威（Host-Authoritative）

### 6.1 角色分工

| | 主機（peer 1） | 客戶端 |
|---|---|---|
| 遊戲邏輯 | 全部：移動、遇敵、戰鬥、學武、經濟、任務、PK、存檔 | 無 |
| 亂數 | 全部在主機上擲 | 不擲（只用於純視覺效果） |
| 傳給對方 | 狀態快照、文字事件、操作結果 | 只有 intent（意圖） |
| 存檔 | 世界存檔與所有角色檔 | 只存自己的「角色護照」備份 |

主機本身也是一位玩家。主機玩家的 intent 走同一個 `handle_intent()`，只是不經過網路（見 6.4）。

### 6.2 連線握手

1. 傳輸層連上後，客戶端送 `c2s_hello({ protocol, game_version, content_hash, identity, display_name, passport? })`。
2. 主機檢查：
   - `protocol` 與 `game_version` 一致；
   - `content_hash` 一致（GameData 對所有資料檔算 SHA-256，GDD 12.7）；
   - `identity` 合法：Steam 模式下，主機用 `peer.get_steam_id_for_peer_id(peer_id)` 取得**真正的** SteamID，忽略客戶端自己報的值【已證實：方法存在】。ENet / 離線模式下使用本機設定檔裡的 UUID（`local_<uuid>`），區網好友之間不做防偽。
   - 名額未滿，沒有被踢除名單。
3. 通過後建立 `Session`，送 `s2c_welcome({ world_info, your_characters[], your_peer_id })`（M0 的 `your_characters` 恆為空陣列），接著對所有人送 `s2c_roster(players[])`；`world_info` 內含 `enabled_eras` 與展開後的 `rule_profile`，客戶端收到後呼叫 `GameData.activate()`（5.5.4）；不通過送 `s2c_rejected(reason)`，0.5 秒後斷線。
4. 5 秒內沒收到 hello 就斷線。

> 可改用 Godot 內建的 `SceneMultiplayer.auth_callback` / `send_auth()` / `complete_auth()` 做握手，好處是驗證通過前對方連 RPC 都不能送【API待驗證：4.6 的確切用法】。M0 先用簡單的 hello RPC，M2 再評估。

### 6.3 Intent（客戶端 → 主機）

所有 intent 都經由**單一 RPC 入口** `WorldServer.c2s_intent(seq, kind, args)`：

- `seq`：客戶端遞增序號，主機回 `s2c_intent_result(seq, ok, reason)`，UI 用來解除按鈕鎖定、顯示錯誤。
- `kind`：字串，定義在 `core/protocol.gd`，例如 `move`、`talk`、`learn`、`self_study`、`buy`、`sell`、`equip`、`use_item`、`chat`、`battle_cmd`、`challenge`、`force_pk`、`party_invite`、`loot_corpse`、`mail_send`……
- `args`：Dictionary，只能放基本型別（int、float、String、Array、Dictionary、Vector2i）。**不允許物件**（`multiplayer.allow_object_decoding` 保持預設 false）。

主機端每個 intent 處理器的固定步驟：

1. `multiplayer.is_server()` 為真（防呆）。
2. 由 `get_remote_sender_id()` 找到 `Session`；沒有就丟棄。
3. 速率限制：每個 peer 每秒最多 20 個 intent（token bucket），超過就丟棄並記錄。
4. 驗證 `args` 的型別和範圍（`Protocol.validate(kind, args)`）。
5. 驗證遊戲條件（人在不在這個區格、NPC 在不在、錢夠不夠……），這一步呼叫 `core/rules/`。
6. 套用變更，標記 dirty，產生事件。
7. 回 `intent_result`。

選擇單一入口而不是每種 intent 一個 RPC：RPC 設定表在所有 peer 上必須一致，單一入口讓新增 intent 不必改 RPC 簽名；序號與錯誤回報也統一處理【設計提案】。

### 6.4 主機玩家與離線模式的「本地短路」

主機自己（peer 1）呼叫 `rpc_id(1, ...)` 給自己時，Godot 要求方法標註 `call_local` 才會執行，而且這種情況下 `get_remote_sender_id()` 的回傳值容易混淆【API待驗證】。為了避免這些細節，本作一律**短路**：

- 送 intent：`NetworkManager.send_intent()` 若 `multiplayer.is_server()`，就直接呼叫 `WorldServer.handle_intent(1, ...)`，不走 RPC。
- 送事件：`ClientState.deliver(peer_id, ...)` 若 `peer_id == multiplayer.get_unique_id()`，就直接呼叫本地處理函式，不走 RPC。

如此一來，離線模式（`OfflineMultiplayerPeer`，unique id = 1，`is_server()` 為真）完全不會發出任何 RPC，但走的是同一套邏輯。

### 6.5 主機 → 客戶端的同步內容

| 資料 | RPC | 模式 | 頻率 |
|---|---|---|---|
| 文字事件批次 | `s2c_events(batch: Array)` | reliable | 每幀最多一次（主機在 `_process` 末尾 flush 每個 peer 的佇列） |
| 自己的角色表 | `s2c_sheet(sheet: Dictionary)` | reliable | dirty 時，每秒最多 4 次；M4 再改差異更新 |
| 目前區格的視圖 | `s2c_region_view(view: Dictionary)` | reliable | 進入區格時全量；之後用 `region_delta` 事件（誰進出、誰移動到哪格） |
| 戰鬥開始/結束 | `s2c_battle_open(state)` / `s2c_battle_close(result)` | reliable | 事件觸發 |
| 戰鬥時間棒錨點 | 包在 `s2c_events` 內（`battle_gauges` 事件：每單位 `gauge` 與 `rate`） | reliable | **事件觸發**：開戰、暫停／恢復、任一單位行動或狀態改變時。客戶端在兩個錨點之間自行外插（10.6） |
| 戰鬥時間棒校正 | `s2c_battle_tick(battle_id, tick, gauges: PackedByteArray)` | **unreliable_ordered** | 1 Hz 校正（可在選項改成 10 Hz 除錯）。掉了沒關係 |
| 戰鬥事件（出招、傷害、狀態） | 包在 `s2c_events` 內 | reliable | 事件觸發 |
| 操作結果 | `s2c_intent_result(seq, ok, reason)` | reliable | 每個 intent 一次 |
| 角色護照 | `s2c_passport(char_json, signature)` | reliable | 角色存檔時（見 8.4） |
| 被踢 | `s2c_kicked(reason)` | reliable | 主機踢人時 |

**範圍（interest management）**：主機只把事件送給「需要知道的人」。規則見第 11 章 `EventRouter`。

**不使用 `MultiplayerSynchronizer` / `MultiplayerSpawner`**：本作的世界是文字與區格，沒有大量需要逐幀同步的節點；顯式 RPC 比較好控制頻寬與權限【設計提案】。

### 6.6 SceneMultiplayer 設定

- `multiplayer.server_relay = false`：主機權威下，客戶端之間不需要互傳訊息；關掉後客戶端也收不到其他客戶端的 `peer_connected`，玩家名單一律由主機的 `s2c_roster` 提供。
  - 研究指出 GodotSteam 教學把 `server_relay` 設在 **SteamMultiplayerPeer 上**，但類別參考頁沒有這個屬性；本作只用 `SceneMultiplayer.server_relay`。設定時機（建立 peer 前或後）【API待驗證】：M0 兩種都試，確認客戶端呼叫其他客戶端的 RPC 會被擋下。
- `multiplayer.allow_object_decoding = false`（預設值，不要改）。

---

## 7. 傳輸層與離線模式

### 7.1 三種傳輸

| 模式 | MultiplayerPeer | 用途 |
|---|---|---|
| `OFFLINE` | `OfflineMultiplayerPeer`（Godot 4 預設 peer，unique id 1）【已證實】 | 單機遊玩；Steam 沒開時；單元/整合測試 |
| `ENET_HOST` / `ENET_CLIENT` | `ENetMultiplayerPeer.create_server(port, max_clients)` / `create_client(address, port)`【已證實】 | 區網、同一台電腦開多個實例測試、沒有 Steam 的好友（自行開埠） |
| `STEAM_HOST` / `STEAM_CLIENT` | `SteamMultiplayerPeer.create_host(0)` / `create_client(host_steam_id, 0)`【已證實：方法存在】 | 正式的好友連線 |

切換傳輸只是換掉 `multiplayer.multiplayer_peer`，`WorldServer` / `ClientState` 的 RPC 程式碼完全不變【已證實】。

ENet 預設埠：`24565`（可在設定改）。

### 7.2 啟動參數

`OS.get_cmdline_user_args()`（`--` 之後的參數）：

| 參數 | 作用 |
|---|---|
| `--no-steam` | 不初始化 Steam（測試、沒有 Steam 的環境） |
| `--offline --world=<name>` | 直接以離線模式進入指定世界 |
| `--enet-host --port=24565 --world=<name>` | 直接開 ENet 主機 |
| `--enet-join=127.0.0.1:24565` | 直接加入 ENet 主機 |
| `--profile=<name>` | 使用 `user://profiles/<name>/`，讓同一台電腦的多個實例有不同身分 |
| `--bot=<script>` | 測試用：載入腳本化的假玩家（第 15 章） |
| `--dedicated --world=<name>` | 無介面專用主機，主機本身不是玩家（8.6）；搭配 `--enet-host` 或 `--steam-host` |
| `--steam-host` | 以 Steam 大廳開房（專用主機用；一般玩家從標題畫面開房） |

`OS.get_cmdline_args()`（Steam 傳來的引擎外參數）：`+connect_lobby <lobby_id>`，冷啟動時接受邀請用【已證實】。

### 7.3 Steam 沒開時的退路

`SteamManager` 初始化失敗（`status != 0`）時：

- 標題畫面顯示原因（`status` 1 其他失敗／2 Steam 沒開／3 用戶端過舊）【已證實】。
- 「開房（Steam）」「加入好友」按鈕變灰，「單機」「區網」可用。
- 遊戲照常運作。

---

## 8. 存檔系統

### 8.1 檔案配置（主機的資料根目錄；下面的 `user://` ＝ 資料根目錄，實際位置見 README「存檔放在哪裡」）

```
user://
├─ settings.json                     # 本機設定：字級、音量、快捷鍵、上次的世界
├─ profiles/<profile>/identity.json  # 非 Steam 身分：{ "local_id": "local_<uuid>" }
├─ worlds/<world_id>/
│  ├─ world.json                     # 世界狀態
│  ├─ world.json.bak1 … bak5         # 輪替備份
│  ├─ options.json                   # 本世界的伺服器選項
│  └─ characters/
│     └─ <identity>/                 # steam_7656119xxxxxxxxxx 或 local_<uuid>
│        ├─ <char_id>.json
│        └─ <char_id>.json.bak1 …
├─ passports/<world_id>/<char_id>.json   # 客戶端收到的角色護照
└─ backup_host/<world_id>/snapshot.json  # 被指定為副主機時收到的世界快照
```

- `identity` 字串：`steam_<SteamID64>` 或 `local_<uuid>`。SteamID 一律以字串保存（5.2）。
- 每個 identity 在同一個世界最多 3 個角色【設計提案】。

### 8.2 world.json 內容

```json
{
  "schema_version": 1,
  "world_id": "w_5f3c9a",
  "world_name": "大理好友服",
  "world_secret": "（32 bytes 亂數的 hex，用來簽角色護照，不傳給客戶端）",
  "content_hash": "sha256:…",
  "game_version": "0.1.0",
  "world_time_s": 123456.7,
  "enabled_eras": ["1.0A"],
  "rule_profile": { "preset": "classic_standard", "overrides": {} },
  "rng_state": "…",
  "regions": { "xixia_wild": { "ground_items": [], "npc_state": {} } },
  "corpses": [ { "id": "c_12", "owner": "steam_…", "char_id": "ch_1", "region": "dali_wild",
                 "at": [3, 4], "created_s": 120000.0, "authorized": [], "items": [] } ],
  "mail": [ { "to_char": "ch_7", "from_name": "令狐小沖", "text": "……", "sent_s": 1.0 } ],
  "guilds": [],
  "bounties": [],
  "flags": {},
  "known_identities": { "steam_…": { "last_name": "阿朱", "banned": false } },
  "backup_host": "steam_…",
  "lineage": 0
}
```

### 8.3 寫入流程

- **時機**：每 `autosave_interval_s`（預設 60 秒）、玩家離線、關服、主機轉移前（GDD 12.5）。
- **原子寫入**：寫 `X.tmp` → 把現有 `X` 改名成 `X.bak1`（舊的 bak 依序往後推，保留 5 份）→ 把 `X.tmp` 改名成 `X`。任何一步失敗都保留舊檔並在畫面上警告。
- **增量**：只寫 dirty 的角色檔；world.json 每次自動存檔都寫（大小可控）。
- **載入失敗**：JSON 解析錯誤或 `schema_version` 不認得時，自動嘗試 `bak1` → `bak5`，並告訴主機玩家用的是哪一份。
- **版本升級**：`SaveMigrations.migrate(dict, from_version)` 依序套用遷移函式。
- **存檔格式為 JSON** 的理由：方便人工檢查、修復和比對。缺點是數字都變 float，所以每個模型都有 `from_dict()` 負責轉型（5.2）。

### 8.4 角色護照（玩家能不能帶走自己的角色檔？）

**能帶走備份，但預設不能帶進別的世界。**

1. 主機每次存某個角色時，也送 `s2c_passport(char_json, signature)` 給該玩家（如果在線），玩家存到 `user://passports/<world_id>/`。
   - `signature = sha256(world_secret + world_id + canonical(char_json))`（`String.sha256_text()`）。
2. **用途一：災難復原**。主機的角色檔遺失時，玩家連入的 hello 帶上護照；主機驗章通過（world_secret 還在）就還原。若主機連 world.json 都遺失（world_secret 也沒了），主機玩家可以在管理面板選「信任這份未驗證護照」逐一手動還原。
3. **用途二：帶到別的世界**。只有對方世界開了 `allow_foreign_characters` 才接受；接受時把角色標記 `origin_world`，並用資料表重新檢查數值上下限（武功不得超過該世界的師父上限、物品 id 必須存在），不合法的部分截斷或移除，再讓主機玩家確認。
4. **簽章能保證什麼、不能保證什麼（誠實說明）**：
   - `world_secret` 只存在主機的 `world.json`，客戶端拿不到，所以「沒有主機檔案存取權的玩家改了護照」會被**察覺**（驗章失敗）。這是**可察覺竄改（tamper-evident）**，而且只在「主機不作弊、主機的檔案沒外流」這個好友間的前提下成立。
   - 它**不防**：主機玩家本人（他有 `world_secret`，可以任意簽）；能拿到主機存檔的人；修改遊戲程式的人；以及 `world_secret` 遺失後主機選擇「信任未驗證護照」的情況。
   - 對**別的世界**而言，這個簽章完全沒有意義：對方主機沒有原世界的 `world_secret`，無法驗章。所以開啟 `allow_foreign_characters` 就等於**信任玩家自報的數值**，只能靠第 3 點的上下限截斷和主機玩家人工確認。UI 上要明白寫「外來角色未經驗證」。
   - 結論：護照是**災難復原工具**，不是防作弊機制。主機上的檔案才是權威。

### 8.5 副主機（手動主機轉移，GDD 12.6）

- 主機在管理面板指定一位好友為副主機（`backup_host`）。
- 每 10 分鐘把世界快照（world.json + 全部角色檔，`var_to_bytes()` 後以 `PackedByteArray.compress(FileAccess.COMPRESSION_ZSTD)` 壓縮）送給副主機。快照超過 256 KB 就切成多段送【推論：Steam 單則訊息有大小上限，確切值未核對】。
- 副主機存到 `user://backup_host/<world_id>/snapshot.json`，標題畫面「從副本開服」即可接手。
- 原主機回來時，雙方比較 `world_time_s`，由主機玩家選擇採用哪一份。不做自動合併。
- **分歧風險**：副主機接手期間原主機若也離線開了單機，兩份世界就分岔，只能二選一，另一份的進度丟失。所以「從副本開服」時要在世界存檔記一個 `lineage` 計數（每次換手 +1），原主機回來時 UI 明確顯示「這份副本已經往前走了 N 小時，採用它會覆蓋你的存檔」。

### 8.6 主機離線策略（host_offline_policy）

「主機一離線，好友就不能玩」和「跟朋友一起玩」的期待衝突（評論 c）。提供以下選項，`server_options.host_offline_policy` 記錄世界用哪一種：

| 選項 | 行為 | 成本與風險 | 里程碑 |
|---|---|---|---|
| `FROZEN`（預設） | 主機關閉＝江湖凍結（9 章）。時間制機制以累計上線時間或世界運行時間計算，沒人吃虧 | 好友在主機不在時不能玩 | M2 |
| `BACKUP_HOST` | 8.5 的手動副主機接手 | 存檔可能分岔，只能二選一 | M2 |
| `DEDICATED` | 一台常開的電腦以**無介面專用主機**模式跑 `WorldServer`，主機本身不是玩家 | 要有一台常開的機器；Steam 模式需要一個 Steam 帳號 | M4（選用） |

**專用主機模式（`DEDICATED`）**【設計提案】：

- 啟動：`godot --headless --path game -- --dedicated --world=<name> [--enet-host --port=24565 | --steam-host]`（匯出版則是 `JYMini.exe --headless -- --dedicated ...`）。新增 `--dedicated` 參數到 7.2。
- `--dedicated` 時：`ClientState.begin_local_session()` 不呼叫，主機沒有自己的角色；`SceneRouter` 不載入 UI；`WorldServer` 照常以 10 Hz 運作；管理操作（踢人、存檔、關服）改由一位被指定為「管理員」的 identity 透過 intent 執行，或用主控台輸入。
- **ENet 版**：最簡單，不需要 Steam。缺點是要開埠（或用 VPN 類工具把好友放進同一個虛擬區網），身分沒有 SteamID 擔保（6.2 的 `local_<uuid>`，好友之間不防偽）。
- **Steam 版**：那台機器必須執行並登入 Steam 用戶端，大廳與 P2P 都以那個帳號為主機。用主要帳號的話，該帳號同時就不能在別台電腦玩同一款遊戲【推論】，所以建議另開一個 Steam 帳號。注意：GodotSteam 的「server 版本」沒有 `SteamMultiplayerPeer`【已證實】，所以必須用一般版 GodotSteam 加 `--headless`，**不是** GameServer API。無介面模式下 Steam 初始化、`run_callbacks()` 與 P2P 是否正常【API待驗證】，M4 實測。
- 世界時間在專用主機上持續累加；GDD 的「主機離線＝江湖凍結」在這個模式下不適用，PK值遞減、坐牢仍以角色的累計上線時間計，不受影響。

---

## 9. 世界時鐘與計時

- **世界時間** `world_time_s`：只在主機運作時累加（預設 `FROZEN`：主機離線＝江湖凍結，GDD 12.6；專用主機模式下持續累加，見 8.6）。用於：遊戲時辰（`game_day_real_s` 預設 7200 秒＝1 遊戲日）、屍體時限（依 rule_profile.corpse_window，5.6）、物品腐壞、NPC 重生。
- **角色上線時間** `character.online_s`：該角色在線時才累加。用於：PK值每 30 分鐘 −1、坐牢刑期（GDD 6.5「以累計上線時間計」）。
- **惰性計算**：物品腐壞、PK值遞減等不逐 tick 計算，而是存「時間戳」，在讀取時算出目前值（例如 `pk_value = max(0, pk_base - floor((online_s - pk_stamp_s) / 1800))`）。這樣主機的固定 tick 只需要處理戰鬥與移動。
- **主機 tick**：`WorldServer._process` 以累加器跑固定 **10 Hz** 邏輯 tick（`TICK = 0.1`，對應 GDD 5.3 的 0.1 秒時間棒 tick），每個 tick：推進所有戰鬥 → 處理屍體到期 → flush 事件。

---

## 10. 戰鬥系統

### 10.1 組成

- `BattleSystem`（`server/`）：持有所有進行中的 `Battle`，`battle_id` 遞增；負責把 peer 對應到 unit。
- `Battle`（`core/battle/`）：純邏輯狀態機，不知道網路存在。輸入是「指令」，輸出是「事件陣列」。每場戰鬥有自己的 `RandomNumberGenerator`（種子由主機的世界 RNG 產生並記入事件），所以同樣的種子加同樣的指令序列一定得到同樣結果，可做回放與測試。
- `BattleUnit`：氣、內、精、神、時間棒、位置、狀態效果、可用指令、控制者（`peer_id` 或 `AI`）。
- `BattleGrid`：12×8 格、單位阻擋、黃色逃跑格（GDD 5.2）。

### 10.2 戰鬥狀態機（整場）

```
          ┌──────────┐
  開戰 ──▶│  SETUP   │  佈陣：玩家在左側、敵人在右側、隨機放 2 個逃跑格
          └────┬─────┘
               ▼
          ┌──────────┐  每 tick 依 GDD 5.3 公式累加所有可行動單位的時間棒
   ┌────▶ │ RUNNING  │──────────────────────────────┐
   │      └────┬─────┘                              │
   │           │ 有單位時間棒 ≥ 100                    │ 勝負已分
   │           ▼                                    ▼
   │   ┌─────────────────┐   AI 單位：立刻決定指令   ┌──────────┐
   │   │ AWAIT_COMMAND   │──────────────────────▶ │ RESOLVING │
   │   │ (等待模式：全部    │   玩家：收到 battle_cmd │  結算一個指令 │
   │   │  時間棒暫停)      │   或逾時 → 自動「防」     │  產生事件     │
   │   └─────────────────┘                        └────┬─────┘
   │                                                   │
   └───────────────────────────────────────────────────┘
                                                        │
                                                        ▼
                                                 ┌──────────┐
                                                 │  ENDED   │ result = VICTORY / DEFEAT / ALL_FLED / ABORTED
                                                 └────┬─────┘
                                                      ▼
                                                 ┌──────────┐
                                                 │ REWARDS  │ 實戰、學點分配（GDD 2.4）、掉落、死亡處理（GDD 6.4）
                                                 └────┬─────┘
                                                      ▼
                                                   CLOSED（從 BattleSystem 移除）
```

- **等待模式開啟**（預設）：任一**玩家**單位進入 READY 時，整場進入 `AWAIT_COMMAND`，所有時間棒暫停，直到所有 READY 的玩家都下了指令或逾時（基準 `wait_mode_timeout_s` 預設 20 秒，依參戰人數縮短，見 10.7；逾時自動「防」）。
- **等待模式關閉**（純半即時）：READY 的玩家單位停在滿條，其他單位照常累積；玩家隨時下指令，下一個 tick 結算。
- 同一 tick 有多個單位 READY：依時間棒溢出量排序，相同再比機敏，再相同用 RNG。

### 10.3 單位狀態

`CHARGING`（累積中）→ `READY`（滿條，等指令）→ `ACTING`（結算中）→ `CHARGING`
旁支：`DISABLED`（點穴、麻痺：不累積或跳過）、`FLED`、`DEAD`、`DISCONNECTED`（斷線：留在戰場、自動「防」直到戰鬥結束；戰場上已沒有在線玩家時當場快轉結算；同一角色在戰鬥結束前重連會接回原戰鬥，GDD 6.4、M2_PLAN D4）。

### 10.4 指令

`battle_cmd` intent 的 `args`：

```
{ "battle_id": 12, "unit_id": 3, "cmd": "ART",
  "art": "sl_changquan", "move": "sl_cq_2", "power_tenths": 7,   # 「成數」1–10
  "target": [8, 4] }
```

`cmd` 列舉（GDD 5.4）：`MOVE ATTACK ART SPECIAL DEFEND REST EQUIP FLEE POISON MEDIC HIDDEN FORMATION INNER ACUPOINT`（`LIGHTNESS` 預設關閉）。主機驗證：unit 屬於這個 peer、unit 是 READY、指令已解鎖、目標在射程內、內力足夠、FLEE 時人站在逃跑格上。

### 10.5 中途加入與 PK

- 隊友走到同一區格可選「加入戰鬥」，`BattleSystem.join(battle_id, character)`，從邊緣空格出場（GDD 5.8）。
- PK（叫戰、強制 PK）也是一場 `Battle`，雙方都是玩家單位；`pk_mode` 與新手保護在**開戰前**由 `MoralityPk` 判定。

### 10.6 戰鬥中的網路

- 開戰：`s2c_battle_open` 送給所有參戰 peer（以及同區格想觀戰的人，M3）。
- **時間棒同步改用事件錨點，不逐 tick 傳送**：兩個事件之間，每個單位的時間棒增加速度是固定的（GDD 5.3 的公式只看屬性與狀態，而狀態改變本身就是事件），所以主機只在「開戰、進入或離開 `AWAIT_COMMAND`、任一單位行動、狀態效果增減」時送一次 `battle_gauges` 事件：`{ tick, units: [[uid, gauge, rate_per_tick, charging], ...] }`。客戶端從錨點開始以 10 Hz 自行累加畫面，到滿條就停在 100 等下一個事件。
- **校正**：`s2c_battle_tick` 降為 **1 Hz**（unreliable_ordered，每單位一個 byte），只用來修正浮點誤差或掉幀；差距超過 5% 才拉回。`server_options` 可改回 10 Hz 供除錯。
- 理由：8 人、多場同時戰鬥時，10 Hz 快照的資料量本身很小（第 14 章），但每個封包都有固定的傳輸標頭與 Steam 端的訊息成本；改用錨點之後封包數降到約十分之一，且等待模式期間（時間棒全停）完全不用送【推論：Steam 每則訊息的固定開銷未實測，M2 用 15.4 的兩帳號測試量一次】。
- 每個指令結算：事件（`battle_act`、`battle_dmg`、`battle_status`、`battle_move`）透過 `s2c_events` 可靠傳送。客戶端以事件為準更新氣血，快照只用來畫時間棒。

### 10.7 8 人戰鬥的等待模式節奏【設計提案】

固定每人 20 秒逾時，8 個玩家輪流發呆時，一輪最壞要等 160 秒（評論 c）。改成以下規則，全部在 `Battle` 內實作（純邏輯，可單元測試）：

1. **逾時隨人數縮短**：每次進入 `AWAIT_COMMAND` 時，
   `timeout = max(wait_mode_timeout_min_s, wait_mode_timeout_s − 2 × (參戰真人數 − 1))`
   預設值下：1 人 20 秒、4 人 14 秒、7 人以上 8 秒。
2. **同時滿條一起等**：同一 tick 進入 READY 的玩家共用一次等待（10.2 已是如此），不是一人一人輪流等。
3. **每輪總預算**：從上一次「所有真人都行動過一次」起算，累計等待時間超過 `wait_mode_round_budget_s`（預設 45 秒）後，本輪剩下的等待一律縮成 `wait_mode_timeout_min_s`。
4. **發呆偵測**：同一位玩家連續兩次逾時，標記 `afk`，之後他的逾時直接是 3 秒（仍自動「防」），直到他自己下一次指令才解除。UI 在他的名字旁顯示「神遊中」。
5. **提早結束等待**：所有在等的玩家都下好指令就立刻結算，不等計時器（10.2 已是如此）。
6. **倒數顯示**：`battle_await` 事件帶上 `deadline_tick`，客戶端顯示倒數，讓其他人知道還要等多久。

`Battle.step()` 的 `AWAIT_COMMAND` 分支要改用上面算出的 `_await_timeout`，不直接讀 `opts.wait_mode_timeout_s`（13.4 骨架已標註）。M2 用 8 個 bot（15.3）跑一場，量「每輪平均等待秒數」，作為調整這三個預設值的依據。

---

## 11. 文字與事件紀錄

### 11.1 事件格式

主機**不送組好的句子**，而是送結構化事件，由客戶端依「誰在看」組字：

```
{ "seq": 10452, "t": 123456.7, "ch": "BATTLE",
  "key": "move_fist_basic",
  "p": { "atk": "ch_1", "def": "m_wolf#2", "move": "sl_cq_1", "tenths": 7, "dmg": 23, "part": "胸口" } }
```

- `ch`（頻道）：`SCENE`、`BATTLE`、`SYSTEM`、`CHAT_WORLD`（千里傳音）、`CHAT_WHISPER`（傳音入密）、`CHAT_SAY`（輕聲細語）、`CHAT_SECT`、`CHAT_GUILD`、`CHAT_PARTY`、`CHAT_RUMOR`（江湖謠言）、`GM`（天外飛仙）、`MAIL`。
- `key`：對應 `text_templates.json`。

**text_templates.json** 每個 key 有「第一人稱」與「旁觀」兩種寫法，重現原作「你使出……」的語氣：

```json
{
  "table": "text_templates", "version": 1,
  "rows": [
    { "id": "move_fist_basic",
      "self":  "你使出{art}「{move}」（{tenths}成力），正中{def}的{part}！（-{dmg}）",
      "target":"{atk}使出{art}「{move}」，正中你的{part}！（-{dmg}）",
      "other": "{atk}使出{art}「{move}」，正中{def}的{part}！" }
  ]
}
```

客戶端的 `TextRenderer`（`ui/common/text_renderer.gd`）判斷自己是 atk、def 還是旁觀者，選模板、把 id 換成名字（名字顏色依善惡：惡藍、中立黃、善白，GDD 6.1）、輸出 BBCode 給 `RichTextLabel`。

### 11.2 EventRouter（誰收得到）

| 頻道 | 收件人 |
|---|---|
| SCENE、CHAT_SAY | 同一區格的玩家 |
| BATTLE | 參戰者（＋觀戰者） |
| CHAT_WORLD、CHAT_RUMOR、GM | 所有在線玩家 |
| CHAT_SECT / GUILD / PARTY | 同門 / 同組織 / 同隊 |
| CHAT_WHISPER、MAIL、SYSTEM（個人） | 指定一人 |

聊天的耗水（GDD 10.1，傳音入密不耗水）在 `ChatSystem` 送出前扣除，飲水為 0 就回 `intent_result(false, "thirsty")`。

### 11.3 客戶端紀錄

- `ClientState.event_log`：環狀緩衝區，最多保留 2000 則；UI 的分頁（全部／千里／門派／組織／隊伍／系統）只是篩選器。
- `RichTextLabel` 只顯示最後 500 行（效能），捲到頂再向緩衝區補。
- 主機也保留每個區格最近 50 則 SCENE 事件，玩家進入區格時補送，讓畫面不是空白的。

---

## 12. UI 場景清單

所有場景在 `res://ui/`，共用 `ui/theme/main_theme.tres`（宣紙底、墨字、朱紅強調，GDD 11.1）。

| 場景 | 路徑 | 內容 | 里程碑 |
|---|---|---|---|
| 開機 | `ui/boot/boot.tscn` | 載入 GameData、初始化 Steam、顯示錯誤 | M0 |
| 網路除錯 | `ui/debug/net_debug.tscn` | 開房/加入/ENet/離線按鈕、peer 清單、RPC 聊天測試 | M0 |
| 標題 | `ui/title/title_menu.tscn` | 單機、開房（Steam）、加入好友、區網、設定、製作群 | M1 |
| 世界選擇 | `ui/world/world_select.tscn` | 建立/載入世界、從副本開服 | M1 |
| 伺服器選項 | `ui/world/server_options_panel.tscn` | M2 最小版：死亡規則、PK 模式、等待模式；M4 完整版：`enabled_eras`、`sects_enabled`、`rule_profile` 預設組合與覆寫、連署人數、`host_offline_policy` | M2（最小版）；M4（完整版） |
| 大廳 | `ui/lobby/lobby_room.tscn` | 成員、邀請（Steam 覆蓋介面）、開始 | M2 |
| 大廳搜尋 | `ui/lobby/lobby_browser.tscn` | 依 `game=jymini_v1` 篩選的公開大廳（測試用） | M2 |
| 角色選擇 | `ui/char/character_select.tscn` | 本世界的角色列表 | M1 |
| 創角 | `ui/char/character_create.tscn` | 性別、擲骰、5 點分配、生日、出生城市（GDD 2.1） | M1 |
| 主畫面 | `ui/main/main_screen.tscn` | GDD 11.2 版面，由下列子場景組成 | M1 |
| ├ 燈籠選單 | `ui/main/lantern_menu.tscn` | Ctrl+1–5、Esc 隱藏 | M1 |
| ├ 小地圖 | `ui/main/region_map.tscn` | CC0 圖塊 + 名字色點 | M1 |
| ├ 場景描述 | `ui/main/scene_panel.tscn` | 描述、出口、人物、動作按鈕 | M1 |
| ├ 訊息紀錄 | `ui/main/message_log.tscn` | 頻道分頁、聊天輸入 | M1 |
| ├ 狀態列 | `ui/main/status_bar.tscn` | 精氣神內四色條、七屬性、飽食飲水 | M1 |
| ├ 快捷列 | `ui/main/hotbars.tscn` | F1–F8 指令列、Alt+1–8 物品列，各 9 頁 | M1 |
| └ 飛鴿圖示 | `ui/main/pigeon_icon.tscn` | 有新信件時閃爍 | M2 |
| 武功面板 | `ui/panels/skills_panel.tscn` | 基本武學、特殊武功、門派技能 | M1 |
| 屬性面板 | `ui/panels/attributes_panel.tscn` | 屬性、衍生數值、進度數值 | M1 |
| 裝備/背包 | `ui/panels/inventory_panel.tscn` | 四分頁、負重 | M1 |
| 系統面板 | `ui/panels/system_panel.tscn` | 顯示名稱、接受叫戰、接受組隊、字級 | M1 |
| NPC 對話 | `ui/dialogs/npc_dialog.tscn` | 對話、學武、任務、商店入口 | M1 |
| 學武 | `ui/dialogs/learn_dialog.tscn` | 消點、上限顯示 | M1 |
| 商店 | `ui/dialogs/shop_dialog.tscn` | 買賣 | M1 |
| 錢莊 | `ui/dialogs/bank_dialog.tscn` | 存錢、倉庫 1000 件 | M1 |
| 屍體拾取 | `ui/dialogs/corpse_dialog.tscn` | 授權、拾取 | M2 |
| 交易 | `ui/dialogs/trade_dialog.tscn` | 雙方確認 | M2 |
| 叫戰確認 | `ui/dialogs/challenge_dialog.tscn` | 接受/拒絕 | M2 |
| 飛鴿傳書 | `ui/dialogs/mail_dialog.tscn` | 收件匣、寫信 | M2 |
| 隊伍 | `ui/panels/party_panel.tscn` | 隊員、邀請、離隊 | M2 |
| 組織 | `ui/panels/guild_panel.tscn` | 連署、位階 | M3 |
| 任務日誌 | `ui/panels/quest_log.tscn` | 進行中任務 | M1 |
| 戰鬥畫面 | `ui/battle/battle_screen.tscn` | 由下列子場景組成 | M1 |
| ├ 戰場格 | `ui/game/battle/battle_iso_view.gd`（+ `unit_sprite.gd`、`battle_fx.gd`） | 等角 12×8、地區背景、立繪、逃跑格、可移動範圍高亮、動畫 | M1 |
| ├ 時間棒 | `ui/battle/atb_bars.tscn` | 依 `battle_gauges` 錨點在本地外插，1 Hz 校正（10.6） | M1 |
| ├ 指令列 | `ui/battle/command_bar.tscn` | 移攻武特防休裝逃毒醫暗陣內穴，未解鎖灰色 | M1 |
| ├ 武功/招式/成數選擇 | `ui/battle/art_picker.tscn` | 1–10 成滑桿 | M1 |
| └ 戰報 | `ui/battle/battle_log.tscn` | 共用 TextRenderer | M1 |
| 玩家管理 | `ui/admin/player_admin.tscn` | 踢人、指定副主機、還原護照 | M2 |
| 製作群 | `ui/credits/credits.tscn` | CC BY 署名、OFL 字型、CC0 來源 | M4 |
| 共用元件 | `ui/common/` | `name_label.tscn`、`toast.tscn`、`confirm_dialog.tscn`、`text_renderer.gd`、`tooltip.tscn` | M1 |

所有 UI 只讀 `ClientState` 和 `GameData`、只透過 `NetworkManager.send_intent()` 送出操作。

---

## 13. GDScript 骨架

以下程式碼是骨架，標示 【API待驗證】 的地方要在 M0 用編輯器確認。

### 13.1 SteamManager（初始化、大廳、邀請）

```gdscript
# res://autoload/steam_manager.gd
extends Node

signal steam_initialized(ok: bool, reason: String)
signal lobby_hosted(lobby_id: int)                  # 主機：大廳建立成功
signal lobby_entered(lobby_id: int, owner_id: int)  # 任何人：進入大廳成功
signal lobby_error(reason: String)
signal lobby_list_received(lobbies: Array)

const APP_ID := 480
const LOBBY_TAG_KEY := "game"
const LOBBY_TAG_VALUE := "jymini_v1"   # 過濾 480 上的垃圾大廳
const MAX_MEMBERS := 8

var available := false
var steam_id: int = 0
var persona_name := ""
var lobby_id: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暫停時回呼也不能停【已證實】
	if "--no-steam" in OS.get_cmdline_user_args():
		_fail("Steam disabled by --no-steam")
		return
	if not Engine.has_singleton("Steam"):      # 【API待驗證】GDExtension 單例的偵測方式
		_fail("GodotSteam not loaded")
		return

	# 唯一的初始化路徑（2.1）：專案設定的自動初始化與 embed callbacks 必須關閉，否則會初始化兩次
	# steamInitEx(app_id, embed_callbacks)；兩個參數都可省略【已證實】
	# 舊版文件有第一個參數是 retrieve_stats 的寫法，4.23 以編輯器說明為準【API待驗證】
	var res: Dictionary = Steam.steamInitEx(APP_ID, false)
	var status := int(res.get("status", 1))
	if status != 0:   # 0 = OK；1 其他失敗、2 Steam 沒開、3 用戶端過舊【已證實】
		_fail("steamInitEx status=%d (%s)" % [status, str(res.get("verbal", ""))])
		return

	available = true
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	print("Steam OK: %s (%d)" % [persona_name, steam_id])

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	steam_initialized.emit(true, "")
	_check_cold_start_invite()

func _process(_delta: float) -> void:
	if available:
		Steam.run_callbacks()   # 每幀呼叫【已證實】；embed 已關閉，所以一定要自己呼叫

func _fail(reason: String) -> void:
	available = false
	push_warning("[SteamManager] " + reason)
	steam_initialized.emit(false, reason)

# ---------- 建立大廳（主機） ----------
func host_lobby() -> void:
	if not available:
		lobby_error.emit("steam_unavailable")
		return
	# LobbyType: PRIVATE=0, FRIENDS_ONLY=1, PUBLIC=2, INVISIBLE=3, PRIVATE_UNIQUE=4【已證實】
	# 常數名稱 Steam.LOBBY_TYPE_FRIENDS_ONLY【API待驗證】，不行就直接傳 1
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_MEMBERS)

func _on_lobby_created(connect_result: int, new_lobby_id: int) -> void:
	if connect_result != 1:   # 1 = Result OK（教學寫法）【已證實】
		lobby_error.emit("createLobby failed: %d" % connect_result)
		return
	lobby_id = new_lobby_id
	Steam.setLobbyJoinable(lobby_id, true)                      # 【API待驗證】
	Steam.setLobbyData(lobby_id, LOBBY_TAG_KEY, LOBBY_TAG_VALUE)
	Steam.setLobbyData(lobby_id, "proto", str(Protocol.VERSION))
	Steam.setLobbyData(lobby_id, "name", "%s 的江湖" % persona_name)
	lobby_hosted.emit(lobby_id)

# ---------- 加入大廳（客戶端） ----------
func join_lobby(target_lobby_id: int) -> void:
	if not available:
		lobby_error.emit("steam_unavailable")
		return
	Steam.joinLobby(target_lobby_id)

# lobby_joined(lobby_id, permissions(未使用，恆為 0), locked, response)【已證實】
func _on_lobby_joined(joined_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# response 1 = 成功（k_EChatRoomEnterResponseSuccess）
	# 常數名稱 Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS【API待驗證】
	if response != 1:
		lobby_error.emit("joinLobby failed: %d" % response)
		return
	lobby_id = joined_id
	var owner_id: int = Steam.getLobbyOwner(joined_id)
	lobby_entered.emit(joined_id, owner_id)   # 主機自己也會收到；NetworkManager 會忽略

# 遊戲已開時，在 Steam 好友清單按「加入遊戲」或接受邀請
# 訊號參數 (lobby_id, friend_id)【API待驗證：參數順序】
func _on_join_requested(requested_lobby_id: int, _friend_id: int) -> void:
	join_lobby(requested_lobby_id)

# 冷啟動：Steam 以 "+connect_lobby <id>" 啟動遊戲【已證實】
func _check_cold_start_invite() -> void:
	var args := OS.get_cmdline_args()
	var i := args.find("+connect_lobby")
	if i != -1 and i + 1 < args.size():
		var id := int(args[i + 1])
		if id > 0:
			join_lobby.call_deferred(id)

func open_invite_overlay() -> void:
	if available and lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)   # 【已證實】覆蓋介面在部分渲染器下可能不穩（1.1）

# 覆蓋介面打不開時的退路：遊戲內好友清單直接邀請（1.1）
func invite_friend(friend_steam_id: int) -> void:
	if available and lobby_id != 0:
		Steam.inviteUserToLobby(lobby_id, friend_steam_id)   # 【API待驗證】

func leave_lobby() -> void:
	if available and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0

# ---------- 搜尋（只會找到 PUBLIC 大廳；FRIENDS_ONLY 靠邀請或好友清單加入） ----------
func search_lobbies() -> void:
	Steam.addRequestLobbyListStringFilter(LOBBY_TAG_KEY, LOBBY_TAG_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)  # 常數名稱【API待驗證】
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	var result: Array = []
	for id in lobbies:
		result.append({
			"id": id,
			"name": Steam.getLobbyData(id, "name"),
			"proto": Steam.getLobbyData(id, "proto"),
			"members": Steam.getNumLobbyMembers(id),
		})
	lobby_list_received.emit(result)
```

> 「FRIENDS_ONLY 大廳不會出現在 `requestLobbyList` 結果裡」是根據 Steamworks 的一般行為【推論】。本作的主要流程是「邀請」與「好友清單加入」，搜尋畫面只在開發測試時用 PUBLIC 大廳。

### 13.2 NetworkManager（傳輸層與 SteamMultiplayerPeer）

```gdscript
# res://autoload/network_manager.gd
extends Node

enum Mode { NONE, OFFLINE, ENET_HOST, ENET_CLIENT, STEAM_HOST, STEAM_CLIENT }

signal session_started(mode: Mode)
signal session_ended(reason: String)

const ENET_DEFAULT_PORT := 24565

var mode: Mode = Mode.NONE
var _intent_seq := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): _end("connection_failed"))
	multiplayer.server_disconnected.connect(func(): _end("server_disconnected"))
	SteamManager.lobby_hosted.connect(_on_lobby_hosted)
	SteamManager.lobby_entered.connect(_on_lobby_entered)

func _set_peer(peer: MultiplayerPeer, new_mode: Mode) -> void:
	multiplayer.server_relay = false   # 主機權威：客戶端之間不互傳【API待驗證：要在設 peer 前或後】
	multiplayer.multiplayer_peer = peer
	mode = new_mode

# ---------- 離線 ----------
func start_offline(world_id: String) -> void:
	_set_peer(OfflineMultiplayerPeer.new(), Mode.OFFLINE)   # unique id = 1, is_server() = true
	WorldServer.start(world_id)
	ClientState.begin_local_session()
	session_started.emit(mode)

# ---------- ENet ----------
func start_enet_host(world_id: String, port := ENET_DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		return err
	_set_peer(peer, Mode.ENET_HOST)
	WorldServer.start(world_id)
	ClientState.begin_local_session()
	session_started.emit(mode)
	return OK

func start_enet_client(address: String, port := ENET_DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	_set_peer(peer, Mode.ENET_CLIENT)
	return OK   # 等 connected_to_server 再送 hello

# ---------- Steam ----------
var _pending_world_id := ""

func host_steam(world_id: String) -> void:
	_pending_world_id = world_id
	SteamManager.host_lobby()   # 等 lobby_hosted

func _on_lobby_hosted(_lobby_id: int) -> void:
	var peer := SteamMultiplayerPeer.new()
	# create_host(virtual_port = 0)【已證實】
	# 另有 host_with_lobby(lobby_id)，語意是「用大廳成員自動連線」，參數與行為【API待驗證】
	var err: Error = peer.create_host(0)
	if err != OK:
		SteamManager.leave_lobby()
		_end("steam_create_host_failed: %d" % err)
		return
	_set_peer(peer, Mode.STEAM_HOST)
	WorldServer.start(_pending_world_id)
	ClientState.begin_local_session()
	session_started.emit(mode)

func _on_lobby_entered(_lobby_id: int, owner_id: int) -> void:
	if owner_id == SteamManager.steam_id:
		return   # 自己是主機，已在 _on_lobby_hosted 處理
	var peer := SteamMultiplayerPeer.new()
	# create_client(host_steam_id, virtual_port = 0)【已證實】
	# 另有 connect_to_lobby(lobby_id)【API待驗證】
	var err: Error = peer.create_client(owner_id, 0)
	if err != OK:
		SteamManager.leave_lobby()
		_end("steam_create_client_failed: %d" % err)
		return
	_set_peer(peer, Mode.STEAM_CLIENT)

# ---------- 連線事件 ----------
func _on_connected_to_server() -> void:
	ClientState.send_hello()          # 客戶端連上後第一件事
	session_started.emit(mode)

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		WorldServer.on_peer_connected(peer_id)   # 開始 5 秒 hello 計時

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		WorldServer.on_peer_disconnected(peer_id)

func identity_for_peer(peer_id: int, claimed: String) -> String:
	# Steam 模式下用 peer 回報的真實 SteamID，忽略客戶端自報值
	if mode == Mode.STEAM_HOST:
		var sid: int = (multiplayer.multiplayer_peer as SteamMultiplayerPeer).get_steam_id_for_peer_id(peer_id)
		return "steam_%d" % sid
	return claimed   # ENet / 離線：信任本機設定檔的 local_<uuid>

func kick(peer_id: int, reason: String) -> void:
	# Steam 大廳沒有原生踢人：先通知，再由主機斷線【已證實：教學採此做法】
	ClientState.s2c_kicked.rpc_id(peer_id, reason)
	get_tree().create_timer(0.5).timeout.connect(_force_disconnect.bind(peer_id))

func _force_disconnect(peer_id: int) -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)   # SteamMultiplayerPeer 是否實作【API待驗證】

func leave() -> void:
	if multiplayer.is_server() and mode != Mode.NONE:
		WorldServer.stop()   # 會先存檔
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	SteamManager.leave_lobby()
	_end("left")

func _end(reason: String) -> void:
	mode = Mode.NONE
	session_ended.emit(reason)

# ---------- Intent 入口（UI 只呼叫這個） ----------
func send_intent(kind: String, args: Dictionary = {}) -> int:
	_intent_seq += 1
	if multiplayer.is_server():
		# 主機玩家與離線模式：本地短路，不走 RPC（見 6.4）
		WorldServer.handle_intent(multiplayer.get_unique_id(), _intent_seq, kind, args)
	else:
		WorldServer.c2s_intent.rpc_id(1, _intent_seq, kind, args)
	return _intent_seq
```

### 13.3 RPC intent 範例：向師父學武（消點）

```gdscript
# res://autoload/world_server.gd（節錄）
extends Node

var running := false
var world: WorldState = null
var sessions: Dictionary = {}       # peer_id -> Session
var _handlers: Dictionary = {}      # kind -> Callable
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_handlers = {
		Protocol.I_LEARN: _intent_learn,
		Protocol.I_MOVE: _intent_move,
		Protocol.I_BATTLE_CMD: _intent_battle_cmd,
		Protocol.I_CHAT: _intent_chat,
		# ……
	}

# 客戶端 → 主機的唯一 RPC 入口。每個 peer 上都存在（RPC 設定必須一致）
@rpc("any_peer", "call_remote", "reliable")
func c2s_intent(seq: int, kind: String, args: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	handle_intent(multiplayer.get_remote_sender_id(), seq, kind, args)

func handle_intent(peer_id: int, seq: int, kind: String, args: Dictionary) -> void:
	var s: Session = sessions.get(peer_id)
	if s == null or s.character == null:
		return
	if not s.rate_limiter.allow():
		return
	if not _handlers.has(kind) or not Protocol.validate_args(kind, args):
		ClientState.deliver_result(peer_id, seq, false, "bad_intent")
		return
	var result: Dictionary = _handlers[kind].call(s, args)
	ClientState.deliver_result(peer_id, seq, result.get("ok", false), result.get("reason", ""))

func _intent_learn(s: Session, args: Dictionary) -> Dictionary:
	var npc_id: String = args["npc"]
	var art_id: String = args["art"]
	var times: int = clampi(int(args.get("times", 1)), 1, 50)   # 一次最多連點 50 下
	var ch: Character = s.character

	if not world.regions.is_npc_present(npc_id, ch.region_id, world.time_s):
		return { "ok": false, "reason": "npc_not_here" }
	if ch.in_battle_id != 0 or ch.jailed():
		return { "ok": false, "reason": "busy" }

	# 純邏輯：檢查門派、師父上限、實戰上限（GDD 4.2）、學點與精是否足夠
	var check: Dictionary = Learning.can_learn_from_master(ch, npc_id, art_id, GameData.tables)
	if not check.ok:
		return check

	var outcome: Dictionary = Learning.study_with_master(ch, art_id, times, GameData.tables, rng)
	# outcome = { gained_prof, levels_up, spent_points, spent_jing, stopped_reason }
	s.mark_dirty(Session.DIRTY_SHEET)
	EventRouter.to_peer(s.peer_id, "SYSTEM", "learn_result", {
		"npc": npc_id, "art": art_id,
		"gain": outcome.gained_prof, "up": outcome.levels_up,
		"pts": outcome.spent_points, "jing": outcome.spent_jing,
	})
	if outcome.levels_up > 0:
		EventRouter.to_region(ch.region_id, "SCENE", "learn_level_up",
			{ "who": ch.id, "art": art_id, "lv": ch.skills.level_of(art_id) }, s.peer_id)
	return { "ok": true }
```

```gdscript
# res://autoload/client_state.gd（節錄）
extends Node

signal events_received(events: Array)
signal sheet_changed(sheet: Dictionary)
signal intent_result(seq: int, ok: bool, reason: String)

var sheet: Dictionary = {}
signal battle_tick_received(battle_id: int, tick: int, gauges: PackedByteArray)

var event_log := EventLogBuffer.new(2000)   # 不要命名為 log，會遮蔽內建的 log()

# 主機 → 客戶端：只有 authority（主機）能呼叫
@rpc("authority", "call_remote", "reliable")
func s2c_events(batch: Array) -> void:
	_apply_events(batch)

@rpc("authority", "call_remote", "reliable")
func s2c_sheet(new_sheet: Dictionary) -> void:
	_apply_sheet(new_sheet)

@rpc("authority", "call_remote", "reliable")
func s2c_intent_result(seq: int, ok: bool, reason: String) -> void:
	intent_result.emit(seq, ok, reason)

@rpc("authority", "call_remote", "unreliable_ordered")
func s2c_battle_tick(battle_id: int, tick: int, gauges: PackedByteArray) -> void:
	battle_tick_received.emit(battle_id, tick, gauges)   # 戰鬥 UI 訂閱

@rpc("authority", "call_remote", "reliable")
func s2c_kicked(reason: String) -> void:
	SceneRouter.show_disconnected("被主機請出：" + reason)

# 主機端呼叫：自己就本地處理，別人就 RPC（6.4 本地短路）
func deliver_events(peer_id: int, batch: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		_apply_events(batch)
	else:
		s2c_events.rpc_id(peer_id, batch)

func deliver_result(peer_id: int, seq: int, ok: bool, reason: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		intent_result.emit(seq, ok, reason)
	else:
		s2c_intent_result.rpc_id(peer_id, seq, ok, reason)

func _apply_events(batch: Array) -> void:
	for e in batch:
		event_log.push(e)
	events_received.emit(batch)

func _apply_sheet(new_sheet: Dictionary) -> void:
	sheet = new_sheet
	sheet_changed.emit(sheet)
```

UI 端（學武對話框）只需要：

```gdscript
func _on_learn_pressed() -> void:
	_pending_seq = NetworkManager.send_intent(Protocol.I_LEARN, { "npc": npc_id, "art": art_id, "times": 10 })
	learn_button.disabled = true
```

### 13.4 戰鬥狀態機骨架

```gdscript
# res://core/battle/battle.gd
class_name Battle
extends RefCounted

enum State { SETUP, RUNNING, AWAIT_COMMAND, RESOLVING, ENDED, REWARDS, CLOSED }
enum Result { NONE, VICTORY, DEFEAT, ALL_FLED, ABORTED }

const GAUGE_FULL := 100.0

var id: int
var state: State = State.SETUP
var result: Result = Result.NONE
var tick_no := 0
var units: Array[BattleUnit] = []
var grid: BattleGrid
var rng := RandomNumberGenerator.new()
var opts: Dictionary            # wait_mode, wait_mode_timeout_s
var _pending: Array[BattleUnit] = []   # READY 等指令的單位
var _wait_elapsed := 0.0
var _await_timeout := 20.0
var _out_events: Array = []

func _init(p_id: int, p_seed: int, p_opts: Dictionary) -> void:
	id = p_id
	rng.seed = p_seed
	opts = p_opts

## 由 BattleSystem 以 10 Hz 呼叫；回傳本 tick 產生的事件
func step(dt: float, tables: Dictionary) -> Array:
	_out_events.clear()
	match state:
		State.SETUP:
			grid.place_escape_tiles(rng)
			for u in units:
				u.last_rate = Formulas.atb_gain(u, tables)
			state = State.RUNNING
			_emit_gauges()
		State.RUNNING:
			tick_no += 1
			for u in units:
				if u.can_charge():
					u.last_rate = Formulas.atb_gain(u, tables)   # GDD 5.3
					u.gauge += u.last_rate
					if u.gauge >= GAUGE_FULL and not _pending.has(u):
						_pending.append(u)
			if not _pending.is_empty():
				_sort_ready(_pending)
				_dispatch_ready(tables)
		State.AWAIT_COMMAND:
			_wait_elapsed += dt
			if _wait_elapsed >= _await_timeout:   # 依人數、每輪預算、afk 算出（10.7）
				for u in _pending:
					if u.queued_cmd.is_empty():
						u.queued_cmd = { "cmd": "DEFEND" }   # 逾時自動防
			if _pending.all(func(u): return not u.queued_cmd.is_empty()):
				_resolve_all(tables)
	return _out_events.duplicate()

func _dispatch_ready(tables: Dictionary) -> void:
	for u in _pending:
		if u.is_ai():
			u.queued_cmd = BattleAI.choose(self, u, tables, rng)
	var humans_waiting := _pending.any(func(u): return u.queued_cmd.is_empty())
	if humans_waiting and opts.wait_mode:
		state = State.AWAIT_COMMAND
		_wait_elapsed = 0.0
		_await_timeout = BattleRules.await_timeout(self, _pending, opts)   # 10.7
		_emit("battle_await", { "units": _pending.map(func(u): return u.uid),
			"deadline_tick": tick_no + int(ceil(_await_timeout / 0.1)) })
		_emit_gauges()   # 時間棒錨點（10.6）：暫停時送一次
	else:
		_resolve_all(tables)   # 非等待模式：只結算已有指令者，其餘停在滿條

## 玩家指令（主機驗證過 peer 與 unit 歸屬之後呼叫）
func submit(unit_uid: int, cmd: Dictionary, tables: Dictionary) -> String:
	var u := _unit(unit_uid)
	if u == null or not _pending.has(u):
		return "not_ready"
	var err := BattleRules.validate_cmd(self, u, cmd, tables)   # 射程、內力、逃跑格……
	if err != "":
		return err
	u.queued_cmd = cmd
	return ""

func _resolve_all(tables: Dictionary) -> void:
	state = State.RESOLVING
	for u in _pending.duplicate():
		if u.queued_cmd.is_empty():
			continue
		_out_events.append_array(BattleRules.execute(self, u, u.queued_cmd, tables, rng))
		u.queued_cmd = {}
		u.gauge = 0.0
		_pending.erase(u)
		if _check_end():
			return
	state = State.RUNNING
	_emit_gauges()   # 行動後速度與時間棒改變，送新錨點

func _emit_gauges() -> void:
	_emit("battle_gauges", { "tick": tick_no, "units": units.map(func(u):
		return [u.uid, u.gauge, u.last_rate, u.can_charge()]) })

func _check_end() -> bool:
	var allies_alive := units.any(func(u): return u.side == 0 and u.is_active())
	var enemies_alive := units.any(func(u): return u.side == 1 and u.is_active())
	if allies_alive and enemies_alive:
		return false
	if not enemies_alive:
		result = Result.VICTORY
	elif units.any(func(u): return u.side == 0 and u.fled):
		result = Result.ALL_FLED
	else:
		result = Result.DEFEAT
	state = State.ENDED
	_emit("battle_end", { "result": result })
	return true

func _sort_ready(list: Array[BattleUnit]) -> void:
	list.sort_custom(func(a, b):
		if a.gauge != b.gauge: return a.gauge > b.gauge
		if a.agi != b.agi: return a.agi > b.agi
		return a.uid < b.uid)   # 最後以 uid 決定，避免依賴不穩定的排序

func _unit(uid: int) -> BattleUnit:
	for u in units:
		if u.uid == uid: return u
	return null

func _emit(key: String, p: Dictionary) -> void:
	_out_events.append({ "ch": "BATTLE", "key": key, "p": p, "bid": id })
```

`REWARDS` 與 `CLOSED` 由 `BattleSystem` 處理（它需要存取角色檔與世界狀態，`Battle` 本身不碰）。

### 13.5 GameData 載入（含 float→int 轉型）

```gdscript
# res://core/data/data_loader.gd
class_name DataLoader
extends RefCounted

const FILES := ["eras", "rule_profiles", "attributes", "basic_skills", "sects", "sect_rules",
	"martial_arts", "masters", "regions", "npcs", "monsters", "items", "quests", "status_effects",
	"text_templates"]
# patches/*.json 與 maps/*.json 另外逐檔載入，也計入 content_hash（此處省略）

var all_tables: Dictionary = {}  # table_name -> { id -> row }，全部 era（5.5.4）
var errors: PackedStringArray = []
var content_hash := ""

## 載入全部 era 的資料；篩選交給 activate()
func load_all(dir := "res://data") -> bool:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	for name in FILES:
		var path := "%s/%s.json" % [dir, name]
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("missing or empty: " + path)
			continue
		hasher.update(text.to_utf8_buffer())
		var json := JSON.new()
		if json.parse(text) != OK:
			errors.append("%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
			continue
		var by_id := {}
		for row in json.data.get("rows", []):
			DataSchema.coerce(name, row)        # 把整數欄位從 float 轉回 int
			var id: String = row.get("id", "")
			if id == "" or by_id.has(id):
				errors.append("%s: empty or duplicate id '%s'" % [name, id])
				continue
			if name not in ["eras", "rule_profiles"] and not row.has("era"):
				errors.append("%s.%s: missing era" % [name, id])   # era 為必填（5.5.2）
				continue
			by_id[id] = row
		all_tables[name] = by_id
	content_hash = hasher.finish().hex_encode()
	return errors.is_empty()

## 依世界的 enabled_eras 產生生效視圖（5.5.2、5.5.3）；主機與客戶端呼叫同一個函式
func activate(enabled_eras: Array) -> Dictionary:
	var on := {}
	for e in enabled_eras:
		on[e] = true
	var view := {}
	for name in all_tables:
		var by_id := {}
		for id in all_tables[name]:
			var row: Dictionary = all_tables[name][id]
			if name == "eras" or name == "rule_profiles" or _row_active(row, on):
				by_id[id] = row.duplicate(true)   # 複製，patch 不會改到原始資料
		view[name] = by_id
	PatchApplier.apply(view, all_tables["eras"], on)   # 依 eras.order 套用 patches/<era>.json
	errors.append_array(DataSchema.check_references(view))   # 生效列只能引用生效列
	return view

static func _row_active(row: Dictionary, on: Dictionary) -> bool:
	if not on.has(row.get("era", "")):
		return false
	var until: String = row.get("era_until", "")
	return until == "" or not on.has(until)
```

`GameData`（Autoload）在 `_ready()` 建立 `DataLoader`、呼叫 `load_all()` 並保存 `content_hash`；載入失敗就在開機畫面列出錯誤，不進遊戲。開世界（主機）或收到 `s2c_welcome`（客戶端）時，`GameData.activate(enabled_eras, rule_profile)` 先檢查 `enabled_eras` 合法（含 `1.0A`、對 `requires` 封閉），再把 `loader.activate()` 的結果存成 `GameData.tables`，並把展開後的 rule_profile 存成 `GameData.rules`（5.6）。

### 13.6 原子存檔

```gdscript
# res://autoload/save_manager.gd（節錄）
const BAK_COUNT := 5

func write_json_atomic(path: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# 輪替備份：bak4→bak5 … 本體→bak1
	for i in range(BAK_COUNT - 1, 0, -1):
		var src := "%s.bak%d" % [path, i]
		if FileAccess.file_exists(src):
			DirAccess.rename_absolute(src, "%s.bak%d" % [path, i + 1])  # Windows 上覆寫既有檔的行為【API待驗證】
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak1")
	return DirAccess.rename_absolute(tmp, path)
```

---

## 14. 效能與頻寬預估

| 項目 | 預估 | 說明 |
|---|---|---|
| 同時在線 | 2–8 人 | 大廳上限 8（Steam 上限 250）【已證實】 |
| 主機邏輯 tick | 10 Hz | 文字遊戲，CPU 負擔極小 |
| 戰鬥時間棒 | 事件錨點（每次行動約 1 則，每單位約 10 bytes）+ 每場 1 Hz 校正 | 原本的 10 Hz 快照 8 場同時也遠低於 10 KB/s；改用錨點主要是減少封包數與等待時的空送（10.6） |
| 等待模式節奏 | 8 人一輪最壞約 45 秒（預算上限）+ 少數 8 秒逾時 | 舊設定（每人 20 秒）最壞 160 秒，見 10.7 |
| 事件 | 每人每秒個位數則 | 每幀批次送出 |
| 角色表 | 約 5–15 KB（JSON 字典序列化後） | dirty 才送，每秒最多 4 次；M4 改差異更新 |
| 世界存檔 | 小於 1 MB | 每 60 秒寫一次，寫入時間可忽略 |

---

## 15. 測試策略

### 15.1 層級

| 層級 | 工具 | 對象 | 何時跑 |
|---|---|---|---|
| 單元測試 | `tests/run_tests.gd`（自帶執行器） | `core/`：公式、學武、門規、善惡/PK、死亡規則、requirements、Battle 狀態機、存檔 to_dict/from_dict | 每次改 `core/` |
| 資料檢查 | `tools/data_lint.gd` | 所有 JSON：語法、必填欄位（含 `era`）、重複 id、交叉參照（對每個 era 的 `requires` 閉包各跑一次 `activate()`，5.5.2）、patch 目標存在、rule_profiles 開關齊全、`src: unverified` 清單 | 每次改 `data/` |
| 平衡模擬 | `tools/balance_sim.gd` | 對照 GDD 5.6 的校準目標（新手打野兔 8–15 點；實戰 1 萬適合鬼王洞） | 改公式或怪物數值時 |
| 決定性回放 | `tests/run_tests.gd` | 固定種子 + 固定指令序列 → 比對「黃金」事件紀錄（`tests/fixtures/battle_*.json`） | 每次改戰鬥 |
| 連線冒煙 | `tools/net_smoke.gd` | 1 個 ENet 主機 + 2 個 bot 客戶端，跑腳本化流程 | 每次改網路或協定 |
| Steam 手動測試 | 檢查清單（15.4） | 兩個 Steam 帳號、兩台電腦 | 每個里程碑結束前 |

### 15.2 指令

```bash
# 第一次在乾淨的 checkout 上，先匯入資源（建立 .godot/）
godot --headless --path game --import            # --import 旗標【API待驗證：4.6 是否可用；不行就用 --editor --quit】

# 單元＋整合測試（自帶執行器，跑 tests/unit 與 tests/integration 的 test_*.gd；有失敗就結束碼 1）
godot --headless --path game --script res://tests/run_tests.gd -- --no-steam [--filter=<字串>]

# 資料檢查（非 0 結束碼代表有錯）
godot --headless --path game --script res://tools/data_lint.gd

# 平衡模擬
godot --headless --path game --script res://tools/balance_sim.gd -- --runs=1000 --case=newbie_vs_rabbit

# 連線冒煙：tools/net_smoke.gd 會自己以 OS.create_process() 開一個主機和兩個 bot 客戶端
godot --headless --path game --script res://tools/net_smoke.gd -- --no-steam
```

- `--script` 模式下 Autoload 是否完整初始化【API待驗證】。為此 `core/` 不依賴 Autoload：`data_lint` 與 `balance_sim` 直接 `DataLoader.new().load_all()`。
- `net_smoke` 必須用正常的主場景模式啟動子程序（`godot --headless --path game -- --no-steam --enet-host ...`），因為它需要 Autoload。
- **測試結束一定要關掉所有子程序**：`net_smoke.gd` 記下每個 `OS.create_process()` 回傳的 pid，結束（含失敗、逾時 60 秒）時一律 `OS.kill(pid)`。`run_tests.gd` 跑完一定自行 `quit()`。手動在編輯器用「除錯 → 自訂執行實例」開多個實例測試後，也要記得全部關閉。

### 15.3 Bot 客戶端

`--bot=res://tests/bots/<name>.gd` 讓一個無介面實例照腳本送 intent 並斷言收到的事件，例如：

```
bots/learn_and_fight.gd：建角 → 走到少林 → 拜師 → 消點 10 次 → 去郊外踩地雷 → 戰鬥到勝利 → 斷言實戰 > 0
bots/pk_pair.gd：兩個 bot 叫戰 → 一方接受 → 戰到一方死亡 → 斷言屍體存在、PK值不變（叫戰不加 PK值）
bots/reconnect.gd：戰鬥中斷線 → 斷言單位自動「防」、戰鬥照常進行 → 戰鬥結束前重新連線 → 接回原戰鬥、角色狀態一致（M2_PLAN D4）
```

### 15.4 Steam 手動測試清單（M0 起每個里程碑都要跑）

- [ ] 兩個帳號、兩台電腦，都從 Steam 用戶端啟動（覆蓋介面才可靠）
- [ ] 主機建 FRIENDS_ONLY 大廳 → 用覆蓋介面邀請 → 對方**遊戲已開**時接受 → 連上、hello 通過
- [ ] 對方**遊戲沒開**時接受邀請（冷啟動）：記錄實際啟動的是本作還是 Spacewar（GDD 附錄 B 第 12 項）
- [ ] 好友清單「加入遊戲」
- [ ] 主機踢人 → 對方看到原因並回到標題
- [ ] 主機關遊戲 → 客戶端收到 `server_disconnected` → 主機重開 → 世界與角色完整
- [ ] Steam 沒開時啟動 → 顯示原因、單機模式可玩
- [ ] 1.1 的渲染器矩陣（Compatibility／ANGLE／Vulkan／D3D12）下覆蓋介面、邀請對話框、好友清單加入各測一次，記錄結果
- [ ] 確認專案設定的 Steam 自動初始化與 embed callbacks 都是關閉的（2.1），log 裡只出現一次初始化
- [ ] `tools/check_vendor.ps1` 通過：GodotSteam 二進位檔雜湊與 `VENDOR.md` 一致（2.2）
- [ ] 確認專案裡沒有 ExpressoBits 的 steam-multiplayer-peer（`addons/` 下只有一個提供 `SteamMultiplayerPeer` 的外掛）
- [ ] 匯出版（非編輯器）重測以上全部；確認 exe 旁有 `steam_api64.dll` 與 `steam_appid.txt`

---

## 16. 里程碑對應（技術面）

| 里程碑 | 技術交付 |
|---|---|
| **M0** | 第 2、3 章安裝（含 2.1 單一初始化路徑、2.2 vendoring 與雜湊紀錄）；1.1 渲染器矩陣實測；7 個 Autoload 的空殼；`eras.json`／`rule_profiles.json` 與 `activate()`；DataLoader + data_lint；三種傳輸 + `net_debug.tscn`（RPC 聊天）；hello 握手；原子存檔；單元測試執行器（`tests/run_tests.gd`）跑通；**第 17 章 API 全部驗證**；匯出一次 |
| **M1** | `core/rules` 全部 M1 公式 + 單元測試；Battle 狀態機 + 決定性回放測試；離線模式完整遊玩；主畫面與戰鬥 UI；TextRenderer |
| **M2** | Steam 大廳完整流程；EventRouter；聊天頻道；PK、屍體、飛鴿；角色護照；副主機快照（含 `lineage`）；時間棒錨點同步；10.7 等待模式節奏 + 8 bot 實測；bot 冒煙測試；Steam 手動清單；伺服器選項面板最小版（死亡規則、PK 模式、等待模式） |
| **M3** | 內容擴充只改 `data/`；新增 requirements type、狀態效果、陣法（多人指令同步）；開啟 `1.0B` era；rule_profile 各開關的規則實作與單元測試 |
| **M4** | 差異更新、效能剖析、伺服器選項面板完整版（`enabled_eras`、`sects_enabled`、`rule_profile` 選擇；M2 已有死亡規則、PK 模式、等待模式的最小版，見 12 章）、選用的專用主機模式（8.6）、製作群頁、正式 AppID 切換（移除 `steam_appid.txt`） |
| **M5 以後** | 後期官方資料片逐一以新 era 加入（`gmdk`、`khbd`、`qfcq`……），每個資料片：補 `eras.json` 的日期與 `requires` → 只新增 `data/` 列與 `patches/<era>.json` → 規則衝突新增 rule_profile 開關（預設 1.0 行為）→ `data_lint` 全組合通過 |

---

## 17. 待驗證 API 清單（M0 必須逐條勾銷）

| # | API／行為 | 本文假設 | 驗證方法 | 不成立時的替代 |
|---|---|---|---|---|
| [x] 1 | `Steam.steamInitEx(app_id, embed_callbacks)` 的參數順序 | `(480, false)`，回傳 `{status, verbal}` | 編輯器說明頁 | 依說明頁調整；舊版有 `retrieve_stats` 參數 |
| [x] 2 | `Engine.has_singleton("Steam")` 能偵測 GDExtension 單例 | true | 印出結果 | 改用 `ClassDB.class_exists("Steam")` |
| [x] 3 | 專案設定 Steam → Initialization 的確切項目名稱，以及「關閉」是否確實不會初始化 | app_id、initialize on startup、embed callbacks；兩個開關都關 | 打開進階設定查看；啟動 log 只出現一次初始化 | 本作只用程式初始化（2.1），找不到開關就確認 `project.godot` 裡沒有相關鍵值 |
| [x] 4 | `Steam.LOBBY_TYPE_FRIENDS_ONLY` 常數名稱 | 存在，值 1 | 說明頁 | 直接傳 `1` |
| [x] 5 | `Steam.setLobbyJoinable(lobby_id, bool)` | 存在 | 說明頁 | 預設即可加入，可省略 |
| [x] 6 | `join_requested` 訊號參數順序 | `(lobby_id, friend_id)` | 說明頁 | 依說明頁調整 |
| [x] 7 | `lobby_joined` 的 response 成功值與常數名稱 | 1 / `CHAT_ROOM_ENTER_RESPONSE_SUCCESS` | 說明頁 | 比對整數 1 |
| [x] 8 | `Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE` 常數名稱 | 存在 | 說明頁 | 省略距離篩選 |
| 9 | 大廳搜尋的預設 50 筆上限、篩選條件每次請求後重設 | Steamworks 行為 | 實測 | 每次搜尋前重設篩選 |
| [x] 10 | `SteamMultiplayerPeer.host_with_lobby()` / `connect_to_lobby()` 的參數與語意 | 未使用，改用 `create_host` / `create_client` | 說明頁 | — |
| 11 | `server_relay` 該設在哪裡、何時設 | `multiplayer.server_relay = false`，設 peer 前 | 實測客戶端互呼 RPC 是否被擋 | 設 peer 後再設；或在 RPC 處理器裡自行檢查 sender 是否為 1 |
| 12 | `SteamMultiplayerPeer.disconnect_peer()` 是否實作 | 有 | 實測踢人 | 只發 `s2c_kicked`，由客戶端自行斷線，並把該 identity 列入本場拒絕名單 |
| 13 | 主機 `rpc_id(1, …)` 給自己時的行為 | 不使用（本地短路） | — | — |
| 14 | 匯出時 `steam_api64.dll` 是否自動複製 | 是（GDExtension 相依） | 匯出後查看資料夾 | 匯出後腳本手動複製 |
| 15 | `.json` 是否一定被打包 | 加上 `*.json` 篩選保險 | 匯出後在 exe 上跑 data_lint 模式 | — |
| 16 | `DirAccess.rename_absolute` 在 Windows 上覆寫既有檔 | 不保證，所以先改名舊檔 | 單元測試 | 先 `remove_absolute` 再改名 |
| [x] 17 | `godot --headless --import` 旗標 | 4.6 可用 | 跑一次 | `godot --headless --editor --quit` |
| [x] 18 | `--script` 模式下 Autoload 是否初始化 | 不依賴 | — | — |
| 19 | 支援 Godot 4.6 的 GUT 版本 | GUT 9.x | 從 Asset Library 安裝後跑空測試 | 自寫簡易 `tests/run.gd`（assert + 結束碼）。**M0 決定：採用退路**，即 `tests/run_tests.gd` + `tests/test_case.gd`，不 vendor GUT |
| 20 | `SceneMultiplayer.auth_callback` 握手 | M2 再評估 | 說明頁 | 維持 hello RPC |
| 21 | Steam 單則訊息大小上限 | 快照超過 256 KB 就分段 | Steamworks 文件 | 分段大小再調小 |
| 22 | 冷啟動接受邀請會不會啟動 Spacewar | 未知 | 兩帳號實測（15.4） | 請好友先開遊戲再接受邀請 |
| 23 | 哪個渲染器／驅動下 Steam 覆蓋介面穩定 | 推論 Compatibility 較好 | 1.1 的四格矩陣實測 | 採用表現最好者；都不行就用 #25 的遊戲內邀請 |
| 24 | Godot 4.6.3 在 Windows 新專案的 `rendering/rendering_device/driver.windows` 預設值；Compatibility 的 ANGLE 退回設定名稱與命令列 `--rendering-driver opengl3_angle` | 可能是 d3d12 | 新建專案後查看專案設定；命令列跑一次 | 依實際值更新 1.1 |
| [x] 25 | `Steam.inviteUserToLobby(lobby_id, steam_id)` | 存在，可繞過覆蓋介面邀請 | 說明頁 | 請好友從 Steam 好友清單「加入遊戲」 |
| 26 | 無介面（`--headless`）下 GodotSteam 初始化、`run_callbacks()`、`SteamMultiplayerPeer` 是否正常 | 正常（一般版 GodotSteam，非 server 版） | M4 在專用主機上實測 | 專用主機只提供 ENet 模式 |
| [x] 27 | GodotSteam 4.23 壓縮檔的實際檔名與內含檔案清單 | 含 `addons/godotsteam/` | 下載後記入 `VENDOR.md` | — |

勾選方式：`[x]` 表示已在 M0 對實際 GodotSteam 4.23（Godot 4.6.3、Windows、Steam 用戶端執行中）核對過，結果見 17.1；沒勾的仍待驗證。

### 17.1 M0 驗證結果（2026-10-17）

名稱與簽名由 `tools/steam_api_probe.gd`（`ClassDB` 列舉）取得；執行行為由無介面實際執行取得。

| # | 實際觀察到的名稱／簽名／行為 |
|---|---|
| 1 | `steamInitEx(app_id: int = 0, embed_callbacks: bool = false) -> Dictionary`，沒有 `retrieve_stats` 參數。Steam 執行中回傳 `{ "status": 0, "verbal": "" }`（鍵名 `status`、`verbal` 已證實）；`get_steam_init_result()` 回傳同樣結構。`STEAM_API_INIT_RESULT_OK = 0`、`STEAM_API_INIT_RESULT_NO_STEAM_CLIENT = 2` |
| 2 | `Engine.has_singleton("Steam")` 與 `ClassDB.class_exists("Steam")` 都是 `true`；`SteamMultiplayerPeer` 可實例化，父類別 `MultiplayerPeerExtension` |
| 3 | 4.23 的設定名稱：`steam/initialization/app_data/app_id`（另有 `app_type`、`demo_id`、`playtest_id`、`tool_id`）、`steam/initialization/processes/initialize_on_startup`、`steam/initialization/processes/embed_callbacks`、`steam/multiplayer_peer/max_channels`（預設 4）、`steam/settings/enable_debug`。兩個開關設為 false 時，啟動 log 只出現一次初始化（本作的 `steamInitEx`） |
| 4 | `LOBBY_TYPE_PRIVATE = 0`、`LOBBY_TYPE_FRIENDS_ONLY = 1`、`LOBBY_TYPE_PUBLIC = 2`、`LOBBY_TYPE_INVISIBLE = 3`；`createLobby(lobby_type: int, max_members: int = 2) -> void`，結果走 `lobby_created(connect: int, lobby_id: int)`，成功時 `connect == RESULT_OK (1)`；480 上實測建立成功 |
| 5 | `setLobbyJoinable(steam_lobby_id: int, joinable: bool) -> bool` 存在 |
| 6 | `join_requested(lobby_id: int, steam_id: int)`，順序與假設相同 |
| 7 | `lobby_joined(lobby: int, permissions: int, locked: bool, response: int)`；`CHAT_ROOM_ENTER_RESPONSE_SUCCESS = 1` |
| 8 | `LOBBY_DISTANCE_FILTER_WORLDWIDE = 3`（`DEFAULT = 1`）；`addRequestLobbyListDistanceFilter(distance_filter: int)`、`addRequestLobbyListStringFilter(key_to_match, value_to_match, comparison_type)`、`LOBBY_COMPARISON_EQUAL = 0`；`lobby_match_list(lobbies: Array)` |
| 10 | `host_with_lobby(lobby_id: int) -> int`、`connect_to_lobby(lobby_id: int) -> int` 存在（語意未測，本作不用）。本作使用的 `create_host(virtual_port: int = 0) -> int`、`create_client(steam_id: int, virtual_port: int = 0) -> int` 存在，`create_host` 已在無介面主機實測回 OK。另有 `add_peer`、`get_peer`、`get_steam_id_for_peer_id`、`get_peer_id_for_steam_id` |
| 11（部分，未勾） | `SteamMultiplayerPeer` **有** `server_relay` 屬性，預設 false（修正 6.x 的說法）；`SceneMultiplayer.server_relay` 預設 true，本作在設 peer 前後都設為 false。客戶端互呼 RPC 是否被擋仍待兩帳號實測 |
| 12（部分，未勾） | `disconnect_peer` 為繼承自 `MultiplayerPeer` 的方法，可呼叫；Steam 下實際踢人仍待實測 |
| 17 | `godot --headless --path . --import` 在 4.6.3 可用，結束碼 0 |
| 18 | `--script` 模式下 Autoload 會初始化（SteamManager 在 `--script` 下也完成 Steam 初始化） |
| 25 | `inviteUserToLobby(steam_lobby_id: int, steam_id_invitee: int) -> bool` 存在；`activateGameOverlayInviteDialog(lobby_id: int)` 存在 |
| 26（部分，未勾） | 無介面下 `steamInitEx`、`run_callbacks()`、`createLobby`、`SteamMultiplayerPeer.create_host` 都正常；與遠端客戶端的 P2P 仍待 M4 實測 |
| 27 | 見 `addons/godotsteam/VENDOR.md` 與 `docs/research/m0_vendor_notes.md`（`godotsteam-4.23-gdextension-plugin-4.4.zip`） |

其他觀察：`getFriendCount(friend_flags: int = 65535)`，`FRIEND_FLAG_IMMEDIATE = 4`；`get_godotsteam_version()` 回傳 `"4.23"`。關閉遊戲時要先關閉 `SteamMultiplayerPeer` 再呼叫 `steamShutdown()`，否則 Steam 會記錄「still have sockets open」（已在 SteamManager／NetworkManager 的 `_exit_tree` 處理）。

---

## 附錄：參考來源

- GodotSteam 初始化：https://godotsteam.com/tutorials/initializing/
- GodotSteam 大廳教學：https://godotsteam.com/tutorials/lobbies/
- GodotSteam Matchmaking 類別：https://godotsteam.com/classes/matchmaking/
- GodotSteam MultiplayerPeer 類別／教學／變更紀錄：https://godotsteam.com/classes/multiplayer_peer/ 、https://godotsteam.com/tutorials/multiplayer_peer/ 、https://godotsteam.com/changelog/multiplayer_peer/
- GodotSteam release 與部落格：https://github.com/GodotSteam/GodotSteam/releases （已封存）、https://godotsteam.com/blog/
- Godot 商店 GodotSteam GDExtension：https://store.godotengine.org/asset/godotsteam/godotsteam-gdextension/
- Godot 高階多人連線：https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- Godot FileAccess：https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
