; Shiba Jintori - Inno Setup 7 (64-bit) installer script
;
; Build with packaging\windows\build-windows.ps1, or by hand:
;   dotnet publish -c Release -r win-x64 --self-contained true -p:DebugType=none -o dist\win-x64
;   "C:\Program Files\Inno Setup 7\ISCC.exe" packaging\windows\ShibaJintori.iss
;
; The installer is written to dist\ShibaJintori-<version>-win-x64-setup.exe

#define AppName "Shiba Jintori"
#define AppExe "ShibaJintori.exe"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef PublishDir
  #define PublishDir "..\..\dist\win-x64"
#endif

[Setup]
AppId={{1A1EA3BA-552C-4E6A-BCDE-1F7E09C03DD5}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\ShibaJintori
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Build a 64-bit (x64) installer that installs in 64-bit mode (new in Inno Setup 7)
SetupArchitecture=x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Let the user choose "just me" (no admin rights needed) or "all users"
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=..\icons\shibajintori.ico
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=..\..\dist
OutputBaseFilename=ShibaJintori-{#AppVersion}-win-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
