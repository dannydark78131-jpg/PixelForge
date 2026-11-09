; PixelForge Image Toolkit — Inno Setup 6 installer (flat, single folder)
; Build by double-clicking BUILD-INSTALLER.bat
#define MyAppName "PixelForge Image Toolkit"
#define MyAppShort "PixelForge"
#define MyAppVersion "1.0.0"
#define MyAppId "{{B7F3A2C1-4D5E-6F7A-8B9C-0D1E2F3A4B5C}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=PixelForge
DefaultDirName={localappdata}\Programs\{#MyAppShort}
DefaultGroupName={#MyAppShort}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=PixelForge-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\app.ico
SetupIconFile=app.ico
MinVersion=10.0.10240

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "ImageAppGUI.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "ImageTools.psm1";  DestDir: "{app}"; Flags: ignoreversion
Source: "Launch-GUI.vbs";   DestDir: "{app}"; Flags: ignoreversion
Source: "app.ico";          DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppShort}"; Filename: "{app}\Launch-GUI.vbs"; IconFilename: "{app}\app.ico"
Name: "{autodesktop}\{#MyAppShort}"; Filename: "{app}\Launch-GUI.vbs"; IconFilename: "{app}\app.ico"; Tasks: desktopicon
Name: "{group}\Uninstall {#MyAppShort}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\Launch-GUI.vbs"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\PixelForge"

[Code]
function InitializeSetup(): Boolean;
begin
  if not Is64BitInstallMode() then begin
    MsgBox('PixelForge requires 64-bit Windows.', mbError, MB_OK);
    Result := False; Exit;
  end;
  Result := True;
end;
