/// 统一业务错误。code 与后端错误码一致。
class AppError implements Exception {
  final int code;
  final String message;

  const AppError(this.code, this.message);

  factory AppError.badRequest([String msg = '参数错误']) =>
      AppError(1001, msg);
  factory AppError.unauthorized([String msg = '未登录或登录已过期']) =>
      AppError(2001, msg);
  factory AppError.smsInvalid([String msg = '验证码错误或已过期']) =>
      AppError(3001, msg);
  factory AppError.tooFrequent([String msg = '操作过于频繁，请稍后再试']) =>
      AppError(4001, msg);
  factory AppError.notFound([String msg = '目标不存在或已删除']) =>
      AppError(5001, msg);
  factory AppError.forbidden([String msg = '没有权限']) => AppError(5002, msg);
  factory AppError.auditReject([String msg = '内容未通过审核']) =>
      AppError(4101, msg);
  factory AppError.internal([String msg = '服务开小差了，请稍后重试']) =>
      AppError(9000, msg);

  @override
  String toString() => 'AppError($code): $message';
}
