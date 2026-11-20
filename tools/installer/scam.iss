; Installateur Windows de sCam (Inno Setup 6).
;
; Compilé par .github/workflows/build.yml une fois l'application assemblée dans
; build\windows\x64\runner\Release :
;
;     ISCC.exe /DAppVersion=1.0.12 tools\installer\scam.iss
;
; L'installation se fait dans le profil de l'utilisateur : aucun droit d'administrateur requis.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{7B1D4C2E-58A3-4F96-B0E7-2C9A6D41F385}
AppName=sCam
AppVersion={#AppVersion}
AppPublisher=ShinezeoGame
AppPublisherURL=https://github.com/ShinezeoGame/sCam
DefaultDirName={autopf}\sCam
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..
OutputBaseFilename=scam-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\scam.exe
UninstallDisplayName=sCam
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Une mise à jour ferme sCam avant de remplacer les fichiers.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\sCam"; Filename: "{app}\scam.exe"
Name: "{autodesktop}\sCam"; Filename: "{app}\scam.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\scam.exe"; Description: "{cm:LaunchProgram,sCam}"; Flags: nowait postinstall skipifsilent
