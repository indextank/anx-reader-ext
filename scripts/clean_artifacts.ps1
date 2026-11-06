<#
.SYNOPSIS
    Reclaim disk space used by Flutter/Dart build artifacts and caches for this repo.

.DESCRIPTION
    Default (safe) mode removes:
      - build outputs of platforms other than Windows (Android/iOS/macOS/Linux/Web/OHOS),
        including plugin build outputs under build\<plugin-name>;
      - the Gradle/Kotlin caches produced by Android builds (android\.gradle, android\.kotlin);
      - build\test_cache and build\unit_test_assets;
      - stale Flutter build-kernel caches under .dart_tool\flutter_build (keeps the
        newest one, so the current Windows build stays incremental);
      - obsolete flutter_tools.* temp directories (older than a day);
      - root-level tool logs (custom_lint.log, flutter_*.log).
    The current Windows build output is left untouched.

    -Full additionally runs `flutter clean` (removes build\, .dart_tool\ and the
    platform ephemeral dirs) followed by `flutter pub get`. It refuses to run while
    the app or `flutter run` is running, unless -StopDevProcesses is given.

    -IncludeCef also deletes the prebuilt CEF download used only by the Linux build
    (third_party\webview_cef\third\cef). It is re-downloaded on the next Linux build.

    -IncludeWebViewCache also deletes the WebView2 profile/cache under %TEMP%\EBWebView
    (this clears cookies of in-app webviews/login state as well).

.EXAMPLE
    pwsh -File scripts/clean_artifacts.ps1
    Safe cleanup: drops non-Windows build outputs and stale caches.

.EXAMPLE
    pwsh -File scripts/clean_artifacts.ps1 -Full -StopDevProcesses
    Stops the running debug session, then `flutter clean` + `flutter pub get`.

.EXAMPLE
    pwsh -File scripts/clean_artifacts.ps1 -IncludeCef -DryRun
    Shows what would be deleted, including the Linux CEF cache, without deleting.
#>
[CmdletBinding()]
param(
    [switch]$Full,
    [switch]$IncludeCef,
    [switch]$IncludeWebViewCache,
    [switch]$StopDevProcesses,
    [switch]$SkipTemp,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $projectRoot 'build'
$script:FreedMB = 0.0

function Get-DirSizeMB {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0.0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0.0 }
    return [math]::Round($sum / 1MB, 1)
}

function Test-PathAllowed {
    param([string]$ResolvedPath)
    $allowedRoots = @($projectRoot)
    if ($env:TEMP) { $allowedRoots += $env:TEMP }
    foreach ($root in $allowedRoots) {
        if ($ResolvedPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Remove-Artifact {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-PathAllowed $resolved)) {
        Write-Warning "skip (outside project/temp): $resolved"
        return
    }
    $sizeMB = Get-DirSizeMB $resolved
    if ($DryRun) {
        Write-Host ("  would delete {0,9:N1} MB  {1}" -f $sizeMB, $resolved)
        return
    }
    try {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        $script:FreedMB += $sizeMB
        Write-Host ("  deleted      {0,9:N1} MB  {1}" -f $sizeMB, $resolved)
    }
    catch {
        Write-Warning ("  failed       {0,9:N1} MB  {1}  ({2})" -f $sizeMB, $resolved, $_.Exception.Message)
    }
}

function Get-ProjectDevProcesses {
    $result = @()
    $result += Get-Process -Name 'anx_reader' -ErrorAction SilentlyContinue
    $result += Get-CimInstance Win32_Process -Filter "Name='dartvm.exe' or Name='dart.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'flutter_tools\.snapshot\s+run' } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    return $result | Where-Object { $_ -ne $null }
}

Write-Host "Project: $projectRoot"
$mode = if ($Full) { 'full' } else { 'safe' }
if ($DryRun) { $mode = "$mode (dry run)" }
Write-Host "Mode: $mode"

# --- 1. Non-Windows platform build outputs -------------------------------------------------
Write-Host 'Non-Windows build outputs:'
foreach ($name in @('app', 'linux', 'macos', 'ios', 'web', 'ohos', 'test_cache', 'unit_test_assets')) {
    Remove-Artifact (Join-Path $buildDir $name)
}

# Gradle/Kotlin caches created by Android builds.
Remove-Artifact (Join-Path $projectRoot 'android\.gradle')
Remove-Artifact (Join-Path $projectRoot 'android\.kotlin')

# Plugin build output directories are named after plugin packages.
$pluginsFile = Join-Path $projectRoot '.flutter-plugins-dependencies'
if (Test-Path -LiteralPath $pluginsFile) {
    try {
        $pluginsJson = Get-Content -LiteralPath $pluginsFile -Raw | ConvertFrom-Json
        $pluginNames = @()
        foreach ($platform in @('android', 'ios', 'macos', 'linux', 'web')) {
            if ($pluginsJson.plugins.PSObject.Properties.Name -contains $platform) {
                $pluginNames += $pluginsJson.plugins.$platform | ForEach-Object { $_.name }
            }
        }
        foreach ($pluginName in ($pluginNames | Sort-Object -Unique)) {
            Remove-Artifact (Join-Path $buildDir $pluginName)
        }
    }
    catch {
        Write-Warning "could not parse .flutter-plugins-dependencies: $($_.Exception.Message)"
    }
}

# --- 2. Stale Flutter build-kernel caches --------------------------------------------------
$flutterBuildCache = Join-Path $projectRoot '.dart_tool\flutter_build'
if (Test-Path -LiteralPath $flutterBuildCache) {
    Write-Host 'Stale build-kernel caches:'
    $cachedConfigs = Get-ChildItem -LiteralPath $flutterBuildCache -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $newest = Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            [pscustomobject]@{
                Path      = $_.FullName
                LastWrite = if ($newest) { $newest.LastWriteTime } else { $_.LastWriteTime }
            }
        } |
        Sort-Object LastWrite -Descending
    if ($cachedConfigs.Count -gt 1) {
        $cachedConfigs | Select-Object -Skip 1 | ForEach-Object { Remove-Artifact $_.Path }
    }
}

# --- 3. Root-level tool logs ---------------------------------------------------------------
Write-Host 'Tool logs:'
Get-ChildItem -LiteralPath $projectRoot -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'custom_lint.log' -or $_.Name -like 'flutter_*.log' } |
    ForEach-Object { Remove-Artifact $_.FullName }

# --- 4. Optional: Linux CEF prebuilt cache -------------------------------------------------
if ($IncludeCef) {
    Write-Host 'Linux CEF prebuilt cache (will be re-downloaded by the next Linux build):'
    Remove-Artifact (Join-Path $projectRoot 'third_party\webview_cef\third\cef')
}

# --- 5. Stale flutter_tools temp directories -----------------------------------------------
if (-not $SkipTemp -and $env:TEMP) {
    Write-Host 'Stale flutter_tools temp dirs (> 1 day old):'
    Get-ChildItem -LiteralPath $env:TEMP -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'flutter_tools.*' -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
        ForEach-Object { Remove-Artifact $_.FullName }
}

# WebView2 profile/cache used by the in-app webviews (kept in the app temp dir).
# Deleting it also clears in-webview cookies, so it is opt-in only.
if ($IncludeWebViewCache -and $env:TEMP) {
    Write-Host 'In-app WebView2 cache:'
    Remove-Artifact (Join-Path $env:TEMP 'EBWebView')
}

# --- 6. Optional full clean ----------------------------------------------------------------
if ($Full) {
    Write-Host 'Full clean:'
    $devProcesses = Get-ProjectDevProcesses
    if ($devProcesses) {
        if ($StopDevProcesses) {
            Write-Host "  stopping dev processes: $($devProcesses.Id -join ', ')"
            if (-not $DryRun) {
                foreach ($process in $devProcesses) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Seconds 2
            }
        }
        else {
            Write-Warning 'anx_reader / flutter run is running. Re-run with -StopDevProcesses, or stop it first.'
            exit 1
        }
    }
    if ($DryRun) {
        Write-Host '  would run: flutter clean'
        Write-Host '  would run: flutter pub get'
    }
    else {
        Push-Location $projectRoot
        try {
            & flutter clean
            if ($LASTEXITCODE -ne 0) { throw "flutter clean failed ($LASTEXITCODE)" }
            & flutter pub get
            if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed ($LASTEXITCODE)" }
        }
        finally {
            Pop-Location
        }
        Write-Host '  flutter clean + flutter pub get done'
    }
    # No dev process is running now, so every flutter_tools temp dir is disposable.
    if (-not $SkipTemp -and -not $DryRun -and $env:TEMP) {
        Write-Host 'flutter_tools temp dirs:'
        Get-ChildItem -LiteralPath $env:TEMP -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'flutter_tools.*' } |
            ForEach-Object { Remove-Artifact $_.FullName }
    }
}

# --- Summary -------------------------------------------------------------------------------
Write-Host ''
if ($DryRun) {
    Write-Host 'Dry run: nothing was deleted.'
}
else {
    Write-Host ("Freed: {0:N1} MB ({1:N2} GB)" -f $script:FreedMB, ($script:FreedMB / 1024))
}
Write-Host ("build dir now: {0:N1} MB" -f (Get-DirSizeMB $buildDir))
