@echo off
setlocal enabledelayedexpansion
rem ============================================================
rem  Test build for anx-reader-ext (Windows host)
rem
rem  Usage:   build_test.bat [rN] [all^|android^|windows]
rem           rN       optional - auto-detected as max existing rN + 1
rem           platform optional - default "all" (APK + Windows zip)
rem
rem  Artifacts (same rN across platforms):
rem    build\app\outputs\flutter-apk\Anx-Reader-android-<ver>-<abi>-rN.apk
rem    build\windows\unsigned\Anx-Reader-windows-<ver>-rN.zip
rem
rem  Android: release, split-per-abi, no-tree-shake-icons; each copy
rem           verified with python zipfile testzip + apksigner.
rem  Windows: release build + staging (runner Release, app_icon.ico as
rem           logo.ico, VC runtime DLLs from scripts\windows\x64) zipped
rem           via Compress-Archive; zip verified with python zipfile.
rem           Unsigned (SignPath is CI-only).
rem
rem  Toolchain env is local-only (not in repo): PUB_CACHE short path
rem  (MAX_PATH), JDK 17 for AGP, nuget.exe for flutter_tts CMake, ATL
rem  headers injected via CL/_LINK_ (VS Build Tools lack atlmfc).
rem ============================================================

cd /d "%~dp0"

set "PLATFORM=%~2"
if "%PLATFORM%"=="" set "PLATFORM=all"

set "PUB_CACHE=E:\pubcache"
set "JAVA_HOME=E:\jdk-17.0.20.1+1"
set "PATH=%JAVA_HOME%\bin;E:\tools;E:\android-sdk\platform-tools;%PATH%"
set "CL=-IE:\atl\ATL\Contents\VC\Tools\MSVC\14.44.35207\atlmfc\include"
set "_LINK_=/LIBPATH:E:\atl\ATL\Contents\VC\Tools\MSVC\14.44.35207\atlmfc\lib\x64"
set "BUILD_TOOLS=E:\android-sdk\build-tools\36.0.0"
set "APK_OUT=build\app\outputs\flutter-apk"
set "WIN_OUT=build\windows\unsigned"
set "WIN_STAGE=build\windows\test-stage"

rem ---- version from pubspec.yaml ----
set "FULLVER="
for /f "tokens=2 delims=: " %%v in ('findstr /b /c:"version:" pubspec.yaml') do set "FULLVER=%%v"
if not defined FULLVER (
  echo [FAIL] cannot read version from pubspec.yaml
  exit /b 1
)
for /f "tokens=1 delims=+" %%v in ("%FULLVER%") do set "VER=%%v"
echo Version: %FULLVER%  (marketing %VER%)  Platform: %PLATFORM%

if /i "%PLATFORM%"=="android" goto rN
if /i "%PLATFORM%"=="windows" goto rN
if /i "%PLATFORM%"=="all" goto rN
echo [FAIL] unknown platform "%PLATFORM%" (all/android/windows)
exit /b 1

rem ---- rN: from arg or auto-detect max existing + 1 across both platforms ----
rem (regex anchors the trailing -rN.apk/.zip; cmd string replace is
rem  case-insensitive and would match the R in "Anx-Reader")
:rN
if not "%~1"=="" (
  set "RN=%~1"
) else (
  set "RN=1"
  for /f "usebackq delims=" %%n in (`powershell -NoProfile -Command "$m=0; Get-ChildItem @('%APK_OUT%\Anx-Reader-android-%VER%-*-r*.apk','%WIN_OUT%\Anx-Reader-windows-*-r*.zip') -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch '-r(\d+)\.(apk^|zip)$' } | ForEach-Object { $n=[int]$Matches[1]; if($n -gt $m){$m=$n} }; $m+1"`) do set "RN=%%n"
)
echo Revision: r%RN%
set "FAILED=0"

rem ============================ ANDROID ============================
if /i "%PLATFORM%"=="windows" goto windows

echo === flutter pub get ===
call flutter pub get || set "FAILED=1"
if "%FAILED%"=="1" goto fail

echo === flutter build apk --release --split-per-abi --no-tree-shake-icons ===
call flutter build apk --release --split-per-abi --no-tree-shake-icons || set "FAILED=1"
if "%FAILED%"=="1" goto fail

for %%a in (armeabi-v7a arm64-v8a x86_64) do (
  if exist "%APK_OUT%\app-%%a-release.apk" (
    set "DST=%APK_OUT%\Anx-Reader-android-%VER%-%%a-r%RN%.apk"
    echo copy: !DST!
    copy /y "%APK_OUT%\app-%%a-release.apk" "!DST!" >nul || (set "FAILED=1" & echo [FAIL] copy %%a)
  ) else (
    echo [WARN] missing %APK_OUT%\app-%%a-release.apk
  )
)
if exist "%APK_OUT%\app-release.apk" (
  set "DST=%APK_OUT%\Anx-Reader-android-%VER%-universal-r%RN%.apk"
  echo copy: !DST!
  copy /y "%APK_OUT%\app-release.apk" "!DST!" >nul || (set "FAILED=1" & echo [FAIL] copy universal)
) else (
  echo [WARN] missing %APK_OUT%\app-release.apk
)

for %%f in ("%APK_OUT%\Anx-Reader-android-%VER%-*-r%RN%.apk") do (
  echo verify: %%~nxf
  python -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); bad=z.testzip(); sys.exit(1 if bad else 0)" "%%f" || (set "FAILED=1" & echo [FAIL] zip check %%~nxf)
  call "%BUILD_TOOLS%\apksigner.bat" verify "%%f" >nul 2>&1 || (set "FAILED=1" & echo [FAIL] apksigner %%~nxf)
)

rem ============================ WINDOWS ============================
:windows
if /i "%PLATFORM%"=="android" goto summary

echo === flutter build windows --release --no-tree-shake-icons ===
call flutter build windows --release --no-tree-shake-icons || set "FAILED=1"
if "%FAILED%"=="1" goto fail

echo === stage windows package ===
rem cmd "copy" does not recurse - xcopy /e is required for the data\ dir
if exist "%WIN_STAGE%" rmdir /s /q "%WIN_STAGE%"
mkdir "%WIN_STAGE%" || goto fail
xcopy /y /e /i /q "build\windows\x64\runner\Release\*" "%WIN_STAGE%" >nul
if errorlevel 1 (set "FAILED=1" & echo [FAIL] xcopy runner Release)
copy /y "windows\runner\resources\app_icon.ico" "%WIN_STAGE%\logo.ico" >nul || (set "FAILED=1" & echo [FAIL] copy logo.ico)
copy /y "scripts\windows\x64\*" "%WIN_STAGE%\" >nul || (set "FAILED=1" & echo [FAIL] copy VC runtime DLLs)
if "%FAILED%"=="1" goto fail

set "WINZIP=%WIN_OUT%\Anx-Reader-windows-%VER%-r%RN%.zip"
if not exist "%WIN_OUT%" mkdir "%WIN_OUT%"
echo zip: !WINZIP!
powershell -NoProfile -Command "Compress-Archive -Path '%WIN_STAGE%\*' -DestinationPath '%WIN_OUT%\Anx-Reader-windows-%VER%-r%RN%.zip' -Force" || (set "FAILED=1" & echo [FAIL] Compress-Archive)

echo verify: Anx-Reader-windows-%VER%-r%RN%.zip
python -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); names=z.namelist(); need=['anx_reader.exe','logo.ico','msvcp140.dll','icudtl.dat','flutter_assets']; miss=[k for k in need if not any(k in n.replace('\\','/') for n in names)]; sys.exit(1 if (z.testzip() or miss) else 0)" "%WIN_OUT%\Anx-Reader-windows-%VER%-r%RN%.zip" || (set "FAILED=1" & echo [FAIL] zip check windows ^(missing or corrupt entries^))
if exist "%WIN_STAGE%" rmdir /s /q "%WIN_STAGE%"

rem ============================ SUMMARY ============================
:summary
if "%FAILED%"=="1" goto fail

echo.
echo === DONE r%RN% (%PLATFORM%) ===
for %%f in ("%APK_OUT%\Anx-Reader-android-%VER%-*-r%RN%.apk") do @echo   %%~nxf
if exist "%WIN_OUT%\Anx-Reader-windows-%VER%-r%RN%.zip" echo   Anx-Reader-windows-%VER%-r%RN%.zip
exit /b 0

:fail
echo [FAIL] build_test aborted
exit /b 1
