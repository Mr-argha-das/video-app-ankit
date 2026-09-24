import 'dart:async';
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

/// File for multipart uploads. Bytes rakhte hain taaki redirect pe request
/// dobara bheji ja sake (http.MultipartFile sirf ek baar send ho sakta hai).
class ApiFile {
  final String field;
  final List<int> bytes;
  final String filename;
  const ApiFile(this.field, this.bytes, this.filename);
}

typedef UnauthorizedCallback = void Function();

/// Single HTTP wrapper — JWT bearer auth, form/JSON/multipart, error parsing.
///
/// Redirects (e.g. server/proxy `http://` → `https://`) khud handle karta hai:
/// Dart POST redirects follow nahi karta aur GET redirect pe Authorization
/// header gira deta hai (→ register fail, `/auth/me` 403). Isliye redirects
/// manually follow hote hain — method, body aur token ke saath — aur naya
/// origin yaad rakha jaata hai taaki agli requests seedha wahan jaayein.
class ApiService {
  String? token;

  /// 401 aane pe call hota hai (session expired → login screen).
  UnauthorizedCallback? onUnauthorized;

  final http.Client _client = http.Client();

  static const _timeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(seconds: 120);

  String get baseUrl => AppConfig.origin;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    if (query == null) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Map<String, String> _headers({bool jsonBody = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (token != null) h['Authorization'] = 'Bearer $token';
    if (jsonBody) h['Content-Type'] = 'application/json';
    return h;
  }

  String? _extractError(dynamic data) {
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map && d.first['msg'] != null) {
        final first = d.first as Map;
        final loc = first['loc'] is List && (first['loc'] as List).isNotEmpty ? (first['loc'] as List).last : null;
        final msg = first['msg'].toString().replaceFirst('Value error, ', '');
        return loc != null && msg == 'Field required' ? '$loc: $msg' : msg;
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
      // Login pe galat password bhi 401 hai — "session expired" sirf tab jab token bheja tha
      if (res.request?.headers['Authorization'] != null) onUnauthorized?.call();
      throw ApiException(401, _extractError(data) ?? 'Session expired. Please login again.');
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _extractError(data) ?? 'Request failed (${res.statusCode})');
    }
    if (res.statusCode >= 300) {
      throw ApiException(
        res.statusCode,
        'Server ne redirect kiya (${res.statusCode}) — AppConfig.baseUrl check karo (https:// use karo).',
      );
    }
    if (data == null) {
      throw ApiException(
        res.statusCode,
        'Server se JSON response nahi aaya — AppConfig.baseUrl galat hai? ($baseUrl)',
      );
    }
    return data;
  }

  /// Sends a request built by [build] (fresh request per attempt) and follows
  /// redirects manually, keeping method, body and Authorization header.
  Future<dynamic> _send(
    http.BaseRequest Function(Uri uri) build,
    Uri uri, {
    Duration timeout = _timeout,
  }) async {
    var target = uri;
    for (var hop = 0; hop < 4; hop++) {
      final req = build(target)..followRedirects = false;
      http.Response res;
      try {
        final streamed = await _client.send(req).timeout(timeout);
        res = await http.Response.fromStream(streamed).timeout(timeout);
      } on TimeoutException {
        throw ApiException(0, 'Server response nahi de raha (timeout). Internet / server check karo.');
      } on ApiException {
        rethrow;
      } catch (e) {
        throw ApiException(0, 'Server se connect nahi ho paya ($baseUrl). Internet / baseUrl check karo.\n$e');
      }

      final isRedirect = const [301, 302, 303, 307, 308].contains(res.statusCode);
      final location = res.headers['location'];
      if (isRedirect && location != null && location.isNotEmpty) {
        final next = target.resolve(location);
        // Sirf origin badla (http→https / host) → yaad rakho, agli requests seedha wahan
        if (next.path == target.path) {
          AppConfig.runtimeOrigin = next.hasPort && next.port != (next.scheme == 'https' ? 443 : 80)
              ? '${next.scheme}://${next.host}:${next.port}'
              : '${next.scheme}://${next.host}';
        }
        target = next;
        continue;
      }
      return _parse(res);
    }
    throw ApiException(310, 'Bahut zyada redirects — AppConfig.baseUrl check karo.');
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) {
    return _send((u) => http.Request('GET', u)..headers.addAll(_headers()), _uri(path, query));
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) {
    final encoded = jsonEncode(body);
    return _send(
      (u) => http.Request('POST', u)
        ..headers.addAll(_headers(jsonBody: true))
        ..body = encoded,
      _uri(path),
    );
  }

  /// application/x-www-form-urlencoded — FastAPI ke Form(...) endpoints ke liye.
  Future<dynamic> postForm(String path, Map<String, String> fields) {
    return _send(
      (u) => http.Request('POST', u)
        ..headers.addAll(_headers())
        ..bodyFields = fields,
      _uri(path),
    );
  }

  Future<dynamic> putForm(String path, Map<String, String> fields) {
    return _send(
      (u) => http.Request('PUT', u)
        ..headers.addAll(_headers())
        ..bodyFields = fields,
      _uri(path),
    );
  }

  Future<dynamic> multipart(
    String method,
    String path, {
    Map<String, String>? fields,
    List<ApiFile>? files,
  }) {
    return _send(
      (u) {
        final req = http.MultipartRequest(method.toUpperCase(), u);
        req.headers.addAll(_headers());
        if (fields != null) req.fields.addAll(fields);
        for (final f in files ?? const <ApiFile>[]) {
          req.files.add(http.MultipartFile.fromBytes(f.field, f.bytes, filename: f.filename));
        }
        return req;
      },
      _uri(path),
      timeout: _uploadTimeout,
    );
  }
}
