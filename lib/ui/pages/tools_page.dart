import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/components.dart';

const _tools = [
  McpToolInfo(
    name: 'get_permissions',
    description: '查询全部权限状态：root/sui/shizuku/无障碍/截屏 + 当前生效级别',
    example: 'get_permissions()',
    icon: Icons.key_rounded,
    color: Color(0xFF2ED573),
    params: [],
  ),
  McpToolInfo(
    name: 'exec',
    description: '执行任意 shell 命令，默认以 root 运行（首次触发 SukiSU 授权弹窗）',
    example: 'exec(command: "pm list packages -3")',
    icon: Icons.terminal_rounded,
    color: Color(0xFF00D4FF),
    params: ['command', 'as_root', 'timeout_s', 'cwd'],
  ),
  McpToolInfo(
    name: 'adb_service',
    description: '内置 ADB：start 开启无线 adb（5555，root 直连）/ stop / status',
    example: 'adb_service(action: "start") → adb connect <IP>:5555',
    icon: Icons.adb_rounded,
    color: Color(0xFF4DB6AC),
    params: ['action'],
    minShell: 'root',
  ),
  McpToolInfo(
    name: 'screenshot',
    description: 'root 截屏 → base64 返回，AI 可直接“看”手机屏幕',
    example: 'screenshot() → 视觉分析',
    icon: Icons.screenshot_rounded,
    color: Color(0xFF26C6DA),
    params: [],
  ),
  McpToolInfo(
    name: 'device_info',
    description: '一键汇总：型号/系统/内核/CPU/内存/存储/电量/开机时长',
    example: 'device_info()',
    icon: Icons.memory_rounded,
    color: Color(0xFF2ED573),
    params: [],
  ),
  McpToolInfo(
    name: 'app_list',
    description: '列出应用（用户/系统/全部），带版本号',
    example: 'app_list(scope: "third")',
    icon: Icons.apps_rounded,
    color: Color(0xFF7C5CFF),
    params: ['scope'],
  ),
  McpToolInfo(
    name: 'app_info',
    description: '单应用详情：版本/UID/数据目录/安装时间/启用状态',
    example: 'app_info(package: "com.android.settings")',
    icon: Icons.info_outline_rounded,
    color: Color(0xFF448AFF),
    params: ['package'],
  ),
  McpToolInfo(
    name: 'app_control',
    description: '禁用/启用/强停/清数据/启动应用（清数据不可恢复）',
    example: 'app_control(package: "com.x", action: "force_stop")',
    icon: Icons.tune_rounded,
    color: Color(0xFFFFA726),
    params: ['package', 'action'],
  ),
  McpToolInfo(
    name: 'logcat',
    description: '抓取系统日志（root 可读全部应用日志与崩溃栈）',
    example: 'logcat(lines: 500, tag: "AndroidRuntime", level: "E")',
    icon: Icons.list_alt_rounded,
    color: Color(0xFFFF7043),
    params: ['lines', 'tag', 'level'],
  ),
  McpToolInfo(
    name: 'dumpsys',
    description: '转储任意系统服务（activity/battery/window…）',
    example: 'dumpsys(service: "battery")',
    icon: Icons.precision_manufacturing_rounded,
    color: Color(0xFF26A69A),
    params: ['service', 'args'],
  ),
  McpToolInfo(
    name: 'audit_log',
    description: '读取命令审计日志（每条 root/shell 执行落盘，排查 AI 执行过什么）',
    example: 'audit_log(tail: 20)',
    icon: Icons.fact_check_rounded,
    color: Color(0xFFFFB74D),
    params: ['tail'],
  ),
  McpToolInfo(
    name: 'set_prop',
    description: '设置系统属性（root，立即生效）',
    example: 'set_prop(name: "debug.hwui.profile", value: "true")',
    icon: Icons.toggle_on_rounded,
    color: Color(0xFFEC407A),
    params: ['name', 'value'],
    minShell: 'root',
  ),
  McpToolInfo(
    name: 'input_event',
    description: '模拟按键/文本/点击/滑动（可全局操作）',
    example: 'input_event(type: "keyevent", arg1: "26") // 电源键',
    icon: Icons.touch_app_rounded,
    color: Color(0xFF5C6BC0),
    params: ['type', 'arg1..arg5'],
  ),
  McpToolInfo(
    name: 'file_ops',
    description: '删除/移动/复制/建目录/chmod/chown',
    example: 'file_ops(action: "chmod", path: "/data/a.sh", mode: "0755")',
    icon: Icons.drive_file_move_rounded,
    color: Color(0xFF8D6E63),
    params: ['action', 'path', 'src', 'dst', 'mode', 'owner'],
  ),
  McpToolInfo(
    name: 'find_file',
    description: 'root 全盘搜索文件，支持通配符',
    example: 'find_file(name: "*.apk", dir: "/data/app")',
    icon: Icons.search_rounded,
    color: Color(0xFF66BB6A),
    params: ['name', 'dir'],
  ),
  McpToolInfo(
    name: 'settings_edit',
    description: '读写系统设置 system/global/secure',
    example: 'settings_edit(action: "get", namespace: "system", key: "screen_brightness")',
    icon: Icons.settings_suggest_rounded,
    color: Color(0xFF42A5F5),
    params: ['action', 'namespace', 'key', 'value'],
  ),
  McpToolInfo(
    name: 'ui_dump',
    requires: 'accessibility',
    description: '读取当前屏幕 UI 结构（JSON：文本/坐标/可点击性），需要无障碍服务',
    example: 'ui_dump() → JSON 树',
    icon: Icons.visibility_rounded,
    color: Color(0xFFFFA726),
    params: [],
  ),
  McpToolInfo(
    name: 'ui_click',
    requires: 'accessibility',
    description: '按文本或坐标点击屏幕元素（长按可选），需要无障碍服务',
    example: 'ui_click(text: "设置") / ui_click(x: 540, y: 1200)',
    icon: Icons.touch_app_rounded,
    color: Color(0xFFFF8A65),
    params: ['text', 'x', 'y', 'long'],
  ),
  McpToolInfo(
    name: 'ui_text',
    requires: 'accessibility',
    description: '向输入框写入文本，需要无障碍服务',
    example: 'ui_text(text: "hello")',
    icon: Icons.keyboard_alt_rounded,
    color: Color(0xFFAB47BC),
    params: ['text'],
  ),
  McpToolInfo(
    name: 'ui_action',
    requires: 'accessibility',
    description: '全局操作：返回/主页/最近任务/通知栏/快速设置/锁屏电源/滚动',
    example: 'ui_action(action: "back")',
    icon: Icons.swipe_rounded,
    color: Color(0xFF7E57C2),
    params: ['action'],
  ),
  McpToolInfo(
    name: 'ui_swipe',
    requires: 'accessibility',
    description: '滑动屏幕手势，需要无障碍服务',
    example: 'ui_swipe(x1: 600, y1: 2000, x2: 600, y2: 400)',
    icon: Icons.gesture_rounded,
    color: Color(0xFF29B6F6),
    params: ['x1', 'y1', 'x2', 'y2', 'duration'],
  ),
  McpToolInfo(
    name: 'location_get',
    requires: 'location',
    description: '获取设备当前位置（GPS/网络，需定位权限）',
    example: 'location_get() → {lat, lng, accuracy}',
    icon: Icons.location_on_rounded,
    color: Color(0xFF4FC3F7),
    params: [],
  ),
  McpToolInfo(
    name: 'notifications_list',
    requires: 'notifications',
    description: '读取通知栏全部通知（包名/标题/内容/时间）',
    example: 'notifications_list() → 最新通知',
    icon: Icons.notifications_rounded,
    color: Color(0xFFEF5350),
    params: [],
  ),
  McpToolInfo(
    name: 'notifications_act',
    requires: 'notifications',
    description: '操作通知：open 点击打开 / clear 清除 / clear_all 清空',
    example: 'notifications_act(action: "open", key: "...")',
    icon: Icons.swipe_rounded,
    color: Color(0xFFE57373),
    params: ['action', 'key'],
  ),
  McpToolInfo(
    name: 'overlay_show',
    requires: 'overlay',
    description: '悬浮窗显示一行文字（N 秒后消失）',
    example: 'overlay_show(text: "AI 控制中", seconds: 3)',
    icon: Icons.picture_in_picture_alt_rounded,
    color: Color(0xFFBA68C8),
    params: ['text', 'seconds'],
  ),
  McpToolInfo(
    name: 'battery_status',
    description: '电池信息：电量/充电状态/温度',
    example: 'battery_status()',
    icon: Icons.battery_charging_full_rounded,
    color: Color(0xFF81C784),
    params: [],
  ),
  McpToolInfo(
    name: 'clipboard_get',
    description: '读取剪贴板内容',
    example: 'clipboard_get() → AI 读剪贴板',
    icon: Icons.content_paste_rounded,
    color: Color(0xFF90A4AE),
    params: [],
  ),
  McpToolInfo(
    name: 'clipboard_set',
    description: '写入剪贴板内容',
    example: 'clipboard_set(text: "复制这段")',
    icon: Icons.content_copy_rounded,
    color: Color(0xFF78909C),
    params: ['text'],
  ),
  McpToolInfo(
    name: 'vibrate',
    description: '设备振动（毫秒）',
    example: 'vibrate(ms: 500)',
    icon: Icons.vibration_rounded,
    color: Color(0xFFB0BEC5),
    params: ['ms'],
  ),
  McpToolInfo(
    name: 'sensor_read',
    description: '传感器数据：加速度/光线/距离/陀螺仪/磁场',
    example: 'sensor_read(type: "light") → 环境亮度',
    icon: Icons.sensors_rounded,
    color: Color(0xFF80CBC4),
    params: ['type'],
  ),
  McpToolInfo(
    name: 'traffic_stats',
    description: '各应用网络流量统计（开机累计）',
    example: 'traffic_stats() → 流量排行',
    icon: Icons.data_usage_rounded,
    color: Color(0xFF4DB6AC),
    params: [],
  ),
  McpToolInfo(
    name: 'nfc_status',
    description: 'NFC 硬件状态查询',
    example: 'nfc_status()',
    icon: Icons.nfc_rounded,
    color: Color(0xFFA1887F),
    params: [],
  ),
  McpToolInfo(
    name: 'phone_state',
    requires: 'phone',
    description: '电话/SIM 状态（网络类型/运营商/漫游）',
    example: 'phone_state()',
    icon: Icons.sim_card_rounded,
    color: Color(0xFF66BB6A),
    params: [],
  ),
  McpToolInfo(
    name: 'call_phone',
    requires: 'phone',
    description: '直接拨打电话',
    example: 'call_phone(number: "10086")',
    icon: Icons.call_rounded,
    color: Color(0xFF43A047),
    params: ['number'],
  ),
  McpToolInfo(
    name: 'open_dialer',
    requires: 'phone',
    description: '打开拨号界面（预填号码）',
    example: 'open_dialer(number: "10086")',
    icon: Icons.dialpad_rounded,
    color: Color(0xFF2E7D32),
    params: ['number'],
  ),
  McpToolInfo(
    name: 'wifi_scan',
    requires: 'wifi',
    description: '扫描附近 WiFi（SSID/信号强度）',
    example: 'wifi_scan() → 附近网络',
    icon: Icons.wifi_rounded,
    color: Color(0xFF29B6F6),
    params: [],
  ),
  McpToolInfo(
    name: 'bluetooth_scan',
    requires: 'bluetooth',
    description: '扫描附近蓝牙设备（4 秒发现窗口）',
    example: 'bluetooth_scan() → 附近设备',
    icon: Icons.bluetooth_rounded,
    color: Color(0xFF1E88E5),
    params: [],
  ),
  McpToolInfo(
    name: 'bluetooth_status',
    requires: 'bluetooth',
    description: '蓝牙状态（开关/已配对设备）',
    example: 'bluetooth_status()',
    icon: Icons.bluetooth_connected_rounded,
    color: Color(0xFF1E88E5),
    params: [],
  ),
  McpToolInfo(
    name: 'storage_list',
    requires: 'file_access',
    description: '列出共享存储目录（/sdcard 下，独立于 root 的 list_dir）',
    example: 'storage_list(path: "/sdcard/Download")',
    icon: Icons.folder_zip_rounded,
    color: Color(0xFFFFB74D),
    params: ['path'],
  ),
  McpToolInfo(
    name: 'storage_read',
    requires: 'file_access',
    description: '读共享存储文件（文本，需文件访问权限）',
    example: 'storage_read(path: "/sdcard/Download/x.txt")',
    icon: Icons.article_rounded,
    color: Color(0xFFFFA726),
    params: ['path'],
  ),
  McpToolInfo(
    name: 'storage_write',
    requires: 'file_access',
    description: '写共享存储文件（需文件访问权限）',
    example: 'storage_write(path: "/sdcard/Download/x.txt", content: "hi")',
    icon: Icons.edit_rounded,
    color: Color(0xFFFF9800),
    params: ['path', 'content'],
  ),
  McpToolInfo(
    name: 'storage_touch',
    requires: 'file_access',
    description: '创建空文件（存在则更新时间戳）',
    example: 'storage_touch(path: "/sdcard/Download/note.txt")',
    icon: Icons.note_add_rounded,
    color: Color(0xFFFF9800),
    params: ['path'],
  ),
  McpToolInfo(
    name: 'storage_disk',
    requires: 'file_access',
    description: '磁盘空间信息（总容量/可用/已用）',
    example: 'storage_disk()',
    icon: Icons.storage_rounded,
    color: Color(0xFFFF9800),
    params: [],
  ),
  McpToolInfo(
    name: 'camera_photo',
    requires: 'camera',
    description: '调用相机拍照（JPEG base64，可直接视觉分析）',
    example: 'camera_photo() → 拍照 → AI 看图',
    icon: Icons.photo_camera_rounded,
    color: Color(0xFF5C6BC0),
    params: [],
  ),
  McpToolInfo(
    name: 'audio_record',
    requires: 'microphone',
    description: '录音 N 秒（m4a base64，可交语音模型）',
    example: 'audio_record(seconds: 10)',
    icon: Icons.mic_rounded,
    color: Color(0xFFEF5350),
    params: ['seconds'],
  ),
  McpToolInfo(
    name: 'sms_list',
    requires: 'sms',
    description: '读取收件箱短信（含验证码场景）',
    example: 'sms_list(limit: 20) → 找验证码',
    icon: Icons.sms_rounded,
    color: Color(0xFF66BB6A),
    params: ['limit'],
  ),
  McpToolInfo(
    name: 'sms_send',
    requires: 'sms',
    description: '发送短信',
    example: 'sms_send(number: "10086", text: "CXLL")',
    icon: Icons.send_rounded,
    color: Color(0xFF43A047),
    params: ['number', 'text'],
  ),
  McpToolInfo(
    name: 'sms_threads',
    requires: 'sms',
    description: '短信会话列表（按 thread_id 分组，含未读数）',
    example: 'sms_threads() → 找未读会话',
    icon: Icons.forum_rounded,
    color: Color(0xFF66BB6A),
    params: ['limit'],
  ),
  McpToolInfo(
    name: 'sms_delete',
    requires: 'sms',
    description: '删除短信（按 id 或号码）',
    example: 'sms_delete(id: 123) / sms_delete(number: "10086")',
    icon: Icons.delete_forever_rounded,
    color: Color(0xFFEF5350),
    params: ['id', 'number'],
  ),
  McpToolInfo(
    name: 'sms_mark_read',
    requires: 'sms',
    description: '标记短信已读（不传 id 全部标记）',
    example: 'sms_mark_read()',
    icon: Icons.done_all_rounded,
    color: Color(0xFF9CCC65),
    params: ['id'],
  ),
  McpToolInfo(
    name: 'contacts_list',
    requires: 'contacts',
    description: '读取通讯录（姓名+号码+id）',
    example: 'contacts_list() → 查联系人',
    icon: Icons.contacts_rounded,
    color: Color(0xFF42A5F5),
    params: ['limit'],
  ),
  McpToolInfo(
    name: 'contacts_search',
    requires: 'contacts',
    description: '搜索联系人（姓名/号码模糊匹配）',
    example: 'contacts_search(query: "张")',
    icon: Icons.search_rounded,
    color: Color(0xFF42A5F5),
    params: ['query'],
  ),
  McpToolInfo(
    name: 'contacts_add',
    requires: 'contacts',
    description: '新增联系人',
    example: 'contacts_add(name: "老王", number: "13800000000")',
    icon: Icons.person_add_rounded,
    color: Color(0xFF1E88E5),
    params: ['name', 'number'],
  ),
  McpToolInfo(
    name: 'contacts_update',
    requires: 'contacts',
    description: '更新联系人（按 id 改姓名/号码）',
    example: 'contacts_update(id: 5, number: "13900000000")',
    icon: Icons.person_pin_rounded,
    color: Color(0xFF1E88E5),
    params: ['id', 'name', 'number'],
  ),
  McpToolInfo(
    name: 'contacts_delete',
    requires: 'contacts',
    description: '删除联系人（按 id）',
    example: 'contacts_delete(id: 5)',
    icon: Icons.person_remove_rounded,
    color: Color(0xFFEF5350),
    params: ['id'],
  ),
  McpToolInfo(
    name: 'call_log',
    requires: 'call_log',
    description: '读取通话记录（号码/类型/时长/时间+id）',
    example: 'call_log(limit: 50)',
    icon: Icons.call_rounded,
    color: Color(0xFF26A69A),
    params: ['limit'],
  ),
  McpToolInfo(
    name: 'call_log_delete',
    requires: 'call_log',
    description: '删除通话记录（id/号码/清空）',
    example: 'call_log_delete(all: true)',
    icon: Icons.call_end_rounded,
    color: Color(0xFFEF5350),
    params: ['id', 'number', 'all'],
  ),
  McpToolInfo(
    name: 'calendar_list',
    requires: 'calendar',
    description: '读取日历事件（标题/时间/描述+id）',
    example: 'calendar_list() → 今日安排',
    icon: Icons.event_rounded,
    color: Color(0xFFFFA726),
    params: ['limit'],
  ),
  McpToolInfo(
    name: 'calendar_add',
    requires: 'calendar',
    description: '新增日历事件',
    example: 'calendar_add(title: "开会", start_ms: 1700000000000, end_ms: 1700003600000)',
    icon: Icons.event_available_rounded,
    color: Color(0xFFFFA726),
    params: ['title', 'start_ms', 'end_ms', 'description'],
  ),
  McpToolInfo(
    name: 'calendar_delete',
    requires: 'calendar',
    description: '删除日历事件（按 id）',
    example: 'calendar_delete(id: 42)',
    icon: Icons.event_busy_rounded,
    color: Color(0xFFEF5350),
    params: ['id'],
  ),
  McpToolInfo(
    name: 'usage_stats',
    requires: 'usage_stats',
    description: '应用使用时长统计（近 N 天前台时间排行）',
    example: 'usage_stats(days: 3)',
    icon: Icons.timeline_rounded,
    color: Color(0xFFAB47BC),
    params: ['days'],
  ),
  McpToolInfo(
    name: 'screen_capture',
    requires: 'capture',
    description: 'MediaProjection 屏幕捕获（无需 root），需在设置页授权',
    example: 'screen_capture() → PNG base64',
    icon: Icons.screenshot_monitor_rounded,
    color: Color(0xFF26C6DA),
    params: [],
  ),
  McpToolInfo(
    name: 'get_root_status',
    description: '查询 root 状态：是否授权、su 路径、SELinux 模式',
    example: 'get_root_status()',
    icon: Icons.verified_user_rounded,
    color: Color(0xFF2ED573),
    params: [],
  ),
  McpToolInfo(
    name: 'read_file',
    description: '读取任意文件（root 权限，可读 /data 等受保护目录）',
    example: 'read_file(path: "/data/adb/ksu/bin/su")',
    icon: Icons.description_rounded,
    color: Color(0xFF7C5CFF),
    params: ['path', 'as_root'],
  ),
  McpToolInfo(
    name: 'write_file',
    description: '写入任意文件（root 权限，自动覆盖，支持大内容）',
    example: 'write_file(path: "/data/local/tmp/x", content: "hi")',
    icon: Icons.edit_rounded,
    color: Color(0xFFFFA726),
    params: ['path', 'content', 'as_root'],
  ),
  McpToolInfo(
    name: 'list_dir',
    description: '列出目录内容（ls -la 原始输出，root 可看任何目录）',
    example: 'list_dir(path: "/data/adb")',
    icon: Icons.folder_open_rounded,
    color: Color(0xFFFF7043),
    params: ['path', 'as_root'],
  ),
];

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final grouped = <String, List<McpToolInfo>>{
      'shell': _tools.where((t) => t.requires == null).toList(),
      'accessibility':
          _tools.where((t) => t.requires == 'accessibility').toList(),
      'capture': _tools.where((t) => t.requires == 'capture').toList(),
      'location': _tools.where((t) => t.requires == 'location').toList(),
      'notifications':
          _tools.where((t) => t.requires == 'notifications').toList(),
      'overlay': _tools.where((t) => t.requires == 'overlay').toList(),
      'file_access': _tools.where((t) => t.requires == 'file_access').toList(),
      'camera': _tools.where((t) => t.requires == 'camera').toList(),
      'microphone': _tools.where((t) => t.requires == 'microphone').toList(),
      'sms': _tools.where((t) => t.requires == 'sms').toList(),
      'contacts': _tools.where((t) => t.requires == 'contacts').toList(),
      'call_log': _tools.where((t) => t.requires == 'call_log').toList(),
      'calendar': _tools.where((t) => t.requires == 'calendar').toList(),
      'usage_stats': _tools.where((t) => t.requires == 'usage_stats').toList(),
      'phone': _tools.where((t) => t.requires == 'phone').toList(),
      'wifi': _tools.where((t) => t.requires == 'wifi').toList(),
      'bluetooth': _tools.where((t) => t.requires == 'bluetooth').toList(),
    };

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          DS.pagePad, DS.sp16, DS.pagePad, DS.bottomNavPad),
      children: [
        Row(
          children: [
            Text('MCP 工具', style: DS.h1),
            const Spacer(),
            StatusBadge(
              app.mcp.running ? '在线' : '离线',
              color: app.mcp.running ? DS.ok : DS.textTertiary,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '共 ${_tools.length} 个 · 按当前权限自动激活',
          style: DS.caption,
        ),
        const SizedBox(height: DS.sp16),
        _quickTest(context, app),
        const SizedBox(height: DS.sp24),

        // 分组
        _group(context, '核心 · shell', grouped['shell']!, 'root/sui/shizuku 可用'),
        _group(context, '特殊 · 无障碍', grouped['accessibility']!,
            '设置页开启后激活（读取组件信息等 root 不具备的能力）'),
        _group(context, '特殊 · 屏幕捕获', grouped['capture']!,
            '设置页授权后激活（无 root 截屏通道）'),
        _group(context, '扩展 · 定位', grouped['location']!,
            '普通权限，无需 root'),
        _group(context, '扩展 · 通知', grouped['notifications']!,
            '通知使用权，AI 可读/点/清通知'),
        _group(context, '扩展 · 悬浮窗', grouped['overlay']!,
            '悬浮窗权限，屏幕显示文字'),
        _group(context, '扩展 · 共享存储', grouped['file_access']!,
            '文件访问权限，无需 root'),
        _group(context, '扩展 · 相机/麦克风',
            [...grouped['camera']!, ...grouped['microphone']!],
            '媒体权限，拍照/录音'),
        _group(context, '扩展 · 短信/通讯录',
            [...grouped['sms']!, ...grouped['contacts']!],
            '信息权限，读发短信/联系人'),
        _group(context, '扩展 · 通话/日历/统计',
            [...grouped['call_log']!, ...grouped['calendar']!, ...grouped['usage_stats']!],
            '通话记录/日历/使用统计'),
        _group(context, '扩展 · 电话/WiFi/蓝牙',
            [...grouped['phone']!, ...grouped['wifi']!, ...grouped['bluetooth']!],
            '拨号/设备状态/WiFi/蓝牙扫描'),
      ],
    );
  }

  Widget _group(BuildContext context, String title, List<McpToolInfo> tools, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, subtitle: hint),
        for (final t in tools) ...[
          _toolTile(context, t),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: DS.sp12),
      ],
    );
  }

  Widget _quickTest(BuildContext context, AppState app) {
    return AppCard(
      padding: const EdgeInsets.all(DS.sp16),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 20, color: DS.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('快速自检', style: DS.h2),
                SizedBox(height: 2),
                Text('以 root 执行 id 验证通道', style: DS.caption),
              ],
            ),
          ),
          PrimaryButton(
            label: '运行',
            icon: Icons.play_arrow_rounded,
            onTap: () => _runTest(context, app),
          ),
        ],
      ),
    );
  }

  Future<void> _runTest(BuildContext context, AppState app) async {
    final r = await app.engine.run('id',
        asRoot: true, timeout: const Duration(seconds: 15));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          r.isOk
              ? '✓ ${r.stdout.trim()}'
              : '✗ exit=${r.exitCode} ${r.stderr.trim()}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ));
  }

  Widget _toolTile(BuildContext context, McpToolInfo t) {
    final app = context.watch<AppState>();
    final active = _isActive(t.requires, app) && _shellOk(t.minShell, app);
    final label = _requiresLabel(t.requires, t.minShell, active);

    final iconColor = active ? t.color : DS.textSecondary;
    final nameColor = active ? DS.textPrimary : DS.textSecondary;
    final descColor = active ? DS.textSecondary : DS.textTertiary;

    return GestureDetector(
      onTap: active
          ? null
          : () {
              final messenger = ScaffoldMessenger.of(context);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('需要开启「$label」后才能使用 ${t.name}'),
                  action: SnackBarAction(
                    label: '去开启',
                    textColor: DS.accent,
                    onPressed: () => app.requestByRequires(t.requires),
                  ),
                ));
            },
      child: Opacity(
        opacity: active ? 1.0 : 0.78,
        child: AppCard(
          padding: const EdgeInsets.all(DS.sp16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DS.r12),
                  border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                ),
                child: Icon(t.icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            t.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: nameColor,
                            ),
                          ),
                        ),
                        if (t.requires != null || t.minShell != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: iconColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              active ? label : '$label 未开启',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: iconColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.description,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.45, color: descColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.example,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: active
                            ? DS.accent.withValues(alpha: 0.9)
                            : DS.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 判断工具是否已激活（对应权限已开启）
  bool _isActive(String? requires, AppState app) {
    final p = app.permissions;
    if (requires == null) return p.hasShell;
    return switch (requires) {
      'file_access' => p.fileAccess,
      'accessibility' => p.accessibility,
      'capture' => p.capture,
      'location' => p.location,
      'notifications' => p.notifications,
      'overlay' => p.overlay,
      'camera' => p.camera,
      'microphone' => p.microphone,
      'sms' => p.sms,
      'contacts' => p.contacts,
      'call_log' => p.callLog,
      'calendar' => p.calendar,
      'usage_stats' => p.usageStats,
      'phone' => p.phone,
      'wifi' => p.wifi,
      'bluetooth' => p.bluetooth,
      _ => false,
    };
  }

  /// 最低 shell 级别检查：root 工具需 root/sui；shizuku 工具需任意 shell
  bool _shellOk(String? min, AppState app) {
    if (min == null) return true;
    if (min == 'root') return app.permissions.hasRoot;
    return app.permissions.hasShell;
  }

  /// 权限中文名（含降级提示）
  String _requiresLabel(String? requires, String? minShell, bool active) {
    if (requires != null) {
      final base = switch (requires) {
        'file_access' => '文件访问',
        'accessibility' => '无障碍',
        'capture' => '屏幕捕获',
        'location' => '定位',
        'notifications' => '通知读取',
        'overlay' => '悬浮窗',
        'camera' => '相机',
        'microphone' => '麦克风',
        'sms' => '短信',
        'contacts' => '通讯录',
        'call_log' => '通话记录',
        'calendar' => '日历',
        'usage_stats' => '使用统计',
        'phone' => '电话',
        'wifi' => 'WiFi',
        'bluetooth' => '蓝牙',
        _ => '对应权限',
      };
      return active ? base : '$base 未开启';
    }
    if (minShell == 'root' && !active) return '需 root';
    if (minShell == 'shizuku' && !active) return '需 shizuku';
    return '';
  }
}
