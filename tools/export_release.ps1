# 匯出 Windows 正式版到專案旁邊的 JY-Mini-OL-Release 資料夾（快照：之後改程式碼不會影響這份 .exe）。
# 用法（PowerShell 5.1）：powershell -ExecutionPolicy Bypass -File tools\export_release.ps1
#
# 可攜版：輸出資料夾裡有 data_root.txt（內容 userdata）→ 遊戲把存檔／設定／記錄檔都寫在 <輸出資料夾>\userdata\，
#   不寫 %APPDATA%。重新匯出只覆蓋 .exe／.pck／.dll／txt，**絕不刪除或覆蓋 userdata\**（匯出前後比對雜湊，變了就報錯）；
#   已存在的 data_root.txt 也不覆蓋（你改過的路徑會保留）。
# 不寫 C:：匯入／匯出時把 Godot 編輯器的 APPDATA／LOCALAPPDATA／TEMP 指到 -GodotHome（預設 ..\JY-Mini-OL-Work\godot_home），
#   編輯器設定、快取、暫存檔都落在 K:。匯出範本第一次會從 %APPDATA%\Godot\export_templates\4.6.3.stable\ 複製（只讀）過去。
param(
    [string]$Godot = "K:\Godot\Godot_v4.6.3-stable_win64_console.exe",
    [string]$OutDir = "",
    [string]$GodotHome = "",
    [switch]$InfoOnly          # 只重寫 版本資訊.txt，不重新匯出
)
$ErrorActionPreference = "Stop"
$Project = Split-Path -Parent $PSScriptRoot
$Parent = Split-Path -Parent $Project
if ($OutDir -eq "") { $OutDir = Join-Path $Parent "JY-Mini-OL-Release" }
if ($GodotHome -eq "") { $GodotHome = Join-Path $Parent "JY-Mini-OL-Work\godot_home" }
$Exe = Join-Path $OutDir "JY-Mini OL.exe"
$UserData = Join-Path $OutDir "userdata"

# ---- 版本資訊.txt：版本、匯出時間、連線協定、資料指紋（從匯出的 .pck 讀）、本版更新 ----
function Write-VersionInfo([string]$OutDir, [string]$Project, [string]$Godot, [string]$GodotHome) {
    $pck = Join-Path $OutDir "JY-Mini OL.pck"
    $ver = (Select-String -Path (Join-Path $Project "export_presets.cfg") -Pattern 'application/product_version="([^"]+)"').Matches[0].Groups[1].Value
    $probe = Join-Path $Project "tools\print_build_info.gd"
    $tmpRoot = Join-Path (Split-Path -Parent $Project) "JY-Mini-OL-Work\testdata\build_info"
    $saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA; TEMP = $env:TEMP; TMP = $env:TMP }
    try {
        if ($GodotHome -ne "") {
            $env:APPDATA = Join-Path $GodotHome "AppData\Roaming"; $env:LOCALAPPDATA = Join-Path $GodotHome "AppData\Local"
            $env:TEMP = Join-Path $GodotHome "Temp"; $env:TMP = $env:TEMP
        }
        # Godot 會印出無害的 ERROR（例如 Steam 外掛在 --main-pack 下找不到）；PS 5.1 會把 stderr 當成錯誤，這裡暫時放行
        $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $out = & $Godot --headless --main-pack $pck --script $probe -- --no-steam "--data-root=$tmpRoot" 2>&1 | Out-String
        $ErrorActionPreference = $eap
    } finally {
        foreach ($k in $saved.Keys) { Set-Item -Path "env:$k" -Value $saved[$k] }
    }
    $proto = if ($out -match 'PROTOCOL=(\d+)') { $Matches[1] } else { "?" }
    $hash = if ($out -match 'CONTENT_HASH=sha256:([0-9a-f]+)') { $Matches[1] } else { "" }
    $short = if ($hash.Length -ge 12) { $hash.Substring(0, 12) } else { "?" }
    $stamp = (Get-Item $pck).LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    # 從 docs\CHANGELOG.md 抄出同版本號那一節
    $notes = ""
    $cl = Join-Path $Project "docs\CHANGELOG.md"
    if (Test-Path $cl) {
        $lines = Get-Content $cl -Encoding UTF8
        $on = $false
        foreach ($l in $lines) {
            if ($l -match '^## ') { $on = $l.Contains($ver) ; continue }
            if ($on) { $notes += $l + "`r`n" }
        }
    }
    if ($notes.Trim() -eq "") { $notes = "（本版更新說明待補）`r`n" }
    $txt = @"
JY-Mini OL 版本資訊
==================
版本：　　$ver
匯出時間：$stamp
連線協定：$proto
資料指紋：$short

跟朋友連線前請互相對照：「連線協定」與「資料指紋」兩個都一樣才能連線。
（完整指紋：sha256:$hash）

本版更新：
$($notes.TrimEnd())
"@
    [System.IO.File]::WriteAllText((Join-Path $OutDir "版本資訊.txt"), $txt, (New-Object System.Text.UTF8Encoding $true))
    Write-Host "已寫入 版本資訊.txt：$ver／協定 $proto／指紋 $short"
}

# ---- 發佈包：不含 userdata（存檔）的乾淨資料夾＋zip，給新舊玩家 ----
function Write-Distribution([string]$OutDir, [string]$Project) {
    $ver = (Select-String -Path (Join-Path $Project "export_presets.cfg") -Pattern 'application/product_version="([^"]+)"').Matches[0].Groups[1].Value
    $distRoot = Join-Path (Split-Path -Parent $Project) "JY-Mini-OL-Dist"
    $name = "JY-Mini-OL_v$ver"
    $dir = Join-Path $distRoot $name
    $zip = Join-Path $distRoot "$name.zip"
    if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }   # 發佈資料夾是產物，可重建；不含任何存檔
    if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($f in @("JY-Mini OL.exe", "JY-Mini OL.pck", "libgodotsteam.windows.template_release.x86_64.dll", "steam_api64.dll", "steam_appid.txt", "data_root.txt", "如何遊玩.txt", "版本資訊.txt")) {
        $src = Join-Path $OutDir $f
        if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $dir $f) -Force }
    }
    $upd = @"
JY-Mini OL 安裝／更新說明（版本 $ver）

【第一次玩】
把整個資料夾解壓縮到任何可寫入的地方（例如 D:\Games\JY-Mini OL\），雙擊「JY-Mini OL.exe」。
不要放在 C:\Program Files（無法寫入存檔）。存檔會自動建立在同一個資料夾的 userdata\ 裡。

【已經在玩，要更新】
把這個壓縮檔裡的所有檔案，解壓縮覆蓋到你原本的遊戲資料夾（選「取代」）。
這個發佈包裡沒有 userdata\，所以你原本的存檔不會被蓋掉。
更新前想保險的話，先把原本的 userdata\ 資料夾複製一份備份。

【從 0.4 以前的版本更新（資料夾裡原本沒有 data_root.txt）】
舊版的存檔在 %APPDATA%\Godot\app_userdata\JY-Mini OL\。更新後遊戲改讀遊戲資料夾裡的 userdata\，
請把舊位置裡的 worlds、profiles、passports、map_memory 資料夾和 settings.json 複製到 <遊戲資料夾>\userdata\ 裡，角色就會回來。

【跟朋友連線】
打開「版本資訊.txt」互相對照：「連線協定」與「資料指紋」都一樣才能連線。
"@
    [System.IO.File]::WriteAllText((Join-Path $dir "安裝與更新說明.txt"), $upd, (New-Object System.Text.UTF8Encoding $true))
    Compress-Archive -Path (Join-Path $dir "*") -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "發佈包：$dir"
    Write-Host "壓縮檔：$zip ($([math]::Round((Get-Item $zip).Length / 1MB)) MB)"
}

if ($InfoOnly) {
    Write-VersionInfo $OutDir $Project $Godot $GodotHome
    Write-Distribution $OutDir $Project
    exit 0
}

# ---- Godot 編輯器的家目錄（不寫 C:） ----
$HomeAppData = Join-Path $GodotHome "AppData\Roaming"
$HomeLocal = Join-Path $GodotHome "AppData\Local"
$HomeTemp = Join-Path $GodotHome "Temp"
foreach ($d in @($HomeAppData, $HomeLocal, $HomeTemp)) { New-Item -ItemType Directory -Force $d | Out-Null }
$tplName = "windows_release_x86_64.exe"
$tplDir = Join-Path $HomeAppData "Godot\export_templates\4.6.3.stable"
if (-not (Test-Path (Join-Path $tplDir $tplName))) {
    $src = Join-Path $env:APPDATA "Godot\export_templates\4.6.3.stable"
    if (-not (Test-Path (Join-Path $src $tplName))) { throw "找不到 4.6.3 匯出範本：$src\$tplName（或 $tplDir）" }
    New-Item -ItemType Directory -Force $tplDir | Out-Null
    foreach ($f in @($tplName, "version.txt")) { Copy-Item (Join-Path $src $f) (Join-Path $tplDir $f) -Force }
    Write-Host "已複製匯出範本到 $tplDir"
}

function Get-TreeHash([string]$dir) {
    if (-not (Test-Path $dir)) { return "" }
    $lines = Get-ChildItem -LiteralPath $dir -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($dir.Length) + "|" + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    return ($lines -join "`n")
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$before = Get-TreeHash $UserData

$saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA; TEMP = $env:TEMP; TMP = $env:TMP }
try {
    $env:APPDATA = $HomeAppData; $env:LOCALAPPDATA = $HomeLocal; $env:TEMP = $HomeTemp; $env:TMP = $HomeTemp
    Write-Host "匯入資源…"
    & $Godot --headless --path $Project --import | Out-Null
    Write-Host "匯出到 $Exe …"
    & $Godot --headless --path $Project --export-release "Windows Release" $Exe
    $code = $LASTEXITCODE
} finally {
    foreach ($k in $saved.Keys) { Set-Item -Path "env:$k" -Value $saved[$k] }
}
if ($code -ne 0 -or -not (Test-Path $Exe)) { throw "匯出失敗（exit $code）" }

# Steamworks 從 .exe 同一層讀 steam_appid.txt（開發期 Spacewar 480）
Copy-Item (Join-Path $Project "steam_appid.txt") (Join-Path $OutDir "steam_appid.txt") -Force

# 可攜版資料根目錄（不覆蓋已存在的設定）
$cfg = Join-Path $OutDir "data_root.txt"
if (-not (Test-Path $cfg)) {
    [System.IO.File]::WriteAllText($cfg, "# 存檔資料夾（相對於本檔所在資料夾）。刪掉本檔＝改回 %APPDATA%\Godot\app_userdata\JY-Mini OL\`r`nuserdata`r`n", (New-Object System.Text.UTF8Encoding $false))
    Write-Host "已寫入 data_root.txt（userdata）"
} else {
    Write-Host "保留既有的 data_root.txt：$((Get-Content $cfg | Where-Object { $_ -notmatch '^\s*(#|$)' }) -join ' ')"
}

$after = Get-TreeHash $UserData
if ($before -ne $after) { throw "userdata 在匯出過程中被改動了！請檢查 $UserData" }

$ver = (Select-String -Path (Join-Path $Project "export_presets.cfg") -Pattern 'application/product_version="([^"]+)"').Matches[0].Groups[1].Value
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$howto = @"
JY-Mini OL（金庸群俠傳Online 懷舊重製・好友版）
版本 $ver　匯出時間 $stamp

【單機】雙擊「JY-Mini OL.exe」→ 標題畫面「單機」。
【區網／直連】標題畫面「區網開房」（主機，UDP 24565）／「區網加入」（輸入主機 IP）。
【Steam】兩邊先登入 Steam（互為好友）並開好遊戲 → 主機「Steam 開房」→「邀請好友」→ 朋友在 Steam 接受邀請。
　開發期使用 Spacewar（AppID 480），所以同資料夾要有 steam_appid.txt，請不要刪。

【存檔位置】這個資料夾裡的 userdata\（data_root.txt 指定；可攜版，不寫 C:\ 的 %APPDATA%）：
　worlds\（世界與角色）、profiles\（本機身分，角色綁在這裡）、passports\（角色護照）、map_memory\（大地圖探索）、
　settings.json（音量等設定）、logs\（記錄檔）。
【備份】關掉遊戲後，把整個 userdata\ 資料夾複製到別處即可；還原＝複製回來。
【更新版本】重新匯出只會換掉 .exe／.pck／.dll／txt，不會動 userdata\。
【給朋友】把這個資料夾複製給朋友時，**不要附上 userdata\**（裡面是你的身分與存檔；朋友用你的身分會跟你衝突）。
　朋友第一次開遊戲會在他自己的資料夾裡建新的 userdata\。資料夾請放在可寫入的位置（例如 D:\Games\），
　不要放在 C:\Program Files（不能寫入時遊戲會退回 %APPDATA%\Godot\app_userdata\JY-Mini OL\）。
"@
Set-Content -Path (Join-Path $OutDir "如何遊玩.txt") -Value $howto -Encoding UTF8

Write-VersionInfo $OutDir $Project $Godot $GodotHome
Write-Distribution $OutDir $Project

Write-Host "完成：" ; Get-ChildItem $OutDir | Select-Object Name, Length | Format-Table -AutoSize
