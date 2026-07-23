@echo off
setlocal
cd /d "%~dp0"
:menu
cls
echo ==================================================
echo    Joint Space - GitHub Sync
echo ==================================================
echo    1. Connect this folder to a GitHub repo
echo    2. Sync now (commit + push)
echo    3. Enable auto-sync  (at login + every 15 min)
echo    4. Disable auto-sync
echo    5. Exit
echo ==================================================
set /p choice="Choose an option (1-5): "
if "%choice%"=="1" goto connect
if "%choice%"=="2" goto syncnow
if "%choice%"=="3" goto enableauto
if "%choice%"=="4" goto disableauto
if "%choice%"=="5" exit /b
goto menu

:connect
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1" -Connect
pause
goto menu

:syncnow
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1"
pause
goto menu

:enableauto
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1" -EnableAuto
pause
goto menu

:disableauto
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1" -DisableAuto
pause
goto menu
