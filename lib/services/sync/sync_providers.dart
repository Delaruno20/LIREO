import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors.dart';

/// Stockage distant d'un unique fichier d'état (`lireo-sync.json`).
abstract class SyncProvider {
  String get id;
  String get label;

  /// Les identifiants développeur sont fournis à la compilation
  /// (`--dart-define`). Sans eux, le fournisseur est affiché comme non configuré.
  bool get configured;
  String get setupHint;

  String? get account;
  Future<bool> restore();
  Future<void> connect();
  Future<void> disconnect();
  Future<String?> download();
  Future<void> upload(String content);
}

const syncFileName = 'lireo-sync.json';

// ------------------------------------------------------------------ Dropbox

/// Dropbox, OAuth 2 PKCE (aucun secret embarqué), dossier d'application.
class DropboxProvider extends SyncProvider {
  DropboxProvider(this._prefs);

  final SharedPreferences _prefs;
  static const _appKey = String.fromEnvironment('DROPBOX_APP_KEY');
  static const _redirect = 'lireo://dropbox-auth';
  String? _accessToken;
  DateTime? _expiresAt;

  @override
  String get id => 'dropbox';
  @override
  String get label => 'Dropbox';
  @override
  bool get configured => _appKey.isNotEmpty;
  @override
  String get setupHint =>
      'Créez une application Dropbox (accès « App folder »), ajoutez l\'URI de redirection $_redirect, '
      'puis compilez avec --dart-define=DROPBOX_APP_KEY=votre_clé.';
  @override
  String? get account => _prefs.getString('sync.dropbox.account');

  String? get _refreshToken => _prefs.getString('sync.dropbox.refresh');

  @override
  Future<bool> restore() async => configured && _refreshToken != null;

  @override
  Future<void> connect() async {
    if (!configured) throw UserFacingError(setupHint);
    final verifier = _randomString(64);
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final url = Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': _appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'redirect_uri': _redirect,
    });
    final result = await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: 'lireo');
    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) throw const UserFacingError('Connexion Dropbox annulée');
    final token = await _tokenRequest({
      'code': code,
      'grant_type': 'authorization_code',
      'code_verifier': verifier,
      'client_id': _appKey,
      'redirect_uri': _redirect,
    });
    await _prefs.setString('sync.dropbox.refresh', token['refresh_token'] as String);
    final info = await _api('https://api.dropboxapi.com/2/users/get_current_account', body: 'null');
    final email = (jsonDecode(info.body) as Map)['email'] as String?;
    if (email != null) await _prefs.setString('sync.dropbox.account', email);
  }

  Future<Map<String, dynamic>> _tokenRequest(Map<String, String> body) async {
    final res = await http.post(Uri.https('api.dropboxapi.com', '/oauth2/token'), body: body);
    if (res.statusCode != 200) throw UserFacingError('Dropbox a refusé l\'authentification (${res.statusCode})');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    _accessToken = json['access_token'] as String;
    _expiresAt = DateTime.now().add(Duration(seconds: (json['expires_in'] as num? ?? 3600).toInt() - 60));
    return json;
  }

  Future<String> _token() async {
    if (_accessToken != null && _expiresAt != null && DateTime.now().isBefore(_expiresAt!)) return _accessToken!;
    final refresh = _refreshToken;
    if (refresh == null) throw const UserFacingError('Dropbox n\'est pas connecté');
    await _tokenRequest({'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': _appKey});
    return _accessToken!;
  }

  Future<http.Response> _api(String url, {Object? body, Map<String, String> headers = const {}}) async {
    final res = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer ${await _token()}',
        if (body is String) 'Content-Type': 'application/json',
        ...headers,
      },
      body: body,
    );
    return res;
  }

  @override
  Future<String?> download() async {
    final res = await _api('https://content.dropboxapi.com/2/files/download',
        headers: {'Dropbox-API-Arg': jsonEncode({'path': '/$syncFileName'})});
    if (res.statusCode == 409) return null; // fichier encore absent
    if (res.statusCode != 200) throw UserFacingError('Téléchargement Dropbox impossible (${res.statusCode})');
    return utf8.decode(res.bodyBytes);
  }

  @override
  Future<void> upload(String content) async {
    final res = await _api(
      'https://content.dropboxapi.com/2/files/upload',
      body: utf8.encode(content),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': jsonEncode({'path': '/$syncFileName', 'mode': 'overwrite', 'mute': true}),
      },
    );
    if (res.statusCode != 200) throw UserFacingError('Envoi Dropbox impossible (${res.statusCode})');
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_refreshToken != null) await _api('https://api.dropboxapi.com/2/auth/token/revoke');
    } catch (_) {}
    _accessToken = null;
    await _prefs.remove('sync.dropbox.refresh');
    await _prefs.remove('sync.dropbox.account');
  }

  static String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

// ------------------------------------------------------------- Google Drive

/// Google Drive, dossier caché de l'application (`appDataFolder`) :
/// LIREO ne voit pas les autres fichiers de l'utilisateur.
class GoogleDriveProvider extends SyncProvider {
  GoogleDriveProvider(this._prefs);

  final SharedPreferences _prefs;
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  GoogleSignInAccount? _user;
  bool _initialized = false;

  @override
  String get id => 'gdrive';
  @override
  String get label => 'Google Drive';
  @override
  bool get configured => _serverClientId.isNotEmpty;
  @override
  String get setupHint =>
      'Dans Google Cloud, activez l\'API Drive, créez un client OAuth « Android » (paquet app.lireo.lireo + '
      'empreinte SHA-1 de signature) et un client « Web », puis compilez avec '
      '--dart-define=GOOGLE_SERVER_CLIENT_ID=identifiant_du_client_web.';
  @override
  String? get account => _prefs.getString('sync.gdrive.account');

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    _initialized = true;
  }

  @override
  Future<bool> restore() async {
    if (!configured || account == null) return false;
    try {
      await _init();
      _user = await GoogleSignIn.instance.attemptLightweightAuthentication();
      return _user != null;
    } catch (e, st) {
      AppError.report(e, st, context: 'gdrive.restore');
      return false;
    }
  }

  @override
  Future<void> connect() async {
    if (!configured) throw UserFacingError(setupHint);
    await _init();
    _user = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    await _user!.authorizationClient.authorizeScopes(_scopes);
    await _prefs.setString('sync.gdrive.account', _user!.email);
  }

  Future<Map<String, String>> _headers() async {
    final user = _user ?? (await restore() ? _user : null);
    if (user == null) throw const UserFacingError('Google Drive n\'est pas connecté');
    final auth = await user.authorizationClient.authorizationForScopes(_scopes) ??
        await user.authorizationClient.authorizeScopes(_scopes);
    return {'Authorization': 'Bearer ${auth.accessToken}'};
  }

  Future<String?> _fileId(Map<String, String> headers) async {
    final res = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = '$syncFileName'",
        'fields': 'files(id)',
      }),
      headers: headers,
    );
    if (res.statusCode != 200) throw UserFacingError('Google Drive indisponible (${res.statusCode})');
    final files = (jsonDecode(res.body) as Map)['files'] as List;
    return files.isEmpty ? null : (files.first as Map)['id'] as String;
  }

  @override
  Future<String?> download() async {
    final headers = await _headers();
    final id = await _fileId(headers);
    if (id == null) return null;
    final res = await http.get(Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}), headers: headers);
    if (res.statusCode != 200) throw UserFacingError('Téléchargement Drive impossible (${res.statusCode})');
    return utf8.decode(res.bodyBytes);
  }

  @override
  Future<void> upload(String content) async {
    final headers = await _headers();
    final id = await _fileId(headers);
    http.Response res;
    if (id != null) {
      res = await http.patch(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files/$id', {'uploadType': 'media'}),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: utf8.encode(content),
      );
    } else {
      const boundary = 'lireo-sync-boundary';
      final body = '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
          '${jsonEncode({'name': syncFileName, 'parents': ['appDataFolder']})}\r\n'
          '--$boundary\r\nContent-Type: application/json\r\n\r\n$content\r\n--$boundary--';
      res = await http.post(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files', {'uploadType': 'multipart'}),
        headers: {...headers, 'Content-Type': 'multipart/related; boundary=$boundary'},
        body: utf8.encode(body),
      );
    }
    if (res.statusCode != 200) throw UserFacingError('Envoi Drive impossible (${res.statusCode})');
  }

  @override
  Future<void> disconnect() async {
    try {
      await _init();
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
    _user = null;
    await _prefs.remove('sync.gdrive.account');
  }
}
