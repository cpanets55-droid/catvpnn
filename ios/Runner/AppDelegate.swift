import Flutter
import NetworkExtension
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.catvpn.nord/vpn"
  private let prefsPrefix = "catvpn_pref_"
  private let keychainService = "com.catvpn.nord.catvp.ikev2"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CatVpnIosBridge") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "prepareVpn":
        result(true)

      case "connect":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
        }
        let hostname = (args["hostname"] as? String) ?? ""
        let username = (args["username"] as? String) ?? ""
        let password = (args["password"] as? String) ?? ""
        if hostname.isEmpty || username.isEmpty || password.isEmpty {
          result("NEED_WG_EXPORT")
          return
        }
        self.connectIkev2(hostname: hostname, username: username, password: password, result: result)

      case "disconnect":
        let manager = NEVPNManager.shared()
        manager.loadFromPreferences { _ in
          manager.connection.stopVPNTunnel()
          result("DOWN")
        }

      case "getStatus":
        let status = NEVPNManager.shared().connection.status
        let isUp = (status == .connected)
        result([
          "state": isUp ? "UP" : "DOWN",
          "rxBytes": 0,
          "txBytes": 0,
          "revoked": false
        ])

      case "shareWireGuardFile":
        guard let args = call.arguments as? [String: Any],
              let config = args["config"] as? String else {
          result(false)
          return
        }
        let rawName = (args["fileName"] as? String) ?? "catvpn-nord"
        let safeName = rawName.replacingOccurrences(of: ".nordvpn.com", with: "")
          .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "-", options: .regularExpression)
        self.presentWireGuardShareSheet(fileName: "\(safeName).conf", content: config, result: result)

      case "savePref":
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String,
           let value = args["value"] as? String {
          UserDefaults.standard.set(value, forKey: self.prefsPrefix + key)
        }
        result(true)

      case "loadPrefs":
        var out: [String: String] = [:]
        for (k, v) in UserDefaults.standard.dictionaryRepresentation() {
          if k.hasPrefix(self.prefsPrefix), let strVal = v as? String {
            let cleanKey = String(k.dropFirst(self.prefsPrefix.count))
            out[cleanKey] = strVal
          }
        }
        result(out)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func connectIkev2(
    hostname: String,
    username: String,
    password: String,
    result: @escaping FlutterResult
  ) {
    guard let passwordRef = savePasswordToKeychain(account: username, password: password) else {
      result("NEED_WG_EXPORT")
      return
    }

    let manager = NEVPNManager.shared()
    manager.loadFromPreferences { loadErr in
      if loadErr != nil {
        result("NEED_WG_EXPORT")
        return
      }

      if manager.connection.status == .connected || manager.connection.status == .connecting {
        manager.connection.stopVPNTunnel()
      }

      let ikev2 = NEVPNProtocolIKEv2()
      ikev2.serverAddress = hostname
      ikev2.remoteIdentifier = hostname
      ikev2.localIdentifier = username
      ikev2.authenticationMethod = .none
      ikev2.useExtendedAuthentication = true
      ikev2.username = username
      ikev2.passwordReference = passwordRef
      ikev2.disconnectOnSleep = false
      ikev2.enablePFS = true

      ikev2.ikeSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256GCM
      ikev2.ikeSecurityAssociationParameters.integrityAlgorithm = .SHA384
      ikev2.ikeSecurityAssociationParameters.diffieHellmanGroup = .group20

      ikev2.childSecurityAssociationParameters.encryptionAlgorithm = .algorithmAES256GCM
      ikev2.childSecurityAssociationParameters.integrityAlgorithm = .SHA384
      ikev2.childSecurityAssociationParameters.diffieHellmanGroup = .group20

      manager.protocolConfiguration = ikev2
      manager.localizedDescription = "CatVPN Nord"
      manager.isEnabled = true

      manager.saveToPreferences { saveErr in
        if saveErr != nil {
          // Missing Personal VPN entitlement (e.g. Free Apple ID sideload) -> fallback to WireGuard .conf share
          result("NEED_WG_EXPORT")
          return
        }

        manager.loadFromPreferences { reloadErr in
          if reloadErr != nil {
            result("NEED_WG_EXPORT")
            return
          }
          do {
            try manager.connection.startVPNTunnel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
              let st = manager.connection.status
              if st == .connected || st == .connecting {
                result("UP")
              } else {
                result("NEED_WG_EXPORT")
              }
            }
          } catch {
            result("NEED_WG_EXPORT")
          }
        }
      }
    }
  }

  private func savePasswordToKeychain(account: String, password: String) -> Data? {
    guard let passwordData = password.data(using: .utf8) else { return nil }

    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
      kSecValueData as String: passwordData,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      kSecReturnPersistentRef as String: true
    ]

    var itemRef: CFTypeRef?
    let status = SecItemAdd(addQuery as CFDictionary, &itemRef)
    if status == errSecSuccess {
      return itemRef as? Data
    }
    return nil
  }

  private func presentWireGuardShareSheet(
    fileName: String,
    content: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
      do {
        try content.write(to: fileUrl, atomically: true, encoding: .utf8)
        guard let presenter = self.topViewController() else {
          result(false)
          return
        }
        let activityVc = UIActivityViewController(
          activityItems: [fileUrl],
          applicationActivities: nil
        )
        if let popover = activityVc.popoverPresentationController {
          popover.sourceView = presenter.view
          popover.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 1,
            height: 1
          )
          popover.permittedArrowDirections = []
        }
        presenter.present(activityVc, animated: true) {
          result(true)
        }
      } catch {
        result(false)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      let win = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
      if let root = win?.rootViewController {
        var top = root
        while let presented = top.presentedViewController {
          top = presented
        }
        return top
      }
    }
    return nil
  }
}
