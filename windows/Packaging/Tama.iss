; Tama for Windows — Inno Setup installer script.
;
; Produces a single per-user TamaSetup.exe (no admin / no UAC prompt). Bundles the
; self-contained .NET 8 publish output, so the target machine needs nothing else installed.
; The build is UNSIGNED, so SmartScreen still warns on first run until a code-signing cert
; is added ("More info -> Run anyway") — the installer format does not change that.
;
; Build (on Windows, from the repo root):
;   dotnet publish windows\Tama.Tray -c Release -r win-x64 --self-contained ^
;     -p:EnableWindowsTargeting=true -o dist\win-x64
;   iscc /DAppVersion=0.1.0 windows\Packaging\Tama.iss
; Output: dist\installer\TamaSetup.exe
; CI does exactly this on a windows-latest runner (see .github/workflows/windows-release.yml).

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
; Publish output dir, relative to this .iss file (windows\Packaging\ -> repo-root\dist\win-x64).
#ifndef PublishDir
  #define PublishDir "..\..\dist\win-x64"
#endif

[Setup]
; Stable AppId — never change it, or upgrades/uninstall entries won't match across versions.
AppId={{8779DD67-0357-44DB-AE37-131FD226ADEE}
AppName=Tama
AppVersion={#AppVersion}
AppVerName=Tama {#AppVersion}
AppPublisher=pmrster
AppPublisherURL=https://github.com/pmrster/tama
DefaultDirName={autopf}\Tama
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist\installer
OutputBaseFilename=TamaSetup
SetupIconFile=tama.ico
UninstallDisplayIcon={app}\Tama.Tray.exe
UninstallDisplayName=Tama
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
; Ask the running tray app to close on install/uninstall so its files aren't locked (upgrade case).
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Tama"; Filename: "{app}\Tama.Tray.exe"

[Tasks]
Name: "startup"; Description: "Launch Tama automatically when I sign in"; GroupDescription: "Startup:"

[Registry]
; Run-at-login (opt-in via the checkbox above) — the SAME HKCU Run value the in-app Settings
; toggle manages, so the two compose cleanly. uninsdeletevalue removes it on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; \
  ValueName: "Tama"; ValueData: """{app}\Tama.Tray.exe"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\Tama.Tray.exe"; Description: "Run Tama now"; Flags: nowait postinstall skipifsilent

; NOTE: %APPDATA%\Tama\ (the app's own saved state — cat mood, usage history, settings) is
; intentionally left in place on uninstall; the user can delete it manually if they want a
; clean wipe. Matches the portable-zip guidance in INSTALL.md.
