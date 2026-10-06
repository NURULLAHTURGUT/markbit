; Markbit Windows installer (Inno Setup 6).
;
; Build the app first, then compile this script from the repository root:
;   flutter build windows --release
;   iscc /DAppVersion=1.0.0 installer\markbit.iss
; The installer is written to installer\Output\.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Markbit"
#define AppExe "markbit.exe"
#define AppPublisher "Nurullah Turgut"
#define AppUrl "https://github.com/NURULLAHTURGUT/markbit"
#define BuildDir "..\build\windows\x64\runner\Release"
; Must match lib/application/reminders.dart so task reminders show as
; Markbit notifications and clicking one opens the app.
#define AppUserModelId "Markbit.Markbit.Desktop"
#define ToastActivatorClsid "186ad914-d194-42b4-a54f-a39be7dba016"

[Setup]
; Never change AppId: Windows uses it to recognise upgrades and uninstalls.
AppId={{91F52378-1E6D-4632-B75F-7F1B355513A7}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
AppCopyright=Copyright (C) 2026 {#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup

; Install for the current user without administrator rights by default
; (%LocalAppData%\Programs\Markbit). The first page lets the user choose
; "all users" instead, which installs to Program Files.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

LicenseFile=..\LICENSE
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
ShowLanguageDialog=auto
UsePreviousLanguage=yes

; Close a running Markbit before files are replaced during an upgrade.
CloseApplications=yes
RestartApplications=no

OutputDir=Output
OutputBaseFilename=Markbit-Setup-{#AppVersion}-x64
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelId}"; AppUserModelToastActivatorCLSID: "{#ToastActivatorClsid}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\setup-language"

[Code]
{ Markbit reads this file on its first launch and starts in the language
  chosen here (see lib/data/installer_language.dart). Notes and settings live
  in the user's AppData folder, so uninstalling never deletes them. }
function AppLanguageCode(): String;
begin
  if ActiveLanguage = 'turkish' then
    Result := 'tr'
  else if ActiveLanguage = 'german' then
    Result := 'de'
  else if ActiveLanguage = 'spanish' then
    Result := 'es'
  else
    Result := 'en';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    SaveStringToFile(ExpandConstant('{app}\setup-language'), AppLanguageCode(), False);
end;
