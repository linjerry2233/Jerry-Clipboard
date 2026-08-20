; Jerry Suite 安装脚本
; Inno Setup 6
;
; 版本管理说明：
;   - AppId 固定不变，确保高版本被识别为同一程序的升级
;   - 安装时自动检测并关闭旧版本进程
;   - 升级时保留用户数据（%APPDATA%\jerry_suite）
;   - 拒绝降级安装（已安装版本高于新版本时）
;   - 卸载时询问是否保留用户数据

#define MyAppName "Jerry Suite"
#define MyAppNameCN "杰瑞套件"
#define MyAppVersion "1.2.2"
#define MyAppPublisher "Jerry"
#define MyAppURL "https://github.com/Linjerry/JerryClipboard"
#define MyAppExeName "jerry_suite.exe"
#define MyAppMutex "JerrySuite_App_Mutex_8E7B3C2A"

[Setup]
; 唯一 AppId（不可更改）——用于版本识别与升级
AppId={{8E7B3C2A-1D4F-4E5A-9B6C-7D8E9F0A1B2C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppContact={#MyAppURL}
AppMutex={#MyAppMutex}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppNameCN}
AllowNoIcons=yes
LicenseFile=
OutputDir=installer
OutputBaseFilename=JerrySuite_Setup_v{#MyAppVersion}
SetupIconFile=assets\icons\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppNameCN}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 四段版本号，写入文件属性与注册表
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}.0
; 关闭程序时优雅关闭
CloseApplications=force
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "installer\ChineseSimplified.isl"

[CustomMessages]
; chinesesimp 自定义消息
chinesesimp.AppNameCN=杰瑞套件
chinesesimp.LaunchProgram=启动 {#MyAppNameCN}
chinesesimp.UninstallProgram=卸载 {#MyAppNameCN}
chinesesimp.AdditionalIcons=附加快捷方式：
chinesesimp.CreateDesktopIcon=创建桌面快捷方式(&D)
chinesesimp.CreateStartupIcon=开机自启动(&S)
chinesesimp.WindowsVersionTooOld=安装程序需要 Windows 10 版本 1809 或更高版本。%n%n当前系统版本过低，无法继续安装。
chinesesimp.AppRunning=检测到 {#MyAppNameCN} 正在运行，安装程序将自动关闭它以继续。
chinesesimp.AppRunningCloseFailed=无法自动关闭 {#MyAppNameCN}，请手动关闭后重试。
chinesesimp.DowngradeTitle=版本过低
chinesesimp.DowngradeMsg=检测到系统中已安装 {#MyAppNameCN} %1。%n%n新版本 %2 低于已安装版本，无法继续安装。%n%n请先卸载旧版本或使用更高版本的安装包。
chinesesimp.OldVersionFoundTitle=检测到旧版本
chinesesimp.OldVersionFoundMsg=检测到系统中已安装 {#MyAppNameCN} %1，将继续进行升级。%n%n用户数据将被保留。
chinesesimp.UninstallDataTitle=保留用户数据
chinesesimp.UninstallDataMsg=是否保留 {#MyAppNameCN} 的用户数据？%n%n点击"是"保留数据（推荐），点击"否"彻底删除所有数据。

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupicon"; Description: "{cm:CreateStartupIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.lib"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "build\windows\x64\runner\Release\data\flutter_assets\*"; DestDir: "{app}\data\flutter_assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppNameCN}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppNameCN}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{autostartup}\{#MyAppNameCN}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载前关闭程序
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""{#MyAppExeName}"" /F 2>nul"; Flags: runhidden; RunOnceId: "KillApp"

[UninstallDelete]
; 仅删除程序目录内的运行时数据，用户数据目录在 [Code] 中按用户选择处理
Type: filesandordirs; Name: "{app}\data"

[Registry]
; 开机自启动项（受 startupicon 任务控制，由 [Icons] 自动创建）
; Empty section - autostartup icon handles it

[Code]
// ============================================================
// 从版本字符串中按 '.' 拆分出第 idx 段（0-based），解析为整数
// 例如 ParseVersionPart('1.2.3', 1) = 2
// ============================================================
function ParseVersionPart(const Ver: String; idx: Integer): Integer;
var
  S: String;
  i, p: Integer;
begin
  Result := 0;
  S := Ver;
  // 依次切掉第一个 '.' 之前的部分
  for i := 0 to idx do begin
    p := Pos('.', S);
    if i = idx then begin
      // 取当前段（剩余字符串中第一个 '.' 之前的部分，或整个剩余）
      if p > 0 then
        Result := StrToIntDef(Copy(S, 1, p - 1), 0)
      else
        Result := StrToIntDef(S, 0);
      exit;
    end;
    // 未到目标段，去掉当前段 + '.'
    if p = 0 then exit;  // 段数不足
    S := Copy(S, p + 1, Length(S) - p);
  end;
end;

// ============================================================
// 版本比较：返回 >0 表示 v1>v2，<0 表示 v1<v2，0 表示相等
// 仅比较 major.minor.patch 三段
// ============================================================
function CompareVersions(v1, v2: String): Integer;
var
  v1Major, v1Minor, v1Patch, v2Major, v2Minor, v2Patch: Integer;
begin
  v1Major := ParseVersionPart(v1, 0);
  v1Minor := ParseVersionPart(v1, 1);
  v1Patch := ParseVersionPart(v1, 2);
  v2Major := ParseVersionPart(v2, 0);
  v2Minor := ParseVersionPart(v2, 1);
  v2Patch := ParseVersionPart(v2, 2);

  if v1Major <> v2Major then
    Result := v1Major - v2Major
  else if v1Minor <> v2Minor then
    Result := v1Minor - v2Minor
  else
    Result := v1Patch - v2Patch;
end;

// ============================================================
// 获取已安装版本号（从注册表读取）
// Inno Setup 自动用 AppId 作为 Uninstall 键名：{AppId}_is1
// ============================================================
function GetInstalledVersion(var Version: String): Boolean;
var
  UninstallKey: String;
begin
  Result := False;
  Version := '';
  // AppId = {8E7B3C2A-1D4F-4E5A-9B6C-7D8E9F0A1B2C}
  // Uninstall 注册表键名为 {8E7B3C2A-1D4F-4E5A-9B6C-7D8E9F0A1B2C}_is1
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#emit SetupSetting("AppId")}_is1';
  // 去掉 AppId 中的外层花括号转义（SetupSetting 返回 {{...}} 形式）
  StringChange(UninstallKey, '{{', '{');

  // PrivilegesRequired=lowest 时写入 HKCU，否则写入 HKLM
  // 同时检查 64 位和 32 位注册表视图
  if RegQueryStringValue(HKCU, UninstallKey, 'DisplayVersion', Version) then begin
    Result := True;
  end else if RegQueryStringValue(HKLM, UninstallKey, 'DisplayVersion', Version) then begin
    Result := True;
  end else if RegQueryStringValue(HKLM32, UninstallKey, 'DisplayVersion', Version) then begin
    Result := True;
  end;
end;

// ============================================================
// 检查 Windows 版本
// ============================================================
function IsWindowsVersionOrGreater(Major, Minor, Build: Integer): Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := (Version.Major > Major) or
            ((Version.Major = Major) and (Version.Minor > Minor)) or
            ((Version.Major = Major) and (Version.Minor = Minor) and (Version.Build >= Build));
end;

// ============================================================
// 关闭正在运行的应用
// ============================================================
procedure KillRunningApp;
var
  ResultCode: Integer;
begin
  // 优雅关闭，失败则强制
  ShellExec('open', 'taskkill', '/IM "{#MyAppExeName}" /F', '', SW_HIDE, ewNoWait, ResultCode);
end;

// ============================================================
// 初始化安装：Windows 版本检查 + 降级检查 + 关闭旧进程
// ============================================================
function InitializeSetup(): Boolean;
var
  InstalledVersion: String;
begin
  Result := True;

  // 1. Windows 版本检查
  if not IsWindowsVersionOrGreater(10, 0, 17763) then begin
    SuppressibleMsgBox(ExpandConstant('{cm:WindowsVersionTooOld}'), mbError, MB_OK, IDOK);
    Result := False;
    Exit;
  end;

  // 2. 降级检查
  if GetInstalledVersion(InstalledVersion) then begin
    if CompareVersions('{#MyAppVersion}', InstalledVersion) < 0 then begin
      // 新版本低于已安装版本，拒绝降级
      SuppressibleMsgBox(
        FmtMessage(ExpandConstant('{cm:DowngradeMsg}'), [InstalledVersion, '{#MyAppVersion}']),
        mbError, MB_OK, IDOK);
      Result := False;
      Exit;
    end else if CompareVersions('{#MyAppVersion}', InstalledVersion) > 0 then begin
      // 升级提示
      SuppressibleMsgBox(
        FmtMessage(ExpandConstant('{cm:OldVersionFoundMsg}'), [InstalledVersion]),
        mbInformation, MB_OK, IDOK);
    end;
  end;

  // 3. 关闭正在运行的应用
  if CheckForMutexes('{#MyAppMutex}') then begin
    SuppressibleMsgBox(ExpandConstant('{cm:AppRunning}'), mbInformation, MB_OK, IDOK);
    KillRunningApp;
    // 等待 mutex 释放
    if CheckForMutexes('{#MyAppMutex}') then begin
      SuppressibleMsgBox(ExpandConstant('{cm:AppRunningCloseFailed}'), mbError, MB_OK, IDOK);
      Result := False;
      Exit;
    end;
  end;
end;

// ============================================================
// 初始化卸载：关闭程序 + 询问是否保留用户数据
// ============================================================
function InitializeUninstall(): Boolean;
var
  UserDir: String;
  MsgResult: Integer;
begin
  Result := True;

  // 关闭正在运行的程序
  if CheckForMutexes('{#MyAppMutex}') then begin
    KillRunningApp;
    Sleep(500);
  end;

  // 询问是否保留用户数据（实际存放在 %APPDATA%\jerry_suite）
  UserDir := ExpandConstant('{userappdata}\jerry_suite');
  if DirExists(UserDir) then begin
    MsgResult := SuppressibleMsgBox(
      ExpandConstant('{cm:UninstallDataMsg}'),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON1, IDYES);
    if MsgResult = IDNO then begin
      // 用户选择彻底删除
      DelTree(UserDir, True, True, True);
    end;
  end;
end;
