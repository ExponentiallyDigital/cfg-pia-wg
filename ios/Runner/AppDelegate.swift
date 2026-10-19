import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CfgPiaWgBuildInfo") {
      BuildInfo.register(with: registrar.messenger())
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
