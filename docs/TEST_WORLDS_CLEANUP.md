# 舊測試世界整理（只搬移，不刪除）

## 現況（2026-10-19 晚：不再寫 C:）

- 遊戲、測試、工具都不再寫 `%APPDATA%\Godot\app_userdata\JY-Mini OL\`（見 README「存檔放在哪裡」）：
  - 正式版存檔：`K:\Project\JY-Mini-OL-Release\userdata\`（`data_root.txt`＝`userdata`）。
  - 開發／編輯器執行：`K:\Project\JY-Mini-OL-Work\userdata\`（專案根目錄 `data_root.txt`＝`../JY-Mini-OL-Work/userdata`）。
  - 所有測試（bot、`tools/*.gd`、`tests/run_tests.gd`）：`K:\Project\JY-Mini-OL-Work\testdata\`（測試根目錄，隨時可以整個刪掉，測試會自己重建）。
- 你的存檔（`worlds\jy2001`、`profiles\default`、`passports\jy2001`、`map_memory\ch_805b0b80.json`／`ch_9b614c72.json`、`settings.json`）
  已逐位元組複製到上面兩個 `userdata\`（雜湊清單：`K:\Project\JY-Mini-OL-Work\logs\owner_save_sha256.txt`）。
- 原本 `%APPDATA%\Godot\app_userdata\JY-Mini OL\` 的**全部內容**（你的存檔原件、`_test\`、`logs\`、`shader_cache\`）已**搬移**到
  `K:\Project\JY-Mini-OL-Work\appdata_old\`（搬之前的雜湊清單：`K:\Project\JY-Mini-OL-Work\logs\appdata_old_sha256.txt`），
  `%APPDATA%` 那個資料夾現在是空的（Godot 每次啟動仍會建立這個空資料夾，裡面不會有檔案）。
- 注意：本文件更早時提到的 `_backup_test_data_20261019\`（25 MB 舊測試世界備份）在搬遷前一次中斷的作業中遺失，`appdata_old\` 裡沒有它。

下面是**改版前**（測試還寫在真正存檔資料夾時）的整理紀錄，留作參考；片段裡的 `$root` 若要用在搬過去的舊資料上，改成 `K:\Project\JY-Mini-OL-Work\appdata_old`。

## 歷史紀錄（2026-10-19 早）

2026-10-19 起所有測試（bot、`tools/*.gd`、`tests/run_tests.gd`）都寫在 `user://_test/`（`--data-root`，見 README「測試」），
不會再出現在你自己的世界旁邊。這份文件處理**改版前**已經留在真正存檔資料夾裡的測試資料：

```
%APPDATA%\Godot\app_userdata\JY-Mini OL\
```

整理當下（2026-10-19）的狀況：`worlds\` 220 個、`profiles\` 362 個、`passports\` 56 個。
**沒有任何東西被刪除或搬動**；要不要搬由你決定，下面的 PowerShell 片段預設只列清單（dry-run）。

## 可能是你自己的（不會搬）

| 資料夾 | 名稱 | 理由 |
|---|---|---|
| worlds | `jy2001` | 你的世界 |
| worlds | `default` | 通用名稱（沒指定世界時的預設名稱也可能是它），裡面可能有你的角色 |
| worlds | `my_world` | README「怎麼玩 M1」的指令 |
| worlds | `steam_t`、`t_offline` | 不是任何 bot／工具／README 測試指令用的名字，看起來是手動測試；**不確定，保留** |
| worlds | `friends`、`lan_test`、`steam_test` | README 的連線遊玩指令（目前不存在；將來出現也不搬） |
| profiles | `default` | 沒帶 `--profile` 時的本機身分（你的角色都在這個身分下） |
| passports | `jy2001` | 你的世界的角色護照 |

## 明確是測試建立的

判斷依據：名字符合 bot／tools／README 測試指令與歷次測試執行用過的命名（`*accept*`、`close_*`、`leak*`、`bgm*`、`ui_play*`、`uibot*`、`m1*`、`m2*`、`m3a*`、`final_*`、`art2_*`、`w2001_*`、`rv*`、`v2_*`、`v3*`、`verify*`、`smoke*`、`probe*`… 完整規則見下方片段的 `$pattern`）。

### worlds（215 個）

```text
accfinal2 art2_791 badbot bgm5_check bgm_test bgm_test2
bgm_test3 cl_ui13106 close_bot_quit close_bot_wm close_m3a_quit close_m3a_wm
close_quit31777 close_quit9983 close_quit_042915 close_r3_quit close_r3_wm close_rv2_072309
close_rv_072309 close_wm20677 close_wm6913 close_wm_042915 close_x_r4q close_x_r4w
cmb_wpui_quit cmb_wpui_wm final_acc_10748 final_shot_21097 final_ui_18546 integ_accept
integ_accept_casual integ_accept_std integ_accept_strict leakcheck leakcheck2 leakcheck3
leakcheck4 leakui_19615 m1_accept m1_accept_casual m1_accept_m3a_1792360064 m1_accept_r3q
m1_accept_std m1_accept_strict m1_net m1_r3_9630 m1fix_casual2_012831 m1fix_casual_012131
m1fix_std_011856 m1fix_strict_012131 m2acc_0692 m2acc_13b8 m2acc_1a15 m2acc_1e57
m2acc_266e m2acc_340f m2acc_34e9 m2acc_3c8e m2acc_4757 m2acc_4b27
m2acc_53cb m2acc_53d2 m2acc_56d8 m2acc_5945 m2acc_6bea m2acc_6d7c
m2acc_7828 m2acc_7972 m2acc_851d m2acc_89c3 m2acc_89dd m2acc_9c3e
m2acc_b09c m2acc_c150 m2acc_dad9 m2acc_db24 m2acc_eaaf m2acc_f52a
m2acc_f5c8 m2acc_f9ae m2close_quit30963 m2close_wm19078 m2int_m1_casual_a7 m2int_m1_net_a7
m2int_m1_std_a7 m2int_m1_strict_a7 m2v_ui12863 m3a_accept_00b0 m3a_accept_077d m3a_accept_245c
m3a_accept_2bd4 m3a_accept_43d5 m3a_accept_48ef m3a_accept_4e49 m3a_accept_5d60 m3a_accept_6054
m3a_accept_7029 m3a_accept_70c2 m3a_accept_7bae m3a_accept_8c5f m3a_accept_ab40 m3a_accept_b378
m3a_accept_b9b5 m3a_accept_c072 m3a_accept_d21b m3a_accept_d35e m3a_accept_d685 m3a_accept_e0c2
m3m_accept_042525 net_smoke r4_accept_9708 rev1_big_6644 rev1_def_19688 review_bot2_19738
review_bot_13107 rv2_accept_19083 rv2_big rv2_def rv2_m1_19661 rv3m1_24713
ui_flee_4562 ui_play ui_play2 ui_play3 ui_play_042525 ui_play_1
ui_play_2 ui_play_3 ui_play_4 ui_play_bug1 ui_play_cd1 ui_play_cmd_1792353794
ui_play_dbg3 ui_play_final ui_play_fix1018b ui_play_fixshot1018b ui_play_fx1 ui_play_m2
ui_play_m2ui_25428 ui_play_m2ui_29519 ui_play_m2w ui_play_m3a ui_play_m3a_win ui_play_nodbg
ui_play_nodbg2 ui_play_r2 ui_play_r2a ui_play_r2b ui_play_r3 ui_play_r3_5239
ui_play_r3a ui_play_r3b ui_play_r3q ui_play_r4b ui_play_r4c ui_play_r4w
ui_play_r4w2 ui_play_rules034927 ui_play_rules035019 ui_play_rv1_5861 ui_play_rv2 ui_play_rv3
ui_play_shots ui_play_vfy1018 ui_play_vfyshot1018 ui_play_wpui ui_play_wpui2 ui_r4_18896
ui_r4b_17981 ui_r4d_2443 ui_r5b_5525 ui_r5d_17597 ui_r5h1_30086 ui_r5h2_11640
ui_r5h3_15040 ui_smoke ui_w2001 ui_window_check v2_default v2_std
v2_strict v3_strict v3a_ui8399 v3aclquit21785 v3aclwm20420 v_iso
verify_m1 verify_ui w2001_accept_cd1018 w2001_accept_fix1018b w2001_accept_fx1 w2001_accept_r3m2
w2001_accept_r4b w2001_accept_vfy1018 w2001_party_32590 w2001_r2fix_1792305247 w2001_r3big w2001_r3def
w2001_r4_1792295101 w2001_rv2_std w2001_scout_1019 w2001_scout_final w2001_verify_a22196 w_close_a
w_close_cmd_quit_1792353851 w_close_cmd_v_1792353866 w_close_cmd_wm_1792353848 w_cmd_m1_1792353576 w_rules_close_quit034851 w_rules_close_wm034848
w_rules_closev034901 w_rules_m1_034635 w_rv_m1_072309 w_scout_probe_net w_scout_probe_off
```

### profiles（361 個）

```text
accfinal2 art217567 bgm5check bgmbot bgmbot2 bgmbot3
closebot closebot_cmd_quit closebot_cmd_v closebot_cmd_wm closebot_quit closebot_r4q
closebot_r4w closebot_wm closecli closequit11697 closequit19843 closewm22361
closewm4943 clui14748 cmb_wpui_quit cmb_wpui_wm facc19294 fshot19474
fui19345 leakcheck leakcheck2 leakcheck3 leakcheck4 leakui11393
m1bot m1bot_casual m1bot_cmd m1bot_m3a m1bot_r2 m1bot_r3q
m1bot_r4b m1bot_rv072309 m1bot_std m1bot_strict m1bothost m1botparty
m1net m1net_a7 m2_leader_0692 m2_leader_13b8 m2_leader_1a15 m2_leader_1e57
m2_leader_266e m2_leader_340f m2_leader_34e9 m2_leader_3c8e m2_leader_4757 m2_leader_4b27
m2_leader_53cb m2_leader_53d2 m2_leader_56d8 m2_leader_5945 m2_leader_6bea m2_leader_6d7c
m2_leader_7828 m2_leader_7972 m2_leader_851d m2_leader_89c3 m2_leader_89dd m2_leader_9c3e
m2_leader_b09c m2_leader_c150 m2_leader_dad9 m2_leader_db24 m2_leader_eaaf m2_leader_f52a
m2_leader_f5c8 m2_leader_f9ae m2_member_0692 m2_member_13b8 m2_member_1a15 m2_member_1e57
m2_member_266e m2_member_340f m2_member_34e9 m2_member_3c8e m2_member_4757 m2_member_4b27
m2_member_53cb m2_member_53d2 m2_member_56d8 m2_member_5945 m2_member_6bea m2_member_6d7c
m2_member_7828 m2_member_7972 m2_member_851d m2_member_89c3 m2_member_89dd m2_member_9c3e
m2_member_b09c m2_member_c150 m2_member_dad9 m2_member_db24 m2_member_eaaf m2_member_f52a
m2_member_f5c8 m2_member_f9ae m2_pker_0692 m2_pker_13b8 m2_pker_1a15 m2_pker_1e57
m2_pker_266e m2_pker_340f m2_pker_34e9 m2_pker_3c8e m2_pker_4757 m2_pker_4b27
m2_pker_53cb m2_pker_53d2 m2_pker_56d8 m2_pker_5945 m2_pker_6bea m2_pker_6d7c
m2_pker_7828 m2_pker_7972 m2_pker_851d m2_pker_89c3 m2_pker_89dd m2_pker_9c3e
m2_pker_b09c m2_pker_c150 m2_pker_dad9 m2_pker_db24 m2_pker_eaaf m2_pker_f52a
m2_pker_f5c8 m2_pker_f9ae m2_victim_0692 m2_victim_13b8 m2_victim_1a15 m2_victim_1e57
m2_victim_266e m2_victim_340f m2_victim_34e9 m2_victim_3c8e m2_victim_4757 m2_victim_4b27
m2_victim_53cb m2_victim_53d2 m2_victim_56d8 m2_victim_5945 m2_victim_6bea m2_victim_6d7c
m2_victim_7828 m2_victim_7972 m2_victim_851d m2_victim_89c3 m2_victim_89dd m2_victim_9c3e
m2_victim_b09c m2_victim_c150 m2_victim_dad9 m2_victim_db24 m2_victim_eaaf m2_victim_f52a
m2_victim_f5c8 m2_victim_f9ae m2clquit28697 m2clwm17408 m2vui1723 m3a_emei_00b0
m3a_emei_077d m3a_emei_245c m3a_emei_2bd4 m3a_emei_43d5 m3a_emei_48ef m3a_emei_4e49
m3a_emei_5d60 m3a_emei_6054 m3a_emei_7029 m3a_emei_8c5f m3a_emei_ab40 m3a_emei_b378
m3a_emei_b9b5 m3a_emei_c072 m3a_emei_d21b m3a_emei_d685 m3a_emei_e0c2 m3a_gumu_00b0
m3a_gumu_077d m3a_gumu_245c m3a_gumu_2bd4 m3a_gumu_43d5 m3a_gumu_48ef m3a_gumu_4e49
m3a_gumu_6054 m3a_gumu_7029 m3a_gumu_7bae m3a_gumu_8c5f m3a_gumu_ab40 m3a_gumu_b378
m3a_gumu_c072 m3a_gumu_d21b m3a_gumu_d35e m3a_gumu_d685 m3a_gumu_e0c2 m3a_hengshan_00b0
m3a_hengshan_077d m3a_hengshan_245c m3a_hengshan_2bd4 m3a_hengshan_43d5 m3a_hengshan_48ef m3a_hengshan_4e49
m3a_hengshan_6054 m3a_hengshan_7029 m3a_hengshan_ab40 m3a_hengshan_b378 m3a_hengshan_c072 m3a_hengshan_d21b
m3a_hengshan_d685 m3a_hengshan_e0c2 m3a_jail_077d m3a_jail_245c m3a_jail_2bd4 m3a_jail_43d5
m3a_jail_48ef m3a_jail_4e49 m3a_jail_6054 m3a_jail_7029 m3a_jail_70c2 m3a_jail_b378
m3a_jail_c072 m3a_jail_d21b m3a_jail_d685 m3a_jail_e0c2 m3a_lingjiu_00b0 m3a_lingjiu_077d
m3a_lingjiu_245c m3a_lingjiu_2bd4 m3a_lingjiu_43d5 m3a_lingjiu_48ef m3a_lingjiu_4e49 m3a_lingjiu_6054
m3a_lingjiu_7029 m3a_lingjiu_ab40 m3a_lingjiu_b378 m3a_lingjiu_c072 m3a_lingjiu_d21b m3a_lingjiu_d685
m3a_lingjiu_e0c2 m3a_quanzhen_00b0 m3a_quanzhen_077d m3a_quanzhen_245c m3a_quanzhen_2bd4 m3a_quanzhen_43d5
m3a_quanzhen_48ef m3a_quanzhen_4e49 m3a_quanzhen_6054 m3a_quanzhen_7029 m3a_quanzhen_ab40 m3a_quanzhen_b378
m3a_quanzhen_c072 m3a_quanzhen_d21b m3a_quanzhen_d685 m3a_quanzhen_e0c2 m3a_wudang_00b0 m3a_wudang_077d
m3a_wudang_245c m3a_wudang_2bd4 m3a_wudang_43d5 m3a_wudang_48ef m3a_wudang_4e49 m3a_wudang_6054
m3a_wudang_7029 m3a_wudang_ab40 m3a_wudang_b378 m3a_wudang_c072 m3a_wudang_d21b m3a_wudang_d685
m3a_wudang_e0c2 m3a_xingxiu_00b0 m3a_xingxiu_077d m3a_xingxiu_245c m3a_xingxiu_2bd4 m3a_xingxiu_43d5
m3a_xingxiu_48ef m3a_xingxiu_4e49 m3a_xingxiu_6054 m3a_xingxiu_7029 m3a_xingxiu_70c2 m3a_xingxiu_ab40
m3a_xingxiu_b378 m3a_xingxiu_c072 m3a_xingxiu_d21b m3a_xingxiu_d685 m3a_xingxiu_e0c2 m3a_xuedao_00b0
m3a_xuedao_077d m3a_xuedao_245c m3a_xuedao_2bd4 m3a_xuedao_43d5 m3a_xuedao_48ef m3a_xuedao_4e49
m3a_xuedao_6054 m3a_xuedao_7029 m3a_xuedao_7bae m3a_xuedao_8c5f m3a_xuedao_b378 m3a_xuedao_c072
m3a_xuedao_d21b m3a_xuedao_d35e m3a_xuedao_d685 m3a_xuedao_e0c2 probebot probenet
reviewbot reviewbot2 rv2m1_14802 smoke_bot1 smoke_bot2 smoke_host
uibot uibot2 uibot3 uibot4 uibot_cmd uibot_m2ui
uibot_r1a uibot_r1b uibot_r2 uibot_r2a uibot_r2b uibot_r3
uibot_r3a uibot_r3b uibot_r3big uibot_r3def uibot_r3q uibot_r4b
uibot_r4c uibot_r4w uibot_r4w2 uibot_rv1 uibot_rv2a uibot_rv2b
uibot_wpui uibot_wpui2 uibothost uiflee uih1 uih2
uih3 uismoke uiverify uiwin v3aclquit10687 v3aclwm17580
v3aui20194 vb1 vb2 vb3 vb4 verifybot
viso
```

### passports（55 個，依世界名稱）

```text
art2_791 m1_accept_m3a_1792360064 m1_r3_9630 m2acc_266e m2acc_34e9 m2acc_4757
m2acc_53d2 m2acc_5945 m2acc_7828 m2acc_7972 m2acc_89c3 m2acc_89dd
m2acc_b09c m2acc_c150 m2acc_dad9 m2acc_db24 m2acc_f5c8 m2int_m1_casual_a7
m2int_m1_net_a7 m2int_m1_std_a7 m2int_m1_strict_a7 m3a_accept_077d m3a_accept_245c m3a_accept_2bd4
m3a_accept_48ef m3a_accept_4e49 m3a_accept_6054 m3a_accept_7029 m3a_accept_70c2 m3a_accept_7bae
m3a_accept_8c5f m3a_accept_b378 m3a_accept_b9b5 m3a_accept_c072 m3a_accept_d21b m3a_accept_d35e
m3a_accept_d685 m3a_accept_e0c2 m3m_accept_042525 rv2_m1_19661 rv3m1_24713 ui_play
ui_play_m2w w2001_accept_r3m2 w2001_accept_r4b w2001_host_1792300282 w2001_party_32590 w2001_r2fix_1792305247
w2001_rv2_std w2001_scout_1019 w2001_scout_final w2001_verify_a22196 w_cmd_m1_1792353576 w_rules_m1_034635
w_rv_m1_072309
```

### 其他測試資料夾（整個資料夾都是測試 log）

`m2_acceptance\`、`m3a_acceptance\`、`net_smoke\`。

`map_memory\`（每個角色到過的房間，純外觀）混了測試角色與你的角色，無法只看檔名分辨，**不動**；刪掉只會讓大地圖重新變黑。
`settings.json` 是你的設定，不動。

## 搬移片段（PowerShell 5.1）

先關掉遊戲。預設 `$dryRun = $true` 只列出會搬的項目；確認清單沒有你的東西後改成 `$false` 再跑一次。
東西會搬到 `JY-Mini OL\_backup_test_data_<日期時間>\`，要還原就把資料夾搬回原位。

```powershell
$root    = Join-Path $env:APPDATA 'Godot\app_userdata\JY-Mini OL'
$backup  = Join-Path $root ('_backup_test_data_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$pattern = '^(acc|accfinal|art2|badbot|bgm|cl_?ui|close|cmb_|facc|final_|fshot|fui|integ_|leak|m1|m2|m3a|m3m|net_smoke|probe|r4_|rev1|review|rv|smoke|ui|v2_|v3|v_iso|viso|vb\d|verify|w2001_|w_close|w_cmd|w_rules|w_rv|w_scout|release_check)'
$keep    = @('jy2001', 'default', 'my_world', 'friends', 'lan_test', 'steam_test', 'steam_t', 't_offline')
$dryRun  = $true   # 確認清單後改成 $false

$count = 0
foreach ($sub in @('worlds', 'profiles', 'passports')) {
    $src = Join-Path $root $sub
    if (-not (Test-Path -LiteralPath $src)) { continue }
    Get-ChildItem -LiteralPath $src -Directory |
        Where-Object { ($_.Name -match $pattern) -and ($keep -notcontains $_.Name) } |
        ForEach-Object {
            $count++
            if ($dryRun) {
                Write-Host ('[dry-run] ' + $sub + '\' + $_.Name)
            } else {
                $dst = Join-Path $backup $sub
                New-Item -ItemType Directory -Force -Path $dst | Out-Null
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path $dst $_.Name)
            }
        }
}
foreach ($d in @('m2_acceptance', 'm3a_acceptance', 'net_smoke')) {
    $p = Join-Path $root $d
    if (Test-Path -LiteralPath $p) {
        $count++
        if ($dryRun) {
            Write-Host ('[dry-run] ' + $d)
        } else {
            New-Item -ItemType Directory -Force -Path $backup | Out-Null
            Move-Item -LiteralPath $p -Destination (Join-Path $backup $d)
        }
    }
}
if ($dryRun) { Write-Host ("$count item(s) would be moved to $backup") } else { Write-Host ("moved $count item(s) to $backup") }
```

預期 dry-run 數量（2026-10-19）：worlds 215 ＋ profiles 361 ＋ passports 55 ＋ 3 個 log 資料夾 ＝ 634。

測試根目錄（現在是 `K:\Project\JY-Mini-OL-Work\testdata\`）隨時可以整個刪掉，測試會自己重建。
