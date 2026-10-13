import 'dart:convert';

import 'package:http/http.dart' as http;

import 'coros_auth.dart';

/// Minimal client for the COROS MCP: stateless JSON-RPC over HTTP with a Bearer token.
/// Tool results arrive as one text item holding a JSON-encoded string of a prose report.
class CorosMcp {
  CorosMcp(this.auth);

  final CorosAuth auth;
  int _id = 0;

  Future<Map<String, dynamic>> _rpc(String method, Map<String, dynamic> params) async {
    final tokens = await auth.validTokens();
    final res = await http.post(
      Uri.parse(mcpUrl),
      headers: {
        'authorization': 'Bearer ${tokens.accessToken}',
        'accept': 'application/json, text/event-stream',
        'content-type': 'application/json',
      },
      body: jsonEncode({'jsonrpc': '2.0', 'id': ++_id, 'method': method, 'params': params}),
    // A dropped connection could otherwise hang forever, holding the check lease and leaving
    // Check now spinning (L54). The slowest real call seen was a few seconds.
    ).timeout(const Duration(seconds: 30));
    final body = _decodeBody(res);
    if (res.statusCode != 200 || body['error'] != null) {
      throw Exception('MCP $method failed ${res.statusCode}: ${jsonEncode(body['error'] ?? body)}');
    }
    return body['result'] as Map<String, dynamic>;
  }

  Map<String, dynamic> _decodeBody(http.Response res) {
    final raw = utf8.decode(res.bodyBytes);
    if ((res.headers['content-type'] ?? '').contains('text/event-stream')) {
      final data = raw.split(RegExp(r'\r?\n')).where((l) => l.startsWith('data:')).map((l) => l.substring(5).trim());
      return jsonDecode(data.last) as Map<String, dynamic>;
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<String> serverInfo() async {
    final r = await _rpc('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {},
      'clientInfo': {'name': 'Training Companion', 'version': '0.0.1'},
    });
    return '${r['serverInfo']?['name']} ${r['serverInfo']?['version'] ?? ''}'.trim();
  }

  /// Calls a tool and returns its report text, decoded from the JSON-encoded string.
  Future<String> callTool(String name, Map<String, dynamic> args) async {
    final r = await _rpc('tools/call', {'name': name, 'arguments': args});
    final content = (r['content'] as List? ?? []).cast<Map<String, dynamic>>();
    var text = content.where((c) => c['type'] == 'text').map((c) => c['text'] as String).join('\n');
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) text = decoded;
    } on FormatException {
      // Already plain text.
    }
    if (r['isError'] == true) throw Exception('$name returned an error: $text');
    return text;
  }
}
