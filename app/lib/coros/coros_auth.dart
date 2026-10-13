import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const _metadataUrl = 'https://mcp.coros.com/.well-known/oauth-authorization-server';
const mcpUrl = 'https://mcp.coros.com/mcp';
const _scope = 'openid offline_access mcp.tools';

/// Where the sign-in page sends the user back to the app after the code has been caught.
/// Matches the intent filter on MainActivity.
const _returnToAppUrl =
    'intent://signed-in#Intent;scheme=trainingcompanion;package=com.trainingcompanion.app;end';

typedef Log = void Function(String message);

class CorosTokens {
  CorosTokens({required this.clientId, required this.accessToken, required this.refreshToken, required this.expiresAt});

  final String clientId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, Object> toJson() => {
        'client_id': clientId,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
      };

  static CorosTokens fromJson(Map<String, dynamic> j) => CorosTokens(
        clientId: j['client_id'] as String,
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );
}

/// Coros sign-in with no server: a self-registered public client, PKCE, and a loopback redirect
/// caught by a listener inside the app. Tokens live only in Android Keystore-backed storage.
class CorosAuth {
  CorosAuth(this.log);

  final Log log;
  final _storage = const FlutterSecureStorage();
  static const _tokensKey = 'coros_tokens';
  static const _installIdKey = 'install_id';

  Map<String, dynamic>? _metadata;
  Future<void>? _refreshing;

  /// Every request to Coros's sign-in server. Without it a dropped connection hangs a token
  /// refresh, and every Coros call waits on that refresh forever (L54).
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _meta() async {
    _metadata ??= jsonDecode((await http.get(Uri.parse(_metadataUrl)).timeout(_timeout)).body) as Map<String, dynamic>;
    return _metadata!;
  }

  Future<CorosTokens?> loadTokens() async {
    final raw = await _storage.read(key: _tokensKey);
    return raw == null ? null : CorosTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// One write of the whole token set, so a crash can never leave a new access token next to a
  /// refresh token Coros has already rotated away.
  Future<void> _saveTokens(CorosTokens t) => _storage.write(key: _tokensKey, value: jsonEncode(t.toJson()));

  Future<void> signOut() => _storage.delete(key: _tokensKey);

  Future<String> _installId() async {
    var id = await _storage.read(key: _installIdKey);
    if (id == null) {
      id = _randomUrlSafe(6);
      await _storage.write(key: _installIdKey, value: id);
    }
    return id;
  }

  /// Coros returns the same client for a repeated client_name, so each install uses its own name.
  Future<String> _register(String redirectUri) async {
    final meta = await _meta();
    final res = await http.post(
      Uri.parse(meta['registration_endpoint'] as String),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'client_name': 'Training Companion · ${await _installId()}',
        'redirect_uris': [redirectUri],
        'grant_types': ['authorization_code', 'refresh_token'],
        'response_types': ['code'],
        'scope': _scope,
        'token_endpoint_auth_method': 'none',
      }),
    ).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['client_id'] is! String) throw Exception('Registration failed ${res.statusCode}: ${res.body}');
    return body['client_id'] as String;
  }

  Future<CorosTokens> signIn() async {
    final meta = await _meta();
    log('Issuer ${meta['issuer']}');

    // Any free port works: Coros accepts loopback redirects on unregistered ports (M0, L14).
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';
    log('Listening on port ${server.port}');

    try {
      final clientId = await _register(redirectUri);
      log('Registered client ${clientId.substring(0, 6)}…');

      final verifier = _randomUrlSafe(32);
      final state = _randomUrlSafe(24);
      final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
      final authorizeUrl = Uri.parse(meta['authorization_endpoint'] as String).replace(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': _scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'resource': mcpUrl,
        'state': state,
      });

      final callback = Completer<Map<String, String>>();
      server.listen((req) async {
        if (req.uri.path != '/callback') {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final params = req.uri.queryParameters;
        log('Callback received while the app was ${_lifecycleNote()}');
        req.response.headers.contentType = ContentType.html;
        req.response.write(_callbackPage(ok: params.containsKey('code')));
        await req.response.close();
        if (!callback.isCompleted) callback.complete(params);
      });

      log('Opening Coros sign-in in a Custom Tab');
      if (!await launchUrl(authorizeUrl, mode: LaunchMode.inAppBrowserView)) {
        throw Exception('Could not open the sign-in page');
      }

      final params = await callback.future.timeout(const Duration(minutes: 5));
      if (params['error'] != null) throw Exception('Sign-in error: ${params['error']} ${params['error_description'] ?? ''}');
      if (params['state'] != state) throw Exception('State mismatch');

      // Android 15+ blocks network for apps in the background (blocked=APP_BACKGROUND), and the
      // callback arrives while the Custom Tab is in front. Hold the code until the app is back.
      if (appState != 'in front') {
        log('Code caught in the background; waiting for the app to come back to the front');
        await _waitUntilInFront().timeout(const Duration(minutes: 5));
      }

      final tokens = await _tokenRequest(meta, clientId, {
        'grant_type': 'authorization_code',
        'code': params['code']!,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
      });
      await _saveTokens(tokens);
      log('Signed in; tokens saved to Keystore storage, valid until ${_shortDate(tokens.expiresAt)}');
      return tokens;
    } finally {
      await server.close(force: true);
      unawaited(closeInAppWebView().catchError((_) {}));
    }
  }

  /// Returns a usable access token, refreshing first if it expires within a day.
  /// Only one refresh runs at a time, because Coros rotates the refresh token on every refresh.
  Future<CorosTokens> validTokens({bool forceRefresh = false}) async {
    final current = await loadTokens();
    if (current == null) throw Exception('Not signed in');
    if (!forceRefresh && current.expiresAt.isAfter(DateTime.now().add(const Duration(days: 1)))) return current;
    if (_refreshing != null) {
      await _refreshing;
      return (await loadTokens())!;
    }
    final done = Completer<void>();
    _refreshing = done.future;
    try {
      final CorosTokens refreshed;
      try {
        refreshed = await _tokenRequest(await _meta(), current.clientId, {
          'grant_type': 'refresh_token',
          'refresh_token': current.refreshToken,
        });
      } catch (_) {
        // The app and the background worker run in separate isolates. If the other one
        // refreshed first, Coros has rotated our refresh token away: use what it saved.
        final latest = await loadTokens();
        if (latest != null && latest.refreshToken != current.refreshToken) return latest;
        rethrow;
      }
      await _saveTokens(refreshed);
      log('Tokens refreshed (refresh token rotated: ${refreshed.refreshToken != current.refreshToken})');
      return refreshed;
    } finally {
      done.complete();
      _refreshing = null;
    }
  }

  Future<CorosTokens> _tokenRequest(Map<String, dynamic> meta, String clientId, Map<String, String> form) async {
    final res = await http.post(Uri.parse(meta['token_endpoint'] as String), body: {'client_id': clientId, ...form}).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Token ${form['grant_type']} failed ${res.statusCode}: ${res.body}');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return CorosTokens(
      clientId: clientId,
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: (body['expires_in'] as num).toInt())),
    );
  }

  /// Set by the UI from the app lifecycle, so the log shows whether the listener worked in the background.
  static String _appState = 'unknown';
  static String get appState => _appState;
  static set appState(String value) {
    _appState = value;
    if (value == 'in front') {
      for (final waiter in _frontWaiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
      _frontWaiters.clear();
    }
  }

  static final _frontWaiters = <Completer<void>>[];
  static Future<void> _waitUntilInFront() {
    if (_appState == 'in front') return Future.value();
    final waiter = Completer<void>();
    _frontWaiters.add(waiter);
    return waiter.future;
  }

  String _lifecycleNote() => appState;

  static String _callbackPage({required bool ok}) => '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{background:#000;color:#fff;font-family:sans-serif;padding:32px}
a{display:inline-block;margin-top:24px;background:#A1F882;color:#000;padding:14px 22px;border-radius:999px;text-decoration:none;font-weight:600}</style>
</head><body><h2>${ok ? 'Signed in to Coros' : 'Sign-in failed'}</h2>
<p style="color:#A9AAA3">Returning to Training Companion…</p>
<a href="$_returnToAppUrl">Return to Training Companion</a>
<script>setTimeout(function(){ location.href = "$_returnToAppUrl"; }, 300);</script></body></html>''';
}

String _randomUrlSafe(int bytes) {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
}

String _shortDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
