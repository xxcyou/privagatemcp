# PrivaGate MCP 接入指南

基于 SukiSU-Ultra / KernelSU 的 root 能力,通过 MCP (Streamable HTTP) 暴露给 AI 客户端。

## 1. 安装

```bash
# arm64 设备(绝大多数现代手机)
adb install app-arm64-v8a-release.apk
```

安装后打开 App → SukiSU 管理器弹出授权框 → 选「始终允许」→ 首页开启 MCP 服务器开关(拉起前台服务保活)。

## 2. 两种连接方式

### A. USB(推荐,走 adb reverse 隧道)

```bash
adb reverse tcp:8787 tcp:8787
# 端点: http://127.0.0.1:8787/mcp
```

### B. 局域网(手机与电脑同网)

手机首页连接信息卡显示 `http://<手机IP>:8787/mcp`,Token 在设置页查看/复制。也可以直接点首页的 **JSON 复制** 按钮,一次复制 `{"url", "token"}` 完整配置(局域网 IP 每 5 秒自动刷新,换网络后实时更新)。

## 3. 配置 AI 客户端

### OpenClaw(openclaw.config.json / mcp 配置)

```json
{
  "mcpServers": {
    "phone-root": {
      "url": "http://127.0.0.1:8787/mcp",
      "headers": { "Authorization": "Bearer <替换为App里的Token>" }
    }
  }
}
```

### Claude Desktop (claude_desktop_config.json)

```json
{
  "mcpServers": {
    "phone-root": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://127.0.0.1:8787/mcp"],
      "env": { "MCP_REMOTE_AUTH_HEADER": "Authorization: Bearer <Token>" }
    }
  }
}
```

## 4. 工具能力一览

App 按**已授权权限**动态注册工具(最多 74 个),未授权权限的工具不会暴露给客户端。分类:

| 分类 | 工具示例 |
|---|---|
| Shell | `exec` / `read_file` / `write_file` / `list_dir` / `dumpsys` / `logcat` / `set_prop` / `input_event` / `settings_edit` / `find_file` |
| 存储 | `storage_list` / `storage_mkdir` / `storage_delete` / `storage_move` / `storage_copy` / `storage_stat` / `storage_read` / `storage_write` / `storage_touch` / `storage_disk` |
| 系统 | `get_root_status` / `get_permissions` / `device_info` / `app_list` / `app_info` / `app_control` / `battery_status` / `wifi_status` / `bluetooth_status` / `sensor_read` / `nfc_status` |
| 隐私 | `sms_list` / `sms_threads` / `sms_send` / `sms_delete` / `sms_mark_read` / `contacts_list` / `contacts_search` / `contacts_add` / `contacts_update` / `contacts_delete` / `call_log_list` / `call_log_delete` / `calendar_list` / `calendar_add` / `calendar_delete` |
| 增强 | `ui_dump` / `ui_click` / `ui_text` / `ui_action` / `ui_swipe` / `ui_wait`(无障碍)/ `screenshot` / `screen_capture`(截屏)/ `camera_photo` / `audio_record` |
| 便捷 | `adb_service`(内置 ADB)/ `notifications_list` / `notifications_act` / `overlay_show` / `usage_stats` / `location_get` / `location_watch` / `phone_state` / `call_phone` / `wifi_scan` / `bluetooth_scan` |

## 5. 验证

```bash
curl -X POST http://127.0.0.1:8787/mcp \
  -H "Authorization: Bearer <Token>" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
```

## 注意

- Token 在设置页可重新生成;重新生成后客户端需同步更新
- 局域网暴露默认开启 Bearer 鉴权,勿在不可信网络使用
- 系统杀掉 App 进程后需重新打开(前台服务保活,非免死)
- 部分权限(MANAGE_EXTERNAL_STORAGE / SYSTEM_ALERT_WINDOW / 无障碍 / 截屏 / 电池白名单)需在系统设置中手动开启,App 内会引导
