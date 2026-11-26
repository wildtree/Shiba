# Builds the Windows release and the Inno Setup 7 installer.
#   powershell -ExecutionPolicy Bypass -File packaging\windows\build-windows.ps1
# Output: dist\win-x64\ (the game) and dist\ShibaJintori-<version>-win-x64-setup.exe

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $root

[xml]$proj = Get-Content (Join-Path $root "ShibaJintori.csproj")
$version = ($proj.Project.PropertyGroup | ForEach-Object { $_.Version } | Where-Object { $_ } | Select-Object -First 1)
if (-not $version) { $version = "1.0.6" }
Write-Host "== Shiba Jintori $version =="

$publish = Join-Path $root "dist\win-x64"
if (Test-Path $publish) { Remove-Item $publish -Recurse -Force }
dotnet publish (Join-Path $root "ShibaJintori.csproj") -c Release -r win-x64 --self-contained true -p:DebugType=none -o $publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

# Find ISCC.exe of Inno Setup 7: registry (64-bit edition first), then default folders, then PATH
$iscc = $null
$keys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 7_is1",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 7_is1",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 7 (32-bit)_is1",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 7 (32-bit)_is1"
)
foreach ($k in $keys) {
    if ($iscc) { break }
    $loc = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).InstallLocation
    if ($loc -and (Test-Path (Join-Path $loc "ISCC.exe"))) { $iscc = Join-Path $loc "ISCC.exe" }
}
if (-not $iscc) {
    $candidates = @(
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe"
    )
    foreach ($c in $candidates) { if (-not $iscc -and (Test-Path $c)) { $iscc = $c } }
}
if (-not $iscc) {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) { throw "ISCC.exe (Inno Setup 7) was not found. Install Inno Setup 7 or add ISCC.exe to PATH." }
Write-Host "Using $iscc"

& $iscc "/DAppVersion=$version" (Join-Path $root "packaging\windows\ShibaJintori.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed" }
Write-Host "Done: dist\ShibaJintori-$version-win-x64-setup.exe"
