@echo off
chcp 65001 >nul
setlocal EnableExtensions

title AD User Password Status GUI - Launcher

echo ==========================================================
echo AD User Password Status GUI - Launcher
echo ==========================================================
echo.
echo Paste the FULL path to AD-UserPasswordStatus-GUI.ps1
echo or paste the folder where the script is located.
echo.
echo Examples:
echo   C:\Tools\Powershell 2026\AD-UserPasswordStatus-GUI\AD-UserPasswordStatus-GUI.ps1
echo   C:\Tools\Powershell 2026\AD-UserPasswordStatus-GUI
echo.

:ASK_PATH
set "INPUT_PATH="
set /p "INPUT_PATH=Script path or folder: "
set "INPUT_PATH=%INPUT_PATH:"=%"

if "%INPUT_PATH%"=="" (
    echo Please enter a path.
    echo.
    goto ASK_PATH
)

if exist "%INPUT_PATH%\" (
    set "SCRIPT_PATH=%INPUT_PATH%\AD-UserPasswordStatus-GUI.ps1"
) else (
    set "SCRIPT_PATH=%INPUT_PATH%"
)

if not exist "%SCRIPT_PATH%" (
    echo.
    echo ERROR: Script file not found:
    echo "%SCRIPT_PATH%"
    echo.
    goto ASK_PATH
)

echo.
echo Starting tool from:
echo "%SCRIPT_PATH%"
echo.
echo This launcher window will close. The GUI will continue separately.

start "AD User Password Status GUI" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT_PATH%"
endlocal
exit /b 0
