import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    PrivacyCover.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CfgPiaWgBuildInfo") {
      BuildInfo.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CfgPiaWgClipboard") {
      SensitiveClipboard.register(with: registrar.messenger())
    }
  }
}

/// ABOUT's build info on iOS (ID-395): the channel MainActivity.kt answers on Android, with the same
/// keys, so lib/build_info_service.dart reads one map on both. Facts about the build itself - commit,
/// branch, runner, time and configuration - are written into the built app's Info.plist by
/// ios/stamp_build_info.sh; the rest is read on the phone. Anything missing is "unknown", never an error.
/// test/unit/ios_build_info_test.dart holds the names here to the Dart side and the stamp script.
enum BuildInfo {
  static let channelName = "com.exponentiallydigital.pia_wireguard_cfga/build_info"
  static let getBuildInfo = "getBuildInfo"
  static let unknown = "unknown"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if call.method == getBuildInfo {
        result(collect())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func collect() -> [String: String] {
    let info = Bundle.main.infoDictionary ?? [:]
    func value(_ key: String) -> String {
      let found = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return found.isEmpty ? unknown : found
    }
    return [
      "versionName": value("CFBundleShortVersionString"),
      "buildNumber": value("CFBundleVersion"),
      "installer": installer(),
      "buildTimestamp": value("CfgBuildTimestamp"),
      "buildType": value("CfgBuildType"),
      "commitHash": value("CfgGitCommit"),
      "commitDate": value("CfgGitCommitDate"),
      "gitBranch": value("CfgGitBranch"),
      "runnerId": value("CfgRunnerId"),
      "cpuAbi": cpuArchitecture(),
      "osVersion": "iOS \(UIDevice.current.systemVersion)",
      "compileSdk": sdk(platform: value("DTPlatformVersion"), minimum: value("MinimumOSVersion")),
      "xcodeVersion": xcode(version: value("DTXcode"), build: value("DTXcodeBuild")),
    ]
  }

  /// Where the app came from. A debug build, or one carrying a provisioning profile (development or
  /// ad hoc), was put on the phone from Xcode; an App Store build has neither, and TestFlight's
  /// receipt is the sandbox one.
  static func installer() -> String {
    #if DEBUG
      return "Xcode"
    #else
      if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
        return "Xcode"
      }
      if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
        return "TestFlight"
      }
      return "App Store"
    #endif
  }

  static func cpuArchitecture() -> String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return unknown
    #endif
  }

  /// "iOS 26.0 SDK, minimum iOS 15.0": the SDK Xcode built against and the oldest iOS the app runs on.
  static func sdk(platform: String, minimum: String) -> String {
    if platform == unknown { return unknown }
    return minimum == unknown ? "iOS \(platform) SDK" : "iOS \(platform) SDK, minimum iOS \(minimum)"
  }

  /// DTXcode is four digits, "2610" for Xcode 26.1 and "2612" for 26.1.2.
  static func xcode(version: String, build: String) -> String {
    let digits = Array(version)
    guard digits.count == 4, digits.allSatisfy({ $0.isNumber }) else { return unknown }
    let major = Int(String(digits[0...1])) ?? 0
    var text = "\(major).\(digits[2])"
    if digits[3] != "0" { text += ".\(digits[3])" }
    return build == unknown ? text : "\(text) (\(build))"
  }
}

/// The clipboard on iOS (ID-404): the channel MainActivity.kt answers on Android, with the same methods.
/// lib/clipboard_service.dart falls back to Flutter's own clipboard without it, and that clear only
/// writes an empty string over the copy.
///
/// Nothing here reads what is on the clipboard: on iOS that is what shows the "pasted from" banner.
/// The clear is checked by counting items instead. A copy is kept on this phone (`localOnly`, so
/// Universal Clipboard doesn't hand it to the user's Mac) and given an expiry, so iOS removes it by
/// itself even if the app is suspended before its own countdown ends.
/// ios/RunnerTests/RunnerTests.swift calls `handle` the way the channel does.
enum SensitiveClipboard {
  static let channelName = "com.exponentiallydigital.pia_wireguard_cfga/clipboard"
  static let clearClipboard = "clearClipboard"
  static let copySensitive = "copySensitive"
  static let defaultExpirySeconds = 60.0

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channelName, binaryMessenger: messenger).setMethodCallHandler(handle)
  }

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case clearClipboard:
      UIPasteboard.general.items = []
      result(UIPasteboard.general.numberOfItems == 0)
    case copySensitive:
      let args = call.arguments as? [String: Any]
      let text = args?["text"] as? String ?? ""
      let seconds = (args?["expiresInSeconds"] as? NSNumber)?.doubleValue ?? defaultExpirySeconds
      UIPasteboard.general.setItems(
        [[UTType.utf8PlainText.identifier: text]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(seconds)])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// The app switcher cover on iOS (ID-403). iOS can't block screenshots, but it takes its app switcher
/// picture as the app leaves the foreground, so the window is covered the moment the scene stops being
/// active and uncovered when it is active again. The cover is the launch screen: the app's background
/// with the launch artwork.
///
/// A debug build skips it, as Android's FLAG_SECURE is skipped in one (MainActivity.kt), so the app can
/// be captured while testing - and so a debug build is how the cover is seen taken out.
/// ios/RunnerTests/RunnerTests.swift checks `show` and `hide`.
enum PrivacyCover {
  static let tag = 0x403
  private static var observers: [NSObjectProtocol] = []

  static func start() {
    #if !DEBUG
      let centre = NotificationCenter.default
      observers = [
        centre.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { note in
          windows(of: note.object).forEach(show)
        },
        centre.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { note in
          windows(of: note.object).forEach(hide)
        },
      ]
    #endif
  }

  private static func windows(of scene: Any?) -> [UIWindow] {
    (scene as? UIWindowScene)?.windows ?? []
  }

  static func show(_ window: UIWindow) {
    guard window.viewWithTag(tag) == nil else { return }
    let cover = UIView(frame: window.bounds)
    cover.tag = tag
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // kBg in lib/app_colors.dart.
    cover.backgroundColor = UIColor(red: 0x12 / 255.0, green: 0x14 / 255.0, blue: 0x1A / 255.0, alpha: 1)
    if let artwork = UIImage(named: "LaunchImage") {
      let image = UIImageView(image: artwork)
      image.center = CGPoint(x: cover.bounds.midX, y: cover.bounds.midY)
      image.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
      cover.addSubview(image)
    }
    window.addSubview(cover)
  }

  static func hide(_ window: UIWindow) {
    window.viewWithTag(tag)?.removeFromSuperview()
  }
}
