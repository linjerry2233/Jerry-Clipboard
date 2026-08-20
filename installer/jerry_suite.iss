; Jerry Suite Windows 安装程序脚本
; 使用 Inno Setup 6 编译生成 setup.exe
; 编译命令: ISCC.exe installer\jerry_suite.iss

#define MyAppName "Jerry Suite"
#define MyAppVersion "1.2.3"
#define MyAppPublisher "com.jerry"
#define MyAppURL "https://github.com/Linjerry/JerryClipboard"
#define MyAppExeName "jerry_suite.exe"

[Setup]
; 注意: AppId 保持唯一，用于升级时识别同一应用
AppId={{B8F3A2E1-7C4D-4E9F-A1B6-3D5E8F2A7C91}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=JerrySuite-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=force
CloseApplicationsFilter=*.exe
RestartApplications=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Code]
function InitializeSetup(): Boolean;
var
  ExitCode: Integer;
begin
  { The application uses a global mutex for single-instance behavior. Inno
    Setup's built-in mutex prompt is not safe for silent upgrades, so terminate
    only this product's process before copying replacement files. }
  Exec(ExpandConstant('{sys}\taskkill.exe'),
    '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
  Result := True;
end;

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 发布目录下所有文件（含 dll、data 目录）
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; 安装完成后可选启动应用
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载前关闭应用进程
Filename: "{cmd}"; Parameters: "/c taskkill /f /im {#MyAppExeName}"; Flags: runhidden; RunOnceId: "KillApp"

[UninstallDelete]
; 清理应用数据目录（可选，Type: filesandordirs 会删除整个目录）
Type: filesandordirs; Name: "{app}"
