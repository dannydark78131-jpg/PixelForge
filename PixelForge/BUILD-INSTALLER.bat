@echo off
REM BUILD-INSTALLER.bat — double-click to build PixelForge-Setup-1.0.0.exe
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

echo === PixelForge — build installer ===
echo.

if not exist "ImageTools.psm1" (
    echo [ERROR] ImageTools.psm1 not found in this folder.
    echo         Copy your ImageTools.psm1 next to this .bat and try again.
    echo.
    pause & exit /b 1
)

set "ISCC="
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if exist "C:\Program Files\Inno Setup 6\ISCC.exe"     set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
if not defined ISCC ( where ISCC >nul 2>&1 && for /f "delims=" %%i in ('where ISCC') do set "ISCC=%%i" )
if not defined ISCC (
    echo [ERROR] Inno Setup 6 not found. Install from https://jrsoftware.org/isdl.php
    pause & exit /b 1
)

echo Building with: !ISCC!
"!ISCC!" /Qp installer.iss
if !ERRORLEVEL! neq 0 ( echo [ERROR] Build failed. & pause & exit /b 1 )

echo.
echo [DONE] PixelForge-Setup-1.0.0.exe created in this folder.
echo        Distribute that one .exe file.
echo.
pause
endlocal & exit /b 0
