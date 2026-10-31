@echo off
setlocal enabledelayedexpansion
rem ============================================================
rem  Android test build for anx-reader-ext (Windows)
rem
rem  Usage:   build_android_test.bat [rN]
rem           rN optional - auto-detected as max existing rN + 1
rem
rem  Steps:   pub get -> flutter build apk (release, split-per-abi,
rem           no-tree-shake-icons) -> copy to
rem           Anx-Reader-android-<ver>-<abi>-rN.apk -> verify each
rem           copy with python zipfile testzip + apksigner
rem
rem  Toolchain env is local-only (not in repo):
rem    PUB_CACHE   short path, avoids 260-char MAX_PATH javac failures
rem    JAVA_HOME   JDK 17 required by AGP 8.x
rem ============================================================

cd /d "%~dp0"

set "PUB_CACHE=E:\pubcache"
set "JAVA_HOME=E:\jdk-17.0.20.1+1"
set "PATH=%JAVA_HOME%\bin;E:\android-sdk\platform-tools;%PATH%"
set "BUILD_TOOLS=E:\android-sdk\build-tools\36.0.0"
set "OUTDIR=build\app\outputs\flutter-apk"

rem ---- version from pubspec.yaml ----
set "FULLVER="
for /f "tokens=2 delims=: " %%v in ('findstr /b /c:"version:" pubspec.yaml') do set "FULLVER=%%v"
if not defined FULLVER (
  echo [FAIL] cannot read version from pubspec.yaml
  exit /b 1
)
for /f "tokens=1 delims=+" %%v in ("%FULLVER%") do set "VER=%%v"
echo Version: %FULLVER%  (marketing %VER%)

rem ---- rN: from arg or auto-detect max existing + 1 ----
if not "%~1"=="" (
  set "RN=%~1"
) else (
  set /a RN=0
  for /f "delims=" %%f in ('dir /b "%OUTDIR%\Anx-Reader-android-%VER%-*-r*.apk" 2^>nul') do (
    set "cand=0"
    set "tail=%%f"
    set "tail=!tail:*-r=!"
    set "tail=!tail:.apk=!"
    set /a cand=!tail! 2>nul
    if !cand! GTR !RN! set /a RN=!cand!
  )
  set /a RN+=1
)
echo Revision: r%RN%

rem ---- build ----
echo === flutter pub get ===
call flutter pub get || goto :fail

echo === flutter build apk --release --split-per-abi --no-tree-shake-icons ===
call flutter build apk --release --split-per-abi --no-tree-shake-icons || goto :fail

rem ---- copy raw outputs to rN-named test builds ----
set "FAILED=0"
for %%a in (armeabi-v7a arm64-v8a x86_64) do (
  if exist "%OUTDIR%\app-%%a-release.apk" (
    set "SRC=%OUTDIR%\app-%%a-release.apk"
    set "DST=%OUTDIR%\Anx-Reader-android-%VER%-%%a-r%RN%.apk"
    echo copy: !DST!
    copy /y "!SRC!" "!DST!" >nul || (set "FAILED=1" & echo [FAIL] copy %%a)
  ) else (
    echo [WARN] missing %OUTDIR%\app-%%a-release.apk
  )
)
if exist "%OUTDIR%\app-release.apk" (
  set "DST=%OUTDIR%\Anx-Reader-android-%VER%-universal-r%RN%.apk"
  echo copy: !DST!
  copy /y "%OUTDIR%\app-release.apk" "!DST!" >nul || (set "FAILED=1" & echo [FAIL] copy universal)
) else (
  echo [WARN] missing %OUTDIR%\app-release.apk
)

rem ---- verify every rN copy (strict zip check + signature) ----
for %%f in ("%OUTDIR%\Anx-Reader-android-%VER%-*-r%RN%.apk") do (
  echo verify: %%~nxf
  python -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); bad=z.testzip(); sys.exit(1 if bad else 0)" "%%f" || (set "FAILED=1" & echo [FAIL] zip check %%~nxf)
  call "%BUILD_TOOLS%\apksigner.bat" verify "%%f" >nul 2>&1 || (set "FAILED=1" & echo [FAIL] apksigner %%~nxf)
)

if "%FAILED%"=="1" goto :fail

echo.
echo === DONE r%RN% ===
for %%f in ("%OUTDIR%\Anx-Reader-android-%VER%-*-r%RN%.apk") do @echo   %%~nxf
exit /b 0

:fail
echo [FAIL] build_android_test aborted
exit /b 1
