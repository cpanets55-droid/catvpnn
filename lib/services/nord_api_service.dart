import 'dart:convert';
import 'dart:io';
import '../models/nord_models.dart';
import 'nord_seed_data.dart';

class _HttpResponseData {
  final int statusCode;
  final String body;

  const _HttpResponseData(this.statusCode, this.body);
}

class NordApiService {
  static const String defaultAccessToken = String.fromEnvironment('NORD_TOKEN');

  static const String _baseUrl = 'https://api.nordvpn.com/v1';

  static const List<String> pinnedCountryCodes = [
    'SG',
    'JP',
    'HK',
    'VN',
    'TW',
    'KR',
    'US',
    'GB',
    'DE',
    'NL',
    'AU',
    'CA',
    'FR',
  ];

  static List<NordCountry> sortCountries(List<NordCountry> input) {
    final countries = List<NordCountry>.from(input);
    countries.sort((a, b) {
      final idxA = pinnedCountryCodes.indexOf(a.code.toUpperCase());
      final idxB = pinnedCountryCodes.indexOf(b.code.toUpperCase());
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return a.name.compareTo(b.name);
    });
    return countries;
  }

  /// Connects strictly over IPv4 with proper TLS SNI so dual-stack Android Wi-Fi
  /// routers without upstream IPv6 never stall on AAAA records.
  static Future<_HttpResponseData> _ipv4Get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 2)
      ..connectionFactory =
          (Uri targetUri, String? proxyHost, int? proxyPort) async {
        final host = proxyHost ?? targetUri.host;
        final port = proxyPort ??
            (targetUri.hasPort
                ? targetUri.port
                : (targetUri.scheme == 'https' ? 443 : 80));

        InternetAddress? ipv4;
        try {
          final addrs = await InternetAddress.lookup(
            host,
            type: InternetAddressType.IPv4,
          ).timeout(const Duration(seconds: 4));
          if (addrs.isNotEmpty) ipv4 = addrs.first;
        } catch (_) {}

        final connectTarget = ipv4 ?? host;
        final rawFuture = Socket.connect(connectTarget, port, timeout: timeout);

        if (proxyHost == null && targetUri.scheme == 'https') {
          final tlsFuture = rawFuture.then(
            (rawSock) => SecureSocket.secure(
              rawSock,
              host: targetUri.host,
            ).timeout(timeout),
          );
          return ConnectionTask.fromSocket(tlsFuture, () {});
        }
        return ConnectionTask.fromSocket(rawFuture, () {});
      };

    try {
      final req = await client.getUrl(uri).timeout(timeout);
      req.persistentConnection = false;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/134.0 Mobile Safari/537.36',
      );
      headers?.forEach((k, v) => req.headers.set(k, v));

      final resp = await req.close().timeout(timeout);
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      return _HttpResponseData(resp.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, String> _authHeaders(String token) {
    final clean = token.trim();
    final encoded = base64Encode(utf8.encode('token:$clean'));
    return {'Authorization': 'Basic $encoded'};
  }

  static Future<NordAccountCredentials> fetchAccountCredentials(
    String token,
  ) async {
    final clean = token.trim();
    try {
      final headers = _authHeaders(clean);
      final credsResp = await _ipv4Get(
        '$_baseUrl/users/services/credentials',
        headers: headers,
      );

      if (credsResp.statusCode == 401 || credsResp.statusCode == 403) {
        throw Exception('NordVPN API Token không hợp lệ hoặc đã bị thu hồi.');
      }
      if (credsResp.statusCode != 200) {
        throw Exception('Lỗi lấy khóa NordLynx (HTTP ${credsResp.statusCode}).');
      }

      final credsJson = jsonDecode(credsResp.body) as Map<String, dynamic>;
      final privateKey = (credsJson['nordlynx_private_key'] as String?) ?? '';
      final username = (credsJson['username'] as String?) ?? '';
      final password = (credsJson['password'] as String?) ?? '';

      if (privateKey.isEmpty) {
        throw Exception('Tài khoản này chưa có khóa NordLynx.');
      }

      String expiresAt = NordSeedData.seedCredentials.expiresAt;
      try {
        final servicesResp = await _ipv4Get(
          '$_baseUrl/users/services',
          headers: headers,
          timeout: const Duration(seconds: 6),
        );
        if (servicesResp.statusCode == 200) {
          final list = jsonDecode(servicesResp.body) as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final svc = item['service'];
              if (svc is Map<String, dynamic> && svc['identifier'] == 'vpn') {
                expiresAt = (item['expires_at'] as String?) ?? expiresAt;
                break;
              }
            }
          }
        }
      } catch (_) {}

      return NordAccountCredentials(
        privateKey: privateKey,
        serviceUsername: username,
        servicePassword: password,
        expiresAt: expiresAt,
      );
    } catch (e) {
      if (clean == defaultAccessToken) {
        return NordSeedData.seedCredentials;
      }
      rethrow;
    }
  }

  static Future<List<NordCountry>> fetchCountries() async {
    try {
      final resp = await _ipv4Get('$_baseUrl/servers/countries');
      if (resp.statusCode == 200) {
        final rawList = jsonDecode(resp.body) as List<dynamic>;
        final countries = rawList
            .whereType<Map<String, dynamic>>()
            .map(NordCountry.fromJson)
            .where((c) => c.id > 0)
            .toList();
        if (countries.isNotEmpty) {
          return sortCountries(countries);
        }
      }
    } catch (_) {}
    return sortCountries(NordSeedData.getCountries());
  }

  static Future<List<NordServer>> fetchRecommendedServers({
    int? countryId,
    int limit = 20,
  }) async {
    final countryFilter =
        countryId != null ? '&filters[country_id]=$countryId' : '';
    final recUrl =
        '$_baseUrl/servers/recommendations?filters[servers_technologies][identifier]=wireguard_udp$countryFilter&limit=$limit';

    List<NordServer> parsed = await _fetchServerListUrl(recUrl);

    if (parsed.isEmpty && countryId != null) {
      final fallbackUrl =
          '$_baseUrl/servers?filters[servers_technologies][identifier]=wireguard_udp&filters[country_id]=$countryId&limit=$limit';
      parsed = await _fetchServerListUrl(fallbackUrl);
    }

    if (parsed.isEmpty) {
      parsed = NordSeedData.getServers(countryId: countryId);
    }

    parsed.sort((a, b) => a.load.compareTo(b.load));
    return parsed;
  }

  static Future<List<NordServer>> _fetchServerListUrl(String url) async {
    try {
      final resp = await _ipv4Get(url);
      if (resp.statusCode != 200) return const [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List<dynamic>) return const [];

      final servers = <NordServer>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final s = NordServer.fromApiJson(item);
          if (s != null) servers.add(s);
        }
      }
      return servers;
    } catch (_) {
      return const [];
    }
  }

  static Future<ExitIpInfo> fetchCurrentExitIp() async {
    try {
      final resp = await _ipv4Get(
        'https://ipwho.is/',
        timeout: const Duration(seconds: 6),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['success'] != false &&
            (data['ip'] as String?)?.isNotEmpty == true) {
          final conn = data['connection'];
          final isp = conn is Map<String, dynamic>
              ? ((conn['isp'] as String?) ?? (conn['org'] as String?) ?? '')
              : '';
          return ExitIpInfo(
            ip: data['ip'] as String,
            country: (data['country'] as String?) ?? '',
            countryCode: (data['country_code'] as String?) ?? '',
            city: (data['city'] as String?) ?? '',
            isp: isp,
          );
        }
      }
    } catch (_) {}

    try {
      final resp = await _ipv4Get(
        'https://api.ipify.org?format=json',
        timeout: const Duration(seconds: 5),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return ExitIpInfo(ip: (data['ip'] as String?) ?? 'Unknown');
    } catch (_) {
      return const ExitIpInfo(ip: 'Chưa xác định');
    }
  }

  static String buildWireGuardConfig({
    required String privateKey,
    required NordServer server,
    bool useCloudflareDns = false,
  }) {
    final dns = useCloudflareDns
        ? '1.1.1.1, 1.0.0.1'
        : '103.86.96.100, 103.86.99.100';

    return '''[Interface]
PrivateKey = ${privateKey.trim()}
Address = 10.5.0.2/16
DNS = $dns
MTU = 1420

[Peer]
PublicKey = ${server.publicKey.trim()}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${server.stationIp.trim()}:51820
PersistentKeepalive = 25
''';
  }
}
