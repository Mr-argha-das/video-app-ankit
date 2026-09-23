import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// API error with readable message (FastAPI ka "detail" field extract karta hai).
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

typedef UnauthorizedCallback = void Function();

/// Single HTTP wrapper — JWT bearer auth, form/JSON/multipart, error parsing.
class ApiService {
  String? token;

  /// 401 aane pe call hota hai (session expired → login screen).
  UnauthorizedCallback? onUnauthorized;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    if (query == null) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Map<String, String> _headers({bool jsonBody = false}) {
    final h = <String, String>{};
    if (token != null) h['Authorization'] = 'Bearer $token';
    if (jsonBody) h['Content-Type'] = 'application/json';
    return h;
  }

  String? _extractError(dynamic data) {
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map && d.first['msg'] != null) {
        return d.first['msg'].toString().replaceFirst('Value error, ', '');
      }
    }
    return null;
  }

  dynamic _parse(http.Response res) {
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException(401, _extractError(data) ?? 'Session expired. Please login again.');
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _extractError(data) ?? 'Request failed (${res.statusCode})');
    }
    return data;
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final res = await http.get(_uri(path, query), headers: _headers());
    return _parse(res);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final res = await http.post(_uri(path), headers: _headers(jsonBody: true), body: jsonEncode(body));
    return _parse(res);
  }

  /// application/x-www-form-urlencoded — FastAPI ke Form(...) endpoints ke liye.
  Future<dynamic> postForm(String path, Map<String, String> fields) async {
    final res = await http.post(_uri(path), headers: _headers(), body: fields);
    return _parse(res);
  }

  Future<dynamic> putForm(String path, Map<String, String> fields) async {
    final res = await http.put(_uri(path), headers: _headers(), body: fields);
    return _parse(res);
  }

  Future<dynamic> multipart(
    String method,
    String path, {
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
  }) async {
    final req = http.MultipartRequest(method.toUpperCase(), _uri(path));
    req.headers.addAll(_headers());
    if (fields != null) req.fields.addAll(fields);
    if (files != null) req.files.addAll(files);
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }
}
