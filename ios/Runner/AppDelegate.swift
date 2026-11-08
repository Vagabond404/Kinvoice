import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.kinvoice.kinvoice/ambient_service"
  private var isAmbientActive = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let binaryMessenger = controller?.binaryMessenger {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: binaryMessenger)
      channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        switch call.method {
        case "startAmbientService":
          self?.configureAudioSession(active: true, result: result)
        case "stopAmbientService":
          self?.configureAudioSession(active: false, result: result)
        case "isServiceRunning":
          result(self?.isAmbientActive ?? false)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func configureAudioSession(active: Bool, result: @escaping FlutterResult) {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      if active {
        // Configure AVAudioSessionCategoryPlayAndRecord with allowBluetooth and mixWithOthers
        try audioSession.setCategory(
          .playAndRecord,
          mode: .measurement,
          options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        isAmbientActive = true
      } else {
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        isAmbientActive = false
      }
      result(true)
    } catch {
      result(FlutterError(code: "AUDIO_SESSION_ERROR", message: error.localizedDescription, details: nil))
    }
  }
}
