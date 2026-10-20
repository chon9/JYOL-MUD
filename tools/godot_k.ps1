# 用「不寫 C:」的方式開 Godot 編輯器／匯入資源（PowerShell 5.1）。
# Godot 編輯器的設定、快取、暫存檔平常寫在 %APPDATA%\Godot、%LOCALAPPDATA%\Godot、%TEMP%；
# 這支把這三個環境變數指到 ..\JY-Mini-OL-Work\godot_home\（跟 tools\export_release.ps1 同一個），再把其餘參數原樣交給 Godot。
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\godot_k.ps1 --headless --path . --import   # 匯入資源（新增 class_name 後）
#   powershell -ExecutionPolicy Bypass -File tools\godot_k.ps1 -e --path .                    # 開編輯器
# 遊戲本身（--path . 執行、測試、bot、tools/*.gd）不需要這支：資料根目錄由 data_root.txt 決定，引擎記錄檔與著色器快取已在 project.godot 關掉。
$ErrorActionPreference = "Stop"
$Godot = if ($env:JY_GODOT) { $env:JY_GODOT } else { "K:\Godot\Godot_v4.6.3-stable_win64_console.exe" }
$Project = Split-Path -Parent $PSScriptRoot
$GodotHome = Join-Path (Split-Path -Parent $Project) "JY-Mini-OL-Work\godot_home"
$HomeAppData = Join-Path $GodotHome "AppData\Roaming"
$HomeLocal = Join-Path $GodotHome "AppData\Local"
$HomeTemp = Join-Path $GodotHome "Temp"
foreach ($d in @($HomeAppData, $HomeLocal, $HomeTemp)) { New-Item -ItemType Directory -Force $d | Out-Null }
$env:APPDATA = $HomeAppData; $env:LOCALAPPDATA = $HomeLocal; $env:TEMP = $HomeTemp; $env:TMP = $HomeTemp
Push-Location $Project
try {
    & $Godot @args
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $code
