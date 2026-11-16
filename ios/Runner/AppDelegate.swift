import Flutter
import NetworkExtension
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.catvpn.nord/vpn"
  private let prefsPrefix = "catvpn_pref_"
  private let keychainService = "com.catvpn.nord.catvp.ikev2"
  private var vpnOperationInProgress = false
  private var preferencesLoaded = false
  private var statusObserver: NSObjectProtocol?
  private var statusTimeout: DispatchWorkItem?

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
        self.disconnectVpn(result: result)

      case "getStatus":
        if self.preferencesLoaded {
          result(self.statusSnapshot())
        } else {
          NEVPNManager.shared().loadFromPreferences { error in
            self.preferencesLoaded = error == nil
            result(error == nil ? self.statusSnapshot() : self.vpnError("VPN_LOAD", error))
          }
        }

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
    guard !vpnOperationInProgress else {
      result(vpnError("VPN_BUSY", nil, "Một thao tác VPN khác đang chạy."))
      return
    }
    vpnOperationInProgress = true
    let finish: FlutterResult = { value in
      self.vpnOperationInProgress = false
      result(value)
    }
    guard let passwordRef = savePasswordToKeychain(account: username, password: password) else {
      finish(vpnError("KEYCHAIN_WRITE", nil, "Không lưu được thông tin VPN vào Keychain."))
      return
    }

    let manager = NEVPNManager.shared()
    manager.loadFromPreferences { loadErr in
      if loadErr != nil {
        finish(self.vpnError("VPN_LOAD", loadErr))
        return
      }
      self.preferencesLoaded = true

      // Finish stopping the previous tunnel before saving a different server.
      if manager.connection.status != .disconnected && manager.connection.status != .invalid {
        manager.connection.stopVPNTunnel()
        self.waitForStatus(.disconnected, timeout: 15) { stopped in
          if stopped {
            self.configureIkev2(hostname: hostname, username: username, passwordRef: passwordRef, result: finish)
          } else {
            finish(self.vpnError("VPN_STOP_TIMEOUT", nil, "VPN cũ chưa ngắt kết nối. Hãy thử lại."))
          }
        }
      } else {
        self.configureIkev2(hostname: hostname, username: username, passwordRef: passwordRef, result: finish)
      }
    }
  }

  private func configureIkev2(hostname: String, username: String, passwordRef: Data, result: @escaping FlutterResult) {
    let manager = NEVPNManager.shared()
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
        result(self.vpnError("VPN_SAVE", saveErr))
        return
      }

      manager.loadFromPreferences { reloadErr in
        if reloadErr != nil {
          result(self.vpnError("VPN_LOAD", reloadErr))
          return
        }
        do {
          try manager.connection.startVPNTunnel()
          self.waitForStatus(.connected, timeout: 45) { connected in
            if connected {
              result("UP")
            } else {
              manager.connection.stopVPNTunnel()
              result(self.vpnError("VPN_CONNECT_FAILED", nil, "Không thiết lập được IKEv2. Kiểm tra mạng, máy chủ và tài khoản dịch vụ NordVPN."))
            }
          }
        } catch {
          result(self.vpnError("VPN_START", error))
        }
      }
    }
  }

  private func vpnError(_ code: String, _ error: Error?, _ message: String = "Không truy cập được cấu hình VPN. Kiểm tra quyền Personal VPN của bản cài đặt.") -> FlutterError {
    return FlutterError(code: code, message: error?.localizedDescription ?? message, details: nil)
  }

  private func statusSnapshot() -> [String: Any] {
    let state: String
    switch NEVPNManager.shared().connection.status {
    case .connected: state = "UP"
    case .connecting, .reasserting: state = "CONNECTING"
    case .disconnecting: state = "DISCONNECTING"
    default: state = "DOWN"
    }
    return ["state": state, "rxBytes": 0, "txBytes": 0, "revoked": false,
            "supportsTrafficStats": false]
  }

  private func disconnectVpn(result: @escaping FlutterResult) {
    guard !vpnOperationInProgress else {
      result(vpnError("VPN_BUSY", nil, "Một thao tác VPN khác đang chạy."))
      return
    }
    vpnOperationInProgress = true
    let manager = NEVPNManager.shared()
    manager.loadFromPreferences { error in
      if let error = error {
        self.vpnOperationInProgress = false
        result(self.vpnError("VPN_LOAD", error))
        return
      }
      self.preferencesLoaded = true
      manager.connection.stopVPNTunnel()
      self.waitForStatus(.disconnected, timeout: 15) { stopped in
        self.vpnOperationInProgress = false
        result(stopped ? "DOWN" : self.vpnError("VPN_STOP_TIMEOUT", nil, "VPN chưa ngắt kết nối. Hãy thử lại."))
      }
    }
  }

  // Observe the actual tunnel state; accepting .connecting as success exposed
  // a false protected state while authentication was still in progress.
  private func waitForStatus(_ target: NEVPNStatus, timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
    let connection = NEVPNManager.shared().connection
    var completed = false
    var sawConnecting = connection.status == .connecting || connection.status == .reasserting
    let finish: (Bool) -> Void = { success in
      guard !completed else { return }
      completed = true
      if let observer = self.statusObserver {
        NotificationCenter.default.removeObserver(observer)
      }
      self.statusObserver = nil
      self.statusTimeout?.cancel()
      self.statusTimeout = nil
      completion(success)
    }
    let evaluate: () -> Void = {
      let status = connection.status
      if status == target || (target == .disconnected && status == .invalid) {
        finish(true)
      } else if target == .connected {
        if status == .connecting || status == .reasserting { sawConnecting = true }
        if status == .invalid || (sawConnecting && status == .disconnected) { finish(false) }
      }
    }
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: connection, queue: .main
    ) { _ in evaluate() }
    let work = DispatchWorkItem { finish(false) }
    statusTimeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    evaluate()
  }

  private func savePasswordToKeychain(account: String, password: String) -> Data? {
    guard let passwordData = password.data(using: .utf8) else { return nil }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: passwordData,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      let addQuery = query.merging(attributes) { _, new in new }
      guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else { return nil }
    } else if updateStatus != errSecSuccess {
      return nil
    }
    var referenceQuery = query
    referenceQuery[kSecReturnPersistentRef as String] = true
    referenceQuery[kSecMatchLimit as String] = kSecMatchLimitOne

    var itemRef: CFTypeRef?
    let status = SecItemCopyMatching(referenceQuery as CFDictionary, &itemRef)
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
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      let fileUrl = directory.appendingPathComponent(fileName)
      do {
        guard let presenter = self.topViewController() else {
          result(false)
          return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: fileUrl, options: [.atomic, .completeFileProtection])
        let activityVc = UIActivityViewController(
          activityItems: [fileUrl],
          applicationActivities: nil
        )
        activityVc.completionWithItemsHandler = { _, _, _, _ in
          try? FileManager.default.removeItem(at: directory)
        }
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
        try? FileManager.default.removeItem(at: directory)
        result(false)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
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
