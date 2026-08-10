/// Shell 权限级别（自动降级链）
enum ShellLevel { none, shizuku, sui, root }

extension ShellLevelX on ShellLevel {
  String get label => switch (this) {
        ShellLevel.root => 'root',
        ShellLevel.sui => 'sui',
        ShellLevel.shizuku => 'shizuku',
        ShellLevel.none => '无',
      };

  int get rank => switch (this) {
        ShellLevel.none => 0,
        ShellLevel.shizuku => 1,
        ShellLevel.sui => 2,
        ShellLevel.root => 3,
      };
}

/// 全量权限状态（万能权限体系）
class Permissions {
  // shell 权限
  bool root;
  bool sui;
  bool shizuku;
  String? suPath;
  String? suiPath;

  // 特殊能力
  bool accessibility;
  bool capture;

  // 扩展权限（无需 root，普通权限/设置页授权）
  bool fileAccess;
  bool location;
  bool overlay;
  bool notifications;
  bool camera;
  bool microphone;
  bool sms;
  bool contacts;
  bool callLog;
  bool calendar;
  bool usageStats;
  bool ignoreBattery;
  bool allApps;
  bool phone;
  bool wifi;
  bool bluetooth;

  Permissions({
    this.root = false,
    this.sui = false,
    this.shizuku = false,
    this.suPath,
    this.suiPath,
    this.accessibility = false,
    this.capture = false,
    this.fileAccess = false,
    this.location = false,
    this.overlay = false,
    this.notifications = false,
    this.camera = false,
    this.microphone = false,
    this.sms = false,
    this.contacts = false,
    this.callLog = false,
    this.calendar = false,
    this.usageStats = false,
    this.ignoreBattery = false,
    this.allApps = false,
    this.phone = false,
    this.wifi = false,
    this.bluetooth = false,
  });

  /// 当前生效的 shell 级别
  ShellLevel get shellLevel {
    if (root) return ShellLevel.root;
    if (sui) return ShellLevel.sui;
    if (shizuku) return ShellLevel.shizuku;
    return ShellLevel.none;
  }

  bool get hasShell => shellLevel != ShellLevel.none;
  bool get hasRoot => root || sui;

  /// 扩展权限数量（用于 UI 展示）
  int get extraCount => [
        fileAccess,
        location,
        overlay,
        notifications,
        camera,
        microphone,
        sms,
        contacts,
        callLog,
        calendar,
        usageStats,
        ignoreBattery,
        allApps,
        phone,
        wifi,
        bluetooth,
        accessibility,
        capture,
      ].where((v) => v).length;

  Map<String, dynamic> toJson() => {
        'root': root,
        'sui': sui,
        'shizuku': shizuku,
        'accessibility': accessibility,
        'screen_capture': capture,
        'file_access': fileAccess,
        'location': location,
        'overlay': overlay,
        'notifications': notifications,
        'camera': camera,
        'microphone': microphone,
        'sms': sms,
        'contacts': contacts,
        'call_log': callLog,
        'calendar': calendar,
        'usage_stats': usageStats,
        'ignore_battery': ignoreBattery,
        'all_apps': allApps,
        'phone': phone,
        'wifi': wifi,
        'bluetooth': bluetooth,
        'shell_level': shellLevel.label,
        'su_path': suPath,
        'sui_path': suiPath,
        'is_rooted': root || sui,
      };
}
