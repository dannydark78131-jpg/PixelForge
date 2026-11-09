PIXELFORGE — one folder, 6 files
=================================
In this folder:
  ImageAppGUI.ps1     the GUI app (WPF, dark theme, 10 tools, saved settings)
  Launch-GUI.vbs      silent launcher used by the desktop/start-menu shortcut
  app.ico             the app icon
  installer.iss       Inno Setup script (do not need to touch)
  BUILD-INSTALLER.bat double-click to build the installer
  ImageTools.psm1     YOU add this — copy YOUR ImageTools.psm1 here

STEP 1  Copy your ImageTools.psm1 into this folder.
STEP 2  Test the GUI: right-click Launch-GUI.vbs -> Open (no console).
        If nothing happens, run in PowerShell:
          powershell -ExecutionPolicy Bypass -File ImageAppGUI.ps1
STEP 3  Install Inno Setup 6 (free): https://jrsoftware.org/isdl.php
STEP 4  Double-click BUILD-INSTALLER.bat -> creates PixelForge-Setup-1.0.0.exe
        Give that single .exe to anyone. It installs per-user (no admin),
        creates a Desktop shortcut + Start Menu entry with the app icon,
        and includes an uninstaller.

Settings are saved in %APPDATA%\PixelForge\settings.json.
