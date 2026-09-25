import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import 'auth_token_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin JSON HTTP client for the `server/` API — attaches the stored JWT
/// (if any) to every request and surfaces the server's `{error}` body as a
/// readable [ApiException] instead of a raw HTTP status.
class ApiClient {
  ApiClient({required this._tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final AuthTokenStore _tokenStore;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${Env.apiBaseUrl}$path').replace(queryParameters: query?.isEmpty ?? true ? null : query);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _tokenStore.read();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final message = (body is Map && body['error'] is String) ? body['error'] as String : '요청에 실패했습니다.';
    throw ApiException(message, statusCode: response.statusCode);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final response = await _client.get(_uri(path, query), headers: await _headers());
    return _decode(response);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final response = await _client.post(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body));
    return _decode(response);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final response = await _client.put(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body));
    return _decode(response);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final response = await _client.patch(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body));
    return _decode(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await _client.delete(_uri(path), headers: await _headers());
    return _decode(response);
  }
}
