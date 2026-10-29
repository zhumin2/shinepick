import 'package:dio/dio.dart';

import '../../core/error/app_error.dart';
import '../../shared/models/user.dart';
import '../../shared/storage/token_store.dart';
import 'api_config.dart';

/// 统一响应结构（与后端 {code,message,data,request_id} 对齐）。
class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  const ApiResponse({required this.code, required this.message, this.data});

  bool get ok => code == 0;

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(dynamic)? parser) {
    return ApiResponse(
      code: (json['code'] as num?)?.toInt() ?? 9000,
      message: (json['message'] as String?) ?? '',
      data: parser == null ? null : parser(json['data']),
    );
  }
}

/// Dio 封装：注入 Token、401 自动刷新重试。
class ApiClient {
  final TokenStore _tokenStore;
  late final Dio dio;

  ApiClient(this._tokenStore) {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  Future<void> _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
      DioException err, ErrorInterceptorHandler handler) async {
    // 401：尝试用 refresh token 换新 access 后重试一次
    if (err.response?.statusCode == 401) {
      final ok = await _tryRefresh();
      if (ok) {
        final token = await _tokenStore.readAccessToken();
        final opts = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer $token';
        try {
          final resp = await dio.fetch(opts);
          handler.resolve(resp);
          return;
        } on DioException catch (e) {
          handler.next(e);
          return;
        }
      }
    }
    handler.next(err);
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _tokenStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final resp = await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final body = ApiResponse.fromJson(resp.data!, null);
      if (!body.ok) return false;
      final data = resp.data!['data'] as Map<String, dynamic>;
      await _tokenStore.saveTokens(
        data['access_token'] as String,
        data['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// GET 请求并解包统一响应。
  Future<T> get<T>(String path, {T Function(dynamic)? parser}) async {
    final resp = await dio.get<Map<String, dynamic>>(path);
    return _unwrap<T>(resp, parser);
  }

  /// POST 请求并解包统一响应。
  Future<T> post<T>(
    String path, {
    Object? data,
    T Function(dynamic)? parser,
  }) async {
    final resp = await dio.post<Map<String, dynamic>>(path, data: data);
    return _unwrap<T>(resp, parser);
  }

  /// PATCH 请求并解包统一响应。
  Future<T> patch<T>(
    String path, {
    Object? data,
    T Function(dynamic)? parser,
  }) async {
    final resp = await dio.patch<Map<String, dynamic>>(path, data: data);
    return _unwrap<T>(resp, parser);
  }

  /// multipart 文件上传（字段名默认 file）。
  Future<T> upload<T>(
    String path,
    String filePath, {
    String field = 'file',
    T Function(dynamic)? parser,
  }) async {
    final form = FormData.fromMap({
      field: await MultipartFile.fromFile(filePath),
    });
    final resp = await dio.post<Map<String, dynamic>>(path, data: form);
    return _unwrap<T>(resp, parser);
  }

  T _unwrap<T>(Response<Map<String, dynamic>> resp, T Function(dynamic)? parser) {
    final body = ApiResponse.fromJson(resp.data!, parser);
    if (!body.ok) {
      throw AppError(body.code, body.message);
    }
    return body.data as T;
  }
}

/// 公开给页面使用的已登录用户信息。
class SessionUser {
  final User? user;
  const SessionUser({this.user});
}
