@echo off
setlocal
rem ============================================================
rem  Real-time run of anx-reader-ext on Windows (flutter run)
rem
rem  Usage:  run_windows.bat [extra flutter run args]
rem          e.g.  run_windows.bat                (debug, hot reload)
rem                run_windows.bat --release      (release profile)
rem
rem  Toolchain env mirrors build_test.bat (local-only paths:
rem  PUB_CACHE short path, JDK 17, nuget, ATL headers) so the
rem  Windows runner (CMake + flutter_tts + ATL) compiles cleanly.
rem ============================================================

cd /d "%~dp0"

set "PUB_CACHE=E:\pubcache"
set "JAVA_HOME=E:\jdk-17.0.20.1+1"
set "PATH=%JAVA_HOME%\bin;E:\tools;E:\android-sdk\platform-tools;%PATH%"
set "CL=-IE:\atl\ATL\Contents\VC\Tools\MSVC\14.44.35207\atlmfc\include"
set "_LINK_=/LIBPATH:E:\atl\ATL\Contents\VC\Tools\MSVC\14.44.35207\atlmfc\lib\x64"

flutter run -d windows %*
endlocal
