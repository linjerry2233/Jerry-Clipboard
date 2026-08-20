import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/models/models.dart';
import '../../core/services/services.dart';

/// 云同步设置面板（嵌入设置弹窗的 Tab 内容）
class CloudSyncSettingsPanel extends StatefulWidget {
  const CloudSyncSettingsPanel({super.key});

  @override
  State<CloudSyncSettingsPanel> createState() => CloudSyncSettingsPanelState();
}

class CloudSyncSettingsPanelState extends State<CloudSyncSettingsPanel> {
  final _configService = CloudSyncConfigService();
  final _crypto = CryptoService();
  final _ssh = SshKeyService();
  final _scheduler = CloudSyncScheduler();

  /// 动态获取同步服务（SSH/REST 模式切换后自动适配）
  CloudSyncService get _sync => getCloudSyncService();

  late CloudSyncConfig _config;
  bool _backendAvailable = false;
  bool _sshKeygenAvailable = false;
  bool _isSyncing = false;
  String _statusMessage = '';
  String _publicKeyContent = '';
  SshKeyType _sshKeyType = SshKeyType.ed25519;

  /// 粘贴私钥内容输入框控制器
  final TextEditingController _pemInputController = TextEditingController();
  late final TextEditingController _repoUrlController;
  late final TextEditingController _branchController;
  late final TextEditingController _usernameController;
  late final TextEditingController _tokenController;

  /// 是否为移动端平台（影响部分 UI，如隐藏"选择私钥"按钮）
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// 当前是否为 SSH 认证模式
  bool get _useSsh => _config.useSsh;

  @override
  void initState() {
    super.initState();
    _config = _configService.config;
    _repoUrlController = TextEditingController(text: _config.repoUrl);
    _branchController = TextEditingController(text: _config.branch);
    _usernameController = TextEditingController(text: _config.username);
    _tokenController = TextEditingController(text: _config.token);
    _checkEnvironment();
    _refreshPublicKey();
  }

  Future<void> _checkEnvironment() async {
    final backendOk = await _sync.isBackendAvailable();
    final sshOk = await _ssh.isSshKeygenAvailable();
    if (!mounted) return;
    setState(() {
      _backendAvailable = backendOk;
      _sshKeygenAvailable = sshOk;
    });
  }

  Future<void> _refreshPublicKey() async {
    if (_config.sshKeyFileName.isEmpty) return;
    final pub = await _ssh.readPublicKey(_config.sshKeyFileName);
    if (!mounted) return;
    setState(() => _publicKeyContent = pub ?? '');
  }

  @override
  void dispose() {
    _pemInputController.dispose();
    _repoUrlController.dispose();
    _branchController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// 公开保存方法：供父级对话框在"保存"按钮点击时调用
  Future<void> save() async {
    await _configService.save(_config);
    await _scheduler.restart();
  }

  Future<void> _exportCloudConfig() async {
    try {
      final content = await _configService.exportConfig();
      const typeGroup = XTypeGroup(
        label: 'Jerry Suite 云同步配置',
        extensions: <String>['jscf'],
      );
      final location = await getSaveLocation(
        acceptedTypeGroups: const [typeGroup],
        suggestedName: 'jerry-suite-cloud-sync.jscf',
        confirmButtonText: '导出',
      );
      if (location == null) return;
      var path = location.path;
      if (p.extension(path).toLowerCase() != '.jscf') path = '$path.jscf';
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(content)),
        name: p.basename(path),
        mimeType: 'application/json',
      ).saveTo(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('云同步配置已导出：${p.basename(path)}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出云同步配置失败：$error')));
    }
  }

  Future<void> _importCloudConfig() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Jerry Suite 云同步配置',
        extensions: <String>['jscf'],
      );
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null) return;
      // SAF implementations may omit XFile.name; the type filter still
      // restricts the picker, so only reject a non-empty explicit name.
      if (file.name.isNotEmpty && !file.name.toLowerCase().endsWith('.jscf')) {
        throw const FormatException('请选择 .jscf 云同步配置文件');
      }
      final imported = await _configService.importConfig(
        await file.readAsString(),
      );
      if (!mounted) return;
      setState(() {
        _config = imported;
        _repoUrlController.text = imported.repoUrl;
        _branchController.text = imported.branch;
        _usernameController.text = imported.username;
        _tokenController.text = imported.token;
      });
      CloudSyncServiceFactory.reset();
      await _scheduler.restart();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('云同步配置已导入并保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入云同步配置失败：$error')));
    }
  }

  /// 保存用户粘贴的私钥 PEM 内容
  ///
  /// 用户可在输入框中直接粘贴 OpenSSH/RSA/ECDSA 私钥内容，
  /// 点击"保存粘贴的密钥"后写入应用私有目录并切换至 SSH 模式。
  Future<void> _savePastedPrivateKey() async {
    final pem = _pemInputController.text.trim();
    if (pem.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请粘贴私钥内容')));
      return;
    }
    if (!pem.contains('BEGIN OPENSSH PRIVATE KEY') &&
        !pem.contains('BEGIN RSA PRIVATE KEY') &&
        !pem.contains('BEGIN EC PRIVATE KEY') &&
        !pem.contains('BEGIN PRIVATE KEY')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密钥内容无效（缺少 PEM 头标记）')));
      return;
    }

    try {
      // 校验私钥可被 dartssh2 解析
      await _ssh.extractPublicKeyFromPem(pem);

      // 写入应用私有目录，文件名用时间戳避免冲突
      final fileName = 'pasted_${DateTime.now().millisecondsSinceEpoch}';
      final importedPath = await _ssh.importPrivateKeyPem(
        pemContent: pem,
        fileName: fileName,
      );

      // 尝试读取同目录 .pub 文件（粘贴场景通常没有）
      final pub = await _ssh.readPublicKeyFromPath(importedPath);

      if (!mounted) return;
      setState(() {
        _config = _config.copyWith(
          sshKeyPath: importedPath,
          sshKeyFileName: _basename(importedPath),
          useSsh: true,
        );
        _publicKeyContent = pub ?? '';
        _pemInputController.clear();
      });
      CloudSyncServiceFactory.reset();
      await save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pub == null
                ? '私钥已保存：${_basename(importedPath)}（无公钥，请手动添加公钥到 Gitee）'
                : '私钥已保存：${_basename(importedPath)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存私钥失败：$e')));
    }
  }

  Future<void> _generateAesKey() async {
    try {
      final path = await _crypto.generateAesKey(_config.aesAlgorithm);
      setState(() {
        _config = _config.copyWith(aesKeyPath: path);
      });
      await save();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AES 密钥已生成：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成 AES 密钥失败：$e')));
    }
  }

  /// 选择已有的 AES 密钥文件
  ///
  /// - 桌面端：直接使用文件路径
  /// - 移动端：Android SAF 返回的 `XFile.path` 是临时缓存副本（content:// 拷贝），
  ///   会被系统清理，导致后续同步报「AES 密钥文件不存在」。因此读取密钥字节
  ///   并写入应用私有目录 `<appSupportDir>/keys/<name>` 持久保存（与 SSH 私钥
  ///   导入逻辑一致）。
  Future<void> _pickAesKeyFile() async {
    const typeGroup = XTypeGroup(
      label: 'AES 密钥',
      extensions: <String>['key', 'bin'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    String path;
    if (_isMobile) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('所选密钥文件为空')));
          return;
        }
        path = await _crypto.importKeyBytes(bytes, fileName: file.name);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入 AES 密钥失败：$e')));
        return;
      }
    } else {
      path = file.path;
    }

    setState(() {
      _config = _config.copyWith(aesKeyPath: path);
    });
    await save();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已选择 AES 密钥：${_basename(path)}')));
  }

  Future<void> _generateSshKey() async {
    if (!_sshKeygenAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未检测到 ssh-keygen，请先安装 OpenSSH')),
      );
      return;
    }
    // 移动端仅支持 Ed25519
    if (_isMobile && !_sshKeyType.supportedOnMobile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移动端仅支持 Ed25519 密钥类型，已自动切换')),
      );
      setState(() => _sshKeyType = SshKeyType.ed25519);
    }
    try {
      final result = await _ssh.generateKeyPair(keyType: _sshKeyType);
      setState(() {
        _config = _config.copyWith(
          sshKeyFileName: _basename(result.privateKeyPath),
          sshKeyPath: result.privateKeyPath,
          // 生成密钥后自动启用 SSH 模式（全平台支持）
          useSsh: true,
        );
        _publicKeyContent = result.publicKeyContent;
      });
      // 切换 SSH 模式后，重置工厂以使用新的同步服务
      CloudSyncServiceFactory.reset();
      await save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isMobile
                ? 'SSH 密钥已生成，已切换至 SSH 直连模式。请将公钥添加到 Gitee/GitHub'
                : 'SSH 密钥已生成：${result.privateKeyPath}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成 SSH 密钥失败：$e')));
    }
  }

  String _basename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  /// 在 Windows 资源管理器中打开指定目录；若提供 [selectFile] 则选中该文件
  ///
  /// Android 平台不支持，直接返回。
  Future<void> _openInExplorer(String dirPath, {String? selectFile}) async {
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前平台不支持打开文件夹')));
      return;
    }
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (selectFile != null) {
        final filePath = p.join(dirPath, selectFile);
        // explorer /select,<path> 会打开目录并选中文件
        await Process.start('explorer.exe', ['/select,', filePath]);
      } else {
        await Process.start('explorer.exe', [dirPath]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开文件夹失败：$e')));
    }
  }

  /// 打开 AES 密钥所在目录
  Future<void> _openAesKeyFolder() async {
    if (_config.aesKeyPath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先生成 AES 密钥')));
      return;
    }
    final dir = p.dirname(_config.aesKeyPath!);
    await _openInExplorer(dir, selectFile: _basename(_config.aesKeyPath!));
  }

  /// 打开 SSH 密钥所在目录
  Future<void> _openSshKeyFolder() async {
    // 优先使用 sshKeyPath（绝对路径），否则用 ~/.ssh/
    if (_config.sshKeyPath != null && _config.sshKeyPath!.isNotEmpty) {
      final dir = p.dirname(_config.sshKeyPath!);
      await _openInExplorer(dir, selectFile: _basename(_config.sshKeyPath!));
      return;
    }
    if (_config.sshKeyFileName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先生成 SSH 密钥')));
      return;
    }
    await _openInExplorer(
      await _ssh.sshDir,
      selectFile: _config.sshKeyFileName,
    );
  }

  /// 选择 SSH 私钥文件
  ///
  /// - 桌面端：直接使用文件路径（dartssh2 可直接读取）
  /// - 移动端：Android SAF 返回 content:// URI，无法直接读取，
  ///   需通过 `XFile.readAsString()` 读取内容，再写入应用私有目录
  ///   `<appSupportDir>/ssh/<filename>`，避免 .bin 后缀和沙箱权限问题。
  Future<void> _pickSshPrivateKey() async {
    const typeGroup = XTypeGroup(
      label: 'SSH 私钥',
      extensions: <String>[], // 私钥通常无扩展名，不限制
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    if (_isMobile) {
      // 移动端：读取内容 → 导入到应用私有目录
      try {
        final pemContent = await file.readAsString();
        if (pemContent.isEmpty ||
            (!pemContent.contains('BEGIN OPENSSH PRIVATE KEY') &&
                !pemContent.contains('BEGIN RSA PRIVATE KEY') &&
                !pemContent.contains('BEGIN EC PRIVATE KEY') &&
                !pemContent.contains('BEGIN PRIVATE KEY'))) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所选文件不是有效的 SSH 私钥（PEM 格式）')),
          );
          return;
        }

        // 使用原始文件名（去除路径），若为空则用默认名
        // 注意：Android SAF 对无扩展名文件会自动附加 .bin 后缀，需剥离
        var originalName = _basename(
          file.name.isEmpty ? 'imported_key' : file.name,
        );
        if (originalName.endsWith('.bin')) {
          originalName = originalName.substring(0, originalName.length - 4);
        }
        final importedPath = await _ssh.importPrivateKeyPem(
          pemContent: pemContent,
          fileName: originalName,
        );

        // 验证私钥可被 dartssh2 解析（无效会抛异常）
        await _ssh.extractPublicKeyFromPem(pemContent);
        // 公钥依赖同目录 .pub 文件（移动端 SAF 通常无法同时获取）
        final pub = await _ssh.readPublicKeyFromPath(importedPath);

        if (!mounted) return;
        setState(() {
          _config = _config.copyWith(
            sshKeyPath: importedPath,
            sshKeyFileName: _basename(importedPath),
            useSsh: true,
          );
          _publicKeyContent = pub ?? '';
        });
        CloudSyncServiceFactory.reset();
        await save();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pub == null
                  ? '私钥已导入：${_basename(importedPath)}（无公钥文件，请手动添加公钥到 Gitee）'
                  : '私钥已导入：${_basename(importedPath)}',
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入私钥失败：$e')));
      }
      return;
    }

    // 桌面端：直接使用文件路径
    final path = file.path;
    setState(() {
      _config = _config.copyWith(
        sshKeyPath: path,
        sshKeyFileName: _basename(path),
        useSsh: true,
      );
    });
    // 切换 SSH 模式后重置工厂
    CloudSyncServiceFactory.reset();
    // 尝试读取对应公钥
    final pub = await _ssh.readPublicKeyFromPath(path);
    if (!mounted) return;
    setState(() => _publicKeyContent = pub ?? '');
    await save();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已选择私钥：${_basename(path)}')));
  }

  Future<void> _copyPublicKey() async {
    if (_publicKeyContent.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _publicKeyContent));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('公钥已复制到剪贴板')));
  }

  /// 通用同步执行方法
  ///
  /// [mode]：'sync' = 双向增量，'push' = 同步至云端，'pull' = 同步至本地
  Future<void> _runSync(String mode) async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _statusMessage = mode == 'push'
          ? '同步至云端中…'
          : mode == 'pull'
          ? '同步至本地中…'
          : '同步中…';
    });
    final Future<SyncResult> Function({SyncProgressCallback? onProgress}) fn;
    switch (mode) {
      case 'push':
        fn = _sync.pushToCloud;
        break;
      case 'pull':
        fn = _sync.pullToLocal;
        break;
      default:
        fn = _sync.syncOnce;
    }
    final result = await CloudSyncCoordinator().run(
      () => fn(
        onProgress: (status, detail) {
          if (!mounted) return;
          setState(() => _statusMessage = detail);
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      _isSyncing = false;
      _statusMessage = result.message;
    });
    // 重新读取配置以刷新 lastSyncAt
    setState(() {
      _config = _configService.config;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 环境检查
          _EnvBadges(
            backendAvailable: _backendAvailable,
            sshKeygenAvailable: _sshKeygenAvailable,
            useSsh: _useSsh,
            isMobile: _isMobile,
          ),
          const SizedBox(height: 12),

          // ============ 仓库配置 ============
          _CloudSettingsCard(
            theme: theme,
            title: '仓库配置',
            icon: Icons.cloud_outlined,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: '仓库地址（HTTPS 或 SSH）',
                  hintText: 'https://gitee.com/user/repo.git',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                ),
                controller: _repoUrlController,
                onChanged: (v) => _config = _config.copyWith(repoUrl: v),
              ),
              const SizedBox(height: 8),
              // 分支与用户名：宽屏并排，窄屏换行
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 480;
                  final fields = <Widget>[
                    TextField(
                      decoration: InputDecoration(
                        labelText: '分支',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      controller: _branchController,
                      onChanged: (v) => _config = _config.copyWith(branch: v),
                    ),
                    TextField(
                      decoration: InputDecoration(
                        labelText: '用户名（可选）',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      controller: _usernameController,
                      onChanged: (v) => _config = _config.copyWith(username: v),
                    ),
                  ];
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 8),
                        Expanded(child: fields[1]),
                      ],
                    );
                  }
                  return Column(
                    children: [fields[0], const SizedBox(height: 8), fields[1]],
                  );
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('使用 SSH 认证'),
                subtitle: Text(
                  _isMobile
                      ? '启用后通过 SSH 密钥直连 Gitee/GitHub'
                      : '关闭则使用 HTTPS + Token',
                ),
                value: _config.useSsh,
                onChanged: (v) {
                  setState(() => _config = _config.copyWith(useSsh: v));
                  // 切换 SSH/REST 模式后重置工厂
                  CloudSyncServiceFactory.reset();
                },
              ),
              if (_config.useSsh &&
                  _config.repoUrl.isNotEmpty &&
                  !_config.repoUrlIsSsh)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SSH 模式下将自动使用：\n${_config.sshRepoUrl}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_config.useSsh) ...[
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: '密码 / Personal Access Token',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  obscureText: true,
                  controller: _tokenController,
                  onChanged: (v) => _config = _config.copyWith(token: v),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // ============ 配置备份 ============
          _CloudSettingsCard(
            theme: theme,
            title: '配置备份',
            icon: Icons.import_export_rounded,
            children: [
              Text(
                '导出或导入云同步的完整配置（仓库、认证、加密密钥路径及同步游标），文件后缀为 .jscf。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _exportCloudConfig,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('一键导出'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importCloudConfig,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('一键导入'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ============ 自动同步 ============
          _CloudSettingsCard(
            theme: theme,
            title: '自动同步',
            icon: Icons.sync,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用自动同步'),
                value: _config.autoSyncEnabled,
                onChanged: (v) => setState(
                  () => _config = _config.copyWith(autoSyncEnabled: v),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同步剪贴板图片'),
                subtitle: const Text('图片体积较大；关闭后只同步剪贴板中的文本和链接'),
                secondary: const Icon(Icons.image_outlined),
                value: _config.syncClipboardImages,
                onChanged: (v) => setState(
                  () => _config = _config.copyWith(syncClipboardImages: v),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('同步间隔'),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      initialValue: _config.autoSyncIntervalMinutes,
                      items: const [
                        DropdownMenuItem(value: 5, child: Text('5 分钟')),
                        DropdownMenuItem(value: 15, child: Text('15 分钟')),
                        DropdownMenuItem(value: 30, child: Text('30 分钟')),
                        DropdownMenuItem(value: 60, child: Text('1 小时')),
                        DropdownMenuItem(value: 180, child: Text('3 小时')),
                        DropdownMenuItem(value: 360, child: Text('6 小时')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(
                            () => _config = _config.copyWith(
                              autoSyncIntervalMinutes: v,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _isSyncing ? null : () => _runSync('sync'),
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('立即同步'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isSyncing ? null : () => _runSync('push'),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('同步至云端'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isSyncing ? null : () => _runSync('pull'),
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('同步至本地'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage.isEmpty
                      ? (_config.lastSyncAt != null
                            ? '上次同步：${_formatTime(_config.lastSyncAt!)}'
                            : '尚未同步')
                      : _statusMessage,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '即时推送已启用：本地新增/删除数据将自动同步至云端',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ============ 加密密钥 ============
          _CloudSettingsCard(
            theme: theme,
            title: '数据加密（AES）',
            icon: Icons.enhanced_encryption_outlined,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 480;
                  final dropdown = DropdownButtonFormField<AesAlgorithm>(
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    initialValue: _config.aesAlgorithm,
                    items: AesAlgorithm.values
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text(a.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(
                          () => _config = _config.copyWith(aesAlgorithm: v),
                        );
                      }
                    },
                  );
                  if (wide) {
                    return Row(
                      children: [
                        const Text('算法'),
                        const SizedBox(width: 16),
                        Expanded(child: dropdown),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('算法'),
                      const SizedBox(height: 6),
                      dropdown,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      _config.aesKeyPath == null
                          ? '尚未生成或选择密钥'
                          : '密钥文件：${_basename(_config.aesKeyPath!)}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _generateAesKey,
                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: const Text('生成'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickAesKeyFile,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('选择密钥'),
                  ),
                  if (Platform.isWindows)
                    OutlinedButton.icon(
                      onPressed: _config.aesKeyPath == null
                          ? null
                          : _openAesKeyFolder,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('打开'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ============ SSH 密钥对 ============
          _CloudSettingsCard(
            theme: theme,
            title: 'SSH 密钥对',
            icon: Icons.vpn_key_outlined,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _pickSshPrivateKey,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('添加 SSH 密钥'),
                ),
              ),
              if (_isMobile && _useSsh) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已启用 SSH 直连模式：本机将通过 SSH 密钥直接连接 Gitee/GitHub，无需 Token。请确保公钥已添加到代码托管平台。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 480;
                  final dropdown = DropdownButtonFormField<SshKeyType>(
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    initialValue: _isMobile
                        ? (SshKeyType.ed25519)
                        : _sshKeyType,
                    items:
                        (_isMobile
                                ? SshKeyType.values
                                      .where((t) => t.supportedOnMobile)
                                      .toList()
                                : SshKeyType.values)
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.displayName),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _sshKeyType = v);
                    },
                  );
                  if (wide) {
                    return Row(
                      children: [
                        const Text('密钥类型'),
                        const SizedBox(width: 16),
                        Expanded(child: dropdown),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('密钥类型'),
                      const SizedBox(height: 6),
                      dropdown,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      _config.sshKeyPath != null &&
                              _config.sshKeyPath!.isNotEmpty
                          ? '私钥文件：${_basename(_config.sshKeyPath!)}'
                          : _config.sshKeyFileName.isEmpty
                          ? '尚未添加密钥'
                          : '密钥文件：~/.ssh/${_config.sshKeyFileName}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _generateSshKey,
                    icon: const Icon(Icons.key, size: 18),
                    label: const Text('生成'),
                  ),
                  if (Platform.isWindows)
                    OutlinedButton.icon(
                      onPressed:
                          (_config.sshKeyPath != null &&
                                  _config.sshKeyPath!.isNotEmpty) ||
                              _config.sshKeyFileName.isNotEmpty
                          ? _openSshKeyFolder
                          : null,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('打开'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _isMobile
                    ? '点击"添加 SSH 密钥"选择本地私钥文件，或"生成"新 Ed25519 密钥对；也可直接粘贴私钥内容保存'
                    : '点击"添加 SSH 密钥"选择本机已有的私钥文件，或"生成"新密钥对；也可直接粘贴私钥内容保存',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pemInputController,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: '或粘贴私钥内容（PEM 格式）',
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _savePastedPrivateKey,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保存粘贴的密钥'),
                ),
              ),
              if (_publicKeyContent.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _publicKeyContent,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: _copyPublicKey,
                        tooltip: '复制公钥',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '请将上述公钥添加到 Gitee/GitHub 的 SSH Keys 设置中',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// 云同步设置页内的分区卡片：与设置页 _SettingsCard 保持视觉一致
class _CloudSettingsCard extends StatelessWidget {
  const _CloudSettingsCard({
    required this.theme,
    required this.title,
    required this.icon,
    required this.children,
  });

  final ThemeData theme;
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.78)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _EnvBadges extends StatelessWidget {
  const _EnvBadges({
    required this.backendAvailable,
    required this.sshKeygenAvailable,
    required this.useSsh,
    required this.isMobile,
  });
  final bool backendAvailable;
  final bool sshKeygenAvailable;
  final bool useSsh;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    // 后端标签：移动端根据 useSsh 显示 SSH/REST；桌面端显示 Git
    final backendLabel = useSsh ? 'SSH 直连' : 'REST API / Git CLI';
    // 密钥生成标签：移动端显示"密钥生成"，桌面端显示"ssh-keygen"
    final keygenLabel = isMobile ? 'SSH 密钥生成' : 'ssh-keygen';
    return Wrap(
      spacing: 8,
      children: [
        _badge(backendLabel, backendAvailable),
        _badge(keygenLabel, sshKeygenAvailable),
      ],
    );
  }

  Widget _badge(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ok
            ? const Color(0xFF22C55E).withValues(alpha: 0.15)
            : const Color(0xFFEF4444).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 14,
            color: ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: ${ok ? "可用" : "未安装"}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
