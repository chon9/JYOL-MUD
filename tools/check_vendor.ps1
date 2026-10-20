# Verifies GodotSteam vendored files against the SHA-256 table in addons/godotsteam/VENDOR.md.
# PowerShell 5.1 compatible. Exit 0 = all match, 1 = mismatch/missing, 2 = VENDOR.md unreadable.
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$addonDir = Join-Path $ProjectRoot 'addons\godotsteam'
$vendorMd = Join-Path $addonDir 'VENDOR.md'

if (-not (Test-Path -LiteralPath $vendorMd)) {
    Write-Host "FAIL: $vendorMd not found"
    exit 2
}

$pattern = '^\|\s*`([^`]+)`\s*\|\s*([0-9a-fA-F]{64})\s*\|'
$entries = @()
foreach ($line in Get-Content -LiteralPath $vendorMd -Encoding UTF8) {
    if ($line -match $pattern) {
        $entries += New-Object PSObject -Property @{ Path = $Matches[1]; Hash = $Matches[2].ToLower() }
    }
}

if ($entries.Count -eq 0) {
    Write-Host "FAIL: no hash entries parsed from VENDOR.md"
    exit 2
}

$failed = 0
foreach ($e in $entries) {
    $file = Join-Path $addonDir ($e.Path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Host ("MISSING  {0}" -f $e.Path)
        $failed++
        continue
    }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
    if ($actual -eq $e.Hash) {
        Write-Host ("OK       {0}" -f $e.Path)
    } else {
        Write-Host ("MISMATCH {0}`n         expected {1}`n         actual   {2}" -f $e.Path, $e.Hash, $actual)
        $failed++
    }
}

# Only one addon may provide SteamMultiplayerPeer (TECH_ARCH 15.4).
$addonsRoot = Join-Path $ProjectRoot 'addons'
$others = Get-ChildItem -LiteralPath $addonsRoot -Recurse -Filter '*.gdextension' -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -ne $addonDir }
foreach ($o in $others) {
    if ((Get-Content -LiteralPath $o.FullName -Raw) -match '(?i)steam') {
        Write-Host ("CONFLICT another Steam GDExtension found: {0}" -f $o.FullName)
        $failed++
    }
}

if ($failed -gt 0) {
    Write-Host ("FAIL: {0} problem(s) across {1} pinned file(s)" -f $failed, $entries.Count)
    exit 1
}
Write-Host ("PASS: {0} pinned file(s) verified" -f $entries.Count)
exit 0
