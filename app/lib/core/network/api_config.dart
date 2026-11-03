/// API 环境配置。
/// dev 指向本机后端；发布版替换为阿里云地址（由 --dart-define 注入）。
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  /// 本包版本号（--dart-define=APP_VERSION=x.y.z，构建脚本注入；用于检查更新比对）。
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// 语义化版本比较：>0 表示 [a] 更新，=0 相同，<0 表示 [a] 更旧。
  /// 非数字段按 0 处理；段数不齐时短者补 0。
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
