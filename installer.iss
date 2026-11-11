#define MyAppName "Конвертер файлов"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "File Converter"
#define MyAppURL "https://podari-zhizn.ru"
#define MyAppExeName "Converter.exe"

[Setup]
AppId={{5D01E170-8772-4BD8-8F21-E8B7504353E1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL=https://github.com/Zmeykofa/file-converter-windows
DefaultDirName={localappdata}\Programs\FileConverter
DisableProgramGroupPage=yes
DefaultGroupName={#MyAppName}
OutputDir=dist
OutputBaseFilename=Setup
SetupIconFile=app.ico
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\Converter.exe
VersionInfoVersion=1.0.0.0
VersionInfoCompany=Open Source
VersionInfoDescription=Офлайн-конвертер файлов для Windows
VersionInfoProductName=Конвертер файлов
VersionInfoProductVersion=1.0.0.0

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "contextmenu"; Description: "Добавить в контекстное меню Проводника («Конвертировать в…» и «Конвертировать…»)"; GroupDescription: "Интеграция в систему:"

[Files]
Source: "Converter.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "menu-launcher.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "Uninstall.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "converter.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "convert-menu.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "worker.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "install-menu.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "pdf-support.cs"; DestDir: "{app}"; Flags: ignoreversion
Source: "app.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "Прочитайте.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "components\*"; DestDir: "{app}\components"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app.ico"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\FileConverter"; Flags: deletekey dontcreatekey

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-menu.ps1"" -TargetDir ""{app}"""; Flags: runhidden; Tasks: contextmenu
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-menu.ps1"" -Remove -TargetDir ""{app}"""; Flags: runhidden

