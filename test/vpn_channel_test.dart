import 'package:catvp/services/vpn_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.catvpn.nord/vpn');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('an in-progress handshake never reports a protected connection',
      () async {
    for (final state in ['CONNECTING', 'DISCONNECTING']) {
      messenger.setMockMethodCallHandler(
          channel, (_) async => {'state': state});
      final status = await VpnChannel.getStatus();
      expect(status.isConnected, isFalse);
      expect(status.isTransitioning, isTrue);
      expect(status.supportsTrafficStats, isFalse);
    }
    messenger.setMockMethodCallHandler(channel, (_) async => {'state': 'UP'});
    expect((await VpnChannel.getStatus()).isConnected, isTrue);
  });

  test('a native status failure stays distinct from a disconnected tunnel',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'VPN_LOAD');
    });
    expect((await VpnChannel.getStatus()).isAvailable, isFalse);
    messenger.setMockMethodCallHandler(channel, (_) async => {'state': 'DOWN'});
    final status = await VpnChannel.getStatus();
    expect(status.isAvailable, isTrue);
    expect(status.isConnected, isFalse);
  });
}
