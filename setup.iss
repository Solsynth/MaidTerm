; ==================================================
#define AppVersion "1.0.0"
#define BuildNumber "2"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=MaidTerm
AppVersion={#AppVersion}
AppPublisher=dev.solsynth.maid
AppPublisherURL=https://solsynth.dev
AppUpdatesURL=https://github.com/Solsynth/MaidTerm/releases
AppCopyright=Copyright © 2026 dev.solsynth.maid
VersionInfoVersion={#FullVersion}
UninstallDisplayName=MaidTerm
UninstallDisplayIcon={app}\terminal.exe

DefaultDirName={commonpf}\MaidTerm
UsePreviousAppDir=no

OutputDir=.\Installer
OutputBaseFilename=windows-x86_64-setup
SetupIconFile=.\windows\runner\resources\app_icon.ico

Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4

ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin

[Files]
Source: ".\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MaidTerm"; Filename: "{app}\terminal.exe"; IconFilename: "{app}\terminal.exe"
Name: "{group}\{cm:UninstallProgram,MaidTerm}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MaidTerm"; Filename: "{app}\terminal.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\terminal.exe"; Description: "Launch MaidTerm"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM terminal.exe"; Flags: runhidden waituntilterminated skipifdoesntexist

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\dev.solsynth\MaidTerm"
Type: files; Name: "{group}\MaidTerm.lnk"
Type: files; Name: "{autodesktop}\MaidTerm.lnk"
