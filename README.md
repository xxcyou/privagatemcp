# PrivaGate MCP

> 把 Android 手机的 root 能力与系统权限,通过 [MCP](https://modelcontextprotocol.io)(Model Context Protocol) 安全地暴露给 AI 客户端。

基于 **SukiSU-Ultra / KernelSU** 内核的 Android MCP 服务器。App 内置 Streamable HTTP MCP 服务,AI 客户端(OpenClaw、Claude Desktop 等)通过 Bearer Token 接入后,即可远程执行 shell、读写文件、操作短信/通讯录/日历/通知,以及调用无障碍、屏幕捕获等能力。

## ✨ 功能

- **权限降级链**:`root → Sui → Shizuku` 自动降级,没有 root 也能用 shell 级能力
- **74 个 MCP 工具**,覆盖 22 项权限:
  - shell: `exec` / `read_file` / `write_file` / `list_dir` / `dumpsys` / `logcat` / `set_prop` / `input_event` …
  - 存储: `storage_list` / `mkdir` / `delete` / `move` / `copy` / `stat` / `read` / `write` / `touch` / `disk`
  - 系统: 电话 / WiFi / 蓝牙 / 定位 / 使用统计 / 电池 / 传感器 / NFC / 剪贴板
  - 隐私: 短信(含会话/删除/已读)、通讯录(增删改查)、通话记录、日历(增删)
  - 增强: 无障碍(`ui_dump` / `ui_click` / `ui_text` / `ui_swipe` …)、屏幕捕获、相机、录音
  - 便捷: 内置 ADB(一键开无线调试)、悬浮窗、通知管理、应用管理
- **按权限动态注册工具**:未开启的权限不会暴露对应 MCP 工具,工具页同步灰显引导开启
- **安全设计**:动态 Bearer Token(可随时重新生成)、局域网直连、前台服务保活
- **多主题**:6 套配色 × 亮/暗/跟随系统
- **内置 ADB**:App 内一键开启 `adb connect` 无线调试

## 🏗 架构

```
┌─────────────────────────── Android 手机 ───────────────────────────┐
│                                                                     │
│  AI 客户端 ──Streamable HTTP──► Dart MCP Server (8787)             │
│                                    │ Bearer Token 鉴权              │
│                                    ▼                               │
│                              AppState / 工具注册层                  │
│                                    │ MethodChannel                 │
│                                    ▼                               │
│  Kotlin 原生层: RootEngine(SukiSU/Sui/Shizuku) · PermHelper       │
│                 AccessibilityService · ScreenCapture · DataTools   │
└─────────────────────────────────────────────────────────────────────┘
```

- `lib/mcp/` — MCP 服务器(Streamable HTTP + SSE 推送 + 按权限注册工具)
- `lib/core/` — root 引擎、权限模型、原生桥接
- `lib/ui/` — 四页 UI(首页/工具/日志/设置)+ 主题系统
- `android/` — Kotlin 原生模块(权限、无障碍、截屏、ADB、媒体)

## 🔧 构建

要求:

- Flutter 3.44+ / Dart 3.12+([flutter-sdk](https://docs.flutter.dev/get-started/install))
- Android SDK 36
- 运行设备需刷入 **SukiSU-Ultra / KernelSU** 内核(或使用 Sui / Shizuku 降级)

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

> ⚠️ 源码默认使用 debug keystore 签名,仅用于自用测试。正式分发请生成自己的 release keystore:
>
> ```bash
> keytool -genkey -v -keystore release.jks -alias priva -keyalg RSA -keysize 2048 -validity 10000
> ```
>
> 并在 `android/app/build.gradle.kts` 中配置 `signingConfigs.release`。

## 📲 使用

安装后打开 App → 授权(root 弹窗选「始终允许」)→ 开启 MCP 服务器开关 → 客户端接入:

```bash
adb reverse tcp:8787 tcp:8787   # USB 直连(推荐)
# 或局域网直连: http://<手机IP>:8787/mcp ,Token 在设置页查看
```

客户端配置示例(OpenClaw):

```json
{
  "mcpServers": {
    "phone-root": {
      "url": "http://127.0.0.1:8787/mcp",
      "headers": { "Authorization": "Bearer <App设置页的Token>" }
    }
  }
}
```

详细接入见 [CONNECT.md](CONNECT.md)。

## 🔐 安全说明

- 所有请求强制 Bearer Token 鉴权,Token 首次启动随机生成,可随时重新生成
- 工具按已授权权限动态注册,**未授权的权限不暴露任何工具**
- root 命令走 SukiSU 授权链,首次执行会触发系统授权确认
- 切勿在不可信网络开启 MCP 服务器;使用完建议关闭开关

## ⚠️ 免责声明

本项目是 **root 级权限管理工具**,可能被滥用或导致设备异常。请仅在**自己的设备**上使用,并自行承担一切风险。作者不对任何误操作、数据丢失或设备损坏负责。请遵守当地法律法规,勿用于任何非法用途。

## 📄 许可证

MIT License,详见 [LICENSE](LICENSE)。
