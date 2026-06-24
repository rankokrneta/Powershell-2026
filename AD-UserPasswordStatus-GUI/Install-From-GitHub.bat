@echo off
chcp 65001 >nul
setlocal EnableExtensions

title Powershell 2026 - AD User Password Status GUI Installer

set "TOOL_SUBFOLDER=AD-UserPasswordStatus-GUI"
set "TOOL_LAUNCHER=Start-AD-UserPasswordStatus-GUI.bat"

echo ==========================================================
echo Powershell 2026 - AD User Password Status GUI Installer
echo ==========================================================
echo.
echo This installer clones or updates the GitHub project/repository.
echo Expected project layout:
echo.
echo   Powershell 2026
echo     ^> AD-UserPasswordStatus-GUI
echo.
echo For a private repository, GitHub may open a browser sign-in window.
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo Git is not installed or not available in PATH.
    echo.
    choice /M "Install Git for Windows using winget now"
    if errorlevel 2 (
        echo Git is required for this installer.
        pause
        exit /b 1
    )
    winget install --id Git.Git -e
    echo.
    echo If Git was installed successfully, close this window and run this installer again.
    pause
    exit /b 0
)

:ASK_REPO
set "REPO_URL="
set /p "REPO_URL=GitHub repo URL, e.g. https://github.com/owner/Powershell-2026.git: "
set "REPO_URL=%REPO_URL:"=%"
if "%REPO_URL%"=="" (
    echo Please enter a GitHub repository URL.
    echo.
    goto ASK_REPO
)

set "DEFAULT_PATH=C:\Tools\Powershell 2026"
set "INSTALL_PATH="
set /p "INSTALL_PATH=Project root install/update folder [%DEFAULT_PATH%]: "
set "INSTALL_PATH=%INSTALL_PATH:"=%"
if "%INSTALL_PATH%"=="" set "INSTALL_PATH=%DEFAULT_PATH%"

set "TOOL_PATH=%INSTALL_PATH%\%TOOL_SUBFOLDER%"

echo.
echo Repository:   %REPO_URL%
echo Project root: %INSTALL_PATH%
echo Tool folder:  %TOOL_PATH%
echo.

if exist "%INSTALL_PATH%\.git\" (
    echo Existing Git repository found. Updating project root...
    git -C "%INSTALL_PATH%" pull --ff-only
    if errorlevel 1 (
        echo.
        echo ERROR: git pull failed.
        pause
        exit /b 1
    )
) else (
    if exist "%INSTALL_PATH%\" (
        dir /b "%INSTALL_PATH%" 2>nul | findstr . >nul
        if not errorlevel 1 (
            echo ERROR: Target project root exists but is not an empty Git repository:
            echo "%INSTALL_PATH%"
            echo.
            echo Choose an empty/new folder, or delete/move the existing folder first.
            pause
            exit /b 1
        )
    )
    echo Cloning repository into project root...
    git clone "%REPO_URL%" "%INSTALL_PATH%"
    if errorlevel 1 (
        echo.
        echo ERROR: git clone failed.
        pause
        exit /b 1
    )
)

set "START_BAT="
if exist "%TOOL_PATH%\%TOOL_LAUNCHER%" set "START_BAT=%TOOL_PATH%\%TOOL_LAUNCHER%"

rem Fallback for older/single-tool repo layout where the tool lives at repo root.
if "%START_BAT%"=="" (
    if exist "%INSTALL_PATH%\%TOOL_LAUNCHER%" set "START_BAT=%INSTALL_PATH%\%TOOL_LAUNCHER%"
)

echo.
echo Install/update complete.
echo.

if not "%START_BAT%"=="" (
    echo Launcher found:
    echo "%START_BAT%"
    echo.
    choice /M "Start the tool now"
    if not errorlevel 2 (
        start "AD User Password Status GUI" "%START_BAT%"
    )
) else (
    echo WARNING: %TOOL_LAUNCHER% was not found.
    echo Expected path:
    echo "%TOOL_PATH%\%TOOL_LAUNCHER%"
)

endlocal
exit /b 0
