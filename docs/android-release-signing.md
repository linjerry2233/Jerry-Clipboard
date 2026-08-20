# Android Release 签名

## 当前配置

- Release 签名类型：PKCS12
- Key alias：`jerry-suite-release`
- Keystore：`android/keys/jerry-suite-release-final.jks`
- 证书 SHA-256：`9215D08964BDAB13A3A3D00566062758750DB95EFCCC7EE10E8D2343923D4A7D`
- APK 签名方案：APK Signature Scheme v2

Keystore 和密码已加入 Git 忽略规则，不会提交到仓库。必须备份 keystore 和对应密码；如果丢失，后续版本无法覆盖安装当前版本，只能更换 applicationId 或卸载重装。

## Gradle 行为

`android/app/build.gradle.kts` 从 `android/key.properties` 或以下用户环境变量读取签名信息：

- `JERRY_ANDROID_STORE_FILE`
- `JERRY_ANDROID_STORE_PASSWORD`
- `JERRY_ANDROID_KEY_ALIAS`
- `JERRY_ANDROID_KEY_PASSWORD`

Release 构建缺少完整签名配置时会直接失败，不再允许生成未签名 APK。Debug 构建不受影响。

## 验证命令

```powershell
flutter build apk --release
C:\Android\Sdk\build-tools\36.0.0\apksigner.bat verify --verbose --print-certs `
  build\app\outputs\flutter-apk\app-release.apk
```

每次交付 Android APK 前都必须确认 `apksigner` 输出 `Verifies`，并核对证书 SHA-256 指纹没有变化。

