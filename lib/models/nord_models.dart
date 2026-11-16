String countryCodeToFlag(String code) {
  final upper = code.trim().toUpperCase();
  if (upper.length != 2) return '🌐';
  final first = upper.codeUnitAt(0);
  final second = upper.codeUnitAt(1);
  if (first < 65 || first > 90 || second < 65 || second > 90) return '🌐';
  return String.fromCharCode(0x1F1E6 + (first - 65)) +
      String.fromCharCode(0x1F1E6 + (second - 65));
}

class NordCountry {
  final int id;
  final String name;
  final String code;

  const NordCountry({
    required this.id,
    required this.name,
    required this.code,
  });

  String get flag => countryCodeToFlag(code);

  factory NordCountry.fromJson(Map<String, dynamic> json) {
    return NordCountry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? 'Unknown',
      code: (json['code'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
      };
}

class NordServer {
  final int id;
  final String name;
  final String hostname;
  final String stationIp;
  final int load;
  final String countryName;
  final String countryCode;
  final int countryId;
  final String cityName;
  final String publicKey;
  final bool hasSocks5;
  final bool hasSslProxy;

  const NordServer({
    required this.id,
    required this.name,
    required this.hostname,
    required this.stationIp,
    required this.load,
    required this.countryName,
    required this.countryCode,
    required this.countryId,
    required this.cityName,
    required this.publicKey,
    this.hasSocks5 = false,
    this.hasSslProxy = false,
  });

  String get flag => countryCodeToFlag(countryCode);

  String get locationLabel =>
      cityName.isNotEmpty ? '$countryName • $cityName' : countryName;

  static NordServer? fromApiJson(Map<String, dynamic> json) {
    final techs = (json['technologies'] as List<dynamic>?) ?? const [];
    String? wgPubKey;
    bool socks = false;
    bool sslProxy = false;

    for (final rawTech in techs) {
      if (rawTech is! Map<String, dynamic>) continue;
      final identifier = rawTech['identifier'] as String? ?? '';
      if (identifier == 'socks') socks = true;
      if (identifier == 'proxy_ssl') sslProxy = true;
      if (identifier == 'wireguard_udp') {
        final metaList = (rawTech['metadata'] as List<dynamic>?) ?? const [];
        for (final m in metaList) {
          if (m is Map<String, dynamic> && m['name'] == 'public_key') {
            wgPubKey = m['value'] as String?;
          }
        }
      }
    }

    final station = (json['station'] as String?) ?? '';
    if (wgPubKey == null || wgPubKey.isEmpty || station.isEmpty) {
      return null;
    }

    String cName = 'Global';
    String cCode = '';
    int cId = 0;
    String city = '';

    final locations = (json['locations'] as List<dynamic>?) ?? const [];
    if (locations.isNotEmpty && locations.first is Map<String, dynamic>) {
      final loc = locations.first as Map<String, dynamic>;
      final countryObj = loc['country'];
      if (countryObj is Map<String, dynamic>) {
        cId = (countryObj['id'] as num?)?.toInt() ?? 0;
        cName = (countryObj['name'] as String?) ?? 'Global';
        cCode = (countryObj['code'] as String?) ?? '';
        final cityObj = countryObj['city'];
        if (cityObj is Map<String, dynamic>) {
          city = (cityObj['name'] as String?) ?? '';
        }
      }
    }

    return NordServer(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? (json['hostname'] as String? ?? ''),
      hostname: (json['hostname'] as String?) ?? '',
      stationIp: station,
      load: (json['load'] as num?)?.toInt() ?? 0,
      countryName: cName,
      countryCode: cCode,
      countryId: cId,
      cityName: city,
      publicKey: wgPubKey,
      hasSocks5: socks,
      hasSslProxy: sslProxy,
    );
  }
}

class NordAccountCredentials {
  final String privateKey;
  final String serviceUsername;
  final String servicePassword;
  final String expiresAt;

  const NordAccountCredentials({
    required this.privateKey,
    required this.serviceUsername,
    required this.servicePassword,
    required this.expiresAt,
  });
}

class ExitIpInfo {
  final String ip;
  final String country;
  final String countryCode;
  final String city;
  final String isp;

  const ExitIpInfo({
    required this.ip,
    this.country = '',
    this.countryCode = '',
    this.city = '',
    this.isp = '',
  });

  String get flag => countryCodeToFlag(countryCode);
}
